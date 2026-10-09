# 0009 — Retrieval stays lexical; the calling agent bridges meaning through a fixed protocol

- Status: accepted
- Date: 2026-10-09

## Context

Lookup v3 (BM25F-lite) scores 10/10 on the dev queries but only 10/25 hit@3 on
the held-out test set, and the `crosslang` class (German question, English note
or the reverse) exposes the limit of word matching. Options and licences are in
`research/knowledge-retrieval-semantic-options-2026-10-09.md` (R1). Four routes
were measured on 2026-10-09 with the same scorer (hit@3 = expected note in the
top 3; test = 25 owner/judge-confirmed held-out questions, dev = 10 queries):

| Route | Dev | Test | Cost per question | Infrastructure |
|---|---|---|---|---|
| Lexical lookup v3 alone | 10/10 | 10/25 (hit@1 8/25) | ~1k tokens, 0.3 s | none |
| Agent rewrites the question into 2-4 keyword sets, uses only the lookup | 10/10 | 25/25 (hit@1 24/25), 2.8 calls on average | ~2-3k tokens, one LLM turn per set | none |
| Agent reads the catalog (`graph/nodes.tsv`, 65 KB, ~16k tokens) and picks | 6/10 | 24/25 (hit@1 23/25) | ~16k tokens | none |
| Catalog + lookup | 10/10 | 24/25 | ~17k tokens | none |
| Dense retrieval on-device (Apple NaturalLanguage `NLEmbedding`, one vector per note, both language models) | dense alone 0/10; weighted hybrid 10/10 only at w_dense 0.03 | dense alone 1/25 (3/56); equal-weight RRF 6/25, below lexical; weighted hybrid 11/25 (23/56), i.e. lexical ±1 | 140 ms per query, 100 s index, 2.75 MB | Swift, macOS-only; the English (512-d) and German (640-d) models share no space — same-meaning cross-language cosine 0.25 vs 0.21 for unrelated pairs, so no cross-language bridge exists (prototype 2026-10-09, measured through the same scorer) |

The rewrite route found every question of each test class (lookup 7,
paraphrase 6, crosslang 8, supersession 4). Caveat: n=25 gives roughly +-19
points at 95 %, so the result shows a large gap, not a precise rate.

Amended 2026-10-09, after the held-out set grew to 56 judge-confirmed
questions (lookup 13, paraphrase 15, crosslang 19, supersession 9): live
agent route 56/56 (hit@1 54/56, 2.8 calls on average); deterministic replay
of the frozen keyword sets through `knowledge-lookup.sh --alt` with
best-rank-first fusion: hit@3 50/56 (89 %), hit@10 55/56 (98 %), hit@1 30/56,
median tokens-to-answer 2,694; lookup alone on the same 56: hit@3 22/56.
Per class (deterministic, hit@3 / hit@10): lookup 12/13, paraphrase 12/15,
crosslang 18/19, supersession 8/9 — all above the 70 % class floor.

## Decision

Retrieval stays lexical and deterministic in the tool. The semantic bridging is
done by the calling agent through a fixed retrieval protocol: put 2-4 keyword
sets into one `--alt` call (the question's own words, its translation into the
other language, the technical terms), judge the hits by the `»` description
lines, and open only the top note's section. There is no vector index, no
embedding model and no hosted service. Rejected: reading the catalog per query
(~16k tokens each time), hosted embeddings (paid, external send), and LLM
extraction into the mirror (ADR 0007: generated structure is deterministic).

## Consequences

- No new dependency; the lookup stays reproducible and costs ~2-3k tokens per
  question instead of ~16k.
- The result depends on the agent following the protocol. The eval harness
  therefore measures the protocol deterministically through frozen rewrites
  (unit D3); it does not call a model.
- Fallback, documented and not built: `bge-m3` via Ollama over the 589
  description lines, fused with BM25F by RRF (one new dependency, fail loud
  when absent). Trigger, any one: a held-out set of at least 50 questions
  scores below 80 % hit@3 under the protocol; the corpus passes ~2k notes; the
  lookup usage log shows agents not following the protocol.
- "Finished" (R1 proposal, not a standard): at least 50 held-out questions,
  hit@3 >= 80 % overall and >= 70 % on cross-language and paraphrase, hit@10 >=
  90 %, median tokens-to-answer <= 5k, index stamp equal to the mirror stamp.
  The current 25 questions do not yet meet the size condition.
- The dense on-device route is measured separately; if it beats the protocol at
  lower cost this ADR is superseded, not edited.
