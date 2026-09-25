# Docs-First Integration Rule

> Fetch authoritative library docs BEFORE writing integration code, not after deploy failures. Always loaded.

## The Rule

**Before integrating an unfamiliar library, SDK, or cloud service, fetch its current documentation first** — via the Context7 MCP (`resolve-library-id` → `query-docs`) or the official template repo. Do not write the integration from memory.

## Why This Matters

Training data in fast-moving ecosystems (deploy platforms, MCP, AI SDKs) is unreliable — APIs, export shapes, and adapters change faster than model knowledge, and discovering that only after a failed deploy costs far more than checking first. The fix is cheap and goes first: read the docs before the code.

## How to Apply

- At the **top** of any integration task involving an unfamiliar package, call `resolve-library-id` + `query-docs` (Context7) or read the official template repo.
- Verify the **exact** export shape and any framework-specific adapter before writing imports.
- Distinct from the `find-docs` skill (on-demand lookup): this rule makes the doc-check a *precondition* of writing integration code, not an optional convenience.

> **Context7 server param-name gotcha:** see the canonical note in [[mcp-tool-usage]] ("Context7 resolve-library-id parameter names") — two servers, different param names (`libraryName` vs `query`).

## Negative Existence Claims Need a Date — and Verify on Pushback (IMP-153)

**"X doesn't exist" / "there is no feature Y" is itself an integration-relevant claim, and the same staleness risk applies to it as to API shapes.** A negative claim sourced from a cached skill, a memory file, or training data is only as current as that source — say so explicitly, with the source's date.

- State the cache/source date alongside any negative existence claim: *"as of my [skill cache from 2026-06-24 / training data], X does not exist"* — never a bare "X doesn't exist."
- **If the user pushes back and asserts the opposite, verify live immediately** (Context7 docs or web search per `web-research-trust.md`) instead of defending the cached claim. Don't ask permission to check — check, then report what changed.

## Anti-Patterns

- ❌ Writing an SDK integration from memory, then debugging the deploy
- ❌ Assuming the last-known API surface is current in a fast-moving ecosystem
- ❌ Skipping the official template repo and reverse-engineering from errors
- ❌ Stating "X doesn't exist" without a source date, then defending it when the user disagrees instead of checking live

## References

- Tooling: Context7 MCP (`context7-keyed`), `find-docs` skill
- Companion: [[mcp-tool-usage]]
- Distilled from multi-project integration experience (merge-intake 2026-05-28)

> Evidence and incident history (moved verbatim, IMP-217): `docs/archive/rules-evidence/docs-first-integration.md`
