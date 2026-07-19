---
name: create-skill
description: "Create Claude Code Skills (SKILL.md files). Use when authoring a new skill, when the user asks about SKILL.md structure or skill frontmatter, when packaging reusable workflows or domain knowledge into a forked-context capability. Skills differ from rules (always-loaded) and hooks (event-triggered) by being on-demand."
context: fork
model: sonnet
allowed-tools: Read, Write, Edit, Glob, Grep
---

# Creating Claude Code Skills

Skills are markdown files that teach the agent how to perform specific tasks: code reviews, commit message generation, database querying, doc generation, or any specialized workflow. They live in `~/.claude/skills/<name>/SKILL.md` (user-global) or `.claude/skills/<name>/SKILL.md` (project).

Unlike rules (always loaded) and hooks (event-triggered), skills are **invoked on demand** — either by the user via the Skill tool, by name in a system prompt, or automatically based on the description's trigger terms.

## Before You Begin: Gather Requirements

Determine:

1. **Purpose**: What specific task or workflow does this skill help with?
2. **Trigger scenarios**: When should the agent automatically apply this skill?
3. **Scope**: Personal (`~/.claude/skills/`) or project (`.claude/skills/`)?
4. **Context mode**: Forked (isolated context) or main?
5. **Domain knowledge**: What specialized info does the agent need that it doesn't already have?
6. **Output format**: Templates, formats, styles required?

If the user gave verbatim instructions or example output, **preserve it word-for-word**.

## Storage Locations

| Type | Path | Scope |
|------|------|-------|
| Personal | `~/.claude/skills/skill-name/` | Available across all your projects |
| Project | `.claude/skills/skill-name/` | Shared with collaborators via version control |

## Directory Layout

Skills are stored as directories containing a `SKILL.md` file:

```
skill-name/
├── SKILL.md              # Required - main instructions
├── reference.md          # Optional - detailed documentation
├── examples.md           # Optional - usage examples
└── scripts/              # Optional - utility scripts
    ├── validate.py
    └── helper.sh
```

## SKILL.md Frontmatter

Every skill requires YAML frontmatter:

```yaml
---
name: your-skill-name
description: "Specific description with both WHAT it does and WHEN to use it. Include trigger terms users might say."
context: fork
model: haiku
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---
```

### Field Reference

| Field | Required | Values | Purpose |
|-------|----------|--------|---------|
| `name` | yes | lowercase-hyphens, ≤64 chars | Unique identifier |
| `description` | yes | non-empty, ≤1024 chars | Triggers automatic invocation; critical for discovery |
| `context` | recommended | `fork` or `main` | `fork` = isolated context (most skills); `main` = inline in main context (rare) |
| `model` | recommended | `haiku`, `sonnet`, `opus` | Preferred model for the task |
| `allowed-tools` | recommended | comma-separated tool names | Restricts what the skill can do |

### Choosing the Model

| Task Type | Model |
|-----------|-------|
| Classification, fetching, lookup | `haiku` |
| Writing, reasoning, code edits | `sonnet` |
| Multi-step planning, framework reasoning | `opus` |

Default to `haiku` unless the task genuinely needs more capability — token costs add up across invocations.

### Choosing the Tools

List **only** the tools the skill actually needs. Each unused tool in the allow-list is a security and behavior surface area.

Common combinations:
- Read-only research: `WebFetch, WebSearch, Read, Grep, Glob`
- Documentation writing: `Read, Write, Edit, Glob, Grep`
- Build validation: `Bash, Read, Glob`
- Git operations: `Bash, Read, Grep, Glob`

## Writing Effective Descriptions

The description is **critical** for auto-invocation. The agent uses it to decide when to apply the skill.

### Best Practices

1. **Write in third person** (description is injected into system prompt):
   - ✅ "Processes Excel files and generates pivot tables"
   - ❌ "I can help you process Excel files"

2. **Be specific, include trigger terms**:
   - ✅ "Extract text and tables from PDF files. Use when working with PDFs, forms, or document extraction tasks."
   - ❌ "Helps with documents"

3. **Include WHAT and WHEN**:
   - WHAT: capabilities offered
   - WHEN: specific scenarios that trigger invocation

### Description Examples

```yaml
# PDF extraction
description: "Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDFs or when the user mentions PDFs, forms, or document extraction."

# Commit messages
description: "Generate conventional-commit-format messages by analyzing git diffs. Use when the user asks for help writing commit messages or reviewing staged changes."

# Code review
description: "Review code for quality, security, and team standards. Use when reviewing PRs, examining code changes, or when the user asks for a code review."
```

## Core Authoring Principles

### 1. Concise is Key

The context window is shared with conversation history, other skills, and active tasks. Every token competes for space.

**Default assumption**: The agent is already smart. Only add context it doesn't already have.

Challenge each piece:
- "Does the agent really need this explanation?"
- "Can I assume the agent knows this?"
- "Does this paragraph justify its token cost?"

### 2. Keep SKILL.md Under 500 Lines

For optimal performance, the main `SKILL.md` should be concise. Use progressive disclosure for detail.

### 3. Progressive Disclosure

Put essentials in `SKILL.md`; detailed reference in separate files the agent reads only when needed.

```markdown
# PDF Processing

## Quick start
[Essential instructions]

## Additional resources
- For complete API details, see [reference.md](reference.md)
- For usage examples, see [examples.md](examples.md)
```

**Keep references one level deep** — link directly from `SKILL.md` to reference files.

### 4. Match Specificity to Task Fragility

| Freedom | When | Example |
|---------|------|---------|
| **High** (text instructions) | Multiple valid approaches | Code review guidelines |
| **Medium** (templates/pseudocode) | Preferred pattern + variation OK | Report generation |
| **Low** (specific scripts) | Fragile, consistency critical | DB migrations |

## Common Patterns

### Template Pattern

```markdown
## Report structure

Use this template:

\`\`\`markdown
# [Analysis Title]

## Executive Summary
[One-paragraph overview]

## Key Findings
- Finding 1 with supporting data
- Finding 2 with supporting data

## Recommendations
1. Actionable recommendation
2. Actionable recommendation
\`\`\`
```

### Workflow Pattern

```markdown
## Process

1. **Analyze** — Read input, identify shape
2. **Plan** — Decide which output template fits
3. **Execute** — Generate output per template
4. **Validate** — Re-read output, check against checklist
```

### Conditional Workflow

```markdown
## Decision tree

**New content?** → Follow "Creation workflow" below
**Editing existing?** → Follow "Edit workflow" below

### Creation workflow
1. [steps]

### Edit workflow
1. [steps]
```

### Feedback Loop

For quality-critical tasks:

```markdown
## Output validation

1. Generate output
2. **Validate immediately**: run `scripts/validate.py output.md`
3. If validation fails:
   - Review error
   - Fix issue
   - Re-validate
4. **Only proceed when validation passes**
```

## Utility Scripts

Pre-made scripts > generated code when:
- Operations are fragile (must be exact)
- Consistency matters across invocations
- Save tokens by not regenerating

```markdown
## Utility scripts

**scripts/analyze.py**: Extract metadata from input
\`\`\`bash
python scripts/analyze.py input.json > meta.json
\`\`\`

**scripts/validate.py**: Check for errors
\`\`\`bash
python scripts/validate.py output/
# Exits 0 on OK, non-zero with error message on failure
\`\`\`
```

Mark scripts as **executable** (most common) or **read-as-reference** (rare).

## Anti-Patterns

### ❌ Too Many Options
```markdown
"You can use pypdf, or pdfplumber, or PyMuPDF..."
```
→ Pick a default. Mention alternatives only with clear "use when X" criteria.

### ❌ Time-Sensitive Info
```markdown
"Before August 2025, use the old API."
```
→ Will rot. Use "current pattern" + "deprecated pattern" sections.

### ❌ Inconsistent Terminology
Pick one term per concept and use it consistently.

### ❌ Vague Skill Names
- ✅ `processing-pdfs`, `code-review`
- ❌ `helper`, `utils`, `tools`

### ❌ Windows-Style Paths
- ✅ `scripts/helper.py`
- ❌ `scripts\helper.py`

## Workflow

### Phase 1: Discovery
1. Skill purpose + use case
2. Scope (personal vs. project)
3. Trigger scenarios
4. Specific requirements
5. Existing examples / patterns

### Phase 2: Design
1. Skill name (lowercase, hyphens, ≤64 chars)
2. Description (specific, third-person, WHAT + WHEN)
3. Pick `context` (usually `fork`)
4. Pick `model` (haiku unless complexity demands more)
5. List `allowed-tools` (minimal)
6. Outline main sections
7. Identify supporting files / scripts

### Phase 3: Implementation
1. Create directory: `mkdir -p ~/.claude/skills/<name>/`
2. Write `SKILL.md` with frontmatter + body
3. Create reference files if needed (one level deep)
4. Create utility scripts if needed (`chmod +x` if executable)

### Phase 4: Verification
- [ ] `SKILL.md` under 500 lines
- [ ] Description specific with trigger terms
- [ ] Consistent terminology
- [ ] All file references one level deep
- [ ] Skill discoverable in next session

## Complete Example

```
code-review/
├── SKILL.md
├── STANDARDS.md
└── examples.md
```

**SKILL.md:**
```markdown
---
name: code-review
description: "Review code for quality, security, and maintainability per team standards. Use when reviewing pull requests or when the user asks for a code review."
context: fork
model: sonnet
allowed-tools: Read, Grep, Glob, Bash
---

# Code Review

## Quick Start

When reviewing code:
1. Run `git diff` to see recent changes
2. Check correctness + edge cases
3. Verify security best practices
4. Assess readability + maintainability
5. Confirm test coverage

## Review Checklist

- [ ] Logic handles edge cases
- [ ] No security vulnerabilities
- [ ] Follows project style
- [ ] Functions appropriately sized
- [ ] Error handling comprehensive
- [ ] Tests cover changes

## Feedback Format

Organize by priority:
- 🔴 **Critical**: Must fix before merge
- 🟡 **Suggestion**: Consider improving
- 🟢 **Nice to have**: Optional

## Additional Resources
- For detailed standards: [STANDARDS.md](STANDARDS.md)
- For example reviews: [examples.md](examples.md)
```

## Related Skills

- `[[create-hook]]` — for event-triggered automation
- `[[create-rule]]` — for always-loaded guidance
- `[[create-subagent]]` — for delegating specialized work to an agent
- `[[migrate-to-skills]]` — for converting old rules/commands to skill format
