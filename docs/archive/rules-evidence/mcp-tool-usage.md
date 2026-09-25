<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Belege, Vorfälle und Messungen, die am 2026-09-24 (IMP-217) wörtlich aus rules/mcp-tool-usage.md ausgelagert wurden — die Regel selbst bleibt dort; hier steht das „Warum" in voller Länge.
-->
# Belege zu `rules/mcp-tool-usage.md`

> Ausgelagert 2026-09-24 (IMP-217). Jeder Block steht unter der Überschrift, unter der er in der Regel stand, und ist unverändert übernommen.

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
