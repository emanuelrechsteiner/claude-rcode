# Agents-as-Users Rule

> Agents must be authorized like users, not given global credentials. Always loaded.

## The Rule

**An agent's authorization scope must be defined per-task, not per-session or globally.** No agent ever runs with credentials it doesn't need for the immediate task — "just give it admin to be safe" only adds attack surface.

## The Threat Model

Common root cause: agents had broader credentials than the immediate task required.

| Attack vector | Mitigation |
|---|---|
| Prompt-injection from web content | Sandbox network; allowlist domains |
| Stolen API key via tool output | Scope keys to specific endpoints |
| Database write via "read-only" agent | Use DB role with read-only privileges |
| Lateral movement via shared filesystem | Containerized sandbox per agent run |
| Credential exfiltration via summary | Scrub secrets from agent outputs |

## How to Apply

1. **Database:** an LLM-backed app queries the DB via a **read-only role**; writes require an explicit user-authenticated path.
2. **API keys:** never give an agent a "master" key; scope per tool (the search tool gets only the search key; never bundle OpenAI + Stripe + GitHub keys or share one key across all agents — one compromise leaks all); rotate scoped keys aggressively.
3. **Filesystem:** sub-agents operating on a single project get **workspace-scoped** access; no `~/` or `/` read for sub-agents; follow the `sandbox:workspace-write` pattern for scoping sub-agent filesystem access.
4. **Network:** default deny; allowlist domains per task (a web-fetch sub-agent e.g. `*.docs.anthropic.com` only, deny everything else) — this prevents prompt-injection-driven exfiltration.
5. **YOLO mode (`--dangerously-skip-permissions`):** **MUST** require an explicit scope-narrow allowlist; by default allowed only in a container/sandbox (enforced by a SessionStart hook); logs **MUST** capture every bash invocation while it is on.

## Meta's "Agents Rule of Two"

Classify each agent run: (1) does it process **untrustworthy input** (web content, user data, external API)? (2) does it access **sensitive systems or private data**? (3) does it **change state** or **communicate externally**? If **two or more are yes**, a human-in-the-loop checkpoint is required before destructive action; pair with `agency-bands.md`.

## Enforcement

Minimum tool allowlists in the sub-agent definitions (`~/.claude/agents/*.md`); `~/.claude/hooks/security-audit.sh` blocks secret exposure on Edit/Write; a SessionStart hook blocks YOLO outside a sandbox; `agency-bands.md` gates irreversible operations even in autonomous mode.

## Anti-Patterns

- ❌ **Trusting agent-summarized data without source verification** — the agent says "no secrets in output": verify with `grep`.
- ❌ **Treating local-host as a trusted boundary** — prompt-injection from a fetched webpage can exfiltrate local files via the agent's filesystem tools; the trust boundary is per-task, not per-host.
