---
name: weekly-improve
description: Weekly pattern extraction — reads 7 days of signals, extracts recurring patterns, and writes IMP proposals to ~/.claude/plans/ for human review.
---

<!-- Expected cwd: ~/.claude · Timer: launchd com.claude-code.routine-weekly-improve (since 2026-08-22, IMP-135; label made generic since IMP-219, 2026-09-25; before that an unversioned cloud binding to a directory renamed on 2026-08-02 — 20 days of silent failure). -->

Run the meta-observer skill in weekly aggregation mode.

## Source Doctrine (user directive, 2026-08-23)

As bindingly set out in `skills/meta-observer/SKILL.md` § Source Doctrine: the
weekly analysis reads **primarily the session transcripts** of the window
(`~/.claude/projects/<project>/*.jsonl` + `chat-archives/`), telemetry (points 1–4
below) only **secondarily** for frequency determination. `git log`/commits **never**
serve as the derivation basis for a finding, only as corroboration of the result. Every
finding (F-001, F-002, …) needs transcript evidence (path + quote/event) or an
explicit justification for why none exists. **Scope:** coding projects only — proj-f5739a
and other pure writing projects are excluded as a source, regardless of
signal volume.

**Window selection (mandatory, IMP-195) — NEVER file mtime:** which transcript files
and which entries within them belong in the 7-day window is decided exclusively by the
`timestamp` of the individual JSONL entries — full reasoning + jq/grep example in
`skills/meta-observer/SKILL.md` § Source Doctrine. NEVER apply `find -newermt`/`-mtime`/`ls -t`
to `~/.claude/projects/` to determine "the transcripts of the window" — the run
on 2026-09-09 did exactly that and produced 99 ghost files (mtime exactly `10:30`, content weeks
old) and counted 11 instead of the real 5 active coding projects. mtime may at most serve as a
pre-filter to EXCLUDE (a file clearly older than the window start), never to INCLUDE.

## Time window
Past 7 days, ending Sunday 22:00 local time.

## Data sources
<!-- PATHS FIXED 2026-07-03 (IMP-075): the originals pointed at nonexistent locations
     (~/.claude/signals.jsonl, session-env/) — the 2026-06-28 run found nothing and
     silently produced no report. These are the real paths: -->
1. **Signals:** `~/.claude/global-observation/signals.jsonl` (live, rotates daily) + `~/.claude/global-observation/archives/signals-*.jsonl.gz` — read the last 7 shards with **`gunzip -c`**. Includes `intent:"error"` events since 2026-07-03.
   > ⚠️ **NEVER `zcat` on macOS** (IMP-110, 2026-08-01): BSD `zcat` expects `.Z` and reads a `.gz` file as **empty — exit 0, no stderr, no error**. This silently hid 1,286 signals from the 2026-07-26 run and would have produced a false "quiet week" report. Verify the read is non-empty before analysing: `gunzip -c <shard> | wc -l` must be > 0 for a shard that exists on disk; a 0 here is a **hard error**, not a quiet day (fail-loud.md).
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
- **Transcript evidence (mandatory, Source Doctrine):** [path + quote/event, OR
  a justification for why none exists]
- **Recommendation:** [rule update | skill creation | hook fix | doc update]
- **Concrete action:** [path + diff or new file]
- **Risk:** [what could break]
```

## Ledger write-back — MANDATORY (IMP-112)

Immediately after writing the proposal file, write every finding into the ledger as
`status:"proposed"`. **Do not hand-write JSON** — pipe the findings into the script:

```bash
jq -nc '...one object per finding...' | \
  bash ~/.claude/scripts/ledger-append-proposed.sh --proposal ~/.claude/plans/meta-proposal-YYYY-WW.md
```

One JSON object per line, fields: `finding` (F-001), `title`, `category`, `riskLevel`,
`recommendation`, `evidence`. `evidence` carries the finding's transcript evidence
(Source Doctrine) — not a signals-count alone. The script computes the next free IMP id,
dedups on `<proposal>#<finding>` (so a re-run appends nothing), and gates on valid
JSON + unique ids.

**Knowledge-library contract (2026-10-09, `docs/OBSIDIAN.md` § Contract v3):** never
write a bare `IMP-NNN` for a finding before the script has assigned it — in the
proposal file a future entry is `P-IMP-NNN` (provisional; the knowledge mirror links
every bare `IMP-NNN` to the ledger note of that number, a `P-` prefix stops it).
`evidence` cites files as backtick paths relative to `~/.claude` (`logbook/<day>.md`,
`projects/<folder>/memory/<file>.md`), never a session id alone, so the mirror can
link them. A finding that replaces an earlier ledger entry says so in
`recommendation` (`supersedes IMP-NNN`). A finding without a recommendation is not
written: an empty entry is a dangling node in the library (16 of 238 on 2026-10-09).

**Pseudonymization (IMP-219):** whatever goes into versioned files carries tokens
instead of real names/paths — `ledger-append-proposed.sh` tokenizes every text field
as a net (`scripts/vault/vault.sh`) and refuses to write on a remaining structural
finding. Local working files under `~/.claude/plans/` (gitignored) may carry real
names — only the ledger write path is affected.

**Trust boundary — do not widen it:** the script writes `proposed` and nothing else.
It never promotes to `implemented`, never applies a change. Observation data must not
write framework governance; a human triages `proposed` → `implemented`.

Why this exists: weeks 27–30 produced **25 findings and 0 ledger entries**. A one-word
fix (the `zcat` defect above) sat unapplied for a week and then broke the next run. A
loop that reads but never writes back is indistinguishable from no loop at all.

## Posting
After writing the file, post a Notion comment on the Claude Code Logbuch page
(id: `${CLAUDE_LOGBOOK_NOTION_PAGE_ID}` — read it the same way daily-docs/SKILL.md
does: `[ -n "${CLAUDE_LOGBOOK_NOTION_PAGE_ID:-}" ] || { [ -f "$HOME/.claude/env.local.sh" ] && . "$HOME/.claude/env.local.sh"; }`,
fail loud if still empty — see `templates/env.local.sh.template`) with the file
path and 3-line summary.

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
