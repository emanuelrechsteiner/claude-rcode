---
name: parallel-dispatch
description: "Orchestrate N parallel write-mode sub-agents safely. Validates disjoint file sets, pre-claims locks per agent, dispatches parallel Agent calls in ONE message, synthesizes results. Use when you need true parallelism with write access — e.g. refactor 5 routes simultaneously, add tests to 4 different modules in parallel, migrate N components at once. Triggers on 'parallel dispatch', 'parallel refactor', 'run agents in parallel', 'fan out work', 'parallel ausführen', 'mehrere agents gleichzeitig', 'parallel abarbeiten', 'gleichzeitig refactoren', 'arbeit auffächern', 'agents parallel starten'."
---

# Parallel Dispatch (Multi-Agent Write Coordination)

This skill enables **safe write-mode parallelism** — multiple sub-agents editing different files at the same time without race conditions. Adapted from HCOM's pre-planned disjoint-fileset pattern.

## When to use

- You have N **independent** work units (3+ recommended)
- Each unit touches a **disjoint** set of files (no shared edits)
- The work is parallelizable: A's output doesn't feed into B's input

**NOT for:**
- Pipelined work (A → B → C) — use sequential dispatch instead
- Single-file work — just edit it
- Read-only research — use Agent tool directly without locking
- Cross-file refactor where A's rename affects B's imports — sequential safer

## Coordination Protocol

```
┌────────────────────────────────────────────────────────────┐
│ 1. PLAN — decompose task into N independent units          │
│    Each unit declares its file set                         │
└────────────────────────────────────────────────────────────┘
                          │
┌────────────────────────────────────────────────────────────┐
│ 2. VERIFY — check no two units share files                 │
│    If overlap → refuse + explain                           │
└────────────────────────────────────────────────────────────┘
                          │
┌────────────────────────────────────────────────────────────┐
│ 3. CLAIM — for each unit, claim its files via              │
│    parallel-claim.sh with the agent's ID                   │
└────────────────────────────────────────────────────────────┘
                          │
┌────────────────────────────────────────────────────────────┐
│ 4. DISPATCH — single message with N Agent tool calls       │
│    Each agent's prompt includes its claimed file paths     │
└────────────────────────────────────────────────────────────┘
                          │
┌────────────────────────────────────────────────────────────┐
│ 5. AUTO-RELEASE — SubagentStop hooks release locks         │
│    parallel-lock-check.sh prevents collisions in-flight    │
└────────────────────────────────────────────────────────────┘
                          │
┌────────────────────────────────────────────────────────────┐
│ 6. SYNTHESIZE — collect agent reports, surface conflicts   │
└────────────────────────────────────────────────────────────┘
```

## Step-by-step instructions for Claude

When this skill is invoked:

### Step 1: Plan the decomposition

Analyze the user's request. Decompose into independent units. For EACH unit, declare:
- **Goal:** one-sentence description (what this agent does)
- **Files:** absolute paths the agent will write to
- **Subagent type:** `backend-agent`, `ui-agent`, `testing-agent`, `cleanup-agent`, or `general-purpose` (pick the most specific)
- **Read-only files:** files needed for context but not edited (these don't need claims)

Output the plan as a markdown table to the user BEFORE dispatch, so they can sanity-check the decomposition.

### Step 2: Verify disjoint file sets

```bash
# All "Files" lists across units must be mutually disjoint.
# If overlap exists: DO NOT DISPATCH. Report the conflict and ask user:
#   - Should the overlap go in one unit (merge agents)?
#   - Should it be sequential (the overlap-file's agent runs first)?
#   - Should the overlap be removed from scope?
```

### Step 3: Pre-claim locks

For each unit, generate a unique agent_id (suggested format: `pdispatch-<turn-id>-<unit-index>`). Then run:

```bash
for file in <unit's files>; do
    bash ~/.claude/scripts/parallel-claim.sh claim "$file" "<agent_id>" 3600
done
```

If any claim fails (returns 2), abort the whole dispatch and report which file is held by whom.

### Step 4: Dispatch in single message with parallel Agent calls

Build N Agent tool calls in ONE message (not sequential). Each call:
- `subagent_type`: from the plan
- `description`: short
- `prompt`: starts with the unit's task + lists claimed files + instruction "You may ONLY edit these files. Other files are locked by other agents."
- `run_in_background`: optional — true if you want to continue working while they run

**StructuredOutput subagents:** If a dispatched subagent must return a `StructuredOutput` (i.e. it calls the `StructuredOutput` tool with a specific schema), the orchestrator MUST prepend the EXACT required output shape to that agent's prompt — including every key name and its type — so the agent can produce a conforming response without guessing. Example:

```
Your response MUST end with a StructuredOutput tool call matching this exact schema:
  { "file": string, "applied": boolean, "summary": string, "skipped_or_notes": string }
Do not omit keys or use different names.
```

**StructuredOutput retry cap:** Track consecutive schema-mismatch errors per subagent. After **3 consecutive mismatches**, ABORT that subagent, do NOT retry again. Surface the required schema and the last error to the user and ask them to resolve the schema ambiguity before re-dispatching. Looping past 3 mismatches has been observed to produce 63/70+ schema errors in a single agent without converging.

**File discovery in strict read-only subagents:** `Glob` and `Grep` tools may be UNAVAILABLE in certain subagent contexts (the agent receives a "No such tool available" error). For subagents whose prompts are purely read-only discovery (no writes), instruct the subagent to use `Bash(find ...)` / `Bash(grep -rn ...)` for file search instead. Example prompt addition:
```
NOTE: If Glob or Grep tools are unavailable, use Bash(find "$PROJECT_ROOT" -name "*.ts") or
Bash(grep -rn "pattern" "$PROJECT_ROOT/src") for file discovery. This is sanctioned for
read-only discovery subagents.
```

### Step 5: Auto-release (no action needed)

`subagent-lock-release.sh` fires on each agent's SubagentStop. All claims for that agent_id are released automatically.

### Step 6: Synthesize

When all N agents return:
- Collect their reports
- List files changed per agent
- Flag any agent that reported a lock-conflict (means they tried to edit outside their fileset)
- Provide consolidated summary to user

## Subagent prompt path-contract

Every dispatched subagent prompt MUST establish the working root explicitly so the agent never operates on hallucinated or foreign paths.

**Required preamble in every subagent prompt:**

```
PROJECT_ROOT=<absolute path to project root, e.g. /path/to/project>
# For git-worktree sessions also set:
WORKTREE_ROOT=$(pwd)   # the agent should run this as its first Bash call

# Sanity-check (agent's first action):
ls "$PROJECT_ROOT"

RULES:
- ALL file paths you Read, Edit, Write, or reference MUST start with $PROJECT_ROOT.
- NEVER use foreign or hallucinated absolute paths (e.g. /home/user, /Users/<someone-else>,
  /workspace, /app, or any path not under $PROJECT_ROOT).
- Strip any trailing slash from $PROJECT_ROOT before joining path segments to avoid doubled
  segments (e.g. avoid "$PROJECT_ROOT/frontend/frontend" — use "$PROJECT_ROOT/frontend").
```

Failure to inject this contract is the leading cause of subagents reading/writing the wrong tree in worktree-based or multi-project sessions. The orchestrator is responsible for supplying the correct `PROJECT_ROOT` value; the subagent is responsible for never deviating from it.

## Worktree & Follow-up Discipline (IMP-070/072)

The lock protocol above covers ONE fan-out message. Two failure surfaces live around it: **chained follow-up spawns** (IMP-070) and **the worktree/branch/merge lifecycle itself** (IMP-072).

### Follow-up writers inherit the parent worktree (IMP-070)

When a finished agent spawns a follow-up LOCAL agent, the follow-up does **NOT** get a fresh worktree — it runs in the parent's cwd on the SAME branch. Chained or concurrent follow-up writers therefore interleave edits on one branch and risk lost/conflicting work.

- Every chained/follow-up agent that WRITES must get **either** `isolation: 'worktree'` (own worktree + own branch) **or** a pre-claimed lock via `parallel-claim.sh` — never neither.
- **Warn explicitly** (one line to the user) whenever 2+ follow-up writers would share one worktree. Treat that as a plan defect, not a runtime detail.
- Read-only follow-ups are exempt — inheriting the parent's worktree is harmless without writes.

### Work-slicing happens BEFORE the first commit (IMP-072)

Conflicts come from two branches touching the same lines — not from worktrees. Slicing is the biggest lever, and it happens before anyone commits:

- Give each agent a **bounded region** (A=auth, B=dashboard, C=api), decided up front.
- **Shared files are the battlefield**: `package.json`, a central `types.ts`, barrel `index.ts`, router config. When multiple agents would need to touch them, the ORCHESTRATOR edits those files ITSELF up front and lands that change before any agent starts.

### Merge order & branch lifetime

- **Merge the smallest / least-contested PR FIRST.** The first PR is free; each later one must catch main up. A 40-file PR merged first forces every sibling into a huge sync.
- **Short-lived branches:** small frequent PRs beat three giant end-of-day ones. A finished agent should go PR → review → merge quickly so the others re-sync early instead of accumulating divergence.

### Single-machine caveats — worktrees isolate git+source, NOT the surroundings

| Layer | Caveat |
|-------|--------|
| `node_modules` | Per-worktree install (gitignored, never shared) — a new dep added in A is invisible to B until B re-installs after sync |
| Dev server | Per-worktree PORT — parallel `npm run dev` instances all fight for 3000 |
| Shared-outside-git state | Local DB, `.env`, caches, docker containers are effectively SHARED — "one agent migrates the schema, the other falls over". Serialize or namespace these |

### Protect main

Branch protection on the target repo: **PR required, no direct pushes, green CI as merge gate.** Doubly important with autonomous agents — none may push straight to main. (Merges to trunk remain ESCALATE-band per `workflow-git.md` / `excessive-agency-gate.md`.)

> Caveat: multi-human worktree flow is mature; multiple autonomous agents on one repo is young and fast-moving — check current worktree support in the specific agent tool before relying on it.

## Example: Refactor 4 React routes in parallel

User says: "Refactor these 4 routes to use the new `useUser()` hook: Insights.tsx, Admin.tsx, Person.tsx, Baum.tsx"

```
## Plan

| Agent ID            | Goal                              | Files                          | Subagent type |
|---------------------|-----------------------------------|--------------------------------|---------------|
| pdispatch-r1-0      | Refactor Insights.tsx to useUser  | src/routes/Insights.tsx        | ui-agent      |
| pdispatch-r1-1      | Refactor Admin.tsx to useUser     | src/routes/Admin.tsx           | ui-agent      |
| pdispatch-r1-2      | Refactor Person.tsx to useUser    | src/routes/Person.tsx          | ui-agent      |
| pdispatch-r1-3      | Refactor Baum.tsx to useUser      | src/routes/Baum.tsx            | ui-agent      |

Disjoint? ✅ (each agent owns 1 file, no overlap)
Claims:    4 acquired
Dispatching 4 agents in parallel...
```

Then ONE message with 4 Agent tool calls. After all return, synthesize.

## Bypass

The user can disable parallel locking via env var (for emergency):

```bash
export CLAUDE_PARALLEL_LOCK_OFF=1
```

Don't use this lightly — it removes the safety net.

## Cost considerations

- N parallel Sonnet agents cost N × single-agent cost. Don't over-decompose.
- Wall time benefit: ~Nx speedup vs sequential
- Token cost: same as sequential (each agent has its own context)
- Sweet spot: 3-6 parallel agents on related but independent work

## Failure modes & recovery

| Mode | Detection | Recovery |
|------|-----------|----------|
| Agent crashes mid-edit | SubagentStop with stop_reason ≠ end_turn | Lock TTL (30min) auto-expires, then can be claimed |
| Lock conflict during plan | claim returns exit 2 | Refuse dispatch, report conflict |
| Agent edits outside its fileset | parallel-lock-check.sh denies | Agent receives JSON-deny, must respect or escalate |
| Lock leak | release-all on SubagentStop | Manual: `bash ~/.claude/scripts/parallel-claim.sh cleanup` |

## Why this is better than naive parallel dispatch

Without coordination, two parallel write agents on overlapping files would race: last writer wins, silent data loss. Our system:
1. **Refuses overlap at plan time** (Step 2)
2. **Locks at claim time** (Step 3)
3. **Enforces locks at edit time** (parallel-lock-check.sh hook)
4. **Auto-releases at agent-stop** (subagent-lock-release.sh hook)

End result: parallel speedup with sequential-grade safety.
