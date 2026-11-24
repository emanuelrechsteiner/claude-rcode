# Workflow and Git

> Conventions for branches, commits and pull requests. Always loaded. Lifecycle table, pull-request details and the keyword list of the report-only classifier: `~/.claude/docs/reference/workflow-git.md`.

- **Find the trunk before you plan a commit or a push.** It is not always `main`: read CONTRIBUTING.md, the branch protection settings or the project memory. If it stays unclear which branch is production, ask before you push.
- **One unit of work, one branch, one pull request.** Branch from the trunk as `<type>/issue-<number>-<kebab-description>`, for example `feat/issue-42-jwt-token-refresh`. Types: feat, fix, refactor, test, docs, style, chore, perf. Commit on the work branch, not on the trunk, unless the user or the repository's own policy says otherwise.
- **Commit message:**

  ```
  <type>(<area>): <description> - closes #<issue-number>

  <body>

  Co-Authored-By: Claude <noreply@anthropic.com>
  ```

  Areas: auth, api, ui, db, config, test, core, infra, status, architecture, conventions. A code commit carries a tracking reference: the issue number in a repository that works with GitHub issues, the ledger id (`IMP-nnn`) in this framework's own repositories. A documentation-only commit may omit it, and so does a commit in a repository that has neither. Keep code changes and documentation changes in separate commits. When the session supplies its own attribution lines, use those as the trailer.
- **Before a commit** the project's type check, tests, linter and build pass, and no debug statements are left in.
- **Commit rhythm.** During implementation work (the request is to implement, build, fix, add or refactor) commit at logical checkpoints (states whose checks pass), at least about once an hour, without being asked. When the request is to research, audit, review, explore, investigate, brainstorm or plan, work report-only. What counts is the main verb of the request, not a keyword somewhere in it: "fix the bug the audit found" is implementation. Report-only means: you write up what you found and edit only files the user named; local branches and local commits are fine; pushing, opening pull requests (also drafts), deploying, tagging and committing on the trunk wait for an explicit instruction, whatever band they would otherwise have. If you cannot tell which kind of request it is, commit locally on a work branch and ask before you publish.
- **Pull requests** target the trunk, link the issue, summarize the change, and list how it was tested and which acceptance criteria were checked. Review your own diff first.
- **Bands** (see `agency-bands`): pushing a work branch and opening a pull request in the user's own repository are SOFT-ACK; a draft pull request there is AUTO. Merging to the trunk is ESCALATE, also after you resolved a merge conflict and also through an MCP tool; prefer `gh pr merge`, which the shell gate sees.
- **Identity.** Some paths belong to a specific git identity (`~/.claude/rules/identity.local.md`; a hook warns at session start on a mismatch). In a context no pattern covers, check `git config user.name` and `git config user.email` before you commit. A wrong author that is still local is fixed with `git -c user.name=... -c user.email=... commit --amend --no-edit`. Once it is pushed to a shared branch, leave the history, say so, and fix the local config.
