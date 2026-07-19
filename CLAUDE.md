# Claude Code — Development Framework

> You orchestrate, agents execute. Use specialized agents for heavy implementation and forked skills for diagnostics/utilities.

## System Architecture

This environment includes auto-loaded rules (`~/.claude/rules/`), commands, skills, agents, hooks, and scheduled tasks. **Exact counts are GENERATED, never hand-maintained** (they drifted in 3 docs simultaneously — IMP-083): run `~/.claude/scripts/framework-inventory.sh` for disk truth (`--json`, `--check key=N` for audits). Snapshot 2026-07-19: 22 rules · 17 commands · 44 skills · 31 hooks on disk / 31 registered · 10 agents · 3 scheduled tasks (`CLAUDE_DIR=<repo-root> bash scripts/framework-inventory.sh`; the script defaults to `~/.claude` and only counts this tree when pointed at it explicitly). Architecture documented in `~/.claude/HARNESS.md`. Token optimization is active via `env` settings.

> **Framework evolution:** this doc, and the rules/hooks/agents it describes, evolve through the framework's own self-improvement loop (see "Observation Pipeline" below) — proposals are synthesized from accumulated session friction, reviewed, then landed as rule or hook changes. Recent focus areas: an autonomy-band system (`agency-bands`) unifying irreversible-operation gating, a window-relative context-management model that scales across model context sizes, an MCP write-gate, and the R.Code atomic development workflow (`/rcode-init`, `/rcode-upgrade`).

### Auto-Loaded Rules (always in context)

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

> **Demoted to on-demand skills (IMP-079, 2026-07-03):** `legacy-codebase-audit`, `rcode-ios`, `framework-extraction`, `kokonutui-pro` (+ component index) — their headers were already trigger specs; they now load only when their topics come up (~5.8K tokens/session saved).

### Agents (Task tool — heavy implementation)

| Agent | Model | Use For |
|-------|-------|---------|
| **control-agent** | **fable** (`claude-fable-5[1m]`, IMP-092) | **Central orchestrator + Autonomy Arbiter** — the ONE canonical dispatch spec (§2: Agent+Model+Effort per spawn; §4: 2nd-order re-plan checkpoint) — coordinates multi-agent workflows, plans + delegates + synthesizes; sole human-facing escalation point for delegated work (sub-agents report ESCALATE-band ops up to it; it consolidates one verbatim y/n per logical operation per `agency-bands.md`) (new 2026-05-24; arbiter role 2026-06-09; model raised opus→fable + §2/§4 formalized 2026-07-15, IMP-091/092) |
| planning-agent | opus | Architecture, task breakdown, implementation plans |
| backend-agent | sonnet | APIs, database, server logic, authentication |
| testing-agent | sonnet | Unit tests, integration tests, E2E tests |
| code-reviewer-agent | sonnet | Code review (READ-ONLY — cannot edit files) |
| cleanup-agent | haiku | Dead code detection, debug artifact removal |
| ~~ux-agent~~ | ~~sonnet~~ | **Archived 2026-05-27** — replaced by `ux-design` skill (function-duplicate, Skill has identical scope) |
| ui-agent | sonnet | Visual design systems, component specs, component implementation. System prompt depersona-framed 2026-05-27 |
| **documentation-agent** | sonnet | **Daily-Docs Routine only** (Mode B → Notion). For ad-hoc docs use `documentation` skill. Mode A removed 2026-05-27. |
| **version-control-agent** | sonnet | **Git discipline** — honors report-only default for research/audit tasks. System prompt depersona-framed 2026-05-27 |
| **pattern-extractor-agent** | sonnet | **`/lessons` Step 6 only** — deep git-commit pattern analysis (learning extraction), spawned via Task tool from `commands/lessons.md`. File lives at `agents/pattern-extractor-agent.md`; for ad-hoc pattern extraction outside `/lessons`, prefer the `pattern-document` skill instead (documented 2026-07-15, IMP-092, R-4) |
| ~~improvement-agent~~ | ~~sonnet~~ | **Archived 2026-01-17** — replaced by `observation-capture.sh` hook + `meta-observer` skill |

### Forked Skills (isolated context — lightweight specialists)

| Skill | Model | Use For |
|-------|-------|---------|
| validate-build | haiku | Quick build/type/lint validation |
| research | haiku | Tech research, API docs, best practices |
| version-control | haiku | Git operations, commits, PRs |
| worktree-consolidate | haiku | Discover + classify all active worktrees, present consolidation plan, gate every merge/push/prune behind y/n (NEW 2026-06-21, IMP-066) |
| nextjs-debug | haiku | Next.js framework diagnostics |
| pattern-document | sonnet | Extract reusable patterns from fixes |
| documentation | sonnet | Technical docs, README, API docs |
| meta-observer | opus | On-demand synthesis of observation signals → IMP proposals (2026-04) |
| memory-index | haiku | Cross-project query layer over 35+ memory dirs (2026-04) |
| scroll-animation-patterns | sonnet | RAF-driven scroll animations, sticky card decks |
| quality-review | sonnet | Milestone-level 6-specialist parallel review (arch/security/perf/testing/maintainability/docs) — deep pre-commit/pre-PR pass (documented 2026-07-03, IMP-083) |
| legacy-codebase-audit / rcode-ios / framework-extraction / kokonutui-pro | — | Demoted from always-loaded rules (IMP-079) — load on-demand via their trigger topics |

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
| git-identity-check.sh | SessionStart | Identity guard — warns when the working directory's expected git identity doesn't match `git config user.name`/`user.email` (see `rules/identity.local.md` for your mapping; the Claude Code login identity is unrelated to git commit identity) |
| guard-unsafe.sh | PreToolUse / Bash | Block destructive commands (rm -rf /, sudo, nc, etc.). **Fix 2026-05-24:** Word-boundary added to nc-regex (was matching `rsync`) |
| git-state-check.sh | PreToolUse / Bash | Check git state before risky operations |
| git-identity-enforce.sh | PreToolUse / Bash | Enforce identity on git commits |
| file-protection.sh | PreToolUse / Write\|Edit | Protect sensitive files |
| **security-audit.sh** | PreToolUse / Write\|Edit | **Block edits introducing secrets** (github_pat_*, ghp_*, AKIA*, sk-*, AIza*, xox*). New 2026-05-24 after PAT-leak finding |
| auto-format.sh | PostToolUse / Edit\|Write | Auto-format after edits |
| post-edit-validate.sh | PostToolUse / Edit\|Write | Validate file post-edit |
| observation-capture.sh | PostToolUse / Edit\|Write | Capture signals for the observation pipeline |
| ~~line-limit-check.sh~~ | (PostToolUse / Edit\|Write) | **Superseded 2026-06-09** — present on disk but NOT registered in `settings.json`; the >400-line warning (per code-quality.md) is folded into `stop-batched-checks.sh` |
| session-end-check.sh | Stop | End-of-session metrics + ledger update |
| **sandbox-guard.sh** | SessionStart | **Warn if YOLO active without sandbox** (Casco YC 7/16-hacked finding). New 2026-05-27 |
| **excessive-agency-gate.sh** | PreToolUse / Bash | **Gate irreversible ops** (force-push, rm -rf, migrations) — exit 2 forces user confirm. New 2026-05-27 |
| **self-critique-log.sh** | Stop | **Append session metadata** (incl. per-session edit count, IMP-082) to `self-critique.jsonl` — consumed by meta-observer since 2026-07-03 |
| **mcp-agency-gate.sh** | PreToolUse / `mcp__.*` | **Deterministic ask-layer for MCP writes** (execute_sql, apply_migration, deploys, calendar/external comms) via native `permissionDecision:ask`. NEW 2026-07-03, IMP-078 |
| **config-drift-check.sh** (scripts/) | Stop | **Warn on config-repo drift**: uncommitted tracked changes >N days or unpushed local commits. NEW 2026-07-03, IMP-084 |
| **web-fetch-safety-gate.sh** | PreToolUse / `WebFetch\|WebSearch` + `mcp__.*` + `Bash` | **Deterministic danger-gate for research fetching** — auto-allows; escalates to native `ask` only on raw-IP/punycode/shortener/binary-download/creds-in-URL/abused-TLD across native+Firecrawl-MCP+Bash routes. Pairs with `web-research-trust.md`. Regression: `hooks/tests/web-fetch-gate-regression.sh`. NEW 2026-07-09, IMP-088 |
| **controller-first-prompt-gate.sh** | UserPromptSubmit | **Fires on every prompt** — detects substantial work, writes the session-scoped `substantial` flag read by the mutation gate, and injects a soft reminder to run Controller-First. NEW 2026-07-15, IMP-089/090 |
| **controller-first-mutation-gate.sh** | PreToolUse / Bash + Write\|Edit | **Deterministic backstop** — blocks non-trivial mutations until some Controller step has run in the session (reads the flags the sibling hooks write). NEW 2026-07-15, IMP-090 |
| **controller-first-subagent-flag.sh** | SubagentStop | **Unlocks the mutation gate** — when a finished subagent's type is `control-agent`, writes the session-scoped `controller-ran` flag for the rest of the session. NEW 2026-07-15, IMP-090 |
| **session-handoff-write.sh** | Stop | **Auto-writes a lightweight handoff doc** to `.rcode/handoff-*.md` when a project has recent commits or signals — cannot archive the chat transcript itself (no client API for that). NEW 2026-06-21, IMP-057 |

> Table shows a curated subset of the registered hooks — the others are infrastructure (parallel-lock-check, gateguard, pretool-auto-read, posttool-track-read, config-protection, stop-batched-checks, postbash-failure-recovery, notification-tts, parallel-analyze-prompt, subagent-lock-release, sandbox-guard). Exactly one on-disk script — `line-limit-check.sh` — is present-but-unregistered (folded into `stop-batched-checks.sh`). Counts: `~/.claude/scripts/framework-inventory.sh`; full registration: `settings.json`. Regression suite for the gates: `hooks/tests/gate-regression.sh` (IMP-076).

#### Bypass tokens (three distinct scopes — do not confuse)

| Token | Scopes | Semantics |
|-------|--------|-----------|
| `CLAUDE_GUARD_OVERRIDE` | `guard-unsafe.sh` | One-shot, inline-from-command-string, logged. Approves a single guarded command. |
| `CLAUDE_AGENCY_ACK_ONCE=<sha256>` | `excessive-agency-gate.sh` (the bash gate) | Op-bound + single-use + inline-visible + logged (`authorizer=user`). The sha is computed over the normalized (data-stripped, whitespace-collapsed) op signature; a mismatch logs `ack-mismatch` and still blocks; a replay re-blocks. **Replaces the old `CLAUDE_GATEGUARD_OFF` for the bash gate** (that flag was read from the hook's own env, fired before any inline `export`, and never worked inline; it was also a session-wide kill-switch — a prompt-injection-escalatable hole). |
| `CLAUDE_CONFIG_PROTECT_OFF` | `config-protection.sh` | Recoverable override for protected-config edits. |

> `CLAUDE_GATEGUARD_OFF` now scopes **only** `gateguard.sh` (the reversible Edit/Write first-touch investigation prompt); it no longer disables the bash gate. The bash gate's working escape is the op-bound `CLAUDE_AGENCY_ACK_ONCE` above; a persistent disable would live in `settings.json` `env`, not a bare inline `export`.

### Observation Pipeline (Self-Improvement, 2026-04)

The archived `improvement-agent` (2026-01-17) is replaced by a lightweight hook + on-demand skill pair:

```
Edit/Write ─▶ PostToolUse ─▶ observation-capture.sh ─▶ signals.jsonl
                                                            │
Session End ─▶ Stop ─▶ session-end-check.sh ─▶ session-metrics.jsonl
                                                            │
                                        (threshold crossed) ▼
                                 "Run /meta-observe to extract patterns"
                                                            │
                User invokes /meta-observe ─▶ meta-observer skill (Opus, fork)
                                                            │
                                        ┌───────────────────┴─────────────────────┐
                                        ▼                                         ▼
                          ~/.claude/plans/meta-proposal-*.md          MCP Memory (Pattern entities)
                                        │
                                        ▼ (after review)
                          /pattern-document skill ─▶ ~/.claude/rules/*.md
                          /lessons command ─▶ CLAUDE.md / CONVENTIONS.md updates
```

**Key files:** `observation-capture.sh`, `session-end-check.sh`, `meta-observer/SKILL.md`, `improvement-ledger.json` (v1.2.0).

Pipeline details in IMP-009 of `~/.claude/global-observation/improvement-ledger.json`.

### Scheduled Tasks (live since 2026-06; source-of-truth consolidated 2026-07-03, IMP-087)

**Authoritative definitions:** `~/.claude/scheduled-tasks/<task>/SKILL.md` — the scheduler reads the SKILL.md as prompt at fire time (editing the file updates the task, no re-registration). **Runtime state** (schedule/enabled/lastRunAt): `mcp__scheduled-tasks__list_scheduled_tasks` / `/schedule` skill. The old `routines/*.yaml` templates were REMOVED 2026-07-03 — they were a stale second source of truth (nightly said "disabled" while running nightly).

| Task | Schedule | Status | Run log (mandatory since IMP-075) |
|------|----------|--------|-----------------------------------|
| daily-docs | 07:10 daily | ✅ live — but `NOTION_PARENT_PAGE_ID` unset → Notion sync silently skipped ("partial") | `daily-docs-log.jsonl` |
| nightly-observation | 02:05 daily | ✅ live (re-enabled 2026-06-21, IMP-049 rotate-signals) | `nightly-obs-log.jsonl` |
| weekly-improve | Sunday 22:06 | ✅ live — data paths FIXED 2026-07-03 (pointed at nonexistent files; ran blind on 2026-06-28) | `weekly-improve-log.jsonl` |

A task run that leaves no log line is indistinguishable from one that never fired (fail-loud applies to routines too).

### Coordination Protocol (Recommended, not Mandatory)

When the control-agent dispatches subagents for multi-step work, the recommended pattern is:
- **Before action:** Brief intent statement (what + why + expected output)
- **After action:** Concrete results (files changed, decisions made, blockers)

This produces clear audit trails but is **guidance, not enforcement**. Skip for trivial work where overhead exceeds value. See `~/.claude/agents/control-agent.md` for the full protocol.

### R.Code Workflow (for managed projects)

For projects with a `.rcode/` directory, use the R.Code atomic development workflow:

| Command | Purpose |
|---------|---------|
| /rcode-init | Initialize a FRESH/greenfield project into R.Code — infrastructure only (rails + short interview), product content stubbed. Greenfield counterpart to /rcode-migrate |
| /brainstorm | Transform app idea → 9 product foundation docs |
| /decompose | Convert BRAINSTORM.md → GitHub issues + milestones |
| /issue \<#\> | Full 9-phase dev workflow for one issue |
| /review \<PR#\> | 10-phase code review with scope verification |
| /phase-gate \<N\> | Verify phase completion before unlocking next |
| /status-sync | Sync PROJECT-STATUS.md with GitHub reality |
| /handoff | Create context transfer document for next agent |
| /lessons | Extract reusable patterns from completed work |
| /simple-onboard | Fast generic onboarding (any repo) + R.Code-suitability verdict; offers migration |
| /rcode-migrate | Adopt an existing codebase into R.Code (reverse of /brainstorm + /decompose) |
| /rcode-upgrade | Upgrade a deployed project's rails to the current framework version — three-way rule diff, per-file y/n, never clobbers customized rules (NEW 2026-07-03, IMP-085) |
| /rcode-review | R.Code-scoped review command (documented 2026-07-03 — was on disk but absent from this table) |
| /continue | Resume an interrupted task — reads PROJECT-STATUS.md + agent-log + git state, determines in-progress /issue and phase, resumes from there; non-R.Code fallback (NEW 2026-06-21, IMP-068) |
| /autonomous-overnight | Run a bounded unattended work session — queues irreversible (ESCALATE) ops rather than auto-approving them; writes overnight-report.md + escalation-queue.md (NEW 2026-06-21, IMP-069) |

> **On-ramp for fresh projects:** `/rcode-init` lays the R.Code rails on an empty/greenfield project — it installs the `.rcode/` state, wires the rules into `.claude/rules/` + `CLAUDE.md`, and seeds the `PROJECT-STATUS.md`/`START_HERE.md` bridge files, **without** inventing product content (a short 4-field interview + honest stubs; `scope-manifest` ships `features: []`). It is the greenfield mirror of `/rcode-migrate`: where migrate reverse-engineers from existing code, init scaffolds the rails and hands off to `/brainstorm` (full product foundation) or direct work. Greenfield-only with soft hand-off (detects a substantial existing codebase → recommends `/rcode-migrate`), idempotent (existing scaffold halts/repairs, never clobbers), local-first (GitHub objects stay with `/decompose`; `git init`/commit/remote gated behind one y/n even in autonomous mode).

> **On-ramp for existing projects:** `/simple-onboard` runs on *any* repo (no `.rcode/` required) and assesses whether R.Code fits; if so it offers `/rcode-migrate`, which reverse-engineers the full artifact set (CONVENTIONS, ARCHITECTURE, scope-manifest, PROJECT-STATUS, GitHub labels/milestones) from the existing code + git history. Migrate is hybrid (auto-derives the observable artifacts, interviews for the few intent fields, honestly stubs the unrecoverable rationale per `fail-loud.md`/`slop-prevention.md`), idempotent, forward-only (no history rewrite), and gates all GitHub/commit mutations behind a y/n confirm.

R.Code rules (commits, scope, workflow) are installed per-project by `/brainstorm`, not loaded globally.

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

### Background Skills (auto-trigger only, hidden from menu)

react-perf-check, tailwindcss-v4-styling, import-fixer, fix-review, orchestration

### Token Optimization

Context window efficiency — keep agent outputs small so they don't fill up the main context:

- Extended thinking capped at **30K tokens** (`MAX_THINKING_TOKENS=30000`) — raised 2026-05-27 from 10K to support Opus 4.7 extra-high effort per Anthropic "Picking the right model" guidance (10K was truncating legitimate reasoning)
- Auto-compact at 90% context usage (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`) — but per `context-engineering.md` rule, reaching 92% is treated as a process failure, not normal flow

### Behavioral Directives

1. **Automatic development recognition**: When user says "build", "create", "develop" → follow the 5-phase workflow in `rules/foundation.md`
2. **Delegate-by-default posture (IMP-055, 2026-06-21)**: For every implementation task, delegate to the appropriate specialized agent rather than executing directly — the main thread acts as control-agent: plan, delegate, synthesize. **Skip-list — do NOT delegate for:** single-file edits, tasks < 2 min, pure Q&A / explanation / conversational turns, work already inside a sub-agent, or when the user named a specific agent. For 2+ independent units, see `rules/parallel-by-default.md` for the dispatch mechanics + confirmation-handshake rules (reversible disjoint file-sets → auto-dispatch with a one-line note; ESCALATE-band op or ambiguous scope → proposal + y/n). The `parallel-analyze-prompt.sh` UserPromptSubmit hook injects this reminder. Opt-out: `CLAUDE_PARALLEL_AUTO_SUGGEST=0`.
3. **Use control-agent for multi-domain work**: When a task spans 3+ specialized agents, invoke `control-agent` first to plan + delegate + synthesize rather than orchestrating manually. The control-agent is also the **Autonomy Arbiter** for delegated work — sub-agents never ask the user directly; they report ESCALATE-band irreversible ops up to the control-agent, which consolidates one verbatim y/n per logical operation per `agency-bands.md`.
4. **Commit discipline**: Commit every 60 minutes during active development (respects report-only default for research/audit tasks per `workflow-git.md`)
5. **Error recovery**: If an agent reports a blocker → assess → spawn resolution agent → resume
6. **Context hygiene**: Run `/clear` between unrelated tasks
7. **Routine awareness**: Daily-docs routine writes to Notion at 07:00. Filling in sub-pages during the day is the intended workflow; the routine just provides the scaffold.

### Framework Consolidation 2026-05-24

This framework was consolidated from 3 years of cross-platform configs (Claude Code, Cursor, Antigravity) on 2026-05-24. Backups and working artifacts live on the author's machine. The consolidation found a leaked GitHub PAT (months old, not pushed to GitHub) which was the trigger for the new `security-audit.sh` hook.
