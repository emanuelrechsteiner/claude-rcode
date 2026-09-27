#!/bin/bash
# vault-check: fixtures (synthetic paths/emails/uuids used to exercise the gate; none are real)
# ledger-append-regression.sh — regression suite for ledger-append-proposed.sh,
# focused on the IMP-219 pseudonymization gate (Welle 2 / Gewerk C, plus the
# Welle 4 finding-id hardening from security-review finding M1: .finding is
# now format-gated AND the assembled sourceProposal is full-checked, not
# merely advisory-scanned) layered on top of the pre-existing IMP-112
# idempotency/validation contract.
#
# Runs entirely against a SCRATCH vault (CLAUDE_VAULT_DIR) and a scratch
# ledger (CLAUDE_LEDGER_FILE) — never touches ~/.claude/vault or
# ~/.claude/global-observation/improvement-ledger.json.
#
# Usage: bash scripts/tests/ledger-append-regression.sh
# Exit: 0 = all cases passed, 1 = at least one failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LEDGER_APPEND="${CLAUDE_LEDGER_APPEND_SCRIPT:-$REPO_ROOT/scripts/ledger-append-proposed.sh}"
VAULT_SH="$REPO_ROOT/scripts/vault/vault.sh"

[[ -f "$LEDGER_APPEND" ]] || { echo "ERROR: ledger-append-proposed.sh not found: $LEDGER_APPEND" >&2; exit 1; }
[[ -f "$VAULT_SH" ]]      || { echo "ERROR: vault.sh not found: $VAULT_SH" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     %s\n' "$1" "$2"; }

fresh_env() {  # sets D/VAULT/LEDGER as globals for the caller
    D=$(mktemp -d "${TMPDIR:-/tmp}/ledger-append-test.XXXXXX")
    VAULT="$D/vault"
    LEDGER="$D/ledger.json"
    echo '{}' > "$LEDGER"
}

init_vault() { CLAUDE_VAULT_DIR="$VAULT" bash "$VAULT_SH" init >/dev/null 2>&1; }
add_vault()  { CLAUDE_VAULT_DIR="$VAULT" bash "$VAULT_SH" add "$@" >/dev/null 2>&1; }

run_append() {  # run_append <proposal> [extra args...] — findings piped in by caller via stdin
    local proposal="$1"; shift
    CLAUDE_VAULT_DIR="$VAULT" CLAUDE_LEDGER_FILE="$LEDGER" bash "$LEDGER_APPEND" --proposal "$proposal" "$@" 2>&1
}

hash_of() { shasum "$1" 2>/dev/null | awk '{print $1}'; }

echo "── ledger-append-proposed.sh: pseudonymization gate regression (IMP-219) ──"

# ── Case 1: vault present, evidence contains a registered vault term -> the
#    written entry holds the TOKEN, never the term. ──────────────────────────
fresh_env
init_vault
add_vault project "SynthCorpAlpha" --group synthcorpalpha
out=$(jq -nc '{finding:"F-001",title:"t1",category:"quality",riskLevel:"low",recommendation:"r1",evidence:"Seen in SynthCorpAlpha during a run"}' \
    | run_append "meta-proposal-2026-01.md")
rc=$?
EVIDENCE_OUT=$(jq -r '.weeklyImproveProposals.entries[0].evidence' "$LEDGER" 2>/dev/null)
if [[ "$rc" -eq 0 ]] && printf '%s' "$EVIDENCE_OUT" | grep -q "^Seen in proj-" && ! printf '%s' "$EVIDENCE_OUT" | grep -q "SynthCorpAlpha"; then
    ok "vault term in evidence: written entry holds the token, not the real term"
else
    bad "vault term in evidence: written entry holds the token, not the real term" "rc=$rc evidence='$EVIDENCE_OUT' out=$out"
fi

# ── Case 2: vault present, a field has an UNREGISTERED structural finding
#    (/Users/<synthetic>/...) -> exit 1, ledger stays byte-IDENTICAL. ────────
fresh_env
init_vault
BEFORE=$(hash_of "$LEDGER")
out=$(jq -nc '{finding:"F-002",title:"t2",category:"quality",riskLevel:"low",recommendation:"r2",evidence:"trace at /Users/synthaccount123/proj/file.ts:9"}' \
    | run_append "meta-proposal-2026-02.md")
rc=$?
AFTER=$(hash_of "$LEDGER")
if [[ "$rc" -eq 1 ]] && [[ "$BEFORE" == "$AFTER" ]] && printf '%s' "$out" | grep -q "BLOCKED"; then
    ok "unregistered structural finding (/Users/...): exit 1, ledger byte-identical"
else
    bad "unregistered structural finding: exit 1, ledger byte-identical" "rc=$rc before=$BEFORE after=$AFTER out=$out"
fi
if printf '%s' "$out" | grep -q "synthaccount123"; then
    bad "structural finding: the real value never appears in script output" "leaked value in: $out"
else
    ok "structural finding: the real value never appears in script output (kind-only reporting)"
fi

# ── Case 3: NO vault at all, finding is otherwise clean -> written anyway,
#    with exactly ONE loud WARNING line (not one per field). ────────────────
fresh_env
NOVAULT="$D/no-such-vault"
out=$(jq -nc '{finding:"F-003",title:"t3",category:"quality",riskLevel:"low",recommendation:"r3",evidence:"nothing sensitive here"}' \
    | CLAUDE_VAULT_DIR="$NOVAULT" CLAUDE_LEDGER_FILE="$LEDGER" bash "$LEDGER_APPEND" --proposal "meta-proposal-2026-03.md" 2>&1)
rc=$?
WARN_COUNT=$(printf '%s\n' "$out" | grep -c "WARNING — no vault present")
if [[ "$rc" -eq 0 ]] && [[ "$WARN_COUNT" -eq 1 ]]; then
    ok "no vault + clean finding: written, exactly one WARNING line (not per-field spam)"
else
    bad "no vault + clean finding: written, exactly one WARNING line" "rc=$rc warn_count=$WARN_COUNT out=$out"
fi

# ── Case 4: NO vault, a field has a structural finding -> exit 1 regardless
#    (structural patterns need no vault, per plans/vault-by-design §3). ─────
fresh_env
out=$(jq -nc '{finding:"F-004",title:"t4",category:"quality",riskLevel:"low",recommendation:"r4",evidence:"trace at /Users/synthpersonB/x.ts"}' \
    | CLAUDE_VAULT_DIR="$NOVAULT" CLAUDE_LEDGER_FILE="$LEDGER" bash "$LEDGER_APPEND" --proposal "meta-proposal-2026-04.md" 2>&1)
rc=$?
if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -q "BLOCKED"; then
    ok "no vault + structural finding: exit 1 (structural check is vault-independent)"
else
    bad "no vault + structural finding: exit 1" "rc=$rc out=$out"
fi

# ── Case 5: idempotency — re-running the identical proposal appends nothing,
#    exits 0, and the ledger's entry count does not grow. ───────────────────
fresh_env
init_vault
jq -nc '{finding:"F-005",title:"t5",category:"quality",riskLevel:"low",recommendation:"r5",evidence:"clean"}' \
    | run_append "meta-proposal-2026-05.md" >/dev/null
N1=$(jq '.weeklyImproveProposals.entries | length' "$LEDGER")
out=$(jq -nc '{finding:"F-005",title:"t5",category:"quality",riskLevel:"low",recommendation:"r5",evidence:"clean"}' \
    | run_append "meta-proposal-2026-05.md")
rc=$?
N2=$(jq '.weeklyImproveProposals.entries | length' "$LEDGER")
if [[ "$rc" -eq 0 ]] && [[ "$N1" == "1" ]] && [[ "$N2" == "1" ]] && printf '%s' "$out" | grep -q "nothing to append"; then
    ok "idempotency: re-running the same proposal appends nothing"
else
    bad "idempotency: re-running the same proposal appends nothing" "rc=$rc n1=$N1 n2=$N2 out=$out"
fi

# ── Case 6: status on the written entry is always "proposed". ───────────────
STATUS=$(jq -r '.weeklyImproveProposals.entries[0].status' "$LEDGER")
if [[ "$STATUS" == "proposed" ]]; then
    ok "written entry carries status=proposed (trust boundary)"
else
    bad "written entry carries status=proposed" "status=$STATUS"
fi

# ── Case 7: --dry-run shows the TOKENIZED preview and writes nothing. ───────
fresh_env
init_vault
add_vault project "SynthCorpBeta" --group synthcorpbeta
BEFORE=$(hash_of "$LEDGER")
out=$(jq -nc '{finding:"F-007",title:"dry run entry",category:"quality",riskLevel:"low",recommendation:"r7",evidence:"Seen in SynthCorpBeta"}' \
    | run_append "meta-proposal-2026-07.md" --dry-run)
rc=$?
AFTER=$(hash_of "$LEDGER")
if [[ "$rc" -eq 0 ]] && [[ "$BEFORE" == "$AFTER" ]] && printf '%s' "$out" | grep -q "DRY-RUN"; then
    ok "--dry-run: writes nothing (ledger byte-identical)"
else
    bad "--dry-run: writes nothing" "rc=$rc before=$BEFORE after=$AFTER out=$out"
fi

# ── Case 8: batch of 2 findings, ONE has a structural violation -> NOTHING
#    written (not even the clean one), and the BLOCKED line names the BAD
#    finding id, not the good one. ───────────────────────────────────────────
fresh_env
init_vault
BEFORE=$(hash_of "$LEDGER")
out=$({
    jq -nc '{finding:"F-008-good",title:"good",category:"quality",riskLevel:"low",recommendation:"clean",evidence:"clean"}'
    jq -nc '{finding:"F-008-bad",title:"bad",category:"quality",riskLevel:"low",recommendation:"clean","evidence":"trace /Users/synthpersonC/y"}'
} | run_append "meta-proposal-2026-08.md")
rc=$?
AFTER=$(hash_of "$LEDGER")
if [[ "$rc" -eq 1 ]] && [[ "$BEFORE" == "$AFTER" ]] \
    && printf '%s' "$out" | grep -q "finding=F-008-bad" \
    && ! printf '%s' "$out" | grep -q "finding=F-008-good field="; then
    ok "batch with one bad entry: NOTHING written, BLOCKED names only the bad finding"
else
    bad "batch with one bad entry: NOTHING written, BLOCKED names only the bad finding" "rc=$rc before=$BEFORE after=$AFTER out=$out"
fi

# ── Case 9: the dedup key's PROPOSAL-BASENAME half IS deterministically
#    tokenized when the vault has a matching term (REVERSED in Welle 3,
#    2026-09-25 — see ledger-append-vault-gate.sh's header for why the
#    earlier "never tokenized" design was safe to retire: Gewerk W3-L
#    tokenizes the ledger's EXISTING sourceProposal keys the same way, in
#    the same wave). The FINDING-ID half (after "#") stays exactly as
#    given — only the basename half is gated. ───────────────────────────────
fresh_env
init_vault
add_vault project "meta-proposal-2026-09.md" --group proposalname09
out=$(jq -nc '{finding:"F-009",title:"t9",category:"quality",riskLevel:"low",recommendation:"r9",evidence:"clean"}' \
    | run_append "meta-proposal-2026-09.md")
rc=$?
SRC_PROPOSAL=$(jq -r '.weeklyImproveProposals.entries[0].sourceProposal' "$LEDGER")
if [[ "$rc" -eq 0 ]] && [[ "$SRC_PROPOSAL" =~ ^proj-[0-9a-f]{6}\#F-009$ ]]; then
    ok "sourceProposal: the proposal-basename half IS tokenized when the vault has a matching term"
else
    bad "sourceProposal must tokenize the proposal-basename half" "rc=$rc sourceProposal=$SRC_PROPOSAL out=$out"
fi

# ── Case 9b: dedup SURVIVES that tokenization — re-running the IDENTICAL
#    proposal (same real basename, same finding) a second time must still
#    be recognized as already-present. Tokenization is a deterministic
#    function of the (unchanged) secret + basename on this machine, so both
#    runs produce the SAME token and the existing dedup lookup still
#    matches. This is the concrete proof for "Dedup muss danach fuer einen
#    Vorschlag, dessen Dateiname einen Tresor-Begriff enthaelt, weiterhin
#    greifen" (plan §8-Nachtrag point 2). ────────────────────────────────────
out2=$(jq -nc '{finding:"F-009",title:"t9",category:"quality",riskLevel:"low",recommendation:"r9",evidence:"clean"}' \
    | run_append "meta-proposal-2026-09.md")
rc2=$?
N_ENTRIES_9=$(jq '.weeklyImproveProposals.entries | length' "$LEDGER")
if [[ "$rc2" -eq 0 ]] && [[ "$N_ENTRIES_9" == "1" ]] && printf '%s' "$out2" | grep -q "nothing to append"; then
    ok "dedup survives sourceProposal tokenization: re-running the same real proposal a second time appends nothing"
else
    bad "dedup must survive sourceProposal tokenization" "rc2=$rc2 n_entries=$N_ENTRIES_9 out2=$out2"
fi

# ── Case 9c: a STRUCTURAL finding in the proposal basename itself (e.g. a
#    raw session UUID reaching --proposal, the exact real-world shape that
#    motivated this rework — see security-review-findings.sh's old
#    `--proposal "security-review-$sid"`) blocks the WHOLE run before any
#    per-finding processing runs, ledger stays byte-identical. This is
#    defense-in-depth independent of security-review-findings.sh's OWN fix
#    (deriving a vault token via `vault.sh token id` before ever calling
#    this script). ─────────────────────────────────────────────────────────
fresh_env
init_vault
BEFORE9C=$(hash_of "$LEDGER")
out=$(jq -nc '{finding:"0",title:"t",category:"quality",riskLevel:"low",recommendation:"r",evidence:"clean"}' \
    | run_append "security-review-aaaaaaaa-1111-4a67-89ab-0123456789ab")
rc=$?
AFTER9C=$(hash_of "$LEDGER")
if [[ "$rc" -eq 1 ]] && [[ "$BEFORE9C" == "$AFTER9C" ]] \
    && printf '%s' "$out" | grep -q "blocked the proposal key itself"; then
    ok "structural finding in the proposal basename itself: whole run blocked, ledger byte-identical"
else
    bad "structural finding in proposal basename must block the whole run" "rc=$rc before=$BEFORE9C after=$AFTER9C out=$out"
fi

# ── Case 10 (Welle 4, security-review finding M1): a structural pattern
#    (UUID) embedded ONLY in the finding-id half of sourceProposal now
#    BLOCKS the whole run — this used to be the non-blocking "advisory"
#    case (a caller-supplied finding id was confirmed, never enforced).
#    Exit 1, ledger byte-identical, the raw UUID never appears in script
#    output (kind-only reporting), and the BLOCKED line references the
#    entry, not the finding value. ────────────────────────────────────────
fresh_env
init_vault
BEFORE10=$(hash_of "$LEDGER")
out=$(jq -nc --arg fid "aaaaaaaa-1111-4a67-89ab-0123456789ab" \
    '{finding:$fid,title:"blocked-now",category:"quality",riskLevel:"low",recommendation:"clean",evidence:"clean"}' \
    | run_append "meta-proposal-2026-10.md")
rc=$?
AFTER10=$(hash_of "$LEDGER")
if [[ "$rc" -eq 1 ]] && [[ "$BEFORE10" == "$AFTER10" ]] \
    && printf '%s' "$out" | grep -q "field=sourceProposal kind=id" \
    && ! printf '%s' "$out" | grep -q "aaaaaaaa-1111-4a67-89ab-0123456789ab"; then
    ok "structural pattern (UUID) confined to the finding id: now BLOCKS, ledger byte-identical, value never printed"
else
    bad "structural pattern in finding id must now block (Welle 4)" "rc=$rc before=$BEFORE10 after=$AFTER10 out=$out"
fi

# ── Case 11 (Welle 4): the finding-id half carries a REGISTERED VAULT TERM
#    that is ALSO charset-safe on its own (a project/account name can be a
#    bare alnum word, e.g. Case 1's "SynthCorpAlpha" shape) -> passes the
#    .finding charset gate, but the FULL vault.sh check on the assembled
#    sourceProposal still catches it. Exit 1, ledger byte-identical, the
#    real term never appears in output. ──────────────────────────────────
fresh_env
init_vault
add_vault project "SynthCorpGamma" --group synthcorpgamma
BEFORE11=$(hash_of "$LEDGER")
out=$(jq -nc '{finding:"SynthCorpGamma",title:"t11",category:"quality",riskLevel:"low",recommendation:"clean",evidence:"clean"}' \
    | run_append "meta-proposal-2026-11.md")
rc=$?
AFTER11=$(hash_of "$LEDGER")
if [[ "$rc" -eq 1 ]] && [[ "$BEFORE11" == "$AFTER11" ]] \
    && printf '%s' "$out" | grep -q "field=sourceProposal kind=project" \
    && ! printf '%s' "$out" | grep -q "SynthCorpGamma"; then
    ok "finding-id equal to a registered vault term: exit 1, ledger byte-identical, term never printed"
else
    bad "finding-id containing a vault term must block (Welle 4)" "rc=$rc before=$BEFORE11 after=$AFTER11 out=$out"
fi

# ── Case 12 (Welle 4): .finding fails the charset/length gate (a bare
#    space + a special character) -> exit 1 at STDIN VALIDATION, before the
#    vault gate ever processes a single entry. Ledger byte-identical,
#    message names the STDIN POSITION only, never the raw finding text. ───
fresh_env
init_vault
BEFORE12=$(hash_of "$LEDGER")
out=$(jq -nc --arg fid "bad id!" \
    '{finding:$fid,title:"t12",category:"quality",riskLevel:"low",recommendation:"clean",evidence:"clean"}' \
    | run_append "meta-proposal-2026-12.md")
rc=$?
AFTER12=$(hash_of "$LEDGER")
if [[ "$rc" -eq 1 ]] && [[ "$BEFORE12" == "$AFTER12" ]] \
    && printf '%s' "$out" | grep -q "stdin position 1" \
    && ! printf '%s' "$out" | grep -q "bad id!"; then
    ok "finding-id with forbidden characters (space/!): exit 1 at stdin validation, position named, value never printed"
else
    bad "finding-id with forbidden characters must block at stdin validation" "rc=$rc before=$BEFORE12 after=$AFTER12 out=$out"
fi

# ── Case 13 (Welle 4): in a batch of TWO findings where only the SECOND has
#    a forbidden character, the reported position is 2 — proving the
#    position is genuinely derived from the offending entry, not
#    hardcoded — and NOTHING is written, not even the first (clean) entry. ─
fresh_env
init_vault
BEFORE13=$(hash_of "$LEDGER")
out=$({
    jq -nc '{finding:"F-013-good",title:"good",category:"quality",riskLevel:"low",recommendation:"clean",evidence:"clean"}'
    jq -nc --arg fid "F 013 bad" '{finding:$fid,title:"bad",category:"quality",riskLevel:"low",recommendation:"clean",evidence:"clean"}'
} | run_append "meta-proposal-2026-13.md")
rc=$?
AFTER13=$(hash_of "$LEDGER")
if [[ "$rc" -eq 1 ]] && [[ "$BEFORE13" == "$AFTER13" ]] \
    && printf '%s' "$out" | grep -q "stdin position 2" \
    && ! printf '%s' "$out" | grep -q "F 013 bad"; then
    ok "batch of two, only the 2nd finding-id malformed: position 2 named, nothing written (not even the good one)"
else
    bad "position must reflect the actual offending entry in a batch" "rc=$rc before=$BEFORE13 after=$AFTER13 out=$out"
fi

# ── Case 14 (Welle 4): a normal short finding id, vault present, nothing
#    sensitive anywhere -> written normally. The happy path is unaffected
#    by the hardening (maps to the "gueltige ID -> geschrieben" acceptance
#    criterion). ────────────────────────────────────────────────────────
fresh_env
init_vault
out=$(jq -nc '{finding:"F-014",title:"t14",category:"quality",riskLevel:"low",recommendation:"clean",evidence:"clean"}' \
    | run_append "meta-proposal-2026-14.md")
rc=$?
N14=$(jq '.weeklyImproveProposals.entries | length' "$LEDGER")
SRC14=$(jq -r '.weeklyImproveProposals.entries[0].sourceProposal' "$LEDGER")
if [[ "$rc" -eq 0 ]] && [[ "$N14" == "1" ]] && [[ "$SRC14" == "meta-proposal-2026-14.md#F-014" ]]; then
    ok "valid short finding id: written normally, sourceProposal unchanged"
else
    bad "valid short finding id must still be written" "rc=$rc n14=$N14 src14=$SRC14 out=$out"
fi

# ── Case 15: vault.sh missing entirely -> script-level FATAL, exit 2 (not a
#    silent pass-through — the gate is required infrastructure, not optional). ──
fresh_env
ISOLATED="$D/isolated-scripts"
mkdir -p "$ISOLATED"
cp "$LEDGER_APPEND" "$ISOLATED/ledger-append-proposed.sh"
cp "$(dirname "$LEDGER_APPEND")/ledger-append-vault-gate.sh" "$ISOLATED/ledger-append-vault-gate.sh"
out=$(jq -nc '{finding:"F-015",title:"t15",category:"quality",riskLevel:"low",recommendation:"r15",evidence:"clean"}' \
    | CLAUDE_LEDGER_FILE="$LEDGER" bash "$ISOLATED/ledger-append-proposed.sh" --proposal "p.md" 2>&1)
rc=$?
if [[ "$rc" -eq 2 ]] && printf '%s' "$out" | grep -q "vault.sh not found"; then
    ok "vault.sh missing entirely: FATAL script-level error, exit 2"
else
    bad "vault.sh missing entirely: FATAL script-level error, exit 2" "rc=$rc out=$out"
fi

# ══ IMP-188: self-maintaining counters (recompute after every write,
#    --recompute-only, --check). ═════════════════════════════════════════
run_mode() {  # run_mode <args...> — against the current scratch LEDGER, no stdin
    CLAUDE_VAULT_DIR="$VAULT" CLAUDE_LEDGER_FILE="$LEDGER" bash "$LEDGER_APPEND" "$@" </dev/null 2>&1
}
drifted_fixture() {  # 3 entries (2 implemented, 1 with measured; 1 proposed), stale header
    jq -n '{
      totalImprovements: 1, totalImplementations: 9, totalStaged: 0, totalRollbacks: 0,
      metrics: {computedAt: "2020-01-01T00:00:00Z", totalEntries: 1,
                statusBreakdown: {implemented: 9}, outcomeMeasurementCoverage: "0/9", note: "keep me"},
      batchA_2020: {description: "d", entries: [
        {id: "IMP-001", status: "implemented", verification: {measured: "5/5 suite"}},
        {id: "IMP-002", status: "implemented", verification: null}]},
      batchB_2020: {description: "d", entries: [{id: "IMP-003", status: "proposed"}]}
    }' > "$LEDGER"
}

# ── Case 16: an append recomputes EVERY counter, not only totalImprovements,
#    and the result passes --check. ──────────────────────────────────────
fresh_env
init_vault
drifted_fixture
jq -nc '{finding:"F-016",title:"t16",category:"quality",riskLevel:"low",recommendation:"clean",evidence:"clean"}' \
    | run_append "meta-proposal-2026-16.md" >/dev/null
rc=$?
C16=$(jq -c '[.totalImprovements, .totalImplementations, .metrics.totalEntries, .metrics.statusBreakdown.proposed, .metrics.outcomeMeasurementCoverage, .metrics.note]' "$LEDGER")
out=$(run_mode --check); rc_check=$?
if [[ "$rc" -eq 0 ]] && [[ "$C16" == '[4,2,4,2,"1/2","keep me"]' ]] && [[ "$rc_check" -eq 0 ]]; then
    ok "append recomputes all counters from the entries (4 ids, 2 implemented, coverage 1/2) and --check passes"
else
    bad "append must recompute all counters" "rc=$rc counters=$C16 rc_check=$rc_check out=$out"
fi

# ── Case 17: --check on a drifted ledger -> exit 1, names each drifted
#    field, ledger byte-identical. ─────────────────────────────────────
fresh_env
drifted_fixture
BEFORE17=$(hash_of "$LEDGER")
out=$(run_mode --check); rc=$?
AFTER17=$(hash_of "$LEDGER")
if [[ "$rc" -eq 1 ]] && [[ "$BEFORE17" == "$AFTER17" ]] \
    && printf '%s' "$out" | grep -q "totalImprovements: stored=1 recomputed=3" \
    && printf '%s' "$out" | grep -q 'metrics.outcomeMeasurementCoverage: stored="0/9" recomputed="1/2"'; then
    ok "--check on a drifted ledger: exit 1, drifted fields named, ledger byte-identical"
else
    bad "--check must fail on drift without writing" "rc=$rc before=$BEFORE17 after=$AFTER17 out=$out"
fi

# ── Case 18: --recompute-only fixes the drift, leaves every entry untouched
#    and keeps non-counter metrics fields; --check passes afterwards. ─────
ENTRIES_BEFORE=$(jq -c '[.batchA_2020, .batchB_2020]' "$LEDGER")
out=$(run_mode --recompute-only); rc=$?
ENTRIES_AFTER=$(jq -c '[.batchA_2020, .batchB_2020]' "$LEDGER")
C18=$(jq -S -c '[.totalImprovements, .totalImplementations, .totalStaged, .totalRollbacks, .metrics.totalEntries, .metrics.statusBreakdown, .metrics.outcomeMeasurementCoverage, .metrics.note, (.metrics.computedAt != "2020-01-01T00:00:00Z"), (.lastUpdated != null)]' "$LEDGER")
out2=$(run_mode --check); rc_check=$?
if [[ "$rc" -eq 0 ]] && [[ "$ENTRIES_BEFORE" == "$ENTRIES_AFTER" ]] \
    && [[ "$C18" == '[3,2,0,0,3,{"deprecated":0,"implemented":2,"in-progress":0,"proposed":1,"regressed":0},"1/2","keep me",true,true]' ]] \
    && [[ "$rc_check" -eq 0 ]]; then
    ok "--recompute-only: counters fixed, entries untouched, note kept, --check passes afterwards"
else
    bad "--recompute-only must fix the counters only" "rc=$rc counters=$C18 entries_same=$([[ "$ENTRIES_BEFORE" == "$ENTRIES_AFTER" ]] && echo y || echo n) rc_check=$rc_check out=$out out2=$out2"
fi

# ── Case 19: --recompute-only --dry-run reports the drift, writes nothing. ─
fresh_env
drifted_fixture
BEFORE19=$(hash_of "$LEDGER")
out=$(run_mode --recompute-only --dry-run); rc=$?
AFTER19=$(hash_of "$LEDGER")
if [[ "$rc" -eq 0 ]] && [[ "$BEFORE19" == "$AFTER19" ]] && printf '%s' "$out" | grep -q "DRY-RUN"; then
    ok "--recompute-only --dry-run: drift reported, ledger byte-identical"
else
    bad "--recompute-only --dry-run must not write" "rc=$rc before=$BEFORE19 after=$AFTER19 out=$out"
fi

# ── Case 20: duplicate IMP ids -> both modes refuse (exit 1), nothing written.
fresh_env
jq -n '{a: {entries: [{id: "IMP-001", status: "implemented"}]}, b: {entries: [{id: "IMP-001", status: "proposed"}]}}' > "$LEDGER"
BEFORE20=$(hash_of "$LEDGER")
out=$(run_mode --check); rc1=$?
out2=$(run_mode --recompute-only); rc2=$?
AFTER20=$(hash_of "$LEDGER")
if [[ "$rc1" -eq 1 ]] && [[ "$rc2" -eq 1 ]] && [[ "$BEFORE20" == "$AFTER20" ]] && printf '%s' "$out" | grep -q "duplicate IMP ids in the ledger: IMP-001"; then
    ok "duplicate ids: --check and --recompute-only both refuse, ledger byte-identical"
else
    bad "duplicate ids must block both modes" "rc1=$rc1 rc2=$rc2 before=$BEFORE20 after=$AFTER20 out=$out out2=$out2"
fi

# ── Case 21: argument misuse is a script-level error (exit 2). ────────────
fresh_env
out=$(run_mode --check --recompute-only); rc1=$?
out2=$(run_mode --check --proposal "p.md"); rc2=$?
if [[ "$rc1" -eq 2 ]] && [[ "$rc2" -eq 2 ]]; then
    ok "--check with --recompute-only or --proposal: exit 2"
else
    bad "mode argument misuse must exit 2" "rc1=$rc1 rc2=$rc2 out=$out out2=$out2"
fi

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
