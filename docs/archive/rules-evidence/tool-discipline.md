<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Belege, Vorfälle und Messungen, die am 2026-09-24 (IMP-217) wörtlich aus rules/tool-discipline.md ausgelagert wurden — die Regel selbst bleibt dort; hier steht das „Warum" in voller Länge.
-->
# Belege zu `rules/tool-discipline.md`

> Ausgelagert 2026-09-24 (IMP-217). Jeder Block steht unter der Überschrift, unter der er in der Regel stand, und ist unverändert übernommen.

## Tool Discipline Rules (Einleitungszeile unter dem Titel)

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

**Rationale:** 3× wrong target path / accidental parallel tree within two weeks (2026-08-04, 2026-08-09, 2026-08-16). One case (META, 2026-08-02) started work in a legacy repo (`example-legacy-repo`, 1,298 lines) instead of the current one (14,229 lines, ~11× larger) — both trees existed on disk under near-identical names, and neither `mtime` nor size was checked before starting.

## Rule 8 — Absolute paths over `cd` chains

**Rationale:** August 2026 chat analysis: 416 `cd` commands — **28% of all Bash invocations** — 124 of them chained (`cd X && cd Y && …`), with 8 documented approval-friction incidents. `cd` chains are also the mechanism behind IMP-162's largest single error class (66 "File does not exist" errors over 37 sessions, see the Bauhof/Haus path-canon note now printed at session start): every `cd` forces the agent to recompute the next command's path relative to wherever the chain left it, and the two-roots split (Bauhof `/Volumes/YourExternalVolume/.../claude-code-config` vs. Haus `~/.claude`) is exactly the kind of mental path arithmetic that goes wrong under that pressure.
