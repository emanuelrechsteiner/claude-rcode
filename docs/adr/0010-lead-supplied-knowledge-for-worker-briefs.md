# 0010 — Lead-supplied knowledge for worker briefs

- Status: accepted
- Date: 2026-11-01

## Context

The owner's concern, as an English paraphrase of the owner's directive of
2026-11-01 (the directive itself is not quoted here): searching the knowledge
library should always be done by a specialised agent. The Lead decides whether
a found note matters for the subagent's task. If it matters, the knowledge
agent passes it on. If it does not, one more search runs with a better query.
Only if that search also comes up empty may the subagent be spawned without
knowledge.

The reason for the design is the worker's capability. A worker on haiku with
low effort is too weak to choose the lookup keywords and to judge relevance on
its own. IMP-267 (2026-10-31) added a write-path gate that forces the act of
looking up, but it cannot check the quality of the lookup: a worker can run one
keyword search, see nothing useful and continue.

The retrieval protocol is decided in `docs/adr/0009-agentic-retrieval-over-lexical-lookup.md`.
Its measured numbers, quoted as that ADR states them: the live agent route
scored 56/56 (hit@1 54/56, 2.8 calls on average); the replayed protocol with
frozen keyword sets scored hit@3 50/56 (89 %); the lookup alone on the same 56
questions scored hit@3 22/56. The protocol depends on the calling agent writing
good keyword sets and judging the hits, which is why the Lead, not the worker,
takes that role here.

## Decision

Before every worker dispatch the Lead writes 2–4 keyword sets for the unit. The
new read-only `knowledge-agent` (haiku) runs `knowledge-lookup.sh` with those
sets and returns verbatim excerpts with paths, never a paraphrase or a
recommendation. The Lead judges relevance on those excerpts. The worker brief
then carries a mandatory sixth field, KNOWLEDGE, with one of three verdicts:
cited (excerpts and paths), none (after two rounds, with the sets searched) or
unavailable (with at least 20 bytes of real content in the reason). `hooks/knowledge-brief-check.sh`
denies a dispatch whose KNOWLEDGE field is missing or invalid, and it checks
that cited notes exist in the mirror and that a none verdict follows a
knowledge-agent search in the same session. A cited or none verdict satisfies
the IMP-267 knowledge gate for the worker, through a `lead-supplied` record; an
unavailable verdict does not, so the worker then looks up on its own. The check
runs in deny mode by default, with a 3-denial breaker that then escalates.
Verdict rules, hardened on 2026-11-01 after review: verdict words are read outside the `sets:` clause and outside double quotes, by precedence (a none-phrase, then `unavailable`, then a `.md` path), so an incidental path never decides a verdict. Citations are mirror-only, and every quoted excerpt of 30 bytes or more must appear verbatim in a cited note. A none verdict needs its `sets:` clause and two distinct knowledge-agent runs (two agent ids) in the session, an unavailable verdict one knowledge-agent dispatch. The injection hook reaches the same verdict through the shared parser `hooks/lib/knowledge-brief.sh` and keeps the lead-supplied bookkeeping (queue, paragraph, record) even when retrieval is off (`CLAUDE_KNOWLEDGE_INJECT=0` or a missing lookup script); only a missing library disables everything. Queue ambiguity: at SubagentStart exactly one unexpired queued entry of the subagent's type is attributed; two or more are ambiguous, so the floor hits may be delivered, no `lead-supplied` record is written and the worker looks up on its own (logged `ambiguous-queue=<n>`).

## Consequences

Easier: every worker brief carries targeted knowledge that the Lead has read,
and every verdict is measurable from the brief check log
(`~/.claude/global-observation/knowledge-brief.log`).

Harder: each unit costs one haiku spawn (11–16 s, measured on two haiku helpers on 2026-11-01; run in parallel within a
wave), and the Lead must write the keyword sets. A dispatch without the field is
denied and costs a round trip.

Trade-offs, named openly:

- A worker's lookup is now not fully its own. This is a deliberate exception to
  the identity isolation of the knowledge gate (a parent's record never
  satisfies a subagent). The exception holds because the Lead's work is the
  evidence that the worker was briefed.
- The dispatch queue matches by agent type in first-in-first-out order. With two
  or more pending dispatches of the same type, the start is ambiguous and gets
  no `lead-supplied` record, so that worker looks up on its own. The cost: same-type
  siblings in one wave look up themselves. A wrong worker can still inherit a
  wrong hits block (low harm), but never a gate pass it did not earn. Lead advice:
  keep only one same-type worker pending at a time per wave.
- Haiku extraction quality for the knowledge-agent is not measured. ADR 0009
  records the rewrites as written by the calling agent; it does not name the model.
- Skills that dispatch agents themselves do not write the field yet, so those
  dispatches hit the breaker.
- The excerpt check denies a brief whose quote was reworded, by design ("copy, don't interpret").

What to measure after two weeks of log data: the share of cited, none and
unavailable verdicts per wave; the number of denials and how many reach the
breaker; the share of starts logged `ambiguous-queue=<n>`; and whether the sets
the Lead wrote reach a relevant note at rank one to three. If the none share is high, the keyword sets are the weak point, not
the library.

Rejected alternatives: the worker runs the Lead's sets itself (this loses the
Lead's judgement of relevance); the Lead reads the notes itself (this costs
Lead context and serialises the wave).
