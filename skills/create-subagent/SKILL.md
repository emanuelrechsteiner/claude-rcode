---
name: create-subagent
description: "Create custom Claude Code subagents (specialized AI agents with focused system prompts and tool allowlists). Use when adding a new agent type like code-reviewer, debugger, doc-writer, or domain-specific assistant. Asks for missing scope/purpose, then writes the agent .md file with proper frontmatter."
context: fork
model: sonnet
allowed-tools: Read, Write, Edit, Glob, Grep
---

# Creating Custom Subagents

Subagents are specialized AI assistants that run in isolated contexts with custom system prompts. They're spawned via the `Agent` tool and report back to the main thread.

Use subagents to:
- **Preserve main context** by isolating exploration / detailed work
- **Specialize behavior** with focused system prompts for a domain
- **Reuse configurations** across projects via user-level agents

## Storage Locations

| Location | Scope | Priority |
|----------|-------|----------|
| `.claude/agents/` | Current project | Higher (overrides user-level) |
| `~/.claude/agents/` | All your projects | Lower (default) |

If two agents share the same name, project-level wins.

**Project agents** are version-controlled — share with your team via git.
**User agents** are personal defaults across all your work.

## Agent File Format

Create a `.md` file with YAML frontmatter + Markdown body (the system prompt):

```markdown
---
name: code-reviewer
description: "Reviews code for quality, security, and team standards. Use proactively after writing or modifying code."
model: sonnet
tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# Code Reviewer

You are a senior code reviewer ensuring high standards of quality and security.

When invoked:
1. Run git diff to see recent changes
2. Focus on modified files
3. Begin review immediately

[... rest of system prompt ...]
```

### Frontmatter Fields

| Field | Required | Values | Purpose |
|-------|----------|--------|---------|
| `name` | yes | lowercase-hyphens | Unique identifier; how the agent is invoked |
| `description` | yes | non-empty | Triggers automatic invocation; critical for discovery |
| `model` | recommended | `opus`, `sonnet`, `haiku` | Preferred model for this agent's work |
| `tools` | recommended | YAML list | Restricts what tools the agent can call |
| `skills` | optional | YAML list | Skills the agent has access to |
| `permissionMode` | optional | `acceptEdits` | Auto-accept edits without prompting |

### Choosing the Model

| Agent Type | Model |
|------------|-------|
| Orchestrator, planner | `opus` |
| Implementation specialist (backend, frontend, testing) | `sonnet` |
| Fast utility (cleanup, validation) | `haiku` |

### Choosing the Tools

List **only** what the agent needs. Common combinations:

| Agent Role | Tools |
|------------|-------|
| Code reviewer (read-only) | `Read, Grep, Glob, Bash` |
| Backend dev | `Read, Write, Edit, Glob, Grep, Bash` |
| Researcher | `WebFetch, WebSearch, Read, Grep, Glob` |
| Doc writer | `Read, Write, Edit, Glob, Grep` + MCP doc tools |
| Cleanup | `Bash, Read, Glob, Grep, Edit` |
| Orchestrator | `Read, Write, Edit, TaskCreate, TaskUpdate, TaskList, Glob, Grep` |

## Writing Effective Descriptions

The description triggers automatic invocation. Be specific.

### Best Practices

```yaml
# ❌ Too vague
description: "Helps with code"

# ✅ Specific + actionable
description: "Expert code review specialist. Proactively reviews code for quality, security, and maintainability. Use immediately after writing or modifying code."
```

Include "use proactively" to encourage automatic delegation when the trigger condition is met.

## Example Subagents

### Code Reviewer

```markdown
---
name: code-reviewer
description: "Code review specialist. Reviews recent changes for quality, security, and team standards. Use proactively after writing or modifying code."
model: sonnet
tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# Code Reviewer

You review code for quality and security. You don't make changes — you report findings.

## When invoked
1. Run `git diff` to see recent changes
2. Focus on modified files only
3. Begin review immediately, no preamble

## Review checklist
- [ ] Logic correct + handles edge cases
- [ ] No security vulnerabilities (injection, XSS, secret leaks)
- [ ] Code follows project style
- [ ] Functions appropriately sized + focused
- [ ] Error handling comprehensive
- [ ] No exposed secrets / API keys
- [ ] Tests cover changes adequately

## Feedback format
Organize by priority:
- 🔴 **Critical**: Must fix before merge
- 🟡 **Warning**: Should fix
- 🟢 **Suggestion**: Consider improving

Include specific examples of how to fix issues.
```

### Debugger

```markdown
---
name: debugger
description: "Debugging specialist for errors, test failures, and unexpected behavior. Use proactively when encountering any issue."
model: sonnet
tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
---

# Debugger

You specialize in root-cause analysis.

## When invoked
1. Capture error message + stack trace
2. Identify reproduction steps
3. Isolate failure location
4. Implement minimal fix
5. Verify solution

## Process
- Analyze error messages + logs
- Check recent code changes (`git log -n 20`)
- Form + test hypotheses
- Add strategic debug logging if needed
- Inspect variable states

## For each issue, provide:
- Root cause explanation
- Evidence supporting diagnosis
- Specific code fix
- Testing approach
- Prevention recommendation

Focus on fixing the underlying issue, not symptoms.
```

### Data Analyst

```markdown
---
name: data-analyst
description: "Data analysis expert for SQL queries, CSV/Excel files, and data insights. Use proactively for data tasks and queries."
model: sonnet
tools:
  - Read
  - Write
  - Bash
  - Grep
  - Glob
---

# Data Analyst

You analyze data using SQL, pandas, or shell tools as appropriate.

## When invoked
1. Understand the analysis requirement
2. Inspect the data shape (head, schema, types)
3. Write the appropriate query / script
4. Analyze + summarize results
5. Present findings clearly

## Key practices
- Write efficient queries with proper filters
- Use appropriate aggregations + joins
- Comment complex logic
- Format results for readability
- Provide data-driven recommendations

## For each analysis, provide:
- Approach explanation
- Assumptions documented
- Key findings highlighted
- Suggested next steps

Always optimize for cost + clarity.
```

## Subagent Creation Workflow

### Phase 1: Decide
- Project-level (`.claude/agents/`) or user-level (`~/.claude/agents/`)?
- Which existing agents already cover this? (Avoid overlap.)
- What's the unique value of this new agent?

### Phase 2: Design
- Pick name (lowercase, hyphens)
- Write description (specific, trigger terms, "use proactively" where appropriate)
- Choose model (opus / sonnet / haiku)
- List minimal tools
- Optionally: skills, permissionMode

### Phase 3: Write
```bash
# For user-level
mkdir -p ~/.claude/agents
$EDITOR ~/.claude/agents/<name>.md

# For project-level
mkdir -p .claude/agents
$EDITOR .claude/agents/<name>.md
```

### Phase 4: System Prompt
Write the body. Be specific about:
- What the agent does when invoked
- The workflow/process to follow
- Output format + structure
- Constraints + guidelines
- What the agent does NOT do (defer-list)

### Phase 5: Test
Invoke the agent:
```
Use the <name> subagent to [task description]
```

Verify:
- Description triggers correctly
- Tool allowlist sufficient (not too restrictive)
- Output format consistent
- No infinite loops or context bleed

## Best Practices

1. **Focused agents**: Each excels at one specific role
2. **Detailed descriptions**: Include trigger terms so the orchestrator knows when to delegate
3. **Version control project agents**: Share with the team
4. **Use proactive language** in descriptions: "use proactively", "use immediately after X"
5. **Document defer-list**: What the agent does NOT do, to avoid scope creep

## Troubleshooting

### Agent Not Found
- Ensure file in `.claude/agents/` or `~/.claude/agents/`
- Check `.md` extension
- Verify YAML frontmatter parses (no syntax errors)

### Agent Not Triggering
- Description too vague — add more specific trigger terms
- Conflicting agent with similar description — make distinguishing words clearer

### Agent Has Too Few Tools
- Add missing tools to `tools:` list
- Test with a minimal task first

### Agent Has Too Many Tools
- Remove unused tools — improves agent focus + security
- If the agent really needs many tools, consider splitting

## Coordination Protocol (Optional)

For agents working within a control-agent-led workflow, add a "Coordination Protocol" section to the system prompt:

```markdown
## Coordination Protocol (Recommended, not Mandatory)

### Before Action
Briefly state intent: what + why + expected output.

### After Action
Report concrete results: files changed, decisions made, blockers.

Skip this protocol for trivial work where overhead exceeds value.
```

The `control-agent` (in `~/.claude/agents/control-agent.md`) expects this pattern but doesn't enforce it.

## Related Skills

- `[[create-skill]]` — for capabilities (not full agents)
- `[[create-rule]]` — for always-loaded guidance instead of an agent
- `[[create-hook]]` — for event-triggered enforcement
