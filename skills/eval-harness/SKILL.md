---
name: eval-harness
description: Eval-driven development for agent work — define capability and regression evals before coding, grade with code, rule, model, or human graders, report pass@k. Use for measurable pass/fail criteria. Triggers on "eval harness", "pass@k", "define evals", "regression eval".
disable-model-invocation: true
---

<!--
Adapted from affaan-m/ECC skills/eval-harness @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# Eval Harness

Eval-driven development (EDD) treats evals as the unit tests of AI-assisted work: write the expected behavior down before implementing, run it repeatedly, track regressions. It is a manual, on-demand procedure (`/eval-harness`), not an always-on behavior.

It sits next to, not in place of, ordinary tests (`testing-suite`, `testing-quality` rules). Use evals when quality cannot be captured by a unit test alone: agent behavior, prompts, skills, open-ended outputs, reliability across retries.

## When to Use

- Setting up eval-driven development for an agent, prompt, or skill change
- Defining pass/fail criteria before a task starts
- Measuring how reliably an agent completes a task (pass@k)
- Building a regression suite for prompt or agent changes
- Comparing behavior across model versions

## Eval types

### Capability evals

Can it do something it could not do before?

```markdown
[CAPABILITY EVAL: feature-name]
Task: what must be accomplished
Success criteria:
  - [ ] Criterion 1
  - [ ] Criterion 2
Expected output: description of the expected result
```

### Regression evals

Did the change break something that worked?

```markdown
[REGRESSION EVAL: feature-name]
Baseline: commit SHA or checkpoint name
Checks:
  - existing-check-1: PASS/FAIL
  - existing-check-2: PASS/FAIL
Result: X/Y passed (previously Y/Y)
```

## Graders

Prefer them in this order: deterministic first, judgment last.

1. **Code grader.** Deterministic checks on the real output.
   ```bash
   grep -q "export function handleAuth" src/auth.ts && echo PASS || echo FAIL
   npm test -- --testPathPattern="auth" && echo PASS || echo FAIL
   npm run build && echo PASS || echo FAIL
   ```
2. **Rule grader.** Regex or schema constraints on an output (JSON schema, required headings, forbidden strings).
3. **Model grader.** An LLM judges open-ended output against a rubric.
   ```markdown
   Evaluate the following change:
   1. Does it solve the stated problem?
   2. Is it well structured?
   3. Are edge cases handled?
   4. Is error handling appropriate?
   Score 1-5 with reasoning.
   ```
   Run the judge in a fresh-context agent (`code-reviewer-agent` for code; per-spawn Agent/Model/Effort per `agents/control-agent.md` §2), never in the session that produced the work, and give it the artifact path rather than your summary of it. Anchor the rubric with concrete pass/fail examples; unanchored scores drift.
4. **Human grader.** For ambiguous or high-risk output, flag it for review.
   ```markdown
   [HUMAN REVIEW REQUIRED]
   Change: what changed
   Reason: why a human must look
   Risk: LOW | MEDIUM | HIGH
   ```

A grader must read the artifact the work produces, not the source the fix just wrote. A check that reads its own edit can only agree with itself (`slop-prevention`, Trigger 3).

## Metrics

- **pass@k**: at least one success in k independent attempts. pass@1 is first-try reliability; pass@3 is reliability with controlled retries.
- **pass^k**: all k attempts succeed. The higher bar, for critical paths.

Suggested thresholds, to tune per project:
- Capability evals: pass@3 at or above 0.90
- Regression evals on release-critical paths: pass^3 = 1.00

State k and the number of trials with every figure. "100%" from three runs is not evidence of 100% reliability.

## Workflow

### 1. Define, before coding

```markdown
## EVAL DEFINITION: feature-xyz

### Capability evals
1. Can create a new user account
2. Can validate the email format
3. Can hash the password securely

### Regression evals
1. Existing login still works
2. Session management unchanged
3. Logout flow intact

### Success metrics
- pass@3 > 90% for capability evals
- pass^3 = 100% for regression evals
```

Write this into the planning artifact for the task (the issue, or `plans/`), so the criteria exist before the implementation does.

### 2. Implement

Write the code against the defined evals. Do not edit an eval to make it pass; changing an eval is a visible, separately explained edit.

### 3. Evaluate

Run each capability eval (record PASS/FAIL per attempt) and the regression checks. For agent-behavior evals, run the task k times in fresh sessions or fresh sub-agents (`testing-agent` for the test-shaped ones; per-spawn Agent/Model/Effort per `agents/control-agent.md` §2); retries inside one polluted context are not independent trials.

### 4. Report

Lead with the verdict, then the table.

```markdown
EVAL REPORT: feature-xyz
Done: yes | no, missing: <list>

Capability evals
  create-user      PASS (pass@1)
  validate-email   PASS (pass@2)
  hash-password    PASS (pass@1)
  Overall          3/3

Regression evals
  login-flow       PASS
  session-mgmt     PASS
  logout-flow      PASS
  Overall          3/3

Metrics
  pass@1: 67% (2/3)    pass@3: 100% (3/3)    trials per eval: 3

Status: READY FOR REVIEW | BLOCKED
```

## Storage

Keep evals with the code, versioned like tests.

```
evals/
  feature-xyz.md      definition
  feature-xyz.log     run history
  baseline.json       regression baselines
```

Where the project uses a release folder, add the eval summary to the release notes.

## Best practices

1. Define evals before coding; it forces clear success criteria.
2. Run them often; regressions are cheapest when caught early.
3. Track pass@k over time, not only the latest number.
4. Prefer code graders; deterministic beats probabilistic.
5. Keep evals fast; slow evals do not get run.
6. Version evals with the code; they are first-class artifacts.
7. Never fully automate security judgments; a human grades those.
8. Verify the grader itself: feed it a known-bad and a known-good case and confirm it tells them apart.

## Anti-patterns

- Overfitting prompts to the known eval examples
- Measuring only the happy path
- Chasing pass rates while cost and latency drift
- Flaky graders inside a release gate
- A model grader that shares context with the work it grades
- Reporting a pass rate without the trial count

## Related skills

- `testing-suite`: unit, E2E, and coverage work that evals complement.
- `quality-review`: multi-specialist review at a milestone.
- `human-testing`: rendered, click-through verification for visible behavior.
