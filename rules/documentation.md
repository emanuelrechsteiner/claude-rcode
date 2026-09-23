# Documentation Rules

> Standards for documentation, comments, and knowledge management.

## Documentation Categories

All documentation falls into two categories:

### ACTIVE — Needed to develop NOW
- **What it contains:** WHAT to do, HOW to do it, CURRENT state
- **Location:** Project root (core docs) or `docs/` (guides)
- **Examples:** README.md, CONVENTIONS.md, API docs, setup guides

### ARCHIVED — Explains WHY and HISTORY
- **What it contains:** WHY decisions were made, CONTEXT, CHANGES over time
- **Location:** `docs/archive/[category]/`
- **Examples:** Decision logs, migration records, superseded specs

### Decision Matrix

| Question | → ACTIVE | → ARCHIVED |
|----------|----------|------------|
| Do I need this to code right now? | ✅ | |
| Does this explain a past decision? | | ✅ |
| Will this change frequently? | ✅ | |
| Is this a historical record? | | ✅ |

## Code Documentation

### JSDoc (TypeScript/JavaScript)
- All public functions and classes
- Include `@param`, `@returns`, `@throws` where applicable
- Include `@example` for non-obvious usage

### Docstrings (Python)
- Google-style docstrings for all public functions/classes
- Include Args, Returns, Raises sections
- Module-level docstrings for non-trivial modules

### Comments
- Explain WHY, not WHAT (the code shows what)
- No commented-out code (use version control)
- TODO comments must include issue reference: `// TODO(#42): description`

## README Structure

Every project README should include:
1. One-line description
2. Tech stack (bullet list)
3. Setup instructions
4. Available commands
5. Project structure overview

## Documentation Updates

- Update docs alongside code changes (same PR, separate commit)
- Never create docs that duplicate existing ones
- Keep ACTIVE docs current — outdated docs are worse than no docs
- Move superseded ACTIVE docs to ARCHIVED with a date header

## File Metadata

When creating or updating documentation:
```markdown
<!--
Status: ACTIVE | ARCHIVED
Last Updated: YYYY-MM-DD
Purpose: One-line description
-->
```
