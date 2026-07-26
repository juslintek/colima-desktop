#!/usr/bin/env bash
# merge-gate.sh — conflict-free integration gate for Colima Desktop.
#
# The Integration_Agent is the ONLY writer to `main`. Before it integrates a
# path-owner's branch it runs three composable checks, in this order:
#
#   1. ownership  — the branch's diff touches ONLY paths under the owned prefix
#                   (any out-of-lane path is rejected).                [Property 3]
#   2. reserved   — reserved paths (.kiro/board/**, proto/colima_ui.proto,
#                   README*, docs/parity-matrix.md, docs/truth-table.csv) are
#                   not touched by a non-owner; proto changes are accepted only
#                   from an architect-approved contract-integration actor. [Property 5 support]
#   3. green      — scripts/verify.sh is GREEN for the touched platform AND no
#                   other platform's STATUS.md scoreboard value regresses. [Property 4]
#
# `gate` composes the three (ownership -> reserved -> green) and integrates to
# `main` only when all pass; otherwise it prints a specific rejection reason and
# exits nonzero. Integration is opt-in via `--merge` (default: dry-run) so the
# gate is safe to run in CI and in tests without mutating history.
#
# Every check is also exposed as a standalone subcommand with injectable inputs
# (file lists, verify result, STATUS snapshots) so the behavior is deterministic
# and property-testable (see task 1.10). Requirements: 2.6, 2.7, 2.8.
#
# POSIX-bash compatible for macOS (bash 3.2): no associative arrays, no mapfile,
# no globstar, no ${var,,} expansion.
set -uo pipefail

# ---------------------------------------------------------------------------
# Exit codes (stable, documented in --help)
# ---------------------------------------------------------------------------
readonly EX_OK=0            # all checks passed
readonly EX_USAGE=1         # bad arguments / usage error
readonly EX_OWNERSHIP=2     # out-of-lane write (ownership rejection)
readonly EX_RESERVED=3      # reserved path touched by a non-owner
readonly EX_GREEN=4         # verify not green, or a scoreboard regression
readonly EX_DISJOINT=5      # two owned prefixes overlap
readonly EX_MERGE=6         # integration (git harvest/commit) failed

PROG="$(basename "$0")"
ROOT="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd || pwd)"

# Reserved paths (design "Reserved-to-orchestrator paths").
readonly VERIFY_SCRIPT="scripts/verify.sh"
readonly STATUS_FILE=".kiro/board/STATUS.md"

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
err()  { printf '%s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

lc() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }

# normalize_prefix <prefix> — strip a trailing /**, /* or / so a directory
# prefix like "scripts/**" becomes "scripts". Exact-file prefixes (e.g.
# ".kiro/board/STATUS.md") are returned unchanged.
normalize_prefix() {
  local x="${1:-}"
  x="${x%/\*\*}"   # trailing literal /**
  x="${x%/\*}"     # trailing literal /*
  x="${x%/}"       # trailing /
  printf '%s' "$x"
}

# path_under_prefix <path> <prefix> — 0 if the path is owned by the prefix.
#   * directory prefix ("scripts/**" -> "scripts"): matches "scripts" or "scripts/*"
#   * exact-file prefix (".kiro/board/STATUS.md"): matches that path exactly
#   * glob prefix ("README*"): matches as a shell glob (unquoted case pattern)
# A normalized prefix that still contains a glob metachar (* or ?) is treated as
# a glob; otherwise it is an exact/directory prefix (quoted so its literal path
# is matched, never accidentally globbed).
path_under_prefix() {
  local p="${1:-}" norm
  norm="$(normalize_prefix "${2:-}")"
  [ -n "$norm" ] || return 1
  case "$norm" in
    *"*"*|*"?"*)
      # shellcheck disable=SC2254  # intentional glob match against the prefix pattern
      case "$p" in $norm) return 0 ;; esac
      ;;
    *)
      case "$p" in "$norm"|"$norm"/*) return 0 ;; esac
      ;;
  esac
  return 1
}

# split_csv <csv> — echo comma-separated items one per line (trimmed).
# The trailing "|| [ -n "$item" ]" guard processes a final item that has no
# trailing newline (otherwise `while read` would silently drop it).
split_csv() {
  printf '%s\n' "${1:-}" | tr ',' '\n' | while IFS= read -r item || [ -n "$item" ]; do
    item="${item#"${item%%[![:space:]]*}"}"   # ltrim
    item="${item%"${item##*[![:space:]]}"}"    # rtrim
    [ -n "$item" ] && printf '%s\n' "$item"
  done
}

# read_paths_source <spec> — echo newline-separated changed paths.
#   spec "-"      -> read from stdin
#   spec FILE     -> read from FILE
# Blank lines and leading "./" are stripped.
read_paths_source() {
  local spec="${1:-}"
  if [ "$spec" = "-" ]; then
    cat
  else
    cat "$spec"
  fi | while IFS= read -r ln || [ -n "$ln" ]; do
    ln="${ln%$'\r'}"       # strip CR (Windows-authored lists)
    ln="${ln#./}"
    [ -n "$ln" ] && printf '%s\n' "$ln"
  done
}

# git_changed_paths <base> <branch> — echo the files a branch changed relative
# to its merge-base with <base> (three-dot diff).
git_changed_paths() {
  local base="${1:-}" branch="${2:-}"
  git -C "$ROOT" diff --name-only "${base}...${branch}"
}

# ---------------------------------------------------------------------------
# check-ownership : diff ⊆ owned prefix(es)                     [Property 3]
# ---------------------------------------------------------------------------
do_check_ownership() {
  local paths_file="$1"; shift
  # remaining args: one or more normalized owned prefixes
  local out_of_lane=0 p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    local in_lane=1 pre
    for pre in "$@"; do
      if path_under_prefix "$p" "$pre"; then in_lane=0; break; fi
    done
    if [ "$in_lane" -ne 0 ]; then
      err "  out-of-lane: $p"
      out_of_lane=1
    fi
  done < "$paths_file"

  if [ "$out_of_lane" -ne 0 ]; then
    err "REJECT (ownership): changeset touches paths outside owned prefix [$*]"
    return $EX_OWNERSHIP
  fi
  info "OK (ownership): all changed paths are under owned prefix [$*]"
  return $EX_OK
}

# ---------------------------------------------------------------------------
# reserved-path classification
# ---------------------------------------------------------------------------
# classify_reserved <path> — echo the reserved class or "" if not reserved.
classify_reserved() {
  local p="${1:-}"
  case "$p" in
    proto/colima_ui.proto)      printf 'proto' ;;
    docs/parity-matrix.md)      printf 'parity' ;;
    docs/truth-table.csv)       printf 'truth' ;;
    .kiro/board|.kiro/board/*)  printf 'board' ;;
    README|README.*|README*)    printf 'readme' ;;
    *)                          printf '' ;;
  esac
}

# actor_allowed_for <class> <actor> — 0 if this actor may write this reserved class.
actor_allowed_for() {
  local class="${1:-}" actor; actor="$(lc "${2:-}")"
  local allowed=""
  case "$class" in
    board)  allowed="orchestrator integration-agent integration_agent" ;;
    proto)  allowed="architect contract-integration contract_integration" ;;
    readme) allowed="architect orchestrator" ;;
    parity) allowed="architect orchestrator" ;;
    truth)  allowed="architect orchestrator" ;;
    *)      return 0 ;;   # not reserved
  esac
  local a
  for a in $allowed; do
    [ "$actor" = "$a" ] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# check-reserved : reserved paths untouched by a non-owner       [supports Property 5]
# ---------------------------------------------------------------------------
do_check_reserved() {
  local paths_file="$1" actor="${2:-}"
  local violated=0 p class
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    class="$(classify_reserved "$p")"
    [ -n "$class" ] || continue
    if ! actor_allowed_for "$class" "$actor"; then
      if [ "$class" = "proto" ]; then
        err "  reserved: $p (proto is architect single-owner; accept only from an architect-approved contract-integration pass)"
      else
        err "  reserved: $p ($class is reserved; actor '${actor:-<none>}' is not an owner)"
      fi
      violated=1
    fi
  done < "$paths_file"

  if [ "$violated" -ne 0 ]; then
    err "REJECT (reserved): a reserved path was modified by a non-owner"
    return $EX_RESERVED
  fi
  info "OK (reserved): no reserved path touched by a non-owner (actor='${actor:-<none>}')"
  return $EX_OK
}

# ---------------------------------------------------------------------------
# STATUS.md scoreboard parsing + regression detection            [Property 4]
# ---------------------------------------------------------------------------
# emit_status_triples <status.md> — print "criterion<TAB>platform<TAB>token"
# for every scoreboard cell. Token is the first word of the cell (PASS, FAIL,
# n/a, ?, scaffold, present, ...).
emit_status_triples() {
  awk -F'|' '
    /^\|/ {
      for (i = 1; i <= NF; i++) { gsub(/^[ \t\r]+/, "", $i); gsub(/[ \t\r]+$/, "", $i) }
      issep = 1
      for (i = 2; i <= NF - 1; i++) { if ($i !~ /^[-:]*$/) { issep = 0; break } }
      if (issep) next
      if (!hdr) { for (i = 3; i <= NF - 1; i++) plat[i] = $i; hdr = 1; next }
      crit = $2
      if (crit == "") next
      for (i = 3; i <= NF - 1; i++) {
        if ((i in plat) && plat[i] != "") {
          n = split($i, a, " ")
          tok = (n >= 1 && a[1] != "") ? a[1] : "?"
          print crit "\t" plat[i] "\t" tok
        }
      }
    }
  ' "$1"
}

# rank <token> — ordinal severity (higher is better) for regression comparison.
rank() {
  case "${1:-}" in
    PASS)             echo 4 ;;
    present|scaffold) echo 3 ;;
    n/a|N/A)          echo 2 ;;
    WARN|warn)        echo 1 ;;
    "?"|"")           echo 1 ;;
    FAIL)             echo 0 ;;
    *)                echo 1 ;;
  esac
}

# status_regressions <before.md> <after.md> <touched-platform> — print one line
# per regressed cell (empty output => no regression). A regression is any cell,
# on a platform OTHER than the touched one, whose rank drops from before->after.
status_regressions() {
  local before="$1" after="$2" touched; touched="$(lc "${3:-}")"
  local before_triples after_triples
  before_triples="$(mktemp "${TMPDIR:-/tmp}/mg-before.XXXXXX")"
  after_triples="$(mktemp "${TMPDIR:-/tmp}/mg-after.XXXXXX")"
  emit_status_triples "$before" > "$before_triples"
  emit_status_triples "$after"  > "$after_triples"

  local crit plat tok_after tok_before r_before r_after
  while IFS="$(printf '\t')" read -r crit plat tok_after; do
    [ -n "$plat" ] || continue
    [ "$(lc "$plat")" = "$touched" ] && continue     # touched platform may change freely
    tok_before="$(awk -F'\t' -v c="$crit" -v p="$plat" '$1==c && $2==p {print $3; exit}' "$before_triples")"
    [ -n "$tok_before" ] || continue                 # no baseline cell => not a regression
    r_before="$(rank "$tok_before")"
    r_after="$(rank "$tok_after")"
    if [ "$r_after" -lt "$r_before" ]; then
      printf '  %s / %s: %s -> %s\n' "$plat" "$crit" "$tok_before" "$tok_after"
    fi
  done < "$after_triples"

  rm -f "$before_triples" "$after_triples"
}

# verify_is_green <mode> <log-or-empty> — resolve the verify result.
#   mode "green"|"not-green"  -> injected result (tests)
#   mode "run"                -> run scripts/verify.sh live and parse RESULT line
#   mode "log"                -> parse an existing verify log ($2)
# Returns 0 if green, 1 otherwise.
verify_is_green() {
  local mode="${1:-run}" logfile="${2:-}"
  case "$mode" in
    green)     return 0 ;;
    not-green) return 1 ;;
    log)
      [ -n "$logfile" ] && [ -f "$logfile" ] || { err "  verify log not found: $logfile"; return 1; }
      grep -q "RESULT: GREEN" "$logfile"
      return $?
      ;;
    run)
      [ -x "$ROOT/$VERIFY_SCRIPT" ] || { err "  $VERIFY_SCRIPT not found/executable"; return 1; }
      local vlog; vlog="$(mktemp "${TMPDIR:-/tmp}/mg-verify.XXXXXX")"
      ( cd "$ROOT" && "./$VERIFY_SCRIPT" ) > "$vlog" 2>&1
      local ok=1
      grep -q "RESULT: GREEN" "$vlog" && ok=0
      [ "$ok" -eq 0 ] || err "  verify.sh did not report GREEN (see run output)"
      rm -f "$vlog"
      return $ok
      ;;
    *) err "  unknown verify mode: $mode"; return 1 ;;
  esac
}

# do_check_green <platform> <verify-mode> <verify-log> <status-before> <status-after>
do_check_green() {
  local platform="${1:-}" vmode="${2:-run}" vlog="${3:-}" sbefore="${4:-}" safter="${5:-}"

  if [ -z "$platform" ]; then
    err "REJECT (green): --platform is required"
    return $EX_GREEN
  fi

  if ! verify_is_green "$vmode" "$vlog"; then
    err "REJECT (green): verify.sh is not GREEN for touched platform '$platform'"
    return $EX_GREEN
  fi

  # Regression check against other platforms' scoreboard values.
  if [ -n "$sbefore" ] && [ -n "$safter" ]; then
    [ -f "$sbefore" ] || { err "REJECT (green): status-before not found: $sbefore"; return $EX_GREEN; }
    [ -f "$safter" ]  || { err "REJECT (green): status-after not found: $safter"; return $EX_GREEN; }
    local regs; regs="$(status_regressions "$sbefore" "$safter" "$platform")"
    if [ -n "$regs" ]; then
      err "REJECT (green): other-platform scoreboard regression(s) detected:"
      err "$regs"
      return $EX_GREEN
    fi
    info "OK (green): verify GREEN and no other-platform scoreboard regression"
  else
    info "OK (green): verify GREEN (scoreboard regression check skipped — no before/after snapshots)"
  fi
  return $EX_OK
}

# ---------------------------------------------------------------------------
# disjoint : pairwise owned-prefix disjointness                 [Property 5]
# ---------------------------------------------------------------------------
# prefixes_overlap <a> <b> — 0 if one normalized prefix contains the other
# (i.e. they are NOT disjoint).
prefixes_overlap() {
  local a b; a="$(normalize_prefix "${1:-}")"; b="$(normalize_prefix "${2:-}")"
  [ -n "$a" ] && [ -n "$b" ] || return 1
  [ "$a" = "$b" ] && return 0
  case "$b" in "$a"/*) return 0 ;; esac
  case "$a" in "$b"/*) return 0 ;; esac
  return 1
}

do_disjoint() {
  # args: two or more prefixes
  local -a prefixes=()
  local x
  for x in "$@"; do prefixes+=("$x"); done
  local n="${#prefixes[@]}"
  if [ "$n" -lt 2 ]; then
    err "usage: $PROG disjoint <prefixA> <prefixB> [<prefixC> ...]"
    return $EX_USAGE
  fi
  local i j overlap=0
  i=0
  while [ "$i" -lt "$n" ]; do
    j=$((i + 1))
    while [ "$j" -lt "$n" ]; do
      if prefixes_overlap "${prefixes[$i]}" "${prefixes[$j]}"; then
        err "  overlap: '${prefixes[$i]}' <> '${prefixes[$j]}'"
        overlap=1
      fi
      j=$((j + 1))
    done
    i=$((i + 1))
  done
  if [ "$overlap" -ne 0 ]; then
    err "REJECT (disjoint): owned prefixes overlap"
    return $EX_DISJOINT
  fi
  info "OK (disjoint): all $n owned prefixes are pairwise disjoint"
  return $EX_OK
}

# ---------------------------------------------------------------------------
# Argument collection helpers (bash 3.2 + set -u safe)
# ---------------------------------------------------------------------------
# Collect owned prefixes from repeated --owned-prefix flags and/or CSV values
# into the global array OWNED_PREFIXES.
OWNED_PREFIXES=()
add_owned_prefix() {
  local item
  while IFS= read -r item; do
    [ -n "$item" ] && OWNED_PREFIXES+=("$item")
  done < <(split_csv "$1")
}

# ---------------------------------------------------------------------------
# Subcommand: check-ownership
# ---------------------------------------------------------------------------
cmd_check_ownership() {
  OWNED_PREFIXES=()
  local files="" branch="" base="main"
  while [ $# -gt 0 ]; do
    case "$1" in
      --owned-prefix) add_owned_prefix "${2:-}"; shift 2 ;;
      --files)        files="${2:-}"; shift 2 ;;
      --branch)       branch="${2:-}"; shift 2 ;;
      --base)         base="${2:-}"; shift 2 ;;
      -h|--help)      usage_check_ownership; return $EX_OK ;;
      *) err "unknown arg: $1"; usage_check_ownership; return $EX_USAGE ;;
    esac
  done
  if [ "${#OWNED_PREFIXES[@]}" -eq 0 ]; then
    err "error: at least one --owned-prefix is required"; return $EX_USAGE
  fi
  local paths_file; paths_file="$(mktemp "${TMPDIR:-/tmp}/mg-paths.XXXXXX")"
  if [ -n "$files" ]; then
    read_paths_source "$files" > "$paths_file"
  elif [ -n "$branch" ]; then
    git_changed_paths "$base" "$branch" > "$paths_file" 2>/dev/null || {
      err "error: could not compute git diff ${base}...${branch}"; rm -f "$paths_file"; return $EX_USAGE; }
  else
    err "error: provide --files <file|-> or --branch <branch>"; rm -f "$paths_file"; return $EX_USAGE
  fi
  do_check_ownership "$paths_file" "${OWNED_PREFIXES[@]}"
  local rc=$?
  rm -f "$paths_file"
  return $rc
}

# ---------------------------------------------------------------------------
# Subcommand: check-reserved
# ---------------------------------------------------------------------------
cmd_check_reserved() {
  local files="" branch="" base="main" actor=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --actor)   actor="${2:-}"; shift 2 ;;
      --files)   files="${2:-}"; shift 2 ;;
      --branch)  branch="${2:-}"; shift 2 ;;
      --base)    base="${2:-}"; shift 2 ;;
      -h|--help) usage_check_reserved; return $EX_OK ;;
      *) err "unknown arg: $1"; usage_check_reserved; return $EX_USAGE ;;
    esac
  done
  local paths_file; paths_file="$(mktemp "${TMPDIR:-/tmp}/mg-paths.XXXXXX")"
  if [ -n "$files" ]; then
    read_paths_source "$files" > "$paths_file"
  elif [ -n "$branch" ]; then
    git_changed_paths "$base" "$branch" > "$paths_file" 2>/dev/null || {
      err "error: could not compute git diff ${base}...${branch}"; rm -f "$paths_file"; return $EX_USAGE; }
  else
    err "error: provide --files <file|-> or --branch <branch>"; rm -f "$paths_file"; return $EX_USAGE
  fi
  do_check_reserved "$paths_file" "$actor"
  local rc=$?
  rm -f "$paths_file"
  return $rc
}

# ---------------------------------------------------------------------------
# Subcommand: check-green
# ---------------------------------------------------------------------------
cmd_check_green() {
  local platform="" vmode="run" vlog="" sbefore="" safter=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --platform)      platform="${2:-}"; shift 2 ;;
      --verify)        vmode="${2:-}"; shift 2 ;;      # green | not-green
      --verify-log)    vmode="log"; vlog="${2:-}"; shift 2 ;;
      --status-before) sbefore="${2:-}"; shift 2 ;;
      --status-after)  safter="${2:-}"; shift 2 ;;
      -h|--help)       usage_check_green; return $EX_OK ;;
      *) err "unknown arg: $1"; usage_check_green; return $EX_USAGE ;;
    esac
  done
  do_check_green "$platform" "$vmode" "$vlog" "$sbefore" "$safter"
}

# ---------------------------------------------------------------------------
# Subcommand: disjoint
# ---------------------------------------------------------------------------
cmd_disjoint() {
  case "${1:-}" in -h|--help) usage_disjoint; return $EX_OK ;; esac
  do_disjoint "$@"
}

# ---------------------------------------------------------------------------
# Subcommand: gate  (compose ownership -> reserved -> green)
# ---------------------------------------------------------------------------
cmd_gate() {
  OWNED_PREFIXES=()
  local branch="" base="main" platform="" actor=""
  local files="" vmode="run" vlog="" sbefore="" safter="" do_merge=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch)        branch="${2:-}"; shift 2 ;;
      --base)          base="${2:-}"; shift 2 ;;
      --owned-prefix)  add_owned_prefix "${2:-}"; shift 2 ;;
      --platform)      platform="${2:-}"; shift 2 ;;
      --actor)         actor="${2:-}"; shift 2 ;;
      --files)         files="${2:-}"; shift 2 ;;
      --verify)        vmode="${2:-}"; shift 2 ;;
      --verify-log)    vmode="log"; vlog="${2:-}"; shift 2 ;;
      --status-before) sbefore="${2:-}"; shift 2 ;;
      --status-after)  safter="${2:-}"; shift 2 ;;
      --merge)         do_merge=1; shift ;;
      -h|--help)       usage_gate; return $EX_OK ;;
      *) err "unknown arg: $1"; usage_gate; return $EX_USAGE ;;
    esac
  done

  if [ "${#OWNED_PREFIXES[@]}" -eq 0 ] || [ -z "$platform" ]; then
    err "error: gate requires --owned-prefix and --platform (and --branch for live mode)"
    return $EX_USAGE
  fi

  # Resolve the changed-paths list once (shared by ownership + reserved).
  local paths_file; paths_file="$(mktemp "${TMPDIR:-/tmp}/mg-paths.XXXXXX")"
  if [ -n "$files" ]; then
    read_paths_source "$files" > "$paths_file"
  elif [ -n "$branch" ]; then
    git_changed_paths "$base" "$branch" > "$paths_file" 2>/dev/null || {
      err "error: could not compute git diff ${base}...${branch}"; rm -f "$paths_file"; return $EX_USAGE; }
  else
    err "error: provide --files <file|-> or --branch <branch>"; rm -f "$paths_file"; return $EX_USAGE
  fi

  info "== merge-gate: branch='${branch:-<files>}' platform='$platform' actor='${actor:-<none>}' =="

  # 1) ownership
  info "-- [1/3] ownership check"
  do_check_ownership "$paths_file" "${OWNED_PREFIXES[@]}"; local rc=$?
  if [ "$rc" -ne 0 ]; then rm -f "$paths_file"; err "GATE: REJECTED at ownership check."; return $rc; fi

  # 2) reserved
  info "-- [2/3] reserved-path check"
  do_check_reserved "$paths_file" "$actor"; rc=$?
  if [ "$rc" -ne 0 ]; then rm -f "$paths_file"; err "GATE: REJECTED at reserved-path check."; return $rc; fi
  rm -f "$paths_file"

  # 3) green + no-regression
  info "-- [3/3] green / no-regression check"
  do_check_green "$platform" "$vmode" "$vlog" "$sbefore" "$safter"; rc=$?
  if [ "$rc" -ne 0 ]; then err "GATE: REJECTED at green check."; return $rc; fi

  # All checks passed.
  if [ "$do_merge" -eq 1 ]; then
    if [ -z "$branch" ]; then
      err "GATE: --merge requires --branch (the source agent branch to harvest)"; return $EX_USAGE
    fi
    info "-- integrating: path-scoped harvest of [${OWNED_PREFIXES[*]}] from '$branch' into main"
    ( cd "$ROOT" && git checkout "$branch" -- "${OWNED_PREFIXES[@]}" ) || {
      err "GATE: harvest (git checkout $branch -- <prefix>) failed"; return $EX_MERGE; }
    # Defense-in-depth: nothing outside the owned prefix may be staged.
    local staged stray="" f
    staged="$(git -C "$ROOT" diff --cached --name-only)"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      local ok=1 pre
      for pre in "${OWNED_PREFIXES[@]}"; do
        if path_under_prefix "$f" "$pre"; then ok=0; break; fi
      done
      [ "$ok" -ne 0 ] && stray="$stray $f"
    done <<EOF
$staged
EOF
    if [ -n "$stray" ]; then
      err "GATE: post-harvest staged out-of-lane paths:$stray — aborting integration"
      return $EX_MERGE
    fi
    ( cd "$ROOT" && git commit -m "integrate($platform): harvest ${OWNED_PREFIXES[*]} from $branch" ) || {
      err "GATE: commit to main failed"; return $EX_MERGE; }
    info "GATE: PASS — integrated '$branch' (${OWNED_PREFIXES[*]}) into main."
  else
    info "GATE: PASS (dry-run) — all checks passed. Re-run with --merge to integrate into main."
  fi
  return $EX_OK
}

# ---------------------------------------------------------------------------
# Usage / help
# ---------------------------------------------------------------------------
usage_check_ownership() {
  cat >&2 <<EOF
usage: $PROG check-ownership --owned-prefix <p> [--owned-prefix <p2>...] (--files <file|->|--branch <b> [--base <ref>])
  Rejects (exit $EX_OWNERSHIP) if any changed path is outside the owned prefix(es).
EOF
}
usage_check_reserved() {
  cat >&2 <<EOF
usage: $PROG check-reserved [--actor <role>] (--files <file|->|--branch <b> [--base <ref>])
  Rejects (exit $EX_RESERVED) if a reserved path is touched by a non-owner.
  Reserved: .kiro/board/**, proto/colima_ui.proto, README*, docs/parity-matrix.md, docs/truth-table.csv
  proto is accepted only from actor 'architect' or 'contract-integration'.
EOF
}
usage_check_green() {
  cat >&2 <<EOF
usage: $PROG check-green --platform <macOS|Windows|Linux|TUI|Daemon>
                 [--verify green|not-green | --verify-log <file>]
                 [--status-before <STATUS.md> --status-after <STATUS.md>]
  Rejects (exit $EX_GREEN) if verify is not GREEN or another platform's scoreboard regresses.
  Default verify mode runs ./$VERIFY_SCRIPT live.
EOF
}
usage_disjoint() {
  cat >&2 <<EOF
usage: $PROG disjoint <prefixA> <prefixB> [<prefixC> ...]
  Rejects (exit $EX_DISJOINT) if any two owned prefixes overlap.
EOF
}
usage_gate() {
  cat >&2 <<EOF
usage: $PROG gate --owned-prefix <p> [--owned-prefix <p2>...] --platform <plat>
              (--branch <b> [--base <ref>] | --files <file|->) [--actor <role>]
              [--verify green|not-green | --verify-log <file>]
              [--status-before <f> --status-after <f>] [--merge]
  Composes ownership -> reserved -> green. Integrates to main only with --merge
  (default: dry-run). Prints a specific rejection reason and exits nonzero on failure.
EOF
}

usage() {
  cat <<EOF
$PROG — conflict-free integration gate (Integration_Agent merge gate).

USAGE
  $PROG <subcommand> [options]

SUBCOMMANDS
  check-ownership   diff ⊆ owned prefix(es)                 [Property 3]
  check-reserved    reserved paths untouched by a non-owner
  check-green       verify.sh GREEN + no scoreboard regress [Property 4]
  disjoint          pairwise owned-prefix disjointness      [Property 5]
  gate              compose ownership -> reserved -> green, then (opt) merge
  help              show this help

EXIT CODES
  $EX_OK  ok / all checks passed        $EX_GREEN  verify not green / scoreboard regression
  $EX_USAGE  usage error                   $EX_DISJOINT  owned prefixes overlap
  $EX_OWNERSHIP  out-of-lane write (ownership)  $EX_MERGE  integration (git) failed
  $EX_RESERVED  reserved path by non-owner

RESERVED PATHS (design "Reserved-to-orchestrator paths")
  .kiro/board/**   proto/colima_ui.proto   README*   docs/parity-matrix.md   docs/truth-table.csv

EXAMPLES
  # Reject a devops branch that strayed outside scripts/**
  $PROG check-ownership --owned-prefix 'scripts/**' --files changed.txt

  # A tui-dev branch integrating to main (dry-run), injected verify result + scoreboard snapshots
  $PROG gate --owned-prefix 'tui/**' --platform TUI --actor tui-dev \\
             --files changed.txt --verify green \\
             --status-before before/STATUS.md --status-after after/STATUS.md

  # Prove two lanes are disjoint
  $PROG disjoint 'daemon/**' 'tui/**' 'Sources/**'

See .kiro/specs/cross-platform-live-verification/design.md ("Conflict-Free Merge Strategy").
EOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
main() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift || true
  case "$sub" in
    check-ownership) cmd_check_ownership "$@" ;;
    check-reserved)  cmd_check_reserved "$@" ;;
    check-green)     cmd_check_green "$@" ;;
    disjoint)        cmd_disjoint "$@" ;;
    gate)            cmd_gate "$@" ;;
    ""|help|-h|--help) usage; [ "$sub" = "" ] && return $EX_USAGE || return $EX_OK ;;
    *) err "unknown subcommand: $sub"; usage >&2; return $EX_USAGE ;;
  esac
}

main "$@"
