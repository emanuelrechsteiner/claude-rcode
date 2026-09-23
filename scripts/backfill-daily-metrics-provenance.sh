#!/bin/bash
# backfill-imp111.sh — one-off backfill of the 18 provenance-less daily-metrics rows
# ─────────────────────────────────────────────────────────────────────────────
# IMP-111 (2026-08-01). Second and FINAL round after the 7-row backfill of
# 2026-07-28. Two classes, handled differently and never conflated:
#
#   RECOVERABLE  (shard on disk) → recompute with compute-daily-metrics.sh,
#                                  splice the correct row in place.
#   UNRECOVERABLE (shard pruned) → agent_invocations := null (never a fabricated
#                                  0) + _provenance.source := "UNRECOVERABLE".
#                                  Other fields are LEFT AS RECORDED — they were
#                                  never reported as drifting; inventing values
#                                  for them would repeat the original defect.
#
# Gates before the splice (fail-loud.md): line count unchanged, 0 invalid JSON,
# exactly N changed lines at exactly the N target dates. Backup written first.
#
# Usage: bash backfill-imp111.sh [--dry-run]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

GO="$HOME/.claude/global-observation"
METRICS="$GO/daily-metrics.jsonl"
ARCHIVES="$GO/archives"
COMPUTE="$HOME/.claude/scripts/compute-daily-metrics.sh"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

log() { echo "[backfill-imp111] $*"; }

[[ -f "$METRICS" ]] || { echo "FATAL: $METRICS not found" >&2; exit 2; }
[[ -x "$COMPUTE" || -f "$COMPUTE" ]] || { echo "FATAL: $COMPUTE not found" >&2; exit 2; }

# ── Classify the provenance-less rows AT RUNTIME (never from a stale list) ────
# (no `mapfile` — macOS ships bash 3.2)
TARGETS=()
while IFS= read -r _d; do TARGETS+=("$_d"); done < <(jq -r 'select(._provenance == null) | .date' "$METRICS" | sort)
log "rows without _provenance: ${#TARGETS[@]}"

RECOVERABLE=(); UNRECOVERABLE=()
for d in "${TARGETS[@]}"; do
  if [[ -f "$ARCHIVES/signals-${d}.jsonl.gz" || -f "$ARCHIVES/signals-${d}.jsonl" ]]; then
    RECOVERABLE+=("$d")
  else
    UNRECOVERABLE+=("$d")
  fi
done
log "recoverable  (${#RECOVERABLE[@]}): ${RECOVERABLE[*]:-none}"
log "unrecoverable(${#UNRECOVERABLE[@]}): ${UNRECOVERABLE[*]:-none}"

LINES_BEFORE=$(wc -l < "$METRICS" | tr -d ' ')

# ── Build the replacement rows into a temp map file ──────────────────────────
TMPDIR_WORK="$(mktemp -d /tmp/backfill-imp111.XXXXXX)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT
NEWROWS="$TMPDIR_WORK/newrows.jsonl"; : > "$NEWROWS"

# --- Recoverable: let compute-daily-metrics.sh derive the numbers -------------
for d in "${RECOVERABLE[@]}"; do
  empty_metrics="$TMPDIR_WORK/empty-$d.jsonl"; : > "$empty_metrics"
  if ! CLAUDE_METRICS_FILE="$empty_metrics" \
       CLAUDE_ALERTS_FILE="$TMPDIR_WORK/alerts-$d.jsonl" \
       bash "$COMPUTE" "$d" >"$TMPDIR_WORK/log-$d.txt" 2>&1; then
    echo "FATAL: compute-daily-metrics.sh failed for $d — aborting, nothing written" >&2
    cat "$TMPDIR_WORK/log-$d.txt" >&2
    exit 1
  fi
  row=$(cat "$empty_metrics")
  [[ -n "$row" ]] || { echo "FATAL: empty computed row for $d" >&2; exit 1; }
  # Preserve the ORIGINAL ts (it records when the row was first written; the
  # recompute must not rewrite that timestamp) and mark the backfill.
  orig_ts=$(jq -r --arg d "$d" 'select(.date==$d) | .ts' "$METRICS")
  printf '%s\n' "$row" | jq -c --argjson ts "$orig_ts" \
    '.ts = $ts
     | ._provenance.backfilled_at = "2026-08-01"
     | ._provenance.backfill_note = "IMP-111 round 2: row predates compute-daily-metrics.sh (2026-07-20); recomputed from the intact archive shard. Original ts preserved."' \
    >> "$NEWROWS"
done

# --- Unrecoverable: honest marker, no invented numbers -----------------------
for d in "${UNRECOVERABLE[@]}"; do
  jq -c --arg d "$d" 'select(.date==$d)
    | .agent_invocations = null
    | ._provenance = {
        source: "UNRECOVERABLE",
        computed_by: null,
        reason: "archive shard signals-\($d).jsonl.gz was pruned by the 30-day retention before any backfill ran; the row can never be recomputed",
        backfilled_at: "2026-08-01",
        backfill_note: "IMP-111 round 2: agent_invocations was a fabricated 0 and is now null. tool_invocations/errors/hook_blocks/sessions are LEFT AS ORIGINALLY RECORDED - they were never reported as drifting, and inventing replacements would repeat the defect this fixes. Treat them as UNVERIFIED.",
        capture_surface: "PostToolUse Edit|Write only"
      }' "$METRICS" >> "$NEWROWS"
done

log "built $(wc -l < "$NEWROWS" | tr -d ' ') replacement rows"

# ── Splice: replace each target row by date, leave everything else byte-identical
OUT="$TMPDIR_WORK/daily-metrics.new.jsonl"
jq -c --slurpfile new "$NEWROWS" '
  . as $orig
  | ($new | map({key: .date, value: .}) | from_entries) as $map
  | $map[$orig.date] // $orig
' "$METRICS" > "$OUT"

# ── GATES ────────────────────────────────────────────────────────────────────
LINES_AFTER=$(wc -l < "$OUT" | tr -d ' ')
INVALID=$(( $(wc -l < "$OUT" | tr -d ' ') - $(jq -c . "$OUT" 2>/dev/null | wc -l | tr -d ' ') ))
CHANGED=$(diff <(jq -c . "$METRICS") <(jq -c . "$OUT") | grep -c '^<' || true)

log "GATE line count : $LINES_BEFORE -> $LINES_AFTER"
log "GATE invalid JSON lines: $INVALID"
log "GATE changed lines: $CHANGED (expected ${#TARGETS[@]})"

[[ "$LINES_AFTER" -eq "$LINES_BEFORE" ]] || { echo "GATE FAILED: line count changed" >&2; exit 1; }
[[ "$INVALID" -eq 0 ]] || { echo "GATE FAILED: invalid JSON produced" >&2; exit 1; }
[[ "$CHANGED" -eq "${#TARGETS[@]}" ]] || { echo "GATE FAILED: changed-line count != target count" >&2; exit 1; }

# Verify no row LOST provenance and none of the untouched rows moved
REMAINING_NULL=$(jq -r 'select(._provenance == null) | .date' "$OUT" | wc -l | tr -d ' ')
[[ "$REMAINING_NULL" -eq 0 ]] || { echo "GATE FAILED: $REMAINING_NULL rows still lack _provenance" >&2; exit 1; }
log "GATE rows still lacking _provenance: 0"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY-RUN — no files mutated. Preview of changed rows:"
  diff <(jq -c 'del(._provenance)' "$METRICS") <(jq -c 'del(._provenance)' "$OUT") || true
  exit 0
fi

BACKUP="$METRICS.bak-imp111-$(date -u +%Y%m%dT%H%M%SZ)"
cp "$METRICS" "$BACKUP"
log "backup: $BACKUP"
mv "$OUT" "$METRICS"
log "DONE — ${#RECOVERABLE[@]} recomputed, ${#UNRECOVERABLE[@]} marked UNRECOVERABLE"
