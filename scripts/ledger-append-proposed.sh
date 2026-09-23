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

PROPOSAL_KEY="$(basename "$PROPOSAL")"

# ── Read + validate the findings from stdin ──────────────────────────────────
INPUT="$(cat)"
[[ -n "${INPUT// }" ]] || die "no findings on stdin (a run with 0 findings should not call this)" 1

if ! printf '%s\n' "$INPUT" | jq -e . >/dev/null 2>&1; then
  die "stdin is not valid JSONL" 1
fi
if printf '%s\n' "$INPUT" | jq -e 'select((.finding // "") == "" or (.title // "") == "")' >/dev/null 2>&1; then
  die "every finding needs a non-empty .finding and .title" 1
fi

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
