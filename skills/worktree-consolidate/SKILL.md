---
name: worktree-consolidate
description: "Safe worktree consolidation specialist. Discovers all active git worktrees, audits their status (dirty state, ahead/behind trunk, open PR), classifies each by merge-readiness, presents a read-only consolidation plan to the user, then gates every mutation (merge, push, prune, branch-delete) behind a one-per-operation y/n via the autonomy-arbiter. Never auto-merges. Triggers on 'merge worktrees', 'consolidate worktrees', 'bring branches together', 'worktree consolidation', 'clean up worktrees', 'prune worktrees', 'worktrees zusammenführen', 'gittrees zusammenführen', 'auf main zusammenführen', 'branches zusammenführen', 'worktree aufräumen'."
context: fork
model: haiku
allowed-tools: Bash(git:*), Bash(gh:*)
---

# Worktree Consolidate — Safe Multi-Worktree Merge Coordination

This skill helps users with many active git worktrees (common in heavy parallel-worktree workflows) safely merge branches back to trunk. It is **diagnostic-first, mutation-gated**: it reads and classifies before it ever touches state, and every destructive action requires an explicit user y/n.

## Safety Invariant (Non-Negotiable)

All merge / push / prune / branch-delete operations are **ESCALATE-band** per `autonomy-arbiter.md`. This skill NEVER auto-merges, auto-pushes, or auto-prunes. Every mutation is offered as a gated y/n. Do not add any bypass.

---

## Workflow (Follow Steps in Order)

### Step 1 — Discover all worktrees

```bash
git worktree list --porcelain
```

Parse output to extract: worktree path, HEAD SHA, branch name, and whether it is bare or detached.

Also record the repo root (the main worktree).

### Step 2 — Determine the real trunk

Per `workflow-git.md`, **trunk is not always `main`**. Determine it by:

```bash
# Check for explicit default branch
git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}'

# Fallback: check CONTRIBUTING.md or branch-protection hints
gh api repos/{owner}/{repo} --jq '.default_branch' 2>/dev/null
```

If the remote default cannot be determined, look for the longest-lived branch among `main`, `master`, `development`, `develop`, `trunk` that exists locally. If still ambiguous, **ask the user** before proceeding — do not guess.

### Step 3 — Per-worktree audit

For each non-main worktree (skip the root / bare entries):

```bash
# 1. Dirty state
git -C <worktree_path> status --porcelain

# 2. Ahead/behind trunk
git -C <worktree_path> rev-list --left-right --count <trunk>...<branch>
# output: "<commits_ahead>\t<commits_behind>"

# 3. Associated PR (if any)
gh pr list --head <branch> --json number,title,state,url 2>/dev/null

# 4. Already merged into trunk?
git -C <worktree_path> merge-base --is-ancestor <branch_sha> origin/<trunk> \
  && echo "already-merged" || echo "not-merged"
```

Collect all results before presenting anything.

### Step 4 — REFUSE dirty worktrees

If any worktree has uncommitted changes (non-empty `git status --porcelain`):

- **Do not proceed** with that worktree.
- Surface the list of uncommitted files.
- Tell the user: "Please commit or stash these changes first, then re-run the skill."
- Exclude that worktree from the consolidation plan entirely. Do not attempt to stash on the user's behalf.

### Step 5 — Classify each worktree

Assign one of three categories, ordered by risk:

| Class | Condition | Recommended action |
|-------|-----------|-------------------|
| `already-merged` | Branch ancestor of trunk HEAD | Offer to prune worktree + delete branch (gated) |
| `clean-mergeable` | 0 dirty files, ahead of trunk, no known conflicts | Offer FF or merge-commit onto trunk (gated) |
| `conflict-likely` | Behind trunk by >0 commits AND has local commits diverging from trunk | Warn user; offer to rebase or merge manually (gated); show conflict-risk score |

Conflict-risk score (informational): `commits_behind × files_changed_estimate`. Higher = more likely to conflict. Sort `conflict-likely` group ascending by score (lowest risk first).

### Step 6 — Present the consolidation PLAN (read-only)

Before ANY mutation, present a summary table:

```
## Worktree Consolidation Plan
Trunk: <trunk_branch> (@ <short_sha>)

| # | Path | Branch | Ahead | Behind | PR | Class | Recommended action |
|---|------|--------|-------|--------|----|-------|--------------------|
| 1 | /path/to/wt1 | feat/foo | 3 | 0 | #42 open | clean-mergeable | merge onto trunk → prune |
| 2 | /path/to/wt2 | fix/bar | 0 | 0 | #38 merged | already-merged | prune only |
| 3 | /path/to/wt3 | feat/baz | 5 | 12 | none | conflict-likely | rebase first (risk: HIGH) |
| 4 | /path/to/wt4 | feat/qux | — | — | — | DIRTY | BLOCKED — commit/stash first |

Dirty worktrees are excluded from this run.
```

After presenting the plan, **pause and ask the user**: "Which of these would you like to consolidate? (All / specific numbers / none)"

Do NOT proceed until the user responds.

### Step 7 — Execute selected merges (one gated operation at a time)

For each user-selected worktree in the `clean-mergeable` or `already-merged` class:

**For `clean-mergeable`:**

Present the exact commands you intend to run, then ask the user for explicit y/n approval before running EACH of the following (they are separate ESCALATE-band operations):

1. `git fetch origin` (non-destructive — AUTO-allowed, no gate)
2. `git checkout <trunk>` and `git merge --no-ff <branch>` OR `git merge --ff-only <branch>` — ask user which style they prefer
3. `git push origin <trunk>` — **ESCALATE** (gated y/n, surfaces the exact command)
4. After push confirmed: offer to prune worktree and delete branch (Step 8)

**For `already-merged`:**

Skip directly to Step 8 (prune + branch delete, still gated).

**For `conflict-likely`:**

Do NOT attempt to merge. Instead:
- Report the estimated conflict risk.
- Offer to run `git merge --no-commit --no-ff <branch>` into a scratch branch so the user can inspect conflicts manually.
- That operation is itself gated (it creates a new state the user must commit or abort).

### Step 8 — Offer to prune (gated)

After a confirmed merge (or for already-merged branches), offer:

```
Would you like to prune the worktree and delete the remote-tracking branch?
Operations that will be run (each requires your approval):
  1. git worktree remove <path>          [local, reversible]
  2. git branch -d <branch>             [local, reversible — uses -d not -D]
  3. git push origin --delete <branch>  [REMOTE — irreversible if no backup]
Proceed? (y/n/partial)
```

Gate each operation individually. Use `git branch -d` (safe delete — refuses if unmerged) not `-D`. For the remote-branch delete, surface a clear irreversibility warning.

### Step 9 — Summary report

After all selected operations (or user abort):

```
## Consolidation Summary
Merged:        [list of branches merged]
Pruned:        [list of worktrees removed]
Branches deleted (local): [list]
Branches deleted (remote): [list]
Skipped (dirty):    [list]
Skipped (conflict): [list]
Skipped (user):     [list]
```

---

## Failure Modes

| Failure | Detection | Response |
|---------|-----------|----------|
| Trunk cannot be determined | No `origin HEAD` and no standard branch name | Ask user explicitly; never guess |
| Dirty worktree detected | `git status --porcelain` non-empty | Exclude from plan; surface files; ask user to fix first |
| Merge conflict at execution time | `git merge` exits non-zero | Abort merge; leave index clean (`git merge --abort`); report which files conflicted; move to next worktree |
| `git worktree remove` fails (modified files) | Non-zero exit | Report and stop; do not force-remove (`--force` is forbidden here) |
| Remote branch delete fails (protected) | `gh`/`git push --delete` returns error | Report branch-protection rule; skip; user must delete via web UI |
| PR still open at merge time | `gh pr list --head <branch>` returns open PR | Warn user ("PR #N is still open"); ask whether to merge PR via GitHub instead; do not merge locally without acknowledgement |
| `gh` CLI not available | `which gh` fails | Fall back to git-only discovery; skip PR status column; note limitation |

---

## Key Rules (Summary)

- **Diagnostic before mutation** — always present the plan first.
- **Trunk detection** — read `workflow-git.md`; never assume `main`.
- **Dirty worktrees** — excluded from the run entirely; never stash on the user's behalf.
- **Every ESCALATE op** (push, prune, remote branch delete) gets an individual y/n.
- **`-d` not `-D`** for branch deletes; the safety check is a feature, not a nuisance.
- **Open PRs** — surface them before local merge; ask which path the user prefers.
- **No bypass tokens** — this skill does not emit `CLAUDE_AGENCY_ACK_ONCE` or any gate-bypass. The autonomy-arbiter gate fires naturally on each gated command; the user supplies the ack.
