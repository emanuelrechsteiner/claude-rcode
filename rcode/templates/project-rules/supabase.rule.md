# Supabase Patterns

> Project-level rule: Install in `.claude/rules/` for Supabase projects.

## Database Operations

- Use Supabase client for ALL database operations
- **RLS policies on EVERY table** — No exceptions
- Never bypass RLS with service role key in client code
- Use parameterized queries via Supabase client (never raw SQL in app code)

## Authentication

- Use Supabase Auth for all user management
- Supabase handles session management and auto-refresh
- Always verify auth state server-side before sensitive operations
- Use `supabase.auth.getUser()` (not `getSession()`) for security-critical checks

## Architecture

- Multi-tenant with RLS for data isolation
- Use Edge Functions for sensitive operations (API keys, external services)
- Never expose service role key to client
- Use Supabase Storage for file uploads (not local filesystem)

## Testing

- Test RLS policies explicitly (ensure users can't access other users' data)
- Test auth flows (signup, login, password reset, session refresh)
- Test multi-tenant isolation (user A cannot see user B's data)
- Mock Supabase client in unit tests

## Common Patterns

```typescript
// Auth check pattern
const { data: { user }, error } = await supabase.auth.getUser();
if (!user) throw new Error('Unauthorized');

// RLS-protected query
const { data, error } = await supabase
  .from('items')
  .select('*')
  .eq('user_id', user.id);

// File upload
const { data, error } = await supabase.storage
  .from('bucket')
  .upload(`${user.id}/${filename}`, file);
```
