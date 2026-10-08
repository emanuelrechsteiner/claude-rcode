#!/usr/bin/env bash
# run-all-tests.sh — one runner for every regression suite in this repo (IMP-242).
#
# Discovery matches scripts/framework-inventory.sh exactly: every non-.bak
# *.sh directly in hooks/tests/ and scripts/tests/ (that includes
# chain-probe-imp108.sh, which is not named *-regression.sh). Each suite runs
# in its own process, with a per-suite timeout, stdout+stderr captured to a
# log. Zero discovered suites is an error, never a green run.
#
# Usage: run-all-tests.sh [--workshop|--live] [--filter <glob>] [--list]
#                         [--junit <file>] [--logs <dir>]
#   --workshop  (default) run the suites in this checkout against its own files
#   --live      run the suites of the live install (CLAUDE_LIVE_CONFIG, default ~/.claude)
#   --filter    only suites whose repo-relative path or basename matches <glob>
#   --list      print the discovered suites and exit 0
#   --junit     also write a JUnit XML report
#   --logs      keep per-suite logs in <dir> (default: a fresh temp dir, printed)
#
# Environment:
#   CLAUDE_SUITE_TIMEOUT    per-suite timeout in seconds (default 300)
#   CLAUDE_TEST_PLATFORM    linux|darwin override of uname (default: uname)
#   CLAUDE_TEST_SKIP_RULES  extra skip rules, newline separated "glob|platform|reason"
#                           (platform "*" = every platform)
#   CLAUDE_TEST_REAL_HOME   1 = do not sandbox HOME (default: sandbox, see below)
#
# HOME sandbox: several hooks hardcode ${HOME}/.claude/... (parallel-lock-check.sh
# calls ${HOME}/.claude/scripts/parallel-claim.sh) and several suites write
# observation logs under $HOME/.claude/global-observation. Each run therefore
# gets a throwaway HOME whose .claude/ symlinks every entry of the tested root
# (so hardcoded paths resolve to the code under test, never to a different
# install) and has its own empty global-observation/ (so nothing is written
# into the real ~/.claude, and CI needs no ~/.claude). Your ~/.gitconfig is
# copied in (git identity is a prerequisite of the deploy suite).
#
# Every CLAUDE_* variable except CLAUDE_SUITE_TIMEOUT and CLAUDE_TEST_* is removed
# from each suite's environment (CLAUDE_GATE_TESTMODE included: suites that need it
# set it themselves), so an operator's session cannot mask or cause a defect.
# Suites get </dev/null as stdin. A suite that exits 0 but leaves an empty log or a
# line starting with RED/FAIL is SUSPECT and counts as a failure.
#
# Exit: 0 only when no suite failed/timed out/was SUSPECT AND at least one suite
# passed (an all-SKIP run proves nothing); 1 otherwise; 2 on usage error;
# 130 when interrupted (INT/TERM/HUP).
set -u
die() { printf 'run-all-tests: %s\n' "$1" >&2; exit 2; }

MODE=workshop FILTER="" LIST=0 JUNIT="" LOGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workshop) MODE=workshop ;;
    --live)     MODE=live ;;
    --list)     LIST=1 ;;
    --filter)   [ $# -ge 2 ] || die "--filter needs a glob"; FILTER="$2"; shift ;;
    --junit)    [ $# -ge 2 ] || die "--junit needs a file"; JUNIT="$2"; shift ;;
    --logs)     [ $# -ge 2 ] || die "--logs needs a directory"; LOGS="$2"; shift ;;
    -h|--help)  sed -n '2,43p' "$0"; exit 0 ;;
    *)          die "unknown argument: $1" ;;
  esac
  shift
done

TIMEOUT="${CLAUDE_SUITE_TIMEOUT:-300}"
case "$TIMEOUT" in ''|*[!0-9]*|0) die "CLAUDE_SUITE_TIMEOUT must be a positive integer, got '$TIMEOUT'" ;; esac
PLATFORM="${CLAUDE_TEST_PLATFORM:-$(uname -s | tr '[:upper:]' '[:lower:]')}"

if [ "$MODE" = live ]; then
  ROOT="${CLAUDE_LIVE_CONFIG:-$HOME/.claude}"
else
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
[ -d "$ROOT" ] || die "root not found: $ROOT"

# Built-in skip rules "glob|platform|reason" (reasons printed). Each was seen failing on
# ubuntu:24.04 (docker, 2026-10-01) but green on macOS (BSD-only features); remove when made portable.
SKIP_RULES="hooks/tests/background-watchdog-regression.sh|linux|BSD-only 'date -j' (date: invalid option -- j)
hooks/tests/routine-liveness-regression.sh|linux|BSD-only 'date -j/-v' in suite or hook
hooks/tests/session-end-staleness-regression.sh|linux|BSD-only 'date -v' (suite builds timestamps with it)
scripts/tests/logbook-count-symlink-regression.sh|linux|macOS symlink/firmlink semantics (exit 1 instead of 19 on Linux, not diagnosed further)
${CLAUDE_TEST_SKIP_RULES:-}"

# Per-suite environment overrides that point a suite at the files of $ROOT
# instead of the default location it would pick on its own (the default is
# the LIVE install for these two suites). Every other suite resolves its
# subject relative to its own location, so it already follows $ROOT.
suite_env() { # suite_env <rel> -> one VAR=value per line
  case "$1" in
    hooks/tests/governing-path-guard-regression.sh) echo "CLAUDE_HOOK=$ROOT/hooks/governing-path-guard.sh" ;;
    hooks/tests/git-state-check-regression.sh) echo "CLAUDE_HOOK=$ROOT/hooks/git-state-check.sh" ;;
    hooks/tests/chain-probe-imp108.sh)         echo "CLAUDE_SETTINGS=$ROOT/settings.json" ;;
  esac
}

skip_reason() { # skip_reason <rel> -> prints reason and returns 0 when skipped
  local rel="$1" glob plat reason
  while IFS='|' read -r glob plat reason; do
    [ -n "$glob" ] || continue
    case "$rel" in $glob) ;; *) continue ;; esac
    if [ "$plat" = "*" ] || [ "$plat" = "$PLATFORM" ]; then
      printf '%s' "${reason:-no reason given}"; return 0
    fi
  done <<< "$SKIP_RULES"
  return 1
}

# ---- discovery (same glob as framework-inventory.sh: tests/*.sh, no .bak) ----
SUITES=()
for f in "$ROOT"/hooks/tests/*.sh "$ROOT"/scripts/tests/*.sh; do
  [ -f "$f" ] || continue
  rel="${f#"$ROOT"/}"
  case "$rel" in *.bak*) continue ;; esac
  if [ -n "$FILTER" ]; then
    case "$rel" in $FILTER) ;; *) case "$(basename "$rel")" in $FILTER) ;; *) continue ;; esac ;; esac
  fi
  SUITES+=("$rel")
done
if [ ${#SUITES[@]} -eq 0 ]; then
  printf 'run-all-tests: ERROR: 0 suites matched under %s (filter: %s) - refusing to report green\n' \
    "$ROOT" "${FILTER:-none}" >&2
  exit 1
fi

if [ "$LIST" = 1 ]; then
  printf '%s\n' "${SUITES[@]}"
  exit 0
fi

if [ -z "$LOGS" ]; then
  LOGS="$(mktemp -d "${TMPDIR:-/tmp}/run-all-tests.XXXXXX")" && [ -d "$LOGS" ] || die "mktemp for the log directory failed"
else
  mkdir -p "$LOGS" || die "cannot create log directory: $LOGS"
fi
printf 'run-all-tests: mode=%s root=%s platform=%s timeout=%ss logs=%s\n' "$MODE" "$ROOT" "$PLATFORM" "$TIMEOUT" "$LOGS"

# ---- HOME sandbox (see header) ----
SBX_HOME="$HOME" SBX_ACTIVE=0 CUR_PID=""
cleanup() { [ "$SBX_ACTIVE" = 1 ] && rm -rf "$SBX_HOME"; return 0; }
on_signal() { # kill the running suite's process group, clean up, exit 130
  [ -n "$CUR_PID" ] && { kill -TERM -- "-$CUR_PID" 2>/dev/null; sleep 1; kill -KILL -- "-$CUR_PID" 2>/dev/null; }
  printf 'run-all-tests: interrupted\n' >&2
  exit 130
}
trap cleanup EXIT; trap on_signal INT TERM HUP
if [ "${CLAUDE_TEST_REAL_HOME:-0}" != 1 ]; then
  SBX_HOME="$(mktemp -d "${TMPDIR:-/tmp}/run-all-tests-home.XXXXXX")" && [ -d "$SBX_HOME" ] || die "mktemp for the sandbox HOME failed"
  SBX_ACTIVE=1
  mkdir -p "$SBX_HOME/.claude/global-observation"
  # Git identity/defaults are an environment prerequisite (deploy-to-live.sh
  # commits without -c user.*), not something to hide: carry the caller's
  # ~/.gitconfig into the sandbox as a copy.
  if [ -f "$HOME/.gitconfig" ]; then cp "$HOME/.gitconfig" "$SBX_HOME/.gitconfig" || die "cannot copy ~/.gitconfig"; fi
  for e in "$ROOT"/* "$ROOT"/.[!.]*; do
    [ -e "$e" ] || continue
    case "$(basename "$e")" in global-observation|.git) continue ;; esac
    ln -s "$e" "$SBX_HOME/.claude/$(basename "$e")" || die "cannot link $e into the sandbox HOME"
  done
fi

xml_escape() { sed -e 's/&/\&amp;/g' -e 's/"/\&quot;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/[^[:print:][:space:]]//g'; }

# run_one <rel> <log>: sets STATUS and ELAPSED. Own process group (set -m) so a
# timeout can kill the suite and everything it spawned.
run_one() {
  local rel="$1" log="$2" start now pid rc v suite_home extra=() scrub=()
  while IFS= read -r kv; do [ -n "$kv" ] && extra+=("$kv"); done < <(suite_env "$rel")
  suite_home="$SBX_HOME"
  # governing-path-guard resolves symlinks and needs a real ~/.claude path; it writes only to its own mktemp fixture.
  case "$rel" in hooks/tests/governing-path-guard-regression.sh) suite_home="$HOME" ;; esac
  [ "$SBX_ACTIVE" = 1 ] && [ "$suite_home" = "$SBX_HOME" ] && extra+=("CLAUDE_LOCK_ROOT=$SBX_HOME/.claude/locks")
  while IFS= read -r v; do
    case "$v" in CLAUDE_SUITE_TIMEOUT|CLAUDE_TEST_*) ;; CLAUDE_*) scrub+=(-u "$v") ;; esac
  done < <(env | sed -n 's/^\(CLAUDE_[A-Za-z0-9_]*\)=.*/\1/p')
  start=$(date +%s)
  set -m
  ( cd "$ROOT" && exec env -u CLAUDE_GATE_TESTMODE ${scrub[@]+"${scrub[@]}"} HOME="$suite_home" ${extra[@]+"${extra[@]}"} bash "$ROOT/$rel" ) </dev/null >"$log" 2>&1 &
  pid=$!
  CUR_PID=$pid
  set +m
  STATUS=""
  while kill -0 "$pid" 2>/dev/null; do
    now=$(date +%s)
    if [ $((now - start)) -ge "$TIMEOUT" ]; then
      kill -TERM -- "-$pid" 2>/dev/null
      for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
      kill -KILL -- "-$pid" 2>/dev/null
      STATUS=TIMEOUT
      break
    fi
    sleep 0.2
  done
  { wait "$pid"; rc=$?; } 2>/dev/null
  CUR_PID=""
  ELAPSED=$(( $(date +%s) - start ))
  if [ -z "$STATUS" ]; then
    if [ "$rc" -ne 0 ]; then STATUS=FAIL
    elif [ ! -s "$log" ]; then STATUS=SUSPECT; SUSPECT_WHY="exit 0 with an empty log"
    elif grep -qE '^[[:space:]]*(RED|FAIL)\b' "$log"; then STATUS=SUSPECT; SUSPECT_WHY="exit 0 but the log has a RED/FAIL line"
    else STATUS=PASS; fi
  fi
  RC=$rc
}

PASS=0 FAILN=0 TOUT=0 SKIPN=0
XML_BODY=""
for rel in "${SUITES[@]}"; do
  log="$LOGS/$(printf '%s' "$rel" | tr '/' '_').log"
  if reason=$(skip_reason "$rel"); then
    SKIPN=$((SKIPN + 1))
    printf 'SKIP     %s  0s  (%s)\n' "$rel" "$reason"
    XML_BODY="$XML_BODY<testcase name=\"$(printf '%s' "$rel" | xml_escape)\" time=\"0\"><skipped message=\"$(printf '%s' "$reason" | xml_escape)\"/></testcase>
"
    continue
  fi
  run_one "$rel" "$log"
  case "$STATUS" in
    PASS)    PASS=$((PASS + 1)) ;;
    FAIL|SUSPECT) FAILN=$((FAILN + 1)) ;;
    TIMEOUT) TOUT=$((TOUT + 1)) ;;
  esac
  printf '%-8s %s  %ss\n' "$STATUS" "$rel" "$ELAPSED"
  [ "$STATUS" = SUSPECT ] && printf '         ^ %s (counted as FAIL)\n' "$SUSPECT_WHY"
  if [ "$STATUS" = PASS ]; then
    XML_BODY="$XML_BODY<testcase name=\"$(printf '%s' "$rel" | xml_escape)\" time=\"$ELAPSED\"/>
"
  else
    XML_BODY="$XML_BODY<testcase name=\"$(printf '%s' "$rel" | xml_escape)\" time=\"$ELAPSED\"><failure message=\"$STATUS (exit $RC)\">$(tail -n 40 "$log" | xml_escape)</failure></testcase>
"
  fi
done

TOTAL=${#SUITES[@]}
printf '%d suites: %d pass, %d fail, %d timeout, %d skip\n' "$TOTAL" "$PASS" "$FAILN" "$TOUT" "$SKIPN"
if [ "$FAILN" -gt 0 ] || [ "$TOUT" -gt 0 ]; then
  printf 'run-all-tests: logs of failing suites are in %s\n' "$LOGS"
fi

if [ -n "$JUNIT" ]; then
  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<testsuite name="claude-code-config" tests="%d" failures="%d" skipped="%d">\n' \
      "$TOTAL" "$((FAILN + TOUT))" "$SKIPN"
    printf '%s' "$XML_BODY"
    printf '</testsuite>\n'
  } > "$JUNIT" || die "cannot write junit file: $JUNIT"
fi

if [ "$PASS" -eq 0 ]; then
  printf 'run-all-tests: ERROR: no suite actually ran and passed (%d skipped) - refusing to report green\n' "$SKIPN" >&2
  exit 1
fi
[ "$FAILN" -eq 0 ] && [ "$TOUT" -eq 0 ]
