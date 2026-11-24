# MCP Tool Usage Guidelines

> Patterns for using MCP tools correctly to prevent validation errors.

## Paths

Serena (`mcp__serena__*`) and MCP filesystem tools take paths RELATIVE to the project root; Claude's native Read/Edit/Write take ABSOLUTE paths. `Error: File does not exist` → check which convention the tool wants. MCP tools cannot write outside the project directory — use native `Write` there.

## Tool selection

Serena for symbol-aware work (`find_symbol`, `find_referencing_symbols`, `replace_symbol_body`, `rename_symbol`); `Grep` for text search; native Read/Write/Edit/Glob for everything else. The `claude-code` context excludes six Serena tools — `read_file`, `create_text_file`, `execute_shell_command`, `find_file`, `list_dir`, `search_for_pattern` — use Read, Write, Bash, Glob, Glob/`ls -la`, Grep instead. Array parameters take arrays, never a string (`["item"]`, not `"item"`).

## Serena

Project-relative paths (`{"name_path_pattern": "MyClass/myMethod", "relative_path": "src/file.ts"}`); parameter names drift upstream — load the current schema via ToolSearch before calling, never from memory. Writes pass `hooks/serena-write-gate.sh` (same inspectors as native Edit/Write, fail-closed; `rename_symbol`/`safe_delete_symbol` ask y/n; `replace_in_files` stays excluded and denied). The project is auto-activated per session, so `activate_project` and `get_current_config` are not available; memory names containing `/` or `..` are denied. Serena writes do not pass `gateguard` or `pretool-auto-read`, and the other reference files of an approved rename are not inspected — read before you write, yourself. Before changing any Serena config (`~/.serena/serena_config.yml`, the `~/.claude.json` registration, hook matchers incl. `mcp__plugin_serena_serena__*`, rollout order), read `templates/serena_config.yml.template` and `docs/adr/0001-serena-write-gate.md`. A double install (`claude plugin list | grep -i serena` non-empty) starts two servers.

## Context7

Both connected Context7 servers (`context7-keyed` and the claude.ai connector) require BOTH `libraryName` and `query` on `resolve-library-id` (schemas checked 2026-11-10; they differed before). When a call fails with `-32602 invalid params`, load the current schema via ToolSearch instead of guessing a parameter name.

## Browser stacks

One stack per use-case, never mixed within a task (IMP-280): local pages and visual sign-off → the desktop app's built-in preview, where the session offers it; scripted click-tests by sub-agents → the Playwright plugin; pages that need the user's logged-in browser session → claude-in-chrome; Lighthouse, performance traces, network and console forensics → chrome-devtools.
