<!--
Status: ACTIVE
Last Updated: 2026-11-23
Purpose: Full inventory of the framework with its history — moved out of CLAUDE.md verbatim on 2026-09-24 (IMP-217). CLAUDE.md is the signpost since then; this document is read on demand, not loaded every session.
-->
# Framework Reference — Inventory and Chronicle

> Moved out 2026-09-24 (IMP-217). The text below is the unchanged wording of the former CLAUDE.md sections (as of 2026-09-24); the numbers in it are snapshots of their respective date — only `scripts/framework-inventory.sh` still delivers the live inventory counts. The auto-loaded short version lives in `CLAUDE.md`, the architecture in `HARNESS.md`, the repo working rules in `docs/WORKING-IN-THIS-REPO.md`.

## Modernization 2026-11-23

The framework was rebuilt on 2026-11-23 to shorten the always-loaded text: the always-loaded framework text measured 67,691 characters before and measures 20,957 after (`wc -m` over `CLAUDE.md` and the four core rules, after the repairs from four rounds of counter-checks and from the first probe series on the target). In a fresh staged process the framework's always-loaded files take about 7,200 tokens instead of about 27,000 (`/context`, 2026-11-24; the owner's overlays are not counted). The always-loaded core is now four rules (`foundation`, `agency-bands`, `slop-prevention`, `workflow-git`), and seven rules are path-scoped (`code-quality`, `security`, `testing-quality`, `documentation`, `domain-docs-convention`, `planning-doc-convention`, `fail-loud`). Rules that were deleted or merged lost their text to the short core, to the long forms under `docs/reference/` (`agency-bands`, `slop-prevention`, `workflow-git`, `web-research-trust`, `tools`, `delegation`), or to `rules/security.md`. Hooks that only repeated a preference are no longer registered in `settings.json`; their scripts and suites stay on disk. The mandatory knowledge round became automatic library injection through `knowledge-inject.sh`; with the knowledge gate off (`CLAUDE_KNOWLEDGE_GATE=off`) that hook words its footers and helper paragraphs as advice and names no gate, and its default mode is unchanged. Eighteen command files carry `disable-model-invocation: true`, so only the user can start them; `knowledge-agent` and `goal-agent` carry `omitClaudeMd: true`. The rule texts from before the rebuild are in `docs/archive/rules-2026-11-23/`, and the long forms are in `docs/reference/`.

## System Architecture

This environment includes auto-loaded rules (`~/.claude/rules/`), commands, skills, agents, hooks, and scheduled tasks. **Exact counts are GENERATED, never hand-maintained** (they drifted in 3 docs simultaneously — IMP-083): run `~/.claude/scripts/framework-inventory.sh` for disk truth (`--json`, `--check key=N` for audits). Snapshot 2026-08-22 (after the Serena write gate, IMP-130/131), rules count corrected 2026-09-23 (`rcode/stages/backward-transitions.md`, formerly `phase-backward-transitions.md`, moved out of `rules/`, see above) and again 2026-09-24 (IMP-218 demoted `release-cli-discipline`/`cloud-cli-discipline` to on-demand skills). **Rules is the one count that differs by location — state both, never one:** workshop = **11 rules** (tracked `*.md` in `rules/`, measured via `ls rules/*.md | wc -l` / `CLAUDE_DIR="$PWD" bash scripts/framework-inventory.sh --json | jq .rules` run against the workshop); live install = **25 rules** until the next deploy (generated 2026-11-23: the 21 tracked files of the set before the rebuild, which the deploy removes, plus 4 git-ignored `*.local.md` overlays that exist only on the deployed machine and never sync to the workshop — `identity.local.md`, `reminders.local.md`, and two more personal overlays, one of whose names is itself a registered vault `<private-layer>` marker (`docs/adr/0003-vault-and-gate.md`) and is deliberately not repeated here — confirmed via `ls ~/.claude/rules/*.local.md`). Other counts (generated 2026-11-23 against the workshop via `CLAUDE_DIR="$PWD" bash scripts/framework-inventory.sh --json`; the live install differs until the next deploy): 22 commands · 69 skills · 54 hooks on disk / 42 registered · 14 agents · 3 scheduled tasks. The live install still registers 52 until the next deploy. Architecture documented in `~/.claude/HARNESS.md`. Token optimization is active via `env` settings.

> **Last major update:** 2026-08-01 — implementation of `meta-proposal-2026-30` (IMP-110..122), regression cases green (case count: `scripts/framework-inventory.sh`). **Three findings turned out worse than reported:** the lock registry was not leaking but *self-blocking* (a claim denied the file to its own subagent AND the orchestrator until TTL — write fan-outs were unusable, IMP-114); the ACK-token signature was computed over the *data-stripped* command, so two deletes with different quoted targets shared one signature and a token approved for A also authorized B (IMP-119); and `had_controller_step` alone would have been worthless because the compliant path exits the hook silently (IMP-116). **One reported finding was wrong:** `guard-unsafe.sh` never blocked `grep` — the four overrides were reflex prefixes, now logged as `OVERRIDE-UNNECESSARY` (IMP-118). Also: the weekly loop finally writes back (25 findings across 4 runs had produced 0 ledger entries, IMP-112), `zcat`→`gunzip -c` (BSD `zcat` read `.gz` as empty, hiding 1,286 signals, IMP-110), `agent_invocations` measured for the first time (IMP-115), loopback FPs removed from the web-fetch gate (46% of its log, IMP-117). Report: `plans/imp-triage-2026-08-01.md`. Previous: 2026-07-03 — Fable-5-Metareview (IMP-073..086): ledger backfilled + honest computed metrics, gate regression suite (case count: `scripts/framework-inventory.sh`) + rm-as-data FP fix, measurement loop closed (verification blocks, /meta --verify operational, staleness escalation), MCP agency gate (`mcp-agency-gate.sh`), rules diet (gate+arbiter → `agency-bands`; 4 micro-rules → `release-cli-discipline`; 4 conditional rules demoted to on-demand skills, ~9K tokens/session saved), model-era refresh (Claude-5 family, window-relative context thresholds), worktree discipline (IMP-070/072), R.Code versioning + `/rcode-upgrade`, drift/restore/retention scripts. Report: `plans/meta-proposal-2026-07-03-fable5-metareview.md`. Previous: 2026-05-27 KB-driven Migration v3.

### Two locations: workshop and live install (NEW 2026-08-04)

This repo exists in **two** places. Whoever doesn't know that edits in the
wrong location and wonders why changes vanish or take effect immediately.

| Location | Role | Path |
|---|---|---|
| **Workshop** (working copy) | Development, testing, and commits happen here. Nothing here is live. | `<BAUHOF>` (see `CLAUDE.md`) |
| **Live install** (installation) | What Claude Code actually reads. Receives only finished deploys. | `~/.claude` |

Remotes: the workshop has `origin` (GitHub) and `live` (→ `~/.claude`);
the live install has `origin` (GitHub) and `workshop` (→ the workshop).

**Deploy:** `claude-deploy [config|cockpit|all]` — refuses to run if the
workshop has uncommitted changes, and only ever fast-forwards. Takes effect
starting with the **next** session.

**Runtime preferences (IMP-127, 2026-08-04):** two things are written into
the live install by Claude Code itself at runtime, and used to make every
deploy fail because of it — `model`/`effortLevel` in `settings.json` (via
`/model`, `/config`) and the plugin state under `plugins/`. The former is
**pulled back** into the workshop during the deploy and recorded there as
its own commit (the live install keeps the value); the latter is no longer
versioned at all. If the live install diverges in *any other* tracked file
or in a key that isn't listed, the deploy still aborts — that's the "someone
worked on the live install by hand" case, and it's meant to stand out.
List + rationale: `RUNTIME_KEYS_JSON` in `scripts/deploy-to-live.sh`,
regression: `scripts/tests/deploy-regression.sh` (case count generated since IMP-205:
`framework-inventory.sh --json | jq .test_suites`). Since 2026-09-09,
`modelSettings` (per-model effort level, written by `/model` + `/effort`)
is also one of the runtime keys — the deploy failed on exactly this on
09-09 (IMP-194).

**Live drift (P-IMP-263, 2026-10-31):** every `config` deploy reports untracked
paths under the live install's governed directories (`skills/`, `hooks/`,
`scripts/`, `rules/*.md`, `cockpit/` and the others listed in the script). The
report is report-only and never blocks. A path matched by the tracked
`live-only-manifest.txt` (one glob per line: `skills/synced/`, `plugins/synced/`,
`plugins/store/`) is exempt. An untracked directory that holds its own `.git` (cockpit, deployed by `claude-deploy cockpit`) is a nested repo: it is listed once in a sub-list as skipped and is never counted or escalated. Every other path is shown with the
hint *adopt or list*, and escalates after 3 consecutive unlisted deploys
(IMP-164). Check without a deploy:
`scripts/deploy-to-live.sh --drift-check <live-dir> <workshop-dir> [state-file]`
(consecutive counting only with a state file; without one nothing is counted).
Regression: `scripts/tests/live-drift-regression.sh`.

> **Dead end (IMP-128, cleared up 2026-08-04):** a `~/.claude/settings.local.json`
> does not solve this — at the **user level**, Claude Code does not read this
> file (the local level only exists per project). Verified by measurement:
> the `NOTION_PARENT_PAGE_ID` entered there is not set in the session
> environment, while the second value in the same file demonstrably comes
> from `~/.zshrc`. The template `templates/settings.local.json.template` has
> been removed (template absent; the dead end is described in `docs/WORKING-IN-THIS-REPO.md` §4 Deploy); `README.md`, `skills/kokonutui-pro`,
> `agents/documentation-agent`, `docs/RETENTION-POLICY`,
> `scripts/restore-drill.sh`, and the public handbook are corrected.
>
> **Where values belong instead:** environment values for Claude's tools go
> into the shell (`~/.zshrc`) — this is the only path proven to work.
> Values that also need to arrive without a shell profile go into the `env`
> block of `settings.json` — **never secrets**, this file is public.
> Machine-stable, non-secret values belong in the spec that needs them (this
> is how it's solved for the log-file path, and since 2026-08-04 also for
> the Notion page of the `daily-docs` routine).

**Why they're separate:** a change to a hook or a rule in `~/.claude`
applies at the next tool call of the **same** session — it's like rewiring
the electrics while the power is still on. The workshop decouples this.
**Why the live install stays complete anyway** (no symlink onto the SSD):
the SSD is an external drive. If `~/.claude` depended on it, Claude Code
would start with **no configuration at all** whenever the drive isn't
mounted — no rules, no hooks, no permissions.

**Runtime data** (`projects/`, `sessions/`, `history.jsonl`, caches) lives
exclusively in the live install and is not versioned — the workshop knows
nothing of it.

The same pattern applies to the **Cockpit** (dashboard): source in the
workshop's sibling directory `…/cockpit`, installed copy at
`~/.claude/cockpit` (7 hook entries and the status line point there — a
PreToolUse hook that reaches into nothing can block tool calls, so the copy
must be local and complete).

**`claude-deploy` is a machine-local symlink, not tracked by git:** since 2026-08-04 `/opt/homebrew/bin/claude-deploy` points to `<WORKSHOP>/scripts/deploy-to-live.sh`, and a fresh machine recreates it with the one-line `ln -s` command in `docs/WORKING-IN-THIS-REPO.md` (References).

#### Moved from CLAUDE.md on 2026-09-29 (IMP-234)

From `### Two places: the workshop and the inhabited live install` (verbatim; CLAUDE.md now merges this into its READ THIS FIRST banner and keeps runtime keys, runtime data and remotes only as a pointer here):

`<WORKSHOP>` = working copy of this repo outside `~/.claude` (real path stored locally in `~/.claude/env.local.sh`).

| Place | Role | Path |
|---|---|---|
| **Workshop** (working copy) | Development, review, and commits happen here. Nothing here is live. | `<WORKSHOP>` |
| **Live install** (installation) | What Claude Code actually reads. Receives only finished deploys. | `~/.claude` |

Remotes: workshop `origin` + `live` (the live install); live install `origin` + `workshop` (the workshop). `claude-deploy [config|cockpit|all]`: only with a clean workshop, fast-forward only, takes effect from the next session; pulls runtime keys (`model`, `effortLevel`, `modelSettings`; IMP-127/194) back into the workshop. Runtime data lives only in the live install. Put environment values in the shell (`~/.zshrc`); values that must arrive even without a shell profile go in `settings.json`'s `env` block — **never secrets**, this file is public. The live install stays complete (no symlink onto the SSD), and so does the Cockpit copy `~/.claude/cockpit` (7 hook entries + the status line point there) — it must be local and complete. More: `docs/WORKING-IN-THIS-REPO.md`, `docs/FRAMEWORK-REFERENCE.md`.

### Auto-Loaded Rules (always in context)

Current state since 2026-11-23. Four rules load always; seven load only when a matching file is read or edited (see *Path-scoped rules* below). Long forms are not loaded: they sit under `docs/reference/` and the core rule points to them.

| Rule | Load | Governs |
|------|------|---------|
| foundation | always | Working directly or with helpers, scope and knowledge, asking and acting |
| agency-bands | always | Bands AUTO / SOFT-ACK / ESCALATE; long form `docs/reference/agency-bands.md` (web research: `docs/reference/web-research-trust.md`) |
| slop-prevention | always | No edits on unverified AI code; rendered proof before a visible claim; long form `docs/reference/slop-prevention.md` |
| workflow-git | always | Branches, commits, PRs, identity, feature lifecycle bands; long form `docs/reference/workflow-git.md` |
| code-quality | path | TypeScript/Python standards, naming, imports |
| testing-quality | path | Testing cadence, coverage targets, validation |
| security | path | Input validation, secrets, auth, data protection; access for agents and LLM-backed apps |
| documentation | path | Active/archived docs, JSDoc, README |
| domain-docs-convention | path | CONTEXT.md glossary and ADRs |
| planning-doc-convention | path | PLANNING.md and similar files as live specs |
| fail-loud | path | Ban silent fallbacks in agent code |

Not loaded: `docs/reference/` (`delegation`, `tools`, `web-research-trust` and the rest) and the rule texts under `docs/archive/rules-2026-11-23/`. The deleted rules' content and their new places are listed in `docs/archive/rules-2026-11-23/README.md`.

#### Before 2026-11-23 (history, kept as written)

| Rule | Governs |
|------|---------|
| foundation | Agent orchestration, dev phases, quality gates |
| code-quality | TypeScript/Python standards, naming, imports |
| testing-quality | Testing cadence, coverage targets, validation |
| security | Input validation, secrets, auth, data protection |
| workflow-git | Branches, commits, PRs, context hygiene |
| documentation | Active/archived docs, JSDoc, README |
| mcp-tool-usage | MCP path conventions, parameter formats |
| api-cost-optimization | Claude-5-family selection matrix (Haiku→Sonnet→Opus→Fable), anti-patterns (refreshed 2026-07-03, IMP-080) |
| identity | Git identity guard for multi-identity users (work / personal / client) |
| tool-discipline | Read-before-Edit, no Bash(cat/grep/find), specify subagent_type (from 30-day audit) |
| parallel-by-default | Decompose tasks → 2+ independent reversible units with disjoint files: AUTO-dispatch parallel with a one-line note; y/n only for ESCALATE-band ops or unprovable disjointness (IMP-055, 2026-06-21) |
| planning-doc-convention | PLANNING.md/PLAN.md as live spec, not draft notebook — separate commits, edits-not-rewrites (IMP-036) |
| **context-engineering** | **Window-RELATIVE thresholds: soft 50% / hard 75-80% / auto-compact margin 90%** — `/context` check at phase boundaries (window-relative since 2026-07-03, IMP-080) |
| **fail-loud** | **Ban silent fallbacks** (`except: pass`, default-return-None for required configs) in agent code (NEW 2026-05-27) |
| **agents-as-users** | **Authz-per-task**, never global credentials, Meta Rule-of-Two (NEW 2026-05-27) |
| **slop-prevention** | **Forbid `Edit` on files with unresolved type-errors**; fresh-agent review before extending AI scaffolds (NEW 2026-05-27) |
| **agency-bands** | **THE band system (merged excessive-agency-gate + autonomy-arbiter, IMP-079)**: R×S×T scoring → AUTO / SOFT-ACK / ESCALATE; irreversible ops always y/n even in YOLO; 4 enforcement layers incl. bash gate + `mcp-agency-gate.sh`; op-bound single-use ACK token |
| **cloud-cli-discipline** | **Inspect state before destructive cloud-CLI ops**; beware team/scope auto-pick (NEW 2026-05-28, merge-intake) |
| **release-cli-discipline** | **Merged 4 micro-rules (IMP-079)**: local-first deploy, tarball-test before publish, `printf "%s"` piping + verify-by-pull, generation-MCP serialization |
| **docs-first-integration** | **Fetch library docs (Context7) BEFORE writing integration code**, not after deploy failures (NEW 2026-05-28, merge-intake) |
| **recommend-on-ask** | **Lead every question / option-set with a concrete recommendation + one-line WHY** (NEW 2026-06-20, IMP-053) |
| **web-research-trust** | **Standing-allow for web fetch/search/scrape** — no per-URL prompt; pause+ask ONLY when ≥10% malicious-content probability (or the deterministic gate flags it). NEW 2026-07-09, IMP-088 |
| **domain-docs-convention** | **Per-project CONTEXT.md glossary** (coin a term from the 3rd paraphrase onward; code names follow the glossary) **+ atomic ADRs** in `docs/adr/` (one decision per file, immutable, superseded-by instead of edited). Adapted from mattpocock/skills, MIT (NEW 2026-08-03, IMP-124) |

> **Demoted to on-demand skills (IMP-079, 2026-07-03):** `legacy-codebase-audit`, `rcode-ios`, `framework-extraction`, `kokonutui-pro` (+ component index) — their headers were already trigger specs; they now load only when their topics come up (~5.8K tokens/session saved).
>
> **Removed from this table (2026-09-23, "Plan folgt Praxis"):** `phase-backward-transitions` — the backward-jump protocol it documented now lives at `~/.claude/rcode/stages/backward-transitions.md` and is read by the R.Code stage playbooks when a backward jump is considered, not loaded into every session of every project. See `docs/adr/0002-rcode-plan-follows-practice.md`.

#### Moved from CLAUDE.md on 2026-09-29 (IMP-234)

From `### Auto-Loaded Rules (always in context)` (verbatim; CLAUDE.md keeps the heading and a one-line pointer here):

| Rule | Governs |
|---|---|
| foundation, parallel-by-default, recommend-on-ask | Orchestration, dispatch, questions |
| agency-bands, agents-as-users, security, fail-loud | Safety, authz, secrets |
| code-quality, testing-quality, slop-prevention | Code and test quality |
| workflow-git, identity | Git, identity |
| tool-discipline, mcp-tool-usage, context-engineering, api-cost-optimization | Tools, MCP, context, models |
| documentation, planning-doc-convention, domain-docs-convention, docs-first-integration, web-research-trust | Docs, plans, ADRs, research |

Demoted to on-demand skills: legacy-codebase-audit, rcode-ios, framework-extraction, kokonutui-pro (IMP-079); release-cli-discipline, cloud-cli-discipline (IMP-218). phase-backward-transitions → `rcode/stages/backward-transitions.md`. Evidence moved out of the rules: `docs/archive/rules-evidence/`.

### Path-scoped rules (2026-11-10, context diet)

| rule | paths |
|---|---|
| code-quality | `**/*.{ts,tsx,js,jsx,mjs,cjs,py,swift,go,rs,java,kt,rb,php,vue,svelte}` |
| security | `**/*.{ts,tsx,js,jsx,mjs,cjs,py,swift,go,rs,java,kt,rb,php,sql,prisma,vue,svelte}`, `**/.env*`, `**/*.{yml,yaml,toml}`, `**/supabase/**`, `**/convex/**` |
| testing-quality | `**/*.{ts,tsx,js,jsx,mjs,cjs,py,swift,go,rs,java,kt,rb,php,vue,svelte}`, `**/tests/**`, `**/__tests__/**`, `**/*.{test,spec}.*` |
| documentation | `**/README*`, `**/docs/**`, `**/*.mdx`, `**/CHANGELOG*`, `**/CONTRIBUTING*` |
| planning-doc-convention | `**/PLANNING.md`, `**/PLAN.md`, `**/PLANS.md`, `**/ARCHITECTURE.md`, `**/ARCH.md`, `**/SPEC.md`, `**/SPECIFICATION.md`, `**/SPECS.md`, `**/DESIGN.md`, `**/DESIGNS.md`, `**/docs/plans/**`, `**/docs/specs/**`, `**/docs/architecture/**` |
| domain-docs-convention | `**/CONTEXT.md`, `**/docs/adr/**`, `**/ADR-*.md` |
| fail-loud | same code paths as code-quality (added 2026-11-23) |

They load when a matching file is read or edited; all other rules are always loaded. Mechanism: code.claude.com/docs/en/memory.md, Path-specific rules.

### Agents (Task tool — heavy implementation)

| Agent | Model | Use For |
|-------|-------|---------|
| **control-agent** | **haiku** (IMP-284, 2026-11-11; was `fable`) | **Central orchestrator + Autonomy Arbiter** — the ONE canonical dispatch spec (§2: Agent+Model+Effort per spawn; §4: 2nd-order re-plan checkpoint) — coordinates multi-agent workflows, plans + delegates + synthesizes; sole human-facing escalation point for delegated work (sub-agents report ESCALATE-band ops up to it; it consolidates one verbatim y/n per logical operation per `agency-bands.md`) (new 2026-05-24; arbiter role 2026-06-09; model raised opus→fable + §2/§4 formalized 2026-07-15, IMP-091/092; model fable→haiku 2026-11-11, IMP-284) |
| planning-agent | haiku | Architecture, task breakdown, implementation plans |
| backend-agent | haiku | APIs, database, server logic, authentication |
| testing-agent | haiku | Unit tests, integration tests, E2E tests |
| code-reviewer-agent | haiku | Code review (READ-ONLY — cannot edit files) |
| cleanup-agent | haiku | Dead code detection, debug artifact removal |
| ~~ux-agent~~ | ~~sonnet~~ | **Archived 2026-05-27** — replaced by `ux-design` skill (function-duplicate, Skill has identical scope) |
| ui-agent | haiku | Visual design systems, component specs, component implementation. System prompt depersona-framed 2026-05-27 |
| **visual-qa-agent** | haiku (since 2026-11-11, IMP-284) | **Read-only visual QA in a real browser** (Playwright MCP tools; no Edit/Write, no `browser_run_code_unsafe`) — screenshot/snapshot first, describe what is visible, then judge; compare against the SOURCE (template file, user screenshot), never a paraphrase (`slop-prevention.md` Trigger 3 as its core mandate). Closes the roster gap that ≥6 `AGENTENWAHL:` rationales named in the window 2026-08-24..09-09 (proj-0384c7: 11/11 dispatches went to general-purpose for visual checks). NEW 2026-09-09, IMP-196 |
| **goal-agent** | haiku | **Read-only scope watcher (IMP-289, 2026-11-11).** Compares the work of a wave (changed files, commits, the goal file) with the goal plan and returns VERDICT, DEVIATIONS and NOT CHECKED: work outside the plan's paths, issues marked done without their check, dropped work nobody recorded. Never edits and never decides; `/team-lead` runs it after every delegation wave |
| **research-agent** | haiku | Documentation/technology research; **can now `Write` a NEW report file** at the path the brief names (never Edit — IMP-197). Lives at `agents/research-agent.md` since 2026-09-09: it had sat in the then-live `agents/archived-replaced-by-skills/` (now `docs/archive/agents-replaced-by-skills/`) while being dispatched **36×** since 2026-08-01 — that folder never archived anything, see IMP-208 below |
| **documentation-agent** | haiku | **Daily-Docs Routine only** (Mode B → Notion). For ad-hoc docs use `documentation` skill. Mode A removed 2026-05-27. |
| **version-control-agent** | haiku | **Git discipline** — honors report-only default for research/audit tasks. System prompt depersona-framed 2026-05-27 |
| **pattern-extractor-agent** | haiku | **`/lessons` Step 6 only** — deep git-commit pattern analysis (learning extraction), spawned via Task tool from `commands/lessons.md`. File lives at **`agents/pattern-extractor-agent.md`** (top level — corrected 2026-08-01). For ad-hoc pattern extraction outside `/lessons`, prefer the `pattern-document` skill instead (documented 2026-07-15, IMP-092, R-4) |
| ~~improvement-agent~~ | ~~sonnet~~ | **Archived 2026-01-17** — replaced by `observation-capture.sh` hook + `meta-observer` skill |

Since 2026-11-23: `knowledge-agent` and `goal-agent` carry `omitClaudeMd: true` (they take everything from the brief and only read). Explore and Plan inherit the session model unless the call passes `model`; on a subscription Explore runs on the model behind the `opus` alias. Every spawn passes `model` and `effort` explicitly.

> **The "archive" folder was live (IMP-208, 2026-09-09).** the then-live `agents/archived-replaced-by-skills/` (now `docs/archive/agents-replaced-by-skills/`) never archived anything: Claude Code scans `agents/` **recursively**, so `build-validator-agent`, `framework-specialist-agent` and `research-agent` were all invocable from inside it (the session's agent list proved it), and two files there — `documentation-agent.md`, `version-control-agent.md` — carried the **same `name:`** as the live top-level agents, with undefined precedence (the archived `version-control` copy predates the report-only rule). The only entry that was ever truly silent was `ux-agent.md.2026-05-26` — a renamed extension. Fix: the folder now lives at `docs/archive/agents-replaced-by-skills/` (where `rules/documentation.md` puts archived material and where nothing loads it); `research-agent.md` moved to `agents/`. **To retire an agent, move it OUT of `agents/` or change its extension — a subfolder does nothing.** Acceptance in the next session: `build-validator-agent`/`framework-specialist-agent` must be absent from the agent list, `visual-qa-agent` present.

#### Moved from CLAUDE.md on 2026-09-29 (IMP-234)

From `### Agents (Task tool)` (verbatim, the whole section body; CLAUDE.md now keeps only pointers here, to the `agents/*.md` descriptions and to `rules/foundation.md`, plus the pattern-extractor-agent hint and the retire-an-agent rule):

| Agent | Model | Use |
|---|---|---|
| control-agent | fable | Orchestrator, arbiter |
| planning-agent | opus | Architecture |
| backend-agent | haiku | APIs, DB, auth |
| testing-agent | haiku | Tests |
| code-reviewer-agent | haiku | Read-only review |
| cleanup-agent | haiku | Dead code |
| ui-agent | haiku | UI components |
| visual-qa-agent | sonnet | Browser QA |
| research-agent | haiku | Research; may `Write` a NEW report file, never Edit |
| documentation-agent | haiku | Daily-Docs only; ad-hoc docs → `documentation` skill |
| version-control-agent | haiku | Git, report-only |
| pattern-extractor-agent | haiku | /lessons Step 6; ad-hoc → `pattern-document` skill |
| knowledge-agent | haiku | Read-only knowledge retrieval, on demand for large waves since 2026-11-23 (the knowledge round is no longer mandatory). Earlier wording, for the knowledge round: runs the lookup with the Lead's sets, returns verbatim excerpts, never judges (IMP-268; tools Bash, Read, Grep, Glob) |

Archived: ux-agent (→ ux-design), improvement-agent (→ observation pipeline). **Retire an agent by moving it OUT of `agents/`; a subfolder does nothing.**

### Forked Skills (isolated context — lightweight specialists)

| Skill | Model | Use For |
|-------|-------|---------|
| validate-build | haiku | Quick build/type/lint validation |
| research | haiku | Tech research, API docs, best practices |
| version-control | haiku | Git operations, commits, PRs |
| worktree-consolidate | haiku | Discover + classify all active worktrees, present consolidation plan, gate every merge/push/prune behind y/n (NEW 2026-06-21, IMP-066) |
| nextjs-debug | haiku | Next.js framework diagnostics |
| pattern-document | haiku | Extract reusable patterns from fixes |
| documentation | haiku | Technical docs, README, API docs |
| meta-observer | opus | On-demand synthesis of observation signals → IMP proposals (2026-04) |
| memory-index | haiku | Cross-project query layer over 35+ memory dirs (2026-04) |
| scroll-animation-patterns | haiku | RAF-driven scroll animations, sticky card decks |
| quality-review | inherit; its 6 specialists are haiku | Milestone-level 6-specialist parallel review (arch/security/perf/testing/maintainability/docs) — deep pre-commit/pre-PR pass (documented 2026-07-03, IMP-083) |
| legacy-codebase-audit / rcode-ios / framework-extraction / kokonutui-pro | — | Demoted from always-loaded rules (IMP-079) — load on-demand via their trigger topics |

#### Moved from CLAUDE.md on 2026-09-29 (IMP-234)

From `### Skills` (verbatim; CLAUDE.md now keeps only the demoted-rules and background-skills hints plus a pointer to this table):

| Skill | Mode | Use |
|---|---|---|
| validate-build, research, version-control, nextjs-debug, worktree-consolidate, memory-index | forked, haiku | Utilities |
| pattern-document, documentation, scroll-animation-patterns, quality-review | forked, haiku | Docs, patterns, review |
| meta-observer; prototype | forked (opus); forked, haiku | IMP proposals; spikes |
| scope-check, rcode-onboard, grilling, resolving-merge-conflicts | main | Scope, onboard, grill, merge |
| create-hook, create-rule, create-skill, create-subagent, migrate-to-skills | creation | Author framework assets |
| legacy-codebase-audit, rcode-ios, framework-extraction, kokonutui-pro, release-cli-discipline, cloud-cli-discipline | on-demand | Demoted rules — load on their topic |
| react-perf-check, tailwindcss-v4-styling, import-fixer, fix-review, orchestration | background | Auto-trigger only |
| context-budget, swiftui-patterns, swift-concurrency-6-2, swift-actor-persistence, swift-protocol-di-testing, liquid-glass-design, postgres-patterns, database-migrations, api-design | main | Adapted from ECC (MIT) 2026-10-01, IMP-245 — `skills/THIRD-PARTY-NOTICES.md` |
| eval-harness, council, click-path-audit, production-audit, canary-watch | manual (`disable-model-invocation`) | Adapted from ECC (MIT) 2026-10-01, IMP-245 — invoke by `/name` only |

### Framework Creation Skills (NEW 2026-05-24 — ported from Cursor)

| Skill | Use For |
|-------|---------|
| create-hook | Author Claude Code hooks + register in settings.json |
| create-rule | Author always-loaded rules in ~/.claude/rules/ |
| create-skill | Author SKILL.md files with proper Claude Code frontmatter |
| create-subagent | Author new specialized agent .md files |
| migrate-to-skills | Convert legacy Cursor .mdc rules / commands to SKILL.md format |

### Hooks (registered in `settings.json`)

| Hook | Event | Purpose |
|------|-------|---------|
| session-start-context.sh | SessionStart | Context loading at session begin |
| git-identity-check.sh | SessionStart | Identity guard (single identity: Maintainer — LegacyIdentity retired 2026-06; Claude-Login `<email>` is unrelated to git) |
| guard-unsafe.sh | PreToolUse / Bash | Block destructive commands (rm -rf /, sudo, nc, etc.). **Fix 2026-05-24:** Word-boundary added to nc-regex (was matching `rsync`) |
| **cockpit-secret-guard.sh** (+ `hooks/lib/cockpit_secret_*.py`) | PreToolUse / `Bash\|Grep\|Glob\|Read` | **Cockpit launch-token tripwire (2026-10-06).** Denies the agent's tmux `capture-pane`/`pipe-pane`/`save-buffer`/`show-buffer`/`list-buffers`/`choose-buffer` (incl. aliases, prefixes, `-L/-S/-f`, env prefixes, wrappers, `bash -c`/`eval`/`$(…)`), any reference to `~/.claude/cockpit/web-*` in any spelling (also as Read/Grep/Glob path), and env dumps of the cockpit server (`ps E/e`, `/proc/*/environ`, only with `server.ts`/`cockpit` named). Quoted data (`git commit -m "…"`, `echo`, `grep` patterns) is not a command and passes. **Override is not a bypass:** an inline `CLAUDE_GUARD_OVERRIDE=1` only turns the deny into a native `ask` prompt to the user; the original command is always scanned unmodified. Fails CLOSED for commands it cannot inspect (> 64 KB, nesting, scanner crash), fails OPEN (loud + logged) only for garbled hook JSON or a missing scanner. **Honest limit: a deterministic best-effort tripwire against the agent's tool calls, not a sandbox** — a same-uid process still reaches the token via terminal scrollback outside tmux, other windows' history or the browser, and a python/node one-liner built from string pieces defeats any pattern guard; `permissions.deny` stays as second layer (effective for the Read tool itself). **Known open classes (2026-10-06, found by automated review and code reading, not yet probed one by one; listed in the hook header):** shell evaluation modelled differently from bash (brace sequences, `${…}` forms, `$(( ))`, `for`, `printf`, `read`), programs with built-in command execution treated as data programs (`git`, `man`, `awk`/`sed`, `find -path`) and unresolved wrapper targets, copy/link destination parsing (`-t`), uncanonicalised path spellings (`/private/…`, `/proc/…/task/…/environ`), interpreter code that builds paths from pieces, debugger attach, MCP tools outside read-like names. Open decision: ASK by default when a command names the Cockpit directory and cannot be classified as harmless. Regression: two suites, `hooks/tests/cockpit-secret-guard-regression.sh` (144 cases, DENY/ALLOW spellings) and `hooks/tests/cockpit-secret-guard-regression-modes.sh` (38 cases, override, logging, fail-closed, fail-open), sharing `hooks/tests/lib/cockpit-secret-guard-harness.sh` (outside the `run-all-tests.sh` glob) |
| git-state-check.sh | PreToolUse / Bash | Check git state before risky operations |
| git-identity-enforce.sh | (not registered since 2026-11-23) | Placeholder that exited 0 on every call (audit 03, B2); kept on disk. Purpose was: enforce identity on git commits |
| file-protection.sh | PreToolUse / Write\|Edit | Protect sensitive files |
| **governing-path-guard.sh** | PreToolUse / Bash, Write\|Edit, MultiEdit | **Blocks writes into the LIVE install's governing paths** (`rules/*.md` except `*.local.md`, `agents/`, `skills/`, `commands/`, `hooks/`, `rcode/`, `scheduled-tasks/`, `scripts/`, `cockpit/`, `output-styles/`, `templates/`, `docs/` (since 2026-11-24, because the long form of the rules lives in `docs/reference/`), `CLAUDE.md`, `settings*.json`) and `git -C <live>` write subcommands — the two-location rule as a mechanism, aimed at the unattended routine runner (IMP-239, 2026-10-01). Fence against accidental writes, not a wall: known limits in the header. Classifier `hooks/lib/governing-path-classify.py`; parse failure fails closed when the command names a live governing path. Override: single-use, op-bound `CLAUDE_GOVERNING_WRITE_ACK=<sha256>` (logged). Regression: `hooks/tests/governing-path-guard-regression.sh` |
| **git-bypass-guard.sh** | PreToolUse / Bash | **Blocks git hook bypass**: `--no-verify` / `commit -n` on commit, push, pull, merge, cherry-pick, rebase, am, revert; `core.hooksPath` overrides; `HUSKY=0`; an agent-set `VAULT_PRECOMMIT_BYPASS` (IMP-240, 2026-10-01; mechanism adapted from ECC `block-no-verify.js`, MIT). Classifier `hooks/lib/git-bypass-classify.py` + `gbg_lex.py`; a classifier failure on a git-shaped command asks instead of allowing. Override: `CLAUDE_GIT_BYPASS_ACK=<sha256>` (logged). Regression: `hooks/tests/git-bypass-guard-regression.sh` |
| **security-audit.sh** | PreToolUse / Write\|Edit | **Block edits introducing secrets** (github_pat_*, ghp_*, AKIA*, sk-*, AIza*, xox*; PEM private keys and JWTs since 2026-10-01 from the shared `scripts/lib/secret-patterns.sh`, IMP-244). No content-marker override. Fails closed if the pattern lib is missing. New 2026-05-24 after PAT-leak finding. Regression: `hooks/tests/security-audit-regression.sh` |
| **vault-write-gate.sh** | PreToolUse / Write\|Edit (also the MultiEdit input shape) | **Blocks a real name/path/account/ID from landing in a versioned file of a framework-repo clone (IMP-219, 2026-09-25)** — checks only the INCOMING text via `scripts/vault/vault.sh check --stdin --as <target>`, the SAME matcher every other consumer uses; a Tresor or structural hit is `exit 2` naming `term → token` on stderr, never the value in the log. Hygiene gate, not the CRITICAL floor: an infrastructure failure (missing `jq`, broken `vault.sh`) fails OPEN with a loud NOTE. Bypass: `CLAUDE_VAULT_GATE_OFF=1` (logged). Also wired as an inspector in `serena-write-gate.sh`, and mirrored for non-Claude-Code writers (`sed`/heredoc/`jq`) by `scripts/git-hooks/pre-commit` (staged content) — the ledger's own append path is gated separately by `scripts/ledger-append-vault-gate.sh`. ADR: `docs/adr/0003`. Regression: `hooks/tests/vault-write-gate-regression.sh` (20 cases; generated 2026-11-11) |
| auto-format.sh | PostToolUse / Edit\|Write | Auto-format after edits |
| post-edit-validate.sh | PostToolUse / Edit\|Write | Validate file post-edit |
| observation-capture.sh | PostToolUse / Edit\|Write | Capture signals for the observation pipeline |
| ~~line-limit-check.sh~~ | (PostToolUse / Edit\|Write) | **Superseded 2026-06-09** — present on disk but NOT registered in `settings.json`; the >400-line warning (per code-quality.md) is folded into `stop-batched-checks.sh` |
| session-end-check.sh | Stop | End-of-session metrics + ledger update |
| **sandbox-guard.sh** | SessionStart | **Warn if YOLO active without sandbox** (Casco YC 7/16-hacked finding). New 2026-05-27 |
| **excessive-agency-gate.sh** | PreToolUse / Bash | **Gate irreversible ops** (force-push, rm -rf, migrations) — exit 2 forces user confirm. New 2026-05-27. Since 2026-11-24 (IMP-300) it also escalates every spelling of a forced push, a hard reset and an npm publish that the three native `ask` prefixes cannot match (options between the tool and the subcommand such as `git -C <dir>`, `-f`, `--force-with-lease`, a `+refspec`, the flag in a later position, a wrapper or an assignment in front), `pnpm publish` and `yarn publish`, and `gh` with a global option before `pr merge`, `pr close`, `release create` or `workflow disable`; the plain spellings stay with the native prompt. Found by a probe run in which `git -C <dir> push --force-with-lease …` ran unstopped. Regression: `hooks/tests/gate-regression.sh` |
| **self-critique-log.sh** | Stop | **Append session metadata** (incl. per-session edit count, IMP-082) to `self-critique.jsonl` — consumed by meta-observer since 2026-07-03 |
| **mcp-agency-gate.sh** | PreToolUse / `mcp__.*` | **Deterministic ask-layer for MCP writes** (execute_sql, apply_migration, deploys, calendar/external comms) via native `permissionDecision:ask`. NEW 2026-07-03, IMP-078 |
| **config-drift-check.sh** (scripts/) | Stop | **Warn on config-repo drift**: uncommitted tracked changes >N days or unpushed local commits. NEW 2026-07-03, IMP-084 |
| **web-fetch-safety-gate.sh** | PreToolUse / `WebFetch\|WebSearch` + `mcp__.*` + `Bash` | **Deterministic danger-gate for research fetching** — auto-allows; escalates to native `ask` only on raw-IP/punycode/shortener/binary-download/creds-in-URL/abused-TLD across native+Firecrawl-MCP+Bash routes. **IMP-117 (2026-08-01):** loopback carve-out (`127.0.0.1`/`::1`/`localhost`/`*.localhost` skip the host-identity checks ONLY — credentials + binary-download still screen them) and a `jq`-built log writer. Pairs with `web-research-trust.md`. **IMP-203 (2026-09-09):** a non-alphabetic last label escalates only for IP-*shaped* hosts (4 dot-segments, or dotless decimal/hex) — `DD.MM.YYYY` dates next to a `curl`/`wget` mention were 2 of 30 escalations in the window. Regression: `hooks/tests/web-fetch-gate-regression.sh` (100 cases). NEW 2026-07-09, IMP-088 |
| **dispatch-capture.sh** | PreToolUse / `Task\|Agent` | **The subagent-dispatch meter** — the only surface that can see a delegation (`observation-capture.sh` matches `Edit\|Write`, so signals.jsonl structurally cannot). Feeds `agent_invocations` in `daily-metrics.jsonl`. Payload is `{ts, session_id, tool, subagent_type, model, run_in_background, isolation}` — deliberately **no prompt** (untrusted + bulky); a missing `model` parameter is logged as `"inherit"`, not `null` (IMP-204 — 51/153 rows were null in the window). No `agent_id` — PreToolUse fires before the runtime assigns one, which is why `background-agent-check.sh` pairs by count. NEW 2026-08-01, IMP-115 — promoted from the expired `q2-probe-dispatch-dump.sh` (retired under IMP-115; now `hooks/archived/`) |
| **git-remote-check.sh** | SessionStart | **Warn when local work has nowhere to go** — repo with 0 git remotes and >N local commits (default 20, `CLAUDE_NOREMOTE_WARN_COMMITS`). Non-blocking, 3 local git calls, no network. NEW 2026-08-01, IMP-122 — generalises a 157-commit/0-remote near-total-loss exposure |
| **routine-liveness-check.sh** | SessionStart | **The reader the routine logs never had** — scans `daily-docs-log`/`nightly-obs-log`/`weekly-improve-log.jsonl`; ≥2 consecutive `status:"error"` runs → a blocker line at session START (routine, count, last error, series start); log older than 2× its interval → "hasn't fired for N days"; silent when healthy or absent; always exit 0. Against the real logs on 2026-09-09 it reported daily-docs 18 and weekly-improve 3 — the 39 failures nobody read (IMP-189) had been visible only to the quarterly audit. Regression: `hooks/tests/routine-liveness-regression.sh` (13). NEW 2026-09-09, IMP-191 |
| **subagent-watchdog.sh** + **background-agent-check.sh** | SubagentStop + UserPromptSubmit/Stop | **Heartbeat for background troops (IMP-198)** — every SubagentStop is logged to `subagent-stops.jsonl` with `stop_reason` and an `abnormal` flag (`stop_reason≠end_turn` or rate-limit/quota/overloaded markers in the last message; preview ≤160 chars, no full messages); `background-agent-check.sh` pairs dispatches against stops per session (the session's rows are selected across the whole log by a `grep -F` prefilter on the session id; the earlier `tail -n 500` window had hidden whole sessions) and, at the next prompt or turn end, prints `⏳ N Hintergrundtrupp(s) ohne Ende-Signal seit M min` (threshold `CLAUDE_BG_STALE_MIN`, default 20) or the preview of an abnormal stop ≤60 min old. Would have said "1 troop without end signal for 5 h 10 min" at the 16:42 "weiter" on 2026-09-01. **Blind spots, by design and documented in the script headers:** a troop that is alive but idle; a crash below the hook layer (no SubagentStop at all); pairing is FIFO by count, not by identity. **P-IMP-260 (2026-10-31):** on Stop, whenever a helper of this session is still open, one un-aged line `NOTE (P-IMP-260): N helper(s) of this session may still be running — a "Done: yes" verdict is not valid until they have stopped.` UserPromptSubmit never gets it. The NOTE's stdout is not fed back to the agent, so the agent lists its own open helpers before a verdict (`commands/issue.md` Step 7 item 3); the NOTE is the owner-facing backstop. Regression: `hooks/tests/background-watchdog-regression.sh` (case count from the inventory; the 2026-09-23 three-state fix — missing `stop_reason` is no longer "abnormal"; 1,515/1,515 logged stops had been false alarms) and `hooks/tests/background-agent-check-regression.sh` (P-IMP-260 NOTE; BSD-only, exits 2 on Linux). NEW 2026-09-09 |
| **security-findings-check.sh** (+ `scripts/security-review-findings.sh`) | SessionStart | **The return channel for automatic security reviews (IMP-207)** — the `security-guidance` plugin runs its reviews as separate `sdk-py` sessions ("Review this change for security vulnerabilities …") and delivers findings only as a chat message into a still-living parent session; nothing persisted, so a HIGH finding from 2026-08-24 sat unread for 16 days. The extractor takes each review session's **last accepted** `StructuredOutput` call (rejected schema attempts come first; a session with none is *incomplete*, never *clean*), writes one row per finding to `security-review-findings.jsonl`, committing each session in the order rows → upstream → OUT → SEEN → STATE (a kill never caches a session as resolved without its rows; the feed reaches the script via stdin, not argv), dedups repeats by a key of path, category and normalized summary (reworded repeats are not collapsed: an open owner decision), routes vendor-owned paths to an upstream list, and offers `--since`/`--project`/`--dry-run`/`--ack <session_id>`/`--to-ledger` (proposed only, through `ledger-append-proposed.sh`). The hook runs it incrementally with a time budget and prints one line: `🔐 N ungesichtete Sicherheitsbefunde für <project> (…) — sichten: --ack <session_id>`. **First run (2026-09-09, since 08-24): 173 review sessions, 89 clean, 18 incomplete, 11 findings** — the 08-24 one, two from the same day about the `--location` fix (a parser differential: quoted values are stripped before the regex runs), and 5 never seen before in proj-a07272/proj-0384c7. Also the source of the IMP-200 path-error family — the review prompt names relative paths without a repo root. **Known limit (2026-10-31, proposed P-IMP-266):** the SessionStart scan takes about 52 s against the hook's `timeout 2`, so the findings feed has been frozen since 2026-09-09 (the file's mtime is the evidence). The P-IMP-264 notification dedup therefore has no visible effect until the scan is incremental (watermark or detached job); repeated notices come from the plugin's task notifications. Regression: `hooks/tests/security-findings-regression.sh` (29 PASS in the 2026-10-31 run; the case count is generated, `framework-inventory.sh`). **Residual (2026-10-31, not closed):** a kill between the OUT append and the SEEN append leaves an orphan row; nothing is lost, but `--to-ledger` refuses until the feed is repaired by hand. Concurrent extractor runs are not locked. NEW 2026-09-09 |
| **graphify hook-guard** (extern) | PreToolUse / `Bash\|Grep` + `Read\|Glob` | **NOT a `hooks/*.sh` script** — invokes the external `graphify` binary (`~/.local/bin/graphify`). Nudges toward `graphify query` instead of raw grep/read WHEN a `graphify-out/graph.json` exists in the project; silent no-op otherwise. Fails open everywhere (exit 0, empty stdout on any error/unknown subcommand). ~37ms/call. Installed 2026-07-31, IMP-109 — see "Graphify" section below. |
| **serena-write-gate.sh** + **serena-post-tool.sh** | PreToolUse + PostToolUse / `mcp__serena__.*\|mcp__plugin_serena_serena__.*` | **Delegating fail-closed gate for Serena WRITE tools (IMP-130, 2026-08-05)** — translates each Serena write call into the native `(file_path, new_string)` shape and runs the SAME inspectors as native Edit/Write (parallel-lock, file-protection, security-audit, config-protection; post: auto-format, EOF check, observation-capture + read tracker). Unknown tool / param drift / missing inspector → deny, never allow; `rename_symbol`/`safe_delete_symbol` → recoverable ask (LSP writes N unnamed files); memory path-escape → deny. Supersedes "read-only by design" (IMP-104); ADR: `docs/adr/0001`. Regression: `hooks/tests/serena-gate-regression.sh` (38 cases; generated 2026-11-10) |
| **knowledge-gate.sh** | (not registered since 2026-11-23; was PreToolUse / `Write\|Edit` and `MultiEdit`) | **Retired from registration 2026-11-23: a lookup before every first write was a preference with many exceptions; kept on disk.** Knowledge-first write gate (IMP-267, 2026-10-31). Placed after `gateguard.sh`. Per agent identity (`agent_id`, else `main`) the first Write/Edit is allowed only when a lookup (`agent-lookup`) or a mirror read (`mirror-read`) is recorded, or the agent has no Bash and received the injected block (`auto-inject`). Otherwise `deny` with the exact lookup command and keyword hints; after 3 denials per identity it lets the edit through with an ESCALATION note. Mode `CLAUDE_KNOWLEDGE_GATE=deny` (default) \| `advisory` \| `off` (logged). Exempt: temp dirs, the knowledge folder, `.rcode/`, `~/.claude/plans/`, `~/.claude/global-observation/`, scratch markdown, fixtures, `.git/`. IMP-268: also accepts a `lead-supplied` record (`allow-lead-supplied`); an unavailable verdict does not satisfy it. Fails open when the library or a script is missing. Log: `~/.claude/global-observation/knowledge-gate.log`. Suite: `hooks/tests/knowledge-gate-regression.sh` |
| **knowledge-record.sh** | (not registered since 2026-11-23; was PostToolUse / `Bash` and `Read\|Grep\|Glob`) | **Not registered since 2026-11-23; kept on disk.** Records the lookup (IMP-267). A Bash command containing `knowledge-lookup.sh` writes an `agent-lookup` record; a path under the mirror writes a `mirror-read` record. Records: `/tmp/knowledge-gate-<session_id>/record-<agent_id\|main>.tsv`. IMP-268: marks knowledge-agent searches in `$STATE_DIR/knowledge-agent-lookups`. Silent. Suite: `hooks/tests/knowledge-gate-regression.sh` |
| **knowledge-inject.sh** | UserPromptSubmit (`--prompt`) / PreToolUse `Task\|Agent` (`--dispatch`) / SubagentStart (`--subagent-start`) | **Automatic lookup delivery (IMP-267).** Registered in all three modes since 2026-11-23; `settings.json` env sets `CLAUDE_KNOWLEDGE_GATE=off` and `CLAUDE_KNOWLEDGE_BRIEF=off`, so a brief without a KNOWLEDGE field is allowed and the queued hits still reach the helper. The description below predates 2026-11-23 for the gate and brief parts; the registration and env settings are current. `--prompt`: for prompts of 8 or more words, adds the top 5 library hits as a `📚 Knowledge (auto-lookup, IMP-267)` block. `--dispatch`: runs the lookup on the subagent brief and queues the block per session; prints nothing, never blocks. `--subagent-start`: injects the queued block plus a mandatory "one lookup before your first Write/Edit" paragraph into the subagent. IMP-268: skips the automatic hits when the Lead cited notes (they stay the floor for a none verdict), exempts the knowledge-agent dispatch, and at `--subagent-start` writes a `lead-supplied` record for the worker (cited or none) only when the queue is unambiguous (exactly one unexpired queued entry of the subagent's type). Two or more: `ambiguous-queue=<n>`, the oldest entry's hits may still be delivered as the floor, but only the plain paragraph is injected and no record is written. When the check lets the 4th attempt through, the hook queues a plain floor entry (`queued-after-escalation`) instead of skipping. Switch `CLAUDE_KNOWLEDGE_INJECT=0` turns off only the automatic hits; the lead-supplied bookkeeping still runs. Log: `~/.claude/global-observation/knowledge-inject.log`. Suite: `hooks/tests/knowledge-inject-regression.sh` |
| **knowledge-mirror-refresh.sh** | SessionStart / `startup` | **Keeps the library snapshot current (IMP-267).** When the mirror's `Last run:` stamp is older than `CLAUDE_KNOWLEDGE_REFRESH_HOURS` (default 24), starts `~/.claude/scripts/knowledge-mirror.sh` detached (lock `<KNOWLEDGE>/mirror/.refresh.lock`, log `<KNOWLEDGE>/eval/mirror-refresh.log`) and prints one line. Switch `CLAUDE_KNOWLEDGE_REFRESH=0`. Suite: `hooks/tests/knowledge-mirror-refresh-regression.sh` |
| **knowledge-brief-check.sh** | (not registered since 2026-11-23; was PreToolUse / `Task\|Agent`) | **Not registered since 2026-11-23, and `CLAUDE_KNOWLEDGE_BRIEF=off` is set in `settings.json` env; kept on disk.** Denies a worker dispatch without a valid KNOWLEDGE field (IMP-268, 2026-11-01).** Uppercase marker, last one outside fences; verdict by precedence; cited paths mirror-only, quoted excerpts verbatim; none needs its `sets:` clause and two distinct knowledge-agent runs (two agent ids) in this session within `CLAUDE_KNOWLEDGE_BRIEF_WINDOW` (default 1800 s); unavailable needs one knowledge-agent dispatch and at least 20 bytes of real content in the reason (spaces, dashes and punctuation do not count); a `.md` inside the `sets:` clause or inside quotes is not a citation; a block over 4000 bytes is denied. The knowledge-agent dispatch itself is exempt. Mode `CLAUDE_KNOWLEDGE_BRIEF=deny` (default) \| `advisory` \| `off`; a 3-denial breaker then escalates with an ESCALATION context, as in the knowledge gate. Fails open when the library is missing. Parser: `hooks/lib/knowledge-brief.sh`. Log (6 TSV fields): `~/.claude/global-observation/knowledge-brief.log`. Suite: `hooks/tests/knowledge-brief-check-regression.sh` |
| **goal-prompt.sh** | UserPromptSubmit | **Every task prompt gets a goal on Cockpit card 4 (IMP-289, 2026-11-11).** For a non-automated prompt of at least `CLAUDE_GOAL_MIN_WORDS` words (default 8) it writes a goal seed (the start of the prompt, one line) through `scripts/goal.sh` and prints the plan instructions: atomic issues with minute estimates, milestones along research, plan, develop, test, deploy, `"fixed": true` for machine time. A prompt that arrives while a goal has open issues keeps the goal and is kept as a `new-prompt` note in the deviation list (the user's own input: never raised at the stop, not counted on the card). Switch `CLAUDE_GOAL_TRACKING=0`; scheduled routines run with it set (`scripts/routine-run.sh`), because they carry their plan in their SKILL.md and have no one to report to at the end of a turn. State: `~/.claude/global-observation/goals/<session>.json` (`CLAUDE_GOAL_DIR`; the folder holds the start of each prompt and is git-ignored). Always exits 0 |
| **goal-track.sh** | PostToolUse / `Edit\|Write\|MultiEdit\|Bash\|Task\|Agent` · PreToolUse / `Task\|Agent` · SubagentStart · SubagentStop | **Keeps the goal card current (IMP-289) and shows the helpers (IMP-277).** After an edit it records the written file and flags it once as an `undeclared-file` deviation when it lies outside every declared issue path; every other matched tool call refreshes the card at most every 30 s, so the time to goal moves while work runs. A dispatch is queued with title, type, model and effort; the start event of the helper (it carries only id and type) takes the newest queued dispatch of its type and becomes a running row (a best-effort pairing), the stop event closes that row with its duration, and a denied dispatch expires after 300 s (`scripts/lib/goal_agents.py`). Helper rows work in a session without a goal. Silent on stdout, always exits 0 |
| **goal-stop.sh** | Stop | **Raises what was not reported (IMP-289).** Blocks the end of a turn once per state when deviations are unacknowledged or an issue is still marked as running, and prints them for the report; passes when `stop_hook_active` is set. Model, pace and time to goal: `scripts/lib/goal_core.py`; Cockpit feed through the existing task events: `scripts/lib/goal_feed.py`. The terminal card shows four rows of 26 characters and starts at the first unfinished row, so the first four rows are a fixed summary in this order: goal, time to goal (`ETA 09:30 · 14m · 33%`), current step (`6m/30m · I2 …`), deviations (`2 deviations · 2 open · …`); issue, deviation and helper rows follow, and a finished goal keeps only the summary. CLI `scripts/goal.sh` (`plan`, `start`, `done`, `add`, `drop`, `deviate`, `ack`, `status`). Suite: `hooks/tests/goal-tracking-regression.sh` |

> Table shows a curated subset of the registered hooks — the others are infrastructure (parallel-lock-check, config-protection, stop-batched-checks, postbash-failure-recovery, notification-tts, subagent-lock-release, sandbox-guard, session-handoff-write). `line-limit-check.sh` is present but unregistered (folded into `stop-batched-checks.sh`). Not registered since 2026-11-23 (scripts and suites stay on disk): gateguard, pretool-auto-read, posttool-track-read, parallel-analyze-prompt, controller-first-prompt-gate, dispatch-specialist-check, git-identity-enforce, knowledge-gate, knowledge-record and knowledge-brief-check; the Bash echo and reminder one-liners were removed as well, because stdout of a hook on exit 0 does not reach the model. Counts: `~/.claude/scripts/framework-inventory.sh`; full registration: `settings.json`. Regression suites — **counts are GENERATED since IMP-205 (2026-09-09): `framework-inventory.sh --json | jq .test_suites`** (static analysis, never executes a suite; `cases:null` + `note` where it cannot be sure). The numbers below are the 2026-09-09 snapshot and WILL drift — four of them had already drifted when the generator was built (serena 35→37, gate 73→147, parallel-lock 12→14, deploy 20→49): `hooks/tests/gate-regression.sh` (169, IMP-076/163/193/209), `web-fetch-gate-regression.sh` (100, IMP-088/117/203), `parallel-lock-regression.sh` (14, IMP-114), `serena-gate-regression.sh` (37, IMP-130), `session-end-staleness-regression.sh` (22, IMP-138/164/192), `routine-liveness-regression.sh` (13, IMP-191), `background-watchdog-regression.sh` (22, IMP-198 + 2026-09-23 three-state fix), `scripts/tests/gather-scripts-regression.sh` (R.Code gather scripts + plan tracker, NEW 2026-09-23), `scripts/tests/command-contract-lint-regression.sh` (26 incl. the tree case, NEW 2026-09-23), `scripts/tests/routine-run-regression.sh` (15, IMP-189/190), `deploy-regression.sh` (49, IMP-127/194).

> ⚠️ **Inventory blind spot (IMP-109):** `framework-inventory.sh` counts `hooks (registered)` as *unique `*.sh` paths in `settings.json`*. The two **graphify** PreToolUse entries invoke a binary, not a `.sh`, so they are **invisible** to that count — it reports the unique-script count (generated 2026-11-10: 49 in the workshop) while `settings.json` actually holds **73 hook entries** (measured 2026-11-10 with `jq`; not an inventory count) (the gap is also inflated by inline `echo`/shell one-liners and by hooks registered under more than one matcher, e.g. `web-fetch-safety-gate.sh` under three). Any future non-`.sh` hook has the same blind spot. `settings.json` remains the only complete registration truth.

#### Bypass tokens (four distinct scopes — do not confuse)

| Token | Scopes | Semantics |
|-------|--------|-----------|
| `CLAUDE_GUARD_OVERRIDE` | `guard-unsafe.sh` | One-shot, inline-from-command-string, logged. Approves a single guarded command. |
| `CLAUDE_AGENCY_ACK_ONCE=<sha256>` | `excessive-agency-gate.sh` (the bash gate) | Op-bound + single-use + inline-visible + logged (`authorizer=user`). The sha is computed over the normalized (data-stripped, whitespace-collapsed) op signature; a mismatch logs `ack-mismatch` and still blocks; a replay re-blocks. **Replaces the old `CLAUDE_GATEGUARD_OFF` for the bash gate** (that flag was read from the hook's own env, fired before any inline `export`, and never worked inline; it was also a session-wide kill-switch — a prompt-injection-escalatable hole). |
| `CLAUDE_CONFIG_PROTECT_OFF` | `config-protection.sh` | Recoverable override for protected-config edits. |
| `CLAUDE_VAULT_GATE_OFF` | `vault-write-gate.sh` (IMP-219) | Session-scoped bypass for the vault write gate only — logged with file + timestamp, never the term. Does not affect `scripts/git-hooks/pre-commit`, which has no bypass token (a foreign-tool write still passes through it on the next commit). |

> `CLAUDE_GATEGUARD_OFF` now scopes **only** `gateguard.sh` (the reversible Edit/Write first-touch investigation prompt, unregistered since 2026-11-23); it no longer disables the bash gate. The bash gate's working escape is the op-bound `CLAUDE_AGENCY_ACK_ONCE` above; a persistent disable would live in `settings.json` `env`, not a bare inline `export`.

### Observation Pipeline (Self-Improvement, 2026-04)

The archived `improvement-agent` (2026-01-17) is replaced by a lightweight hook + on-demand skill pair:

```
Edit/Write ─▶ PostToolUse ─▶ observation-capture.sh ─▶ signals.jsonl
                                                            │
Session End ─▶ Stop ─▶ session-end-check.sh ─▶ session-metrics.jsonl
                                                            │
                                        (threshold crossed) ▼
                            "Run the meta-observer skill to extract patterns"
                                                            │
      User invokes the meta-observer skill ─▶ meta-observer skill (Opus, fork)
                                                            │
                                        ┌───────────────────┴─────────────────────┐
                                        ▼                                         ▼
                          ~/.claude/plans/meta-proposal-*.md          MCP Memory (Pattern entities)
                                        │
                                        ▼ (after review)
                          /pattern-document skill ─▶ ~/.claude/rules/*.md
                          /lessons command ─▶ CLAUDE.md / CONVENTIONS.md updates

  ── write-back, IMP-112 (2026-08-01) ────────────────────────────────────────
  weekly-improve ─▶ ledger-append-proposed.sh ─▶ improvement-ledger.json
                                                  (status:"proposed" ONLY)
                                                            │
  Session End ─▶ session-end-check.sh Reminder 7 ─▶ "N proposed IMPs awaiting
                                                     triage" (escalates at 14d)
                                                            │
                                        human triage ──────▶ proposed → implemented
```

> **Why the write-back exists:** weeks 27–30 produced **25 findings and 0 ledger entries**. The loop
> reliably wrote proposals and reliably logged its runs; nothing downstream consumed them — so a
> one-word fix (the `zcat` defect) sat unapplied for a week and then broke the next run. A loop that
> reads but never writes back is indistinguishable from no loop at all.
>
> **Trust boundary — do not widen it:** `ledger-append-proposed.sh` writes `status:"proposed"` and
> nothing else. It never promotes to `implemented` and never applies a change. Observation data must
> not write framework governance; a human is the gate. Idempotent via a `sourceProposal` dedup key.

**Key files:** `observation-capture.sh`, `session-end-check.sh`, `meta-observer/SKILL.md`, `ledger-append-proposed.sh`, `dispatch-capture.sh`, `compute-daily-metrics.sh`, `improvement-ledger.json` (v1.2.0).

Pipeline details in IMP-009 of `~/.claude/global-observation/improvement-ledger.json`.

### Scheduled Tasks (live since 2026-06; source-of-truth consolidated 2026-07-03, IMP-087)

**Authoritative definitions:** `~/.claude/scheduled-tasks/<task>/SKILL.md` — the scheduler reads the SKILL.md as prompt at fire time (editing the file updates the task, no re-registration). **Runtime state** (schedule/enabled/lastRunAt): `mcp__scheduled-tasks__list_scheduled_tasks` / `/schedule` skill. The old `routines/*.yaml` templates were REMOVED 2026-07-03 — they were a stale second source of truth (nightly said "disabled" while running nightly).

**Timer mechanism (since 2026-08-22, IMP-135; label made generic since IMP-219, 2026-09-25):** local `launchd` timers, bound to `~/.claude` (not to a workshop-relative or cloud cwd) — templates under `scripts/launchd/routine-<task>.plist.template` (placeholders `__HOME__`/`__LABEL__`), runner `scripts/routine-run.sh <task> [--dry-run]`, installer `scripts/install-routine-timers.sh` renders them to the generic label `com.claude-code.routine-<task>` and unloads the old, user-bound label `com.<user>.claude-routine-<task>` if present (idempotent, checks before installing that `routine-run.sh` already sits in `~/.claude/scripts/`, `--uninstall` to remove). Replaces the unversioned cloud binding to a cwd, valid until 2026-08-02, that a reorganization renamed — 20 days of silent failure with no signal at all. Watchdog against a repeat silent death: a liveness sweep in the quarterly audit plus a session-end alarm decoupled from the routine itself (IMP-138, implemented 2026-08-22 — `session-end-check.sh` alarms purely on `DAYS_STALE` and names the age of the newest shard; regression `hooks/tests/session-end-staleness-regression.sh`, 22 cases since IMP-164 (generated 2026-11-10)).

**Runner startup failure (IMP-189, found and fixed 2026-09-09):** the runner
shipped on 08-22 had **not one single** successful run through 09-09 — 39
failed runs (nightly 18, daily 18, weekly 3), all `runner: claude exited 1`.
Cause: `routine-run.sh` passed the SKILL.md as the argument after `-p`;
its first line, `---`, was read by `claude` 2.1.266's option parser as an
unknown option (`error: unknown option '---`). `--dry-run` never calls
`claude` and structurally could not see this (IMP-190, `proposed`). Fix
c165871: pass the prompt via stdin (`< SKILL.md`), regression
`scripts/tests/routine-run-regression.sh` (9 checks, case D against the
real binary). First ok line for the nightly routine: 2026-09-09 10:37 after
a manual start (3,262 signals rotated, 15 shards and 15 metric day-lines
caught up); the launchd **environment** itself counts as proven only once
the timer-fired run of 2026-09-10 02:05 succeeds. **The IMP-138 alarm line
sat in every session end for the entire outage (counter > 240) and went
unheeded** — a watchdog at session *start* that reads the routine logs
itself is IMP-191/192 (`proposed`). Report:
`plans/meta-proposal-2026-09-09-improvement-run.md`.

| Task | Schedule | Status | Run log (mandatory since IMP-075) |
|------|----------|--------|-----------------------------------|
| daily-docs | 07:10 daily | ⚠️ first run with the repaired runner pending for 2026-09-10 07:10 — 18 failed runs 08-23–09-09 (IMP-189). **Cause of the silent Notion outage fixed 2026-08-04 (IMP-128):** the parent page now sits in `scheduled-tasks/daily-docs/SKILL.md` §B, previously in `NOTION_PARENT_PAGE_ID` — a variable that was never set, because it sat in the unread `settings.local.json`. The step now reports `partial` **with a reason** instead of silently skipping. **Effect still unproven** — the routine has never reached the Notion step since 08-04, due to IMP-189. | `daily-docs-log.jsonl` |
| nightly-observation | 02:05 daily | ✅ ok line 2026-09-09 10:37 (first since 2026-08-02, after 18 failed runs — IMP-189; started manually, timer-fired run 2026-09-10 02:05 pending). Step 2 delegated to `compute-daily-metrics.sh`; Step 2b trims the dispatch meter (IMP-115) | `nightly-obs-log.jsonl` |
| weekly-improve | Sunday 22:06 | ⚠️ next run Sun 2026-09-13 22:06 — 3 failed runs (08-23, 08-30, 09-06, IMP-189), last ok run 2026-07-27. data paths FIXED 2026-07-03; **`zcat`→`gunzip -c` FIXED 2026-08-01 (IMP-110)** — BSD `zcat` read every `.gz` shard as empty with exit 0, so the 2026-07-26 run analysed 1,286 invisible signals; **ledger write-back now mandatory (IMP-112)** | `weekly-improve-log.jsonl` |

A task run that leaves no log line is indistinguishable from one that never fired (fail-loud applies to routines too).

#### Moved from CLAUDE.md on 2026-09-29 (IMP-234)

From `### Scheduled Tasks` (verbatim; CLAUDE.md keeps the SKILL.md-at-fire-time and run-log rules plus a pointer here):

`scheduled-tasks/<task>/SKILL.md` is read as prompt at fire time (editing it updates the task, no re-registration); runtime state: `mcp__scheduled-tasks__list_scheduled_tasks` / `/schedule`. Run by launchd (`scripts/routine-run.sh`, installer `scripts/install-routine-timers.sh`), watched by routine-liveness-check.sh. A run without a log line is indistinguishable from one that never fired.

| Task | Schedule | Run log (mandatory since IMP-075) |
|---|---|---|
| daily-docs | 07:10 daily | daily-docs-log.jsonl |
| nightly-observation | 02:05 daily | nightly-obs-log.jsonl |
| weekly-improve | Sunday 22:06 | weekly-improve-log.jsonl |

### Coordination Protocol (Recommended, not Mandatory)

When the control-agent dispatches subagents for multi-step work, the recommended pattern is:
- **Before action:** Brief intent statement (what + why + expected output)
- **After action:** Concrete results (files changed, decisions made, blockers)

This produces clear audit trails but is **guidance, not enforcement**. Skip for trivial work where overhead exceeds value. See `~/.claude/agents/control-agent.md` for the full protocol.

### R.Code: one entrance + stages (2026-09-23 — "Plan folgt Praxis")

**Start here.** `/team-lead "<directive>"` is THE documented main entrance for all R.Code project
work (and stays the generic controller outside R.Code projects too). It orients on the project
(config, status, agent-log, any open re-entry brief or escalation queue), detects which **Stage**
the directive needs — Plan, Design, Develop, Test, or Launch, never "Phase" (a Phase is a project
milestone; the two words used to be conflated — see the glossary in
`~/.claude/rcode/rules/rcode-workflow.md`) — loads the matching playbook, binds work to open work
units, and dispatches right-sized workers.

`/plan-team` … `/launch-team` remain installed as thin aliases (`/team-lead` with the Stage
forced) — kept as doors because the user types their names as keywords, not because practice runs
through them: across 471 main transcripts, `/team-lead` was invoked **67×** (16 projects) against
**0×** for the five Stage-forced aliases combined (measured 2026-09-23; evidence + rationale in
`docs/adr/0002-rcode-plan-follows-practice.md`).

| Command | Stage |
|---------|-------|
| /plan-team | Plan — product foundation, architecture, roadmap, unit slicing |
| /design-team | Design — UX flows, wireframes, design system, component specs |
| /develop-team | Develop — implement units as vertical slices, incl. unit-local tests |
| /test-team | Test — milestone/RC validation, PR review, safety-net strategy |
| /launch-team | Launch — release, deployment, production operations |
| /team-lead | the single entrance; infers the Stage from the directive + project state when no alias forces one |

Stage playbooks: `~/.claude/rcode/stages/{plan,design,develop,test,launch}.md` — the procedure
content that used to be duplicated 5× across the team commands (the IMP-083 drift class) now lives
here once, read by reference. The backward Stage-jump protocol moved the same day to
`~/.claude/rcode/stages/backward-transitions.md` — no longer an always-loaded rule (see
"Auto-Loaded Rules" above); the playbooks load it when a jump is considered. Supporting doors, all
still valid: `/rcode-onboard` (orient; skill), `/handoff` (session end), setup `/rcode-init` ·
`/brainstorm` · `/rcode-migrate`, planning-into-units `/decompose`, periodic `/status-sync` ·
`/phase-gate <N>` · `/lessons` · `/rcode-upgrade`, protocols `/issue` (the unit protocol —
standalone invocation or dispatched-worker mode) and `/rcode-review` (review protocol),
`/continue` (resume), `/autonomous-overnight`, `/simple-onboard`. (22 commands total; verify with
`framework-inventory.sh`, never by hand — hand-maintained counts drifted in 3 docs, IMP-083.)

> **Released ≠ deployed** (IMP-120, 2026-08-01): these shipped as `claude-rcode` v1.1.0/v1.2.0 on
> 2026-07-26, but only `team-lead.md` was actually installed in `~/.claude/commands/` until
> 2026-08-01 — a session invoking `/plan-team` would simply have failed. All six are installed now.
> Before asserting availability on any machine, check `ls ~/.claude/commands/ | grep -i team`, not
> a doc. A backward Stage-jump requires a documented futility proof — protocol in
> `~/.claude/rcode/stages/backward-transitions.md`.

### R.Code Workflow (for managed projects)

For projects with a `.rcode/` directory, use the R.Code atomic development workflow (full
picture: `~/.claude/rcode/README.md`). The entrance is `/team-lead` above; the table below
documents the supporting commands it calls, plus their standalone use.

**Tracker note:** every project records one of two trackers in `.rcode/config.json` → `tracker`:
**`github`** (work units = GitHub issues, `gh` required) or **`plan`** (work units = `P-NNN`
checkbox lines in `BRAINSTORM.md`, no GitHub needed). `/decompose`, `/rcode-init`, and
`/rcode-migrate` ask once and persist the answer; every other command below reads it. Measured
2026-09-23: of the 5 R.Code-managed projects, one has no git remote at all and one tracks units
as `P-NNN` — GitHub used to be a hard prerequisite everywhere, which those 2 could never satisfy.

| Command | Purpose |
|---------|---------|
| /rcode-init | Initialize a FRESH/greenfield project into R.Code — infrastructure only (rails + short interview, incl. tracker choice), product content stubbed. Greenfield counterpart to /rcode-migrate |
| /brainstorm | Transform app idea → 9 product foundation docs |
| /decompose | Convert BRAINSTORM.md → tracked work units — GitHub issues + milestones (`github` tracker) or `P-NNN` checkbox units in BRAINSTORM.md (`plan` tracker, no GitHub needed) |
| /issue \<unit\> | The unit protocol (Steps 0–9) for one work unit (`#N` or `P-NNN`) — standalone invocation (full protocol incl. branch + PR) or dispatched-worker mode (implementation only; the lead owns branching, status writes, and the merge decision) |
| /phase-gate \<N\> | Verify project Phase N (a milestone) completion before unlocking the next |
| /status-sync | Sync PROJECT-STATUS.md with tracker reality (GitHub, or the plan tracker's BRAINSTORM.md) |
| /handoff | Create context transfer document for next agent |
| /lessons | Extract reusable patterns from completed work |
| /simple-onboard | Fast generic onboarding (any repo) + R.Code-suitability verdict; offers migration — GitHub is no longer required |
| /rcode-migrate | Adopt an existing codebase into R.Code (reverse of /brainstorm + /decompose); missing issue tracker is no longer a hard blocker |
| /rcode-upgrade | Upgrade a deployed project's rails to the current framework version — three-way rule diff, per-file y/n, never clobbers customized rules; commits the applied rail update after one explicit y/n (NEW 2026-07-03, IMP-085; commit behavior changed 2026-09-23 — see `docs/adr/0002-rcode-plan-follows-practice.md`) |
| /rcode-review | R.Code-scoped review command — tracker-aware (GitHub PR, or a local diff against trunk in plan mode). The only review command in R.Code — `/review` never existed |
| /continue | Resume an interrupted task — reads PROJECT-STATUS.md + agent-log + git state, determines the in-progress work unit and Step, resumes from there; non-R.Code fallback (NEW 2026-06-21, IMP-068) |
| /autonomous-overnight | Run a bounded unattended work session — queues irreversible (ESCALATE) ops rather than auto-approving them; writes overnight-report.md + escalation-queue.md (NEW 2026-06-21, IMP-069) |

> **On-ramp for fresh projects:** `/rcode-init` lays the R.Code rails on an empty/greenfield project — it installs the `.rcode/` state, wires the rules into `.claude/rules/` + `CLAUDE.md`, and seeds the `PROJECT-STATUS.md`/`START_HERE.md` bridge files, **without** inventing product content (a short 4-field interview + honest stubs; `scope-manifest` ships `features: []`). It is the greenfield mirror of `/rcode-migrate`: where migrate reverse-engineers from existing code, init scaffolds the rails and hands off to `/brainstorm` (full product foundation) or direct work. Greenfield-only with soft hand-off (detects a substantial existing codebase → recommends `/rcode-migrate`), idempotent (existing scaffold halts/repairs, never clobbers), local-first (GitHub objects stay with `/decompose`; `git init`/commit/remote gated behind one y/n even in autonomous mode).

> **On-ramp for existing projects:** `/simple-onboard` runs on *any* repo (no `.rcode/` required) and assesses whether R.Code fits; if so it offers `/rcode-migrate`, which reverse-engineers the full artifact set (CONVENTIONS, ARCHITECTURE, scope-manifest, PROJECT-STATUS, GitHub labels/milestones) from the existing code + git history. Migrate is hybrid (auto-derives the observable artifacts, interviews for the few intent fields, honestly stubs the unrecoverable rationale per `fail-loud.md`/`slop-prevention.md`), idempotent, forward-only (no history rewrite), and gates all GitHub/commit mutations behind a y/n confirm.

R.Code rails (rules for commits, scope, workflow) are installed per-project by `/brainstorm`
(and `/rcode-init` / `/rcode-migrate`), not loaded globally.

#### Moved from CLAUDE.md on 2026-09-29 (IMP-234)

From `### R.Code` (verbatim; CLAUDE.md keeps the entrance, the Stage names, the tracker field and the command list as one line, and points here for the gates):

For projects with a `.rcode/` directory, use the R.Code workflow. **`/team-lead "<directive>"` is THE entrance** (and the generic controller outside R.Code): picks the **Stage** — Plan, Design, Develop, Test, Launch; never "Phase" (= milestone) — loads its `rcode/stages/` playbook, dispatches. `/plan-team` … `/launch-team` are thin aliases that force their Stage.

Tracker in `.rcode/config.json`: `github` (issues) or `plan` (`P-NNN` in `BRAINSTORM.md`). /decompose, /rcode-init, /rcode-migrate set it; the rest read it.

| Kind | Commands |
|---|---|
| Setup | /rcode-init (greenfield; `git init`/commit/remote behind one y/n even in autonomous mode), /brainstorm, /simple-onboard (any repo; offers /rcode-migrate), /rcode-migrate (GitHub/commit mutations behind y/n) |
| Units | /decompose, /issue \<unit\>, /rcode-review (the only review command — `/review` never existed) |
| Periodic | /status-sync, /phase-gate \<N\>, /lessons, /rcode-upgrade (per-file y/n, never clobbers customized rules) |
| Session | /continue, /handoff, /autonomous-overnight (unattended; queues ESCALATE ops, never auto-approves) |

Rails install per project. 22 commands (verify with `framework-inventory.sh`); /rcode-onboard is a skill. Before asserting availability on any machine, check `ls ~/.claude/commands/ | grep -i team`, not a doc. A backward Stage-jump requires a documented futility proof (`rcode/stages/backward-transitions.md`).

### Key Skills (auto-triggered)

| Skill | Triggers On | Mode |
|-------|-------------|------|
| validate-build | "validate", "check build", "type check" | forked |
| research | "research", "best practices", "API docs" | forked |
| version-control | "git", "commit", "branch", "PR" | forked |
| nextjs-debug | "nextjs debug", "404 error", "hydration" | forked |
| pattern-document | "document pattern", "create rule" | forked |
| documentation | "document", "README", "API docs" | forked |
| scope-check | "scope check", "scope creep", "verify scope" | main |
| rcode-onboard | "onboard", "get started", "what should I work on" | main |
| grilling | "grill me", "stress-test my plan", "löcher mich", "hinterfrag meinen plan" | main |
| prototype | "prototype", "spike", "wegwerf-prototyp", "varianten bauen" | forked |
| resolving-merge-conflicts | merge/rebase conflicts, "merge-konflikt", "konflikt auflösen" | main |

> **Adopted 2026-08-03 from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, IMP-124..126):** the 3 skills above, the `domain-docs-convention` rule (CONTEXT.md + ADRs), the Fowler-smell baseline in `code-reviewer-agent` (Step 4b — automatically carries into all 6 `quality-review` specialists, IMP-125), and the rollout of `disable-model-invocation: true` to the user-scheduled analysis skills `historical-signals`/`historical-signals-v2` (IMP-126 — bringing the total to 5 skills carrying it; `meta-observer` and `migrate-to-skills` had it unnoticed since 2026-05-27 already, and the weekly-improve routine demonstrably still runs regardless: ok runs on 07-12/07-20/07-27 with 4/6/11 findings — the scheduled session reads the SKILL.md as a file, not via the gated invocation path).

### Background Skills (auto-trigger only, hidden from menu)

react-perf-check, tailwindcss-v4-styling, import-fixer, fix-review, orchestration

### Output Style — `Hausbau` (opt-in, not the published default; 2026-09-26)

`~/.claude/output-styles/hausbau.md`, activated via `"outputStyle": "Hausbau"` in `settings.json`
or `/output-style Hausbau`. Every explanation is written in plain language against one sustained
metaphor — planning, building, moving into and maintaining a house — with a **fixed concept↔image
mapping table** so the vocabulary stays stable across sessions instead of being reinvented per
answer. Intended for readers who are not deeply technical (product owners, clients, first-time
founders); facts and numbers stay exact, only the language changes.

| Property | Value |
|---|---|
| Default | **None (plain developer language); opt-in via `/output-style Hausbau`.** The owner's own `settings.json` carries `"outputStyle": "Hausbau"` as a personal runtime preference (same category as `model`/`effortLevel`); publish transform 40 (`publish-transforms.d/40-strip-private-hooks.sh`) strips that key on release, so a fresh public install answers in normal developer language until someone opts in. |
| `keep-coding-instructions` | **`true` — load-bearing.** The frontmatter default is `false`, which would strip Claude Code's built-in software-engineering instructions (change scoping, comment discipline, verification). The style changes *how the work is described*, never how it is done — omitting this flag would silently degrade the work itself. |
| Scope | **Main conversation only.** A subagent runs its own system prompt and is unaffected; only the synthesized answer the user reads is styled. A `fork` is the exception (inherits the parent prompt). |
| Activation | Reads at session start — a change takes effect after `/clear` or a new session, not mid-conversation. |
| Precedence | Set at user level; a project-level `outputStyle` would override it (none exists today). |

Non-negotiable inside the style: **facts stay concrete** (numbers, dates, file names are reproduced
verbatim — the image carries the meaning, never replaces the measurement), and **the metaphor may
never soften a defect** — it must make the problem more vivid, not more comfortable. Where a topic
has no honest counterpart in construction, the style requires saying so and explaining directly
rather than forcing the analogy.

### Token Optimization

Context window efficiency — keep agent outputs small so they don't fill up the main context:

- `MAX_THINKING_TOKENS` and `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` were removed from `settings.json` `env` on 2026-11-23. The first had no effect on current models (adaptive thinking is not bounded by it; the reasoning control is `effortLevel`). The second belonged to the context-threshold rule that was removed; the harness compacts on its own.
- `settings.json` `env` (2026-11-23) holds `CLAUDE_CODE_SUBAGENT_MODEL` (kept), `CLAUDE_KNOWLEDGE_GATE=off` and `CLAUDE_KNOWLEDGE_BRIEF=off`. With the brief check off, a brief without a KNOWLEDGE field is allowed, and `knowledge-inject.sh` still queues the automatic hits for the helper.

### Behavioral Directives

1. **Larger builds**: when the request is to build, create or develop something that spans several units, the order is research and plan, design, implementation, checks, with a gate before each next step (`rules/foundation.md`; agents per step in `docs/reference/delegation.md`, "Larger builds").
2. **Delegation per task (since 2026-11-23; replaces the delegate-by-default posture of IMP-055, 2026-06-21)**: The main session decides per task. It works directly when the task is small, sequential or depends on context it already holds; it hands independent, long-output or review units to helpers. The decision rule is in `rules/foundation.md`; dispatch mechanics, model tiers and parallel work are in `docs/reference/delegation.md`. No hook injects a delegation reminder any more (`parallel-analyze-prompt.sh` and `controller-first-prompt-gate.sh` are unregistered), and `CLAUDE_PARALLEL_AUTO_SUGGEST` no longer has an effect.
3. **Multi-agent work**: for work that spans several agents or waves the main session acts as the lead through `/team-lead`; `agents/control-agent.md` holds the full procedure (decomposition, briefs, wave review). Sub-agents never ask the user directly: they report ESCALATE-band operations up, and the lead asks the user once per operation (`rules/agency-bands.md`).
4. **Commit discipline**: Commit every 60 minutes during active development (respects report-only default for research/audit tasks per `workflow-git.md`)
5. **Error recovery**: If an agent reports a blocker → assess → spawn resolution agent → resume
6. **Context hygiene** (advice for the user, not an instruction to the agent, which cannot clear its own session): `/clear` between unrelated tasks.
7. **Routine awareness**: Daily-docs routine writes to Notion at 07:00. Filling in sub-pages during the day is the intended workflow; the routine just provides the scaffold.

### Framework Consolidation 2026-05-24

This framework was consolidated from 3 years of cross-platform configs (Claude Code, Cursor, Antigravity) on 2026-05-24. Backups and working artifacts live on the author's machine. The consolidation found a leaked GitHub PAT (months old, not pushed to GitHub) which was the trigger for the new `security-audit.sh` hook.

---

### Provenance gate, live-drift manifest and review template (2026-10-31)

Surfaces added with the 2026-10-31 meta-proposal (P-IMP-260…265; ledger ids
IMP-260…265, see `global-observation/improvement-ledger.json`
`metaProposal_2026-10-31`). Counts are generated (`framework-inventory.sh`).

| Artifact | Kind | What it does |
|---|---|---|
| `scripts/provenance-check.sh` | script (IMP-262) | Third-party provenance gate. Every file with an origin marker (an origin field, an adapted-from note, a parenthesised license name, or a license identifier tag) needs a `skills/THIRD-PARTY-NOTICES.md` `##` section that names the upstream, carries the full license text and a Copyright line; exit 2 on a miss. Two inline annotation tokens (`not-adopted` and `own`, spelled out in the script header) mark a mention rather than an adoption, but only when they sit on the marker's own line; an annotation counts only when its file and token are registered in the `## Non-adoptions (provenance annotations)` section of `skills/THIRD-PARTY-NOTICES.md`; an unregistered one is reported as `UNREGISTERED ANNOTATION <file>:<line>` (exit 2) and suppresses nothing, and registered hits are counted as `N annotated (registered)`, never dropped silently. Wired into `scripts/publish.sh` step 5b (`--all-files`, aborts on a miss). |
| `scripts/tests/provenance-check-regression.sh` | suite | Fixture trees per case. The real-workshop case requires exit 0. |
| `live-only-manifest.txt` | tracked manifest (IMP-263) | Globs exempt from the live-drift report: installer- or plugin-owned paths (`skills/synced/`, `plugins/synced/`, `plugins/store/`). Nested git repos (cockpit) are not listed here: the drift check skips them on its own, and this file is also the security-findings vendor list. Everything else untracked under a governed directory is adopt-or-list material. |
| `scripts/deploy-to-live.sh --drift-check` | mode (IMP-263) | Report-only live-drift check without a deploy. Described under *Two locations* above. |
| `scripts/tests/live-drift-regression.sh` | suite | Covers the drift report, manifest exemptions and escalation. |
| `templates/review-page.md.template` | template (P-IMP-261) | Review-page skeleton for requests with a universal quantifier (alle/all/jede/every): coverage line `shown N of M — excluded: …` first, total count last. Referenced by `skills/scope-check/SKILL.md` § Presentation Mode. |
| `hooks/tests/background-agent-check-regression.sh` | suite (P-IMP-260) | Pins the Stop NOTE: present exactly when a helper of the session is open, not age-gated, absent from UserPromptSubmit. |

### Knowledge-first gate and automatic lookup (2026-10-31, IMP-267)

Surfaces added so that the cross-project knowledge library (Obsidian mirror, `docs/OBSIDIAN.md` Stage 3) is consulted by agents and subagents: measured lookup use had been 3 of 585 top-level sessions and 0 of 598 subagent transcripts. Ledger section `knowledgeFirst_2026_10_31`. Counts are generated (`framework-inventory.sh`).

**Status since 2026-11-23:** the write gate `knowledge-gate.sh`, the recorder `knowledge-record.sh` and the brief check `knowledge-brief-check.sh` are no longer registered; their scripts stay on disk. Library hits still arrive automatically through `knowledge-inject.sh` (prompt, dispatch and subagent start), and the knowledge round is no longer mandatory. The table below and the paragraphs of the next section describe the 2026-10 and 2026-11 state and are kept as history.

| Artifact | Kind | What it does |
|---|---|---|
| `hooks/knowledge-gate.sh` | hook (IMP-267) | PreToolUse gate on the first Write/Edit of each agent identity; deny with a 3-denial breaker. Described under *Hooks*. |
| `hooks/knowledge-record.sh` | hook (IMP-267) | PostToolUse recorder of lookup runs and mirror reads (`/tmp/knowledge-gate-<session_id>/`). |
| `hooks/knowledge-inject.sh` | hook (IMP-267) | Three modes (`--prompt`, `--dispatch`, `--subagent-start`): top library hits for prompts and subagent briefs. |
| `hooks/knowledge-mirror-refresh.sh` | hook (IMP-267) | SessionStart: rebuilds the mirror detached when its stamp is older than 24 hours. |
| `hooks/tests/knowledge-gate-regression.sh` | suite | Gate modes, breaker, exemptions, records. |
| `hooks/tests/knowledge-inject-regression.sh` | suite | Prompt, dispatch and subagent-start injection; fail-open paths. |
| `hooks/tests/knowledge-mirror-refresh-regression.sh` | suite | Refresh threshold, lock and switch. |
| `scripts/lib/knowledge-lookup-fields.sh` | fix (IMP-267) | Locale fix: the lookup aborted with `cut: Illegal byte sequence` under `de_DE.UTF-8`; cases in `scripts/tests/knowledge-lookup-regression.sh`. |

### Lead-supplied knowledge for worker briefs (2026-11-01, IMP-268)

**Status since 2026-11-23:** the knowledge round is no longer mandatory and the brief check is not registered. When a unit touches an area with history, the Lead runs one lookup and puts fitting notes with their paths into the brief; the template keeps the KNOWLEDGE field as optional. The paragraph below is the 2026-11-01 state.

The Lead runs a **knowledge round** before every worker dispatch: it writes 2–4 keyword sets, the read-only `knowledge-agent` (haiku) returns verbatim excerpts with paths, and the Lead judges relevance on them. The verdict goes into the brief's sixth field, KNOWLEDGE: cited, none (its `sets:` clause and two distinct knowledge-agent runs) or unavailable (one dispatch, at least 20 bytes of real content in the reason). `hooks/knowledge-brief-check.sh` denies a dispatch without a valid field; the template holds the full rules. A cited or none verdict satisfies the IMP-267 gate for the worker through a `lead-supplied` record; an unavailable verdict does not. **Ambiguous queue:** at SubagentStart exactly one unexpired queued entry of the subagent's type is attributed; two or more are ambiguous (`ambiguous-queue=<n>`), so no `lead-supplied` record is written and the worker looks up on its own. Lead advice: keep only one same-type worker pending at a time per wave. **Bookkeeping with retrieval off:** `CLAUDE_KNOWLEDGE_INJECT=0` or a missing lookup script switch off only the automatic hits; queue, paragraph and record still run, so a cited brief still satisfies the gate. Only a missing library disables everything. **Escalation:** when the check lets the 4th attempt through, the injection hook queues a plain floor entry (`queued-after-escalation`) instead of skipping. Decision and trade-offs: `docs/adr/0010-lead-supplied-knowledge-for-worker-briefs.md`. Glossary: `CONTEXT.md` (Knowledge round, KNOWLEDGE field, Lead-supplied).

| Artifact | Kind | What it does |
|---|---|---|
| `agents/knowledge-agent.md` | agent (IMP-268) | Haiku, read-only; runs the lookup with the Lead's sets and returns verbatim excerpts. Never judges or paraphrases. |
| `hooks/lib/knowledge-brief.sh` | shared parser (IMP-268) | Parses the KNOWLEDGE field of a brief and decides its verdict (`kb_decide`) for the brief check, the inject hook and their suites. |
| `hooks/lib/knowledge-inject-lib.sh` | shared helpers (IMP-268) | The inject hook's paragraph texts (with Bash-less variants), queue helpers with the ambiguity rule, and the Bash-less rule. |
| `hooks/knowledge-brief-check.sh` | hook (IMP-268) | PreToolUse `Task\|Agent`: deny, advisory or off (`CLAUDE_KNOWLEDGE_BRIEF`). Described under *Hooks*. |
| `hooks/tests/knowledge-brief-check-regression.sh` | suite (IMP-268) | Verdict precedence, marker rules, mirror-only cited paths, verbatim excerpt check, 4000-byte block limit, search window, reason length, knowledge-agent exemption, breaker, fail-open. |
| `templates/auftragsbrief.md.template` | template (IMP-268) | Sixth mandatory field KNOWLEDGE, with its three forms. |
| `commands/team-lead.md` §3 | command spec (IMP-268) | The knowledge round before the first worker dispatch of a wave; the wave's verdict count line. |
| `agents/control-agent.md` §2 | agent spec (IMP-268) | The same knowledge round for planner and sub-agent form; the brief's KNOWLEDGE field. |
| `rules/foundation.md` | rule (IMP-268) | One bullet: the Lead runs the knowledge round before every dispatch. |
| `docs/adr/0010-lead-supplied-knowledge-for-worker-briefs.md` | ADR (IMP-268) | Decision, consequences, what to measure after two weeks. |
| `hooks/knowledge-inject.sh`, `hooks/knowledge-record.sh`, `hooks/knowledge-gate.sh` | hook extensions (IMP-268) | Skip automatic hits when cited; `--dispatch` reaches the same verdict as the check (shared parser `hooks/lib/knowledge-brief.sh`) and keeps the bookkeeping when retrieval is off; exempt the knowledge-agent; `lead-supplied` record; knowledge-agent search marks; gate acceptance. Described in the hook rows above. |

---

## Moved from CLAUDE.md on 2026-11-10 (context diet)

History. Entries in this section that describe mechanisms since retired (delegate by default, the two token-threshold settings, the knowledge gate) are superseded by the current sections above, updated on 2026-11-23.

Verbatim text removed from the auto-loaded `CLAUDE.md` in the context diet; the file keeps a short replacement for each section. Each block carries its original heading.

**Original heading: System Architecture — first paragraph (replaced)**

**Counts are GENERATED, never hand-maintained:** `scripts/framework-inventory.sh`. **Rules is the one count that differs by location — state both, never one:** workshop 21 tracked, live install 24 after `claude-deploy` (+3 git-ignored `*.local.md`). Inventory/history (incl. key files and archived agents): `docs/FRAMEWORK-REFERENCE.md`; architecture: `HARNESS.md`; changes: `global-observation/improvement-ledger.json`.

**Original heading: ### Skills**

Demoted rules live as on-demand skills — load them on their topic: legacy-codebase-audit, rcode-ios, framework-extraction, kokonutui-pro (IMP-079); release-cli-discipline, cloud-cli-discipline (IMP-218). Forked, haiku (IMP-255): pattern-document, documentation, scroll-animation-patterns; quality-review inherits, its 6 specialists are haiku. Background, auto-trigger only: react-perf-check, tailwindcss-v4-styling, import-fixer, fix-review, orchestration. Full list with modes: `docs/FRAMEWORK-REFERENCE.md` §Forked Skills.

**Original heading: #### Bypass tokens (three distinct scopes — do not confuse) — table**

| Token | Scopes | Semantics |
|-------|--------|-----------|
| `CLAUDE_GUARD_OVERRIDE` | `guard-unsafe.sh` | One-shot, inline-from-command-string, logged. Approves a single guarded command. |
| `CLAUDE_AGENCY_ACK_ONCE=<sha256>` | `excessive-agency-gate.sh` (the bash gate) | Op-bound, single-use, inline-visible, logged (`authorizer=user`); contract: [[agency-bands]]. Replaces the old `CLAUDE_GATEGUARD_OFF` for the bash gate — that flag scopes only `gateguard.sh`; a persistent disable would live in `settings.json` `env`, not an inline `export`. |
| `CLAUDE_CONFIG_PROTECT_OFF` | `config-protection.sh` | Recoverable override for protected-config edits. |

**Original heading: ### Observation Pipeline — paragraph (sentence about `/meta-observe` replaced)**

Signals feed `/meta-observe` proposals; weekly-improve writes back. **Trust boundary — do not widen it:** `ledger-append-proposed.sh` writes only `status:"proposed"` — never promotes to `implemented`, never applies a change; observation data must not write framework governance, a human is the gate.

**Original heading: ### Scheduled Tasks**

`scheduled-tasks/<task>/SKILL.md` is read as prompt at fire time (editing it updates the task, no re-registration); runtime state: `mcp__scheduled-tasks__list_scheduled_tasks` / `/schedule`; every run must leave a run-log line (IMP-075) — else it is indistinguishable from one that never fired. Schedules, runner: `docs/FRAMEWORK-REFERENCE.md` §Scheduled Tasks.

**Original heading: ### R.Code**

Projects with a `.rcode/` directory use the R.Code workflow. **`/team-lead "<directive>"` is THE entrance** (also the generic controller outside R.Code); it picks the **Stage** (Plan, Design, Develop, Test, Launch — never "Phase", a milestone); `/plan-team` … `/launch-team` force their Stage. Tracker in `.rcode/config.json`: `github` (issues) or `plan` (`P-NNN` in `BRAINSTORM.md`), set by /decompose, /rcode-init, /rcode-migrate. Rails install per project. 22 commands (verify with `framework-inventory.sh`); /rcode-onboard is a skill. Before asserting availability on any machine, check `ls ~/.claude/commands/ | grep -i team`, not a doc. A backward Stage-jump requires a documented futility proof (`rcode/stages/backward-transitions.md`). Commands: /rcode-init, /brainstorm, /simple-onboard, /rcode-migrate, /decompose, /issue \<unit\>, /rcode-review (the only review command — `/review` never existed), /status-sync, /phase-gate \<N\>, /lessons, /rcode-upgrade, /continue, /handoff, /autonomous-overnight. Each command's y/n gates: `docs/FRAMEWORK-REFERENCE.md` §R.Code.

**Original heading: ### Output Style — Hausbau (personal preference, opt-in)**

`output-styles/hausbau.md` — house-building metaphor for readers who are not deeply technical — is the owner's runtime preference, not a framework default (publish transform 40 strips `outputStyle` on release; opt in with `/output-style Hausbau`). `keep-coding-instructions: true` is load-bearing: `false`, the default, strips the built-in engineering instructions. Main thread only, read at session start; a project-level `outputStyle` overrides it. Facts stay concrete; the metaphor never softens a defect; where construction has no honest counterpart, say so and explain directly.

**Original heading: ### Token Optimization**

*Superseded on 2026-11-23: both settings were removed from `settings.json` and the context-threshold rule no longer exists. Kept as history.*

`MAX_THINKING_TOKENS=30000` is inert for the Haiku 5.5 worker default (adaptive thinking is always on and not bounded by it); the reasoning control is `effortLevel`. Auto-compact at 90% (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`) — but per `context-engineering.md`, reaching 92% is treated as a process failure, not normal flow.

**Original heading: ### Behavioral Directives (compressed to one line per item)**

*Superseded on 2026-11-23 by the "Behavioral Directives" list further up. Kept as history.*

### Behavioral Directives

1. **Development recognition:** build/create/develop → 5-phase workflow (`rules/foundation.md`).
2. **Delegate by default** — you orchestrate, agents execute (specialized agents for heavy implementation, forked skills for diagnostics/utilities); skip-list: `rules/foundation.md`; 2+ independent units: `parallel-by-default.md`; opt-out `CLAUDE_PARALLEL_AUTO_SUGGEST=0`.
3. **Multi-domain work:** 3+ agents → `control-agent` first, the Autonomy Arbiter — sub-agents never ask the user directly ([[agency-bands]]); recommended, not mandatory: brief intent before action (what + why + expected output), concrete results after (files changed, decisions, blockers).
4. **Commit discipline:** every 60 min; report-only default per `workflow-git.md`.
5. **Error recovery:** blocker → assess → spawn resolution agent → resume.
6. **Context hygiene:** `/clear` between unrelated tasks.
7. **Routine awareness:** daily-docs writes a Notion scaffold, filled during the day.

**Original heading: Hooks paragraph (gate list shortened; full list in the reference doc)**

`settings.json` is the only complete registration truth (the non-`.sh` graphify hook-guard is invisible to `framework-inventory.sh`). Gates a session will meet: guard-unsafe, excessive-agency-gate, mcp-agency-gate, web-fetch-safety-gate, security-audit, vault-write-gate, file-protection, config-protection, pretool-auto-read, gateguard, serena-write-gate, dispatch-specialist-check, git-identity-enforce, git-state-check. Full table + suites: `docs/FRAMEWORK-REFERENCE.md` §Hooks.

**Original heading: READ THIS FIRST banner — points 1 to 3 and the Deploy paragraph (shortened in CLAUDE.md)**

> 1. **Changes go in the workshop only.** An edit to `~/.claude/...` goes live immediately, mid-session, and is lost at the next deploy (fast-forward conflict).
> 2. **You cannot verify your own work in your own session:** rules, hooks, and skills load at session start, so a change takes effect only in a **new** session after `claude-deploy`. Never claim "it works" — write down what the user needs to verify.
> 3. **Always verify what you CAN before reporting done:** call hook scripts and shell tools directly (pipe JSON via stdin, check exit code and output), `jq . settings.json` for syntax, the regression suites under `hooks/tests/`.

> Deploy: `claude-deploy [config|cockpit|all]` — clean workshop only, fast-forward only, effective from the next session. The live install and the Cockpit copy `~/.claude/cockpit` (7 hook entries + the status line point there) stay local and complete — no symlink onto the SSD. Environment values go in the shell (`~/.zshrc`); values that must arrive even without a shell profile go in `settings.json`'s `env` block — **never secrets**, the file is public. The deploy pulls runtime keys (`model`, `effortLevel`, `modelSettings`; IMP-127/194) back into the workshop; runtime data, remotes: `docs/FRAMEWORK-REFERENCE.md` §Two locations; conventions + acceptance protocol: `docs/WORKING-IN-THIS-REPO.md`.

**Original heading: `### Agents (Task tool)` — roster paragraph (shortened in CLAUDE.md)**

Roster with models: `docs/FRAMEWORK-REFERENCE.md` §Agents; each agent's use-when is its `agents/*.md` description; the Need → Agent map is in `rules/foundation.md`. pattern-extractor-agent: /lessons Step 6; ad-hoc → `pattern-document` skill.

---

## Graphify — Knowledge-Graph Tool (external, installed 2026-07-31, IMP-109)

**Durable framework note. The `## graphify` section below is TOOL-OWNED and gets overwritten — put nothing here that matters into it.**

`graphify` (PyPI `graphifyy`, CLI `graphify`) turns a codebase + docs/SQL/PDFs into a queryable knowledge graph. Code is parsed locally via tree-sitter AST (no API key, no LLM); doc/PDF semantic extraction needs an API key. Installed globally via `uv tool install graphifyy` → `~/.local/bin/graphify` (+ `graphify-mcp`).

| Fact | Detail |
|---|---|
| Install scope | **Global**, applied by hand. `graphify claude install` has **no global mode** — it hard-writes `./CLAUDE.md` + `./.claude/settings.json` in the *cwd only*. The global wiring was replicated manually by calling `claude_install`'s internals against `Path.home()`. Re-running the plain CLI command in a project installs a **second, project-scoped** copy. |
| Hooks added | 2 PreToolUse entries in `~/.claude/settings.json` (`Bash\|Grep` → `hook-guard search`, `Read\|Glob` → `hook-guard read`). See the ⚠️ inventory blind spot above. |
| Mode | **Nudge-only** (installed without `--strict`). Strict mode would DENY the first raw source read per session until a `graphify query` runs — not enabled. Toggle env: `GRAPHIFY_HOOK_STRICT`. |
| Activation | Both hooks are **inert until a `graphify-out/graph.json` exists** in the project. No graph has been built in any project yet — run `graphify .` (or `graphify extract <path>`) to create one. |
| Failure mode | Fails open by design: unknown subcommand, empty stdin, or any exception → exit 0, empty stdout. Verified 2026-07-31. Consistent with `fail-loud.md` only because it is an *advisory* hook, not a gate — it must never block a legitimate tool call. |
| Upkeep | `graphify update .` after code changes (AST-only, free). `graphify uninstall` removes it from all detected platforms. |
| Backups | Pre-install copies: `~/.claude/CLAUDE.md.bak-graphify-*`, `~/.claude/settings.json.bak-graphify-*`. |

> **Known wart:** writing `settings.json` through graphify's Python writer re-encoded existing emoji in unrelated hook commands as `\uXXXX` escapes and dropped the trailing newline (newline restored by hand). Functionally identical after JSON parse; only cosmetic on inspection.
