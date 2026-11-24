---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,py,swift,go,rs,java,kt,kts,rb,php,vue,svelte,astro,sh,bash,zsh,c,h,cc,cpp,hpp,cs,m,mm,dart,gd,lua,ex,exs,scala,sql,prisma,html,css,scss}"
  - "**/.env*"
  - "**/*.{yml,yaml,toml}"
  - "**/supabase/**"
  - "**/convex/**"
  - "**/Dockerfile*"
  - "**/*.tf"
  - "**/vercel.json"
  - "**/firebase.json"
---

# Security Rules

> Universal security practices. Applies to all projects and tech stacks. Path-scoped: loads when a source, config or env file is read or edited.

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

## Access for agents and LLM-backed apps

An agent or an LLM-backed app gets the access its current task needs, not more.

- Database: queries run through a read-only role; writes need an explicit, user-authenticated path.
- API keys: one scoped key per tool, no master keys, no key shared between agents; rotate scoped keys.
- Filesystem: sub-agents work inside the workspace, not in the home directory or the filesystem root.
- Network: deny by default; allow domains per task. This is about what an app or a helper may reach; your own research fetching follows the web research paragraph in `agency-bands`.
- A session that skips permission checks (`--dangerously-skip-permissions`) belongs in a container or sandbox with a narrow allowlist and a log of every shell command it runs; `hooks/sandbox-guard.sh` warns at session start when it runs elsewhere.
- Do not rely on an agent's statement that its output holds no secrets; check with a search. A fetched page can make an agent send local files through its own tools.

## Platform-Specific Notes

Reminders — detailed patterns live in project-level rules:
- **Supabase:** RLS policies on EVERY table, Edge Functions for sensitive ops
- **Convex:** `ctx.auth.getUserIdentity()` in every query/mutation, validators on all inputs
- **FastAPI:** Pydantic models for validation, dependency injection for auth
- **Next.js:** API routes excluded from middleware, server-side validation
