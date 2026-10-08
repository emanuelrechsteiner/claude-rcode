# Testing & Quality Rules

> Universal testing patterns, validation gates, and quality assurance.

## Testing Cadence

| After... | Do This |
|---|---|
| Implementing a function | Write unit tests for it |
| Completing a feature | Write integration tests |
| Fixing a bug | Write regression test that would have caught it |
| Every 30 minutes of coding | Run existing test suite |
| Before every commit | Run full test suite |

## Coverage Targets

Line ≥80%, branch ≥75%, function ≥80%; every public function has at least one test.

## Test Structure

- **TypeScript (Jest/Vitest):** co-locate tests (`component.test.tsx` next to `component.tsx`); descriptive names (`describe('UserAuth') → it('should reject expired tokens')`); test edge cases — empty inputs, null values, boundary conditions, error paths.
- **Python (pytest):** co-locate or use a `tests/` directory mirroring `src/`; fixtures for shared setup (`conftest.py`); `@pytest.mark.asyncio` for async tests; mock external services, never call real APIs in unit tests.

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
|---|---|
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

A "fixed"/"done" claim about a VISIBLE state (UI, game graphics, layout, render output) is a gate of its own, not covered by a green suite — see [[slop-prevention]] §"Trigger 3 — Visible claim without rendered proof".

### Verify at the Sink, Not the Suite (Data-Exfiltration Fixes) (IMP-158)

A "fixed" claim about a data-exfiltration defect (a filter, exclusion, or manifest gate meant to stop a bulk pipeline from sending certain files/records to an external backend) is only valid with proof taken at the actual sender/output: which files/records the external tool really receives — a capture of the real invocation parameters, or a dry run printing the real target-file list. A green test/regression suite that merely checks a counter or manifest field is **not** that proof: it can confirm an exclusion field was *set* without proving the sender ever *reads* it. Holds for any data-sink fix, not only bulk-pipeline runs; pairs with [[agency-bands]] §"Bulk-Pipeline Manifest Gate (IMP-152)".

### Verify Via the Same Code Path, Not a Reimplementation (IMP-158)

When verifying a fix means counting or resolving something (files, targets, matches) that the production code also counts or resolves, the verification must call the **same** resolution code the production path uses — never a second, independently written counting/matching routine. Separately written implementations drift, and a test on the drifted copy passes while the real path stays broken; a bespoke recount that computes differently from the actual send is itself a defect class, not a safety margin.

### Automatic Check Results Belong to Their Trigger (IMP-158)

If your own action causes an automatic check to run (a security review, a lint pass, any verification firing alongside or after your work), you must retrieve its result before declaring the triggering work "fixed"/"done" — having triggered it is not enough. A check that finds something and logs it where nobody reads it is functionally silent ([[fail-loud]]'s "reported somewhere *observable*?" test, applied to the reporting side). This is a duty on the **work thread**, not a hook this repo can register, whether a Claude-Code-bundled feature (e.g. `/security-review`; the repo defines none of its own) or a repo hook produced the check.

## Post-Fix Protocol

After fixing any bug: (1) run `/fix-review` to check for missed occurrences; (2) write a regression test; (3) consider `/pattern-document` if the fix reveals a reusable pattern; (4) commit with a clear message referencing the issue.
