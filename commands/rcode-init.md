---
description: "Initialize a FRESH / greenfield project as a R.Code-managed project. Lays down the .rcode/ workflow state, installs + wires the rules, and seeds the bridge files — so every later command (/brainstorm, /decompose, /issue, /phase-gate) runs inside the framework. The greenfield counterpart to /rcode-migrate: it has no code to reverse-engineer, so it scaffolds the rails and runs a SHORT interview instead of inventing product content."
argument-hint: "[optional: project name or a one-line description]"
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
  - Bash(touch:*)
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `agents/control-agent.md` §4.

# R.Code Init — Lay the Rails for a Fresh Project

You are executing the R.Code `/rcode-init` command. This brings a **fresh / greenfield project** under R.Code management by installing the **workflow infrastructure only** — not product content.

Think of it as the **greenfield counterpart to `/rcode-migrate`**:

| Command | Starting point | How it fills the artifacts |
|---------|----------------|----------------------------|
| `/rcode-migrate` | an existing codebase | **reverse-engineers** from code + git history |
| `/rcode-init` | an empty / fresh project | **scaffolds the rails** + a SHORT interview; leaves product content as honest stubs |
| `/brainstorm` | a concrete app idea | **generates** the full product foundation (research/spec/design/arch/plan) |

`/rcode-init` deliberately does **NOT** run research, invent features, or generate the product foundation. It lays down the `.rcode/` state, wires the rules into the project, and creates the two bridge files (`PROJECT-STATUS.md`, `START_HERE.md`) that downstream commands require. When it finishes, the project **is** R.Code-managed and the user can either run `/brainstorm` (to generate the product foundation) or start working directly in the framework.

**INPUT (optional context):** $ARGUMENTS

---

## Core Principles (read before doing anything)

1. **INFRASTRUCTURE ONLY.** Init lays the rails; it does not generate product content. It NEVER invents architecture, conventions, features, user stories, brand voice, or a research plan. Those are `/brainstorm`'s job. Anything not knowable at init time is written as an **explicit stub** that points to the command that fills it — never a fabricated value.
2. **FAIL-LOUD / NO-SLOP.** Per `fail-loud.md` + `slop-prevention.md`: every field you cannot fill from the SHORT interview or from a detected manifest gets a stub marker like `[not yet defined — run /brainstorm to generate]`. Empty is honest; invented is slop. The `scope-manifest.json` ships with `features: []`, not a fabricated `F001`.
3. **IDEMPOTENT.** Safe to re-run. Detect an existing `.rcode/` (Phase 0) and reconcile rather than clobber. Never overwrite a populated `CLAUDE.md` — **merge** the R.Code block in. Guard every file write against an existing richer version (a file already produced by `/brainstorm`/`/migrate` wins — skip it and say so).
4. **GREENFIELD-ONLY, SOFT HAND-OFF.** Init is for empty / near-empty / boilerplate-only projects. If it detects a **substantial existing codebase**, it does NOT hard-abort — it recommends `/rcode-migrate` (which can actually reverse-engineer) and asks whether to proceed anyway. Boilerplate (e.g. `create-next-app` output) is fine: detect the stack, but do NOT reverse-engineer features.
5. **EXCESSIVE-AGENCY-GATE.** Local scaffold writes are reversible and need no gate. But `git init`, the initial commit, and any **remote** creation (`gh repo create`, adding a remote) change durable / external state — gate them behind an explicit `y/n` confirmation and PAUSE, **even in autonomous / YOLO mode** (per `agency-bands.md`). Init creates **no** GitHub labels / milestones / issues — that stays `/decompose`'s job; do not duplicate it.

---

## Phase 0 — DETECT & ROUTE (read-only, NO gate)

Decide whether init is the right command, and gather the few facts the scaffold needs.

### 0.1 Already a R.Code project? (existence ≠ completeness)

```bash
ls -la .rcode 2>/dev/null
```

Do NOT key the decision on the directory alone. A prior run could have been interrupted mid-scaffold — Phase 2.1 creates `.rcode/phase-summaries/` as one of the *first* writes, so the dir can exist while the scaffold is incomplete. Probe the **required scaffold set**:

```bash
for f in .rcode/config.json .rcode/scope-manifest.json \
         .claude/rules/rcode-workflow.md .claude/rules/rcode-commits.md \
         .claude/rules/rcode-scope.md PROJECT-STATUS.md START_HERE.md; do
  [ -f "$f" ] && echo "ok   $f" || echo "MISS $f"
done
```

- **`.rcode/` absent** → fresh init, continue normally.
- **All required files present** → already fully R.Code-managed. Do **not** re-scaffold. Report and route: "Already R.Code-managed. Use `/status-sync` to reconcile state, `/rcode-onboard` to orient, or `/brainstorm` if the product foundation was never generated." Then **STOP** (no writes).
- **Some present, some `MISS`** → a partial / interrupted scaffold. Auto-enter the **idempotent repair path** (no special incantation needed): if `config.json` already holds the interview answers, read them and skip Phase 1; otherwise ask only for the missing fields. Re-run Phase 2 with the skip-if-richer guards active (they already preserve any richer file produced by `/brainstorm` or `/migrate`), filling ONLY the `MISS` pieces. Report exactly which files were repaired.

### 0.2 Greenfield check — is there already a real codebase?

Measure the source surface (ignore heavy dirs and boilerplate config). Use `Glob`:

```
**/*.{ts,tsx,js,jsx,py,go,rs,swift,rb,java,kt,php,vue,svelte}
```

…excluding `node_modules`, `.next`, `.turbo`, `dist`, `build`, `.venv`, `target`, `coverage`, `.git`.

Classify by hand-source-file count (files the user actually wrote, not generated scaffold):

| Source files | Classification | Action |
|--------------|----------------|--------|
| 0 | **Empty greenfield** | Proceed — pure scaffold. |
| 1–~15, looks like framework boilerplate (matches a known starter layout, single author, < a handful of commits) | **Boilerplate greenfield** | Proceed — detect stack (0.4), but do NOT reverse-engineer features. |
| > ~15 hand-written source files, OR multiple feature dirs, OR meaningful git history | **Substantial codebase** | This is `/rcode-migrate` territory. Surface it and ask (0.3). |

> These thresholds are heuristics, not hard gates — mirror the advisory-signal logic in `/rcode-migrate` Phase 0.2 and `framework-extraction.md`. When borderline, explain what you see and let the user decide.

### 0.3 Soft hand-off (only if "Substantial codebase")

Do NOT abort. Use `AskUserQuestion`:

> "This project already has a real codebase ([N] source files, [N] commits). `/rcode-migrate` is built for this — it reverse-engineers conventions, architecture, and features from the existing code + git history, which `/rcode-init` will not do (it would leave those as empty stubs). Recommended: run `/rcode-migrate` instead. Proceed with the lightweight init anyway?"

Options: **"Use /rcode-migrate (recommended)"** → stop, instruct the user to run it. · **"Proceed with init anyway"** → continue (the stubs will be honest about what wasn't captured). · **"Cancel"** → stop.

### 0.4 Detect git + stack (read-only)

```bash
# Git substrate (for the Phase-3 gated offer)
git rev-parse --is-inside-work-tree 2>/dev/null     # in a repo?
git remote -v 2>/dev/null                            # remote configured?
git branch --show-current 2>/dev/null
git log --oneline 2>/dev/null | wc -l                # commit count
```

Detect any declared stack from manifests **if present** (boilerplate case) — read, don't guess:

```bash
ls package.json pnpm-lock.yaml yarn.lock package-lock.json bun.lockb \
   pyproject.toml requirements.txt poetry.lock Pipfile uv.lock \
   go.mod Cargo.toml Gemfile composer.json *.csproj \
   Package.swift pubspec.yaml 2>/dev/null
```

From whatever exists, derive: language(s), framework(s), package manager, and the **real toolchain commands** for the pre-commit trio (Phase 2 CLAUDE.md). If NOTHING is declared (pure empty greenfield), the stack is **unknown** — that is expected; capture it in the interview (Phase 1) or leave it stubbed. Do NOT invent a stack.

---

## Phase 1 — SHORT INTERVIEW (the few human-only fields)

Init knows almost nothing from disk on an empty project, so capture the minimum needed to make the scaffold real — and **only** the minimum. Use `AskUserQuestion`. Everything not asked here is stubbed, never invented.

Pre-fill answers from `$ARGUMENTS` where possible (e.g. if the user already passed a name/description, confirm rather than re-ask).

Ask (collapse into as few `AskUserQuestion` blocks as possible):

1. **Project name** — default to the current directory name; let the user confirm/override.
2. **One-line vision** — "In one sentence, what is this project and who is it for?" (Goes into `START_HERE.md` "What Is This?" and `CLAUDE.md` overview. If the user declines, stub it.)
3. **Project type** — Web app / API / Mobile / CLI / Library / Other.
4. **Stack** — ONLY if not already detected in 0.4. Offer the common stacks as options (e.g. "Next.js + TypeScript", "Python / FastAPI", "Go", "Swift / iOS", "Undecided — decide during /brainstorm"). "Undecided" is a first-class answer → the pre-commit trio and stack rules are stubbed until `/brainstorm` settles the architecture.

Keep it to **these four**. Do not interview for architecture, features, conventions, or research — those belong to `/brainstorm`.

---

## Phase 2 — SCAFFOLD (local writes, NO gate)

Create the infrastructure. All writes here are local and reversible — no gate. Apply the **skip-if-richer** guard before each write: if a file already exists with real content (e.g. a hand-written `README.md`, or a `CLAUDE.md` with user notes), **merge** the R.Code block rather than overwrite.

> Reference the EXACT template field names from `~/.claude/rcode/templates/` so downstream commands (`/status-sync`, `/issue`, `/phase-gate`) parse the files correctly.

### 2.1 `.rcode/` workflow state

```bash
mkdir -p .rcode/phase-summaries
touch .rcode/phase-summaries/.gitkeep   # keep the empty dir under version control
```

**`.rcode/config.json`** (no template — construct it; `status: "initialized"` distinguishes it from brainstorm's `"brainstormed"` and migrate's `"migrated"`):

```json
{
  "project_name": "[from interview]",
  "repository": "[git remote URL, or null if no remote yet]",
  "created_date": "[today YYYY-MM-DD]",
  "workflow_version": "2.0.0",
  "framework_version": "[first line of ~/.claude/rcode/VERSION]",
  "total_phases": 0,
  "total_issues": 0,
  "current_phase": 0,
  "status": "initialized"
}
```

> **`framework_version`** is the global R.Code rail version — `Read` the **first line** of `~/.claude/rcode/VERSION` and stamp it verbatim (never hardcode a date). It lets `/rcode-upgrade` later diff this project's rails against the current global set. If the VERSION file is missing, write `null` and say so in the Phase-4 report — never invent a version (per `fail-loud.md`).

**`.rcode/scope-manifest.json`** — from `SCOPE-MANIFEST.template.json`, but with an **empty** feature list (inventing features would be slop; `/brainstorm` or `/decompose` populates them):

```json
{
  "project_name": "[name]",
  "created_date": "[today]",
  "version": "1.0.0",
  "locked": false,
  "locked_date": null,
  "total_issues": 0,
  "total_features": 0,
  "features": [],
  "scope_changes": [],
  "metadata": {
    "created_by": "rcode-init",
    "last_updated": "[today]",
    "last_updated_by": "rcode-init"
  }
}
```

**`.rcode/agent-log.md`** — seed entry:

```markdown
# Agent Log — [Project Name]

> Append-only session history. Never delete entries.

---

## Session: Init

**Date:** [today]
**Agent:** rcode-init

**Actions:**
- Initialized fresh project into the R.Code workflow
- Created .rcode/ state (config, empty scope-manifest, logs)
- Installed + wired workflow rules into .claude/rules/ and CLAUDE.md
- Seeded bridge files (PROJECT-STATUS.md, START_HERE.md) in the "initialized, not yet planned" state
- Product foundation NOT generated (stubbed) — pending /brainstorm

**Next Steps:**
- Run /brainstorm to generate the product foundation (research, spec, architecture, plan), OR start defining work directly
- Then /decompose to create GitHub issues, then /issue <#> for the daily loop
```

**`.rcode/blocked-issues.md`** — standard empty stub:

```markdown
# Blocked Issues

> Issues that cannot proceed. Updated by `/issue` and `/status-sync`.

No blocked issues yet.
```

### 2.2 Install + wire the rules

```bash
mkdir -p .claude/rules
cp ~/.claude/rcode/rules/rcode-workflow.md .claude/rules/
cp ~/.claude/rcode/rules/rcode-commits.md  .claude/rules/
cp ~/.claude/rcode/rules/rcode-scope.md    .claude/rules/
```

**Stack-specific rules** — copy ONLY if the stack was detected/declared in Phase 0/1 (skip entirely if "Undecided"):
- Next.js App Router → `cp ~/.claude/rcode/templates/project-rules/nextjs-app-router.rule.md .claude/rules/`
- Supabase → `supabase.rule.md` · Convex → `convex.rule.md` · Python/FastAPI → `python-fastapi.rule.md` · React + animation → `react-performance.rule.md`

> If "Undecided", note in the report that stack rules will be added by `/brainstorm` once the architecture is chosen.

### 2.3 `CLAUDE.md` (merge, never clobber)

From `~/.claude/rcode/templates/CLAUDE-PROJECT.template.md`. Ensure the rule imports are at the top:

```markdown
@.claude/rules/rcode-workflow.md
@.claude/rules/rcode-commits.md
@.claude/rules/rcode-scope.md
```

Fill what's known from the interview (project name, type, one-line vision → overview). **Adapt the "Mandatory Pre-Commit" trio to the detected/declared toolchain** — do NOT hardcode `tsc && test && build`:
- Node/TS → `npx tsc --noEmit && npm test && npm run build`
- Python → `mypy . && pytest && ruff check .`
- Rust → `cargo build && cargo test && cargo clippy`
- Go → `go build ./... && go test ./... && go vet ./...`
- **Undecided** → stub it: `[pre-commit trio — set once the stack is chosen in /brainstorm]`

Everything not yet known (Quick Architecture table, Critical Conventions, Current Status detail) gets a stub marker `[not yet defined — run /brainstorm to generate]`, NOT a fabricated value.

> **If `CLAUDE.md` already exists** (e.g. the user has personal notes): merge — prepend the rule imports if missing and add a R.Code section; preserve all existing content. Never overwrite.

### 2.4 Bridge files — `PROJECT-STATUS.md` + `START_HERE.md`

These two are the files `/issue` Phase 0 and `/status-sync` REQUIRE. Create them in the **"initialized, nothing planned yet"** state.

**`PROJECT-STATUS.md`** — from `PROJECT-STATUS.template.md`:
- **Current Status:** `Active Phase: Phase 0 — Initialization (no development phases planned yet)` · `Overall Progress: Not yet planned — run /brainstorm to generate the product foundation` · `Last Updated: [now]` · `Last Updated By: rcode-init`. (Write the progress as prose, NOT a degenerate "0/0 issues / 0%" — there is no real phase yet, and "0 of 0" reads as a bug to anyone onboarding.)
- **Progress by Phase:** a single row — `| 0 | Initialization | 0 | 0 | 0 | 0 | 0 | 0% |` — with a note: `No development phases defined yet. Run /brainstorm → /decompose to populate.`
- **Next Available Issues / In Progress / Blocked / Recent Activity:** empty, each with the explicit note `None yet — run /decompose to create issues.`
- **Scope Health:** `Scope Manifest Status: Unlocked` · `Total Features: 0` · `Scope Changes: 0`.
- **Roadmap / Strategic Prioritization:** `Strategic Posture: Consolidate — project just initialized; foundation not yet generated.` Priority table → single stub row pointing to `/brainstorm`. `Recommended Next Strategic Move: Run /brainstorm to generate the product foundation.`
- **Quality Metrics:** mark each `[not configured]` until a stack + tooling exist (do NOT write `0` for tools that aren't set up — that would be a false green, per `fail-loud.md`).

**`START_HERE.md`** — from `START-HERE.template.md`:
- "What Is This?" → the one-line vision from the interview (or stub if declined).
- Tech Stack table → filled if detected/declared, else `[to be decided — see /brainstorm]`.
- Current Status → render as prose, NOT a degenerate "Phase 0 of 0 — 0% complete": `Initialized — not yet planned. Run /brainstorm to generate the product foundation.` (There is no real phase yet; the "Phase [N] of [M]" numeric form only makes sense once `/decompose` exists. Keep this aligned with the PROJECT-STATUS prose above.)
- Environment Setup / commands → real commands if a stack is present, else stub.
- Key Documents table → keep as-is (the doc set the framework expects), but the not-yet-generated ones (`ARCHITECTURE.md`, `SPECIFICATION.md`, `BRAINSTORM.md`, `RESEARCH_FINDINGS.md`, `CONVENTIONS.md`) are flagged "generated by /brainstorm".

### 2.5 `.gitignore` (only if absent, minimal)

If no `.gitignore` exists, create a minimal one that at least protects secrets (`.env`, `.env.*`, `!.env.example`) and the obvious heavy dirs for the detected stack. If one exists, leave it untouched. Keep this light — full ignore rules are the project's concern, not init's.

> Do NOT generate `ARCHITECTURE.md`, `SPECIFICATION.md`, `BRAINSTORM.md`, `RESEARCH_FINDINGS.md`, `CONVENTIONS.md`, `CONTRIBUTING.md`, or `README.md` content here. Those are product foundation → `/brainstorm`. Creating empty stubs of them is fine ONLY if you mark them clearly as "to be generated by /brainstorm"; preferring NOT to create them keeps the tree honest. Default: do not create them.

---

## Phase 3 — GIT (⛔ EXCESSIVE-AGENCY GATE — optional, even in autonomous mode)

Local scaffold (Phase 2) is already on disk and needs no gate. This phase touches **durable / external** state, so it is gated. Init creates **NO** GitHub labels, milestones, or issues — that is `/decompose`'s job.

> **Trunk-commit exception (named on purpose):** the initial scaffold commit lands on the fresh repo's trunk (`main`/`master`). `workflow-git.md` forbids direct-to-trunk commits in general — but a brand-new repo has only a root commit to make, no feature branch or PR is meaningful before `/decompose`, and the commit is fully local-reversible (`git reset` / delete `.git`). This is the sanctioned **project-bootstrap exception**; the sibling `/rcode-migrate` relies on the identical exception for its baseline commit.

### 3.1 Determine what (if anything) to offer

From Phase 0.4:
- **No git repo** → offer `git init` + an initial commit of the scaffold. Optionally offer to create a GitHub remote.
- **Git repo, no remote** → offer the initial scaffold commit. Optionally offer to create + link a remote.
- **Git repo + remote** → offer the initial scaffold commit only.

### 3.2 GATE — present and PAUSE

Print a summary and ask `y/n` (do not proceed without an explicit `y` — this holds in autonomous / YOLO mode too):

```
⛔ R.Code Init — about to change durable/external state:

  git init:        [yes / not needed (already a repo)]
  Initial commit:  scaffold files on branch [main/current]
                   → .rcode/, .claude/rules/rcode-*.md,
                     CLAUDE.md, PROJECT-STATUS.md, START_HERE.md [, .gitignore]
  GitHub remote:   [none / OFFER gh repo create <name> --private]   ← only if user opted in

  NOT touched: no labels, no milestones, no issues (that's /decompose).

Repo: [owner/repo or "local only"]   Branch: [name]

Proceed? (y/n)
```

- **Remote creation** (`gh repo create`, adding a remote, `git push`) is **irreversible / external** → it is the part that genuinely needs the gate. Only offer it if the user asked for a remote; default is **local-only**.
- A purely local `git init` + first commit is reversible (`rm -rf .git` / `git reset`), but bundle it into the same single `y/n` for one clean confirmation.
- If `n` → stop. All Phase-2 files remain on disk for the user to review / commit themselves. Say so plainly.

### 3.3 Execute (only after `y`)

> **This command's execution correctness is the only safety layer here.** Neither `gh repo create` nor a non-force `git push` is in the deterministic bash-gate ESCALATE set (that set is `git push --force`, `gh pr merge/close`, `gh release create`). So per `fail-loud.md`: do NOT suppress errors, and do NOT chain an irreversible step after an unverified one. Surface failures; make each step conditional on the previous succeeding.

```bash
# only if not already a repo
git init

# stage exactly the scaffold this run created — NO stderr suppression (fail-loud).
git add .rcode/ .claude/rules/ CLAUDE.md PROJECT-STATUS.md START_HERE.md
# add .gitignore ONLY if YOU created it in Phase 2.5 this run; omit it otherwise
# (a pre-existing .gitignore must not be swept into a commit that claims only-scaffold).

# commit only if something was actually staged — avoid a silent no-op the report would misreport as a commit
if git diff --cached --quiet; then
  echo "Nothing staged (scaffold may already be committed) — skipping commit, not failing."
else
  git commit -m "$(cat <<'EOF'
chore(project): initialize R.Code workflow scaffold

Laid the R.Code rails for a fresh project (infrastructure only —
product foundation pending /brainstorm):
- .rcode/ state (config, empty scope-manifest, logs)
- .claude/rules/rcode-{workflow,commits,scope}.md wired into CLAUDE.md
- PROJECT-STATUS.md + START_HERE.md bridge files (Phase 0 — initialized)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
fi
```

If (and only if) the user opted into a remote — gate the push on repo-creation **succeeding** (`&&`), so a failed `gh repo create` (auth error, name collision) never pushes to a stale or wrong remote:

```bash
gh repo create [name] --private --source=. --remote=origin \
  && git push -u origin "$(git branch --show-current)"
```

If `gh repo create` fails, STOP and report its error verbatim — do not retry blindly and do not push to an unverified remote.

> No git tag here (init is not a milestone). `/decompose` creates the first tag (`scope-lock-*`).

Append a one-line outcome to `.rcode/agent-log.md` if the commit/remote happened.

---

## Phase 4 — VERIFY & REPORT

Display a structured summary:

```
R.Code Init Complete — the rails are laid.

Project: [name]   ([type])   Stack: [detected/declared or "undecided — pending /brainstorm"]
Mode: [empty greenfield / boilerplate greenfield / init-anyway over existing code]

Created (infrastructure):
  - .rcode/config.json            [status: initialized]
  - .rcode/scope-manifest.json    [unlocked, 0 features]
  - .rcode/agent-log.md, blocked-issues.md, phase-summaries/
  - .claude/rules/rcode-{workflow,commits,scope}.md   [+ stack rules if any]
  - CLAUDE.md                          [rules wired; pre-commit trio: <trio or stub>]
  - PROJECT-STATUS.md                  [Phase 0 — initialized]
  - START_HERE.md                      [vision + onboarding]
  [- .gitignore                        [created — secrets protected] ]

Stubbed (honest — to be generated by /brainstorm):
  - ARCHITECTURE / SPECIFICATION / CONVENTIONS / BRAINSTORM / RESEARCH_FINDINGS
  - CLAUDE.md architecture + conventions sections
  - Quality metrics ([not configured] until tooling exists)

Git: [git init done | already a repo] · [commit <sha> | left uncommitted for review] · [remote created | local only]

The project is now R.Code-managed — every command runs in the framework from here.

Next step (choose one):
  • /brainstorm "<idea + target group + user story>"   ← generate the full product foundation (recommended)
  • or define a few features yourself, then /decompose   ← for a simple project
  • then /issue <#> for the daily development loop
```

> **Surface this handoff caveat in the report:** `/brainstorm` is NOT idempotent against an init'd tree — it regenerates `.rcode/` and overwrites this init scaffold (config `created_date`, the seed `## Session: Init` agent-log entry, `START_HERE.md`, `CLAUDE.md`). For a fresh project this is **expected and harmless**: the interview answers are placeholders, not yet load-bearing. If you instead skip `/brainstorm` and define work manually (or via `/decompose`), the init scaffold persists as-is.

---

## Guard Recap (do not skip)

- **INFRASTRUCTURE ONLY** — no invented architecture/features/conventions; product content is stubbed and pointed at `/brainstorm`.
- **FAIL-LOUD / NO-SLOP** — unknown fields carry explicit stub markers; `scope-manifest` ships with `features: []`; quality metrics are `[not configured]`, never a false `0`.
- **IDEMPOTENT** — existing `.rcode/` halts re-scaffold; `CLAUDE.md` is merged not clobbered; richer existing files win.
- **GREENFIELD-ONLY, SOFT HAND-OFF** — substantial codebase → recommend `/rcode-migrate`, proceed only on explicit user confirm.
- **EXCESSIVE-AGENCY GATE** — `git init` / initial commit / remote creation gated behind one `y/n`, even in autonomous mode; remote creation is the genuinely irreversible part. **No** GitHub labels/milestones/issues — that's `/decompose`.
