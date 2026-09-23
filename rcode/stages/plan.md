# Plan Playbook

Stage 1 — Plan. Product foundation, architecture, roadmap, and work-unit
slicing. Loaded by `~/.claude/commands/team-lead.md` (directly, or via the
`/plan-team` alias) once R.Code Mode has selected this Stage.

## Asset cluster

| Asset | Kind | Use for |
|---|---|---|
| `planning-agent` | agent (opus) | Architecture, task breakdown, plans |
| `research-agent` | agent (haiku) | Tech/market research, prior-art, API survey; can write a report file |
| `research` | skill | Lighter-weight research that doesn't need a standalone report file |
| `project-planning` | skill | Roadmap structuring, dependency mapping |
| `project-bootstrap` | skill | Repo exploration, docs audit, project setup |
| `scope-check` | skill | Scope-creep verification against the plan |

## Operating modes

Each mode is a TRIGGER — read the named file and execute its procedure,
never copy it into this turn's context.

| Mode | Trigger when | Procedure |
|---|---|---|
| Greenfield Foundation | No product docs, idea-stage | `~/.claude/commands/brainstorm.md` |
| Roadmap → Units | `BRAINSTORM.md` exists, no/stale units | `~/.claude/commands/decompose.md` |
| Greenfield Rails | Empty/new repo, no `.rcode/` | `~/.claude/commands/rcode-init.md` |
| Existing-Codebase Adoption | Substantial code, no `.rcode/` | `~/.claude/commands/rcode-migrate.md` |
| First Orientation | Unknown repo, suitability unclear | `~/.claude/commands/simple-onboard.md` |
| Docs Audit + Scaffolding | Docs drift, asset-audit needed | `~/.claude/commands/bootstrap.md` |
| Mid-Life Replanning | Roadmap must be re-prioritized | No absorbed command — first-time coverage: re-read `PROJECT-STATUS.md` + `.rcode/scope-manifest.json`, diff via `planning-agent`, run the `scope-check` skill before handoff |

## Stage nuance (backward transitions)

Full protocol (both jump classes, Futilitätsnachweis, circuit breaker,
re-entry brief, invalidation) is defined once in
`~/.claude/rcode/stages/backward-transitions.md` — read it, don't re-derive
it here.

Plan is the earliest Stage — no Stage 0, and no Stage below it in this
scheme. This Stage is always the **target** of a backward transition, never
its source — any Stage N → Stage 1 jump falls under the general
Drawing-Board rule (Stage N → Stage < N−1), whose one worked example landing
on Stage 1 is 4→1; a jump like 5→1 applies that same general rule rather
than being separately worked out. Team-lead's Orient step (re-entry-brief
check) is how this Stage receives that jump.

## Authority boundary

This Stage's authority ends at a validated plan, roadmap, or work-unit set —
not code, not tests, not implementation order beyond the handed-off roadmap.
If it becomes clear mid-work that the *plan itself* is wrong, that's an
escalation to management, never a silent re-plan.

## --overnight

When the invoking command carries `--overnight`, follow
`~/.claude/commands/autonomous-overnight.md` unchanged (its `Mechanism
(INVARIANT — DO NOT MODIFY)` section governs ESCALATE-band queueing) — not
restated here.
