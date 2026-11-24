#!/bin/bash
# knowledge-gate-regression.sh — regression suite for knowledge-gate.sh and knowledge-record.sh (IMP-267)
# ─────────────────────────────────────────────────────────────────────
# Covers gate decisions (deny, advisory, escalation, record / mirror-read /
# auto-inject allows, Bash-less agents, identity isolation, fail-open paths) and
# the record hook (prefilter, invocation parsing, usage errors, Glob patterns).
# Everything lives in a mktemp scratch dir; HOME is a scratch home, so no real
# ~/.claude file is read or written. Target paths sit under /opt, outside every
# exempt tmp location.
#
# Usage: bash hooks/tests/knowledge-gate-regression.sh
# ─────────────────────────────────────────────────────────────────────
set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$HOOKS_DIR/knowledge-gate.sh"
RECORDER="$HOOKS_DIR/knowledge-record.sh"
REAL_JQ="$(command -v jq)"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/knowledge-gate-regression.XXXXXX")"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

HOME_S="$SCRATCH/home"
LIB="$SCRATCH/knowledge"
STUB="$SCRATCH/knowledge-lookup-stub.sh"
AGENTS="$SCRATCH/agents"
STATE="$SCRATCH/state"
LOGF="$SCRATCH/gate.log"
FAKEBIN="$SCRATCH/fakebin"
TARGET="/opt/kg-regression-project/src/payment-service.ts"
mkdir -p "$HOME_S" "$LIB/mirror/memory" "$AGENTS" "$STATE" "$FAKEBIN"
printf '# Library\n' > "$LIB/mirror/README.md"
printf -- '---\nname: zsh modifier\n---\n» zsh modifier trap\n' > "$LIB/mirror/memory/zsh-modifier.md"
printf '#!/bin/bash\necho "stub $*"\n' > "$STUB"
chmod +x "$STUB"
printf -- '#!/bin/bash\n: > "%s"\nexec "%s" "$@"\n' "$SCRATCH/jq-called" "$REAL_JQ" > "$FAKEBIN/jq"
chmod +x "$FAKEBIN/jq"
printf -- '---\nname: research-agent\ntools: Read, Write, Grep, Glob\n---\nbody\n' > "$AGENTS/research-agent.md"
printf -- '---\nname: backend-agent\ntools:\n  - Read\n  - Bash\n  - Write\n---\nbody\n' > "$AGENTS/backend-agent.md"
printf -- '---\nname: code-reviewer-agent\ntools:\n  - Read\n  - Grep\n---\nbody\n' > "$AGENTS/code-reviewer-agent.md"
printf -- '---\nname: planning-agent\ntools: Read, Write, Bash(git:*)\n---\nbody\n' > "$AGENTS/planning-agent.md"
printf -- '---\nname: legacy-agent\ndescription: no tools key\n---\nbody\n' > "$AGENTS/legacy-agent.md"
printf -- '---\nname: zero-indent-agent\ntools:\n- Read\n- Grep\n---\nbody\n' > "$AGENTS/zero-indent-agent.md"
printf -- '---\nname: list-bash-agent\ntools:\n  - Read\n  - Bash(git:*)\n---\nbody\n' > "$AGENTS/list-bash-agent.md"
printf -- '---\nname: inline-bash-agent\ntools: Read, Bash\n---\nbody\n' > "$AGENTS/inline-bash-agent.md"
printf -- '---\nname: plugin-agent\ntools: Read, Grep\n---\nbody\n' > "$AGENTS/plug:research.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected: %s\n     got:      %s\n' "$1" "$2" "$3"; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
expect_has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "contains: $2" "$(printf '%s' "$3" | head -c 300)" ;; esac; }
expect_lacks() { case "$3" in *"$2"*) bad "$1" "does not contain: $2" "$(printf '%s' "$3" | head -c 300)" ;; *) ok "$1" ;; esac; }

# ── JSON builders ────────────────────────────────────────────────────
# pre_json <session> <tool> <path> [agent_id agent_type]
pre_json() {
    jq -nc --arg s "$1" --arg tool "$2" --arg p "$3" --arg a "${4:-}" --arg t "${5:-}" \
        '{session_id: $s, hook_event_name: "PreToolUse", tool_name: $tool, tool_input: {file_path: $p}}
         + (if $a == "" then {} else {agent_id: $a, agent_type: $t} end)'
}
# post_json <session> <tool> <tool_input-json> [agent_id agent_type]
post_json() {
    jq -nc --arg s "$1" --arg tool "$2" --argjson ti "$3" --arg a "${4:-}" --arg t "${5:-}" \
        '{session_id: $s, hook_event_name: "PostToolUse", tool_name: $tool, tool_input: $ti}
         + (if $a == "" then {} else {agent_id: $a, agent_type: $t} end)'
}
bash_input() { jq -nc --arg c "$1" '{command: $c}'; }
path_input() { jq -nc --arg p "$2" --arg k "$1" '{($k): $p}'; }

# ── runners ──────────────────────────────────────────────────────────
OUT=""; ERR=""; RC=0
# gate <json> [VAR=value ...]: runs the gate in a clean environment
gate() {
    local json="$1"; shift
    OUT=$(printf '%s' "$json" | env -i PATH="$PATH" HOME="$HOME_S" CLAUDE_KNOWLEDGE_DIR="$LIB" \
        CLAUDE_KNOWLEDGE_LOOKUP="$STUB" CLAUDE_AGENTS_DIR="$AGENTS" CLAUDE_KNOWLEDGE_STATE_ROOT="$STATE" \
        CLAUDE_KNOWLEDGE_GATE_LOG="$LOGF" "$@" bash "$GATE" 2>"$SCRATCH/err")
    RC=$?
    ERR=$(cat "$SCRATCH/err")
}
ROUT=""; RRC=0
# recorder <json> [VAR=value ...]: runs the PostToolUse record hook
recorder() {
    local json="$1"; shift
    ROUT=$(printf '%s' "$json" | env -i PATH="$PATH" HOME="$HOME_S" CLAUDE_KNOWLEDGE_DIR="$LIB" \
        CLAUDE_KNOWLEDGE_STATE_ROOT="$STATE" "$@" bash "$RECORDER" 2>/dev/null)
    RRC=$?
}
# seed_record <session> <identity> <kind>: writes a record line as the inject hook would
seed_record() {
    mkdir -p "$STATE/knowledge-gate-$1"
    printf '%s\t%s\t%s\n' "2026-10-31T10:00:00Z" "$3" "seeded" >> "$STATE/knowledge-gate-$1/record-$2.tsv"
}
# log_count <session> <event>
log_count() {
    [ -f "$LOGF" ] || { printf '0'; return; }
    awk -F '\t' -v s="$1" -v e="$2" '$2 == s && $5 == e { n++ } END { print n + 0 }' "$LOGF"
}
# log_detail_count <session> <event> <detail-substring>
log_detail_count() {
    [ -f "$LOGF" ] || { printf '0'; return; }
    awk -F '\t' -v s="$1" -v e="$2" -v d="$3" '$2 == s && $5 == e && index($6, d) > 0 { n++ } END { print n + 0 }' "$LOGF"
}
# log_agent_count <session> <agent_type>: lines with exactly six fields and this agent_type column
log_agent_count() {
    [ -f "$LOGF" ] || { printf '0'; return; }
    awk -F '\t' -v s="$1" -v a="$2" 'NF == 6 && $2 == s && $4 == a { n++ } END { print n + 0 }' "$LOGF"
}
# rec_count <session> <identity> <kind>
rec_count() {
    local f="$STATE/knowledge-gate-$1/record-$2.tsv"
    [ -f "$f" ] || { printf '0'; return; }
    awk -F '\t' -v k="$3" '$2 == k { n++ } END { print n + 0 }' "$f"
}
decision_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }
reason_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }
context_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty'; }

echo "── knowledge-gate.sh (PreToolUse) ──"

echo "1. non-Write tools are silent"
gate "$(pre_json s-read Read "$TARGET")"
expect_eq "Read: exit 0" 0 "$RC"
expect_eq "Read: no output" "" "$OUT"

echo "2. exempt paths are silent; '..' never exempts"
for p in /private/tmp/scratch.ts /opt/kg/.rcode/state.json /opt/kg/test/fixtures/data.json "$LIB/mirror/memory/x.md"; do
    gate "$(pre_json s-exempt Edit "$p")"
    expect_eq "exempt $p: exit 0 and silent" "0|" "$RC|$OUT"
done
gate "$(pre_json s-exempt-v Edit /private/tmp/scratch.ts)" CLAUDE_KNOWLEDGE_GATE_VERBOSE=1
expect_eq "exempt with VERBOSE=1 is logged" 1 "$(log_count s-exempt-v exempt)"
gate "$(pre_json s-dotdot Edit /tmp/../srv/kg/a.ts)"
expect_eq "/tmp/../srv path is not exempt: deny" "deny" "$(decision_of "$OUT")"
gate "$(pre_json s-dotdot2 Edit "$LIB/mirror/../x.md")"
expect_eq "mirror/../x.md is not exempt: deny" "deny" "$(decision_of "$OUT")"

echo "3. library or lookup missing: fail open, logged once"
gate "$(pre_json s-nolib Edit "$TARGET")" CLAUDE_KNOWLEDGE_DIR="$SCRATCH/no-such-library"
expect_eq "library missing: exit 0" 0 "$RC"
expect_eq "library missing: silent" "" "$OUT"
gate "$(pre_json s-nolib Edit "$TARGET")" CLAUDE_KNOWLEDGE_DIR="$SCRATCH/no-such-library"
expect_eq "library missing: logged once across two edits" 1 "$(log_count s-nolib library-missing)"
gate "$(pre_json s-nolookup Edit "$TARGET")" CLAUDE_KNOWLEDGE_LOOKUP="$SCRATCH/no-lookup.sh"
expect_eq "lookup script missing: silent and logged" "1|" "$(log_count s-nolookup library-missing)|$OUT"
gate "$(pre_json s-nokdir Edit "$TARGET")" CLAUDE_KNOWLEDGE_DIR=
expect_eq "no CLAUDE_KNOWLEDGE_DIR and no env.local.sh: logged, silent" "1|" "$(log_count s-nokdir library-missing)|$OUT"

echo "4. deny mode, no record: deny text and counter"
gate "$(pre_json s-deny Edit "$TARGET")"
R=$(reason_of "$OUT")
expect_eq "first attempt: exit 0" 0 "$RC"
expect_eq "first attempt: permissionDecision deny" "deny" "$(decision_of "$OUT")"
expect_has "reason names the gate" "Knowledge gate (IMP-267)" "$R"
expect_has "reason has the exact lookup command" 'bash ~/.claude/scripts/knowledge-lookup.sh --max 6 "<your own words>" --alt "<German/English translation>" --alt "<technical terms>"' "$R"
expect_has "reason has the judge sentence" "judge by the » lines, open only the top note's section" "$R"
expect_has "reason names the mirror Read hint" "$LIB/mirror/ also counts" "$R"
expect_has "reason suggests path keywords" "payment, service" "$R"
expect_has "reason states denial 1 of 3" "denial 1 of 3" "$R"
expect_eq "reason is at most 900 characters" "yes" "$([ "$(printf '%s' "$R" | jq -Rs 'length')" -le 900 ] && printf yes || printf no)"
expect_eq "denial counter is 1" 1 "$(cat "$STATE/knowledge-gate-s-deny/denials-main")"
expect_eq "deny is logged" 1 "$(log_count s-deny deny)"

echo "5. denials 2 and 3 still deny"
gate "$(pre_json s-deny Edit "$TARGET")"
expect_eq "second attempt: deny" "deny" "$(decision_of "$OUT")"
expect_has "second attempt: denial 2 of 3" "denial 2 of 3" "$(reason_of "$OUT")"
gate "$(pre_json s-deny Edit "$TARGET")"
expect_eq "third attempt: deny" "deny" "$(decision_of "$OUT")"
expect_has "third attempt: denial 3 of 3" "denial 3 of 3" "$(reason_of "$OUT")"

echo "6. fourth attempt escalates; from the fifth on the edit is silent and logged with its count"
gate "$(pre_json s-deny Edit "$TARGET")"
expect_eq "fourth attempt: exit 0" 0 "$RC"
expect_eq "fourth attempt: no deny" "" "$(decision_of "$OUT")"
expect_has "fourth attempt: ESCALATION context" "ESCALATION (knowledge gate, IMP-267): edit allowed after 3 denials" "$(context_of "$OUT")"
expect_eq "fourth attempt: escalation logged" 1 "$(log_count s-deny escalation)"
gate "$(pre_json s-deny Edit "$TARGET")"
expect_eq "fifth attempt: exit 0 and no stdout" "0|" "$RC|$OUT"
expect_eq "fifth attempt: logged as denial 5, allowed" 1 "$(log_detail_count s-deny escalation "denial 5, allowed")"

echo "7. advisory mode never denies"
for _ in 1 2 3 4; do gate "$(pre_json s-adv Edit "$TARGET")" CLAUDE_KNOWLEDGE_GATE=advisory; done
expect_eq "advisory: no permissionDecision after four attempts" "" "$(decision_of "$OUT")"
expect_has "advisory: additionalContext carries the text" "Knowledge gate (IMP-267)" "$(context_of "$OUT")"
expect_eq "advisory: logged" 4 "$(log_count s-adv advisory)"

echo "8. lookup recorded by the record hook allows silently, logged once"
recorder "$(post_json s-rec Bash "$(bash_input 'bash ~/.claude/scripts/knowledge-lookup.sh --max 6 "payment service"')")"
gate "$(pre_json s-rec Edit "$TARGET")"
expect_eq "agent-lookup record: exit 0 and silent" "0|" "$RC|$OUT"
gate "$(pre_json s-rec Edit "$TARGET")"
expect_eq "agent-lookup record: allow-record logged once" 1 "$(log_count s-rec allow-record)"

echo "9. mirror read satisfies the gate"
recorder "$(post_json s-mirror Read "$(path_input file_path "$LIB/mirror/memory/zsh-modifier.md")")"
gate "$(pre_json s-mirror Edit "$TARGET")"
expect_eq "mirror-read record: silent" "0|" "$RC|$OUT"

echo "10. auto-inject with a Bash-less agent_type allows; Bash agents deny"
seed_record s-inj research-agent-id auto-inject
gate "$(pre_json s-inj Edit "$TARGET" research-agent-id research-agent)"
expect_eq "research-agent (no Bash, inline tools): silent" "0|" "$RC|$OUT"
expect_eq "research-agent: allow-bashless logged" 1 "$(log_count s-inj allow-bashless)"
seed_record s-inj reviewer-id auto-inject
gate "$(pre_json s-inj Edit "$TARGET" reviewer-id code-reviewer-agent)"
expect_eq "code-reviewer-agent (no Bash, list tools): silent" "0|" "$RC|$OUT"
seed_record s-inj zi-id auto-inject
gate "$(pre_json s-inj Edit "$TARGET" zi-id zero-indent-agent)"
expect_eq "zero-indent list without Bash: Bash-less, silent" "0|" "$RC|$OUT"
seed_record s-inj plug-id auto-inject
gate "$(pre_json s-inj Edit "$TARGET" plug-id plug:research)"
expect_eq "colon in agent_type (plugin agent) is accepted: Bash-less, silent" "0|" "$RC|$OUT"

echo "11. auto-inject with an agent that has Bash denies"
seed_record s-inj-bash backend-id auto-inject
gate "$(pre_json s-inj-bash Edit "$TARGET" backend-id backend-agent)"
expect_eq "backend-agent (list tools with Bash): deny" "deny" "$(decision_of "$OUT")"
seed_record s-inj-bash planner-id auto-inject
gate "$(pre_json s-inj-bash Edit "$TARGET" planner-id planning-agent)"
expect_eq "planning-agent (Bash(git:*) inline): deny" "deny" "$(decision_of "$OUT")"
seed_record s-inj-bash lbash-id auto-inject
gate "$(pre_json s-inj-bash Edit "$TARGET" lbash-id list-bash-agent)"
expect_eq "Bash(git:*) as a list item: deny" "deny" "$(decision_of "$OUT")"
seed_record s-inj-bash ibash-id auto-inject
gate "$(pre_json s-inj-bash Edit "$TARGET" ibash-id inline-bash-agent)"
expect_eq "inline 'tools: Read, Bash': deny" "deny" "$(decision_of "$OUT")"
seed_record s-inj-bash legacy-id auto-inject
gate "$(pre_json s-inj-bash Edit "$TARGET" legacy-id legacy-agent)"
expect_eq "legacy-agent (no tools key, so all tools): deny" "deny" "$(decision_of "$OUT")"
seed_record s-inj-bash explore-id auto-inject
gate "$(pre_json s-inj-bash Edit "$TARGET" explore-id Explore)"
expect_eq "Explore (built-in, no file): deny" "deny" "$(decision_of "$OUT")"
seed_record s-inj-bash main auto-inject
gate "$(pre_json s-inj-bash Edit "$TARGET")"
expect_eq "main with auto-inject is never Bash-less: deny" "deny" "$(decision_of "$OUT")"
gate "$(pre_json s-tab Edit "$TARGET" tab-id "$(printf 'research-agent\tx')")"
expect_eq "agent_type with a tab: logged with the tab removed" 1 "$(log_agent_count s-tab research-agentx)"

echo "12. identity isolation"
recorder "$(post_json s-iso Bash "$(bash_input 'bash ~/.claude/scripts/knowledge-lookup.sh --max 6 "x"')")"
gate "$(pre_json s-iso Edit "$TARGET" sub-x backend-agent)"
expect_eq "subagent with only main's record: deny" "deny" "$(decision_of "$OUT")"
expect_has "subagent denial names the subagent" "for sub-x" "$(reason_of "$OUT")"
recorder "$(post_json s-iso Bash "$(bash_input 'bash ~/.claude/scripts/knowledge-lookup.sh --stack')" sub-y backend-agent)"
gate "$(pre_json s-iso Edit "$TARGET" sub-y backend-agent)"
expect_eq "subagent with its own lookup record: silent" "0|" "$RC|$OUT"
recorder "$(post_json s-iso2 Bash "$(bash_input 'bash ~/.claude/scripts/knowledge-lookup.sh --stack')" 'sub/x' backend-agent)"
gate "$(pre_json s-iso2 Edit "$TARGET" 'sub/x' backend-agent)"
expect_eq "agent_id with a slash: record written and read under the same name" "0|" "$RC|$OUT"
recorder "$(post_json s-iso3 Bash "$(bash_input 'bash ~/.claude/scripts/knowledge-lookup.sh --stack')")"
gate "$(pre_json s-iso3 Edit "$TARGET" '!!!' backend-agent)"
expect_eq "agent_id that sanitises to nothing does not borrow main's record: deny" "deny" "$(decision_of "$OUT")"

echo "13. mode off and unknown mode"
gate "$(pre_json s-off Edit "$TARGET")" CLAUDE_KNOWLEDGE_GATE=off
gate "$(pre_json s-off Edit "$TARGET")" CLAUDE_KNOWLEDGE_GATE=off
expect_eq "off: exit 0 and silent" "0|" "$RC|$OUT"
expect_eq "off: logged once per session" 1 "$(log_count s-off off)"
gate "$(pre_json s-bogus Edit "$TARGET")" CLAUDE_KNOWLEDGE_GATE=bogus
expect_eq "unknown mode: falls back to deny" "deny" "$(decision_of "$OUT")"
expect_has "unknown mode: warns on stderr" "unknown CLAUDE_KNOWLEDGE_GATE=bogus" "$ERR"

echo "14. MultiEdit is gated; empty input and unwritable state fail open"
gate "$(pre_json s-multi MultiEdit "$TARGET")"
expect_eq "MultiEdit without record: deny" "deny" "$(decision_of "$OUT")"
gate '{}'
expect_eq "empty object: exit 0, no output" "0|" "$RC|$OUT"
printf 'not a directory' > "$SCRATCH/state-as-file"
gate "$(pre_json s-fail Edit "$TARGET")" CLAUDE_KNOWLEDGE_STATE_ROOT="$SCRATCH/state-as-file"
expect_eq "unwritable state root: exit 0, silent" "0|" "$RC|$OUT"
expect_has "unwritable state root: reports fail-open on stderr" "fail open" "$ERR"

echo "15. Bash-less deny text: Read or Grep, never 'run bash'"
gate "$(pre_json s-bl Edit "$TARGET" bl-id research-agent)"
R=$(reason_of "$OUT")
expect_eq "Bash-less without record: deny" "deny" "$(decision_of "$OUT")"
expect_has "Bash-less text asks for Read or Grep" "Read or Grep one note under $LIB/mirror/" "$R"
expect_lacks "Bash-less text does not say 'run bash'" "run bash" "$R"
expect_lacks "Bash-less text does not carry the lookup command" "bash ~/.claude/scripts/knowledge-lookup.sh" "$R"
expect_has "Bash-less text keeps the judge sentence" "judge by the » lines, open only the top note's section" "$R"

echo "16. exempt paths are decided before the env.local.sh subshell"
mkdir -p "$HOME_S/.claude"
printf 'touch "%s"\n' "$SCRATCH/sourced-marker" > "$HOME_S/.claude/env.local.sh"
gate "$(pre_json s-hot Edit /private/tmp/scratch.ts)" CLAUDE_KNOWLEDGE_DIR=
expect_eq "exempt path: env.local.sh not sourced (marker absent)" "absent" "$([ -e "$SCRATCH/sourced-marker" ] && printf present || printf absent)"
gate "$(pre_json s-hot Edit "$TARGET")" CLAUDE_KNOWLEDGE_DIR=
expect_eq "non-exempt path: env.local.sh is sourced (marker present)" "present" "$([ -e "$SCRATCH/sourced-marker" ] && printf present || printf absent)"
rm -f "$HOME_S/.claude/env.local.sh"

echo "17. hook headers cite no private memo path and no session counts"
HYG=$(grep -l -e 'knowledge-reach-decision' -e ' 585 ' -e ' 598 ' -e 'decision memo' "$GATE" "$RECORDER" "$HOOKS_DIR/knowledge-brief-check.sh" "$HOOKS_DIR/knowledge-inject.sh" 2>/dev/null)
expect_eq "no private memo path, session count or 'decision memo' in the four hook files" "" "$HYG"
expect_has "gate header states the measured non-use with its date" "measured non-use of the lookup (2026-10-31)." "$(sed -n 6p "$GATE")"
echo "── knowledge-record.sh (PostToolUse) ──"

echo "18. record hook writes evidence"
recorder "$(post_json s-r1 Bash "$(bash_input 'bash ~/.claude/scripts/knowledge-lookup.sh --max 6 "zsh"')")"
expect_eq "Bash lookup: agent-lookup line written" 1 "$(rec_count s-r1 main agent-lookup)"
expect_eq "Bash lookup: prints nothing" "0|" "$RRC|$ROUT"
recorder "$(post_json s-r2 Bash "$(bash_input 'bash ~/.claude/scripts/knowledge-lookup.sh --help')")"
expect_eq "Bash --help: nothing written" 0 "$(rec_count s-r2 main agent-lookup)"
recorder "$(post_json s-r3 Bash "$(bash_input 'ls -la /opt')")"
expect_eq "unrelated Bash: nothing written" 0 "$(rec_count s-r3 main agent-lookup)"
recorder "$(post_json s-rh Bash "$(bash_input 'bash ~/.claude/scripts/knowledge-lookup.sh --stack prefix--helpers')")"
expect_eq "--help inside a keyword (prefix--helpers) is not a usage query: recorded" 1 "$(rec_count s-rh main agent-lookup)"
recorder "$(post_json s-rh2 Bash "$(bash_input 'bash ~/.claude/scripts/knowledge-lookup.sh zsh --help')")"
expect_eq "--help as a separate token at the end: nothing written" 0 "$(rec_count s-rh2 main agent-lookup)"
recorder "$(post_json s-r4 Read "$(path_input file_path "$LIB/mirror/memory/zsh-modifier.md")")"
expect_eq "Read under mirror: mirror-read written" 1 "$(rec_count s-r4 main mirror-read)"
recorder "$(post_json s-r5 Read "$(path_input file_path /opt/kg-regression-project/README.md)")"
expect_eq "Read elsewhere: nothing written" 0 "$(rec_count s-r5 main mirror-read)"
recorder "$(post_json s-r6 Read "$(path_input file_path "$LIB/mirror-evil/x.md")")"
expect_eq "Read of a sibling named mirror-evil: nothing written" 0 "$(rec_count s-r6 main mirror-read)"
recorder "$(post_json s-r7 Grep "$(path_input path "$LIB/mirror")")"
expect_eq "Grep with mirror path: mirror-read written" 1 "$(rec_count s-r7 main mirror-read)"
recorder "$(post_json s-r8 Read "$(path_input file_path "$LIB/mirror/memory/zsh-modifier.md")" sub-z backend-agent)"
expect_eq "subagent mirror read goes to its own record" 1 "$(rec_count s-r8 sub-z mirror-read)"
expect_eq "subagent mirror read leaves main's record alone" 0 "$(rec_count s-r8 main mirror-read)"
recorder "$(post_json s-r9 Read "$(path_input file_path "$LIB/mirror/memory/zsh-modifier.md")")" CLAUDE_KNOWLEDGE_DIR=
expect_eq "no library dir: mirror read not recorded" 0 "$(rec_count s-r9 main mirror-read)"
recorder '{}'
expect_eq "empty object: exit 0 and no output" "0|" "$RRC|$ROUT"

echo "19. prefilter: a plain Bash input never reaches jq"
rm -f "$SCRATCH/jq-called"
recorder "$(post_json s-ls Bash "$(bash_input 'ls -la /opt')")" PATH="$FAKEBIN:$PATH"
expect_eq "plain ls: exit 0, nothing recorded" "0|0" "$RRC|$(rec_count s-ls main agent-lookup)"
expect_eq "plain ls: jq not invoked" "absent" "$([ -e "$SCRATCH/jq-called" ] && printf present || printf absent)"
recorder "$(post_json s-ls2 Bash "$(bash_input 'bash ~/.claude/scripts/knowledge-lookup.sh --stack')")" PATH="$FAKEBIN:$PATH"
expect_eq "positive control: lookup input does reach jq" "present" "$([ -e "$SCRATCH/jq-called" ] && printf present || printf absent)"

echo "20. invocation parsing"
# lookup_case <expected 0|1> <name> <command>: fresh session per case, then count agent-lookup lines
SEQ=0
lookup_case() {
    SEQ=$((SEQ+1))
    local sid="s-cmd-$SEQ"
    recorder "$(post_json "$sid" Bash "$(bash_input "$3")")"
    expect_eq "$2" "$1" "$(rec_count "$sid" main agent-lookup)"
}
lookup_case 1 "plain invocation (bare name)" 'knowledge-lookup.sh --stack'
lookup_case 1 "bash ~/.claude/scripts/knowledge-lookup.sh --stack" 'bash ~/.claude/scripts/knowledge-lookup.sh --stack'
lookup_case 1 "LC_ALL=C bash ...knowledge-lookup.sh" 'LC_ALL=C bash ~/.claude/scripts/knowledge-lookup.sh --stack'
lookup_case 1 "cd /x && bash scripts/knowledge-lookup.sh foo" 'cd /x && bash scripts/knowledge-lookup.sh foo'
lookup_case 1 "timeout 10 bash ...knowledge-lookup.sh" 'timeout 10 bash ~/.claude/scripts/knowledge-lookup.sh foo'
# shellcheck disable=SC2016
lookup_case 1 "\$HOME path after pipe" 'cat notes.txt | bash $HOME/.claude/scripts/knowledge-lookup.sh zsh'
lookup_case 1 "./scripts path after semicolon" 'git status; ./scripts/knowledge-lookup.sh x'
lookup_case 1 "quoted path is still an invocation" 'bash "~/.claude/scripts/knowledge-lookup.sh" --stack'
lookup_case 0 "negative: grep -n names the script" 'grep -n foo scripts/knowledge-lookup.sh'
lookup_case 0 "negative: echo quotes the name" 'echo "run knowledge-lookup.sh"'
lookup_case 0 "negative: bash -n (syntax check)" 'bash -n scripts/knowledge-lookup.sh'
lookup_case 0 "negative: shellcheck" 'shellcheck scripts/knowledge-lookup.sh'
lookup_case 0 "negative: git log -- path" 'git log -- scripts/knowledge-lookup.sh'
lookup_case 0 "negative: cat and sed name the script" 'cat scripts/knowledge-lookup.sh; sed -n 1,5p scripts/knowledge-lookup.sh'
lookup_case 0 "negative: quoted separator does not open a segment" 'echo "x; knowledge-lookup.sh"'
lookup_case 0 "negative: --help still excluded" 'cd /x && bash scripts/knowledge-lookup.sh --help'
echo "  heredoc, wrappers, escapes:"
lookup_case 0 "heredoc body naming the script is data" $'cat <<EOF\nbash ~/.claude/scripts/knowledge-lookup.sh --stack\nEOF'
lookup_case 0 "quoted tab-indented heredoc body (<<-'EOT') is data" $'cat <<-\'EOT\'\n\tbash ~/x/knowledge-lookup.sh zsh\n\tEOT'
lookup_case 1 "invocation after a heredoc terminator counts" $'cat <<EOF\nnotes\nEOF\nbash ~/x/knowledge-lookup.sh zsh'
lookup_case 1 "env LC_ALL=C bash ...knowledge-lookup.sh x" 'env LC_ALL=C bash ~/.claude/scripts/knowledge-lookup.sh x'
lookup_case 1 "time bash ...knowledge-lookup.sh x" 'time bash ~/.claude/scripts/knowledge-lookup.sh x'
lookup_case 1 "bash -x ...knowledge-lookup.sh x" 'bash -x ~/.claude/scripts/knowledge-lookup.sh x'
lookup_case 0 "escaped quotes do not open a quote: echo says it" 'echo "say \"knowledge-lookup.sh\""'
echo "  usage errors:"
lookup_case 0 "bash …knowledge-lookup.sh --max 6 (no keyword) is a usage error" 'bash ~/.claude/scripts/knowledge-lookup.sh --max 6'
lookup_case 1 "bash …knowledge-lookup.sh --stack counts" 'bash ~/.claude/scripts/knowledge-lookup.sh --stack'
lookup_case 1 "--alt alone counts" 'bash ~/.claude/scripts/knowledge-lookup.sh --max 6 --alt "zsh"'

echo "21. Glob pattern under the mirror (no path) is a mirror read"
recorder "$(post_json s-glob Glob "$(jq -nc --arg p "$LIB/mirror/**/*.md" '{pattern: $p}')")"
expect_eq "Glob pattern under mirror: mirror-read written" 1 "$(rec_count s-glob main mirror-read)"
recorder "$(post_json s-glob2 Glob "$(jq -nc '{pattern: "/opt/kg-regression-project/**/*.ts"}')")"
expect_eq "Glob pattern elsewhere: nothing written" 0 "$(rec_count s-glob2 main mirror-read)"

echo "22. German UTF-8 locale (LANG=de_DE.UTF-8): umlauts in commands, paths and records"
# The runners clear the environment, so every case above runs in the C locale; the live hooks inherit
# the user's LANG. Found 2026-11-01: awk aborted on an umlaut command and the lookup went unrecorded.
UML_CMD='bash ~/.claude/scripts/knowledge-lookup.sh --max 6 "Änderungsprotokoll" --alt "Veröffentlichung Übersicht"'
recorder "$(post_json s-de Bash "$(bash_input "$UML_CMD")")" LANG=de_DE.UTF-8
expect_eq "umlaut lookup under de_DE.UTF-8: agent-lookup written" 1 "$(rec_count s-de main agent-lookup)"
gate "$(pre_json s-de Edit "$TARGET")" LANG=de_DE.UTF-8
expect_eq "gate under de_DE.UTF-8 reads the umlaut record: silent allow" "0|" "$RC|$OUT"
gate "$(pre_json s-de-path Edit "/opt/kg/Übersicht/Änderungen-service.ts")" LANG=de_DE.UTF-8
expect_eq "umlaut target path under de_DE.UTF-8: deny, exit 0" "deny|0" "$(decision_of "$OUT")|$RC"
expect_has "umlaut target path: keywords from the ASCII parts" "service" "$(reason_of "$OUT")"
recorder "$(post_json s-de-long Bash "$(bash_input "bash ~/.claude/scripts/knowledge-lookup.sh --stack $(printf 'ä%.0s' $(seq 1 60))")")" LANG=de_DE.UTF-8
expect_eq "long umlaut command: recorded" 1 "$(rec_count s-de-long main agent-lookup)"
DETAIL=$(LC_ALL=C awk -F '\t' '$2 == "agent-lookup" { print $3 }' "$STATE/knowledge-gate-s-de-long/record-main.tsv")
expect_eq "long umlaut command: detail cut to at most 120 bytes" "yes" "$([ "$(printf '%s' "$DETAIL" | LC_ALL=C wc -c | tr -d ' ')" -le 120 ] && printf yes || printf no)"
expect_eq "long umlaut command: the byte cut never splits a character (valid UTF-8)" "yes" "$(printf '%s' "$DETAIL" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 && printf yes || printf no)"

echo "23. lead-supplied record (IMP-268): allowed for every agent type, logged once per identity"
seed_record s-lead lead-id lead-supplied
gate "$(pre_json s-lead Edit "$TARGET" lead-id backend-agent)"
expect_eq "lead-supplied, Bash agent (backend-agent): silent allow" "0|" "$RC|$OUT"
gate "$(pre_json s-lead Edit "$TARGET" lead-id backend-agent)"
expect_eq "lead-supplied: allow-lead-supplied logged once across two edits" 1 "$(log_count s-lead allow-lead-supplied)"
seed_record s-lead-bl bl-id lead-supplied
gate "$(pre_json s-lead-bl Edit "$TARGET" bl-id research-agent)"
expect_eq "lead-supplied, Bash-less agent (research-agent): silent allow" "0|" "$RC|$OUT"
seed_record s-lead-main main lead-supplied
gate "$(pre_json s-lead-main Edit "$TARGET")"
expect_eq "lead-supplied, main: silent allow" "0|" "$RC|$OUT"
gate "$(pre_json s-lead Edit "$TARGET" other-id backend-agent)"
expect_eq "lead-supplied record of another identity does not count: deny" "deny" "$(decision_of "$OUT")"

echo "24. knowledge-agent lookups file (IMP-268): one line per knowledge-agent search"
KAL() { printf '%s' "$STATE/knowledge-gate-$1/knowledge-agent-lookups"; }
file_lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else printf '0'; fi; }
recorder "$(post_json s-ka Bash "$(bash_input 'bash ~/.claude/scripts/knowledge-lookup.sh --max 6 "payment"')" ka-1 knowledge-agent)"
expect_eq "knowledge-agent lookup (agent_type in the input): one line" 1 "$(file_lines "$(KAL s-ka)")"
expect_eq "knowledge-agent lookup: first field is ISO-8601 UTC" "yes" "$(awk -F '\t' 'NR == 1 && $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ { print "yes" }' "$(KAL s-ka)")"
expect_eq "knowledge-agent lookup: second field is the agent id" "ka-1" "$(awk -F '\t' 'NR == 1 { print $2 }' "$(KAL s-ka)")"
expect_eq "knowledge-agent lookup: the agent's own record still gets agent-lookup" 1 "$(rec_count s-ka ka-1 agent-lookup)"
expect_eq "knowledge-agent lookups file is mode 0600" 600 "$(stat -f %Lp "$(KAL s-ka)" 2>/dev/null || stat -c %a "$(KAL s-ka)")"
mkdir -p "$STATE/knowledge-gate-s-kam"
printf 'knowledge-agent\n' > "$STATE/knowledge-gate-s-kam/agent-type-ka-2"
recorder "$(jq -nc '{session_id: "s-kam", tool_name: "Bash", tool_input: {command: "bash ~/.claude/scripts/knowledge-lookup.sh --stack"}, agent_id: "ka-2"}')"
expect_eq "agent_type absent from the input, marker says knowledge-agent: one line" 1 "$(file_lines "$(KAL s-kam)")"
expect_eq "marker fallback: second field is ka-2" "ka-2" "$(awk -F '\t' 'NR == 1 { print $2 }' "$(KAL s-kam)")"
recorder "$(post_json s-kb Bash "$(bash_input 'bash ~/.claude/scripts/knowledge-lookup.sh --stack')" kb-1 backend-agent)"
expect_eq "backend-agent lookup: no knowledge-agent-lookups line" 0 "$(file_lines "$(KAL s-kb)")"
recorder "$(jq -nc '{session_id: "s-kc", tool_name: "Bash", tool_input: {command: "bash ~/.claude/scripts/knowledge-lookup.sh --stack"}, agent_id: "ka-3"}')"
expect_eq "agent_id with no agent_type and no marker: no knowledge-agent line" 0 "$(file_lines "$(KAL s-kc)")"
recorder "$(post_json s-kd Bash "$(bash_input 'ls -la /opt')" ka-4 knowledge-agent)"
expect_eq "knowledge-agent, unrelated Bash: no line" 0 "$(file_lines "$(KAL s-kd)")"

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
