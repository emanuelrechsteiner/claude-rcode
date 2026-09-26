#!/bin/bash
# ledger-append-proposed.sh — write findings from a meta-proposal into the ledger
# ─────────────────────────────────────────────────────────────────────────────
# IMP-112 (2026-08-01). Closes the write-back gap that made the weekly loop a
# no-op: weeks 27/28/29/30 produced 25 findings and ZERO ledger entries, so a
# one-word fix (the zcat defect) survived a full week unapplied and then broke
# the next run. A loop that reads but never writes back is indistinguishable
# from no loop at all.
#
# TRUST BOUNDARY (deliberate, do not "improve" this away):
#   This script only ever writes status:"proposed". It NEVER promotes to
#   implemented and NEVER applies a change. Observation data must not be able
#   to write framework governance — human review stays the gate. See the
#   meta-observer skill's anti-patterns and agency-bands.md.
#
# PSEUDONYMIZATION GATE (IMP-219, 2026-09-25; sourceProposal tokenized since
# the Welle-3 rework, finding-id now format-gated + full-checked since
# Welle 4): every text field this script is about to write (title, category,
# riskLevel, notes/recommendation, evidence, source) is tokenized via
# `scripts/vault/vault.sh tokenize` (when a vault exists at ~/.claude/vault)
# and then structurally checked via `vault.sh check --structural-only
# --stdin` — which needs no vault and runs unconditionally (fail loud, not
# fail closed, on a fresh clone with no vault). A structural finding
# remaining in ANY field of ANY entry aborts the WHOLE run — exit 1, NOTHING
# written, not even the other clean entries of the same run. See
# scripts/ledger-append-vault-gate.sh for the gate itself.
# `sourceProposal` (the dedup key, "<proposal-basename>#<finding-id>") gates
# its PROPOSAL-BASENAME half through the exact same tokenize+check
# primitive, gated ONCE at script start (before the dedup lookup, so a
# re-run of the identical proposal still dedups correctly — tokenization is
# deterministic per machine). The FINDING-ID half — REVISED in Welle 4
# (security-review finding M1: a caller-supplied finding id used to reach
# the ledger with only a non-empty check and a non-blocking advisory scan,
# so a caller passing a real vault term or a path/email/session-id shaped
# string as ".finding" would write it, unmodified, into the versioned
# ledger) — is now gated in two layers: (1) below, every entry's ".finding"
# must match ^[A-Za-z0-9._-]{1,64}$ (a short id like "F-001") BEFORE dedup
# or entry-building even starts, or the WHOLE run is refused (exit 1,
# nothing written, the error names only the offending entry's POSITION on
# stdin, never its value); (2) ledger-append-vault-gate.sh's
# lvg_check_source_proposal then runs a BLOCKING full `vault.sh check`
# (vault + structural, no --structural-only) on the fully assembled
# sourceProposal, closing the remaining case where a charset-safe finding id
# happens to equal a real registered vault term. Neither layer tokenizes or
# rewrites the finding-id itself — a hit means refuse-to-write, not
# silent substitution (the dedup key stays byte-stable across a re-run).
#
# Input: one JSON object per line on stdin, each:
#   {"finding":"F-001","title":"...","category":"...","riskLevel":"low",
#    "recommendation":"...","evidence":"..."}
#   (title + finding are required; the rest default sensibly.)
#
# Usage:
#   ledger-append-proposed.sh --proposal ~/.claude/plans/meta-proposal-2026-31.md \
#     [--dry-run] < findings.jsonl
#
# Idempotent: the dedup key is "<proposal-basename>#<finding>". Re-running the
# same proposal appends nothing and exits 0.
#
# Exit codes:
#   0  — entries appended, or all were duplicates (idempotent), or dry-run
#   1  — input/ledger validation failed → NOTHING written
#   2  — script-level error (missing deps, bad arguments)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LEDGER="${CLAUDE_LEDGER_FILE:-$HOME/.claude/global-observation/improvement-ledger.json}"
SECTION="weeklyImproveProposals"

log() { echo "[ledger-append-proposed] $*"; }
die() { echo "[ledger-append-proposed] FATAL: $*" >&2; exit "${2:-2}"; }

command -v jq >/dev/null 2>&1 || die "jq not found"

PROPOSAL=""; DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposal) PROPOSAL="${2:-}"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$PROPOSAL" ]] || die "--proposal <path> is required"
[[ -f "$LEDGER" ]]   || die "ledger not found: $LEDGER"
jq -e . "$LEDGER" >/dev/null 2>&1 || die "ledger is not valid JSON — refusing to touch it" 1

# ── Pseudonymization gate (IMP-219) init'd EARLY, before PROPOSAL_KEY is
#    used anywhere: as of the Welle-3 rework, sourceProposal (built below as
#    "$PROPOSAL_KEY#<finding>") is DETERMINISTICALLY TOKENIZED — the SAME
#    vault.sh tokenize primitive as every other field, via lvg_gate_value
#    directly (no second tokenizer) — because Gewerk W3-L is tokenizing the
#    ledger's EXISTING sourceProposal keys in the same wave. Gating the key
#    here, before the dedup lookup below, means dedup keeps matching a
#    re-run of the identical proposal: tokenization is a pure function of
#    the (unchanged) secret + proposal basename, so the SAME real basename
#    always yields the SAME token on this machine, both in an old
#    (now-tokenized) ledger entry and a fresh run's candidate key. A
#    structural finding remaining in the key itself aborts the WHOLE run —
#    nothing is written, matching this script's existing all-or-nothing
#    contract for a batch with one bad entry.
. "$SCRIPT_DIR/ledger-append-vault-gate.sh"
lvg_init "$SCRIPT_DIR" || die "vault gate unavailable — refusing to write (see FATAL above)"

PROPOSAL_KEY_RAW="$(basename "$PROPOSAL")"
pkey_rc=0
lvg_gate_value "(proposal)" "sourceProposal-prefix" "$PROPOSAL_KEY_RAW" || pkey_rc=$?
case "$pkey_rc" in
  0) PROPOSAL_KEY="$LVG_OUT" ;;
  2) die "pseudonymization gate blocked the proposal key itself (sourceProposal prefix derived from --proposal '$PROPOSAL') — NOTHING written" 1 ;;
  *) die "vault gate: internal error while validating the proposal key" 1 ;;
esac

# ── Read + validate the findings from stdin ──────────────────────────────────
INPUT="$(cat)"
[[ -n "${INPUT// }" ]] || die "no findings on stdin (a run with 0 findings should not call this)" 1

if ! printf '%s\n' "$INPUT" | jq -e . >/dev/null 2>&1; then
  die "stdin is not valid JSONL" 1
fi
if printf '%s\n' "$INPUT" | jq -e 'select((.finding // "") == "" or (.title // "") == "")' >/dev/null 2>&1; then
  die "every finding needs a non-empty .finding and .title" 1
fi

# ── .finding format gate (IMP-219 Welle 4, security-review finding M1) ──────
# .finding becomes the FINDING-ID half of sourceProposal ("<proposal-
# basename>#<finding>"), a value this script writes verbatim into the
# versioned ledger. Before this gate, any non-empty string was accepted —
# a caller could pass free text, a real path/email/session-id, or a
# registered vault term, and it would land in the ledger unmodified (only a
# non-blocking advisory scan ever looked at it). Constraining the CHARSET
# here closes the free-text/structural-pattern route outright (no "/", "@",
# or whitespace can ever reach sourceProposal via this field); the
# remaining risk — a charset-safe id that still coincides with a real vault
# term — is closed downstream by ledger-append-vault-gate.sh's
# lvg_check_source_proposal (a full, blocking vault.sh check on the
# assembled sourceProposal). The message below names only the STDIN
# POSITION of the offending entry — never its value, since an entry that
# fails this test is by definition not yet known to be safe to print
# (rules/fail-loud.md).
BAD_FINDING_POS=$(printf '%s\n' "$INPUT" | jq -s -r '
  to_entries
  | map(select((.value.finding // "") as $f | ($f | type) != "string" or ($f | test("^[A-Za-z0-9._-]{1,64}$") | not)))
  | if length > 0 then (.[0].key + 1 | tostring) else empty end
')
[[ -z "$BAD_FINDING_POS" ]] || die "the .finding at stdin position $BAD_FINDING_POS is not a short id (must match ^[A-Za-z0-9._-]{1,64}\$, e.g. \"F-001\") — refusing to build sourceProposal from it" 1

N_IN=$(printf '%s\n' "$INPUT" | jq -s 'length')
log "proposal: $PROPOSAL_KEY  findings on stdin: $N_IN"

# ── Highest existing IMP id, searched RECURSIVELY (the ledger is a nested
#    object, not a flat array — a top-level scan silently misses most ids) ────
NEXT_NUM=$(jq -r '
  [.. | objects | .id? | select(type == "string") | select(test("^IMP-[0-9]+$"))]
  | map(ltrimstr("IMP-") | tonumber) | max // 0 | . + 1
' "$LEDGER")
log "next free id: IMP-$(printf '%03d' "$NEXT_NUM")"

# ── Build the new entries, skipping any whose sourceProposal already exists ──
NEW_ENTRIES=$(printf '%s\n' "$INPUT" | jq -s \
  --slurpfile ledger "$LEDGER" \
  --arg proposal "$PROPOSAL" \
  --arg pkey "$PROPOSAL_KEY" \
  --arg today "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson start "$NEXT_NUM" '
  ($ledger[0] | [.. | objects | .sourceProposal? | select(type == "string")]) as $seen
  | map(select((($pkey + "#" + .finding) as $k | ($seen | index($k)) | not)))
  | to_entries
  | map({
      _findingId: .value.finding,
      id: ("IMP-" + (($start + .key) | tostring)),
      title: .value.title,
      status: "proposed",
      riskLevel: (.value.riskLevel // "unknown"),
      category: (.value.category // "uncategorized"),
      proposedAt: $today,
      implementedAt: null,
      source: ("weekly-improve auto-write-back (IMP-112) from " + $proposal),
      sourceProposal: ($pkey + "#" + .value.finding),
      notes: (.value.recommendation // ""),
      evidence: (.value.evidence // ""),
      verification: {
        kpi: null, baseline: null, target: null, measured: null, measuredAt: null,
        note: "proposed entries carry no measurement; a human review must set status and fill this block before it may read implemented (IMP-075)"
      }
    })
' )

N_NEW=$(printf '%s' "$NEW_ENTRIES" | jq 'length')
N_DUP=$(( N_IN - N_NEW ))
log "new: $N_NEW   already present (idempotent skip): $N_DUP"

if [[ "$N_NEW" -eq 0 ]]; then
  log "nothing to append — this proposal is already in the ledger"
  exit 0
fi

# ── Pseudonymization gate (IMP-219) on the per-entry fields — see the
#    header comment + scripts/ledger-append-vault-gate.sh for what this does
#    and does not cover. The PKEY half of sourceProposal was already gated
#    above (before the dedup lookup); lvg_init was already called there too.
#    Must run BEFORE the splice below: NEW_ENTRIES is reassigned to the
#    gated (and _findingId-stripped) version, and the splice must never see
#    an un-gated value or the scratch _findingId field. ─────────────────
TMP_ENTRIES_IN="$(mktemp "${TMPDIR:-/tmp}/ledger-append-entries-in.XXXXXX")"
TMP_ENTRIES_OUT="$(mktemp "${TMPDIR:-/tmp}/ledger-append-entries-out.XXXXXX")"
printf '%s' "$NEW_ENTRIES" > "$TMP_ENTRIES_IN"
lvg_gate_entries_file "$TMP_ENTRIES_IN" "$TMP_ENTRIES_OUT" \
  || die "vault gate: internal error while validating new entries — NOTHING written"
NEW_ENTRIES="$(cat "$TMP_ENTRIES_OUT")"
rm -f "$TMP_ENTRIES_IN" "$TMP_ENTRIES_OUT"

[[ "$LVG_BLOCKED" -eq 0 ]] || die "pseudonymization gate blocked one or more findings (see BLOCKED lines above) — NOTHING written, not even the other entries in this run" 1

# ── Splice into the ledger ───────────────────────────────────────────────────
UPDATED=$(jq \
  --argjson new "$NEW_ENTRIES" \
  --arg section "$SECTION" \
  --arg today "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  .[$section] = (
    (.[$section] // {
      description: "Findings written back automatically by the weekly-improve routine (IMP-112). status:\"proposed\" ONLY — a human review promotes them; the routine never self-approves.",
      entries: []
    })
    | .entries += $new
  )
  | .totalImprovements = ([.. | objects | .id? | select(type == "string") | select(test("^IMP-[0-9]+$"))] | unique | length)
  | .lastUpdated = $today
' "$LEDGER") || die "jq splice failed" 1

# ── Gates: valid JSON, id uniqueness, no status regression ───────────────────
printf '%s' "$UPDATED" | jq -e . >/dev/null 2>&1 || die "produced invalid JSON — nothing written" 1

DUP_IDS=$(printf '%s' "$UPDATED" | jq -r '
  [.. | objects | .id? | select(type == "string") | select(test("^IMP-[0-9]+$"))]
  | group_by(.) | map(select(length > 1) | .[0]) | join(",")')
[[ -z "$DUP_IDS" ]] || die "duplicate IMP ids would be created: $DUP_IDS" 1

BAD_STATUS=$(printf '%s' "$NEW_ENTRIES" | jq -r 'map(select(.status != "proposed")) | length')
[[ "$BAD_STATUS" -eq 0 ]] || die "refusing to write an entry with status != proposed (trust boundary)" 1

log "GATE valid JSON: ok   GATE unique ids: ok   GATE all status=proposed: ok"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY-RUN — would append:"
  printf '%s' "$NEW_ENTRIES" | jq -r '.[] | "  \(.id)  [\(.riskLevel)/\(.category)]  \(.title)"'
  exit 0
fi

BACKUP="$LEDGER.bak-append-$(date -u +%Y%m%dT%H%M%SZ)"
cp "$LEDGER" "$BACKUP"
TMP="$(mktemp /tmp/ledger-append.XXXXXX)"
printf '%s\n' "$UPDATED" > "$TMP"
mv "$TMP" "$LEDGER"

log "backup: $BACKUP"
printf '%s' "$NEW_ENTRIES" | jq -r '.[] | "  appended \(.id)  \(.title)"'
log "DONE — $N_NEW proposed entries appended. They await human triage; nothing was applied."
