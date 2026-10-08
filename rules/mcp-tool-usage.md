# MCP Tool Usage Guidelines

> Patterns for using MCP tools correctly to prevent validation errors.

## Path Conventions

| Tools | Paths | ✅ | ❌ |
|---|---|---|---|
| Serena (`mcp__serena__*`), MCP filesystem (`mcp__filesystem__*`) | **relative** to project root | `src/components/Button.tsx`, `./src/utils/helper.ts` | `/Users/<user>/project/src/Button.tsx` |
| Claude native `Read` / `Edit` / `Write` | **absolute** | `/Users/<user>/project/src/Button.tsx` | `src/Button.tsx` |

`Error: File does not exist` → check relative vs absolute for that tool. MCP tools cannot write outside the project directory (`AssertionError - Cannot create file outside of project directory`) — use Claude's native `Write` for files outside the project.

## Tool Selection Matrix

| Need | MCP Tool | Native Tool | Notes |
|---|---|---|---|
| Read file | `mcp__filesystem__read_text_file` | `Read` | Native handles more formats |
| Edit file (regex) | `mcp__serena__replace_content` | `Edit` | Serena writes run through `serena-write-gate.sh` |
| Edit file (exact) | — | `Edit` | Simple replacements |
| Edit whole symbol | `mcp__serena__replace_symbol_body` | `Edit` | Gated; token-efficient for full-symbol rewrites |
| Rename symbol (all refs) | `mcp__serena__rename_symbol` | — | Gated with a y/n ask (LSP writes N files) |
| Write file | `mcp__filesystem__write_file` | `Write` | Similar capabilities |
| Find symbols | `mcp__serena__find_symbol` | — | Language-aware (LSP) |
| Find references | `mcp__serena__find_referencing_symbols` | — | Language-aware; `Grep` misses/over-matches |
| Search text | — | `Grep` | Serena's `search_for_pattern` is excluded (below) |
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

Array parameters take arrays, never a string (`Invalid input: expected array, received string` → wrap single items: `["item"]`, not `"item"`):
- `mcp__filesystem__read_multiple_files`: `{"paths": ["/absolute/path/file1.ts", "/absolute/path/file2.ts"]}`
- `mcp__filesystem__edit_file`: `{"path": "/absolute/path/file.ts", "edits": [{"oldText": "find this", "newText": "replace with"}]}`

Provide all required parameters; ``The required parameter `old_string` is missing`` means the wrong tool (MCP vs native) or missing fields. Before a native `Edit`, Read the file first ([[tool-discipline]] Rule 1).

### Context7 resolve-library-id parameter names

Two Context7 MCP servers can be connected simultaneously, and they use **different** parameter names for `resolve-library-id`: `context7-keyed` takes `libraryName`, `your-context7-server-uuid` takes `query` (e.g. `{ "libraryName": "react" }`). The wrong name throws a **-32602 invalid params** error — before calling `resolve-library-id`, check which server is active and use the matching name.
