# Tool Discipline Rules

> Hard rules on tool selection. Always loaded.

## Rule 1 — Read AND investigate before Edit or Write

Before calling `Edit` or `Write` on an existing file, ALWAYS call `Read` on that exact path first in the current conversation — no exceptions for "I know the file" or "I already saw it"; the tool enforces this. **Why:** insufficient investigation before edit turns every iteration into a preventable round-trip.

- Need to edit a file? `Read` it AND `Grep` for files that import it FIRST. A new file needs no prior Read. After the user edited a file manually, `Read` again — your cached view is stale.
- `pretool-auto-read.sh` blocks an Edit of a file not Read in this session; `gateguard.sh` answers the FIRST Edit/Write touch of a file per session with JSON-deny "investigate first: Read + grep for importers/callers + verify scope matches user's instruction" — the second attempt is allowed. Bypass gateguard for known-safe mechanical edits: `CLAUDE_GATEGUARD_OFF=1`.

## Rule 2 — Never use Bash for file reads, searches, or listings

These Bash patterns are **forbidden**; the dedicated tool has better permissions, caching, and error handling:

| ❌ Bash Pattern | ✅ Use Instead |
|---|---|
| `cat file.txt` | `Read` (absolute path) |
| `head -20 file` | `Read(limit=20)` |
| `tail -50 file` | `Read(offset=<total-50>)` |
| `grep pattern file` | `Grep(pattern, path)` |
| `grep -r pattern dir/` | `Grep(path="dir/", output_mode="files_with_matches")` |
| `find . -name "*.ts"` | `Glob(pattern="**/*.ts")` |
| `ls src/` | `Glob(pattern="src/*")`; `Bash(ls -la src/)` OK only for metadata (size, mtime, perms) |
| `echo "content" > file` | `Write` |
| `sed -i 's/a/b/g' file` | `Edit(old_string="a", new_string="b", replace_all=true)` |

**Bash is correct for:** `wc -l` (line counting), `du -sh` (size), `stat -f %m` (file metadata), `git ...`, `jq ...` (JSON), `xargs ...` (list piping), process management (`kill`, `ps`, `lsof`, background processes).

**Skill exception:** skills whose explicit job is cross-project aggregation, historical-signal extraction, or transcript-traversal MAY declare `Bash(cat *)`, `Bash(head *)`, `Bash(tail *)`, `Bash(grep *)`, `Bash(find *)` in their `allowed-tools`. Currently scoped: `memory-index`, `meta-observer`, `historical-signals*`; any other skill claiming these patterns is a policy violation.

**This is a PREFERENCE, not a floor-enforced rule (IMP-157):** a file read is no host destruction / exfiltration / irreversible damage, so `guard-unsafe.sh` does not block it; `hooks/read-tool-preference-advisory.sh` gives one non-blocking note per session and never prevents the command. The framework's Auto-Mode reminder instructs the opposite (read with `cat`/`head`/`sed -n` rather than the Read tool) in the same session — say so, don't paper over it. When they conflict, prefer the cheaper path: Read/Grep for large files or files you'll touch more than once (better caching, bounded reads via `limit`/`offset`); plain `cat`/`head`/`sed -n` for a small one-off read where Auto Mode's bash-first posture is in effect. Neither is a hard rule; do not "fix" an advisory-note hit by switching tools reflexively.

## Rule 3 — Specify `subagent_type` on every Agent call

When calling the `Agent` tool, always specify `subagent_type`; never leave it unspecified. **Why:** specialized agents are sized correctly for their task, saving tokens and improving output quality (IMP-159). Decide which fits: `Explore` (codebase exploration, finding files) · `Plan` (implementation strategies) · `research-agent` (external API docs, best-practices research) · `backend-agent`, `testing-agent`, `ui-agent` (domain-specific implementation; UX work → `ux-design` skill) · `code-reviewer-agent` (read-only review) · `cleanup-agent` (dead code detection) · `general-purpose` **only** when no specialized agent fits AND the task genuinely spans multiple domains.

### Enforcement layer: `dispatch-specialist-check.sh` (IMP-159)

A PreToolUse hook on `Task|Agent`; a **recoverable ask, not a hard block** (the user's decision).

- Fires only when `subagent_type` is `general-purpose` or missing/empty; named specialists pass silently.
- To satisfy it, start (or include) a line in the Task prompt with a marker, case-insensitive, followed by ≥15 characters of reason: `AGENTENWAHL: <reason>` · `AGENT-RATIONALE: <reason>` · `BEGRÜNDUNG AGENTENWAHL: <reason>` (also `BEGRUENDUNG AGENTENWAHL:`).
- **The rationale must NAME a specialist and say why it does not fit (IMP-213)** — "only when no specialist fits" is a claim about the specialists; a line that merely asserts "no specialist covers this" is refused with an ask. Accepted names: every `agents/*.md` basename plus the built-ins `Explore` and `Plan`.
- Without a valid rationale it asks (`permissionDecision:"ask"`); an identical retry of the same (subagent_type, prompt) pair in the same session passes silently, so a headless run cannot deadlock.
- **From the 3rd GRANTED `general-purpose` dispatch per session it asks regardless of the rationale (IMP-213)** — a series of them is nearly always a skipped decomposition. Threshold `CLAUDE_DISPATCH_GP_MAX` (default 2); **refused attempts do not consume the quota**.
- Opt-out: `CLAUDE_DISPATCH_CHECK_OFF=1` (logged). Log: `~/.claude/global-observation/dispatch-specialist.log`; regression: `hooks/tests/dispatch-specialist-regression.sh`.

**Honest exception:** where no specialist genuinely fits (game-asset/level design, cross-cutting repo inventories, and similar), a one-line `AGENTENWAHL:` naming the real reason is the intended, complete resolution, not a formality to route around — the hook makes that call visible and logged; it does not force a specialist where none fits.

## Rule 4 — Parallel when independent, sequential when dependent

Fire multiple tool calls in a single message when they have no data dependency and failure of one doesn't invalidate the others (e.g. reading 3 unrelated files); fire sequentially when call B needs the result of call A (e.g. `Glob` → `Read`). **Why:** parallel calls cut wall-clock time and context overhead.

## Rule 5 — Absolute paths for native tools; project-relative for MCP

`Read`, `Edit`, `Write` take **absolute paths** (they reject relative); `mcp__filesystem__*`, `mcp__serena__*` take **project-relative paths** (`src/file.ts`; they reject absolute outside the project). Details: `rules/mcp-tool-usage.md`.

## Rule 6 — Don't reread files you just wrote

After `Edit` or `Write` succeeds, don't `Read` the file back "to verify" — a failed write would have errored; it wastes context. **Exception:** Read if the user is likely to have modified the file since your write.

## Rule 7 — Announce target path before bulk file ops; resolve repo ambiguity

1. Before a bulk file operation (move/copy/mass-create across many files), state the target path in one line — "Ziel: `<absolute path>`" — before touching any file.
2. Afterward, check that no unintended duplicate tree was left behind.
3. When two or more repos/directories share the same or a similar name, compare `mtime` (`Bash(stat -f %m ...)`) and size (`Bash(wc -l ...)` / `Bash(du -sh ...)`) across all candidates and state the choice + reason before starting — never just start in whichever one `Glob`/`ls` surfaced first.

## Rule 8 — Absolute paths over `cd` chains

Pass the full absolute path to each command as an argument (e.g. `git -C /abs/path/to/repo status`) instead of `cd`-ing first. `cd` is not forbidden, but not the reflex: it stays legitimate where a tool genuinely requires it (some git operations inside a foreign/unrelated repo, an interactive REPL, a build tool that only resolves relative to cwd). Do not chain 2+ `cd`s in one command (`cd A && cd B && cmd`) — go to the final absolute path directly, or use `git -C`/tool-native path flags. **Why:** every `cd` forces recomputing the next command's path, and the workshop vs. live-install split is where that arithmetic goes wrong (IMP-162).
