#!/usr/bin/env bash
# Regression suite for goal tracking (IMP-289): scripts/goal.sh, hooks/goal-prompt.sh,
# hooks/goal-track.sh, hooks/goal-stop.sh.
#
# Locks in: seed and plan, pace and time to goal from measured durations, recorded
# deviations (added, dropped, detour, undeclared file, new prompt), the Cockpit feed
# lines, the one-time stop block, the prior from earlier goals and the hooks' quiet paths.
# Everything runs in a mktemp sandbox with a fixed clock (CLAUDE_GOAL_NOW).
#
# Usage: bash hooks/tests/goal-tracking-regression.sh      Exit: 0 all green, 1 otherwise
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GOAL="$ROOT/scripts/goal.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home" CLAUDE_GOAL_DIR="$WORK/goals" COCKPIT_DIR="$WORK/cockpit"
mkdir -p "$HOME" "$COCKPIT_DIR" "$WORK/proj/src"
unset CLAUDE_GOAL_TRACKING CLAUDE_GOAL_MIN_WORDS
PASS=0; FAILN=0; S="sess-1"; T0=1800000000; NOW=$T0

ok() { echo "PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL  $1 — $2"; FAILN=$((FAILN + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1" "condition false: $2"; fi; } # name, condition
g() { (cd "$WORK/proj" && CLAUDE_GOAL_NOW="$NOW" bash "$GOAL" --session "$S" "$@"); }
m() { g status --json | jq -r "$1"; }
hook() { printf '%s' "$2" | CLAUDE_GOAL_NOW="$NOW" bash "$ROOT/hooks/$1"; }
EV="$COCKPIT_DIR/events-$S.jsonl"

echo "== seed and plan =="
g seed --cwd "$WORK/proj" --text "Build the export   feature
with two lines" >/dev/null
check "seed writes the goal as one line" '[[ "$(m .state.goal.text)" == "Build the export feature with two lines" ]]'
check "seed puts the four summary rows on the feed in a fixed order" '[[ "$(grep "\"TaskCreated\"" "$EV" | head -4 | jq -r .data.task_id | tr "\n" " ")" == "g1-goal g1-eta g1-now g1-devs " ]] && grep -q "GOAL Build the export" "$EV" && grep -q "no plan yet" "$EV"'
PLAN='{"goal":"Export works end to end","milestones":[{"id":"M1","title":"Core"}],"issues":[{"id":"I1","title":"Writer","milestone":"M1","est_min":10,"paths":["src/*"]},{"id":"I2","title":"Reader","milestone":"M1","est_min":20,"paths":["src/*"]},{"id":"I3","title":"Docs","milestone":"M1","size":"M","paths":["docs/*"]}]}'
printf '%s' "$PLAN" | g plan >/dev/null
check "plan: three issues, 45 estimated minutes (size M = 15)" '[[ "$(m ".metrics.issues == 3 and .metrics.total_est == 45")" == true ]]'
check "plan: without history the pace is 1 and the time to goal is the estimate" '[[ "$(m ".metrics.pace == 1 and .metrics.remaining_min == 45")" == true ]]'

echo "== pace and time to goal from measured durations =="
g start I1 >/dev/null
NOW=$((T0 + 1200))
g done I1 >/dev/null
check "done: the measured duration is stored (20 min)" '[[ "$(m ".state.issues[0].actual_min == 20")" == true ]]'
check "pace: 20 measured minutes for 10 estimated = 2" '[[ "$(m ".metrics.pace == 2")" == true ]]'
check "time to goal: 35 open minutes x pace 2 = 70" '[[ "$(m ".metrics.remaining_min == 70")" == true ]]'
check "progress counts estimated minutes: 10 of 45 = 22 percent" '[[ "$(m .metrics.pct)" == 22 ]]'
check "status text names ETA and pace" 'g status | grep -q "pace x2" && g status | grep -q "ETA "'
# The terminal card shows 26 characters of a row: what matters most stands first.
check "feed: the time row leads with ETA, minutes left and percent" 'grep -qE "ETA [0-9]{2}:[0-9]{2} · 70m · 22% · pace x2 · 1/3 issues" "$EV"'
check "feed: with nothing running the step row names the next issue" 'grep -q "next: I2 Reader · est 20m" "$EV"'
g start I2 >/dev/null
check "feed: the step row leads with elapsed and estimated minutes of the running issue" 'grep -q "0m/20m · I2 Reader" "$EV"'
NOW=$((NOW + 600))
check "running issue: elapsed time is taken off the scaled estimate (30 + 30)" '[[ "$(m ".metrics.remaining_min == 60")" == true ]]'
NOW=$((NOW + 6000))
check "overrun: a running issue never counts as less than a tenth of its scaled estimate" '[[ "$(m ".metrics.remaining_min == 34")" == true ]]'

echo "== deviations =="
g add I4 "Hotfix found on the way" --est 5 --why "the reader crashed on empty input" --detour >/dev/null
check "add --detour records the issue and a deviation" '[[ "$(m ".state.deviations | length")" == 1 && "$(m ".state.deviations[0].kind")" == detour && "$(m .metrics.issues)" == 4 ]]'
check "feed: the deviation row counts and names the newest one" 'grep -q "1 deviation · 1 open · detour: I4 Hotfix found on the way" "$EV"'
g drop I3 --why "owner said docs later" >/dev/null
check "drop records a scope-drop and takes the issue out of the estimate" '[[ "$(m ".state.deviations[1].kind")" == scope-drop && "$(m .metrics.issues)" == 3 ]]'
check "status shows the scope change against the first plan" 'g status | grep -q "Scope: planned 3 issues / 45 min, now 3 issues / 35 min"'
g touch --file "$WORK/proj/src/a.ts"
g touch --file "$WORK/proj/README.md"
g touch --file "$WORK/proj/README.md"
g touch --file "/somewhere/else/x.md"
check "touch: inside a declared path is fine, outside is flagged exactly once" '[[ "$(m "[.state.deviations[] | select(.kind == \"undeclared-file\")] | length")" == 1 ]]'
check "touch: a file outside the project is recorded, not flagged" '[[ "$(m ".state.touched | has(\"/somewhere/else/x.md\")")" == true ]]'

echo "== end-of-turn check =="
R1=$(g stop-check); R2=$(g stop-check)
check "stop-check lists unreported deviations and the running issue, once" '[[ "$R1" == *"Unreported deviation(s) (3)"* && "$R1" == *"I2"* && -z "$R2" ]]'
g ack >/dev/null; g done I2 >/dev/null; g start I4 >/dev/null; g done I4 >/dev/null
check "after ack and done nothing is left and the goal is complete" '[[ -z "$(g stop-check)" && "$(m .metrics.open)" == 0 && "$(m .metrics.eta_ts)" == null ]]'

echo "== Cockpit feed =="
feed_ok() { local line; while IFS= read -r line; do printf '%s' "$line" | jq -e . >/dev/null 2>&1 || return 1; [ "${#line}" -lt 1900 ] || return 1; done <"$EV"; }
check "every feed line is valid JSON and under 1900 bytes" 'feed_ok'
check "issue rows are created, set running and completed" 'grep -q "\"task_id\": \"g1-I1\"" "$EV" && grep -q "\"taskId\": \"g1-I2\", \"status\": \"in_progress\"" "$EV" && grep -q "\"taskId\": \"g1-I1\", \"status\": \"completed\"" "$EV"'
check "the dropped issue leaves the card and the deviation is a row" 'grep -q "\"taskId\": \"g1-I3\", \"status\": \"deleted\"" "$EV" && grep -q "DEVIATION · scope-drop" "$EV"'
check "the finished goal keeps only the summary: done, duration, all reported" 'grep -qE "done [0-9]{2}:[0-9]{2} · took [0-9]+m · 3 issues" "$EV" && grep -q "all issues done" "$EV" && grep -q "3 deviations · reported" "$EV" && grep -q "\"taskId\": \"g1-I1\", \"status\": \"deleted\"" "$EV" && grep -q "\"taskId\": \"g1-goal\", \"status\": \"completed\"" "$EV"'

echo "== prior from earlier goals =="
check "only real durations enter the history (2 of 3 done issues)" '[[ "$(wc -l <"$CLAUDE_GOAL_DIR/velocity.jsonl" | tr -d " ")" == 2 ]]'
S="sess-2"
g seed --cwd "$WORK/proj2" --text "A second goal in a new session" >/dev/null
printf '%s' '{"goal":"Second","issues":[{"id":"A","title":"a","est_min":10}]}' | g plan >/dev/null
check "a new goal starts with the median pace of earlier issues (3.75)" '[[ "$(m .metrics.pace)" == 3.75 && "$(m .metrics.remaining_min)" == 37.5 ]]'

echo "== machine time is not scaled by the pace =="
S="sess-fixed"; NOW=$((NOW + 100))
printf '%s' '{"goal":"Ship","issues":[{"id":"W","title":"work","est_min":10},{"id":"V","title":"more work","est_min":10},{"id":"T","title":"suite run","est_min":12,"fixed":true}]}' | g plan >/dev/null
g start W >/dev/null; NOW=$((NOW + 300)); g done W >/dev/null
check "fixed issue: pace 0.5 halves the open work (5) but not the machine time (12)" '[[ "$(m ".metrics.pace == 0.5 and .metrics.remaining_min == 17")" == true ]]'
g start T >/dev/null; NOW=$((NOW + 1200)); g done T >/dev/null
check "a finished fixed issue does not change the pace" '[[ "$(m ".metrics.pace == 0.5")" == true ]]'
check "status marks machine time" 'g status | grep -q "suite run — est 12m, took 20m \[machine time\]"'

echo "== the measured pace is clamped =="
# The duration is wall-clock time from start to done. An issue that sat idle must not
# multiply every open estimate: the measured pace stays within 0.2 and 5, like the prior.
S="sess-clamp"; NOW=$((T0 + 20000))
printf '%s' '{"goal":"Clamp","issues":[{"id":"A","title":"a","est_min":10},{"id":"B","title":"b","est_min":10}]}' | g plan >/dev/null
g start A >/dev/null; NOW=$((NOW + 10800)); g done A >/dev/null
check "an issue that sat idle for three hours cannot push the pace above 5" '[[ "$(m ".metrics.pace == 5 and .metrics.remaining_min == 50")" == true ]]'
VLINES=$(wc -l <"$CLAUDE_GOAL_DIR/velocity.jsonl" | tr -d " ")
g done A >/dev/null 2>&1; RC=$?
check "a second done on the same issue is refused and writes no second pace record" '[[ $RC == 1 && "$(wc -l <"$CLAUDE_GOAL_DIR/velocity.jsonl" | tr -d " ")" == "$VLINES" ]]'

echo "== hooks =="
P=$(jq -nc --arg c "$WORK/proj3" '{session_id:"sess-3",cwd:$c,prompt:"Please build the import feature with tests and documentation for it"}')
OUT=$(hook goal-prompt.sh "$P")
check "prompt hook: a task prompt writes a seed and explains the plan call" '[[ -f "$CLAUDE_GOAL_DIR/sess-3.json" && "$OUT" == *"goal.sh --session sess-3 plan"* ]]'
OUT=$(hook goal-prompt.sh "$(jq -nc '{session_id:"sess-4",cwd:"/tmp",prompt:"<task-notification> a b c d e f g h i j k l"}')")
check "prompt hook: an automated turn writes nothing" '[[ -z "$OUT" && ! -f "$CLAUDE_GOAL_DIR/sess-4.json" ]]'
OUT=$(hook goal-prompt.sh "$(jq -nc '{session_id:"sess-5",cwd:"/tmp",prompt:"yes do it"}')")
check "prompt hook: a short prompt writes nothing" '[[ -z "$OUT" && ! -f "$CLAUDE_GOAL_DIR/sess-5.json" ]]'
OUT=$(printf '%s' "$(jq -nc '{session_id:"sess-6",cwd:"/tmp",prompt:"Please build the import feature with tests and documentation"}')" | CLAUDE_GOAL_TRACKING=0 bash "$ROOT/hooks/goal-prompt.sh")
check "prompt hook: CLAUDE_GOAL_TRACKING=0 switches it off" '[[ -z "$OUT" && ! -f "$CLAUDE_GOAL_DIR/sess-6.json" ]]'
# A value that starts with a dash must reach the tool as a value, not as an option.
OUT=$(hook goal-prompt.sh "$(jq -nc --arg c "$WORK/proj7" '{session_id:"sess-7",cwd:$c,prompt:"- build the import feature with tests and documentation for it"}')")
check "prompt hook: a prompt that starts with a list dash still gets its goal" '[[ -f "$CLAUDE_GOAL_DIR/sess-7.json" && "$OUT" == *"goal.sh --session sess-7 plan"* ]]'
OUT=$(hook goal-prompt.sh "$(jq -nc --arg c "$WORK/proj8" '{session_id:"sess-8",cwd:$c,prompt:"--- name: x --- build the import feature with tests and documentation"}')")
check "prompt hook: a prompt that starts with a frontmatter fence still gets its goal" '[[ -f "$CLAUDE_GOAL_DIR/sess-8.json" && "$(jq -r .goal.text "$CLAUDE_GOAL_DIR/sess-8.json")" == "--- name: x --- build"* ]]'
S="sess-3"
printf '%s' '{"goal":"Import","issues":[{"id":"X","title":"x","est_min":5,"paths":["src/*"]}]}' | g plan >/dev/null
OUT=$(hook goal-prompt.sh "$P")
check "prompt hook: a new prompt on an open goal is kept as a note that counts as reported" '[[ "$OUT" == *"noted on the goal"* && "$(m ".state.deviations[0].kind")" == new-prompt && "$(m ".state.deviations[0].acked")" == true ]]'
OUT=$(hook goal-stop.sh '{"session_id":"sess-3","stop_hook_active":false}')
check "stop hook: a follow-up prompt alone never blocks the end of a turn" '[[ -z "$OUT" ]]'
check "feed: a follow-up prompt is not counted as a deviation of the work" 'grep -q "no deviations" "$COCKPIT_DIR/events-sess-3.jsonl" && ! grep -q "1 deviation ·" "$COCKPIT_DIR/events-sess-3.jsonl" && ! grep -q "DEVIATION · new-prompt" "$COCKPIT_DIR/events-sess-3.jsonl"'
hook goal-track.sh "$(jq -nc --arg f "$WORK/proj3/other/y.md" '{session_id:"sess-3",tool_name:"Edit",tool_input:{file_path:$f}}')"
check "track hook: a write outside the declared paths becomes a deviation" '[[ "$(m "[.state.deviations[] | select(.kind == \"undeclared-file\")] | length")" == 1 ]]'
hook goal-track.sh "$(jq -nc '{session_id:"sess-none",tool_name:"Edit",tool_input:{file_path:"/x"}}')"; RC=$?
check "track hook: silent and without effect in a session without a goal" '[[ $RC == 0 && ! -f "$CLAUDE_GOAL_DIR/sess-none.json" ]]'
# The refresh limit is decided in the shell from the age of the state file, so that a tool
# call does not start Python. The tool's own clock is pinned far ahead: only the file age counts.
BASH_CALL='{"hook_event_name":"PostToolUse","session_id":"sess-3","tool_name":"Bash","tool_input":{"command":"ls"}}'
BEFORE=$(m ".state.feed.last_sync"); NOW=$((NOW + 1000))
hook goal-track.sh "$BASH_CALL"
check "track hook: a tool call within 30 s of the last refresh costs no refresh" '[[ "$(m ".state.feed.last_sync")" == "$BEFORE" ]]'
python3 -c 'import os, sys, time; old = time.time() - 120; os.utime(sys.argv[1], (old, old))' "$CLAUDE_GOAL_DIR/sess-3.json"
hook goal-track.sh "$BASH_CALL"
check "track hook: once the state is older than 30 s the next tool call refreshes the card" '[[ "$(m ".state.feed.last_sync == $NOW")" == true ]]'
g start X >/dev/null
OUT=$(hook goal-stop.sh '{"session_id":"sess-3","stop_hook_active":false}')
check "stop hook: blocks once and names the open items" '[[ "$(printf "%s" "$OUT" | jq -r .decision)" == block && "$OUT" == *"undeclared-file"* && "$OUT" != *"new-prompt"* && "$OUT" == *"X"* ]]'
OUT=$(hook goal-stop.sh '{"session_id":"sess-3","stop_hook_active":false}')
check "stop hook: the same state does not block twice" '[[ -z "$OUT" ]]'
g deviate "looked into an unrelated warning" >/dev/null
OUT=$(hook goal-stop.sh '{"session_id":"sess-3","stop_hook_active":true}')
check "stop hook: never blocks a stop that answers a stop hook" '[[ -z "$OUT" ]]'
OUT=$(hook goal-stop.sh 'not json'); RC=$?
check "stop hook: malformed input exits 0 silently" '[[ $RC == 0 && -z "$OUT" ]]'
OUT=$(hook goal-prompt.sh ''); RC=$?
check "prompt hook: empty input exits 0 silently" '[[ $RC == 0 && -z "$OUT" ]]'

echo "== refusals =="
(cd "$WORK/proj" && bash "$GOAL" --session "bad/id" status) >/dev/null 2>&1; RC=$?
check "a session id with a slash is refused" '[[ $RC == 1 ]]'
printf '%s' '{"issues":[]}' | g plan >/dev/null 2>&1; RC=$?
check "a plan without issues is refused" '[[ $RC == 1 ]]'
printf 'nonsense' | g plan >/dev/null 2>&1; RC=$?
check "a plan that is not JSON is refused" '[[ $RC == 1 ]]'
g start NOPE >/dev/null 2>&1; RC=$?
check "an unknown issue is refused" '[[ $RC == 1 ]]'
OUT=$(printf '%s' '[1, 2]' | g plan 2>&1); RC=$?
check "a plan of the wrong shape is refused with a message, not a traceback" '[[ $RC == 1 && "$OUT" == *"wrong shape"* && "$OUT" != *"Traceback"* ]]'
printf '%s' '{"goal":"P","issues":[{"id":"S1","title":"s","est_min":"NaN"}]}' | g plan >/dev/null 2>&1; RC=$?
check "an estimate that is not a finite number is refused" '[[ $RC == 1 ]]'
S="sess-paths"; printf '%s' '{"goal":"P","issues":[{"id":"S1","title":"s","est_min":5,"paths":"src/*"}]}' | g plan >/dev/null
check "a path given as one string is one path, not its characters" '[[ "$(m ".state.issues[0].paths | length")" == 1 ]]'

echo "== helper rows on the card (IMP-277) =="
S="sess-ag"; EV="$COCKPIT_DIR/events-$S.jsonl"; NOW=$((T0 + 5000))
pre() { hook goal-track.sh "$(jq -nc --arg s "$S" --arg d "$1" --arg t "$2" --arg m "$3" --arg e "$4" '{hook_event_name:"PreToolUse",session_id:$s,tool_name:"Agent",tool_input:{description:$d,subagent_type:$t,model:$m,effort:$e,prompt:"p"}}')"; }
sub() { hook goal-track.sh "$(jq -nc --arg s "$S" --arg ev "$1" --arg i "$2" --arg t "$3" '{hook_event_name:$ev,session_id:$s,agent_id:$i,agent_type:$t}')"; }
OUT=$(pre "Write the suites" testing-agent haiku low); RC=$?
check "dispatch: queued silently, no row yet, also without a goal" '[[ $RC == 0 && -z "$OUT" && "$(m ".state.agent_queue | length")" == 1 && ! -e "$EV" ]]'
sub SubagentStart ag-1 testing-agent
check "start: the helper becomes a running row with title, model and effort" 'grep -q "HELPER · testing-agent · Write the suites · haiku/low · running 0m" "$EV" && [[ "$(m ".state.agents[0].id")" == ag-1 && "$(m ".state.agent_queue | length")" == 0 ]]'
check "a session without a goal shows helpers and no goal row" '! grep -q "GOAL " "$EV"'
hook goal-track.sh '{"hook_event_name":"PostToolUse","session_id":"sess-ag","tool_name":"Edit","tool_input":{"file_path":"/x/y.md"}}'
OUT=$(hook goal-stop.sh '{"session_id":"sess-ag","stop_hook_active":false}')
check "a session that only has helper rows records no files and never blocks a stop" '[[ "$(m ".state.touched | length")" == 0 && -z "$OUT" ]]'
NOW=$((NOW + 150)); sub SubagentStop ag-1 testing-agent
check "stop: the row is closed with the measured duration" 'grep -q "Write the suites · haiku/low · took 2.5m" "$EV" && grep -q "\"taskId\": \"a1\", \"status\": \"completed\"" "$EV"'
pre "Review the diff" code-reviewer-agent haiku medium
pre "Build the endpoint" backend-agent haiku high
sub SubagentStart ag-3 backend-agent
sub SubagentStart ag-2 code-reviewer-agent
check "two dispatches that start in reverse order keep their own titles" '[[ "$(m ".state.agents[] | select(.id == \"ag-3\") | .title")" == "Build the endpoint" && "$(m ".state.agents[] | select(.id == \"ag-2\") | .title")" == "Review the diff" ]]'
pre "Denied dispatch" backend-agent haiku low
NOW=$((NOW + 301)); sub SubagentStart ag-4 backend-agent
check "a denied dispatch expires: a later helper does not inherit its title" '[[ "$(m ".state.agents[] | select(.id == \"ag-4\") | .title")" == "(started without a recorded dispatch)" ]]'
sub SubagentStart ag-4 backend-agent
check "a repeated start event adds no second row" '[[ "$(m "[.state.agents[] | select(.id == \"ag-4\")] | length")" == 1 ]]'
pre "--draft" testing-agent haiku low
sub SubagentStart ag-5 testing-agent
check "a one-word dispatch title that starts with dashes is kept as the title" '[[ "$(m ".state.agents[] | select(.id == \"ag-5\") | .title")" == "--draft" ]]'
OUT=$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"sess-ag","tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$ROOT/hooks/goal-track.sh"); RC=$?
check "a PreToolUse call of another tool is ignored" '[[ $RC == 0 && -z "$OUT" && "$(m ".state.agent_queue | length")" == 0 ]]'
g seed --cwd "$WORK/proj" --text "A goal that arrives after the first helpers" >/dev/null
check "a goal set later keeps the helper rows beside the goal row" '[[ "$(m ".state.agents | length")" == 5 ]] && grep -q "GOAL A goal that arrives" "$EV"'
check "every helper feed line is valid JSON and under 1900 bytes" 'feed_ok'
# The card lists rows in the order they were created and starts at the first unfinished one:
# helper rows from before the goal are created again behind the goal's four summary rows.
created() { grep "\"TaskCreated\"" "$EV" | jq -r .data.task_id | grep -n -m1 "$1" | cut -d: -f1; }
check "a goal set later puts the helper rows behind its summary rows" '[[ "$(created "^g1-goal$")" -lt "$(created "^g1-a")" ]] && grep -q "\"taskId\": \"a2\", \"status\": \"deleted\"" "$EV"'

pre "First try" ui-agent haiku low
pre "Second try" ui-agent haiku low
sub SubagentStart ag-7 ui-agent
check "a dispatch that was denied and sent again: the helper takes the newer entry" '[[ "$(m ".state.agents[] | select(.id == \"ag-7\") | .title")" == "Second try" ]]'
pre "No type given" "" haiku low
sub SubagentStart ag-8 general-purpose
check "a dispatch without a type fits the helper that starts next" '[[ "$(m ".state.agents[] | select(.id == \"ag-8\") | .title")" == "No type given" ]]'

echo "== a lock left behind by a dead writer =="
S="sess-lock"; mkdir "$COCKPIT_DIR/.lock-$S"
g seed --cwd "$WORK/proj" --text "A goal written while a dead writer still holds the lock" >/dev/null
check "the stale lock is removed after one second and the rows are written" '[[ ! -d "$COCKPIT_DIR/.lock-sess-lock" ]] && grep -q "GOAL A goal written while" "$COCKPIT_DIR/events-sess-lock.jsonl"'

echo "== parallel writers =="
# Tool calls of one message run at the same time, and so do their hooks: twelve file records
# and a done arrive together. Without the per-session lock the slower writers erase the others.
S="sess-par"
g seed --cwd "$WORK/proj" --text "Parallel writers keep every record of the goal" >/dev/null
printf '%s' '{"goal":"Parallel writers","issues":[{"id":"P1","title":"one issue","est_min":5,"paths":["src/*"]}]}' | g plan >/dev/null
g start P1 >/dev/null
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do g touch --file "$WORK/proj/other/f$n.md" >/dev/null 2>&1 & done
g done P1 >/dev/null 2>&1 &
wait
check "parallel writers: twelve simultaneous file records and a done lose nothing" '[[ "$(m "[.state.deviations[] | select(.kind == \"undeclared-file\")] | length")" == 12 && "$(m ".state.issues[0].status")" == done ]]'
check "parallel writers: the state file is still valid JSON" 'jq -e . "$CLAUDE_GOAL_DIR/sess-par.json" >/dev/null'

echo ""
echo "goal-tracking regression: $PASS passed, $FAILN failed"
[ "$FAILN" -eq 0 ] || exit 1
