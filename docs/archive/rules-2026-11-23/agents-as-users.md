# Agents-as-Users Rule

> Agents are authorized like users — per task, never globally. Always loaded.

## The Rule

**An agent's authorization scope must be defined per-task, not per-session or globally.** No agent ever runs with credentials it doesn't need for the immediate task — "just give it admin to be safe" only adds attack surface.

## How to Apply

1. **Database:** an LLM-backed app queries through a read-only role; writes need an explicit user-authenticated path.
2. **API keys:** no master keys; one scoped key per tool, never one key bundled or shared across agents; rotate scoped keys aggressively.
3. **Filesystem:** sub-agents get workspace-scoped access, never `~/` or `/`.
4. **Network:** default deny; allowlist domains per task.
5. **YOLO mode (`--dangerously-skip-permissions`)** MUST have an explicit, narrow allowlist and is by default allowed only in a container or sandbox; `hooks/sandbox-guard.sh` WARNS at SessionStart when YOLO runs outside a known sandbox — it does not block — and every bash invocation MUST be logged while YOLO is on.
6. **Secrets:** never commit `.env` files, keys, tokens or credentials, and scrub secrets from agent outputs; after any `<tool> env pull`, diff the local key set against the remote listing (`<tool> env ls`) — providers silently skip variables marked "Sensitive" (detail: `~/.claude/rules/security.md`, path-scoped).

**Rule of Two:** untrusted input, sensitive data/system, state change or external comms — two or more YES force a human checkpoint before any destructive action; defined once in `rules/agency-bands.md`.

## Enforcement

Minimum tool allowlists in `agents/*.md`; `hooks/security-audit.sh` blocks secret exposure on Edit/Write; `rules/agency-bands.md` gates irreversible ops. Never trust an agent's "no secrets in output" claim — verify with `grep`; the trust boundary is per task, not per host (a fetched page can exfiltrate local files through the agent's own tools).
