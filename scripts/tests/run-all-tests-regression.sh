#!/usr/bin/env bash
# Regression suite for scripts/run-all-tests.sh (IMP-242).
#
# Every case runs the runner (a copy inside a mktemp fixture repo, so it
# discovers the fixture's suites, not the real ones) and asserts on exit code
# and output. Nothing here touches ~/.claude or the real suites.
#
# Usage:  bash scripts/tests/run-all-tests-regression.sh
# Exit:   0 = all green, 1 = at least one red

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER_SRC="${CLAUDE_RUNNER_SCRIPT:-$SCRIPT_DIR/../run-all-tests.sh}"
[ -f "$RUNNER_SRC" ] || { echo "ERROR: runner not found: $RUNNER_SRC" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/run-all-tests-reg.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS + 1)); echo "  ok    $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  RED   $1 -- $2"; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi; }
expect_has() { if printf '%s' "$3" | grep -qE -- "$2"; then ok "$1"; else bad "$1" "pattern '$2' not in: $3"; fi; }
expect_lacks() { if printf '%s' "$3" | grep -qE -- "$2"; then bad "$1" "unexpected '$2' in: $3"; else ok "$1"; fi; }

# new_repo <name> -> fixture repo dir containing a copy of the runner
new_repo() {
  local d="$WORK/$1"
  mkdir -p "$d/scripts" "$d/hooks/tests" "$d/scripts/tests"
  cp "$RUNNER_SRC" "$d/scripts/run-all-tests.sh"
  printf '%s' "$d"
}
# add_suite <repo> <rel> <body...>
add_suite() { printf '#!/usr/bin/env bash\necho suite-output\n%s\n' "$3" > "$1/$2"; }
# a suite that exits 0 without printing anything (must be flagged SUSPECT)
add_silent() { printf '#!/usr/bin/env bash\nexit 0\n' > "$1/$2"; }
# run <repo> <args...> -> sets OUT (stdout+stderr) and RC
run() { local d="$1"; shift; OUT=$(bash "$d/scripts/run-all-tests.sh" "$@" 2>&1); RC=$?; }

echo "-- run-all-tests regression (IMP-242) --"

# 1. zero suites matched -> exit 1, loud
R=$(new_repo zero); run "$R"
expect_eq  "zero-match/exit1" 1 "$RC"
expect_has "zero-match/says-why" '0 suites matched' "$OUT"

# 2. one passing suite -> exit 0, PASS line, exact summary format
R=$(new_repo pass); add_suite "$R" hooks/tests/a-regression.sh 'exit 0'; run "$R"
expect_eq  "one-pass/exit0" 0 "$RC"
expect_has "one-pass/PASS-line" '^PASS +hooks/tests/a-regression\.sh  [0-9]+s$' "$OUT"
expect_has "summary/format" '^1 suites: 1 pass, 0 fail, 0 timeout, 0 skip$' "$OUT"

# 3. one failing suite -> exit 1, FAIL line, log kept with the suite output
R=$(new_repo fail); add_suite "$R" hooks/tests/a-regression.sh 'echo boom-marker >&2; exit 3'
add_suite "$R" scripts/tests/b-regression.sh 'exit 0'; run "$R" --logs "$WORK/fail-logs"
expect_eq  "one-fail/exit1" 1 "$RC"
expect_has "one-fail/FAIL-line" '^FAIL +hooks/tests/a-regression\.sh' "$OUT"
expect_has "one-fail/other-suite-still-ran" '^PASS +scripts/tests/b-regression\.sh' "$OUT"
expect_has "one-fail/summary" '^2 suites: 1 pass, 1 fail, 0 timeout, 0 skip$' "$OUT"
expect_has "one-fail/stderr-captured-in-log" 'boom-marker' "$(cat "$WORK"/fail-logs/hooks_tests_a-regression.sh.log)"

# 4. timeout -> exit 1, TIMEOUT line, the suite's child is killed
R=$(new_repo tmo)
add_suite "$R" hooks/tests/slow-regression.sh "sleep 60 & echo \$! > \"$WORK/tmo.pid\"; wait"
START=$(date +%s); CLAUDE_SUITE_TIMEOUT=2 run "$R"; ELAPSED=$(( $(date +%s) - START ))
expect_eq  "timeout/exit1" 1 "$RC"
expect_has "timeout/TIMEOUT-line" '^TIMEOUT +hooks/tests/slow-regression\.sh' "$OUT"
expect_has "timeout/summary" '1 suites: 0 pass, 0 fail, 1 timeout, 0 skip' "$OUT"
[ "$ELAPSED" -lt 20 ] && ok "timeout/returns-promptly (${ELAPSED}s)" || bad "timeout/returns-promptly" "${ELAPSED}s"
if kill -0 "$(cat "$WORK/tmo.pid" 2>/dev/null || echo 0)" 2>/dev/null; then bad "timeout/child-killed" "child still alive"; else ok "timeout/child-killed"; fi

# 5. --filter: by basename and by path; no match -> exit 1
R=$(new_repo filt); add_suite "$R" hooks/tests/a-regression.sh 'exit 0'; add_suite "$R" scripts/tests/b-regression.sh 'exit 1'
run "$R" --filter 'a-*'
expect_eq  "filter/basename-exit0" 0 "$RC"
expect_has "filter/summary-one" '^1 suites: 1 pass' "$OUT"
run "$R" --filter 'scripts/tests/*'
expect_has "filter/path-selects-b" '^FAIL +scripts/tests/b-regression\.sh' "$OUT"
run "$R" --filter 'nothing-*'
expect_eq  "filter/no-match-exit1" 1 "$RC"

# 6. --list prints sorted paths, runs nothing
R=$(new_repo list)
add_suite "$R" hooks/tests/z-regression.sh "touch \"$WORK/list-ran\""
add_suite "$R" scripts/tests/a-regression.sh "touch \"$WORK/list-ran\""
run "$R" --list
expect_eq  "list/exit0" 0 "$RC"
expect_eq  "list/paths" "hooks/tests/z-regression.sh
scripts/tests/a-regression.sh" "$OUT"
[ -e "$WORK/list-ran" ] && bad "list/runs-nothing" "a suite was executed" || ok "list/runs-nothing"

# 7. discovery matches the inventory glob: any tests/*.sh counts, .bak does not
R=$(new_repo glob); add_suite "$R" hooks/tests/chain-probe-x.sh 'exit 0'; add_suite "$R" hooks/tests/old.sh.bak 'exit 1'
run "$R" --list
expect_eq  "glob/non-regression-name-included-bak-excluded" "hooks/tests/chain-probe-x.sh" "$OUT"

# 8. SKIP prints its reason, does not execute, does not fail the run
R=$(new_repo skip); add_suite "$R" hooks/tests/mac-regression.sh "touch \"$WORK/skip-ran\"; exit 1"; add_suite "$R" hooks/tests/ok-regression.sh 'exit 0'
CLAUDE_TEST_PLATFORM=linux CLAUDE_TEST_SKIP_RULES='hooks/tests/mac-*|linux|needs macOS date -v' run "$R"
expect_eq  "skip/exit0" 0 "$RC"
expect_has "skip/line-with-reason" '^SKIP +hooks/tests/mac-regression\.sh.*needs macOS date -v' "$OUT"
expect_has "skip/summary" '^2 suites: 1 pass, 0 fail, 0 timeout, 1 skip$' "$OUT"
[ -e "$WORK/skip-ran" ] && bad "skip/not-executed" "skipped suite ran" || ok "skip/not-executed"
CLAUDE_TEST_PLATFORM=darwin CLAUDE_TEST_SKIP_RULES='hooks/tests/mac-*|linux|needs macOS' run "$R"
expect_has "skip/other-platform-not-skipped" '^FAIL +hooks/tests/mac-regression\.sh' "$OUT"

# 9. CLAUDE_GATE_TESTMODE from the caller never reaches a suite
R=$(new_repo tm); add_suite "$R" hooks/tests/tm-regression.sh '[ -z "${CLAUDE_GATE_TESTMODE:-}" ]'
CLAUDE_GATE_TESTMODE=1 run "$R"
expect_eq  "testmode/not-inherited" 0 "$RC"

# 10. HOME sandbox: suite sees a throwaway HOME whose .claude resolves to the tested root
R=$(new_repo home); add_suite "$R" hooks/tests/h-regression.sh \
  '[ "$HOME" != "'"$HOME"'" ] && [ -f "$HOME/.claude/scripts/run-all-tests.sh" ] && [ -d "$HOME/.claude/global-observation" ]'
run "$R"
expect_eq  "home/sandboxed-and-linked-to-root" 0 "$RC"

# 11. invalid timeout / unknown flag -> usage error exit 2
R=$(new_repo bad); add_suite "$R" hooks/tests/a-regression.sh 'exit 0'
CLAUDE_SUITE_TIMEOUT=abc run "$R"; expect_eq "usage/bad-timeout-exit2" 2 "$RC"
run "$R" --nope;                   expect_eq "usage/unknown-flag-exit2" 2 "$RC"

# 12. --junit writes a report that records the failure
R=$(new_repo junit); add_suite "$R" hooks/tests/a-regression.sh 'echo junit-detail; exit 1'
run "$R" --junit "$WORK/out.xml"
expect_has "junit/failure-recorded" '<failure message="FAIL \(exit 1\)">' "$(cat "$WORK/out.xml")"
expect_has "junit/counts" 'tests="1" failures="1" skipped="0"' "$(cat "$WORK/out.xml")"

# 13. all-SKIP is not green (a skip-everything rule must not pass a gate)
R=$(new_repo allskip); add_suite "$R" hooks/tests/a-regression.sh 'exit 0'
CLAUDE_TEST_SKIP_RULES='*|*|x' run "$R"
expect_eq  "all-skip/exit1" 1 "$RC"
expect_has "all-skip/summary-and-error" '0 pass, 0 fail, 0 timeout, 1 skip' "$OUT"
expect_has "all-skip/says-why" 'no suite actually ran' "$OUT"

# 14. SUSPECT: exit 0 with an empty log, or with a RED/FAIL line, counts as failure
R=$(new_repo susp); add_silent "$R" hooks/tests/empty-regression.sh
add_suite "$R" hooks/tests/red-regression.sh 'echo "  RED something broke"; exit 0'
add_suite "$R" hooks/tests/fine-regression.sh 'echo "PASS: 3   FAIL: 0"; exit 0'; run "$R"
expect_eq  "suspect/exit1" 1 "$RC"
expect_has "suspect/empty-log" '^SUSPECT +hooks/tests/empty-regression\.sh' "$OUT"
expect_has "suspect/red-line" '^SUSPECT +hooks/tests/red-regression\.sh' "$OUT"
expect_has "suspect/counted-as-fail" '^3 suites: 1 pass, 2 fail' "$OUT"

# 15. a suite killed by a signal is a FAIL
R=$(new_repo sigk); add_suite "$R" hooks/tests/k-regression.sh 'echo started; kill -9 $$'; run "$R"
expect_has "signal-killed/FAIL" '^FAIL +hooks/tests/k-regression\.sh' "$OUT"

# 16. suite environment: CLAUDE_* scrubbed (CLAUDE_TEST_*/SUITE_TIMEOUT kept), stdin is /dev/null,
#     suite_env override points git-state-check at the tested root
R=$(new_repo envs)
add_suite "$R" hooks/tests/e-regression.sh '[ -z "${CLAUDE_FOO:-}" ] && [ "${CLAUDE_TEST_KEEP:-}" = 1 ] && [ "${CLAUDE_SUITE_TIMEOUT:-}" = 30 ] && [ "$(cat | wc -c | tr -d " ")" = 0 ]; echo checked'
add_suite "$R" hooks/tests/git-state-check-regression.sh '[ "$CLAUDE_HOOK" = "'"$R"'/hooks/git-state-check.sh" ]; echo checked'
OUT=$(CLAUDE_FOO=1 CLAUDE_TEST_KEEP=1 CLAUDE_SUITE_TIMEOUT=30 bash "$R/scripts/run-all-tests.sh" 2>&1 <<< "stdin-data"); RC=$?
expect_eq  "env/scrub-stdin-and-suite-env" 0 "$RC"

# 17. HOME sandbox: observation writes stay out of the tested root and the real HOME; sandbox removed
R=$(new_repo obs); mkdir -p "$R/global-observation" "$WORK/tmp-obs"
add_suite "$R" hooks/tests/o-regression.sh 'mkdir -p "$HOME/.claude/global-observation"; echo x > "$HOME/.claude/global-observation/obs-probe-$$"; echo done'
TMPDIR="$WORK/tmp-obs" run "$R" --logs "$WORK/obs-logs"
expect_eq  "sandbox/root-untouched" 0 "$(ls "$R/global-observation" | wc -l | tr -d ' ')"
expect_eq  "sandbox/real-home-untouched" 0 "$(ls "$HOME/.claude/global-observation" 2>/dev/null | grep -c '^obs-probe-')"
expect_eq  "sandbox/removed-after-normal-exit" 0 "$(ls "$WORK/tmp-obs" | grep -c '^run-all-tests-home')"

# 18. cleanup after a timeout and after SIGTERM/SIGINT of the runner (child group killed, exit 130)
R=$(new_repo cl1); mkdir -p "$WORK/tmp-to"
add_suite "$R" hooks/tests/s-regression.sh 'sleep 60'
TMPDIR="$WORK/tmp-to" CLAUDE_SUITE_TIMEOUT=1 run "$R" --logs "$WORK/to-logs"
expect_eq  "sandbox/removed-after-timeout" 0 "$(ls "$WORK/tmp-to" | grep -c '^run-all-tests-home')"
for SIG in TERM INT; do
  R=$(new_repo "sig$SIG"); mkdir -p "$WORK/tmp-$SIG"
  add_suite "$R" hooks/tests/s-regression.sh "sleep 60 & echo \$! > \"$WORK/sig$SIG.pid\"; wait"
  set -m
  TMPDIR="$WORK/tmp-$SIG" bash "$R/scripts/run-all-tests.sh" --logs "$WORK/sig-logs-$SIG" >/dev/null 2>&1 &
  RPID=$!
  set +m
  for _ in $(seq 1 50); do [ -s "$WORK/sig$SIG.pid" ] && break; sleep 0.2; done
  kill -"$SIG" "$RPID" 2>/dev/null; { wait "$RPID"; RC=$?; } 2>/dev/null
  expect_eq  "signal-$SIG/exit130" 130 "$RC"
  if kill -0 "$(cat "$WORK/sig$SIG.pid" 2>/dev/null || echo 0)" 2>/dev/null; then bad "signal-$SIG/child-killed" "alive"; else ok "signal-$SIG/child-killed"; fi
  expect_eq  "signal-$SIG/sandbox-removed" 0 "$(ls "$WORK/tmp-$SIG" | grep -c '^run-all-tests-home')"
done

# 19. a root path containing ".bak" does not hide its suites; junit escapes odd names
R=$(new_repo 'x.bak'); add_suite "$R" 'hooks/tests/q"uote-regression.sh' 'echo hi'
run "$R" --junit "$WORK/q.xml"
expect_eq  "bak-in-root/still-discovered" 0 "$RC"
expect_has "junit/name-escaped" 'name="hooks/tests/q&quot;uote-regression\.sh"' "$(cat "$WORK/q.xml")"

echo
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
