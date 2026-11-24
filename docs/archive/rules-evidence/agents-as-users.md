<!--
Status: ARCHIVED
Last Updated: 2026-11-10
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/agents-as-users.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/agents-as-users.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Intro blockquote

Derived from Casco YC red-team finding (7/16 agents hacked in 30 min) + OWASP MCP Top 10 + Brian John "Hacking Subagents Into Codex" (KB cluster 09, 2026-05-26).

## The Threat Model

Casco (YC W26) red-teamed 16 deployed AI agents in 30 minutes. **7 were hacked.**

## 1. Database access

- Pattern: Hasura DB-read-only-role talk (cluster 09)

## 3. Filesystem access

- Brian John ("Hacking Subagents Into Codex") shows the `sandbox:workspace-write` pattern

## Meta's "Agents Rule of Two"

Per Brian John's BetterUp talk,

## References

- Casco YC W26 red-team finding — 7/16 agents hacked in 30 min
- Brian John (BetterUp) — "Hacking Subagents Into Codex CLI" — Meta Rule-of-Two
- OWASP MCP Top 10 (cluster 09)
- Hasura DB-read-only-role pattern
- Cluster source: see author's knowledge base (private)

## Moved from the rule on 2026-09-29 (IMP-234)

> Condensing round IMP-234 (instruction files under 150k chars). The passages below were shortened, merged into a numbered list, or folded in `rules/agents-as-users.md`; each is carried over verbatim from the rule as it stood before that round, under the heading it had there. The normative content stays in the rule; what lives only here is the sub-heading layout, the "Wave-4" history label, and two anti-patterns folded into the rule's statements (admin rights; one key shared across agents).

### 1. Database access
- LLM-backed app calls DB via **read-only role** for queries
- Writes require an explicit user-authenticated path

### 2. API keys
- Never give an agent a "master" API key
- Scope per-tool: search-tool gets only search-API-key; do not bundle OpenAI + Stripe + GitHub keys
- Rotate scoped keys aggressively

### 3. Filesystem access
- Subagents operating on a single project get **workspace-scoped** access
- No `~/` or `/` read for sub-agents
- Follow the `sandbox:workspace-write` pattern for scoping sub-agent filesystem access

### 4. Network access
- Default deny. Allowlist domains per task.
- Web-fetch sub-agents: allowlist e.g. `*.docs.anthropic.com`, deny everything else
- Prevents prompt-injection-driven exfiltration

### 5. YOLO Mode (`--dangerously-skip-permissions`)
- **MUST require explicit scope-narrow allowlist** if used
- Default: only allowed in container/sandbox (enforced by Wave-4 SessionStart hook)
- Logs MUST capture every bash invocation when YOLO is on

### Meta's "Agents Rule of Two"

Classify each agent run by three dimensions:
1. Does it process **untrustworthy input**? (yes if web content, user data, external API)
2. Does it access **sensitive systems or private data**?
3. Does it **change state** or **communicate externally**?

If **two or more are yes**: requires human-in-the-loop checkpoint before destructive action. Pair with `agency-bands.md`.

### Enforcement

- Subagent definitions specify minimum tool allowlist (already done in `~/.claude/agents/*.md`)
- `~/.claude/hooks/security-audit.sh` blocks secret exposure on Edit/Write
- New SessionStart hook (Wave 4) blocks YOLO outside sandbox
- `agency-bands.md` gates irreversible operations even in autonomous mode

### Anti-Patterns

### ❌ "Just give it admin to be safe"
Reverse: more permissions = more attack surface.

### ❌ Sharing one API key across all agents in a project
One agent compromise = all keys leaked.

### ❌ Trusting agent-summarized data without source verification
Agent says "no secrets in output" — verify with `grep`.

### ❌ Treating local-host as a trusted boundary
Prompt-injection from a fetched webpage can exfiltrate from local files via the agent's filesystem tools. Trust boundary is per-task, not per-host.

## Moved 2026-11-10 (context diet)

> Passages moved verbatim out of `rules/agents-as-users.md` on 2026-11-10 (context diet). The rule keeps the normative text; each block keeps the heading it had in the rule. The intro quote was replaced by a shorter one.

> Agents must be authorized like users, not given global credentials. Always loaded.

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
