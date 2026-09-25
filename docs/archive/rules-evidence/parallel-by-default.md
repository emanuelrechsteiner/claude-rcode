<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Belege, Vorfälle und Messungen, die am 2026-09-24 (IMP-217) wörtlich aus rules/parallel-by-default.md ausgelagert wurden — die Regel selbst bleibt dort; hier steht das „Warum" in voller Länge.
-->
# Belege zu `rules/parallel-by-default.md`

> Ausgelagert 2026-09-24 (IMP-217). Jeder Block steht unter der Überschrift, unter der er in der Regel stand, und ist unverändert übernommen.

## The Norm

This rule exists because: serial execution of independent work is a token-cost and wall-time multiplier. The user's signals.jsonl data shows 27% of work happens across 2+ files in single sessions — much of it parallelizable but currently serialized. Gating *reversible, disjoint* parallel work behind a confirmation prompt added friction without safety value; the gate now applies only where it earns its cost.

## Write-mode dispatches: worktree & follow-up discipline (IMP-070/072)

> **Retracted metric (IMP-114, 2026-08-01).** This passage used to cite "exactly **1** real multi-lock dispatch in 6 weeks" (metareview 2026-07-03). That figure came from `parallel-coordination.jsonl`, which logged only *releases* — and the release path compared two identifier spaces that never intersect (orchestrator claim id vs. runtime harness id), so it reported "released 0 locks" on **3,212 of 3,212** records and was structurally incapable of counting anything. The same broken comparison also drove `parallel-lock-check.sh`, which therefore denied a claimed file to the very subagent it had been claimed for — verified directly on 2026-08-01. Write fan-outs were not merely rare, they were **unusable**. Both defects are fixed and claims are now logged. **Actual usage is currently unmeasured**; the only reliable data point is 18 claims in one session (2026-07-26). Do not cite a usage rate until the new claim log has accumulated. Regression suite: `hooks/tests/parallel-lock-regression.sh`.
