# Documentation Rules

> Standards for documentation, comments, and knowledge management.

## Documentation Categories

| Category (all documentation is one of two) | Contains | Location | Examples |
|---|---|---|---|
| **ACTIVE** — needed to develop NOW | WHAT to do, HOW to do it, CURRENT state | Project root (core docs) or `docs/` (guides) | README.md, CONVENTIONS.md, API docs, setup guides |
| **ARCHIVED** — explains WHY and HISTORY | WHY decisions were made, CONTEXT, CHANGES over time | `docs/archive/[category]/` | Decision logs, migration records, superseded specs |

### Decision Matrix

| Question | → ACTIVE | → ARCHIVED |
|---|---|---|
| Do I need this to code right now? | ✅ | |
| Does this explain a past decision? | | ✅ |
| Will this change frequently? | ✅ | |
| Is this a historical record? | | ✅ |

## Code Documentation

- **JSDoc (TypeScript/JavaScript):** all public functions and classes; include `@param`, `@returns`, `@throws` where applicable, and `@example` for non-obvious usage.
- **Docstrings (Python):** Google-style for all public functions/classes, with Args, Returns, Raises sections; module-level docstrings for non-trivial modules.
- **Comments:** explain WHY, not WHAT (the code shows what); no commented-out code (use version control); TODO comments must include an issue reference: `// TODO(#42): description`.

## README Structure

Every project README should include: (1) one-line description, (2) tech stack (bullet list), (3) setup instructions, (4) available commands, (5) project structure overview.

## Documentation Updates

Update docs alongside code changes (same PR, separate commit); never create docs that duplicate existing ones; keep ACTIVE docs current — outdated docs are worse than no docs; move superseded ACTIVE docs to ARCHIVED with a date header.

## File Metadata

When creating or updating documentation:
```markdown
<!--
Status: ACTIVE | ARCHIVED
Last Updated: YYYY-MM-DD
Purpose: One-line description
-->
```
