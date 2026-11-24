# API Cost Optimization Rules

> Model-selection heuristics for Anthropic API calls. Always loaded.

## Model era (Claude 5.x, 2026-10)

Tiers, cheapest → most capable: Haiku 5.5 → Sonnet 5.5 → Opus 5.5 → Fable 5.2 (API ids `claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`, `claude-fable-5-2`; the Agent tool's `model` parameter takes only the aliases `haiku`, `sonnet`, `opus`, `fable`). Price ratio about 1:20:40:100 (reference cached 2026-10-06 for Fable 5.1; Fable 5.2 pricing not reviewed yet); 1M window on all tiers; Haiku 5.5 runs adaptive thinking that `MAX_THINKING_TOKENS` cannot bound. Verify current pricing, cache TTL and cache-write premiums at docs.claude.com/pricing before any batch job. Facts and history: `docs/model-era-review-2026-10-12.md`.

## Haiku-first default

Every worker sub-agent starts on `haiku`, with its effort stated explicitly (Haiku defaults to `medium`); the task's named check decides whether the output stands. Classification, extraction, formatting, drafting, code edits, tests and review all start there.

## Model-selection matrix

Use when choosing a tier; it is the Model axis of `~/.claude/agents/control-agent.md` §2.

| Tier | Role | Typical input and complexity |
|---|---|---|
| `haiku` | default for every worker: classification, extraction, formatting, drafting, code edits, tests, review | up to 100K tokens at the cheapest rate; the named check decides |
| `sonnet` | worker only after a recorded Haiku failure on that task class | reasoning-heavy drafting or code where Haiku failed its named check |
| `opus` | coordinator for complex multi-spawn work, cross-file architecture, planning | 50K+ tokens, multi-doc synthesis, must-be-right decisions |
| `fable` | team lead for the hardest coordination and `/meta`-style meta-analysis | whole-framework corpora; where Opus has demonstrably fallen short |

## When to escalate a worker

Haiku → Sonnet → Opus → Fable only on recorded evidence, all three: (1) the same task class failed its named check on the lower tier — record check, spawn and failing output; (2) it was retried once at a higher effort and still failed; (3) the failure is recorded where a later reader finds it (ledger, task list or agent log).

## Coordinators by role, never by escalation

`/team-lead` and the other command pins run the `fable` alias (resolves to Fable 5.2, probed 2026-11-10; Opus 5.5 permitted): a command pin sets the model of the main turn, and only the main agent coordinates on that tier. Every agent definition falls back to `haiku`, `control-agent`, `planning-agent` and `visual-qa-agent` included (owner decision 2026-11-11): a spawned agent starts on the worker tier and moves up only under the escalation rule above. `project-planning` and `meta-observer` run Opus 5.5.

## Cost heuristic

Total cost = (input + output tokens) × N_turns × price per token; a cheaper model that needs more turns can cost more. For agent loops Haiku stays the default; a loop that fails its named check is the recorded-failure case above, not a reason to start on Sonnet. Cap retries at 2 with exponential backoff; a failure that repeats on Haiku is an escalation case, not a retry loop.

## Cache discipline

Every model switch flushes the prompt cache (hits cost 0.1× base input or less): plan and execute in separate sessions with the plan passed as a file; one model per session class (worker Haiku, coordinator Fable/Opus); keep a steady cadence (5-minute TTL). Enable prompt caching for repeated work over stable context (long system prompts, retrieved docs). KPI: 80–90 % cache-hit rate; below that the session pattern is the problem, not the model choice.

When writing AI-powered code: default the worker tier to Haiku, assign coordinator tiers by role, and log the model per call for cost attribution.

Ledger: IMP-011, IMP-080, IMP-220, IMP-255.
