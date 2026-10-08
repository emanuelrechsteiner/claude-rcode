<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/workflow-git.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/workflow-git.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Trunk Is Not Always `main`

> Distilled from multi-project experience (merge-intake 2026-05-28): default-`main` assumptions repeatedly caused mis-targeted work.

## Commit Format

  > **Why this was rewritten (IMP-121, 2026-08-01):** the rule previously demanded an issue number
  > unconditionally and was violated **17 times out of 17** across every active repo — not out of
  > sloppiness, but because those repos genuinely use `IMP-###`. A rule that is broken 100% of the
  > time does not enforce discipline, it teaches that rules are decorative. The requirement is
  > unchanged in substance (every code commit must be traceable to a tracked unit of work); only the
  > accepted form now matches how the repos actually work.

## Report-Only Default for Research / Planning / Audit Tasks

Evidence basis: across many sessions the user repeatedly typed "Do NOT commit. Report back." and "Do NOT create branches or commits. Just write the files." What that intent actually protects against is **publishing** work prematurely (pushes, PRs, deploys) — not a throwaway local branch. The earlier blanket ban on `git checkout -b` over-corrected: it suppressed a 100%-reversible operation, forcing analysis work to pile up on the trunk working tree.

## Moved from the rule on 2026-09-29 (IMP-234)

> Condensing round IMP-234 (instruction files under 150k chars). The passages below were shortened, merged into prose, or removed in `rules/workflow-git.md`; each is carried over verbatim from the rule as it stood before that round, under the heading it had there. The normative content stays in the rule; what lives only here is list formatting, a duplicated types line, and extra examples.

### Branch Management

- **One Issue = One Branch = One PR** — Never combine issues
- Branch from `main` (or `development` if project uses it)
- Branch naming: `<type>/issue-<number>-<kebab-description>`
  - Example: `feat/issue-42-jwt-token-refresh`
- Types: `feat`, `fix`, `refactor`, `test`, `docs`, `style`, `chore`, `perf`

### Trunk Is Not Always `main`

**At task start, read the repo's branch policy before any commit/push planning.** Multiple repos treat a non-`main` branch as the production / integration target (`development`, a long-lived release branch, etc.). Reflexively defaulting to `main` actively causes harm there.

- Check `CONTRIBUTING.md`, `CODEOWNERS`, branch-protection settings, or a per-project memory for the real trunk.
- Branch *from* and target PRs *at* that trunk — not reflexively `main`.
- When unsure which branch is production, ask before pushing.

### Commit Format

- **Types:** feat, fix, refactor, test, docs, style, chore, perf
- **Areas:** auth, api, ui, db, config, test, core, infra, status, architecture, conventions
- Every code commit carries a **tracking reference** (docs-only may omit). Two forms are valid, and
  which one applies is a property of the repo, not a preference:
  - **GitHub issue number** (`#42`, `closes #42`) — required in repos running an issue-driven loop
    (`/decompose` → `/issue <#>`), i.e. wherever `gh issue list` is non-empty.
  - **Ledger id** (`IMP-114`) — the correct reference in this framework's own config repos, which
    track work in `improvement-ledger.json` rather than as GitHub issues.
- **Separation of concerns:** Never mix code changes and doc changes in same commit
- Commit every 60 minutes during active development

### Pre-Commit Checklist

Before every commit:
- [ ] Type checker passes (`tsc --noEmit` / `mypy`)
- [ ] Tests pass (`npm test` / `pytest`)
- [ ] Linter passes (`eslint` / `ruff`)
- [ ] Build succeeds (`npm run build`)
- [ ] No debug statements (`console.log`, `print()`, `debugger`)
- [ ] No stray characters at EOF
- [ ] Commit message follows format
- [ ] Issue number referenced

### Pull Requests

- PR title: Clear description of what and why
- PR body includes:
  - Linked issue reference
  - Summary of changes
  - Testing checklist
  - Acceptance criteria verification
- PRs always target `main` or `development` (never other feature branches)
- Self-review before requesting review

### Feature Lifecycle Autonomy Bands

> Band semantics, gate mechanics, ack tokens, and the MCP ESCALATE set are defined once in [[agency-bands]]. This table only maps the standard feature-branch lifecycle onto those bands — it is **NOT standing approval for any unattended merge or irreversible operation.**

Prefer `gh pr merge` over MCP merge tools — the bash gate fires and logs at the command head. MCP-routed merges are equally ESCALATE (a merge trips the Meta Rule-of-Two: untrusted PR input + shared-remote state + external notifications) and are gated by `mcp-agency-gate.sh`; see [[agency-bands]].

### Context Hygiene

**MANDATORY: Run `/clear` between issues.**

Symptoms of context contamination:
- "Based on the authentication work we did earlier..."
- "Using the same pattern as before..."
- Reusing variable names from a different issue

Signs of good context hygiene:
- Reading the issue fresh every time
- Checking what actually exists in the codebase
- Validating assumptions rather than carrying them over

### Forbidden Actions

- Direct commits to main/master/development
- Skipping `/clear` between issues
- Implementing beyond the issue's scope
- Skipping PR creation
- PRs without linked issues
- Skipping tests
- Committing secrets
- Merging without review
- Force pushing to shared branches

### Report-Only Default for Research / Planning / Audit Tasks

**When the user's request is classified as research, audit, review, explore, investigate, brainstorm, or plan — NEVER perform IRREVERSIBLE or REMOTE git/state operations without explicit instruction.** Local, fully-reversible scaffolding (a working branch + local commits) is explicitly allowed and even encouraged, because it costs nothing to undo and keeps the working tree clean.

### What is suppressed vs. allowed in report-only mode

| Operation | In report-only mode | Why |
|-----------|--------------------|-----|

### Classifier — the keyword must govern the ACTION VERB

A single research/audit keyword anywhere in the message must NOT flip the entire task to report-only. Classify by what the keyword *modifies*:

- **Report-only** when the research/audit keyword is the **head verb of the request** — i.e. the user is asking you to *produce an analysis*: "audit the auth layer", "review this module", "research how X works", "plan the migration", "what would you do here", "nur schauen", "report back".
- **NOT report-only** when the keyword merely qualifies an implementation request: "implement the plan we reviewed", "fix the bug the audit found", "refactor X after you investigate the call sites". Here the head verb is implement/fix/refactor → commit-by-default applies; the embedded "reviewed/audit/investigate" is a descriptor, not the task.

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

### Second pass — Context Hygiene symptom / good-sign lists (first-pass wording)

Contamination symptoms: "Based on the authentication work we did earlier...", "Using the same pattern as before...", variable names reused from a different issue. Good hygiene: read the issue fresh every time, check what actually exists in the codebase, validate assumptions instead of carrying them over.
