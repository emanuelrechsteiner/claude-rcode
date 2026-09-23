---
name: migrate-to-skills
description: "Migrate legacy rule/command files (Cursor .mdc rules, slash-command markdown, old-format skills) to Claude Code SKILL.md format. Use when consolidating cross-platform configs, importing Cursor or Antigravity workflows to Claude Code, or refactoring old rules into the skills/ directory."
context: fork
model: sonnet
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Migrate Legacy Configs to Claude Code Skills

Convert rules and commands from Cursor (`.cursor/rules/*.mdc`, `.cursor/commands/*.md`), Antigravity (`.agent/`), or other tools into Claude Code Skills (`~/.claude/skills/<name>/SKILL.md`).

**CRITICAL:** Preserve the exact body content. Do not modify, reformat, or "improve" it — copy verbatim. The migration is about restructuring metadata, not editing the content.

## Source → Target Mapping

| Source | Target |
|--------|--------|
| `.cursor/rules/*.mdc` (Cursor "Applied intelligently" rules) | `.claude/skills/<name>/SKILL.md` |
| `~/.cursor/rules/*.mdc` (user-level Cursor rules) | `~/.claude/skills/<name>/SKILL.md` |
| `.cursor/commands/*.md` (Cursor slash commands) | `.claude/skills/<name>/SKILL.md` or `.claude/commands/<name>.md` |
| `~/.cursor/commands/*.md` (user-level Cursor commands) | `~/.claude/skills/<name>/SKILL.md` or `~/.claude/commands/<name>.md` |
| `.agent/rules/*.md` (Antigravity rules) | `.claude/rules/<name>.md` (if always-load) or `.claude/skills/<name>/SKILL.md` |
| `.agent/workflows/*.md` (Antigravity workflows) | `.claude/commands/<name>.md` |

### Decision: Skill vs. Command vs. Rule

| If the source is... | Target it as... | Why |
|---------------------|-----------------|-----|
| Workflow with steps (slash command) | `commands/<name>.md` | Commands are invoked by `/<name>` |
| Specialized domain knowledge / template | `skills/<name>/SKILL.md` | Skills load on-demand with `Skill` tool |
| Always-applicable principle | `rules/<name>.md` | Rules auto-load every session |

When in doubt: **commands for "do this workflow"**, **skills for "use this knowledge"**, **rules for "follow this principle"**.

## Cursor Rule Migration (.mdc → SKILL.md)

### Source format
```markdown
---
description: What this rule does
globs: **/*.ts
alwaysApply: false
---
# Title
Body content...
```

### Target format
```markdown
---
name: <kebab-name>
description: "<original description, expanded with WHEN trigger>"
context: fork
model: sonnet
allowed-tools: Read, Write, Edit, Glob, Grep
---
# Title
Body content...
```

### Changes
1. Add `name` field (kebab-case from filename)
2. Add `context: fork` (Claude Code skills run in isolated context)
3. Add `model:` and `allowed-tools:` (sensible defaults based on the rule's purpose)
4. Remove `globs` and `alwaysApply` (not used in Claude Code skills — file matching is via description triggers)
5. **Preserve body verbatim** — no edits, no reformatting

### Glob Handling

If the original rule had `globs: **/*.ts` (only applied to TypeScript files), translate to the description:

```yaml
# Original
globs: **/*.ts
description: "TypeScript coding conventions"

# Migrated
description: "TypeScript coding conventions. Use when working with .ts or .tsx files."
```

## Cursor Command Migration (.md → SKILL.md or command)

### Source
```markdown
# Commit current work
Instructions here...
```

### Target Option A: command (recommended for slash-invoked workflows)
```markdown
# Commit current work
Instructions here...
```
Save to `~/.claude/commands/commit.md` — invoked via `/commit`.

### Target Option B: SKILL.md (recommended for knowledge / templates)
```markdown
---
name: commit
description: "Commit current work with standardized message format. Use when the user types /commit or asks to commit changes."
context: fork
model: haiku
allowed-tools: Bash, Read, Grep
---
# Commit current work
Instructions here...
```
Save to `~/.claude/skills/commit/SKILL.md` — invoked via `Skill` tool.

### Changes
1. If Option A (command): keep filename, save to `commands/` — no frontmatter needed
2. If Option B (skill): add frontmatter, infer description from first heading + content, save to `skills/<name>/SKILL.md`
3. **Preserve body verbatim**

## Antigravity Migration (.agent → .claude)

### `.agent/rules/*.md` → `.claude/rules/*.md`

If the rule should always-load:
- Save as `.claude/rules/<name>.md` (no frontmatter required, or minimal)
- Preserve body verbatim

If it's a domain-specific guide (loaded on-demand):
- Save as `.claude/skills/<name>/SKILL.md` with proper frontmatter

### `.agent/workflows/*.md` → `.claude/commands/*.md`

These are workflow scripts (R.Code-style). Save to `.claude/commands/<name>.md` for `/<name>` invocation.

## Migration Workflow

### If you have the Agent tool available

DO NOT read all the files yourself. Delegate to parallel subagents.

1. **Identify the categories**: project rules, user rules, project commands, user commands
2. **Dispatch parallel subagents** (one per category) to:
   I. Find files matching the source pattern
   II. Check filter criteria (rules: has `description`, no `globs`, no `alwaysApply: true`; commands: always migrate)
   III. List files to migrate
   IV. For each: read, write the new file preserving body EXACTLY, log the migration
   V. Optionally delete the original (only after confirmation)
3. **Wait for all subagents**, then summarize results
4. **Offer undo** — if the user wants to revert, do the reverse

### If working solo (no Agent tool)

1. **Find source files** using Glob:
   ```bash
   # Project rules
   find . -path '*/.cursor/rules/*.mdc' -type f
   # User rules
   find ~/.cursor/rules -name '*.mdc' -type f 2>/dev/null
   # Commands
   find . -path '*/.cursor/commands/*.md' -type f
   find ~/.cursor/commands -name '*.md' -type f 2>/dev/null
   ```

2. **For each file**:
   a. Read the source
   b. Extract description from frontmatter (rules) or first heading (commands)
   c. Determine target: skill, command, or rule (see decision table above)
   d. Create target directory (`mkdir -p`)
   e. Write target file with new frontmatter + verbatim body
   f. Log the migration

3. **Optionally delete originals** — only after the user verifies the migration

4. **Summarize**: list of source → target pairs

## Filter Criteria (Cursor → Claude Code)

### Migrate Rules If
- Has `description` field
- Does NOT have `alwaysApply: true` (those are global Cursor rules, equivalent of Claude Code's auto-loaded `rules/`)
- Does NOT have specific `globs` (those are file-type-specific; consider keeping in Cursor instead, or translate to skill description)

### Migrate Commands
- All commands always migrate (they're plain markdown without frontmatter)

### Skip
- `~/.cursor/skills-cursor/*` — these are Cursor's internal built-in skills, managed automatically (already done if you're reading this — those are the skills being ported)
- `.cursor/worktrees/*` — temporary worktrees
- `.git/` directories

## Naming Conventions

- Skill name = filename without extension, converted to lowercase + hyphens
- Examples:
  - `MyRule.mdc` → `my-rule`
  - `CodeReview.md` → `code-review`
  - `bootstrap-codebase.md` → `bootstrap-codebase` (already conformant)

## CRITICAL Rules

1. **Preserve body verbatim** — no edits, no fixes, no "improvements". Copy character-for-character.
2. **Use the read/write tools**, not terminal `cat`/`echo` — the tools are safer and clearer.
3. **Verify before deleting** originals — only delete after the user confirms migration works.
4. **Migrate atomically** — one file at a time, with logged success before moving to the next.
5. **Test triggers** — after migration, verify the new skill/command can be invoked.

## Undo Strategy

If something goes wrong:
1. Originals are typically untouched until explicit deletion
2. If deleted, check your own backups (the user's chosen backup location, if any — set up before running this migration)
3. To undo a single file: read the new SKILL.md, extract body, reconstruct original frontmatter (Cursor format), write back to original path
4. If unsure: STOP and ask the user — don't compound the error

## Quick Reference

### Cursor → Claude Code Frontmatter Translation

| Cursor Field | Claude Code Equivalent |
|--------------|------------------------|
| `name:` | `name:` (same) |
| `description:` | `description:` (same; may expand with WHEN triggers) |
| `globs:` | (removed — encode in description if needed) |
| `alwaysApply: true` | (moved to `rules/` directory; no equivalent field) |
| `disable-model-invocation: true` | (not needed — skills aren't auto-invoked in Claude Code unless description triggers match) |
| — | `context: fork` (new — controls context isolation) |
| — | `model: haiku\|sonnet\|opus` (new — preferred model) |
| — | `allowed-tools: ...` (new — tool allowlist) |

## Related Skills

- `[[create-skill]]` — for authoring new skills from scratch
- `[[create-rule]]` — for authoring new always-loaded rules
- `[[create-hook]]` — for hook scripts
- `[[create-subagent]]` — for subagent definitions
