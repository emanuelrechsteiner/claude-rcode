# Context Engineering Rules

> Reconciled empirical thresholds for managing Claude Code's context window. Derived from KB synthesis of 140 videos on context engineering (2026-05-26); converted to window-relative percentages 2026-07-03 (IMP-080) — windows now range from 200K up to 1M (`[1m]` model suffix), so absolute token constants mislead. Always loaded.

## Why Window-Relative (IMP-080)

The original thresholds (100K soft / 250K hard) were tuned for the Opus-4.x-era **200K** window. Sessions now run on models with windows up to **1M** (`[1m]` suffix, e.g. `claude-fable-5[1m]`). Absolute constants mislead in both directions: on a 1M window, 100K is only 10% fill (a premature `/clear` throws away healthy headroom); on a 200K window, treating 250K as "safe" is already past auto-compact. **All thresholds below are % of the active window.** The historical 200K numbers are kept as the worked example.

## The Thresholds (Reconciled, window-relative)

Multiple sources cite different "context rot" numbers (40%, 60%, 100K, 92%). They describe **different events**, not contradictions:

| Threshold (% of window) | Event | Worked example (historical 200K window) | Source |
|-------------------------|-------|------------------------------------------|--------|
| **~40–60% fill** | Onset of degradation ("dumb zone" begins) | ~80–120K tokens | Dex Horthy "No Vibes Allowed" |
| **~50% fill (soft ceiling)** | Smart-zone exit — proactive action needed | ~100K tokens | Matt Pocock "Full Walkthrough for AI Coding" |
| **~75–80% fill (hard ceiling)** | No new heavy work | ~150–160K tokens | Practitioner consensus |
| **Beyond the hard ceiling** | Hallucination risk climbs steeply | ~250K tokens (cited on larger-window models) | Cole Medin "2000+ Hours CC" / WHISK |
| **Auto-compact margin (90%)** | Last-resort process failure | ~180K tokens | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90` in `settings.json` (Claude Code stock default: 92%) |

**Rule:** Soft ceiling **50% of the window**, hard ceiling **75–80%**, **never reach the auto-compact margin** (90% per `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90` in `settings.json`).

## The /context Check at Phase Boundaries

Whenever you transition between PIV/PRP phases (Prime → Plan → Implement → Validate), check `/context` — it reports fill as % of the active window:

| Current fill (% of window) | Action | (200K worked example) |
|----------------------------|--------|------------------------|
| < 30% | Continue normally | < 60K |
| 30–50% | Plan-only addition, no heavy reads | 60–100K |
| 50–75% | Proactive `/clear` if next phase is independent. Otherwise compact-to-markdown. | 100–150K |
| 75–90% | Required: write context-snapshot.md, then `/clear` and re-seed from snapshot | 150–180K |
| ≥ 90% (auto-compact margin) | Process failure — log to `signals.jsonl`, post-mortem at session-end | 180K+ |

## Tactics

### Proactive `/clear` (recommended at ~50% fill when next phase independent)
Cleanest reset. No compression loss. Re-seed via `claude.md` + relevant files with `@filename`. Use when task A is fully complete and task B is a fresh start.

### Intentional Compaction (at 50–75% fill when continuity required)
Better than `/compact` because YOU control what's preserved.

Workflow:
1. Write `~/Documents/context-snapshot-YYYYMMDD-HHMM.md` with:
   - What we did so far
   - Key decisions and reasoning
   - Open questions
   - Next steps
2. `/clear`
3. Seed new session from the snapshot file (`@~/Documents/context-snapshot-...md`)

### Subagent Dispatch for Heavy Research
Any single research/exploration step expected to consume > ~10% of the window (~20K tokens on the historical 200K window — scale proportionally on larger windows) **must** use a subagent. Main thread receives summary, not raw content. Use `Explore` for read-only investigation.

### Never Rely on Auto-Compact (the 90% margin)
Auto-compact summarizes head + tail and deletes the middle — lossy and arbitrary. Locally it fires at 90% (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90` in `settings.json`; Claude Code's stock default is 92%). If you reach the auto-compact margin the workflow has already failed. Treat reaching it as an observable process failure (log to signals.jsonl).

## Anti-Patterns

### ❌ "Just one more thing" at 75%+
Adding "small" tasks at high fill rapidly accelerates to auto-compact.

### ❌ Carrying context across unrelated issues
The conversation memory from issue #42 will pollute issue #43. `/clear` between issues is already mandated by `workflow-git.md`.

### ❌ Loading entire codebases at session start
Anti-pattern from older RAG workflows. Use agentic search — read only what you need when you need it.

### ❌ Skipping the phase-boundary `/context` check
This is when you have a clean moment to recalibrate. Skipping = drift.

## Enforcement

- This rule is always loaded — reminder is in-context
- `session-end-check.sh` hook can warn when session crossed the hard ceiling (75–80% of the window; ~150–160K on the historical 200K window)
- Phase-gate command in R.Code workflow should add `/context` check before advancing

## References

> Source numbers below are absolute tokens from the 200K-window era (Opus 4.x); read them as the %-of-window thresholds above.

- Matt Pocock — "Full Walkthrough: Workflow for AI Coding" — smart-zone <100K threshold (= ~50% of 200K)
- Cole Medin — "2000+ Hours of Claude Code" / WHISK framework — 250K hallucination cliff (cited on larger-window models)
- Dex Horthy — "No Vibes Allowed: Solving Hard Problems in Complex Codebases" — 40% dumb-zone empirical
- Jared Zoneraich — "How Claude Code Works" — 92% auto-compact mechanism, H2A buffer (local override: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90`)
- Model-era conversion to window-relative: IMP-080 (2026-07-03)
- Cluster source: see author's knowledge base (private)
