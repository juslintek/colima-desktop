#!/usr/bin/env bash
# scripts/live/guard_property_test.sh — PROPERTY-BASED tests for the live-env
# profile safety guard and the disposable-profile teardown lifecycle.
#
#   Feature: cross-platform-live-verification, Property 1  (profile safety guard)
#   Feature: cross-platform-live-verification, Property 2  (teardown safety + idempotency)
#   Requirements: 8.2, 8.4, 8.5
#
# WHAT THIS PROVES
#   Property 1 (guard totality + mutator override rejection):
#     * For ANY generated profile name, `guard <name>` (scripts/live/guard.sh)
#       succeeds IFF the name is EXACTLY "desktop-e2e"; every other value
#       (empty, whitespace, case variants, prefixes/suffixes, path-traversal,
#       globs, homoglyph/unicode look-alikes, random noise) is REJECTED with a
#       SAFETY message and NO side effect (never issues a colima/docker call).
#     * `colima_e2e` rejects any caller-supplied --profile/-p, and when clean
#       injects --profile desktop-e2e; `docker_e2e` rejects any caller-supplied
#       -H/--host/-c/--context, and when clean pins DOCKER_HOST to the
#       desktop-e2e socket. A rejected mutator NEVER calls the real binary.
#
#   Property 2 (teardown safety + idempotency), proven HERMETICALLY:
#     * scripts/live/e2e-env.sh `teardown`/`down` only ever target the
#       "desktop-e2e" profile (every mutating `colima` call carries
#       `--profile desktop-e2e`; every `docker` call is pinned to the
#       desktop-e2e socket; no other profile/host is ever referenced).
#     * teardown would call `colima ... --profile desktop-e2e delete --force`;
#       down would call `colima ... --profile desktop-e2e stop`.
#     * both are idempotent no-ops when the profile is already absent/stopped.
#     * teardown removes exactly the `e2e-`-prefixed docker resources and, even
#       when resource cleanup FAILS (post-failure teardown), still deletes the
#       profile — so no `e2e-` resource / profile is left referenced.
#
#   *** SAFETY: this test NEVER runs a real teardown of the running profile. ***
#   Property 2 drives e2e-env.sh inside an ISOLATED fake $HOME (so the socket
#   path is fake, never ~/.colima/desktop-e2e/docker.sock) with PATH-shadowed
#   fake `colima`/`docker` binaries that only RECORD the args they'd receive.
#   The real desktop-e2e profile is never contacted.
#
# USAGE
#   scripts/live/guard_property_test.sh                 # run all properties
#   PBT_ITERS=200 PBT_SEED=42 scripts/live/guard_property_test.sh
#
# Deterministic: same PBT_SEED => same generated inputs (a self-contained LCG,
# not $RANDOM, so it is reproducible across hosts/bash builds).
# macOS bash 3.2 compatible. Exits non-zero if any property fails.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD_SH="${HERE}/guard.sh"
E2E_ENV_SH="${HERE}/e2e-env.sh"
ALLOWED="desktop-e2e"

ITERS="${PBT_ITERS:-150}"        # per-facet iterations (>= 100 required)
SEED="${PBT_SEED:-1337}"
SUMMARY="${PBT_SUMMARY:-${TMPDIR:-/tmp}/guard_pbt_summary.txt}"

# --- sanity: the units under test must exist ----------------------------------
[ -f "$GUARD_SH" ]   || { echo "FATAL: missing $GUARD_SH" >&2; exit 2; }
[ -f "$E2E_ENV_SH" ] || { echo "FATAL: missing $E2E_ENV_SH" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 required (fake AF_UNIX socket)" >&2; exit 2; }

# --- isolated scratch (short base so AF_UNIX sun_path stays < 104 bytes) -------
WORK="$(mktemp -d /tmp/gpbt.XXXXXX)"
FAKEBIN="${WORK}/bin"
mkdir -p "$FAKEBIN"
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# --- PATH-shadowed recording fakes --------------------------------------------
# fake `colima`: records argv to $LIVE_GUARD_STUB; emulates profile state via a
# state file so idempotency across invocations can be proven; `list` prints JSON
# derived from that state; delete/stop/start mutate it. Exits $FAKE_COLIMA_RC.
cat > "${FAKEBIN}/colima" <<'FAKE_COLIMA'
#!/usr/bin/env bash
stub="${LIVE_GUARD_STUB:-/dev/null}"
statef="${FAKE_COLIMA_STATE_FILE:-}"
printf 'colima %s\n' "$*" >> "$stub"
sub="${1:-}"
st="absent"
if [ -n "$statef" ] && [ -f "$statef" ]; then st="$(cat "$statef" 2>/dev/null)"; fi
case "$sub" in
  list)
    case "$st" in
      running) printf '[{"name":"desktop-e2e","status":"Running"}]\n' ;;
      stopped) printf '[{"name":"desktop-e2e","status":"Stopped"}]\n' ;;
      *)       printf '[]\n' ;;
    esac
    ;;
  delete)        [ -n "$statef" ] && printf 'absent'  > "$statef" ;;
  stop)          [ -n "$statef" ] && printf 'stopped' > "$statef" ;;
  start|restart) [ -n "$statef" ] && printf 'running' > "$statef" ;;
esac
exit "${FAKE_COLIMA_RC:-0}"
FAKE_COLIMA

# fake `docker`: records `DOCKER_HOST=<val> -- <argv>`; `ps -aq` prints the
# scripted id list; exits $FAKE_DOCKER_RC (to simulate cleanup failures).
cat > "${FAKEBIN}/docker" <<'FAKE_DOCKER'
#!/usr/bin/env bash
stub="${LIVE_GUARD_STUB:-/dev/null}"
printf 'docker DOCKER_HOST=%s -- %s\n' "${DOCKER_HOST:-<unset>}" "$*" >> "$stub"
case "$*" in
  *"ps -aq"*)
    if [ -n "${FAKE_DOCKER_PS_FILE:-}" ] && [ -f "$FAKE_DOCKER_PS_FILE" ]; then
      cat "$FAKE_DOCKER_PS_FILE"
    fi
    ;;
esac
exit "${FAKE_DOCKER_RC:-0}"
FAKE_DOCKER
chmod +x "${FAKEBIN}/colima" "${FAKEBIN}/docker"

# --- deterministic PRNG (glibc-style LCG; reproducible from SEED) -------------
# State lives in a FILE, not a shell variable: rng/rng_mod are used inside $( )
# command substitution, and a subshell cannot mutate a parent shell variable —
# so a variable-based LCG would be reset on every call and never advance. A
# file-backed state persists across subshells, so the sequence advances for the
# whole run and is fully reproducible from SEED.
RNG_STATE_FILE="${WORK}/rng.state"
printf '%s' "$(( SEED & 0x7fffffff ))" > "$RNG_STATE_FILE"
rng() {
  local s; s="$(cat "$RNG_STATE_FILE" 2>/dev/null)"; [ -n "$s" ] || s=1
  s=$(( (s * 1103515245 + 12345) & 0x7fffffff ))
  printf '%s' "$s" > "$RNG_STATE_FILE"
  printf '%s' "$s"
}
rng_mod() { local n="$1" r; [ "$n" -le 0 ] && { printf '0'; return; }; r="$(rng)"; printf '%s' "$(( r % n ))"; }

# --- reporting ----------------------------------------------------------------
P1_PASS=0; P1_FAIL=0; P1_ITERS=0; P1_FAILEX=""
P2_PASS=0; P2_FAIL=0; P2_ITERS=0; P2_FAILEX=""

ok1()   { P1_PASS=$((P1_PASS+1)); }
bad1()  { P1_FAIL=$((P1_FAIL+1)); [ -z "$P1_FAILEX" ] && P1_FAILEX="$1"; printf '  P1 FAIL: %s\n' "$1" >&2; }
ok2()   { P2_PASS=$((P2_PASS+1)); }
bad2()  { P2_FAIL=$((P2_FAIL+1)); [ -z "$P2_FAILEX" ] && P2_FAILEX="$1"; printf '  P2 FAIL: %s\n' "$1" >&2; }

# ==============================================================================
# PROPERTY 1 — profile safety guard totality
# Feature: cross-platform-live-verification, Property 1
# ==============================================================================

# Adversarial names that MUST all be rejected (guaranteed coverage of the
# empty/whitespace/case/prefix/suffix/path-traversal/glob/homoglyph classes).
BAD_FIXED=(
  "" " " "  " "	" "
" "default" "Default" "DEFAULT" "DESKTOP-E2E" "Desktop-E2e"
  "desktop-e2e " " desktop-e2e" "	desktop-e2e" "desktop-e2e	" "desktop-e2e
"
  "desktop" "desktop-e2" "desktop-e2e2" "desktop-e2ee" "desktopE2e" "desktop_e2e"
  "desktop.e2e" "desktop e2e" "e2e" "prod" "staging" "cdtest" "colima" "test"
  "*" "?" "desktop-*" "desktop-e2*" "?esktop-e2e" "[d]esktop-e2e" "desktop-e2[e]"
  "../desktop-e2e" "./desktop-e2e" "desktop-e2e/../default" "desktop-e2e/x"
  "/desktop-e2e" "desktop-e2e/" "~/desktop-e2e" "\$E2E_PROFILE" "desktop-e2e;rm"
  "desktop-e2e default" "desktop-e2e\ndefault" "d3sktop-e2e"
  "café" "désktop-e2e" " désktop" "🚀" "desktop-e2é" "ⅾesktop-e2e" "desktop-e2е"
  "desktop‑e2e" "ＤＥＳＫＴＯＰ" "Ｄesktop-e2e"
)

# Deterministic mutation of the allowed name (all still rejected).
mutate_allowed() {
  local base="desktop-e2e" op; op="$(rng_mod 8)"
  case "$op" in
    0) printf '%s ' "$base" ;;
    1) printf ' %s' "$base" ;;
    2) printf '%s%s' "$base" "$(rng_mod 10)" ;;
    3) printf 'DESKTOP-E2E' ;;
    4) printf '%s' "${base%-e2e}" ;;
    5) printf '%s/x' "$base" ;;
    6) printf '%s' "${base}-" ;;
    7) printf '%s	' "$base" ;;
  esac
}

# Deterministic random ASCII/byte noise (0..18 chars from a punchy charset).
rand_ascii() {
  local len s c n charset i
  charset='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_. /*?[]'
  n=${#charset}; len="$(rng_mod 19)"; s=""; i=0
  while [ "$i" -lt "$len" ]; do
    c="$(rng_mod "$n")"; s="${s}${charset:$c:1}"; i=$((i+1))
  done
  printf '%s' "$s"
}

gen_name() {  # $1 = category selector
  case "$1" in
    ascii) rand_ascii ;;
    mut)   mutate_allowed ;;
    good)  printf '%s' "$ALLOWED" ;;
  esac
}

P1A_STUB="${WORK}/p1a.stub"

run_guard() {  # $1=name -> sets G_RC, G_ERR; asserts no side effect via empty stub
  : > "$P1A_STUB"
  G_ERR="$(LIVE_GUARD_STUB="$P1A_STUB" PATH="${FAKEBIN}:$PATH" \
            bash "$GUARD_SH" guard "$1" 2>&1 >/dev/null)"
  G_RC=$?
}

printf '== Property 1: profile safety guard totality ==\n'
printf 'Feature: cross-platform-live-verification, Property 1\n'

# --- P1a: guard(name) accepts iff name == desktop-e2e; else rejects + SAFETY ---
i=0
while [ "$i" -lt "${#BAD_FIXED[@]}" ] || [ "$i" -lt "$ITERS" ]; do
  if [ "$i" -lt "${#BAD_FIXED[@]}" ]; then
    name="${BAD_FIXED[$i]}"; cat="fixed"
  else
    sel="$(rng_mod 10)"
    case "$sel" in
      0|1|2|3) name="$(gen_name ascii)"; cat="ascii" ;;
      4|5|6)   name="$(gen_name mut)";   cat="mut" ;;
      7)       name="$(gen_name good)";  cat="good" ;;
      *)       name="${BAD_FIXED[$(rng_mod ${#BAD_FIXED[@]})]}"; cat="fixed2" ;;
    esac
  fi

  if [ "$name" = "$ALLOWED" ]; then exp=0; else exp=1; fi
  run_guard "$name"
  P1_ITERS=$((P1_ITERS+1))

  fail=""
  if [ "$exp" -eq 0 ]; then
    [ "$G_RC" -eq 0 ] || fail="accept-expected"
  else
    [ "$G_RC" -ne 0 ] || fail="reject-expected"
    case "$G_ERR" in *SAFETY*) : ;; *) fail="${fail:+$fail,}no-SAFETY-msg" ;; esac
  fi
  # guard must NEVER touch colima/docker (stub must be empty either way)
  [ -s "$P1A_STUB" ] && fail="${fail:+$fail,}side-effect"

  if [ -z "$fail" ]; then ok1; else
    bad1 "guard cat=$cat name=[$(printf '%q' "$name")] exp_rc=$exp got_rc=$G_RC err=[$G_ERR] ($fail)"
  fi
  i=$((i+1))
done

# --- P1b: colima_e2e / docker_e2e reject caller flag overrides, else pin -------
P1B_STUB="${WORK}/p1b.stub"

call_mutator() {  # $1=fn ("colima_e2e"|"docker_e2e"); rest=args -> prints "rc=.. called=.."
  local fn="$1"; shift
  GUARD_SH="$GUARD_SH" LIVE_GUARD_STUB="$P1B_STUB" FN="$fn" PATH="${FAKEBIN}:$PATH" \
    bash --noprofile --norc -c '
      : > "$LIVE_GUARD_STUB"
      . "$GUARD_SH" >/dev/null 2>&1 || { echo "rc=99 called=0"; exit 0; }
      "$FN" "$@" >/dev/null 2>&1
      rc=$?
      if [ -s "$LIVE_GUARD_STUB" ]; then c=1; else c=0; fi
      printf "rc=%s called=%s\n" "$rc" "$c"
    ' _ "$@"
}

COLIMA_OVERRIDES=( "--profile" "--profile=x" "-p" "-p=x" )
DOCKER_OVERRIDES=( "-H" "--host" "--host=tcp://evil:2375" "-c" "--context" "--context=evil" )
# For the OVERRIDE (reject) case any subcommand is fine: guard.sh rejects the
# override BEFORE colima is ever invoked, so even mutating subs never run.
COLIMA_SUBS=( start stop delete restart status update prune )
# For the CLEAN (accept) case the sub DOES reach the binary, so restrict it to
# READ-ONLY subcommands: even in the (never-observed) event of a PATH-shadow
# miss, a real `colima status/version/list` cannot mutate the live profile.
COLIMA_CLEAN=( status version list )
DOCKER_CLEAN=( info ps version images )

i=0
while [ "$i" -lt "$ITERS" ]; do
  which="$(rng_mod 2)"      # 0=colima, 1=docker
  mode="$(rng_mod 3)"       # 0,1 = override (reject) ; 2 = clean (accept)
  P1_ITERS=$((P1_ITERS+1))
  res=""; rc=""; called=""; fail=""; desc=""

  if [ "$which" -eq 0 ]; then
    sub="${COLIMA_SUBS[$(rng_mod ${#COLIMA_SUBS[@]})]}"
    if [ "$mode" -le 1 ]; then
      ov="${COLIMA_OVERRIDES[$(rng_mod ${#COLIMA_OVERRIDES[@]})]}"
      # interleave the override with benign args in a random spot
      if [ "$(rng_mod 2)" -eq 0 ]; then
        res="$(call_mutator colima_e2e "$sub" "$ov" default)"
      else
        res="$(call_mutator colima_e2e "$sub" --cpu 2 "$ov" default)"
      fi
      desc="colima_e2e $sub .. $ov default (override->reject)"
      rc="${res%% *}"; rc="${rc#rc=}"; called="${res##* }"; called="${called#called=}"
      { [ "$rc" != "0" ] && [ "$called" = "0" ]; } || fail="override-not-rejected"
    else
      rosub="${COLIMA_CLEAN[$(rng_mod ${#COLIMA_CLEAN[@]})]}"
      res="$(call_mutator colima_e2e "$rosub")"
      desc="colima_e2e $rosub (clean->inject --profile desktop-e2e)"
      rc="${res%% *}"; rc="${rc#rc=}"; called="${res##* }"; called="${called#called=}"
      { [ "$rc" = "0" ] && [ "$called" = "1" ]; } || fail="clean-not-accepted"
      if [ -z "$fail" ]; then
        grep -q -- "--profile ${ALLOWED}" "$P1B_STUB" || fail="profile-not-injected"
        grep -Eq -- '--profile (default|staging|cdtest|colima|test)' "$P1B_STUB" && fail="${fail:+$fail,}wrong-profile"
      fi
    fi
  else
    if [ "$mode" -le 1 ]; then
      ov="${DOCKER_OVERRIDES[$(rng_mod ${#DOCKER_OVERRIDES[@]})]}"
      if [ "$(rng_mod 2)" -eq 0 ]; then
        res="$(call_mutator docker_e2e "$ov" evilval ps)"
      else
        res="$(call_mutator docker_e2e ps "$ov" evilval)"
      fi
      desc="docker_e2e .. $ov evilval (override->reject)"
      rc="${res%% *}"; rc="${rc#rc=}"; called="${res##* }"; called="${called#called=}"
      { [ "$rc" != "0" ] && [ "$called" = "0" ]; } || fail="override-not-rejected"
    else
      sub="${DOCKER_CLEAN[$(rng_mod ${#DOCKER_CLEAN[@]})]}"
      res="$(call_mutator docker_e2e "$sub")"
      desc="docker_e2e $sub (clean->pin DOCKER_HOST)"
      rc="${res%% *}"; rc="${rc#rc=}"; called="${res##* }"; called="${called#called=}"
      { [ "$rc" = "0" ] && [ "$called" = "1" ]; } || fail="clean-not-accepted"
      if [ -z "$fail" ]; then
        grep -q -- "DOCKER_HOST=unix://.*/${ALLOWED}/docker.sock" "$P1B_STUB" || fail="host-not-pinned"
      fi
    fi
  fi

  if [ -z "$fail" ]; then ok1; else bad1 "$desc res=[$res] ($fail)"; fi
  i=$((i+1))
done

# ==============================================================================
# PROPERTY 2 — teardown safety + idempotency (HERMETIC — never the live profile)
# Feature: cross-platform-live-verification, Property 2
# ==============================================================================

printf '== Property 2: teardown safety + idempotency (hermetic) ==\n'
printf 'Feature: cross-platform-live-verification, Property 2\n'

H2_N=0
# Run e2e-env.sh <cmd> inside an isolated fake $HOME with the recording fakes.
# Sets: H2_STUB (recorded argv), H2_HOME. Optionally reuses a caller home/state.
h2_run() {  # $1=cmd $2=state $3=mksock(yes|no) $4=psids(space sep) $5=docker_rc [$6=reuse_home]
  local cmd="$1" state="$2" mksock="$3" psids="$4" drc="$5" reuse="${6:-}"
  local home stub statef psf
  if [ -n "$reuse" ]; then
    home="$reuse"
  else
    H2_N=$((H2_N+1)); home="${WORK}/h.${H2_N}"
    mkdir -p "${home}/.colima/${ALLOWED}"
    printf '%s' "$state" > "${home}/state"
  fi
  stub="${home}/stub.log"; : > "$stub"
  statef="${home}/state"
  psf="${home}/ps"; printf '%s\n' $psids > "$psf"
  if [ "$mksock" = "yes" ] && [ ! -S "${home}/.colima/${ALLOWED}/docker.sock" ]; then
    python3 -c 'import socket,sys
s=socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])' "${home}/.colima/${ALLOWED}/docker.sock" 2>/dev/null || true
  fi
  HOME="$home" PATH="${FAKEBIN}:$PATH" \
    LIVE_GUARD_STUB="$stub" FAKE_COLIMA_STATE_FILE="$statef" \
    FAKE_DOCKER_PS_FILE="$psf" FAKE_DOCKER_RC="$drc" \
    LIVE_EVIDENCE_DIR="${home}/art" \
    bash "$E2E_ENV_SH" "$cmd" >/dev/null 2>&1
  H2_STUB="$stub"; H2_HOME="$home"
}

# Shared safety invariant over a recorded stub: every colima --profile value is
# desktop-e2e, no foreign profile token, every docker call pinned to the
# desktop-e2e socket with no host/context override.
check_targeting() {  # $1=stub -> prints "" if ok, else a reason token
  local stub="$1" n_prof n_ok d_all d_ok
  # every mutating `colima --profile <x>` must have <x> == desktop-e2e
  n_prof="$(grep '^colima ' "$stub" 2>/dev/null | grep -c -- '--profile')"
  n_ok="$(grep '^colima ' "$stub" 2>/dev/null | grep -c -- "--profile ${ALLOWED}")"
  case "$n_prof" in ''|*[!0-9]*) n_prof=0 ;; esac
  case "$n_ok"   in ''|*[!0-9]*) n_ok=0   ;; esac
  [ "$n_prof" = "$n_ok" ] || { printf 'colima-profile-mismatch(%s!=%s)' "$n_prof" "$n_ok"; return; }
  grep '^colima ' "$stub" 2>/dev/null | grep -Eq -- '(^| )-p( |$)' && { printf 'colima-short-p'; return; }
  grep '^colima ' "$stub" 2>/dev/null | grep -Eq -- '(default|staging|cdtest)' && { printf 'foreign-profile-token'; return; }
  # every docker call must be pinned to the desktop-e2e socket, no host/context override
  d_all="$(grep -c '^docker ' "$stub" 2>/dev/null)"
  d_ok="$(grep '^docker ' "$stub" 2>/dev/null | grep -c "DOCKER_HOST=unix://.*/${ALLOWED}/docker.sock")"
  case "$d_all" in ''|*[!0-9]*) d_all=0 ;; esac
  case "$d_ok"  in ''|*[!0-9]*) d_ok=0  ;; esac
  [ "$d_all" = "$d_ok" ] || { printf 'docker-not-pinned(%s/%s)' "$d_ok" "$d_all"; return; }
  grep '^docker ' "$stub" 2>/dev/null | grep -Eq -- '(^| )(-H|--host|-c|--context)( |=)' && { printf 'docker-override'; return; }
  printf ''
}

count_lines() {  # robust single-integer count of matching lines (0 if none/missing).
  # NB: `grep -c` prints 0 AND exits 1 on no match, so a `|| printf 0` fallback
  # would double-print — capture into a var and normalise instead.
  local c; c="$(grep -c -- "$1" "$2" 2>/dev/null)"
  case "$c" in ''|*[!0-9]*) c=0 ;; esac
  printf '%s' "$c"
}

STATES=( running stopped absent )

i=0
while [ "$i" -lt "$ITERS" ]; do
  P2_ITERS=$((P2_ITERS+1))
  if [ "$(rng_mod 2)" -eq 0 ]; then cmd="teardown"; else cmd="down"; fi
  state="${STATES[$(rng_mod 3)]}"
  if [ "$(rng_mod 2)" -eq 0 ]; then mksock="yes"; else mksock="no"; fi
  drc=0; [ "$(rng_mod 4)" -eq 0 ] && drc=1
  nids="$(rng_mod 4)"; ids=""; j=0
  while [ "$j" -lt "$nids" ]; do ids="${ids} e2e-$(rng)"; j=$((j+1)); done
  ids="${ids# }"

  h2_run "$cmd" "$state" "$mksock" "$ids" "$drc"
  fail=""

  # (a) targeting invariant — only ever desktop-e2e
  t="$(check_targeting "$H2_STUB")"; [ -n "$t" ] && fail="target:$t"

  # (b) command/state oracle
  n_del="$(count_lines 'colima delete --profile '"$ALLOWED"' --force' "$H2_STUB")"
  n_stop="$(count_lines 'colima stop --profile '"$ALLOWED" "$H2_STUB")"
  if [ "$cmd" = "teardown" ]; then
    case "$state" in
      running|stopped) [ "$n_del" -ge 1 ] || fail="${fail:+$fail,}no-delete";;
      absent)          [ "$n_del" -eq 0 ] || fail="${fail:+$fail,}delete-when-absent";;
    esac
    [ "$n_stop" -eq 0 ] || fail="${fail:+$fail,}unexpected-stop"
    # docker cleanup only when the profile socket is present
    if [ "$mksock" = "yes" ]; then
      [ "$(count_lines 'network prune' "$H2_STUB")" -ge 1 ] || fail="${fail:+$fail,}no-net-prune"
      [ "$(count_lines 'volume  *prune' "$H2_STUB")" -ge 1 ] || fail="${fail:+$fail,}no-vol-prune"
      if [ -n "$ids" ]; then
        [ "$(count_lines 'rm -f' "$H2_STUB")" -ge 1 ] || fail="${fail:+$fail,}no-rm"
      fi
    else
      [ "$(count_lines '^docker ' "$H2_STUB")" -eq 0 ] || fail="${fail:+$fail,}docker-without-socket"
    fi
  else  # down
    case "$state" in
      running) [ "$n_stop" -ge 1 ] || fail="${fail:+$fail,}no-stop";;
      *)       [ "$n_stop" -eq 0 ] || fail="${fail:+$fail,}stop-when-not-running";;
    esac
    [ "$n_del" -eq 0 ] || fail="${fail:+$fail,}unexpected-delete"
    # down never runs docker resource cleanup
    [ "$(count_lines '^docker ' "$H2_STUB")" -eq 0 ] || fail="${fail:+$fail,}down-touched-docker"
  fi

  if [ -z "$fail" ]; then ok2; else
    bad2 "cmd=$cmd state=$state sock=$mksock drc=$drc ids=[$ids] n_del=$n_del n_stop=$n_stop ($fail)"
  fi
  i=$((i+1))
done

# --- P2 deterministic anchors: stateful idempotency + post-failure teardown ---

# (1) teardown twice in the SAME home: first deletes, second is a no-op.
h2_run teardown running yes "e2e-aaa e2e-bbb" 0
first_del="$(count_lines 'colima delete --profile '"$ALLOWED"' --force' "$H2_STUB")"
reuse_home="$H2_HOME"
h2_run teardown running yes "" 0 "$reuse_home"   # state file is now 'absent' after first delete
second_del="$(count_lines 'colima delete --profile '"$ALLOWED"' --force' "$H2_STUB")"
P2_ITERS=$((P2_ITERS+1))
if [ "$first_del" -ge 1 ] && [ "$second_del" -eq 0 ] && [ -z "$(check_targeting "$H2_STUB")" ]; then
  ok2
else
  bad2 "idempotency teardown-twice first_del=$first_del second_del=$second_del (want >=1 then 0)"
fi

# (2) down twice in the SAME home: first stops, second is a no-op.
h2_run down running no "" 0
first_stop="$(count_lines 'colima stop --profile '"$ALLOWED" "$H2_STUB")"
reuse_home="$H2_HOME"
h2_run down running no "" 0 "$reuse_home"        # state file is now 'stopped' after first stop
second_stop="$(count_lines 'colima stop --profile '"$ALLOWED" "$H2_STUB")"
P2_ITERS=$((P2_ITERS+1))
if [ "$first_stop" -ge 1 ] && [ "$second_stop" -eq 0 ]; then ok2; else
  bad2 "idempotency down-twice first_stop=$first_stop second_stop=$second_stop (want >=1 then 0)"
fi

# (3) post-failure teardown: docker cleanup FAILS (rc=1) but the profile is
#     still deleted, so nothing is left referenced.
h2_run teardown running yes "e2e-x e2e-y e2e-z" 1
P2_ITERS=$((P2_ITERS+1))
pf_del="$(count_lines 'colima delete --profile '"$ALLOWED"' --force' "$H2_STUB")"
pf_rm="$(count_lines 'rm -f' "$H2_STUB")"
if [ "$pf_del" -ge 1 ] && [ "$pf_rm" -ge 1 ] && [ -z "$(check_targeting "$H2_STUB")" ]; then
  ok2
else
  bad2 "post-failure teardown pf_del=$pf_del pf_rm=$pf_rm (want delete>=1 & rm attempted despite docker rc=1)"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================
P1_TOTAL=$((P1_PASS+P1_FAIL))
P2_TOTAL=$((P2_PASS+P2_FAIL))
{
  printf 'guard/teardown property tests — seed=%s iters/facet=%s\n' "$SEED" "$ITERS"
  printf 'Property 1 (profile safety guard):      %s/%s passed (%s iterations)\n' "$P1_PASS" "$P1_TOTAL" "$P1_ITERS"
  printf 'Property 2 (teardown safety+idempotent): %s/%s passed (%s iterations)\n' "$P2_PASS" "$P2_TOTAL" "$P2_ITERS"
  [ -n "$P1_FAILEX" ] && printf 'Property 1 first failing example: %s\n' "$P1_FAILEX"
  [ -n "$P2_FAILEX" ] && printf 'Property 2 first failing example: %s\n' "$P2_FAILEX"
} | tee "$SUMMARY"

printf '\n'
if [ "$P1_FAIL" -eq 0 ] && [ "$P2_FAIL" -eq 0 ] && [ "$P1_ITERS" -ge 100 ] && [ "$P2_ITERS" -ge 100 ]; then
  printf 'RESULT: PASS (Property 1: %s iters, Property 2: %s iters — both >= 100, 0 failures)\n' "$P1_ITERS" "$P2_ITERS"
  exit 0
fi
printf 'RESULT: FAIL (P1 fails=%s iters=%s ; P2 fails=%s iters=%s)\n' "$P1_FAIL" "$P1_ITERS" "$P2_FAIL" "$P2_ITERS"
exit 1
