# MCP Tool Usage Guidelines

> Patterns for using MCP tools correctly to prevent validation errors

## Path Conventions

### Serena + MCP Filesystem Tools (relative paths)

Serena (`mcp__serena__*`) and the MCP filesystem server (`mcp__filesystem__*`) use
**relative paths** from project root:

```
✅ relative_path: "src/components/Button.tsx"
✅ relative_path: "./src/utils/helper.ts"
❌ relative_path: "/Users/name/project/src/Button.tsx"  // WRONG - absolute path
```

### Claude Native Tools (absolute paths)

Claude's built-in Read/Edit/Write tools use **absolute paths**:

```
✅ file_path: "/Users/name/project/src/Button.tsx"
❌ file_path: "src/Button.tsx"  // WRONG - relative path
```

## Tool Selection Matrix

| Need | MCP Tool | Native Tool | Notes |
|------|----------|-------------|-------|
| Read file | `mcp__filesystem__read_text_file` | `Read` | Native handles more formats |
| Edit file (regex) | — | `Edit` | Serena's `replace_content` is globally excluded (see below) |
| Edit file (exact) | — | `Edit` | Simple replacements |
| Write file | `mcp__filesystem__write_file` | `Write` | Similar capabilities |
| Find symbols | `mcp__serena__find_symbol` | — | Language-aware (LSP) |
| Find references | `mcp__serena__find_referencing_symbols` | — | Language-aware; `Grep` misses/over-matches |
| Search text | — | `Grep` | Serena's `search_for_pattern` is excluded by the `claude-code` context |
| List files | `mcp__filesystem__list_directory` | `Glob` | Native more flexible |

## Serena: read-only by design (2026-07-17)

Serena runs as a regular MCP server — tools are `mcp__serena__*`, **not** the old
plugin prefix `mcp__plugin_serena_serena__*`. Two independent layers remove tools:

**1. The `claude-code` context** excludes 6 tools that duplicate native ones:

| Excluded Serena tool | Use instead |
|---|---|
| `read_file` | `Read` |
| `create_text_file` | `Write` |
| `execute_shell_command` | `Bash` |
| `find_file` | `Glob` |
| `list_dir` | `Glob` / `Bash(ls -la)` |
| `search_for_pattern` | `Grep` |

**2. `excluded_tools` in `~/.serena/serena_config.yml`** removes every WRITING tool
(`replace_symbol_body`, `insert_*_symbol`, `replace_content`, `replace_in_files`,
`rename_symbol`, `safe_delete_symbol`, `write_memory`, `edit_memory`, `delete_memory`,
`rename_memory`).

**Why:** the hooks in `settings.json` match on tool NAMES (`Write|Edit`). No
`mcp__serena__*` name matches, so Serena edits bypassed all 10 Write|Edit hooks —
including `security-audit.sh` (secret blocking) and `observation-capture.sh`
(the signals.jsonl pipeline). Every one of those hooks is fail-open (exit 0 on a
missing `file_path`/`content`), so an adapter would have reported green without
checking anything. See [[agents-as-users]] — a tool that looks protected but isn't
is worse than a known gap.

**Consequence:** Serena is for READING/NAVIGATION only — `find_symbol`,
`find_referencing_symbols`, `find_declaration`, `find_implementations`,
`get_symbols_overview`, `get_diagnostics_for_file`. All edits go through native
`Edit`/`Write`. Serena's own startup prompt pushes toward Serena edits — ignore it.
If a file was read only via Serena, `Read` it natively before editing.

**Both layers are GLOBAL, and both live OUTSIDE this repo** — `~/.serena/serena_config.yml`
(Serena owns the file and rewrites it) and `~/.claude.json` (the `--context claude-code`
registration). Cloning this repo alone does NOT reproduce them. The reproducible copy,
with the full rationale and the verification traps, is
**`templates/serena_config.yml.template`** — read it before touching any Serena config.
History + measurements: IMP-104/105 in `global-observation/improvement-ledger.json`.

Why global rather than per-project: neither problem is a property of a project.
The hook-bypass is a property of the hook architecture (matchers bind to tool NAMES),
and `.claude/worktrees/` is a Claude Code convention every project can use — a
per-project fix would have solved 1 of 16. Serena merges global and per-project
`ignored_paths` additively, so project-specific noise still belongs in `.serena/project.yml`.

> **Verification traps** (both cost us a wrong conclusion): `serena tools list` shows
> DEFAULT tools, not effective ones — use `get_current_config`. And
> `serena project is_ignored_path` reports "IS NOT ignored" for any NON-EXISTENT path —
> always test with a real file.

## Common Parameter Formats

### mcp__filesystem__read_multiple_files

**Correct:**
```json
{
  "paths": ["/absolute/path/file1.ts", "/absolute/path/file2.ts"]
}
```

**Wrong:**
```json
{
  "paths": "file1.ts"  // ❌ String instead of array
}
```

### mcp__filesystem__edit_file

**Correct:**
```json
{
  "path": "/absolute/path/file.ts",
  "edits": [
    { "oldText": "find this", "newText": "replace with" }
  ]
}
```

**Wrong:**
```json
{
  "path": "/absolute/path/file.ts",
  "edits": "find this -> replace with"  // ❌ String instead of array
}
```

### ~~mcp__serena__replace_content~~ — REMOVED 2026-07-17

Serena's `replace_content` (and every other Serena writing tool) is globally excluded
via `excluded_tools` in `~/.serena/serena_config.yml` — see "Serena: read-only by design"
above. Use native `Edit` instead; only native `Edit`/`Write` trigger the protection hooks.

### mcp__serena__find_symbol (read-only — relative paths)

**Correct:**
```json
{
  "name_path_pattern": "MyClass/myMethod",
  "relative_path": "src/file.ts",
  "include_body": true
}
```

**Wrong:**
```json
{
  "name_path_pattern": "myMethod",
  "relative_path": "/Users/name/project/src/file.ts"  // ❌ Absolute path
}
```

> Parameter names differ per Serena tool and drift between upstream versions
> (e.g. `replace_symbol_body` uses `name_path`, `safe_delete_symbol` uses
> `name_path_pattern`). Always load the current schema via ToolSearch before calling —
> never from memory.

### Context7 resolve-library-id parameter names

Two Context7 MCP servers can be connected simultaneously, and they use **different** parameter names for `resolve-library-id`:

| Server | Parameter name |
|--------|---------------|
| `context7-keyed` | `libraryName` |
| `<your-context7-server-uuid>` | `query` |

Using the wrong parameter name throws a **-32602 invalid params** error. Before calling `resolve-library-id`, check which server is active and use the matching name.

**Correct (context7-keyed):**
```json
{ "libraryName": "react" }
```

**Correct (`<your-context7-server-uuid>` server):**
```json
{ "query": "react" }
```

## Project Boundary Restrictions

MCP tools cannot write outside project directory:

```
❌ Cannot create file outside of the project directory
   got relative_path='/Users/.../.claude/plans/...'
```

**Solution:** Use Claude's native `Write` tool for files outside project.

## Error Prevention Checklist

Before using MCP tools:

- [ ] **Path format** - Using relative for MCP, absolute for native?
- [ ] **Array parameters** - Using arrays where required (paths, edits)?
- [ ] **Required fields** - All required parameters provided?
- [ ] **Project boundary** - File within project directory?
- [ ] **Read first** - Read file before editing (for native Edit)?

## Common Error Patterns

### Pattern 1: Wrong path format
```
Error: File does not exist
```
→ Check if using relative vs absolute correctly for the tool

### Pattern 2: Wrong parameter type
```
Invalid input: expected array, received string
```
→ Wrap single items in arrays: `["item"]` not `"item"`

### Pattern 3: Missing required parameter
```
The required parameter `old_string` is missing
```
→ You're using wrong tool (MCP vs native) or missing fields

### Pattern 4: Path outside project
```
AssertionError - Cannot create file outside of project directory
```
→ Use Claude's native Write tool for external files
