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
    UPSTREAM="$D/upstream-findings.md"
    MANIFEST="$D/no-manifest.txt"   # absent by default: no live-only manifest
    mkdir -p "$ROOT"
    echo '{}' > "$LEDGERFILE"
}

run_extractor() {   # run_extractor <extra args...>
    CLAUDE_SEC_FINDINGS_ROOT="$ROOT" \
    CLAUDE_SEC_FINDINGS_OUT="$OUT" \
    CLAUDE_SEC_FINDINGS_STATE="$STATE" \
    CLAUDE_SEC_FINDINGS_SEEN="$SEEN" \
    CLAUDE_SEC_FINDINGS_ACK="$ACK" \
    CLAUDE_SEC_FINDINGS_UPSTREAM="$UPSTREAM" \
    CLAUDE_SEC_FINDINGS_MANIFEST="$MANIFEST" \
    CLAUDE_LEDGER_APPEND_SCRIPT="$LEDGER_APPEND" \
    CLAUDE_LEDGER_FILE="$LEDGERFILE" \
    bash "$EXTRACTOR" "$@" 2>&1
}

# run_hook <cwd>: every path the hook's embedded extractor run could touch is
# pinned to this scratch fixture. Without the pins the hook would scan the REAL
# ~/.claude/projects and write the REAL state/seen/upstream files.
run_hook() {
    CLAUDE_SEC_FINDINGS_SCRIPT="$EXTRACTOR" \
    CLAUDE_SEC_FINDINGS_ROOT="$ROOT" \
    CLAUDE_SEC_FINDINGS_OUT="$OUT" \
    CLAUDE_SEC_FINDINGS_STATE="$STATE" \
    CLAUDE_SEC_FINDINGS_SEEN="$SEEN" \
    CLAUDE_SEC_FINDINGS_ACK="$ACK" \
    CLAUDE_SEC_FINDINGS_UPSTREAM="$UPSTREAM" \
    CLAUDE_SEC_FINDINGS_MANIFEST="$MANIFEST" \
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
# accepted. Mirrors a real observed case: 1 finding -> corrected 0.
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
mkdir -p "$ROOT/-Volumes-example-myproj"
recent_ts=$(date -u -v-2d +"%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null || date -u -d '-2 days' +"%Y-%m-%dT%H:%M:%S.000Z")
write_review "$ROOT/-Volumes-example-myproj/sess-recent.jsonl" "$recent_ts" \
  '[{"filePath":"hooks/risky.sh","category":"cat-g","severity":"high","confidence":0.9,"vulnerableCode":"v","explanation":"a risky pattern was found here","fix":"fix it"}]'
run_extractor >/dev/null
out=$(run_hook "/Volumes/example/myproj")
if printf '%s' "$out" | grep -q "^🔐 1 unreviewed security findings" \
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

# ── P-IMP-264: dedup + vendor routing (cases 11-19) ──────────────────────────
ago() {   # ago DAYS -> ISO-8601 UTC timestamp, DAYS days before now
    date -u -v-"$1"d +"%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null || date -u -d "-$1 days" +"%Y-%m-%dT%H:%M:%S.000Z"
}
one_finding() {   # one_finding FILE CATEGORY SUMMARY -> JSON array with one finding
    printf '[{"filePath":"%s","category":"%s","severity":"high","confidence":0.9,"vulnerableCode":"v","explanation":"%s","fix":"fix it"}]' "$1" "$2" "$3"
}

# ── Case 11: same finding twice within 7 days -> second marked duplicate_of,
#    only one unacked finding in the SessionStart line. ──
fresh_env
mkdir -p "$ROOT/-Volumes-example-dedup"
F="$(one_finding 'hooks/dup.sh' 'cat-d' 'the same explanation text')"
write_review "$ROOT/-Volumes-example-dedup/sess-d1.jsonl" "$(ago 9)" "$F"
write_review "$ROOT/-Volumes-example-dedup/sess-d2.jsonl" "$(ago 3)" "$F"
run_extractor >/dev/null
n_out=$(wc -l < "$OUT" | tr -d ' ')
d1_dup=$(jq -r 'select(.session_id=="sess-d1") | .duplicate_of // "null"' "$OUT")
d2_dup=$(jq -r 'select(.session_id=="sess-d2") | .duplicate_of // "null"' "$OUT")
out=$(run_hook "/Volumes/example/dedup")
if [[ "$n_out" -eq 2 && "$d1_dup" == "null" && "$d2_dup" == sess-d1@* ]] \
   && printf '%s' "$out" | grep -q "^🔐 1 unreviewed security findings"; then
    ok "dedup 7-day window: repeat within 7 days is written with duplicate_of and not counted as unacked"
else
    bad "dedup within the 7-day window" "n_out=$n_out d1=$d1_dup d2=$d2_dup out: $out"
fi
rm -rf "$D"

# ── Case 12: same finding 8 days later -> counted again (no duplicate_of). ──
fresh_env
mkdir -p "$ROOT/-Volumes-example-dedup"
F="$(one_finding 'hooks/dup.sh' 'cat-d' 'the same explanation text')"
write_review "$ROOT/-Volumes-example-dedup/sess-e1.jsonl" "$(ago 11)" "$F"
write_review "$ROOT/-Volumes-example-dedup/sess-e2.jsonl" "$(ago 3)" "$F"
run_extractor >/dev/null
e2_dup=$(jq -r 'select(.session_id=="sess-e2") | .duplicate_of // "null"' "$OUT")
out=$(run_hook "/Volumes/example/dedup")
if [[ "$e2_dup" == "null" ]] && printf '%s' "$out" | grep -q "^🔐 2 unreviewed security findings"; then
    ok "dedup window: the same finding 8 days later is counted again"
else
    bad "repeat after the 7-day window" "e2_dup=$e2_dup out: $out"
fi
rm -rf "$D"

# ── Case 13: vendor-owned path -> one upstream line (not a second line for the
#    repeat), excluded from the unacked count, summarised as the upstream token. ──
fresh_env
mkdir -p "$ROOT/-Volumes-example-vendor"
F="$(one_finding 'skills/synced/skill-creator/eval-viewer/generate_review.py' 'xss' 'unescaped html in the review page')"
write_review "$ROOT/-Volumes-example-vendor/sess-v1.jsonl" "$(ago 2)" "$F"
write_review "$ROOT/-Volumes-example-vendor/sess-v2.jsonl" "$(ago 1)" "$F"
run_extractor >/dev/null
v1_vendor=$(jq -r 'select(.session_id=="sess-v1") | .vendor' "$OUT")
n_upstream_lines=$(grep -c 'generate_review.py' "$UPSTREAM" 2>/dev/null)
out=$(run_hook "/Volumes/example/vendor")
if [[ "$v1_vendor" == "true" && "${n_upstream_lines:-0}" -eq 1 ]] \
   && grep -q '^- 20[0-9-]* skills/synced/skill-creator/eval-viewer/generate_review.py — xss: unescaped html' "$UPSTREAM" \
   && printf '%s' "$out" | grep -q "(+1 upstream, see plans/upstream-findings.md)" \
   && ! printf '%s' "$out" | grep -q "unreviewed"; then
    ok "vendor path: one upstream line for the key, not in the unacked count, reader prints the upstream token"
else
    bad "vendor-owned path routing" "vendor=$v1_vendor upstream_lines=${n_upstream_lines:-0} out: $out"
fi
rm -rf "$D"

# ── Case 14: non-vendor path unaffected: counted as unacked, no upstream file,
#    no upstream token. ──
fresh_env
mkdir -p "$ROOT/-Volumes-example-plain"
F="$(one_finding 'hooks/plain.sh' 'cat-p' 'plain explanation')"
write_review "$ROOT/-Volumes-example-plain/sess-p1.jsonl" "$(ago 2)" "$F"
run_extractor >/dev/null
p_vendor=$(jq -r '.vendor' "$OUT")
out=$(run_hook "/Volumes/example/plain")
if [[ "$p_vendor" == "false" && ! -e "$UPSTREAM" ]] \
   && printf '%s' "$out" | grep -q "^🔐 1 unreviewed" \
   && ! printf '%s' "$out" | grep -q "upstream"; then
    ok "non-vendor path: counted as unacked, no upstream file written, no upstream token"
else
    bad "non-vendor path must be unaffected" "vendor=$p_vendor out: $out"
fi
rm -rf "$D"

# ── Case 15: live-only-manifest.txt entries are shell globs (a directory entry
#    with a trailing slash, and a "*" glob); comment lines are ignored. ──
fresh_env
mkdir -p "$ROOT/-Volumes-example-manifest"
printf '# live-only paths\n\nmy-live-only/\nvend*/x.sh\n' > "$D/manifest.txt"
MANIFEST="$D/manifest.txt"
write_review "$ROOT/-Volumes-example-manifest/sess-m1.jsonl" "$(ago 2)" \
  "$(one_finding 'my-live-only/tool.sh' 'cat-m' 'live only explanation')"
write_review "$ROOT/-Volumes-example-manifest/sess-m2.jsonl" "$(ago 2)" \
  "$(one_finding 'vendored/x.sh' 'cat-g' 'glob explanation')"
run_extractor >/dev/null
m_vendors=$(jq -s -c '[.[].vendor]' "$OUT")
out=$(run_hook "/Volumes/example/manifest")
if [[ "$m_vendors" == "[true,true]" ]] && printf '%s' "$out" | grep -q "^🔐 (+2 upstream" \
   && ! printf '%s' "$out" | grep -q "unreviewed"; then
    ok "live-only manifest: a directory entry and a * glob are both routed upstream"
else
    bad "manifest-listed vendor paths" "vendors=$m_vendors out: $out"
fi
rm -rf "$D"

# ── Case 16: two different findings in the same file and category stay distinct. ──
fresh_env
mkdir -p "$ROOT/-Volumes-example-distinct"
write_review "$ROOT/-Volumes-example-distinct/sess-x1.jsonl" "$(ago 2)" \
  "$(one_finding 'hooks/same.sh' 'cat-s' 'first distinct explanation')"
write_review "$ROOT/-Volumes-example-distinct/sess-x2.jsonl" "$(ago 2)" \
  "$(one_finding 'hooks/same.sh' 'cat-s' 'second distinct explanation')"
run_extractor >/dev/null
n_out=$(wc -l < "$OUT" | tr -d ' ')
n_marked=$(jq -r 'select(.duplicate_of != null) | .session_id' "$OUT" | wc -l | tr -d ' ')
if [[ "$n_out" -eq 2 && "$n_marked" -eq 0 ]]; then
    ok "distinct findings in one file and category are not merged"
else
    bad "distinct findings must not collapse" "n_out=$n_out n_marked=$n_marked"
fi
rm -rf "$D"

# ── Case 17: a legacy row (no dedup fields, written before this change) is
#    matched by a new repeat: the new row carries duplicate_of, the legacy row
#    stays unrewritten and counted once. ──
fresh_env
mkdir -p "$ROOT/-Volumes-example-legacy"
F="$(one_finding 'hooks/legacy.sh' 'cat-l' 'legacy explanation')"
printf '%s\n' '{"ts":"'"$(ago 9)"'","session_id":"sess-legacy","project":"-Volumes-example-legacy","file":"hooks/legacy.sh","severity":"high","category":"cat-l","summary":"legacy explanation","fix":"fix it","source":"fixture"}' >> "$OUT"
echo "sess-legacy#0" >> "$SEEN"
write_review "$ROOT/-Volumes-example-legacy/sess-l2.jsonl" "$(ago 3)" "$F"
run_extractor >/dev/null
l2_dup=$(jq -r 'select(.session_id=="sess-l2") | .duplicate_of // "null"' "$OUT")
legacy_dup=$(jq -r 'select(.session_id=="sess-legacy") | .duplicate_of // "null"' "$OUT")
out=$(run_hook "/Volumes/example/legacy")
if [[ "$l2_dup" == sess-legacy@* && "$legacy_dup" == "null" ]] && printf '%s' "$out" | grep -q "^🔐 1 unreviewed"; then
    ok "legacy row: a new repeat is matched against it; the legacy row is not rewritten"
else
    bad "legacy row matching" "l2_dup=$l2_dup legacy_dup=$legacy_dup out: $out"
fi
rm -rf "$D"

# ── Case 18: --to-ledger sends the first-seen plain row only: no vendor row,
#    no repeat. ──
fresh_env
mkdir -p "$ROOT/proj-tl"
write_review "$ROOT/proj-tl/sess-tv1.jsonl" "$(ago 2)" \
  "$(one_finding 'skills/synced/x/vendor.py' 'cat-v' 'vendor explanation')"
write_review "$ROOT/proj-tl/sess-tp1.jsonl" "$(ago 2)" "$(one_finding 'hooks/tl.sh' 'cat-t' 'plain tl explanation')"
write_review "$ROOT/proj-tl/sess-tp2.jsonl" "$(ago 1)" "$(one_finding 'hooks/tl.sh' 'cat-t' 'plain tl explanation')"
run_extractor >/dev/null
out=$(CLAUDE_VAULT_SCRIPT=/nonexistent CLAUDE_SEC_FINDINGS_LEDGER_PROJECT="proj-tl" run_extractor --dry-run --to-ledger)
if printf '%s' "$out" | grep -q -- "--to-ledger: 1 unacked finding(s)"; then
    ok "--to-ledger: vendor-owned row and repeat are excluded, first-seen plain row is sent"
else
    bad "--to-ledger exclusion of vendor and repeat rows" "$out"
fi
rm -rf "$D"

# ── Case 19: --dry-run reports how many EXISTING feed rows are repeats and
#    writes nothing (OUT line count unchanged). ──
fresh_env
printf '%s\n' '{"ts":"'"$(ago 9)"'","session_id":"sess-h1","project":"proj-h","file":"hooks/h.sh","severity":"low","category":"c","summary":"history text","fix":"f","source":"fixture"}' >> "$OUT"
printf '%s\n' '{"ts":"'"$(ago 5)"'","session_id":"sess-h2","project":"proj-h","file":"hooks/h.sh","severity":"low","category":"c","summary":"history text","fix":"f","source":"fixture"}' >> "$OUT"
printf 'sess-h1#0\nsess-h2#0\n' >> "$SEEN"
out=$(run_extractor --dry-run)
n_out=$(wc -l < "$OUT" | tr -d ' ')
if printf '%s' "$out" | grep -q "existing feed rows that are repeats: 1 of 2" && [[ "$n_out" -eq 2 ]]; then
    ok "dry run: reports 1 of 2 existing rows as repeats and writes nothing"
else
    bad "dry-run repeat count over existing rows" "n_out=$n_out out: $out"
fi
rm -rf "$D"

echo "──────────────────────────────────────"
# ── Review fixes (2026-10-31): cases 20-26 ───────────────────────────────────

# ── Case 20 (finding 1): SIGKILL after a session is parsed, before its rows are
#    committed. STATE must NOT record it as resolved; the next run emits its row. ──
fresh_env
mkdir -p "$ROOT/-Volumes-example-kill"
write_review "$ROOT/-Volumes-example-kill/sess-k1.jsonl" "$(ago 2)" \
  "$(one_finding 'hooks/kill.sh' 'cat-k' 'kill explanation')"
CLAUDE_SEC_FINDINGS_TEST_KILL_AT="after-parse:sess-k1" run_extractor >/dev/null; kill_rc=$?
state_has=$(jq -r 'has("sess-k1")' "$STATE")
rows_after_kill=$(wc -l < "$OUT" | tr -d ' ')
run_extractor >/dev/null
state_count=$(jq -r '.["sess-k1"].findings_count // "none"' "$STATE")
rows_after_rerun=$(jq -c 'select(.session_id=="sess-k1")' "$OUT" | wc -l | tr -d ' ')
if [[ "$kill_rc" -ne 0 && "$state_has" == "false" && "$rows_after_kill" -eq 0 \
      && "$rows_after_rerun" -eq 1 && "$state_count" == "1" ]]; then
    ok "kill after parse: STATE does not record the session; the next run emits its row"
else
    bad "kill after parse must not poison the cache" "kill_rc=$kill_rc state_has=$state_has rows_after_kill=$rows_after_kill rows_after_rerun=$rows_after_rerun state_count=$state_count"
fi
rm -rf "$D"

# ── Case 21 (finding 1): SIGKILL between the OUT append and the SEEN append. No row is
#    lost; STATE does not record the session; the rerun warns that the feed is unpaired.
#    (The rerun re-emits the row marked duplicate_of the orphan copy: a known residual.) ──
fresh_env
mkdir -p "$ROOT/-Volumes-example-kill2"
write_review "$ROOT/-Volumes-example-kill2/sess-k2.jsonl" "$(ago 2)" \
  "$(one_finding 'hooks/kill2.sh' 'cat-k2' 'kill two explanation')"
CLAUDE_SEC_FINDINGS_TEST_KILL_AT="after-out:sess-k2" run_extractor >/dev/null; kill_rc=$?
state_has=$(jq -r 'has("sess-k2")' "$STATE")
out_rerun=$(run_extractor)
rows_k2=$(jq -c 'select(.session_id=="sess-k2")' "$OUT" | wc -l | tr -d ' ')
state_has2=$(jq -r 'has("sess-k2")' "$STATE")
if [[ "$kill_rc" -ne 0 && "$state_has" == "false" && "$rows_k2" -ge 1 && "$state_has2" == "true" ]] \
   && printf '%s' "$out_rerun" | grep -q "unpaired"; then
    ok "kill between OUT and SEEN: no row lost, STATE not recorded, rerun warns the feed is unpaired"
else
    bad "kill between OUT and SEEN" "kill_rc=$kill_rc state_has=$state_has rows_k2=$rows_k2 state_has2=$state_has2 rerun: $out_rerun"
fi
rm -rf "$D"

# ── Case 22 (finding 2): a --since run must not poison the cache: the older session
#    it filtered out is still emitted by a later unfiltered run. ──
fresh_env
mkdir -p "$ROOT/proj-s"
write_review "$ROOT/proj-s/sess-old-s.jsonl" "2026-07-01T09:00:00.000Z" \
  '[{"filePath":"old-s.sh","category":"c","severity":"low","confidence":0.5,"vulnerableCode":"v","explanation":"old since finding","fix":"f"}]'
write_review "$ROOT/proj-s/sess-new-s.jsonl" "2026-08-24T09:00:00.000Z" \
  '[{"filePath":"new-s.sh","category":"c","severity":"low","confidence":0.5,"vulnerableCode":"v","explanation":"new since finding","fix":"f"}]'
run_extractor --since 2026-08-01 >/dev/null
run_extractor >/dev/null
n_old_s=$(jq -c 'select(.file=="old-s.sh")' "$OUT" | wc -l | tr -d ' ')
n_new_s=$(jq -c 'select(.file=="new-s.sh")' "$OUT" | wc -l | tr -d ' ')
if [[ "$n_old_s" -eq 1 && "$n_new_s" -eq 1 ]]; then
    ok "--since then unfiltered: the older session filtered out by --since is emitted by the later run"
else
    bad "--since must not poison the cache" "old=$n_old_s new=$n_new_s"
fi
rm -rf "$D"

# ── Case 23 (finding 3): a feed larger than 300 KB (and above the 1 MB argv limit of
#    macOS) plus a new finding: the run must succeed, with no FATAL, and emit the row. ──
fresh_env
mkdir -p "$ROOT/proj-big"
{
  for i in $(seq 1 5000); do
    printf '{"ts":"2026-08-01T10:00:00.000Z","session_id":"sess-big-%s","project":"proj-big","file":"hooks/big-%s.sh","severity":"low","category":"cat-big","summary":"history row %s, padded so the feed is large: lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua","fix":"fix","source":"fixture"}\n' "$i" "$i" "$i"
  done
} > "$OUT"
{ for i in $(seq 1 5000); do printf 'sess-big-%s#0\n' "$i"; done; } > "$SEEN"
feed_bytes=$(wc -c < "$OUT" | tr -d ' ')
write_review "$ROOT/proj-big/sess-big-new.jsonl" "$(ago 2)" \
  "$(one_finding 'hooks/big-new.sh' 'cat-bn' 'new row after a large feed')"
run_extractor > "$D/big.log"; big_rc=$?
big_row=$(jq -c 'select(.session_id=="sess-big-new")' "$OUT" | wc -l | tr -d ' ')
if [[ "$feed_bytes" -gt 300000 && "$big_rc" -eq 0 && "$big_row" -eq 1 ]] && ! grep -q FATAL "$D/big.log"; then
    ok "large feed (${feed_bytes} bytes): the run succeeds, no argv failure, the new row is emitted"
else
    bad "large feed must not break the run" "feed_bytes=$feed_bytes rc=$big_rc new_row=$big_row log: $(tail -2 "$D/big.log")"
fi
rm -rf "$D"

# ── Cases 24-26 (finding 4): the upstream token is printed only when the upstream list
#    gained rows since it was last printed. ──
fresh_env
mkdir -p "$ROOT/-Volumes-example-upmark"
write_review "$ROOT/-Volumes-example-upmark/sess-u1.jsonl" "$(ago 2)" \
  "$(one_finding 'skills/synced/tool/up1.py' 'xss' 'first upstream explanation')"
run_extractor >/dev/null
out_u1=$(run_hook "/Volumes/example/upmark")
out_u2=$(run_hook "/Volumes/example/upmark")
write_review "$ROOT/-Volumes-example-upmark/sess-u2.jsonl" "$(ago 1)" \
  "$(one_finding 'skills/synced/tool/up2.py' 'xss' 'second upstream explanation')"
run_extractor >/dev/null
out_u3=$(run_hook "/Volumes/example/upmark")
marker_u="$(cat "$D/security-review-findings-upstream-shown.txt" 2>/dev/null)"
if printf '%s' "$out_u1" | grep -q "(+1 upstream"; then
    ok "upstream token: first session after a new vendor row shows it"
else
    bad "upstream token on first vendor row" "out: $out_u1"
fi
if [[ -z "$out_u2" ]]; then
    ok "upstream token: next session with no new vendor row shows nothing"
else
    bad "upstream token must not be re-raised per session" "out: $out_u2"
fi
if printf '%s' "$out_u3" | grep -q "(+2 upstream" && [[ "$marker_u" == "2" ]]; then
    ok "upstream token: a new vendor row shows it again (+2), marker records 2 rows"
else
    bad "upstream token after a new vendor row" "out: $out_u3 marker: $marker_u"
fi
rm -rf "$D"

echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
