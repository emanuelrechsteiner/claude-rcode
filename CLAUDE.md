# Claude Code — Development Framework

> ## ⚠️ ZUERST LESEN — dieses Repo existiert an ZWEI Orten
>
> **Bevor du irgendetwas änderst, stelle mit `pwd` fest, wo du bist.**
>
> | `pwd` beginnt mit … | Du bist im … | Was hier gilt |
> |---|---|---|
> | `/Volumes/YourExternalVolume/…/5-AI-APPS/claude-code-config` | **BAUHOF** (Arbeitskopie) | Hier wird entwickelt und committet. Nichts wirkt live. **Das ist der richtige Ort für Änderungen.** |
> | `/Users/your-username/.claude` | **HAUS** (Installation) | Was Claude Code tatsächlich liest. **Hier NICHT von Hand ändern** — nur `claude-deploy` schreibt hierher. |
>
> **Die drei Regeln für Agenten:**
> 1. **Änderungen ausschließlich im Bauhof.** Editierst du `~/.claude/...` direkt, geht die Änderung bei der nächsten Übergabe verloren (Fast-Forward-Konflikt) — und sie wird sofort scharf, mitten in der laufenden Sitzung.
> 2. **Du kannst deine Arbeit NICHT in deiner eigenen Sitzung verifizieren.** Regeln, Hooks und Skills liest Claude Code beim **Sitzungsstart**. Was du änderst, wirkt erst in einer **neuen** Sitzung nach `claude-deploy`. Behaupte niemals „funktioniert" — schreibe, was der Nutzer prüfen muss.
> 3. **Was du trotzdem selbst prüfen kannst:** Hook-Skripte und Shell-Werkzeuge direkt aufrufen (JSON per stdin hineinschieben, Exit-Code und Ausgabe prüfen), `jq . settings.json` zur Syntaxprüfung, vorhandene Regressionssuiten unter `hooks/tests/` laufen lassen. Tu das immer, bevor du fertig meldest.
>
> Vollständige Baustellenordnung inkl. Abnahmeprotokoll: **`docs/WORKING-IN-THIS-REPO.md`**.
> Übergabe ins Haus: `claude-deploy [config|cockpit|all]`.

> You orchestrate, agents execute. Use specialized agents for heavy implementation and forked skills for diagnostics/utilities.

## System Architecture

This environment includes auto-loaded rules (`~/.claude/rules/`), commands, skills, agents, hooks, and scheduled tasks. **Exact counts are GENERATED, never hand-maintained** (they drifted in 3 docs simultaneously — IMP-083): run `~/.claude/scripts/framework-inventory.sh` for disk truth (`--json`, `--check key=N` for audits). Snapshot 2026-08-22 (nach Serena-Write-Gate, IMP-130/131), rules count corrected 2026-09-23 (`phase-backward-transitions.md` moved out of `rules/`, see above). **Rules is the one count that differs by location — state both, never one:** Bauhof = **23 rules** (tracked `*.md` in `rules/`, measured via `CLAUDE_DIR="$PWD" bash scripts/framework-inventory.sh --json | jq .rules` run against the Bauhof); Haus = **25 rules after the next `claude-deploy`** (the same 23 tracked files plus 2 git-ignored `*.local.md` overlays that exist only on the deployed machine and never sync to the Bauhof — confirmed via `ls ~/.claude/rules/*.local.md`). Remaining counts don't have a Bauhof/Haus split (measured 2026-09-23 in both via `framework-inventory.sh --json`): 22 commands · 51 skills · 41 hooks on disk / 42 registered · 12 agents · 3 scheduled tasks. Architecture documented in `~/.claude/HARNESS.md`. Token optimization is active via `env` settings.

> **Last major update:** 2026-08-01 — Umsetzung `meta-proposal-2026-30` (IMP-110..122), 182 regression cases green. **Three findings turned out worse than reported:** the lock registry was not leaking but *self-blocking* (a claim denied the file to its own subagent AND the orchestrator until TTL — write fan-outs were unusable, IMP-114); the ACK-token signature was computed over the *data-stripped* command, so two deletes with different quoted targets shared one signature and a token approved for A also authorized B (IMP-119); and `had_controller_step` alone would have been worthless because the compliant path exits the hook silently (IMP-116). **One reported finding was wrong:** `guard-unsafe.sh` never blocked `grep` — the four overrides were reflex prefixes, now logged as `OVERRIDE-UNNECESSARY` (IMP-118). Also: the weekly loop finally writes back (25 findings across 4 runs had produced 0 ledger entries, IMP-112), `zcat`→`gunzip -c` (BSD `zcat` read `.gz` as empty, hiding 1,286 signals, IMP-110), `agent_invocations` measured for the first time (IMP-115), loopback FPs removed from the web-fetch gate (46% of its log, IMP-117). Report: `plans/imp-triage-2026-08-01.md`. Previous: 2026-07-03 — Fable-5-Metareview (IMP-073..086): ledger backfilled + honest computed metrics, gate regression suite (28 cases) + rm-as-data FP fix, measurement loop closed (verification blocks, /meta --verify operational, staleness escalation), MCP agency gate (`mcp-agency-gate.sh`), rules diet (gate+arbiter → `agency-bands`; 4 micro-rules → `release-cli-discipline`; 4 conditional rules demoted to on-demand skills, ~9K tokens/session saved), model-era refresh (Claude-5 family, window-relative context thresholds), worktree discipline (IMP-070/072), R.Code versioning + `/rcode-upgrade`, drift/restore/retention scripts. Report: `plans/meta-proposal-2026-07-03-fable5-metareview.md`. Previous: 2026-05-27 KB-driven Migration v3.

### Zwei Orte: Bauhof und bewohntes Haus (NEU 2026-08-04)

Dieses Repo existiert an **zwei** Stellen. Wer das nicht weiß, editiert am
falschen Ort und wundert sich, warum Änderungen verschwinden oder sofort
scharf sind.

| Ort | Rolle | Pfad |
|---|---|---|
| **Bauhof** (Arbeitskopie) | Hier wird entwickelt, geprüft, committet. Nichts wirkt live. | `/Volumes/YourExternalVolume/1-PROJECTS/Development/5-AI-APPS/claude-code-config` |
| **Haus** (Installation) | Was Claude Code tatsächlich liest. Empfängt nur fertige Übergaben. | `~/.claude` |

Remotes: Der Bauhof hat `origin` (GitHub) und `live` (→ `~/.claude`);
das Haus hat `origin` (GitHub) und `workshop` (→ Bauhof).

**Übergabe:** `claude-deploy [config|cockpit|all]` — verweigert die Arbeit,
wenn der Bauhof uneingecheckte Änderungen hat, und macht ausschließlich
Fast-Forward. Wirksam ab der **nächsten** Sitzung.

**Laufzeitpräferenzen (IMP-127, 2026-08-04):** Zwei Dinge schreibt Claude Code
im Betrieb selbst ins Haus und ließ damit früher jede Übergabe scheitern —
`model`/`effortLevel` in `settings.json` (über `/model`, `/config`) und den
Plugin-Zustand unter `plugins/`. Ersteres wird bei der Übergabe in den Bauhof
**zurückgezogen** und dort als eigener Commit verbucht (das Haus behält den
Wert), Letzteres ist nicht mehr versioniert. Weicht das Haus in einer *anderen*
verfolgten Datei oder einem nicht gelisteten Schlüssel ab, bricht die Übergabe
weiterhin ab — das ist der Fall „von Hand am bewohnten Haus gearbeitet", und der
soll auffallen. Liste + Begründung: `RUNTIME_KEYS_JSON` in
`scripts/deploy-to-live.sh`, Regression: `scripts/tests/deploy-regression.sh`
(49 Fälle, Stand 2026-09-09 — seit IMP-205 generiert: `framework-inventory.sh --json | jq .test_suites`).
Seit 2026-09-09 gehört auch `modelSettings` (Aufwandsstufe je Modell, geschrieben von
`/model` + `/effort`) zu den Laufzeitschlüsseln — die Übergabe brach am 09.09. genau daran ab (IMP-194).

> **Sackgasse (IMP-128, abgeräumt 2026-08-04):** Eine `~/.claude/settings.local.json`
> löst das nicht — auf **Nutzerebene** liest Claude Code diese Datei nicht (die lokale
> Ebene existiert nur pro Projekt). Nachgemessen: die dort stehende
> `NOTION_PARENT_PAGE_ID` ist in der Sitzungsumgebung nicht gesetzt, während der zweite
> Wert derselben Datei nachweislich aus `~/.zshrc` kommt. Die Vorlage
> `templates/settings.local.json.template` ist entfernt, `README.md`,
> `skills/kokonutui-pro`, `agents/documentation-agent`, `docs/RETENTION-POLICY`,
> `scripts/restore-drill.sh` und das öffentliche Handbuch sind korrigiert.
>
> **Wo Werte stattdessen hingehören:** Umgebungswerte für Claudes Werkzeuge in die
> Shell (`~/.zshrc`) — nur dieser Weg ist belegt. Werte, die auch ohne Shell-Profil
> ankommen müssen, in den `env`-Block von `settings.json` — **niemals Geheimnisse**,
> diese Datei ist öffentlich. Maschinenstabile, nicht geheime Werte gehören in die
> Spec, die sie braucht (so gelöst für den Logbuch-Pfad und seit 2026-08-04 auch für
> die Notion-Seite der `daily-docs`-Routine).

**Warum getrennt:** Eine Änderung an einem Hook oder einer Regel in
`~/.claude` gilt beim nächsten Werkzeugaufruf **derselben** Sitzung — man
saniert die Elektrik bei anliegendem Strom. Der Bauhof entkoppelt das.
**Warum das Haus trotzdem vollständig bleibt** (kein Symlink auf die SSD):
Die SSD ist ein externes Laufwerk. Hinge `~/.claude` daran, startete Claude
Code ohne eingehängtes Laufwerk **ganz ohne Konfiguration** — kein Regelwerk,
keine Hooks, keine Berechtigungen.

**Laufzeitdaten** (`projects/`, `sessions/`, `history.jsonl`, Caches) leben
ausschließlich im Haus und sind nicht versioniert — der Bauhof kennt sie nicht.

Gleiches Muster für das **Cockpit** (Dashboard): Quelle in
`5-AI-APPS/cockpit`, installierte Kopie in `~/.claude/cockpit` (dorthin
zeigen 7 Hook-Einträge und die Statuszeile — ein PreToolUse-Hook, der ins
Leere greift, kann Werkzeugaufrufe blockieren, deshalb muss die Kopie lokal
und vollständig sein).

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
| **domain-docs-convention** | **CONTEXT.md-Glossar pro Projekt** (Begriff prägen ab 3. Umschreibung; Code-Namen folgen dem Glossar) **+ atomare ADRs** in `docs/adr/` (eine Entscheidung pro Datei, unveränderlich, superseded-by statt Edit). Adaptiert aus mattpocock/skills, MIT (NEW 2026-08-03, IMP-124) |

> **Demoted to on-demand skills (IMP-079, 2026-07-03):** `legacy-codebase-audit`, `rcode-ios`, `framework-extraction`, `kokonutui-pro` (+ component index) — their headers were already trigger specs; they now load only when their topics come up (~5.8K tokens/session saved).
>
> **Removed from this table (2026-09-23, "Plan folgt Praxis"):** `phase-backward-transitions` — the backward-jump protocol it documented now lives at `~/.claude/rcode/stages/backward-transitions.md` and is read by the R.Code stage playbooks when a backward jump is considered, not loaded into every session of every project. See `docs/adr/0002-rcode-plan-folgt-praxis.md`.

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
| **visual-qa-agent** | sonnet | **Read-only visual QA in a real browser** (Playwright MCP tools; no Edit/Write, no `browser_run_code_unsafe`) — screenshot/snapshot first, describe what is visible, then judge; compare against the SOURCE (template file, user screenshot), never a paraphrase (`slop-prevention.md` Trigger 3 as its core mandate). Closes the roster gap that ≥6 `AGENTENWAHL:` rationales named in the window 2026-08-24..09-09 (Projekt J: 11/11 dispatches went to general-purpose for visual checks). NEW 2026-09-09, IMP-196 |
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
| git-identity-check.sh | SessionStart | Identity guard (single identity: Emanuel Maintainer — LegacyIdentity retired 2026-06; Claude-Login `info@legacy-identity.de` is unrelated to git) |
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
| **web-fetch-safety-gate.sh** | PreToolUse / `WebFetch\|WebSearch` + `mcp__.*` + `Bash` | **Deterministic danger-gate for research fetching** — auto-allows; escalates to native `ask` only on raw-IP/punycode/shortener/binary-download/creds-in-URL/abused-TLD across native+Firecrawl-MCP+Bash routes. **IMP-117 (2026-08-01):** loopback carve-out (`127.0.0.1`/`::1`/`localhost`/`*.localhost` skip the host-identity checks ONLY — credentials + binary-download still screen them) and a `jq`-built log writer. Pairs with `web-research-trust.md`. **IMP-203 (2026-09-09):** a non-alphabetic last label escalates only for IP-*shaped* hosts (4 dot-segments, or dotless decimal/hex) — `DD.MM.YYYY` dates next to a `curl`/`wget` mention were 2 of 30 escalations in the window. Regression: `hooks/tests/web-fetch-gate-regression.sh` (100 cases). NEW 2026-07-09, IMP-088 |
| **dispatch-capture.sh** | PreToolUse / `Task\|Agent` | **The subagent-dispatch meter** — the only surface that can see a delegation (`observation-capture.sh` matches `Edit\|Write`, so signals.jsonl structurally cannot). Feeds `agent_invocations` in `daily-metrics.jsonl`. Payload is `{ts, session_id, tool, subagent_type, model, run_in_background, isolation}` — deliberately **no prompt** (untrusted + bulky); a missing `model` parameter is logged as `"inherit"`, not `null` (IMP-204 — 51/153 rows were null in the window). No `agent_id` — PreToolUse fires before the runtime assigns one, which is why `background-agent-check.sh` pairs by count. NEW 2026-08-01, IMP-115 — promoted from the expired `q2-probe-dispatch-dump.sh` (now `hooks/archived/`) |
| **git-remote-check.sh** | SessionStart | **Warn when local work has nowhere to go** — repo with 0 git remotes and >N local commits (default 20, `CLAUDE_NOREMOTE_WARN_COMMITS`). Non-blocking, 3 local git calls, no network. NEW 2026-08-01, IMP-122 — generalises a 157-commit/0-remote near-total-loss exposure |
| **routine-liveness-check.sh** | SessionStart | **The reader the routine logs never had** — scans `daily-docs-log`/`nightly-obs-log`/`weekly-improve-log.jsonl`; ≥2 consecutive `status:"error"` runs → a blocker line at session START (routine, count, last error, series start); log older than 2× its interval → "hasn't fired for N days"; silent when healthy or absent; always exit 0. Against the real logs on 2026-09-09 it reported daily-docs 18 and weekly-improve 3 — the 39 failures nobody read (IMP-189) had been visible only to the quarterly audit. Regression: `hooks/tests/routine-liveness-regression.sh` (13). NEW 2026-09-09, IMP-191 |
| **subagent-watchdog.sh** + **background-agent-check.sh** | SubagentStop + UserPromptSubmit/Stop | **Heartbeat for background troops (IMP-198)** — every SubagentStop is logged to `subagent-stops.jsonl` with `stop_reason` and an `abnormal` flag (`stop_reason≠end_turn` or rate-limit/quota/overloaded markers in the last message; preview ≤160 chars, no full messages); `background-agent-check.sh` pairs dispatches against stops per session and, at the next prompt or turn end, prints `⏳ N Hintergrundtrupp(s) ohne Ende-Signal seit M min` (threshold `CLAUDE_BG_STALE_MIN`, default 20) or the preview of an abnormal stop ≤60 min old. Would have said "1 troop without end signal for 5 h 10 min" at the 16:42 "weiter" on 2026-09-01. **Blind spots, by design and documented in the script headers:** a troop that is alive but idle; a crash below the hook layer (no SubagentStop at all); pairing is FIFO by count, not by identity. Regression: `hooks/tests/background-watchdog-regression.sh` (22 since the 2026-09-23 three-state fix — missing `stop_reason` is no longer "abnormal"; 1,515/1,515 logged stops had been false alarms). NEW 2026-09-09 |
| **security-findings-check.sh** (+ `scripts/security-review-findings.sh`) | SessionStart | **The return channel for automatic security reviews (IMP-207)** — the `security-guidance` plugin runs its reviews as separate `sdk-py` sessions ("Review this change for security vulnerabilities …") and delivers findings only as a chat message into a still-living parent session; nothing persisted, so a HIGH finding from 2026-08-24 sat unread for 16 days. The extractor takes each review session's **last accepted** `StructuredOutput` call (rejected schema attempts come first; a session with none is *incomplete*, never *clean*), writes one row per finding to `security-review-findings.jsonl`, dedups by session+index with a watermark, and offers `--since`/`--project`/`--dry-run`/`--ack <session_id>`/`--to-ledger` (proposed only, through `ledger-append-proposed.sh`). The hook runs it incrementally with a time budget and prints one line: `🔐 N ungesichtete Sicherheitsbefunde für <project> (…) — sichten: --ack <session_id>`. **First run (2026-09-09, since 08-24): 173 review sessions, 89 clean, 18 incomplete, 11 findings** — the 08-24 one, two from the same day about the `--location` fix (a parser differential: quoted values are stripped before the regex runs), and 5 never seen before in Projekt I/Projekt J. Also the source of the IMP-200 path-error family — the review prompt names relative paths without a repo root. Regression: `hooks/tests/security-findings-regression.sh` (13). NEW 2026-09-09 |
| **graphify hook-guard** (extern) | PreToolUse / `Bash\|Grep` + `Read\|Glob` | **NOT a `hooks/*.sh` script** — invokes the external `graphify` binary (`~/.local/bin/graphify`). Nudges toward `graphify query` instead of raw grep/read WHEN a `graphify-out/graph.json` exists in the project; silent no-op otherwise. Fails open everywhere (exit 0, empty stdout on any error/unknown subcommand). ~37ms/call. Installed 2026-07-31, IMP-109 — see "Graphify" section below. |
| **serena-write-gate.sh** + **serena-post-tool.sh** | PreToolUse + PostToolUse / `mcp__serena__.*\|mcp__plugin_serena_serena__.*` | **Delegating fail-closed gate for Serena WRITE tools (IMP-130, 2026-08-05)** — translates each Serena write call into the native `(file_path, new_string)` shape and runs the SAME inspectors as native Edit/Write (parallel-lock, file-protection, security-audit, config-protection; post: auto-format, EOF check, observation-capture + read tracker). Unknown tool / param drift / missing inspector → deny, never allow; `rename_symbol`/`safe_delete_symbol` → recoverable ask (LSP writes N unnamed files); memory path-escape → deny. Supersedes "read-only by design" (IMP-104); ADR: `docs/adr/0001`. Regression: `hooks/tests/serena-gate-regression.sh` (37 cases) |

> Table shows a curated subset of the registered hooks — the others are infrastructure (parallel-lock-check, gateguard, pretool-auto-read, posttool-track-read, config-protection, stop-batched-checks, postbash-failure-recovery, notification-tts, parallel-analyze-prompt, subagent-lock-release, sandbox-guard, controller-first-mutation-gate, controller-first-subagent-flag, session-handoff-write). Exactly one on-disk script — `line-limit-check.sh` — is present-but-unregistered (folded into `stop-batched-checks.sh`). Counts: `~/.claude/scripts/framework-inventory.sh`; full registration: `settings.json`. Regression suites — **counts are GENERATED since IMP-205 (2026-09-09): `framework-inventory.sh --json | jq .test_suites`** (static analysis, never executes a suite; `cases:null` + `note` where it cannot be sure). The numbers below are the 2026-09-09 snapshot and WILL drift — four of them had already drifted when the generator was built (serena 35→37, gate 73→147, parallel-lock 12→14, deploy 20→49): `hooks/tests/gate-regression.sh` (169, IMP-076/163/193/209), `web-fetch-gate-regression.sh` (100, IMP-088/117/203), `parallel-lock-regression.sh` (14, IMP-114), `serena-gate-regression.sh` (37, IMP-130), `session-end-staleness-regression.sh` (22, IMP-138/164/192), `routine-liveness-regression.sh` (13, IMP-191), `background-watchdog-regression.sh` (22, IMP-198 + 2026-09-23 three-state fix), `scripts/tests/gather-scripts-regression.sh` (R.Code gather scripts + plan tracker, NEW 2026-09-23), `scripts/tests/command-contract-lint-regression.sh` (26 incl. the tree case, NEW 2026-09-23), `scripts/tests/routine-run-regression.sh` (15, IMP-189/190), `deploy-regression.sh` (49, IMP-127/194).

> ⚠️ **Inventory blind spot (IMP-109):** `framework-inventory.sh` counts `hooks (registered)` as *unique `*.sh` paths in `settings.json`*. The two **graphify** PreToolUse entries invoke a binary, not a `.sh`, so they are **invisible** to that count — it reports 33/33 while `settings.json` actually holds **43 hook entries** (the gap is also inflated by inline `echo`/shell one-liners and by hooks registered under more than one matcher, e.g. `web-fetch-safety-gate.sh` under three). Any future non-`.sh` hook has the same blind spot. `settings.json` remains the only complete registration truth.

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

**Zeitgeber-Mechanismus (seit 2026-08-22, IMP-135):** lokale `launchd`-Timer, gebunden an `~/.claude` (nicht an ein Bauhof-relatives oder Cloud-cwd) — Definitionen unter `scripts/launchd/com.your-username.claude-routine-<task>.plist`, Läufer `scripts/routine-run.sh <task> [--dry-run]`, Installer `scripts/install-routine-timers.sh` (idempotent, prüft vor der Installation, dass `routine-run.sh` bereits in `~/.claude/scripts/` liegt, `--uninstall` zum Rückbau). Löst die bis 2026-08-02 gültige unversionierte Cloud-Bindung an ein cwd ab, das eine Reorganisation umbenannte — 20 Tage stiller Ausfall ohne jedes Signal. Wachhund gegen einen erneuten stillen Tod: Liveness-Sweep im Quartals-Audit plus ein von der Routine selbst entkoppelter session-end-Alarm (IMP-138, umgesetzt 2026-08-22 — `session-end-check.sh` alarmiert allein auf `DAYS_STALE` und nennt das Alter des neuesten Shards; Regression `hooks/tests/session-end-staleness-regression.sh`, 15 Fälle seit IMP-164).

**Startfehler des Läufers (IMP-189, gefunden und behoben 2026-09-09):** Der am 22.08. ausgelieferte
Läufer hatte bis zum 09.09. **keinen einzigen** erfolgreichen Lauf — 39 Fehlläufe (nightly 18, daily 18,
weekly 3), alle `runner: claude exited 1`. Ursache: `routine-run.sh` übergab die SKILL.md als Argument
hinter `-p`; deren erste Zeile `---` las der Optionsparser von `claude` 2.1.266 als unbekannte Option
(`error: unknown option '---`). `--dry-run` ruft `claude` nie auf und konnte das strukturell nicht sehen
(IMP-190, `proposed`). Fix c165871: Prompt über stdin (`< SKILL.md`), Regression
`scripts/tests/routine-run-regression.sh` (9 Prüfungen, Fall D gegen die echte Binary). Erste ok-Zeile
der Nachtroutine 2026-09-09 10:37 nach manuellem Start (3.262 Signale rotiert, 15 Shards und 15
Metrik-Tageszeilen nachgeholt); die launchd-**Umgebung** gilt erst mit dem Zeitgeber-Lauf 2026-09-10
02:05 als bewiesen. **Die IMP-138-Alarmzeile stand während des gesamten Ausfalls in jedem Sitzungsende
(Zähler > 240) und blieb unbeachtet** — ein Wachhund am Sitzungs*anfang*, der die Routine-Logs selbst
liest, ist IMP-191/192 (`proposed`). Bericht: `plans/meta-proposal-2026-09-09-improvement-run.md`.

| Task | Schedule | Status | Run log (mandatory since IMP-075) |
|------|----------|--------|-----------------------------------|
| daily-docs | 07:10 daily | ⚠️ erster Lauf mit repariertem Läufer 2026-09-10 07:10 ausstehend — 18 Fehlläufe 23.08.–09.09. (IMP-189). **Ursache des stillen Notion-Ausfalls behoben 2026-08-04 (IMP-128):** die Parent-Page steht jetzt in `scheduled-tasks/daily-docs/SKILL.md` §B, vorher in `NOTION_PARENT_PAGE_ID` — einer Variable, die nie gesetzt war, weil sie in der nicht gelesenen `settings.local.json` stand. Der Schritt meldet jetzt `partial` **mit Grund** statt still zu überspringen. **Wirkung noch unbewiesen** — die Routine hat den Notion-Schritt seit dem 04.08. wegen IMP-189 nie erreicht. | `daily-docs-log.jsonl` |
| nightly-observation | 02:05 daily | ✅ ok-Zeile 2026-09-09 10:37 (erste seit 2026-08-02, nach 18 Fehlläufen — IMP-189; manuell gestartet, Zeitgeber-Lauf 2026-09-10 02:05 ausstehend). Step 2 delegated to `compute-daily-metrics.sh`; Step 2b trims the dispatch meter (IMP-115) | `nightly-obs-log.jsonl` |
| weekly-improve | Sunday 22:06 | ⚠️ nächster Lauf So 2026-09-13 22:06 — 3 Fehlläufe (23.08., 30.08., 06.09., IMP-189), letzter ok-Lauf 2026-07-27. data paths FIXED 2026-07-03; **`zcat`→`gunzip -c` FIXED 2026-08-01 (IMP-110)** — BSD `zcat` read every `.gz` shard as empty with exit 0, so the 2026-07-26 run analysed 1,286 invisible signals; **ledger write-back now mandatory (IMP-112)** | `weekly-improve-log.jsonl` |

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
`docs/adr/0002-rcode-plan-folgt-praxis.md`).

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
| /rcode-upgrade | Upgrade a deployed project's rails to the current framework version — three-way rule diff, per-file y/n, never clobbers customized rules; commits the applied rail update after one explicit y/n (NEW 2026-07-03, IMP-085; commit behavior changed 2026-09-23 — see `docs/adr/0002-rcode-plan-folgt-praxis.md`) |
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

> **Adoptiert 2026-08-03 aus [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, IMP-124..126):** die 3 Skills oben, die Regel `domain-docs-convention` (CONTEXT.md + ADRs), die Fowler-Smell-Baseline im `code-reviewer-agent` (Step 4b — trägt automatisch in alle 6 `quality-review`-Spezialisten, IMP-125), und der Rollout von `disable-model-invocation: true` auf die nutzergetakteten Analyse-Skills `historical-signals`/`historical-signals-v2` (IMP-126 — damit tragen es 5 Skills; `meta-observer` und `migrate-to-skills` hatten es unbemerkt schon seit 2026-05-27, und die weekly-improve-Routine läuft nachweislich trotzdem: ok-Läufe 12./20./27.07. mit 4/6/11 Findings — die geplante Session liest die SKILL.md als Datei, nicht über den gesperrten Aufrufweg).

### Background Skills (auto-trigger only, hidden from menu)

react-perf-check, tailwindcss-v4-styling, import-fixer, fix-review, orchestration

### Output Style — `Hausbau` (default since 2026-08-01)

`~/.claude/output-styles/hausbau.md`, activated via `"outputStyle": "Hausbau"` in `settings.json`.
Every explanation is written in plain language against one sustained metaphor — planning, building,
moving into and maintaining a house — with a **fixed concept↔image mapping table** so the vocabulary
stays stable across sessions instead of being reinvented per answer.

| Property | Value |
|---|---|
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

## Apple Erinnerungen (Reminders) - zentrales Erinnerungstool

Claude can have AppleScript access to the Apple Reminders app on macOS
(e.g. via an automation MCP tool) once the user confirms it is available.
Where available, treat Apple Reminders as the default place for
reminders/to-dos rather than a one-off project note file.

- If the user wants to be reminded of something, or asks for a reminder,
  to-do, deadline, or follow-up: create it in Apple Reminders (in addition
  to a project-specific note file where one is relevant).
- Before creating an entry, list the existing Reminders lists and pick the
  matching one; create a new list for a genuinely new topic.
- Only set a due date when requested or clearly useful — otherwise leave
  it open.
- Do not assume a fixed set of list names: enumerate the user's actual
  lists on their machine (they are personal and vary per user) rather
  than hardcoding examples here.

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

## graphify

A knowledge graph may exist at `graphify-out/` (god nodes, community structure, cross-file relationships) — **only in projects where `graphify .` has actually been run.** Check for `graphify-out/graph.json` before assuming one is present; do not hunt for it otherwise.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
