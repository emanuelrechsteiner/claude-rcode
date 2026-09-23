---
name: create-rule
description: "Create Claude Code rules for persistent agent guidance. Use when adding coding standards, project conventions, security policies, workflow rules, or any guidance you want auto-loaded every session. Asks for missing scope/purpose, then writes a focused rule file to ~/.claude/rules/ (user-global) or .claude/rules/ (project)."
context: fork
model: sonnet
allowed-tools: Read, Write, Edit, Glob, Grep
---

# Creating Claude Code Rules

Rules are markdown files in `~/.claude/rules/` (user-global) or `.claude/rules/` (project-scoped) that get auto-loaded into every session as guidance. They differ from skills (which load on-demand) by always being in context.

Use rules for principles, conventions, and policies that should be **always-on**. Use skills when behavior should be invoked deliberately.

## Gather Requirements

Before creating a rule, determine:

1. **Purpose**: What principle, convention, or policy is being encoded?
2. **Scope**: User-global (applies to all your projects) or project-specific (this repo only)?
3. **Override Behavior**: Does this complement existing rules, or contradict them?
4. **Evidence**: What incident / pattern motivated this rule? (Helps prevent rule rot.)

### Inferring from Context

If a recent conversation revealed a recurring mistake or validated approach, infer the rule from that. The strongest rules are those derived from real friction, not abstract principles.

## Storage Locations

| Scope | Path | When to Use |
|-------|------|-------------|
| User-global | `~/.claude/rules/<name>.md` | Personal defaults across all projects |
| Project | `.claude/rules/<name>.md` | Project-specific conventions, version-controlled |

User-global rules are loaded for every session regardless of cwd. Project rules load only when working in that project.

## Rule File Format

Rules are `.md` files with optional YAML frontmatter and Markdown body. The Claude Code rule format is simpler than Cursor's:

```markdown
# Rule Name

> One-line description of what this rule governs.

## When This Applies

[Specific conditions, file types, workflow phases]

## The Rule

[The actual guidance — clear and specific]

## Examples

### ✅ Good
```
[concrete example of correct behavior]
```

### ❌ Bad
```
[concrete example of what to avoid]
```

## Rationale

[Why this rule exists — incident reference, evidence, principle]
```

Note: Unlike Cursor's `.mdc` rules with `globs` and `alwaysApply`, **all** Claude Code rules in `rules/` always-apply. There's no file-pattern matching at the rule level. If you need conditional rules, use Skills with descriptions that include trigger conditions.

## Naming Conventions

- Lowercase with hyphens: `code-quality.md`, `security.md`, `tool-discipline.md`
- One concern per file (avoid mega-rules)
- Group related sub-concerns within a file via `##` headings

## Length Guidelines

- **Under 200 lines**: Optimal — token cost stays low, agent can hold full context
- **200-400 lines**: Acceptable for foundational rules (e.g., `foundation.md`)
- **Over 400 lines**: Split into focused sub-rules

The user's current `~/.claude/rules/` has 13 rules averaging ~150 lines each. Match that scale.

## Writing Effective Rules

### Lead with the Rule, Then Justify

```markdown
## Rule
Read before Edit or Write. No exceptions for "I know the file."

**Why:** 50 "File has not been read yet" errors in the 30-day audit.

**How to apply:**
- Need to edit /path/file.ts → Read('/path/file.ts') first
- Creating new file → Write is fine without Read
```

NOT:

```markdown
The user has experienced many issues with editing files...
```

### Include Verifiable Examples

Vague rules don't change behavior. Show the diff:

```markdown
## ✅ Use Read tool for file content
Read(file_path="/abs/path/file.ts")

## ❌ Don't use cat
Bash(cat file.ts)  # forbidden — use Read
```

### Anchor in Evidence

Strong rules cite past incidents:

```markdown
## Reason
"github_pat_*" plaintext file found on disk 2026-05-24 (5 months old).
See SECURITY-ACTIONS.md for incident details.
```

Without evidence, rules become "things the user once said" and decay.

## Anti-Patterns

### ❌ Restating Generic Best Practices

```markdown
# Code Quality
- Write clean code
- Use meaningful names
- Don't repeat yourself
```

This is noise. The agent already knows. Only write rules for things that are:
- Non-obvious
- Project-specific
- Counter to a common default
- Backed by an incident

### ❌ Time-Sensitive Information

```markdown
# After August 2025, use the new auth library
```

Will rot. Instead:

```markdown
# Auth library
Use @auth/v3. v2 deprecated; see ADR-0042 for migration.
```

### ❌ Mixed Concerns

A rule called `everything.md` covering security + style + git is unmaintainable. Split.

### ❌ Excessive Length

A 1000-line rule is no longer a rule — it's a manual. Either split or convert to a Skill.

## Quality Checklist

- [ ] One concern per file
- [ ] Under 200 lines (or justified longer)
- [ ] Concrete examples (✅ / ❌)
- [ ] Rationale included (Why does this exist?)
- [ ] No time-sensitive info
- [ ] Specific enough that violations are detectable

## Workflow

1. **Verify need**: Is this really a rule, or should it be:
   - A Skill (on-demand behavior)?
   - A Hook (programmatic enforcement)?
   - A documentation note (one-time context)?
2. **Pick scope** (user vs. project)
3. **Pick filename** (kebab-case, single concern)
4. **Write the rule** (rule + why + how + examples)
5. **Save** to correct location
6. **Verify auto-load** (next session start should include it)

## Auto-Load Verification

Rules in `~/.claude/rules/` are loaded via the auto-load mechanism (see `CLAUDE.md` reference to "13 auto-loaded rules"). When you add a new rule, the count in `CLAUDE.md` may need updating.

## Examples From the User's Setup

Strong rules from `~/.claude/rules/`:
- `tool-discipline.md` — Cites specific failure counts ("50 Edit-before-Read errors over 30 days")
- `identity-config-check.md` — References a hook (`git-identity-check.sh`) that enforces it
- `api-cost-optimization.md` — Backed by production evidence (a two-phase email triage pipeline)

The strongest rules in this codebase are derived from measured incidents, not abstract principles.

## Related Skills

- `[[create-skill]]` — for behaviors that should load on-demand, not always
- `[[create-hook]]` — for programmatic enforcement (not just guidance)
- `[[migrate-to-skills]]` — for converting old rules-with-globs to Skills
