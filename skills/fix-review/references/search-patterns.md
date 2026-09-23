# Search Patterns Reference

Comprehensive grep/search patterns for code review.

## Function and Method Search

```bash
# Find function declaration
grep -rn "function functionName" src/
grep -rn "const functionName = " src/
grep -rn "functionName = async" src/

# Find function calls
grep -rn "functionName(" src/

# Find method definitions in class
grep -rn "methodName(" src/ --include="*.ts"

# Find arrow functions
grep -rn "const functionName = (" src/
grep -rn "const functionName = async (" src/
```

## Type and Interface Search

```bash
# Find type definition
grep -rn "type TypeName" src/
grep -rn "interface InterfaceName" src/

# Find type usage
grep -rn ": TypeName" src/
grep -rn "as TypeName" src/
grep -rn "<TypeName>" src/

# Find type extensions
grep -rn "extends TypeName" src/
grep -rn "& TypeName" src/

# Find implementations
grep -rn "implements InterfaceName" src/
```

## Import and Export Search

```bash
# Find all imports of a module
grep -rn "from.*'module-path'" src/
grep -rn "import.*from.*module" src/

# Find named imports
grep -rn "import { ExportName" src/

# Find default imports
grep -rn "import ExportName from" src/

# Find dynamic imports
grep -rn "import(" src/

# Find re-exports
grep -rn "export.*from" src/

# Find files importing from a specific module
grep -l "from.*'@/lib/auth'" src/**/*.{ts,tsx}
```

## Class Search

```bash
# Find class definition
grep -rn "class ClassName" src/

# Find class extensions
grep -rn "extends ClassName" src/

# Find constructor
grep -rn "constructor(" src/

# Find static methods
grep -rn "static methodName" src/
```

## React Component Search

```bash
# Find component definition
grep -rn "function ComponentName" src/
grep -rn "const ComponentName: React.FC" src/
grep -rn "const ComponentName = (" src/

# Find component usage
grep -rn "<ComponentName" src/

# Find hook usage
grep -rn "use[A-Z]" src/ --include="*.tsx"

# Find context usage
grep -rn "useContext(ContextName)" src/

# Find props interface
grep -rn "interface.*Props" src/
```

## API and Endpoint Search

```bash
# Find API route definitions (Next.js)
grep -rn "export.*GET\|POST\|PUT\|DELETE" app/api/

# Find fetch calls
grep -rn "fetch(" src/
grep -rn "axios\." src/

# Find API endpoint strings
grep -rn "'/api/" src/
grep -rn '"/api/' src/
```

## Database and ORM Search

```bash
# Find Prisma model usage
grep -rn "prisma\." src/

# Find database queries
grep -rn "findMany\|findUnique\|create\|update\|delete" src/

# Find SQL queries
grep -rn "SELECT\|INSERT\|UPDATE\|DELETE" src/
```

## Exclusion Patterns

```bash
# Exclude test files
grep -rn "pattern" src/ | grep -v "\.test\." | grep -v "__tests__"

# Exclude node_modules
grep -rn "pattern" --exclude-dir=node_modules .

# Exclude specific files
grep -rn "pattern" src/ --exclude="*.d.ts"

# Multiple exclusions
grep -rn "pattern" src/ \
  --exclude-dir=node_modules \
  --exclude-dir=.next \
  --exclude="*.test.ts" \
  --exclude="*.spec.ts"
```

## Context-Aware Search

```bash
# Show 3 lines before and after
grep -rn -B3 -A3 "pattern" src/

# Show only filenames
grep -l "pattern" src/**/*.ts

# Count occurrences per file
grep -c "pattern" src/**/*.ts

# Show line numbers
grep -n "pattern" file.ts
```

## Regular Expression Patterns

```bash
# Find function with specific parameter count
grep -rE "function \w+\(\w+, \w+, \w+\)" src/

# Find async functions
grep -rE "async (function|\w+ =)" src/

# Find React hooks
grep -rE "use[A-Z][a-zA-Z]+\(" src/

# Find TODO comments
grep -rE "TODO|FIXME|HACK|XXX" src/

# Find console statements
grep -rE "console\.(log|error|warn|debug)" src/
```
