---
name: legacy-codebase-audit
description: Onboarding audit checklist for TypeScript/React codebases flagged as legacy, built with less powerful agents, or showing quality-debt signals. Use on the first session in an unfamiliar TS/React codebase or before feature work on quality-debt code. Triggers on "audit", "codebase audit", "legacy", "technical debt", "modernization", "built with older/less powerful agents", "quality debt", "altlast", "altlasten", "technische schulden", "modernisierung", "code-audit", "codebasis prüfen", "aufräumen vor feature-arbeit".
---

# Legacy Codebase Audit

> Onboarding checklist for TypeScript/React codebases flagged as "built with less powerful agents" or showing quality-debt signals. Derived from an example legacy TS/React project audit, 2026-04-12. On-demand skill — demoted from always-loaded rule per IMP-079 (2026-07-03).

## When This Skill Applies

- First session on an unfamiliar TS/React codebase
- User mentions "technical debt", "modernization", "audit", "legacy", or "built with older/less powerful agents"
- Type-check or test metrics look poor on first read

Run the audit **before** making feature changes. Audit-first prevents compounding debt.

## Audit Checklist (Run in Order)

### 1. TypeScript Strictness
```bash
grep -E '"strict"\s*:\s*(true|false)' tsconfig.json
grep -c ': any\b' src/**/*.ts src/**/*.tsx 2>/dev/null  # baseline any-count
```
**Triage thresholds:**
- `strict: false` → Critical. Migration roadmap required before feature work.
- `any`-count > 50 → High. Schedule dedicated type-coverage sprint.
- `any`-count 10–50 → Medium. Ban new any, attrit over 2–3 PRs.
- `any`-count < 10 → Low. Add lint rule `@typescript-eslint/no-explicit-any: error`.

### 2. Test Coverage
```bash
# Depending on framework
npx vitest run --coverage 2>/dev/null || npx jest --coverage 2>/dev/null
```
**Triage thresholds:**
- < 20% line coverage → Critical. Cannot refactor safely. Write characterization tests before touching code.
- 20–60% → High. Write tests for any file touched.
- 60–80% → Medium. Maintain; add tests for new code.
- 80%+ → OK.

### 3. Security Audit — Cryptography
Hunt for `Math.random()` in security-relevant contexts:
```bash
grep -rn "Math\.random" src/ | grep -viE "test|spec|mock|fixture"
```
**Critical pattern:** `Math.random()` used for:
- Differential privacy noise → non-crypto RNG violates privacy guarantees
- Tokens, IDs, secrets → predictable, enables attacks
- Sampling for compliance/audit → bias risk

**Remediation:** Replace with `crypto.randomInt()` (Node) or `crypto.getRandomValues()` (browser).

### 4. Framework Duplication
```bash
jq '.devDependencies | keys[]' package.json | grep -iE "(jest|vitest|mocha|ava)"
jq '.devDependencies | keys[]' package.json | grep -iE "(react-query|swr|apollo|urql)"
```
**Red flags:**
- Jest AND Vitest both present → Migrate to one, document which wins.
- React Query installed but no `useQuery` calls → Dead dependency; remove or start using.
- Multiple form libraries (react-hook-form + formik) → Pick one.

### 5. File-Size Thresholds
```bash
find src -type f \( -name "*.ts" -o -name "*.tsx" \) -exec wc -l {} + | sort -rn | head -20
```
**Triage:**
- Files > 1500 LOC → Refactor candidates. Split by responsibility.
- Files > 2500 LOC → Critical. Break up before touching.
- Components > 250 LOC → Review for extraction (threshold aligned with `CLAUDE_LINE_LIMIT` default per IMP-050; was 400).

### 6. Dead Dependencies
```bash
npx depcheck 2>/dev/null || npx knip 2>/dev/null
```
Remove unused. Every dead dep is supply-chain surface + install time + mental overhead.

### 7. Build & Lint State
```bash
npx tsc --noEmit 2>&1 | grep -c "error TS"
npx eslint . --max-warnings 0 2>&1 | tail -5
```
If either fails on main branch → first task is restoring green, before feature work.

## Prioritization Matrix

After audit, sequence fixes as:

1. **Security-critical** (Math.random in crypto, secrets exposure, SQL injection) — before any deploy
2. **Build-blocking** (TS errors, lint errors on main) — before next merge
3. **TypeScript strict migration** (stepwise: enable in new files → ban new `any` → attrit existing) — ongoing
4. **Test coverage** (characterize before refactor) — per-PR uplift
5. **File-size / architecture** (split monoliths) — during feature work that touches them
6. **Dep cleanup** — single-PR sweep when stable

**Do NOT start with lowest-risk cleanup.** Security + build-blocking first; aesthetics last.

## Documentation Requirements

For each legacy project, create / update:
- `docs/AUDIT-YYYY-MM-DD.md` — full audit snapshot with metrics
- `docs/MODERNIZATION-ROADMAP.md` — sequenced remediation plan
- `CLAUDE.md` — notes on strictness level, test framework (after consolidation), known hotspots

## Example Reference Case

Specifics from a 2026-04-12 audit (`/path/to/your/legacy-project`):
- TypeScript `strict: false`, 111+ `any` types
- Line coverage 8.7% (far below 20% critical threshold)
- `Math.random()` used for Differential Privacy noise → privacy guarantee violated
- Jest AND Vitest both present → framework consolidation needed
- Largest files > 1500 LOC
- React Query installed but never called

→ Priority order: Security (crypto RNG) → TypeScript strict migration → Code splitting → Coverage uplift. See IMP-010 in improvement-ledger.json.
