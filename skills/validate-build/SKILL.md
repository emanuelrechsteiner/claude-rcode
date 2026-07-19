---
name: validate-build
description: Full build validation skill. Runs TypeScript compilation, ESLint validation, and production build checks. Generates a comprehensive validation report with pass/fail status for each check. Use when you need to verify code quality before committing, deploying, or creating a PR. Triggers on "validate", "validate build", "check build", "run validation", "pre-commit check", "build check", "type check", "tsc check", "validiere", "build prüfen", "build checken", "ist das gebaut", "baut das", "typescript fehler", "lint fehler", "build kaputt", "kann das kompilieren", "pre-commit".
context: fork
model: haiku
allowed-tools: Read, Glob, Grep, Bash(npm *), Bash(npx tsc *), Bash(npx eslint *)
---

# Validate Build Skill - Comprehensive Code Validation

## Purpose

This skill performs full project validation to catch errors before they reach the repository or production. It provides a structured report with clear pass/fail indicators.

## Validation Sequence

Execute these checks in order, stopping on critical failures:

### 1. TypeScript Compilation Check

```bash
# Run TypeScript compiler without emitting files
npx tsc --noEmit

# Expected: Exit code 0 and no error output
# BLOCKING: If this fails, all other checks are unreliable
```

**What it catches:**
- Type errors
- Missing imports
- Interface mismatches
- Strict null violations
- Unused variables (if configured)

### 2. ESLint Validation

```bash
# Run ESLint on all TypeScript/JavaScript files
npx eslint --ext .ts,.tsx,.js,.jsx src/ --max-warnings 0

# Alternative: Check only staged files
git diff --cached --name-only --diff-filter=ACMR -- '*.ts' '*.tsx' '*.js' '*.jsx' | xargs npx eslint
```

**What it catches:**
- Code style violations
- Potential bugs (unused vars, unreachable code)
- Security issues (unsafe DOM manipulation, eval usage)
- React hook violations
- Import order issues

### 3. Production Build Check

```bash
# Run production build
npm run build

# This validates:
# - All imports resolve correctly
# - No runtime import errors
# - Bundle can be generated
# - Server components render correctly (Next.js)
```

**What it catches:**
- Module resolution errors
- Build-time errors
- Missing environment variables
- Server/client component mismatches

### 4. Unit Tests (If Present)

```bash
# Run tests in non-watch mode
npm test -- --run 2>/dev/null || npm test -- --passWithNoTests 2>/dev/null

# Skip if no test script exists
```

## Validation Report Template

Generate this report after running all checks:

```markdown
# Build Validation Report

**Project**: [project-name]
**Timestamp**: [ISO timestamp]
**Branch**: [current git branch]

## Summary

| Check | Status | Details |
|-------|--------|---------|
| TypeScript | ✅ PASS / ❌ FAIL | [error count] errors |
| ESLint | ✅ PASS / ⚠️ WARN / ❌ FAIL | [error/warning count] |
| Build | ✅ PASS / ❌ FAIL | [build time or error] |
| Tests | ✅ PASS / ❌ FAIL / ⏭️ SKIP | [test count] |

## Overall Status: ✅ READY TO COMMIT / ❌ BLOCKING ISSUES

## Details

### TypeScript Errors
[List specific errors if any]

### ESLint Issues
[List specific issues if any]

### Build Errors
[List specific errors if any]

### Failed Tests
[List failed tests if any]

## Recommendations
[Specific fix recommendations based on errors found]
```

## Quick Commands

```bash
# Full validation (recommended)
npx tsc --noEmit && npx eslint src/ && npm run build

# TypeScript only
npx tsc --noEmit

# ESLint only
npx eslint src/

# Build only
npm run build
```

## When to Use This Skill

1. **Before committing** - Ensure no broken code enters the repository
2. **Before creating PR** - Verify branch is merge-ready
3. **Before deploying** - Final sanity check
4. **After major refactoring** - Verify nothing broke
5. **When CI fails locally** - Debug build issues

## Error Resolution Guide

### TypeScript Errors

| Error Type | Common Cause | Fix |
|------------|--------------|-----|
| TS2307 | Cannot find module | Check import path, install package |
| TS2339 | Property does not exist | Add to interface or use type assertion |
| TS2345 | Argument type mismatch | Fix parameter type or add conversion |
| TS2531 | Object possibly null | Add null check or use optional chaining |
| TS7006 | Parameter has implicit any | Add explicit type annotation |

### ESLint Errors

| Error | Fix |
|-------|-----|
| no-unused-vars | Remove unused variable or prefix with _ |
| react-hooks/exhaustive-deps | Add missing dependencies or disable with comment |
| @typescript-eslint/no-explicit-any | Replace with proper type |
| import/order | Reorder imports according to config |

### Build Errors

| Error Pattern | Common Cause | Fix |
|---------------|--------------|-----|
| Module not found | Missing dependency | npm install [package] |
| Cannot resolve | Wrong import path | Fix the path |
| Server/Client mismatch | Using hooks in server component | Add 'use client' directive |

## Best Practices

1. **Run validation before every commit** - Make it a habit
2. **Fix TypeScript errors immediately** - Don't let them accumulate
3. **Keep zero ESLint warnings** - Warnings become errors over time
4. **Test build locally** - Don't rely solely on CI
5. **Document exceptions** - If you must ignore a rule, explain why

## Additional Resources

### Reference Files
- **`references/error-resolution-guide.md`** - Detailed error codes and resolution steps for TypeScript, ESLint, and build errors
