---
name: memory-index
description: Cross-project memory query layer. Aggregates the 35+ project-specific memory directories under ~/.claude/projects/ into on-demand MCP Memory Graph entities. Enables queries like "what did I learn about Next.js middleware?" or "which projects use SwiftData?". Triggers on "memory search", "find project context", "cross-project query", "what have I learned about X", "search projects", "remember Y".
context: fork
model: haiku
allowed-tools: Read, Glob, Grep, Bash(ls *), Bash(find *), Bash(wc *), Bash(head *), Bash(cat *), mcp__memory__search_nodes, mcp__memory__open_nodes, mcp__memory__create_entities, mcp__memory__add_observations, mcp__memory__create_relations, mcp__memory__read_graph
---

# Memory Index Skill — Cross-Project Query Layer

## Purpose

The Claude Code memory system writes per-project memory directories under `~/.claude/projects/-Users-<username>-...` (one per cwd). As of 2026-04, there are 35+ such directories in this setup. Individually they are useful; collectively they are opaque — "what have I learned about X across all projects?" requires grepping individual transcripts.

This skill aggregates project metadata into the MCP Memory Graph (type: `Project`, with Relations to `Pattern`, `Library`, `ErrorClass`) so cross-project queries become first-class.

## When to Use

- User asks "what have I learned about X?" across projects
- Before starting a new project in a known domain (prior-art check)
- When `/meta-observe` reports recurring patterns and needs project-level context
- When onboarding to a codebase that resembles a past project

## Workflow

### Step 1 — Detect whether cache is fresh

MCP Memory entities of type `Project` carry an `indexedAt` observation. If the newest is < 7 days old AND no new project directories have appeared under `~/.claude/projects/` since, skip to Step 4 (query-only mode).

```bash
ls -la ~/.claude/projects/ | head -20
```

Compare against `mcp__memory__search_nodes({ query: "Project indexedAt" })`.

### Step 2 — Enumerate projects

```bash
ls ~/.claude/projects/ 2>/dev/null
```

For each directory name (it encodes the cwd, e.g. `-Users-<username>-Cowork-<your-ios-project>-<your-ios-project>`):
- Decode the project path (replace `-` with `/`, handle leading `-`)
- Sample the most recent session transcript (last file, last ~200 lines)
- Extract: project name, apparent tech stack (package.json / Package.swift / requirements.txt signals), recent topics

### Step 3 — Create or update Memory entities

For each project:
```
mcp__memory__create_entities({
  entities: [{
    name: "project:<basename>",
    entityType: "Project",
    observations: [
      "path: <decoded cwd>",
      "indexedAt: <ISO date>",
      "techStack: <e.g. Next.js, TypeScript, Tailwind>",
      "recentThemes: <e.g. scroll animation, Mailchimp integration>",
      "status: <active|dormant based on recent activity>"
    ]
  }]
})
```

Create Relations to existing Pattern/Library/ErrorClass entities where found:
- "Project uses Library" for detected frameworks
- "Project encounters ErrorClass" for recurring error categories
- "Project applies Pattern" for frameworks defined in rules/

### Step 4 — Answer the user's query

For queries like "what have I learned about Next.js middleware":
```
mcp__memory__search_nodes({ query: "Next.js middleware" })
```
Follow Relations to surface: affected projects, relevant rules (foundation, workflow-git, etc.), past improvements (IMP entries that mention middleware).

### Step 5 — Return summary

Concise response:
- **Projects with evidence:** bullet list (basename + 1-line relevance)
- **Relevant rules/skills:** paths
- **Ledger entries:** IMP-XXX with title
- **Suggested next step:** if the question is "should I do X?" — pattern-based recommendation

## Anti-Patterns

### ❌ Index on every session start
35+ directories × file reads = slow. The skill runs on demand, not automatically.

### ❌ Store raw transcripts in Memory Graph
Transcripts are huge. Only aggregated observations (stack, themes, status) go into entities.

### ❌ Delete old Project entities aggressively
Dormant projects still hold patterns worth querying. Mark `status: dormant` rather than delete.

### ❌ Ingest during ongoing project work
Ingestion reads many files. If the user is mid-task, ask before running a full re-index.

## Integration

- **Depends on:** MCP Memory server (`mcp__memory__*` tools)
- **Complements:** `meta-observer` skill (which focuses on signals.jsonl, not project transcripts)
- **Addresses:** IMP-013 (Cross-Project Memory Query Layer) in improvement-ledger.json

## Success Criteria

A query like "what did I learn about scroll animation" returns within 5 seconds:
- A `project:<landing-page-project>` entity reference
- Paths to relevant rules (`scroll-animation-patterns` skill, `api-cost-optimization.md`, etc.)
- IMP-012 reference if relevant
- 2–3 sentence synthesis with citations to sources

## Dormant-Project Detection

A project is marked dormant when:
- No session directory activity for 30+ days
- No git commits in the project cwd for 30+ days

Dormant projects stay queryable but are marked so recommendations can weight active projects higher.
