# Tool Discipline Rules

> Hard rules on tool selection. Always loaded.

## Rule 1 — Read AND investigate before Edit or Write

Before calling `Edit` or `Write` on an existing file, ALWAYS call `Read` on that exact path first in the current conversation. No exceptions for "I know the file" or "I already saw it" — the tool enforces this.

**Why:** insufficient investigation before edit turns every iteration into a preventable round-trip.

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

**Why:** Dedicated tools have better permissions, caching, and error handling. The system prompt says this explicitly; this rule is the reinforcement.

**Exceptions (Bash is correct here):**
- `Bash(wc -l file)` — line counting (no dedicated tool)
- `Bash(du -sh dir/)` — size reporting
- `Bash(stat -f %m file)` — file metadata
- `Bash(git ...)` — all git operations
- `Bash(jq ...)` — JSON processing (Grep/Glob can't do this)
- `Bash(xargs ...)` — piping list operations
- Process management (`kill`, `ps`, `lsof`, background processes)

**Skill exception:** Skills whose explicit job is cross-project aggregation, historical-signal extraction, or transcript-traversal MAY declare `Bash(cat *)`, `Bash(head *)`, `Bash(tail *)`, `Bash(grep *)`, `Bash(find *)` in their `allowed-tools`. Read/Grep/Glob do not scale across the 35+ memory dirs + JSONL archive trees these skills work on. Currently scoped exemption: `memory-index`, `meta-observer`, `historical-signals*`. Any other skill claiming these patterns is a policy violation.

**This is a PREFERENCE, not a floor-enforced rule (corrected IMP-157, 2026-08-24).** Enforcing it at the CRITICAL floor of `guard-unsafe.sh` (per `rules/agency-bands.md`, reserved for host destruction / exfiltration / irreversible damage) is a category error: a file read is none of those, and enforcing a tool-style preference at the safety floor makes the floor something to route around rather than respect. The block arm on bare `cat`/`head`/non-follow `tail` is **removed**; `hooks/read-tool-preference-advisory.sh` (PreToolUse on Bash) gives a single non-blocking note per session instead, and never prevents the command from running.

**The conflict this rule has with the framework's own Auto-Mode reminder is real, not hypothetical — say so, don't paper over it.** Auto Mode's system reminder instructs the opposite of this rule: "read files with cat, head, or sed -n ... rather than using the dedicated Read tool." Both instructions are live in the same session. When they conflict, prefer whichever is cheaper for the situation at hand — Read/Grep for large files or files you'll touch more than once (better caching, bounded reads via `limit`/`offset`), plain `cat`/`head`/`sed -n` where Auto Mode's bash-first posture is already in effect and the read is small and one-off. Neither is a hard rule; do not treat a hit from the advisory note as something to "fix" by switching tools reflexively.

## Rule 3 — Specify `subagent_type` on every Agent call

When calling the `Agent` tool, always specify `subagent_type`. Never leave it unspecified.

**Why:** Specialized agents are sized correctly for their task, saving tokens and improving output quality. Prose alone has not moved the `general-purpose` rate (IMP-159) — hence the enforcement layer below.

**How to apply:** Before calling Agent, decide which subagent fits:
- `Explore` — codebase exploration, finding files
- `Plan` — designing implementation strategies
- `research-agent` — external API docs, best-practices research
- `backend-agent`, `testing-agent`, `ui-agent` — domain-specific implementation (UX work → `ux-design` skill; ux-agent archived 2026-05-27)
- `code-reviewer-agent` — read-only review
- `cleanup-agent` — dead code detection
- `general-purpose` — use **only** when no specialized agent fits AND task genuinely spans multiple domains

### Enforcement layer: `dispatch-specialist-check.sh` (IMP-159, 2026-08-24)

A PreToolUse hook on `Task|Agent` now backs this rule with a **recoverable ask, not a hard block** — the user's explicit decision: the rule cannot always tell a genuine no-specialist-fits case (see "Honest exception" below) from reflexive `general-purpose` use, so it asks for a one-line rationale instead of refusing the dispatch.

- Fires only when `subagent_type` is `general-purpose` or missing/empty. Named specialists pass silently.
- To satisfy it, start (or include) a line in the Task prompt with one of these markers, case-insensitive, followed by ≥15 characters of reason:
  `AGENTENWAHL: <reason>` · `AGENT-RATIONALE: <reason>` · `BEGRÜNDUNG AGENTENWAHL: <reason>` (also accepted without the umlaut: `BEGRUENDUNG AGENTENWAHL:`).
- Without a rationale, the hook returns `permissionDecision:"ask"` naming the measured `general-purpose` rate and the current specialist roster (read live from `agents/*.md` at hook-run time, so this list cannot drift out of sync with the doc above). An identical retry of the same (subagent_type, prompt) pair within the same session passes silently the second time, so an unattended/headless run cannot deadlock on an unanswerable prompt.
- **The rationale must NAME a specialist and reject it (IMP-213, 2026-09-21).** Rule 3 permits `general-purpose` *only when no specialist fits* — that is a claim **about** the specialists, so it has to name at least one of them and say why it does not fit. A line that merely asserts "no specialist covers this" without naming one is refused with an ask. Accepted names: every `agents/*.md` basename plus the built-ins `Explore` and `Plan` (legitimate alternatives to weigh, even though they have no definition file).
- **From the 3rd GRANTED `general-purpose` dispatch per session, the hook asks regardless of the rationale (IMP-213).** Threshold `CLAUDE_DISPATCH_GP_MAX` (default 2). Past that point the individual dispatch is no longer the question — a *series* of `general-purpose` spawns is nearly always a skipped decomposition rather than a series of genuine exceptions. **Refused attempts do not consume the quota**; only granted ones do.
- Opt-out: `CLAUDE_DISPATCH_CHECK_OFF=1` (logged).
- Log: `~/.claude/global-observation/dispatch-specialist.log` — decision, subagent_type, rationale_present, prompt_len, `gp_count`, and `rationale_snippet` (the rationale line only, ≤200 chars). The snippet is a **deliberate, bounded exception** to the "no prompt text in logs" principle of `dispatch-capture.sh`: without it, only the *presence* of a rationale is measurable, never its substance. Regression: `hooks/tests/dispatch-specialist-regression.sh` (21 assertions).

**Honest exception — the rationale is a legitimate answer, not a workaround to close:** some work genuinely has no matching specialist today — game-asset/level design, cross-cutting repo inventories, and similar tasks that don't fit `backend-agent`/`ui-agent`/`testing-agent`/etc. The hook exists to make that judgment call *visible and logged*, not to force a specialist dispatch where none fits. A one-line `AGENTENWAHL:` naming the real reason is the intended, complete resolution for those cases — it is not a formality to route around.

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

## Rule 7 — Announce target path before bulk file ops; resolve repo ambiguity

Before a bulk file operation (move/copy/mass-create across many files), state the target path in one line before executing, and check for an unintended duplicate afterward. When two or more repos or directories share the same or a similar name, compare `mtime` and size/line-count across the candidates before choosing, and state the choice with the reason — never just start in whichever one `Glob`/`ls` surfaced first.

**How to apply:**
1. Before a move/copy/mass-create spanning many files: one line — "Ziel: `<absolute path>`" — before touching any file.
2. After the operation: check that no unintended duplicate tree was left behind.
3. If multiple candidate directories/repos share the same or a similar name: compare `mtime` (`Bash(stat -f %m ...)`) and size (`Bash(wc -l ...)` / `Bash(du -sh ...)`) across all candidates, and name the choice + why before starting work in either.

## Rule 8 — Absolute paths over `cd` chains

Prefer passing the full absolute path to each command over `cd`-ing into a directory first. `cd` is not forbidden, but it should not be the reflex.

**Why:** every `cd` forces the agent to recompute the next command's path relative to wherever the chain left it, and the two-roots split (workshop `<BAUHOF>` vs. live install `~/.claude`) is exactly the kind of mental path arithmetic that goes wrong under that pressure (IMP-162).

**How to apply:**
- Default: `git -C /abs/path/to/repo status`, `Read(file_path="/abs/path/...")`, `python3 /abs/path/script.py` — carry the absolute path as an argument, not as an ambient `cd`.
- `cd` remains legitimate where a tool genuinely requires it (some git operations inside a foreign/unrelated repo, an interactive REPL, a build tool that only resolves relative to cwd) — the point is deliberate use, not the reflexive `cd` opening a command chain.
- Do not chain 2+ `cd`s in one command (`cd A && cd B && cmd`) — go to the final absolute path directly, or use `git -C`/tool-native path flags.

## Verification

This rule's effectiveness should be measured by:
- 30-day count of `"File has not been read yet"` errors → target <5 (baseline 50)
- 30-day count of `Bash(cat|grep|find ...)` failures → target <10 (baseline ~65)
- 30-day count of `Agent` calls with `subagent_type: unspecified` → target <5 (baseline 65)

These metrics can be pulled from `signals.jsonl` + session JSONL archives once IMP-014 (observation hook fidelity) ships.

> Evidence and incident history (moved verbatim, IMP-217): `docs/archive/rules-evidence/tool-discipline.md`
