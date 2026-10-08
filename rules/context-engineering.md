# Context Engineering Rules

> Window-relative thresholds for managing Claude Code's context window — soft ceiling 50%, hard ceiling 75–80%, never the 90% auto-compact margin. Always loaded.

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

**Rule:** Soft ceiling **50% of the window**, hard ceiling **75–80%**, **never reach the auto-compact margin**.

## The /context Check at Phase Boundaries

Whenever you transition between PIV/PRP phases (Prime → Plan → Implement → Validate), check `/context` — it reports fill as % of the active window. This is the clean moment to recalibrate; skipping it = drift.

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

`session-end-check.sh` can warn when a session crossed the hard ceiling; the R.Code phase-gate command should add a `/context` check before advancing.
