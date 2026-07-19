---
description: "Verify phase completion with quality gates before unlocking the next phase. Run when all issues in a phase are closed."
argument-hint: "<phase-number>"
model: claude-fable-5[1m]
allowed-tools:
  - Task
  - Read
  - Write
  - Edit
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(npm:*)
  - Bash(npx:*)
  - Glob
  - Grep
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `agents/control-agent.md` §4.

# R.Code Phase Gate — Phase Completion Verification

You are executing the R.Code `/phase-gate` command for **Phase $ARGUMENTS**.

This is a **5-step verification**. All steps must pass for the phase gate to open.

---

## Step 1: ISSUE VERIFICATION

**Check:** Are all phase issues closed and all PRs merged?

```bash
# Get all issues for this phase's milestone
gh issue list --milestone "Phase $ARGUMENTS: [Phase Name]" --state all --json number,title,state

# Count open vs closed
gh issue list --milestone "Phase $ARGUMENTS: [Phase Name]" --state open --json number
gh issue list --milestone "Phase $ARGUMENTS: [Phase Name]" --state closed --json number

# Verify all PRs are merged
gh pr list --state all --json number,title,state,mergedAt --search "milestone:\"Phase $ARGUMENTS\""
```

**Verify:**
- [ ] All issues in the milestone are **closed**
- [ ] All PRs linked to these issues are **merged** (not just closed)
- [ ] No orphaned PRs (PRs without linked issues)
- [ ] No open PRs that should have been merged

**Result:** [N]/[N] issues closed, [N]/[N] PRs merged

---

## Step 2: QUALITY VERIFICATION

**Check:** Does the codebase build, pass tests, and have no type errors?

```bash
# TypeScript compilation
npx tsc --noEmit

# ESLint validation
npx eslint src/

# Full test suite
npm test

# Production build
npm run build
```

**Verify:**
- [ ] TypeScript: **0 errors**
- [ ] ESLint: **0 errors, 0 warnings**
- [ ] Tests: **All passing** ([N] tests)
- [ ] Build: **Successful**

**Result:** [PASS/FAIL with details]

---

## Step 3: SCOPE VERIFICATION

**Check:** Were all planned features delivered? No extras? No missing?

1. **Read `.rcode/scope-manifest.json`**
2. **For each feature assigned to Phase $ARGUMENTS:**
   - Are all feature issues closed?
   - Is the feature functionally complete?
   - Were any acceptance criteria skipped?

3. **Check for unplanned additions:**
   - Compare `git log --oneline v0.[N-1].0..HEAD` against planned issues
   - Are there commits that don't reference a planned issue?

4. **Check for scope changes:**
   - Are all scope changes in `scope_changes` array documented and approved?

**Verify:**
- [ ] All planned features for this phase are complete
- [ ] No unplanned features were added
- [ ] All scope changes are documented and approved
- [ ] Feature status updated to "complete" in scope manifest

**Result:** [N]/[N] features complete, [N] scope changes (all approved)

---

## Step 4: CREATE PHASE SUMMARY

Generate `.rcode/phase-summaries/phase-$ARGUMENTS-summary.md` using the PHASE-SUMMARY template:

1. **Overview:** Phase number, name, completion date, duration, issue count, git tag
2. **What Was Built:** Feature-level description (what the user can now do)
3. **Issues Completed:** Table of all issues with highlights
4. **Key Decisions:** New ADRs or significant choices
5. **Patterns Established:** New conventions or approaches
6. **Known Technical Debt:** Work deferred to future phases
7. **Context for Next Phase:** State of codebase, assumptions, watch-outs, recommended next steps

**This is the most critical output** — future agents will read this summary instead of reviewing every individual issue from this phase.

---

## Step 5: TAG AND COMMIT

```bash
# Update scope manifest — mark phase features as complete
# (edit .rcode/scope-manifest.json)

# Update PROJECT-STATUS.md — mark phase as 100% complete
# Update START_HERE.md — increment current phase

# Commit
git add .rcode/phase-summaries/phase-$ARGUMENTS-summary.md \
       .rcode/scope-manifest.json \
       PROJECT-STATUS.md \
       START_HERE.md

git commit -m "$(cat <<'EOF'
docs(phase-gate): phase $ARGUMENTS complete — [Phase Name]

Phase $ARGUMENTS Summary:
- [N] issues completed
- [N] features delivered: [list]
- [N] new ADRs
- [N] patterns established
- Known tech debt: [brief list or "none"]

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

# Create version tag
git tag -a "v0.$ARGUMENTS.0-[phase-name-kebab]" -m "Phase $ARGUMENTS: [Phase Name] complete

Features: [list]
Issues: [N] completed
Quality: All checks passing"
```

---

## Gate Results

### PASS — Phase Complete

```
Phase Gate $ARGUMENTS: PASS

Phase $ARGUMENTS — [Phase Name] is COMPLETE.

Summary:
  Issues: [N]/[N] closed
  Quality: All checks passing
  Scope: All features delivered
  Tag: v0.$ARGUMENTS.0-[phase-name]

Phase Summary: .rcode/phase-summaries/phase-$ARGUMENTS-summary.md

Next Phase: Phase [N+1] — [Phase Name]
  [N] issues planned
  [N] parallel-safe issues available

Recommended: Run /lessons to extract patterns before starting next phase.
```

### BLOCK — Phase Incomplete

```
Phase Gate $ARGUMENTS: BLOCK

Phase $ARGUMENTS cannot be completed. Issues found:

Issues:
  - [ ] #[N] — [Title] (still open)
  - [ ] #[N] — [Title] (PR not merged)

Quality:
  - TypeScript: [N] errors
  - Tests: [N] failing

Scope:
  - Feature [F00N] is incomplete: [details]

Action Required:
  1. [Specific action to resolve each blocker]
  2. Re-run /phase-gate $ARGUMENTS after resolving
```

### WARN — Phase Complete with Caveats

```
Phase Gate $ARGUMENTS: WARN (Proceed with Caution)

Phase $ARGUMENTS is technically complete but has caveats:

Warnings:
  - [Technical debt item deferred]
  - [Test coverage below target: X% vs Y% target]

These items are documented in the phase summary.
Phase [N+1] may proceed but should address warnings early.
```

---

## Append to Agent Log

```markdown
## Session: Phase Gate $ARGUMENTS

**Date:** [today]
**Agent:** [identifier]
**Result:** [PASS / BLOCK / WARN]

**Phase Summary:**
- Issues completed: [N]
- Features delivered: [list]
- Quality: [status]
- Tag: v0.$ARGUMENTS.0-[phase-name]

**Next Steps:**
- [Run /lessons]
- [Begin Phase N+1]
```
