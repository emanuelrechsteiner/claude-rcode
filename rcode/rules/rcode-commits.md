# R.Code Workflow — Git Commit Conventions

> These rules define the git strategy for R.Code-managed projects.
> Import via `@.claude/rules/rcode-commits.md` in your project's CLAUDE.md.

---

## Commit Message Format

Every commit follows this structured format:

```
<type>(<area>): <description> - closes #<issue-number>

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

```
<type>/issue-<number>-<kebab-case-description>
```

### Examples

```
feat/issue-42-jwt-token-refresh
fix/issue-87-login-redirect-loop
refactor/issue-103-extract-auth-middleware
docs/issue-15-api-documentation
test/issue-56-venue-integration-tests
```

### Rules

- Branch names are **lowercase** with **hyphens** (kebab-case)
- Always include the **issue number**
- Description should be **3-5 words** max
- One branch per issue — **never combine issues**

---

## Tag Conventions

| Tag Format | When Created | Example |
|------------|--------------|---------|
| `v0.<phase>.0-<phase-name>` | Phase completion (`/phase-gate`) | `v0.1.0-foundation` |
| `v1.0.0` | First production release | `v1.0.0` |
| `scope-lock-<YYYY-MM-DD>` | After `/decompose` locks scope | `scope-lock-2026-03-01` |
| `handoff-<YYYY-MM-DD>` | Major agent transitions | `handoff-2026-03-15` |

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

### Rule: Every Code Commit References an Issue

Every code commit (feat, fix, refactor, test, perf) **must** reference a GitHub issue number with `closes #N` or `refs #N`.

**Exception:** Pure documentation commits (`docs` type) and `chore` commits may omit issue references if they are maintenance tasks.

---

## Commit Workflow

### During `/issue`

```bash
# 1. Create branch
git checkout -b feat/issue-42-jwt-refresh

# 2. Implement (multiple small commits OK)
git commit -m "feat(auth): add refresh token model - refs #42"
git commit -m "feat(auth): implement token rotation logic - refs #42"
git commit -m "test(auth): add refresh token tests - refs #42"

# 3. Final commit (closes the issue)
git commit -m "feat(auth): complete JWT refresh flow - closes #42"

# 4. Separate docs commit
git commit -m "docs(status): update project status after #42"
```

### During `/phase-gate`

```bash
# Phase summary commit
git commit -m "docs(phase-gate): phase 2 complete - authentication"

# Tag
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

- [ ] TypeScript compiles (`npx tsc --noEmit`)
- [ ] Tests pass (`npm test`)
- [ ] ESLint passes (`npx eslint src/`)
- [ ] Build succeeds (`npm run build`)
- [ ] No debug statements (`console.log`, `debugger`)
- [ ] No stray characters at EOF
- [ ] Commit message follows format above
- [ ] Issue number is referenced
- [ ] Branch name matches convention
