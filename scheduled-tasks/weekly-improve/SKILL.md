---
name: weekly-improve
description: Weekly pattern extraction — reads 7 days of signals, extracts recurring patterns, and writes IMP proposals to ~/.claude/plans/ for human review.
---

Run the meta-observer skill in weekly aggregation mode.

## Time window
Past 7 days, ending Sunday 22:00 local time.

## Data sources
<!-- PATHS FIXED 2026-07-03 (IMP-075): the originals pointed at nonexistent locations
     (~/.claude/signals.jsonl, session-env/) — the 2026-06-28 run found nothing and
     silently produced no report. These are the real paths: -->
1. **Signals:** `~/.claude/global-observation/signals.jsonl` (live, rotates daily) + `~/.claude/global-observation/archives/signals-*.jsonl.gz` (zcat the last 7 shards). Includes `intent:"error"` events since 2026-07-03.
2. **Session metrics:** `~/.claude/global-observation/session-metrics.jsonl` — filter last 7 days by `ts`
3. **Improvement ledger:** `~/.claude/global-observation/improvement-ledger.json` — existing IMP-* entries (to avoid duplicates); note the sections `metaObserverImprovements_2026-06-20` and `metareviewImprovements_2026-07-03`
4. **Self-critique metadata:** `~/.claude/global-observation/self-critique.jsonl` — last 7 days (session end states)
5. **Memory updates:** weekly diff of `~/.claude/projects/*/memory/`

## Pattern extraction targets

### A) Recurring errors (≥3 occurrences in window)
- Tool errors (Edit-before-Read, hook blocks)
- Build/test failures with common root cause
- Hook false-positives or escapes
→ Recommend: rule update, hook fix, skill creation

### B) Tool-usage anti-patterns
- `Bash(cat ...)` instead of Read (per tool-discipline.md)
- `subagent_type: unspecified` calls
- Sequential calls that should have been parallel
→ Recommend: tool-discipline.md update, rule refinement

### C) Validated workflows (positive signal)
- Sequences user explicitly praised ("yes exactly", "perfect")
- Patterns repeated successfully across multiple sessions
→ Recommend: promote to rule or skill

### D) Memory drift
- Memories contradicting current code state
- Stale references (file paths, function names) detected via grep
→ Recommend: memory cleanup, MEMORY.md curation

## Output
Path: `~/.claude/plans/meta-proposal-YYYY-WW.md` (W = ISO week number)

Structure:
```markdown
# Meta-Proposal Week YYYY-WW (ending YYYY-MM-DD)

## Summary
[N findings, classified by priority]

## Findings

### F-001 (priority: high|medium|low)
- **Pattern:** [recurring observation]
- **Frequency:** [N occurrences in window]
- **Recommendation:** [rule update | skill creation | hook fix | doc update]
- **Concrete action:** [path + diff or new file]
- **Risk:** [what could break]
```

## Posting
After writing the file, post a Notion comment on the Claude Code Logbuch page
(id: `${NOTION_PARENT_PAGE_ID}`, set in `settings.local.json` `env`) with the file path and 3-line summary.

## Run log — MANDATORY, even on failure (IMP-075)
As the FINAL step of every run — including "quiet week" and error runs — append one line to
`~/.claude/global-observation/weekly-improve-log.jsonl`:
```bash
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg status "ok|quiet|error" \
       --arg proposal "<path-or-empty>" --arg findings "<N>" \
       '{ts:$ts,task:"weekly-improve",status:$status,proposal:$proposal,findings:($findings|tonumber)}' \
       >> ~/.claude/global-observation/weekly-improve-log.jsonl
```
A run that leaves no log line is indistinguishable from a run that never fired — that
ambiguity hid a silently-failing run on 2026-06-28 (fail-loud.md applies to routines too).

## Important
- Do NOT auto-apply any changes. This is review-gated.
- Highlight low-confidence findings explicitly.
- If no patterns found, write a brief "quiet week" report. Don't fabricate.