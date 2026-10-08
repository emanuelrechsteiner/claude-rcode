<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/parallel-by-default.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/parallel-by-default.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## The Norm

This rule exists because: serial execution of independent work is a token-cost and wall-time multiplier. The user's signals.jsonl data shows 27% of work happens across 2+ files in single sessions — much of it parallelizable but currently serialized. Gating *reversible, disjoint* parallel work behind a confirmation prompt added friction without safety value; the gate now applies only where it earns its cost.

## Write-mode dispatches: worktree & follow-up discipline (IMP-070/072)

> **Retracted metric (IMP-114, 2026-08-01).** This passage used to cite "exactly **1** real multi-lock dispatch in 6 weeks" (metareview 2026-07-03). That figure came from `parallel-coordination.jsonl`, which logged only *releases* — and the release path compared two identifier spaces that never intersect (orchestrator claim id vs. runtime harness id), so it reported "released 0 locks" on **3,212 of 3,212** records and was structurally incapable of counting anything. The same broken comparison also drove `parallel-lock-check.sh`, which therefore denied a claimed file to the very subagent it had been claimed for — verified directly on 2026-08-01. Write fan-outs were not merely rare, they were **unusable**. Both defects are fixed and claims are now logged. **Actual usage is currently unmeasured**; the only reliable data point is 18 claims in one session (2026-07-26). Do not cite a usage rate until the new claim log has accumulated. Regression suite: `hooks/tests/parallel-lock-regression.sh`.

## Moved from the rule on 2026-09-29 (IMP-234)

> Condensing round IMP-234 (instruction files under 150k chars). The passages below were shortened or removed in `rules/parallel-by-default.md`; each is carried over verbatim from the rule as it stood before that round, under the heading it had there. The normative content stays in the rule; what lives only here is repeated wording (the self-check restated The Norm), a duplicate of the write-mode discipline now pointed to in the `parallel-dispatch` skill, and a second example row of the proposal template.

### Parallel-by-Default Rule (intro under the title)

> For every task with 2+ independent units, evaluate parallel dispatch BEFORE executing — see "The Norm" below for the auto-dispatch vs. confirmation-handshake split. Always loaded.
>
> **Model + Effort per unit is NOT decided here.** This rule owns the independence analysis and the dispatch/confirmation mechanics; the Agent/Model/Effort assignment for each unit is the canonical dispatch spec in `agents/control-agent.md` §2 (IMP-091) — reference it, don't restate the matrix.

### The Norm

When the user gives any task that could be decomposed into 2+ independent units, your default behavior is:

Why: serial execution of independent work is a token-cost and wall-time multiplier, and gating *reversible, disjoint* parallel work behind a confirmation prompt added friction without safety value — the gate now applies only where it earns its cost (evidence: `docs/archive/rules-evidence/parallel-by-default.md`).

### The Proposal Format (for ESCALATE-band or ambiguous-scope work)

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
```

After user confirms → use the `/parallel-dispatch` skill which handles the claim → dispatch → synthesis protocol.

### When to skip the proposal (just execute)

The rule has exceptions to prevent unnecessary friction:

1. **Reversible work with disjoint, lock-claimed file-sets** → auto-dispatch with a one-line note, no proposal (this is now the default for the common case, not an exception)
2. **User already specified parallelism** ("do these 3 in parallel") → just do it
3. **User opted out for this session** (`CLAUDE_PARALLEL_AUTO_SUGGEST=0`) → no proposal, no analysis
4. **Single-domain trivial task** → no decomposition exists, skip
5. **Already in `/parallel-dispatch` context** → don't recurse
6. **Read-only / investigation tasks with no writes** → just dispatch parallel directly, no claims needed

The proposal+confirmation handshake is required only for the two cases in step 4 of **The Norm**: ESCALATE-band ops in the parallel set, or scope you cannot prove disjoint.

### Failure modes to watch for

| Mode | Symptom | Mitigation |
|------|---------|------------|
| Over-decomposition | 8 agents for trivial work | Sweet spot is 3-6 units; if more, you're probably over-fragmenting |
| Hidden dependency | A renames X, B references X | Spot during the disjoint-fileset check; if found, merge or sequence |
| Unrealistic parallelism | Pipelined work shoved into parallel | If A's output is B's input, they're sequential — don't pretend otherwise |
| Proposal fatigue | User says "just do it" repeatedly | After 3 same-task-type proposals accepted, propose adding to your own pattern memory |

### Integration with existing systems

- `~/.claude/skills/parallel-dispatch/` — the executor (already built)
- `~/.claude/skills/check-parallelizable/` — the analyzer (helper)
- `~/.claude/scripts/parallel-claim.sh` — the lock registry
- `~/.claude/hooks/parallel-lock-check.sh` — enforcement
- `~/.claude/hooks/subagent-lock-release.sh` — auto-release
- `~/.claude/hooks/parallel-analyze-prompt.sh` — prompt-time reminder
- `~/.claude/agents/control-agent.md` — uses the same protocol for multi-agent work

### Write-mode dispatches: worktree & follow-up discipline (IMP-070/072)

For any WRITE-mode dispatch — especially chained follow-up writers, which inherit the parent's worktree+branch instead of getting a fresh one — follow **"Worktree & Follow-up Discipline (IMP-070/072)"** in `~/.claude/skills/parallel-dispatch/SKILL.md`: isolation per writer (worktree or pre-claimed lock), work-slicing before the first commit (orchestrator edits shared files like `package.json`/`types.ts` itself up front), smallest-PR-first merge order, short-lived branches, per-worktree `node_modules`/dev-PORT, protected main. The lock protocol is for WRITE fan-outs only; read-only swarms (common and healthy) need no claims at all.

**Actual usage is currently unmeasured** (both counting defects behind that are fixed, IMP-114) — do not cite a usage rate until the new claim log has accumulated. Regression suite: `hooks/tests/parallel-lock-regression.sh`. Full incident: `docs/archive/rules-evidence/parallel-by-default.md`.

### Opt-out

If parallel suggestion becomes intrusive, the user can disable for current session:

```bash
export CLAUDE_PARALLEL_AUTO_SUGGEST=0
```

Or permanently in `~/.zshrc`. The rule remains loaded but proposals are suppressed.

### Self-check before executing any non-trivial task

Ask yourself:
1. Can this be decomposed into 2+ atomic units? → if NO, execute serial
2. Are the units truly independent (disjoint files, no output→input chain)? → if NO, execute serial
3. Is each unit meaningful (>2min serial)? → if NO, execute serial
4. If YES to all three, check the dispatch path:
   - **Reversible work, file-sets provably disjoint, locks claimable** → auto-dispatch in parallel with a one-line note. No confirmation prompt.
   - **Contains an ESCALATE-band/irreversible op, OR scope is ambiguous (can't prove disjoint)** → present the proposal in the exact format above and wait for confirmation.
5. Either way, each unit still needs its Model + Effort assigned before dispatch — pull that from `agents/control-agent.md` §2 (do not skip the assignment just because the dispatch path itself is auto-approved).

### Second pass — keyword index after the `parallel-dispatch/SKILL.md` pointer (first-pass wording)

(isolation per writer, work-slicing before the first commit, smallest-PR-first merge order, short-lived branches, per-worktree `node_modules`/dev-PORT, protected main)
