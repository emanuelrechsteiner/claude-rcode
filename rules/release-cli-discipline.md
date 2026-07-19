# Release & CLI Discipline Rule

> Four cross-project disciplines around shipping and CLI value-handling, distilled from the 2026-05-28 config merge-intake. **Consolidated 2026-07-03 (IMP-079) — supersedes `local-first-deploy.md`, `publish-discipline.md`, `shell-cli-piping.md`, `mcp-generation-serialize.md`; every rule and anti-pattern preserved.** Always loaded.

## 1. Local-First Deploy

**Before deploying a serverless function or build to the cloud, run the build locally and exercise the compiled artifact directly.** Cloud deploy-debug loops are the last resort, not the first test — each cloud iteration is a remote build + log-fetch round-trip, 5–10× the wall-time of a local pass. Observed: 4 failed cloud deploys cost ~12 minutes; a single local `<tool> build` + direct import of the compiled function (e.g. `import('.vercel/output/functions/.../index.js')` or the platform equivalent) would have caught all four bugs in <5 seconds.

- Run the platform's **local build** (`<tool> build`) before pushing a deploy.
- **Directly import / invoke** the compiled function artifact locally to exercise its logic before the cloud sees it.
- Reserve cloud deploys for environment/runtime concerns that genuinely can't be reproduced locally.

Anti-patterns:
- ❌ Treating `git push` / cloud deploy as the test loop for function logic
- ❌ Reading cloud logs to debug a bug a local import would have surfaced instantly

## 2. Publish Discipline

**Before publishing a package, install its packed tarball into a fresh consumer outside the monorepo and exercise every documented entry point.** Workspace symlinks resolve differently than a published package and hide: build-format mismatches (e.g. design-token `$value` vs `value` DTCG shape), CSS `@import` ordering issues under specific bundler + framework combinations, and missing files in the published set (`files` field omissions). The consumer hits these on first install — after publish is too late.

1. `pnpm pack` (or `npm pack`) to produce the `.tgz`
2. Install the `.tgz` into a **fresh consumer project outside the monorepo**
3. Run **every documented entry point** + a visual smoke test
4. Only then `changeset publish` / `npm publish`

Anti-patterns:
- ❌ Verifying only via workspace symlink, then publishing
- ❌ Publishing without exercising the documented public entry points
- ❌ Assuming the `files` set is correct without a packed install

## 3. Shell-to-CLI Piping

**When writing a value into a CLI (env vars, secrets, config), never pipe via `echo` or an unquoted heredoc.** Two silent corruption traps, neither of which throws at write time — they surface as a confusing downstream bug hours later:

1. **`echo "VALUE" | <tool> ...` appends a trailing newline** — downstream `new Date(value)`, `JSON.parse(value)`, or `value === expected` break in non-obvious ways, while the value *looks* right in most dashboards.
2. **Heredoc `<<EOF` with shell variables** can capture literal surrounding quotes into the stored value, silently breaking bearer-token comparisons and equality checks.

- Use `printf "%s" "$VALUE" | <tool> ...` (no trailing newline) — not `echo`.
- For programmatic writes, prefer the provider's REST API over the CLI.
- **Verify-by-pull:** after any write, pull the value back and compare byte-for-byte against the intended value.
- Defensively `.trim()` env-derived values before parsing in application code.

Anti-patterns:
- ❌ `echo "$TOKEN" | provider secret set NAME` (adds `\n`)
- ❌ `provider env add NAME <<EOF` with quoted interpolation
- ❌ Writing, then trusting without a read-back verification

## 4. MCP Generation Serialization

**Before invoking a generation-style MCP tool, confirm the user is not actively using that product's web UI in another tab, and serialize agent-and-human access.** Generation endpoints (e.g. text-to-screen / text-to-asset generators) mutate shared server-side session state; if the human is simultaneously driving the same product's web UI, concurrent calls collide — corrupting state, losing work, or returning errors. CRUD / read endpoints on the same server usually tolerate concurrency and don't need this gate.

Anti-patterns:
- ❌ Firing a generation MCP call while the user has the product's web UI open
- ❌ Assuming all endpoints on one MCP server share the same concurrency tolerance

## References

- Companions: `api-cost-optimization.md` (§1 — cheapest per successful outcome), `testing-quality.md` (§2), `code-quality.md` (§3 — defensive parsing of external values), `mcp-tool-usage.md` (§4)
- Distilled from multi-project experience (merge-intake 2026-05-28); consolidated per IMP-079 (2026-07-03) — originals in git history
