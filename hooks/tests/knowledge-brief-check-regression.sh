#!/bin/bash
# knowledge-brief-check-regression.sh — regression suite for knowledge-brief-check.sh and lib/knowledge-brief.sh (IMP-268)
# ─────────────────────────────────────────────────────────────────────
# Covers the parser (marker, fences, CRLF, verdict classes, citations, excerpts, sets), the
# decision kb_decide (cited resolution and excerpts, none and unavailable windows, deny texts),
# the hook's denial ladder, advisory and off modes, exemptions and every fail-open log line.
# Everything lives in a mktemp scratch dir and a scratch HOME; no real library, state or log.
#
# Usage: bash hooks/tests/knowledge-brief-check-regression.sh
# ─────────────────────────────────────────────────────────────────────
set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/knowledge-brief-check.sh"
LIBF="$HOOKS_DIR/lib/knowledge-brief.sh"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/knowledge-brief-regression.XXXXXX")"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

HOME_S="$SCRATCH/home"
LIB="$SCRATCH/knowledge"
STATE="$SCRATCH/state"
LOGF="$SCRATCH/brief.log"
mkdir -p "$HOME_S/notes" "$HOME_S/kb/mirror/rules" "$LIB/mirror/rules" "$LIB/mirror/ledger" "$STATE" "$SCRATCH/abs"
printf '# Library\n' > "$LIB/mirror/README.md"
printf '%s\n' '# Sample rule' 'The rule text.' 'a verbatim excerpt from the sample rule text' \
    'ein ausreichend langer Auszug aus der Regel' 'a long enough verbatim excerpt here' \
    'Übersicht der Veröffentlichung, mit Umlauten im Auszug' 'present excerpt, long enough here' \
    'none relevant wording inside the excerpt, long enough' > "$LIB/mirror/rules/sample-rule.md"
printf '%s\n' 'Band matrix: AUTO, SOFT-ACK and ESCALATE for irreversible operations' > "$LIB/mirror/rules/bands.md"
printf '%s\n' '# Wrapped' 'The quick brown fox' 'jumps over the lazy dog every day.' > "$LIB/mirror/rules/wrapped-rule.md"
printf '# IMP-001\n' > "$LIB/mirror/ledger/IMP-001.md"
printf '%s\n' '# Home note' 'the home note excerpt, long enough for the check' > "$HOME_S/notes/home-note.md"
printf '%s\n' '# Absolute note' 'a long enough verbatim excerpt here' > "$SCRATCH/abs/abs-note.md"
printf '# Home rule\nthe home note excerpt, long enough for the check\n' > "$HOME_S/kb/mirror/rules/home-rule.md"
printf '# Library\n' > "$HOME_S/kb/mirror/README.md"
ln -s "$SCRATCH/abs/abs-note.md" "$LIB/mirror/rules/link-out.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected: %s\n     got:      %s\n' "$1" "$2" "$3"; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
expect_has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "contains: $2" "$(printf '%s' "$3" | head -c 300)" ;; esac; }
expect_lacks() { case "$3" in *"$2"*) bad "$1" "does not contain: $2" "$(printf '%s' "$3" | head -c 300)" ;; *) ok "$1" ;; esac; }

# ── builders ─────────────────────────────────────────────────────────
# task_json <session> <tool> <subagent_type> <description> <prompt>
task_json() {
    jq -nc --arg s "$1" --arg t "$2" --arg sub "$3" --arg d "$4" --arg p "$5" \
        '{session_id: $s, hook_event_name: "PreToolUse", tool_name: $t, tool_input: {subagent_type: $sub, description: $d, prompt: $p}}'
}
# with_block <block>: a dispatch prompt with the block set off by blank lines
with_block() {
    printf 'Unit: write the parser for the brief field.\n\n%s\n\nTask: implement it and report back.\n' "$1"
}
# iso_ago <seconds>: UTC timestamp this many seconds in the past (BSD and GNU date)
iso_ago() {
    local epoch=$(( $(date -u +%s) - $1 ))
    date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ
}
# seed_lookup <session> <iso> [agent id]: one knowledge-agent run line, as knowledge-record.sh writes it;
# without an id every call is a new run (a distinct agent id)
SEED_N=0
seed_lookup() {
    mkdir -p "$STATE/knowledge-gate-$1"
    SEED_N=$((SEED_N + 1))
    printf '%s\t%s\n' "$2" "${3:-ka-$SEED_N}" >> "$STATE/knowledge-gate-$1/knowledge-agent-lookups"
}
# seed_fresh <session> <count>: <count> fresh search lines
seed_fresh() {
    local _
    for _ in $(seq 1 "$2"); do seed_lookup "$1" "$(iso_ago 0)"; done
}
# seed_dispatch <session> [iso]: a knowledge-agent dispatch mark, as the hook writes it
seed_dispatch() {
    mkdir -p "$STATE/knowledge-gate-$1"
    printf '%s\t%s\n' "${2:-$(iso_ago 0)}" "knowledge-agent" >> "$STATE/knowledge-gate-$1/knowledge-agent-dispatches"
}

P_MISSING=$(with_block "")
P_CITED=$(with_block 'KNOWLEDGE (lead-supplied): sets: "brief gate" | "knowledge field"; rules/sample-rule.md L3: "a verbatim excerpt from the sample rule text"')
P_NONE=$(with_block 'KNOWLEDGE: none relevant after 2 searches — sets: "dispatch hook" | "deny marker"')
P_INVALID=$(with_block 'KNOWLEDGE: none relevant')
P_UNAV=$(with_block 'KNOWLEDGE: unavailable — the library lookup timed out twice during this session')
P_UNAV_SHORT=$(with_block 'KNOWLEDGE: no lookup was possible over the whole long session, unavailable.')

# ── runners ──────────────────────────────────────────────────────────
OUT=""; ERR=""; RC=0
# brief <json> [VAR=value ...]: runs the hook in a clean environment (later VAR=value overrides the defaults)
brief() {
    local json="$1"; shift
    OUT=$(printf '%s' "$json" | env -i PATH="$PATH" HOME="$HOME_S" CLAUDE_KNOWLEDGE_DIR="$LIB" \
        CLAUDE_KNOWLEDGE_STATE_ROOT="$STATE" CLAUDE_KNOWLEDGE_BRIEF_LOG="$LOGF" "$@" bash "$HOOK" 2>"$SCRATCH/err")
    RC=$?
    ERR=$(cat "$SCRATCH/err")
}
LIBOUT=""; LIBRC=0
# libcall <function> [args...]: one library function in a clean bash
# shellcheck disable=SC2016  # the bash -c program is intentionally single-quoted
libcall() {
    LIBOUT=$(env -i PATH="$PATH" bash -c '. "$1" && shift && "$@"' _ "$LIBF" "$@" 2>/dev/null)
    LIBRC=$?
}
# dec <prompt> <state_dir> [window]: kb_block then kb_decide, as the hooks do; the decision line in DEC
DEC=""
dec() {
    local blk
    # shellcheck disable=SC2016  # the bash -c program is intentionally single-quoted
    blk=$(env -i PATH="$PATH" bash -c '. "$1" && kb_block "$2"' _ "$LIBF" "$1" 2>/dev/null)
    libcall kb_decide "$blk" "$LIB" "$2" "${3:-1800}"; DEC="$LIBOUT"
}
decision_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }
reason_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }
context_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty'; }
bytes_of() { printf '%s' "$1" | LC_ALL=C wc -c | tr -d ' '; }
# log_count <session> <event>
log_count() {
    [ -f "$LOGF" ] || { printf '0'; return; }
    LC_ALL=C awk -F '\t' -v s="$1" -v e="$2" '$2 == s && $5 == e { n++ } END { print n + 0 }' "$LOGF"
}
# log_detail_count <session> <event> <detail-substring>
log_detail_count() {
    [ -f "$LOGF" ] || { printf '0'; return; }
    LC_ALL=C awk -F '\t' -v s="$1" -v e="$2" -v d="$3" '$2 == s && $5 == e && index($6, d) > 0 { n++ } END { print n + 0 }' "$LOGF"
}
perm_of() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }

echo "── lib/knowledge-brief.sh (parser) ──"

echo "1. kb_block"
T1=$'Intro prose that is not part of the field.\nKNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "excerpt"\nsecond line of the field\n\nafter the blank line, not in the block'
libcall kb_block "$T1"
expect_eq "block: rc 0" 0 "$LIBRC"
expect_eq "block: marker line and continuation, stops at the blank line" $'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "excerpt"\nsecond line of the field' "$LIBOUT"
libcall kb_block "no marker anywhere in this text"
expect_eq "block: no marker -> rc 1" 1 "$LIBRC"
expect_eq "block: no marker -> empty output" "" "$LIBOUT"
libcall kb_block $'knowledge: lowercase is not a marker\nmore'
expect_eq "block: a lowercase marker is not a marker (capitals only)" 1 "$LIBRC"
libcall kb_block $'Knowledge: see below for the field.\nno colon marker'
expect_eq "block: 'Knowledge:' in mixed case is not a marker" 1 "$LIBRC"
libcall kb_block $'WISSEN: keine passende Notiz gefunden\nweiter'
expect_eq "block: WISSEN marker accepted" 0 "$LIBRC"
libcall kb_block $'- **KNOWLEDGE (lead-supplied):** sets: "x"\nmore'
expect_eq "block: markdown-decorated marker accepted" 0 "$LIBRC"
libcall kb_block $'Prose says KNOWLEDGE but this is not a marker\nno colon here'
expect_eq "block: a mention without the colon is not a marker" 1 "$LIBRC"
libcall kb_block $'Knowledge: see below for the field.\n\nKNOWLEDGE: none relevant after 2 searches — sets: "a" | "b"'
expect_eq "block: prose 'Knowledge: see below' above a real field: the real field wins" 'KNOWLEDGE: none relevant after 2 searches — sets: "a" | "b"' "$LIBOUT"
libcall kb_block $'```\nKNOWLEDGE: unavailable — fenced example text, not a real field\n```\n'
expect_eq "block: a marker inside a backtick fence is ignored (rc 1)" 1 "$LIBRC"
libcall kb_block $'```\nKNOWLEDGE: unavailable — fenced example text in the fence\n```\nKNOWLEDGE: none relevant after 2 searches — sets: "a" | "b"'
expect_eq "block: a real marker after a backtick fence still counts" 'KNOWLEDGE: none relevant after 2 searches — sets: "a" | "b"' "$LIBOUT"
libcall kb_block $'~~~\nKNOWLEDGE: fenced example with a tilde fence\n~~~\nWISSEN: nichts gefunden nach zwei Suchen — sets: "a"'
expect_eq "block: a tilde fence hides its marker; the WISSEN line after it counts" 'WISSEN: nichts gefunden nach zwei Suchen — sets: "a"' "$LIBOUT"
libcall kb_block $'KNOWLEDGE: unavailable — the first reason, long enough to count\n\nKNOWLEDGE: none relevant after 2 searches — sets: "a" | "b"'
expect_eq "block: two markers, the LAST one wins" 'KNOWLEDGE: none relevant after 2 searches — sets: "a" | "b"' "$LIBOUT"
libcall kb_block $'KNOWLEDGE (lead-supplied): sets: "a"; rules/x.md L1: "crlf line"\r\nsecond line\r\n'
expect_eq "block: CRLF input: rc 0" 0 "$LIBRC"
expect_eq "block: CRLF input: no carriage return in the block" 0 "$(printf '%s' "$LIBOUT" | LC_ALL=C tr -d -c '\r' | LC_ALL=C wc -c | tr -d ' ')"
BIG="KNOWLEDGE: x $(head -c 5000 /dev/zero | tr '\0' 'a')"
libcall kb_block "$BIG"
expect_eq "block: no size cut, the whole 5000-byte block is printed" "$BIG" "$LIBOUT"

echo "2. kb_verdict"
V_CITED='KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "a verbatim excerpt of at least forty bytes"'
libcall kb_verdict "$V_CITED"; expect_eq "verdict: cited note" "cited" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE: none relevant after 2 searches — sets: "dispatch hook" | "deny marker"'; expect_eq "verdict: none relevant" "none" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE: unavailable — the library lookup timed out twice during this session'; expect_eq "verdict: unavailable with a reason" "unavailable" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE: no lookup was possible over the whole long session, unavailable.'; expect_eq "verdict: unavailable with under 20 bytes after it is invalid" "invalid" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE: none relevant'; expect_eq "verdict: body under 40 bytes is invalid" "invalid" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; the brief describes the excerpt in prose only.'; expect_eq "verdict: prose without a verdict is invalid" "invalid" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "none relevant wording inside the excerpt"'; expect_eq "verdict: a none phrase inside an excerpt does not count (cited)" "cited" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE (lead-supplied): sets: "nothing relevant to say" | "b"; rules/sample-rule.md L3: "a long enough verbatim excerpt here"'; expect_eq "verdict: a none phrase inside sets does not count (cited)" "cited" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE (lead-supplied): sets: "unavailable mirror" | "b"; rules/sample-rule.md L3: "a long enough verbatim excerpt here"'; expect_eq "verdict: unavailable inside sets does not count (cited)" "cited" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE: none relevant after 2 searches — sets: "library unavailable at night" | "b"'; expect_eq "verdict: none in the body beats unavailable named only in sets" "none" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE: none relevant after 2 searches — sets: "a" | "b"; see rules/sample-rule.md for context'; expect_eq "verdict: a none block that names a path is none (class precedence)" "none" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE: none relevant, the library itself is unavailable right now for others.'; expect_eq "verdict: none phrase before unavailable" "none" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE: unavailable — the mirror is offline right now; sets: "none relevant"'; expect_eq "verdict: none named only in sets does not beat unavailable" "unavailable" "$LIBOUT"
libcall kb_verdict 'WISSEN: nichts passendes gefunden nach zwei Suchen — sets: "a" | "b"'; expect_eq "verdict: German none phrase" "none" "$LIBOUT"
libcall kb_verdict 'WISSEN (lead-supplied): sets: "a"; rules/sample-rule.md L3: "ein ausreichend langer Auszug aus der Regel"'; expect_eq "verdict: German marker with a cited note" "cited" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE (lead-supplied): sets: "Änderungsprotokoll" | "Veröffentlichung"; rules/sample-rule.md L3: "Übersicht der Veröffentlichung, mit Umlauten im Auszug"'; expect_eq "verdict: umlauts in the excerpt keep the cited verdict" "cited" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE: keine passende Notiz, nach der Suche nichts gefunden, bitte weiter'; expect_eq "verdict: German keine passende" "none" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE: Nichts Relevant nach zwei Suchen, bitte weiter, die Liste bleibt leer'; expect_eq "verdict: none phrase is matched case-insensitively" "none" "$LIBOUT"

echo "3. kb_citations"
# shellcheck disable=SC2016  # the backticks are literal brief text
libcall kb_citations 'KNOWLEDGE (lead-supplied): sets: "a"; == rules/sample-rule.md L3–L9: "x"  `ledger/IMP-001.md`:L12, (rules/a.md), rules/b.md.'
expect_eq "citations: strips ==, backticks, :L suffix, parentheses, trailing dot" $'rules/sample-rule.md\nledger/IMP-001.md\nrules/a.md\nrules/b.md' "$LIBOUT"
libcall kb_citations 'rules/x.md:L3–L9 and rules/y.md:L12'
expect_eq "citations: en-dash range and colon-L suffix" $'rules/x.md\nrules/y.md' "$LIBOUT"
libcall kb_citations 'see rules/z.md: and rules/z.md again'
expect_eq "citations: distinct paths only" "rules/z.md" "$LIBOUT"
libcall kb_citations 'no citations here at all'
expect_eq "citations: none -> empty" "" "$LIBOUT"
libcall kb_citations 'the token foo.mdx is not a note'
expect_eq "citations: a .mdx token is not a note" "" "$LIBOUT"
libcall kb_citations 'KNOWLEDGE: none relevant after 2 searches — sets: "a" | "b"; "rules/sample-rule.md L3: quoted path only"'
expect_eq "citations: a .md path inside double quotes is not a citation" "" "$LIBOUT"
libcall kb_citations 'KNOWLEDGE (lead-supplied): sets: "a"; rules/a.md L1: "see rules/quoted.md here"; rules/b.md L2: "x"'
expect_eq "citations: quoted path skipped, unquoted paths kept" $'rules/a.md\nrules/b.md' "$LIBOUT"

echo "4. kb_sets"
libcall kb_sets 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/x.md L3: "y"'
expect_eq "sets: text up to the semicolon" '"a" | "b"' "$LIBOUT"
libcall kb_sets 'KNOWLEDGE: none relevant — sets: "last one, no semicolon"'
expect_eq "sets: up to the end when there is no semicolon" '"last one, no semicolon"' "$LIBOUT"
libcall kb_sets 'KNOWLEDGE: none relevant'
expect_eq "sets: absent -> empty" "" "$LIBOUT"

echo "5. kb_excerpts"
libcall kb_excerpts 'KNOWLEDGE (lead-supplied): sets: "a long set entry for the sets clause"; rules/x.md L3: "a verbatim excerpt of enough length"'
expect_eq "excerpts: only the segment outside the sets clause" "a verbatim excerpt of enough length" "$LIBOUT"
libcall kb_excerpts 'rules/x.md L3: "short one"'
expect_eq "excerpts: under 30 bytes is not an excerpt" "" "$LIBOUT"
libcall kb_excerpts 'rules/x.md L1: "   two   spaces   here and enough text   "'
expect_eq "excerpts: whitespace collapsed and trimmed" "two spaces here and enough text" "$LIBOUT"
libcall kb_excerpts 'rules/bands.md L1: "» Band matrix: AUTO, SOFT-ACK and ESCALATE"'
expect_eq "excerpts: a leading '» ' is removed" "Band matrix: AUTO, SOFT-ACK and ESCALATE" "$LIBOUT"
libcall kb_excerpts $'rules/wrapped-rule.md L1: "a verbatim line\nbreaking across lines here"'
expect_eq "excerpts: a segment across a line break is joined" "a verbatim line breaking across lines here" "$LIBOUT"

echo "6. kb_decide: resolution of cited notes (the decision line)"
dec "$(with_block 'KNOWLEDGE: none relevant')" "$SCRATCH/none"
expect_has "decide: invalid body -> deny invalid, naming the rule" "deny invalid no verdict: the body needs" "$DEC"
dec "" "$SCRATCH/none"
expect_eq "decide: no block -> deny missing" "deny missing no KNOWLEDGE field: no line of the brief starts with KNOWLEDGE: or WISSEN:" "$DEC"
BIGB="KNOWLEDGE: none relevant after 2 searches — sets: \"a\" | \"b\" $(head -c 4100 /dev/zero | tr '\0' 'x')"
dec "$BIGB" "$SCRATCH/none"
expect_has "decide: block over 4000 bytes -> deny naming the size" "4000 bytes or more" "$DEC"
expect_has "decide: the size block names its exact byte count" "($(bytes_of "$BIGB"))" "$DEC"
dec 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; "rules/sample-rule.md L3: quoted path only"' "$SCRATCH/none"
expect_has "decide: a .md only inside double quotes -> deny invalid, names no note" "deny invalid the brief names no note outside its sets clause and double quotes" "$DEC"
dec "$(with_block "KNOWLEDGE (lead-supplied): sets: \"a\" | \"b\"; $SCRATCH/abs/abs-note.md L1: \"a long enough verbatim excerpt here\"")" "$SCRATCH/none"
# the cause cuts the path at 160 bytes: a long TMPDIR would hide the file name, so the prefix is asserted
expect_has "decide: an absolute path outside the mirror -> deny outside" "cited note outside the library mirror: ${SCRATCH:0:100}" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "a verbatim excerpt from the sample rule text"; rules/link-out.md L1: "a long enough verbatim excerpt here"')" "$SCRATCH/none"
expect_has "decide: a symlink inside the mirror pointing outside -> deny (symlink)" "cited note is a symlink (refused): rules/link-out.md" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/../rules/sample-rule.md L3: "a verbatim excerpt from the sample rule text"')" "$SCRATCH/none"
expect_has "decide: a .. segment -> deny and names the path" "cited note path has a .. segment (refused): rules/../rules/sample-rule.md" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; ../sample-rule.md L3: "a relative parent path, long enough here"')" "$SCRATCH/none"
expect_has "decide: a relative path starting with .. -> deny" "has a .. segment" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample rule.md L3: "a long enough verbatim excerpt here"')" "$SCRATCH/none"
expect_has "decide: a path with a space -> deny with the space as the cause" 'cited note path has a space ("rules/sample rule.md")' "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/missing-note.md L3: "an excerpt of a note that is not in the library"')" "$SCRATCH/none"
expect_eq "decide: a missing note -> deny not found, naming it" "deny cited cited note not found in the library: rules/missing-note.md" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "too short"')" "$SCRATCH/none"
expect_has "decide: no excerpt of 30 bytes -> deny needs an excerpt" "a cited verdict needs at least one verbatim excerpt" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "a verbatim excerpt from the sample rule text"')" "$SCRATCH/none"
expect_eq "decide: an excerpt matching a note line -> allow, 1 note, 1 excerpt" "allow cited 1 notes, 1 excerpts" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/wrapped-rule.md L2: "The quick brown fox jumps over the lazy dog"')" "$SCRATCH/none"
expect_eq "decide: an excerpt matching across a line break (whitespace-normalised) -> allow" "allow cited 1 notes, 1 excerpts" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/wrapped-rule.md L2: "The quick brown fox leaps over the lazy dog"')" "$SCRATCH/none"
expect_has "decide: a reworded excerpt -> deny naming its first 40 bytes" 'excerpt not found in the cited notes: "The quick brown fox leaps over the'  "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "a verbatim excerpt from the sample rule words"')" "$SCRATCH/none"
expect_has "decide: a reword AFTER byte 30 (the 30-byte prefix still matches) -> deny (full match)" 'excerpt not found in the cited notes: "a verbatim excerpt from the sample rule' "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "a verbatim excerpt from the sample rule text…"')" "$SCRATCH/none"
expect_has "decide: an excerpt with a trailing ellipsis the note does not contain -> deny (first 40 bytes shown)" 'excerpt not found in the cited notes: "a verbatim excerpt from the sample rule' "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "a verbatim excerpt from the sample rule text..."')" "$SCRATCH/none"
expect_has "decide: an excerpt with a trailing three dots the note does not contain -> deny" "excerpt not found in the cited notes" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/wrapped-rule.md L2: "fox jumps over the lazy dog every day."')" "$SCRATCH/none"
expect_eq "decide: an excerpt spanning two note lines (the normalised text) -> allow" "allow cited 1 notes, 1 excerpts" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "a verbatim excerpt from the sample rule text"')" "$SCRATCH/none"
expect_eq "decide: an exact excerpt of 30+ bytes -> allow" "allow cited 1 notes, 1 excerpts" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "a verbatim excerpt from the sample rule text" and "short"')" "$SCRATCH/none"
expect_eq "decide: a short quote beside a full one is not checked (30-byte threshold) -> allow" "allow cited 1 notes, 1 excerpts" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/bands.md L1: "» Band matrix: AUTO, SOFT-ACK and ESCALATE"')" "$SCRATCH/none"
expect_eq "decide: a '» '-prefixed description excerpt -> allow" "allow cited 1 notes, 1 excerpts" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/bands.md L1: "Band matrix: AUTO, SOFT-ACK and ESCALATE"; rules/sample-rule.md L3: "a verbatim excerpt from the sample rule text"')" "$SCRATCH/none"
expect_eq "decide: two notes, one excerpt each -> allow 2 notes, 2 excerpts" "allow cited 2 notes, 2 excerpts" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/bands.md L1: "a verbatim excerpt from the sample rule text"; rules/sample-rule.md L3: "x"')" "$SCRATCH/none"
expect_eq "decide: an excerpt found in any cited note is enough" "allow cited 2 notes, 1 excerpts" "$DEC"
dec "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/bands.md L1: "Band matrix: AUTO, SOFT-ACK and ESCALATE"; rules/missing-note.md L1: "x"')" "$SCRATCH/none"
expect_has "decide: one missing among two existing -> deny naming the missing one" "rules/missing-note.md" "$DEC"
LONGP=$(head -c 300 /dev/zero | tr '\0' 'p')
dec "$(with_block "KNOWLEDGE (lead-supplied): sets: \"a\" | \"b\"; rules/$LONGP.md L3: \"an excerpt of a note that is not in the library\"")" "$SCRATCH/none"
expect_eq "decide: a long missing path is cut to 160 bytes in the cause" "yes" "$([ "$(bytes_of "$DEC")" -lt 400 ] && printf yes || printf no)"

echo "6b. second review: the parser's evidence rules"
libcall kb_verdict 'KNOWLEDGE: unavailable                              '
expect_eq "unavailable: 30 spaces after the word give no reason -> invalid" "invalid" "$LIBOUT"
EM7=$(printf '—%.0s' 1 2 3 4 5 6 7)
libcall kb_verdict "KNOWLEDGE: unavailable ${EM7}                              "
expect_eq "unavailable: seven em dashes and spaces are no reason -> invalid" "invalid" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE: Mirror check: unavailable — abcdefghijklmnopqrst'
expect_eq "unavailable: exactly 20 bytes of reason -> unavailable" "unavailable" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE: Mirror check: unavailable — abcdefghijklmnopqrs'
expect_eq "unavailable: 19 bytes of reason -> invalid" "invalid" "$LIBOUT"
libcall kb_reason 'KNOWLEDGE: Mirror check: unavailable — abc def, ghi.'
expect_eq "kb_reason: separators removed from the reason text" "abcdefghi" "$LIBOUT"
libcall kb_reason "KNOWLEDGE: unavailable — $(printf 'x%.0s' $(seq 1 100))"
expect_eq "kb_reason: at most 80 bytes" "80" "$(bytes_of "$LIBOUT")"
libcall kb_citations 'KNOWLEDGE (lead-supplied): sets: "tool-discipline.md foo" | "x"; rules/sample-rule.md L3: "a verbatim excerpt from the sample rule text"'
expect_eq "citations: a .md named inside sets: is not a citation; the real path is" "rules/sample-rule.md" "$LIBOUT"
libcall kb_verdict 'KNOWLEDGE (lead-supplied): sets: "tool-discipline.md foo" | "x"; "a verbatim excerpt of enough length here"'
expect_eq "verdict: a .md only inside sets: is not a verdict trigger" "invalid" "$LIBOUT"
libcall kb_sets 'KNOWLEDGE: none relevant — sets: "a" | "b"
rules/x.md L1: "y"'
expect_eq "sets: ends at the end of its line when there is no semicolon" '"a" | "b"' "$LIBOUT"
EXPECT_CK=$(printf '%s\n%s' "general-purpose" "unit-key" | shasum | awk '{print $1}')
libcall kb_counter_key general-purpose unit-key ""
expect_eq "counter key: the description key is sha1(subagent, description)" "$EXPECT_CK" "$LIBOUT"
P250=$(printf 'q%.0s' $(seq 1 250))
EXPECT_CK2=$(printf '%s\n%s' "backend-agent" "$(printf '%s' "$P250" | cut -c1-200)" | shasum | awk '{print $1}')
libcall kb_counter_key backend-agent "" "$P250"
expect_eq "counter key: without a description the first 200 bytes of the prompt" "$EXPECT_CK2" "$LIBOUT"

echo "7. kb_decide: none needs a sets clause and two knowledge-agent runs in the window"
NDIR="$SCRATCH/n-empty"; mkdir -p "$NDIR"
NONE_BLOCK='KNOWLEDGE: none relevant after 2 searches — sets: "dispatch hook" | "deny marker"'
dec "$NONE_BLOCK" "$NDIR"
expect_eq "none: no search file -> deny, found 0" "deny none a none-relevant verdict needs two knowledge-agent runs in this session within the last 1800s (found 0)" "$DEC"
N1="$SCRATCH/n-one"; mkdir -p "$N1"; printf '%s\tka\n' "$(iso_ago 0)" > "$N1/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$N1"
expect_has "none: one fresh search -> deny, found 1" "(found 1)" "$DEC"
N2="$SCRATCH/n-two"; mkdir -p "$N2"; printf '%s\tka1\n%s\tka2\n' "$(iso_ago 0)" "$(iso_ago 5)" > "$N2/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$N2"
expect_eq "none: two fresh searches -> allow" "allow none 2 searches in window" "$DEC"
N3="$SCRATCH/n-old"; mkdir -p "$N3"; printf '%s\tka\n%s\tka\n' "$(iso_ago 7200)" "$(iso_ago 0)" > "$N3/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$N3"
expect_has "none: an old search does not count (one fresh, found 1)" "(found 1)" "$DEC"
N4="$SCRATCH/n-win"; mkdir -p "$N4"; printf '%s\tka1\n%s\tka2\n' "$(iso_ago 120)" "$(iso_ago 120)" > "$N4/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$N4" 60
expect_has "none: window 60 s, two 120 s old searches -> deny, found 0" "last 60s (found 0)" "$DEC"
dec "$NONE_BLOCK" "$N4" 300
expect_eq "none: window 300 s, the same two searches -> allow" "allow none 2 searches in window" "$DEC"
N5="$SCRATCH/n-garbage"; mkdir -p "$N5"; printf '%s\tka\ngarbage line without a tab\n' "$(iso_ago 0)" > "$N5/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$N5"
expect_has "none: a malformed last line, one valid earlier line -> counted (found 1)" "(found 1)" "$DEC"
N6="$SCRATCH/n-garbage2"; mkdir -p "$N6"; printf '%s\tka1\n%s\tka2\ngarbage line\n' "$(iso_ago 0)" "$(iso_ago 3)" > "$N6/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$N6"
expect_eq "none: two valid lines and a malformed last one -> allow" "allow none 2 searches in window" "$DEC"
N7="$SCRATCH/n-dir"; mkdir -p "$N7/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$N7"
expect_has "none: the lookups path is a directory -> found 0" "(found 0)" "$DEC"
N8="$SCRATCH/n-future"; mkdir -p "$N8"; printf '%s\tka1\n%s\tka2\n' "$(iso_ago -3600)" "$(iso_ago 0)" > "$N8/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$N8"
expect_has "none: a future stamp is not counted (found 1)" "(found 1)" "$DEC"
N9="$SCRATCH/n-badts"; mkdir -p "$N9"; printf 'not-a-timestamp\tka\n%s\tka\n' "$(iso_ago 0)" > "$N9/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$N9"
expect_has "none: an unparsable stamp is skipped (found 1)" "(found 1)" "$DEC"
N10="$SCRATCH/n-same-id"; mkdir -p "$N10"; printf '%s\tkaone\n%s\tkaone\n' "$(iso_ago 0)" "$(iso_ago 3)" > "$N10/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$N10"
expect_has "none: two lines from ONE agent id are one run -> deny (found 1)" "(found 1)" "$DEC"
N11="$SCRATCH/n-two-ids"; mkdir -p "$N11"; printf '%s\tkaone\n%s\tkatwo\n' "$(iso_ago 0)" "$(iso_ago 3)" > "$N11/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$N11"
expect_eq "none: two agent ids -> allow" "allow none 2 searches in window" "$DEC"
dec 'KNOWLEDGE: none relevant after 2 searches — nothing named here at all' "$N11"
expect_eq "none without a sets clause -> deny naming the sets" 'deny none a none-relevant verdict must name the sets searched (sets: "…" | "…")' "$DEC"
TAILE="$SCRATCH/n-tail-early"; mkdir -p "$TAILE"
{ printf '%s\tke1\n%s\tke2\n' "$(iso_ago 0)" "$(iso_ago 0)"; for _ in $(seq 1 58); do printf '%s\tkold\n' "$(iso_ago 7200)"; done; } > "$TAILE/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$TAILE"
expect_has "none: fresh runs older than the last 50 lines are not read (found 0)" "(found 0)" "$DEC"
TAILL="$SCRATCH/n-tail-late"; mkdir -p "$TAILL"
{ for _ in $(seq 1 58); do printf '%s\tkold\n' "$(iso_ago 7200)"; done; printf '%s\tke1\n%s\tke2\n' "$(iso_ago 0)" "$(iso_ago 0)"; } > "$TAILL/knowledge-agent-lookups"
dec "$NONE_BLOCK" "$TAILL"
expect_eq "none: the last 50 lines hold two fresh runs -> allow" "allow none 2 searches in window" "$DEC"
mk_bytes_block() { local p='KNOWLEDGE: none relevant after 2 searches — sets: "a" | "b" '; printf '%s%s' "$p" "$(head -c $(( $1 - $(bytes_of "$p") )) /dev/zero | tr '\0' 'x')"; }
B4000=$(mk_bytes_block 4000); B3999=$(mk_bytes_block 3999)
dec "$B4000" "$N2"
expect_eq "size: a block of exactly 4000 bytes is denied" "deny none KNOWLEDGE block is 4000 bytes or more (4000); keep it under 4000 bytes" "$DEC"
dec "$B3999" "$N2"
expect_eq "size: 3999 bytes is under the limit (allowed with two runs)" "allow none 2 searches in window" "$DEC"

echo "8. kb_decide: unavailable needs a knowledge-agent dispatch mark; kb_mark_dispatch"
UNAV_BLOCK='KNOWLEDGE: unavailable — the library lookup timed out twice during this session'
U0="$SCRATCH/u-none"; mkdir -p "$U0"
dec "$UNAV_BLOCK" "$U0"
expect_eq "unavailable: no dispatch mark -> deny (found none)" "deny unavailable an unavailable verdict needs a knowledge-agent dispatch in this session within the last 1800s (found none)" "$DEC"
U1="$SCRATCH/u-mark"; mkdir -p "$U1"
libcall kb_mark_dispatch "$U1"; MARK_RC=$LIBRC
expect_eq "mark: kb_mark_dispatch returns 0" 0 "$MARK_RC"
expect_eq "mark: the file holds one knowledge-agent line" 1 "$(LC_ALL=C awk -F '\t' '$2 == "knowledge-agent" && NF == 2' "$U1/knowledge-agent-dispatches" | wc -l | tr -d ' ')"
expect_eq "mark: the dispatch file is mode 600" "600" "$(perm_of "$U1/knowledge-agent-dispatches")"
dec "$UNAV_BLOCK" "$U1"
expect_eq "unavailable: with a fresh mark -> allow; the logged reason is the text after the word, separators removed" "allow unavailable thelibrarylookuptimedouttwiceduringthissession" "$DEC"
dec 'KNOWLEDGE: "unavailable" was the old status; unavailable — knowledge-agent timed out after two tries' "$U1"
expect_has "unavailable: a quoted earlier mention does not defeat a real reason (scan-based) -> allow" "allow unavailable" "$DEC"
dec 'KNOWLEDGE: "unavailable" was the old status, unavailable — no' "$U1"
expect_has "unavailable: a quoted mention does not satisfy a too-short real reason (scan-based) -> deny invalid" "deny invalid no verdict" "$DEC"
dec 'KNOWLEDGE: unavailable — "a long quoted text that is not a reason at all here"' "$U1"
expect_has "unavailable: a reason only inside quotes is too short (scan-based) -> deny invalid" "deny invalid no verdict" "$DEC"
U2="$SCRATCH/u-old"; mkdir -p "$U2"; printf '%s\tknowledge-agent\n' "$(iso_ago 7200)" > "$U2/knowledge-agent-dispatches"
dec "$UNAV_BLOCK" "$U2"
expect_has "unavailable: an old mark does not count" "(found none)" "$DEC"

echo "── knowledge-brief-check.sh (PreToolUse Task|Agent) ──"

echo "9. non-dispatch input and malformed input are silent or fail open"
brief "$(task_json s-tool Read general-purpose d1 "$P_MISSING")"
expect_eq "Read tool: exit 0, silent" "0|" "$RC|$OUT"
expect_eq "Read tool: nothing logged" 0 "$(log_count s-tool deny)"
brief "$(task_json s-agent Agent general-purpose d-agent "$P_MISSING")"
expect_eq "Agent tool is gated like Task: deny" "deny" "$(decision_of "$OUT")"
brief 'not json at all'
expect_eq "non-JSON: exit 0, silent stdout" "0|" "$RC|$OUT"
expect_has "non-JSON: stderr note" "not JSON" "$ERR"
expect_eq "non-JSON: logged not-json under session -" 1 "$(log_count - not-json)"
brief "$(task_json "" Task general-purpose d "$P_MISSING")"
expect_eq "empty session: exit 0, silent" "0|" "$RC|$OUT"
expect_eq "empty session: logged no-session with session -" 1 "$(log_count - no-session)"
brief '{"tool_name":"Task","session_id":"s-str","tool_input":"abc"}'
expect_eq "string tool_input is read as empty: exit 0" 0 "$RC"
expect_eq "string tool_input is read as empty: missing field denied" "deny" "$(decision_of "$OUT")"

echo "10. knowledge-agent is exempt, logged once, and its dispatch is marked"
brief "$(task_json s-kb Task knowledge-agent knowledge-agent d "$P_MISSING")"
expect_eq "knowledge-agent: exit 0, silent" "0|" "$RC|$OUT"
brief "$(task_json s-kb Task knowledge-agent knowledge-agent d "$P_MISSING")"
expect_eq "knowledge-agent: exempt logged once across two runs" 1 "$(log_count s-kb exempt-knowledge-agent)"
expect_eq "knowledge-agent: each dispatch is marked in knowledge-agent-dispatches" 2 "$(LC_ALL=C awk -F '\t' '$2 == "knowledge-agent"' "$STATE/knowledge-gate-s-kb/knowledge-agent-dispatches" | wc -l | tr -d ' ')"
expect_eq "knowledge-agent: the mark file is mode 600" "600" "$(perm_of "$STATE/knowledge-gate-s-kb/knowledge-agent-dispatches")"

echo "11. mode off and unknown mode"
brief "$(task_json s-off Task general-purpose d "$P_MISSING")" CLAUDE_KNOWLEDGE_BRIEF=off
brief "$(task_json s-off Task general-purpose d "$P_MISSING")" CLAUDE_KNOWLEDGE_BRIEF=off
expect_eq "off: exit 0, silent" "0|" "$RC|$OUT"
expect_eq "off: logged once per session" 1 "$(log_count s-off off)"
brief "$(task_json s-bogus Task general-purpose d "$P_MISSING")" CLAUDE_KNOWLEDGE_BRIEF=bogus
expect_eq "unknown mode: falls back to deny" "deny" "$(decision_of "$OUT")"
expect_has "unknown mode: warns on stderr" "unknown CLAUDE_KNOWLEDGE_BRIEF=bogus" "$ERR"
expect_eq "unknown mode: logged mode-fallback" 1 "$(log_count s-bogus mode-fallback)"
brief "$(task_json s-win Task general-purpose d "$P_MISSING")" CLAUDE_KNOWLEDGE_BRIEF_WINDOW=soon
expect_eq "non-numeric window: logged window-fallback" 1 "$(log_count s-win window-fallback)"

echo "12. library missing: fail open, logged once"
brief "$(task_json s-nolib Task general-purpose d "$P_MISSING")" CLAUDE_KNOWLEDGE_DIR="$SCRATCH/no-library"
expect_eq "library missing: exit 0, silent" "0|" "$RC|$OUT"
brief "$(task_json s-nolib Task general-purpose d "$P_MISSING")" CLAUDE_KNOWLEDGE_DIR="$SCRATCH/no-library"
expect_eq "library missing: logged once across two dispatches" 1 "$(log_count s-nolib library-missing)"
brief "$(task_json s-nokdir Task general-purpose d "$P_MISSING")" CLAUDE_KNOWLEDGE_DIR=
expect_eq "no CLAUDE_KNOWLEDGE_DIR and no env.local.sh: logged, silent" "1|" "$(log_count s-nokdir library-missing)|$OUT"

echo "13. parser missing: copied hook without its library, fail open and logged"
mkdir -p "$SCRATCH/nolib"; cp "$HOOK" "$SCRATCH/nolib/knowledge-brief-check.sh"
HOOK_REAL="$HOOK"; HOOK="$SCRATCH/nolib/knowledge-brief-check.sh"
brief "$(task_json s-nopar Task general-purpose d "$P_MISSING")"
HOOK="$HOOK_REAL"
expect_eq "parser missing: exit 0, silent stdout" "0|" "$RC|$OUT"
expect_has "parser missing: stderr note" "parser" "$ERR"
expect_eq "parser missing: logged parser-missing" 1 "$(log_count s-nopar parser-missing)"

echo "14. the denial ladder: deny 1-3, escalation at 4, silent and logged from 5"
J_LADDER=$(task_json s-ladder Task general-purpose unit-ladder "$P_MISSING")
brief "$J_LADDER"
R=$(reason_of "$OUT")
expect_eq "denial 1: permissionDecision deny" "deny" "$(decision_of "$OUT")"
expect_has "denial 1: reason starts with the IMP-268 marker" "Knowledge brief (IMP-268)" "$R"
expect_has "denial 1: states denial 1 of 3" "denial 1 of 3" "$R"
expect_has "denial 1: names the missing field" "no valid KNOWLEDGE field" "$R"
expect_has "denial 1: carries the lead-supplied template" 'KNOWLEDGE (lead-supplied): sets:' "$R"
expect_has "denial 1: states the specific cause" "no KNOWLEDGE field: no line of the brief starts with" "$R"
expect_eq "denial 1: reason at most 900 bytes" "yes" "$([ "$(bytes_of "$R")" -le 900 ] && printf yes || printf no)"
brief "$J_LADDER"
expect_has "denial 2: states denial 2 of 3" "denial 2 of 3" "$(reason_of "$OUT")"
brief "$J_LADDER"
expect_eq "denial 3: deny" "deny" "$(decision_of "$OUT")"
expect_has "denial 3: states denial 3 of 3" "denial 3 of 3" "$(reason_of "$OUT")"
brief "$J_LADDER"
expect_eq "denial 4: no deny" "" "$(decision_of "$OUT")"
expect_has "denial 4: ESCALATION context" "ESCALATION (knowledge brief, IMP-268): dispatch allowed after 3 denials" "$(context_of "$OUT")"
expect_eq "denial 4: escalation logged" 1 "$(log_count s-ladder escalation)"
brief "$J_LADDER"
expect_eq "denial 5: exit 0 and no stdout" "0|" "$RC|$OUT"
expect_eq "denial 5: logged as denial 5, allowed" 1 "$(log_detail_count s-ladder escalation "denial 5, allowed")"
expect_eq "denial counter file holds 5" "5" "$(cat "$STATE"/knowledge-gate-s-ladder/brief-denials-* 2>/dev/null)"
brief "$(task_json s-ladder Task general-purpose unit-other "$P_MISSING")"
expect_has "a different description starts again at denial 1" "denial 1 of 3" "$(reason_of "$OUT")"
expect_eq "healthy denial counter: no counter-reset logged" 0 "$(log_count s-ladder counter-reset)"
COR_KEY=$(printf '%s\n%s' "general-purpose" "unit-cor" | shasum | awk '{print $1}')
mkdir -p "$STATE/knowledge-gate-s-cor"; printf 'abc\n' > "$STATE/knowledge-gate-s-cor/brief-denials-$COR_KEY"
brief "$(task_json s-cor Task general-purpose unit-cor "$P_MISSING")"
expect_eq "corrupt denial counter: logged counter-reset" 1 "$(log_count s-cor counter-reset)"
expect_has "corrupt denial counter: restarts at denial 1" "denial 1 of 3" "$(reason_of "$OUT")"

echo "15. advisory never denies; the text says attempt N, never 'of 3'"
for _ in 1 2 3 4; do brief "$(task_json s-adv Task general-purpose unit-adv "$P_MISSING")" CLAUDE_KNOWLEDGE_BRIEF=advisory; done
expect_eq "advisory: no permissionDecision after four dispatches" "" "$(decision_of "$OUT")"
expect_has "advisory: additionalContext carries the text" "Knowledge brief (IMP-268)" "$(context_of "$OUT")"
expect_has "advisory: the fourth text says attempt 4" "attempt 4" "$(context_of "$OUT")"
expect_eq "advisory: logged four times" 4 "$(log_count s-adv advisory)"
expect_eq "advisory: never logs an escalation" 0 "$(log_count s-adv escalation)"
for _ in 1 2 3 4; do brief "$(task_json s-adv Task general-purpose unit-adv "$P_MISSING")" CLAUDE_KNOWLEDGE_BRIEF=advisory; done
expect_has "advisory: the eighth text says attempt 8" "attempt 8" "$(context_of "$OUT")"
expect_lacks "advisory: the eighth text never says 'of 3'" "of 3" "$(context_of "$OUT")"

echo "16. invalid, unavailable and missing fields"
brief "$(task_json s-inv Task general-purpose unit-inv "$P_INVALID")"
expect_eq "invalid body (under 40 bytes): deny" "deny" "$(decision_of "$OUT")"
expect_has "invalid body: reason names the invalid verdict" "no verdict: the body needs a none-phrase" "$(reason_of "$OUT")"
brief "$(task_json s-inv Task general-purpose unit-inv2 "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; the brief describes the excerpt in prose only.')")"
expect_eq "prose without a verdict: deny" "deny" "$(decision_of "$OUT")"
brief "$(task_json s-inv Task general-purpose unit-inv3 "$(with_block 'KNOWLEDGE: unavailable — the library lookup timed out twice during this session')")"
expect_eq "unavailable with a reason but no dispatch mark: deny" "deny" "$(decision_of "$OUT")"
expect_has "unavailable without a mark: names the dispatch need" "needs a knowledge-agent dispatch" "$(reason_of "$OUT")"
seed_dispatch s-inv
brief "$(task_json s-inv Task general-purpose unit-inv4 "$(with_block 'KNOWLEDGE: unavailable — the library lookup timed out twice during this session')")"
expect_eq "unavailable with a reason and a mark: allowed" "" "$(decision_of "$OUT")"
brief "$(task_json s-inv Task general-purpose unit-inv5 "$P_UNAV_SHORT")"
expect_eq "unavailable with under 20 bytes after the word: deny" "deny" "$(decision_of "$OUT")"

echo "17. cited notes through the hook"
seed_dispatch s-cit
brief "$(task_json s-cit Task general-purpose unit-cit "$P_CITED")"
expect_eq "cited, existing note and excerpt: silent allow" "0|" "$RC|$OUT"
expect_eq "cited: allow-cited logged once" 1 "$(log_count s-cit allow-cited)"
expect_eq "cited: detail records the notes and excerpts" 1 "$(log_detail_count s-cit allow-cited "1 notes, 1 excerpts")"
brief "$(task_json s-cit Task general-purpose unit-home "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; ~/notes/home-note.md L1: "the home note excerpt, long enough for the check"')")"
expect_eq "cited ~/ path outside the mirror: deny" "deny" "$(decision_of "$OUT")"
expect_has "cited ~/ path outside the mirror: names outside" "outside the library mirror: ~/notes/home-note.md" "$(reason_of "$OUT")"
brief "$(task_json s-cit Task general-purpose unit-home2 "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; ~/kb/mirror/rules/home-rule.md L1: "the home note excerpt, long enough for the check"')")" CLAUDE_KNOWLEDGE_DIR="$HOME_S/kb"
expect_eq "cited ~/ path inside the mirror: allow" "0|" "$RC|$OUT"
brief "$(task_json s-cit Task general-purpose unit-abs "$(with_block "KNOWLEDGE (lead-supplied): sets: \"a\" | \"b\"; $LIB/mirror/rules/sample-rule.md L1: \"a verbatim excerpt from the sample rule text\"")")"
expect_eq "cited absolute path inside the mirror: allow" "0|" "$RC|$OUT"
brief "$(task_json s-cit Task general-purpose unit-abs2 "$(with_block "KNOWLEDGE (lead-supplied): sets: \"a\" | \"b\"; $SCRATCH/abs/abs-note.md L1: \"a long enough verbatim excerpt here\"")")"
expect_has "cited absolute path outside the mirror: deny outside" "outside the library mirror" "$(reason_of "$OUT")"
brief "$(task_json s-cit Task general-purpose unit-link "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/link-out.md L1: "a long enough verbatim excerpt here"')")"
expect_has "symlink inside the mirror pointing outside: deny (symlink)" "is a symlink (refused)" "$(reason_of "$OUT")"
brief "$(task_json s-cit Task general-purpose unit-miss "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/missing-note.md L3: "an excerpt of a note that is not in the library"')")"
expect_eq "cited missing note: deny" "deny" "$(decision_of "$OUT")"
expect_has "cited missing note: names it" "cited note not found in the library: rules/missing-note.md" "$(reason_of "$OUT")"
brief "$(task_json s-cit Task general-purpose unit-two "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a"; rules/sample-rule.md L3: "present excerpt, long enough here"; rules/gone.md L1: "missing excerpt, long enough too"')")"
expect_has "one missing among two existing: deny naming the missing one" "rules/gone.md" "$(reason_of "$OUT")"
brief "$(task_json s-cit Task general-purpose unit-dd "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/../rules/sample-rule.md L3: "a path with a parent segment, long enough"')")"
expect_eq "cited path with .. is never resolved: deny" "deny" "$(decision_of "$OUT")"
expect_has "cited path with .. names the path" "rules/../rules/sample-rule.md" "$(reason_of "$OUT")"
brief "$(task_json s-cit Task general-purpose unit-dd2 "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; ../sample-rule.md L3: "a relative parent path, long enough here"')")"
expect_eq "cited path that starts with .. : deny" "deny" "$(decision_of "$OUT")"
brief "$(task_json s-cit Task general-purpose unit-sp "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample rule.md L3: "a long enough verbatim excerpt here"')")"
expect_has "cited path with a space: deny with a clear cause" "has a space" "$(reason_of "$OUT")"
brief "$(task_json s-cit Task general-purpose unit-noex "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "short"')")"
expect_has "cited note without an excerpt: deny" "needs at least one verbatim excerpt" "$(reason_of "$OUT")"
brief "$(task_json s-cit Task general-purpose unit-reword "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "a verbatim excerpt that was reworded"')")"
expect_has "reworded excerpt: deny naming the excerpt" 'excerpt not found in the cited notes: "a verbatim excerpt that was reworded"' "$(reason_of "$OUT")"
brief "$(task_json s-cit Task general-purpose unit-wrap "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/wrapped-rule.md L2: "The quick brown fox jumps over the lazy dog"')")"
expect_eq "excerpt across a line break in the note: allow" "0|" "$RC|$OUT"
brief "$(task_json s-cit Task general-purpose unit-desc "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/bands.md L1: "» Band matrix: AUTO, SOFT-ACK and ESCALATE"')")"
expect_eq "description excerpt with '» ' prefix: allow" "0|" "$RC|$OUT"
brief "$(task_json s-cit Task general-purpose unit-long "$(with_block "KNOWLEDGE (lead-supplied): sets: \"a\" | \"b\"; rules/$LONGP.md L3: \"an excerpt of a note that is not in the library\"")")"
expect_eq "deny text of a long path stays at most 900 bytes" "yes" "$([ "$(bytes_of "$(reason_of "$OUT")")" -le 900 ] && printf yes || printf no)"
expect_eq "deny text of the cited verdict with the long path: deny" "deny" "$(decision_of "$OUT")"
brief "$(task_json s-cit Task general-purpose unit-sets "$(with_block 'KNOWLEDGE (lead-supplied): sets: "none relevant" | "x"; rules/sample-rule.md L3: "a long enough verbatim excerpt here"')")"
expect_eq "a none phrase inside sets does not flip a cited verdict: allow" "0|" "$RC|$OUT"
brief "$(task_json s-cit Task general-purpose unit-quoted "$(with_block 'KNOWLEDGE (lead-supplied): sets: "a" | "b"; rules/sample-rule.md L3: "none relevant wording inside the excerpt, long enough"')")"
expect_eq "a none phrase inside an excerpt does not flip a cited verdict: allow" "0|" "$RC|$OUT"

echo "18. the allow of a cited verdict is logged with its detail"
expect_eq "cited allow: the logged detail names one note and one excerpt" "yes" "$([ "$(log_detail_count s-cit allow-cited "1 notes, 1 excerpts")" -ge 1 ] && printf yes || printf no)"

echo "19. none through the hook"
seed_fresh s-none-fresh 2
brief "$(task_json s-none-fresh Task general-purpose unit-none "$P_NONE")"
expect_eq "none with two fresh searches: silent allow" "0|" "$RC|$OUT"
expect_eq "none with two fresh searches: allow-none logged" 1 "$(log_count s-none-fresh allow-none)"
seed_fresh s-none-one 1
brief "$(task_json s-none-one Task general-purpose unit-none1 "$P_NONE")"
expect_eq "none with one fresh search: deny" "deny" "$(decision_of "$OUT")"
expect_has "none with one fresh search: found 1" "(found 1)" "$(reason_of "$OUT")"
brief "$(task_json s-none-nofile Task general-purpose unit-none "$P_NONE")"
expect_eq "none without any search file: deny" "deny" "$(decision_of "$OUT")"
expect_has "none without any search file: found 0" "(found 0)" "$(reason_of "$OUT")"
seed_lookup s-none-old "$(iso_ago 7200)"
brief "$(task_json s-none-old Task general-purpose unit-none "$P_NONE")"
expect_eq "none with a two-hour-old search line: deny" "deny" "$(decision_of "$OUT")"
expect_has "none deny names the window and the count" "within the last 1800s (found 0)" "$(reason_of "$OUT")"
seed_lookup s-none-win "$(iso_ago 120)"
seed_lookup s-none-win "$(iso_ago 120)"
brief "$(task_json s-none-win Task general-purpose unit-none "$P_NONE")" CLAUDE_KNOWLEDGE_BRIEF_WINDOW=60
expect_eq "window 60 s with two 120 s old searches: deny" "deny" "$(decision_of "$OUT")"
brief "$(task_json s-none-win Task general-purpose unit-none "$P_NONE")" CLAUDE_KNOWLEDGE_BRIEF_WINDOW=300
expect_eq "window 300 s with the same two searches: allow" "0|" "$RC|$OUT"
brief "$(task_json s-none-path Task general-purpose unit-none-path "$(with_block 'KNOWLEDGE: none relevant after 2 searches — sets: "a" | "b"; see rules/sample-rule.md for context')")"
expect_eq "none block that names a path: deny (no fresh search)" "deny" "$(decision_of "$OUT")"
expect_has "none block naming a path: the none cause is reported" "none-relevant verdict" "$(reason_of "$OUT")"
expect_lacks "none block naming a path: not treated as a cited note" "not found in the library" "$(reason_of "$OUT")"
seed_lookup s-none-bad "not-a-timestamp"
seed_lookup s-none-bad "$(iso_ago 0)"
brief "$(task_json s-none-bad Task general-purpose unit-none "$P_NONE")"
expect_eq "none with an unparsable stamp and one fresh search: deny" "deny" "$(decision_of "$OUT")"
expect_has "none with an unparsable stamp: counted one" "(found 1)" "$(reason_of "$OUT")"

echo "20. unavailable and marker variants through the hook"
brief "$(task_json s-un Task general-purpose unit-un "$P_UNAV")"
expect_eq "unavailable with a reason and no mark: deny" "deny" "$(decision_of "$OUT")"
brief "$(task_json s-kbm Task knowledge-agent knowledge-agent d "$P_MISSING")"
brief "$(task_json s-kbm Task general-purpose unit-kbm "$P_UNAV")"
expect_eq "after one exempt knowledge-agent dispatch through the hook: unavailable allowed" "0|" "$RC|$OUT"
expect_eq "unavailable allowed: allow-unavailable logged once" 1 "$(log_count s-kbm allow-unavailable)"
seed_dispatch s-un
brief "$(task_json s-un Task general-purpose unit-un2 "$P_UNAV")"
expect_eq "unavailable with a mark: silent allow" "0|" "$RC|$OUT"
seed_dispatch s-wis
brief "$(task_json s-wis Task general-purpose unit-wis "$(with_block 'WISSEN: sets: "a"; rules/sample-rule.md L3: "ein ausreichend langer Auszug aus der Regel"')")"
expect_eq "WISSEN marker with a cited note: allow" "0|" "$RC|$OUT"
brief "$(task_json s-dec Task general-purpose unit-dec "$(with_block '- **KNOWLEDGE (lead-supplied):** sets: "a"; rules/sample-rule.md L3: "a long enough verbatim excerpt here"')")"
expect_eq "decorated marker with a cited note: allow" "0|" "$RC|$OUT"
seed_fresh s-wnone 2
brief "$(task_json s-wnone Task general-purpose unit-wnone "$(with_block 'WISSEN: nichts passendes gefunden nach zwei Suchen — sets: "a" | "b"')")"
expect_eq "WISSEN none phrase with two fresh searches: allow" "0|" "$RC|$OUT"
brief "$(task_json s-upper Task general-purpose unit-upper "$(with_block 'Knowledge: see below for the field.

KNOWLEDGE: none relevant after 2 searches — sets: "a" | "b"')")"
expect_eq "prose 'Knowledge:' above a real field: the real none field wins (deny, no searches)" "deny" "$(decision_of "$OUT")"
expect_has "prose 'Knowledge:' above a real field: the none cause" "none-relevant verdict" "$(reason_of "$OUT")"
seed_fresh s-fence 2
brief "$(task_json s-fence Task general-purpose unit-fence "$(with_block '```
KNOWLEDGE: unavailable — fenced example text inside the code fence
```')")"
expect_eq "a marker inside a fence is ignored: no field, deny" "deny" "$(decision_of "$OUT")"
expect_has "a marker inside a fence is ignored: the missing-field cause" "no KNOWLEDGE field" "$(reason_of "$OUT")"
seed_dispatch s-two
brief "$(task_json s-two Task general-purpose unit-two-m "$(with_block 'KNOWLEDGE: none relevant after 2 searches — sets: "a" | "b"

KNOWLEDGE: unavailable — the last marker wins and its reason is long enough')")"
expect_eq "two markers through the hook: the last (unavailable with a mark) wins: allow" "0|" "$RC|$OUT"
expect_eq "two markers through the hook: logged allow-unavailable" 1 "$(log_count s-two allow-unavailable)"
brief "$(task_json s-crlf Task general-purpose unit-crlf "$(printf 'Unit.\r\n\r\nKNOWLEDGE (lead-supplied): sets: "a"; rules/sample-rule.md L3: "a long enough verbatim excerpt here"\r\n\r\nTask.\r\n')")"
expect_eq "CRLF prompt with a cited verdict: same verdict as LF: allow" "0|" "$RC|$OUT"
expect_eq "CRLF prompt: logged allow-cited" 1 "$(log_count s-crlf allow-cited)"

echo "20b. second review: evidence rules and the shared counter key, through the hook"
UNAV_PAD=$(printf ' %.0s' $(seq 1 30))
brief "$(task_json s-rv Task general-purpose unit-rv1 "$(with_block "KNOWLEDGE: unavailable${UNAV_PAD}")")"
expect_eq "unavailable with spaces only (no reason): deny" "deny" "$(decision_of "$OUT")"
EM7=$(printf '—%.0s' 1 2 3 4 5 6 7)
seed_dispatch s-rv
brief "$(task_json s-rv Task general-purpose unit-rv2 "$(with_block "KNOWLEDGE: unavailable ${EM7}${UNAV_PAD}")")"
expect_eq "unavailable with seven em dashes and spaces, with a mark: deny" "deny" "$(decision_of "$OUT")"
brief "$(task_json s-rv Task general-purpose unit-rv3 "$(with_block 'KNOWLEDGE: Mirror check: unavailable — abcdefghijklmnopqrst')")"
expect_eq "unavailable with exactly 20 bytes of reason and a mark: allow" "0|" "$RC|$OUT"
brief "$(task_json s-rv Task general-purpose unit-rv4 "$(with_block 'KNOWLEDGE: Mirror check: unavailable — abcdefghijklmnopqrs')")"
expect_eq "unavailable with 19 bytes of reason: deny" "deny" "$(decision_of "$OUT")"
seed_fresh s-rvn 2
brief "$(task_json s-rvn Task general-purpose unit-rvn "$(with_block 'KNOWLEDGE: none relevant after 2 searches — nothing named here at all')")"
expect_has "none without sets, two runs: deny naming the sets" "must name the sets searched" "$(reason_of "$OUT")"
seed_lookup s-rvo "$(iso_ago 0)" ka-one
seed_lookup s-rvo "$(iso_ago 0)" ka-one
brief "$(task_json s-rvo Task general-purpose unit-rvo "$P_NONE")"
expect_has "none: two lines from one agent id: deny (found 1)" "(found 1)" "$(reason_of "$OUT")"
seed_fresh s-rvt 2
brief "$(task_json s-rvt Task general-purpose unit-rvt "$P_NONE")"
expect_eq "none: two agent ids: allow" "0|" "$RC|$OUT"
brief "$(task_json s-rm Task general-purpose unit-rm "$(with_block 'KNOWLEDGE (lead-supplied): sets: "tool-discipline.md foo" | "x"; rules/sample-rule.md L3: "a verbatim excerpt from the sample rule text"')")"
expect_eq "a .md inside sets plus a real cited path: allow" "0|" "$RC|$OUT"
brief "$(task_json s-rm Task general-purpose unit-rm2 "$(with_block 'KNOWLEDGE (lead-supplied): sets: "tool-discipline.md foo" | "x"; "a verbatim excerpt of enough length here"')")"
expect_has "a .md only inside sets: deny, names no note outside the sets clause" "names no note outside its sets clause" "$(reason_of "$OUT")"
EXPECT_CK=$(printf '%s\n%s' "general-purpose" "unit-ck" | shasum | awk '{print $1}')
brief "$(task_json s-ck Task general-purpose unit-ck "$P_MISSING")"
expect_eq "the hook's denial counter is named by the shared key kb_counter_key" "1" "$(cat "$STATE/knowledge-gate-s-ck/brief-denials-$EXPECT_CK" 2>/dev/null)"

echo "21. UTF-8 locale: umlauts give the same verdicts"
brief "$(task_json s-de Task general-purpose unit-de "$(with_block 'KNOWLEDGE (lead-supplied): sets: "Änderungsprotokoll" | "Veröffentlichung"; rules/sample-rule.md L3: "Übersicht der Veröffentlichung, mit Umlauten im Auszug"')")" LANG=de_DE.UTF-8
expect_eq "de_DE.UTF-8: cited block with umlauts: silent allow" "0|" "$RC|$OUT"
brief "$(task_json s-de Task general-purpose unit-de2 "$(with_block 'KNOWLEDGE: Übersicht ohne Verdikt, nur Prosa über Veröffentlichung und Änderungen')")" LANG=de_DE.UTF-8
expect_eq "de_DE.UTF-8: umlaut prose without a verdict: deny" "deny" "$(decision_of "$OUT")"
expect_eq "de_DE.UTF-8: exit 0" 0 "$RC"

echo "22. the hook's own sizes, log shape and the sibling hooks it must agree with"
expect_eq "log exists and is not empty" "yes" "$([ -s "$LOGF" ] && printf yes || printf no)"
expect_eq "log lines all carry six TSV fields" "0" "$(LC_ALL=C awk -F '\t' 'NF != 6' "$LOGF" 2>/dev/null | wc -l | tr -d ' ')"
expect_eq "state dir name is read from knowledge-gate.sh and knowledge-record.sh" "yes" "$(grep -qF "knowledge-gate-\$SAFE_SID" "$HOOKS_DIR/knowledge-gate.sh" && grep -qF "knowledge-gate-\$SAFE_SID" "$HOOKS_DIR/knowledge-record.sh" && printf yes || printf no)"
expect_eq "state dir name is read from knowledge-inject.sh" "yes" "$(grep -qF "knowledge-gate-\$SESSION" "$HOOKS_DIR/knowledge-inject.sh" && printf yes || printf no)"
expect_eq "the knowledge-agent marker file name matches knowledge-record.sh" "yes" "$(grep -qF 'knowledge-agent-lookups' "$HOOKS_DIR/knowledge-record.sh" && printf yes || printf no)"
expect_eq "hook is at most 250 lines" "yes" "$([ "$(wc -l < "$HOOK" | tr -d ' ')" -le 250 ] && printf yes || printf no)"
expect_eq "library is at most 300 lines" "yes" "$([ "$(wc -l < "$LIBF" | tr -d ' ')" -le 300 ] && printf yes || printf no)"
expect_eq "the four hook files cite no private memo path, no session count and no 'decision memo'" "" "$(grep -l -e 'knowledge-reach-decision' -e ' 585 ' -e ' 598 ' -e 'decision memo' "$HOOK" "$LIBF" "$HOOKS_DIR/knowledge-gate.sh" "$HOOKS_DIR/knowledge-record.sh" "$HOOKS_DIR/knowledge-inject.sh" 2>/dev/null)"
expect_eq "the check calls kb_counter_key and the inject helper (denial_count) calls it too" "yes" "$(grep -q 'kb_counter_key' "$HOOK" && grep -q 'kb_counter_key' "$HOOKS_DIR/lib/knowledge-inject-lib.sh" && printf yes || printf no)"

echo "23. fail-open paths are logged with a TSV line"
expect_eq "fail-open: a non-JSON input leaves a log line (not-json)" "1" "$(log_count - not-json)"
expect_eq "fail-open: an empty session leaves a log line (no-session)" "1" "$(log_count - no-session)"
expect_eq "fail-open: unknown mode leaves a log line (mode-fallback)" "1" "$(log_count s-bogus mode-fallback)"
expect_eq "fail-open: a corrupt counter leaves a log line (counter-reset)" "1" "$(log_count s-cor counter-reset)"
expect_eq "fail-open: a missing parser leaves a log line (parser-missing)" "1" "$(log_count s-nopar parser-missing)"

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
