<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Evidence, incidents, and measurements moved verbatim out of rules/tool-discipline.md on 2026-09-24 (IMP-217) — the rule itself stays there; this file carries the full-length "why".
-->
# Evidence for `rules/tool-discipline.md`

> Moved out 2026-09-24 (IMP-217). Every block sits under the same heading it had in the rule, and is carried over unchanged.

## Tool Discipline Rules (intro line under the title)

> Hard rules on tool selection. Derived from 30-day session audit (2026-04-20): 50 Edit-before-Read failures + 57 Bash(cat) failures + Bash(find/grep) anti-patterns. Always loaded.

## Rule 1 — Read AND investigate before Edit or Write

**Rationale:** 50 `"File has not been read yet. Read it first before writing to it."` errors over 30 days + 23 files edited 3+ times per day (signals.jsonl, 2026-05) = insufficient investigation before edit. Every iteration was a preventable round-trip.

## Rule 2 — Never use Bash for file reads, searches, or listings

**Rationale:** 57 `Bash(cat ...)` failures + multiple `Bash(find ...)` / `Bash(grep ...)` failures in the 30-day window. Dedicated tools have better permissions, caching, and error handling. The system prompt says this explicitly; this rule is the reinforcement.

**This is a PREFERENCE, not a floor-enforced rule (corrected IMP-157, 2026-08-24).** `guard-unsafe.sh` used to hard-block bare `cat`/`head`/non-follow `tail` at the CRITICAL floor (per `rules/agency-bands.md`, reserved for host destruction / exfiltration / irreversible damage). That was a category error: a file read is none of those, and enforcing a tool-style preference at the safety floor makes the floor something to route around rather than respect. Measured cost: 9 confirmed false blocks across 8 sessions over two months, incl. blocking a sub-agent from reading its own task output in the session scratchpad. The block arm is **removed**; `hooks/read-tool-preference-advisory.sh` (PreToolUse on Bash) now gives a single non-blocking note per session instead, and never prevents the command from running.

## Rule 3 — Specify `subagent_type` on every Agent call

**Rationale:** 65 of 259 Agent calls (25%) over 30 days used the default `general-purpose` subagent (2026-04-20 baseline). Specialized agents are sized correctly for their task, saving tokens and improving output quality.

**Rule broken by its own target, not fixed (IMP-159, chat-corpus analysis, Aug 2026, 296 coding transcripts):** the general-purpose rate has RISEN to 43.5–45.9% since this rule was written — the 25% baseline was the *floor*, not a ceiling that got enforced. `control-agent` itself was dispatched via `subagent_type` **zero** times across 123 framework sessions. A same-day comparison (2026-08-09) makes the cost concrete: one project dispatched 14/16 Task calls to named specialists → 12/12 issues closed, 101 green tests, no escalation; another dispatched 11/11 to `general-purpose` with symptom-titled prompts → an escalation day, traced in the transcript to a subagent with no defined acceptance criterion substituting its own judgment for an explicit user instruction. Prose alone did not move this number in either direction.

### Enforcement layer: `dispatch-specialist-check.sh` (IMP-159, 2026-08-24)

- **From the 3rd GRANTED `general-purpose` dispatch per session, the hook asks regardless of the rationale (IMP-213).** Threshold `CLAUDE_DISPATCH_GP_MAX` (default 2). Past that point the individual dispatch is no longer the question — a *series* of `general-purpose` spawns is nearly always a skipped decomposition rather than a series of genuine exceptions. **Refused attempts do not consume the quota**; only granted ones do (the first build counted attempts, which let two refusals burn the whole quota before the first legitimate dispatch — caught by the regression suite, not by reading the code).
- Log: `~/.claude/global-observation/dispatch-specialist.log` — decision, subagent_type, rationale_present, prompt_len, `gp_count`, and `rationale_snippet` (the rationale line only, ≤200 chars). The snippet is a **deliberate, bounded exception** to the "no prompt text in logs" principle of `dispatch-capture.sh`: without it, only the *presence* of a rationale is measurable, never its substance — which is exactly why the 2026-08/09 formality gap was invisible for four weeks. Regression: `hooks/tests/dispatch-specialist-regression.sh` (21 assertions).

**Measured reason for the IMP-213 tightening.** Over 2026-08-24..09-21 the gate saw 60 `general-purpose` dispatches and waved **57 of them through on marker presence alone**; only 3 ever produced an ask. The rule text already said "only when no specialist fits" verbatim — restating it is the one intervention this rule has already documented as ineffective ("Prose alone did not move this number in either direction"). The gap was never the wording; it was that the gate checked *whether* something was written, never *what*.

## Rule 7 — Announce target path before bulk file ops; resolve repo ambiguity

**Rationale:** 3× wrong target path / accidental parallel tree within two weeks (2026-08-04, 2026-08-09, 2026-08-16). One case (META, 2026-08-02) started work in a legacy repo (`acct-cd22fb`, 1,298 lines) instead of the current one (14,229 lines, ~11× larger) — both trees existed on disk under near-identical names, and neither `mtime` nor size was checked before starting.

## Rule 8 — Absolute paths over `cd` chains

**Rationale:** August 2026 chat analysis: 416 `cd` commands — **28% of all Bash invocations** — 124 of them chained (`cd X && cd Y && …`), with 8 documented approval-friction incidents. `cd` chains are also the mechanism behind IMP-162's largest single error class (66 "File does not exist" errors over 37 sessions, see the workshop/live-install path-canon note now printed at session start): every `cd` forces the agent to recompute the next command's path relative to wherever the chain left it, and the two-roots split (workshop `<WORKSHOP>` vs. live install `~/.claude`) is exactly the kind of mental path arithmetic that goes wrong under that pressure.

## Moved from the rule on 2026-09-29 (IMP-234)

> Condensing round IMP-234 (instruction files under 150k chars). The passages below were shortened or removed in `rules/tool-discipline.md`; each is carried over verbatim from the rule as it stood before that round, under the heading it had there. The normative content stays in the rule; what lives only here is rationale, hook internals, history, and extra examples.

### Rule 1 — Read AND investigate before Edit or Write

**Layered enforcement (2026-05-26):**
- `pretool-auto-read.sh` (PreToolUse hook): blocks Edit if file wasn't Read in this session
- `gateguard.sh` (PreToolUse hook, Layer 1): on the FIRST Edit/Write touch of a file per session, returns JSON-deny with "investigate first: Read + grep for importers/callers + verify scope matches user's instruction" — second attempt allowed

**How to apply:**
- Need to edit `/path/file.ts`? → `Read('/path/file.ts')` AND `Grep` for files that import it FIRST
- Creating a new file? → `Write` is fine without prior Read (file doesn't exist yet, gateguard bypasses)
- Modifying a file after the user just edited it manually? → `Read` again — your cached view is stale
- Bypass gateguard for known-safe mechanical edits: set `CLAUDE_GATEGUARD_OFF=1`

### Rule 2 — Never use Bash for file reads, searches, or listings

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

### Rule 3 — Specify `subagent_type` on every Agent call

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

- Without a rationale, the hook returns `permissionDecision:"ask"` naming the measured `general-purpose` rate and the current specialist roster (read live from `agents/*.md` at hook-run time, so this list cannot drift out of sync with the doc above). An identical retry of the same (subagent_type, prompt) pair within the same session passes silently the second time, so an unattended/headless run cannot deadlock on an unanswerable prompt.
- **From the 3rd GRANTED `general-purpose` dispatch per session, the hook asks regardless of the rationale (IMP-213).** Threshold `CLAUDE_DISPATCH_GP_MAX` (default 2). Past that point the individual dispatch is no longer the question — a *series* of `general-purpose` spawns is nearly always a skipped decomposition rather than a series of genuine exceptions. **Refused attempts do not consume the quota**; only granted ones do.
- Log: `~/.claude/global-observation/dispatch-specialist.log` — decision, subagent_type, rationale_present, prompt_len, `gp_count`, and `rationale_snippet` (the rationale line only, ≤200 chars). The snippet is a **deliberate, bounded exception** to the "no prompt text in logs" principle of `dispatch-capture.sh`: without it, only the *presence* of a rationale is measurable, never its substance. Regression: `hooks/tests/dispatch-specialist-regression.sh` (21 assertions).

**Honest exception — the rationale is a legitimate answer, not a workaround to close:** some work genuinely has no matching specialist today — game-asset/level design, cross-cutting repo inventories, and similar tasks that don't fit `backend-agent`/`ui-agent`/`testing-agent`/etc. The hook exists to make that judgment call *visible and logged*, not to force a specialist dispatch where none fits. A one-line `AGENTENWAHL:` naming the real reason is the intended, complete resolution for those cases — it is not a formality to route around.

### Rule 4 — Parallel when independent, sequential when dependent

- Example: Reading 3 unrelated files, launching 2 Explore agents on different areas

**Rationale:** Parallel tool calls reduce wall-clock time and context overhead. The system prompt already encourages this; this rule is the checklist.

### Rule 5 — Absolute paths for native tools; project-relative for MCP

- `Read`, `Edit`, `Write` — **absolute paths** (`/Users/.../file.ts`). Native tools reject relative.
- `mcp__filesystem__*`, `mcp__serena__*` — **project-relative paths** (`src/file.ts`). MCP tools reject absolute outside project.

Already documented in `rules/mcp-tool-usage.md` — this rule references it for completeness.

### Rule 7 — Announce target path before bulk file ops; resolve repo ambiguity

Before a bulk file operation (move/copy/mass-create across many files), state the target path in one line before executing, and check for an unintended duplicate afterward. When two or more repos or directories share the same or a similar name, compare `mtime` and size/line-count across the candidates before choosing, and state the choice with the reason — never just start in whichever one `Glob`/`ls` surfaced first.

### Rule 8 — Absolute paths over `cd` chains

**Why:** every `cd` forces the agent to recompute the next command's path relative to wherever the chain left it, and the two-roots split (workshop `<BAUHOF>` vs. live install `~/.claude`) is exactly the kind of mental path arithmetic that goes wrong under that pressure (IMP-162).

**How to apply:**
- Default: `git -C /abs/path/to/repo status`, `Read(file_path="/abs/path/...")`, `python3 /abs/path/script.py` — carry the absolute path as an argument, not as an ambient `cd`.
- `cd` remains legitimate where a tool genuinely requires it (some git operations inside a foreign/unrelated repo, an interactive REPL, a build tool that only resolves relative to cwd) — the point is deliberate use, not the reflexive `cd` opening a command chain.

### Verification

This rule's effectiveness should be measured by:
- 30-day count of `"File has not been read yet"` errors → target <5 (baseline 50)
- 30-day count of `Bash(cat|grep|find ...)` failures → target <10 (baseline ~65)
- 30-day count of `Agent` calls with `subagent_type: unspecified` → target <5 (baseline 65)

These metrics can be pulled from `signals.jsonl` + session JSONL archives once IMP-014 (observation hook fidelity) ships.

### Second pass — `## Verification` section (first-pass wording)

KPIs (30-day counts from `signals.jsonl` + session JSONL archives, once IMP-014 ships): `"File has not been read yet"` errors <5 (baseline 50); `Bash(cat|grep|find ...)` failures <10 (baseline ~65); `Agent` calls with `subagent_type: unspecified` <5 (baseline 65).
