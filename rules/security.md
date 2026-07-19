# Security Rules

> Universal security practices. Applies to all projects and tech stacks.

## Input Validation

- **Validate ALL user inputs** — Never trust client data
- Use parameterized queries (never string concatenation for SQL/queries)
- Validate file uploads: check size limits, MIME types, file extensions
- Sanitize outputs to prevent XSS
- Validate URLs, emails, and IDs with proper regex/libraries

## Secrets Management

- **NEVER commit secrets** — No API keys, passwords, tokens, or credentials in code
- Use `.env` files (always in `.gitignore`)
- Provide `.env.example` with placeholder values
- Use environment variables for all configuration
- Block committing: `.env`, `credentials.json`, SSH keys, `*.pem`, `*.key`

### Secrets Pull Verification

- Some providers mark variables as **"Sensitive"**, which then **silently skip** `<tool> env pull` — your local `.env` looks complete but is missing the sensitive subset.
- After every env-pull, **diff the local key set against the remote listing** (`<tool> env ls`) and warn on any divergence.
- Never assume a pulled `.env` is complete; verify key parity before relying on it.

> Distilled from multi-project experience (merge-intake 2026-05-28): provider-managed "Sensitive" vars silently absent from local pulls.

## Authentication & Authorization

- Use established auth libraries (Supabase Auth, Convex Auth, NextAuth, Passport.js)
- Implement proper session management with auto-refresh
- Verify authentication in EVERY API endpoint / server function
- Never trust client-side auth state for security decisions
- Use secure cookie attributes: `httpOnly`, `secure`, `sameSite`

## Data Protection

- Implement proper data isolation (RLS policies, function-level auth, tenant checks)
- Never expose internal IDs or stack traces to users
- Use HTTPS everywhere
- Implement CORS with explicit allowed origins
- Rate limit public endpoints

## Code-Level Security

- Never use dynamic code execution or string-to-code evaluation
- No path traversal — Validate and sanitize all file paths
- Use temporary files securely with proper cleanup
- No information leakage in error messages (log details server-side, show generic messages to users)
- Implement proper error handling that doesn't expose internals

## Platform-Specific Notes

These are reminders — detailed patterns live in project-level rules:
- **Supabase:** RLS policies on EVERY table, Edge Functions for sensitive ops
- **Convex:** `ctx.auth.getUserIdentity()` in every query/mutation, validators on all inputs
- **FastAPI:** Pydantic models for validation, dependency injection for auth
- **Next.js:** API routes excluded from middleware, server-side validation
