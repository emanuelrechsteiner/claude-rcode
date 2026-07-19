# Claude Code Configuration Manual

> Comprehensive guide for configuring Claude Code CLI with sub-agents, hooks, commands, skills, and plugins.

**Version**: 1.0.0
**Last Updated**: January 2026
**Based on**: Official Anthropic Documentation & Best Practices

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Settings Configuration](#2-settings-configuration)
3. [CLAUDE.md Memory Files](#3-claudemd-memory-files)
4. [Permissions System](#4-permissions-system)
5. [MCP Servers](#5-mcp-servers)
6. [Sub-Agents](#6-sub-agents)
7. [Hooks](#7-hooks)
8. [Custom Commands](#8-custom-commands)
9. [Skills](#9-skills)
10. [Plugins](#10-plugins)
11. [Best Practices](#11-best-practices)
12. [Troubleshooting](#12-troubleshooting)
13. [Quick Reference](#13-quick-reference)

---

## 1. Introduction

Claude Code is Anthropic's official CLI for Claude that helps users with software engineering tasks. The configuration system allows extensive customization through:

- **Settings files** - JSON configuration for permissions, model selection, hooks, and plugins
- **CLAUDE.md files** - Markdown-based memory and instructions
- **Sub-agents** - Specialized agents for focused tasks
- **Hooks** - Lifecycle event handlers for automation
- **Commands** - Custom slash commands for recurring tasks
- **Skills** - Model-invokable capabilities with supporting resources
- **Plugins** - Modular extensions combining all the above

### Directory Structure Overview

```
~/.claude/                          # User-level (global) configuration
├── settings.json                   # Global settings
├── settings.local.json             # Personal overrides (auto-gitignored)
├── CLAUDE.md                       # Global instructions
├── agents/                         # Personal agent definitions
├── commands/                       # Personal slash commands
├── skills/                         # Personal skills
├── hooks/                          # Personal hook scripts
├── plugins/                        # Installed plugins
└── rules/                          # Modular rule files

project-root/
├── .claude/                        # Project-level configuration
│   ├── settings.json               # Project settings (team-shared)
│   ├── settings.local.json         # Personal project overrides
│   ├── CLAUDE.md                   # Project memory
│   ├── agents/                     # Project-specific agents
│   ├── commands/                   # Project-specific commands
│   ├── skills/                     # Project-specific skills
│   └── rules/                      # Modular project rules
├── CLAUDE.md                       # Alternative project memory location
└── .mcp.json                       # MCP servers (team-shared)
```

---

## 2. Settings Configuration

### 2.1 Settings File Hierarchy

Settings are loaded with the following precedence (highest to lowest):

1. **Managed** - Organization-deployed (`/Library/Application Support/ClaudeCode/`)
2. **Command line arguments** - Session overrides
3. **Local** - `.claude/settings.local.json` (personal, gitignored)
4. **Project** - `.claude/settings.json` (team-shared)
5. **User** - `~/.claude/settings.json` (global)

### 2.2 Core Settings Options

```json
{
  "model": "opus",
  "maxTokens": 4000,
  "outputStyle": "Explanatory",
  "alwaysThinkingEnabled": true,
  "spinnerTipsEnabled": true,
  "respectGitignore": true,
  "env": {
    "CUSTOM_VAR": "value"
  },
  "attribution": {
    "commit": "Generated with Claude Code",
    "pr": ""
  }
}
```

### 2.3 Sandbox Configuration

```json
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "allowUnsandboxedCommands": false,
    "network": {
      "httpProxyPort": 8080,
      "socksProxyPort": 8081,
      "allowUnixSockets": ["~/.ssh/agent-socket"],
      "allowLocalBinding": true
    },
    "excludedCommands": ["git", "docker", "npm", "node"]
  }
}
```

### 2.4 Agent Settings

```json
{
  "agents": {
    "auto-activate": true,
    "coordination-required": true,
    "reporting-interval": 30
  }
}
```

### 2.5 Status Line Configuration

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

---

## 3. CLAUDE.md Memory Files

### 3.1 Purpose

CLAUDE.md files provide persistent instructions and context that Claude reads automatically. They serve as:
- Project-specific coding standards
- Architecture documentation
- Workflow instructions
- Team conventions

### 3.2 Location Hierarchy

| Location | Scope | Use Case |
|----------|-------|----------|
| `~/.claude/CLAUDE.md` | Global | Personal preferences |
| `./CLAUDE.md` | Project | Team-shared instructions |
| `./.claude/CLAUDE.md` | Project | Alternative project location |
| `./CLAUDE.local.md` | Project | Personal project overrides |
| `./.claude/rules/*.md` | Project | Modular topic rules |
| `./src/auth/CLAUDE.md` | Folder | Context-specific rules |

### 3.3 File Import Syntax

Reference external files with `@` prefix:

```markdown
# Project Overview
@README.md

# Package Configuration
@package.json

# Git Workflow
@docs/git-instructions.md

# Personal Instructions
@~/.claude/my-project-instructions.md
```

**Maximum import depth**: 5 hops

### 3.4 Path-Specific Rules

Use YAML frontmatter to scope rules to specific files:

```markdown
---
paths:
  - "src/api/**/*.ts"
  - "lib/utils/**/*.ts"
---

# API Development Rules

- All functions must include JSDoc comments
- Add error handling for async operations
- Use consistent error response format
```

---

## 4. Permissions System

### 4.1 Permission Categories

| Category | Behavior |
|----------|----------|
| `deny` | Block regardless (checked first) |
| `ask` | Prompt user for approval |
| `allow` | Permit automatically |

### 4.2 Configuration Structure

```json
{
  "permissions": {
    "deny": [
      "Bash(sudo:*)",
      "Bash(rm -rf /*:*)",
      "Read(**/.env)",
      "Read(**/secrets/**)"
    ],
    "ask": [
      "Bash(git push:*)",
      "Bash(git commit:*)",
      "Bash(npm install:*)"
    ],
    "allow": [
      "Bash(git status:*)",
      "Bash(npm run:*)",
      "Read(.claude/)",
      "Edit(./src/**/*.ts)"
    ],
    "additionalDirectories": [
      "/Users/name/projects"
    ]
  }
}
```

### 4.3 Pattern Syntax

| Pattern | Example | Matches |
|---------|---------|---------|
| Exact match | `Bash(npm run build)` | Only `npm run build` |
| Prefix wildcard | `Bash(npm run:*)` | `npm run build`, `npm run test` |
| Glob anywhere | `Bash(git * main)` | `git commit main`, `git push main` |
| Relative paths | `Read(./.env)` | Files relative to settings.json |
| Home expansion | `Read(~/.aws/**)` | Home directory paths |
| Recursive glob | `Edit(./src/**/*.ts)` | All .ts files in src tree |

### 4.4 Tool Types

- `Bash(command)` - Terminal commands
- `Read(filepath)` - File read access
- `Edit(filepath)` - File write/edit access
- `Write(filepath)` - File creation
- `WebFetch` - HTTP requests
- `Task(*)` - Sub-agent spawning

---

## 5. MCP Servers

### 5.1 Configuration Scopes

| Scope | Location | Use Case |
|-------|----------|----------|
| `project` | `.mcp.json` | Team-shared servers |
| `local` | `~/.claude.json` | Personal project servers |
| `user` | `~/.claude.json` | Global personal utilities |

### 5.2 CLI Commands

```bash
# Add servers
claude mcp add --transport http <name> <url>
claude mcp add --transport stdio <name> -- <command> [args...]
claude mcp add --transport http <name> --scope project <url>

# Manage servers
claude mcp list
claude mcp get <name>
claude mcp remove <name>

# Check status in Claude Code
/mcp
```

### 5.3 Configuration Format

```json
{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/"
    },
    "local-db": {
      "type": "stdio",
      "command": "/path/to/server",
      "args": ["--config", "config.json"],
      "env": {
        "DB_URL": "postgresql://user:pass@localhost/db",
        "API_KEY": "${API_TOKEN:-default}"
      }
    }
  }
}
```

### 5.4 Environment Variables

- `MCP_TIMEOUT=10000` - Server startup timeout (ms)
- `MAX_MCP_OUTPUT_TOKENS=50000` - Max output per tool call

---

## 6. Sub-Agents

### 6.1 Agent Definition Format

Agents are Markdown files with YAML frontmatter in `.claude/agents/`:

```markdown
---
name: code-reviewer
description: Expert code review specialist. Use for security, performance, and maintainability reviews.
tools: Read, Grep, Glob
model: sonnet
---

You are a code review specialist with expertise in security, performance, and best practices.

CRITICAL: You are READ-ONLY. You cannot modify files or run commands.

When reviewing code:
1. First, understand the codebase structure using Glob and Read
2. Identify security vulnerabilities
3. Check for performance issues
4. Verify adherence to coding standards
5. Suggest specific, actionable improvements
```

### 6.2 Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique identifier (lowercase, hyphens) |
| `description` | Yes | When Claude should delegate |
| `tools` | No | Allowed tools (omit = inherit all) |
| `disallowedTools` | No | Explicit tool denials |
| `model` | No | `sonnet`, `opus`, `haiku`, or `inherit` |
| `permissionMode` | No | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, `plan` |
| `skills` | No | Pre-loaded skills |
| `hooks` | No | Lifecycle hooks |

### 6.3 Tool Restriction Patterns

| Agent Type | Recommended Tools |
|------------|-------------------|
| Read-only | `Read, Grep, Glob` |
| Execution | `Bash, Read, Grep` |
| Modification | `Read, Edit, Write, Grep, Glob` |
| Full access | Omit `tools` field |

### 6.4 Multi-Agent Orchestration

**Sequential Pattern**:
```
PM-spec → Architect-review → Implementer-tester
```

**Parallel Pattern**:
```
[style-checker] + [security-scanner] + [test-coverage]
     ↓                   ↓                    ↓
                   [coordinator]
```

### 6.5 Agent Best Practices

1. **Single-responsibility**: One clear goal per agent
2. **Clear descriptions**: Action-oriented for proper matching
3. **Explicit tool restrictions**: Whitelist rather than blacklist
4. **Defined completion criteria**: What "done" means
5. **No nested subagents**: Agents cannot spawn their own subagents

---

## 7. Hooks

### 7.1 Hook Event Types

| Event | When It Fires |
|-------|---------------|
| `SessionStart` | Claude Code starts/resumes |
| `UserPromptSubmit` | User submits a prompt |
| `PreToolUse` | Before tool execution |
| `PermissionRequest` | Permission dialogs appear |
| `PostToolUse` | After tool completes |
| `Stop` | Claude finishes responding |
| `SubagentStop` | Subagent completes |
| `PreCompact` | Before context compaction |
| `Notification` | Claude sends notifications |
| `Setup` | With `--init`, `--init-only`, `--maintenance` |
| `SessionEnd` | Session terminates |

### 7.2 Hook Configuration

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/validate-bash.sh",
            "timeout": 60
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/auto-format.sh \"$file_path\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Check for uncommitted changes. Return {\"ok\": true} or {\"ok\": false, \"reason\": \"...\"}"
          }
        ]
      }
    ]
  }
}
```

### 7.3 Matcher Patterns

| Pattern | Matches |
|---------|---------|
| `"Write"` | Only Write tool |
| `"Edit\|Write"` | Edit or Write |
| `"mcp__github__.*"` | All GitHub MCP tools |
| `"*"` | All tools |
| `""` | All (useful for Notification) |

### 7.4 Hook Types

**Command Hooks** (`type: "command"`):
- Execute shell scripts
- Exit codes: `0` = success, `2` = block
- Receive JSON input via stdin
- Return JSON output for modifications

**Prompt Hooks** (`type: "prompt"`):
- Use LLM for intelligent decisions
- Only for Stop/SubagentStop events
- Return `{decision, reason, continue}` JSON

### 7.5 Environment Variables

| Variable | Description |
|----------|-------------|
| `$CLAUDE_PROJECT_DIR` | Absolute path to project root |
| `$CLAUDE_CODE_REMOTE` | "true" if web environment |
| `$CLAUDE_ENV_FILE` | Path to persist env vars (SessionStart) |

### 7.6 Input/Output Format

**Input (stdin)**:
```json
{
  "session_id": "string",
  "transcript_path": "string",
  "cwd": "string",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test",
    "description": "Run tests"
  }
}
```

**PreToolUse JSON Output** (permission control):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask",
    "permissionDecisionReason": "Reason for decision",
    "updatedInput": {"command": "modified-command"}
  }
}
```

### 7.7 Common Hook Examples

**Dangerous Command Blocker**:
```bash
#!/bin/bash
command=$(jq -r '.tool_input.command')
if [[ "$command" =~ (rm.*-rf|sudo|dd\ if=) ]]; then
    echo "Blocked dangerous command: $command" >&2
    exit 2
fi
exit 0
```

**Post-Edit TypeScript Check**:
```bash
#!/bin/bash
FILE_PATH="$1"
if [[ "$FILE_PATH" =~ \.(ts|tsx)$ ]]; then
    npx tsc --noEmit 2>&1 | head -20
    exit ${PIPESTATUS[0]}
fi
exit 0
```

**Auto-Format on Write**:
```bash
#!/bin/bash
file_path=$(jq -r '.tool_input.file_path')
if [[ "$file_path" == *.ts ]]; then
    npx prettier --write "$file_path"
fi
exit 0
```

---

## 8. Custom Commands

### 8.1 Command Definition

Commands are Markdown files in `.claude/commands/`:

```
.claude/commands/
├── refactor.md       → /refactor
├── review.md         → /review
└── frontend/
    └── component.md  → /component
```

### 8.2 Command Structure

```markdown
---
description: Short description shown in /help
argument-hint: [required-arg] [optional-arg]
allowed-tools: Read, Grep, Glob, Bash
model: claude-sonnet-4-20250514
disable-model-invocation: true
---

Your command prompt here.

Current state:
!`git status -s`

User request:
$ARGUMENTS
```

### 8.3 Frontmatter Fields

| Field | Description |
|-------|-------------|
| `description` | When/why to use (shown in `/help`) |
| `argument-hint` | Expected arguments |
| `allowed-tools` | Restrict to specific tools |
| `model` | Override model selection |
| `disable-model-invocation` | Prevent auto-triggering |
| `user-invocable` | Hide from `/` menu |

### 8.4 Variable Substitution

| Variable | Description |
|----------|-------------|
| `$ARGUMENTS` | All arguments passed |
| `$1`, `$2`, `$3` | Positional arguments |
| `${CLAUDE_SESSION_ID}` | Current session ID |
| `!`command`` | Execute bash, inject output |
| `@filepath` | Include file contents |

### 8.5 Built-in Commands

- `/help` - Display all commands
- `/clear` - Clear conversation
- `/compact` - Compress history
- `/config` - Open settings
- `/memory` - View memory files
- `/mcp` - Check MCP status
- `/init` - Initialize project

---

## 9. Skills

### 9.1 Skill Structure

```
.claude/skills/skill-name/
├── SKILL.md          # Required: Main definition
├── README.md         # Optional: Documentation
├── references/       # Optional: Detailed guides
│   ├── patterns.md
│   └── api-reference.md
├── examples/         # Optional: Working examples
│   └── example.ts
└── scripts/          # Optional: Utilities
    └── validate.sh
```

### 9.2 SKILL.md Format

```markdown
---
name: skill-identifier
description: Clear description of when Claude should use this skill. Include trigger phrases like "create component", "review code", "debug issue".
version: 1.0.0
disable-model-invocation: true
user-invocable: false
allowed-tools: Read, Grep, Glob
context: fork
agent: Explore
model: claude-opus-4-5
---

# Skill Overview

Core instructions and procedures.

## Additional Resources

### Reference Files
- **`references/patterns.md`** - Detailed patterns

### Examples
- **`examples/script.ts`** - Working example
```

### 9.3 Frontmatter Fields

| Field | Description |
|-------|-------------|
| `name` | Unique identifier (lowercase, hyphens) |
| `description` | **CRITICAL**: Determines auto-invocation |
| `version` | Semantic version |
| `disable-model-invocation` | Manual `/skill-name` only |
| `user-invocable` | Hide from manual invocation |
| `allowed-tools` | Restrict tool access |
| `context` | `fork` for isolated subagent |
| `agent` | Subagent type (`Explore`, `Plan`) |
| `model` | Override model |

### 9.4 Progressive Disclosure

| Level | Content | When Loaded |
|-------|---------|-------------|
| 1 | Name + Description | Always |
| 2 | SKILL.md body | When triggered |
| 3 | references/, examples/ | On-demand |

### 9.5 Skills vs Commands vs Agents

| Aspect | Skill | Command | Agent |
|--------|-------|---------|-------|
| Invocation | Auto + Manual | Manual only | Spawned by Claude |
| Supporting files | Yes | No | Yes |
| Best for | Guidance, knowledge | Actions | Complex tasks |

### 9.6 Writing Effective Descriptions

**Good**:
```yaml
description: This skill should be used when the user asks to "create a hook", "add PreToolUse validation", or mentions "hook patterns". Provides comprehensive hook development guidance.
```

**Bad**:
```yaml
description: Helps with hooks
```

---

## 10. Plugins

### 10.1 Plugin Structure

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json      # ONLY file in .claude-plugin/
├── commands/            # At plugin root, NOT in .claude-plugin/
├── agents/
├── skills/
├── hooks/
├── .mcp.json
└── README.md
```

**CRITICAL**: All component directories must be at plugin root, NOT inside `.claude-plugin/`.

### 10.2 Plugin Manifest (plugin.json)

```json
{
  "name": "my-plugin",
  "description": "Plugin description",
  "version": "1.0.0",
  "author": {
    "name": "Your Name",
    "email": "email@example.com"
  },
  "homepage": "https://docs.example.com",
  "repository": "https://github.com/author/plugin",
  "license": "MIT",
  "keywords": ["keyword1", "keyword2"],
  "commands": ["./commands/"],
  "agents": "./agents/",
  "skills": "./skills/",
  "hooks": "./hooks/hooks.json",
  "mcpServers": "./mcp-config.json"
}
```

### 10.3 Installation Commands

```bash
# Install from marketplace
claude plugin install <plugin> [--scope user|project|local]

# Enable/Disable
claude plugin enable <plugin>
claude plugin disable <plugin>

# Update
claude plugin update <plugin>

# Uninstall
claude plugin uninstall <plugin>
```

### 10.4 Configuration in settings.json

```json
{
  "enabledPlugins": {
    "formatter@acme-tools": true,
    "deployer@acme-tools": true,
    "analyzer@security-plugins": false
  }
}
```

### 10.5 Testing Plugins Locally

```bash
claude --plugin-dir ./my-plugin

# Multiple plugins
claude --plugin-dir ./plugin-one --plugin-dir ./plugin-two
```

### 10.6 Official Plugins

| Category | Plugins |
|----------|---------|
| Languages | typescript-lsp, pyright-lsp, gopls-lsp, rust-analyzer-lsp, etc. |
| Code Quality | code-review, pr-review-toolkit, security-guidance |
| Development | feature-dev, frontend-design, plugin-dev |
| Git | commit-commands |
| Integrations | firebase, vercel, playwright |
| MCP | context7, serena |

---

## 11. Best Practices

### 11.1 Security

1. **Deny-first permissions**: Start with denials, then add allows
2. **Explicit tool restrictions**: Always whitelist in agents/skills
3. **Hook validation**: Validate all inputs in hooks
4. **No secrets in config**: Use environment variables
5. **Review hook scripts**: Hooks run with user permissions

### 11.2 Organization

1. **Modular rules**: Use `.claude/rules/*.md` for topic organization
2. **Skill over command**: Prefer skills for new development
3. **Project settings in VCS**: Share `.claude/settings.json` with team
4. **Local for personal**: Use `.local.json` for machine-specific config

### 11.3 Performance

1. **Lean SKILL.md**: Target 1,500-2,000 words
2. **Progressive disclosure**: Move details to references/
3. **Tool restrictions**: Limit tools to reduce permission prompts
4. **Fast hooks**: Keep SessionStart hooks quick

### 11.4 Development Workflow

1. **Clear descriptions**: Action-oriented for proper matching
2. **Test locally**: Use `--plugin-dir` before publishing
3. **Semantic versioning**: Major.Minor.Patch format
4. **Document everything**: README, CHANGELOG, inline comments

---

## 12. Troubleshooting

### 12.1 Common Issues

**Agent not activating**:
- Check Task tool is in allowed tools
- Verify description matches task clearly
- Try explicit naming: "Use the X agent to..."
- Restart session (agents load at startup)

**Hook not triggering**:
- Verify matcher pattern case-sensitivity
- Check file permissions (executable)
- Test with explicit tool name
- Check exit codes (0 = success, 2 = block)

**Skill not found**:
- Verify directory structure
- Check SKILL.md exists
- Validate YAML frontmatter
- Test description trigger phrases

**Permission denied**:
- Check deny rules (highest priority)
- Verify allow pattern syntax
- Use relative paths from settings.json location
- Check sandbox configuration

### 12.2 Debugging Commands

```bash
# View loaded settings
/config

# Check MCP status
/mcp

# View memory files
/memory

# Test hook interactively
/hooks

# Check plugin status
/plugin
```

### 12.3 Common Gotchas

1. **Frontmatter YAML**: Must be between `---` markers at very top
2. **Matcher case-sensitivity**: `"write"` won't match `Write`
3. **Path traversal blocked**: Cannot use `../` in plugins
4. **Tool inheritance**: Omitting `tools` = ALL tools allowed
5. **Settings don't merge**: Local overrides, doesn't extend
6. **Windows long prompts**: May fail with 8191 char limit
7. **No nested subagents**: Agents can't spawn their own agents

---

## 13. Quick Reference

### 13.1 Directory Cheat Sheet

| Location | Purpose |
|----------|---------|
| `~/.claude/settings.json` | Global settings |
| `~/.claude/CLAUDE.md` | Global memory |
| `~/.claude/agents/` | Personal agents |
| `~/.claude/commands/` | Personal commands |
| `~/.claude/skills/` | Personal skills |
| `~/.claude/hooks/` | Personal hook scripts |
| `.claude/settings.json` | Project settings |
| `.claude/rules/*.md` | Modular rules |
| `.mcp.json` | MCP servers |

### 13.2 Useful Commands

```bash
# Settings
/config                 # Open settings
/memory                 # View memory files

# MCP
/mcp                    # Check status
claude mcp list         # List servers
claude mcp add          # Add server

# Plugins
/plugin                 # Plugin manager
claude plugin install   # Install plugin
claude plugin enable    # Enable plugin

# Hooks
/hooks                  # Hook setup
```

### 13.3 File Templates

**Agent Template**:
```markdown
---
name: agent-name
description: When to use this agent
tools: Read, Grep, Glob
model: sonnet
---

System prompt here.
```

**Command Template**:
```markdown
---
description: What this command does
argument-hint: [arg]
allowed-tools: Read, Grep
---

Command prompt with $ARGUMENTS
```

**Skill Template**:
```markdown
---
name: skill-name
description: Trigger phrases and when to use
---

Skill instructions here.
```

---

## Resources

### Official Documentation
- [Claude Code Docs](https://code.claude.com/docs/)
- [Settings Reference](https://code.claude.com/docs/en/settings)
- [Memory Management](https://code.claude.com/docs/en/memory)
- [Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Skills Guide](https://code.claude.com/docs/en/skills)
- [Plugins Reference](https://code.claude.com/docs/en/plugins-reference)
- [Sub-Agents Guide](https://code.claude.com/docs/en/sub-agents)

### Repositories
- [Claude Code GitHub](https://github.com/anthropics/claude-code)
- [Official Plugins](https://github.com/anthropics/claude-plugins-official)
- [Awesome Claude Code](https://github.com/hesreallyhim/awesome-claude-code)
- [Claude Code Subagents](https://github.com/VoltAgent/awesome-claude-code-subagents)

### Community
- [ClaudeLog](https://claudelog.com/)
- [Claude World](https://claude-world.com/)

---

*This manual is maintained as part of the Claude Code self-improvement infrastructure.*
