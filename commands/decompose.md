---
description: "Convert BRAINSTORM.md into tracked GitHub issues with milestones, labels, and dependency tracking. Run after /brainstorm."
model: claude-fable-5[1m]
allowed-tools:
  - Task
  - Read
  - Write
  - Edit
  - Bash(gh:*)
  - Bash(git:*)
  - Glob
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `agents/control-agent.md` §4.

# R.Code Decompose — Issue Creation Pipeline

You are executing the R.Code `/decompose` command. This converts the development plan into tracked, actionable GitHub issues.

---

## Pre-Flight Checks

1. **Verify BRAINSTORM.md exists** — If not, instruct user to run `/brainstorm` first
2. **Verify git repository** — Must be initialized and connected to GitHub remote
3. **Verify GitHub CLI** — Run `gh auth status` to confirm authentication
4. **Verify scope manifest exists** — `.rcode/scope-manifest.json` must exist
5. **Read BRAINSTORM.md** — Parse all phases and issues

---

## Step 1: Create Labels

Create labels for issue categorization using `gh label create`:

### Phase Labels
```bash
gh label create "phase-1" --color "0E8A16" --description "Phase 1: [Phase Name]"
gh label create "phase-2" --color "1D76DB" --description "Phase 2: [Phase Name]"
gh label create "phase-3" --color "D93F0B" --description "Phase 3: [Phase Name]"
# ... for each phase
```

### Type Labels
```bash
gh label create "type:feature" --color "0E8A16" --description "New feature"
gh label create "type:fix" --color "D93F0B" --description "Bug fix"
gh label create "type:test" --color "FBCA04" --description "Testing"
gh label create "type:docs" --color "0075CA" --description "Documentation"
gh label create "type:infrastructure" --color "D4C5F9" --description "Infrastructure/tooling"
gh label create "type:refactor" --color "E4E669" --description "Code refactoring"
```

### Area Labels
```bash
gh label create "area:auth" --color "C2E0C6" --description "Authentication/authorization"
gh label create "area:api" --color "C2E0C6" --description "API endpoints"
gh label create "area:ui" --color "C2E0C6" --description "User interface"
gh label create "area:db" --color "C2E0C6" --description "Database/data layer"
gh label create "area:config" --color "C2E0C6" --description "Configuration/setup"
gh label create "area:core" --color "C2E0C6" --description "Core business logic"
```

### Workflow Labels
```bash
gh label create "blocked" --color "B60205" --description "Blocked by another issue"
gh label create "blocking" --color "D93F0B" --description "Blocking other issues"
gh label create "parallel-safe" --color "0E8A16" --description "Can be worked on in parallel"
gh label create "rcode" --color "5319E7" --description "R.Code workflow managed"
```

---

## Step 2: Create GitHub Milestones

Create one milestone per phase using the GitHub API:

```bash
gh api repos/{owner}/{repo}/milestones -f title="Phase 1: [Phase Name]" -f description="[Phase goal from BRAINSTORM.md]" -f state="open"
gh api repos/{owner}/{repo}/milestones -f title="Phase 2: [Phase Name]" -f description="[Phase goal]" -f state="open"
# ... for each phase
```

---

## Step 3: Create Issues

For EACH issue in BRAINSTORM.md, create a GitHub issue with enhanced body:

```bash
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
- [ ] All tests pass
- [ ] TypeScript compiles without errors
- [ ] Code follows CONVENTIONS.md patterns

## Scope Boundary

**IN SCOPE:**
- [What this issue covers]

**OUT OF SCOPE:**
- [What this issue does NOT cover — explicit boundaries]
- [Related work that belongs to other issues]

## Architectural Context

- Relevant ADR: [ADR-NNN from ARCHITECTURE.md]
- Conventions: [Relevant section from CONVENTIONS.md]
- Design: [Relevant section from SPECIFICATION.md if UI work]

## Technical Details

- Files to create/modify: [list]
- Testing strategy: [unit/integration/e2e]
- Dependencies: [npm packages if any]

## Predecessor Issues

- [#N — must be completed first (if any)]

## Successor Issues

- [#N — blocked until this is complete (if any)]

## Feature

Feature: [Feature ID from scope-manifest.json]
Phase: [Phase number]
ISSUE_EOF
)"
```

### Issue Creation Order

Create issues **in phase order** so that issue numbers roughly correspond to implementation order. This makes the BRAINSTORM.md checkbox tracking more intuitive.

---

## Step 4: Add Parallel-Safe and Blocking Labels

After all issues are created, add workflow labels:

```bash
# Mark parallel-safe issues
gh issue edit [N] --add-label "parallel-safe"

# Mark blocking relationships in issue bodies
# (GitHub doesn't have native blocking, so we document in issue body)
```

---

## Step 5: Lock Scope Manifest

Update `.rcode/scope-manifest.json`:

1. Set `"locked": true`
2. Set `"locked_date": "[today]"`
3. Populate `issues` arrays in each feature with actual GitHub issue numbers
4. Update `total_issues` count

---

## Step 6: Generate PROJECT-STATUS.md

Create `PROJECT-STATUS.md` from the PROJECT-STATUS template with:

- All phases listed with issue counts (all at 0% complete)
- "Next Available Issues" populated with Phase 1 parallel-safe issues
- Empty "Currently In Progress" and "Recent Activity" sections
- Scope Health section showing locked manifest

### Populate the "Roadmap / Strategic Prioritization" section

The template includes a `## Roadmap / Strategic Prioritization` section (placed right after `## Scope Health`). Fill it with the **initial strategic ordering** derived from BRAINSTORM.md — do NOT leave the placeholders. Use this exact section format:

```markdown
## Roadmap / Strategic Prioritization

**Strategic Posture:** [Ship / Consolidate] — [one line: is now a good moment to ship/release or to consolidate? Derived from current phase completion %, open blockers, and test/quality status.]

| Priority | Phase / Milestone | Strategic Rationale | Suggested Timing | Must-Precede |
|----------|-------------------|---------------------|------------------|--------------|
| P1 | [Phase N — Name] | [Why this matters now] | [next release window / after Phase N gate / deferred] | [#N or blocking dependency] |
| P2 | [Phase N — Name] | [Why this matters] | [next release window / after Phase N gate / deferred] | [#N or —] |
| P3 | [Phase N — Name] | [Why this matters] | [next release window / after Phase N gate / deferred] | [#N or —] |

**Recommended Next Strategic Move:** [one-liner: what to prioritize next and WHY — the next strategic lever, not just the next issue.]
```

Populate it as follows:

- **Strategic Posture:** At decompose time nothing is shipped yet (0% complete, scope just locked) — so the posture is almost always `Consolidate` ("foundation phase, build before release"). Derive the one-liner from: overall completion % (0%), open blockers (none yet), and quality status (no tests/build yet).
- **Priority table:** Derive the initial P1/P2/P3 ranking from the BRAINSTORM.md **phase order**, **milestones**, and the **Dependencies** and **Risk** tables:
  - Earlier phases and risk-mitigating / dependency-unblocking milestones rank higher (P1).
  - Use one row per phase/milestone (or per the most strategically significant milestones if there are many phases).
  - **Phase / Milestone** = the BRAINSTORM.md phase name + its GitHub milestone.
  - **Strategic Rationale** = why it comes first strategically (e.g. "unblocks all downstream auth work", "highest-risk integration — de-risk early").
  - **Suggested Timing** = `after Phase N gate` for sequenced phases; `next release window` for the first shippable milestone; `deferred` for nice-to-haves.
  - **Must-Precede** = blocking dependencies from the BRAINSTORM.md Dependencies table (predecessor phases/issues that must complete first).
- **Recommended Next Strategic Move:** the single highest-leverage thing to do next (usually "complete Phase 1 foundation to unblock parallel work"), with the WHY — not merely "do issue #N".

---

## Step 7: Update BRAINSTORM.md

Update each issue line in BRAINSTORM.md with the actual GitHub issue number:

```markdown
# Before:
- [ ] Issue Title `feat` `auth`

# After:
- [ ] #42 — Issue Title `feat` `auth`
```

---

## Step 8: Update START_HERE.md

Update the current status line:
```markdown
**Phase 1 of [M]** — [Phase Name] — **0% complete**
```

---

## Step 9: Git Tag

```bash
git tag -a "scope-lock-$(date +%Y-%m-%d)" -m "Scope manifest locked: [N] issues across [M] phases"
```

---

## Step 10: Commit

```bash
git add PROJECT-STATUS.md BRAINSTORM.md START_HERE.md .rcode/scope-manifest.json
git commit -m "$(cat <<'EOF'
docs(project): decompose into [N] issues across [M] phases

- Created [N] GitHub issues with milestones, labels, and dependencies
- Created [M] milestones (one per phase)
- Generated PROJECT-STATUS.md with progress tracking
- Locked scope manifest ([N] features, [N] issues)
- Updated BRAINSTORM.md with issue numbers

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
- Created [N] GitHub issues across [M] phases
- Created [M] milestones
- Created labels: phase, type, area, workflow
- Generated PROJECT-STATUS.md
- Locked scope manifest

**Next Steps:**
- Review created issues on GitHub
- Run `/phase-gate 0` to verify foundation
- Begin Phase 1 with `/issue <first-issue-number>`
```

---

## Output Summary

```
R.Code Decompose Complete!

Created:
  - [N] GitHub issues across [M] phases
  - [M] milestones
  - [N] labels (phase, type, area, workflow)
  - PROJECT-STATUS.md (progress dashboard)

Scope Manifest: LOCKED
Git Tag: scope-lock-[date]

Phase 1 — [Phase Name]:
  - [N] issues total
  - [N] parallel-safe (can start immediately)
  - First issue: #[N] — [Title]

Next Step: Run `/issue [first-issue-number]` to begin development.
```
