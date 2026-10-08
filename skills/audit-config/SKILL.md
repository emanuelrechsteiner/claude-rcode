---
name: audit-config
description: Run a deterministic audit of ~/.claude configuration against known schema-drift patterns (invalid settings fields, stale model IDs, broken hook patterns, naming collisions). Triggers on "audit config", "check config", "verify configuration", "config audit", "konfiguration prüfen", "audit my claude setup", "config check", or quarterly via launchd. Reports CRITICAL/WARN findings to ~/.claude/audit-reports/.
allowed-tools: Bash(bash ~/.claude/scripts/audit-config.sh), Bash(bash ~/.claude/scripts/command-contract-lint.sh), Bash(bash ~/.claude/scripts/config-security-audit.sh *), Read, Glob
---

# Audit-Config Skill

Runs `~/.claude/scripts/audit-config.sh` and surfaces the findings to the conversation. The script encodes every drift pattern discovered during past audits and is the deterministic gate that complements deeper Claude-driven analysis.

## What gets checked

The script audits five layers of the Claude Code config against official docs at https://code.claude.com/docs/en/:

1. **`settings.json`** — invalid top-level fields, deprecated fields (`voiceEnabled`, `includeCoAuthoredBy`), malformed permission rules (pipe-alternation in `Bash()`, `Task(*)` as tool), hook double-registration, matcher `"*"` on Stop/SubagentStop.

2. **`agents/*.md`** — invalid tool names (`TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`, `ExitPlanMode`, `NotebookEdit`), non-schema frontmatter fields (`permissionMode`, `skills`, `hooks` at top level), stale dated model IDs, missing required `name`/`description`.

3. **`commands/*.md`** — naming collisions with bundled commands (`review`, `init`, `code-review`, `security-review`, `compact`, `model`, `verify`, `run`, `loop`, `schedule`, etc.), stale model IDs, **plus a fixed call to `scripts/command-contract-lint.sh`** (IMP-089 closed-loop wiring, 2026-07-15) — checks the `controller-contract:v1` marker, its `exempt="<reason>"` attribute, the three mandatory preamble lines (Controller-First / Model×Effort-per-§2 / Second-order-checkpoints), stale rule/agent refs, and that every `**X-agent**` mention resolves to a real `agents/X-agent.md`. Failures fold into this report as WARN findings prefixed `command-contract-lint:`.

4. **`skills/*/SKILL.md`** — stale model IDs, legacy frontmatter (`triggers:`, `category:`, `mode:`, `context: forked`), wrong field name (`tools:` instead of `allowed-tools:`), name regex compliance.

5. **`hooks/*.sh`** — silently-broken pattern (using `$1` without stdin-cat fallback because Claude Code does NOT substitute `$tool_name` / `$file_path` etc.), bogus var substitutions in settings.json hook commands.

## Usage

### Run the audit

```!
bash ~/.claude/scripts/audit-config.sh
```

`audit-config.sh` already invokes `command-contract-lint.sh` internally as a fixed check (see §3 above) — its findings are folded into the same report. To run the command-contract linter standalone (e.g. while iterating on a single command file):

```!
bash ~/.claude/scripts/command-contract-lint.sh
```

### Read the latest report

The script outputs to `~/.claude/audit-reports/audit-YYYY-MM-DD.md`. List recent reports:

```!
ls -t ~/.claude/audit-reports/audit-*.md | head -5
```

## After running

If the script finds CRITICAL issues:
1. Read the latest report from `~/.claude/audit-reports/`
2. For each CRITICAL finding, apply the suggested fix
3. Re-run the audit to confirm clean state
4. Commit fixes with message like `chore(config): fix audit findings YYYY-MM-DD`

If only WARN findings: review at your convenience. Non-blocking.

## Security pass

`scripts/config-security-audit.sh [--root <dir>] [--live] [--json] [--report] [--allow <file>]` is a read-only, offline static security audit (IMP-244), separate from the schema audit above. Run it quarterly together with `audit-config.sh`, and before enabling any new MCP server or hook. Default root is the repo containing the script; `--live` audits `~/.claude` (and MCP servers in `~/.claude.json`); `--report` is the only write (`~/.claude/audit-reports/config-security-<date>.md`).

- Rules `CSA-NNN`: 001/002 broad `permissions.allow` (`Bash(*)`, bare `Bash`/`Write`/`Edit`, `Bash(sudo:*)`...), `bypassPermissions`, `skipDangerousModePermissionPrompt` (settings, settings.local, settings.framework); 010-014 hook files and bodies (missing, world-writable, `eval`, network without a localhost-only URL, `base64 -d | sh`; every file under `hooks/`); 020-022 MCP definitions (`npx -y`, `@latest`/unpinned, literal env secrets); 030 hidden Unicode (CRITICAL, file:line:col), 031 instruction-shaped HTML comments (only strict `Status:`/`Last Updated:`/`controller-contract:` lines are exempt), 032 BOM, 033 file could not be scanned; 040 cloned repo shipping its own `.mcp.json`/`.claude/settings*.json`; 050/051 invalid settings JSON (CRITICAL).
- Exceptions: `scripts/config-security-audit.allow`, one `rule-id<TAB>pattern<TAB>reason` per line. `Bash(*)` ships pre-listed (offset by guard-unsafe / excessive-agency-gate, see `rules/agency-bands.md`). Suppressed findings stay visible as `SUPPRESSED` with their reason.
- Exit codes: 0 no CRITICAL, 1 CRITICAL found, 2 usage/internal error.
- Heuristics (hook-body and comment-verb matches are line regexes) can false-positive on pattern strings; each message says so. Regression: `bash scripts/tests/config-security-audit-regression.sh`.

## Schedule

This skill is also invoked quarterly via launchd:
- Jan 1, Apr 1, Jul 1, Oct 1 at 03:00 local time
- Job: `com.user.claude-audit` (placeholder — rename to `com.<yourdomain>.claude-audit` for your machine; see `scripts/com.user.claude-audit.plist.template`)
- Logs: `~/.claude/audit-reports/launchd.{stdout,stderr}.log`

Check next-fire time:
```bash
launchctl list | grep claude-audit
```

## Extending the script

When you discover a NEW drift pattern (e.g. another deprecated field, another naming collision class), add a check to `~/.claude/scripts/audit-config.sh`. The script is intentionally bash + jq + grep so it remains fast and dependency-free — runs in <1 second even with 35+ skills.

For drift patterns that need LLM judgment (e.g. "is this description still accurate?"), don't try to encode in bash — instead spawn a Claude session with the report as context.
