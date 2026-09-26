# Stage Backward-Transitions Protocol

> Canonical backward-jump protocol for the five Stages a `/team-lead`
> directive can be loaded into (Plan → Design → Develop → Test → Launch,
> reachable directly or via the `/plan-team`…`/launch-team` aliases): the
> two jump classes, the **futility proof** requirement, the circuit
> breaker, the re-entry-brief artifact, target-Stage entry behavior, and the
> invalidation rule for skipped artifacts. Derived from
> `~/.claude/plans/team-phase-restructure-2026-07-26.md` §5, converted to
> Stage terms 2026-09-23 (R.Code rework "Plan folgt Praxis", ADR 0002).
>
> **Loading:** this file lives under `~/.claude/rcode/stages/` — it is NOT
> globally auto-loaded (absent from CLAUDE.md's Auto-Loaded Rules table).
> Each Stage playbook's "Stage nuance" section, and
> `~/.claude/commands/team-lead.md`'s R.Code Mode, read it by reference when
> a backward jump is under consideration — it is not read on every turn.

## The Two Classes

Forward always runs Stage 1→2→3→4→5 (Plan→Design→Develop→Test→Launch). A
backward jump from Stage N to any Stage < N falls into exactly one of two
classes. Which class applies is decided by **jump distance**, never by
motive.

### 1. Iteration (Stage N → Stage N−1) — SOFT-ACK

The normal working loop; Test→Develop (4→3) is the everyday case.

- The Lead jumps back **itself**, no y/n. It logs one line: the reason, and
  what the target Stage inherits.
- Writes a re-entry brief (short form — see below).
- **Circuit breaker:** on the **3rd consecutive** round of the same loop
  (e.g. 4→3→4→3→4), the *next* jump escalates to the Drawing Board class —
  one question to management: iterate again, or drop deeper? The counter is
  `loop_count` in `.rcode/re-entry-brief.md` (below). Rationale:
  `~/.claude/rules/slop-prevention.md` — an agent told to "make the tests
  green" will weaken the assertion sooner than fix the code, and each single
  round looks plausible in isolation; only the counter catches the pattern
  across rounds.

### 2. Drawing Board (Stage N → Stage < N−1) — ESCALATE

Colloquially "back to the drawing board." Valid **only** once it's
established that Iteration in Stage N−1 cannot fix the problem. Requires a
**futility proof**:

> The blocking constraint was not set in Stage N−1, but in Stage X. No
> solution exists within Stage N−1's degrees of freedom.

A gut feeling ("the design is probably at fault") is explicitly not enough.
The futility proof has four required elements:

1. **Finding in Stage N** — what concretely fails, with evidence
2. **Futility proof for Stage N−1** — which constraint blocks, and which
   Stage set it
3. **Target Stage X + change mandate** — what must change there
4. **Invalidation list** — which artifacts from the skipped Stages become
   suspect (see Invalidation below)

#### Worked examples

| Jump | Class | Why |
|---|---|---|
| 4→3 (Test→Develop) | Iteration | Test finds a bug; Develop can fix it |
| 4→2 (Test→Design) | Drawing Board — futility proof required | The required state must cross a component boundary that **Design** drew — no implementation path inside that design satisfies it |
| 4→1 (Test→Plan) | Drawing Board — futility proof required | The feature demonstrably solves the wrong user problem — no design of it helps |
| 5→3 (Launch→Develop) | Drawing Board — futility proof required | Prod incident whose root cause is an implementation decision Test could not structurally have caught |

## Re-Entry Brief (Artifact)

Every backward jump — Iteration included — writes
`.rcode/re-entry-brief.md`. Skipping it means the target Stage starts
blind, and the jump becomes unauditable after the fact.

```markdown
# Re-Entry Brief
- from_stage: 4 · to_stage: 2 · class: drawing-board | iteration
- loop_count: <Nth consecutive round of the same loop>
- date: YYYY-MM-DD · authorized_by: lead | user-y/n

## Finding (Stage N)
## Futility Proof for Stage N−1   (drawing-board class only)
## Change Mandate to Target Stage
## Invalidation List                  (see Invalidation below)
```

## Target-Stage Entry Behavior

`~/.claude/commands/team-lead.md`'s R.Code Mode Orient step checks for
`.rcode/re-entry-brief.md` on every turn. If its `to_stage` equals the
Stage this turn detects or was forced into, that Stage must: read the brief
first, adopt its change mandate as scope, carry its invalidation list into
this turn's Proportional Exit — and, only after completing that work,
archive the brief to `.rcode/re-entry-archive/`. Never delete it; it is the
audit trail for the jump.

## Invalidation of Skipped Artifacts

A 4→2 jump calls the Stage-3 work into question on the merits. Rule:
artifacts from the skipped Stages are **not auto-discarded** — they are
marked *suspect* and **re-verified through their own Stage's checks** (the
skipped Stage's asset cluster / core loop, per its playbook) on the next
forward pass. "It was already green" does not excuse skipping that
re-verification — the same discipline as `~/.claude/rules/slop-prevention.md`
(never build on unverified work). This is deliberately NOT phrased as
"re-run `/phase-gate`" — `/phase-gate` gates the project Phase (milestone),
a different axis from Stage; conflating the two was exactly the confusion
this rework's glossary (`~/.claude/rcode/README.md`) exists to end.

## References

- Full protocol origin: `~/.claude/plans/team-phase-restructure-2026-07-26.md` §5
- Companions: `~/.claude/rules/slop-prevention.md` (circuit breaker +
  invalidation rationale), `~/.claude/rules/agency-bands.md` (SOFT-ACK vs.
  ESCALATE semantics)
- Read by the "Stage nuance" section of every playbook —
  `~/.claude/rcode/stages/plan.md`, `design.md`, `develop.md`, `test.md`,
  `launch.md` — and by `~/.claude/commands/team-lead.md`'s R.Code Mode.
