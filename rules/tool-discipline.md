# Tool Discipline Rules

> Hard rules on tool selection. Derived from 30-day session audit (2026-04-20): 50 Edit-before-Read failures + 57 Bash(cat) failures + Bash(find/grep) anti-patterns. Always loaded.

## Rule 1 — Read AND investigate before Edit or Write

Before calling `Edit` or `Write` on an existing file, ALWAYS call `Read` on that exact path first in the current conversation. No exceptions for "I know the file" or "I already saw it" — the tool enforces this.

**Rationale:** 50 `"File has not been read yet. Read it first before writing to it."` errors over 30 days + 23 files edited 3+ times per day (signals.jsonl, 2026-05) = insufficient investigation before edit. Every iteration was a preventable round-trip.

**Layered enforcement (2026-05-26):**
- `pretool-auto-read.sh` (PreToolUse hook): blocks Edit if file wasn't Read in this session
- `gateguard.sh` (PreToolUse hook, Layer 1): on the FIRST Edit/Write touch of a file per session, returns JSON-deny with "investigate first: Read + grep for importers/callers + verify scope matches user's instruction" — second attempt allowed

**How to apply:**
- Need to edit `/path/file.ts`? → `Read('/path/file.ts')` AND `Grep` for files that import it FIRST
- Creating a new file? → `Write` is fine without prior Read (file doesn't exist yet, gateguard bypasses)
- Modifying a file after the user just edited it manually? → `Read` again — your cached view is stale
- Bypass gateguard for known-safe mechanical edits: set `CLAUDE_GATEGUARD_OFF=1`

## Rule 2 — Never use Bash for file reads, searches, or listings

The following Bash patterns are **forbidden**. Use the dedicated tool instead:

| ❌ Bash Pattern | ✅ Use Instead |
|-----------------|---------------|
| `cat file.txt` | `Read(file_path="/abs/path/file.txt")` |
| `head -20 file` | `Read(file_path="...", limit=20)` |
| `tail -50 file` | `Read(file_path="...", offset=<total-50>)` |
| `grep pattern file` | `Grep(pattern="...", path="...")` |
| `grep -r pattern dir/` | `Grep(pattern="...", path="dir/", output_mode="files_with_matches")` |
| `find . -name "*.ts"` | `Glob(pattern="**/*.ts")` |
| `ls src/` | `Glob(pattern="src/*")` for files; `Bash(ls -la src/)` OK only for metadata (size, mtime, perms) |
| `echo "content" > file` | `Write(file_path="...", content="...")` |
| `sed -i 's/a/b/g' file` | `Edit(file_path="...", old_string="a", new_string="b", replace_all=true)` |

**Rationale:** 57 `Bash(cat ...)` failures + multiple `Bash(find ...)` / `Bash(grep ...)` failures in the 30-day window. Dedicated tools have better permissions, caching, and error handling. The system prompt says this explicitly; this rule is the reinforcement.

**Exceptions (Bash is correct here):**
- `Bash(wc -l file)` — line counting (no dedicated tool)
- `Bash(du -sh dir/)` — size reporting
- `Bash(stat -f %m file)` — file metadata
- `Bash(git ...)` — all git operations
- `Bash(jq ...)` — JSON processing (Grep/Glob can't do this)
- `Bash(xargs ...)` — piping list operations
- Process management (`kill`, `ps`, `lsof`, background processes)

**Skill exception:** Skills whose explicit job is cross-project aggregation, historical-signal extraction, or transcript-traversal MAY declare `Bash(cat *)`, `Bash(head *)`, `Bash(tail *)`, `Bash(grep *)`, `Bash(find *)` in their `allowed-tools`. Read/Grep/Glob do not scale across the 35+ memory dirs + JSONL archive trees these skills work on. Currently scoped exemption: `memory-index`, `meta-observer`, `historical-signals*`. Any other skill claiming these patterns is a policy violation.

## Rule 3 — Specify `subagent_type` on every Agent call

When calling the `Agent` tool, always specify `subagent_type`. Never leave it unspecified.

**Rationale:** 65 of 259 Agent calls (25%) over 30 days used the default `general-purpose` subagent. Specialized agents are sized correctly for their task, saving tokens and improving output quality.

**How to apply:** Before calling Agent, decide which subagent fits:
- `Explore` — codebase exploration, finding files
- `Plan` — designing implementation strategies
- `research-agent` — external API docs, best-practices research
- `backend-agent`, `testing-agent`, `ui-agent` — domain-specific implementation (UX work → `ux-design` skill; ux-agent archived 2026-05-27)
- `code-reviewer-agent` — read-only review
- `cleanup-agent` — dead code detection
- `general-purpose` — use **only** when no specialized agent fits AND task genuinely spans multiple domains

## Rule 4 — Parallel when independent, sequential when dependent

Fire multiple tool calls in a single message when:
- They have no data dependency on each other
- Failure of one doesn't invalidate the others
- Example: Reading 3 unrelated files, launching 2 Explore agents on different areas

Fire sequentially when:
- Call B needs the result of call A
- Example: `Glob` → then `Read` on matched paths

**Rationale:** Parallel tool calls reduce wall-clock time and context overhead. The system prompt already encourages this; this rule is the checklist.

## Rule 5 — Absolute paths for native tools; project-relative for MCP

- `Read`, `Edit`, `Write` — **absolute paths** (`/Users/.../file.ts`). Native tools reject relative.
- `mcp__filesystem__*`, `mcp__serena__*` — **project-relative paths** (`src/file.ts`). MCP tools reject absolute outside project.

Already documented in `rules/mcp-tool-usage.md` — this rule references it for completeness.

## Rule 6 — Don't reread files you just wrote

After `Edit` or `Write` succeeds, the tool's error would have told you if the write failed. Don't `Read` the same file back "to verify." Wastes context.

**Exception:** If the user is likely to have modified the file between your Write and next action, Read is appropriate.

## Verification

This rule's effectiveness should be measured by:
- 30-day count of `"File has not been read yet"` errors → target <5 (baseline 50)
- 30-day count of `Bash(cat|grep|find ...)` failures → target <10 (baseline ~65)
- 30-day count of `Agent` calls with `subagent_type: unspecified` → target <5 (baseline 65)

These metrics can be pulled from `signals.jsonl` + session JSONL archives once IMP-014 (observation hook fidelity) ships.
