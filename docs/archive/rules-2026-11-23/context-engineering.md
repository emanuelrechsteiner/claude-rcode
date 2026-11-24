# Context Engineering Rules

> Window-relative thresholds for managing Claude Code's context window — soft ceiling 50%, hard ceiling 75–80%, never the 90% auto-compact margin. Always loaded.

## Why Window-Relative (IMP-080)

**All thresholds below are % of the active window**; the historical 200K numbers are the worked example.

## The Thresholds (Reconciled, window-relative)

| Threshold (% of window) | Meaning |
|---|---|
| **~40–60 %** | Onset of degradation ("dumb zone" begins) |
| **~50 % (soft ceiling)** | Smart-zone exit — proactive action needed |
| **~75–80 % (hard ceiling)** | No new heavy work |
| **90 % (auto-compact margin)** | Last-resort process failure (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90` in `settings.json`) |

**Rule:** Soft ceiling **50% of the window**, hard ceiling **75–80%**, **never reach the auto-compact margin**.

## The /context Check at Phase Boundaries

Whenever you transition between PIV/PRP phases (Prime → Plan → Implement → Validate), check `/context` — it reports fill as % of the active window. This is the clean moment to recalibrate; skipping it = drift.

| Current fill (% of window) | Action |
|---|---|
| < 30% | Continue normally |
| 30–50% | Plan-only addition, no heavy reads |
| 50–75% | Proactive `/clear` if next phase is independent. Otherwise compact-to-markdown. |
| 75–90% | Required: write context-snapshot.md, then `/clear` and re-seed from snapshot |
| ≥ 90% | Process failure — log to `signals.jsonl`, post-mortem at session-end |

## Tactics

- **Proactive `/clear`** (recommended at ~50% fill when the next phase is independent): cleanest reset, no compression loss. Re-seed via `claude.md` + relevant files with `@filename`.
- **Intentional compaction** (at 50–75% fill when continuity is required): write `~/Documents/context-snapshot-YYYYMMDD-HHMM.md` (what was done, key decisions and reasoning, open questions, next steps), `/clear`, then seed the new session from it — better than `/compact` because YOU control what's preserved.
- **Subagent dispatch for heavy research:** any research/exploration step expected to consume more than ~10% of the window **must** use a subagent; the main thread receives a summary, not raw content. Use `Explore` for read-only investigation.
- **Never rely on auto-compact:** it is lossy and arbitrary; reaching the auto-compact margin is an observable process failure (log to `signals.jsonl`).

## Anti-Patterns

- ❌ **Anti-patterns:** "just one more thing" at 75%+, carrying context across unrelated issues (`/clear`, see `rules/workflow-git.md`), loading entire codebases at session start.

`session-end-check.sh` can warn when a session crossed the hard ceiling; the R.Code phase-gate command should add a `/context` check before advancing.
