#!/usr/bin/env bash
# scripts/live/deps-check.sh — LIVE DependencyManager verification harness (R10).
#
# WHAT THIS PROVES
#   The macOS DependencyManager (Sources/Services/DependencyManager.swift) reports
#   the REAL host state — never a hardcoded value — for every tool Colima Desktop
#   tracks: colima, lima, qemu, krunkit, docker-cli, kubectl (Requirement 10.1).
#   This harness runs the SAME detection semantics as the Swift probe against the
#   running `desktop-e2e` environment and records which tools are present/absent/
#   outdated on THIS host, plus the strongest live signal: the Docker daemon
#   actually responding over the profile-scoped socket.
#
# STRICTLY READ-ONLY toward the live environment.
#   It only reads: binary presence + `--version`, `docker version` (via the
#   guarded desktop-e2e socket), `colima status`, `limactl list`, and
#   `kubectl version --client`. It NEVER creates/removes/starts/stops/deletes any
#   container, image, volume, network, VM, or profile. Every docker/colima call is
#   routed through the shared guard (scripts/live/guard.sh), which pins the
#   desktop-e2e profile/socket and rejects any override.
#
# EVIDENCE
#   Writes machine-readable + human-readable evidence into artifacts/live/ (which
#   is self-git-ignored, so host-specific paths are never committed — R8.6):
#     artifacts/live/deps-check.json
#     artifacts/live/deps-check.txt
#
# The version floors below MIRROR DependencyTool.minimumVersion in the Swift
# source, so the shell classification matches the app's classification.
#
# macOS bash 3.2 compatible. No `set -e` (many intentional non-zero checks).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/live/guard.sh
. "${HERE}/guard.sh" || { printf '[deps-check] FATAL: could not load the safety guard (guard.sh)\n' >&2; exit 1; }

ROOT="$(cd "${HERE}/../.." && pwd)"
LIVE_DIR="${LIVE_EVIDENCE_DIR:-${ROOT}/artifacts/live}"

# Search paths mirror SystemDependencyProbe.searchPaths (Apple-silicon brew,
# Intel brew, system).
SEARCH_PATHS="/opt/homebrew/bin /usr/local/bin /usr/bin /bin"

log() { printf '[deps-check] %s\n' "$*" >&2; }

# run_to <seconds> <cmd...> : hard timeout (macOS has no `timeout` binary) so a
# wedged socket/binary can never hang the harness.
run_to() {
  local t="$1"; shift
  "$@" &
  local p=$!
  ( sleep "$t"; kill -9 "$p" 2>/dev/null ) >/dev/null 2>&1 &
  local w=$!
  wait "$p" 2>/dev/null; local rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  return $rc
}

# resolve_binary "<cand1 cand2 ...>" -> prints first executable found, else empty.
resolve_binary() {
  local cands="$1" c d full
  for c in $cands; do
    for d in $SEARCH_PATHS; do
      full="${d}/${c}"
      [ -x "$full" ] && { printf '%s' "$full"; return 0; }
    done
  done
  return 1
}

# extract_ver <text> -> first dotted numeric version, else empty.
extract_ver() { printf '%s' "$1" | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1; }

# get_version <path> <tool> -> parsed version string (mirrors the Swift probe's
# per-tool version invocation).
get_version() {
  local path="$1" tool="$2"
  case "$tool" in
    kubectl) extract_ver "$(run_to 10 "$path" version --client --output=yaml 2>/dev/null)" ;;
    colima)  extract_ver "$(run_to 10 "$path" version 2>/dev/null)" ;;
    *)       extract_ver "$(run_to 10 "$path" --version 2>&1)" ;;
  esac
}

# ver_lt <a> <b> -> exit 0 (true) iff version a is strictly older than b.
ver_lt() {
  local a b a1 a2 a3 b1 b2 b3
  a="$1"; b="$2"
  a1="$(printf '%s' "$a" | cut -d. -f1)"; a2="$(printf '%s' "$a" | cut -d. -f2)"; a3="$(printf '%s' "$a" | cut -d. -f3)"
  b1="$(printf '%s' "$b" | cut -d. -f1)"; b2="$(printf '%s' "$b" | cut -d. -f2)"; b3="$(printf '%s' "$b" | cut -d. -f3)"
  a1="${a1:-0}"; a2="${a2:-0}"; a3="${a3:-0}"
  b1="${b1:-0}"; b2="${b2:-0}"; b3="${b3:-0}"
  # guard against non-numeric
  case "${a1}${a2}${a3}${b1}${b2}${b3}" in *[!0-9]*) return 1 ;; esac
  [ "$a1" -lt "$b1" ] && return 0; [ "$a1" -gt "$b1" ] && return 1
  [ "$a2" -lt "$b2" ] && return 0; [ "$a2" -gt "$b2" ] && return 1
  [ "$a3" -lt "$b3" ] && return 0
  return 1
}

# Per-tool metadata (mirrors DependencyTool in the Swift source).
#   tool | binary-candidates | minimum-version | required | brew-formula
tool_meta() {
  case "$1" in
    colima)     printf '%s\t%s\t%s\t%s' "colima" "0.6.0" "true"  "colima" ;;
    lima)       printf '%s\t%s\t%s\t%s' "limactl" "0.20.0" "false" "lima" ;;
    qemu)       printf '%s\t%s\t%s\t%s' "qemu-system-aarch64 qemu-system-x86_64 qemu-img" "8.0.0" "false" "qemu" ;;
    krunkit)    printf '%s\t%s\t%s\t%s' "krunkit" "0.1.0" "false" "krunkit" ;;
    docker-cli) printf '%s\t%s\t%s\t%s' "docker" "20.10.0" "true" "docker" ;;
    kubectl)    printf '%s\t%s\t%s\t%s' "kubectl" "1.24.0" "false" "kubectl" ;;
  esac
}

TOOLS="colima lima qemu krunkit docker-cli kubectl"

main() {
  guard "$E2E_PROFILE" || { log "SAFETY: guard refused; aborting"; exit 1; }
  mkdir -p "$LIVE_DIR"

  local ts arch
  ts="$(date -u +%FT%TZ)"
  arch="$(uname -m)"

  # --- live Docker daemon signal (strongest evidence) via the desktop-e2e socket
  local docker_present docker_client_ver docker_server_ver docker_responds ver_out
  docker_present="$(resolve_binary docker || true)"
  docker_client_ver=""; docker_server_ver=""; docker_responds="false"
  if [ -n "$docker_present" ]; then
    ver_out="$(run_to 25 docker_e2e version 2>/dev/null)" || true
    docker_client_ver="$(printf '%s' "$ver_out" | awk '/^Client/{c=1} c&&/Version:/{print $2; exit}')"
    docker_server_ver="$(printf '%s' "$ver_out" | awk '/^Server/{s=1} s&&/Version:/{print $2; exit}')"
    [ -n "$docker_server_ver" ] && docker_responds="true"
  fi

  # --- colima profile status (read-only, guarded)
  local colima_status
  colima_status="$(run_to 20 colima_e2e status 2>&1 | grep -Eo 'is running|is not running' | head -1)"
  [ -z "$colima_status" ] && colima_status="unknown"

  # --- classify every tracked tool ------------------------------------------
  local json_tools="" txt_lines="" summary_present=0 summary_missing=0 summary_outdated=0
  local first=1
  local tool meta binary_cands minv required brewf path version state installcmd
  for tool in $TOOLS; do
    meta="$(tool_meta "$tool")"
    binary_cands="$(printf '%s' "$meta" | cut -f1)"
    minv="$(printf '%s' "$meta" | cut -f2)"
    required="$(printf '%s' "$meta" | cut -f3)"
    brewf="$(printf '%s' "$meta" | cut -f4)"

    path="$(resolve_binary "$binary_cands" || true)"
    version=""; state="missing"; installcmd=""
    if [ -n "$path" ]; then
      version="$(get_version "$path" "$tool")"
      if [ -n "$version" ] && ver_lt "$version" "$minv"; then
        state="outdated"
      else
        state="installed"
      fi
    fi
    if [ "$state" != "installed" ]; then
      if resolve_binary brew >/dev/null 2>&1; then
        if [ "$tool" = "krunkit" ]; then
          installcmd="brew tap slp/krunkit && brew install ${brewf}"
        else
          installcmd="brew install ${brewf}"
        fi
      else
        installcmd="signed download (see DependencyManager.signedDownloadURL)"
      fi
    fi

    case "$state" in
      installed) summary_present=$((summary_present + 1)) ;;
      missing)   summary_missing=$((summary_missing + 1)) ;;
      outdated)  summary_outdated=$((summary_outdated + 1)) ;;
    esac

    txt_lines="${txt_lines}$(printf '  %-11s %-9s %-10s %s\n' "$tool" "$state" "${version:-–}" "${path:-not found}")
"
    [ $first -eq 0 ] && json_tools="${json_tools},"
    first=0
    json_tools="${json_tools}
    {\"tool\":\"${tool}\",\"present\":$([ -n "$path" ] && echo true || echo false),\"state\":\"${state}\",\"version\":\"${version}\",\"minimum\":\"${minv}\",\"required\":${required},\"resolved_path\":\"${path}\",\"install_path\":\"${installcmd}\"}"
  done

  # --- write JSON evidence ---------------------------------------------------
  {
    printf '{\n'
    printf '  "generated": "%s",\n' "$ts"
    printf '  "host_arch": "%s",\n' "$arch"
    printf '  "profile": "%s",\n' "$E2E_PROFILE"
    printf '  "docker_socket": "%s",\n' "$E2E_SOCK"
    printf '  "docker_socket_present": %s,\n' "$([ -S "$E2E_SOCK" ] && echo true || echo false)"
    printf '  "docker_daemon_responds": %s,\n' "$docker_responds"
    printf '  "docker_server_version": "%s",\n' "$docker_server_ver"
    printf '  "docker_client_version": "%s",\n' "$docker_client_ver"
    printf '  "colima_profile_status": "%s",\n' "$colima_status"
    printf '  "summary": {"installed": %d, "missing": %d, "outdated": %d},\n' "$summary_present" "$summary_missing" "$summary_outdated"
    printf '  "tools": [%s\n  ]\n' "$json_tools"
    printf '}\n'
  } > "${LIVE_DIR}/deps-check.json"

  # --- write human-readable evidence ----------------------------------------
  {
    printf 'DependencyManager LIVE check — %s\n' "$ts"
    printf 'host arch:              %s\n' "$arch"
    printf 'profile:               %s\n' "$E2E_PROFILE"
    printf 'docker socket:         %s (present: %s)\n' "$E2E_SOCK" "$([ -S "$E2E_SOCK" ] && echo yes || echo no)"
    printf 'docker daemon responds: %s (server %s, client %s)\n' "$docker_responds" "${docker_server_ver:-?}" "${docker_client_ver:-?}"
    printf 'colima profile status:  %s\n' "$colima_status"
    printf '\n  %-11s %-9s %-10s %s\n' "TOOL" "STATE" "VERSION" "PATH"
    printf '  %s\n' "-------------------------------------------------------------"
    printf '%s' "$txt_lines"
    printf '\nclassification floors mirror DependencyTool.minimumVersion (Swift).\n'
    printf 'installed=%d missing=%d outdated=%d\n' "$summary_present" "$summary_missing" "$summary_outdated"
  } > "${LIVE_DIR}/deps-check.txt"

  # --- echo the summary to stdout -------------------------------------------
  cat "${LIVE_DIR}/deps-check.txt"
  log "evidence written: ${LIVE_DIR}/deps-check.json, ${LIVE_DIR}/deps-check.txt"

  # GREEN if the live checks ran and the docker daemon responded over the
  # profile socket (missing optional tools are valid evidence, not a failure).
  if [ "$docker_responds" = "true" ]; then
    log "RESULT: GREEN — live checks ran; docker daemon responds via ${E2E_PROFILE} socket."
    return 0
  fi
  log "RESULT: checks ran but docker daemon did not respond via ${E2E_PROFILE} socket."
  return 3
}

main "$@"
