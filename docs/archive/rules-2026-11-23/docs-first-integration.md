# Docs-First Integration Rule

> Fetch authoritative library docs BEFORE writing integration code, not after deploy failures. Always loaded.

## The Rule

**Before integrating an unfamiliar library, SDK, or cloud service, fetch its current documentation first** — via the Context7 MCP (`resolve-library-id` → `query-docs`) or the official template repo. Do not write the integration from memory.

## How to Apply

- Do the doc-check at the **top** of any integration task involving an unfamiliar package, as a precondition of writing integration code.
- Verify the **exact** export shape and framework adapter before writing imports; Context7 parameter names: see [[mcp-tool-usage]].

## Negative Existence Claims Need a Date — and Verify on Pushback (IMP-153)

State the source date with any negative existence claim, never a bare "X doesn't exist". On pushback, verify live immediately (Context7 docs or web search) instead of defending the cached claim — do not ask permission to check; check, then report what changed.
