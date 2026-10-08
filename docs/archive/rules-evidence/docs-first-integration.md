<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/docs-first-integration.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/docs-first-integration.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Why This Matters

In fast-moving ecosystems (deploy platforms, MCP, AI SDKs) training data is unreliable — APIs, export shapes, and adapters change faster than model knowledge. The repeated failure mode:

1. Assume the API from memory
2. Write the integration
3. Lose 10+ minutes to deploy-debug loops
4. *Then* check the docs and discover a framework-specific adapter or a changed export shape that invalidates step 2

The fix is cheap and goes first: read the docs before the code.

## Negative Existence Claims Need a Date — and Verify on Pushback (IMP-153)

**Evidence:** 2026-08-02, a skill cache dated 2026-06-24 produced "Opus 5 doesn't exist" — the user was right; the model had shipped 2026-07-24, four weeks after the cache was built. The cache wasn't wrong when written; it was stale and presented without a date, so the claim read as current fact instead of a dated snapshot.

## Moved from the rule on 2026-09-29 (IMP-234)

> Moved out verbatim while the rule was condensed to its normative core. The Context7 note is owned by `rules/mcp-tool-usage.md` (the rule keeps a pointer); three of the four anti-patterns restate the rule's own statements and are kept here in full.

### How to Apply — Context7 note (verbatim)

> **Context7 server param-name gotcha:** see the canonical note in [[mcp-tool-usage]] ("Context7 resolve-library-id parameter names") — two servers, different param names (`libraryName` vs `query`).

### Anti-Patterns (verbatim)

- ❌ Writing an SDK integration from memory, then debugging the deploy
- ❌ Assuming the last-known API surface is current in a fast-moving ecosystem
- ❌ Skipping the official template repo and reverse-engineering from errors
- ❌ Stating "X doesn't exist" without a source date, then defending it when the user disagrees instead of checking live

### References (verbatim)

- Tooling: Context7 MCP (`context7-keyed`), `find-docs` skill
- Companion: [[mcp-tool-usage]]
- Distilled from multi-project integration experience (merge-intake 2026-05-28)
