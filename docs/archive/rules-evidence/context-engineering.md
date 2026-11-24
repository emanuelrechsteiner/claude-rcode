<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/context-engineering.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/context-engineering.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Intro (blockquote under the H1 title)

> Reconciled empirical thresholds for managing Claude Code's context window. Derived from KB synthesis of 140 videos on context engineering (2026-05-26); converted to window-relative percentages 2026-07-03 (IMP-080) — windows now range from 200K up to 1M (`[1m]` model suffix), so absolute token constants mislead. Always loaded.

## Why Window-Relative (IMP-080)

The original thresholds (100K soft / 250K hard) were tuned for the Opus-4.x-era **200K** window. Sessions now run on models with windows up to **1M** (`[1m]` suffix, e.g. `claude-fable-5-1[1m]`). Absolute constants mislead in both directions: on a 1M window, 100K is only 10% fill (a premature `/clear` throws away healthy headroom); on a 200K window, treating 250K as "safe" is already past auto-compact. **All thresholds below are % of the active window.** The historical 200K numbers are kept as the worked example.

## References

> Source numbers below are absolute tokens from the 200K-window era (Opus 4.x); read them as the %-of-window thresholds above.

- Matt Pocock — "Full Walkthrough: Workflow for AI Coding" — smart-zone <100K threshold (= ~50% of 200K)
- Cole Medin — "2000+ Hours of Claude Code" / WHISK framework — 250K hallucination cliff (cited on larger-window models)
- Dex Horthy — "No Vibes Allowed: Solving Hard Problems in Complex Codebases" — 40% dumb-zone empirical
- Jared Zoneraich — "How Claude Code Works" — 92% auto-compact mechanism, H2A buffer (local override: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90`)
- Cluster source: see author's knowledge base (private)

## Moved from the rule on 2026-09-29 (IMP-234)

> Moved out verbatim while the rule was condensed to its normative core. The rule keeps the thresholds table without its "Source" column (the provenance lives here) and states the enforcement and anti-pattern items in one line each.

### The Thresholds (Reconciled, window-relative) — original table with sources (verbatim)

| Threshold (% of window) | Event | Worked example (historical 200K window) | Source |
|-------------------------|-------|------------------------------------------|--------|
| **~40–60% fill** | Onset of degradation ("dumb zone" begins) | ~80–120K tokens | Dex Horthy "No Vibes Allowed" |
| **~50% fill (soft ceiling)** | Smart-zone exit — proactive action needed | ~100K tokens | Matt Pocock "Full Walkthrough for AI Coding" |
| **~75–80% fill (hard ceiling)** | No new heavy work | ~150–160K tokens | Practitioner consensus |
| **Beyond the hard ceiling** | Hallucination risk climbs steeply | ~250K tokens (cited on larger-window models) | Cole Medin "2000+ Hours CC" / WHISK |
| **Auto-compact margin (90%)** | Last-resort process failure | ~180K tokens | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90` in `settings.json` (Claude Code stock default: 92%) |

### Anti-Patterns (verbatim items)

### ❌ Loading entire codebases at session start
Anti-pattern from older RAG workflows. Use agentic search — read only what you need when you need it.

### ❌ Skipping the phase-boundary `/context` check
This is when you have a clean moment to recalibrate. Skipping = drift.

### Enforcement (verbatim)

- This rule is always loaded — reminder is in-context
- `session-end-check.sh` hook can warn when session crossed the hard ceiling (75–80% of the window; ~150–160K on the historical 200K window)
- Phase-gate command in R.Code workflow should add `/context` check before advancing

### References (verbatim)

- Model-era conversion to window-relative: IMP-080 (2026-07-03)

## Moved 2026-11-10 (context diet)

Source: pre-diet rules/context-engineering.md (2026-11-10 snapshot). Verbatim blocks, original headings kept.

## Why Window-Relative (IMP-080)

Windows range from 200K up to **1M** (`[1m]` suffix, e.g. `claude-fable-5-1[1m]`), so absolute token constants mislead in both directions (on 1M, 100K is only 10% fill; on 200K, a "safe" 250K is already past auto-compact). **All thresholds below are % of the active window**; the historical 200K numbers are the worked example.

## The Thresholds (Reconciled, window-relative)

Sources cite different "context rot" numbers (40%, 60%, 100K, 92%) because they describe **different events**, not contradictions:

| Threshold (% of window) | Event | Worked example (historical 200K window) |
|---|---|---|
| **~40–60% fill** | Onset of degradation ("dumb zone" begins) | ~80–120K tokens |
| **~50% fill (soft ceiling)** | Smart-zone exit — proactive action needed | ~100K tokens |
| **~75–80% fill (hard ceiling)** | No new heavy work | ~150–160K tokens |
| **Beyond the hard ceiling** | Hallucination risk climbs steeply | ~250K tokens (cited on larger-window models) |
| **Auto-compact margin (90%)** | Last-resort process failure (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90` in `settings.json`; Claude Code stock default 92%) | ~180K tokens |

## The /context Check at Phase Boundaries

| Current fill (% of window) | Action | (200K worked example) |
|---|---|---|
| < 30% | Continue normally | < 60K |
| 30–50% | Plan-only addition, no heavy reads | 60–100K |
| 50–75% | Proactive `/clear` if next phase is independent. Otherwise compact-to-markdown. | 100–150K |
| 75–90% | Required: write context-snapshot.md, then `/clear` and re-seed from snapshot | 150–180K |
| ≥ 90% (auto-compact margin) | Process failure — log to `signals.jsonl`, post-mortem at session-end | 180K+ |

## Tactics

- **Proactive `/clear`** (recommended at ~50% fill when the next phase is independent — task A fully complete, task B a fresh start): cleanest reset, no compression loss. Re-seed via `claude.md` + relevant files with `@filename`.
- **Intentional compaction** (at 50–75% fill when continuity is required) — better than `/compact` because YOU control what's preserved: write `~/Documents/context-snapshot-YYYYMMDD-HHMM.md` (what we did so far, key decisions and reasoning, open questions, next steps), `/clear`, then seed the new session from the snapshot (`@~/Documents/context-snapshot-...md`).
- **Subagent dispatch for heavy research:** any single research/exploration step expected to consume > ~10% of the window (~20K tokens on the historical 200K window — scale proportionally) **must** use a subagent; the main thread receives a summary, not raw content. Use `Explore` for read-only investigation.
- **Never rely on auto-compact:** it summarizes head + tail and deletes the middle — lossy and arbitrary. If you reach the auto-compact margin the workflow has already failed; treat it as an observable process failure (log to `signals.jsonl`).

## Anti-Patterns

- ❌ **"Just one more thing" at 75%+** — adding "small" tasks at high fill rapidly accelerates to auto-compact.
- ❌ **Carrying context across unrelated issues** — issue #42's memory pollutes #43; `/clear` between issues is mandated by [[workflow-git]].
- ❌ **Loading entire codebases at session start** — use agentic search: read only what you need when you need it.

### Second pass

Text removed from `rules/context-engineering.md` by the second pass (2026-11-10, fix-up item B17), verbatim:

```text
B17 removed: write a context snapshot file, `/clear`, then seed the new session from it
```
