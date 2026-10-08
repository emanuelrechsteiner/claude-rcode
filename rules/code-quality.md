# Code Quality Rules

> Universal code standards. Applies to all languages and frameworks.

## TypeScript Standards

**Strict mode always** — no `any` without written justification. Interfaces for object shapes, types for unions/intersections; destructure imports when possible (`import { foo } from 'bar'`); ES modules (import/export), not CommonJS (require); prefer `const` over `let`, never `var`.

## Python Standards

**Full type hints** (PEP 484) — no `Any` without justification. mypy strict mode when available; dataclasses or Pydantic for structured data; pathlib for file operations (not os.path); Google-style docstrings; async/await for I/O operations.

## Universal Standards

**No commented-out code** (use version control); **no debug statements** in commits (`console.log`, `print()`, `debugger`); **no stray characters at EOF**; **JSDoc/docstrings** for public functions and classes; **error handling**: catch specific exceptions, never swallow errors silently; **follow existing patterns**: match the project's established style before introducing new patterns; **max file length**: consider splitting files over 250 lines (IMP-050; enforced by `stop-batched-checks.sh`, configurable via `CLAUDE_LINE_LIMIT`).

## Naming Conventions

| | TypeScript/JS | Python |
|---|---|---|
| Files | `kebab-case.ts`; components `PascalCase.tsx` | `snake_case.py` |
| Directories | `kebab-case/` (TypeScript) | `snake_case/` |
| Functions/methods | `camelCase` | `snake_case` |

Classes `PascalCase` in all languages; constants `UPPER_SNAKE_CASE`; interfaces/types `PascalCase`, no `I` prefix.

## Import Organization

Order imports consistently: (1) external packages (node_modules / pip), (2) internal aliases (`@/` paths), (3) relative imports (`../`, `./`), (4) type-only imports last.

## Component Structure (React/Next.js)

Server Components by default (Next.js App Router); `'use client'` only when needed (hooks, event handlers, browser APIs); proper `loading.tsx` and `error.tsx` for each route segment; max ~150 lines per component file.
