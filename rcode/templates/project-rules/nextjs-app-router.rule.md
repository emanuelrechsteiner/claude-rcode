# Next.js App Router Patterns

> Project-level rule: Install in `.claude/rules/` for Next.js App Router projects.

## CRITICAL: API Routes and Middleware

When using middleware (i18n, auth), API routes MUST be excluded:

```typescript
// middleware.ts — CORRECT
export const config = {
  matcher: ['/((?!api|_next|static|.*\\..*).*)'  ]
};
```

```typescript
// BAD — Catches API routes
matcher: ['/(.*)', '/:path*']
```

**Always test POST/PUT/DELETE requests after adding any middleware.**

## Route Handler Template

```typescript
// app/api/[endpoint]/route.ts
import { NextRequest, NextResponse } from 'next/server';

export async function GET(request: NextRequest) {
  try {
    return NextResponse.json({ data: 'result' });
  } catch (error) {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}

// Dynamic routes: params is a Promise in App Router
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
}
```

## SSE (Server-Sent Events)

```typescript
return new Response(stream, {
  headers: {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache, no-transform',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no'  // If behind proxy
  }
});
```

## Component Standards

- Server Components by default
- `'use client'` only for hooks, event handlers, browser APIs
- Proper `loading.tsx` and `error.tsx` per route segment
- No conflicting route names (`page.tsx` vs `route.ts` in same folder)

## Pre-Deploy Checklist

- [ ] API routes excluded from middleware matcher
- [ ] Static files excluded from middleware
- [ ] POST requests tested after adding middleware
- [ ] All route handlers export correct HTTP methods
- [ ] Proper error handling with status codes
- [ ] SSE headers set correctly for streaming
