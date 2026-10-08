# 0006 — Obsidian is a read window, never a writer of what the framework reads

- Status: accepted
- Date: 2026-10-08

## Context

The owner asked for Obsidian to be integrated with R.Code, at the global level
and at the project level, as a way to read and navigate the distilled knowledge
(rules, ADRs, glossary, logbook, per-project memory) with working links. Three
properties of Obsidian make "just open the folder" unsafe wherever the
framework or Claude Code reads the files:

- It writes. A rename or move rewrites links in other notes, a click on an
  unresolved link creates a note, and an edit in the Properties UI rewrites the
  whole frontmatter block (comments lost, list style changed).
- What the framework reads is load-bearing. Every command, agent and skill
  definition starts with YAML frontmatter, and every `rules/*.md` is auto-loaded
  after deploy, so a created or rewritten file changes behaviour.
- The existing guard does not cover it. `hooks/governing-path-guard.sh` is a
  PreToolUse hook on Claude's own tools and cannot see Obsidian's writes into
  the live install.

Opening `~/.claude` would also expose every `rules/*.local.md`, including the
private-layer overlay. The official Obsidian advice is against symlinks.

## Decision

Obsidian is a read window: it never writes into a file that the framework or
Claude Code reads. Framework design is read by opening the workshop as an
Obsidian vault, where every write to a tracked file is visible in `git status`
and a dirty workshop blocks `claude-deploy`. The runtime distillate (logbook,
per-project memory, meta-proposals, tracked rules, a rendered ledger index) is
read through a machine-local copy, the knowledge mirror, written by
`scripts/knowledge-mirror.sh` into a knowledge folder outside `~/.claude`, the
workshop and any synced folder. `~/.claude` is never opened as an Obsidian
vault. Folder symlinks into `~/.claude` are deferred, not rejected.

## Consequences

- Stage 1 needs no new code and is fully testable on the workshop before any
  deploy. Nothing Obsidian does in the knowledge folder can reach a file the
  framework reads.
- The copy goes stale between runs. The trigger is manual for now, and an
  automatic one is considered only after the copy is seen going stale in
  practice. Symlinks are reopened only if that staleness hurts.
- A script and a regression suite must be maintained, and a mirror copy edited
  by hand is refused, not merged. The owner's own notes live in the knowledge
  folder, not in the workshop.
- Clicking an unresolved link in the workshop can still create a file. The
  mitigations are the Stage 1 settings and git, not prevention.
- This ADR records the decision only. Whether each stage works is tracked in
  `docs/OBSIDIAN.md` and stays unverified until the owner's checklists pass.
- Ledger: IMP-248.
