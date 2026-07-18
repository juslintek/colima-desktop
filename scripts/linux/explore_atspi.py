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
    xdotool (optional, for mouse-click fallback)

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

Pass 5 note (role=unknown):
  - Run 29642368079 proves the real main UI with 11 sidebar labels loads, but
    pyatspi reports every role as 'unknown' on this GTK4 + ubuntu-latest combo.
  - Role-based matching ('list' in role.lower(), 'frame' in role.lower()) all fail.
  - Fix: all tree traversal and widget lookup is now fully ROLE-BLIND.
    * find_sidebar_listbox() uses 4 name-based strategies:
        1. DFS for accessible name == "sidebar_list" (widget_name on ListBox)
        2. DFS for accessible name == "Navigation" (Property::Label on ListBox)
        3. DFS for "sidebar_scroll" then first child with >= 5 children
        4. Score-based: find node whose children names overlap known sidebar labels
    * Navigation strategies A/B/C/D are superseded by pass 8 grid nav — see below.
  - Requires 12 non-empty captures (all sidebar surfaces) + all 12 fps unique.
  - dump_tree_diagnostic() emits bounded tree (depth<=6) on first activation miss.

Pass 6 note (identical fingerprints — doAction(0) false-accept):
  - Run 29642873493: all 11 captures have 87 elements and identical fingerprints.
    Root cause: Strategy D used doAction(0) which fires whatever action happens
    to be at index 0 (e.g. clipboard, focus) and returns True. The GTK sidebar's
    connect_row_selected signal only fires when GTK internally processes a real
    pointer/keyboard select — an arbitrary AT-SPI action does NOT trigger it.
  - Fix (pass 6):
    1. REMOVE the doAction(0) arbitrary-index fallback entirely.
       Only invoke doAction(i) where action.getName(i).lower() in
       ('click', 'activate', 'select').
    2. PRIMARY mouse fallback: queryComponent().getExtents(DESKTOP_COORDS) →
       pyatspi.Registry.generateMouseEvent(cx, cy, 'b1c').
    3. SECONDARY mouse fallback: xdotool mousemove cx cy click 1 (AT-SPI extents).
    4. CONTENT FINGERPRINT CHECK after each activation attempt.

Pass 7 note (AT-SPI extents unusable — xdotool positional fallback):
  - Run 29643261452: Navigation node with 11 children confirmed. AT-SPI extents
    return zero/off-screen for all sidebar rows — so generateMouseEvent and
    xdotool with AT-SPI extents both fail. Implemented positional grid fallback.

Pass 8 note (mislabeled captures — deterministic xdotool grid, AT-SPI nav removed):
  - Run 29643626991 diagnostic: even-index surfaces (Images=2, Networks=4,
    Kubernetes=6, Runtime=8, Profiles=10) recorded `mouse_event:95,18`. 95,18 is
    the AT-SPI component extent of the Dashboard row (index 0). Root cause:
    strategies A/B/C match sidebar rows by AT-SPI name, then call AT-SPI
    component extents for the click — but ALL sidebar rows return the SAME wrong
    extents (Dashboard's position) because the GTK4/AT-SPI combo on this runner
    reports all row extents identically. Even-indexed rows "activated" while
    clicking Dashboard, producing mislabeled ground truth.
  - Fix (pass 8):
    1. Dashboard (index 0) is the INITIAL state. No click is sent. fp_before is
       recorded as the baseline.
    2. For every index 1..11, ALL AT-SPI doAction / component-coordinate
       strategies are BYPASSED entirely. Navigation uses ONLY the verified Xvfb
       positional grid via xdotool:
           abs_x = win_x + 100
           abs_y = win_y + 23 + 38 * i   (i = 0-based surface index)
       activation_method recorded as `xdotool_grid:index=N`.
    3. Window origin (win_x, win_y) obtained dynamically via:
           xdotool search --sync --onlyvisible --name "Colima Desktop"
           xdotool getwindowgeometry <wid> → parse "Position: X,Y"
       Falls back to (0,0) if xdotool search fails (Xvfb default placement).
    4. After each click, fingerprint must differ from the PREVIOUS surface's fp.
       Surface fails if fingerprint unchanged.
    5. After all 12 captures, ALL 12 content fingerprints must be UNIQUE
       (frozenset cardinality == 12). Any duplicate = run fails.
    6. AT-SPI tree traversal and screenshots are preserved unchanged (read-only
       AT-SPI use is reliable; only AT-SPI-driven click-navigation was broken).
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
    ("monitoring",    "Monitoring"),
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


def get_node_accessible_name(node) -> str:
    """Return best accessible name for a node: name, description, or accessible attributes."""
    try:
        n = node.name or ""
        if n:
            return n
    except Exception:
        pass
    try:
        d = node.description or ""
        if d:
            return d
    except Exception:
        pass
    try:
        attrs = node.getAttributes()
        if attrs:
            for a in attrs:
                if isinstance(a, str) and a.strip():
                    return a.strip()
    except Exception:
        pass
    return ""


def find_node_by_accessible_name(root, target_name: str, max_depth: int = 25) -> object:
    """
    DFS search for a node whose accessible name (name/desc/attrs) exactly matches
    target_name.  Role-blind — works even when all roles are reported as 'unknown'.
    """
    def _search(node, depth):
        if depth > max_depth:
            return None
        try:
            n = get_node_accessible_name(node)
            if n == target_name:
                return node
        except Exception:
            pass
        try:
            for i in range(node.childCount):
                child = node.getChildAtIndex(i)
                if child is not None:
                    found = _search(child, depth + 1)
                    if found is not None:
                        return found
        except Exception:
            pass
        return None

    return _search(root, 0)


def find_sidebar_listbox(app_acc):
    """
    Find the sidebar ListBox widget.  Role-blind strategies (GTK4 + this runner
    combo may report every role as 'unknown', so we cannot rely on role matching):

    Strategy 1: DFS for node with accessible name == "sidebar_list"
                (widget_name set in main.rs; GTK4 exposes widget_name as AT-SPI name
                 for some widget types on some GTK versions)
    Strategy 2: DFS for node with accessible name == "Navigation"
                (accessible Property::Label set on the ListBox)
    Strategy 3: DFS for node with accessible name == "sidebar_scroll"
                (ScrolledWindow parent; use its first child as the listbox)
    Strategy 4: Collect all nodes with >= 5 children; pick the one whose children
                have accessible names matching the known surface labels.
                This is the most robust fallback — works regardless of role/name.

    The sidebar is a gtk::ListBox inside a gtk::ScrolledWindow inside the left
    pane of the gtk::Paned.  At depth <= 15 from app root.
    """
    # Strategy 1 & 2 — direct name match
    for target in ("sidebar_list", "Navigation"):
        node = find_node_by_accessible_name(app_acc, target, max_depth=25)
        if node is not None:
            print(
                f"[find_sidebar_listbox] Strategy 1/2 found via name={target!r}: "
                f"name={getattr(node, 'name', '?')!r} role={role_name(node)!r} "
                f"children={getattr(node, 'childCount', '?')}",
                flush=True,
            )
            return node

    # Strategy 3 — find sidebar_scroll then get first child
    scroll_node = find_node_by_accessible_name(app_acc, "sidebar_scroll", max_depth=25)
    if scroll_node is not None:
        try:
            for i in range(scroll_node.childCount):
                child = scroll_node.getChildAtIndex(i)
                if child is not None and child.childCount >= 5:
                    print(
                        f"[find_sidebar_listbox] Strategy 3 (sidebar_scroll child): "
                        f"name={getattr(child, 'name', '?')!r} children={child.childCount}",
                        flush=True,
                    )
                    return child
        except Exception:
            pass

    # Strategy 4 — find a node whose children's accessible names include known sidebar labels
    known_labels = {label for _, label in SIDEBAR_SURFACES}

    best_node = None
    best_score = 0

    def _collect_candidates(node, depth=0):
        nonlocal best_node, best_score
        if depth > 20:
            return
        try:
            nchildren = node.childCount
            if nchildren >= 5:
                # Check how many children have names matching sidebar labels
                child_names = set()
                for i in range(min(nchildren, 20)):
                    try:
                        ch = node.getChildAtIndex(i)
                        if ch is not None:
                            n = get_node_accessible_name(ch)
                            if n:
                                child_names.add(n)
                            # Also check grandchildren (row > label pattern)
                            for j in range(min(ch.childCount, 5)):
                                try:
                                    gch = ch.getChildAtIndex(j)
                                    if gch is not None:
                                        gn = get_node_accessible_name(gch)
                                        if gn:
                                            child_names.add(gn)
                                except Exception:
                                    pass
                    except Exception:
                        pass
                score = len(child_names & known_labels)
                if score > best_score:
                    best_score = score
                    best_node = node
        except Exception:
            pass
        try:
            for i in range(node.childCount):
                ch = node.getChildAtIndex(i)
                if ch is not None:
                    _collect_candidates(ch, depth + 1)
        except Exception:
            pass

    _collect_candidates(app_acc)

    if best_node is not None and best_score >= 3:
        print(
            f"[find_sidebar_listbox] Strategy 4 (label-match): "
            f"name={getattr(best_node, 'name', '?')!r} "
            f"children={getattr(best_node, 'childCount', '?')} "
            f"label_score={best_score}/{len(known_labels)}",
            flush=True,
        )
        return best_node

    print("[find_sidebar_listbox] All strategies exhausted — sidebar not found", flush=True)
    return None


def dump_tree_diagnostic(root, max_depth: int = 6, max_children: int = 20) -> list:
    """
    Bounded DFS dump for diagnostics when a label is missing.
    Returns a list of dicts with name/role/childCount — enough to debug
    why a particular node is not being found.
    """
    result = []

    def _dump(node, depth):
        if depth > max_depth:
            return
        try:
            n = node.name or ""
            r = role_name(node)
            nc = node.childCount
            result.append({
                "depth": depth,
                "name": n,
                "role": r,
                "childCount": nc,
            })
            for i in range(min(nc, max_children)):
                ch = node.getChildAtIndex(i)
                if ch is not None:
                    _dump(ch, depth + 1)
        except Exception as e:
            result.append({"depth": depth, "error": str(e)})

    _dump(root, 0)
    return result


def _get_row_center(row) -> tuple:
    """Return (x, y) center of a row's component extents, or None."""
    try:
        comp = row.queryComponent()
        ext = comp.getExtents(pyatspi.DESKTOP_COORDS)
        if ext.width > 0 and ext.height > 0:
            return (ext.x + ext.width // 2, ext.y + ext.height // 2)
    except Exception:
        pass
    return None


def _get_content_fingerprint(app_acc) -> frozenset:
    """
    Compute a fingerprint of the currently-visible content area (main_stack).

    Walk the AT-SPI tree, find the node whose accessible name is 'main_stack'
    (the gtk::Stack widget in build_main_window), then collect the sorted set of
    non-empty accessible names of its children and grandchildren — these are the
    per-surface view widgets (e.g. 'containers_list', 'images_list', etc.).

    If main_stack is not found (e.g. all roles unknown), fall back to collecting
    names from the entire app tree, excluding known sidebar widget names, so that
    the fingerprint still changes when the stack switches pages.

    Returns a frozenset of strings — identical sets mean no navigation happened.
    """
    SIDEBAR_NAMES = {sid for sid, _ in SIDEBAR_SURFACES} | \
                    {name for _, name in SIDEBAR_SURFACES} | \
                    {"sidebar_list", "sidebar_scroll", "Navigation"}

    def _collect_names_from(node, max_depth=4, depth=0) -> set:
        names = set()
        if depth > max_depth:
            return names
        try:
            n = node.name or ""
            if n and n not in SIDEBAR_NAMES:
                names.add(n)
        except Exception:
            pass
        try:
            for i in range(node.childCount):
                ch = node.getChildAtIndex(i)
                if ch is not None:
                    names.update(_collect_names_from(ch, max_depth, depth + 1))
        except Exception:
            pass
        return names

    # Try to find main_stack first (2 levels deep is usually enough)
    stack_node = find_node_by_accessible_name(app_acc, "main_stack", max_depth=15)
    if stack_node is not None:
        names = set()
        try:
            for i in range(stack_node.childCount):
                ch = stack_node.getChildAtIndex(i)
                if ch is not None:
                    n = ch.name or ""
                    if n:
                        names.add(n)
                    # grandchildren — the real content widgets
                    names.update(_collect_names_from(ch, max_depth=2, depth=0))
        except Exception:
            pass
        if names:
            return frozenset(names)

    # Fallback: full-tree names minus sidebar names
    all_names = _collect_names_from(app_acc, max_depth=12)
    return frozenset(all_names)


def _get_sidebar_row_coords(surface_index: int, display: str) -> tuple:
    """
    Return (x, y) absolute screen coordinates for sidebar row at surface_index.

    Pass 7: AT-SPI queryComponent().getExtents() returns zero/off-screen extents
    for all sidebar rows in the CI runner.  We derive coordinates from the known
    Xvfb 1280×800 sidebar geometry instead:

        Left pane width ≈ 200px; row centers at x ≈ 100 (relative to window).
        Row y positions (relative to window):
            row 0 (Dashboard)  y ≈ 23
            row 1 (Containers) y ≈ 61
            each subsequent row +38px
        Formula: rel_y = 23 + 38 * surface_index

    Stage A — dynamic window origin (preferred):
        xdotool search --sync --onlyvisible --name "Colima Desktop"
        → returns window IDs; take the first.
        xdotool getwindowgeometry <wid>
        → parse "Position: <X>,<Y>" line.
        abs_x = win_x + 100
        abs_y = win_y + (23 + 38 * surface_index)

    Stage B — fixed Xvfb fallback (documented; only used if Stage A fails):
        Xvfb positions the window at (0, 0) by default (no WM decoration offset).
        abs_x = 100
        abs_y = 23 + 38 * surface_index

    The grid constants (x=100, y=23, step=38) are derived from the screenshot
    captured in run 29643261452 (Xvfb 1280×800, stable sidebar geometry).
    The fallback is explicitly documented as an Xvfb invariant — if a WM
    decorates the window, Stage A handles the offset automatically.
    """
    rel_x = 100
    rel_y = 23 + 38 * surface_index

    # ── Stage A: dynamic window origin via xdotool ───────────────────────
    try:
        env = os.environ.copy()
        env["DISPLAY"] = display

        # Search for the app window by name pattern (Colima Desktop or colima)
        for name_pattern in ("Colima Desktop", "colima-desktop", "colima"):
            search_result = subprocess.run(
                ["xdotool", "search", "--sync", "--onlyvisible", "--name", name_pattern],
                capture_output=True, text=True, timeout=5, env=env,
            )
            if search_result.returncode == 0 and search_result.stdout.strip():
                wids = search_result.stdout.strip().split()
                wid = wids[0]
                print(
                    f"  [coords] xdotool search found wid={wid!r} "
                    f"(pattern={name_pattern!r}, total={len(wids)})",
                    flush=True,
                )

                # Get window geometry to find its origin
                geom_result = subprocess.run(
                    ["xdotool", "getwindowgeometry", wid],
                    capture_output=True, text=True, timeout=5, env=env,
                )
                if geom_result.returncode == 0:
                    for line in geom_result.stdout.splitlines():
                        line = line.strip()
                        if line.startswith("Position:"):
                            # e.g. "Position: 0,0 (screen: 0)"
                            pos_part = line.split(":", 1)[1].split("(")[0].strip()
                            win_x_str, win_y_str = pos_part.split(",")
                            win_x = int(win_x_str.strip())
                            win_y = int(win_y_str.strip())
                            abs_x = win_x + rel_x
                            abs_y = win_y + rel_y
                            print(
                                f"  [coords] Dynamic origin: win=({win_x},{win_y}) "
                                f"→ abs=({abs_x},{abs_y}) for surface_index={surface_index}",
                                flush=True,
                            )
                            return (abs_x, abs_y)
                break
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError, Exception) as e:
        print(f"  [coords] Stage A failed: {e}", flush=True)

    # ── Stage B: fixed Xvfb fallback ─────────────────────────────────────
    # Xvfb places windows at (0,0) by default (no WM decoration offset).
    # These constants are derived from the Xvfb 1280×800 screenshot in
    # run 29643261452 and are the honest, documented fallback.
    abs_x = rel_x      # = 100
    abs_y = rel_y      # = 23 + 38*i
    print(
        f"  [coords] Xvfb fixed fallback: ({abs_x},{abs_y}) "
        f"for surface_index={surface_index}",
        flush=True,
    )
    return (abs_x, abs_y)


def _try_xdotool_positional(
    surface_index: int,
    display: str,
    surface_pause: float,
    fp_before,
    app_acc,
) -> tuple:
    """
    Navigate to sidebar surface at surface_index using xdotool positional click.

    Coordinates are derived from _get_sidebar_row_coords(surface_index, display),
    which first tries xdotool getwindowgeometry (dynamic, handles any WM placement)
    and falls back to fixed Xvfb constants (x=100, y=23+38*i) if that fails.

    Uses:  xdotool mousemove --sync <x> <y> click 1
    The --sync flag ensures the mouse actually moves before the click is sent.

    After the click, waits surface_pause seconds for GTK to process the
    row-selected signal and update the Stack page, then checks the content
    fingerprint.  Returns (True, method_str) only if the fingerprint changed
    (or if this is the first/Dashboard surface with fp_before=None).
    """
    x, y = _get_sidebar_row_coords(surface_index, display)
    env = os.environ.copy()
    env["DISPLAY"] = display

    method_str = f"xdotool_positional:i={surface_index},({x},{y})"
    try:
        result = subprocess.run(
            ["xdotool", "mousemove", "--sync", str(x), str(y), "click", "1"],
            capture_output=True, text=True, timeout=8, env=env,
        )
        if result.returncode != 0:
            print(
                f"  [xdotool_positional] exit={result.returncode} "
                f"stderr={result.stderr.strip()!r}",
                flush=True,
            )
            return (False, "")

        print(
            f"  [xdotool_positional] click sent to ({x},{y}) for index={surface_index}",
            flush=True,
        )

        # Bounded settle: wait for GTK to process the click + update the Stack
        time.sleep(surface_pause)

        # Fingerprint check — accept unconditionally for Dashboard (first surface)
        if fp_before is None:
            return (True, method_str)

        fp_after = _get_content_fingerprint(app_acc)
        if fp_after != fp_before:
            print(
                f"  [xdotool_positional] Content changed "
                f"(fp_before size={len(fp_before)}, fp_after size={len(fp_after)})",
                flush=True,
            )
            return (True, method_str)
        else:
            print(
                f"  [xdotool_positional] No content change at ({x},{y}) — "
                f"coords may be wrong or GTK didn't register the click",
                flush=True,
            )
            return (False, "")

    except (FileNotFoundError, subprocess.TimeoutExpired, Exception) as e:
        print(f"  [xdotool_positional] Exception: {e}", flush=True)
        return (False, "")


def navigate_to_surface_grid(
    surface_index: int,
    surface_name: str,
    app_acc,
    fp_before: frozenset,
    surface_pause: float,
    display: str,
) -> tuple:
    """
    Pass 8: deterministic sidebar navigation via xdotool positional grid.

    ALL AT-SPI doAction / component-coordinate strategies are bypassed because
    run 29643626991 proved they produce mislabeled captures: AT-SPI extents for
    ALL sidebar rows map to the same wrong coords (Dashboard's position), so even
    a correct name-match ends up clicking Dashboard for every even-indexed surface.

    This function is the ONLY navigation path used for indices 1..11.
    Dashboard (index 0) is never passed here — it is the initial state.

    Grid formula (from Xvfb 1280×800 screenshot evidence, run 29643261452):
        abs_x = win_x + 100
        abs_y = win_y + 23 + 38 * surface_index   (surface_index is 0-based)

    Window origin (win_x, win_y):
      Stage A — xdotool search + getwindowgeometry (dynamic; handles any WM placement)
      Stage B — (0, 0) fixed fallback (Xvfb default; window at top-left)

    Fingerprint check: fp_before must be provided (not None for indices 1..11).
    Accepts only if _get_content_fingerprint(app_acc) != fp_before after the click.
    Returns (True, "xdotool_grid:index=N") on success, (False, "") on failure.
    """
    x, y = _get_sidebar_row_coords(surface_index, display)
    method_str = f"xdotool_grid:index={surface_index}"
    env = os.environ.copy()
    env["DISPLAY"] = display

    print(
        f"  [grid_nav] surface={surface_name!r} index={surface_index} → ({x},{y})",
        flush=True,
    )

    try:
        result = subprocess.run(
            ["xdotool", "mousemove", "--sync", str(x), str(y), "click", "1"],
            capture_output=True, text=True, timeout=8, env=env,
        )
        if result.returncode != 0:
            print(
                f"  [grid_nav] xdotool exit={result.returncode} "
                f"stderr={result.stderr.strip()!r}",
                flush=True,
            )
            return (False, "")
    except (FileNotFoundError, subprocess.TimeoutExpired, Exception) as e:
        print(f"  [grid_nav] xdotool exception: {e}", flush=True)
        return (False, "")

    # Wait for GTK to process the row-selected signal and update the Stack page
    time.sleep(surface_pause)

    # Verify content changed
    fp_after = _get_content_fingerprint(app_acc)
    if fp_after != fp_before:
        print(
            f"  [grid_nav] ✓ content changed "
            f"(fp_before={len(fp_before)} names, fp_after={len(fp_after)} names)",
            flush=True,
        )
        return (True, method_str)

    print(
        f"  [grid_nav] ✗ no content change at ({x},{y}) — "
        f"click may have missed or GTK did not update stack",
        flush=True,
    )
    return (False, "")


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

        tree_diagnostic_captured = False

        # ── Pass 8: deterministic surface traversal ──────────────────────
        #
        # Dashboard (index 0) is the INITIAL state — no click sent.
        # For every index 1..11, navigation is EXCLUSIVELY via xdotool positional
        # grid (navigate_to_surface_grid). All AT-SPI doAction / component-extent
        # strategies are bypassed because run 29643626991 proved they produce
        # mislabeled captures: AT-SPI extents for all sidebar rows map to the same
        # wrong position (Dashboard's coords), causing even-indexed surfaces to
        # silently click Dashboard and record Dashboard content under a different
        # surface label.
        #
        # Validation at the end requires ALL 12 content fingerprints to be unique.
        all_content_fps = []  # collect per-surface frozenset for uniqueness check
        prev_fp = _get_content_fingerprint(app_acc)  # Dashboard baseline fp

        for idx, (surface_id, surface_name) in enumerate(SIDEBAR_SURFACES):
            # idx is 0-based here; SIDEBAR_SURFACES[0] = ("dashboard", "Dashboard")
            surface_errors = []
            activated = False
            activation_method = "none"

            if idx == 0:
                # Dashboard is the initial/already-displayed surface.
                # Record fp, take screenshot, collect tree — no navigation needed.
                activated = True
                activation_method = "initial_state"
                print(f"[explore_atspi] Surface 0: {surface_name} (initial state)", flush=True)
            else:
                # Indices 1..11: use ONLY the xdotool positional grid.
                # fp_before = the previous surface's content fingerprint.
                fp_before_nav = prev_fp
                activated, activation_method = navigate_to_surface_grid(
                    surface_index=idx,
                    surface_name=surface_name,
                    app_acc=app_acc,
                    fp_before=fp_before_nav,
                    surface_pause=args.surface_pause,
                    display=display,
                )
                if not activated:
                    surface_errors.append(
                        f"xdotool_grid navigation failed for '{surface_name}' "
                        f"(index={idx}, coords=({100}, {23 + 38 * idx})): "
                        f"content fingerprint did not change after click."
                    )
                    print(
                        f"  WARNING: grid navigation failed for '{surface_name}'",
                        flush=True,
                    )
                    if not tree_diagnostic_captured:
                        tree_diagnostic_captured = True
                        diag = dump_tree_diagnostic(app_acc, max_depth=6, max_children=20)
                        errors.append({
                            "phase": "activation_diagnostic",
                            "surface": surface_id,
                            "surface_label": surface_name,
                            "message": (
                                f"Grid nav failed for '{surface_name}' (index={idx}). "
                                "Bounded tree follows."
                            ),
                            "tree_diagnostic": diag,
                        })
                else:
                    print(
                        f"  [explore_atspi] Surface {idx}: {surface_name} "
                        f"(method={activation_method!r})",
                        flush=True,
                    )

            # Collect tree from app root for this surface
            elements = collect_tree(app_acc, surface_name)
            total_elements += len(elements)

            # Content fingerprint AFTER navigation (used as fp_before for next surface)
            current_fp = _get_content_fingerprint(app_acc)
            all_content_fps.append(current_fp)
            prev_fp = current_fp  # next iteration uses this as fp_before

            # Element-name fingerprint (for ground-truth metadata)
            element_names_fingerprint = tuple(sorted(set(
                e["name"] for e in elements if e.get("name", "").strip()
            )))

            # Screenshot — 1-based file numbering for readability
            ss_file = SCREENSHOTS_DIR / f"{idx + 1:04d}-{surface_id}.png"
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
                "activation_method": activation_method,
                "element_count": len(elements),
                "element_names_fingerprint": list(element_names_fingerprint[:30]),
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

        # ── All-unique fingerprints guard (pass 8) ───────────────────────
        # Require ALL 12 content fingerprints to be unique.  Any duplicate means
        # two surfaces captured the same content — a mislabeled navigation.
        # (Distinct element-count fps are unreliable — we use content fps here.)
        nonempty_surfaces = [s for s in surfaces_data if s["element_count"] > 0]
        activated_count = sum(1 for s in surfaces_data if s["activated"])

        distinct_content_fps = len(set(all_content_fps))
        distinct_name_fps = len(set(
            tuple(s.get("element_names_fingerprint", [])) for s in nonempty_surfaces
        ))

        print(
            f"[explore_atspi] Surfaces: {len(surfaces_data)} total, "
            f"{len(nonempty_surfaces)} non-empty, "
            f"{distinct_content_fps}/12 distinct content-fps, "
            f"{distinct_name_fps} distinct name-fps, "
            f"{activated_count} activated",
            flush=True,
        )

        # Require 12 non-empty captures
        if len(nonempty_surfaces) < 12:
            errors.append({
                "phase": "distinct_surfaces_check",
                "error": (
                    f"Only {len(nonempty_surfaces)}/12 non-empty surfaces captured. "
                    "Navigation is not working or some surfaces returned empty trees."
                ),
                "nonempty_surfaces": [s["surface"] for s in nonempty_surfaces],
                "activated_count": activated_count,
            })
            print(
                f"ERROR: only {len(nonempty_surfaces)}/12 non-empty surfaces (need all 12)",
                file=sys.stderr,
            )

        # Require ALL 12 content fingerprints to be unique (pass 8 hard gate)
        if distinct_content_fps < 12 and len(all_content_fps) == 12:
            # Find which surfaces have duplicate fps for diagnostic output
            seen_fps: dict = {}
            duplicates = []
            for i, fp in enumerate(all_content_fps):
                if fp in seen_fps:
                    duplicates.append({
                        "surface_a": SIDEBAR_SURFACES[seen_fps[fp]][0],
                        "surface_b": SIDEBAR_SURFACES[i][0],
                        "shared_fp_size": len(fp),
                    })
                else:
                    seen_fps[fp] = i
            errors.append({
                "phase": "all_unique_fps_check",
                "error": (
                    f"Only {distinct_content_fps}/12 unique content fingerprints. "
                    f"{len(duplicates)} duplicate pair(s) found — these surfaces have "
                    "identical content, indicating navigation did not work for them."
                ),
                "duplicate_pairs": duplicates,
                "hint": (
                    "Pass 8 root cause was AT-SPI extents returning Dashboard coords "
                    "for all rows. Grid nav should fix this. If duplicates persist, "
                    "increase surface_pause (GTK stack update may be slow), or "
                    "verify grid coords match actual Xvfb layout."
                ),
            })
            print(
                f"ERROR: only {distinct_content_fps}/12 unique content fps "
                f"({len(duplicates)} duplicate pair(s)): {duplicates}",
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
            "pyatspi DFS traversal (read-only) + screenshots; "
            "sidebar navigation: Dashboard (index 0) = initial state (no click); "
            "indices 1..11 = ONLY xdotool positional grid "
            "(x=win_x+100, y=win_y+23+38*i, dynamic window origin via "
            "xdotool search + getwindowgeometry, Xvfb fixed fallback (0,0)); "
            "activation_method recorded as xdotool_grid:index=N; "
            "each navigation verified by content fingerprint change; "
            "all 12 content fingerprints must be unique "
            "(pass 8: AT-SPI doAction/component-extent navigation fully removed "
            "after run 29643626991 proved it produces mislabeled captures); "
            "DISC-03: Monitoring added as 12th surface (index 11, y=win_y+441)"
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

    # Fail if non-empty-surfaces guard tripped
    if any(
        e.get("phase") == "distinct_surfaces_check" and "only" in e.get("error", "").lower()
        for e in errors
    ):
        print("VALIDATION FAILED: insufficient non-empty surfaces captured", file=sys.stderr)
        return 1

    # Fail if all-unique content fingerprints gate tripped (pass 8)
    if any(e.get("phase") == "all_unique_fps_check" for e in errors):
        print("VALIDATION FAILED: duplicate content fingerprints — navigation mislabeled", file=sys.stderr)
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
