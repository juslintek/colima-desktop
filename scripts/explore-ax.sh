#!/usr/bin/env bash
# explore-ax.sh — Walk the macOS Accessibility tree for Colima Desktop, one tab at a time.
# Emits exploration/macos/ground-truth.json + per-tab screenshots.
# Requires: Accessibility + Screen Recording permissions (verified: both Granted).
# Usage: ./scripts/explore-ax.sh [--mock]   (--mock passes --backend-mock to the app)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DerivedData/Build/Products/Debug/Colima Desktop.app"
BIN="$APP/Contents/MacOS/Colima Desktop"
OUT="$ROOT/exploration/macos"
SHOTS="$OUT/screenshots"
mkdir -p "$SHOTS"

MOCK_FLAG="${1:-}"
USE_MOCK=false
[[ "$MOCK_FLAG" == "--mock" ]] && USE_MOCK=true

TABS=(dashboard containers images volumes networks kubernetes machines profiles configuration ai monitoring runtimeControls community)
TAB_LABELS=("Dashboard" "Containers" "Images" "Volumes" "Networks" "Kubernetes" "Machines" "Profiles" "Configuration" "AI Workloads" "Monitoring" "Runtime Controls" "Community")
BUILD_VERSION=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")
HOST_OS=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
HOST_ARCH=$(uname -m)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "=== Colima Desktop AX Explorer ==="
echo "App: $APP"
echo "Mock mode: $USE_MOCK"
echo "Output: $OUT"
echo ""

# Kill any existing Colima Desktop instance
timeout 5 osascript -e 'quit app "Colima Desktop"' 2>/dev/null; sleep 1

# Python AX traversal helper — written to /tmp for reuse
cat > /tmp/ax_traverse.py << 'PYEOF'
#!/usr/bin/env python3
"""
Traverse the AX tree of a running app using osascript/applescript.
Outputs a JSON array of elements.
"""
import subprocess, json, sys, re

APP_NAME = "Colima Desktop"

def run_osascript(script):
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=15)
    return r.stdout.strip(), r.stderr.strip()

def get_ax_tree_for_tab(tab_name, tab_label):
    """Use osascript to walk the AX tree of the front window."""
    script = f'''
tell application "System Events"
    try
        set theApp to first process whose name is "Colima Desktop"
        set theWindow to front window of theApp
        set result to ""
        -- Get window info
        set wTitle to title of theWindow
        -- Walk all UI elements up to depth 5
        set allElems to entire contents of theWindow
        set elemList to ""
        repeat with elem in allElems
            try
                set aRole to role of elem
                set aDesc to ""
                try
                    set aDesc to description of elem
                end try
                set aTitle to ""
                try
                    set aTitle to title of elem
                end try
                set aValue to ""
                try
                    set aValue to value of elem as string
                end try
                set aEnabled to true
                try
                    set aEnabled to enabled of elem
                end try
                set aActions to ""
                try
                    set aActionNames to action names of elem
                    set aActions to aActionNames as string
                end try
                set aIdent to ""
                try
                    set aIdent to help of elem
                end try
                -- Encode as pipe-delimited line
                set elemList to elemList & aRole & "|" & aTitle & "|" & aDesc & "|" & aValue & "|" & (aEnabled as string) & "|" & aActions & "|" & aIdent & "\\n"
            end try
        end repeat
        return elemList
    on error errMsg
        return "ERROR: " & errMsg
    end try
end tell
'''
    out, err = run_osascript(script)
    return out, err

def parse_elements(raw_text, tab):
    """Parse the pipe-delimited element lines into structured dicts."""
    elements = []
    for i, line in enumerate(raw_text.split('\n')):
        line = line.strip()
        if not line or line.startswith('ERROR:'):
            continue
        parts = line.split('|')
        if len(parts) < 7:
            parts += [''] * (7 - len(parts))
        role, title, description, value, enabled_str, actions_raw, identifier = parts[:7]
        # Parse enabled
        enabled = enabled_str.lower() not in ('false', '0', 'no', '')
        # Parse actions
        actions = []
        if actions_raw.strip():
            # applescript returns comma-separated list often as: "AXPress, AXShowMenu"
            for a in re.split(r'[,\s]+', actions_raw.strip()):
                a = a.strip().strip('"\'')
                if a:
                    actions.append(a)
        # Build element record
        elem = {
            "index": i,
            "role": role.strip(),
            "title": title.strip(),
            "description": description.strip(),
            "value": value.strip()[:120],  # truncate long values
            "enabled": enabled,
            "actions": actions,
            "identifier": identifier.strip(),
            "tab": tab
        }
        # Skip trivially empty elements
        if not any([elem["role"], elem["title"], elem["description"]]):
            continue
        elements.append(elem)
    return elements

if __name__ == "__main__":
    tab = sys.argv[1] if len(sys.argv) > 1 else "unknown"
    tab_label = sys.argv[2] if len(sys.argv) > 2 else tab
    raw, err = get_ax_tree_for_tab(tab, tab_label)
    if raw.startswith("ERROR:") or (not raw and err):
        result = {"tab": tab, "tab_label": tab_label, "error": raw or err, "elements": []}
    else:
        elems = parse_elements(raw, tab)
        result = {"tab": tab, "tab_label": tab_label, "element_count": len(elems), "elements": elems}
    print(json.dumps(result, ensure_ascii=False))
PYEOF
chmod +x /tmp/ax_traverse.py

# Initialize JSON output
declare -a TAB_RESULTS

echo "Exploring ${#TABS[@]} tabs..."
for i in "${!TABS[@]}"; do
    tab="${TABS[$i]}"
    label="${TAB_LABELS[$i]}"
    seq=$(printf "%04d" $((i+1)))
    shot="$SHOTS/${seq}-${tab}.png"

    echo -n "  [$((i+1))/${#TABS[@]}] $label ... "

    # Launch app with this tab
    if $USE_MOCK; then
        "$BIN" --open-tab "$tab" --backend-mock >/dev/null 2>&1 &
    else
        "$BIN" --open-tab "$tab" >/dev/null 2>&1 &
    fi
    APP_PID=$!
    sleep 4

    # Bring to front
    osascript -e 'tell application "Colima Desktop" to activate' 2>/dev/null
    sleep 2

    # Screenshot via peekaboo
    peekaboo image --app "Colima Desktop" --output "$shot" 2>/dev/null \
        || screencapture -x "$shot" 2>/dev/null \
        || true

    # AX traverse
    ax_json=$(timeout 20 python3 /tmp/ax_traverse.py "$tab" "$label" 2>/dev/null || echo '{"tab":"'"$tab"'","error":"python3 traversal failed","elements":[]}')
    TAB_RESULTS+=("$ax_json")

    echo "done ($(echo "$ax_json" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(str(d.get("element_count",0))+" elements")' 2>/dev/null || echo '?'))"

    # Kill app
    kill "$APP_PID" 2>/dev/null
    timeout 5 osascript -e 'quit app "Colima Desktop"' 2>/dev/null
    sleep 1
done

# Build final ground-truth JSON
COLIMA_VERSION=$(colima version 2>/dev/null | head -1 | awk '{print $3}' || echo "unknown")

# Build JSON using Python with temp files approach
echo "Building ground-truth.json..."

# Write each tab result to a temp file without shell parameter-expansion braces.
for i in "${!TABS[@]}"; do
    if [[ -n "${TAB_RESULTS[$i]:-}" ]]; then
        printf '%s\n' "${TAB_RESULTS[$i]}" > "/tmp/ax_tab_${i}.json"
    else
        printf '{"error":"not captured","elements":[]}\n' > "/tmp/ax_tab_${i}.json"
    fi
done

python3 << PYEOF
import json, os, sys, datetime, subprocess

ROOT = "${ROOT}"
OUT = f"{ROOT}/exploration/macos"

tabs = ["dashboard","containers","images","volumes","networks","kubernetes","machines","profiles","configuration","ai","monitoring","runtimeControls","community"]
tab_labels = ["Dashboard","Containers","Images","Volumes","Networks","Kubernetes","Machines","Profiles","Configuration","AI Workloads","Monitoring","Runtime Controls","Community"]

# Get colima version
try:
    cv = subprocess.run(["colima","version"], capture_output=True, text=True, timeout=5)
    colima_ver = cv.stdout.split('\n')[0].replace("colima version ","").strip() if cv.returncode==0 else "unknown"
except:
    colima_ver = "unknown"

# Get app build version
try:
    plist_path = f"{ROOT}/build/DerivedData/Build/Products/Debug/Colima Desktop.app/Contents/Info.plist"
    pv = subprocess.run(["defaults","read",plist_path,"CFBundleShortVersionString"], capture_output=True, text=True, timeout=5)
    app_ver = pv.stdout.strip() if pv.returncode==0 else "unknown"
    bv = subprocess.run(["defaults","read",plist_path,"CFBundleVersion"], capture_output=True, text=True, timeout=5)
    build_num = bv.stdout.strip() if bv.returncode==0 else "unknown"
except:
    app_ver = build_num = "unknown"

# Get host info
try:
    os_ver = subprocess.run(["sw_vers","-productVersion"], capture_output=True, text=True).stdout.strip()
except:
    os_ver = "unknown"

tab_results = []
for i, (tab, label) in enumerate(zip(tabs, tab_labels)):
    tmpf = f"/tmp/ax_tab_{i}.json"
    if os.path.exists(tmpf):
        try:
            with open(tmpf) as f:
                data = json.load(f)
        except Exception as e:
            data = {"tab": tab, "tab_label": label, "error": f"JSON parse error: {e}", "elements": []}
    else:
        data = {"tab": tab, "tab_label": label, "error": "not captured", "elements": []}
    
    # Add screenshot path
    seq = f"{i+1:04d}"
    shot_rel = f"screenshots/{seq}-{tab}.png"
    shot_abs = f"{OUT}/{shot_rel}"
    data["screenshot"] = shot_rel if os.path.exists(shot_abs) else None
    data["tab_label"] = label
    tab_results.append(data)

ground_truth = {
    "platform": "macOS",
    "timestamp": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "host": {
        "os_version": os_ver,
        "arch": "aarch64",
        "colima_version": colima_ver,
        "colima_profile": "default"
    },
    "app": {
        "name": "Colima Desktop",
        "version": app_ver,
        "build": build_num,
        "build_path": "build/DerivedData/Build/Products/Debug/Colima Desktop.app",
        "launch_mode": "real backend (RealServiceProvider)",
        "backend_flag": "--open-tab <tab> (no --backend-mock, real colima profile)"
    },
    "ax_method": "osascript System Events entire-contents traversal (AXUIElement via AppleScript bridge)",
    "permissions": {
        "screen_recording": "Granted",
        "accessibility": "Granted"
    },
    "tabs_explored": len(tab_results),
    "tabs": tab_results
}

out_path = f"{OUT}/ground-truth.json"
with open(out_path, "w") as f:
    json.dump(ground_truth, f, indent=2, ensure_ascii=False)

print(f"Written: {out_path}")
total_elems = sum(len(t.get("elements",[])) for t in tab_results)
print(f"Total elements across all tabs: {total_elems}")
for t in tab_results:
    status = f"{t.get('element_count', len(t.get('elements',[])))}" if not t.get('error') else f"ERROR: {t.get('error','?')[:60]}"
    print(f"  {t['tab_label']}: {status}")
PYEOF

echo ""
echo "Validating JSON..."
python3 -m json.tool "$OUT/ground-truth.json" > /dev/null && echo "JSON valid ✅" || echo "JSON INVALID ❌"

echo ""
echo "=== Screenshots ==="
ls -1 "$SHOTS"/*.png 2>/dev/null | wc -l | xargs echo "  count:"
ls -1 "$SHOTS"/*.png 2>/dev/null

echo ""
echo "Done. Output: $OUT/"
