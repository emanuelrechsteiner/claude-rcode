---
description: "Stage 3 alias — Develop: implement work units as vertical slices, including unit-local tests. Thin wrapper around /team-lead with the Stage forced."
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

# Develop Team — Stage 3 (Develop)

Stage 3 — Develop: execute the `~/.claude/commands/team-lead.md` procedure
with the Stage forced to Develop; the playbook is
`~/.claude/rcode/stages/develop.md`.

Directive: $ARGUMENTS

`--overnight` → `~/.claude/commands/autonomous-overnight.md`.
