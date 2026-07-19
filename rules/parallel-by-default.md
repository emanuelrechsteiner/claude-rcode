# Parallel-by-Default Rule

> For every task with 2+ independent units, evaluate parallel dispatch BEFORE executing. Auto-dispatch reversible work with disjoint, lock-claimed file-sets (state a one-line note, no gate); reserve the confirmation handshake for parallel work that contains irreversible/ESCALATE-band ops or has ambiguous scope. Sequential is the exception, not the default. Always loaded.
>
> **Model + Effort per unit is NOT decided here.** This rule owns the independence analysis and the dispatch/confirmation mechanics; the Agent/Model/Effort assignment for each unit is the canonical dispatch spec in `agents/control-agent.md` §2 (IMP-091) — reference it, don't restate the matrix.

## The Norm

When the user gives any task that could be decomposed into 2+ independent units, your default behavior is:

1. **Decompose** the task into atomic units
2. **Analyze independence** — do units share files? Does B need A's output?
3. **If 2+ truly independent units exist AND the work is reversible with disjoint, lock-claimed file-sets** → **auto-dispatch** in parallel. State a one-line note ("Dispatching N parallel agents on disjoint file-sets X/Y/Z; locks pre-claimed") — do NOT gate on a confirmation prompt.
4. **Reserve the confirmation handshake** (the full proposal + y/n) for parallel work that either:
   - contains an **irreversible / ESCALATE-band operation** (anything in `agency-bands.md`'s ESCALATE band — force-push, prod migration, `gh pr merge`, deploys, external sends, destructive deletes), or
   - has **ambiguous scope** (file-sets you cannot prove disjoint, or unclear which files each unit touches).
5. **Only execute sequentially** when parallelism is shown to be wasteful or unsafe.

This rule exists because: serial execution of independent work is a token-cost and wall-time multiplier. The user's signals.jsonl data shows 27% of work happens across 2+ files in single sessions — much of it parallelizable but currently serialized. Gating *reversible, disjoint* parallel work behind a confirmation prompt added friction without safety value; the gate now applies only where it earns its cost.

## Decision Matrix — when YES, when NO

| Pattern | Parallel? | Reason |
|---------|-----------|--------|
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

Use this structure only when the confirmation handshake is required (step 4 above): the parallel work contains an irreversible/ESCALATE-band op, or you cannot prove the file-sets disjoint. For reversible, disjoint work, skip this and auto-dispatch with a one-line note. When a proposal IS required, present the plan BEFORE executing:

```markdown
🔀 **Parallelization detected**

Task: <one-sentence summary>
Decomposition: N independent units identified

| # | Agent ID            | Subagent       | Model  | Effort | Goal                      | Files (exclusive) |
|---|---------------------|----------------|--------|--------|---------------------------|-------------------|
| 0 | pdispatch-<sid>-0   | ui-agent       | sonnet | medium | Refactor X                | src/routes/X.tsx  |
| 1 | pdispatch-<sid>-1   | ui-agent       | sonnet | medium | Refactor Y                | src/routes/Y.tsx  |
| 2 | pdispatch-<sid>-2   | testing-agent  | sonnet | low    | Add tests for Z           | tests/Z.test.ts   |

Model + Effort values come from the canonical assignment in `agents/control-agent.md` §2 — this table surfaces the result, it does not re-derive it.

Estimated wall-time:
- Sequential: ~12min
- Parallel:   ~4min (3x speedup)

Token cost: ~$0.X (parallel does not change token cost vs sequential — same total work)

Safety: All file sets are disjoint ✅. Lock claims will be pre-acquired.
SubagentStop hooks will auto-release. parallel-lock-check.sh will block any
cross-agent collision.

**Proceed with parallel dispatch? (y/n/modify)**
```

After user confirms → use the `/parallel-dispatch` skill which handles the claim → dispatch → synthesis protocol.

## When to skip the proposal (just execute)

The rule has exceptions to prevent unnecessary friction:

1. **Reversible work with disjoint, lock-claimed file-sets** → auto-dispatch with a one-line note, no proposal (this is now the default for the common case, not an exception)
2. **User already specified parallelism** ("do these 3 in parallel") → just do it
3. **User opted out for this session** (`CLAUDE_PARALLEL_AUTO_SUGGEST=0`) → no proposal, no analysis
4. **Single-domain trivial task** → no decomposition exists, skip
5. **Already in `/parallel-dispatch` context** → don't recurse
6. **Read-only / investigation tasks with no writes** → just dispatch parallel directly, no claims needed

The proposal+confirmation handshake is required only for the two cases in step 4 of **The Norm**: ESCALATE-band ops in the parallel set, or scope you cannot prove disjoint.

## Failure modes to watch for

| Mode | Symptom | Mitigation |
|------|---------|------------|
| Over-decomposition | 8 agents for trivial work | Sweet spot is 3-6 units; if more, you're probably over-fragmenting |
| Hidden dependency | A renames X, B references X | Spot during the disjoint-fileset check; if found, merge or sequence |
| Unrealistic parallelism | Pipelined work shoved into parallel | If A's output is B's input, they're sequential — don't pretend otherwise |
| Proposal fatigue | User says "just do it" repeatedly | After 3 same-task-type proposals accepted, propose adding to your own pattern memory |

## Integration with existing systems

- `~/.claude/skills/parallel-dispatch/` — the executor (already built)
- `~/.claude/skills/check-parallelizable/` — the analyzer (helper)
- `~/.claude/scripts/parallel-claim.sh` — the lock registry
- `~/.claude/hooks/parallel-lock-check.sh` — enforcement
- `~/.claude/hooks/subagent-lock-release.sh` — auto-release
- `~/.claude/hooks/parallel-analyze-prompt.sh` — prompt-time reminder
- `~/.claude/agents/control-agent.md` — uses the same protocol for multi-agent work

## Write-mode dispatches: worktree & follow-up discipline (IMP-070/072)

For any WRITE-mode dispatch — especially chained follow-up writers, which inherit the parent's worktree+branch instead of getting a fresh one — follow **"Worktree & Follow-up Discipline (IMP-070/072)"** in `~/.claude/skills/parallel-dispatch/SKILL.md`: isolation per writer (worktree or pre-claimed lock), work-slicing before the first commit (orchestrator edits shared files like `package.json`/`types.ts` itself up front), smallest-PR-first merge order, short-lived branches, per-worktree `node_modules`/dev-PORT, protected main. Measured reality (metareview 2026-07-03): exactly **1** real multi-lock dispatch in 6 weeks — the lock protocol is for WRITE fan-outs only; read-only swarms (common and healthy) need no claims at all.

## Opt-out

If parallel suggestion becomes intrusive, the user can disable for current session:

```bash
export CLAUDE_PARALLEL_AUTO_SUGGEST=0
```

Or permanently in `~/.zshrc`. The rule remains loaded but proposals are suppressed.

## Self-check before executing any non-trivial task

Ask yourself:
1. Can this be decomposed into 2+ atomic units? → if NO, execute serial
2. Are the units truly independent (disjoint files, no output→input chain)? → if NO, execute serial
3. Is each unit meaningful (>2min serial)? → if NO, execute serial
4. If YES to all three, check the dispatch path:
   - **Reversible work, file-sets provably disjoint, locks claimable** → auto-dispatch in parallel with a one-line note. No confirmation prompt.
   - **Contains an ESCALATE-band/irreversible op, OR scope is ambiguous (can't prove disjoint)** → present the proposal in the exact format above and wait for confirmation.
5. Either way, each unit still needs its Model + Effort assigned before dispatch — pull that from `agents/control-agent.md` §2 (do not skip the assignment just because the dispatch path itself is auto-approved).
