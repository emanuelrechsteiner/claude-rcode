<!--
Status: ACTIVE
Last Updated: 2026-11-23
Purpose: Long form of the tool notes: MCP paths and selection, Serena, Context7, browser stacks and the native tool rules 7 and 8
-->

Long form of the tool notes: the former mcp-tool-usage rule and Rules 7 and 8 of the former tool-discipline rule (both removed on 2026-11-23; last texts in `docs/archive/rules-2026-11-23/`). Not loaded automatically.

# MCP Tool Usage Guidelines

> Patterns for using MCP tools correctly to prevent validation errors.

## Paths

Serena (`mcp__serena__*`) and MCP filesystem tools take paths RELATIVE to the project root; Claude's native Read/Edit/Write take ABSOLUTE paths. `Error: File does not exist` → check which convention the tool wants. MCP tools cannot write outside the project directory — use native `Write` there.

## Tool selection

Serena for symbol-aware work (`find_symbol`, `find_referencing_symbols`, `replace_symbol_body`, `rename_symbol`); `Grep` for text search; native Read/Write/Edit/Glob for everything else. The `claude-code` context excludes six Serena tools — `read_file`, `create_text_file`, `execute_shell_command`, `find_file`, `list_dir`, `search_for_pattern` — use Read, Write, Bash, Glob, Glob/`ls -la`, Grep instead. Array parameters take arrays, never a string (`["item"]`, not `"item"`).

## Serena

Project-relative paths (`{"name_path_pattern": "MyClass/myMethod", "relative_path": "src/file.ts"}`); parameter names drift upstream — load the current schema via ToolSearch before calling, never from memory. Writes pass `hooks/serena-write-gate.sh` (same inspectors as native Edit/Write, fail-closed; `rename_symbol`/`safe_delete_symbol` ask y/n; `replace_in_files` stays excluded and denied). The project is auto-activated per session, so `activate_project` and `get_current_config` are not available; memory names containing `/` or `..` are denied. Serena writes pass the Serena write gate only: read a file before you change it through Serena. The gate inspects the one definition file that a rename or a safe delete names; the other files that reference the symbol are not inspected, so read them yourself before you approve. Before changing any Serena config (`~/.serena/serena_config.yml`, the `~/.claude.json` registration, hook matchers incl. `mcp__plugin_serena_serena__*`, rollout order), read `templates/serena_config.yml.template` and `docs/adr/0001-serena-write-gate.md`. A double install (`claude plugin list | grep -i serena` non-empty) starts two servers.

## Context7

Both connected Context7 servers (`context7-keyed` and the claude.ai connector) require BOTH `libraryName` and `query` on `resolve-library-id` (schemas checked 2026-11-10; they differed before). When a call fails with `-32602 invalid params`, load the current schema via ToolSearch instead of guessing a parameter name.

## Browser stacks

One stack per use-case, never mixed within a task (IMP-280): local pages and visual sign-off → the desktop app's built-in preview, where the session offers it; scripted click-tests by sub-agents → the Playwright plugin; pages that need the user's logged-in browser session → claude-in-chrome; Lighthouse, performance traces, network and console forensics → chrome-devtools.

## Rule 7 — Announce target path before bulk file ops; resolve repo ambiguity

1. Before a bulk file operation (move/copy/mass-create across many files), state the target path in one line — "Ziel: `<absolute path>`" — before touching any file.
2. Afterward, check that no unintended duplicate tree was left behind.
3. When two or more repos/directories share a similar name, compare `mtime` and size across all candidates and state the choice + reason before starting — never just start in whichever one `Glob`/`ls` surfaced first.

## Rule 8 — Absolute paths over `cd` chains

Pass the full absolute path to each command as an argument (e.g. `git -C /abs/path/to/repo status`) instead of `cd`-ing first. `cd` is not forbidden — it stays legitimate where a tool genuinely requires the cwd (a foreign repo, a REPL, a build tool that resolves relative to cwd) — but it is not the reflex. Do not chain 2+ `cd`s in one command (`cd A && cd B && cmd`) — go to the final absolute path directly, or use `git -C`/tool-native path flags.
