---
description: "Convert BRAINSTORM.md into tracked work units — GitHub issues + milestones, or plan IDs (checkbox lines in BRAINSTORM.md) if no GitHub tracker. Run after /brainstorm."
model: claude-fable-5-1[1m]
allowed-tools:
  - Task
  - Read
  - Write
  - Edit
  - Bash(gh:*)
  - Bash(git:*)
  - Glob
  - Grep
  - AskUserQuestion
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `~/.claude/agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `~/.claude/agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `~/.claude/agents/control-agent.md` §4.

# R.Code Decompose — Work-Unit Creation Pipeline

You are executing the R.Code `/decompose` command. This converts the development plan in `BRAINSTORM.md` into tracked, actionable **work units** — either GitHub issues (tracker: `github`) or plan IDs (tracker: `plan`, checkbox lines in `BRAINSTORM.md`, no GitHub needed).

---

## Pre-Flight Checks

1. **Verify `BRAINSTORM.md` exists** — if not, instruct the user to run `/brainstorm` first.
2. **Verify git repository** — must be initialized (tracker-agnostic; a remote is only required for `tracker: github`).
3. **Verify scope manifest exists** — `.rcode/scope-manifest.json` must exist.
4. **Determine the tracker** (asked, never guessed):
   - `Read` `.rcode/config.json`. If it has a `tracker` field, use it — do not re-ask.
   - If absent, ask **once** via `AskUserQuestion`. Recommendation: **`github`** if a git remote exists AND `gh auth status` succeeds AND `gh issue list --state all --limit 1` returns ≥1 issue; otherwise **`plan`** (the common case — nothing to reconcile against yet).
   - Persist the answer into `.rcode/config.json`'s `tracker` field — `Edit` only that field; **preserve every other existing field verbatim** (created_date, framework_version, status, any legacy `workflow_version`, …) — never replace the object wholesale.
   - `tracker: github` also needs: git repository connected to a GitHub remote, `gh auth status` succeeding. If either is missing while the user picked `github`, stop and say so (fail-loud) rather than silently falling back to `plan`.
5. **Read `BRAINSTORM.md`** — parse all phases and the unit lines under each `### Phase N — <Name>` heading.
6. **Determine the next unit ID (both trackers).** Scan `BRAINSTORM.md` for every existing `P-NNN` ID in **either** grammar it might contain — checkbox lines (`- [ ] P-012 — …` / `- [x] P-012 — …`) AND table rows whose first cell is `| P-NNN |` — take the highest `NNN` found across both, and start numbering new plan units after it (zero-padded, ≥3 digits: `P-001`, …, `P-312`, `P-313`, …). This applies only in `tracker: plan`; `tracker: github` numbers issues via `gh issue create`'s own return value instead. **A table whose FIRST header cell is `#`/`ID`/`Nr`/`Nr.` and whose row first cell is an integer or `#`+integer (K-A — the Projekt N practice) is also a valid existing plan-unit table**, using a LOCAL plan number (`#N`, disambiguated from a GitHub issue by the `plan` tracker field, not by ID shape) — it is **never renumbered and never feeds the `P-NNN` counter** (a separate, local namespace). **Never rewrite an existing table row of either form** — new units are always appended in checkbox `P-NNN` form, regardless of which grammar(s) the file already used; a new unit is never assigned a bare `#N`.

---

## Step 1: Tracker branch

### github mode

Continue to Step 2 (Labels) through Step 4 (parallel-safe) below, **gated** by the ⛔ confirmation in Step 2.0.

### plan mode

Skip Steps 2–4 entirely (no GitHub objects exist in plan mode). Go straight to **Step 3-plan — Assign plan units** below, then continue at Step 5 (Lock Scope Manifest). No gate is needed for plan-mode unit assignment — it is a local, reversible write to `BRAINSTORM.md`.

---

## Step 2: Create Labels + Milestones (github mode only, ⛔ gated)

### 2.0 GATE — present and PAUSE (even in autonomous mode)

Before creating any GitHub object, print a summary and ask `y/n`:

```
⛔ R.Code Decompose — about to create GitHub objects (tracker: github):

  Labels:     [N] phase/type/area/workflow labels (existing ones skipped — idempotent)
  Milestones: [M] — one per Phase (existing ones skipped — idempotent)
  Issues:     [N] new (an issue with an identical title is skipped, not duplicated)
  Tag:        scope-lock-[today]        (Step 9 — local only, never pushed)
  Commit:     PROJECT-STATUS.md, BRAINSTORM.md, START_HERE.md,
              .rcode/scope-manifest.json[, .rcode/config.json if tracker was just persisted]

Repo: [owner/repo]   Branch: [current]

Proceed? (y/n)
```

If `n` → stop. `BRAINSTORM.md` and the scope manifest remain unlocked and on disk for review; nothing is created.

### 2.1 Create labels — IDEMPOTENTLY

`gh label create` FAILS on duplicates, which would violate fail-loud if blindly suppressed. **Check existence first**, then create only missing ones (same pattern as `~/.claude/commands/rcode-migrate.md` Phase 3.1):

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

### Phase Labels

```bash
create_label "phase-1" "0E8A16" "Phase 1: [Phase Name]"
create_label "phase-2" "1D76DB" "Phase 2: [Phase Name]"
create_label "phase-3" "D93F0B" "Phase 3: [Phase Name]"
# ... for each phase found in BRAINSTORM.md
```

### Type Labels

```bash
create_label "type:feature"       "0E8A16" "New feature"
create_label "type:fix"           "D93F0B" "Bug fix"
create_label "type:test"          "FBCA04" "Testing"
create_label "type:docs"          "0075CA" "Documentation"
create_label "type:infrastructure" "D4C5F9" "Infrastructure/tooling"
create_label "type:refactor"      "E4E669" "Code refactoring"
```

### Area Labels

```bash
create_label "area:auth"   "C2E0C6" "Authentication/authorization"
create_label "area:api"    "C2E0C6" "API endpoints"
create_label "area:ui"     "C2E0C6" "User interface"
create_label "area:db"     "C2E0C6" "Database/data layer"
create_label "area:config" "C2E0C6" "Configuration/setup"
create_label "area:core"   "C2E0C6" "Core business logic"
```

### Workflow Labels

```bash
create_label "blocked"       "B60205" "Blocked by another issue"
create_label "blocking"      "D93F0B" "Blocking other issues"
create_label "parallel-safe" "0E8A16" "Can be worked on in parallel"
create_label "rcode"         "5319E7" "R.Code workflow managed"
```

### 2.2 Create milestones — IDEMPOTENTLY

One milestone per phase, skipping any that already exist (same pattern as `rcode-migrate.md` Phase 3.2):

```bash
existing_milestones=$(gh api repos/{owner}/{repo}/milestones --jq '.[].title')
create_milestone() {  # title description
  if printf '%s\n' "$existing_milestones" | grep -qxF "$1"; then
    echo "milestone exists, skipping: $1"
  else
    gh api repos/{owner}/{repo}/milestones -f title="$1" -f description="$2" -f state="open"
  fi
}
create_milestone "Phase 1: [Phase Name]" "[Phase goal from BRAINSTORM.md]"
create_milestone "Phase 2: [Phase Name]" "[Phase goal]"
# ... for each phase
```

---

## Step 3: Create Issues (github mode only)

For EACH not-yet-numbered unit line in `BRAINSTORM.md`, first check whether an issue with the **exact same title** already exists (idempotent — mirrors the label/milestone pattern above), and skip creation if so:

```bash
existing_titles=$(gh issue list --state all --limit 1000 --json title --jq '.[].title')
if printf '%s\n' "$existing_titles" | grep -qxF "[Phase N] [Issue Title]"; then
  echo "issue exists, skipping: [Phase N] [Issue Title]"
else
  gh issue create \
    --title "[Phase N] [Issue Title]" \
    --label "phase-N,type:[type],area:[area],rcode" \
    --milestone "Phase N: [Phase Name]" \
    --body "$(cat <<'ISSUE_EOF'
## Description

[Clear description of what needs to be implemented]

## Acceptance Criteria

- [ ] [Specific, testable criterion 1]
- [ ] [Specific, testable criterion 2]
- [ ] [Specific, testable criterion 3]
- [ ] Code follows CONVENTIONS.md patterns
- [ ] Check trio passes (CLAUDE.md → Mandatory Pre-Commit)

## Scope Boundary

**IN SCOPE:**
- [What this issue covers]

**OUT OF SCOPE:**
- [What this issue does NOT cover — explicit boundaries]
- [Related work that belongs to other issues]

## Architectural Context

- Relevant ADR: [ADR-NNN from ARCHITECTURE.md, if any]
- Conventions: [Relevant section from CONVENTIONS.md]
- Design: [Relevant section from SPECIFICATION.md if UI work]

## Technical Details

- Files to create/modify: [list]
- Testing strategy: [unit/integration/e2e]
- Dependencies: [npm packages if any]
- Requires env: [comma-separated env var names this unit needs, or "none"]

## Predecessor Issues

- [#N — must be completed first (if any)]

## Successor Issues

- [#N — blocked until this is complete (if any)]

## Feature

Feature: [Feature ID from scope-manifest.json]
Phase: [Phase number]
ISSUE_EOF
)"
fi
```

### Issue Creation Order

Create issues **in phase order** so that issue numbers roughly correspond to implementation order. This makes the `BRAINSTORM.md` checkbox tracking more intuitive.

---

## Step 3-plan: Assign plan units (plan mode only, no gate)

For EACH not-yet-numbered unit line in `BRAINSTORM.md` (grouped under its `### Phase N — <Name>` heading), assign the next `P-NNN` ID (per the Pre-Flight §6 numbering rule) and rewrite it in checkbox form, appending optional indented body lines (per `~/.claude/rcode/templates/BRAINSTORM.template.md`'s unit-line comment — two or more leading spaces):

```markdown
- [ ] P-012 — <Title> `<type>` `<area>`[ `parallel-safe`][ `blocked-by:P-010`]
  Description: <what needs to be implemented>
  Acceptance: <criterion 1>; <criterion 2>; Code follows CONVENTIONS.md patterns; Check trio passes (CLAUDE.md → Mandatory Pre-Commit)
  Scope boundary: IN: <what this unit covers> / OUT: <what it explicitly does not>
  Requires env: <comma-separated env var names, or "none">
```

**Never rewrite an existing table-form row** (Pre-Flight §6) — only append new units in checkbox form. Mark `parallel-safe` units the same way `github` mode would via the label. Blocking relationships are documented via `blocked-by:P-NNN` directly in the unit line — plan mode has no native blocking field to fall back on.

---

## Step 4: Add Parallel-Safe Labels (github mode only)

After all issues are created, add the workflow label to the ones the plan marked parallel-safe:

```bash
gh issue edit [N] --add-label "parallel-safe"
```

Blocking relationships have no native GitHub field — document them in the issue body's Predecessor/Successor Issues sections (already part of the Step 3 template).

---

## Step 5: Lock Scope Manifest

Update `.rcode/scope-manifest.json` (tracker-agnostic — works the same whether units are `#N` or `P-NNN`):

1. Set `"locked": true`
2. Set `"locked_date": "[today]"`
3. **Backfill missing feature entries first (C29).** For each Core Feature
   (`F001`, `F002`, …) listed in `BRAINSTORM.md` that has **no matching
   entry** in `.rcode/scope-manifest.json`'s `features` array — the
   guaranteed state on the documented "skip `/brainstorm`, hand-write
   `BRAINSTORM.md`, run `/decompose` directly" path — create one: `name`/
   `description` from the `BRAINSTORM.md` feature block, `phase` from its
   first referencing unit. Do this BEFORE step 4 below populates `issues[]`,
   so every feature has somewhere to receive its unit IDs.
4. Populate each feature's `issues` array with the actual unit IDs (`#N` or `P-NNN`)
5. Update `total_issues` count (keeps its name for compatibility; counts units in either tracker)

---

## Step 6: Generate PROJECT-STATUS.md

Create `PROJECT-STATUS.md` from the `PROJECT-STATUS.template.md` with:

- All phases listed with unit counts (all at 0% complete)
- "Next Available Units" populated with Phase 1 parallel-safe units
- Empty "Currently In Progress" and "Recent Activity" sections
- Scope Health section showing the locked manifest

**Update `.rcode/config.json` (K-E):** set `total_phases` to the number of
`### Phase N — <Name>` headings just processed from `BRAINSTORM.md`,
`current_phase` to `1` (the first phase becomes active), and `status` to
`"decomposed"` — `status` is one of `initialized | brainstormed | migrated |
decomposed`, and this is the write that reaches the terminal value, the
same pattern `rcode-migrate.md`/`brainstorm.md` already follow for their
own status values. `Edit` only these three fields — preserve every other
field verbatim, including historical/legacy ones (A7). This is the write
that gives `current_phase` its first real value past scaffold time;
`/phase-gate` is the only later writer that
advances it (on PASS/WARN, to N+1).

### Populate the "Roadmap / Strategic Prioritization" section

The template includes a `## Roadmap / Strategic Prioritization` section (placed right after `## Scope Health`). Fill it with the **initial strategic ordering** derived from `BRAINSTORM.md` — do NOT leave the placeholders. Use this exact section format:

```markdown
## Roadmap / Strategic Prioritization

**Strategic Posture:** [Ship / Consolidate] — [one line: is now a good moment to ship/release or to consolidate? Derived from current phase completion %, open blockers, and test/quality status.]

| Priority | Phase / Milestone | Strategic Rationale | Suggested Timing | Must-Precede |
|----------|-------------------|---------------------|------------------|--------------|
| P1 | [Phase N — Name] | [Why this matters now] | [next release window / after Phase N gate / deferred] | [#N or P-NNN or blocking dependency] |
| P2 | [Phase N — Name] | [Why this matters] | [next release window / after Phase N gate / deferred] | [#N or P-NNN or —] |
| P3 | [Phase N — Name] | [Why this matters] | [next release window / after Phase N gate / deferred] | [#N or P-NNN or —] |

**Recommended Next Strategic Move:** [one-liner: what to prioritize next and WHY — the next strategic lever, not just the next unit.]
```

Populate it as follows:

- **Strategic Posture:** at decompose time nothing is shipped yet (0% complete, scope just locked) — so the posture is almost always `Consolidate` ("foundation phase, build before release"). Derive the one-liner from: overall completion % (0%), open blockers (none yet), and quality status (no tests/build yet).
- **Priority table:** Derive the initial P1/P2/P3 ranking from the `BRAINSTORM.md` **phase order**, **milestones** (github mode) or **Phase headings** (plan mode), and the **Dependencies** and **Risk** tables:
  - Earlier phases and risk-mitigating / dependency-unblocking work rank higher (P1).
  - Use one row per phase/milestone (or per the most strategically significant milestones if there are many phases).
  - **Phase / Milestone** = the `BRAINSTORM.md` phase name (+ its GitHub milestone, if any).
  - **Strategic Rationale** = why it comes first strategically (e.g. "unblocks all downstream auth work", "highest-risk integration — de-risk early").
  - **Suggested Timing** = `after Phase N gate` for sequenced phases; `next release window` for the first shippable milestone; `deferred` for nice-to-haves.
  - **Must-Precede** = blocking dependencies from the `BRAINSTORM.md` Dependencies table (predecessor phases/units that must complete first).
- **Recommended Next Strategic Move:** the single highest-leverage thing to do next (usually "complete Phase 1 foundation to unblock parallel work"), with the WHY — not merely "do unit #N/P-NNN".

---

## Step 7: Update BRAINSTORM.md

Update each unit line in `BRAINSTORM.md` with its actual ID — already done inline as part of Step 3 (github: `gh issue create`'s returned number) / Step 3-plan (plan: assigned `P-NNN`). Confirm every unit under a processed phase now carries an ID before continuing.

```markdown
# Before:
- [ ] Issue Title `feat` `auth`

# After (github):
- [ ] #42 — Issue Title `feat` `auth`

# After (plan):
- [ ] P-012 — Issue Title `feat` `auth`
```

---

## Step 8: Update START_HERE.md

Update the current status line:
```markdown
**Phase 1 of [M]** — [Phase Name] — **0% complete**
```

---

## Step 9: Git Tag (local only — never pushed)

```bash
git tag -a "scope-lock-$(date +%Y-%m-%d)" -m "Scope manifest locked: [N] units across [M] phases (tracker: [github|plan])"
```

Pushing this tag is explicitly **not** part of this command — it stays local until a human decides to push it (or a later command does, under its own gate).

---

## Step 10: Commit

```bash
git add PROJECT-STATUS.md BRAINSTORM.md START_HERE.md \
       .rcode/scope-manifest.json .rcode/config.json
# .rcode/config.json is now always touched this run (Step 6 sets
# total_phases/current_phase/status, K-E; Pre-Flight §4 may also have
# persisted the tracker field)
# .rcode/agent-log.md is deliberately NOT in this list — Step 11 writes it
# AFTER this commit and gives it its own follow-up commit.
git commit -m "$(cat <<'EOF'
docs(project): decompose into [N] work units across [M] phases

- Tracker: [github | plan]
- Created [N] work units ([N] GitHub issues with labels + milestones | [N] plan IDs P-NNN in BRAINSTORM.md)
- [Created [M] GitHub milestones + labels | No GitHub objects — plan tracker]
- Generated PROJECT-STATUS.md with progress tracking
- Locked scope manifest ([N] features, [N] units)
- Updated BRAINSTORM.md with unit IDs

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Step 11: Append to Agent Log

Append to `.rcode/agent-log.md`:

```markdown
## Session: Decompose

**Date:** [today]
**Agent:** decompose-pipeline

**Actions:**
- Tracker: [github | plan]
- Created [N] work units across [M] phases
- [Created [M] milestones + labels: phase, type, area, workflow | No GitHub objects — plan tracker]
- Generated PROJECT-STATUS.md
- Locked scope manifest

**Next Steps:**
- Review created work units [on GitHub | in BRAINSTORM.md]
- Run `/phase-gate 0` to verify foundation, if applicable
- Begin Phase 1 with `/team-lead "develop Phase 1"`
```

**Commit this entry.** `.rcode/agent-log.md` is written after Step 10's
commit and is not in that commit's `git add` list — stage and commit it
separately here so the log entry does not stay uncommitted:

```bash
git add .rcode/agent-log.md
git commit -m "$(cat <<'EOF'
docs(project): log decompose session

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Output Summary

```
R.Code Decompose Complete!

Tracker: [github | plan]

Created:
  - [N] work units across [M] phases   [github: N GitHub issues | plan: N P-NNN IDs in BRAINSTORM.md]
  - [M] milestones (github only)
  - [N] labels: phase, type, area, workflow (github only)
  - PROJECT-STATUS.md (progress dashboard)

Scope Manifest: LOCKED
Git Tag: scope-lock-[date]   (local only — not pushed)

Phase 1 — [Phase Name]:
  - [N] units total
  - [N] parallel-safe (can start immediately)
  - First unit: [#N | P-NNN] — [Title]

Next Step: Run `/team-lead "develop Phase 1"` to begin development.
```
