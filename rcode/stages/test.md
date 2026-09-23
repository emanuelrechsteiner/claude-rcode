# Test Playbook

Stage 4 — Test & Review. Milestone/RC validation, PR review, and
safety-net strategy. Loaded by `~/.claude/commands/team-lead.md` (directly,
or via the `/test-team` alias) once R.Code Mode has selected this Stage.

## Asset cluster

| Asset | Kind | Use for |
|---|---|---|
| `quality-review` | skill | 6-specialist milestone review (arch/security/perf/testing/maintainability/docs) |
| `testing-agent` | agent (sonnet) | Coverage gaps, regression tests |
| `code-reviewer-agent` | agent (sonnet, read-only) | Per-file code review |
| `visual-qa-agent` | agent (sonnet, read-only) | Rendered check in a real browser before a milestone/RC is signed off |
| `testing-suite` | skill | Unit/E2E/visual test authoring |
| `human-testing` | skill | Manual UX/UI click-through validation |
| `validate-build` | skill | Build/type/lint validation |
| `fix-review` | skill | Post-fix missed-occurrence sweep |
| `type-coverage` | skill | Type-coverage measurement |

## Operating modes

| Mode | Trigger when | Procedure |
|---|---|---|
| Milestone / RC Validation (default) | Directive names a milestone, RC, or coverage goal spanning a file-set | Assemble the validation strategy directly from the asset cluster above — native to this Stage, no absorbed command |
| PR Review | Directive names one specific PR (github tracker) or branch diff (plan tracker) | `~/.claude/commands/rcode-review.md` |

**Distinction:** this Stage validates a milestone-wide file-set, not a
single PR (Develop already reviews single PRs/diffs inside its own Core
loop). This Stage sets validation *strategy*, not the pass/fail gate
checklist — that stays `~/.claude/commands/phase-gate.md`'s job, and belongs
to the project Phase (milestone), not this Stage.

## Stage nuance (backward transitions)

Full protocol in `~/.claude/rcode/stages/backward-transitions.md` — read it,
don't re-derive it here.

Test's standard loop is **4→3** (Iteration) — a found bug Develop can fix;
the tightest loop in the model, and the one most likely to hit the circuit
breaker (`~/.claude/rules/slop-prevention.md`: told to "make the tests
green," an agent will weaken the assertion sooner than fix the code, and
each round looks plausible alone). Its drawing-board cases are **4→2** (the
required state crosses a component boundary the design drew) and **4→1**
(the feature solves the wrong problem).

## Authority boundary

This Stage's authority ends at a validated go/no-go verdict on the
milestone or RC — not implementing fixes itself beyond directing the
specialist agents above, not release timing, not shipping. If it becomes
clear mid-work that the *plan itself* is wrong (scope was never
test-ready), that's an escalation to management, never a silent re-plan.

## --overnight

When the invoking command carries `--overnight`, follow
`~/.claude/commands/autonomous-overnight.md` unchanged (its `Mechanism
(INVARIANT — DO NOT MODIFY)` section governs ESCALATE-band queueing) — not
restated here.
