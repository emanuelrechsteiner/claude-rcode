---
name: import-fixer
description: Fix broken imports after file moves or renames. Scans for import errors, identifies broken paths, and updates all affected files. Use after moving files, renaming modules, or when seeing "Cannot find module" errors. Triggers on "fix imports", "broken imports", "cannot find module", "update imports", "import error", "imports reparieren", "kaputte imports", "modul nicht gefunden", "imports fixen", "importpfade aktualisieren", "import fehler".
user-invocable: false
allowed-tools: Read, Glob, Grep, Edit, Bash(npm *, npx tsc *)
---

# Import Fixer Skill - Resolve Broken Import Paths

## Purpose

After moving, renaming, or restructuring files, this skill finds all broken imports and fixes them automatically.

## When to Use

- After moving files to new directories
- After renaming files or modules
- When seeing "Cannot find module" TypeScript errors
- After refactoring folder structure
- When import paths are inconsistent

## Diagnostic Steps

### Step 1: Identify Broken Imports

```bash
# Run TypeScript to find all import errors
npx tsc --noEmit 2>&1 | grep -E "Cannot find module|Module not found"

# Find imports that reference non-existent files
for import_path in $(grep -roh "from ['\"]\..*['\"]" src/ | sed "s/from ['\"]//;s/['\"]//"); do
  # Check if path exists (approximate)
  if [[ ! -f "src/${import_path}.ts" && ! -f "src/${import_path}.tsx" && ! -f "src/${import_path}/index.ts" ]]; then
    echo "Potentially broken: $import_path"
  fi
done
```

### Step 2: Find Old vs New Paths

```bash
# Find recently moved/renamed files
git status --short | grep "^R"

# Or find files matching the old module name
find src/ -name "*.ts" -o -name "*.tsx" | xargs grep -l "oldModuleName"
```

### Step 3: Map Import Updates

For each broken import:
1. Identify the old path
2. Find where the file was moved to
3. Calculate the new relative path
4. Update all files that import it

## Fix Protocol

### For a Moved File

```bash
# Example: file moved from src/utils/helper.ts to src/lib/utils/helper.ts

# Find all files importing the old path
grep -rn "from ['\"].*utils/helper" src/ --include="*.ts" --include="*.tsx"

# Update each occurrence
# Old: import { func } from '../utils/helper'
# New: import { func } from '../lib/utils/helper'
```

### For a Renamed File

```bash
# Example: file renamed from helper.ts to helpers.ts

# Find all imports of old name
grep -rn "from ['\"].*helper['\"]" src/ --include="*.ts" --include="*.tsx"

# Update to new name
grep -rn "from ['\"].*helpers['\"]" src/ --include="*.ts" --include="*.tsx"
```

### For Index Re-exports

```bash
# Check if module is re-exported from index
grep -rn "export.*from.*moduleName" src/**/index.ts
```

## Common Patterns

### Pattern 1: Relative Path Depth Changed

```typescript
// File moved deeper into directory structure
// Old (from src/components/Button.tsx)
import { util } from '../utils/helper'

// New (file moved to src/components/ui/Button.tsx)
import { util } from '../../utils/helper'
```

### Pattern 2: Directory Renamed

```typescript
// Old directory: src/utils/
// New directory: src/lib/

// Update all imports in the codebase:
// from '../utils/' -> from '../lib/'
```

### Pattern 3: Barrel Export Added

```typescript
// If you added an index.ts barrel export:
// Old: import { Button } from './components/Button'
// New: import { Button } from './components'
```

## Automated Fix Commands

### Find and Replace Import Paths

```bash
# Using sed to update paths (macOS)
find src/ -name "*.ts" -o -name "*.tsx" | xargs sed -i '' 's|from '\''\.\.\/old-path|from '\''\.\.\/new-path|g'

# Verify changes
git diff --name-only
```

### TypeScript Path Aliases

If using path aliases in tsconfig.json:

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"],
      "@components/*": ["src/components/*"]
    }
  }
}
```

Consider updating to use aliases for moved files to avoid relative path issues.

## Verification

After fixing imports:

```bash
# 1. Check TypeScript compiles
npx tsc --noEmit

# 2. Check build succeeds
npm run build

# 3. Verify no remaining broken imports
grep -rn "from.*oldPath" src/
```

## Report Template

```markdown
# Import Fix Report

## Files Moved/Renamed
| Old Path | New Path |
|----------|----------|
| src/utils/helper.ts | src/lib/utils/helper.ts |

## Files Updated
| File | Changes |
|------|---------|
| src/components/Button.tsx | Updated 2 imports |
| src/pages/Home.tsx | Updated 1 import |

## Verification
- [ ] TypeScript compiles: ✅
- [ ] Build succeeds: ✅
- [ ] No broken imports remain: ✅
```

## Quick Fix Commands

```bash
# Quick import check
npx tsc --noEmit 2>&1 | grep "Cannot find module" | head -10

# Show all relative imports in a file
grep -n "from ['\"]\..*['\"]" src/file.tsx

# Count broken imports
npx tsc --noEmit 2>&1 | grep -c "Cannot find module"
```

## Integration

Use after:
- File restructuring
- Module refactoring
- Before running `/validate-build`
- When TypeScript reports import errors
