# Workflow & Git Rules

> Git conventions, branch management, PR process, and context hygiene.

## Branch Management

- **One Issue = One Branch = One PR** — never combine issues.
- Branch from `main` (or `development` if the project uses it); naming `<type>/issue-<number>-<kebab-description>` (e.g. `feat/issue-42-jwt-token-refresh`); types `feat`, `fix`, `refactor`, `test`, `docs`, `style`, `chore`, `perf`.

## Trunk Is Not Always `main`

**At task start, read the repo's branch policy before any commit/push planning** — many repos use a non-`main` production/integration branch (`development`, a long-lived release branch, etc.), and reflexively defaulting to `main` actively causes harm there. Find the real trunk in `CONTRIBUTING.md`, `CODEOWNERS`, branch-protection settings, or a per-project memory; branch *from* and target PRs *at* that trunk; when unsure which branch is production, ask before pushing.

## Commit Format

```
<type>(<area>): <description> - closes #<issue-number>

<body>

Co-Authored-By: Claude <noreply@anthropic.com>
```

- **Types** as above; **Areas:** auth, api, ui, db, config, test, core, infra, status, architecture, conventions.
- Every code commit carries a **tracking reference** (docs-only may omit); the form is a property of the repo, not a preference: a **GitHub issue number** (`#42`, `closes #42`) in repos running an issue-driven loop (`/decompose` → `/issue <#>`, i.e. `gh issue list` is non-empty); a **ledger id** (`IMP-114`) in this framework's own config repos, which track work in `improvement-ledger.json`.
- Never mix code changes and doc changes in the same commit. Commit every 60 minutes during active development.

## Pre-Commit Checklist

Before every commit: type checker passes (`tsc --noEmit` / `mypy`) · tests pass (`npm test` / `pytest`) · linter passes (`eslint` / `ruff`) · build succeeds (`npm run build`) · no debug statements (`console.log`, `print()`, `debugger`) · no stray characters at EOF · commit message follows the format · issue number referenced.

## Pull Requests

Title: a clear description of what and why. Body: linked issue reference, summary of changes, testing checklist, acceptance-criteria verification. PRs always target `main` or `development` (never other feature branches). Self-review before requesting review.

## Feature Lifecycle Autonomy Bands

> Maps the standard feature-branch lifecycle onto the bands defined once in [[agency-bands]] (band semantics, gate mechanics, ack tokens, MCP ESCALATE set) — **NOT standing approval for any unattended merge or irreversible operation.**

| Lifecycle step | Band |
|---|---|
| `git checkout -b <feature-branch>` (create branch) | **AUTO** |
| `git add` / `git commit` on feature branch | **AUTO** |
| `git push <feature-branch>` (non-force) | **SOFT-ACK** |
| `gh pr create --draft` (open draft PR) | **AUTO** |
| `gh pr create` (open PR that notifies reviewers) | **SOFT-ACK** |
| Code review via `code-reviewer-agent` (read-only) | **AUTO** |
| Resolve merge conflict → commit + push | **SOFT-ACK** — **never auto-merge** after conflict resolution; a human verifies correctness before merge proceeds |
| `gh pr merge` / `git merge` to trunk / GitHub auto-merge / MCP-routed merge (`mcp__*__merge_pull_request`) | **ESCALATE** |

Prefer `gh pr merge` over MCP merge tools — the bash gate fires and logs at the command head. MCP-routed merges are equally ESCALATE (Meta Rule-of-Two: untrusted PR input + shared-remote state + external notifications), gated by `mcp-agency-gate.sh`.

## Context Hygiene

**MANDATORY: Run `/clear` between issues.** Contamination symptoms: "Based on the authentication work we did earlier...", "Using the same pattern as before...", variable names reused from a different issue. Good hygiene: read the issue fresh every time, check what actually exists in the codebase, validate assumptions instead of carrying them over.

## Forbidden Actions

Direct commits to main/master/development · skipping `/clear` between issues · implementing beyond the issue's scope · skipping PR creation · PRs without linked issues · skipping tests · committing secrets · merging without review · force pushing to shared branches.

## Report-Only Default for Research / Planning / Audit Tasks

**When the user's request is classified as research, audit, review, explore, investigate, brainstorm, or plan — NEVER perform IRREVERSIBLE or REMOTE git/state operations without explicit instruction.** Local, fully-reversible scaffolding (a working branch + local commits) is explicitly allowed and even encouraged: it costs nothing to undo and keeps the working tree clean.

| Operation | In report-only mode | Why |
|---|---|---|
| Write read-only artifacts, proposals, analyses | ✅ Allowed | The deliverable of research/audit |
| Edit files the user explicitly named | ✅ Allowed | User-directed |
| `git checkout -b <working-branch>` (local) | ✅ Allowed | Fully reversible; isolates scratch work |
| `git add` / `git commit` on a local working branch | ✅ Allowed | Local-only, reversible (`git reset`, branch delete) |
| `git push` / `git push -u` | ❌ Suppressed | Publishes; not trivially reversible on shared remotes |
| `gh pr create` (even draft) to a shared repo | ❌ Suppressed | Notifies others; remote state |
| Deploys, prod migrations, releases, tags pushed to remote | ❌ Suppressed | Irreversible / externally visible |
| Direct commit to trunk (`main`/`master`/`development`) | ❌ Suppressed | Violates Branch Management above, regardless of mode |

Rule of thumb: **if it lives only in your local `.git` and can be undone with a reset or a branch delete, it is allowed in report-only mode. If it leaves the machine or changes shared/production state, it is suppressed until the user says otherwise.**

### Classifier — the keyword must govern the ACTION VERB

A single research/audit keyword anywhere in the message must NOT flip the entire task to report-only; classify by what the keyword *modifies*:

- **Report-only** when the keyword is the **head verb of the request** — the user asks you to *produce an analysis* ("audit the auth layer", "what would you do here").
- **NOT report-only** when it merely qualifies an implementation request ("implement the plan we reviewed", "fix the bug the audit found") — the head verb is implement/fix/refactor, so commit-by-default applies; the embedded keyword is a descriptor, not the task.

Keyword set (head-verb position triggers report-only): audit, auditiere, review, überprüfe, inspect, research, recherche, investigate, untersuche, explore, brainstorm, plan, planen, entwirf, denk durch, nur schauen, nur report, report only, report back, what would you do, was würdest du, vorschlag.

Commit-by-default (the 60-min cadence above) applies when the **head verb** is an implementation verb: "implement X", "build X", "baue", "implementiere"; "fix the bug", "repariere", "beheben"; "add feature X", "füge X hinzu"; "refactor X", "strukturiere um"; `/issue <#>` invocations.

**Genuinely uncertain classification:** take the **safe reversible middle ground** — commit on a local working branch, but do NOT push/PR/deploy — then **ask before publishing** with a short clarification rather than guessing. The reversibility-vs-mode reasoning is the band system of [[agency-bands]].
