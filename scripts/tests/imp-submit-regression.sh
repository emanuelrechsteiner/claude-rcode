#!/bin/bash
# vault-check: fixtures (synthetic values only — invented stand-ins, never a real term)
#
# imp-submit-regression.sh — regression suite for scripts/imp-submit.sh
# (IMP-219, Welle 4 / Gewerk G-script, plans/vault-by-design-2026-09-25.md).
#
# Runs ENTIRELY against a fresh CLAUDE_VAULT_DIR (mktemp, per test group) and
# a fresh temp ledger file — NEVER the real ~/.claude/vault or the real
# ~/.claude/global-observation/improvement-ledger.json. Usage:
#   bash scripts/tests/imp-submit-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOL="${CLAUDE_IMP_SUBMIT_SCRIPT:-$REPO_ROOT/scripts/imp-submit.sh}"
VAULT="${CLAUDE_VAULT_SCRIPT:-$REPO_ROOT/scripts/vault/vault.sh}"
[[ -f "$TOOL" ]] || { echo "ERROR: imp-submit.sh not found: $TOOL" >&2; exit 1; }
[[ -f "$VAULT" ]] || { echo "ERROR: vault.sh not found: $VAULT" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \xe2\x9c\x85 %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \xe2\x9d\x8c %s\n     %s\n' "$1" "$2"; }

fresh_vault() {
  CLAUDE_VAULT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/imp-submit-regr-vault.XXXXXX")"
  export CLAUDE_VAULT_DIR
}

# no_vault <label> — points CLAUDE_VAULT_DIR at a path under our own
# SCRATCH that is never created/initialized -- vault_exists() checks file
# existence, so an absent directory and an empty one are equally "no vault".
no_vault() {
  CLAUDE_VAULT_DIR="$SCRATCH/no-vault-$1"
  export CLAUDE_VAULT_DIR
}

check_exit() {  # check_exit <label> <expected> <actual>
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then ok "$label"; else bad "$label" "expected exit $expected, got $actual"; fi
}

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/imp-submit-regr-scratch.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

# A clean, fully-filled form matching templates/imp-submission.template.md's
# six required headings (English, canonical form) byte-for-byte. Built as a
# literal heredoc (rather than programmatically patching the shipped
# template) so this suite stays decoupled from the template's own
# HTML-comment formatting.
write_clean_form() {  # write_clean_form <path>
  cat > "$1" <<'FORMEOF'
# IMP Submission

## What does NOT belong in here

instructional text, ignored by imp-submit.sh's own output.

## Problem Class

silent fallback in a script

## Symptom

The run reports ok, but <project> sees no new lines.

## Measurement / Evidence

17 of 40 sessions showed X (grep over 40 JSONL files, cutoff date 2026-09-25).

## Proposed Change

Negate the condition on line 3 of rules/foo.md.

## Risk / Band

AUTO -- purely local, reversible change.

## Rollback

git revert the commit.

## Local IMP ID (optional — submitter's own reference only)

IMP-999
FORMEOF
}

# The same clean form, but with the OLDER German headings that
# scripts/imp-submit.sh accepts as aliases — proves an older, German-headed
# submission still validates after the english-only heading switch.
write_clean_form_de() {  # write_clean_form_de <path>
  cat > "$1" <<'FORMEOF'
# IMP-Einreichung

## Was NICHT hineingehört

instructional text, ignored by imp-submit.sh's own output.

## Problemklasse

stiller Fallback in einem Skript

## Symptom

Der Lauf meldet ok, aber <projekt> sieht keine neuen Zeilen.

## Messwert / Beleg

17 von 40 Sitzungen zeigten X (grep ueber 40 JSONL-Dateien, Stichtag 2026-09-25).

## Vorgeschlagene Änderung

In rules/foo.md Zeile 3 die Bedingung negieren.

## Risiko / Band

AUTO -- rein lokale, reversible Aenderung.

## Rücknahme

git revert des Commits.

## Lokale IMP-ID (optional — nur Referenz des Einreichers)

IMP-999
FORMEOF
}

echo "== usage / argument edge cases =="
set +e
bash "$TOOL" >/dev/null 2>/dev/null
check_exit "no arguments at all exits 1" 1 "$?"
bash "$TOOL" -h >/dev/null 2>/dev/null
check_exit "-h exits 0" 0 "$?"
bash "$TOOL" --from-ledger >/dev/null 2>/dev/null
check_exit "--from-ledger with no id exits 1" 1 "$?"
set -e

echo "== mode 1: clean, fully filled form (with a vault present) =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
FORM="$SCRATCH/clean.md"
write_clean_form "$FORM"
set +e
OUT="$(bash "$TOOL" "$FORM" 2>"$SCRATCH/clean.err")"
RC=$?
set -e
check_exit "clean + filled form exits 0" 0 "$RC"
echo "$OUT" | grep -q "checked with vault.sh" \
  && ok "output carries the checked-header line" \
  || bad "output carries the checked-header line" "$OUT"
echo "$OUT" | grep -q "## What does NOT belong in here" \
  && bad "forbidden-instructions section is stripped from the output" "still present" \
  || ok "forbidden-instructions section is stripped from the output"

echo "== mode 1: a required field left exactly as the template's own unfilled placeholder =="
sed 's/git revert the commit\.//' "$FORM" > "$SCRATCH/missing.md"
set +e
bash "$TOOL" "$SCRATCH/missing.md" >"$SCRATCH/missing.out" 2>"$SCRATCH/missing.err"
RC=$?
set -e
check_exit "missing required field exits 1" 1 "$RC"
grep -q "Rollback" "$SCRATCH/missing.err" \
  && ok "missing-field report names the empty field (Rollback)" \
  || bad "missing-field report names the empty field" "$(cat "$SCRATCH/missing.err")"

echo "== mode 1: a vault-registered synthetic term inside the form =="
bash "$VAULT" add project "SynthLeakTerm" --group synthleakgrp >/dev/null 2>&1
TOKEN_LEAK="$(awk -F'\t' '$2=="SynthLeakTerm"{print $3}' "$CLAUDE_VAULT_DIR/map.tsv")"
sed 's/silent fallback in a script/silent fallback with SynthLeakTerm/' "$FORM" > "$SCRATCH/leak.md"
set +e
OUT_LEAK="$(bash "$TOOL" "$SCRATCH/leak.md" 2>"$SCRATCH/leak.err")"
RC=$?
set -e
check_exit "form with a registered vault term exits 2" 2 "$RC"
if printf '%s\n%s\n' "$OUT_LEAK" "$(cat "$SCRATCH/leak.err")" | grep -q "SynthLeakTerm"; then
  bad "the real term never appears in stdout/stderr" "found the raw term in the tool's own output"
else
  ok "the real term never appears in stdout/stderr"
fi
grep -q "$TOKEN_LEAK" "$SCRATCH/leak.err" \
  && ok "the finding report names the token instead of the term" \
  || bad "the finding report names the token instead of the term" "$(cat "$SCRATCH/leak.err")"

echo "== mode 1: a structural pattern (a session-id-shaped token, not a path) =="
# Deliberately NOT a /Users/... or /home/... fixture (vault safety): this
# repo's own edit-time vault-write-gate treats those prefixes as a possible
# leak on ANY edit whose new content carries them, even an already-vetted
# synthetic fixture. A synthetic session-id-shaped token exercises the SAME
# structural detector (kind=id, see scripts/vault/lib.sh) without that shape.
sed 's#Negate the condition on line 3 of rules/foo.md.#See session_abcdefghijklmnopqrstuvwx for the trace.#' "$FORM" > "$SCRATCH/struct.md"
set +e
bash "$TOOL" "$SCRATCH/struct.md" >"$SCRATCH/struct.out" 2>"$SCRATCH/struct.err"
RC=$?
set -e
check_exit "form with a session-id-shaped token exits 2" 2 "$RC"

echo "== mode 1: clean form with the OLDER German headings (accepted alias) =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
FORM_DE="$SCRATCH/clean-de.md"
write_clean_form_de "$FORM_DE"
set +e
OUT_DE="$(bash "$TOOL" "$FORM_DE" 2>"$SCRATCH/clean-de.err")"
RC=$?
set -e
check_exit "German-headed form exits 0 (alias accepted)" 0 "$RC"
echo "$OUT_DE" | grep -q "checked with vault.sh" \
  && ok "German-headed form: output carries the checked-header line" \
  || bad "German-headed form: output carries the checked-header line" "$OUT_DE"
echo "$OUT_DE" | grep -q "## Was NICHT hineingehört" \
  && bad "German-headed form: forbidden-instructions section is stripped" "still present" \
  || ok "German-headed form: forbidden-instructions section is stripped"

echo "== mode 1: clean form, but NO vault present at all =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
write_clean_form "$FORM"
no_vault 1
set +e
bash "$TOOL" "$FORM" >"$SCRATCH/novault.out" 2>"$SCRATCH/novault.err"
RC=$?
set -e
check_exit "clean form with no vault present still exits 0" 0 "$RC"
grep -qi "WARNING" "$SCRATCH/novault.err" \
  && ok "a loud warning line is emitted when no vault exists" \
  || bad "a loud warning line is emitted when no vault exists" "$(cat "$SCRATCH/novault.err")"

echo "== --from-ledger: synthetic vault term inside ledger entries of BOTH known shapes =="
fresh_vault
bash "$VAULT" init >/dev/null 2>&1
bash "$VAULT" add project "SynthLedgerTerm" --group synthledgergrp >/dev/null 2>&1
TOKEN_LEDGER="$(awk -F'\t' '$2=="SynthLedgerTerm"{print $3}' "$CLAUDE_VAULT_DIR/map.tsv")"
LEDGER="$SCRATCH/ledger.json"
cat > "$LEDGER" <<'LEDGEREOF'
{
  "activeImprovements": {
    "IMP-100": {
      "title": "Old-shape entry about SynthLedgerTerm",
      "description": "kurz",
      "implementation": "tue X wegen SynthLedgerTerm",
      "status": "implemented",
      "implementedAt": "2026-01-01T00:00:00Z"
    }
  },
  "weeklyImproveProposals": {
    "entries": [
      {
        "id": "IMP-200",
        "title": "New-shape entry about SynthLedgerTerm too",
        "category": "process",
        "riskLevel": "low",
        "notes": "Aendere die Regel wegen SynthLedgerTerm",
        "evidence": "5 von 5 Laeufen zeigten das Problem",
        "status": "proposed",
        "proposedAt": "2026-09-01T00:00:00Z",
        "implementedAt": null,
        "source": "test",
        "sourceProposal": "test#F-1",
        "verification": {}
      }
    ]
  }
}
LEDGEREOF
CKSUM_BEFORE="$(shasum -a 256 "$LEDGER" | awk '{print $1}')"

set +e
OUT_PROPOSAL="$(bash "$TOOL" --from-ledger IMP-200 --ledger "$LEDGER" 2>"$SCRATCH/from200.err")"
RC=$?
set -e
check_exit "--from-ledger on a .weeklyImproveProposals-shaped entry exits 0" 0 "$RC"
if printf '%s' "$OUT_PROPOSAL" | grep -q "SynthLedgerTerm"; then
  bad "the real term never appears in the pre-filled form (new shape)" "found the raw term"
else
  ok "the real term never appears in the pre-filled form (new shape)"
fi
printf '%s' "$OUT_PROPOSAL" | grep -q "$TOKEN_LEDGER" \
  && ok "the pre-filled form carries the token instead (new shape)" \
  || bad "the pre-filled form carries the token instead (new shape)" "$OUT_PROPOSAL"
printf '%s' "$OUT_PROPOSAL" | grep -q "Rollback" \
  && ok "the still-needed hint names Rollback (never derivable from a ledger entry)" \
  || bad "the still-needed hint names Rollback" "$OUT_PROPOSAL"

set +e
OUT_ACTIVE="$(bash "$TOOL" --from-ledger IMP-100 --ledger "$LEDGER" 2>"$SCRATCH/from100.err")"
RC=$?
set -e
check_exit "--from-ledger on an .activeImprovements-shaped entry exits 0" 0 "$RC"
if printf '%s' "$OUT_ACTIVE" | grep -q "SynthLedgerTerm"; then
  bad "the real term never appears in the pre-filled form (old shape)" "found the raw term"
else
  ok "the real term never appears in the pre-filled form (old shape)"
fi
printf '%s' "$OUT_ACTIVE" | grep -q "$TOKEN_LEDGER" \
  && ok "the older ledger shape (title/description/implementation) is pre-filled too" \
  || bad "the older ledger shape is pre-filled too" "$OUT_ACTIVE"

echo "== --from-ledger: unknown id =="
set +e
bash "$TOOL" --from-ledger IMP-999999 --ledger "$LEDGER" >"$SCRATCH/unknown.out" 2>"$SCRATCH/unknown.err"
RC=$?
set -e
check_exit "--from-ledger with an unknown id exits 1" 1 "$RC"

echo "== --from-ledger: no vault present =="
no_vault 2
set +e
bash "$TOOL" --from-ledger IMP-200 --ledger "$LEDGER" >"$SCRATCH/novault2.out" 2>"$SCRATCH/novault2.err"
RC=$?
set -e
check_exit "--from-ledger with no vault present exits 1" 1 "$RC"

CKSUM_AFTER="$(shasum -a 256 "$LEDGER" | awk '{print $1}')"
[[ "$CKSUM_BEFORE" == "$CKSUM_AFTER" ]] \
  && ok "the ledger file is byte-identical after every --from-ledger call (read-only)" \
  || bad "the ledger file is byte-identical after every --from-ledger call" "checksum changed: $CKSUM_BEFORE -> $CKSUM_AFTER"

echo ""
echo "imp-submit-regression: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
