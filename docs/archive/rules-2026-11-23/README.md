<!--
Status: ARCHIVED
Last Updated: 2026-11-23
Purpose: Unchanged copies of the always-loaded CLAUDE.md and the rule files that the 2026-11-23 modernization replaced or deleted. Kept for history; not loaded by Claude Code and not referenced by the live configuration.
-->

# Archive — Rules and CLAUDE.md before the 2026-11-23 modernization

> Each file here is a byte-for-byte copy of the baseline version at tag `baseline/pre-modernization-2026-11-23`. Nothing in this folder has been edited. The disposition table below is the one from `ops/modernization-2026-11/DESIGN.md` §2. The archived CLAUDE.md differs from the baseline in exactly one place: its section "External collaboration" (a private note) was removed on 2026-11-23.

| Baseline file | Disposition | Where its content lives afterwards |
|---|---|---|
| `CLAUDE.md` | replaced by `target/CLAUDE.md` | workshop and live notice: SessionStart hook and `AGENTS.md`; inventory, bypass tokens, observation pipeline, routines, output style: `docs/FRAMEWORK-REFERENCE.md` (already there); karst note: project memory only (removed from the file) |
| `rules/foundation.md` | replaced by `target/rules/foundation.md` | delegation detail: `docs/reference/delegation.md`, `agents/control-agent.md` |
| `rules/agency-bands.md` | replaced by `target/rules/agency-bands.md` | long form: `docs/reference/agency-bands.md` |
| `rules/slop-prevention.md` | replaced by `target/rules/slop-prevention.md` | long form: `docs/reference/slop-prevention.md` |
| `rules/workflow-git.md` | replaced by `target/rules/workflow-git.md` | long form: `docs/reference/workflow-git.md` |
| `rules/identity.md` | deleted | `workflow-git.md` (Identity) |
| `rules/recommend-on-ask.md` | deleted | `foundation.md` (Asking and acting) |
| `rules/docs-first-integration.md` | deleted | `foundation.md` (Scope, knowledge and decisions) |
| `rules/web-research-trust.md` | deleted | `agency-bands.md` (last paragraph); long form `docs/reference/web-research-trust.md` |
| `rules/mcp-tool-usage.md` | deleted | long form `docs/reference/tools.md` |
| `rules/tool-discipline.md` | deleted | `foundation.md` (Asking and acting; agent choice); the remainder is native tool behaviour; archived |
| `rules/context-engineering.md` | deleted | thresholds dropped (no source for current models); archived |
| `rules/api-cost-optimization.md` | deleted | `docs/reference/delegation.md` (model tiers) |
| `rules/parallel-by-default.md` | deleted | `docs/reference/delegation.md` (parallel work), `skills/parallel-dispatch` |
| `rules/agents-as-users.md` | deleted | `rules/security.md` gets a section "Access for agents and LLM-backed apps"; per-task access also in `docs/reference/delegation.md` |

`rules/fail-loud.md` is not archived: it stays in `rules/` as a path-scoped rule with an adjusted header line.
