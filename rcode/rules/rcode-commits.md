# R.Code Workflow — Git Commit Conventions

> These rules define the git strategy for R.Code-managed projects.
> Import via `@.claude/rules/rcode-commits.md` in your project's CLAUDE.md.

---

## Commit Message Format

Every commit follows this structured format:

```
<type>(<area>): <description> - closes #<N>   (tracker github)
<type>(<area>): <description> - closes P-<NNN> (tracker plan)

Phase: <phase-number>
Feature: <feature-id>

<body — what changed and why>

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Example

```
feat(auth): implement JWT token refresh flow - closes #42

Phase: 2
Feature: F003-authentication

- Add refresh token rotation with 7-day expiry
- Implement token blacklist in Redis for revoked tokens
- Add middleware to auto-refresh expired access tokens
- Handle edge case: concurrent refresh requests use mutex

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Commit Types

| Type | When to Use | Example |
|------|-------------|---------|
| `feat` | New feature or capability | `feat(venues): add venue creation form` |
| `fix` | Bug fix | `fix(auth): resolve token expiry race condition` |
| `refactor` | Code restructuring (no behavior change) | `refactor(api): extract validation middleware` |
| `test` | Adding or updating tests | `test(venues): add CRUD integration tests` |
| `docs` | Documentation only changes | `docs(status): update project status after #42` |
| `style` | Formatting, whitespace (no logic change) | `style(ui): fix inconsistent indentation` |
| `chore` | Maintenance, dependencies, tooling | `chore(deps): update React to v19` |
| `perf` | Performance improvement | `perf(db): add index for venue lookup query` |

---

## Area Scopes

### Code Areas

| Area | Covers |
|------|--------|
| `auth` | Authentication, authorization, sessions |
| `api` | API routes, endpoints, middleware |
| `ui` | UI components, layouts, pages |
| `db` | Database schema, migrations, queries |
| `config` | Configuration, environment, build |
| `test` | Test infrastructure, fixtures, mocks |
| `core` | Core business logic, shared utilities |
| `infra` | CI/CD, deployment, Docker |

### Documentation Areas

| Area | Covers |
|------|--------|
| `status` | PROJECT-STATUS.md updates |
| `architecture` | ARCHITECTURE.md, ADR updates |
| `conventions` | CONVENTIONS.md updates |
| `scope` | Scope manifest changes |
| `handoff` | Agent handoff documentation |
| `phase-gate` | Phase summary documents |
| `project` | BRAINSTORM.md, CLAUDE.md, START_HERE.md |

---

## Branch Naming Convention

Tracker `github`:
```
<type>/issue-<N>-<kebab-case-description>
```
Tracker `plan`:
```
<type>/p-<NNN>-<kebab-case-description>
```

### Examples

```
feat/issue-42-jwt-token-refresh          (tracker github)
fix/issue-87-login-redirect-loop
refactor/issue-103-extract-auth-middleware
docs/issue-15-api-documentation
test/issue-56-venue-integration-tests

feat/p-042-jwt-token-refresh             (tracker plan)
fix/p-087-login-redirect-loop
```

### Rules

- Branch names are **lowercase** with **hyphens** (kebab-case)
- Always include the **unit ID** (`issue-<N>` or `p-<NNN>`)
- Description should be **3-5 words** max
- One branch per unit — **never combine units** — this is **standalone
  mode** for `/issue`

### The Lead's Work Branch (Worker Mode, A1)

When `/team-lead` dispatches workers for one or more units in a single
wave, the workers do NOT create per-unit branches — they commit onto ONE
shared branch the lead names before dispatch:
```
work/<YYYY-MM-DD>-<slug>
```
(unless the user named a branch explicitly). The lead owns this branch —
creation, the consolidated merge decision (ESCALATE, one y/n), and
per-unit commit references stay exactly as in standalone mode (see below).
The per-unit branch convention above applies only to standalone `/issue`.

---

## Tag Conventions

| Tag Format | When Created | Example |
|------------|--------------|---------|
| `v0.<phase>.0-<phase-name>` | Phase completion, on `/phase-gate` PASS or WARN — **optional but recommended** (`/phase-gate` proposes it, never forces it) | `v0.1.0-foundation` |
| `v1.0.0` | First production release (an ESCALATE-band release, via `/launch-team`) | `v1.0.0` |
| `scope-lock-<YYYY-MM-DD>` | After `/decompose` locks scope | `scope-lock-2026-03-01` |
| `handoff-<YYYY-MM-DD>` | Major agent transitions | `handoff-2026-03-15` |

`/phase-gate` and `/decompose` create these as **local** tags (AUTO band,
per `~/.claude/rules/agency-bands.md`) — pushing tags to a remote is a
separate, explicit step, not part of either command.

### Semantic Versioning

- **v0.N.0** — Phase N complete (pre-release)
- **v1.0.0** — First production release (all phases complete)
- **v1.N.0** — Post-release feature additions
- **v1.0.N** — Post-release bug fixes

---

## Separation of Concerns

### Rule: Documentation Commits Are Separate from Code Commits

**NEVER mix code changes with documentation updates in the same commit.**

```bash
# CORRECT: Separate commits
git commit -m "feat(auth): implement login endpoint - closes #42"
git commit -m "docs(status): update project status after #42"

# WRONG: Mixed commit
git commit -m "feat(auth): implement login + update docs"
```

### Rule: Every Code Commit References a Work Unit

Every code commit (feat, fix, refactor, test, perf) **must** reference a
work unit with `closes` or `refs`, tracker-agnostic regex:
```
(closes|refs) (#[0-9]+|P-[0-9]{3,}(\.\.P-[0-9]{3,})?)((, ?)(#[0-9]+|P-[0-9]{3,}(\.\.P-[0-9]{3,})?))*
```
Real examples: `refs #42`, `closes P-051`, `refs P-051..P-105`,
`refs P-085, P-100`.

**A unit's own implementation commit references exactly one unit** —
ranges (`P-051..P-105`) and comma lists (`#48, #49, #50`) are reserved for
**consolidation commits** (e.g. a lead's squash-merge closing several
units from one wave at once), never for the unit's own work. See
`rcode-workflow.md` "Critical Rules" for the same statement in workflow
terms.

**Exception:** Pure documentation commits (`docs` type) and `chore`
commits may omit unit references if they are maintenance tasks.

---

## Commit Workflow

### During `/issue` — Standalone Mode (`/issue <unit>` invoked directly)

```bash
# 1. Create branch
git checkout -b feat/issue-42-jwt-refresh

# 2. Implement (multiple small commits OK)
git commit -m "feat(auth): add refresh token model - refs #42"
git commit -m "feat(auth): implement token rotation logic - refs #42"
git commit -m "test(auth): add refresh token tests - refs #42"

# 3. Final commit (closes the unit)
git commit -m "feat(auth): complete JWT refresh flow - closes #42"

# 4. Separate docs commit, on the SAME branch (the standalone run IS the
#    lead/main thread here — see rcode-workflow.md's single-writer rule
#    for why a dispatched WORKER never writes this commit itself)
git commit -m "docs(status): update project status after #42"
```

### During `/issue` — Worker Mode (dispatched by `/team-lead`, A1)

No branch creation, no push, no PR, and no status/agent-log commit — the
worker commits its implementation onto the branch the LEAD already named
(see "The Lead's Work Branch" above), then reports back:

```bash
# On work/2026-09-23-auth-refresh (created by the lead before dispatch)
git commit -m "feat(auth): complete JWT refresh flow - closes #42"
```

The lead writes the status/agent-log commit and owns the eventual merge
decision (ESCALATE, one y/n) once all of the wave's units land.

### During `/phase-gate`

```bash
# Phase summary commit
git commit -m "docs(phase-gate): phase 2 complete - authentication"

# Tag — optional but recommended, only on PASS or WARN
git tag -a v0.2.0-authentication -m "Phase 2: Authentication complete"
```

### During `/handoff`

```bash
# Handoff commit
git commit -m "docs(handoff): session handoff $(date +%Y-%m-%d)"
```

---

## Pre-Commit Checklist

Before every commit, verify:

- [ ] The project's **check trio** passes — the project's `CLAUDE.md` →
      `## Mandatory Pre-Commit` is the single source for what that means
      (type/build · test · lint); never a hardcoded tool list here
- [ ] No debug statements (`console.log`, `print()`, `debugger`)
- [ ] No stray characters at EOF
- [ ] Commit message follows the format above
- [ ] Work unit is referenced (`closes`/`refs` — see the regex above)
- [ ] Branch name matches convention (standalone mode) or is the lead's
      named work branch (worker mode)
