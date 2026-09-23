---
description: "Perform comprehensive review with scope verification, convention compliance, and architectural consistency checks. Tracker-aware: reviews a GitHub PR or a local branch diff."
argument-hint: "<PR-number | unit-id-or-branch>"
model: claude-fable-5-1[1m]
allowed-tools:
  - Task
  - Read
  - Glob
  - Grep
  - Bash(gh:*)
  - Bash(git:*)
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
  - Bash(npm:*)
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `~/.claude/agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `~/.claude/agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `~/.claude/agents/control-agent.md` §4.

# R.Code Review — /rcode-review

You are executing the R.Code `/rcode-review` command for **$ARGUMENTS**.

**Target resolution (tracker-aware).** Resolve the tracker from
`.rcode/config.json` `.tracker`; if unset, resolve it the way
`~/.claude/scripts/rcode-units.sh` does (A3) and say so.

- **tracker `github` + a remote exists:** `$ARGUMENTS` is a PR number — review
  it via `gh pr view` / `gh pr diff` / `gh pr checks`.
- **tracker `plan`, or `github` without a remote:** `$ARGUMENTS` is a unit ID
  (`P-NNN`) or a branch name — review via
  `git diff <trunk>...<branch>` (trunk per `~/.claude/rules/workflow-git.md`,
  usually `main`) and read the unit's body (Description / Acceptance /
  Scope boundary) directly from `BRAINSTORM.md` (both grammars, A2).

This is a **10-part review — Review checks 0–9**. Every check produces a
finding (PASS, WARN, or FAIL).

---

## Review Check 0: SCOPE VERIFICATION

**Purpose:** Ensure the change only contains modifications that belong to the linked unit.

1. **Identify the linked unit:**
   ```bash
   gh pr view $ARGUMENTS --json body,title | grep -oE '(closes|refs) (#[0-9]+|P-[0-9]{3,})'   # tracker: github
   # tracker: plan / no remote — $ARGUMENTS IS the unit ID
   ```

2. **Read the unit's scope boundary:**
   ```bash
   gh issue view <unit-number> --json body     # tracker: github
   # tracker: plan — read the unit's body from BRAINSTORM.md
   ```
   Extract the "IN SCOPE" and "OUT OF SCOPE" sections.

3. **Analyze changed files:**
   ```bash
   gh pr diff $ARGUMENTS --stat                     # tracker: github
   git diff <trunk>...<branch> --stat                # tracker: plan / no remote
   ```

4. **Scope check for every changed file:**
   - Does this file relate to the unit's scope?
   - Are there changes to files "owned" by other units?
   - Are there new files not mentioned in the unit plan?
   - Are there new dependencies not discussed in the unit?

5. **Check acceptance criteria coverage:**
   - For each acceptance criterion in the unit, verify it's addressed in the code
   - Flag criteria that are NOT addressed (scope shrinkage)
   - Flag code that goes beyond criteria (scope creep)

**Finding:** SCOPE: CLEAN / WARNING / VIOLATION

---

## Review Check 1: CONTEXT

**Purpose:** Understand the change's purpose and current state.

1. **Read the change:**
   ```bash
   gh pr view $ARGUMENTS --json title,body,state,labels,milestone,headRefName,baseRefName   # tracker: github
   # tracker: plan / no remote — git log -1 <branch>; read the unit body
   ```

2. **Check CI status** (tracker `github` with a remote only):
   ```bash
   gh pr checks $ARGUMENTS
   ```

3. **Verify branch naming** follows `<type>/issue-<N>-<description>`
   (tracker `github`) or `<type>/p-<NNN>-<description>` (tracker `plan`).

4. **Verify PR title** (tracker `github` only) follows
   `[Phase N] <Title> - closes #<N>` format.

**Finding:** CONTEXT: PASS / WARN / FAIL

---

## Review Check 2: CODE QUALITY

**Purpose:** Review code for bugs, readability, and maintainability.

1. **Read the full diff:**
   ```bash
   gh pr diff $ARGUMENTS                # tracker: github
   git diff <trunk>...<branch>          # tracker: plan / no remote
   ```

2. **Check for:**
   - Logic errors and potential bugs
   - Proper error handling (no swallowed errors)
   - Type safety (no untyped escape hatches without justification)
   - No `console.log`, `debugger`, or TODO comments without a unit reference
   - Readable variable/function names
   - Functions under 50 lines, files under 500 lines
   - DRY principles (no unnecessary duplication)
   - Proper null/undefined handling

3. **Run the type/build and lint portions of the check trio** — the
   project's three pre-commit checks (type/build · test · lint), defined
   ONCE in the project's `CLAUDE.md` → "## Mandatory Pre-Commit" (M7). Do not
   hardcode `tsc`/`eslint` here — run exactly what that section names.

**Finding:** CODE QUALITY: PASS / WARN / FAIL

---

## Review Check 3: CONVENTION COMPLIANCE

**Purpose:** Verify code follows established patterns.

1. **Read CONVENTIONS.md** — Load the current code conventions

2. **Verify:**
   - File locations match folder structure rules
   - File naming follows conventions (PascalCase, camelCase, etc.)
   - Component structure follows the template
   - Import order follows rules
   - State management uses the approved approach
   - API patterns follow the standard format
   - Error handling follows the approved pattern

3. **Flag any new patterns** not in CONVENTIONS.md — these should be
   documented as "proposed convention updates" in the PR description (or, no
   PR, in the review report handed to the lead).

**Finding:** CONVENTIONS: PASS / WARN / FAIL

---

## Review Check 4: ARCHITECTURAL CONSISTENCY

**Purpose:** Verify implementation aligns with ADRs and system design.

1. **Read ARCHITECTURE.md** — identify relevant ADRs for this change's
   domain. ADRs follow the two-tier model (A5): design-time decisions live
   inline as `### ADR-NNN` entries in `ARCHITECTURE.md`; implemented/final
   decisions are ALSO filed as immutable `docs/adr/NNNN-*.md`, with the
   inline entry linking to it. Check BOTH places before concluding no ADR
   exists.

2. **Verify:**
   - Implementation follows the relevant ADR's decision
   - No architectural anti-patterns introduced
   - Data flow matches the documented patterns
   - No undocumented external service integrations
   - State management approach is consistent

3. **Flag any architectural deviations** — these require an ADR update or new ADR

**Finding:** ARCHITECTURE: PASS / WARN / FAIL

---

## Review Check 5: SECURITY

**Purpose:** Check for security vulnerabilities.

1. **Check for:**
   - Hardcoded credentials, API keys, or secrets
   - SQL injection vulnerabilities (raw queries without parameterization)
   - XSS vulnerabilities (unescaped user input in HTML)
   - Missing authentication checks on protected routes
   - Missing authorization checks (user accessing other users' data)
   - Insecure data storage (sensitive data in localStorage)
   - Missing input validation on API endpoints
   - Missing CSRF protection
   - Exposed stack traces or internal errors to users

**Finding:** SECURITY: PASS / WARN / FAIL

---

## Review Check 6: TESTING

**Purpose:** Verify test quality and coverage.

1. **Run the test portion of the check trio** (CLAUDE.md → Mandatory
   Pre-Commit).

2. **Review test quality:**
   - Are all acceptance criteria covered by tests?
   - Do tests check both happy path and error cases?
   - Are edge cases from the unit body tested?
   - Are tests independent (no shared state)?
   - Do test names clearly describe what they verify?
   - Is there appropriate use of mocks (not too much, not too little)?

**Finding:** TESTING: PASS / WARN / FAIL

---

## Review Check 7: PERFORMANCE

**Purpose:** Check for performance issues.

1. **Check for:**
   - N+1 database queries
   - Missing database indexes for new queries
   - Unbounded data fetching (no pagination/limits)
   - Unnecessary re-renders (React: inline objects, missing memoization)
   - Large bundle imports (import entire library vs tree-shaking)
   - Missing loading states for async operations
   - Memory leaks (event listeners not cleaned up)

**Finding:** PERFORMANCE: PASS / WARN / FAIL

---

## Review Check 8: DOCUMENTATION

**Purpose:** Verify documentation is adequate.

1. **Check for:**
   - JSDoc/docstrings on exported functions and complex internal functions
   - Comments explaining "why" (not "what") for non-obvious code
   - Updated README if public API changed
   - API route documentation if new endpoints added
   - Type documentation for complex interfaces

**Finding:** DOCUMENTATION: PASS / WARN / FAIL

---

## Review Check 9: ACCEPTANCE CRITERIA

**Purpose:** Final verification that all requirements are met.

1. **For each acceptance criterion in the unit:**
   - [ ] Criterion 1 — [PASS/FAIL: where in code this is satisfied]
   - [ ] Criterion 2 — [PASS/FAIL: where in code]
   - [ ] Criterion 3 — [PASS/FAIL: where in code]

2. **Run the build portion of the check trio** (CLAUDE.md → Mandatory
   Pre-Commit).

**Finding:** ACCEPTANCE: PASS / WARN / FAIL

---

## Review Summary

Generate a structured review report:

```markdown
# Review Report — $ARGUMENTS

## Results

| Check | Name | Finding | Details |
|-------|------|---------|---------|
| 0 | Scope Verification | [CLEAN/WARN/VIOLATION] | [Details] |
| 1 | Context | [PASS/WARN/FAIL] | [Details] |
| 2 | Code Quality | [PASS/WARN/FAIL] | [Details] |
| 3 | Convention Compliance | [PASS/WARN/FAIL] | [Details] |
| 4 | Architectural Consistency | [PASS/WARN/FAIL] | [Details] |
| 5 | Security | [PASS/WARN/FAIL] | [Details] |
| 6 | Testing | [PASS/WARN/FAIL] | [Details] |
| 7 | Performance | [PASS/WARN/FAIL] | [Details] |
| 8 | Documentation | [PASS/WARN/FAIL] | [Details] |
| 9 | Acceptance Criteria | [PASS/WARN/FAIL] | [Details] |

## Verdict: [APPROVE / REQUEST CHANGES / COMMENT]

## Issues Found

### MUST FIX (blocking merge)
- [SCOPE VIOLATION: description]
- [CONVENTION VIOLATION: description]
- [ARCHITECTURE VIOLATION: description]
- [SECURITY ISSUE: description]

### SHOULD FIX (improve before merge)
- [QUALITY ISSUE: description]
- [TESTING GAP: description]

### COULD FIX (nice to have)
- [SUGGESTION: description]
```

---

## Post-Review Actions

### tracker `github` with a remote (a PR object exists)

**If APPROVE:**
```bash
gh pr review $ARGUMENTS --approve --body "[Review report]"
```

**If REQUEST CHANGES:**
```bash
gh pr review $ARGUMENTS --request-changes --body "[Review report with required fixes]"
```

**If COMMENT:**
```bash
gh pr review $ARGUMENTS --comment --body "[Review report with suggestions]"
```

### tracker `plan`, or `github` without a remote (no PR object)

There is nothing to `gh pr review`. Hand the review report directly to the
user (or to the lead, if dispatched under `/team-lead`) and, if the unit was
dispatched by a worker, include it in that worker's report-back per
`~/.claude/commands/issue.md` "Worker mode". Do not fabricate a PR review call.

---

## Rejection Categories (Severity Order)

1. **SCOPE VIOLATION** — Out-of-scope changes → MUST FIX (remove out-of-scope code)
2. **SECURITY ISSUE** — Vulnerability detected → MUST FIX
3. **ARCHITECTURE VIOLATION** — Contradicts ADRs → MUST FIX (follow ADR or create new ADR)
4. **CONVENTION VIOLATION** — Breaks patterns → MUST FIX (follow CONVENTIONS.md)
5. **QUALITY ISSUE** — Bug, poor readability → SHOULD FIX
6. **TESTING GAP** — Missing test coverage → SHOULD FIX
7. **PERFORMANCE CONCERN** — Potential bottleneck → SHOULD FIX
8. **DOCUMENTATION GAP** — Missing docs → COULD FIX
9. **SUGGESTION** — Improvement idea → COULD FIX
