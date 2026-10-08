# Third-Party Notices (skills)

Fourteen skills in this directory are adapted from the open-source repository
`affaan-m/ECC` (clone commit `c70874f`, 2026-09-29, license MIT, Copyright (c) 2026 Affaan Mustafa).
They are rewritten for this framework, not installed or copied verbatim: each source skill was read in
full, ECC-specific commands, paths, agents, and branding were removed or replaced with this framework's
equivalents, and unsafe or silent-fallback code samples were corrected. Each adapted `SKILL.md` carries
a provenance comment directly below its frontmatter. Adaptation date: 2026-10-01 (IMP-245).

Note on origin: `production-audit` and `click-path-audit` are marked `origin: community` in their source
frontmatter, i.e. community contributions included in ECC and distributed under ECC's MIT license; their
individual authors are not named in the source and no separate copyright line was available locally.

| Skill | Source path | Commit | License | What was changed |
|---|---|---|---|---|
| `context-budget` | `ECC: skills/context-budget/SKILL.md` | c70874f | MIT | Re-based on this framework's budgets (150k-character instruction budget vs. skill listing); dropped the `/context-budget` command and the Python JSONL snippet; added `/context` as the authoritative figure. |
| `swiftui-patterns` | `ECC: skills/swiftui-patterns/SKILL.md` | c70874f | MIT | View-model sample no longer swallows load errors (`try?` plus `?? []` replaced by an explicit error state); the sample view now renders that error with a retry action (`ContentUnavailableView`); condensed; links to `rcode-ios` and sibling Swift skills. |
| `swift-concurrency-6-2` | `ECC: skills/swift-concurrency-6-2/SKILL.md` | c70874f | MIT | Tightened wording; dropped an unrelated Foundation Models anti-pattern. Additions not in the source: a "verify current setting names" note, a note that default MainActor isolation is not for library targets, a note that `@concurrent` is for CPU-heavy work (I/O already suspends), the advice to replace legacy `DispatchQueue` synchronization where touched, and "clean build is evidence" in the migration steps. |
| `swift-actor-persistence` | `ECC: skills/swift-actor-persistence/SKILL.md` | c70874f | MIT | Loader now throws on corrupt data instead of mapping every failure to an empty cache; init is `throws`; `Sendable` constraint added; duplicate-id note. |
| `swift-protocol-di-testing` | `ECC: skills/swift-protocol-di-testing/SKILL.md` | c70874f | MIT | Added guidance on `@unchecked Sendable` mocks, asserting specific errors, and real-implementation integration tests. |
| `liquid-glass-design` | `ECC: skills/liquid-glass-design/SKILL.md` | c70874f | MIT | Condensed; added verify-against-current-docs and availability-guard note, accessibility checks, and a rendered-proof requirement. |
| `postgres-patterns` | `ECC: skills/postgres-patterns/SKILL.md` | c70874f | MIT | Removed references to ECC agents and skills; added an authority/safety section and a note that `EXPLAIN ANALYZE` executes the statement; managed-database cautions on the config template; RLS test advice. Factual edits to the data-type table: IDs now say "`bigint` identity, or an ordered UUID (v7) where distributed ids are needed" (source: "`bigint`", avoid "random UUID"), and strings "avoid `varchar(255)` without a real limit" (source: avoid `varchar(255)`); also `max_connections` restart note and the per-role `statement_timeout` advice are additions. |
| `database-migrations` | `ECC: skills/database-migrations/SKILL.md` | c70874f | MIT | Added an authority section (prod migrations are ESCALATE-band) and target confirmation; condensed per-tool workflows to commands plus gotchas; dropped the console-logging runner sample and the long per-tool code samples; rename sample reordered to add column, dual-write deploy, batched backfill, drop; batched backfill filters `email IS NOT NULL` so the loop terminates; Django backfill advice requires a terminating loop. |
| `api-design` | `ECC: skills/api-design/SKILL.md` | c70874f | MIT | Condensed to the conventions and one Next.js example (Go and Django REST samples dropped); added idempotency, filter whitelisting, and `req.json()` wrapped in error handling returning 400. |
| `eval-harness` | `ECC: skills/eval-harness/SKILL.md` | c70874f | MIT | Removed the runtime-specific utilities section and the `/eval` command; storage moved to a project `evals/` folder; added independent-grader and trial-count rules. Manual-only. |
| `council` | `ECC: skills/council/SKILL.md` | c70874f | MIT | Replaced references to other ECC skills with `grilling`, `code-reviewer-agent`, `planning-agent`, ADRs; sub-agents dispatched as `Plan`, read-only, with an explicit `model` parameter; removed product-specific example. Manual-only. |
| `click-path-audit` | `ECC: skills/click-path-audit/SKILL.md` | c70874f | MIT | Removed project-specific agent split and external skill references; full audit split into two waves (store mapper, then parallel area agents given the map path); added observed-behavior confirmation and untraced-touchpoint reporting. Manual-only. |
| `production-audit` | `ECC: skills/production-audit/SKILL.md` | c70874f | MIT | Replaced skill cross-references with this framework's skills; made the read-only boundary and missing-lens cap explicit; description says "no repo data sent to third-party scanners". Manual-only. |
| `canary-watch` | `ECC: skills/canary-watch/SKILL.md` | c70874f | MIT | Removed hook, notification-webhook, and home-directory log integrations; added baseline, "not checked" reporting, and safety scope. Manual-only. |

Not adapted: `skill-comply` (depends on bundled Python scripts and a CLI subprocess runner; not ported).

Known issues inherited from the source and not fixed in this round (out of scope):

- `swift-protocol-di-testing`: the "reports a corrupt file" test asserts only `CocoaError.self`, although the text asks for the specific error; its `SyncManager` uses the default iCloud file system, so under test it may throw `containerNotAvailable` before reaching the read.
- `swift-actor-persistence`: if `persistToFile()` throws, `cache` is already mutated, so memory and disk diverge while the caller sees the error; the fix is to write a copy and commit it to the cache only after a successful save.
- `council`: the voices run as the built-in `Plan` agent, whose own prompt is about implementation plans and may skew a voice toward plan format; the prompt template should tell each voice to ignore any plan-format preamble.

## Additional attribution

| Skill | Upstream | License | Copyright line |
|---|---|---|---|
| `postgres-patterns` | Supabase Agent Skills (credited in the source skill: "Supabase team", MIT License) | MIT | Supabase Agent Skills, MIT, copyright line not available offline; verify against the upstream LICENSE before relying on it. |

## License text (applies to the adapted portions)

MIT License

Copyright (c) 2026 Affaan Mustafa

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
