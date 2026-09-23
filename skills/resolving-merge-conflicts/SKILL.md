---
name: resolving-merge-conflicts
description: "Work through an in-progress git merge or rebase conflict hunk by hunk, resolving by original intent traced to each side's primary sources (commits, PRs, issues), then run the project's checks and finish the operation. Use on merge/rebase conflicts, 'resolve conflict', 'merge-konflikt', 'rebase-konflikt', 'konflikt auflösen', 'CONFLICT (content)'."
context: main
---

# Resolving Merge Conflicts

Resolve by **intent**, not by picking sides mechanically. Every conflict is two changes that were each made for a reason — the resolution must honor both reasons or consciously document why one loses.

## Process

1. **See the current state.** `git status`, `git log --oneline --graph` on both sides, list the conflicting files. Establish which operation is in progress (merge vs. rebase) and what its stated goal is.

2. **Find the primary sources for each conflict.** Understand deeply why each change was made and what the original intent was: read the commit messages of both sides, check the PRs, check the original issues/tickets. Never resolve a hunk whose two intents you cannot state in one sentence each.

3. **Resolve each hunk.** Preserve both intents where possible. Where they are incompatible, pick the one matching the operation's stated goal and note the trade-off. Do **not** invent new behaviour. Default is always to resolve, never `--abort` — aborting throws away the analysis. If genuinely stuck (intents irreconcilable AND the goal doesn't decide it), say so and ask the user rather than aborting silently. (The escape hatches `--abort`/`--quit`/`--skip` pass `git-state-check.sh` since IMP-123, but they are a user decision, not a default.)

4. **Discover the project's automated checks and run them** — typically typecheck, then tests, then format. Fix anything the merge broke. A conflict resolution that was never compiled is unverified per `rules/slop-prevention.md`.

5. **Finish the operation — with the trunk gate.** Stage everything and commit; if rebasing, continue until all commits are rebased. **House rule per `rules/workflow-git.md`:** completing a merge INTO trunk after conflict resolution is SOFT-ACK at minimum — state what was resolved and how to undo, and never auto-merge to trunk; a human verifies correctness before that merge proceeds. Rebase/merge completion on a feature branch proceeds normally.

## Report

Close with a compact table: file · both intents (one line each) · resolution chosen · trade-off (if any). This is the artifact the human verifies in step 5.

---
*Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) `resolving-merge-conflicts` (MIT License, © 2026 Matt Pocock); trunk gate and verification wiring per this framework's workflow-git and slop-prevention rules (IMP-124).*
