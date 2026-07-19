---
description: Treat the given prompt as a management directive — decompose it and dispatch to subagents as team lead (manual Fable5/Ultracode entry point)
argument-hint: <the task or directive to hand to the team>
model: claude-fable-5[1m]
allowed-tools:
  - Task
  - TaskCreate
  - TaskUpdate
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash(git:*)
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `agents/control-agent.md` §4.

# Team Lead — Manual Controller-First Entry Point

This command is the manual counterpart to the (soft-only) `controller-first-*`
hooks: instead of a hook trying to nudge or gate the main thread into
controller behavior, you invoke this command explicitly — the `model:`
frontmatter pins THIS turn to `claude-fable-5[1m]` regardless of the session
model — and it makes the current turn genuinely act as team lead: this prompt
is a management directive, not a task to execute directly.

> NOTE: the pin covers only the command turn. If you reply mid-flow (e.g. to
> a y/n), the next turn falls back to the session model — for multi-turn
> delegation sessions, additionally set the chat model to Fable5.

## User's Directive

$ARGUMENTS

## Instructions

### 1. Read as a management directive
Treat `$ARGUMENTS` as instructions from a manager to a team lead, not as
something to implement inline. Your job this turn is to plan and delegate,
not to write code yourself (skip-list exceptions from `rules/foundation.md`
still apply: single-file edits, <2min tasks, pure Q&A — those you may answer
directly, but you MUST name the exception in one line first, e.g.
"skip-list: single-file edit". If the directive plausibly touches 2+ files
or 2+ domains, the exception does not apply. The user invoked /team-lead
deliberately — when in doubt, delegate.)

Do NOT Task-dispatch the control-agent as a subagent for this — subagents
cannot spawn further subagents, so a spawned control-agent degrades to
planner mode (per `agents/control-agent.md` "Dispatch model") and this turn
would have to dispatch its plan anyway. This turn IS the control-agent, in
its main-thread planner form; CLAUDE.md Behavioral Directive 3 ("invoke
control-agent first") is satisfied by this command itself.

### 2. Decompose
Break the directive into atomic units of work. For each unit, determine:
- Which specialized agent fits (see `agents/control-agent.md` §2 for the
  Agent/Model/Effort assignment table and `rules/tool-discipline.md` Rule 3
  for the agent-selection matrix)
- Whether it's independent of the other units (disjoint files, no
  output→input chain) — see `rules/parallel-by-default.md`

### 3. Dispatch
- 2+ independent, reversible units with disjoint files → dispatch in
  parallel in a single message, per `rules/parallel-by-default.md`.
- Anything containing an ESCALATE-band op, or with unprovable disjointness →
  present the proposal format from `rules/parallel-by-default.md` and wait
  for a real y/n.
- Single-domain / sequential work → dispatch the one right specialist rather
  than doing it yourself.

### 4. Synthesize + Re-Plan
After EVERY delegation wave — not only at the end — run the 2nd-order
checkpoint from `agents/control-agent.md` §4: digest-review outputs against
the §2 definition-of-done, re-evaluate the remaining plan and each spawn's
Model×Effort sizing, and decide explicitly (continue / re-decompose /
escalate) BEFORE dispatching the next wave. Then consolidate all outputs
into one coherent result for the user. Surface any ESCALATE-band operations
subagents flagged up to you (per `rules/agency-bands.md` — you are the
human-facing escalation point for this delegation).

## Why This Command Exists

The `controller-first-prompt-gate.sh` / `-mutation-gate.sh` hook pair
(IMP-089/090) can only *nudge* (inject a context reminder) or *react*
(block a mutation after the fact) — a `PreToolUse`/`UserPromptSubmit` hook
is a synchronous shell script and cannot itself invoke an LLM turn or force
a specific agent to run before the main thread responds. `/team-lead` closes
that gap the only way actually available: an explicit, user-invoked command
that makes *this* turn behave as the team lead, on the frontmatter-pinned
Fable5 substrate (a manual chat switch to Fable5 is only needed to keep
mid-flow follow-up turns on Fable).
