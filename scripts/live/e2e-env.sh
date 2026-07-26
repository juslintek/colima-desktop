#!/usr/bin/env bash
# scripts/live/e2e-env.sh — disposable live-backend environment lifecycle.
#
# Manages a DEDICATED, DISPOSABLE colima profile named "desktop-e2e" that is the
# ONLY profile the live real-backend tests (verify.sh RealBackend lane, the TUI
# gated PTY lane, and the R9 exercise harness) ever touch. It NEVER creates,
# modifies, stops, or deletes any other colima profile.
#
# Subcommands (all idempotent):
#   up                bring the env up: stop OrbStack (recorded for restore),
#                     ensure colima+docker are installed, start ONLY desktop-e2e,
#                     block on its profile-scoped docker socket, write evidence.
#   status            report whether desktop-e2e is running + its docker socket path.
#   down              stop the desktop-e2e profile (reversible; keeps it for reuse).
#   teardown          remove e2e- resources AND delete the desktop-e2e profile
#                     (leaves the host clean).
#   restore-orbstack  restart OrbStack (undo the `up` stop).
#   guard <profile>   exit 0 iff <profile> == desktop-e2e, else reject (hard
#                     safety invariant; shared with the harness / verify.sh).
#   selftest          run the shared guard's accept/reject battery (no mutation).
#   harness-exec -- <cmd...>
#                     guard, lock the safe env, then exec <cmd> (R9 harness lane).
#   evidence          (re)write colima status + docker info evidence.
#
# HARD SAFETY INVARIANTS (defined once in scripts/live/guard.sh, sourced here):
#   * desktop-e2e ONLY. E2E_PROFILE is a locked literal that cannot be overridden
#     by env or args; every mutating colima call is routed through `colima_e2e`,
#     which asserts the target via `guard`, injects `--profile desktop-e2e`, and
#     rejects any caller-supplied --profile/-p. No other profile can be touched.
#   * Every docker call goes through `docker_e2e`, which pins DOCKER_HOST to the
#     profile-scoped socket and rejects any -H/--host/-c/--context override,
#     never the ambient docker context / /var/run/docker.sock.
#   * Idempotent: `up` when already up is a no-op success; `down`/`teardown` when
#     already down/absent succeed.
#   * Reversible: stopping OrbStack is recorded and restorable via restore-orbstack.
#
# macOS bash 3.2 compatible. No `set -e` (many intentional non-zero status checks);
# errors are handled explicitly with return codes.
set -uo pipefail

# --- shared safety choke-point (single source of truth) ------------------------
# The allowed-profile constant, the guard, and the ONLY sanctioned colima/docker
# mutators (colima_e2e / docker_e2e) live in guard.sh so this lifecycle and the
# R9 exercise harness (task 10.6) share ONE enforced invariant. Sourcing fails
# closed if the environment tried to pre-seed a non-desktop-e2e profile.
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/live/guard.sh
. "${HERE}/guard.sh" || { printf '[e2e-env] FATAL: could not load the safety guard (guard.sh)\n' >&2; exit 1; }

# Back-compat alias: existing lifecycle code below refers to $SOCK.
readonly SOCK="$E2E_SOCK"

ROOT="$(cd "${HERE}/../.." && pwd)"
readonly ROOT
# Live evidence area (self-ignored so host-specific data is never committed — R8.6).
readonly LIVE_DIR="${LIVE_EVIDENCE_DIR:-${ROOT}/artifacts/live}"
readonly ORB_STATE="${LIVE_DIR}/orbstack.state"

# Fresh-creation resources (modest, disposable). Applied ONLY when the profile
# does not yet exist — an existing profile is restarted with its own config so
# it is never destroyed/reshaped.
readonly E2E_CPU=2
readonly E2E_MEMORY=2      # GiB
readonly E2E_DISK=20       # GiB
readonly E2E_VM_TYPE="vz"
readonly E2E_MOUNT_TYPE="virtiofs"
readonly E2E_RUNTIME="docker"

log() { printf '[e2e-env] %s\n' "$*" >&2; }
err() { printf '[e2e-env] ERROR: %s\n' "$*" >&2; }

# run_to <seconds> <cmd...> : run a command with a hard timeout (no `timeout`
# binary on macOS). Prevents a wedged docker socket from hanging the script.
run_to() {
  local t="$1"; shift
  "$@" &
  local p=$!
  ( sleep "$t"; kill -9 "$p" 2>/dev/null ) >/dev/null 2>&1 &
  local w=$!
  wait "$p" 2>/dev/null; local rc=$?
  # Stop the watchdog and reap it so the shell does not print an async
  # "Terminated" job-control notice into the logs/evidence.
  kill "$w" 2>/dev/null
  wait "$w" 2>/dev/null
  return $rc
}

# guard() and colima_e2e()/docker_e2e() are provided by guard.sh (sourced above),
# so this lifecycle and the R9 exercise harness enforce ONE shared invariant.

# --- profile state -------------------------------------------------------------
# profile_status: echoes running | stopped | absent for desktop-e2e.
profile_status() {
  local line
  line="$(colima list --json 2>/dev/null | grep '"name":"'"${E2E_PROFILE}"'"')" || true
  if [ -z "$line" ]; then
    echo "absent"; return 0
  fi
  case "$line" in
    *'"status":"Running"'*) echo "running" ;;
    *)                      echo "stopped" ;;
  esac
}

# --- OrbStack (reversible stop) ------------------------------------------------
orbstack_running() { pgrep -x OrbStack >/dev/null 2>&1; }

record_orbstack_state() { # $1 = running | not-running
  mkdir -p "$LIVE_DIR"
  {
    echo "# desktop-e2e live-env — OrbStack state recorded $(date -u +%FT%TZ)"
    echo "orbstack_was=${1}"
    echo "# restore with: scripts/live/e2e-env.sh restore-orbstack"
    echo "# or manually:  orbctl start   (or: open -a OrbStack)"
  } > "$ORB_STATE"
}

stop_orbstack() {
  if orbstack_running; then
    log "OrbStack is running — stopping it gracefully (recorded for restore)"
    record_orbstack_state "running"
    if command -v orbctl >/dev/null 2>&1; then
      orbctl stop >/dev/null 2>&1 || osascript -e 'quit app "OrbStack"' >/dev/null 2>&1 || pkill -x OrbStack 2>/dev/null || true
    else
      osascript -e 'quit app "OrbStack"' >/dev/null 2>&1 || pkill -x OrbStack 2>/dev/null || true
    fi
    local i
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
      orbstack_running || { log "OrbStack stopped"; return 0; }
      sleep 1
    done
    if orbstack_running; then
      log "WARN: OrbStack still running after stop attempt; live tests still bind ONLY the ${E2E_PROFILE} socket, so this is safe"
    fi
  else
    log "OrbStack not running — nothing to stop"
    record_orbstack_state "not-running"
  fi
  return 0
}

restore_orbstack() {
  if orbstack_running; then
    log "OrbStack already running"
    return 0
  fi
  if [ -f "$ORB_STATE" ]; then
    log "recorded state: $(grep '^orbstack_was=' "$ORB_STATE" 2>/dev/null || echo 'unknown')"
  fi
  log "starting OrbStack ..."
  if command -v orbctl >/dev/null 2>&1; then
    orbctl start >/dev/null 2>&1 || open -a OrbStack >/dev/null 2>&1 || true
  else
    open -a OrbStack >/dev/null 2>&1 || true
  fi
  log "OrbStack start requested (it may take a moment to come up)"
  return 0
}

# --- tool install --------------------------------------------------------------
ensure_tools() {
  local missing=""
  command -v colima >/dev/null 2>&1 || missing="${missing} colima"
  command -v docker >/dev/null 2>&1 || missing="${missing} docker"
  missing="${missing# }"
  if [ -z "$missing" ]; then
    log "colima + docker present ($(colima version 2>/dev/null | head -1))"
    return 0
  fi
  log "installing missing tools:${missing:+ }${missing}"
  if command -v brew >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    brew install ${missing} || { err "brew install failed for:${missing:+ }${missing}"; return 1; }
  else
    err "missing tools (${missing}) and Homebrew is not available to install them"
    return 1
  fi
}

# --- gitignore the evidence dir (R8.6) -----------------------------------------
ensure_evidence_gitignore() {
  mkdir -p "$LIVE_DIR"
  if [ ! -f "${LIVE_DIR}/.gitignore" ]; then
    {
      echo "# Transient live-backend evidence — contains host-specific paths/data."
      echo "# Never commit (Requirement 8.6 / R6 global gate)."
      echo "# Regenerate with: scripts/live/e2e-env.sh evidence"
      echo "*"
      echo "!.gitignore"
    } > "${LIVE_DIR}/.gitignore"
  fi
}

# --- socket readiness / verification -------------------------------------------
wait_socket() {
  if [ -S "$SOCK" ]; then
    log "docker socket present: ${SOCK}"
    return 0
  fi
  log "waiting for docker socket ${SOCK} (up to ~5m) ..."
  local i
  for i in $(seq 1 150); do
    [ -S "$SOCK" ] && { log "docker socket present: ${SOCK}"; return 0; }
    sleep 2
  done
  err "docker socket ${SOCK} did not appear within timeout"
  return 1
}

# docker MUST be pinned to the profile socket — the ambient context points at
# /var/run/docker.sock (no daemon when OrbStack is stopped) and would hang.
# docker_e2e (from guard.sh) asserts the guard and pins DOCKER_HOST for us.
verify_socket() {
  if run_to 30 docker_e2e info >/dev/null 2>&1; then
    log "docker responds via ${SOCK}"
    return 0
  fi
  err "docker did not respond via ${SOCK}"
  return 1
}

# --- evidence ------------------------------------------------------------------
write_evidence() {
  ensure_evidence_gitignore
  log "capturing evidence into ${LIVE_DIR} ..."
  colima status --profile "$E2E_PROFILE" --json > "${LIVE_DIR}/colima-status.json" 2>/dev/null || true
  colima list --json                          > "${LIVE_DIR}/colima-list.json"   2>/dev/null || true
  colima status --profile "$E2E_PROFILE"      > "${LIVE_DIR}/colima-status.txt"  2>&1 || true
  run_to 30 docker_e2e info    > "${LIVE_DIR}/docker-info.txt"    2>&1 || true
  run_to 30 docker_e2e version > "${LIVE_DIR}/docker-version.txt" 2>&1 || true
  {
    echo "desktop-e2e live-env evidence — $(date -u +%FT%TZ)"
    echo "profile:       ${E2E_PROFILE}"
    echo "status:        $(profile_status)"
    echo "docker socket: ${SOCK}"
    echo "socket present: $([ -S "$SOCK" ] && echo yes || echo no)"
  } > "${LIVE_DIR}/e2e-summary.txt"
  log "evidence written: colima-status.json, colima-list.json, docker-info.txt, docker-version.txt, e2e-summary.txt"
}

# --- lifecycle -----------------------------------------------------------------
ensure_profile_up() {
  local st; st="$(profile_status)"
  case "$st" in
    running)
      log "profile '${E2E_PROFILE}' already running (idempotent no-op)"
      return 0
      ;;
    stopped)
      log "profile '${E2E_PROFILE}' exists but stopped — restarting with its existing config"
      colima_e2e start || { err "failed to restart '${E2E_PROFILE}'"; return 1; }
      ;;
    absent)
      log "profile '${E2E_PROFILE}' absent — creating (${E2E_CPU} CPU / ${E2E_MEMORY} GiB / ${E2E_DISK} GiB, ${E2E_VM_TYPE}, ${E2E_MOUNT_TYPE}, ${E2E_RUNTIME})"
      colima_e2e start \
        --cpu "$E2E_CPU" \
        --memory "$E2E_MEMORY" \
        --disk "$E2E_DISK" \
        --vm-type "$E2E_VM_TYPE" \
        --mount-type "$E2E_MOUNT_TYPE" \
        --runtime "$E2E_RUNTIME" \
        || { err "failed to create/start '${E2E_PROFILE}'"; return 1; }
      ;;
    *)
      err "unexpected profile status: ${st}"
      return 1
      ;;
  esac
  return 0
}

cmd_up() {
  log "bringing up the '${E2E_PROFILE}' live environment ..."
  ensure_tools    || return 1
  stop_orbstack
  ensure_profile_up || return 1
  wait_socket     || return 1
  verify_socket   || return 1
  write_evidence
  log "UP: '${E2E_PROFILE}' is running; docker socket ${SOCK} responds."
  log "run 'scripts/live/e2e-env.sh status' to re-check, or 'down'/'teardown' to stop/remove."
  return 0
}

cmd_status() {
  local st; st="$(profile_status)"
  echo "profile:         ${E2E_PROFILE}"
  echo "status:          ${st}"
  echo "docker socket:   ${SOCK}"
  if [ -S "$SOCK" ]; then
    echo "socket present:  yes"
    if run_to 20 docker_e2e info >/dev/null 2>&1; then
      echo "docker responds: yes"
    else
      echo "docker responds: no"
    fi
  else
    echo "socket present:  no"
    echo "docker responds: no"
  fi
  [ "$st" = "running" ]
}

cmd_down() {
  local st; st="$(profile_status)"
  if [ "$st" = "running" ]; then
    log "stopping profile '${E2E_PROFILE}' ..."
    colima_e2e stop || { err "failed to stop '${E2E_PROFILE}'"; return 1; }
    log "DOWN: '${E2E_PROFILE}' stopped (profile retained; run 'up' to restart or 'teardown' to delete)."
  else
    log "profile '${E2E_PROFILE}' not running (${st}) — nothing to stop (idempotent)"
  fi
  return 0
}

# Best-effort removal of e2e- prefixed docker resources before deleting the VM.
cleanup_e2e_resources() {
  if [ ! -S "$SOCK" ]; then
    log "docker socket absent — skipping e2e- resource cleanup"
    return 0
  fi
  log "removing e2e- prefixed docker resources (best-effort) ..."
  local ids
  ids="$(run_to 20 docker_e2e ps -aq --filter 'name=e2e-' 2>/dev/null)" || true
  if [ -n "$ids" ]; then
    # shellcheck disable=SC2086
    run_to 40 docker_e2e rm -f $ids >/dev/null 2>&1 || true
  fi
  run_to 20 docker_e2e network prune -f --filter 'label=e2e' >/dev/null 2>&1 || true
  run_to 20 docker_e2e volume  prune -f --filter 'label=e2e' >/dev/null 2>&1 || true
  return 0
}

cmd_teardown() {
  cleanup_e2e_resources
  local st; st="$(profile_status)"
  if [ "$st" = "absent" ]; then
    log "profile '${E2E_PROFILE}' already absent — nothing to delete (idempotent)"
    return 0
  fi
  log "deleting profile '${E2E_PROFILE}' (force) to leave the host clean ..."
  colima_e2e delete --force || { err "failed to delete '${E2E_PROFILE}'"; return 1; }
  log "TEARDOWN: '${E2E_PROFILE}' deleted."
  log "OrbStack was stopped by 'up' if it had been running — restore it with 'scripts/live/e2e-env.sh restore-orbstack'."
  return 0
}

usage() {
  cat >&2 <<EOF
Usage: scripts/live/e2e-env.sh <subcommand>

  up                Stop OrbStack (recorded), ensure colima+docker, start ONLY the
                    disposable '${E2E_PROFILE}' profile, block on its docker socket.
  status            Report whether '${E2E_PROFILE}' is running + its docker socket path.
  down              Stop the '${E2E_PROFILE}' profile (reversible; profile retained).
  teardown          Remove e2e- resources AND delete '${E2E_PROFILE}' (host left clean).
  restore-orbstack  Restart OrbStack (undo the 'up' stop).
  guard <profile>   Exit 0 iff <profile> == '${E2E_PROFILE}', else reject (SAFETY).
  selftest          Run the shared guard's accept/reject battery (no live mutation).
  harness-exec -- <cmd...>
                    Guard, lock the safe env, then exec <cmd> (R9 harness choke-point).
  evidence          (Re)write colima/docker evidence into ${LIVE_DIR}.

Safety: this script NEVER touches any colima profile other than '${E2E_PROFILE}'.
The allowed-profile constant + guard + colima_e2e/docker_e2e mutators are defined
once in scripts/live/guard.sh and shared by every live-mutating entry point.
EOF
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    up)               shift; cmd_up "$@" ;;
    status)           shift; cmd_status "$@" ;;
    down)             shift; cmd_down "$@" ;;
    teardown)         shift; cmd_teardown "$@" ;;
    restore-orbstack) shift; restore_orbstack "$@" ;;
    guard)            shift; guard "${1:-}" ;;
    selftest)         shift; _live_guard_selftest "$@" ;;
    harness-exec)     shift; _live_guard_exec "$@" ;;
    evidence)         shift; write_evidence "$@" ;;
    ""|-h|--help|help) usage; [ -z "$cmd" ] && exit 2 || exit 0 ;;
    *) err "unknown subcommand: ${cmd}"; usage; exit 2 ;;
  esac
}

main "$@"
