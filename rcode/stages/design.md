# Design Playbook

Stage 2 — Design. UX flows, wireframes, design system, and component specs.
Loaded by `~/.claude/commands/team-lead.md` (directly, or via the
`/design-team` alias) once R.Code Mode has selected this Stage.

## Asset cluster

| Asset | Kind | Use for |
|---|---|---|
| `ux-design` | skill | User flows, wireframes, interaction design |
| `ui-development` | skill | Component specs (spec-authoring portion) |
| `ui-agent` | agent (sonnet) | Visual design systems, component specs |
| `scroll-animation-patterns` | skill | RAF-driven scroll animation specs |
| `tailwindcss-v4-styling` | skill | Design-token/theme configuration |
| `kokonutui-pro` | skill | Component index for pre-built UI patterns |
| `human-testing` | skill | Visual acceptance / click-through review |
| `visual-qa-agent` | agent (sonnet, read-only) | Rendered check of a design-system demo/Storybook story against the spec before handoff |

## Core loop

For each in-scope design task, work directly from the asset cluster above —
no absorbed command exists for design work. UX flows and wireframes go
through the `ux-design` skill; design-system and component-spec authoring go
through `ui-development` (spec-authoring portion) and `ui-agent`; the visual
acceptance pass — confirming the result actually looks and behaves right
before handoff — runs through `human-testing` or, for one rendered
artifact, `visual-qa-agent` (per `~/.claude/rules/slop-prevention.md`
Trigger 3: compare against the SOURCE spec, never a paraphrase of it). Tasks
with disjoint file-sets may run in parallel per
`~/.claude/rules/parallel-by-default.md`.

## Idle case

Not every directive needs new design. If team-lead's Stage-detection
judgment finds no design change is required, don't manufacture one: read
the current state, log "no design changes needed" with the one-line reason,
and proceed straight to Proportional Exit — a pass-through turn, not an
empty one.

## Stage nuance (backward transitions)

Full protocol in `~/.claude/rcode/stages/backward-transitions.md` — read it,
don't re-derive it here.

Design's only reachable *outgoing* class is **Iteration (2→1)** —
Design→Plan. Drawing Board needs a target below Stage 1, which doesn't
exist, so that class can't originate here. Design can still be the
**target** of a Drawing Board jump from a later Stage (worked example: 4→2)
— handled by team-lead's Orient step (re-entry-brief check).

## Authority boundary

This Stage's authority ends at a validated design system, flows, and
component specs — not implementation, not application code, not
implementation order. If it becomes clear mid-work that the *plan itself*
is wrong, that's an escalation to management, never a silent re-plan.

## --overnight

When the invoking command carries `--overnight`, follow
`~/.claude/commands/autonomous-overnight.md` unchanged (its `Mechanism
(INVARIANT — DO NOT MODIFY)` section governs ESCALATE-band queueing) — not
restated here.
