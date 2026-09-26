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
