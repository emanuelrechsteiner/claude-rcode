<!--
Status: ACTIVE
Last Updated: 2026-09-24
Purpose: Full inventory of the framework with its history — moved out of CLAUDE.md verbatim on 2026-09-24 (IMP-217). CLAUDE.md is the signpost since then; this document is read on demand, not loaded every session.
-->
# Framework Reference — Inventory and Chronicle

> Moved out 2026-09-24 (IMP-217). The text below is the unchanged wording of the former CLAUDE.md sections (as of 2026-09-24); the numbers in it are snapshots of their respective date — only `scripts/framework-inventory.sh` still delivers the live inventory counts. The auto-loaded short version lives in `CLAUDE.md`, the architecture in `HARNESS.md`, the repo working rules in `docs/WORKING-IN-THIS-REPO.md`.

## System Architecture

This environment includes auto-loaded rules (`~/.claude/rules/`), commands, skills, agents, hooks, and scheduled tasks. **Exact counts are GENERATED, never hand-maintained** (they drifted in 3 docs simultaneously — IMP-083): run `~/.claude/scripts/framework-inventory.sh` for disk truth (`--json`, `--check key=N` for audits). Snapshot 2026-08-22 (after the Serena write gate, IMP-130/131), rules count corrected 2026-09-23 (`phase-backward-transitions.md` moved out of `rules/`, see above) and again 2026-09-24 (IMP-218 demoted `release-cli-discipline`/`cloud-cli-discipline` to on-demand skills). **Rules is the one count that differs by location — state both, never one:** workshop = **21 rules** (tracked `*.md` in `rules/`, measured via `ls rules/*.md | wc -l` / `CLAUDE_DIR="$PWD" bash scripts/framework-inventory.sh --json | jq .rules` run against the workshop); live install = **24 rules after the next `claude-deploy`** (the same 21 tracked files plus 3 git-ignored `*.local.md` overlays that exist only on the deployed machine and never sync to the workshop — `identity.local.md`, `reminders.local.md`, and a third, more personal overlay whose name is itself a registered vault `<private-layer>` marker (`docs/adr/0003-vault-and-gate.md`) and is deliberately not repeated here — confirmed via `ls ~/.claude/rules/*.local.md`). Remaining counts don't have a workshop/live-install split (measured 2026-09-23 in both via `framework-inventory.sh --json`): 22 commands · 51 skills · 41 hooks on disk / 42 registered · 12 agents · 3 scheduled tasks. Architecture documented in `~/.claude/HARNESS.md`. Token optimization is active via `env` settings.

> **Last major update:** 2026-08-01 — implementation of `meta-proposal-2026-30` (IMP-110..122), 182 regression cases green. **Three findings turned out worse than reported:** the lock registry was not leaking but *self-blocking* (a claim denied the file to its own subagent AND the orchestrator until TTL — write fan-outs were unusable, IMP-114); the ACK-token signature was computed over the *data-stripped* command, so two deletes with different quoted targets shared one signature and a token approved for A also authorized B (IMP-119); and `had_controller_step` alone would have been worthless because the compliant path exits the hook silently (IMP-116). **One reported finding was wrong:** `guard-unsafe.sh` never blocked `grep` — the four overrides were reflex prefixes, now logged as `OVERRIDE-UNNECESSARY` (IMP-118). Also: the weekly loop finally writes back (25 findings across 4 runs had produced 0 ledger entries, IMP-112), `zcat`→`gunzip -c` (BSD `zcat` read `.gz` as empty, hiding 1,286 signals, IMP-110), `agent_invocations` measured for the first time (IMP-115), loopback FPs removed from the web-fetch gate (46% of its log, IMP-117). Report: `plans/imp-triage-2026-08-01.md`. Previous: 2026-07-03 — Fable-5-Metareview (IMP-073..086): ledger backfilled + honest computed metrics, gate regression suite (28 cases) + rm-as-data FP fix, measurement loop closed (verification blocks, /meta --verify operational, staleness escalation), MCP agency gate (`mcp-agency-gate.sh`), rules diet (gate+arbiter → `agency-bands`; 4 micro-rules → `release-cli-discipline`; 4 conditional rules demoted to on-demand skills, ~9K tokens/session saved), model-era refresh (Claude-5 family, window-relative context thresholds), worktree discipline (IMP-070/072), R.Code versioning + `/rcode-upgrade`, drift/restore/retention scripts. Report: `plans/meta-proposal-2026-07-03-fable5-metareview.md`. Previous: 2026-05-27 KB-driven Migration v3.

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
regression: `scripts/tests/deploy-regression.sh` (49 cases, as of
2026-09-09 — generated since IMP-205:
`framework-inventory.sh --json | jq .test_suites`). Since 2026-09-09,
`modelSettings` (per-model effort level, written by `/model` + `/effort`)
is also one of the runtime keys — the deploy failed on exactly this on
09-09 (IMP-194).

> **Dead end (IMP-128, cleared up 2026-08-04):** a `~/.claude/settings.local.json`
> does not solve this — at the **user level**, Claude Code does not read this
> file (the local level only exists per project). Verified by measurement:
> the `NOTION_PARENT_PAGE_ID` entered there is not set in the session
> environment, while the second value in the same file demonstrably comes
> from `~/.zshrc`. The template `templates/settings.local.json.template` has
> been removed; `README.md`, `skills/kokonutui-pro`,
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
| **domain-docs-convention** | **Per-project CONTEXT.md glossary** (coin a term from the 3rd paraphrase onward; code names follow the glossary) **+ atomic ADRs** in `docs/adr/` (one decision per file, immutable, superseded-by instead of edited). Adapted from mattpocock/skills, MIT (NEW 2026-08-03, IMP-124) |

> **Demoted to on-demand skills (IMP-079, 2026-07-03):** `legacy-codebase-audit`, `rcode-ios`, `framework-extraction`, `kokonutui-pro` (+ component index) — their headers were already trigger specs; they now load only when their topics come up (~5.8K tokens/session saved).
>
> **Removed from this table (2026-09-23, "Plan folgt Praxis"):** `phase-backward-transitions` — the backward-jump protocol it documented now lives at `~/.claude/rcode/stages/backward-transitions.md` and is read by the R.Code stage playbooks when a backward jump is considered, not loaded into every session of every project. See `docs/adr/0002-rcode-plan-follows-practice.md`.

### Agents (Task tool — heavy implementation)

| Agent | Model | Use For |
|-------|-------|---------|
| **control-agent** | **fable** (`claude-fable-5-1[1m]`, IMP-092) | **Central orchestrator + Autonomy Arbiter** — the ONE canonical dispatch spec (§2: Agent+Model+Effort per spawn; §4: 2nd-order re-plan checkpoint) — coordinates multi-agent workflows, plans + delegates + synthesizes; sole human-facing escalation point for delegated work (sub-agents report ESCALATE-band ops up to it; it consolidates one verbatim y/n per logical operation per `agency-bands.md`) (new 2026-05-24; arbiter role 2026-06-09; model raised opus→fable + §2/§4 formalized 2026-07-15, IMP-091/092) |
| planning-agent | opus | Architecture, task breakdown, implementation plans |
| backend-agent | sonnet | APIs, database, server logic, authentication |
| testing-agent | sonnet | Unit tests, integration tests, E2E tests |
| code-reviewer-agent | sonnet | Code review (READ-ONLY — cannot edit files) |
| cleanup-agent | haiku | Dead code detection, debug artifact removal |
| ~~ux-agent~~ | ~~sonnet~~ | **Archived 2026-05-27** — replaced by `ux-design` skill (function-duplicate, Skill has identical scope) |
| ui-agent | sonnet | Visual design systems, component specs, component implementation. System prompt depersona-framed 2026-05-27 |
| **visual-qa-agent** | sonnet | **Read-only visual QA in a real browser** (Playwright MCP tools; no Edit/Write, no `browser_run_code_unsafe`) — screenshot/snapshot first, describe what is visible, then judge; compare against the SOURCE (template file, user screenshot), never a paraphrase (`slop-prevention.md` Trigger 3 as its core mandate). Closes the roster gap that ≥6 `AGENTENWAHL:` rationales named in the window 2026-08-24..09-09 (proj-0384c7: 11/11 dispatches went to general-purpose for visual checks). NEW 2026-09-09, IMP-196 |
| **research-agent** | haiku | Documentation/technology research; **can now `Write` a NEW report file** at the path the brief names (never Edit — IMP-197). Lives at `agents/research-agent.md` since 2026-09-09: it had sat in `agents/archived-replaced-by-skills/` while being dispatched **36×** since 2026-08-01 — that folder never archived anything, see IMP-208 below |
| **documentation-agent** | sonnet | **Daily-Docs Routine only** (Mode B → Notion). For ad-hoc docs use `documentation` skill. Mode A removed 2026-05-27. |
| **version-control-agent** | sonnet | **Git discipline** — honors report-only default for research/audit tasks. System prompt depersona-framed 2026-05-27 |
| **pattern-extractor-agent** | sonnet | **`/lessons` Step 6 only** — deep git-commit pattern analysis (learning extraction), spawned via Task tool from `commands/lessons.md`. File lives at **`agents/pattern-extractor-agent.md`** (top level — corrected 2026-08-01). For ad-hoc pattern extraction outside `/lessons`, prefer the `pattern-document` skill instead (documented 2026-07-15, IMP-092, R-4) |
| ~~improvement-agent~~ | ~~sonnet~~ | **Archived 2026-01-17** — replaced by `observation-capture.sh` hook + `meta-observer` skill |

> **The "archive" folder was live (IMP-208, 2026-09-09).** `agents/archived-replaced-by-skills/` never archived anything: Claude Code scans `agents/` **recursively**, so `build-validator-agent`, `framework-specialist-agent` and `research-agent` were all invocable from inside it (the session's agent list proved it), and two files there — `documentation-agent.md`, `version-control-agent.md` — carried the **same `name:`** as the live top-level agents, with undefined precedence (the archived `version-control` copy predates the report-only rule). The only entry that was ever truly silent was `ux-agent.md.2026-05-26` — a renamed extension. Fix: the folder now lives at `docs/archive/agents-replaced-by-skills/` (where `rules/documentation.md` puts archived material and where nothing loads it); `research-agent.md` moved to `agents/`. **To retire an agent, move it OUT of `agents/` or change its extension — a subfolder does nothing.** Acceptance in the next session: `build-validator-agent`/`framework-specialist-agent` must be absent from the agent list, `visual-qa-agent` present.

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
| git-identity-check.sh | SessionStart | Identity guard (single identity: Maintainer — LegacyIdentity retired 2026-06; Claude-Login `<email>` is unrelated to git) |
| guard-unsafe.sh | PreToolUse / Bash | Block destructive commands (rm -rf /, sudo, nc, etc.). **Fix 2026-05-24:** Word-boundary added to nc-regex (was matching `rsync`) |
| git-state-check.sh | PreToolUse / Bash | Check git state before risky operations |
| git-identity-enforce.sh | PreToolUse / Bash | Enforce identity on git commits |
| file-protection.sh | PreToolUse / Write\|Edit | Protect sensitive files |
| **security-audit.sh** | PreToolUse / Write\|Edit | **Block edits introducing secrets** (github_pat_*, ghp_*, AKIA*, sk-*, AIza*, xox*). New 2026-05-24 after PAT-leak finding |
| **vault-write-gate.sh** | PreToolUse / Write\|Edit (also the MultiEdit input shape) | **Blocks a real name/path/account/ID from landing in a versioned file of a framework-repo clone (IMP-219, 2026-09-25)** — checks only the INCOMING text via `scripts/vault/vault.sh check --stdin --as <target>`, the SAME matcher every other consumer uses; a Tresor or structural hit is `exit 2` naming `term → token` on stderr, never the value in the log. Hygiene gate, not the CRITICAL floor: an infrastructure failure (missing `jq`, broken `vault.sh`) fails OPEN with a loud NOTE. Bypass: `CLAUDE_VAULT_GATE_OFF=1` (logged). Also wired as an inspector in `serena-write-gate.sh`, and mirrored for non-Claude-Code writers (`sed`/heredoc/`jq`) by `scripts/git-hooks/pre-commit` (staged content) — the ledger's own append path is gated separately by `scripts/ledger-append-vault-gate.sh`. ADR: `docs/adr/0003`. Regression: `hooks/tests/vault-write-gate-regression.sh` (13 cases) |
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
| **web-fetch-safety-gate.sh** | PreToolUse / `WebFetch\|WebSearch` + `mcp__.*` + `Bash` | **Deterministic danger-gate for research fetching** — auto-allows; escalates to native `ask` only on raw-IP/punycode/shortener/binary-download/creds-in-URL/abused-TLD across native+Firecrawl-MCP+Bash routes. **IMP-117 (2026-08-01):** loopback carve-out (`127.0.0.1`/`::1`/`localhost`/`*.localhost` skip the host-identity checks ONLY — credentials + binary-download still screen them) and a `jq`-built log writer. Pairs with `web-research-trust.md`. **IMP-203 (2026-09-09):** a non-alphabetic last label escalates only for IP-*shaped* hosts (4 dot-segments, or dotless decimal/hex) — `DD.MM.YYYY` dates next to a `curl`/`wget` mention were 2 of 30 escalations in the window. Regression: `hooks/tests/web-fetch-gate-regression.sh` (100 cases). NEW 2026-07-09, IMP-088 |
| **dispatch-capture.sh** | PreToolUse / `Task\|Agent` | **The subagent-dispatch meter** — the only surface that can see a delegation (`observation-capture.sh` matches `Edit\|Write`, so signals.jsonl structurally cannot). Feeds `agent_invocations` in `daily-metrics.jsonl`. Payload is `{ts, session_id, tool, subagent_type, model, run_in_background, isolation}` — deliberately **no prompt** (untrusted + bulky); a missing `model` parameter is logged as `"inherit"`, not `null` (IMP-204 — 51/153 rows were null in the window). No `agent_id` — PreToolUse fires before the runtime assigns one, which is why `background-agent-check.sh` pairs by count. NEW 2026-08-01, IMP-115 — promoted from the expired `q2-probe-dispatch-dump.sh` (now `hooks/archived/`) |
| **git-remote-check.sh** | SessionStart | **Warn when local work has nowhere to go** — repo with 0 git remotes and >N local commits (default 20, `CLAUDE_NOREMOTE_WARN_COMMITS`). Non-blocking, 3 local git calls, no network. NEW 2026-08-01, IMP-122 — generalises a 157-commit/0-remote near-total-loss exposure |
| **routine-liveness-check.sh** | SessionStart | **The reader the routine logs never had** — scans `daily-docs-log`/`nightly-obs-log`/`weekly-improve-log.jsonl`; ≥2 consecutive `status:"error"` runs → a blocker line at session START (routine, count, last error, series start); log older than 2× its interval → "hasn't fired for N days"; silent when healthy or absent; always exit 0. Against the real logs on 2026-09-09 it reported daily-docs 18 and weekly-improve 3 — the 39 failures nobody read (IMP-189) had been visible only to the quarterly audit. Regression: `hooks/tests/routine-liveness-regression.sh` (13). NEW 2026-09-09, IMP-191 |
| **subagent-watchdog.sh** + **background-agent-check.sh** | SubagentStop + UserPromptSubmit/Stop | **Heartbeat for background troops (IMP-198)** — every SubagentStop is logged to `subagent-stops.jsonl` with `stop_reason` and an `abnormal` flag (`stop_reason≠end_turn` or rate-limit/quota/overloaded markers in the last message; preview ≤160 chars, no full messages); `background-agent-check.sh` pairs dispatches against stops per session and, at the next prompt or turn end, prints `⏳ N Hintergrundtrupp(s) ohne Ende-Signal seit M min` (threshold `CLAUDE_BG_STALE_MIN`, default 20) or the preview of an abnormal stop ≤60 min old. Would have said "1 troop without end signal for 5 h 10 min" at the 16:42 "weiter" on 2026-09-01. **Blind spots, by design and documented in the script headers:** a troop that is alive but idle; a crash below the hook layer (no SubagentStop at all); pairing is FIFO by count, not by identity. Regression: `hooks/tests/background-watchdog-regression.sh` (22 since the 2026-09-23 three-state fix — missing `stop_reason` is no longer "abnormal"; 1,515/1,515 logged stops had been false alarms). NEW 2026-09-09 |
| **security-findings-check.sh** (+ `scripts/security-review-findings.sh`) | SessionStart | **The return channel for automatic security reviews (IMP-207)** — the `security-guidance` plugin runs its reviews as separate `sdk-py` sessions ("Review this change for security vulnerabilities …") and delivers findings only as a chat message into a still-living parent session; nothing persisted, so a HIGH finding from 2026-08-24 sat unread for 16 days. The extractor takes each review session's **last accepted** `StructuredOutput` call (rejected schema attempts come first; a session with none is *incomplete*, never *clean*), writes one row per finding to `security-review-findings.jsonl`, dedups by session+index with a watermark, and offers `--since`/`--project`/`--dry-run`/`--ack <session_id>`/`--to-ledger` (proposed only, through `ledger-append-proposed.sh`). The hook runs it incrementally with a time budget and prints one line: `🔐 N ungesichtete Sicherheitsbefunde für <project> (…) — sichten: --ack <session_id>`. **First run (2026-09-09, since 08-24): 173 review sessions, 89 clean, 18 incomplete, 11 findings** — the 08-24 one, two from the same day about the `--location` fix (a parser differential: quoted values are stripped before the regex runs), and 5 never seen before in proj-a07272/proj-0384c7. Also the source of the IMP-200 path-error family — the review prompt names relative paths without a repo root. Regression: `hooks/tests/security-findings-regression.sh` (13). NEW 2026-09-09 |
| **graphify hook-guard** (extern) | PreToolUse / `Bash\|Grep` + `Read\|Glob` | **NOT a `hooks/*.sh` script** — invokes the external `graphify` binary (`~/.local/bin/graphify`). Nudges toward `graphify query` instead of raw grep/read WHEN a `graphify-out/graph.json` exists in the project; silent no-op otherwise. Fails open everywhere (exit 0, empty stdout on any error/unknown subcommand). ~37ms/call. Installed 2026-07-31, IMP-109 — see "Graphify" section below. |
| **serena-write-gate.sh** + **serena-post-tool.sh** | PreToolUse + PostToolUse / `mcp__serena__.*\|mcp__plugin_serena_serena__.*` | **Delegating fail-closed gate for Serena WRITE tools (IMP-130, 2026-08-05)** — translates each Serena write call into the native `(file_path, new_string)` shape and runs the SAME inspectors as native Edit/Write (parallel-lock, file-protection, security-audit, config-protection; post: auto-format, EOF check, observation-capture + read tracker). Unknown tool / param drift / missing inspector → deny, never allow; `rename_symbol`/`safe_delete_symbol` → recoverable ask (LSP writes N unnamed files); memory path-escape → deny. Supersedes "read-only by design" (IMP-104); ADR: `docs/adr/0001`. Regression: `hooks/tests/serena-gate-regression.sh` (37 cases) |

> Table shows a curated subset of the registered hooks — the others are infrastructure (parallel-lock-check, gateguard, pretool-auto-read, posttool-track-read, config-protection, stop-batched-checks, postbash-failure-recovery, notification-tts, parallel-analyze-prompt, subagent-lock-release, sandbox-guard, controller-first-mutation-gate, controller-first-subagent-flag, session-handoff-write). Exactly one on-disk script — `line-limit-check.sh` — is present-but-unregistered (folded into `stop-batched-checks.sh`). Counts: `~/.claude/scripts/framework-inventory.sh`; full registration: `settings.json`. Regression suites — **counts are GENERATED since IMP-205 (2026-09-09): `framework-inventory.sh --json | jq .test_suites`** (static analysis, never executes a suite; `cases:null` + `note` where it cannot be sure). The numbers below are the 2026-09-09 snapshot and WILL drift — four of them had already drifted when the generator was built (serena 35→37, gate 73→147, parallel-lock 12→14, deploy 20→49): `hooks/tests/gate-regression.sh` (169, IMP-076/163/193/209), `web-fetch-gate-regression.sh` (100, IMP-088/117/203), `parallel-lock-regression.sh` (14, IMP-114), `serena-gate-regression.sh` (37, IMP-130), `session-end-staleness-regression.sh` (22, IMP-138/164/192), `routine-liveness-regression.sh` (13, IMP-191), `background-watchdog-regression.sh` (22, IMP-198 + 2026-09-23 three-state fix), `scripts/tests/gather-scripts-regression.sh` (R.Code gather scripts + plan tracker, NEW 2026-09-23), `scripts/tests/command-contract-lint-regression.sh` (26 incl. the tree case, NEW 2026-09-23), `scripts/tests/routine-run-regression.sh` (15, IMP-189/190), `deploy-regression.sh` (49, IMP-127/194).

> ⚠️ **Inventory blind spot (IMP-109):** `framework-inventory.sh` counts `hooks (registered)` as *unique `*.sh` paths in `settings.json`*. The two **graphify** PreToolUse entries invoke a binary, not a `.sh`, so they are **invisible** to that count — it reports 33/33 while `settings.json` actually holds **43 hook entries** (the gap is also inflated by inline `echo`/shell one-liners and by hooks registered under more than one matcher, e.g. `web-fetch-safety-gate.sh` under three). Any future non-`.sh` hook has the same blind spot. `settings.json` remains the only complete registration truth.

#### Bypass tokens (four distinct scopes — do not confuse)

| Token | Scopes | Semantics |
|-------|--------|-----------|
| `CLAUDE_GUARD_OVERRIDE` | `guard-unsafe.sh` | One-shot, inline-from-command-string, logged. Approves a single guarded command. |
| `CLAUDE_AGENCY_ACK_ONCE=<sha256>` | `excessive-agency-gate.sh` (the bash gate) | Op-bound + single-use + inline-visible + logged (`authorizer=user`). The sha is computed over the normalized (data-stripped, whitespace-collapsed) op signature; a mismatch logs `ack-mismatch` and still blocks; a replay re-blocks. **Replaces the old `CLAUDE_GATEGUARD_OFF` for the bash gate** (that flag was read from the hook's own env, fired before any inline `export`, and never worked inline; it was also a session-wide kill-switch — a prompt-injection-escalatable hole). |
| `CLAUDE_CONFIG_PROTECT_OFF` | `config-protection.sh` | Recoverable override for protected-config edits. |
| `CLAUDE_VAULT_GATE_OFF` | `vault-write-gate.sh` (IMP-219) | Session-scoped bypass for the vault write gate only — logged with file + timestamp, never the term. Does not affect `scripts/git-hooks/pre-commit`, which has no bypass token (a foreign-tool write still passes through it on the next commit). |

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

**Timer mechanism (since 2026-08-22, IMP-135; label made generic since IMP-219, 2026-09-25):** local `launchd` timers, bound to `~/.claude` (not to a workshop-relative or cloud cwd) — templates under `scripts/launchd/routine-<task>.plist.template` (placeholders `__HOME__`/`__LABEL__`), runner `scripts/routine-run.sh <task> [--dry-run]`, installer `scripts/install-routine-timers.sh` renders them to the generic label `com.claude-code.routine-<task>` and unloads the old, user-bound label `com.<user>.claude-routine-<task>` if present (idempotent, checks before installing that `routine-run.sh` already sits in `~/.claude/scripts/`, `--uninstall` to remove). Replaces the unversioned cloud binding to a cwd, valid until 2026-08-02, that a reorganization renamed — 20 days of silent failure with no signal at all. Watchdog against a repeat silent death: a liveness sweep in the quarterly audit plus a session-end alarm decoupled from the routine itself (IMP-138, implemented 2026-08-22 — `session-end-check.sh` alarms purely on `DAYS_STALE` and names the age of the newest shard; regression `hooks/tests/session-end-staleness-regression.sh`, 15 cases since IMP-164).

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
