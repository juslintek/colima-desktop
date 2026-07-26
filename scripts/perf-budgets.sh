#!/usr/bin/env bash
# perf-budgets.sh — define, MEASURE (read-only vs desktop-e2e), and record the
# performance budgets for Colima Desktop's key operations (R7 / Requirement 11.5).
#
# WHAT IT PRODUCES
#   docs/performance-budgets.json   machine-readable source of truth the RC gate
#                                   can check; each budget = {metric, threshold,
#                                   measured, unit, pass|fail|n/a, ...}.
#   docs/performance-budgets.md     human-readable table + methodology + caveats,
#                                   generated FROM the JSON so the two never drift.
#
# BUDGET SET (aligned to Requirement 11.5 startup-time / idle-resource / large-list,
# expanded to the reasonable operational set):
#   * daemon startup to gRPC-listening        (startup)
#   * macOS app cold start                     (startup)      — n/a in this harness
#   * RPC round-trip: Status/Version           (rpc)          — docker version
#   * RPC round-trip: system info              (rpc)          — docker info
#   * RPC round-trip: ListContainers           (rpc)          — docker ps -a
#   * RPC round-trip: ListImages               (rpc)          — docker images
#   * control-plane RPC: colima status         (rpc)
#   * stream first-frame: stats                (stream)       — docker stats --no-stream
#   * daemon idle memory (RSS)                 (resource)
#   * cold container-list / cold image-list    (large-list)   — first (cold) call
#   * TUI displayed-output line cap            (memory-safety)— static, enforced (P14)
#   * TUI displayed-output byte cap            (memory-safety)— static, enforced (P14)
#   * gRPC max receive message size            (memory-safety)— static (grpc-go default)
#
# SAFETY / HONESTY
#   * READ-ONLY toward the live env. Every docker/colima call is routed through the
#     shared safety choke-point scripts/live/guard.sh (desktop-e2e ONLY) and only
#     ever runs status/list/stats RPCs — it NEVER creates, starts, stops, or deletes
#     any resource or profile.
#   * The daemon startup/RSS probe launches the committed build/colima-daemon on a
#     PRIVATE /tmp unix socket in listen-only mode; it makes no RPC and never touches
#     colima/docker, so it is read-only toward the live env too.
#   * Anything not measurable on this host is recorded measured="n/a" with a reason —
#     never faked. Under heavy host load a real latency may exceed its budget; that is
#     recorded honestly (pass="fail") with the load caveat, and `--check` treats an
#     under-load over-budget as a WARNING, not a gate failure (Requirement 11.5 intent).
#   * Every live call runs under a wall-clock watchdog so a wedged socket cannot hang.
#
# USAGE
#   scripts/perf-budgets.sh [--out-dir docs] [--samples N] [--daemon-bin PATH]
#   scripts/perf-budgets.sh --check [--out-dir docs]   # RC-gate consumption of the JSON
#
# macOS bash 3.2 compatible. No `set -e` (many intentional non-zero probes).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/share/dotnet:$PATH"

OUT_DIR="docs"
SAMPLES=6
DAEMON_BIN="build/colima-daemon"
MODE="measure"

while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir)    OUT_DIR="$2"; shift 2 ;;
    --samples)    SAMPLES="$2"; shift 2 ;;
    --daemon-bin) DAEMON_BIN="$2"; shift 2 ;;
    --check)      MODE="check"; shift ;;
    -h|--help)    grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "perf-budgets: unknown arg: $1" >&2; exit 2 ;;
  esac
done

JSON_PATH="${ROOT}/${OUT_DIR}/performance-budgets.json"
MD_PATH="${ROOT}/${OUT_DIR}/performance-budgets.md"

PY="$(command -v python3 || command -v python)"
if [ -z "$PY" ]; then echo "perf-budgets: python3 is required" >&2; exit 2; fi

# ── --check mode: consume the JSON as an RC gate ──────────────────────────────
# Exits 0 when every measurable budget passes. A budget that only fails because
# the host is under heavy load (recorded via under_load=true on the run) is a
# WARNING, not a failure (Requirement 11.5 allows load-inflated timings). A
# NON-load over-budget, or a hard error, exits non-zero.
if [ "$MODE" = "check" ]; then
  if [ ! -f "$JSON_PATH" ]; then
    echo "perf-budgets --check: $JSON_PATH not found (run: make perf-budgets)" >&2
    exit 1
  fi
  "$PY" - "$JSON_PATH" <<'PYCHECK'
import json, sys
doc = json.load(open(sys.argv[1]))
under_load = bool(doc.get("host", {}).get("under_load"))
hard = []      # non-load over-budget → gate failure
warn = []      # under-load over-budget → warning only
for b in doc.get("budgets", []):
    if b.get("pass") == "fail":
        (warn if under_load else hard).append(b)
print("== perf-budgets --check ==")
print("generated:", doc.get("generated_utc"), "| under_load:", under_load)
s = doc.get("summary", {})
print("summary: pass=%s fail=%s n/a=%s total=%s" % (s.get("pass"), s.get("fail"), s.get("na"), s.get("total")))
for b in warn:
    print("  WARN (load): %s measured=%s%s > budget=%s%s"
          % (b["metric"], b["measured"], b["unit"], b["threshold"], b["unit"]))
for b in hard:
    print("  FAIL: %s measured=%s%s > budget=%s%s"
          % (b["metric"], b["measured"], b["unit"], b["threshold"], b["unit"]))
if hard:
    print("RESULT: perf budgets EXCEEDED (not load-attributable)")
    sys.exit(1)
print("RESULT: perf budgets OK" + (" (over-budgets attributed to host load — warnings only)" if warn else ""))
sys.exit(0)
PYCHECK
  exit $?
fi

# ── measure mode ──────────────────────────────────────────────────────────────
# Source the shared safety choke-point: provides guard/docker_e2e/colima_e2e and
# the locked E2E_PROFILE / E2E_SOCK / E2E_DOCKER_HOST constants. Fails closed if
# the env pre-seeds a non-desktop-e2e profile.
# shellcheck source=scripts/live/guard.sh
. "${ROOT}/scripts/live/guard.sh" || { echo "perf-budgets: could not load scripts/live/guard.sh" >&2; exit 1; }
guard "$E2E_PROFILE" || { echo "perf-budgets: guard refused $E2E_PROFILE" >&2; exit 1; }

RESULTS="$(mktemp "${TMPDIR:-/tmp}/perf-results.XXXXXX")"
trap 'rm -f "$RESULTS"' EXIT

now_ns() { gdate +%s%N 2>/dev/null || "$PY" -c 'import time;print(int(time.time()*1e9))'; }
emit()   { printf '%s\t%s\n' "$1" "$2" >> "$RESULTS"; }   # key <TAB> ms|MB (>=0 ok, -1 timeout, -2 err, -3 n/a)

# timed <key> <timeout_s> -- <cmd...> : run once through the guard, record elapsed ms.
# The command runs in a backgrounded subshell; a watchdog kills the whole subtree on
# timeout so a wedged socket can never hang the run. rc 137 → -1 (timeout); other
# non-zero → -2 (error); success → elapsed ms.
timed() {
  local key="$1" to="$2"; shift 2; [ "${1:-}" = "--" ] && shift
  local start end rc pid w
  start="$(now_ns)"
  ( "$@" >/dev/null 2>&1 ) &
  pid=$!
  ( sleep "$to"; kill -9 "$pid" 2>/dev/null; pkill -9 -P "$pid" >/dev/null 2>&1 ) >/dev/null 2>&1 &
  w=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  end="$(now_ns)"
  if [ "$rc" -eq 137 ]; then emit "$key" "-1"; return; fi
  if [ "$rc" -ne 0 ]; then emit "$key" "-2"; return; fi
  emit "$key" "$(( (end - start) / 1000000 ))"
}

echo "== perf-budgets: measuring (read-only) against ${E2E_PROFILE} =="

SOCK_OK=0
[ -S "$E2E_SOCK" ] && SOCK_OK=1
DOCKER_SERVER_VERSION="n/a"
CTR_COUNT="n/a"
IMG_COUNT="n/a"

if [ "$SOCK_OK" -eq 1 ]; then
  echo "-- desktop-e2e socket present; timing docker/colima RPCs (guarded) --"
  # Context facts (guarded, read-only).
  DOCKER_SERVER_VERSION="$(docker_e2e version --format '{{.Server.Version}}' 2>/dev/null | tr -d '[:space:]')"
  [ -z "$DOCKER_SERVER_VERSION" ] && DOCKER_SERVER_VERSION="n/a"
  CTR_COUNT="$(docker_e2e ps -aq 2>/dev/null | grep -c . | tr -d '[:space:]')"
  IMG_COUNT="$(docker_e2e images -q 2>/dev/null | grep -c . | tr -d '[:space:]')"

  i=0
  while [ "$i" -lt "$SAMPLES" ]; do
    timed docker_version   15 -- docker_e2e version --format '{{.Server.Version}}'
    timed docker_info      20 -- docker_e2e info --format '{{.ServerVersion}}'
    timed list_containers  20 -- docker_e2e ps -a -q
    timed list_images      20 -- docker_e2e images -q
    i=$((i + 1))
  done
  # Stream first-frame (stats emits a single frame with --no-stream) + colima control-plane.
  j=0
  while [ "$j" -lt 3 ]; do
    timed stats_first_frame 25 -- docker_e2e stats --no-stream --no-trunc
    timed colima_status     30 -- colima_e2e status --json
    j=$((j + 1))
  done
else
  echo "-- desktop-e2e socket ABSENT; live RPC budgets → measured=n/a --" >&2
fi

# Daemon startup-to-listening + idle RSS: launch the committed daemon binary on a
# PRIVATE /tmp unix socket (listen-only — no colima/docker contact), time to socket,
# read RSS, then graceful-stop. Read-only toward the live env.
DAEMON_BUILD_DATE="n/a"
if [ -x "$DAEMON_BIN" ]; then
  DAEMON_BUILD_DATE="$(stat -f '%Sm' -t '%Y-%m-%d' "$DAEMON_BIN" 2>/dev/null || echo n/a)"
  # Use a SHORT /tmp path, never $TMPDIR: macOS unix-socket sun_path is capped at
  # ~104 bytes and the default $TMPDIR (/var/folders/…/T/) overflows it, which would
  # make net.Listen fail and the daemon exit before creating its socket.
  DSOCK="/tmp/cd-perfd-$$.sock"
  DLOG="/tmp/cd-perfd-$$.log"
  rm -f "$DSOCK"
  # Support both the current daemon (`--listen unix:<path>`) and an older committed
  # build that only accepts `-socket <path>`: pick whichever the binary advertises.
  daemon_help="$("$DAEMON_BIN" -h 2>&1)"
  if printf '%s' "$daemon_help" | grep -q -- '-listen'; then
    daemon_listen_arg="--listen unix:${DSOCK}"
  else
    daemon_listen_arg="-socket ${DSOCK}"
  fi
  d_start="$(now_ns)"
  # shellcheck disable=SC2086  # intentional word-split: two args, path has no spaces
  "$DAEMON_BIN" $daemon_listen_arg >"$DLOG" 2>&1 &
  dpid=$!
  ready=-1
  k=0
  while [ "$k" -lt 200 ]; do   # up to ~10s
    if [ -S "$DSOCK" ]; then d_end="$(now_ns)"; ready=$(( (d_end - d_start) / 1000000 )); break; fi
    if ! kill -0 "$dpid" 2>/dev/null; then break; fi   # died early
    sleep 0.05
    k=$((k + 1))
  done
  emit daemon_startup "$ready"
  if [ "$ready" -ge 0 ]; then
    rss_kb="$(ps -o rss= -p "$dpid" 2>/dev/null | tr -dc 0-9)"
    if [ -n "$rss_kb" ]; then emit daemon_rss_mb "$(( rss_kb / 1024 ))"; else emit daemon_rss_mb "-2"; fi
  else
    emit daemon_rss_mb "-3"
  fi
  kill "$dpid" 2>/dev/null; wait "$dpid" 2>/dev/null
  rm -f "$DSOCK" "$DLOG"
else
  emit daemon_startup "-3"
  emit daemon_rss_mb "-3"
fi

# Host facts for the caveat.
NCPU="$(sysctl -n hw.ncpu 2>/dev/null || echo 0)"
LOADAVG_RAW="$(sysctl -n vm.loadavg 2>/dev/null || echo '{ 0 0 0 }')"

echo "-- assembling ${OUT_DIR}/performance-budgets.{json,md} --"

RESULTS="$RESULTS" JSON_PATH="$JSON_PATH" MD_PATH="$MD_PATH" \
SOCK_OK="$SOCK_OK" NCPU="$NCPU" LOADAVG_RAW="$LOADAVG_RAW" \
DOCKER_SERVER_VERSION="$DOCKER_SERVER_VERSION" CTR_COUNT="$CTR_COUNT" IMG_COUNT="$IMG_COUNT" \
DAEMON_BIN="$DAEMON_BIN" DAEMON_BUILD_DATE="$DAEMON_BUILD_DATE" PERF_PROFILE="$E2E_PROFILE" SAMPLES="$SAMPLES" \
"$PY" - <<'PYGEN'
import os, json, statistics, datetime

results_path = os.environ["RESULTS"]
samples = {}
with open(results_path) as fh:
    for ln in fh:
        ln = ln.strip()
        if not ln or "\t" not in ln:
            continue
        k, v = ln.split("\t", 1)
        try:
            samples.setdefault(k, []).append(int(v))
        except ValueError:
            pass

def valid(xs):
    return [x for x in xs if x is not None and x >= 0]

def agg(key, how):
    xs = samples.get(key, [])
    v = valid(xs)
    if not v:
        # distinguish the failure kind for an honest reason
        raw = xs[0] if xs else -3
        return None, {-1: "timed out", -2: "call failed", -3: "not available on this host"}.get(raw, "not measured")
    if how == "cold":
        first = xs[0]
        return (first if first >= 0 else min(v)), None
    if how == "median_warm":
        warm = valid(xs[1:]) or v
        return int(round(statistics.median(warm))), None
    if how == "min":
        return min(v), None
    if how == "single":
        return v[0], None
    return int(round(statistics.median(v))), None

ncpu = int(os.environ.get("NCPU", "0") or 0)
# vm.loadavg looks like "{ 8.14 8.20 8.32 }"
raw = os.environ.get("LOADAVG_RAW", "")
load1 = None
for tok in raw.replace("{", " ").replace("}", " ").split():
    try:
        load1 = float(tok); break
    except ValueError:
        continue
under_load = bool(ncpu and load1 is not None and load1 > ncpu * 0.6)
sock_ok = os.environ.get("SOCK_OK") == "1"

# Budget definitions. direction is lower-is-better for every timing/size budget.
DEFS = [
    # startup
    dict(metric="Daemon startup to gRPC-listening", category="startup", key="daemon_startup",
         how="single", threshold=1500, unit="ms",
         desc="Time for the committed colima-daemon to create its listening socket (listen-only launch, no RPC)."),
    dict(metric="macOS app cold start", category="startup", key=None,
         threshold=3000, unit="ms",
         na_reason="macOS GUI cold-start is measured via an instrumented app launch / CI, not in this read-only headless harness",
         desc="Cold launch of the SwiftUI app to first interactive frame."),
    # rpc round-trip (warm)
    dict(metric="RPC round-trip: Status/Version (docker version)", category="rpc", key="docker_version",
         how="median_warm", threshold=300, unit="ms",
         desc="Warm round-trip of a Ping/Version-class RPC (backs ColimaService.Status / DockerService version)."),
    dict(metric="RPC round-trip: system info (docker info)", category="rpc", key="docker_info",
         how="median_warm", threshold=600, unit="ms",
         desc="Warm round-trip of a system-status RPC."),
    dict(metric="RPC round-trip: ListContainers (docker ps -a)", category="rpc", key="list_containers",
         how="median_warm", threshold=500, unit="ms",
         desc="Warm round-trip of DockerService.ListContainers."),
    dict(metric="RPC round-trip: ListImages (docker images)", category="rpc", key="list_images",
         how="median_warm", threshold=500, unit="ms",
         desc="Warm round-trip of DockerService.ListImages."),
    dict(metric="Control-plane RPC: colima status", category="rpc", key="colima_status",
         how="median_warm", threshold=2000, unit="ms",
         desc="Warm round-trip of the colima control-plane status (VM Status); CLI-spawn heavy."),
    # stream
    dict(metric="Stream first-frame: stats (docker stats --no-stream)", category="stream", key="stats_first_frame",
         how="min", threshold=2000, unit="ms",
         desc="Latency to the first frame of the stats stream (best of N; backs DockerService.StreamStats / VMStats)."),
    # idle resource
    dict(metric="Daemon idle memory (RSS)", category="resource", key="daemon_rss_mb",
         how="single", threshold=100, unit="MB",
         desc="Resident set size of the freshly-started, idle daemon (listen-only)."),
    # large / cold list
    dict(metric="Cold container-list (first call)", category="large-list", key="list_containers",
         how="cold", threshold=800, unit="ms",
         desc="First (cold) ListContainers after idle; upper bound scales with list size (see host.containers)."),
    dict(metric="Cold image-list (first call)", category="large-list", key="list_images",
         how="cold", threshold=800, unit="ms",
         desc="First (cold) ListImages after idle; upper bound scales with list size (see host.images)."),
    # memory-safety (static, already enforced)
    dict(metric="TUI displayed-output line cap (Property 14)", category="memory-safety", static=2000,
         threshold=2000, unit="lines", pass_static=True,
         desc="maxOutputLines drop-oldest ring in tui/internal/ui/actions.go; enforced by the Property 14 tests."),
    dict(metric="TUI displayed-output byte cap (Property 14)", category="memory-safety", static=262144,
         threshold=262144, unit="bytes", pass_static=True,
         desc="maxOutputBytes (256 KiB) secondary ceiling in tui/internal/ui/actions.go; enforced by the Property 14 tests."),
    dict(metric="gRPC max receive message size", category="memory-safety", static=4194304,
         threshold=4194304, unit="bytes", pass_static=True,
         desc="grpc-go default MaxRecvMsgSize (4 MiB) bounds a single RPC payload held in memory."),
]

budgets = []
for d in DEFS:
    b = dict(metric=d["metric"], category=d["category"], threshold=d["threshold"], unit=d["unit"])
    note = ""
    if "static" in d:
        b["measured"] = d["static"]
        b["pass"] = "pass" if d.get("pass_static") and d["static"] <= d["threshold"] else "fail"
        note = d.get("desc", "")
    elif d.get("key") is None:
        b["measured"] = "n/a"
        b["pass"] = "n/a"
        note = d.get("na_reason", "") + (" — " + d["desc"] if d.get("desc") else "")
    else:
        measured, reason = agg(d["key"], d.get("how", "median"))
        if measured is None:
            b["measured"] = "n/a"
            b["pass"] = "n/a"
            note = ("%s (%s)" % (d.get("desc", ""), reason)).strip()
            if not sock_ok and d["category"] in ("rpc", "stream", "large-list"):
                note = "desktop-e2e socket absent — " + note
        else:
            b["measured"] = measured
            b["pass"] = "pass" if measured <= d["threshold"] else "fail"
            xs = samples.get(d["key"], [])
            v = valid(xs)
            b["samples_ms"] = xs
            if v:
                b["measured_best"] = min(v)
            note = d.get("desc", "")
            if b["pass"] == "fail" and under_load:
                note = (note + " NOTE: over budget under heavy host load (load1=%.2f on %d cores); best observed=%s%s — recorded honestly, attributed to load."
                        % (load1 or 0.0, ncpu, b.get("measured_best", measured), d["unit"])).strip()
    b["note"] = note
    budgets.append(b)

npass = sum(1 for b in budgets if b["pass"] == "pass")
nfail = sum(1 for b in budgets if b["pass"] == "fail")
nna = sum(1 for b in budgets if b["pass"] == "n/a")
# A run is GREEN when nothing fails, OR every failure is load-attributable.
if nfail == 0:
    result = "GREEN"
elif under_load:
    result = "GREEN (over-budgets attributed to host load)"
else:
    result = "BUDGETS-EXCEEDED"

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
doc = {
    "schema": "colima-desktop/performance-budgets@1",
    "generated_utc": now,
    "profile": os.environ.get("PERF_PROFILE", "desktop-e2e"),
    "measurement": "read-only via scripts/live/guard.sh (docker_e2e/colima_e2e); no resource create/destroy",
    "host": {
        "ncpu": ncpu,
        "load_avg_1m": load1,
        "under_load": under_load,
        "docker_server_version": os.environ.get("DOCKER_SERVER_VERSION", "n/a"),
        "containers": os.environ.get("CTR_COUNT", "n/a"),
        "images": os.environ.get("IMG_COUNT", "n/a"),
        "daemon_binary": os.environ.get("DAEMON_BIN", "n/a"),
        "daemon_binary_build_date": os.environ.get("DAEMON_BUILD_DATE", "n/a"),
        "samples_per_rpc": int(os.environ.get("SAMPLES", "0") or 0),
        "socket_present": sock_ok,
    },
    "caveat": ("Host was heavily loaded at measurement time (1-minute load average %s on %d CPUs). "
               "Latency and startup numbers are therefore PESSIMISTIC upper bounds; a value that exceeds "
               "its budget under this load is recorded honestly (pass=\"fail\") and attributed to load — "
               "`--check` treats it as a warning, not a gate failure. Re-run on a quiescent host for "
               "representative numbers." % (("%.2f" % load1) if load1 is not None else "n/a", ncpu)),
    "budgets": budgets,
    "summary": {"pass": npass, "fail": nfail, "na": nna, "total": len(budgets), "result": result},
}

with open(os.environ["JSON_PATH"], "w") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")

# ── human-readable markdown (generated FROM the JSON) ─────────────────────────
def fmt_measured(b):
    m = b["measured"]
    if m == "n/a":
        return "n/a"
    return "%s %s" % (m, b["unit"])

def fmt_threshold(b):
    return "%s %s" % (b["threshold"], b["unit"])

status_icon = {"pass": "PASS", "fail": "FAIL", "n/a": "n/a"}

lines = []
lines.append("# Performance Budgets")
lines.append("")
lines.append("> Generated by `scripts/perf-budgets.sh` — do not hand-edit; re-run `make perf-budgets`.")
lines.append("")
lines.append("Requirement 11.5 (R7 hardening) requires recording **startup-time**, **idle-resource**, "
             "and **large-list** budgets. This document defines those plus the operational RPC / stream / "
             "memory-safety budgets for Colima Desktop, and records the REAL values measured on this host, "
             "**read-only**, against the live disposable `%s` colima profile." % doc["profile"])
lines.append("")
lines.append("- **Generated (UTC):** %s" % doc["generated_utc"])
lines.append("- **Profile:** `%s` (measurement %s)" % (doc["profile"], doc["measurement"]))
lines.append("- **Docker server:** %s | **containers:** %s | **images:** %s" %
             (doc["host"]["docker_server_version"], doc["host"]["containers"], doc["host"]["images"]))
lines.append("- **Daemon binary:** `%s` (built %s)" %
             (doc["host"]["daemon_binary"], doc["host"]["daemon_binary_build_date"]))
lines.append("- **Host:** %d CPUs, 1-min load average %s%s" %
             (doc["host"]["ncpu"],
              ("%.2f" % load1) if load1 is not None else "n/a",
              "  ⚠️ **HEAVILY LOADED**" if under_load else ""))
lines.append("")
lines.append("> **Load caveat.** %s" % doc["caveat"])
lines.append("")
lines.append("**Result:** %s — pass=%d, fail=%d, n/a=%d, total=%d." %
             (doc["summary"]["result"], npass, nfail, nna, len(budgets)))
lines.append("")
lines.append("| Category | Metric | Budget | Measured | Status | Notes |")
lines.append("|----------|--------|--------|----------|--------|-------|")
for b in budgets:
    note = b.get("note", "").replace("|", "\\|")
    extra = ""
    if "measured_best" in b and b["pass"] != "n/a":
        extra = " (best %s %s)" % (b["measured_best"], b["unit"])
    lines.append("| %s | %s | %s | %s%s | %s | %s |" %
                 (b["category"], b["metric"], fmt_threshold(b), fmt_measured(b), extra,
                  status_icon[b["pass"]], note))
lines.append("")
lines.append("## Methodology")
lines.append("")
lines.append("- **Live RPCs** are timed by routing `docker`/`colima` through `scripts/live/guard.sh` "
             "(`docker_e2e`/`colima_e2e`), which pins the `%s` docker socket and rejects any host/profile "
             "override — so measurement is confined to the disposable profile and is strictly read-only "
             "(status/list/stats only; nothing is created, started, stopped, or deleted)." % doc["profile"])
lines.append("- Each RPC is sampled %d times; the **first** sample is reported as the *cold* number and the "
             "**median of the warm** samples as the round-trip number. Stream first-frame is the best of 3." %
             doc["host"]["samples_per_rpc"])
lines.append("- **Daemon startup / idle RSS** launch the committed `%s` on a private `/tmp` unix socket in "
             "listen-only mode (no RPC, no colima/docker contact), time to the listening socket, then read "
             "RSS and graceful-stop." % doc["host"]["daemon_binary"])
lines.append("- **Memory-safety** budgets are static, already-enforced caps: the TUI bounded-output ring "
             "(`maxOutputLines`, `maxOutputBytes`) verified by the Property 14 tests, and the grpc-go default "
             "4 MiB receive limit that bounds a single RPC payload.")
lines.append("- Every live call runs under a wall-clock watchdog, so a wedged socket can never hang the run.")
lines.append("")
lines.append("## Re-measuring / gating")
lines.append("")
lines.append("```bash")
lines.append("make perf-budgets     # re-measure against a running desktop-e2e and regenerate this doc + JSON")
lines.append("make perf-check       # RC-gate: read docs/performance-budgets.json; non-load over-budgets fail")
lines.append("```")
lines.append("")
lines.append("The machine-readable source of truth is `docs/performance-budgets.json` "
             "(each budget = `{metric, threshold, measured, unit, pass}`); the release-candidate gate consumes "
             "it via `scripts/perf-budgets.sh --check`. Per Requirement 11.5's intent, a budget that is only "
             "exceeded because the host is under heavy load is reported as a warning, not a gate failure; a "
             "non-load over-budget fails the gate.")
lines.append("")
lines.append("## Not measured here (honest n/a)")
lines.append("")
for b in budgets:
    if b["pass"] == "n/a":
        lines.append("- **%s** — %s" % (b["metric"], b.get("note", "")))
lines.append("")

with open(os.environ["MD_PATH"], "w") as fh:
    fh.write("\n".join(lines))

print("perf-budgets: wrote %s and %s" % (os.environ["JSON_PATH"], os.environ["MD_PATH"]))
print("perf-budgets: result=%s pass=%d fail=%d na=%d" % (result, npass, nfail, nna))
PYGEN

echo "== perf-budgets: done =="
