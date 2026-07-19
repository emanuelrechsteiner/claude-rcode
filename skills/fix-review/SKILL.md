---
name: fix-review
description: Post-fix completeness checker. After making a code fix, this skill identifies the fix scope, searches for all related occurrences, verifies call sites are updated, and checks for cascading issues. Use after fixing bugs to ensure nothing was missed. Triggers on "review fix", "check fix", "fix complete", "verify fix", "did I miss anything", "cascading changes", "fix überprüfen", "fix checken", "nichts vergessen", "noch mehr stellen", "habe ich was übersehen", "gibt es noch weitere", "alle stellen gefunden", "komplette abdeckung", "sind wir vollständig".
user-invocable: false
allowed-tools: Read, Glob, Grep, Bash(git diff *), Bash(git log *)
---

# Fix Review Skill - Post-Fix Completeness Verification

## Purpose

After making a code fix, systematically verify that:
1. All occurrences of the changed code are addressed
2. All call sites are updated
3. No cascading issues were introduced
4. The fix actually resolves the original issue

## Fix Review Protocol

### Step 1: Identify What Changed

```bash
# See recent changes in the working directory
git diff HEAD~1 --name-only

# See specific changes
git diff HEAD~1 --unified=3

# If not committed, see uncommitted changes
git diff --name-only
git diff --unified=3
```

**Extract from the diff:**
- Function/method names that changed
- Type/interface names that changed
- Variable names that changed
- Import paths that changed
- API endpoints that changed

### Step 2: Search for Related Occurrences

For each changed identifier, search the entire codebase:

```bash
# Search for function/method usage
grep -rn "functionName" src/ --include="*.ts" --include="*.tsx"

# Search for type/interface usage
grep -rn "TypeName" src/ --include="*.ts" --include="*.tsx"

# Search for import statements
grep -rn "from.*modulePath" src/ --include="*.ts" --include="*.tsx"

# Case-insensitive search for variations
grep -rni "searchterm" src/
```

### Step 3: Verify Call Sites

For function signature changes, verify all callers:

```bash
# Find all files that import the changed module
grep -l "import.*from.*'modulePath'" src/**/*.{ts,tsx}

# Find all usages of a function
grep -rn "functionName(" src/

# Find all implementations of an interface
grep -rn "implements InterfaceName" src/
grep -rn ": InterfaceName" src/
```

### Step 4: Check for Cascading Issues

**Type Changes:**
```bash
# If you changed a type, find all usages
grep -rn "TypeName" src/ | grep -v "\.test\." | grep -v "__tests__"
```

**Interface Changes:**
```bash
# Find implementations
grep -rn "implements.*InterfaceName" src/

# Find type annotations using the interface
grep -rn ": InterfaceName" src/
```

**Export Changes:**
```bash
# Find all imports of the changed export
grep -rn "import.*{.*exportName.*}" src/
grep -rn "import exportName from" src/
```

## Fix Review Checklist

### For Function/Method Changes

- [ ] All call sites found and verified
- [ ] Parameter order matches at all call sites
- [ ] Return type handling is correct at all call sites
- [ ] Default parameters are compatible
- [ ] Overloads (if any) are updated

### For Type/Interface Changes

- [ ] All implementations updated
- [ ] All type annotations using it are compatible
- [ ] Generic constraints (if any) are satisfied
- [ ] Optional vs required fields are consistent

### For Import/Export Changes

- [ ] All import statements updated
- [ ] Re-exports (index.ts) updated
- [ ] Dynamic imports updated
- [ ] Test file imports updated

### For API/Endpoint Changes

- [ ] All frontend callers updated
- [ ] API documentation updated
- [ ] Test fixtures updated
- [ ] Mock data updated

## Common Incomplete Fix Patterns

### Pattern 1: Renamed Function, Missed Call Sites

**Symptom:** Runtime error "X is not a function"

**Detection:**
```bash
# Find old name still in use
grep -rn "oldFunctionName" src/
```

### Pattern 2: Changed Interface, Missed Implementation

**Symptom:** TypeScript error "Property X is missing"

**Detection:**
```bash
# Find implementations
grep -rn "implements InterfaceName" src/
grep -rn ": InterfaceName =" src/
```

### Pattern 3: Changed Export, Missed Import

**Symptom:** Build error "X is not exported from Y"

**Detection:**
```bash
# Find imports of the changed module
grep -rn "from.*'changed/module'" src/
```

### Pattern 4: Changed Type, Missed Dependent Types

**Symptom:** TypeScript cascading errors

**Detection:**
```bash
# Find types that extend or use the changed type
grep -rn "extends.*ChangedType" src/
grep -rn "<.*ChangedType.*>" src/
```

## Review Report Template

After completing the review, generate this report:

```markdown
# Fix Review Report

## Fix Summary
- **Files Changed**: [list]
- **Primary Change**: [description]
- **Related Identifiers**: [list of functions, types, etc.]

## Search Results

### Call Sites Found
| Location | Status | Notes |
|----------|--------|-------|
| file.ts:42 | ✅ Updated | |
| other.ts:15 | ✅ Updated | |
| test.ts:88 | ⚠️ Needs Review | Test mock may need update |

### Cascading Changes Needed
| Item | Action Required |
|------|-----------------|
| [item] | [action] |

## Verification Status
- [ ] All call sites verified
- [ ] TypeScript compiles
- [ ] Tests pass
- [ ] Build succeeds

## Remaining Issues
[List any issues found that need attention]
```

## Quick Reference Commands

```bash
# Find all occurrences of a symbol
grep -rn "symbolName" src/ --include="*.ts" --include="*.tsx"

# Find files importing a module
grep -l "from.*'module'" src/**/*.{ts,tsx}

# Find type usages
grep -rn ": TypeName" src/
grep -rn "as TypeName" src/
grep -rn "<TypeName>" src/

# Find function calls
grep -rn "functionName(" src/

# Exclude test files from search
grep -rn "pattern" src/ | grep -v "\.test\." | grep -v "__tests__"

# Find recent changes to a specific file
git log -p --follow -- path/to/file.ts
```

## Integration with Other Skills

After running fix-review, consider:
1. Run `/validate-build` to verify TypeScript and build pass
2. Run tests to verify behavior
3. If fix involved patterns, consider `/pattern-document` to capture learning

## Additional Resources

### Reference Files
- **`references/search-patterns.md`** - Comprehensive grep/search patterns for finding functions, types, imports, classes, React components, and more
