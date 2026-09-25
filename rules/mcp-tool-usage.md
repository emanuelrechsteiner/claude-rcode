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
| Edit file (regex) | `mcp__serena__replace_content` | `Edit` | Serena writes run through `serena-write-gate.sh` (see below) |
| Edit file (exact) | — | `Edit` | Simple replacements |
| Edit whole symbol | `mcp__serena__replace_symbol_body` | `Edit` | Gated; token-efficient for full-symbol rewrites |
| Rename symbol (all refs) | `mcp__serena__rename_symbol` | — | Gated with a y/n ask (LSP writes N files) |
| Write file | `mcp__filesystem__write_file` | `Write` | Similar capabilities |
| Find symbols | `mcp__serena__find_symbol` | — | Language-aware (LSP) |
| Find references | `mcp__serena__find_referencing_symbols` | — | Language-aware; `Grep` misses/over-matches |
| Search text | — | `Grep` | Serena's `search_for_pattern` is excluded by the `claude-code` context |
| List files | `mcp__filesystem__list_directory` | `Glob` | Native more flexible |

## Serena

Tools are `mcp__serena__*`. Paths are project-relative, never absolute:
`{"name_path_pattern": "MyClass/myMethod", "relative_path": "src/file.ts"}`.
Param names differ per tool and drift upstream (`replace_symbol_body` takes
`name_path`) — load the current schema via ToolSearch before calling, never from memory.

- **Writes** pass `hooks/serena-write-gate.sh`: same inspectors as native Edit/Write,
  **fail-closed** (unknown tool, param drift, missing inspector → deny).
- `rename_symbol` / `safe_delete_symbol` → recoverable y/n ask (the LSP writes N
  unnamed files). `replace_in_files` stays excluded AND gate-denied. Memory names
  containing `/` or `..` → deny.
- Not delegated: gateguard / pretool-auto-read / controller-first; nor are the N−1
  reference files of an approved rename inspected.
- The project is auto-activated per session (`--project .`), so `activate_project`
  and `get_current_config` are not available.
- Double install? `claude plugin list | grep -i serena` must be empty — never trust a doc.

The `claude-code` context excludes 6 tools:

| Excluded | Use instead |
|---|---|
| `read_file` | `Read` |
| `create_text_file` | `Write` |
| `execute_shell_command` | `Bash` |
| `find_file` | `Glob` |
| `list_dir` | `Glob` / `Bash(ls -la)` |
| `search_for_pattern` | `Grep` |

Before changing any Serena config (`~/.serena/serena_config.yml`, the `~/.claude.json`
registration, hook matchers incl. `mcp__plugin_serena_serena__*`, rollout order), read
`templates/serena_config.yml.template` and `docs/adr/0001-serena-write-gate.md`.

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

### Context7 resolve-library-id parameter names

Two Context7 MCP servers can be connected simultaneously, and they use **different** parameter names for `resolve-library-id`:

| Server | Parameter name |
|--------|---------------|
| `context7-keyed` | `libraryName` |
| `your-context7-server-uuid` | `query` |

Using the wrong parameter name throws a **-32602 invalid params** error. Before calling `resolve-library-id`, check which server is active and use the matching name.

**Correct (context7-keyed):**
```json
{ "libraryName": "react" }
```

**Correct (your-context7-server-uuid server):**
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

> Evidence and incident history (moved verbatim, IMP-217): `docs/archive/rules-evidence/mcp-tool-usage.md`
