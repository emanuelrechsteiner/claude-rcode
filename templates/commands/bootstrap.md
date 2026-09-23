---
description: Explore the repo, audit+consolidate docs, and (optionally) bootstrap Claude assets (CLAUDE.md, subagents, hooks). Read-only by default; asks before writing.
argument-hint: [--docs-only | --bootstrap-only | --agents | --hooks | --yes] [notes]
model: claude-sonnet-4-20250514
allowed-tools: Read, Glob, Grep, LS, Bash(git status:*), Bash(git rev-parse:*), Bash(git branch:*), Bash(git log:*), Bash(pwd:*), Bash(echo:*)
---

# Claude Code — Repo Explorer & Docs Consolidator (+ Optional Project Bootstrap)

Import @~/.claude/agents/project-bootstrap-agent.md

Parse flags from $ARGUMENTS:
- --docs-only → Do not create Claude assets.
- --bootstrap-only → Skip docs; only set up CLAUDE.md, subagents, hooks as requested.
- --agents → Include `.claude/agents/*`.
- --hooks → Include `.claude/settings.json` with safe, non-destructive hooks.
- --yes → If present, you may proceed with Write/Edit after showing the plan. Otherwise, ask for approval.

## Context (auto-collected)
- Repo root: !`git rev-parse --show-toplevel`
- Branch: !`git branch --show-current`
- Status: !`git status -s`
- Recent commits: !`git log --oneline -10`

## OPERATING PRINCIPLES
- Pipeline: EXPLORE → PLAN → EXECUTE → SUMMARIZE.
- Read-first. Prefer Read, Glob, Grep, LS. Ask before Edit/Write/Bash.
- Redact secrets; never read `.env*` unless explicitly allowed.
- Ignore heavy/vendor dirs: node_modules, .next, .turbo, dist, build, .venv, target, coverage, .git.

## EXPLORE (fast scan)
Detect repo layout, languages, frameworks, package managers, build/test tools, containers/compose, CI, ORM/migrations, APIs, DBs, env usage.

Skim (read-only):
- Root: README*, CONTRIBUTING*, CHANGELOG*, LICENSE, .editorconfig
- Build/deps: package.json, pnpm-workspace.yaml, yarn.lock, pyproject.toml, requirements*.txt, go.mod, Gemfile, Cargo.toml
- Runtime: /apps, /packages, /services, /frontend, /backend, /src, /server, /api, /db/migrations, /prisma/schema.prisma
- Config/test: docker-compose*.yml, Dockerfile*, Procfile, vitest.config.*, jest.*, pytest.ini, playwright.*, cypress.config.*
- Lint/format: eslint.*, prettier.*, ruff.*, mypy.*

## EXISTING DOCS AUDIT
Search for docs in root and /docs:
- README.md, ARCHITECTURE*.md, API*.md, DATA*.md, SETUP*.md, SECURITY*.md, CONTRIBUTING.md, CHANGELOG.md, /docs/**, /adr/** or /docs/decisions/**
Assess FRESHNESS (timestamp + code alignment) and CORRECTNESS (spot-check configs/scripts/schema).

## PLAN (print before acting)
Output a concise plan:
- Which standard docs to create/update.
- For each existing doc: CONSOLIDATE (merge) or ARCHIVE (outdated/incorrect).
- Files proposed for deletion after consolidation.
- Whether to also create Claude assets (based on flags).
Then pause for approval (unless --yes).

## EXECUTE (only after approval)
0) Consolidate/Migrate docs
- If UP-TO-DATE: fold content into targets; preserve useful tables/snippets; mark source for deletion.
- If OUTDATED/PARTLY WRONG: move to docs/history/<YYYY-MM-DD>/<original-path>; prepend a header explaining why and the new canonical location.
- Fix internal links; then delete superseded originals (never delete LICENSE/legal).

1) Create/Update standard docs
Write/refresh:
- docs/overview.md — Purpose, user journeys, high-level stack; Mermaid system diagram; key scripts/ports.
- docs/architecture.md — Modules/services + responsibilities; dependency hotspots; extension points.
- docs/api.md — Endpoints (path/method/auth/params); integrations; rate-limit notes.
- docs/data-model.md — Datastores; entities/relations; Mermaid ER/class diagram; migration/seed notes.
- docs/dev-setup.md — Prereqs; .env.example (values redacted) with code paths; start/test/lint/format/build/storybook.
- docs/testing.md — How to run tests; coverage tips; gaps; next smoke tests.
- docs/security.md — Secrets handling; auth flows; permission boundaries; risks + quick wins.
- docs/code-map.md — Tree (depth 2–3) with one-liners per important dir/file; links to key entrypoints/configs.
- docs/decisions/0001-architecture-baseline.md — ADR with trade-offs + open questions/TODOs.

2) (Conditional) Claude project bootstrap
Only if flags request it (or not --docs-only). Use templates from ~/.claude/templates/bootstrap:
- Write CLAUDE.md
- If --agents or --bootstrap-only: create `.claude/agents/` from templates
- If --hooks or --bootstrap-only: create `.claude/settings.json` with safe, non-destructive hooks and place `.claude/hooks/guard-unsafe.sh` and `auto-format.sh` (chmod +x)

3) Legacy migration
If legacy conventions/rules exist, migrate durable content into the new docs/CLAUDE.md; archive original to docs/history/YYYY-MM-DD/ with a short header; remove conflicts.

## SUMMARIZE (print at end)
- Checklist of created/updated files
- Archived files + new locations
- Deleted files
- Top TODOs & questions
- Exact commands to run the app and tests locally

## PERMISSIONING
- Before any Edit/Write/Bash, show the action list and wait for approval (unless --yes). Default to read-only if not granted.
