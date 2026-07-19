---
description: Fast read-only orientation on ANY repo (stack, structure, run/test commands) PLUS a R.Code-suitability verdict that can escalate to /rcode-migrate. Lightweight — for deep docs-audit + asset scaffolding use /bootstrap instead.
argument-hint: [notes]
model: claude-fable-5[1m]
allowed-tools: Read, Glob, Grep, Bash(git rev-parse:*), Bash(git branch:*), Bash(git log:*), Bash(git rev-list:*), Bash(git shortlog:*), Bash(git status:*), Bash(git tag:*), Bash(pwd:*), Bash(gh issue list:*), Bash(gh pr list:*), Bash(gh repo view:*), Bash(gh api:*), AskUserQuestion
---

<!-- controller-contract:v1 exempt="read-only/mechanical, no agent dispatch" -->

# Simple Onboard — Fast Orientation + R.Code-Suitability Verdict

You orient a developer (or a fresh agent) on **any** repository — R.Code-managed or not — in a couple of minutes, then give a read-only verdict on whether the project is a good fit for the R.Code atomic development workflow.

## Operating constraints (READ FIRST)

- **READ-ONLY. No writes, ever.** This command onboards and reports. It MUST NOT create, edit, move, or delete any file (no CLAUDE.md, no docs, no scaffolding). If the user wants docs consolidation or asset scaffolding, point them to `/bootstrap`.
- **This is NOT a fourth exploration engine.** Three already exist:
  - `/bootstrap` — heavy explorer (opus): docs audit + consolidation + asset scaffolding. Send the user here for deep work.
  - `rcode-onboard` skill — orients on an *already* R.Code-managed project (reads PROJECT-STATUS, agent-log, etc.).
  - `project-bootstrap` skill — read-only explorer that bootstraps Memory MCP.
  Your niche is **FAST orient + methodology recommendation**. Stay lightweight. Do NOT consolidate docs, do NOT enumerate every file, do NOT read whole source trees.
- Ignore heavy dirs in all scans: `node_modules`, `.next`, `.turbo`, `dist`, `build`, `.venv`, `target`, `coverage`, `.git`.
- Never read `.env*` or secrets. Redact anything secret-shaped that surfaces.
- `$ARGUMENTS` is optional free-text context (e.g. "focus on the API package") — weave it in if present.

---

## PART A — FAST ORIENT (lighter than /bootstrap)

Goal: a tight orientation, NOT a docs audit. Gather just enough to answer "what is this, how do I run it, where do I start."

### A1. Context (read-only)

Run:
- `git rev-parse --show-toplevel` — repo root (if this fails, it's not a git repo — note that and skip git-derived signals in Part B)
- `git branch --show-current`
- `git status -s`
- `git log --oneline -10`

### A2. Detect stack + tooling

Use **Glob/Grep/Read**, not `find`/`cat`. Read only manifests + README, not source trees.

- **Package manager + stack** from whichever exist: `package.json` (+ `pnpm-lock.yaml` / `yarn.lock` / `package-lock.json` / `bun.lockb`), `pyproject.toml` / `requirements*.txt` / `uv.lock`, `go.mod`, `Cargo.toml`, `Gemfile`, `composer.json`, `*.xcodeproj` / `Package.swift` (Swift/iOS), `pubspec.yaml` (Flutter).
- **Frameworks** from deps + config files: Next.js, React, Vue, Svelte, FastAPI, Django, Rails, SwiftUI/SwiftData, etc.
- **Monorepo surface** (also feeds Part B): `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, workspaces field, `/apps`, `/packages`, `/services`.

### A3. Map structure + entry points

- Top-level dirs (one `Glob` of the root, ignore heavy dirs).
- Entry points: `src/main.*`, `src/index.*`, `app/`, `pages/`, `cmd/`, `main.go`, `manage.py`, `App.swift`, the `main`/`bin`/`scripts` field in the manifest.
- 3–6 **key files** worth opening first (router, top-level app component, server bootstrap, config).

### A4. How to install / run / test

Pull verbatim from, in priority order: `package.json` `scripts`, `Makefile` targets, `Taskfile.yml`, `justfile`, then README "Getting Started" / "Development" section. Report the **exact commands** (install, dev/run, build, test, lint). Do not invent commands — if none are discoverable, say so.

### A5. One-paragraph "what this app is"

From README description / `package.json` `"description"` / pyproject description. One paragraph, plain language. If no description exists, infer cautiously from structure and say it's inferred.

---

## PART B — RCODE-SUITABILITY VERDICT (read-only signals)

R.Code is an **atomic, issue-driven development workflow** for **large, long-lived, multi-agent** software projects. It imposes: one issue = one branch = one PR, a `.rcode/` scope manifest, `PROJECT-STATUS.md` / phase gates, conventional `type(area): … - closes #N` commits, and a GitHub issue tracker as the source of truth. It pays off when project scale + handoff risk make ad-hoc workflows lose information; it is pure overhead on small or throwaway work.

Compute a verdict — **STRONG**, **MODERATE**, or **NOT RECOMMENDED** — from read-only signals. Do NOT mutate anything to gather them.

### B1. Already-managed / disqualifier checks (do these first)

- **`.rcode/` exists** → already R.Code-managed. Verdict is **NOT RECOMMENDED (already adopted)**; route the user to the `rcode-onboard` skill / `/status-sync`, and run Part D.
- **Another disciplined workflow already present** (e.g. `.changeset/`, a strict `CONTRIBUTING.md` with enforced PR/issue process, a release-please / semantic-release config, dense conventional-commit history) → lean **NOT RECOMMENDED** (don't layer a second methodology). Note what's already in place.
- **iOS / SwiftData project** (`.xcodeproj`, `Package.swift`, SwiftUI/SwiftData) → if otherwise suitable, route to the **rcode-ios** variant rather than the generic flow. Say so explicitly in the verdict.

### B2. POSITIVE signals (push toward recommend)

Gather read-only; each present signal increases suitability:

- **Scale / longevity**
  - Git history age: `git log --reverse --format=%ad --date=short | head -1` → first commit; older than ~6–12 months is positive.
  - Commit count: `git rev-list --count HEAD` — high count is positive.
  - Issue volume (requires `gh`): `gh issue list --state open --limit 1 --json number` plus `gh issue list --state all --limit 1 --json number` headers, or `gh repo view --json … ` counts. ~50+ open or ~200+ total issues is a strong positive.
  - Milestones: `gh api repos/{owner}/{repo}/milestones --jq 'length'` — several milestones is positive.
- **Large surface**: monorepo with multiple `apps/` / `packages/` / `services/` (from A2/A3).
- **Multiple contributors / multi-agent handoff risk** (the core problem R.Code solves):
  - `git shortlog -sn --all | head` → **3+ distinct contributors** is positive.
  - **Many `Co-Authored-By: Claude` commits**: `git log --grep='Co-Authored-By: Claude' --oneline | wc -l` — a high count signals agent-handoff churn, a strong positive.
- **Structure-deficit** (the gaps R.Code fills — their ABSENCE is the positive signal):
  - No scope manifest / `SPECIFICATION.md`.
  - No `PROJECT-STATUS.md` / `ROADMAP.md`.
  - Inconsistent commit messages **lacking** the `type(area): … closes #N` shape (sample `git log --oneline -50` and eyeball the ratio).
  - Long-lived / multi-issue branches: `git branch -a` showing branches that don't map 1:1 to issues.
  - Scope-creep evidence: large sprawling commits, "while I was here" messages, merge commits bundling unrelated work.

### B3. REQUIRED substrate (prerequisite, not auto-disqualifier)

- R.Code requires a **GitHub issue tracker**. Detect via `gh repo view` succeeding + issues being usable.
- If **absent** (no GitHub remote / issues disabled): this is a **prerequisite gap** that **raises adoption cost** — it does NOT auto-disqualify. Note it explicitly as "would need a GitHub issue tracker set up first" and factor it as a cost, not a veto.

### B4. NEGATIVE signals (push toward NOT recommend)

- Small / short-lived: few commits, < ~3 months old, tiny surface.
- Single-author and single-package.
- Throwaway / prototype / scratch (name or README says so; `experiments/`, `sandbox/`, `poc/`).
- Already under another disciplined workflow, or already `.rcode/` (from B1).

### B5. Verdict rubric

Weigh B2 positives against B4 negatives; treat B3 absence as added cost.

- **STRONG** — clear scale/longevity AND handoff risk (3+ contributors and/or many Claude-coauthored commits) AND a real structure-deficit. The methodology would plug visible information-loss. (If GitHub tracker absent, still STRONG but flag the setup cost.)
- **MODERATE** — some positives but mixed: e.g. long-lived but single-author, or large surface but already partially structured, or strong on scale but the GitHub-tracker substrate is missing (raising cost). Worth offering, with caveats.
- **NOT RECOMMENDED** — dominated by negatives (small/short/single-author/single-package/throwaway) OR already disciplined OR already `.rcode/`.

State the verdict as one line with the **single most load-bearing reason**.

---

## PART C — ESCALATION (only if STRONG or MODERATE)

If the verdict is **STRONG** or **MODERATE**, use **AskUserQuestion** to offer the migration. The question block must:

1. **Briefly explain R.Code** — one sentence: "atomic, issue-driven development for large / long-lived / multi-agent projects; trades a little ceremony for durable status + clean handoffs."
2. **Show the one-line verdict reason** (the load-bearing reason from B5).
3. **Offer to run `/rcode-migrate`.**

Use options roughly like:
- **"Yes — migrate"** → instruct the user to invoke `/rcode-migrate` (it converts an existing repo into a R.Code-managed project). If a `/rcode-migrate` command is not available in this environment, fall back to recommending `/brainstorm` to scaffold the R.Code foundation, and say so plainly — do not silently substitute.
- **"Tell me more first"** → give a 3–4 bullet summary of what migration changes (scope manifest, PROJECT-STATUS, conventional commits + closes #N, one-issue-one-branch-one-PR), then re-offer.
- **"No thanks"** → acknowledge in one line and stop. Do not nag.

For an **iOS/SwiftData** project, phrase the escalation toward the **rcode-ios** variant.

If the verdict is **NOT RECOMMENDED**: state it in **one line** with the reason and **do not** trigger AskUserQuestion or nag.

---

## PART D — UN-TICKETED / STRUCTURAL WORK (only if `.rcode/` exists)

If — and only if — a `.rcode/` directory exists, add a short note surfacing structural work that isn't tracked as a normal issue. Reuse the same surface as the `rcode-onboard` skill, read-only:

- **agent-log** (`.rcode/agent-log.md`) — last 1–2 entries: in-progress work, handoffs, recommended next action.
- **scope_changes[]** — any scope-manifest changes (`.rcode/scope-manifest.json` `scope_changes` array) not reflected in issues.
- **blocked issues** — from `PROJECT-STATUS.md` or `gh issue list --label blocked`.

Keep it to a few bullets. If no `.rcode/` exists, **skip Part D entirely** (it doesn't apply).

---

## OUTPUT — compact report

Print this and nothing heavier:

```markdown
# Onboard — <project name>

## What it is
<one paragraph from A5>

## Stack & structure
- **Stack:** <languages / frameworks>  •  **Pkg mgr:** <pm>  •  **Surface:** <single pkg | monorepo: N apps/M packages>
- **Entry points:** <key entry files>
- **Key files to read first:** <3–6 paths>

## Run it
- Install: `<cmd>`
- Dev/Run: `<cmd>`
- Test:    `<cmd>`
- Build:   `<cmd>`
(omit any that don't exist; note if none were discoverable)

## R.Code suitability: **<STRONG | MODERATE | NOT RECOMMENDED>**
> <one-line load-bearing reason>

- Signals for:    <top positive signals, e.g. "18mo history, 5 contributors, 312 Claude-coauthored commits, no PROJECT-STATUS, non-conventional commits">
- Signals against / cost: <e.g. "no GitHub issue tracker yet — would need setup first">
- Substrate: <GitHub issue tracker present | absent (adoption cost)>
<if iOS:> - Route: rcode-ios variant

<!-- Part D block only if .rcode/ exists -->
## Un-ticketed / structural work
- <agent-log last action / handoff>
- <scope_changes not reflected in issues>
- <blocked issues>
```

Then, **only if STRONG/MODERATE**, trigger the Part C AskUserQuestion. Keep the whole response compact — this is fast orientation, not an audit. For anything deeper, tell the user to run `/bootstrap`.
