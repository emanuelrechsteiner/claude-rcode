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

## Serena: writes go through the delegating gate (IMP-130, 2026-08-05)

Serena runs as a regular MCP server — tools are `mcp__serena__*`.

> **Correction 2026-08-15.** This paragraph used to add "**not** the old plugin prefix
> `mcp__plugin_serena_serena__*`". That was false on the author's machine: the plugin
> `serena@claude-plugins-official` was still installed AND still `true` in
> `settings.json.enabledPlugins`, so **every session started two Serena servers** —
> one with `--context claude-code` (22 tools) and one without (28 tools, i.e. the six
> the context deliberately excludes, `execute_shell_command` among them). The gate
> refused that tool when tested (`permissionDecision: deny`), so nothing was breached;
> the door was simply built. Both copies are gone now (plugin uninstalled, key removed).
> Keep the plugin prefix in the hook matchers regardless — belt and suspenders costs
> nothing, and a re-install would otherwise land unguarded. **Check with
> `claude plugin list | grep -i serena` (must be empty), never with a doc.**

History: from 2026-07-17 to 2026-08-05
ALL Serena writing tools were globally excluded ("read-only by design", IMP-104/105)
because the `settings.json` hook matchers bind to tool NAMES (`Write|Edit`) — no
`mcp__serena__*` name matches, so Serena edits bypassed all 10 Write|Edit hooks,
including `security-audit.sh` (secret blocking) and `observation-capture.sh`
(the signals.jsonl pipeline).

**Superseded by the delegating gate** (`docs/adr/0001-serena-write-gate.md`):

- **`hooks/serena-write-gate.sh`** (PreToolUse, matcher `mcp__serena__.*|mcp__plugin_serena_serena__.*`)
  translates each Serena write call into the native `(file_path, new_string)` shape
  and delegates to the SAME inspectors the native path runs — `parallel-lock-check`,
  `file-protection`, `security-audit`, then `config-protection` (its recoverable
  `ask` deliberately last). **FAIL-CLOSED**: unknown tool suffix, missing contract
  param (upstream param-name drift), unparseable stdin, or a missing inspector
  script → deny, never allow. This answers IMP-104's fail-open objection instead
  of ignoring it. No bypass env var exists.
- **`hooks/serena-post-tool.sh`** (PostToolUse, same matcher) feeds the native
  post-edit chain (`auto-format`, `post-edit-validate` with propagated findings,
  `observation-capture` → signals.jsonl) and records Serena READS with an explicit
  `relative_path` into the read tracker, so a later native `Edit` passes
  `pretool-auto-read`.
- Regression: `hooks/tests/serena-gate-regression.sh` (37 cases, incl.
  secret-through-the-Serena-door → block, and gate-without-inspectors → deny).

**Special cases:** `rename_symbol` / `safe_delete_symbol` are reference-aware —
the LSP writes N reference files the call never names; the gate forwards a
recoverable **ask** instead of silently allowing (the per-file inspectors saw only
the definition file). `replace_in_files` (multi-file, no mappable single path)
stays excluded AND gate-denied. Memory names with `/` or `..` (incl. Serena's
`global/` prefix) are denied — path-escape from `.serena/memories/`.

**1. The `claude-code` context** still excludes 6 tools that duplicate native ones:

| Excluded Serena tool | Use instead |
|---|---|
| `read_file` | `Read` |
| `create_text_file` | `Write` |
| `execute_shell_command` | `Bash` |
| `find_file` | `Glob` |
| `list_dir` | `Glob` / `Bash(ls -la)` |
| `search_for_pattern` | `Grep` |

**2. `excluded_tools` in `~/.serena/serena_config.yml`** now removes only
`replace_in_files` (belt + suspenders with the gate's deny).

**Known residual gaps (documented, not hidden):** `gateguard.sh` /
`pretool-auto-read.sh` (read-before-edit) and `controller-first-mutation-gate.sh`
are NOT delegated — Serena's symbolic workflow reads symbols before editing by
construction; revisit if the gate log shows abuse. The N−1 reference files of an
approved `rename_symbol` are not individually inspected or logged.

**Rollout order is load-bearing:** deploy the gate to `~/.claude` FIRST
(`claude-deploy config` + new session), only THEN shorten `excluded_tools` in
`~/.serena/serena_config.yml`. The reverse order runs write tools unprotected for
a session.

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

## Project auto-activation via `--project .` (2026-08-15)

The user-scope registration in `~/.claude.json` now ends in `--context claude-code
--project .`. Claude Code starts the MCP server with **cwd = the session's project
directory** (measured via `lsof` on live processes), and Serena resolves a relative
path against that cwd (`ProjectType.convert` → `Path(value).resolve()`), so the dot
pins nothing — each session activates its own project. Log proof: `Activating
<project> at <path>`.

**Consequence you must know:** the `claude-code` context sets `single_project: true`,
so with a fixed project Serena drops two tools (`SingleProjectExclusions`):
`activate_project` (no mid-session project switching) and `get_current_config`.
This supersedes the earlier deliberate "no `--project` flag" rule, which bought
project mobility at the price of activating by hand at every single session start.
Reverting is one edit: drop `"--project", "."` from the args.

> **Verification traps** (each cost us a wrong conclusion): `serena tools list` shows
> DEFAULT tools, not effective ones — and `get_current_config` is **no longer available**
> since `--project` was added, so the current check is to spawn a server and read
> `~/.serena/logs/<date>/`:
> `serena start-mcp-server --context claude-code --project . </dev/null`.
> `serena project is_ignored_path` reports "IS NOT ignored" for any NON-EXISTENT path —
> always test with a real file. And a doc claiming a plugin is disabled is **not**
> evidence that it is — verify with `claude plugin list`, which is what the 2026-08-15
> double-installation finding turned on.

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

### mcp__serena__replace_content — RE-ENABLED behind the gate (2026-08-05)

Excluded 2026-07-17 → re-enabled per IMP-130: every Serena writing tool now runs
through `serena-write-gate.sh`, which delegates to the same protection hooks the
native path triggers — see "Serena: writes go through the delegating gate" above.
`replace_in_files` remains the one permanently excluded writer (multi-file).

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
