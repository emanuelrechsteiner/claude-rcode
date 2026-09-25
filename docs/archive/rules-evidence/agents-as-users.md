<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Belege, Vorfälle und Messungen, die am 2026-09-24 (IMP-217) wörtlich aus rules/agents-as-users.md ausgelagert wurden — die Regel selbst bleibt dort; hier steht das „Warum" in voller Länge.
-->
# Belege zu `rules/agents-as-users.md`

> Ausgelagert 2026-09-24 (IMP-217). Jeder Block steht unter der Überschrift, unter der er in der Regel stand, und ist unverändert übernommen.

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
