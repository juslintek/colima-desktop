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
    * activate_sidebar_row() uses:
        A. row.name == surface_id ("dashboard", "containers", ...)
        B. row.name == surface_name ("Dashboard", "Containers", ...)
        C. child.name == surface_name (Label child inside row)
        D. Positional index from SIDEBAR_SURFACES order (last resort)
  - Requires 11 non-empty captures (all sidebar surfaces) + >= 3 distinct name-fps.
  - dump_tree_diagnostic() emits bounded tree (depth<=6) on first activation miss.

Pass 6 note (identical fingerprints — doAction(0) false-accept):
  - Run 29642873493: all 11 captures have 87 elements and identical fingerprints.
    Root cause: Strategy D used doAction(0) which fires whatever action happens
    to be at index 0 (e.g. clipboard, focus) and returns True. The GTK sidebar's
    connect_row_selected signal only fires when GTK internally processes a real
    pointer/keyboard select — an arbitrary AT-SPI action does NOT trigger it.
  - Fix (this pass):
    1. REMOVE the doAction(0) arbitrary-index fallback entirely.
       Only invoke doAction(i) where action.getName(i).lower() in
       ('click', 'activate', 'select').
    2. PRIMARY mouse fallback: queryComponent().getExtents(DESKTOP_COORDS) →
       pyatspi.Registry.generateMouseEvent(cx, cy, 'b1c').
    3. SECONDARY mouse fallback: xdotool click <x> <y> (using same extents).
    4. CONTENT FINGERPRINT CHECK after each activation attempt:
       _get_content_fingerprint() finds the 'main_stack' node (DFS by widget_name)
       and collects the sorted set of widget_names/accessible-names of its visible
       children (the stack pages). If the fingerprint did not change from the
       previous surface, the activation attempt is rejected and the next fallback
       is tried. Only when the fingerprint changes (or for Dashboard/first surface)
       is the activation accepted.
    5. activate_sidebar_row() returns (bool, str) — activated flag + method name —
       for diagnostics recorded in ground-truth.json.
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


def activate_sidebar_row(
    listbox,
    surface_id: str,
    surface_name: str,
    app_acc,
    fp_before: frozenset,
    surface_pause: float,
) -> tuple:
    """
    Navigate to a sidebar surface with verified content change.

    Pass-6 changes vs pass-5:
      - REMOVED doAction(0) arbitrary-index fallback (falsely accepted in run
        29642873493 because index-0 action was clipboard/focus, not navigation).
      - Only named actions 'click', 'activate', or 'select' are invoked.
      - After each activation method, pause surface_pause seconds and check
        _get_content_fingerprint(app_acc). If the fingerprint is unchanged from
        fp_before, the attempt is rejected and the next fallback is tried.
      - Fallback chain per matched row:
          1. doAction named 'click'/'activate'/'select'
          2. pyatspi.Registry.generateMouseEvent(cx, cy, 'b1c') at center
          3. xdotool click cx cy (subprocess call)
      - For the Dashboard (first surface), fp_before is None and change check
        is skipped — Dashboard is the initial/baseline surface.
      - Returns (activated: bool, method: str) for diagnostics.

    Row matching strategies (unchanged from pass-5):
      A. row.name == surface_id  (e.g. "dashboard")
      B. row.name == surface_name (e.g. "Dashboard")
      C. child.name == surface_name or surface_id
      D. positional index from SIDEBAR_SURFACES

    The row candidates are tried in A→B→C→D order; for each candidate the
    activation fallback chain is attempted with fingerprint verification.
    """

    def _fp_changed(method_label: str) -> bool:
        """Pause, recompute fingerprint, return True if content changed."""
        if fp_before is None:
            # First surface (Dashboard) — no baseline; accept unconditionally
            return True
        time.sleep(surface_pause)
        fp_after = _get_content_fingerprint(app_acc)
        if fp_after != fp_before:
            print(
                f"  [activate] Content changed after {method_label} "
                f"(fp_before size={len(fp_before)}, fp_after size={len(fp_after)})",
                flush=True,
            )
            return True
        print(
            f"  [activate] No content change after {method_label} — rejecting",
            flush=True,
        )
        return False

    def _try_named_action(row, label: str) -> tuple:
        """Try doAction for 'click', 'activate', or 'select' on row."""
        try:
            action = row.queryAction()
            for j in range(action.nActions):
                raw = action.getName(j)
                aname = raw.lower() if raw else ""
                if aname in ("click", "activate", "select"):
                    action.doAction(j)
                    if _fp_changed(f"doAction({raw!r}) on {label}"):
                        return (True, f"doAction:{raw}")
        except Exception:
            pass
        return (False, "")

    def _try_mouse_event(row, label: str) -> tuple:
        """Try pyatspi.Registry.generateMouseEvent at row center."""
        center = _get_row_center(row)
        if center is None:
            return (False, "")
        x, y = center
        try:
            pyatspi.Registry.generateMouseEvent(x, y, "b1c")
            if _fp_changed(f"generateMouseEvent({x},{y}) on {label}"):
                return (True, f"mouse_event:{x},{y}")
        except Exception:
            pass
        return (False, "")

    def _try_xdotool(row, label: str) -> tuple:
        """Try xdotool click at row center (subprocess)."""
        center = _get_row_center(row)
        if center is None:
            return (False, "")
        x, y = center
        try:
            result = subprocess.run(
                ["xdotool", "mousemove", str(x), str(y), "click", "1"],
                capture_output=True, timeout=5,
            )
            if result.returncode == 0:
                if _fp_changed(f"xdotool click {x},{y} on {label}"):
                    return (True, f"xdotool:{x},{y}")
        except (FileNotFoundError, subprocess.TimeoutExpired, Exception):
            pass
        return (False, "")

    def _activate_row_all_methods(row, label: str) -> tuple:
        """Try all activation methods on a matched row; return first success."""
        ok, method = _try_named_action(row, label)
        if ok:
            return (True, method)
        ok, method = _try_mouse_event(row, label)
        if ok:
            return (True, method)
        ok, method = _try_xdotool(row, label)
        if ok:
            return (True, method)
        return (False, "")

    def _name_matches(node) -> bool:
        try:
            n = node.name or ""
            if n in (surface_id, surface_name):
                return True
        except Exception:
            pass
        try:
            d = node.description or ""
            if d in (surface_id, surface_name):
                return True
        except Exception:
            pass
        return False

    # Strategies A & B: direct row iteration on listbox
    try:
        nchildren = listbox.childCount
        for i in range(nchildren):
            row = listbox.getChildAtIndex(i)
            if row is None:
                continue

            if _name_matches(row):
                ok, method = _activate_row_all_methods(row, f"A/B row[{i}]")
                if ok:
                    print(
                        f"  [activate] A/B (row name match i={i}), "
                        f"surface={surface_name!r}, method={method!r}",
                        flush=True,
                    )
                    return (True, method)

            # Strategy C: check child label
            try:
                for ci in range(row.childCount):
                    child = row.getChildAtIndex(ci)
                    if child is not None:
                        cn = get_node_accessible_name(child)
                        if cn in (surface_name, surface_id):
                            ok, method = _activate_row_all_methods(row, f"C row[{i}].child[{ci}]")
                            if ok:
                                print(
                                    f"  [activate] C (child label i={i} ci={ci}), "
                                    f"surface={surface_name!r}, method={method!r}",
                                    flush=True,
                                )
                                return (True, method)
            except Exception:
                pass
    except Exception:
        pass

    # Strategy D: positional index (last resort — no doAction(0), still uses
    # named-action → mouse → xdotool, with fingerprint check)
    try:
        idx = next(i for i, (sid, _) in enumerate(SIDEBAR_SURFACES) if sid == surface_id)
        row = listbox.getChildAtIndex(idx)
        if row is not None:
            ok, method = _activate_row_all_methods(row, f"D positional[{idx}]")
            if ok:
                print(
                    f"  [activate] D (positional index={idx}), "
                    f"surface={surface_name!r}, method={method!r}",
                    flush=True,
                )
                return (True, method)
    except Exception:
        pass

    print(f"  [activate] All strategies failed for surface={surface_name!r}", flush=True)
    return (False, "none")


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

        # Traverse each surface
        for idx, (surface_id, surface_name) in enumerate(SIDEBAR_SURFACES, 1):
            surface_errors = []
            activated = False
            activation_method = "none"

            # Capture content fingerprint BEFORE activation so we can verify
            # that the sidebar row activation actually changed the displayed surface.
            # Dashboard is the initial surface — no prior baseline, skip change check.
            is_first_surface = (idx == 1)
            fp_before = None if is_first_surface else _get_content_fingerprint(app_acc)

            if sidebar is not None:
                activated, activation_method = activate_sidebar_row(
                    sidebar, surface_id, surface_name,
                    app_acc, fp_before, args.surface_pause,
                )
                if not activated:
                    surface_errors.append(
                        f"Could not activate sidebar row '{surface_name}' "
                        f"(all methods tried: named-action, generateMouseEvent, xdotool; "
                        f"none produced a content fingerprint change)"
                    )
                    print(f"  WARNING: sidebar row '{surface_name}' not activated", flush=True)
                    # Capture bounded tree diagnostic on first activation failure
                    if not tree_diagnostic_captured:
                        tree_diagnostic_captured = True
                        diag = dump_tree_diagnostic(app_acc, max_depth=6, max_children=20)
                        errors.append({
                            "phase": "activation_diagnostic",
                            "surface": surface_id,
                            "surface_label": surface_name,
                            "message": (
                                f"First missing label: '{surface_name}'. "
                                "Bounded pre-navigation tree follows (depth<=6, children<=20 each)."
                            ),
                            "tree_diagnostic": diag,
                        })
                        print(
                            f"  [diagnostic] Dumped tree ({len(diag)} nodes) for missing '{surface_name}'",
                            flush=True,
                        )
                else:
                    print(f"  Activated: {surface_name} (method={activation_method!r})", flush=True)
                    # Already paused inside activate_sidebar_row for fp check; no extra sleep needed
            else:
                surface_errors.append("Sidebar not found; skipping activation")
                # Still pause so view has time to render before collection
                time.sleep(args.surface_pause)

            # Collect tree from app root for this surface
            elements = collect_tree(app_acc, surface_name)
            total_elements += len(elements)

            # Build a name-based fingerprint: sorted tuple of non-empty element names
            # This allows detecting truly-distinct surfaces even when element counts
            # happen to be similar across surfaces.
            element_names_fingerprint = tuple(sorted(set(
                e["name"] for e in elements if e.get("name", "").strip()
            )))

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

        # ── Distinct-surfaces guard ──────────────────────────────────────
        # Require:
        #   (a) >= 11 non-empty captures (one per sidebar surface)
        #   (b) >= 3 distinct name-fingerprints (real different content across surfaces)
        #       Element-count alone is unreliable because GTK4 full-tree captures always
        #       include the entire window tree; use the set of element names instead.
        #
        # The name-fingerprint is: sorted tuple of distinct non-empty element names.
        # If navigation is not working, all 11 captures show the same surface and
        # therefore identical name-sets.  If working, different surfaces expose
        # different widget names (e.g. "containers_list" vs "images_list" etc.).
        nonempty_surfaces = [s for s in surfaces_data if s["element_count"] > 0]
        distinct_count_fps = len(set(s["element_count"] for s in nonempty_surfaces))
        distinct_name_fps = len(set(
            tuple(s.get("element_names_fingerprint", [])) for s in nonempty_surfaces
        ))
        activated_count = sum(1 for s in surfaces_data if s["activated"])

        print(
            f"[explore_atspi] Surfaces: {len(surfaces_data)} total, "
            f"{len(nonempty_surfaces)} non-empty, {distinct_count_fps} distinct count-fps, "
            f"{distinct_name_fps} distinct name-fps, {activated_count} activated",
            flush=True,
        )

        # Require 11 non-empty captures
        if len(nonempty_surfaces) < 11:
            errors.append({
                "phase": "distinct_surfaces_check",
                "error": (
                    f"Only {len(nonempty_surfaces)}/11 non-empty surfaces captured. "
                    "Navigation is not working or some surfaces returned empty trees."
                ),
                "nonempty_surfaces": [s["surface"] for s in nonempty_surfaces],
                "activated_count": activated_count,
            })
            print(
                f"ERROR: only {len(nonempty_surfaces)}/11 non-empty surfaces (need all 11)",
                file=sys.stderr,
            )

        # Require distinct name fingerprints (real navigation happened)
        # Use a lower bar of 3 distinct fps in case some surfaces are structurally similar
        if distinct_name_fps < 3 and len(nonempty_surfaces) >= 3:
            # All non-empty surfaces have the same name content — likely identical captures
            errors.append({
                "phase": "distinct_surfaces_check",
                "error": (
                    f"Only {distinct_name_fps} distinct name-fingerprints across "
                    f"{len(nonempty_surfaces)} non-empty surfaces (need >= 3). "
                    "All captures appear to show the same surface — sidebar navigation "
                    "rows are not being activated, or all views have identical AT-SPI trees."
                ),
                "recommendation": (
                    "Pass 6 fix: doAction(0) fallback removed. Only named click/activate/select "
                    "actions are used, followed by generateMouseEvent and xdotool as fallbacks. "
                    "Each attempt is verified by content fingerprint change on main_stack. "
                    "If still failing: check that main_stack widget_name is accessible via AT-SPI, "
                    "or that view widgets have distinct accessible names per surface."
                ),
            })
            print(
                f"WARNING: only {distinct_name_fps} distinct name-fps "
                f"(element-count fps: {distinct_count_fps})",
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
            "named doAction('click'/'activate'/'select') → "
            "generateMouseEvent(center,'b1c') → xdotool click; "
            "each attempt verified by content fingerprint change on main_stack "
            "(pass 6: removed arbitrary doAction(0) fallback)"
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

    # Fail if distinct-surfaces guard tripped (too few non-empty surfaces)
    if any(
        e.get("phase") == "distinct_surfaces_check" and "only" in e.get("error", "").lower()
        for e in errors
    ):
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
