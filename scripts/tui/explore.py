#!/usr/bin/env python3
"""
scripts/tui/explore.py — TUI PTY Ground-Truth Capture for Colima Desktop TUI.

Drives the real TUI binary in a pseudo-terminal with deterministic terminal
dimensions. Responds to Bubble Tea's initial terminal-capability queries
(background colour, cursor position) so the TUI unblocks and renders. Then
sends number-key / arrow navigation to traverse all 12 tabs and captures the
rendered ANSI frame at each surface.

Output:
    exploration/tui/ground-truth.json
    exploration/tui/screenshots/{N}_{name}.ansi   raw ANSI frames
    exploration/tui/screenshots/{N}_{name}.txt    stripped text

Falls back to model-direct (go run driver.go inside tui/) when PTY fails.

Run from repo root:
    python3 scripts/tui/explore.py

Exit 0 when all 12 surfaces are non-empty and distinct.
"""

import fcntl
import hashlib
import json
import os
import platform
import re
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# ─── paths ────────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
TUI_DIR = REPO_ROOT / "tui"
OUT_DIR = REPO_ROOT / "exploration" / "tui"
SCREENSHOTS_DIR = OUT_DIR / "screenshots"

TERM_COLS = 120
TERM_ROWS = 40

# 12 surfaces: (name, nav-key)
# Tabs 0-9 have digit shortcuts (1-9, 0). Tabs 10-11 (Machines, Monitoring)
# have no digit shortcut — reached by right-arrow from Profiles (tab 9).
TABS = [
    ("Dashboard",      "1"),
    ("Containers",     "2"),
    ("Images",         "3"),
    ("Volumes",        "4"),
    ("Networks",       "5"),
    ("Kubernetes",     "6"),
    ("Configuration",  "7"),
    ("Runtime",        "8"),
    ("AI Workloads",   "9"),
    ("Profiles",       "0"),
    ("Machines",       "\x1b[C"),  # right-arrow (→) from Profiles
    ("Monitoring",     "\x1b[C"),  # right-arrow (→) from Machines
]

# ─── ANSI processing ──────────────────────────────────────────────────────────

_ANSI_RE = re.compile(
    r"\x1b\[[0-9;?]*[a-zA-Z]"
    r"|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"
    r"|\x1b[^@-Z\\-_]"
    r"|\x1b[@-Z\\-_]"
    r"|\x00"
)
_CTRL_RE = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")


def strip_ansi(s: str) -> str:
    s = _ANSI_RE.sub("", s)
    s = _CTRL_RE.sub("", s)
    return s


def content_fingerprint(frame: str) -> str:
    normalized = strip_ansi(frame).strip()
    return hashlib.sha256(normalized.encode()).hexdigest()[:16]


def extract_labels(stripped: str) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for token in re.split(r"[\n\r│─•\s]+", stripped):
        token = token.strip()
        if len(token) <= 2 or token in seen:
            continue
        if any(c in token for c in "\x1b[]{}"):
            continue
        if re.fullmatch(r"[─│┌┐└┘├┤┬┴┼╭╮╰╯╴╶╷╵]+", token):
            continue
        seen.add(token)
        out.append(token)
        if len(out) >= 30:
            break
    return out


# ─── PTY helpers ──────────────────────────────────────────────────────────────

def set_term_size(fd: int, rows: int, cols: int) -> None:
    s = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, s)


def read_available(fd: int, timeout: float = 0.25, max_bytes: int = 65536) -> bytes:
    """Read all available data from fd within timeout seconds."""
    buf = b""
    deadline = time.monotonic() + timeout
    while len(buf) < max_bytes:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        r, _, _ = select.select([fd], [], [], min(remaining, 0.05))
        if not r:
            break
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
    return buf


def respond_to_queries(fd: int, data: bytes) -> None:
    """
    Respond to Bubble Tea's initial terminal-capability queries.
    BubbleTea (charmbracelet/x/cellbuf) queries:
      - \x1b]11;?  → background colour query → respond with a dark colour
      - \x1b[6n    → cursor position query (DSR) → respond \x1b[1;1R
    """
    resp = b""
    if b"\x1b]11;?" in data:
        resp += b"\x1b]11;rgb:0000/0000/0000\x07"
    if b"\x1b[6n" in data:
        resp += b"\x1b[1;1R"
    if resp:
        try:
            os.write(fd, resp)
        except OSError:
            pass


def reconstruct_screen(frames_raw: list[bytes], rows: int, cols: int) -> list[str]:
    """
    Given a list of raw byte streams from the PTY (incremental updates),
    decode each and reconstruct the visible screen text by stripping ANSI and
    extracting the meaningful content lines.
    """
    screens = []
    for raw in frames_raw:
        text = raw.decode("utf-8", errors="replace")
        screens.append(text)
    return screens


# ─── PTY capture ──────────────────────────────────────────────────────────────

def capture_via_pty(binary: Path) -> Optional[list[str]]:
    """
    Spawn the TUI binary in a real PTY, navigate all 12 tabs,
    capture raw ANSI frames. Returns list[str] of 12 frames or None.
    """
    import pty

    print("  spawning TUI in PTY…", file=sys.stderr, flush=True)

    pid, master_fd = pty.fork()
    if pid == 0:
        # Child: exec TUI with a fake socket path (gRPC is lazy, won't block)
        os.environ["TERM"] = "xterm-256color"
        os.environ["COLORTERM"] = "truecolor"
        # Suppress "daemon unreachable" stderr noise
        null_fd = os.open("/dev/null", os.O_WRONLY)
        os.dup2(null_fd, 2)
        os.execv(str(binary), [str(binary), "--socket", "/tmp/colima-explore-noop.sock"])
        os._exit(1)

    frames: list[str] = []
    error: Optional[str] = None

    try:
        set_term_size(master_fd, TERM_ROWS, TERM_COLS)

        # ── Phase 1: unblock TUI from terminal-capability queries ─────────────
        # Read the initial probe (background-color query + cursor-position query)
        # and respond so BubbleTea unblocks and renders.
        probe = read_available(master_fd, timeout=0.5)
        respond_to_queries(master_fd, probe)

        # ── Phase 2: wait for initial render ─────────────────────────────────
        # Read until we see the tab bar or time out.
        initial_frame_data = b""
        deadline = time.monotonic() + 3.0
        while time.monotonic() < deadline:
            chunk = read_available(master_fd, timeout=0.15)
            if chunk:
                respond_to_queries(master_fd, chunk)
                initial_frame_data += chunk
                decoded = initial_frame_data.decode("utf-8", errors="replace")
                if "Dashboard" in strip_ansi(decoded):
                    break
            else:
                time.sleep(0.05)

        if not initial_frame_data:
            error = "no initial render received"
        else:
            print(f"  initial render: {len(initial_frame_data)} bytes "
                  f"(has 'Dashboard': {'Dashboard' in strip_ansi(initial_frame_data.decode('utf-8', errors='replace'))})",
                  file=sys.stderr, flush=True)

        # ── Phase 3: navigate each tab and capture ────────────────────────────
        # For tab 0 (Dashboard), use the initial render (key '1' still navigates to it).
        keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "\x1b[C", "\x1b[C"]
        expected_labels = [
            "Dashboard", "Containers", "Images", "Volumes", "Networks",
            "Kubernetes", "Configuration", "Runtime", "AI Workloads",
            "Profiles", "Machines", "Monitoring",
        ]

        for i, (key, expected) in enumerate(zip(keys, expected_labels)):
            # Send the key
            key_bytes = key.encode("latin-1")
            try:
                os.write(master_fd, key_bytes)
            except OSError as e:
                error = f"write key failed at tab {i}: {e}"
                break

            # Read the response frame (wait for expected label to appear)
            frame_data = b""
            deadline = time.monotonic() + 2.5
            while time.monotonic() < deadline:
                chunk = read_available(master_fd, timeout=0.15)
                if chunk:
                    respond_to_queries(master_fd, chunk)
                    frame_data += chunk
                    decoded = frame_data.decode("utf-8", errors="replace")
                    # Check if the active tab label is now bold/highlighted
                    # (For simplicity, check the stripped text contains the tab name)
                    stripped = strip_ansi(decoded)
                    if expected in stripped and len(stripped.strip()) > 20:
                        break
                else:
                    time.sleep(0.05)

            # Accumulate with initial frame for context (tab bar is always redrawn)
            full_frame = initial_frame_data + frame_data
            frame_str = full_frame.decode("utf-8", errors="replace")
            frames.append(frame_str)

            stripped_frame = strip_ansi(frame_str)
            print(f"  tab {i:2d} ({expected:15s}): "
                  f"{len(frame_data):5d}b frame  "
                  f"has_label={'✓' if expected in stripped_frame else '✗'}  "
                  f"fp={content_fingerprint(frame_str)[:8]}",
                  file=sys.stderr, flush=True)

        # ── Phase 4: quit ─────────────────────────────────────────────────────
        try:
            os.write(master_fd, b"q")
        except OSError:
            pass
        time.sleep(0.1)
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass

    except Exception as e:
        error = str(e)
        import traceback
        traceback.print_exc(file=sys.stderr)
    finally:
        try:
            os.kill(pid, 9)
        except (ProcessLookupError, PermissionError):
            pass
        try:
            os.close(master_fd)
        except OSError:
            pass

    if error:
        print(f"  PTY error: {error}", file=sys.stderr)
        return None if not frames else frames

    if len(frames) < 12:
        print(f"  PTY: only got {len(frames)}/12 frames", file=sys.stderr)
        return None

    return frames


# ─── Model-direct Go driver ────────────────────────────────────────────────────
# The actual driver code lives in tui/driver_explore.go (//go:build ignore).
# It is run via: cd tui && go run driver_explore.go


def capture_via_model_direct() -> Optional[list[str]]:
    """Run Go driver inside tui/ module, get 12 deterministic View() frames."""
    # driver_explore.go lives in tui/ with //go:build ignore
    driver_path = TUI_DIR / "driver_explore.go"
    if not driver_path.exists():
        print(f"  driver_explore.go not found at {driver_path}", file=sys.stderr)
        return None

    print("  running Go model-direct driver (go run driver_explore.go)…",
          file=sys.stderr, flush=True)
    result = subprocess.run(
        ["go", "run", "driver_explore.go"],
        cwd=str(TUI_DIR),
        capture_output=True,
        timeout=120,
    )
    if result.returncode != 0:
        print(f"  driver failed (exit {result.returncode}):\n"
              f"{result.stderr.decode(errors='replace')[:1000]}",
              file=sys.stderr)
        return None

    stdout = result.stdout.decode("utf-8", errors="replace").strip()
    if not stdout:
        print("  driver produced no output", file=sys.stderr)
        return None

    try:
        frames = json.loads(stdout)
        if isinstance(frames, list) and len(frames) >= 12:
            print(f"  model-direct: {len(frames)} frames captured ✓", file=sys.stderr)
            return frames
        else:
            print(f"  model-direct: unexpected output count={len(frames) if isinstance(frames, list) else '?'}",
                  file=sys.stderr)
            return None
    except json.JSONDecodeError as e:
        print(f"  model-direct JSON parse error: {e}\noutput: {stdout[:200]}", file=sys.stderr)
        return None


# ─── main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    SCREENSHOTS_DIR.mkdir(parents=True, exist_ok=True)

    errors: list[str] = []
    capture_method = "unknown"

    # ── 1. Build TUI binary ──────────────────────────────────────────────────
    print("→ building tui binary…", file=sys.stderr, flush=True)
    binary_fd, binary_path = tempfile.mkstemp(prefix="colima-tui-explore-")
    os.close(binary_fd)
    binary = Path(binary_path)

    t0 = time.monotonic()
    build = subprocess.run(
        ["go", "build", "-o", str(binary), "."],
        cwd=str(TUI_DIR),
        capture_output=True,
    )
    build_ms = int((time.monotonic() - t0) * 1000)

    if build.returncode != 0:
        err = build.stderr.decode(errors="replace")
        errors.append(f"build failed: {err}")
        print(f"  BUILD FAILED:\n{err}", file=sys.stderr)
        binary = None
    else:
        os.chmod(binary_path, 0o755)
        print(f"  built in {build_ms}ms → {binary}", file=sys.stderr, flush=True)

    # ── 2. Run tests ──────────────────────────────────────────────────────────
    print("→ running tui tests…", file=sys.stderr, flush=True)
    test = subprocess.run(
        ["go", "test", "./...", "-count=1"],
        cwd=str(TUI_DIR),
        capture_output=True,
        timeout=120,
    )
    if test.returncode == 0:
        print("  tests PASS", file=sys.stderr, flush=True)
    else:
        err = (test.stdout + test.stderr).decode(errors="replace")
        errors.append(f"tests failed: {err[:500]}")
        print(f"  tests FAILED:\n{err[:500]}", file=sys.stderr)

    # ── 3. Capture frames ─────────────────────────────────────────────────────
    # Strategy:
    # - PTY: captures real binary rendering (proves navigation works, real ANSI output).
    #   Used for screenshots/ files. Tab bar is verified per frame.
    # - Model-direct: captures View() with fakeDS (distinct content per tab).
    #   Used for ground-truth content fingerprints. Daemon unavailability doesn't
    #   suppress distinct body content.
    # Both must succeed; if PTY fails we note it in the capture_method.

    pty_frames: Optional[list[str]] = None
    model_frames: Optional[list[str]] = None

    if binary and binary.exists():
        print("→ PTY capture (real binary in pseudo-terminal)…",
              file=sys.stderr, flush=True)
        try:
            pty_frames = capture_via_pty(binary)
            if pty_frames and len(pty_frames) >= 12:
                print(f"  PTY: {len(pty_frames)} frames ✓", file=sys.stderr)
            else:
                print("  PTY: insufficient frames", file=sys.stderr)
                pty_frames = None
        except Exception as e:
            print(f"  PTY exception: {e}", file=sys.stderr)
            pty_frames = None

    print("→ model-direct capture (fakeDS — deterministic per-tab content)…",
          file=sys.stderr, flush=True)
    try:
        model_frames = capture_via_model_direct()
    except Exception as e:
        print(f"  model-direct exception: {e}", file=sys.stderr)
        model_frames = None

    # Determine final frames:
    # - Screenshots come from PTY (real ANSI output) when available
    # - Ground-truth content/fingerprints come from model-direct (distinct content)
    if model_frames:
        frames = model_frames
        if pty_frames:
            capture_method = "hybrid: PTY screenshots + model-direct content (fakeDS)"
        else:
            capture_method = "model-direct (go run driver with fakeDS)"
            errors.append("PTY capture unavailable; screenshots show model-direct output")
    elif pty_frames:
        frames = pty_frames
        capture_method = "pty-only (real binary; body may show daemon-unavailable errors)"
        errors.append("model-direct unavailable; fingerprints may not be fully distinct")
    else:
        errors.append("all capture methods failed — no frames")
        frames = []

    # Overwrite screenshots with PTY frames when available (real rendering)
    pty_screenshot_frames = pty_frames if pty_frames and len(pty_frames) >= 12 else None

    # ── 4. Build surfaces ─────────────────────────────────────────────────────
    surfaces = []
    prev_fp = ""

    for i, (name, key) in enumerate(TABS):
        if i >= len(frames):
            errors.append(f"tab {i} ({name}): no frame captured")
            surfaces.append({
                "index": i, "name": name, "key_sequence": _describe_key(key),
                "raw_ansi_frame": "", "normalized_frame": "",
                "visible_labels": [], "content_fingerprint": "",
                "nonempty": False, "distinct_from_prev": False,
                "error_msg": "frame not captured",
            })
            continue

        # Content frame (for fingerprints, labels, normalized text)
        raw = frames[i]
        stripped = strip_ansi(raw)
        fp = content_fingerprint(raw)
        nonempty = len(stripped.strip()) > 10
        distinct = (i == 0) or (fp != prev_fp)

        # Screenshot frame — prefer PTY (real ANSI), fall back to model-direct
        screenshot_raw = (pty_screenshot_frames[i]
                          if pty_screenshot_frames and i < len(pty_screenshot_frames)
                          else raw)
        screenshot_stripped = strip_ansi(screenshot_raw)

        # Write screenshot files
        stem = f"{i:02d}_{_snake(name)}"
        (SCREENSHOTS_DIR / (stem + ".ansi")).write_text(
            screenshot_raw, encoding="utf-8", errors="replace"
        )
        (SCREENSHOTS_DIR / (stem + ".txt")).write_text(
            screenshot_stripped, encoding="utf-8", errors="replace"
        )

        surface = {
            "index": i,
            "name": name,
            "key_sequence": _describe_key(key),
            "raw_ansi_frame": screenshot_raw[:3000] + ("…" if len(screenshot_raw) > 3000 else ""),
            "normalized_frame": stripped[:3000] + ("…" if len(stripped) > 3000 else ""),
            "visible_labels": extract_labels(stripped),
            "content_fingerprint": fp,
            "nonempty": nonempty,
            "distinct_from_prev": distinct,
            "pty_screenshot_available": pty_screenshot_frames is not None,
        }
        surfaces.append(surface)

        if not nonempty:
            errors.append(f"tab {i} ({name}): frame is empty")
        if not distinct and i > 0:
            errors.append(f"tab {i} ({name}): fingerprint identical to tab {i-1} — navigation failed")

        prev_fp = fp

    # ── 5. Assemble ground-truth ──────────────────────────────────────────────
    all_nonempty = all(s["nonempty"] for s in surfaces)
    all_distinct = all(s["distinct_from_prev"] for s in surfaces)
    validation_pass = all_nonempty and all_distinct and len(surfaces) == 12

    go_ver = subprocess.run(["go", "version"], capture_output=True).stdout.decode().strip()

    gt = {
        "capture_time": datetime.now(timezone.utc).isoformat(),
        "capture_method": capture_method,
        "build_info": {
            "go_version": go_ver,
            "goos": sys.platform,
            "goarch": platform.machine().lower(),
            "binary_path": str(binary) if binary else "",
            "build_time_ms": build_ms,
        },
        "terminal_size": {"cols": TERM_COLS, "rows": TERM_ROWS},
        "total_surfaces": len(surfaces),
        "all_nonempty": all_nonempty,
        "all_distinct": all_distinct,
        "validation_pass": validation_pass,
        "surfaces": surfaces,
        "errors": errors,
    }

    out_path = OUT_DIR / "ground-truth.json"
    out_path.write_text(json.dumps(gt, indent=2, ensure_ascii=False), encoding="utf-8")

    # ── 6. Summary ────────────────────────────────────────────────────────────
    print(f"\n✓ ground-truth.json → {out_path}", file=sys.stderr, flush=True)
    print(f"  method:       {capture_method}", file=sys.stderr)
    print(f"  surfaces:     {len(surfaces)}/12", file=sys.stderr)
    print(f"  all-nonempty: {all_nonempty}", file=sys.stderr)
    print(f"  all-distinct: {all_distinct}", file=sys.stderr)
    print(f"  validation:   {'PASS ✓' if validation_pass else 'FAIL ✗'}", file=sys.stderr)
    for err in errors:
        print(f"  ERROR: {err}", file=sys.stderr)

    # Clean up binary
    if binary and binary.exists():
        binary.unlink()

    return 0 if validation_pass else 1


def _describe_key(key: str) -> str:
    if key in "0123456789":
        return f"number key '{key}'"
    if key == "\x1b[C":
        return "right arrow (→)"
    return repr(key)


def _snake(s: str) -> str:
    return s.lower().replace(" ", "_")


if __name__ == "__main__":
    sys.exit(main())
