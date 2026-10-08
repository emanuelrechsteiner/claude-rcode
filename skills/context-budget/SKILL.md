---
name: context-budget
description: Audit what loads into the context window (rules, CLAUDE.md, skill and agent descriptions, MCP tool schemas) and rank token-saving cuts. Use when the window fills too fast or before adding components. Triggers on "context budget", "context bloat", "token overhead", "instruction budget".
---

<!--
Adapted from affaan-m/ECC skills/context-budget @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# Context Budget

Estimate the fixed overhead every session pays before the first prompt, and report where it can be cut. This is a read-only audit: it never edits a component, it recommends.

## When to Use

- Output quality degrades or the window fills faster than the work justifies.
- Many skills, agents, rules, or MCP servers were added recently.
- Before adding a component: is there room?
- After adding one: did the overhead creep?

## What counts, and how

Two budgets exist and they are measured in different units. Do not mix them.

| Component | Loads when | Unit that matters | How to measure |
|---|---|---|---|
| `CLAUDE.md` chain (global + project) | every session | characters, against the framework's 150k instruction budget | `wc -m` per file |
| `rules/*.md` and `rules/*.local.md` | every session (no `paths:` frontmatter) | characters, same 150k budget | `wc -m` per file |
| Skill descriptions | every session, in the skill listing | characters of `description:`; the listing has its own budget | `Grep` for `^description:`, count the line lengths |
| Skill bodies | only when the skill is invoked | tokens, once per invocation | `wc -l`, `wc -m` |
| Skills with `disable-model-invocation: true` | never listed; body on `/name` only | zero listing cost | `Grep` for the flag |
| Agent descriptions | every session, in the Agent tool listing | characters | `Grep` for `^description:` in `agents/*.md` |
| MCP servers | every session, tool schemas | tokens; estimate about 500 per tool (rough, varies widely) | count tools per server in the active config |
| Hook output injected at SessionStart | every session | characters | run the hook, `wc -m` |

Token estimates: prose about `chars / 4`; code-heavy files a bit worse. State every figure as an estimate unless it came from `/context`.

The authoritative live number is `/context` (fill as a percentage of the active window). Everything this skill computes is a static estimate; if the two disagree, `/context` wins and the gap itself is a finding.

## Workflow

### 1. Inventory

Measure each row of the table above. Use `Glob` for file lists and `Grep`/`wc` for sizes. Read-only. In a long inventory, delegate the counting to an `Explore` agent (per-spawn Agent/Model/Effort per `agents/control-agent.md` §2) so the main thread receives the table, not the raw listings.

Flag:
- rule files that could be path-scoped or demoted to an on-demand skill
- `CLAUDE.md` sections that restate a rule
- skill or agent descriptions over about 300 characters, or stuffed with trigger lists in two languages
- skills that are manual-only procedures but still listed (candidates for `disable-model-invocation: true`)
- agents over about 200 lines (their body is paid on every spawn)
- MCP servers over about 20 tools, or servers that only wrap a CLI that is already available (`gh`, `git`, `npm`)

### 2. Classify

| Bucket | Criteria | Action |
|---|---|---|
| Always needed | referenced by `CLAUDE.md`, backs a gate or hook, matches the project type | keep |
| Sometimes needed | domain-specific, used in some projects | scope it: `paths:` for rules, on-demand skill instead of rule |
| Rarely needed | no reference, overlapping content, no match with the project | remove or demote |

### 3. Detect issues

- Redundant: a skill that duplicates an agent, a rule that duplicates `CLAUDE.md`, two rules saying the same thing.
- Stale: references to removed agents, commands, or model IDs.
- Evidence inside a rule: incident detail belongs in an archive file, the rule keeps only the normative text.
- Over-subscription: more MCP servers than the work uses.

### 4. Report

```
Context Budget Report
Model / window: <active model>, <window size>   (source: /context or stated assumption)

| Component              | Count | Chars  | Est. tokens | Counts toward           |
|------------------------|-------|--------|-------------|-------------------------|
| CLAUDE.md chain        |       |        |             | 150k instruction budget |
| rules                  |       |        |             | 150k instruction budget |
| skill descriptions     |       |        |             | skill listing budget    |
| agent descriptions     |       |        |             | agent listing           |
| MCP tool schemas       |       |        |             | tokens only             |

Instruction budget: <used> of 150,000 chars (<pct>%)
Findings (ranked by estimated saving): ...
Top 3 cuts: 1. <action> saves about <n> chars / tokens
```

For a verbose run, add per-file sizes of the ten heaviest files and the specific duplicated lines between overlapping components.

## Rules of thumb

- MCP tool schemas are usually the largest single lever; a server with 30 tools can outweigh all skill descriptions combined.
- Rules are the most expensive line of text in the system: every character is paid in every session. A new always-loaded rule must displace something.
- Skill and agent descriptions are cheap individually and expensive in bulk; the fix is shorter descriptions and `disable-model-invocation`, not deleting useful skills.
- Report the cause in the numbers, not "it feels heavy". If a figure is a guess, say so.

## Output discipline

- Lead with the one-line verdict: used vs. budget, and the single biggest lever.
- Never claim a saving without naming the file or server it comes from.
- Do not apply any cut. Present the list; the owner decides (rules and `CLAUDE.md` are governed files).
