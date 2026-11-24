# Tool Discipline Rules

> Hard rules on tool selection. Always loaded.

## Rule 1 — Read AND investigate before Edit or Write

Before calling `Edit` or `Write` on an existing file, ALWAYS call `Read` on that exact path first in the current conversation — no exceptions for "I know the file" or "I already saw it"; the tool enforces this. **Why:** insufficient investigation before edit turns every iteration into a preventable round-trip.

- Need to edit a file? `Read` it AND `Grep` for files that import it FIRST. A new file needs no prior Read. After the user edited a file manually, `Read` again — your cached view is stale.
- `hooks/pretool-auto-read.sh` blocks (exit 2) an Edit of a file not Read in this session; `hooks/gateguard.sh` adds a non-blocking note on an un-investigated first touch (Read + grep for importers/callers + verify the scope matches the user's instruction first) and passes a file already Read; `CLAUDE_GATEGUARD_OFF=1` silences the note.

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

**Skill exception:** Skills whose job is cross-project aggregation or transcript traversal (`memory-index`, `meta-observer`, `historical-signals*`) may declare `Bash(cat *)`, `Bash(head *)`, `Bash(tail *)`, `Bash(grep *)`, `Bash(find *)` in `allowed-tools`; no other skill may.

**This is a preference, not a floor-enforced rule (IMP-157):** the Auto-Mode reminder says the opposite (read with `cat`/`head`/`sed -n`) — say so, don't paper over it; when they conflict, prefer Read/Grep for large or repeatedly used files and a plain `cat`/`head` for a small one-off read. Do not switch tools reflexively.

## Rule 3 — Specify `subagent_type` on every Agent call

When calling the `Agent` tool, always specify `subagent_type`; never leave it unspecified. **Why:** specialized agents are sized correctly for their task, saving tokens and improving output quality (IMP-159). Decide which fits: `Explore` (codebase exploration, finding files) · `Plan` (implementation strategies) · `research-agent` (external API docs, best-practices research) · `backend-agent`, `testing-agent`, `ui-agent` (domain-specific implementation; UX work → `ux-design` skill) · `code-reviewer-agent` (read-only review) · `cleanup-agent` (dead code detection) · `general-purpose` **only** when no specialized agent fits AND the task genuinely spans multiple domains.

`Explore` writes no file and runs nothing that changes state, not even a scratch file or a test suite: a measurement that needs output files or a suite run goes to `testing-agent` or `backend-agent` (IMP-283).

### Enforcement: `hooks/dispatch-specialist-check.sh` (IMP-159)

PreToolUse on Task|Agent; a recoverable ask, not a block. It fires only when `subagent_type` is `general-purpose` or missing/empty. A line starting with `AGENTENWAHL:` (or `AGENT-RATIONALE:` / `BEGRÜNDUNG AGENTENWAHL:` / `BEGRUENDUNG AGENTENWAHL:`) with at least 15 characters that NAMES a specialist and says why it does not fit satisfies it (IMP-213); accepted names are every `agents/*.md` basename plus `Explore` and `Plan`. Without a valid rationale it asks; an identical retry of the same (type, prompt) pair passes, so a headless run cannot deadlock. From the 3rd granted general-purpose dispatch per session it asks regardless (`CLAUDE_DISPATCH_GP_MAX`, default 2; refused attempts do not consume the quota); opt-out `CLAUDE_DISPATCH_CHECK_OFF=1` (logged). Where no specialist genuinely fits (game-asset/level design, cross-cutting repo inventories), a one-line rationale is the intended resolution, not a formality.

## Rule 4 — Parallel when independent, sequential when dependent

Fire multiple tool calls in a single message when they have no data dependency and failure of one doesn't invalidate the others (e.g. reading 3 unrelated files); fire sequentially when call B needs the result of call A (e.g. `Glob` → `Read`). **Why:** parallel calls cut wall-clock time and context overhead.

## Rule 5 — Absolute paths for native tools; project-relative for MCP

`Read`, `Edit`, `Write` take **absolute paths** (they reject relative); `mcp__filesystem__*`, `mcp__serena__*` take **project-relative paths** (`src/file.ts`; they reject absolute outside the project). Details: `rules/mcp-tool-usage.md`.

## Rule 6 — Don't reread files you just wrote

After `Edit` or `Write` succeeds, don't `Read` the file back "to verify" — a failed write would have errored; it wastes context. **Exception:** Read if the user is likely to have modified the file since your write.

## Rule 7 — Announce target path before bulk file ops; resolve repo ambiguity

1. Before a bulk file operation (move/copy/mass-create across many files), state the target path in one line — "Ziel: `<absolute path>`" — before touching any file.
2. Afterward, check that no unintended duplicate tree was left behind.
3. When two or more repos/directories share a similar name, compare `mtime` and size across all candidates and state the choice + reason before starting — never just start in whichever one `Glob`/`ls` surfaced first.

## Rule 8 — Absolute paths over `cd` chains

Pass the full absolute path to each command as an argument (e.g. `git -C /abs/path/to/repo status`) instead of `cd`-ing first. `cd` is not forbidden — it stays legitimate where a tool genuinely requires the cwd (a foreign repo, a REPL, a build tool that resolves relative to cwd) — but it is not the reflex. Do not chain 2+ `cd`s in one command (`cd A && cd B && cmd`) — go to the final absolute path directly, or use `git -C`/tool-native path flags.
