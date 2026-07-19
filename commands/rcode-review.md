---
description: "Perform comprehensive code review with scope verification, convention compliance, and architectural consistency checks."
argument-hint: "<PR-number>"
model: claude-fable-5[1m]
allowed-tools:
  - Task
  - Read
  - Glob
  - Grep
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(npx:*)
  - Bash(npm:*)
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `agents/control-agent.md` §4.

# R.Code Review — Comprehensive Code Review

You are executing the R.Code `/review` command for PR **#$ARGUMENTS**.

This is a **10-phase review**. Every phase must produce a finding (PASS, WARN, or FAIL).

---

## Phase 0: SCOPE VERIFICATION

**Purpose:** Ensure the PR only contains changes that belong to the linked issue.

1. **Identify the linked issue:**
   ```bash
   gh pr view $ARGUMENTS --json body,title | grep -oP 'closes #\K\d+'
   ```

2. **Read the issue's scope boundary:**
   ```bash
   gh issue view [issue-number] --json body
   ```
   Extract the "IN SCOPE" and "OUT OF SCOPE" sections.

3. **Analyze changed files:**
   ```bash
   gh pr diff $ARGUMENTS --stat
   ```

4. **Scope check for every changed file:**
   - Does this file relate to the issue's scope?
   - Are there changes to files "owned" by other issues?
   - Are there new files not mentioned in the issue plan?
   - Are there new dependencies not discussed in the issue?

5. **Check acceptance criteria coverage:**
   - For each acceptance criterion in the issue, verify it's addressed in the code
   - Flag criteria that are NOT addressed (scope shrinkage)
   - Flag code that goes beyond criteria (scope creep)

**Finding:** SCOPE: CLEAN / WARNING / VIOLATION

---

## Phase 1: CONTEXT

**Purpose:** Understand the PR's purpose and current state.

1. **Read the PR:**
   ```bash
   gh pr view $ARGUMENTS --json title,body,state,labels,milestone,headRefName,baseRefName
   ```

2. **Check CI status:**
   ```bash
   gh pr checks $ARGUMENTS
   ```

3. **Verify branch naming** follows `<type>/issue-<N>-<description>` convention.

4. **Verify PR title** follows `[Phase N] <Title> - closes #<N>` format.

**Finding:** CONTEXT: PASS / WARN / FAIL

---

## Phase 2: CODE QUALITY

**Purpose:** Review code for bugs, readability, and maintainability.

1. **Read the full diff:**
   ```bash
   gh pr diff $ARGUMENTS
   ```

2. **Check for:**
   - Logic errors and potential bugs
   - Proper error handling (no swallowed errors)
   - TypeScript type safety (no `any` without justification)
   - No `console.log`, `debugger`, or TODO comments without issue references
   - Readable variable/function names
   - Functions under 50 lines, files under 500 lines
   - DRY principles (no unnecessary duplication)
   - Proper null/undefined handling

3. **Run static analysis:**
   ```bash
   npx tsc --noEmit
   npx eslint src/
   ```

**Finding:** CODE QUALITY: PASS / WARN / FAIL

---

## Phase 3: CONVENTION COMPLIANCE

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

3. **Flag any new patterns** not in CONVENTIONS.md — these should be documented in the PR description as "proposed convention updates"

**Finding:** CONVENTIONS: PASS / WARN / FAIL

---

## Phase 4: ARCHITECTURAL CONSISTENCY

**Purpose:** Verify implementation aligns with ADRs and system design.

1. **Read ARCHITECTURE.md** — Identify relevant ADRs for this PR's domain

2. **Verify:**
   - Implementation follows the relevant ADR's decision
   - No architectural anti-patterns introduced
   - Data flow matches the documented patterns
   - No undocumented external service integrations
   - State management approach is consistent

3. **Flag any architectural deviations** — these require an ADR update or new ADR

**Finding:** ARCHITECTURE: PASS / WARN / FAIL

---

## Phase 5: SECURITY

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

## Phase 6: TESTING

**Purpose:** Verify test quality and coverage.

1. **Run tests:**
   ```bash
   npm test
   ```

2. **Review test quality:**
   - Are all acceptance criteria covered by tests?
   - Do tests check both happy path and error cases?
   - Are edge cases from the issue body tested?
   - Are tests independent (no shared state)?
   - Do test names clearly describe what they verify?
   - Is there appropriate use of mocks (not too much, not too little)?

3. **Check coverage** (if coverage tool is configured):
   ```bash
   npm test -- --coverage
   ```

**Finding:** TESTING: PASS / WARN / FAIL

---

## Phase 7: PERFORMANCE

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

## Phase 8: DOCUMENTATION

**Purpose:** Verify documentation is adequate.

1. **Check for:**
   - JSDoc on exported functions and complex internal functions
   - Comments explaining "why" (not "what") for non-obvious code
   - Updated README if public API changed
   - API route documentation if new endpoints added
   - Type documentation for complex interfaces

**Finding:** DOCUMENTATION: PASS / WARN / FAIL

---

## Phase 9: ACCEPTANCE CRITERIA

**Purpose:** Final verification that all requirements are met.

1. **For each acceptance criterion in the issue:**
   - [ ] Criterion 1 — [PASS/FAIL: where in code this is satisfied]
   - [ ] Criterion 2 — [PASS/FAIL: where in code]
   - [ ] Criterion 3 — [PASS/FAIL: where in code]

2. **Verify build:**
   ```bash
   npm run build
   ```

**Finding:** ACCEPTANCE: PASS / WARN / FAIL

---

## Review Summary

Generate a structured review report:

```markdown
# Review Report — PR #$ARGUMENTS

## Results

| Phase | Check | Finding | Details |
|-------|-------|---------|---------|
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

### If APPROVE:
```bash
gh pr review $ARGUMENTS --approve --body "[Review report]"
```

### If REQUEST CHANGES:
```bash
gh pr review $ARGUMENTS --request-changes --body "[Review report with required fixes]"
```

### If COMMENT:
```bash
gh pr review $ARGUMENTS --comment --body "[Review report with suggestions]"
```

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
