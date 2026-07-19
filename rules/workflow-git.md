# Workflow & Git Rules

> Git conventions, branch management, PR process, and context hygiene.

## Branch Management

- **One Issue = One Branch = One PR** — Never combine issues
- Branch from `main` (or `development` if project uses it)
- Branch naming: `<type>/issue-<number>-<kebab-description>`
  - Example: `feat/issue-42-jwt-token-refresh`
- Types: `feat`, `fix`, `refactor`, `test`, `docs`, `style`, `chore`, `perf`

## Trunk Is Not Always `main`

**At task start, read the repo's branch policy before any commit/push planning.** Multiple repos treat a non-`main` branch as the production / integration target (`development`, a long-lived release branch, etc.). Reflexively defaulting to `main` actively causes harm there.

- Check `CONTRIBUTING.md`, `CODEOWNERS`, branch-protection settings, or a per-project memory for the real trunk.
- Branch *from* and target PRs *at* that trunk — not reflexively `main`.
- When unsure which branch is production, ask before pushing.

> Distilled from multi-project experience (merge-intake 2026-05-28): default-`main` assumptions repeatedly caused mis-targeted work.

## Commit Format

```
<type>(<area>): <description> - closes #<issue-number>

<body>

Co-Authored-By: Claude <noreply@anthropic.com>
```

- **Types:** feat, fix, refactor, test, docs, style, chore, perf
- **Areas:** auth, api, ui, db, config, test, core, infra, status, architecture, conventions
- Every code commit references an issue number (docs-only may omit)
- **Separation of concerns:** Never mix code changes and doc changes in same commit
- Commit every 60 minutes during active development

## Pre-Commit Checklist

Before every commit:
- [ ] Type checker passes (`tsc --noEmit` / `mypy`)
- [ ] Tests pass (`npm test` / `pytest`)
- [ ] Linter passes (`eslint` / `ruff`)
- [ ] Build succeeds (`npm run build`)
- [ ] No debug statements (`console.log`, `print()`, `debugger`)
- [ ] No stray characters at EOF
- [ ] Commit message follows format
- [ ] Issue number referenced

## Pull Requests

- PR title: Clear description of what and why
- PR body includes:
  - Linked issue reference
  - Summary of changes
  - Testing checklist
  - Acceptance criteria verification
- PRs always target `main` or `development` (never other feature branches)
- Self-review before requesting review

## Feature Lifecycle Autonomy Bands

> Band semantics, gate mechanics, ack tokens, and the MCP ESCALATE set are defined once in [[agency-bands]]. This table only maps the standard feature-branch lifecycle onto those bands — it is **NOT standing approval for any unattended merge or irreversible operation.**

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

Prefer `gh pr merge` over MCP merge tools — the bash gate fires and logs at the command head. MCP-routed merges are equally ESCALATE (a merge trips the Meta Rule-of-Two: untrusted PR input + shared-remote state + external notifications) and are gated by `mcp-agency-gate.sh`; see [[agency-bands]].

## Context Hygiene

**MANDATORY: Run `/clear` between issues.**

Symptoms of context contamination:
- "Based on the authentication work we did earlier..."
- "Using the same pattern as before..."
- Reusing variable names from a different issue

Signs of good context hygiene:
- Reading the issue fresh every time
- Checking what actually exists in the codebase
- Validating assumptions rather than carrying them over

## Forbidden Actions

- Direct commits to main/master/development
- Skipping `/clear` between issues
- Implementing beyond the issue's scope
- Skipping PR creation
- PRs without linked issues
- Skipping tests
- Committing secrets
- Merging without review
- Force pushing to shared branches

## Report-Only Default for Research / Planning / Audit Tasks

**When the user's request is classified as research, audit, review, explore, investigate, brainstorm, or plan — NEVER perform IRREVERSIBLE or REMOTE git/state operations without explicit instruction.** Local, fully-reversible scaffolding (a working branch + local commits) is explicitly allowed and even encouraged, because it costs nothing to undo and keeps the working tree clean.

Evidence basis: across many sessions the user repeatedly typed "Do NOT commit. Report back." and "Do NOT create branches or commits. Just write the files." What that intent actually protects against is **publishing** work prematurely (pushes, PRs, deploys) — not a throwaway local branch. The earlier blanket ban on `git checkout -b` over-corrected: it suppressed a 100%-reversible operation, forcing analysis work to pile up on the trunk working tree.

### What is suppressed vs. allowed in report-only mode

| Operation | In report-only mode | Why |
|-----------|--------------------|-----|
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

A single research/audit keyword anywhere in the message must NOT flip the entire task to report-only. Classify by what the keyword *modifies*:

- **Report-only** when the research/audit keyword is the **head verb of the request** — i.e. the user is asking you to *produce an analysis*: "audit the auth layer", "review this module", "research how X works", "plan the migration", "what would you do here", "nur schauen", "report back".
- **NOT report-only** when the keyword merely qualifies an implementation request: "implement the plan we reviewed", "fix the bug the audit found", "refactor X after you investigate the call sites". Here the head verb is implement/fix/refactor → commit-by-default applies; the embedded "reviewed/audit/investigate" is a descriptor, not the task.

Keyword set (head-verb position triggers report-only): audit, auditiere, review, überprüfe, inspect, research, recherche, investigate, untersuche, explore, brainstorm, plan, planen, entwirf, denk durch, nur schauen, nur report, report only, report back, what would you do, was würdest du, vorschlag.

### Classification triggers (commit-by-default)

Default commit discipline (per 60-min cadence above) applies when the **head verb** is an implementation verb:
- "implement X", "build X", "baue", "implementiere"
- "fix the bug", "repariere", "beheben"
- "add feature X", "füge X hinzu"
- "refactor X", "strukturiere um"
- `/issue <#>` invocations

### How to handle ambiguity

If the head-verb classification is genuinely uncertain, default to the **safe reversible middle ground**: create a local working branch and commit there, but do NOT push/PR/deploy — then **ask before publishing** with a short clarification rather than guessing. Example: "I've kept this on a local `audit/...` branch with commits — want me to push it / open a PR, or leave it local?"

> The reversibility-vs-mode reasoning here is the band system defined in [[agency-bands]].
