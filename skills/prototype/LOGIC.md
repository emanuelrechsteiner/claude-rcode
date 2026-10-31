<!-- Adapted from mattpocock/skills skills/engineering/prototype/LOGIC.md (MIT License, © 2026 Matt Pocock) — IMP-124 -->

# Logic Prototype

A single self-contained HTML page that lets the user drive a state model by hand in the browser. Use this when the question is about **business logic, state transitions, or data shape** — the kind of thing that looks reasonable on paper but only feels wrong once you push it through real cases.

## When this is the right shape

- "I'm not sure if this state machine handles the edge case where X then Y."
- "Does this data model actually let me represent the case where..."
- "I want to feel out what the API should look like before writing it."
- Anything where the user wants to **press buttons and watch state change** — including people who cannot run the repo (designer, PM, domain expert).

If the question is "what should this look like" — wrong branch. Use [UI.md](UI.md).

## Process

### 1. State the question

Before writing code, write down what state model and what question you're prototyping. One paragraph, shown at the top of the page and repeated as a comment in the file. A logic prototype that answers the wrong question is pure waste — make the question explicit so it can be checked later, by you or by whoever opens the file.

### 2. Pick the language

The page runs in the browser, so the logic is plain JavaScript in one `<script>` block: no framework, no bundler, no package install. If the host project is TypeScript, add `// @ts-check` and JSDoc types so the module can be lifted with its types intact. If the project has no obvious runtime (e.g. a docs repo), ask.

### 3. Isolate the logic in a portable module

Put the actual logic — the bit that's answering the question — behind a small, pure interface that could be lifted out and dropped into the real codebase later. The HTML shell around it is throwaway; the logic module shouldn't be.

The right shape depends on the question:

- **A pure reducer** — `(state, action) => state`. Good when actions are discrete events and state is a single value.
- **A state machine** — explicit states and transitions. Good when "which actions are even legal right now" is part of the question.
- **A small set of pure functions** over a plain data type. Good when there's no implicit current state — just transformations.
- **A class or module with a clear method surface** when the logic genuinely owns ongoing internal state.

Pick whichever shape best fits the question, *not* whichever is easiest to wire to a page. Keep it pure: no I/O, no DOM access, no `alert`, `localStorage`, `fetch` or `console.log` for control flow. Place it in its own block at the top of the `<script>`, marked as the part to lift. The shell calls into it; nothing flows the other direction.

This is what makes the prototype useful past its own lifetime: when the question's been answered, the validated reducer / machine / function set can be lifted into the real module on its own.

### 4. Build the smallest HTML shell that exposes the state

Build it as **one self-contained HTML file**: inline CSS and one inline script, no build step, no server, no external files. It must open by double-click and still work after being emailed. Do not split it into several files or use `type="module"` imports — a page opened from disk cannot load them.

Each page has these parts, top to bottom:

1. **Question** — the paragraph from step 1, plus a visible "PROTOTYPE — throwaway" banner.
2. **Current state** — pretty-printed in a `<pre>`, one field per line, labelled in domain language. Re-render this whole panel after every action; don't append.
3. **Actions** — one button per action (e.g. "Add user", "Advance clock"), with small inputs for parameters. If the logic rejects an action, show its reason next to the button. Disable buttons only when legality is part of the question.
4. **History** — an append-only list: each action taken and what it changed.
5. **Walkthroughs** (when the question has known scenarios) — one tab per scenario, each listing the ordered buttons to press. Free-play buttons stay available.

Behaviour:

1. **Initialise state** — a single in-memory object. Render the page on load.
2. **Dispatch** — a button click passes the current state and the action to the pure logic; the returned state replaces the old one.
3. **Re-render** the state panel and history after every action.
4. **Reset** returns to the initial state.

Plain CSS, system font, one column. Nothing that needs a library.

### 5. Make it openable in one step

No task-runner entry, no command: the user double-clicks the file. Name it so a casual reader sees it's a prototype (e.g. `<name>-prototype.html`) and place it next to the module it prototypes.

### 6. Hand it over

Open the file in the user's browser (`open <path>`) and give them the path. They drive it themselves; the interesting moments are when they say "wait, that shouldn't be possible" or "huh, I assumed X would be different" — those are the bugs in the *idea*, which is the whole point. If they want new actions added, add them. Prototypes evolve.

### 7. Capture the answer and the prototype

Once the prototype has answered its question, capture the answer, then capture the prototype the way the [SKILL](SKILL.md) describes. The logic-specific mapping: the validated reducer / machine / function set lifts into the real module (the decision, absorbed); the HTML page rides along to the throwaway branch that keeps the prototype as a primary source.

## Anti-patterns

- **Don't add tests.** A prototype that needs tests is no longer a prototype.
- **Don't wire it to the real database.** Use an in-memory store unless the question is specifically about persistence.
- **Don't generalise.** No "what if we wanted to support X later." The prototype answers one question.
- **Don't blur the logic and the shell.** If the logic module touches `document`, `window`, `alert`, or any element, it's no longer portable. Keep the page a thin shell over a pure module.
- **Don't add a build step, a server, or a second file.** The page is useful because anyone can open it by double-click; a bundler or a local server turns it into a dev environment.
- **Don't ship the shell into production.** The page is optimised for being clicked through by hand. The logic module behind it is the bit worth keeping.
