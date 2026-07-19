# Code Quality Rules

> Universal code standards. Applies to all languages and frameworks.

## TypeScript Standards

- **Strict mode always** — No `any` without written justification
- Use interfaces for object shapes, types for unions/intersections
- Destructure imports when possible: `import { foo } from 'bar'`
- Use ES modules (import/export), not CommonJS (require)
- Prefer `const` over `let`, never use `var`

## Python Standards

- **Full type hints** (PEP 484) — No `Any` without justification
- mypy strict mode when available
- Use dataclasses or Pydantic for structured data
- pathlib for file operations (not os.path)
- Google-style docstrings
- async/await for I/O operations

## Universal Standards

- **No commented-out code** — Use version control instead
- **No debug statements** in commits — No `console.log`, `print()`, `debugger`
- **No stray characters at EOF**
- **JSDoc/docstrings** for public functions and classes
- **Error handling** — Catch specific exceptions, never swallow errors silently
- **Follow existing patterns** — Match the project's established style before introducing new patterns
- **Max file length** — Consider splitting files over 250 lines (IMP-050; enforced by `stop-batched-checks.sh`, configurable via `CLAUDE_LINE_LIMIT`)

## Naming Conventions

### Files & Directories
- **TypeScript/JS:** `kebab-case.ts` for files, `PascalCase.tsx` for components
- **Python:** `snake_case.py` for files
- **Directories:** `kebab-case/` (TypeScript) or `snake_case/` (Python)

### Code
- **Functions/methods:** `camelCase` (TS/JS) or `snake_case` (Python)
- **Classes:** `PascalCase` in all languages
- **Constants:** `UPPER_SNAKE_CASE`
- **Interfaces/Types:** `PascalCase`, no `I` prefix

## Import Organization

Order imports consistently:
1. External packages (node_modules / pip packages)
2. Internal aliases (@/ paths)
3. Relative imports (../ and ./)
4. Type-only imports last

## Component Structure (React/Next.js)

- Server Components by default (Next.js App Router)
- `'use client'` only when needed (hooks, event handlers, browser APIs)
- Proper loading.tsx and error.tsx for each route segment
- Max ~150 lines per component file
