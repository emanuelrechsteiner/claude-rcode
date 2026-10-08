<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/mcp-tool-usage.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/mcp-tool-usage.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Serena: writes go through the delegating gate (IMP-130, 2026-08-05)

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

## Project auto-activation via `--project .` (2026-08-15)

The user-scope registration in `~/.claude.json` now ends in `--context claude-code
--project .`. Claude Code starts the MCP server with **cwd = the session's project
directory** (measured via `lsof` on live processes), and Serena resolves a relative
path against that cwd (`ProjectType.convert` → `Path(value).resolve()`), so the dot
pins nothing — each session activates its own project. Log proof: `Activating
<project> at <path>`.

This supersedes the earlier deliberate "no `--project` flag" rule, which bought
project mobility at the price of activating by hand at every single session start.

> …verify with `claude plugin list`, which is what the 2026-08-15
> double-installation finding turned on.

## Moved from the rule on 2026-09-29 (IMP-234)

> Moved out verbatim while the rule was condensed to its normative core. The rule now states each of these once (path-convention table, one parameter-format example per tool, the error strings inline); the original blocks are kept here.

### Project Boundary Restrictions

MCP tools cannot write outside project directory:

```
❌ Cannot create file outside of the project directory
   got relative_path='/Users/.../.claude/plans/...'
```

**Solution:** Use Claude's native `Write` tool for files outside project.

### Error Prevention Checklist

Before using MCP tools:

- [ ] **Path format** - Using relative for MCP, absolute for native?
- [ ] **Array parameters** - Using arrays where required (paths, edits)?
- [ ] **Required fields** - All required parameters provided?
- [ ] **Project boundary** - File within project directory?
- [ ] **Read first** - Read file before editing (for native Edit)?

### Common Error Patterns

#### Pattern 1: Wrong path format
```
Error: File does not exist
```
→ Check if using relative vs absolute correctly for the tool

#### Pattern 2: Wrong parameter type
```
Invalid input: expected array, received string
```
→ Wrap single items in arrays: `["item"]` not `"item"`

#### Pattern 3: Missing required parameter
```
The required parameter `old_string` is missing
```
→ You're using wrong tool (MCP vs native) or missing fields

#### Pattern 4: Path outside project
```
AssertionError - Cannot create file outside of project directory
```
→ Use Claude's native Write tool for external files

### Common Parameter Formats — the ❌ examples and the second Context7 example (verbatim)

#### mcp__filesystem__read_multiple_files

**Wrong:**
```json
{
  "paths": "file1.ts"  // ❌ String instead of array
}
```

#### mcp__filesystem__edit_file

**Wrong:**
```json
{
  "path": "/absolute/path/file.ts",
  "edits": "find this -> replace with"  // ❌ String instead of array
}
```

#### Context7 resolve-library-id parameter names

**Correct (the other server):**
```json
{ "query": "react" }
```
