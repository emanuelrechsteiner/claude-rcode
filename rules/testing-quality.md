---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,py,swift,go,rs,java,kt,kts,rb,php,vue,svelte,astro,sh,bash,zsh,c,h,cc,cpp,hpp,cs,m,mm,dart,gd,lua,ex,exs,scala,sql,prisma,html,css,scss}"
  - "**/tests/**"
  - "**/__tests__/**"
  - "**/*.{test,spec}.*"
---

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

Verification principles — rendered proof for visible claims, verify at the sink, verify via the same code path, automatic check results belong to their trigger — live in `rules/slop-prevention.md` (always loaded; long form in `~/.claude/docs/reference/slop-prevention.md`).

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

## Post-Fix Protocol

After fixing any bug: (1) run `/fix-review` to check for missed occurrences; (2) write a regression test; (3) consider `/pattern-document` if the fix reveals a reusable pattern; (4) commit with a clear message referencing the issue.
