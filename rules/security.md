# Security Rules

> Universal security practices. Applies to all projects and tech stacks.

## Input Validation

- **Validate ALL user inputs** — never trust client data; validate URLs, emails, and IDs with proper regex/libraries
- Use parameterized queries (never string concatenation for SQL/queries)
- Validate file uploads: check size limits, MIME types, file extensions
- Sanitize outputs to prevent XSS

## Secrets Management

- **NEVER commit secrets** — no API keys, passwords, tokens, or credentials in code; block committing `.env`, `credentials.json`, SSH keys, `*.pem`, `*.key`
- Use environment variables for all configuration: `.env` files (always in `.gitignore`), plus a `.env.example` with placeholder values

### Secrets Pull Verification

Some providers mark variables as **"Sensitive"**, which then **silently skip** `<tool> env pull` — your local `.env` looks complete but lacks that subset. After every env-pull, **diff the local key set against the remote listing** (`<tool> env ls`) and warn on any divergence; never assume a pulled `.env` is complete before key parity is verified.

## Authentication & Authorization

- Use established auth libraries (Supabase Auth, Convex Auth, NextAuth, Passport.js) and proper session management with auto-refresh
- Verify authentication in EVERY API endpoint / server function; never trust client-side auth state for security decisions
- Use secure cookie attributes: `httpOnly`, `secure`, `sameSite`

## Data Protection

- Implement proper data isolation (RLS policies, function-level auth, tenant checks)
- Never expose internal IDs or stack traces to users
- Use HTTPS everywhere; implement CORS with explicit allowed origins; rate limit public endpoints

## Code-Level Security

- Never use dynamic code execution or string-to-code evaluation
- No path traversal — validate and sanitize all file paths
- Use temporary files securely with proper cleanup
- No information leakage in error messages (log details server-side, show generic messages to users); implement proper error handling that doesn't expose internals

## Platform-Specific Notes

Reminders — detailed patterns live in project-level rules:
- **Supabase:** RLS policies on EVERY table, Edge Functions for sensitive ops
- **Convex:** `ctx.auth.getUserIdentity()` in every query/mutation, validators on all inputs
- **FastAPI:** Pydantic models for validation, dependency injection for auth
- **Next.js:** API routes excluded from middleware, server-side validation
