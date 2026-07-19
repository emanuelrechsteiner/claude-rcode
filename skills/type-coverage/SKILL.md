---
name: type-coverage
description: Track and improve TypeScript type coverage. Identifies untyped code, implicit any usage, and type safety gaps. Use to understand codebase type safety and systematically improve it. Triggers on "type coverage", "typescript coverage", "any types", "type safety", "improve types", "type audit".
allowed-tools: Read, Glob, Grep, Bash(npx tsc *, npx type-coverage *)
---

# Type Coverage Skill - TypeScript Type Safety Audit

## Purpose

Measure and improve TypeScript type coverage across the codebase. Identify areas with weak typing and prioritize improvements.

## When to Use

- During code quality audits
- Before major refactoring
- When inheriting a codebase
- To track type safety improvements over time
- When reducing `any` usage

## Quick Coverage Check

### Using type-coverage Package

```bash
# Install if needed
npm install -D type-coverage

# Run coverage check
npx type-coverage --detail --at-least 90

# Check specific directory
npx type-coverage src/components/ --detail
```

### Manual Detection

```bash
# Count explicit 'any' types
grep -rn ": any" src/ --include="*.ts" --include="*.tsx" | wc -l

# Count implicit any (via TypeScript)
npx tsc --noEmit --strict 2>&1 | grep -c "implicitly has an 'any' type"

# Find type assertions
grep -rn "as any\|<any>" src/ --include="*.ts" --include="*.tsx" | wc -l
```

## Coverage Categories

### 1. Explicit `any` Types

**Detection:**
```bash
grep -rn ": any\b" src/ --include="*.ts" --include="*.tsx" | grep -v "\.test\."
```

**Priority:** High - These are intentional escapes from type safety

**Common Fixes:**
| Pattern | Fix |
|---------|-----|
| `data: any` | Define proper interface |
| `error: any` | Use `Error` or `unknown` |
| `props: any` | Create Props interface |
| `event: any` | Use React event types |

### 2. Type Assertions to `any`

**Detection:**
```bash
grep -rn "as any" src/ --include="*.ts" --include="*.tsx"
grep -rn "<any>" src/ --include="*.ts" --include="*.tsx"
```

**Priority:** High - Often hides type mismatches

**Common Fixes:**
- Use proper type assertion: `as SpecificType`
- Fix underlying type mismatch
- Use type guards instead

### 3. Implicit `any` Parameters

**Detection:**
```bash
npx tsc --noImplicitAny 2>&1 | grep "implicitly has an 'any' type"
```

**Priority:** Medium - Missing type annotations

**Common Fixes:**
- Add explicit parameter types
- Enable `noImplicitAny` in tsconfig.json

### 4. Missing Return Types

**Detection:**
```bash
# Functions without return type annotation
grep -rn "function.*(" src/ --include="*.ts" | grep -v "): "
grep -rn "=.*=>" src/ --include="*.ts" | grep -v "): "
```

**Priority:** Low-Medium - TypeScript can infer, but explicit is better

### 5. Untyped Dependencies

**Detection:**
```bash
# Check for missing @types packages
npm ls | grep -E "@types" | wc -l
npm install --dry-run @types/... 2>&1 | grep "available"
```

## Coverage Report Template

```markdown
# TypeScript Type Coverage Report

**Date**: [timestamp]
**Project**: [project-name]

## Summary

| Metric | Count | Target |
|--------|-------|--------|
| Type Coverage | 85.3% | 90% |
| Explicit `any` | 42 | <20 |
| Type Assertions | 18 | <10 |
| Implicit `any` | 12 | 0 |

## Hotspots (Most Untyped)

| File | Untyped Lines | % Typed |
|------|---------------|---------|
| src/api/client.ts | 28 | 62% |
| src/utils/legacy.ts | 45 | 48% |

## `any` Usage by Category

| Category | Count | Location Examples |
|----------|-------|-------------------|
| API responses | 15 | src/api/*.ts |
| Event handlers | 8 | src/components/*.tsx |
| External libs | 12 | src/lib/*.ts |
| Legacy code | 7 | src/utils/legacy.ts |

## Recommended Actions

1. **High Priority**: Fix API response types (15 occurrences)
   - Create interfaces for all API endpoints
   - Use Zod for runtime validation

2. **Medium Priority**: Fix event handler types (8 occurrences)
   - Use React.ChangeEvent, React.MouseEvent, etc.

3. **Low Priority**: Add @types for untyped deps
```

## Improvement Workflow

### Phase 1: Enable Strict Options

```json
// tsconfig.json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true
  }
}
```

### Phase 2: Fix High-Priority `any`

Focus on:
1. API response types
2. Function parameters
3. Event handlers

### Phase 3: Remove Type Assertions

Replace `as any` with proper types or type guards:

```typescript
// BAD
const data = response.data as any;

// GOOD
interface ApiResponse {
  data: UserData;
}
const data = response.data as ApiResponse;

// BETTER - with validation
const data = UserDataSchema.parse(response.data);
```

### Phase 4: Track Progress

```bash
# Save baseline
npx type-coverage --json > coverage-baseline.json

# After improvements
npx type-coverage --json > coverage-current.json

# Compare
diff coverage-baseline.json coverage-current.json
```

## Quick Commands

```bash
# Quick any count
echo "Explicit any: $(grep -rn ': any' src/ --include='*.ts' --include='*.tsx' | wc -l)"
echo "Type assertions: $(grep -rn 'as any' src/ --include='*.ts' --include='*.tsx' | wc -l)"

# Show all any locations
grep -rn ": any\|as any" src/ --include="*.ts" --include="*.tsx" | head -20

# Type coverage percentage (if type-coverage installed)
npx type-coverage 2>/dev/null || echo "Install: npm i -D type-coverage"
```

## Integration

Works with:
- `/validate-build` - Type errors block build
- `build-validator-agent` - Reports type issues
- CI/CD - Add coverage gate to pipeline
