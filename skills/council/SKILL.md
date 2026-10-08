---
name: council
description: Four-voice council (Architect, Skeptic, Pragmatist, Critic) for ambiguous decisions and go/no-go calls, using fresh-context sub-agents against anchoring. Use when several paths are credible. Triggers on "council", "second opinions", "go or no-go", "devil's advocate".
disable-model-invocation: true
---

<!--
Adapted from affaan-m/ECC skills/council @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# Council

Four advisors look at one decision from different angles:

- the in-context voice (Architect), which is you
- a Skeptic sub-agent
- a Pragmatist sub-agent
- a Critic sub-agent

For decision-making under ambiguity. Not for code review, implementation planning, or architecture design. Manual-only (`/council`): it spawns three sub-agents, so it should run when asked for, not on a keyword match.

## When to Use

- A decision has several credible paths and no obvious winner
- The tradeoffs need to be made explicit
- The user asks for second opinions, dissent, or multiple perspectives
- Conversational anchoring is a real risk
- A go/no-go call would benefit from adversarial challenge

Examples: monorepo vs polyrepo, ship now vs hold for polish, feature flag vs full rollout, narrow scope vs keep strategic breadth.

## When not to use

| Instead of a council | Use |
|---|---|
| One decision, user should resolve it step by step | `grilling` |
| Checking whether output is correct | `code-reviewer-agent`, or the adversarial counter-check in `slop-prevention` |
| Breaking a feature into steps | `planning-agent`, `project-planning` |
| Designing a system architecture | `planning-agent` |
| Reviewing code for bugs or security | `code-reviewer-agent`, `quality-review` |
| A straight factual question | answer directly |
| An obvious execution task | do the task |

## Roles

| Voice | Lens |
|---|---|
| Architect (you) | correctness, maintainability, long-term implications |
| Skeptic | premise challenge, simplification, assumption breaking |
| Pragmatist | shipping speed, user impact, operational reality |
| Critic | edge cases, downside risk, failure modes |

The three external voices run as fresh sub-agents that receive only the question and the relevant context, not the conversation. That is the anti-anchoring mechanism.

## Workflow

### 1. Extract the real question

Reduce the decision to one explicit prompt: what are we deciding, which constraints matter, what counts as success. If the question is vague, ask one clarifying question first, with your recommendation (`recommend-on-ask`).

### 2. Gather only the necessary context

For a codebase-specific decision, collect the relevant files, snippets, issue text, or metrics, and keep it compact. Hand over file paths and quote the user's wording verbatim; do not hand over your paraphrase of them (`slop-prevention`, "copy, don't interpret"). For a strategic decision, skip repo snippets unless they change the answer.

### 3. Form the Architect position first

Before reading the other voices, write down: your initial position, its three strongest reasons, and the main risk in your preferred path. Doing this first stops the synthesis from simply mirroring the external voices.

### 4. Launch three independent voices in parallel

One message, three `Agent` calls. They are read-only reasoning tasks, so use `subagent_type: Plan` for each (do not fall back to `general-purpose`). Each gets the decision question, compact context if needed, a strict role, and no conversation history.

Prompt shape:

```text
You are the [ROLE] on a four-voice decision council.

Question:
[decision question, quoted verbatim]

Context:
[only the relevant snippets, constraints, or file paths]

Respond with:
1. Position: 1-2 sentences
2. Reasoning: 3 concise bullets
3. Risk: the biggest risk in your recommendation
4. Surprise: one thing the other voices may miss

Be direct. No hedging. Under 300 words. Do not modify any file.
```

Role emphasis:
- **Skeptic**: challenge the framing, question assumptions, propose the simplest credible alternative.
- **Pragmatist**: optimize for speed, simplicity, and real-world execution.
- **Critic**: surface downside risk, edge cases, and the ways the plan could fail.

Pass an explicit `model` parameter on each of the three Agent calls (default `sonnet`, per `rules/api-cost-optimization.md`); omitting it runs the voice on the caller's model (`agents/control-agent.md` §2).

### 5. Synthesize with bias guardrails

You are both a participant and the synthesizer. Therefore:
- Do not dismiss an external view without saying why.
- If an external voice changed your recommendation, say so.
- Always include the strongest dissent, even if you reject it.
- If two voices align against your initial position, treat that as a real signal.
- Keep the raw positions visible before the verdict.
- Treat sub-agent claims about the codebase as claims: spot-check one that the verdict depends on.

### 6. Present a compact verdict

```markdown
## Council: [short decision title]

**Architect:** [1-2 sentence position]
[1 line on why]

**Skeptic:** [1-2 sentence position]
[1 line on why]

**Pragmatist:** [1-2 sentence position]
[1 line on why]

**Critic:** [1-2 sentence position]
[1 line on why]

### Verdict
- **Consensus:** where they align
- **Strongest dissent:** the most important disagreement
- **Premise check:** did the Skeptic challenge the question itself?
- **Recommendation:** the synthesized path, with a one-line reason
```

Keep it scannable on a phone screen. The final decision stays with the user; the council informs it.

## Persistence

Do not write ad-hoc notes to shadow paths. Persist a decision only when it changes something real:
- a decision someone may later ask "why?" about becomes an ADR in `docs/adr/` (`domain-docs-convention`)
- a coined term goes into `CONTEXT.md`
- a decision that changes active work goes into the issue or planning doc it affects

If nothing durable changed, leave nothing behind.

## Multi-round follow-up

The default is one round. For another round, keep the new question focused, include the previous verdict only if necessary, and keep the Skeptic as clean as possible to preserve the anti-anchoring value.

## Anti-patterns

- Using a council for code review or plain implementation work
- Giving the sub-agents the whole conversation transcript
- Hiding disagreement in the final verdict
- Persisting every decision as a note regardless of importance
- Treating the verdict as binding instead of as input

## Example

Question: "Should we ship the beta now, or hold until the dashboard is more complete?"

Likely shape: the Architect pushes for structural integrity and a coherent surface; the Skeptic asks whether the dashboard is actually the gating factor; the Pragmatist asks what can ship now without harming trust; the Critic focuses on support burden and expectation debt. The value is not unanimity. It is making the disagreement legible before choosing.
