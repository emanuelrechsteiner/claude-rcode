<!--
Status: ACTIVE
Last Updated: 2026-10-12
Purpose: Dated record of the Haiku 5.5 model-era change (default worker moves from Sonnet to Haiku 5.5; coordinators by role), facts, measurement, decisions P1-P7, open owner decisions
-->

# Model-Era Review: Haiku 5.5 Default Worker (2026-10-12)

The previous review, `docs/model-era-review-2026-09-27.md` (IMP-220), describes the Haiku 4.5 / Sonnet 5 era and
keeps Sonnet as the default worker. On 2026-10-12 the owner decided that Haiku 5.5 (`claude-haiku-5-5`) is the
default worker model, with coordinators on Fable 5.1 or Opus 5.5. This record captures the facts, the measurement
and the decisions. It supersedes the worker-default statements of the 2026-09-27 review; its cost and thinking
findings remain valid except where section 4 states otherwise.

Labels used below: **given** = supplied to this record on 2026-10-12 with the source and date named;
**derived** = arithmetic on given values. Nothing here was re-fetched from the web for this record.

## 1. Sources

| # | Source | Date | Used for |
|---|---|---|---|
| S1 | https://code.claude.com/docs/en/model-config | fetched 2026-10-12 (given) | Alias resolution, provider table, default effort, adaptive reasoning |
| S2 | https://code.claude.com/docs/en/env-vars | fetched 2026-10-12 (given) | `CLAUDE_CODE_SUBAGENT_MODEL`, effort and thinking env vars |
| S3 | https://code.claude.com/docs/en/sub-agents | fetched 2026-10-12 (given; URL confirmed by the coordinator) | Sub-agent frontmatter `effort`, per-invocation `effort`, model resolution order |
| S4 | Anthropic API model reference, Claude Code bundled `claude-api` skill (no URL) | cached 2026-10-06 (given) | Haiku 5.5 / Sonnet 5.5 / Opus 5.5 / Fable 5.1 prices, context windows, Haiku 5.5 effort facts |
| S5 | `docs/model-era-review-2026-09-27.md` (this repo) | 2026-09-27 (repo file) | Previous-era prices and Haiku 4.5 facts |

## 2. Cost matrix and ratio (before / after)

Prices are USD per million tokens, input / output.

| Tier | Before: API id | Before: price | Before: context | After: API id | After: price | After: context |
|---|---|---|---|---|---|---|
| Haiku | `claude-haiku-4-5-20251001` | $1 / $5 (S5) | 200K (S5) | `claude-haiku-5-5` | $0.10 / $0.50 for prompts ≤100K; $0.50 / $2.50 above (S4) | 1M (S4) |
| Sonnet | `claude-sonnet-5` | $2 / $10 (S5) | 1M (S5) | `claude-sonnet-5-5` | $2 / $10 (S4) | 1M (S4) |
| Opus | `claude-opus-5-5` | $4 / $20 (S5) | 1M (S5) | `claude-opus-5-5` | $4 / $20 (S4) | 1M (S4) |
| Fable | `claude-fable-5-1` | $10 / $50 (S5) | 1M (S5) | `claude-fable-5-1` | $10 / $50 (S4) | 1M (S4) |

- **Ratio before** Haiku : Sonnet : Opus : Fable = **1 : 2 : 4 : 10**, input and output (S5, given).
- **Ratio after** = **1 : 20 : 40 : 100**, input and output, for prompts ≤100K tokens (derived from S4).
  - Haiku's relative cost against Sonnet moved from 1:2 to 1:20. This is the basis of the owner's "extremely cheap" directive.
- **Long-prompt caveat (derived):** above 100K tokens Haiku 5.5 costs $0.50 / $2.50. The Sonnet 5.5 and Opus 5.5
  long-prompt prices were not supplied, so the ratio above 100K **cannot be stated**.
- **Tokenizer:** the 2026-09-27 tokenizer caveat (S5) was not re-checked for Haiku 5.5 and is not restated.
- Alias ids changed: the Sonnet id in the new era is `claude-sonnet-5-5`, not `claude-sonnet-5`.

## 3. Alias resolution and provider caveat

Given from S1:

- "The `opus`, `sonnet`, and `haiku` aliases resolve to the newest version on the Anthropic API and to an earlier
  version on some other providers."
- Provider table: `haiku` maps to **Haiku 5.5 on the Anthropic API** and to **Haiku 4.5 on Claude Platform on AWS,
  Amazon Bedrock, Google Cloud Agent Platform and Microsoft Foundry**.
- To pin the model on those providers: `ANTHROPIC_DEFAULT_HAIKU_MODEL`.

Consequences recorded here:

- On the Anthropic API the short alias `haiku` is the policy value (P1). On the other four providers the same alias
  resolves to Haiku 4.5. Only the Anthropic API is in use in this installation (given; not re-verified).
- The 2026-09-21 measurement cited in an audit (section 7) predates Haiku 5.5 and shows only "newest version", not
  a pin to Haiku 4.5. It is not evidence of a pin.

## 4. Effort and thinking facts

Given from S1, S2, S3, S4:

| Fact | Source |
|---|---|
| Default effort is `high` on every model that supports effort, except Opus 5.5, Sonnet 5.5 and Haiku 5.5, which default to `medium`. | S1 |
| Haiku 5.5 effort levels: low / medium / high / xhigh / max; default medium. | S4 |
| Fable models, Sonnet 5 and later, Haiku 5.5, and Opus 4.7 and later always use adaptive reasoning. | S1 |
| `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` and the fixed thinking budget mode do not apply to those models. | S1 |
| Thinking cannot be turned off on Opus 5.5, Sonnet 5.5, Haiku 5.5 or the Fable models. | S1 |
| Claude Code ignores nonzero values on adaptive reasoning models (env-var wording, quoted in the 2026-09-27 review). | S5 |
| Sub-agent frontmatter `effort`: sets effort when the sub-agent is active; overrides the session level, **but not the `CLAUDE_CODE_EFFORT_LEVEL` environment variable**. | S3 |
| Per-invocation `effort` parameter requires Claude Code v2.1.292 or later. | S3 |
| `max` is not accepted in `modelSettings` or `effortLevel`. | S1/S2 (given) |
| Refusals have no server-side fallback on Haiku 5.5. | S4 |

Model resolution for sub-agents, in order (S3): (1) invocation `model` parameter, (2) frontmatter `model`,
(3) `CLAUDE_CODE_SUBAGENT_MODEL` (alias or full id), (4) the main conversation model.

Open facts (not answered by the given sources):

- The docs do **not** state whether `modelSettings` applies to sub-agents.
- `CLAUDE_CODE_EFFORT_LEVEL` is **not set** in this installation (given; checked in `settings.json` `env` on
  2026-10-12). The frontmatter `effort` values in P5 therefore take effect; if the variable is ever set, they do not.
- `MAX_THINKING_TOKENS=30000` is now **inert on every current tier**: Haiku 5.5 is adaptive too. The 2026-09-27 review
  noted Haiku 4.5 was the last tier where it acted. See open decision (e).

## 5. Baseline measurement (before the change)

Source: `~/.claude/global-observation/dispatch-capture.jsonl`, measured 2026-10-12 (given). Window start not supplied.

**Sub-agent dispatches by model, last 1,054 captured (given counts; shares derived):**

| Model | Dispatches | Share (derived) |
|---|---|---|
| sonnet | 575 | 54.6 % |
| opus | 203 | 19.3 % |
| unset | 230 | 21.8 % |
| inherit | 36 | 3.4 % |
| fable | 6 | 0.6 % |
| haiku | 4 | 0.4 % |
| **Total** | **1,054** | 100 % |

**Top agent types (given):** backend-agent 245; general-purpose 197; research-agent 105; ui-agent 100;
code-reviewer-agent 88; Explore 72; planning-agent 59.

**Frontmatter and routing before the change (given, 2026-10-12):**

| Surface | Count / value |
|---|---|
| Agents: model per frontmatter | 8 sonnet / 2 haiku / 1 opus / 1 fable (12 agents) |
| Skills: model per frontmatter | 9 sonnet / 11 haiku / 2 opus (22 skills) |
| Commands pinned to `claude-fable-5-1[1m]` | 17 |
| `settings.json` `env.CLAUDE_CODE_SUBAGENT_MODEL` | `sonnet` |
| Routines launched with | `--model sonnet` |

The 0.4 % haiku share is the number the 30-day recount in section 9 is measured against.

## 6. Decisions

Owner directive, verbatim (German, 2026-10-12):

> "Es gibt ein neues Modell von Haiku. Es ist Haiku 5.5. Es hat Efforts und ist extrem günstig. Ich will, dass es in vielen Fällen eingesetzt wird. […] TEam LEad läuft mit Fable 5.1 oder OPus 5.5 für komplexe und koordinierende Aufgaben. SIe spanwnen andere Agenten. HAiku 5.5 wir unser neues Gog To Modell. SOnnet nur noch, wenn Haiku das Problem nich lösen kann."

Translation for readers (not the verbatim text): "There is a new Haiku model, Haiku 5.5. It has efforts and is
extremely cheap. I want it used in many cases. […] Team Lead runs on Fable 5.1 or Opus 5.5 for complex and
coordinating tasks. They spawn other agents. Haiku 5.5 becomes our new go-to model. Sonnet only when Haiku cannot
solve the problem."

Policy as implemented (IMP-255):

| # | Decision | Detail |
|---|---|---|
| P1 | Worker default = `haiku` | Short alias kept everywhere. The Agent tool accepts only `haiku`, `sonnet`, `opus`, `fable`. |
| P2 | Sonnet for a worker only on a recorded Haiku failure | The same task class must fail its named check. Retry once at higher effort. Record the failure in the ledger, task list or agent log. Same rule applies up the ladder (Haiku → Sonnet → Opus → Fable). |
| P3 | Coordinators by role | `/team-lead`, command pins and control-agent = Fable 5.1 (Opus 5.5 permitted). planning-agent, project-planning and meta-observer = opus. Routine weekly-improve = opus. Routine daily-docs and nightly-observation = haiku. |
| P4 | Exception: visual-qa-agent stays `sonnet` | Owner rule of 2026-10-09 excludes Haiku from browser click-work. Owner decision pending (section 8a). |
| P5 | Effort in agent frontmatter | high: backend, testing, ui, code-reviewer, pattern-extractor, planning. medium: research, documentation, version-control. low: cleanup. |
| P6 | `CLAUDE_CODE_SUBAGENT_MODEL` → `haiku` | `modelSettings` effort for `claude-haiku-5-5` must be set in the live install via `/config`. It is a runtime key, pulled back into the workshop at deploy. |
| P7 | Stale-id regex extended | The audit-config check for stale model ids now matches `claude-(opus\|sonnet\|haiku)-(3\|4\|4-1\|4-5)-[0-9]{8}`. |

**Files changed for P1–P7** (repo-relative; the workshop branch `work/2026-10-12-haiku-55-default`):

| Decision | Files |
|---|---|
| P1, P2, P3 | `rules/api-cost-optimization.md`; `agents/control-agent.md` §2; `commands/team-lead.md`; `rules/parallel-by-default.md`; `CLAUDE.md` |
| P1, P5 (frontmatter) | 10 × `agents/*.md`; 14 × `skills/*/SKILL.md` |
| P1 (mirror tables) | `rcode/stages/design.md`, `rcode/stages/develop.md`, `rcode/stages/test.md`, `rcode/stages/launch.md` |
| Documentation of the policy | `docs/FRAMEWORK-REFERENCE.md` |
| P6 | `settings.json` (`env` block only); `scripts/routine-run.sh` (routine launch flag); `scripts/tests/routine-run-regression.sh` |
| P7 | `scripts/audit-config.sh` |
| Templates | `templates/command-contract.template`; `templates/commands/*.md` |
| Helper script | `skills/historical-signals-v2/scripts/cluster_prompts.py` |
| Ledger | `global-observation/improvement-ledger.json` |

Scope as given: agent, skill and command frontmatter; the `settings.json` env value; routine launch flags.
This list is the complete file set reported by the coordinator; it was not re-derived by this record.

## 7. Method note: the Haiku-run audit

The audit and the implementation were run by sub-agents on Haiku 5.5 (effort high / medium). This was the first
live test of the policy. Three read-only Haiku audits delivered line-verified tables. The lead caught two
misjudgments and one policy divergence.

**Right:**

- Line-verified tables: each claim cited a file and line, which made the lead's check cheap.

**Wrong:**

1. One audit claimed the `haiku` alias is pinned to Haiku 4.5, citing a 2026-09-21 measurement. Haiku 5.5 did not
   exist on that date, so the measurement shows only "newest version" (section 3).
2. The same audit saw a contradiction between the env floor and that measurement. The measurement ran with the
   env var unset (IMP-212), so no contradiction exists.
3. Two audits proposed keeping Sonnet for backend-agent, code-reviewer-agent and security-review voices on a
   "95 % accuracy" argument. No Haiku failure had been measured. The lead applied the owner's rule (P2) instead.

Lesson recorded for the method: an audit's measurement must be dated against the model era it describes, and a
quality argument without a recorded failure does not override P1.

## 8. Open owner decisions

- **(a) visual-qa-agent and browser work on Haiku.** Owner rule of 2026-10-09 excludes Haiku from browser click-work;
  P4 keeps `sonnet` until decided.
- **(b) `modelSettings` entry for `claude-haiku-5-5` via `/config`.** Needed for the effort level in P6. Runtime key;
  set in the live install, not in the workshop.
- **(c) Stage-alias commands and other coordinators: Fable 5.1 or Opus 5.5.** Opus 5.5 costs 40 % of Fable 5.1 per
  the given prices (derived: $4 / $10 on input, $20 / $50 on output, i.e. 40 % on both).
- **(d) Provider pin `ANTHROPIC_DEFAULT_HAIKU_MODEL`**, only if the policy is ever run outside the Anthropic API
  (section 3; four providers resolve `haiku` to Haiku 4.5).
- **(e) `MAX_THINKING_TOKENS=30000` is inert on every current tier.** Remove, or keep. Section 4: all tiers in use
  are adaptive. The 2026-09-27 review recommended keeping it; that recommendation predates Haiku 5.5.

## 9. Acceptance checklist (NEW session after deploy)

Nothing above is verified in a live session yet. The deploy is `claude-deploy config`; the new rules, hooks and
settings load only in a **new** session.

- [ ] Spawn one `general-purpose` agent **without** a `model` parameter. Read its model from the last line of
      `~/.claude/global-observation/dispatch-capture.jsonl`. Expected `haiku` (resolution step 3,
      `CLAUDE_CODE_SUBAGENT_MODEL`; inferred from section 4, not tested). The dispatch-specialist-check hook asks
      for a `general-purpose` dispatch unless an `AGENTENWAHL:` line is present.
- [ ] Spawn `backend-agent` **without** parameters. Confirm `haiku` in the capture log (resolution step 2, frontmatter).
- [ ] Run `bash ~/.claude/scripts/routine-run.sh --dry-run daily-docs` (usage pattern as in the script's header).
      Confirm `--model haiku` in the output.
- [ ] After 30 days, recount the dispatch model shares from `dispatch-capture.jsonl` and compare with the section 5
      baseline (haiku 0.4 %, sonnet 54.6 %, opus 19.3 %, unset 21.8 %). Record the window dates with the count.
- [ ] Each run leaves a run-log line (IMP-075) so an unfired routine is distinguishable from a silent one.
