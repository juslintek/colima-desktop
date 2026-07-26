#!/usr/bin/env bash
#
# checksums.sh — emit a SHA-256 checksums manifest for EVERY release artifact
# (R8 / task 13.1, Requirement 12.1: "...with checksums...").
#
# Scans a dist directory, computes sha256 + size for each artifact, merges each
# artifact's optional `<artifact>.meta.json` sidecar (written by the per-component
# packaging scripts: component / signed / signing_status / required_credentials),
# and writes two files next to the artifacts:
#
#   SHA256SUMS.txt        standard `<sha256>  <name>` lines (sha256sum -c compatible)
#   release-manifest.json { version, artifacts[], signing_summary, required_credentials[] }
#
# The manifest is HONEST about signing: an artifact built without its signing
# credential carries signed=false and signing_status="UNSIGNED — signing
# credential <NAME> absent", and the union of every artifact's required
# credential names is reported so a fully-signed release's prerequisites are
# explicit. Nothing here signs, fakes a signature, or reads a secret.
#
# USAGE
#   scripts/release/checksums.sh [--dir dist] [--version X.Y.Z] [--quiet]
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

DIR="$ROOT/dist"
VERSION=""
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "checksums.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$VERSION" ] && VERSION="$(bash "$ROOT/scripts/version.sh" marketing 2>/dev/null || echo 0.0.0)"
[ -d "$DIR" ] || { echo "checksums.sh: dist dir not found: $DIR" >&2; exit 1; }

DIR="$DIR" VERSION="$VERSION" QUIET="$QUIET" python3 - <<'PY'
import hashlib, json, os, sys, datetime

d = os.environ["DIR"]
version = os.environ["VERSION"]
quiet = os.environ.get("QUIET") == "1"

# Files that are manifest OUTPUT or sidecar INPUT, never artifacts themselves.
EXCLUDE_EXACT = {"SHA256SUMS.txt", "release-manifest.json", "appcast.xml", ".gitignore", ".DS_Store"}

def is_artifact(name):
    if name in EXCLUDE_EXACT:
        return False
    if name.startswith("."):
        return False
    if name.endswith(".meta.json"):
        return False
    return True

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def guess_component(name):
    n = name.lower()
    if n.endswith(".dmg") or ".app" in n: return "macos-app"
    if "daemon" in n: return "daemon"
    if "tui" in n: return "tui"
    if n.endswith(".msix") or n.endswith(".msixbundle") or n.endswith(".zip") and "win" in n: return "windows"
    if n.endswith(".deb") or n.endswith(".rpm") or ("linux" in n and n.endswith(".tar.gz")): return "linux"
    return "other"

artifacts = []
for name in sorted(os.listdir(d)):
    full = os.path.join(d, name)
    if not os.path.isfile(full) or not is_artifact(name):
        continue
    entry = {
        "name": name,
        "size_bytes": os.path.getsize(full),
        "sha256": sha256(full),
        "component": guess_component(name),
        "signed": False,
        "signing_status": "UNSIGNED — signing status not reported by packager",
        "required_credentials": [],
    }
    # Merge the sidecar written by the packaging script, if present.
    side = full + ".meta.json"
    if os.path.isfile(side):
        try:
            meta = json.load(open(side))
            for k in ("component", "signed", "signing_status", "required_credentials", "notes"):
                if k in meta:
                    entry[k] = meta[k]
        except Exception as e:
            entry["signing_status"] = f"UNSIGNED — sidecar unreadable ({e})"
    artifacts.append(entry)

# SHA256SUMS.txt (sha256sum -c compatible: "<hash>  <name>")
sums_path = os.path.join(d, "SHA256SUMS.txt")
with open(sums_path, "w") as f:
    for a in artifacts:
        f.write(f"{a['sha256']}  {a['name']}\n")

signed = sum(1 for a in artifacts if a["signed"])
unsigned = len(artifacts) - signed
req = sorted({c for a in artifacts for c in a.get("required_credentials", [])})

manifest = {
    "version": version,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "artifacts": artifacts,
    "signing_summary": {"signed": signed, "unsigned": unsigned, "total": len(artifacts)},
    "required_credentials": req,
}
man_path = os.path.join(d, "release-manifest.json")
with open(man_path, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")

if not quiet:
    print(f"== release checksums manifest (v{version}) ==")
    print(f"-- {len(artifacts)} artifact(s) in {d} --")
    for a in artifacts:
        print(f"  {a['sha256'][:16]}…  {a['size_bytes']:>12,d} B  {a['name']}")
        print(f"      component={a['component']}  signed={a['signed']}  {a['signing_status']}")
    print(f"-- signing: {signed} signed / {unsigned} unsigned / {len(artifacts)} total --")
    if req:
        print("-- required signing credentials for a fully-signed release:")
        for c in req:
            print(f"     {c}")
    print(f"-- wrote {os.path.relpath(sums_path, os.path.dirname(d))} + {os.path.relpath(man_path, os.path.dirname(d))} --")

if not artifacts:
    print("checksums.sh: WARNING no artifacts found in dist dir", file=sys.stderr)
    sys.exit(1)
PY
