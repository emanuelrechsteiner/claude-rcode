---
name: nextjs-debug
description: Framework diagnostics for Next.js applications. Troubleshoots API route 404/405 errors, middleware redirect loops, SSR/hydration issues, and server/client component problems. Use when facing Next.js-specific issues. Triggers on "nextjs debug", "404 error", "405 error", "middleware issue", "hydration error", "server component", "client component", "API route not working".
context: fork
model: haiku
allowed-tools: Read, Glob, Grep, Bash(npm *), Bash(npx next *)
---

# Next.js Debug Skill - Framework Diagnostics

## Purpose

Quickly diagnose and resolve common Next.js issues by running targeted diagnostic checks and providing specific solutions.

## Issue Categories

### 1. API Route Issues (404/405)

**Symptoms:**
- POST request returns 404
- API route returns 405 Method Not Allowed
- API works in development but not production

**Diagnostic Steps:**

```bash
# 1. Verify route file exists
ls -la app/api/[endpoint]/route.ts

# 2. Check exported HTTP methods
grep -E "export (async )?function (GET|POST|PUT|DELETE|PATCH)" app/api/*/route.ts

# 3. Check middleware configuration
grep -A 10 "matcher" middleware.ts

# 4. Look for API exclusion in middleware
grep "api" middleware.ts
```

**Common Fixes:**

| Problem | Fix |
|---------|-----|
| Route file missing | Create `app/api/[endpoint]/route.ts` |
| Wrong HTTP method | Export correct function: `export async function POST()` |
| Middleware intercepting | Add `/api/*` exclusion to matcher |
| Path mismatch | Verify client fetch URL matches route path |

**Middleware Fix Template:**
```typescript
export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico).*)']
};
```

### 2. Middleware Redirect Loops

**Symptoms:**
- Browser shows "too many redirects"
- Page never loads
- Request keeps bouncing between paths

**Diagnostic Steps:**

```bash
# 1. Check middleware redirect conditions
grep -A 20 "redirect\|NextResponse.redirect" middleware.ts

# 2. Check authentication logic
grep -B 5 -A 10 "if.*authenticated\|if.*session\|if.*cookie" middleware.ts

# 3. Check matcher scope
grep "matcher" middleware.ts
```

**Common Fixes:**

| Problem | Fix |
|---------|-----|
| Redirect target matches middleware | Exclude target from matcher |
| Missing auth check on redirect target | Add condition to skip redirect if already on target |
| Cookie not persisting | Set cookie before redirect |

### 3. Hydration Mismatches

**Symptoms:**
- Console warning: "Hydration failed because the initial UI does not match"
- Content flickers on page load
- Interactive elements don't work initially

**Diagnostic Steps:**

```bash
# 1. Find browser-only APIs
grep -rn "window\.\|document\.\|localStorage\|sessionStorage" src/ --include="*.tsx"

# 2. Find date/time rendering
grep -rn "new Date\|toLocaleString\|Date\.now" src/ --include="*.tsx"

# 3. Find random values
grep -rn "Math\.random\|uuid\|nanoid" src/ --include="*.tsx"

# 4. Find conditional rendering that could differ
grep -rn "typeof window\|process\.browser" src/ --include="*.tsx"
```

**Common Fixes:**

| Problem | Fix |
|---------|-----|
| Browser API in render | Wrap in `useEffect` or use `dynamic({ ssr: false })` |
| Date/time differs | Use consistent formatting or `suppressHydrationWarning` |
| Random values | Generate in `useEffect` or pass from server |

**Pattern:**
```tsx
// BAD - runs on server with different value
const time = new Date().toLocaleString();

// GOOD - only runs on client
const [time, setTime] = useState<string>();
useEffect(() => {
  setTime(new Date().toLocaleString());
}, []);
```

### 4. Server/Client Component Issues

**Symptoms:**
- Error: "useState is not a function"
- Error: "Hooks can only be called inside a function component"
- Error: "You're importing a component that needs X"

**Diagnostic Steps:**

```bash
# 1. Find files using React hooks
grep -rn "useState\|useEffect\|useRef\|useContext\|useCallback\|useMemo" src/ --include="*.tsx" -l

# 2. Check which have 'use client'
for f in $(grep -rn "useState\|useEffect" src/ --include="*.tsx" -l); do
  if ! grep -q "use client" "$f"; then
    echo "Missing 'use client': $f"
  fi
done

# 3. Find event handlers (need client component)
grep -rn "onClick\|onChange\|onSubmit" src/ --include="*.tsx" -l
```

**Common Fixes:**

| Problem | Fix |
|---------|-----|
| Hook in server component | Add `'use client'` directive at top of file |
| Event handler in server component | Add `'use client'` or extract to client component |
| Context in server component | Create client wrapper component |

### 5. Build/Bundle Issues

**Symptoms:**
- Build fails with module errors
- Unexpected bundle size
- "Module not found" errors

**Diagnostic Steps:**

```bash
# 1. Check for circular dependencies
npx madge --circular src/

# 2. Analyze bundle size
npm run build
npx @next/bundle-analyzer

# 3. Check for server-only imports in client
grep -rn "from 'fs'\|from 'path'\|from 'crypto'" src/ --include="*.tsx"
```

## Quick Diagnostic Command

Run this for a quick health check:

```bash
echo "=== Next.js Diagnostic ===" && \
echo "Middleware:" && ls -la middleware.ts 2>/dev/null || echo "No middleware" && \
echo "API Routes:" && find app/api -name "route.ts" 2>/dev/null | head -10 && \
echo "Client Components:" && grep -rl "use client" src/ 2>/dev/null | wc -l && \
echo "Server Hooks Usage:" && grep -rn "useState\|useEffect" src/ --include="*.tsx" 2>/dev/null | grep -v "use client" | head -5
```

## Debugging Workflow

1. **Identify the error type** (404, hydration, hooks, etc.)
2. **Run targeted diagnostics** for that category
3. **Check the common fixes table**
4. **Apply the fix**
5. **Verify with build:** `npm run build`

## Integration

This skill works with:
- `framework-specialist-agent` for complex issues
- `/validate-build` for verification after fixes
- `nextjs-app-router-patterns.md` rule for prevention

## Quick Reference

### File Checklist for API Routes

- [ ] File is at `app/api/[endpoint]/route.ts`
- [ ] HTTP method function is exported
- [ ] Method name is uppercase (GET, POST, etc.)
- [ ] Middleware excludes `/api/*`
- [ ] No `page.tsx` in same folder

### File Checklist for Client Components

- [ ] `'use client'` at very top of file
- [ ] No server-only imports
- [ ] All hooks are inside component body
- [ ] Event handlers are in client components
