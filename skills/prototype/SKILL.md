---
name: prototype
description: "Build a throwaway prototype to answer a design question — a runnable interactive terminal app for state/logic questions, or several radically different UI variations on one route switchable via URL param. Use when unsure whether a state model or logic feels right, or what a UI should look like. Triggers on 'prototype', 'spike', 'wegwerf-prototyp', 'varianten bauen', 'mal durchspielen', 'ausprobieren bevor wir bauen', 'welche variante'."
context: fork
model: sonnet
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Prototype

A prototype is **throwaway code that answers a question**. The question decides the shape.

## Pick a branch

Identify which question is being answered — from the user's prompt, the surrounding code, or by asking if the user is around:

- **"Does this logic / state model feel right?"** → [LOGIC.md](LOGIC.md). Build a tiny interactive terminal app that pushes the state machine through cases that are hard to reason about on paper.
- **"What should this look like?"** → [UI.md](UI.md). Generate several radically different UI variations on a single route, switchable via a URL search param and a floating bottom bar.

The two branches produce very different artifacts — getting this wrong wastes the whole prototype. If the question is genuinely ambiguous and the user isn't reachable, default to whichever branch better matches the surrounding code (a backend module → logic; a page or component → UI) and state the assumption at the top of the prototype.

## Rules that apply to both

1. **Throwaway from day one, and clearly marked as such.** Locate the prototype code close to where it will actually be used (next to the module or page it's prototyping for) so context is obvious — but name it so a casual reader sees it's a prototype, not production. For throwaway UI routes, obey whatever routing convention the project already uses; don't invent a new top-level structure.
2. **One command to run.** Whatever the project's existing task runner supports — `pnpm <name>`, `python <path>`, `bun <path>`, etc. The user must be able to start it without thinking.
3. **No persistence by default.** State lives in memory. Persistence is the thing the prototype is *checking*, not something it should depend on. If the question explicitly involves a database, hit a scratch DB or a local file with a clear "PROTOTYPE — wipe me" name.
4. **Skip the polish.** No tests, no error handling beyond what makes the prototype *runnable*, no abstractions. The point is to learn something fast. (This is a sanctioned exception to the usual testing cadence — prototype code never merges to trunk as-is, see rule 6.)
5. **Surface the state.** After every action (logic) or on every variant switch (UI), print or render the full relevant state so the user can see what changed.
6. **Capture it when done.** Fold any validated decision into the real code, then capture the prototype itself as a **primary source**: commit it to a local throwaway branch, out of trunk (a local branch is AUTO-band per `rules/agency-bands.md` — no push needed), and leave a context pointer to that branch on the implementation issue. Capture the answer too — the verdict and the question it settled — in the issue, a commit body, or an ADR (`rules/domain-docs-convention.md`). Trunk keeps only the validated decision.

---
*Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) `prototype` (MIT License, © 2026 Matt Pocock); capture step aligned with this framework's agency-bands and domain-docs conventions (IMP-124).*
