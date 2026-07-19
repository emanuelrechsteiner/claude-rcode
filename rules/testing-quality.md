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

## Post-Fix Protocol

After fixing any bug:
1. Run `/fix-review` to check for missed occurrences
2. Write a regression test
3. Consider `/pattern-document` if the fix reveals a reusable pattern
4. Commit with clear message referencing the issue
