# Convex Patterns

> Project-level rule: Install in `.claude/rules/` for Convex projects.

## Database Operations

- Use `query` and `mutation` for ALL database operations
- **Function-level auth in EVERY public function** — No exceptions
- Use validators on all function arguments
- TypeScript strict mode with Convex-generated types

## Authentication

- Use `@convex-dev/auth` for auth setup
- Check `ctx.auth.getUserIdentity()` at the START of every query/mutation
- Never trust client-side auth state for security decisions
- Use `useAuthState`/`useAuthActions` hooks on client

```typescript
// Auth check pattern — REQUIRED in every public function
export const getItems = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new Error("Unauthorized");
    // proceed...
  },
});
```

## Architecture

- Multi-tenant via function-level auth checks
- `internalMutation`/`internalQuery` for server-only operations
- `action` for external API calls (cannot directly access DB)
- Use `ctx.runQuery()`/`ctx.runMutation()` inside actions
- All queries are real-time by default (no polling needed)

## Code Generation

- Run `npx convex dev` to generate types
- Commit generated files to version control
- Use generated types for type safety

## Storage

- `ctx.storage.store()` for file uploads
- Use `storageId` references in documents
- Set up expiration via Convex cron jobs
- Client-side encrypt sensitive files before upload

## Testing

- Test functions as standard TypeScript
- Use `convex-test` utilities
- Mock identities for auth testing
- Verify auth prevents unauthorized access
- Test validators reject bad inputs
