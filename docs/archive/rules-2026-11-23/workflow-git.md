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

Types as above; areas: auth, api, ui, db, config, test, core, infra, status, architecture, conventions. Every code commit carries a tracking reference (docs-only may omit) — a GitHub issue number in issue-driven repos (`gh issue list` non-empty), a ledger id (`IMP-nnn`) in this framework's own repos. Never mix code and doc changes in one commit; commit every 60 minutes during active development.

## Pre-Commit Checklist

Before every commit: type checker · tests · linter · build pass; no debug statements; no stray characters at EOF; commit message follows the format; issue number referenced.

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

Prefer `gh pr merge` over MCP merge tools (the bash gate logs at command head); MCP-routed merges are equally ESCALATE via `hooks/mcp-agency-gate.sh`.

## Context Hygiene

**MANDATORY: Run `/clear` between issues.** Good hygiene: read the issue fresh every time, check what actually exists in the codebase, validate assumptions instead of carrying them over.

## Forbidden Actions

Direct commits to main/master/development · skipping `/clear` between issues · implementing beyond the issue's scope · skipping PR creation · PRs without linked issues · skipping tests · committing secrets · merging without review · force pushing to shared branches.

## Report-Only Default for Research / Planning / Audit Tasks

**When the user's request is classified as research, audit, review, explore, investigate, brainstorm, or plan — NEVER perform IRREVERSIBLE or REMOTE git/state operations without explicit instruction.**

Allowed in report-only mode: read-only artifacts (proposals, analyses), edits to files the user named, a local working branch, local commits. Suppressed until the user says otherwise: `git push`, `gh pr create` (even draft) to a shared repo, deploys/migrations/releases/pushed tags, and any direct commit to trunk.

Rule of thumb: **if it lives only in your local `.git` and can be undone with a reset or a branch delete, it is allowed in report-only mode. If it leaves the machine or changes shared/production state, it is suppressed until the user says otherwise.**

### Classifier — the keyword must govern the ACTION VERB

A single research/audit keyword anywhere in the message must NOT flip the entire task to report-only; classify by what the keyword *modifies*:

- **Report-only** when the keyword is the **head verb of the request** — the user asks you to *produce an analysis* ("audit the auth layer", "what would you do here").
- **NOT report-only** when it merely qualifies an implementation request ("implement the plan we reviewed", "fix the bug the audit found") — the head verb is implement/fix/refactor, so commit-by-default applies; the embedded keyword is a descriptor, not the task.

Keyword set (head-verb position triggers report-only): audit, auditiere, review, überprüfe, inspect, research, recherche, investigate, untersuche, explore, brainstorm, plan, planen, entwirf, denk durch, nur schauen, nur report, report only, report back, what would you do, was würdest du, vorschlag.

Commit-by-default (the 60-min cadence above) applies when the **head verb** is an implementation verb: "implement X", "build X", "baue", "implementiere"; "fix the bug", "repariere", "beheben"; "add feature X", "füge X hinzu"; "refactor X", "strukturiere um"; `/issue <#>` invocations.

**Genuinely uncertain classification:** take the **safe reversible middle ground** — commit on a local working branch, but do NOT push/PR/deploy — then **ask before publishing** with a short clarification rather than guessing.
