---
name: check-parallelizable
description: "Analyze whether a task can be parallelized into independent sub-agents. Returns a structured proposal with file claim-sets, agent assignments, and confirmation prompt — or a clear explanation why sequential is better. Auto-triggers BEFORE any non-trivial task that involves multiple files or units. Triggers on 'check parallel', 'analyze parallel', 'kann ich das parallel', 'can this be parallel', 'parallelization analysis', 'geht das parallel', 'parallel prüfen', 'parallelisierbar', 'lässt sich das aufteilen', 'kann man das gleichzeitig machen'."
user-invocable: true
---

# Check Parallelizable

Structured analysis to determine whether a task warrants parallel multi-agent dispatch. Use this BEFORE starting work on any task that touches 2+ files or has 2+ identifiable sub-goals.

## When to invoke

- The user gave a task with 2+ files / 2+ sub-goals
- You are about to dispatch sub-agents and want to check if parallel is safe
- The user explicitly asks "can this be parallelized?"

**Auto-triggered:** The `parallel-by-default` rule (always loaded) requires you to do this analysis BEFORE executing any non-trivial task. This skill provides the structured framework.

## The 5-step analysis

### Step 1 — Decompose

Break the task into atomic units. Each unit must:
- Have ONE clear goal (1 sentence)
- Touch a defined set of files
- Be completable by a single sub-agent

Output a numbered list. No vague units like "fix everything" — every unit must be specific.

### Step 2 — Independence Check

For each pair of units (i, j), check:

```
1. Do they share any files?            → if YES: NOT independent
2. Does j use code/values from i's output?  → if YES: pipelined, NOT parallel
3. Will i's changes affect j's imports?     → if YES: coupled, NOT parallel
```

If ANY pair fails → can't parallelize all. Either:
- Merge the dependent pair into one larger unit
- Or sequence them (i first, then j)

### Step 3 — Meaningful-Size Check

Each unit should take >2min of serial work. If <2min:
- The parallel overhead (claim/dispatch/synthesize) exceeds the gain
- Just do it sequentially

### Step 4 — Estimate Speedup

```
Sequential time = Σ unit_times
Parallel time   = max(unit_times) + ~30s coordination overhead
Speedup factor  = Sequential / Parallel
```

If speedup < 1.5x → not worth it.
If speedup 1.5-2x → maybe worth it.
If speedup > 2x → definitely worth it.

### Step 5 — Build the Proposal (or explain why sequential)

If parallelizable: present this template to the user:

```markdown
🔀 **Parallelization Plan**

Task: <one-sentence summary>

| # | Agent ID         | Subagent       | Goal | Files (exclusive) | Est. time |
|---|------------------|----------------|------|-------------------|-----------|
| 0 | pdispatch-<sid>-0 | <type>         | ...  | ...               | ~Xmin     |
| 1 | pdispatch-<sid>-1 | <type>         | ...  | ...               | ~Xmin     |
| 2 | pdispatch-<sid>-2 | <type>         | ...  | ...               | ~Xmin     |

**Independence:** ✅ All file sets disjoint, no output dependencies
**Estimated speedup:** Sequential ~Xmin → Parallel ~Ymin (Zx faster)
**Token cost:** ~$0.X (parallel ≈ sequential — same total work)
**Safety:** Lock system (parallel-claim + parallel-lock-check) guarantees
no two agents write to same file. SubagentStop auto-releases locks.

**Proceed?** (y / n / modify the plan)
```

If NOT parallelizable: explain why in 2-3 sentences. Don't waste tokens on a 6-row proposal table for a task that's actually 1 unit.

## Sub-agent Type Selection

When assigning agents in the proposal, pick the most specific:

| Task type | Subagent |
|-----------|----------|
| React components / UI | `ui-agent` |
| Backend APIs, DB, server logic | `backend-agent` |
| Tests (unit, integration, E2E) | `testing-agent` |
| Documentation | `documentation-agent` |
| Cleanup / dead-code | `cleanup-agent` |
| UX flows / wireframes | `ux-agent` |
| Read-only investigation | `Explore` |
| Architecture planning | `planning-agent` |
| Mixed / orchestration | `control-agent` |
| Code review (read-only) | `code-reviewer-agent` |
| Generic | `general-purpose` (last resort) |

## After User Approval

Hand off to `/parallel-dispatch` skill which:
1. Pre-claims locks via `parallel-claim.sh`
2. Dispatches all agents in ONE message with parallel Agent calls
3. Waits for all to return
4. Synthesizes results
5. Reports back

## Examples

### Example 1 — YES parallel

**Input:** "Refactor Insights.tsx, Admin.tsx, Person.tsx, Baum.tsx to use the new `useUser()` hook"

**Analysis:**
- Decompose: 4 units, one per file
- Independence: ✅ each file is independent, the hook is already implemented
- Size: ~3min per refactor = meaningful
- Speedup: 12min serial → 3min parallel (4x)
- → Build proposal

### Example 2 — NO parallel (pipelined)

**Input:** "Plan the new auth flow, then implement it, then write tests"

**Analysis:**
- Decompose: 3 units
- Independence: ❌ Plan output feeds implementation; implementation defines test surface
- → Sequential: planning-agent → backend-agent → testing-agent
- Explain: "These 3 units are pipelined (B depends on A's output, C depends on B's surface). Running them in parallel would mean implementing without a plan and writing tests against nothing. Better sequential — I'll dispatch planning-agent first."

### Example 3 — NO parallel (single unit)

**Input:** "Add type annotation to function getUser in user.ts"

**Analysis:**
- Decompose: 1 unit
- → Just execute. No proposal needed.

### Example 4 — YES parallel (read-only)

**Input:** "Check the docs for Next.js routing, Supabase auth, and Tailwind theming"

**Analysis:**
- Decompose: 3 read-only research units
- Independence: ✅ no writes at all
- Speedup: 3x (parallel WebFetch calls)
- → Read-only parallel doesn't even need locks. Just dispatch 3 Explore/research agents in one message.

## Common pitfalls

1. **Over-decomposition:** 8 agents for what's really 2 logical units. Aim for 3-6, not 8+.
2. **Hidden coupling:** "These are independent" but actually B imports a type from A. Run a quick grep before claiming independence.
3. **Pipeline-as-parallel:** "Build feature X" can't be 5 parallel agents — it has internal sequencing. Use control-agent for those.
4. **Trivial parallelism:** Don't propose 3 parallel agents for 3 one-line fixes. Just do them.

## See also

- `~/.claude/rules/parallel-by-default.md` — the behavioral norm
- `~/.claude/skills/parallel-dispatch/SKILL.md` — the executor
- `~/.claude/scripts/parallel-claim.sh` — the lock registry
- `~/.claude/agents/control-agent.md` — multi-agent orchestration
