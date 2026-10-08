# Docs-First Integration Rule

> Fetch authoritative library docs BEFORE writing integration code, not after deploy failures. Always loaded.

## The Rule

**Before integrating an unfamiliar library, SDK, or cloud service, fetch its current documentation first** — via the Context7 MCP (`resolve-library-id` → `query-docs`) or the official template repo. Do not write the integration from memory.

## Why This Matters

In fast-moving ecosystems (deploy platforms, MCP, AI SDKs) APIs, export shapes, and adapters change faster than model knowledge; discovering that after a failed deploy costs far more than checking first.

## How to Apply

- Do the doc-check at the **top** of any integration task involving an unfamiliar package — a *precondition* of writing integration code, not an optional convenience (unlike the on-demand `find-docs` skill).
- Verify the **exact** export shape and any framework-specific adapter before writing imports.
- Context7 parameter names differ per server: see [[mcp-tool-usage]] §"Context7 resolve-library-id parameter names".

## Negative Existence Claims Need a Date — and Verify on Pushback (IMP-153)

**"X doesn't exist" / "there is no feature Y" is itself an integration-relevant claim, with the same staleness risk as API shapes:** a negative claim sourced from a cached skill, a memory file, or training data is only as current as that source.

- State the cache/source date alongside any negative existence claim — *"as of my [skill cache from 2026-06-24 / training data], X does not exist"*, never a bare "X doesn't exist."
- **If the user pushes back and asserts the opposite, verify live immediately** (Context7 docs or web search per [[web-research-trust]]) instead of defending the cached claim. Don't ask permission to check — check, then report what changed.

## Anti-Patterns

Besides the inverses of the rules above: ❌ assuming the last-known API surface is current in a fast-moving ecosystem; ❌ skipping the official template repo and reverse-engineering from errors.
