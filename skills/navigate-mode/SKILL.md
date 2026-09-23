---
name: navigate-mode
description: Codebase navigation primitives for fast orientation. Bundles canned scripts to locate entry points, list routes, list state stores, and surface recently-touched hot files. Use instead of ad-hoc grep when answering "where is X" / "how is this wired" questions. Triggers on "where is", "find entry point", "list routes", "list stores", "show me the routes", "hot files", "what's the main file", "navigate", "navigation", "orient me", "wo ist", "einstiegspunkt", "wo liegt".
context: fork
model: haiku
allowed-tools: Bash, Read, Grep, Glob
---

# navigate-mode — Codebase Navigation Primitives

Use this skill when the user asks NAVIGATE / RESEARCH / EXPLAIN questions about an unfamiliar codebase. Instead of improvising greps, dispatch one of the four primitives below via `scripts/navigate.sh`.

Evidence basis: NAVIGATE (16.2%) + RESEARCH (16.1%) + EXPLAIN (3.2%) = ~35% of all user prompts (signals 2023–2026).

## The 4 Primitives

All commands accept an optional path argument (default `.`):

```
bash scripts/navigate.sh find-entry-point [path]
bash scripts/navigate.sh list-routes      [path]
bash scripts/navigate.sh list-stores      [path]
bash scripts/navigate.sh hot-files        [path]
```

### 1. `find-entry-point`
Detects project type from manifest (`package.json`, `pyproject.toml`, `Package.swift`, `Cargo.toml`, `go.mod`) and prints the likely entry file. Use when the user asks "what's the main file?", "where does this start?", "einstiegspunkt".

### 2. `list-routes`
- **Next.js:** lists files under `app/` and `pages/`
- **React Router:** greps for `<Route ` JSX usages
- **Vue Router:** greps for `routes:` arrays
Use when the user asks "list routes", "show me the routes", "what pages does this have".

### 3. `list-stores`
Greps for state-management definitions:
- Zustand `create(`
- Redux Toolkit `createSlice(`
- Pinia `defineStore(`
- React Context `createContext(`
Use when the user asks "where's the state", "list stores", "what context providers exist".

### 4. `hot-files`
`git log --since='30 days ago'` aggregated, sorted by edit-frequency. Top 20 files. Use when the user asks "what's been changing", "hot files", "wo wird viel gearbeitet".

## Output Format
Each primitive prints human-readable text (not JSON). Headers + indented lists. Pipe through `head` if output is long.

## When NOT to use
- Deep semantic questions (use `Read` / `Grep` directly)
- Single-file lookups where path is already known
- Cross-project queries (use `memory-index` skill instead)
