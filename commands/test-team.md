---
description: "Stage 4 alias — Test & Review: milestone/RC validation, PR review, and safety-net strategy. Thin wrapper around /team-lead with the Stage forced."
argument-hint: <the directive to this team> [--overnight]
model: claude-fable-5-1[1m]
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
  - Bash(bash:*)
  - Bash(gh:*)
  - Bash(npm:*)
  - AskUserQuestion
---

<!-- controller-contract:v1 -->
> **Controller-First.** This is a substantial R.Code entry point: decompose the work via the controller before mutating anything (see `~/.claude/agents/control-agent.md` §1-2).
> **Model×Effort per spawn** is assigned via `~/.claude/agents/control-agent.md` §2 — the single canonical dispatch spec; do not re-derive it here.
> **Second-order checkpoints** run after every delegation wave per `~/.claude/agents/control-agent.md` §4.

# Test Team — Stage 4 (Test & Review)

Stage 4 — Test & Review: execute the `~/.claude/commands/team-lead.md`
procedure with the Stage forced to Test; the playbook is
`~/.claude/rcode/stages/test.md`.

Directive: $ARGUMENTS

`--overnight` → `~/.claude/commands/autonomous-overnight.md`.
