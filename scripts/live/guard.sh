#!/usr/bin/env bash
# scripts/live/guard.sh — the single, shared PROFILE SAFETY CHOKE-POINT for every
# piece of live-backend tooling (Property 1 / Requirements 8.2, 8.5).
#
# WHY THIS FILE EXISTS
#   Live real-backend verification runs DESTRUCTIVE Colima/Docker operations
#   (create / start / stop / delete). The program's hardest invariant is that
#   those operations may ONLY ever touch the disposable `desktop-e2e` profile —
#   NEVER the user's `default` profile or any real data. This file is the ONE
#   place the allowed-profile constant is defined and the ONE gate every
#   live-mutating entry point must pass through, so the invariant cannot be
#   bypassed by environment, arguments, or a future harness that forgets to
#   re-implement it.
#
# HOW IT IS USED (choke-point, three ways)
#   * sourced by scripts/live/e2e-env.sh  (the lifecycle: up / down / teardown)
#   * sourced OR exec'd by the R9 live-exercise harness (task 10.6) so its
#     exercise physically cannot target another profile
#   * runnable as a CLI for shell / CI callers and for its own self-test:
#       scripts/live/guard.sh guard <profile>    # exit 0 iff desktop-e2e
#       scripts/live/guard.sh profile            # print the locked profile name
#       scripts/live/guard.sh socket             # print the profile-scoped socket
#       scripts/live/guard.sh env                # print the locked, safe env exports
#       scripts/live/guard.sh exec -- <cmd...>   # guard, lock env, then exec cmd
#       scripts/live/guard.sh selftest           # prove the accept/reject battery
#
# HARD RULES ENFORCED HERE
#   1. E2E_PROFILE is a LOCKED literal. It is NEVER read from the environment or
#      from a command-line argument. If the environment tries to pre-seed a
#      different value, loading fails CLOSED (refuses to run at all).
#   2. guard(<profile>) returns 0 iff <profile> == desktop-e2e (exact match);
#      every other value prints a SAFETY message and returns non-zero — BEFORE
#      any Colima/Docker call is issued.
#   3. colima_e2e / docker_e2e are the ONLY sanctioned mutators. They assert the
#      guard, pin the profile / socket, and REJECT any caller-supplied profile
#      flag (colima --profile/-p) or host/context flag (docker -H/--host/-c/
#      --context) so the injected target can never be overridden.
#   4. Read-only: nothing in this file starts / stops / deletes / reshapes any
#      profile. It only decides "allowed?" and pins the target.
#
# macOS bash 3.2 compatible. Safe to source (returns) and to execute (exits).
# No `set` at file scope on purpose: a sourced library must not mutate the
# caller's shell options. Every expansion is written to be `set -u` safe.

# --- locked constant (idempotent + fail-closed against env/arg override) -------
if [ "${_LIVE_GUARD_LOADED:-}" != "1" ]; then
  # Fail closed: if something pre-seeded E2E_PROFILE to anything other than the
  # allowed profile, refuse rather than trust it. (An inherited value that
  # already equals desktop-e2e is harmless and accepted.)
  if [ -n "${E2E_PROFILE+x}" ] && [ "${E2E_PROFILE}" != "desktop-e2e" ]; then
    printf '[live-guard] FATAL: E2E_PROFILE was pre-set to "%s"; refusing to run (only desktop-e2e is allowed).\n' "${E2E_PROFILE}" >&2
    return 1 2>/dev/null || exit 1
  fi
  readonly E2E_PROFILE="desktop-e2e"
  readonly E2E_COLIMA_HOME="${HOME}/.colima"
  readonly E2E_SOCK="${E2E_COLIMA_HOME}/${E2E_PROFILE}/docker.sock"
  readonly E2E_DOCKER_HOST="unix://${E2E_SOCK}"
  _LIVE_GUARD_LOADED=1
fi

# --- minimal self-contained logger (namespaced so it never clobbers a caller) --
_live_guard_msg() { printf '[live-guard] %s\n' "$*" >&2; }

# --- the guard (Property 1) ----------------------------------------------------
# guard <profile>: return 0 iff <profile> is EXACTLY the allowed profile, else
# print a SAFETY message and return 1. Pure + read-only; no side effects.
guard() {
  local target="${1:-}"
  if [ "$target" != "$E2E_PROFILE" ]; then
    _live_guard_msg "SAFETY: refusing live action against profile '${target}' (only '${E2E_PROFILE}' is allowed)"
    return 1
  fi
  return 0
}

# --- the ONLY sanctioned colima mutator ----------------------------------------
# colima_e2e <subcommand> [args...]: asserts the guard and hard-injects
# --profile desktop-e2e. Rejects any caller-supplied --profile/-p so the
# injected target can never be overridden by a trailing flag.
colima_e2e() {
  guard "$E2E_PROFILE" || return 1
  if [ "$#" -eq 0 ]; then
    _live_guard_msg "colima_e2e: missing subcommand"
    return 2
  fi
  local a
  for a in "$@"; do
    case "$a" in
      --profile|--profile=*|-p|-p=*)
        _live_guard_msg "SAFETY: refusing colima call with explicit profile flag '${a}' (profile is fixed to '${E2E_PROFILE}')"
        return 1
        ;;
    esac
  done
  local sub="$1"; shift
  colima "$sub" --profile "$E2E_PROFILE" "$@"
}

# --- the ONLY sanctioned docker mutator ----------------------------------------
# docker_e2e [args...]: asserts the guard and pins DOCKER_HOST to the
# profile-scoped socket. Rejects any caller-supplied host/context flag
# (-H/--host/-c/--context) that could redirect docker to another daemon.
docker_e2e() {
  guard "$E2E_PROFILE" || return 1
  local a
  for a in "$@"; do
    case "$a" in
      -H|--host|--host=*|-c|--context|--context=*)
        _live_guard_msg "SAFETY: refusing docker call with host/context override flag '${a}' (socket is pinned to '${E2E_PROFILE}')"
        return 1
        ;;
    esac
  done
  env DOCKER_HOST="$E2E_DOCKER_HOST" docker "$@"
}

# --- harness choke-point launcher ----------------------------------------------
# _live_guard_exec [--] <cmd> [args...]: guard, export the locked safe env, then
# exec the command. This is how a harness that shells out is forced through the
# invariant — there is no profile argument, so it can only ever run desktop-e2e.
_live_guard_exec() {
  guard "$E2E_PROFILE" || return 1
  [ "${1:-}" = "--" ] && shift
  if [ "$#" -eq 0 ]; then
    _live_guard_msg "exec: no command given (usage: guard.sh exec -- <cmd> [args...])"
    return 2
  fi
  export E2E_PROFILE
  export DOCKER_HOST="$E2E_DOCKER_HOST"
  export TEST_RUNNER_COLIMA_DESKTOP_REAL_E2E=1
  export TEST_RUNNER_COLIMA_DESKTOP_TEST_PROFILE="$E2E_PROFILE"
  exec "$@"
}

# --- self-test (fixed accept/reject battery; hermetic — stubs the binaries) ----
# This is the task-10.2 self-check that proves the guard on this host without
# touching the live environment. The full randomized property test (Property 1
# + Property 2, >=100 iterations) is task 10.3.
_live_guard_selftest() {
  local pass=0 fail=0
  _st_ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
  _st_fail() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

  printf '[live-guard selftest] allowed profile = %s\n' "$E2E_PROFILE"

  # 1) accepts the one allowed profile
  if guard "$E2E_PROFILE" 2>/dev/null; then
    _st_ok "guard accepts '${E2E_PROFILE}'"
  else
    _st_fail "guard should accept '${E2E_PROFILE}'"
  fi

  # 2) rejects everything else (empty, default, case/whitespace/prefix variants,
  #    path-traversal, globs) — none of these must ever pass.
  local bad
  for bad in \
      "default" "" " " "Default" "DESKTOP-E2E" "desktop-e2e " " desktop-e2e" \
      "desktop" "desktop-e2e2" "e2e" "prod" "colima" "*" "desktop-*" \
      "../desktop-e2e" "desktop-e2e/../default" "desktop-e2e/x"; do
    if guard "$bad" 2>/dev/null; then
      _st_fail "guard should REJECT '${bad}'"
    else
      _st_ok "guard rejects '${bad}'"
    fi
  done

  # 2b) a rejection emits a SAFETY message on stderr
  if guard "default" 2>&1 >/dev/null | grep -q "SAFETY"; then
    _st_ok "rejection prints a SAFETY message"
  else
    _st_fail "rejection should print a SAFETY message"
  fi

  # 3) the locked constant + socket are the expected values
  if [ "$E2E_PROFILE" = "desktop-e2e" ]; then
    _st_ok "E2E_PROFILE is locked to desktop-e2e"
  else
    _st_fail "E2E_PROFILE is wrong: '${E2E_PROFILE}'"
  fi
  case "$E2E_SOCK" in
    */.colima/desktop-e2e/docker.sock) _st_ok "socket path is profile-scoped" ;;
    *) _st_fail "socket path unexpected: '${E2E_SOCK}'" ;;
  esac

  # 4) colima_e2e / docker_e2e routing + override rejection.
  #    HERMETIC: shadow the real binaries with fakes on PATH so nothing can
  #    mutate the live env even if a rejection check regressed. A recorded line
  #    in $stubfile means the wrapper CALLED the binary; an empty file means it
  #    rejected BEFORE calling. PATH shadowing (not shell functions) is used so
  #    the real `colima ...` and `env DOCKER_HOST=... docker` code paths run.
  local fakebin stubfile _oldpath
  fakebin="$(mktemp -d "${TMPDIR:-/tmp}/live-guard-bin.XXXXXX")"
  stubfile="$(mktemp "${TMPDIR:-/tmp}/live-guard-stub.XXXXXX")"
  cat > "${fakebin}/colima" <<EOF
#!/usr/bin/env bash
printf 'colima %s\n' "\$*" >> "${stubfile}"
exit 0
EOF
  cat > "${fakebin}/docker" <<EOF
#!/usr/bin/env bash
printf 'docker DOCKER_HOST=%s -- %s\n' "\${DOCKER_HOST:-<unset>}" "\$*" >> "${stubfile}"
exit 0
EOF
  chmod +x "${fakebin}/colima" "${fakebin}/docker"
  _oldpath="$PATH"
  PATH="${fakebin}:${PATH}"

  : > "$stubfile"
  if colima_e2e start --cpu 2 >/dev/null 2>&1 && grep -q -- "--profile desktop-e2e" "$stubfile"; then
    _st_ok "colima_e2e injects --profile desktop-e2e"
  else
    _st_fail "colima_e2e should inject --profile desktop-e2e"
  fi

  : > "$stubfile"
  if colima_e2e start --profile default >/dev/null 2>&1; then
    _st_fail "colima_e2e should REJECT a caller --profile"
  elif [ -s "$stubfile" ]; then
    _st_fail "colima_e2e must NOT call colima when rejecting --profile"
  else
    _st_ok "colima_e2e rejects caller --profile (colima never called)"
  fi

  : > "$stubfile"
  if colima_e2e start -p default >/dev/null 2>&1; then
    _st_fail "colima_e2e should REJECT a caller -p"
  elif [ -s "$stubfile" ]; then
    _st_fail "colima_e2e must NOT call colima when rejecting -p"
  else
    _st_ok "colima_e2e rejects caller -p (colima never called)"
  fi

  : > "$stubfile"
  if docker_e2e info >/dev/null 2>&1 && grep -q "DOCKER_HOST=${E2E_DOCKER_HOST}" "$stubfile"; then
    _st_ok "docker_e2e pins DOCKER_HOST to the profile socket"
  else
    _st_fail "docker_e2e should pin DOCKER_HOST=${E2E_DOCKER_HOST}"
  fi

  : > "$stubfile"
  if docker_e2e -H tcp://evil:2375 ps >/dev/null 2>&1; then
    _st_fail "docker_e2e should REJECT an -H override"
  elif [ -s "$stubfile" ]; then
    _st_fail "docker_e2e must NOT call docker when rejecting -H"
  else
    _st_ok "docker_e2e rejects -H override (docker never called)"
  fi

  : > "$stubfile"
  if docker_e2e --context evil ps >/dev/null 2>&1; then
    _st_fail "docker_e2e should REJECT a --context override"
  elif [ -s "$stubfile" ]; then
    _st_fail "docker_e2e must NOT call docker when rejecting --context"
  else
    _st_ok "docker_e2e rejects --context override (docker never called)"
  fi

  PATH="$_oldpath"
  rm -rf "$fakebin"
  rm -f "$stubfile"

  # 5) the constant cannot be overridden by the environment (subprocess checks
  #    against the fail-closed loader at the top of this file). `env` is used to
  #    set the child's environment because E2E_PROFILE is readonly in this shell.
  local self="${BASH_SOURCE[0]}"
  if env E2E_PROFILE=desktop-e2e bash "$self" profile >/dev/null 2>&1; then
    _st_ok "env E2E_PROFILE=desktop-e2e is accepted (matches the lock)"
  else
    _st_fail "env E2E_PROFILE=desktop-e2e should be accepted"
  fi
  if env E2E_PROFILE=default bash "$self" profile >/dev/null 2>&1; then
    _st_fail "env E2E_PROFILE=default MUST be refused (fail-closed)"
  else
    _st_ok "env E2E_PROFILE=default is refused (fail-closed)"
  fi

  printf '\n[live-guard selftest] passed=%d failed=%d\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

# --- CLI usage -----------------------------------------------------------------
_live_guard_usage() {
  cat >&2 <<EOF
Usage: scripts/live/guard.sh <subcommand>

  guard <profile>     Exit 0 iff <profile> == '${E2E_PROFILE:-desktop-e2e}', else reject with a SAFETY message.
  profile             Print the locked allowed profile name.
  socket              Print the profile-scoped docker socket path.
  env                 Print the locked, safe environment exports (for eval/inspection).
  exec -- <cmd...>    Guard, export the locked safe env, then exec <cmd> (harness choke-point).
  selftest            Run the fixed accept/reject battery (proves the invariant on this host).

This file is the single source of truth for the desktop-e2e safety invariant.
It NEVER starts/stops/deletes/reshapes any profile; it only decides "allowed?"
and pins the target. The disposable lifecycle lives in scripts/live/e2e-env.sh.
EOF
}

# --- CLI dispatch --------------------------------------------------------------
_live_guard_main() {
  local sub="${1:-}"
  [ "$#" -gt 0 ] && shift || true
  case "$sub" in
    guard)    guard "${1:-}" ;;
    profile)  printf '%s\n' "$E2E_PROFILE" ;;
    socket)   printf '%s\n' "$E2E_SOCK" ;;
    env)
      printf 'export E2E_PROFILE=%s\n' "$E2E_PROFILE"
      printf 'export DOCKER_HOST=%s\n' "$E2E_DOCKER_HOST"
      printf 'export TEST_RUNNER_COLIMA_DESKTOP_REAL_E2E=1\n'
      printf 'export TEST_RUNNER_COLIMA_DESKTOP_TEST_PROFILE=%s\n' "$E2E_PROFILE"
      ;;
    exec)     _live_guard_exec "$@" ;;
    selftest) _live_guard_selftest ;;
    ""|-h|--help|help)
      _live_guard_usage
      [ -z "$sub" ] && return 2 || return 0
      ;;
    *)
      _live_guard_msg "unknown subcommand: ${sub}"
      _live_guard_usage
      return 2
      ;;
  esac
}

# Run the CLI only when executed directly; stay silent (just define) when sourced.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  _live_guard_main "$@"
  exit $?
fi
: # sourced: ensure a clean (0) return status from `source`/`.`
