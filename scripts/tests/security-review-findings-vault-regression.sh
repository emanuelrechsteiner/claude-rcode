#!/bin/bash
# security-review-findings-vault-regression.sh — regression suite for the
# IMP-219 sid_token fix in scripts/security-review-findings.sh's --to-ledger
# path (plan §7-Nachtrag point 13 / §8-Nachtrag W3-S).
#
# WHY A SEPARATE FILE: hooks/tests/security-findings-regression.sh already
# covers the extractor's detection/dedup/hook logic in full, but it belongs
# to Gewerk W3-H (hooks/**), not W3-S (scripts/** outside scripts/vault/**) —
# per plans/vault-by-design-2026-09-25.md's Welle-1 note ("Brauchst du dort
# einen neuen Fall, melde ihn, statt die Datei zu ändern; deine eigene
# Suite-Abdeckung kommt in scripts/tests/, falls nötig"). That suite's own
# --to-ledger cases run with --dry-run and only assert on the "N unacked
# finding(s)" log line, printed BEFORE the per-session loop — they never
# actually exercise (or would notice a regression in) the per-session
# sid_token derivation this file specifically targets.
#
# Before the fix: LEDGER_ARGS=(--proposal "security-review-$sid") put the
# REAL session id (a personal/machine identifier) into the ledger's
# sourceProposal field, unconditionally. After the fix: a vault token
# (`vault.sh token id`) stands in for it, deterministically and without
# ever storing the session id anywhere; with no vault/secret present, that
# session's ledger write is skipped with a loud WARN — never a silent
# fallback to the raw id.
#
# Runs entirely against scratch fixtures/vault/ledger — never touches
# ~/.claude/projects, ~/.claude/vault, or the real improvement-ledger.json.
#
# Usage: bash scripts/tests/security-review-findings-vault-regression.sh
# Exit: 0 = all cases passed, 1 = at least one failed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXTRACTOR="$REPO_ROOT/security-review-findings.sh"
LEDGER_APPEND="$REPO_ROOT/ledger-append-proposed.sh"
VAULT_SH="$REPO_ROOT/vault/vault.sh"

for f in "$EXTRACTOR" "$LEDGER_APPEND" "$VAULT_SH"; do
  [[ -f "$f" ]] || { echo "ERROR: required script not found: $f" >&2; exit 1; }
done

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     %s\n' "$1" "$2"; }

fresh_env() {
    D=$(mktemp -d "${TMPDIR:-/tmp}/sec-findings-vault-test.XXXXXX")
    ROOT="$D/projects"
    OUT="$D/out.jsonl"
    STATE="$D/state.json"
    SEEN="$D/seen.txt"
    ACK="$D/ack.txt"
    LEDGERFILE="$D/ledger.json"
    VAULT="$D/vault"
    mkdir -p "$ROOT/proj-v"
    echo '{}' > "$LEDGERFILE"
}

init_vault() { CLAUDE_VAULT_DIR="$VAULT" bash "$VAULT_SH" init >/dev/null 2>&1; }

# write_review SESSIONFILE TS FINDINGS_JSON — a single-shot accepted review
# (same shape as hooks/tests/security-findings-regression.sh's own helper —
# not re-derived from memory, copied verbatim from that file's fixture).
write_review() {
    local f="$1" ts="$2" findings="$3"
    cat > "$f" <<EOF
{"type":"user","entrypoint":"sdk-py","message":{"role":"user","content":"Review this change for security vulnerabilities.\n\nChanged files (you may Read these and any other file in the repo):\n  - some/file.sh"},"timestamp":"$ts"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_a1","name":"StructuredOutput","input":{"findings":$findings}}]},"timestamp":"$ts"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_a1","content":"Structured output provided successfully"}]},"timestamp":"$ts"}
EOF
}

run_extractor() {   # run_extractor <extra args...>
    CLAUDE_SEC_FINDINGS_ROOT="$ROOT" \
    CLAUDE_SEC_FINDINGS_OUT="$OUT" \
    CLAUDE_SEC_FINDINGS_STATE="$STATE" \
    CLAUDE_SEC_FINDINGS_SEEN="$SEEN" \
    CLAUDE_SEC_FINDINGS_ACK="$ACK" \
    CLAUDE_LEDGER_APPEND_SCRIPT="$LEDGER_APPEND" \
    CLAUDE_LEDGER_FILE="$LEDGERFILE" \
    CLAUDE_VAULT_SCRIPT="${CLAUDE_VAULT_SCRIPT_OVERRIDE:-$VAULT_SH}" \
    CLAUDE_VAULT_DIR="$VAULT" \
    bash "$EXTRACTOR" "$@" 2>&1
}

echo "── security-review-findings.sh: --to-ledger sid_token regression (IMP-219) ──"

# ── Case 1: vault present -> the ledger entry's sourceProposal carries a
#    vault TOKEN, never the real session id; the token matches EXACTLY what
#    `vault.sh token id <sid>` derives standalone (same primitive, no second
#    computation). ─────────────────────────────────────────────────────────
fresh_env
init_vault
write_review "$ROOT/proj-v/sess-real-uuid-1234.jsonl" "2026-09-09T10:00:00.000Z" \
  '[{"filePath":"x.sh","category":"cat-x","severity":"high","confidence":0.9,"vulnerableCode":"v","explanation":"exp","fix":"fx"}]'
CLAUDE_SEC_FINDINGS_LEDGER_PROJECT="proj-v" run_extractor >/dev/null
out=$(CLAUDE_SEC_FINDINGS_LEDGER_PROJECT="proj-v" run_extractor --to-ledger)
rc=$?
expected_token=$(CLAUDE_VAULT_DIR="$VAULT" bash "$VAULT_SH" token id "sess-real-uuid-1234")
SRC_PROPOSAL=$(jq -r '[.. | objects | .sourceProposal? | select(type=="string")][0] // empty' "$LEDGERFILE")
if [[ "$rc" -eq 0 ]] && [[ "$SRC_PROPOSAL" == "security-review-${expected_token}#0" ]]; then
    ok "vault present: sourceProposal carries the vault token, matching vault.sh token id's own output"
else
    bad "vault present: sourceProposal must carry the deterministic token" "rc=$rc sourceProposal=$SRC_PROPOSAL expected_token=$expected_token out=$out"
fi
if printf '%s' "$SRC_PROPOSAL" | grep -q "sess-real-uuid-1234"; then
    bad "the real session id must never appear in sourceProposal" "sourceProposal=$SRC_PROPOSAL"
else
    ok "the real session id never appears in sourceProposal"
fi

# ── Case 2: no vault/secret at all -> that session's ledger write is
#    SKIPPED with a loud WARN, never a silent fallback to the raw session
#    id; the scratch ledger stays untouched; exit code stays 0 (a skip is
#    not treated as a fatal script error — other sessions may still be
#    processable). ────────────────────────────────────────────────────────
fresh_env
NOVAULT="$D/no-such-vault"
write_review "$ROOT/proj-v/sess-another-real-id.jsonl" "2026-09-09T11:00:00.000Z" \
  '[{"filePath":"y.sh","category":"cat-y","severity":"low","confidence":0.5,"vulnerableCode":"v","explanation":"exp","fix":"fx"}]'
CLAUDE_SEC_FINDINGS_LEDGER_PROJECT="proj-v" CLAUDE_VAULT_DIR="$NOVAULT" run_extractor >/dev/null
out=$(CLAUDE_SEC_FINDINGS_LEDGER_PROJECT="proj-v" CLAUDE_VAULT_DIR="$NOVAULT" run_extractor --to-ledger)
rc=$?
LEDGER_IDS=$(jq -c '[.. | objects | .id? // empty]' "$LEDGERFILE" 2>/dev/null)
if [[ "$rc" -eq 0 ]] && [[ "$LEDGER_IDS" == "[]" ]] && printf '%s' "$out" | grep -q "no vault/secret available to derive a token"; then
    ok "no vault: ledger write skipped with a loud WARN, scratch ledger stays empty"
else
    bad "no vault: must skip with WARN, never write" "rc=$rc ledger_ids=$LEDGER_IDS out=$out"
fi
if printf '%s' "$out" | grep -q "sess-another-real-id"; then
    bad "the real session id must never appear in script output even on the no-vault path" "out=$out"
else
    ok "the real session id never appears in script output on the no-vault path"
fi

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
