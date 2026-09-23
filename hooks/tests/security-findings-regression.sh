#!/bin/bash
# security-findings-regression.sh — regression suite for
# scripts/security-review-findings.sh + hooks/security-findings-check.sh
# (IMP-207, 2026-09-09).
#
# Runs ENTIRELY against synthetic fixtures in scratch directories — never
# reads or writes ~/.claude/global-observation/ or ~/.claude/projects/, and
# never touches the real improvement-ledger.json (a scratch ledger is used
# for the --to-ledger cases).
#
# Usage: bash hooks/tests/security-findings-regression.sh
# Exit: 0 = all cases passed, 1 = at least one failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXTRACTOR="${CLAUDE_SEC_FINDINGS_EXTRACTOR:-$REPO_ROOT/scripts/security-review-findings.sh}"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../security-findings-check.sh}"
LEDGER_APPEND="$REPO_ROOT/scripts/ledger-append-proposed.sh"

[[ -f "$EXTRACTOR" ]] || { echo "ERROR: extractor not found: $EXTRACTOR" >&2; exit 1; }
[[ -f "$HOOK" ]]      || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }
[[ -f "$LEDGER_APPEND" ]] || { echo "ERROR: ledger-append-proposed.sh not found: $LEDGER_APPEND" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     %s\n' "$1" "$2"; }

fresh_env() {
    # fresh_env -> prints a scratch dir; sets up ROOT/OUT/STATE/SEEN/ACK/LEDGER
    # under it as global vars for the caller (D, ROOT, OUT, STATE, SEEN, ACK, LEDGERFILE).
    D=$(mktemp -d "${TMPDIR:-/tmp}/sec-findings-test.XXXXXX")
    ROOT="$D/projects"
    OUT="$D/out.jsonl"
    STATE="$D/state.json"
    SEEN="$D/seen.txt"
    ACK="$D/ack.txt"
    LEDGERFILE="$D/ledger.json"
    mkdir -p "$ROOT"
    echo '{}' > "$LEDGERFILE"
}

run_extractor() {   # run_extractor <extra args...>
    CLAUDE_SEC_FINDINGS_ROOT="$ROOT" \
    CLAUDE_SEC_FINDINGS_OUT="$OUT" \
    CLAUDE_SEC_FINDINGS_STATE="$STATE" \
    CLAUDE_SEC_FINDINGS_SEEN="$SEEN" \
    CLAUDE_SEC_FINDINGS_ACK="$ACK" \
    CLAUDE_LEDGER_APPEND_SCRIPT="$LEDGER_APPEND" \
    CLAUDE_LEDGER_FILE="$LEDGERFILE" \
    bash "$EXTRACTOR" "$@" 2>&1
}

run_hook() {   # run_hook <cwd>
    CLAUDE_SEC_FINDINGS_SCRIPT="$EXTRACTOR" \
    CLAUDE_SEC_FINDINGS_OUT="$OUT" \
    CLAUDE_SEC_FINDINGS_ACK="$ACK" \
    CLAUDE_SEC_FINDINGS_HOOK_CWD="$1" \
    bash "$HOOK" </dev/null 2>&1
}

# write_review SESSIONFILE TS FINDINGS_JSON — a single-shot accepted review
write_review() {
    local f="$1" ts="$2" findings="$3"
    cat > "$f" <<EOF
{"type":"user","entrypoint":"sdk-py","message":{"role":"user","content":"Review this change for security vulnerabilities.\n\nChanged files (you may Read these and any other file in the repo):\n  - some/file.sh"},"timestamp":"$ts"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_a1","name":"StructuredOutput","input":{"findings":$findings}}]},"timestamp":"$ts"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_a1","content":"Structured output provided successfully"}]},"timestamp":"$ts"}
EOF
}

# write_incomplete SESSIONFILE TS — a review session with no accepted result
write_incomplete() {
    local f="$1" ts="$2"
    cat > "$f" <<EOF
{"type":"user","entrypoint":"sdk-py","message":{"role":"user","content":"Review this change for security vulnerabilities.\n\nChanged files:\n  - some/file.sh"},"timestamp":"$ts"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_i1","name":"Read","input":{"file_path":"some/file.sh"}}]},"timestamp":"$ts"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_i1","content":"1\\tfile contents"}]},"timestamp":"$ts"}
EOF
}

# write_false_positive SESSIONFILE TS — cli entrypoint, marker text present
# and even LEADING the message (mirrors the real incident: a user pasting
# this exact task's own prompt into an interactive session).
write_false_positive() {
    local f="$1" ts="$2"
    cat > "$f" <<EOF
{"type":"user","entrypoint":"cli","message":{"role":"user","content":"Review this change for security vulnerabilities. (this is a chat message ABOUT the reviewer, not the reviewer itself)"},"timestamp":"$ts"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok, noted"}]},"timestamp":"$ts"}
EOF
}

# write_retry SESSIONFILE TS — first StructuredOutput call rejected by
# schema validation (is_error:true), second (different finding count)
# accepted. Mirrors the real Projekt A aaaa0004 case: 1 finding -> corrected 0.
write_retry() {
    local f="$1" ts="$2"
    cat > "$f" <<EOF
{"type":"user","entrypoint":"sdk-py","message":{"role":"user","content":"Review this change for security vulnerabilities.\n\nChanged files:\n  - some/file.sh"},"timestamp":"$ts"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_r1","name":"StructuredOutput","input":{"findings":[{"filePath":"c.sh","category":"cat-z","severity":"high","confidence":0.9,"vulnerableCode":"x","explanation":"explanation C","fix":"fix C"}]}}]},"timestamp":"$ts"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_r1","content":"Output does not match required schema: /findings: must be array","is_error":true}]},"timestamp":"$ts"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_r2","name":"StructuredOutput","input":{"findings":[]}}]},"timestamp":"$ts"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_r2","content":"Structured output provided successfully"}]},"timestamp":"$ts"}
EOF
}

echo "── security-review-findings.sh + security-findings-check.sh regression (IMP-207) ──"

# ── Case 1: detection — genuine sdk-py review recognized, cli false-positive
#    (marker text present, even leading) correctly excluded from N_REVIEW. ──
fresh_env
mkdir -p "$ROOT/proj-a"
write_review "$ROOT/proj-a/sess-1.jsonl" "2026-08-20T10:00:00.000Z" '[]'
write_false_positive "$ROOT/proj-a/sess-fp.jsonl" "2026-08-20T10:05:00.000Z"
out=$(run_extractor --dry-run)
if printf '%s' "$out" | grep -q "confirmed non-review (false positive): 1" && printf '%s' "$out" | grep -q "review sessions confirmed: 1"; then
    ok "detection: genuine sdk-py review counted, cli false-positive excluded"
else
    bad "detection: genuine vs false-positive session classification" "$out"
fi
rm -rf "$D"

# ── Case 2: field extraction — every documented field lands correctly in OUT. ──
fresh_env
mkdir -p "$ROOT/proj-b"
write_review "$ROOT/proj-b/sess-2.jsonl" "2026-08-20T11:00:00.000Z" \
  '[{"filePath":"hooks/foo.sh","category":"cat-x","severity":"high","confidence":0.9,"vulnerableCode":"vc","explanation":"explanation A","fix":"fix A"}]'
run_extractor >/dev/null
row=$(jq -c 'select(.file=="hooks/foo.sh")' "$OUT" 2>/dev/null)
if [[ -n "$row" ]] \
   && [[ "$(printf '%s' "$row" | jq -r '.severity')" == "high" ]] \
   && [[ "$(printf '%s' "$row" | jq -r '.category')" == "cat-x" ]] \
   && [[ "$(printf '%s' "$row" | jq -r '.summary')" == "explanation A" ]] \
   && [[ "$(printf '%s' "$row" | jq -r '.fix')" == "fix A" ]] \
   && [[ "$(printf '%s' "$row" | jq -r '.session_id')" == "sess-2" ]] \
   && [[ "$(printf '%s' "$row" | jq -r '.project')" == "proj-b" ]] \
   && [[ "$(printf '%s' "$row" | jq -r '.ts')" == "2026-08-20T11:00:00.000Z" ]]; then
    ok "field extraction: file/severity/category/summary/fix/session_id/project/ts all correct"
else
    bad "field extraction" "row: $row"
fi
rm -rf "$D"

# ── Case 3: idempotency — running twice does not duplicate the OUT row. ──
fresh_env
mkdir -p "$ROOT/proj-c"
write_review "$ROOT/proj-c/sess-3.jsonl" "2026-08-20T12:00:00.000Z" \
  '[{"filePath":"x.sh","category":"c","severity":"low","confidence":0.5,"vulnerableCode":"v","explanation":"e","fix":"f"}]'
run_extractor >/dev/null
n1=$(wc -l < "$OUT" | tr -d ' ')
out2=$(run_extractor)
n2=$(wc -l < "$OUT" | tr -d ' ')
# Two independent nets both hold: the STATE watermark makes the 2nd run skip
# re-parsing this already-resolved, mtime-unchanged session entirely (so it
# never even becomes a "candidate" the 2nd time — that IS the watermark
# working, not a bug), and even if it HAD been re-parsed, the SEEN dedup net
# would have caught it as a duplicate rather than double-writing it. Either
# way the observable invariant is: the OUT line count never grows on rerun.
if [[ "$n1" -eq 1 && "$n2" -eq 1 ]] && printf '%s' "$out2" | grep -q "finding candidates this run: 0"; then
    ok "idempotency: second run adds no duplicate row (still 1 line; watermark skipped the re-scan)"
else
    bad "idempotency" "n1=$n1 n2=$n2 out2: $out2"
fi

# Prove the SECOND net (SEEN dedup) independently: force a re-parse by
# invalidating the STATE cache, and confirm the row still doesn't duplicate.
echo '{}' > "$STATE"
out3=$(run_extractor)
n3=$(wc -l < "$OUT" | tr -d ' ')
if [[ "$n3" -eq 1 ]] && printf '%s' "$out3" | grep -q "duplicate(already recorded): 1"; then
    ok "idempotency: with the watermark invalidated (forced re-parse), the SEEN dedup net independently prevents a duplicate row"
else
    bad "idempotency (SEEN dedup net with invalidated watermark)" "n3=$n3 out3: $out3"
fi
rm -rf "$D"

# ── Case 4: --since filtering by the finding's OWN record timestamp. ──
fresh_env
mkdir -p "$ROOT/proj-d"
write_review "$ROOT/proj-d/sess-old.jsonl" "2026-07-01T09:00:00.000Z" \
  '[{"filePath":"old.sh","category":"c","severity":"low","confidence":0.5,"vulnerableCode":"v","explanation":"old finding","fix":"f"}]'
write_review "$ROOT/proj-d/sess-new.jsonl" "2026-08-24T09:00:00.000Z" \
  '[{"filePath":"new.sh","category":"c","severity":"low","confidence":0.5,"vulnerableCode":"v","explanation":"new finding","fix":"f"}]'
run_extractor --since 2026-08-01 >/dev/null
has_old=$(jq -c 'select(.file=="old.sh")' "$OUT" 2>/dev/null)
has_new=$(jq -c 'select(.file=="new.sh")' "$OUT" 2>/dev/null)
if [[ -z "$has_old" && -n "$has_new" ]]; then
    ok "--since 2026-08-01: excludes the 2026-07-01 finding, includes the 2026-08-24 one"
else
    bad "--since filtering" "has_old='$has_old' has_new='$has_new'"
fi
rm -rf "$D"

# ── Case 5: --ack excludes a session from --to-ledger; unacked passes through
#    to ledger-append-proposed.sh in dry-run without touching the real ledger. ──
fresh_env
mkdir -p "$ROOT/proj-e"
write_review "$ROOT/proj-e/sess-ack.jsonl" "2026-08-24T10:00:00.000Z" \
  '[{"filePath":"e.sh","category":"cat-e","severity":"medium","confidence":0.7,"vulnerableCode":"v","explanation":"exp E","fix":"fix E"}]'
CLAUDE_SEC_FINDINGS_LEDGER_PROJECT="proj-e" run_extractor >/dev/null
out_before=$(CLAUDE_SEC_FINDINGS_LEDGER_PROJECT="proj-e" run_extractor --dry-run --to-ledger)
if printf '%s' "$out_before" | grep -q "1 unacked finding"; then
    ok "--to-ledger (before ack): finds the 1 unacked finding"
else
    bad "--to-ledger before ack" "$out_before"
fi
run_extractor --ack sess-ack >/dev/null
out_after=$(CLAUDE_SEC_FINDINGS_LEDGER_PROJECT="proj-e" run_extractor --dry-run --to-ledger)
if printf '%s' "$out_after" | grep -q "no unacked findings"; then
    ok "--ack sess-ack then --to-ledger: 0 unacked findings (excluded)"
else
    bad "--to-ledger after ack" "$out_after"
fi
ledger_after=$(jq -c '[.. | objects | .id? // empty]' "$LEDGERFILE" 2>/dev/null)
if [[ "$ledger_after" == "[]" ]]; then
    ok "--to-ledger --dry-run never wrote to the scratch ledger"
else
    bad "--to-ledger --dry-run must not write" "ledger ids present: $ledger_after"
fi
rm -rf "$D"

# ── Case 6: hook is silent when OUT has nothing for the current project. ──
fresh_env
mkdir -p "$ROOT/proj-f"
write_review "$ROOT/proj-f/sess-f.jsonl" "2026-08-24T10:00:00.000Z" \
  '[{"filePath":"f.sh","category":"c","severity":"low","confidence":0.5,"vulnerableCode":"v","explanation":"e","fix":"f"}]'
run_extractor >/dev/null
out=$(run_hook "/some/totally/unrelated/project")
if [[ -z "$out" ]]; then
    ok "hook: silent when no OUT rows match the current project"
else
    bad "hook: silent for non-matching project" "unexpected output: $out"
fi
rm -rf "$D"

# ── Case 7: hook prints exactly one correct line for a matching, unacked,
#    in-window finding — names the count, file, severity, and an --ack hint
#    naming the right session_id. ──
fresh_env
mkdir -p "$ROOT/-Volumes-Test-myproj"
recent_ts=$(date -u -v-2d +"%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null || date -u -d '-2 days' +"%Y-%m-%dT%H:%M:%S.000Z")
write_review "$ROOT/-Volumes-Test-myproj/sess-recent.jsonl" "$recent_ts" \
  '[{"filePath":"hooks/risky.sh","category":"cat-g","severity":"high","confidence":0.9,"vulnerableCode":"v","explanation":"a risky pattern was found here","fix":"fix it"}]'
run_extractor >/dev/null
out=$(run_hook "/Volumes/Test/myproj")
if printf '%s' "$out" | grep -q "^🔐 1 ungesichtete Sicherheitsbefunde" \
   && printf '%s' "$out" | grep -q "hooks/risky.sh" \
   && printf '%s' "$out" | grep -q "\[high\]" \
   && printf '%s' "$out" | grep -q -- "--ack sess-recent"; then
    ok "hook: one matching finding -> exactly one correctly-worded line"
else
    bad "hook: single-finding line content" "$out"
fi
rm -rf "$D"

# ── Case 8: incomplete session (no accepted StructuredOutput) is neither
#    counted as clean NOR written as a finding row. ──
fresh_env
mkdir -p "$ROOT/proj-h"
write_incomplete "$ROOT/proj-h/sess-incomplete.jsonl" "2026-08-24T10:00:00.000Z"
out=$(run_extractor --dry-run)
n_out=$(wc -l < "$OUT" | tr -d ' ')
if printf '%s' "$out" | grep -q "incomplete(no accepted result yet): 1" \
   && printf '%s' "$out" | grep -q "clean(0 findings): 0" \
   && [[ "$n_out" -eq 0 ]]; then
    ok "incomplete session: counted as incomplete, not clean, no OUT row"
else
    bad "incomplete session handling" "out: $out / OUT lines: $n_out"
fi
rm -rf "$D"

# ── Case 9: retry handling — first (rejected) StructuredOutput call had 1
#    finding, the ACCEPTED second call has 0 -> must resolve to 0 (clean),
#    never to the rejected call's 1. ──
fresh_env
mkdir -p "$ROOT/proj-i"
write_retry "$ROOT/proj-i/sess-retry.jsonl" "2026-08-23T11:00:00.000Z"
out=$(run_extractor --dry-run)
n_out=$(wc -l < "$OUT" 2>/dev/null | tr -d ' ')
if printf '%s' "$out" | grep -q "clean(0 findings): 1" && [[ "${n_out:-0}" -eq 0 ]]; then
    ok "retry handling: the ACCEPTED (2nd) call's 0 findings wins over the rejected 1st call's 1"
else
    bad "retry handling" "out: $out / OUT lines: ${n_out:-0}"
fi
rm -rf "$D"

# ── Case 10: two findings in ONE session get two DISTINCT dedup'd rows
#    (not collapsed, not merged). ──
fresh_env
mkdir -p "$ROOT/proj-j"
write_review "$ROOT/proj-j/sess-multi.jsonl" "2026-08-24T10:00:00.000Z" \
  '[{"filePath":"m1.sh","category":"c1","severity":"high","confidence":0.9,"vulnerableCode":"v1","explanation":"e1","fix":"f1"},{"filePath":"m2.sh","category":"c2","severity":"low","confidence":0.5,"vulnerableCode":"v2","explanation":"e2","fix":"f2"}]'
run_extractor >/dev/null
n_out=$(wc -l < "$OUT" | tr -d ' ')
has_m1=$(jq -c 'select(.file=="m1.sh" and .category=="c1")' "$OUT" 2>/dev/null)
has_m2=$(jq -c 'select(.file=="m2.sh" and .category=="c2")' "$OUT" 2>/dev/null)
if [[ "$n_out" -eq 2 && -n "$has_m1" && -n "$has_m2" ]]; then
    ok "multi-finding session: 2 findings -> 2 distinct OUT rows"
else
    bad "multi-finding dedup/indexing" "n_out=$n_out has_m1='$has_m1' has_m2='$has_m2'"
fi
rm -rf "$D"

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
