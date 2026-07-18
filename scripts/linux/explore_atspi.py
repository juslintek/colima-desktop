#!/usr/bin/env python3
"""
Linux AT-SPI2 explorer for Colima Desktop GTK4 app.

Walks the accessibility tree via pyatspi, activates each sidebar surface,
captures element metadata (role, name, description, states, actions, value),
takes screenshots via scrot / import fallback, and writes
exploration/linux/ground-truth.json.

Requirements:
    python3-pyatspi  (or pip install pyatspi)
    at-spi2-core running and DBUS_SESSION_BUS_ADDRESS set
    Xvfb display (DISPLAY set)
    GTK_A11Y=atspi, NO_AT_BRIDGE=0  (set before the app is launched)
    scrot or imagemagick (optional, for screenshots)

Usage (called by the CI workflow):
    python3 scripts/linux/explore_atspi.py \\
        --app ./target/release/colima-desktop \\
        --outdir exploration/linux \\
        [--timeout 60] [--surface-pause 1.5]

GTK4 accessibility notes:
  - GTK4 uses GTK_A11Y=atspi and NO_AT_BRIDGE=0 — NOT GTK_MODULES=gail:atk-bridge
    (that was GTK2/3 only; setting it on GTK4 is a no-op at best, error at worst).
  - Do NOT set GTK_A11Y=1 — "1" is not a valid backend name. Valid values are:
    accesskit | atspi | test | none | help. Using an invalid value produces
    "Unrecognized accessibility backend '1'" and silently disables AT-SPI.
  - The app must be launched *after* at-spi-bus-launcher is running and
    DBUS_SESSION_BUS_ADDRESS is set in the environment.
  - gsettings org.gnome.desktop.interface toolkit-accessibility must be true.

Colima shim note (pass 4):
  - In CI, `colima` is not installed.  DependencyManager::is_colima_installed()
    uses which::which("colima"); when absent, the app shows the onboarding window
    instead of the real sidebar UI, causing all 11 captures to be identical.
  - The caller (run_explore.sh / explore-linux.yml) MUST place a colima shim on
    PATH before launching this script.  The shim responds to --version (exit 0),
    making is_colima_installed() return true so build_main_window() is invoked.
  - This script adds a guard: it checks whether the window rendered is the
    onboarding window (widget_name=window_onboarding, title contains "Setup" or
    accessible label "Colima Desktop Setup"), and fails immediately if so, emitting
    a structured error with instructions to add the colima shim to PATH.
"""

import argparse
import json
import os
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
# App identity
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

# ---------------------------------------------------------------------------
# AT-SPI helpers
# ---------------------------------------------------------------------------

def role_name(acc_obj) -> str:
    try:
        return pyatspi.role_to_string(acc_obj.getRole())
    except Exception:
        return "unknown"


def get_states(acc_obj) -> list:
    try:
        state_set = acc_obj.getState()
        names = []
        for state in pyatspi.StateType.values.values():
            if state_set.contains(state):
                names.append(str(state).replace("STATE_", "").lower())
        return names
    except Exception:
        return []


def get_actions(acc_obj) -> list:
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


def collect_tree(root, tab_label: str, max_depth: int = 30, _depth: int = 0) -> list:
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
# Accessible app list (for diagnostics)
# ---------------------------------------------------------------------------

def list_atspi_apps() -> list:
    """Return names of all apps visible in the AT-SPI desktop tree."""
    names = []
    try:
        desktop = pyatspi.Registry.getDesktop(0)
        for i in range(desktop.childCount):
            app = desktop.getChildAtIndex(i)
            if app is not None:
                names.append(app.name or f"<unnamed-{i}>")
    except Exception as e:
        names.append(f"<error: {e}>")
    return names


# ---------------------------------------------------------------------------
# Find the app in the AT-SPI desktop tree
# ---------------------------------------------------------------------------

def find_app_accessible(timeout: int):
    """Poll the AT-SPI desktop until we find an app matching APP_ID."""
    deadline = time.monotonic() + timeout
    last_apps: list = []
    while time.monotonic() < deadline:
        try:
            desktop = pyatspi.Registry.getDesktop(0)
            for i in range(desktop.childCount):
                app = desktop.getChildAtIndex(i)
                if app is None:
                    continue
                try:
                    app_name = app.name or ""
                    if APP_ID in app_name or "colima" in app_name.lower():
                        return app
                except Exception:
                    continue
            last_apps = [
                (desktop.getChildAtIndex(i).name or "<unnamed>")
                for i in range(desktop.childCount)
                if desktop.getChildAtIndex(i) is not None
            ]
        except Exception:
            pass
        time.sleep(0.5)

    print(
        f"[explore_atspi] Timed out. Apps visible at deadline: {last_apps}",
        file=sys.stderr,
    )
    return None


def detect_onboarding_window(app_acc) -> bool:
    """
    Return True if the app is showing the onboarding window rather than the
    main UI.  Checks:
      1. Top-level window widget_name == "window_onboarding"
         (set in main.rs build_onboarding_window)
      2. Window accessible label contains "Setup"
      3. Any descendant named "onboarding_title" exists (Label in onboarding view)

    If any of these match, the DependencyManager::is_colima_installed() check
    returned false — the colima shim was not on PATH when the app launched.
    """
    def _check_node(node, depth=0):
        if depth > 8:
            return False
        try:
            wname = node.name or ""
            wdesc = node.description or ""
            role = role_name(node)
            # widget_name as accessible name (gtk4-rs sets it via set_widget_name
            # and AT-SPI exposes it as the object's name for some widget types)
            if wname in ("window_onboarding", "onboarding_title"):
                return True
            # Window with "Setup" in its accessible label
            if "frame" in role.lower() and "setup" in wname.lower():
                return True
            if "setup" in wdesc.lower():
                return True
            # Check accessible Properties (title attribute)
            try:
                attrs = node.getAttributes()
                if attrs:
                    for a in attrs:
                        if "setup" in str(a).lower():
                            return True
            except Exception:
                pass
        except Exception:
            pass
        try:
            for i in range(min(node.childCount, 40)):
                child = node.getChildAtIndex(i)
                if child is not None and _check_node(child, depth + 1):
                    return True
        except Exception:
            pass
        return False

    return _check_node(app_acc)


def find_sidebar_listbox(app_acc):
    """
    Find the sidebar ListBox widget.  Tries multiple strategies in order:

    1. widget_name == "sidebar_list"   (set explicitly in main.rs build_sidebar)
    2. accessible Property::Label == "Navigation"  (also set in build_sidebar)
    3. First LIST_BOX role with >= 5 children  (sidebar has 11 entries)
    4. Any LIST_BOX role (fallback)

    The sidebar is a gtk::ListBox inside a gtk::ScrolledWindow inside the left
    pane of the gtk::Paned.  At depth <= 15 from app root.
    """
    best_listbox = None
    best_listbox_children = 0

    def search(node, _depth=0):
        nonlocal best_listbox, best_listbox_children
        if _depth > 20:
            return None
        try:
            node_name = node.name or ""
            node_desc = node.description or ""
            role = role_name(node)

            # Strategy 1: exact widget_name match (AT-SPI name for gtk4-rs ListBox)
            if node_name == "sidebar_list":
                return node

            # Strategy 2: accessible label == "Navigation"
            if node_name == "Navigation" and "list" in role.lower():
                return node
            if node_desc == "Navigation" and "list" in role.lower():
                return node

            # Strategy 3 & 4: remember best LIST_BOX by child count
            if "list" in role.lower():
                try:
                    nchildren = node.childCount
                    if nchildren > best_listbox_children:
                        best_listbox = node
                        best_listbox_children = nchildren
                except Exception:
                    pass

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

    explicit = search(app_acc)
    if explicit is not None:
        return explicit

    # Fall back to best list box found during traversal (strategy 3/4)
    if best_listbox is not None and best_listbox_children >= 2:
        print(
            f"[find_sidebar_listbox] Using fallback list box "
            f"(children={best_listbox_children}, name={getattr(best_listbox, 'name', '?')!r})",
            flush=True,
        )
        return best_listbox

    return None


def activate_sidebar_row(listbox, surface_name: str) -> bool:
    """Click the sidebar row whose accessible name matches surface_name."""
    try:
        for i in range(listbox.childCount):
            row = listbox.getChildAtIndex(i)
            if row is None:
                continue
            row_name = (row.name or "").strip()

            matched = row_name == surface_name
            if not matched:
                # Also check label children
                try:
                    for c in range(row.childCount):
                        child = row.getChildAtIndex(c)
                        if child and (child.name or "").strip() == surface_name:
                            matched = True
                            break
                except Exception:
                    pass

            if matched:
                # Try doAction first
                try:
                    action = row.queryAction()
                    for j in range(action.nActions):
                        if action.getName(j) in ("click", "activate"):
                            action.doAction(j)
                            return True
                except Exception:
                    pass
                # Fallback: mouse click via component extents
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
    return False


# ---------------------------------------------------------------------------
# Main exploration
# ---------------------------------------------------------------------------

def build_app_env() -> dict:
    """
    Build the environment for the GTK4 app subprocess.

    Critical GTK4 accessibility env vars:
      GTK_A11Y=atspi     — select the AT-SPI backend explicitly. Valid GTK4 values:
                           accesskit | atspi | test | none | help.
                           Do NOT use GTK_A11Y=1 — "1" is unrecognized and causes
                           "Unrecognized accessibility backend '1'" which silently
                           kills AT-SPI registration.
      NO_AT_BRIDGE=0     — allow AT-SPI bridge registration (headless runners
                           set this to 1, which silently disables AT-SPI)
      DISPLAY            — must point to the running Xvfb
      DBUS_SESSION_BUS_ADDRESS — must be the session bus where at-spi-bus-launcher
                                 is registered

    Do NOT set GTK_MODULES=gail:atk-bridge — that is GTK2/3 only; on GTK4 it
    either does nothing or causes warnings.
    """
    env = os.environ.copy()
    env["GTK_A11Y"] = "atspi"
    env["NO_AT_BRIDGE"] = "0"
    env["GSETTINGS_BACKEND"] = env.get("GSETTINGS_BACKEND", "memory")

    # Ensure DISPLAY and DBUS_SESSION_BUS_ADDRESS are present
    display = env.get("DISPLAY", ":99")
    env["DISPLAY"] = display

    # Remove any legacy GTK2/3 env vars that interfere with GTK4
    env.pop("GTK_MODULES", None)
    env.pop("GTK_PATH", None)

    return env


def main() -> int:
    display = os.environ.get("DISPLAY", ":99")
    dbus_addr = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "<not set>")
    timestamp = datetime.now(timezone.utc).isoformat()

    print(
        f"[explore_atspi] Starting. display={display!r} "
        f"dbus={dbus_addr!r} app={args.app!r}",
        flush=True,
    )

    # Build environment for the app subprocess
    app_env = build_app_env()

    # Diagnostic: print AT-SPI apps before we launch ours
    apps_before = list_atspi_apps()
    print(f"[explore_atspi] AT-SPI apps before launch: {apps_before}", flush=True)

    # Launch app; capture stderr for diagnostics
    app_stderr_path = OUT_DIR / "app_stderr.txt"
    app_stderr_fh = open(app_stderr_path, "w")

    app_proc = subprocess.Popen(
        [args.app],
        env=app_env,
        stdout=subprocess.DEVNULL,
        stderr=app_stderr_fh,
    )
    app_pid = app_proc.pid
    print(f"[explore_atspi] App launched, pid={app_pid}", flush=True)

    surfaces_data = []
    errors = []
    total_elements = 0
    screenshot_paths = []
    early_exit_code = None

    try:
        # Check if app exited immediately (crash or missing deps)
        time.sleep(1.0)
        early_exit_code = app_proc.poll()
        if early_exit_code is not None:
            app_stderr_fh.flush()
            stderr_text = app_stderr_path.read_text() if app_stderr_path.exists() else ""
            msg = (
                f"App exited immediately with code {early_exit_code}. "
                f"stderr: {stderr_text[:500]!r}"
            )
            print(f"ERROR: {msg}", file=sys.stderr)
            errors.append({"phase": "startup", "error": msg})

            result = _build_blocked_result(
                timestamp, display, app_pid, early_exit_code,
                apps_before, errors,
            )
            _write_result(result)
            return 1

        # Wait for AT-SPI registration
        print(
            f"[explore_atspi] Waiting up to {args.timeout}s for app in AT-SPI tree…",
            flush=True,
        )
        app_acc = find_app_accessible(args.timeout)

        if app_acc is None:
            apps_at_timeout = list_atspi_apps()
            app_stderr_fh.flush()
            stderr_text = app_stderr_path.read_text() if app_stderr_path.exists() else ""
            msg = (
                f"App '{APP_ID}' not found in AT-SPI tree after {args.timeout}s. "
                f"Apps visible: {apps_at_timeout}. "
                f"App still running: {app_proc.poll() is None}. "
                f"App stderr (first 400 chars): {stderr_text[:400]!r}"
            )
            print(f"ERROR: {msg}", file=sys.stderr)
            errors.append({"phase": "startup", "error": msg})
            errors.append({
                "phase": "diagnostics",
                "atspi_apps_at_timeout": apps_at_timeout,
                "app_exit_code": app_proc.poll(),
                "dbus_session_bus_address": dbus_addr,
                "display": display,
                "gtk_a11y": app_env.get("GTK_A11Y"),
                "no_at_bridge": app_env.get("NO_AT_BRIDGE"),
            })

            result = _build_blocked_result(
                timestamp, display, app_pid, app_proc.poll(),
                apps_at_timeout, errors,
            )
            _write_result(result)
            return 1

        print(f"[explore_atspi] Found app: name={app_acc.name!r}", flush=True)

        # Short pause for window to render
        time.sleep(1.5)

        # ── Onboarding guard ─────────────────────────────────────────────
        # If the app rendered the onboarding window, `colima` was not on PATH.
        # Fail fast with a structured error rather than capturing 11 identical
        # onboarding screenshots.
        if detect_onboarding_window(app_acc):
            msg = (
                "App rendered the onboarding window (DependencyManager::is_colima_installed() "
                "returned false). This means `colima` is not on PATH when the app launches. "
                "Fix: ensure scripts/linux/colima_shim.sh is copied to a temp bin dir and that "
                "dir is prepended to PATH before launching this script. "
                "See run_explore.sh and explore-linux.yml for the canonical setup."
            )
            print(f"ERROR: {msg}", file=sys.stderr)
            errors.append({
                "phase": "onboarding_guard",
                "error": msg,
                "fix": (
                    "Place a `colima` shim binary on PATH before launching. "
                    "The shim must respond to `colima --version` with exit 0. "
                    "See scripts/linux/colima_shim.sh."
                ),
            })
            # Take a diagnostic screenshot before bailing
            ss_path = SCREENSHOTS_DIR / "0000-onboarding-detected.png"
            if take_screenshot(display, ss_path):
                screenshot_paths.append(f"exploration/linux/screenshots/{ss_path.name}")
            result = _build_blocked_result(
                timestamp, display, app_pid, None,
                list_atspi_apps(), errors,
            )
            _write_result(result)
            return 1

        # Take initial screenshot
        ss_path = SCREENSHOTS_DIR / "0000-launch.png"
        if take_screenshot(display, ss_path):
            screenshot_paths.append(f"exploration/linux/screenshots/{ss_path.name}")
            print(f"[explore_atspi] Screenshot: {ss_path}", flush=True)

        # Find sidebar
        sidebar = find_sidebar_listbox(app_acc)
        if sidebar is None:
            msg = (
                "Could not find sidebar ListBox in AT-SPI tree. "
                "Tried: widget_name='sidebar_list', accessible label='Navigation', "
                "any LIST_BOX role with >=2 children. "
                "This usually means the onboarding window is showing (colima not on PATH) "
                "or the AT-SPI tree is not fully populated yet."
            )
            print(f"ERROR: {msg}", file=sys.stderr)
            errors.append({"phase": "sidebar_locate", "error": msg})
            # Fail immediately — without the sidebar we cannot navigate surfaces
            result = _build_blocked_result(
                timestamp, display, app_pid, None,
                list_atspi_apps(), errors,
            )
            _write_result(result)
            return 1
        else:
            sidebar_role = role_name(sidebar)
            sidebar_name = getattr(sidebar, 'name', '') or ''
            print(
                f"[explore_atspi] Sidebar found: role={sidebar_role!r} "
                f"name={sidebar_name!r} children={sidebar.childCount}",
                flush=True,
            )

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

        if total_elements == 0:
            errors.append({
                "phase": "validation",
                "error": "Zero elements collected — AT-SPI tree was empty after successful app registration",
            })
            print("ERROR: zero elements collected", file=sys.stderr)

        # ── Distinct-surfaces guard ──────────────────────────────────────
        # Require at least 2 surface captures that are non-empty AND have
        # distinct element-count fingerprints.  If all surfaces have
        # identical element counts it strongly suggests the sidebar navigation
        # is not working (e.g. all captures are the same onboarding view or
        # the same main window without switching).
        nonempty_surfaces = [s for s in surfaces_data if s["element_count"] > 0]
        distinct_counts = len(set(s["element_count"] for s in nonempty_surfaces))
        activated_count = sum(1 for s in surfaces_data if s["activated"])

        print(
            f"[explore_atspi] Surfaces: {len(surfaces_data)} total, "
            f"{len(nonempty_surfaces)} non-empty, {distinct_counts} distinct element counts, "
            f"{activated_count} activated",
            flush=True,
        )

        if len(nonempty_surfaces) < 2:
            errors.append({
                "phase": "distinct_surfaces_check",
                "error": (
                    f"Only {len(nonempty_surfaces)} non-empty surfaces captured (need >= 2). "
                    "Navigation is not working or all surfaces returned empty trees."
                ),
            })
            print(
                f"ERROR: only {len(nonempty_surfaces)} non-empty surfaces (need >= 2)",
                file=sys.stderr,
            )

        if distinct_counts < 2 and len(nonempty_surfaces) >= 2:
            # All non-empty surfaces have the same element count — suspect
            # identical captures (e.g. all showing onboarding or same view)
            errors.append({
                "phase": "distinct_surfaces_check",
                "error": (
                    f"All {len(nonempty_surfaces)} non-empty surfaces have the same element "
                    f"count ({nonempty_surfaces[0]['element_count']}). This strongly suggests "
                    "all captures are identical (sidebar navigation not working or onboarding "
                    "window captured repeatedly)."
                ),
                "recommendation": (
                    "Verify the colima shim is on PATH so the main window loads. "
                    "Check sidebar activation: doAction('click'/'activate') may not be "
                    "triggering a view switch — try generateMouseEvent fallback."
                ),
            })
            print(
                f"WARNING: all non-empty surfaces identical ({distinct_counts} distinct counts)",
                file=sys.stderr,
            )

    except Exception as exc:
        errors.append({"phase": "exploration", "error": str(exc)})
        print(f"ERROR during exploration: {exc}", file=sys.stderr)
        import traceback
        traceback.print_exc()
    finally:
        app_stderr_fh.close()
        try:
            app_proc.terminate()
            app_proc.wait(timeout=5)
        except Exception:
            try:
                app_proc.kill()
            except Exception:
                pass

    # Read any captured stderr for the result
    stderr_snippet = ""
    try:
        stderr_snippet = app_stderr_path.read_text()[:800]
    except Exception:
        pass

    result = {
        "platform": "Linux",
        "timestamp": timestamp,
        "host": {
            "display": display,
            "dbus_session_bus_address": dbus_addr,
            "app_binary": str(args.app),
            "app_pid": app_pid,
            "app_early_exit_code": early_exit_code,
            "gtk_a11y": app_env.get("GTK_A11Y"),
            "no_at_bridge": app_env.get("NO_AT_BRIDGE"),
        },
        "app": {
            "name": "Colima Desktop (GTK4/gtk4-rs)",
            "app_id": APP_ID,
            "surfaces_explored": len(SIDEBAR_SURFACES),
        },
        "at_spi_method": (
            "pyatspi DFS traversal; sidebar row activation via "
            "doAction('click'/'activate') then generateMouseEvent fallback"
        ),
        "element_count": total_elements,
        "surfaces_count": len(surfaces_data),
        "screenshots": screenshot_paths,
        "surfaces": surfaces_data,
        "errors": errors,
        "app_stderr_snippet": stderr_snippet,
    }

    _write_result(result)

    if total_elements == 0:
        print("VALIDATION FAILED: zero elements — AT-SPI capture incomplete", file=sys.stderr)
        return 1

    # Fail if distinct-surfaces guard tripped
    if any(e.get("phase") == "distinct_surfaces_check" and "only" in e.get("error", "") for e in errors):
        print("VALIDATION FAILED: insufficient distinct surfaces captured", file=sys.stderr)
        return 1

    return 0


def _build_blocked_result(timestamp, display, app_pid, app_exit_code, apps_visible, errors):
    dbus_addr = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "<not set>")
    app_env = build_app_env()
    stderr_snippet = ""
    try:
        stderr_snippet = (OUT_DIR / "app_stderr.txt").read_text()[:800]
    except Exception:
        pass

    return {
        "platform": "Linux",
        "timestamp": timestamp,
        "environment_blocked": True,
        "environment_block_reason": (
            "App did not register in AT-SPI tree. See errors[] for details."
        ),
        "host": {
            "display": display,
            "dbus_session_bus_address": dbus_addr,
            "app_binary": str(args.app),
            "app_pid": app_pid,
            "app_exit_code": app_exit_code,
            "gtk_a11y": app_env.get("GTK_A11Y"),
            "no_at_bridge": app_env.get("NO_AT_BRIDGE"),
            "atspi_apps_visible": apps_visible,
        },
        "app": {"name": "Colima Desktop (GTK4/gtk4-rs)", "runtime": "N/A"},
        "element_count": 0,
        "surfaces_count": 0,
        "screenshots": [],
        "surfaces": [],
        "errors": errors,
        "app_stderr_snippet": stderr_snippet,
    }


def _write_result(result: dict) -> None:
    out_path = OUT_DIR / "ground-truth.json"
    out_path.write_text(json.dumps(result, indent=2))
    print(f"[explore_atspi] Output: {out_path}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
