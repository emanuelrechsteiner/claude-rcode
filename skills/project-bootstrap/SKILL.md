---
name: project-bootstrap
description: Repository exploration and project bootstrap specialist. Explores repos, audits docs, and optionally bootstraps Memory MCP context. Use when starting a new project, exploring a codebase, or setting up project structure. Triggers on "bootstrap", "explore repo", "new project", "codebase exploration", "project setup", "audit docs", "repo erkunden", "projekt aufsetzen", "codebase erkunden", "neues projekt starten", "projektstruktur anlegen", "verschaff dir einen überblick".
model: haiku
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(git rev-parse:*), Bash(git branch:*), Bash(git log:*), Bash(pwd:*), Bash(ls:*)
---

# Project Bootstrap Skill

## Memory-First Protocol (MANDATORY)

Before starting any task:
1. Query Memory MCP for existing project context: `mcp__memory__search_nodes`
2. Check for previously bootstrapped projects: `mcp__memory__open_nodes`

During task execution:
- Create project entities in Memory MCP: `mcp__memory__create_entities`
- Add project observations (structure, tech stack): `mcp__memory__add_observations`
- Link project to related entities: `mcp__memory__create_relations`

**DO NOT create CLAUDE.md files. Initialize Memory MCP entities instead.**

## Purpose

Explore a repository, audit and consolidate docs, and optionally bootstrap Claude assets.

## Operating Principles

- **Read-first**: Explore → Plan → Execute → Summarize
- **Redact secrets**: Do not read `.env*` unless explicitly authorized
- **Ignore heavy directories**: `node_modules`, `dist`, `.git`, `.next`, `.turbo`, `build`, `.venv`, `target`, `coverage`

## Exploration Protocol

### Step 1: Context Gathering
```bash
git rev-parse --show-toplevel  # Root
git branch --show-current      # Branch
git status -s                  # Status
git log --oneline -10          # Recent commits
```

### Step 2: Fast Scan
```json
{
  "detect": "Languages, frameworks, pkg mgrs, build/test tools, containers, CI, ORM, APIs, DBs, env",
  "skim": {
    "root": "README*, CONTRIBUTING*, CHANGELOG*, LICENSE, .editorconfig",
    "deps": "package.json, pnpm-workspace.yaml, pyproject.toml, requirements*.txt, go.mod, Gemfile, Cargo.toml",
    "runtime": "/apps, /packages, /services, /src, /server, /api, /db/migrations, /prisma",
    "config": "docker-compose*, Dockerfile*, vitest.config.*, jest.*, pytest.ini, playwright.*, eslint.*, prettier.*"
  },
  "docs_audit": "Search README.md, ARCHITECTURE*, API*, DATA*, SETUP*, SECURITY*, /docs/**, /adr/**"
}
```

### Step 3: Documentation Audit
- Assess freshness and correctness of existing docs
- Identify gaps and outdated content
- Plan consolidation if needed

## Output Format

```yaml
Project:
  name: "[Name]"
  type: "[Web app|API|Mobile|etc]"
  stack: "[Key technologies]"
  status: "[Active development|Maintenance|etc]"

Structure:
  root: "[Key directories]"
  entry_points: "[Main files]"
  
Technology:
  languages: "[Primary languages]"
  frameworks: "[Frameworks used]"
  databases: "[Data stores]"
  
Documentation:
  existing: "[List of docs found]"
  gaps: "[Missing documentation]"
  recommendations: "[Suggested improvements]"

Commands:
  install: "[Dependency installation]"
  dev: "[Development server]"
  build: "[Build command]"
  test: "[Test command]"
```

## Capabilities

- Fast repo scan (structure, languages, build/test tooling)
- Existing docs audit for freshness and correctness
- Consolidation plan with archival of stale docs
- Optional bootstrap of Memory MCP context

## Coordination

- Coordinates with Version Control for commits
- Coordinates with Documentation for doc structure
- Reports to Orchestration for multi-step tasks

## Flags

- `--docs-only`: Only audit documentation
- `--bootstrap-only`: Only create bootstrap assets
- `--yes`: Skip approval prompts
