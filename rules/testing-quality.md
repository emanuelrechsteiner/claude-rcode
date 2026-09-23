# Testing & Quality Rules

> Universal testing patterns, validation gates, and quality assurance.

## Testing Cadence

| After... | Do This |
|----------|---------|
| Implementing a function | Write unit tests for it |
| Completing a feature | Write integration tests |
| Fixing a bug | Write regression test that would have caught it |
| Every 30 minutes of coding | Run existing test suite |
| Before every commit | Run full test suite |

## Coverage Targets

- **Line coverage:** ≥80%
- **Branch coverage:** ≥75%
- **Function coverage:** ≥80%
- Every public function should have at least one test

## Test Structure

### TypeScript (Jest/Vitest)
- Co-locate tests: `component.test.tsx` next to `component.tsx`
- Descriptive names: `describe('UserAuth') → it('should reject expired tokens')`
- Test edge cases: empty inputs, null values, boundary conditions, error paths

### Python (pytest)
- Co-locate or use `tests/` directory mirroring `src/` structure
- Fixtures for shared setup (`conftest.py`)
- `@pytest.mark.asyncio` for async tests
- Mock external services, never call real APIs in unit tests

## Validation Gates

### Before Every Commit (REQUIRED)
```
npx tsc --noEmit       # TypeScript check (TS projects)
npm test               # Run tests
npm run build          # Verify build succeeds
```

Or for Python:
```
mypy .                 # Type check
pytest                 # Run tests
ruff check .           # Linting
black --check .        # Formatting
```

### Phase Transition Gates

| From → To | Required Checks |
|-----------|-----------------|
| Planning → Implementation | Architecture approved |
| Implementation → Testing | Type check + build pass |
| Testing → Documentation | Tests pass, coverage met |
| Documentation → Commit | All above + no lint errors |

### NEVER Proceed If:
- Type checker has errors
- Build fails
- Tests fail
- Stray characters at EOF detected

### Rendered-Proof for Visual Claims

A "fixed"/"done" claim about a VISIBLE state (UI, game graphics, layout, render output) is a validation gate like any other — see `slop-prevention.md` Trigger 3 for the full rule (rendered proof required — screenshot of the running program / rendered page; self-referential tests forbidden). Don't fold a visual claim into the type-check/test-suite gates above: a green test suite proves the code compiles and the assertions pass, not that the thing actually looks right when rendered.

### Verify at the Sink, Not the Suite (Data-Exfiltration Fixes) (IMP-158)

A "fixed" claim about a data-exfiltration defect — a filter, exclusion, or manifest gate meant to stop a bulk pipeline from sending certain files/records to an external backend — is only valid with proof taken at the actual sender/output: which files/records the external tool really receives (a capture of the real invocation parameters, or a dry run that prints the real target-file list). A green test/regression suite that merely checks a counter or a manifest field is **not** that proof — it can confirm an exclusion field was *set* correctly without proving the sender ever *reads* that field. This is a general rule for any data-sink fix, not only bulk-pipeline runs; see `agency-bands.md` "Bulk-Pipeline Manifest Gate (IMP-152)" for the related ESCALATE rule this pairs with.

**Evidence:** 2026-08-03 — the automatic security check found the first fix cosmetic: "the 'exclusion' only removes files from the file count … `graphify extract` is invoked on the unfiltered project root". Four minutes later the triggering work-thread reported "fixed" with 42 green checks. The green suite measured the file counter, not the actual call the external tool received — exactly the confusion this rule forbids.

### Verify Via the Same Code Path, Not a Reimplementation (IMP-158)

When a fix's verification needs to count or resolve something (files, targets, matches) that the production code also counts or resolves, the verification must call the **same** resolution code the production path uses — not a second, independently written counting/matching routine. Two implementations meant to agree but written separately will drift, and a test built on the drifted copy passes while the real path stays broken; a bespoke recount that computes differently from the actual send is itself a defect class, not a safety margin.

**Evidence (same incident as above, the countermeasure that held):** "Ich habe dafür bewusst denselben Zähl-Code verwendet wie die Zielauflösung selbst, keine Nachbau-Logik — eine zweite, eigene Zählung, die anders rechnet als der Versand, war genau der Konstruktionsfehler hinter dem Vorfall."

### Automatic Check Results Belong to Their Trigger (IMP-158)

If your own action causes an automatic check to run — a security review, a lint pass, any verification that fires alongside or after your work — you are responsible for retrieving that check's result before declaring the triggering work "fixed"/"done", not merely for having triggered it. A check that runs, finds something, and logs it where nobody reads it is functionally silent — this is `fail-loud.md`'s "did the failure get reported somewhere *observable*?" test applied to the reporting side, not just the failing side.

**Scope note:** at the time of writing, no `/security-review` command or skill is defined in this repo (`commands/`, `skills/`) — the string `security-review` appears only in `skills/audit-config/SKILL.md` as a name to avoid colliding with, i.e. it is treated there as a **Claude-Code-bundled** feature, not a repo-owned one. This rule is therefore written as a duty on the **work thread**, not as a hook this repo can register: whoever's action caused an automatic check to run must read its outcome before reporting completion, regardless of whether a bundled feature or a repo hook produced the check.

**Evidence (same incident):** the check that found the fix cosmetic never reached the work-thread that reported "fixed" four minutes later. See `agency-bands.md` "Bulk-Pipeline Manifest Gate (IMP-152)" § "Verify at the sink, not the suite" for the exfiltration-specific half of this same incident.

## Post-Fix Protocol

After fixing any bug:
1. Run `/fix-review` to check for missed occurrences
2. Write a regression test
3. Consider `/pattern-document` if the fix reveals a reusable pattern
4. Commit with clear message referencing the issue
