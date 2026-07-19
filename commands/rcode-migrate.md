---
description: "Migrate an already-started project INTO the R.Code framework. Reverse of /brainstorm + /decompose: derives the same artifact set from the existing CODEBASE + GIT HISTORY instead of from an idea. Use on an existing repo you want to bring under R.Code management."
argument-hint: "[optional: short note on the project, e.g. 'internal admin dashboard, ~8 months old']"
model: claude-fable-5[1m]
allowed-tools:
  - Task
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(mkdir:*)
  - Bash(cp:*)
  - Bash(ls:*)
  - Bash(wc:*)
  - Bash(jq:*)
  - Bash(npx:*)
  - Bash(npm:*)
  - Bash(pnpm:*)
  - Bash(yarn:*)
  - Bash(mypy:*)
  - Bash(pytest:*)
  - Bash(ruff:*)
  - Bash(black:*)
  - Bash(cargo:*)
  - Bash(go:*)
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `agents/control-agent.md` §4.

# R.Code Migrate — Adopt an Existing Project Into the Workflow

You are executing the R.Code `/rcode-migrate` command. This brings an **already-started codebase** under R.Code management.

It is conceptually **`/brainstorm` + `/decompose` run IN REVERSE**: it produces the same artifact set, but **derives it from the existing CODE + GIT HISTORY** instead of from a fresh idea. The forward commands invent a plan; this command **reconstructs** one from what already exists.

> **Naming note:** This is unrelated to the `migrate-to-skills` skill (which ports Cursor/Antigravity config files to SKILL.md format). This command is about **project-methodology adoption** — bringing a real codebase under the R.Code development workflow.

**INPUT (optional context):** $ARGUMENTS

---

## Core Principles (read before doing anything)

1. **FORWARD-ONLY.** The existing codebase is the immutable past. NEVER rewrite git history, never back-date issues, never fabricate commits. All existing work collapses into a single synthetic **"Phase 0 — Pre-R.Code Baseline."** R.Code management starts from *now*.
2. **FAIL-LOUD / NO-SLOP.** Every field you cannot derive with confidence from the code or git history gets an **explicit stub marker** — never an invented value. Forbidden to fabricate: ADR rationale, alternatives-considered, brand voice, user stories, success metrics, research that didn't happen. Hallucinated history violates `fail-loud.md` and `slop-prevention.md`. Mark gaps; do not paper over them.
3. **IDEMPOTENT.** Safe to re-run. Guard every `gh label`/`gh milestone` creation against duplicates. Don't clobber an already-populated working tree — detect existing artifacts and reconcile rather than overwrite.
4. **EXCESSIVE-AGENCY-GATE.** Creating GitHub objects (labels, milestones, issues), git tags, and commits changes shared state and notifies collaborators. Before ANY of these, present a y/n confirmation summary and PAUSE — **even in autonomous / YOLO mode** (per `agency-bands.md`). The read-only analysis phases need no gate; the state-changing phases do.

---

## Phase 0 — DETECT & FEASIBILITY (read-only, NO gate)

Determine whether migration is appropriate. Output a verdict: **STRONG / MODERATE / NOT POSSIBLE**.

### 0.1 Gather signals

```bash
# Is this a git repo at all?
git rev-parse --is-inside-work-tree 2>/dev/null

# How much history exists?
git log --oneline 2>/dev/null | wc -l                       # commit count
git log -1 --format=%ci 2>/dev/null                         # most recent commit
git log --reverse --format=%ci 2>/dev/null | head -1        # first commit (age)
git shortlog -sn --all 2>/dev/null                          # distinct authors

# Is there a GitHub remote + issue tracker reachable?
git remote -v 2>/dev/null
gh repo view --json name,owner,hasIssuesEnabled 2>/dev/null
gh issue list --state all --limit 5 2>/dev/null

# Is this already a R.Code project?
ls -la .rcode 2>/dev/null
```

Use `Glob` to size the codebase (e.g. `**/*.{ts,tsx,js,py,go,rs,swift}`) and detect package count (multiple `package.json` / `pyproject.toml` / workspaces).

### 0.2 Feasibility check — hard blockers vs. advisory

There are two distinct classes. **Hard blockers** make migration technically impossible — abort. **Advisory signals** mean migration would likely cost more than it returns — *recommend against, but proceed if the user explicitly insists*. Do not conflate them: a borderline-but-real project that trips an advisory signal must not be hard-aborted.

**A) HARD BLOCKERS — abort if ANY holds.** Explain clearly WHY + what to do instead, then **STOP** (no writes, no gate):

| Reason | Why it blocks migration | What the user can do instead |
|--------|------------------------|------------------------------|
| **No git repository** | R.Code's entire traceability model (commits → issues → phases) is built on git. There is no "Phase 0 baseline" to anchor to. | `git init`, make an initial commit of the current state, connect a GitHub remote, then re-run. |
| **No issue tracker AND user unwilling to adopt one** | The `/decompose → /issue` loop *binds work to GitHub issues + milestones*. Without an issue tracker the workflow has nothing to bind to — `/issue <#>` cannot run. Ask the user: "This repo has no GitHub issues enabled. R.Code needs an issue tracker. Enable GitHub Issues / adopt one?" If they decline → abort. | Enable GitHub Issues on the repo (or migrate to a GitHub-hosted remote), then re-run. |
| **Already a R.Code project** (`.rcode/` exists) | Already migrated. Re-running migration would conflict with existing state. | Use `/status-sync` to reconcile state, or `/rcode-onboard` to get oriented. |

**B) ADVISORY SIGNALS — recommend against, proceed only if the user confirms.** Surface these as a caution with the verdict; do NOT auto-abort:

| Signal | Why it argues against migrating now | Recommended alternative |
|--------|------------------------------------|-------------------------|
| **Throwaway / prototype / spike** | R.Code overhead (issues, phases, scope manifest, reviews) only pays off on durable work. A spike you'll delete next week is pure overhead. | Keep it lightweight. Adopt R.Code later **if** the prototype graduates to a real project. |
| **Too small (overhead > value)** | Mirrors `framework-extraction.md`'s premature-adoption logic: heuristic thresholds — **< ~20 issues' worth of work, < a few months old, single author, single package**. If most of these hold, the ceremony likely costs more than it returns. | Revisit when the project grows: multiple contributors, multiple packages, or a backlog that genuinely needs phase/issue tracking. |

If only advisory signals are present, tell the user plainly ("this looks small/early — R.Code may be overkill") and ask whether to proceed anyway before continuing to Phase 1.

### 0.3 Verdict

If not aborting, classify and report:

- **STRONG** — git history with real depth, GitHub issues enabled, multi-month / multi-author / multi-feature codebase, clear module boundaries. Migration will produce high-fidelity artifacts.
- **MODERATE** — meets the minimum bar (git + issue tracker available + not throwaway) but is thin in places (shallow history, single author, or fuzzy module boundaries). Migration works but more fields will land in PARTIAL/STUB territory. Tell the user which.

Present the verdict and the evidence behind it, then continue to Phase 1. (Phases 1–2 are read-only/local-write; the first irreversible action is gated in Phase 3.)

---

## Phase 1 — ANALYZE (read-only)

Reverse-engineer the project. Spawn an `Explore` (or `general-purpose`) agent via the **Task** tool for the heavy read work if the codebase is large (> ~20K tokens of reading) so the main context stays lean. Otherwise do it inline with `Glob`/`Grep`/`Read`.

### 1.1 Detect the stack

Read manifests + lockfiles to establish ground truth:

```bash
ls package.json pnpm-lock.yaml yarn.lock package-lock.json \
   pyproject.toml requirements.txt poetry.lock Pipfile \
   go.mod Cargo.toml Gemfile composer.json *.csproj \
   Package.swift 2>/dev/null
```

From these derive: language(s), framework(s), package manager, test framework, lint/format tooling, and the **real toolchain commands** (you will need these in Phase 2 for the CLAUDE.md pre-commit trio and in PROJECT-STATUS quality metrics).

### 1.2 Cluster modules → FEATURES

Group the codebase into 3–8 coarse **features** by inspecting:
- top-level `src/<feature>/` directories
- route groups (`app/(group)/`, `pages/`, router definitions)
- domain modules / packages / bounded contexts
- service + model pairings

Each cluster becomes a feature `F001`, `F002`, … with a name and a one-line description derived from the code. These map into the scope manifest and BRAINSTORM feature list.

### 1.3 Observe conventions (for CONVENTIONS.md, high fidelity)

Directly observe — do not guess:
- **Folder structure** — by-feature vs by-type; where utilities/types/tests live
- **Naming** — file casing per category (components, hooks, utils, modules)
- **Import ordering** — sample several files
- **Test layout** — co-located vs `tests/` mirror; framework + assertion style
- **State management** — store libraries / context / signals in use
- **Error handling** — error shapes, try/catch patterns, API error format
- **API patterns** — REST/GraphQL/RPC, route conventions, status-code usage

### 1.4 Reverse-engineer architecture (for ARCHITECTURE.md, partial)

- **Tech stack table** — from 1.1, with versions from lockfiles
- **Integrations** — grep SDK/client imports (e.g. `stripe`, `@supabase`, `firebase`, `openai`, `@aws-sdk`, `convex`) → external services
- **Environment variables** — collect `process.env.*` / `os.environ[...]` / `import.meta.env.*` / `.env.example` keys
- **Data flow** — trace representative route → service → db chains
- **CI/CD** — read `.github/workflows/*`, other pipeline configs
- **Deployment** — infer from config (`vercel.json`, `Dockerfile`, `fly.toml`, etc.)

### 1.5 Synthesize the Phase-0 baseline from git

```bash
git log --reverse --format=%ci | head -1     # project start
git log -1 --format=%ci                       # latest activity
git shortlog -sn --all                        # contributors
git log --format=%s | head -50                # recent commit subjects (themes)
git tag --list                                # existing release markers
```

Compress ALL of this into a single synthetic **"Phase 0 — Pre-R.Code Baseline"**: date range, contributor count, headline capabilities, existing tags. This is the only "phase" that describes the past.

---

## Phase 2 — GENERATE ARTIFACTS (local writes, NO gate yet)

Generate the R.Code artifact set. Every artifact falls into exactly **one of three feasibility classes**. Be explicit in each generated file about which fields are which.

> Reference the EXACT template field names from `~/.claude/rcode/templates/`. Match their structure so downstream commands (`/status-sync`, `/issue`, `/phase-gate`) parse them correctly.

### Class AUTO — high fidelity, derivable from code

Generate these directly and confidently:

- **`CONVENTIONS.md`** — from §1.3. Use `CONVENTIONS.template.md` structure (folder structure, file naming, component/state/error/API patterns). Fill from observed reality.
- **`CONTRIBUTING.md`** — from `CONTRIBUTING.template.md`. Adapt prerequisites + setup/test commands to the detected stack.
- **Project `CLAUDE.md`** — from `CLAUDE-PROJECT.template.md`. **CRITICAL:** adapt the pre-commit command trio to the DETECTED toolchain — do NOT hardcode `tsc && test && build`:
  - Python → `mypy . && pytest && ruff check .`
  - Rust → `cargo build && cargo test && cargo clippy`
  - Go → `go build ./... && go test ./... && go vet ./...`
  - Node/TS → `npx tsc --noEmit && npm test && npm run build`
  Wire the rule imports (done in Phase 4) and fill the architecture/conventions/status sections.
- **`START_HERE.md`** — from `START-HERE.template.md`. Tech-stack table, key documents, real setup/dev/test commands. Status line: `Phase 0 of N — Pre-R.Code Baseline — migrated`.
- **Stack-specific project rules** — copy the matching files from `~/.claude/rcode/templates/project-rules/` into `.claude/rules/` based on detected stack (`nextjs-app-router.rule.md`, `supabase.rule.md`, `convex.rule.md`, `python-fastapi.rule.md`, `react-performance.rule.md`).
- **`.rcode/config.json`** — no template; construct from detected facts:
  ```json
  {
    "project_name": "[from package.json / dir name]",
    "repository": "[git remote URL]",
    "created_date": "[Phase-0 first-commit date]",
    "migrated_date": "[today]",
    "workflow_version": "2.0.0",
    "framework_version": "[first line of ~/.claude/rcode/VERSION]",
    "total_phases": 1,
    "total_issues": 0,
    "current_phase": 0,
    "status": "migrated"
  }
  ```
  `framework_version` is the global R.Code rail version — `Read` the **first line** of `~/.claude/rcode/VERSION` and stamp it verbatim (enables `/rcode-upgrade` later). If that file is missing, write `null` and surface it in the Phase-5 report — never invent a version (fail-loud).

### Class PARTIAL — fill the observable half, mark gaps explicitly

Generate the structure; fill what's derivable; mark every non-derivable field with `[reconstructed post-hoc — original decision context unavailable]` (or a more specific marker). NEVER invent the missing half.

- **`ARCHITECTURE.md`** (from `ARCHITECTURE.template.md`):
  - **Derive:** System Overview diagram, Tech Stack table (+ versions), Integration Points, Environment Variables table, Data Flow, Security/attack-surface (observed), CI/CD.
  - **Mark as gaps inside each ADR:** the `Context`, `Alternatives Considered` table, and `Why Rejected` columns → `[reconstructed post-hoc — original decision context unavailable]`. You MAY state the `Decision` (what was chosen — that's observable from code) and `Consequences` (observable), but you must NOT fabricate why alternatives were rejected.
- **`PROJECT-STATUS.md`** (from `PROJECT-STATUS.template.md`):
  - **Quality Metrics** — run the detected toolchain to get real numbers (type errors, lint warnings, test coverage, build status). If a tool isn't present, mark that metric `[not configured]` — do not write `0`.
  - **Recent Activity** — populate from `git log` (real commits as activity rows).
  - **Progress by Phase** — a single synthetic **Phase 0 — Pre-R.Code Baseline** row. Issue/phase progress model is synthetic until real issues exist.
  - Header: Active Phase = Phase 0; Last Updated By = `rcode-migrate`.
- **`.rcode/scope-manifest.json`** (from `SCOPE-MANIFEST.template.json`):
  - Feature `name`/`description` from §1.2 module clustering.
  - `scope_boundary` → from the Phase-2 interview (NEEDS-HUMAN below) for the top features; otherwise a stub: `"[scope boundary not captured at migration — define on next scope review]"`.
  - Set `"locked": true` with `"locked_date": "[today]"` — scope is **already realized** in code, so it is locked-by-construction, not locked-by-plan.
  - `metadata.created_by`: `"rcode-migrate"`. `last_updated`/`last_updated_by` accordingly.
  - `total_features` from the cluster count; `total_issues` 0 (no R.Code-tracked issues yet).
- **`.rcode/phase-summaries/phase-0-summary.md`** (from `PHASE-SUMMARY.template.md`): synthetic baseline summary — "What Was Built" = headline capabilities from §1.5; "Gate Result" = `N/A (baseline)`; "Context for Next Phase" = current state of the codebase.
- **`.rcode/agent-log.md`** — **append-only seed (Design Principle 2).** Migrate's Phase-0 gate already aborts when `.rcode/` pre-exists, so in normal flow this file is absent and you CREATE it with the header below. Defense-in-depth: if an `agent-log.md` somehow already exists, APPEND only the `## Session: Migrate` block (from that line down) — do not emit a second `# Agent Log` header or rewrite the file.
  ```markdown
  # Agent Log — [Project Name]

  > Append-only session history. Never delete entries.

  ---

  ## Session: Migrate

  **Date:** [today]
  **Agent:** rcode-migrate

  **Actions:**
  - Migrated existing project to R.Code on [today]
  - Reverse-engineered [N] features, conventions, and architecture from code + git history
  - Established synthetic Phase 0 — Pre-R.Code Baseline
  - Generated AUTO/PARTIAL/STUB artifact set

  **Next Steps:**
  - Review STUBBED and PARTIAL-gap fields
  - Run `/status-sync`, then `/phase-gate 0`
  ```
- **`.rcode/blocked-issues.md`** — standard empty stub ("No blocked issues yet.").

### Class NEEDS-HUMAN — HYBRID MODE (auto thin slices + SHORT interview + honest stubs)

Auto-derive what you can, run a **SHORT** interactive interview for the highest-value fields ONLY, and leave honest stubs for the rest. Use the `AskUserQuestion` mechanism (ask the user concise questions) — do NOT fabricate.

**The interview must be SHORT — only these:**
1. **Vision one-liner** — "In one sentence, what is this project and who is it for?"
2. **`scope_boundary` for the top ~3–5 features** (from §1.2) — "For feature `<X>`, what does it explicitly NOT cover?"

Everything else in this class is auto-derived or stubbed — never interviewed, never invented.

- **`BRAINSTORM.md`** (from `BRAINSTORM.template.md`):
  - **Auto:** Technical Architecture Summary table (stack), Core Features list (F001…, from §1.2).
  - **Interview:** Vision paragraph (one-liner from Q1).
  - **Stub:** the forward plan — Development Phases / Estimated Timeline / Milestone Markers → `N/A — migrated codebase; existing work is Phase 0 baseline. Future phases are planned via /decompose going forward.`
- **`SPECIFICATION.md`** (from `SPECIFICATION.template.md`):
  - **Auto:** Design System tokens (extract from `tailwind.config.*`, `@theme`, CSS custom properties / `:root` vars); Data Model (from schema files / migrations / ORM models); Component Patterns (observed).
  - **Interview:** nothing required.
  - **Stub:** Brand Voice & Tone, User Stories & Journeys, Design Principles, Success Metrics → `[not captured — project predates R.Code. Document during the next product-planning session.]` NEVER invent brand voice or user stories.
- **`RESEARCH_FINDINGS.md`** (from `RESEARCH-FINDINGS.template.md`):
  - **Auto:** the **"Selected"** column only of the tech-stack tables (what the project actually uses).
  - **Stub:** Alternatives Considered, Key Reasons, Trade-offs, Cost Analysis, Open Questions → `[research not captured — project predates R.Code. The technology was already chosen; rationale was not recorded.]` NEVER fabricate alternatives or rejection reasons.

> The AUTO/PARTIAL/STUB classification of every field MUST be visible in the generated files (via the explicit stub markers) so a human reviewer can see exactly what is real vs. reconstructed vs. unknown.

---

## Phase 3 — GITHUB ADOPTION (⛔ EXCESSIVE-AGENCY GATE)

This phase creates shared-state GitHub objects. **STOP and confirm first.**

### 3.0 GATE — present and PAUSE (even in autonomous mode)

Print a summary and ask `y/n`:

```
⛔ R.Code Migrate — about to create GitHub objects + git tag:

  Labels:     [N] (phase-0, type:*, area:*, blocked, blocking, parallel-safe, rcode)
              → existing labels will be SKIPPED, not overwritten
  Milestone:  1 — "Phase 0: Pre-R.Code Baseline"
  Issues:     0 new (forward-only — no retroactive issues for past commits)
  Existing open issues: [N] found → OFFER to label `rcode` + assign to baseline milestone
  Git tag:    rcode-migrate-[today]   (runs in Phase 5, after Phase 4 wires the rules)
  Commit:     migration artifacts          (runs in Phase 5 — stages ALL files below)
              → Phase-2 docs (CONVENTIONS/CONTRIBUTING/CLAUDE.md/START_HERE/ARCHITECTURE/
                PROJECT-STATUS/SCOPE-MANIFEST/BRAINSTORM/SPECIFICATION/RESEARCH_FINDINGS),
                .rcode/ state, and the .claude/rules/rcode-*.md copied in Phase 4

Repo: [owner/repo]   Branch: [current]

Proceed with GitHub adoption now, and the gated commit + tag in Phase 5? (y/n)
```

This single `y` authorizes the irreversible actions across Phases 3–5 (GitHub objects now; commit + tag at the end after the local files are wired). List the exact staged-file set in the summary so the consent covers the *final* action, not just the GitHub mutation. Do not proceed to 3.1+ without an explicit `y`. If `n`, stop — all Phase-2 files remain on disk for review (no GitHub mutation, no commit, no tag).

### 3.1 Create labels — IDEMPOTENTLY

`gh label create` FAILS on duplicates, which would violate fail-loud if blindly suppressed. **Check existence first**, then create only missing ones:

```bash
existing=$(gh label list --limit 200 --json name --jq '.[].name')
create_label() {  # name color description
  if printf '%s\n' "$existing" | grep -qxF "$1"; then
    echo "label exists, skipping: $1"
  else
    gh label create "$1" --color "$2" --description "$3"   # real errors still surface
  fi
}
```

Create the EXACT set from `/decompose` (only `phase-0` here since there's a single synthetic phase):

```bash
# Phase
create_label "phase-0"            "5319E7" "Phase 0: Pre-R.Code Baseline"
# Type
create_label "type:feature"       "0E8A16" "New feature"
create_label "type:fix"           "D93F0B" "Bug fix"
create_label "type:test"          "FBCA04" "Testing"
create_label "type:docs"          "0075CA" "Documentation"
create_label "type:infrastructure" "D4C5F9" "Infrastructure/tooling"
create_label "type:refactor"      "E4E669" "Code refactoring"
# Area
create_label "area:auth"          "C2E0C6" "Authentication/authorization"
create_label "area:api"           "C2E0C6" "API endpoints"
create_label "area:ui"            "C2E0C6" "User interface"
create_label "area:db"            "C2E0C6" "Database/data layer"
create_label "area:config"        "C2E0C6" "Configuration/setup"
create_label "area:core"          "C2E0C6" "Core business logic"
# Workflow
create_label "blocked"            "B60205" "Blocked by another issue"
create_label "blocking"           "D93F0B" "Blocking other issues"
create_label "parallel-safe"      "0E8A16" "Can be worked on in parallel"
create_label "rcode"         "5319E7" "R.Code workflow managed"
```

> **Reconcile, don't clobber.** On a repo that already has labels (its own or from a prior migrate run), the existence check makes this a no-op for those — exactly the idempotency requirement.

### 3.2 Create the baseline milestone — IDEMPOTENTLY

```bash
if gh api repos/{owner}/{repo}/milestones --jq '.[].title' | grep -qxF "Phase 0: Pre-R.Code Baseline"; then
  echo "baseline milestone exists, skipping"
else
  gh api repos/{owner}/{repo}/milestones \
    -f title="Phase 0: Pre-R.Code Baseline" \
    -f description="Existing pre-migration codebase. Forward-only baseline; no retroactive issues." \
    -f state="open"
fi
```

> One milestone per (synthetic) phase = one milestone total for a fresh migration.

### 3.3 Reconcile EXISTING issues (forward-only — do NOT create issues for past commits)

This is **forward-only adoption.** Do NOT mint issues for historical work and do NOT rewrite history.

If the repo has existing **open** issues, **OFFER** (don't force) to bring them under R.Code:

```bash
gh issue list --state open --json number,title,labels,milestone --limit 500
```

Ask the user: *"Found [N] open issues. Label them `rcode` and assign to the Phase-0 baseline milestone? (y/n)"* If yes:

```bash
gh issue edit <N> --add-label "rcode" --milestone "Phase 0: Pre-R.Code Baseline"
```

Respect issues that already carry the label / milestone (idempotent skip). Leave closed issues untouched.

---

## Phase 4 — WIRE (local writes)

Install and wire the workflow rules into the project.

```bash
mkdir -p .claude/rules
cp ~/.claude/rcode/rules/rcode-workflow.md .claude/rules/
cp ~/.claude/rcode/rules/rcode-commits.md  .claude/rules/
cp ~/.claude/rcode/rules/rcode-scope.md    .claude/rules/
```

In the project `CLAUDE.md`, ensure the rule imports are present at the top (idempotent — add only if missing):

```markdown
@.claude/rules/rcode-workflow.md
@.claude/rules/rcode-commits.md
@.claude/rules/rcode-scope.md
```

> If the project already has a `CLAUDE.md`, **merge** the imports + R.Code sections into it; do not overwrite the user's existing content. Preserve their notes.

**Ensure `PROJECT-STATUS.md` exists** — it is the bridge file that `/issue` Phase 0 and `/status-sync` require. If Phase 2 already wrote it, confirm it's present.

---

## Phase 5 — VERIFY & REPORT, then COMMIT (gated)

### 5.1 Commit the migration

The commit was authorized by the Phase-3 gate. Stage only the artifacts this command created/modified:

```bash
git add CONVENTIONS.md CONTRIBUTING.md CLAUDE.md START_HERE.md \
        ARCHITECTURE.md PROJECT-STATUS.md BRAINSTORM.md \
        SPECIFICATION.md RESEARCH_FINDINGS.md \
        .rcode/ .claude/rules/
git commit -m "$(cat <<'EOF'
docs(project): migrate [project name] into R.Code workflow

Reverse-engineered the existing codebase + git history into the
R.Code artifact set. Forward-only adoption — existing work is
captured as a synthetic Phase 0 baseline; no history was rewritten.

- AUTO (high fidelity): CONVENTIONS, CONTRIBUTING, CLAUDE.md, START_HERE, project rules, config.json
- PARTIAL (gaps marked): ARCHITECTURE (ADR rationale reconstructed/unavailable), PROJECT-STATUS, scope-manifest, phase-0 summary
- STUBBED (needs human): BRAINSTORM vision, SPECIFICATION brand/stories, RESEARCH alternatives
- GitHub: phase-0 + type/area/workflow labels, Phase-0 baseline milestone
- Scope manifest locked (scope already realized in code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

git tag -a "rcode-migrate-$(date +%Y-%m-%d)" \
  -m "Project migrated into R.Code workflow: [N] features, Phase 0 baseline"
```

Append the Phase-5 outcome to `.rcode/agent-log.md` if anything material changed after the seed entry.

### 5.2 Final report

Display a structured summary:

```
R.Code Migration Complete!

Verdict: [STRONG / MODERATE]   Repo: [owner/repo]

Files created / modified:
  AUTO (high fidelity):
    - CONVENTIONS.md, CONTRIBUTING.md, CLAUDE.md, START_HERE.md
    - .claude/rules/rcode-{workflow,commits,scope}.md
    - .claude/rules/[stack-specific].rule.md
    - .rcode/config.json
  PARTIAL (gaps explicitly marked):
    - ARCHITECTURE.md            [ADR Context/Alternatives marked reconstructed]
    - PROJECT-STATUS.md          [real quality metrics; synthetic Phase-0 model]
    - .rcode/scope-manifest.json   [locked; feature names from code]
    - .rcode/phase-summaries/phase-0-summary.md
    - .rcode/agent-log.md, blocked-issues.md
  STUBBED (needs human review):
    - BRAINSTORM.md              [vision from interview; forward plan = N/A]
    - SPECIFICATION.md           [tokens/data-model auto; brand/stories stubbed]
    - RESEARCH_FINDINGS.md       [selected stack only; alternatives stubbed]

GitHub objects created:
  - Labels: [N created, M skipped-existing]
  - Milestone: Phase 0: Pre-R.Code Baseline
  - Existing issues reconciled: [N labeled rcode / none]

Git: commit [sha], tag rcode-migrate-[date]

Reconstructed from: [N] features, [N] commits, [date range], [N] contributors

Recommended next step:
  1. Review the STUBBED + PARTIAL-gap fields (search for "[reconstructed" / "[not captured")
  2. Run /status-sync   (reconcile dashboard with GitHub)
  3. Run /phase-gate 0  (verify the baseline)
  4. Going forward, plan new work with /decompose → /issue <#>
```

---

## Guard Recap (do not skip)

- **IDEMPOTENT** — every `gh label`/milestone guarded by existence check; CLAUDE.md merged not clobbered; re-running is safe.
- **EXCESSIVE-AGENCY GATE** — Phase-3 y/n confirmation before any GitHub object, tag, or commit, even in autonomous mode.
- **FAIL-LOUD / NO-SLOP** — unknowable fields carry explicit stub markers; never invent ADR rationale, alternatives, brand voice, user stories, or research.
- **FORWARD-ONLY** — no history rewrite; existing code = Phase-0 baseline; no retroactive issues.
