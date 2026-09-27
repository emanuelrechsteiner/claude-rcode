<!--
Status: ACTIVE
Last Updated: 2026-09-27
Purpose: Four-point model-era review (IMP-080 trigger) for the Claude 5.x family, done as IMP-220
-->

# Model-Era Review: Claude 5.x (2026-09-27, IMP-220)

The runtime is `claude-opus-5-5[1m]` (`settings.json` `model`), and `rules/api-cost-optimization.md`
still named Opus 4.8 / Fable 5. This note covers the four points of the "Model-Era Review Trigger
(IMP-080)" in `skills/meta-observer/SKILL.md`. It is the evidence behind the rule edit; the rule itself
stays short.

## Sources (fetched 2026-09-27)

Every number below is copied from these pages. None comes from memory.

| Source | URL |
|---|---|
| Pricing | https://platform.claude.com/docs/en/about-claude/pricing (`docs.claude.com/en/docs/about-claude/pricing` 302-redirects here) |
| Models overview | https://platform.claude.com/docs/en/about-claude/models/overview (redirects from `docs.claude.com`) |
| Claude Code env vars | https://code.claude.com/docs/en/env-vars |
| Claude Code model config | https://code.claude.com/docs/en/model-config |

## 1. Cost matrix and escalation ladder

Base prices per million tokens (Pricing, "Model pricing" table):

| Model | API id | Input | 5m cache write | 1h cache write | Cache hit | Output | Context window |
|---|---|---|---|---|---|---|---|
| Haiku 4.5 | `claude-haiku-4-5-20251001` | $1 | $1.25 | $2 | $0.10 | $5 | 200K |
| Sonnet 5 | `claude-sonnet-5` | $2 | $2.50 | $4 | $0.20 | $10 | 1M |
| Opus 5.5 | `claude-opus-5-5` | $4 | $5 | $8 | $0.20 | $20 | 1M |
| Fable 5.1 | `claude-fable-5-1` | $10 | $12.50 | $20 | $0.25 | $50 | 1M |

- **Tier ratio:** Haiku : Sonnet : Opus : Fable = **1 : 2 : 4 : 10**, the same for input and output.
  - Opus 5.5 costs 2× Sonnet 5. Fable 5.1 costs 5× Sonnet 5 and 2.5× Opus 5.5.
- **Changes since the Opus 4.8 era:**
  - Opus 5.5 is cheaper than Opus 4.8 ($4/$20 vs $5/$25).
  - Sonnet 5's $2/$10 is now the standard price; the planned rise to $3/$15 on 2026-09-01 was cancelled (Pricing, footnote 3).
- **Tokenizer caveat:** Pricing says "Claude 4.7 and later models … use a newer tokenizer … approximately 30%
  more tokens for the same text", and "Claude Sonnet 4.6 and earlier models use the previous tokenizer".
  - Haiku 4.5 predates 4.7. Per task, the Haiku↔Sonnet gap is therefore somewhat wider than 1:2.
  - Whether Haiku 4.5 uses the old tokenizer is an inference from the version order. The page does not name Haiku 4.5 explicitly.
- **Escalation ladder:** Haiku → Sonnet → Opus → Fable is unchanged in shape. The rule now names Haiku 4.5 → Sonnet 5 → Opus 5.5 → Fable 5.1.
- **Mythos:** Mythos 5.1 is listed as "limited availability" (Project Glasswing, invitation only) and is not in use here, so it was dropped from the tier line.
- **Divergence worth a human decision (not changed):** Models overview says "start with Claude Opus 5.5 for most workloads".
  - The rule's anti-pattern "Top-tier-for-everything" still makes Sonnet 5 the default.
  - Opus is now only 2× Sonnet, which weakens the cost side of that anti-pattern.
  - The rule's framing was kept because changing the default dispatch policy is out of scope for a model-era review.

## 2. `MAX_THINKING_TOKENS=30000`

- **Finding:** the variable is **inert for 3 of the 4 tiers**. Claude Code env vars says: "Claude Code ignores
  nonzero values on adaptive reasoning models". Model config says: "Fable models, Sonnet 5, and Opus 4.7 and later
  always use adaptive reasoning. The fixed thinking budget mode and `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` don't
  apply to them."
  - Models overview lists thinking as "Adaptive (always on)" for Fable 5.1 and Opus 5.5, "Adaptive" for Sonnet 5, and "Extended" for Haiku 4.5.
- **Where it still acts:** only on Haiku 4.5, which uses extended thinking with a fixed budget. Claude Code caps the value at one token below max output (Haiku 4.5 max output 64K), so 30000 is valid there.
- **The real control now is effort:** `effortLevel` / `/effort` / `CLAUDE_CODE_EFFORT_LEVEL`. Model config says Opus 5.5 defaults to `medium`, and other effort-capable models default to `high`.
- **Verdict:** keep the value; it is harmless and still bounds Haiku subagents. The *justification* in CLAUDE.md is stale, because the line reads as a global thinking cap. See the recommendations below.

## 3. `context-engineering.md` ceilings vs. the 1M windows

- **Confirm-only for the percentages.** The rule is already window-relative:
  - soft 50%, hard 75–80%, never the auto-compact margin
  - on a 1M window: soft ≈ 500K, hard ≈ 750–800K tokens
- **One precision gap.** Model config says models with a native 1M window, including "Opus 4.7 and later on the Anthropic API", compact "at about 967K tokens by default".
  - Env vars says `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` sets "the percentage (1-100) of the auto-compact window", "can't raise the threshold", and applies "only in sessions that compact before the model's context limit" (1M sessions do).
  - So `90` means about 90% of ~967K ≈ 870K tokens, about 87% of the 1M window. That figure is my arithmetic from the two quoted statements, not a documented number.
  - The rule's "90% margin" label is close enough to keep. It is not exactly 90% of the window.
- **Haiku 4.5** has a 200K window, so the rule's historical 200K worked example still applies to it.
- **Not verified:** whether the `[1m]` suffix in `claude-opus-5-5[1m]` still does anything on the Anthropic API.
  - Model config says `sonnet[1m]` has "no effect" when Sonnet 5 is native 1M, and that Opus 4.7+ runs 1M natively there.
  - The docs do not say the same for `opus[1m]`. Left as-is.

## 4. Cache TTL and write premiums

Pricing, "Prompt caching" table:

- **5-minute write:** 1.25× base input, valid 5 minutes. The rule's 5-min TTL is **confirmed**, and it is still the default.
- **1-hour write:** 2× base input, valid 1 hour. The rule did not mention this; it now says "1h optional".
- **Cache read:** 0.1× base input, except 0.05× on Opus 5.5 and 0.025× on Fable 5.1 (and Mythos 5.1).
- **Corrected in the rule:** "80–90% cost reduction" understated the read discount. It now says:
  - a hit costs 0.1× base input (0.05× Opus 5.5, 0.025× Fable 5.1)
  - "a read costs ≤10% of base input"
- **Unchanged:** the model-switch flush mechanics and the "cache hit rate 80–90%" KPI. The KPI is a hit-rate target, not a price claim.
- **Long context:** "Claude 4.6 and later models … include the full 1M token context window at standard pricing". There is no >200K premium for any of the four tiers in use.

## Recommendations for files not edited here

1. **CLAUDE.md "Token Optimization".** Reword `MAX_THINKING_TOKENS=30000` so it does not read as a global cap. Suggested text: "`MAX_THINKING_TOKENS=30000` bounds only Haiku 4.5 (fixed-budget thinking); Sonnet 5 / Opus 5.5 / Fable 5.1 use adaptive thinking and ignore it, so effort (`effortLevel`) is the control."
   - The same line says "auto-compact at 90% … reaching 92% is treated as a process failure". That contradicts `context-engineering.md`, which treats reaching the 90% margin as the failure. Align it to 90%.
   - Watch the 150k budget: the rewrite should replace text, not add to it.
2. **`settings.json` env.** No change required.
   - `MAX_THINKING_TOKENS` is harmless; removing it would let Haiku use Claude Code's default cap. Keep it unless the user wants Haiku thinking unbounded.
   - `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90` still takes effect on 1M sessions (≈870K).
   - `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` is consistent with the rule's Sonnet default.
   - If the user adopts Anthropic's "Opus 5.5 for most workloads", this is the value to revisit.
3. **`rules/context-engineering.md`.** Optional one-line precision: the 90% margin is 90% of the auto-compact window (~967K by default on 1M models ≈ 870K tokens), not of the full window. The thresholds need no numeric change. This must be budget-neutral.

## Verification

- `grep -cE 'Opus 4\.8|Fable 5\b' rules/api-cost-optimization.md` → **6 before, still 6 after**. The KPI regex is flawed: `\b` matches between `5` and `.`, so every "Fable 5.1" counts.
- Correct KPI: `grep -cE 'Opus 4\.8|Fable 5([^.0-9]|$)' rules/api-cost-optimization.md` → **6 at HEAD, 0 after this edit**.
- `wc -m rules/api-cost-optimization.md`: 8435 → 8416.
- Pricing source date: 2026-09-27 (fetched from the pricing URL above).
