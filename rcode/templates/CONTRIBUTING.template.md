# Contributing to [Project Name]

> This project uses the **R.Code Development Workflow** — a strict atomic development process designed for AI-assisted development with comprehensive git traceability.

---

## Getting Started

### Prerequisites

- Node.js [version]
- [Package manager] (npm/yarn/pnpm/bun)
- Git
- GitHub CLI (`gh`) — for issue and PR management
- Claude Code — for AI-assisted development with R.Code commands

### Setup

```bash
# Clone
git clone [REPO_URL]
cd [PROJECT_NAME]

# Install dependencies
[INSTALL_COMMAND]

# Set up environment
cp .env.example .env.local
# Edit .env.local with your values

# Verify setup
[DEV_COMMAND]
[TEST_COMMAND]
```

---

## Development Workflow

This project follows the R.Code workflow. Every code change follows this loop:

```
1. Orient          /rcode-onboard (or read START_HERE.md)
2. Pick issue      From PROJECT-STATUS.md
3. Implement       /issue <#>
4. Review          /review <PR#>
5. Clean context   /clear
6. Repeat
```

### Key Commands

| Command | Purpose |
|---------|---------|
| `/issue <#>` | Full development workflow for one issue |
| `/review <PR#>` | Code review before merge |
| `/status-sync` | Update progress dashboard |
| `/phase-gate <N>` | Verify phase completion |
| `/handoff` | Context handoff between sessions |

---

## Code Standards

### Commit Messages

```
<type>(<area>): <description> - closes #<N>

Phase: <N>
Feature: <feature-id>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `style`, `chore`, `perf`

### Branch Naming

```
<type>/issue-<N>-<kebab-description>
```

### Pre-Commit Checklist

- [ ] TypeScript compiles: `npx tsc --noEmit`
- [ ] Tests pass: `npm test`
- [ ] Build succeeds: `npm run build`
- [ ] ESLint clean: `npx eslint src/`
- [ ] No `console.log` or `debugger` statements

---

## Project Structure

See `CONVENTIONS.md` for detailed folder structure and naming conventions.

---

## Architecture

See `ARCHITECTURE.md` for technology decisions and ADRs.

---

## Scope Policy

- Every issue has a defined **scope boundary** (what's in AND what's out)
- No changes outside the scope of the assigned issue
- New ideas → new issues (never add unplanned work to a branch)
- Scope changes require human approval

See `.claude/rules/rcode-scope.md` for full scope discipline rules.

---

## Getting Help

| I need to... | Read this |
|--------------|-----------|
| Understand the project | `START_HERE.md` |
| See current progress | `PROJECT-STATUS.md` |
| Know the coding style | `CONVENTIONS.md` |
| Understand tech choices | `ARCHITECTURE.md` |
| See feature requirements | `SPECIFICATION.md` |
| Read the full plan | `BRAINSTORM.md` |
