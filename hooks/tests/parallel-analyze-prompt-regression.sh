#!/usr/bin/env bash
# parallel-analyze-prompt-regression.sh — regression suite for hooks/parallel-analyze-prompt.sh
# ─────────────────────────────────────────────────────────────────────────────
# UserPromptSubmit reminder (context diet, 2026-11-10). The reminder is shown once per session on a
# task-shaped prompt; automated turns (subagent hand-backs, task notifications, system text) and
# non-task prompts get no reminder. Every case runs the hook on synthetic JSON with its own HOME and
# TMPDIR, so nothing reaches ~/.claude/global-observation or the real reminder markers.
#
# Usage:  bash hooks/tests/parallel-analyze-prompt-regression.sh
# Exit:   0 = all assertions pass, 1 = failures listed on stdout.
set -u
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
HOOK="$HOOKS_DIR/parallel-analyze-prompt.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/parallel-analyze-prompt-regression.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

PASS=0; FAIL=0; FAILURES=""
CASE_N=0; CASE_DIR=""; CASE_HOME=""; CASE_TMP=""
TASK_PROMPT="baue eine neue funktion in src/foo.ts fuer login"
PLAIN_PROMPT="Was ist der Stand?"

assert_eq() {  # description, expected, actual
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILURES="${FAILURES}  [$1] expected='$2' got='$3'\n"
    fi
}

new_case() {  # fresh HOME (log) and TMPDIR (markers) for each case
    CASE_N=$((CASE_N + 1))
    CASE_DIR="$SCRATCH/case-$CASE_N"
    CASE_HOME="$CASE_DIR/home"
    CASE_TMP="$CASE_DIR/tmp"
    mkdir -p "$CASE_HOME" "$CASE_TMP"
}

# run_prompt SESSION PROMPT -> OUT (stdout), RC (exit code). Inherited CLAUDE_PARALLEL_AUTO_SUGGEST is unset.
run_prompt() {
    OUT=$(printf '{"prompt":"%s","session_id":"%s"}' "$2" "$1" \
        | env -u CLAUDE_PARALLEL_AUTO_SUGGEST HOME="$CASE_HOME" TMPDIR="$CASE_TMP" \
            bash "$HOOK" 2>"$CASE_DIR/stderr")
    RC=$?
}

# run_json SESSION PROMPT -> OUT, RC: the payload is built with jq, so quotes, backslashes and newlines stay valid JSON
run_json() {
    OUT=$(jq -nc --arg p "$2" --arg s "$1" '{prompt: $p, session_id: $s}' \
        | env -u CLAUDE_PARALLEL_AUTO_SUGGEST HOME="$CASE_HOME" TMPDIR="$CASE_TMP" \
            bash "$HOOK" 2>"$CASE_DIR/stderr")
    RC=$?
}

# run_prompt_no_session PROMPT -> OUT, RC: a payload without session_id
run_prompt_no_session() {
    OUT=$(printf '{"prompt":"%s"}' "$1" \
        | env -u CLAUDE_PARALLEL_AUTO_SUGGEST HOME="$CASE_HOME" TMPDIR="$CASE_TMP" \
            bash "$HOOK" 2>"$CASE_DIR/stderr")
    RC=$?
}

LOG_FILE() { printf '%s' "$CASE_HOME/.claude/global-observation/parallel-prompts.jsonl"; }
log_count() {  # log_count PATTERN: number of log lines in this case matching PATTERN
    local f
    f=$(LOG_FILE)
    if [ -f "$f" ]; then grep -c -- "$1" "$f" || true; else printf '0'; fi
}
marker() {  # marker SESSION: the once-marker path for this session and hook
    printf '%s' "$CASE_TMP/claude-prompt-reminders/$1.parallel-analyze-prompt"
}
has_reminder() {  # has_reminder OUT: 1 when OUT is the Pre-Flight reminder JSON
    printf '%s' "$1" | jq -e '.hookSpecificOutput.additionalContext | contains("Pre-Flight")' >/dev/null 2>&1 \
        && printf '1' || printf '0'
}
exists() { if [ -e "$1" ]; then printf '1'; else printf '0'; fi; }

# ═══════════════════════════════════════════════════════════════════════════
# A) the first task-shaped prompt of a session gets the reminder; the second one does not
# ═══════════════════════════════════════════════════════════════════════════
new_case
run_prompt "s-first" "$TASK_PROMPT"
assert_eq "first task prompt: reminder emitted" 1 "$(has_reminder "$OUT")"
assert_eq "first task prompt: rc 0" 0 "$RC"
assert_eq "first task prompt: log line fired 1" 1 "$(log_count '"fired":1')"
assert_eq "first task prompt: once-marker written under TMPDIR" 1 "$(exists "$(marker s-first)")"

run_prompt "s-first" "baue eine neue funktion in src/bar.ts fuer logout"
assert_eq "same session, second task prompt: silent" "" "$OUT"
assert_eq "same session, second task prompt: rc 0" 0 "$RC"
assert_eq "same session, second task prompt: log line already-shown" 1 "$(log_count 'already-shown')"
assert_eq "same session, second task prompt: no second fired line" 1 "$(log_count '"fired":1')"

# ═══════════════════════════════════════════════════════════════════════════
# B) once per session_id: another session still gets its first reminder
# ═══════════════════════════════════════════════════════════════════════════
new_case
run_prompt "s-one" "$TASK_PROMPT"
run_prompt "s-two" "$TASK_PROMPT"
assert_eq "second session: its first task prompt gets the reminder" 1 "$(has_reminder "$OUT")"
assert_eq "two sessions: one marker each" 2 "$(ls "$CASE_TMP/claude-prompt-reminders" 2>/dev/null | wc -l | tr -d ' ')"

# ═══════════════════════════════════════════════════════════════════════════
# C) automated turns: silent, logged as fired 0, and no marker is written
# ═══════════════════════════════════════════════════════════════════════════
AUTO_TURNS=(
    '[Subagent hand-back] Report: baue eine neue funktion in src/foo.ts fuer login'
    '<task-notification> done: baue eine neue funktion in src/foo.ts fuer login'
    '[SYSTEM NOTIFICATION - NOT USER INPUT] baue eine neue funktion in src/foo.ts fuer login'
    '<system-reminder> baue eine neue funktion in src/foo.ts fuer login'
    '   <agent-message> baue eine neue funktion in src/foo.ts fuer login'
)
for i in "${!AUTO_TURNS[@]}"; do
    new_case
    run_prompt "s-auto-$i" "${AUTO_TURNS[$i]}"
    assert_eq "automated turn #$i: silent" "" "$OUT"
    assert_eq "automated turn #$i: rc 0" 0 "$RC"
    assert_eq "automated turn #$i: log line reason automated-turn" 1 "$(log_count 'automated-turn')"
    assert_eq "automated turn #$i: no once-marker written" 0 "$(exists "$(marker "s-auto-$i")")"
done

new_case
run_prompt "s-auto-then-user" "[Subagent hand-back] Report: baue eine neue funktion in src/foo.ts fuer login"
run_prompt "s-auto-then-user" "$TASK_PROMPT"
assert_eq "automated turn first, then the real task prompt: reminder still emitted" 1 "$(has_reminder "$OUT")"

# ═══════════════════════════════════════════════════════════════════════════
# D) non-task prompts: silent, no marker, no fired line
# ═══════════════════════════════════════════════════════════════════════════
new_case
run_prompt "s-plain" "$PLAIN_PROMPT"
assert_eq "non-task prompt: silent" "" "$OUT"
assert_eq "non-task prompt: rc 0" 0 "$RC"
assert_eq "non-task prompt: no once-marker" 0 "$(exists "$(marker s-plain)")"
assert_eq "non-task prompt: no fired 1 line" 0 "$(log_count '"fired":1')"

# A marker that appears mid-text is user content, not an automated turn: the prompt is judged on its task words
MID_MARKERS=('<system-reminder>' '[Subagent hand-back]' '<task-notification>' '[SYSTEM NOTIFICATION - NOT USER INPUT]' '<agent-message from="x">')
for m in "${MID_MARKERS[@]}"; do
    new_case
    run_json "s-mid" "Warum feuert der Hook bei $m nicht? baue eine neue funktion in src/foo.ts fuer login"
    assert_eq "marker mid-text ($m) is not an automated turn: reminder emitted" 1 "$(has_reminder "$OUT")"
done

# Umlaut task prompt under the live locale (hooks run with LANG=de_DE.UTF-8 and LC_ALL unset) and under C
for LOC in "LANG=de_DE.UTF-8 LC_ALL=" "LANG=C LC_ALL=C"; do
    new_case
    OUT=$(jq -nc --arg p 'Füge bitte Tests hinzu und ändere src/app.ts' --arg s "s-umlaut" '{prompt: $p, session_id: $s}' \
        | env -u CLAUDE_PARALLEL_AUTO_SUGGEST $LOC HOME="$CASE_HOME" TMPDIR="$CASE_TMP" bash "$HOOK" 2>"$CASE_DIR/stderr"); RC=$?
    assert_eq "umlaut task prompt ($LOC): reminder emitted" 1 "$(has_reminder "$OUT")"
    assert_eq "umlaut task prompt ($LOC): rc 0" 0 "$RC"
done

# A newline, a backslash and a double quote in the prompt: every log line still parses as JSON
new_case
ESC_PROMPT=$(printf 'baue eine neue funktion\nin src/foo.ts "quoted" mit C:\\pfad fuer login')
run_json "s-esc" "$ESC_PROMPT"
assert_eq "newline, quote and backslash prompt: reminder emitted" 1 "$(has_reminder "$OUT")"
assert_eq "newline, quote and backslash prompt: every log line parses as JSON" 1 "$(jq . "$(LOG_FILE)" >/dev/null 2>&1 && printf 1 || printf 0)"
assert_eq "newline, quote and backslash prompt: log sample is the prompt verbatim" "$ESC_PROMPT" "$(jq -r '.prompt_sample' "$(LOG_FILE)")"

# A once-marker that cannot be written: the reminder still goes out, the log says so
new_case
: > "$CASE_DIR/not-a-dir"
OUT=$(jq -nc '{prompt: "baue eine neue funktion in src/foo.ts fuer login", session_id: "s-unwritable"}' \
    | env -u CLAUDE_PARALLEL_AUTO_SUGGEST HOME="$CASE_HOME" TMPDIR="$CASE_DIR/not-a-dir" bash "$HOOK" 2>"$CASE_DIR/stderr"); RC=$?
assert_eq "unwritable once-marker: reminder still emitted" 1 "$(has_reminder "$OUT")"
assert_eq "unwritable once-marker: log line marker unwritable" 1 "$(log_count '"marker":"unwritable"')"
assert_eq "unwritable once-marker: stderr names the failure" 1 "$(grep -c 'cannot write' "$CASE_DIR/stderr" || true)"

# ═══════════════════════════════════════════════════════════════════════════
# E) opt-out and session id handling
# ═══════════════════════════════════════════════════════════════════════════
new_case
OUT=$(printf '{"prompt":"%s","session_id":"s-optout"}' "$TASK_PROMPT" \
    | env CLAUDE_PARALLEL_AUTO_SUGGEST=0 HOME="$CASE_HOME" TMPDIR="$CASE_TMP" bash "$HOOK" 2>/dev/null)
assert_eq "opt-out CLAUDE_PARALLEL_AUTO_SUGGEST=0: silent" "" "$OUT"
assert_eq "opt-out: no once-marker" 0 "$(exists "$(marker s-optout)")"

new_case
run_prompt "../escape" "$TASK_PROMPT"
assert_eq "unsafe session id: reminder emitted" 1 "$(has_reminder "$OUT")"
assert_eq "unsafe session id: marker name sanitised to 'escape'" 1 "$(exists "$(marker escape)")"

new_case
run_prompt_no_session "$TASK_PROMPT"
FIRST_OUT="$OUT"
run_prompt_no_session "baue eine neue funktion in src/bar.ts fuer logout"
assert_eq "no session_id: first task prompt emitted" 1 "$(has_reminder "$FIRST_OUT")"
assert_eq "no session_id: second task prompt emitted too (no marker)" 1 "$(has_reminder "$OUT")"
assert_eq "no session_id: no marker, so the reminder repeats (pre-diet behaviour)" 0 "$(ls "$CASE_TMP/claude-prompt-reminders" 2>/dev/null | wc -l | tr -d ' ')"

echo "── parallel-analyze-prompt-regression: $PASS passed, $FAIL failed ──"
if [ "$FAIL" -gt 0 ]; then
    printf "%b" "$FAILURES"
    exit 1
fi
exit 0
