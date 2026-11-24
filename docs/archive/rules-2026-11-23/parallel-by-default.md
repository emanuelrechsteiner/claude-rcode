# Parallel-by-Default Rule

> For every task with 2+ independent units, evaluate parallel dispatch BEFORE executing. Always loaded. Each unit's Agent/Model/Effort comes from `agents/control-agent.md` §2 (IMP-091) — assign it before every dispatch, auto-approved or not; don't restate the matrix here.

## The Norm

When a task could be decomposed into 2+ independent units:

1. **Decompose** the task into atomic units.
2. **Analyze independence** — do units share files? Does B need A's output? Is each unit meaningful (>2 min serial)? Shared files, an output→input chain, or tiny units → execute serially.
3. **If 2+ truly independent units exist AND the work is reversible with disjoint, lock-claimed file-sets** → **auto-dispatch** in parallel with a one-line note ("Dispatching N parallel agents on disjoint file-sets X/Y/Z; locks pre-claimed") — do NOT gate on a confirmation prompt.
4. **Reserve the confirmation handshake** (the full proposal + y/n) for parallel work that either contains an **irreversible / ESCALATE-band operation** (anything in `agency-bands.md`'s ESCALATE band — force-push, prod migration, `gh pr merge`, deploys, external sends, destructive deletes) or has **ambiguous scope** (file-sets you cannot prove disjoint, or unclear which files each unit touches).
5. **Only execute sequentially** when parallelism is shown to be wasteful or unsafe.

Why: serial execution of independent work multiplies token cost and wall time, while a confirmation gate on *reversible, disjoint* work adds friction without safety value.

## Decision Matrix — when YES, when NO

Parallel: the same mechanical operation across 3+ files, backend + frontend + tests, 3+ repos/docs read-only, tests for 4 modules, N component migrations, audits of disjoint sub-systems.
Not parallel: a single-file edit, pipelined work (plan → implement → test), tasks under 2 minutes, a cross-file rename that couples files, read-then-decide flows.

## The Proposal Format (for ESCALATE-band or ambiguous-scope work)

For ESCALATE-band or ambiguous-scope parallel work present the proposal (units, agent/model/effort, exclusive file sets, wall-time, safety line) BEFORE executing and wait for y/n; after confirmation the `parallel-dispatch` skill runs claim → dispatch → synthesis. Template: `~/.claude/docs/archive/rules-evidence/parallel-by-default.md`.

## When to skip the proposal (just execute)

1. Reversible work with disjoint, lock-claimed file-sets → auto-dispatch with a one-line note (the common-case default).
2. User already specified parallelism ("do these 3 in parallel") → just do it.
3. User opted out (`export CLAUDE_PARALLEL_AUTO_SUGGEST=0` for the session, or in `~/.zshrc` permanently) → no proposal, no analysis; the rule stays loaded.
4. Single-domain trivial task → no decomposition exists.
5. Already in `/parallel-dispatch` context → don't recurse.
6. Read-only / investigation tasks with no writes → dispatch in parallel directly, no claims needed.

## Failure modes to watch for

Watch for over-decomposition (sweet spot 3–6 units), hidden dependencies (if the disjoint-file-set check finds one: merge or sequence the units), pipelined work forced parallel, and proposal fatigue.

## Write-mode dispatches: worktree & follow-up discipline (IMP-070/072)

For any WRITE-mode dispatch, follow `~/.claude/skills/parallel-dispatch/SKILL.md` §"Worktree & Follow-up Discipline (IMP-070/072)" (isolation per writer; the lock protocol is for WRITE fan-outs only, read-only swarms need no claims). Actual usage is currently unmeasured (IMP-114) — do not cite a usage rate until the new claim log has accumulated.

Integration (under `~/.claude/`): skills `parallel-dispatch/` (executor) and `check-parallelizable/` (analyzer); `scripts/parallel-claim.sh` (lock registry); hooks `parallel-lock-check.sh` (enforcement), `subagent-lock-release.sh` (auto-release), `parallel-analyze-prompt.sh` (prompt-time reminder); `agents/control-agent.md` uses the same protocol.
