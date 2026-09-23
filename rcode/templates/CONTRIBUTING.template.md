# Contributing to [Project Name]

> This project uses the **R.Code Development Workflow** — a strict atomic development process designed for AI-assisted development with comprehensive git traceability.

---

## Getting Started

### Prerequisites

- [Runtime/language — e.g., Node.js, Python, Go] [version]
- [Package manager, if applicable] (npm/yarn/pnpm/bun/pip/uv/…)
- Git
- GitHub CLI (`gh`) — only if this project tracks work as GitHub issues (`tracker: "github"` in `.rcode/config.json`)
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
2. Work            /team-lead "<directive>" — the main entrance; plans and dispatches units
                    (or /issue <unit> directly for a single unit you already picked)
3. Review          /rcode-review <PR#>
4. Clean context   /clear
5. Repeat
```

### Key Commands

| Command | Purpose |
|---------|---------|
| `/team-lead "<directive>"` | Main entrance — plans, dispatches, and tracks work units |
| `/issue <unit>` | Full development workflow for one work unit (`#N` or `P-NNN`) |
| `/rcode-review <PR#>` | Code review before merge |
| `/status-sync` | Update progress dashboard |
| `/phase-gate <N>` | Verify phase completion |
| `/handoff` | Context handoff between sessions |

---

## Code Standards

### Commit Messages

Full convention: `.claude/rules/rcode-commits.md` (single source). Quick reference:

```
<type>(<area>): <description> - closes #<N>    (tracker github)
<type>(<area>): <description> - closes P-<NNN> (tracker plan)

Phase: <N>
Feature: <feature-id>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `style`, `chore`, `perf`

### Branch Naming

```
<type>/issue-<N>-<kebab-description>  (tracker github)
<type>/p-<NNN>-<kebab-description>    (tracker plan)
```

### Pre-Commit Checklist

- [ ] Check trio passes — see this project's `CLAUDE.md` → `## Mandatory Pre-Commit`
- [ ] No debug statements left in the diff (e.g. `console.log`, `print()`, `debugger`)

---

## Project Structure

See `CONVENTIONS.md` for detailed folder structure and naming conventions.

---

## Architecture

See `ARCHITECTURE.md` for technology decisions and ADRs.

---

## Scope Policy

- Every unit has a defined **scope boundary** (what's in AND what's out)
- No changes outside the scope of the assigned unit
- New ideas → new units (never add unplanned work to a branch)
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
