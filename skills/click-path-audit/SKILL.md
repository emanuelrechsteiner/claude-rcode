---
name: click-path-audit
description: Trace each button through its full state-change sequence to find handlers whose calls cancel each other or leave the UI in the wrong state. Use when users report dead buttons but debugging found nothing. Triggers on "click path audit", "button does nothing", "handlers undo each other".
disable-model-invocation: true
---

<!--
Adapted from affaan-m/ECC skills/click-path-audit @ c70874f (MIT, Copyright (c) 2026 Affaan Mustafa); reviewed and rewritten 2026-10-01 for this framework.
-->

# Click-Path Audit: Behavioral Flow Audit

Find the bugs that static reading misses: state interactions with side effects, races between sequential calls, and handlers that silently undo each other. Manual-only (`/click-path-audit`) because a full audit is expensive and should be scoped on purpose.

## The problem this solves

Ordinary debugging checks that the function exists (wiring), does not crash (runtime), and returns the right type (data flow). It does not check:

- Does the final UI state match what the button label promises?
- Does function B silently undo what function A just did?
- Does a shared store (Zustand, Redux, context) have side effects that cancel the intended action?

Worked example: a "New Email" button called `setComposeMode(true)` then `selectThread(null)`. Both worked alone. But `selectThread` also reset `composeMode` to `false`, so the button did nothing. Systematic debugging missed it: the handler exists, both functions exist, nothing crashes, the types are right.

## How it works

For every interactive touchpoint in the target area:

```
1. IDENTIFY the handler (onClick, onSubmit, onChange, ...)
2. TRACE every function call in the handler, IN ORDER
3. For EACH call:
   a. What state does it READ?
   b. What state does it WRITE?
   c. Does it have SIDE EFFECTS on shared state?
   d. Does it reset or clear other state?
4. CHECK: does a later call UNDO a change from an earlier call?
5. CHECK: is the FINAL state what the button label promises?
6. CHECK: can async calls resolve in a wrong order?
```

## Execution

### Step 1: Map the state stores

Before auditing any touchpoint, build a side-effect map of every action in every store in scope.

```
For each store / context in scope, for each action or setter:
  - which fields does it set?
  - does it RESET other fields as a side effect?
  - record: actionName -> { sets: [...], resets: [...] }
```

This map is the critical reference; the example bug was invisible without knowing that `selectThread` resets `composeMode`.

```
STORE: emailStore
  setComposeMode(bool)      sets: {composeMode}
  selectThread(thread|null) sets: {selectedThread, selectedThreadId, messages, drafts,
                                   selectedDraft, summary}
                            RESETS: {composeMode: false, composeData: null, redraftOpen: false}
  setDraftGenerating(bool)  sets: {draftGenerating}

DANGEROUS RESETS (an action clears state it does not own):
  selectThread -> resets composeMode (owned by setComposeMode)
  reset        -> resets everything
```

### Step 2: Audit each touchpoint

```
TOUCHPOINT: [button label] in [Component:line]
  HANDLER: onClick -> {
    call 1: functionA() -> sets {X: true}
    call 2: functionB() -> sets {Y: null}  RESETS {X: false}   <- CONFLICT
  }
  EXPECTED: what the label promises the user will see
  ACTUAL:   X is false because functionB reset it
  VERDICT:  BUG, with a one-line description
```

Check each of these six patterns.

**1. Sequential undo**
```
handler() {
  setState_A(true)    // sets X = true
  setState_B(null)    // side effect: resets X = false
}
// X is false; the first call was pointless
```

**2. Async race**
```
handler() {
  fetchA().then(() => setState({ loading: false }))
  fetchB().then(() => setState({ loading: true }))
}
// the final loading state depends on which request resolves first
```

**3. Stale closure**
```
const [count, setCount] = useState(0)
const handler = useCallback(() => {
  setCount(count + 1)   // captures the stale count
  setCount(count + 1)   // same stale count: increments by 1, not 2
}, [count])
```

**4. Missing state transition**
```
// the button says "Save" but the handler only validates
// the button says "Delete" but the handler sets a flag and never calls the API
// the button says "Send" but the endpoint is removed or broken
```

**5. Conditional dead path**
```
handler() {
  if (someState) {        // someState is ALWAYS false at this point
    doTheActualThing()    // never reached
  }
}
```

**6. Effect interference**
```
// the button sets stateX = true
// a useEffect watching stateX resets it to false
// the user sees nothing happen
```

### Step 3: Report

For each bug:

```
CLICK-PATH-NNN: [severity: CRITICAL | HIGH | MEDIUM | LOW]
  Touchpoint: [button label] in [file:line]
  Pattern:    [Sequential Undo | Async Race | Stale Closure | Missing Transition | Dead Path | Effect Interference]
  Handler:    [function name or inline]
  Trace:
    1. [call] -> sets {field: value}
    2. [call] -> RESETS {field: value}   <- CONFLICT
  Expected:   what the user expects
  Actual:     what actually happens
  Fix:        specific change
```

Lead the report with the verdict: `Done: yes | no, missing: <touchpoints not traced>`. List touchpoints that were skipped, so an untraced button is never read as a clean one.

## Static trace vs. observed behavior

The trace is a reading of the code. For each BUG verdict that matters, confirm it on the running app before calling it fixed or found: reproduce the click with the `human-testing` skill (Playwright), or for a visual end state use `visual-qa-agent`, and describe what is on screen before judging it. After the fix, the same click must show the promised state, with a screenshot, not just a changed handler (`slop-prevention`, Trigger 3).

## Scope control

The audit is expensive; scope it deliberately.

- **Full app:** at launch or after a major refactor. Read-only, so independent areas run in parallel.
- **Single page:** after building a page, or when a user reports a dead button.
- **Store-focused:** after changing a store action; audit every consumer of the changed actions.

Recommended split for a full audit, in two waves (read-only `Explore` agents; per-spawn Agent/Model/Effort per `agents/control-agent.md` §2):

```
Wave 1: one mapper (Explore, read-only) maps ALL state stores (Step 1) and returns the
        store map to the main thread. The main thread writes it to a scratch file.
Wave 2: one message, parallel Explore agents, one per page or feature area, each given
        the scratch-file path of the store map plus its area's entry files.
```

Wave 2 starts only after wave 1 has returned. Give each agent the path; do not retell the map in your own words.

## When to use

- Debugging found "no bugs", yet users report broken UI
- After modifying a store action (check all callers)
- After a refactor that touches shared state
- Before a release, on the critical user flows
- When a button "does nothing": this is the tool for that

## When not to use

- API-level bugs (wrong response shape, missing endpoint): use ordinary debugging
- Styling and layout problems: look at the rendered result (`visual-qa-agent`)
- Performance problems: profile (`react-perf-check`)

## Workflow neighbors

- Run after ordinary debugging has found the bugs that are cheap to find.
- Every bug found here gets a regression test (`testing-agent`), written to fail on the old handler.
- After fixes, run `fix-review` to look for the same pattern elsewhere.

## Example: the bug that motivated this skill

Handler:
```
onClick={() => {
  useEmailStore.getState().setComposeMode(true)   // sets composeMode = true
  useEmailStore.getState().selectThread(null)     // RESETS composeMode = false
}}
```

Store:
```
selectThread: (thread) => set({
  selectedThread: thread,
  selectedThreadId: thread?.id ?? null,
  messages: [],
  drafts: [],
  selectedDraft: null,
  summary: null,
  composeMode: false,     // this silent reset killed the button
  composeData: null,
  redraftOpen: false,
})
```

Ordinary debugging missed it: the handler is not dead, both functions exist, neither crashes, the types match. The audit catches it: Step 1 records that `selectThread` resets `composeMode`; Step 2 traces call 1 setting true and call 2 resetting false; verdict Sequential Undo, with a final state that contradicts the button's intent.
