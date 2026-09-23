# Agents-as-Users Rule

> Agents must be authorized like users, not given global credentials. Derived from Casco YC red-team finding (7/16 agents hacked in 30 min) + OWASP MCP Top 10 + Brian John "Hacking Subagents Into Codex" (KB cluster 09, 2026-05-26). Always loaded.

## The Rule

**An agent's authorization scope must be defined per-task, not per-session or globally.** No agent ever runs with credentials it doesn't need for the immediate task.

## The Threat Model

Casco (YC W26) red-teamed 16 deployed AI agents in 30 minutes. **7 were hacked.** Common root cause: agents had broader credentials than the immediate task required.

| Attack vector | Mitigation |
|---|---|
| Prompt-injection from web content | Sandbox network; allowlist domains |
| Stolen API key via tool output | Scope keys to specific endpoints |
| Database write via "read-only" agent | Use DB role with read-only privileges |
| Lateral movement via shared filesystem | Containerized sandbox per agent run |
| Credential exfiltration via summary | Scrub secrets from agent outputs |

## How to Apply

### 1. Database access
- LLM-backed app calls DB via **read-only role** for queries
- Writes require an explicit user-authenticated path
- Pattern: Hasura DB-read-only-role talk (cluster 09)

### 2. API keys
- Never give an agent a "master" API key
- Scope per-tool: search-tool gets only search-API-key; do not bundle OpenAI + Stripe + GitHub keys
- Rotate scoped keys aggressively

### 3. Filesystem access
- Subagents operating on a single project get **workspace-scoped** access
- No `~/` or `/` read for sub-agents
- Brian John ("Hacking Subagents Into Codex") shows the `sandbox:workspace-write` pattern

### 4. Network access
- Default deny. Allowlist domains per task.
- Web-fetch sub-agents: allowlist e.g. `*.docs.anthropic.com`, deny everything else
- Prevents prompt-injection-driven exfiltration

### 5. YOLO Mode (`--dangerously-skip-permissions`)
- **MUST require explicit scope-narrow allowlist** if used
- Default: only allowed in container/sandbox (enforced by Wave-4 SessionStart hook)
- Logs MUST capture every bash invocation when YOLO is on

## Meta's "Agents Rule of Two"

Per Brian John's BetterUp talk, classify each agent run by three dimensions:
1. Does it process **untrustworthy input**? (yes if web content, user data, external API)
2. Does it access **sensitive systems or private data**?
3. Does it **change state** or **communicate externally**?

If **two or more are yes**: requires human-in-the-loop checkpoint before destructive action. Pair with `agency-bands.md`.

## Enforcement

- Subagent definitions specify minimum tool allowlist (already done in `~/.claude/agents/*.md`)
- `~/.claude/hooks/security-audit.sh` blocks secret exposure on Edit/Write
- New SessionStart hook (Wave 4) blocks YOLO outside sandbox
- `agency-bands.md` gates irreversible operations even in autonomous mode

## Anti-Patterns

### ❌ "Just give it admin to be safe"
Reverse: more permissions = more attack surface.

### ❌ Sharing one API key across all agents in a project
One agent compromise = all keys leaked.

### ❌ Trusting agent-summarized data without source verification
Agent says "no secrets in output" — verify with `grep`.

### ❌ Treating local-host as a trusted boundary
Prompt-injection from a fetched webpage can exfiltrate from local files via the agent's filesystem tools. Trust boundary is per-task, not per-host.

## References

- Casco YC W26 red-team finding — 7/16 agents hacked in 30 min
- Brian John (BetterUp) — "Hacking Subagents Into Codex CLI" — Meta Rule-of-Two
- OWASP MCP Top 10 (cluster 09)
- Hasura DB-read-only-role pattern
- Cluster source: see author's knowledge base (private)
