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

| Pattern | Parallel? | Reason |
|---|---|---|
| Refactor 3+ similar files (routes, components, services) | ✅ YES | Same mechanical operation, disjoint files |
| Build feature requiring backend + frontend + tests | ✅ YES | Different specialists, different file trees |
| Investigate 3+ separate repos/docs | ✅ YES | No shared state, read-only |
| Add tests to 4 different modules | ✅ YES | Each test file independent |
| Migrate N components from lib X to lib Y | ✅ YES | Same operation per file |
| Audit M sub-systems (settings, agents, skills, hooks) | ✅ YES | Disjoint scopes |
| Single-file edit | ❌ NO | No decomposition possible |
| Pipelined work (plan → implement → test) | ❌ NO | Sequential dependency |
| Tiny tasks (<2min each) | ❌ NO | Overhead exceeds gain |
| Cross-file rename where A's change affects B's imports | ❌ NO | Coupled state |
| Read-then-decide flow (each step depends on previous) | ❌ NO | Pipeline shape |

## The Proposal Format (for ESCALATE-band or ambiguous-scope work)

Only when step 4 requires the handshake: present the plan in this exact format BEFORE executing and wait for confirmation.

```markdown
🔀 **Parallelization detected**

Task: <one-sentence summary>
Decomposition: N independent units identified

| # | Agent ID | Subagent | Model | Effort | Goal | Files (exclusive) |
|---|---|---|---|---|---|---|
| 0 | pdispatch-<sid>-0 | ui-agent | sonnet | medium | Refactor X | src/routes/X.tsx |

Estimated wall-time:
- Sequential: ~12min
- Parallel:   ~4min (3x speedup)

Token cost: ~$0.X (parallel does not change token cost vs sequential — same total work)

Safety: All file sets are disjoint ✅. Lock claims will be pre-acquired.
SubagentStop hooks will auto-release. parallel-lock-check.sh will block any
cross-agent collision.

**Proceed with parallel dispatch? (y/n/modify)**
```

After the user confirms → the `/parallel-dispatch` skill handles the claim → dispatch → synthesis protocol.

## When to skip the proposal (just execute)

1. Reversible work with disjoint, lock-claimed file-sets → auto-dispatch with a one-line note (the common-case default).
2. User already specified parallelism ("do these 3 in parallel") → just do it.
3. User opted out (`export CLAUDE_PARALLEL_AUTO_SUGGEST=0` for the session, or in `~/.zshrc` permanently) → no proposal, no analysis; the rule stays loaded.
4. Single-domain trivial task → no decomposition exists.
5. Already in `/parallel-dispatch` context → don't recurse.
6. Read-only / investigation tasks with no writes → dispatch in parallel directly, no claims needed.

## Failure modes to watch for

| Mode | Symptom | Mitigation |
|---|---|---|
| Over-decomposition | 8 agents for trivial work | Sweet spot is 3-6 units; if more, you're probably over-fragmenting |
| Hidden dependency | A renames X, B references X | Spot during the disjoint-fileset check; if found, merge or sequence |
| Unrealistic parallelism | Pipelined work shoved into parallel | If A's output is B's input, they're sequential |
| Proposal fatigue | User says "just do it" repeatedly | After 3 same-task-type proposals accepted, propose adding to your own pattern memory |

## Write-mode dispatches: worktree & follow-up discipline (IMP-070/072)

For any WRITE-mode dispatch — especially chained follow-up writers, which inherit the parent's worktree+branch instead of getting a fresh one — follow `~/.claude/skills/parallel-dispatch/SKILL.md` §"Worktree & Follow-up Discipline (IMP-070/072)" (isolation per writer, work-slicing before the first commit, smallest-PR-first merge order, short-lived branches, per-worktree `node_modules`/dev-PORT, protected main). The lock protocol is for WRITE fan-outs only; read-only swarms need no claims. **Actual usage is currently unmeasured** (IMP-114) — do not cite a usage rate until the new claim log has accumulated. Regression suite: `hooks/tests/parallel-lock-regression.sh`.

Integration (under `~/.claude/`): skills `parallel-dispatch/` (executor) and `check-parallelizable/` (analyzer); `scripts/parallel-claim.sh` (lock registry); hooks `parallel-lock-check.sh` (enforcement), `subagent-lock-release.sh` (auto-release), `parallel-analyze-prompt.sh` (prompt-time reminder); `agents/control-agent.md` uses the same protocol.
