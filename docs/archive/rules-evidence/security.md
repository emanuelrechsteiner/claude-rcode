<!--
Status: ARCHIVED
Last Updated: 2026-09-29
Purpose: Evidence and passages moved verbatim out of rules/security.md on 2026-09-29 (IMP-234) — the rule itself stays there; this file carries the full-length "why" and the wording it had before the condensing round.
-->
# Evidence for `rules/security.md`

> Moved out 2026-09-29 (IMP-234). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Moved from the rule on 2026-09-29 (IMP-234)

> Condensing round IMP-234 (instruction files under 150k chars). The passages below were removed from, or merged into shorter bullets in, `rules/security.md`; each is carried over verbatim from the rule as it stood before that round, under the heading it had there. The normative content stays in the rule; what lives only here is the provenance line and the pre-merge bullet wording.

### Input Validation

- **Validate ALL user inputs** — Never trust client data
- Use parameterized queries (never string concatenation for SQL/queries)
- Validate file uploads: check size limits, MIME types, file extensions
- Sanitize outputs to prevent XSS
- Validate URLs, emails, and IDs with proper regex/libraries

### Secrets Management

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

### Authentication & Authorization

- Use established auth libraries (Supabase Auth, Convex Auth, NextAuth, Passport.js)
- Implement proper session management with auto-refresh
- Verify authentication in EVERY API endpoint / server function
- Never trust client-side auth state for security decisions
- Use secure cookie attributes: `httpOnly`, `secure`, `sameSite`

### Data Protection

- Use HTTPS everywhere
- Implement CORS with explicit allowed origins
- Rate limit public endpoints

### Code-Level Security

- No path traversal — Validate and sanitize all file paths
- No information leakage in error messages (log details server-side, show generic messages to users)
- Implement proper error handling that doesn't expose internals

### Platform-Specific Notes

These are reminders — detailed patterns live in project-level rules:
