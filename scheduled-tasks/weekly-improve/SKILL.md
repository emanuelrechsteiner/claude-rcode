---
name: weekly-improve
description: Weekly pattern extraction — reads 7 days of signals, extracts recurring patterns, and writes IMP proposals to ~/.claude/plans/ for human review.
---

<!-- Erwartetes cwd: ~/.claude · Zeitgeber: launchd com.your-username.claude-routine-weekly-improve (seit 2026-08-22, IMP-135; davor unversionierte Cloud-Bindung an ein 2026-08-02 umbenanntes Verzeichnis — 20 Tage stiller Ausfall). -->

Run the meta-observer skill in weekly aggregation mode.

## Quellen-Doktrin (Nutzer-Direktive 2026-08-23)

Wie in `skills/meta-observer/SKILL.md` § Quellen-Doktrin verbindlich festgelegt: die
Wochenanalyse liest **primär die Session-Transkripte** des Fensters
(`~/.claude/projects/<projekt>/*.jsonl` + `chat-archives/`), Telemetrie (Punkt 1–4
unten) nur **sekundär** zur Häufigkeitsbestimmung. `git log`/Commits dienen **nie** als
Herleitungsbasis eines Findings, nur als Korroboration des Ergebnisses. Jedes Finding
(F-001, F-002, …) braucht einen Transkript-Beleg (Pfad + Zitat/Ereignis) oder eine
explizite Begründung, warum keiner existiert. **Scope:** nur Coding-Projekte — Projekt A
und andere reine Schreibprojekte sind als Quelle ausgenommen, unabhängig vom
Signalvolumen.

**Fenster-Selektion (Pflicht, IMP-195) — NIE Datei-mtime:** Welche Transkriptdateien
und welche Einträge darin ins 7-Tage-Fenster gehören, wird ausschliesslich über den
`timestamp` der einzelnen JSONL-Einträge entschieden — volle Begründung + jq/grep-Beispiel
in `skills/meta-observer/SKILL.md` § Fenster-Selektion. NIE `find -newermt`/`-mtime`/`ls -t`
auf `~/.claude/projects/` anwenden, um "die Transkripte des Fensters" zu ermitteln — im Lauf
vom 2026-09-09 lieferte genau das 99 Geisterdateien (mtime exakt `10:30`, Inhalt Wochen
alt) und zählte 11 statt real 5 aktive Coding-Projekte. mtime darf höchstens als Vorfilter
AUSSCHLIESSEN (Datei eindeutig älter als der Fensterbeginn), nie EINSCHLIESSEN.

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
- **Transkript-Beleg (Pflicht, Quellen-Doktrin):** [Pfad + Zitat/Ereignis, ODER
  Begründung warum keins existiert]
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
`recommendation`, `evidence`. `evidence` carries the Transkript-Beleg from the finding
(Quellen-Doktrin) — not a signals-count alone. The script computes the next free IMP id,
dedups on `<proposal>#<finding>` (so a re-run appends nothing), and gates on valid
JSON + unique ids.

**Trust boundary — do not widen it:** the script writes `proposed` and nothing else.
It never promotes to `implemented`, never applies a change. Observation data must not
write framework governance; a human triages `proposed` → `implemented`.

Why this exists: weeks 27–30 produced **25 findings and 0 ledger entries**. A one-word
fix (the `zcat` defect above) sat unapplied for a week and then broke the next run. A
loop that reads but never writes back is indistinguishable from no loop at all.

## Posting
After writing the file, post a Notion comment on the Claude Code Logbuch page
(id: <your-notion-page-id>) with the file path and 3-line summary.

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