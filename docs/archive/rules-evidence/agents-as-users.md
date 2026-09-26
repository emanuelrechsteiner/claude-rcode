<!--
Status: ARCHIVED
Last Updated: 2026-09-24
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
