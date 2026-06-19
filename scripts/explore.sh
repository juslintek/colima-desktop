#!/usr/bin/env bash
# Explore every Colima Desktop view against the REAL backend by launching the app
# deep-linked to each tab (--open-tab), screenshotting the window, and quitting.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DerivedData/Build/Products/Debug/Colima Desktop.app"
BIN="$APP/Contents/MacOS/Colima Desktop"
OUT="$ROOT/docs/exploration/screenshots"
mkdir -p "$OUT"
rm -f "$OUT"/*.png

TABS=(dashboard containers images volumes networks kubernetes machines profiles configuration ai monitoring runtimeControls community)
seq=0
manifest="$ROOT/docs/exploration/_shots.tsv"
: > "$manifest"

shoot() { # seq file
  # Capture the frontmost Colima Desktop window by id; fall back to full screen.
  local wid
  wid=$(osascript -e 'tell application "System Events" to tell (first process whose name is "Colima Desktop") to try
        return id of front window
      end try' 2>/dev/null)
  if [[ -n "$wid" && "$wid" =~ ^[0-9]+$ ]]; then
    screencapture -x -o -l "$wid" "$1" 2>/dev/null || screencapture -x "$1"
  else
    screencapture -x "$1"
  fi
}

for tab in "${TABS[@]}"; do
  seq=$((seq+1))
  num=$(printf "%04d" "$seq")
  file="$OUT/${num}-${tab}.png"
  "$BIN" --open-tab "$tab" >/dev/null 2>&1 &
  pid=$!
  # bring to front + let data load
  sleep 4
  osascript -e 'tell application "Colima Desktop" to activate' 2>/dev/null
  sleep 2
  shoot "$file"
  printf "%s\t%s\t%s\n" "$num" "$tab" "${num}-${tab}.png" >> "$manifest"
  kill "$pid" 2>/dev/null
  osascript -e 'quit app "Colima Desktop"' 2>/dev/null
  sleep 1
done
echo "Captured $seq screenshots to $OUT"
ls -1 "$OUT"
