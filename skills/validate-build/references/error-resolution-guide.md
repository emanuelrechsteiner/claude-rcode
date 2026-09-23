# Error Resolution Guide

Detailed reference for resolving common validation errors.

## TypeScript Error Codes

### TS2307: Cannot find module

**Symptom**: `Cannot find module 'X' or its corresponding type declarations`

**Causes**:
1. Package not installed
2. Missing `@types/` package
3. Wrong import path
4. Missing `tsconfig.json` paths configuration

**Solutions**:
```bash
# Install missing package
npm install X

# Install type definitions
npm install -D @types/X

# Check if package exists
npm show X

# Verify tsconfig paths
cat tsconfig.json | grep -A 10 "paths"
```

### TS2339: Property does not exist

**Symptom**: `Property 'X' does not exist on type 'Y'`

**Causes**:
1. Accessing undefined property
2. Type is too narrow
3. Missing interface property
4. Object shape doesn't match type

**Solutions**:
```typescript
// Add to interface
interface Y {
  X: string; // Add missing property
}

// Type assertion (use sparingly)
(obj as any).X

// Optional chaining
obj?.X

// Type guard
if ('X' in obj) {
  obj.X // TypeScript knows X exists
}
```

### TS2345: Argument type mismatch

**Symptom**: `Argument of type 'X' is not assignable to parameter of type 'Y'`

**Solutions**:
```typescript
// Explicit conversion
functionCall(value as Y)

// Type narrowing
if (isY(value)) {
  functionCall(value)
}

// Fix the source type
const value: Y = correctValue
```

### TS2531: Object possibly null

**Symptom**: `Object is possibly 'null' or 'undefined'`

**Solutions**:
```typescript
// Null check
if (obj !== null) {
  obj.property
}

// Optional chaining
obj?.property

// Non-null assertion (use sparingly)
obj!.property

// Default value
obj ?? defaultValue
```

### TS7006: Parameter has implicit any

**Symptom**: `Parameter 'X' implicitly has an 'any' type`

**Solutions**:
```typescript
// Add explicit type
function fn(X: string) { }

// Use type inference
const fn = (X: Parameters<typeof otherFn>[0]) => { }

// Generic approach
function fn<T>(X: T) { }
```

## ESLint Error Resolution

### react-hooks/exhaustive-deps

**Problem**: Missing dependencies in useEffect/useCallback/useMemo

**Solution**:
```typescript
// Add missing dependency
useEffect(() => {
  doSomething(value)
}, [value]) // Add 'value' to deps

// Or suppress with reason
useEffect(() => {
  doSomething(value)
  // eslint-disable-next-line react-hooks/exhaustive-deps
}, []) // Intentionally empty - runs once
```

### no-unused-vars

**Problem**: Variable declared but never used

**Solution**:
```typescript
// Remove if truly unused
// delete const unused = 1

// Prefix with underscore for intentionally unused
const _intentionallyUnused = getConfig()

// For function params
function handler(_event: Event) { }
```

### @typescript-eslint/no-explicit-any

**Problem**: Using `any` type

**Solution**:
```typescript
// Use unknown for truly unknown types
const data: unknown = await fetch()

// Use specific type
const data: User = await fetchUser()

// Use generic
function process<T>(data: T): T { return data }
```

## Build Error Resolution

### Module not found

**Problem**: Webpack/build can't resolve import

**Solutions**:
```bash
# Check if module exists
ls node_modules/module-name

# Reinstall dependencies
rm -rf node_modules && npm install

# Clear build cache
npm run clean
rm -rf .next  # for Next.js

# Check import path is correct
# Wrong: import { X } from './components/Button'
# Right: import { X } from './components/Button/Button'
```

### Server/Client Component Mismatch (Next.js)

**Problem**: Using client features in server component

**Solution**:
```typescript
// Add 'use client' directive at top of file
'use client'

import { useState } from 'react'

// Now hooks work
export function Component() {
  const [state, setState] = useState(false)
}
```

### Environment Variables Missing

**Problem**: `process.env.X is undefined`

**Solutions**:
```bash
# Check .env file exists
cat .env.local

# For Next.js client-side, prefix with NEXT_PUBLIC_
# .env.local
NEXT_PUBLIC_API_URL=https://api.example.com

# Restart dev server after .env changes
npm run dev
```
