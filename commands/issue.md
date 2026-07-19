---
description: "Complete the full development workflow for a specific GitHub issue with scope enforcement, convention compliance, and status tracking."
argument-hint: "<issue-number>"
model: claude-fable-5[1m]
allowed-tools:
  - Task
  - Read
  - Write
  - Edit
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(npm:*)
  - Bash(npx:*)
  - Glob
  - Grep
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `agents/control-agent.md` §4.

# R.Code Issue — Atomic Development Workflow

You are executing the R.Code `/issue` command for issue **#$ARGUMENTS**.

This is a **9-phase workflow**. Execute each phase in order. Do not skip phases.

---

## Phase 0: ONBOARD CHECK

Before touching any code, verify readiness:

1. **Read CONVENTIONS.md** — Know the code patterns before writing code
2. **Read ARCHITECTURE.md** (skim) — Know the tech decisions
3. **Read PROJECT-STATUS.md** — Verify this issue is available and not blocked
4. **Check predecessors** — If the issue has predecessor issues, verify they are all closed:
   ```bash
   gh issue view [predecessor-number] --json state
   ```
5. **Verify phase** — Confirm this issue belongs to the **current active phase** (don't work ahead of phase gates)
6. **Check scope manifest** — Verify the issue maps to a feature in `.rcode/scope-manifest.json`

**STOP if:** Issue is blocked, predecessors are open, or issue is from a future phase.

---

## Phase 1: ANALYZE + SCOPE BOUNDARY

1. **Fetch the issue:**
   ```bash
   gh issue view $ARGUMENTS --json title,body,labels,milestone
   ```

2. **Parse from the issue body:**
   - Description
   - Acceptance criteria (every `- [ ]` item)
   - Scope boundary (IN SCOPE and OUT OF SCOPE)
   - Architectural context (relevant ADRs, conventions)
   - Predecessor/successor issues
   - Feature ID

3. **State your scope boundary explicitly:**

   ```
   ISSUE #[N]: [Title]

   I WILL implement:
   - [Item 1 from acceptance criteria]
   - [Item 2]
   - [Item 3]

   I will NOT implement:
   - [Item 1 from out-of-scope]
   - [Item 2 from out-of-scope]
   ```

4. **Plan the approach:**
   - Files to create or modify
   - Testing strategy (unit, integration, e2e)
   - Commit structure (how many commits, what each covers)
   - Estimated time

---

## Phase 2: BRANCH

```bash
# Ensure main is up to date
git checkout main
git pull origin main

# Create feature branch
git checkout -b <type>/issue-$ARGUMENTS-<short-description>
```

Branch naming rules (from `rcode-commits.md`):
- Lowercase, kebab-case
- Include issue number
- 3-5 word description max
- Type matches the primary work: `feat`, `fix`, `refactor`, `test`, `docs`

---

## Phase 3: IMPLEMENT + CONVENTION ENFORCEMENT

Implement the solution following these rules:

1. **Follow CONVENTIONS.md** — File locations, naming patterns, component structure
2. **Follow ARCHITECTURE.md** — Use approved patterns from relevant ADRs
3. **Reference SPECIFICATION.md** — If implementing UI, follow the design system
4. **Stay in scope** — Only modify files related to this issue

### Sub-Agent Delegation

Use specialized agents via the Task tool as needed:

| Need | Agent | Context to Provide |
|------|-------|--------------------|
| API/database work | `backend-agent` | Issue body + CONVENTIONS.md API section + ARCHITECTURE.md |
| UI components | `ui-agent` | Issue body + CONVENTIONS.md component section + SPECIFICATION.md design system |
| Complex logic | Direct implementation | Follow CONVENTIONS.md patterns |

### Convention Checks During Implementation

- [ ] Files are in the correct directories per CONVENTIONS.md
- [ ] Naming follows conventions (PascalCase components, camelCase utilities, etc.)
- [ ] Import order follows conventions
- [ ] Error handling follows the approved pattern
- [ ] State management uses the approved approach
- [ ] No new patterns introduced without documentation

**If a new pattern is needed** that isn't in CONVENTIONS.md:
- Document it as a "proposed convention update" in the PR description
- Do NOT update CONVENTIONS.md in this branch (that's for `/lessons`)

---

## Phase 4: TEST

1. **Write tests** — Spawn `testing-agent` via Task tool if needed:
   ```
   Write tests for issue #$ARGUMENTS:
   - [List acceptance criteria to test]
   - Follow testing patterns from CONVENTIONS.md
   - Include edge cases from the issue body
   ```

2. **Run validation** — Execute the full validation suite:
   ```bash
   npx tsc --noEmit          # TypeScript check
   npx eslint src/           # Lint check
   npm test                  # Run tests
   npm run build             # Build check
   ```

3. **All four checks must pass before proceeding.**

   If any check fails:
   - Fix the issue
   - Re-run all checks
   - Do NOT proceed to Phase 5 with failing checks

---

## Phase 5: COMMIT

Follow the structured commit format from `rcode-commits.md`:

```bash
git add [specific files — never use git add .]

git commit -m "$(cat <<'EOF'
<type>(<area>): <description> - closes #$ARGUMENTS

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

---

## Phase 6: PR

1. **Push the branch:**
   ```bash
   git push -u origin <branch-name>
   ```

2. **Run scope check** — Before creating the PR, verify scope:
   ```bash
   git diff main...HEAD --stat  # Review all changed files
   ```
   Every changed file must relate to this issue. Flag anything unexpected.

3. **Create the PR:**
   ```bash
   gh pr create --title "[Phase N] <Issue Title> - closes #$ARGUMENTS" --body "$(cat <<'PR_EOF'
   ## Summary

   [2-3 bullet points: what was implemented]

   ## Scope Verification

   **Issue:** #$ARGUMENTS
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
   - ADR-[N]: [How this ADR informed the implementation]

   ## Test Plan

   - [ ] TypeScript compiles (`npx tsc --noEmit`)
   - [ ] ESLint passes (`npx eslint src/`)
   - [ ] Tests pass (`npm test`)
   - [ ] Build succeeds (`npm run build`)
   - [ ] Manual verification: [specific steps]

   ## New Patterns (if any)

   [Document any new patterns that should be considered for CONVENTIONS.md]

   ---
   Generated with R.Code Workflow v2.0
   PR_EOF
   )"
   ```

---

## Phase 7: VERIFY

1. **Check CI status:**
   ```bash
   gh pr checks $PR_NUMBER
   ```

2. **Verify issue is linked:**
   ```bash
   gh pr view $PR_NUMBER --json body | grep "closes #$ARGUMENTS"
   ```

3. If CI fails, fix issues and push again. Do not merge with failing CI.

---

## Phase 8: STATUS SYNC

After the PR is created (or after merge), update project status:

1. **Update PROJECT-STATUS.md:**
   - Increment completed count for this phase
   - Update percentage
   - Add entry to "Recent Activity" table
   - Update "Next Available Issues"

2. **Update BRAINSTORM.md:**
   - Check off the completed issue: `- [x] #$ARGUMENTS — [Title]`

3. **Update START_HERE.md:**
   - Update the current status line with new percentage

4. **Append to `.rcode/agent-log.md`:**
   ```markdown
   ## Session: Issue #$ARGUMENTS

   **Date:** [today]
   **Agent:** [identifier]
   **Issue:** #$ARGUMENTS — [Title]
   **Branch:** [branch-name]
   **PR:** #[PR-number]

   **What was done:**
   - [Brief description of implementation]

   **Decisions made:**
   - [Any architectural or pattern decisions]

   **New patterns:**
   - [Any patterns that should be considered for CONVENTIONS.md]
   ```

5. **Commit status updates:**
   ```bash
   git checkout main  # or stay on branch if PR not merged yet
   git add PROJECT-STATUS.md BRAINSTORM.md START_HERE.md .rcode/agent-log.md
   git commit -m "docs(status): update project status after #$ARGUMENTS"
   ```

---

## Phase 9: CONTEXT HYGIENE

1. **Output completion summary:**
   ```
   Issue #$ARGUMENTS Complete!

   Branch: [branch-name]
   PR: #[PR-number]
   Status: [Awaiting review / Merged]

   Next available issues:
   - #[N] — [Title] (parallel-safe)
   - #[N] — [Title]
   ```

2. **Remind about context clearing:**
   ```
   IMPORTANT: Run /clear before starting the next issue.
   Context bleed between issues can cause scope violations.
   ```

3. If more issues are available in the current phase, suggest the next one from PROJECT-STATUS.md.
