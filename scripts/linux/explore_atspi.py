#!/usr/bin/env python3
"""
Linux AT-SPI2 explorer for Colima Desktop GTK4 app.

Walks the accessibility tree via pyatspi, activates each sidebar surface,
captures element metadata (role, name, description, states, actions, value),
takes screenshots via GNOME Screenshot / scrot / import fallback,
and writes exploration/linux/ground-truth.json.

Requirements:
    python3-pyatspi  (or pip install pyatspi)
    at-spi2-core running
    Xvfb display
    dbus-launch / dbus-run-session
    scrot or gnome-screenshot (optional, for screenshots)

Usage (called by the CI workflow — see .github/workflows/explore-linux.yml):
    python3 scripts/linux/explore_atspi.py \
        --app ./target/release/colima-desktop \
        --outdir exploration/linux \
        [--timeout 60]
"""

import argparse
import json
import os
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# pyatspi import — required; exit 1 with a clear message if absent
# ---------------------------------------------------------------------------
try:
    import pyatspi  # type: ignore
except ImportError:
    print(
        "ERROR: pyatspi not found. Install with: sudo apt-get install -y python3-pyatspi",
        file=sys.stderr,
    )
    sys.exit(1)

# ---------------------------------------------------------------------------
# CLI args
# ---------------------------------------------------------------------------
parser = argparse.ArgumentParser(description="AT-SPI2 explorer for Colima Desktop Linux")
parser.add_argument("--app", required=True, help="Path to the colima-desktop binary")
parser.add_argument("--outdir", default="exploration/linux", help="Output directory")
parser.add_argument("--timeout", type=int, default=60, help="Max seconds to wait for app in AT-SPI tree")
parser.add_argument("--surface-pause", type=float, default=1.5, help="Seconds to wait after switching surfaces")
args = parser.parse_args()

OUT_DIR = Path(args.outdir)
SCREENSHOTS_DIR = OUT_DIR / "screenshots"
OUT_DIR.mkdir(parents=True, exist_ok=True)
SCREENSHOTS_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Utility: collect all accessible nodes from a root recursively
# ---------------------------------------------------------------------------
APP_ID = "dev.colima.desktop"

SIDEBAR_SURFACES = [
    ("dashboard",     "Dashboard"),
    ("containers",    "Containers"),
    ("images",        "Images"),
    ("volumes",       "Volumes"),
    ("networks",      "Networks"),
    ("machines",      "Machines"),
    ("kubernetes",    "Kubernetes"),
    ("configuration", "Configuration"),
    ("runtime",       "Runtime"),
    ("ai_workloads",  "AI Workloads"),
    ("profiles",      "Profiles"),
]


def role_name(acc_obj) -> str:
    """Return a human-readable role string."""
    try:
        return pyatspi.role_to_string(acc_obj.getRole())
    except Exception:
        return "unknown"


def get_states(acc_obj) -> list[str]:
    try:
        state_set = acc_obj.getState()
        names = []
        for state in pyatspi.StateType.values.values():
            if state_set.contains(state):
                names.append(str(state).replace("STATE_", "").lower())
        return names
    except Exception:
        return []


def get_actions(acc_obj) -> list[str]:
    try:
        action = acc_obj.queryAction()
        return [action.getName(i) for i in range(action.nActions)]
    except Exception:
        return []


def get_value(acc_obj):
    try:
        v = acc_obj.queryValue()
        return v.currentValue
    except Exception:
        return None


def serialize_node(node, tab_label: str) -> dict:
    try:
        name = node.name or ""
    except Exception:
        name = ""
    try:
        desc = node.description or ""
    except Exception:
        desc = ""
    try:
        role = role_name(node)
    except Exception:
        role = "unknown"

    return {
        "role": role,
        "name": name,
        "description": desc,
        "states": get_states(node),
        "actions": get_actions(node),
        "value": get_value(node),
        "surface": tab_label,
    }


def collect_tree(root, tab_label: str, max_depth: int = 30, _depth: int = 0) -> list[dict]:
    """DFS-collect all nodes up to max_depth."""
    if _depth > max_depth:
        return []
    results = [serialize_node(root, tab_label)]
    try:
        for i in range(root.childCount):
            child = root.getChildAtIndex(i)
            if child is not None:
                results.extend(collect_tree(child, tab_label, max_depth, _depth + 1))
    except Exception:
        pass
    return results


# ---------------------------------------------------------------------------
# Screenshot
# ---------------------------------------------------------------------------

def take_screenshot(display: str, path: Path) -> bool:
    """Try scrot → import → xwd+convert; return True on success."""
    env = os.environ.copy()
    env["DISPLAY"] = display

    for cmd in [
        ["scrot", "--silent", str(path)],
        ["import", "-window", "root", str(path)],
    ]:
        try:
            result = subprocess.run(cmd, env=env, capture_output=True, timeout=10)
            if result.returncode == 0 and path.exists():
                return True
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue

    # xwd + convert fallback
    try:
        xwd_path = path.with_suffix(".xwd")
        r1 = subprocess.run(
            ["xwd", "-display", display, "-root", "-silent", "-out", str(xwd_path)],
            capture_output=True, timeout=10,
        )
        if r1.returncode == 0:
            r2 = subprocess.run(
                ["convert", str(xwd_path), str(path)],
                capture_output=True, timeout=10,
            )
            xwd_path.unlink(missing_ok=True)
            if r2.returncode == 0 and path.exists():
                return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    return False


# ---------------------------------------------------------------------------
# Find the app in the AT-SPI desktop tree
# ---------------------------------------------------------------------------

def find_app_accessible(timeout: int):
    """Poll the AT-SPI desktop until we find an app matching APP_ID."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            desktop = pyatspi.Registry.getDesktop(0)
            for i in range(desktop.childCount):
                app = desktop.getChildAtIndex(i)
                if app is None:
                    continue
                try:
                    if APP_ID in (app.name or "") or "colima" in (app.name or "").lower():
                        return app
                except Exception:
                    continue
        except Exception:
            pass
        time.sleep(0.5)
    return None


def find_sidebar_listbox(app_acc):
    """Find the sidebar ListBox widget by name 'sidebar_list'."""
    def search(node, _depth=0):
        if _depth > 15:
            return None
        try:
            if node.name == "sidebar_list" or (
                "Navigation" in (node.description or "")
            ):
                return node
        except Exception:
            pass
        try:
            for i in range(node.childCount):
                child = node.getChildAtIndex(i)
                if child is not None:
                    result = search(child, _depth + 1)
                    if result is not None:
                        return result
        except Exception:
            pass
        return None

    return search(app_acc)


def activate_sidebar_row(listbox, surface_name: str) -> bool:
    """Click the sidebar row whose accessible name matches surface_name."""
    try:
        for i in range(listbox.childCount):
            row = listbox.getChildAtIndex(i)
            if row is None:
                continue
            row_name = (row.name or "").strip()
            # Also check label children
            if row_name == surface_name:
                try:
                    action = row.queryAction()
                    for j in range(action.nActions):
                        if action.getName(j) in ("click", "activate"):
                            action.doAction(j)
                            return True
                    # Fallback: select the row via component click
                    comp = row.queryComponent()
                    ext = comp.getExtents(pyatspi.DESKTOP_COORDS)
                    x = ext.x + ext.width // 2
                    y = ext.y + ext.height // 2
                    pyatspi.Registry.generateMouseEvent(x, y, "b1c")
                    return True
                except Exception:
                    pass
            # Check child label text
            try:
                for c in range(row.childCount):
                    child = row.getChildAtIndex(c)
                    if child and (child.name or "").strip() == surface_name:
                        try:
                            action = row.queryAction()
                            for j in range(action.nActions):
                                if action.getName(j) in ("click", "activate"):
                                    action.doAction(j)
                                    return True
                        except Exception:
                            pass
                        try:
                            comp = row.queryComponent()
                            ext = comp.getExtents(pyatspi.DESKTOP_COORDS)
                            x = ext.x + ext.width // 2
                            y = ext.y + ext.height // 2
                            pyatspi.Registry.generateMouseEvent(x, y, "b1c")
                            return True
                        except Exception:
                            pass
            except Exception:
                pass
    except Exception:
        pass
    return False


# ---------------------------------------------------------------------------
# Main exploration
# ---------------------------------------------------------------------------

def main() -> int:
    display = os.environ.get("DISPLAY", ":99")
    timestamp = datetime.now(timezone.utc).isoformat()

    print(f"[explore_atspi] Starting. display={display} app={args.app}", flush=True)

    # Launch app
    env = os.environ.copy()
    env["DISPLAY"] = display
    env["NO_AT_BRIDGE"] = "0"
    env["GTK_MODULES"] = "gail:atk-bridge"
    env["GSETTINGS_BACKEND"] = "memory"
    env["G_MESSAGES_DEBUG"] = "none"

    app_proc = subprocess.Popen(
        [args.app],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    print(f"[explore_atspi] App launched, pid={app_proc.pid}", flush=True)

    surfaces_data = []
    errors = []
    total_elements = 0
    screenshot_paths = []

    try:
        # Wait for AT-SPI registration
        print(f"[explore_atspi] Waiting up to {args.timeout}s for app in AT-SPI tree…", flush=True)
        app_acc = find_app_accessible(args.timeout)

        if app_acc is None:
            msg = f"App '{APP_ID}' not found in AT-SPI tree after {args.timeout}s"
            print(f"ERROR: {msg}", file=sys.stderr)
            errors.append({"phase": "startup", "error": msg})

            # Still write a diagnostic JSON
            result = {
                "platform": "Linux",
                "timestamp": timestamp,
                "environment_blocked": True,
                "environment_block_reason": msg,
                "host": {
                    "display": display,
                    "app_binary": str(args.app),
                },
                "app": {"name": "Colima Desktop (GTK4)", "runtime": "N/A"},
                "element_count": 0,
                "surfaces": [],
                "errors": errors,
            }
            out_path = OUT_DIR / "ground-truth.json"
            out_path.write_text(json.dumps(result, indent=2))
            print(f"[explore_atspi] Diagnostic JSON written to {out_path}", flush=True)
            return 1

        print(f"[explore_atspi] Found app: name='{app_acc.name}'", flush=True)

        # Short pause for window to render
        time.sleep(1.5)

        # Take initial screenshot
        ss_path = SCREENSHOTS_DIR / "0000-launch.png"
        if take_screenshot(display, ss_path):
            screenshot_paths.append(str(ss_path.relative_to(OUT_DIR.parent.parent
                                                              if OUT_DIR.parent.parent.exists()
                                                              else OUT_DIR)))
            print(f"[explore_atspi] Screenshot: {ss_path}", flush=True)

        # Find sidebar
        sidebar = find_sidebar_listbox(app_acc)
        if sidebar is None:
            msg = "Could not find sidebar ListBox (sidebar_list) in AT-SPI tree"
            print(f"WARNING: {msg}", file=sys.stderr)
            errors.append({"phase": "sidebar_locate", "error": msg})

        # Traverse each surface
        for idx, (surface_id, surface_name) in enumerate(SIDEBAR_SURFACES, 1):
            surface_errors = []
            activated = False

            if sidebar is not None:
                activated = activate_sidebar_row(sidebar, surface_name)
                if not activated:
                    surface_errors.append(f"Could not activate sidebar row '{surface_name}'")
                    print(f"  WARNING: sidebar row '{surface_name}' not activated", flush=True)
                else:
                    print(f"  Activated: {surface_name}", flush=True)
                    time.sleep(args.surface_pause)
            else:
                surface_errors.append("Sidebar not found; skipping activation")

            # Collect tree from app root for this surface
            elements = collect_tree(app_acc, surface_name)
            total_elements += len(elements)

            # Screenshot
            ss_file = SCREENSHOTS_DIR / f"{idx:04d}-{surface_id}.png"
            ss_taken = take_screenshot(display, ss_file)
            if ss_taken:
                screenshot_paths.append(f"exploration/linux/screenshots/{ss_file.name}")
                print(f"  Screenshot: {ss_file.name} ({len(elements)} elements)", flush=True)
            else:
                print(f"  No screenshot for {surface_name} (tool unavailable)", flush=True)

            surfaces_data.append({
                "surface": surface_id,
                "surface_label": surface_name,
                "activated": activated,
                "element_count": len(elements),
                "screenshot": f"exploration/linux/screenshots/{ss_file.name}" if ss_taken else None,
                "elements": elements,
                "errors": surface_errors,
            })

        # Validate: require non-zero elements
        if total_elements == 0:
            errors.append({"phase": "validation", "error": "Zero elements collected — AT-SPI tree was empty"})
            print("ERROR: zero elements collected", file=sys.stderr)

    except Exception as exc:
        errors.append({"phase": "exploration", "error": str(exc)})
        print(f"ERROR during exploration: {exc}", file=sys.stderr)
        import traceback
        traceback.print_exc()
    finally:
        # Terminate the app
        try:
            app_proc.terminate()
            app_proc.wait(timeout=5)
        except Exception:
            try:
                app_proc.kill()
            except Exception:
                pass

    # Build output document
    result = {
        "platform": "Linux",
        "timestamp": timestamp,
        "host": {
            "display": display,
            "app_binary": str(args.app),
        },
        "app": {
            "name": "Colima Desktop (GTK4/gtk4-rs)",
            "app_id": APP_ID,
            "surfaces_explored": len(SIDEBAR_SURFACES),
        },
        "at_spi_method": "pyatspi DFS traversal; sidebar row activation via doAction/generateMouseEvent",
        "element_count": total_elements,
        "surfaces_count": len(surfaces_data),
        "screenshots": screenshot_paths,
        "surfaces": surfaces_data,
        "errors": errors,
    }

    out_path = OUT_DIR / "ground-truth.json"
    out_path.write_text(json.dumps(result, indent=2))
    print(f"\n[explore_atspi] Done. elements={total_elements} surfaces={len(surfaces_data)}", flush=True)
    print(f"[explore_atspi] Output: {out_path}", flush=True)

    # Validation gate: non-zero elements required for success exit code
    if total_elements == 0:
        print("VALIDATION FAILED: zero elements — AT-SPI capture incomplete", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
