---
description: "Execute the atomic unit protocol (Steps 0-9) for one work unit, with scope enforcement, convention compliance, and status tracking. Runs standalone or as a /team-lead worker."
argument-hint: "<unit-id>"
model: claude-fable-5-1[1m]
allowed-tools:
  - Task
  - Read
  - Write
  - Edit
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(npm:*)
  - Bash(npx:*)
  - Bash(pnpm:*)
  - Bash(yarn:*)
  - Bash(bun:*)
  - Bash(mypy:*)
  - Bash(pytest:*)
  - Bash(ruff:*)
  - Bash(black:*)
  - Bash(cargo:*)
  - Bash(go:*)
  - Bash(swift:*)
  - Bash(xcodebuild:*)
  - Bash(make:*)
  - Bash(bash:*)
  - Glob
  - Grep
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `~/.claude/agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `~/.claude/agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `~/.claude/agents/control-agent.md` §4.

> **Auch Arbeitsvorschrift für von `/team-lead` dispatchte Worker (IMP-150, siehe A1):**
> Wird diesem Protokoll ein von `/team-lead` dispatchter Worker für EINE Arbeitseinheit
> zugewiesen, durchläuft er nur das unten definierte **Worker mode** — nicht die vollen
> Steps 0–9. Nutzer-Eskalationen (ESCALATE-band, y/n) laufen über den Lead als Arbiter
> (`~/.claude/rules/agency-bands.md`), nicht direkt an den Nutzer.

# R.Code Issue — Unit Protocol (Steps 0–9)

You are executing the R.Code `/issue` command for work unit **$ARGUMENTS** —
`#N` when the project's tracker is `github`; when it is `plan`, `P-NNN` for
the standard checkbox/table grammar, or a LOCAL `#N` for the older
local-numbered table form (K-A — the `plan` tracker field disambiguates a
local `#N` from a GitHub issue, not the ID shape) — see
`~/.claude/rcode/README.md` §Tracker Modes for the full grammar. Resolve the
tracker from `.rcode/config.json` `.tracker`; if unset, resolve it the way
`~/.claude/scripts/rcode-units.sh` does (A3) and say so.

This command has **two modes**:

- **Standalone mode** — `/issue <unit>` invoked directly. Runs ALL Steps 0–9
  below, in order.
- **Worker mode** — a worker dispatched by `/team-lead` for exactly one unit,
  as part of a wave. Runs only Steps 0, 1, 3, 4, 5 — see "## Worker mode"
  below for exactly what changes and what it reports back.

Do not skip a step that applies to your mode.

---

## Worker mode

A worker dispatched by `/team-lead` for one unit receives, by reference
(never paraphrased): this file's "Worker mode" section, the unit ID, the
tracker, and the branch name the lead has already created for the wave
(`~/.claude/commands/team-lead.md` §3.2 point 4).

Practice basis (A1): under `/team-lead`, 16 sub-agents across 4 waves
committed to ONE shared branch (`overnight/2026-09-21-foundation`,
proj-292e7a) — `/issue` standalone mode was never invoked for any of them.
Worker mode formalizes what already happens in practice instead of pretending
every dispatched worker runs the full standalone protocol.

In Worker mode, run only:

- **Step 0** — readiness + env-key preflight, for this unit only.
- **Step 1** — scope boundary ("I WILL / I will NOT").
- **Step 3** — implement per CONVENTIONS.md / ARCHITECTURE.md.
- **Step 4** — check trio.
- **Step 5** — commit ON THE BRANCH THE LEAD NAMED (commit ref format in
  Step 5); do NOT create a branch, do NOT push, do NOT open a PR.

A worker in Worker mode NEVER writes `PROJECT-STATUS.md`, `BRAINSTORM.md`, or
`.rcode/agent-log.md` — Steps 2, 6, 7, 8, 9 belong to the lead (branching,
PR/merge decision, status sync, agent-log, context hygiene). This is the
single-writer rule (A12): dispatched workers never write the lead's shared
docs. Instead, a worker reports back:

```
Unit: <unit-id>
Files changed: <list>
Commits: <hash — subject>
Check trio: PASS | FAIL (which check, if FAIL)
Deviations from the Auftragsbrief (if any): <what, why>
```

Standalone mode runs every Step below, in order.

---

## Step 0: Readiness Check

*(Standalone + Worker — Worker mode runs this only for its own unit.)*

Before touching any code, verify readiness:

1. **Read CONVENTIONS.md** — Know the code patterns before writing code. If
   the file is absent, this is a **finding, not a STOP**: note it and fall
   back to the project's `CLAUDE.md` → "Mandatory Pre-Commit" section plus
   any installed stack rules as the convention source (C30).
2. **Read ARCHITECTURE.md** (skim) — Know the tech decisions. If the file is
   absent, this is a **finding, not a STOP**: note it and proceed without
   it — there is no fallback source for ADR context when it's missing.
3. **Read PROJECT-STATUS.md** — Verify this unit is available and not blocked.
   (Worker mode: the lead already verified this during unit binding — re-check
   only if something looks stale.)
4. **Check predecessors** — if the unit has predecessor units, verify they are
   all closed:
   ```bash
   gh issue view <predecessor> --json state          # tracker: github
   # tracker: plan — read the predecessor's checkbox (- [x]) or Status/State
   # column value in BRAINSTORM.md (both grammars, A2)
   ```
5. **Verify Phase** — confirm this unit belongs to the **current active
   Phase** (don't work ahead of a phase gate).
6. **Check scope manifest** — verify the unit maps to a feature in
   `.rcode/scope-manifest.json`.
7. **Env-key preflight (IMP-169, A11)** — run the env-key preflight defined
   in `~/.claude/rcode/stages/develop.md` "## Env-key preflight" for this
   unit's `Requires env:` keys. Missing keys → list the missing NAMES ONLY
   (never values) with a recommendation before proceeding.

**STOP if:** the unit is blocked, a predecessor is open, the unit is from a
future Phase, or a required env key is missing and unresolved. (Worker mode:
report the blocker back to the lead instead of stopping the whole session.)

---

## Step 1: Scope Boundary

*(Standalone + Worker)*

1. **Fetch the unit** (tracker-aware):
   ```bash
   gh issue view <N> --json title,body,labels,milestone     # tracker: github
   ```
   tracker `plan` — read the unit's body from `BRAINSTORM.md`. Three forms
   are readable: the checkbox form (`- [ ] P-012 — <Title> ...`, with an
   optional indented body below it), the `P-NNN` table-row form whose FIRST
   cell is the ID (`| P-001 | [Phase 1] <Title> | <Type> | <Area> | ... |`,
   used by e.g. proj-292e7a's 312 units), and a LOCAL `#N` table form whose
   first HEADER cell is `#`/`ID`/`Nr`/`Nr.` (K-A — the practice in project proj-47cf29;
   the `plan` tracker field disambiguates it from a GitHub issue, not the ID
   shape) — see `~/.claude/rcode/README.md` §Tracker Modes for the full
   grammar.

2. **Parse from the unit body:**
   - Description
   - Acceptance criteria (every `- [ ]` item)
   - Scope boundary (IN SCOPE and OUT OF SCOPE)
   - Architectural context — relevant ADRs. Check BOTH places (A5): inline
     `### ADR-NNN` entries in `ARCHITECTURE.md` and filed
     `docs/adr/NNNN-*.md`.
   - Predecessor/successor units
   - Feature ID
   - `Requires env:` (already consumed in Step 0)

3. **State your scope boundary explicitly:**

   ```
   UNIT <id>: [Title]

   I WILL implement:
   - [Item 1 from acceptance criteria]
   - [Item 2]

   I will NOT implement:
   - [Item 1 from out-of-scope]
   - [Item 2]
   ```

4. **Plan the approach** (Standalone: include files to touch, testing
   strategy, commit structure, and a time estimate. Worker: the lead already
   estimated at dispatch — plan files/tests/commits, skip the estimate.)

---

## Step 2: Branch

*(Standalone only — Worker mode: skip. The lead already created the working
branch for the wave; commit onto it in Step 5.)*

```bash
# Ensure the project's trunk is up to date — the trunk is NOT always `main`
# (read the branch policy per ~/.claude/rules/workflow-git.md "Trunk Is Not Always main").
trunk="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's#^origin/##')"
trunk="${trunk:-main}"   # no remote/origin HEAD (e.g. tracker plan, local-only repo) → confirm the trunk name with the user once if it is not main
git checkout "${trunk}"
if git remote get-url origin >/dev/null; then git pull --ff-only origin "${trunk}"; fi

# Create the unit branch
git checkout -b <type>/issue-<N>-<short-description>        # tracker: github
git checkout -b <type>/p-<NNN>-<short-description>           # tracker: plan
```

Branch naming rules (from `~/.claude/rcode/rules/rcode-commits.md`):
- Lowercase, kebab-case
- Include the unit ID (`issue-<N>` or `p-<NNN>`)
- 3–5 word description max
- Type matches the primary work: `feat`, `fix`, `refactor`, `test`, `docs`

---

## Step 3: Implement + Convention Enforcement

*(Standalone + Worker)*

Implement the solution following these rules:

1. **Follow CONVENTIONS.md** — File locations, naming patterns, component
   structure. If it was absent at Step 0, follow the fallback noted there
   instead (project `CLAUDE.md` → "Mandatory Pre-Commit" + stack rules).
2. **Follow ARCHITECTURE.md** — Use approved patterns from relevant ADRs. If
   it was absent at Step 0, proceed without ADR guidance — do not invent
   architectural constraints that were never documented.
3. **Reference SPECIFICATION.md** — If implementing UI, follow the design system
4. **Stay in scope** — Only modify files related to this unit

### Sub-Agent Delegation

Use specialized agents via the Task tool as needed:

| Need | Agent | Context to Provide |
|------|-------|--------------------|
| API/database work | `backend-agent` | Unit body + CONVENTIONS.md API section + ARCHITECTURE.md |
| UI components | `ui-agent` | Unit body + CONVENTIONS.md component section + SPECIFICATION.md design system |
| Rendered-output check | `visual-qa-agent` | Screenshot/snapshot the change against the SPECIFICATION.md design system — read-only |
| Complex logic | Direct implementation | Follow CONVENTIONS.md patterns |

### Convention Checks During Implementation

- [ ] Files are in the correct directories per CONVENTIONS.md
- [ ] Naming follows conventions (PascalCase components, camelCase utilities, etc.)
- [ ] Import order follows conventions
- [ ] Error handling follows the approved pattern
- [ ] State management uses the approved approach
- [ ] No new patterns introduced without documentation

**If a new pattern is needed** that isn't in CONVENTIONS.md:
- Document it as a "proposed convention update" (Standalone: in the PR
  description; Worker: in the report-back to the lead)
- Do NOT update CONVENTIONS.md in this branch (that's for `/lessons`)

---

## Step 4: Test + Check Trio

*(Standalone + Worker)*

1. **Write tests** — Spawn `testing-agent` via Task tool if needed:
   ```
   Write tests for unit <id>:
   - [List acceptance criteria to test]
   - Follow testing patterns from CONVENTIONS.md
   - Include edge cases from the unit body
   ```

2. **Run the check trio** — the project's three pre-commit checks
   (type/build · test · lint), defined ONCE in the project's `CLAUDE.md` →
   "## Mandatory Pre-Commit" (M7). Do not hardcode `npx tsc`/`npm test` here
   — read the trio from that section and run exactly those commands.

3. **All three checks must pass before proceeding.**

   If any check fails:
   - Fix the issue
   - Re-run the check trio
   - Do NOT proceed to Step 5 with a failing check

---

## Step 5: Commit

*(Standalone + Worker — Worker mode commits on the branch the lead named;
Standalone creates its own branch in Step 2 first.)*

Follow the structured commit format from `~/.claude/rcode/rules/rcode-commits.md`:

```bash
git add [specific files — never use git add .]

git commit -m "$(cat <<'EOF'
<type>(<area>): <description> - closes #<N>          # tracker: github
<type>(<area>): <description> - closes P-<NNN>       # tracker: plan

Phase: [phase-number]
Feature: [feature-id]

[Body — what changed and why, bullet points]

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Commit Rules

- **Stage specific files** — Never `git add .` or `git add -A`
- **One logical change per commit** — Split if needed
- **Separate docs from code** — Documentation updates get their own commit
- **Include Phase and Feature trailers** — Required for traceability
- **Commit reference** accepts single IDs, ranges, and comma lists (A2):
  `(closes|refs) (#[0-9]+|P-[0-9]{3,}(\.\.P-[0-9]{3,})?)((, ?)(#[0-9]+|P-[0-9]{3,}(\.\.P-[0-9]{3,})?))*`
  (single source: `~/.claude/rcode/rules/rcode-commits.md`) — e.g.
  `refs P-051..P-105`, `refs P-085, P-100`

---

## Step 6: PR

*(Standalone only — Worker mode: skip; the lead makes the consolidated merge
decision after the wave, ESCALATE per `~/.claude/rules/agency-bands.md`)*

1. **Push the branch** — tracker `github` with a remote only (SOFT-ACK per
   `~/.claude/rules/workflow-git.md`):
   ```bash
   git push -u origin <branch-name>
   ```
   Tracker `plan`, or `github` without a remote: leave the branch as-is —
   there is no PR object to open. The lead makes the consolidated merge
   decision (merge to trunk = ESCALATE, one y/n).

2. **Run scope check** — before creating the PR, verify scope:
   ```bash
   # Re-resolve the trunk the same way Step 2 did — a fresh Bash invocation
   # does not inherit Step 2's $trunk, and the trunk is NOT always `main`
   # (~/.claude/rules/workflow-git.md "Trunk Is Not Always main").
   trunk="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's#^origin/##')"
   trunk="${trunk:-main}"
   git diff "${trunk}"...HEAD --stat  # Review all changed files
   ```
   Every changed file must relate to this unit. Flag anything unexpected.

3. **Create the PR** (tracker `github` with a remote only):
   ```bash
   gh pr create --title "[Phase N] <Unit Title> - closes #<N>" --body "$(cat <<'PR_EOF'
   ## Summary

   [2-3 bullet points: what was implemented]

   ## Scope Verification

   **Unit:** #<N>
   **Feature:** [Feature ID]
   **Phase:** [N]

   ### Acceptance Criteria Status
   - [x] [Criterion 1 — how it was implemented]
   - [x] [Criterion 2 — how it was implemented]

   ### Scope Boundary Verification
   - All changes are within the defined scope boundary
   - No out-of-scope modifications detected
   - [Any notes about scope-adjacent decisions]

   ### Conventions Followed
   - [Convention 1 from CONVENTIONS.md]
   - [Convention 2]

   ### ADRs Referenced
   - ADR-[N]: [how this ADR informed the implementation — check both the
     inline ARCHITECTURE.md entry and docs/adr/, per A5]

   ## Test Plan

   - [ ] Check trio passes (CLAUDE.md → Mandatory Pre-Commit)
   - [ ] Manual verification: [specific steps]

   ## New Patterns (if any)

   [Document any new patterns that should be considered for CONVENTIONS.md]

   ---
   Generated with R.Code Workflow
   PR_EOF
   )"
   ```

---

## Step 7: Verify

*(Standalone only, and only when a PR exists — tracker `github` with a
remote)*

1. **Check CI status:**
   ```bash
   gh pr checks $PR_NUMBER
   ```

2. **Verify unit is linked:**
   ```bash
   gh pr view $PR_NUMBER --json body | grep "closes #<N>"
   ```

3. If CI fails, fix issues and push again. Do not merge with failing CI.

---

## Step 8: Status Sync

*(Standalone only — Worker mode: the lead owns this, see
`~/.claude/commands/team-lead.md` §3.2 "Proportional exit". Single-writer
rule, A12: `/issue` standalone is a permitted writer of these files; a
dispatched worker never is — see "Worker mode" above.)*

After the PR is created (or, tracker `plan` / no remote, after Step 5's
commit lands), update project status **on the unit branch** — never
checkout the project's trunk branch to commit these (M9; the trunk is NOT
always `main` — see Step 2's dynamic-trunk resolution):

1. **Update PROJECT-STATUS.md:**
   - Increment completed count for this Phase
   - Update percentage
   - Add entry to "Recent Activity" table
   - Update "Next Available Units"

2. **Update BRAINSTORM.md:**
   - Tracker `plan`, checkbox-form unit: flip `- [ ]` → `- [x] P-<NNN> —
     [Title]`.
   - Tracker `plan`, table-form unit (A2): update its `Status`/`State`
     column to whatever "done" value the table already uses (e.g.
     `done`/`✅`) — never invent a new column. If the table has no
     `Status`/`State` column, do NOT silently skip: note in the agent-log
     entry (below) that completion could not be recorded for this unit.
   - Tracker `github`: skip — units live as GitHub issues, not in
     BRAINSTORM.md.

3. **Update START_HERE.md:**
   - Update the current status line with new percentage.

4. **Append to `.rcode/agent-log.md`.** Every entry `/issue` writes carries
   `**Last step:** N` (A3 — `~/.claude/scripts/resume-state.sh` parses this
   to compute `last_logged_step`):
   ```markdown
   ## Session: Unit <id>

   **Date:** [today]
   **Agent:** [identifier]
   **Last step:** 8
   **Unit:** <id> — [Title]
   **Branch:** [branch-name]
   **PR:** #[PR-number] (tracker github + remote only)

   **What was done:**
   - [Brief description of implementation]

   **Decisions made:**
   - [Any architectural or pattern decisions]

   **New patterns:**
   - [Any patterns that should be considered for CONVENTIONS.md]
   ```

5. **Commit status updates — on the current (unit) branch, never trunk (M9):**
   ```bash
   git add PROJECT-STATUS.md BRAINSTORM.md START_HERE.md .rcode/agent-log.md
   git commit -m "docs(status): update project status after <id>"
   ```
   **(A13)** If the branch was already pushed in Step 6, push this
   `docs(status)` commit too. If the PR already merged before this step ran,
   note the needed follow-up status commit explicitly in the agent-log entry
   instead of silently dropping it.

---

## Step 9: Context Hygiene

*(Standalone only — Worker mode: fresh context per unit is already provided
by the dispatch itself; nothing to do here)*

1. **Output completion summary:**
   ```
   Unit <id> Complete!

   Branch: [branch-name]
   PR: #[PR-number] (if any)
   Status: [Awaiting review / Merged / Committed]

   Next available units:
   - <id> — [Title] (parallel-safe)
   - <id> — [Title]
   ```

2. **Remind about context clearing:**
   ```
   IMPORTANT: Run /clear before starting the next unit.
   Context bleed between units can cause scope violations.
   ```

3. If more units are available in the current Phase, suggest the next one
   from PROJECT-STATUS.md.
