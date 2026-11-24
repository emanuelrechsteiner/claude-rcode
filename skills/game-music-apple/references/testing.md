# Testing and Measuring Game Music

Three questions, three methods: (1) does a transition sound continuous (offline renders and signal assertions), (2) does the state logic decide correctly (fake-clock unit tests), (3) does music cost frame rate (A/B runs and profiling). Listening decides the last word on (1).

## 1. Offline Transition Tests

- **Matrix:** render every ordered pair of pieces (N × (N − 1) directed transitions; 20 for five pieces), plus round trips (A to B to A) and at least one longer chain, to WAV with fixed inputs. Use manual rendering (apple-engine.md section 10).
- **Keep the transition math pure.** Put the gain, alignment and mixing logic in a function over sample buffers so it can be tested without the player node. Test the player node separately as an integration step.
- **Check the first block.** Offline rendering can return silence at the start (forum reports; anecdotal). Fail the test if the first render block is all zero where music is expected.
- **Assertions** (thresholds are to be calibrated by ear; none are sourced):
  - **Exact join (primary; no onset detection):** outside the overlap the render equals the outgoing source (before the join) or the incoming source (after it), at the known gain of 1 or 0; inside the overlap it equals the two source segments under the known gain curves. Assert a maximum absolute error below 1e-4 full scale and a cross-correlation peak lag of 0 samples in the offline renderer (starting values, synthesis; calibrate on the known-good set). This tests alignment at the sample. A raw sample-jump test cannot do that, because it mostly measures high-frequency content.
  - **Click (secondary):** the largest sample-to-sample jump within 64 samples around the join must stay below 4 times the median jump of the surrounding 2,048 samples (starting values, synthesis).

```swift
// sketch, not compiled: click check against the local median jump
let jumps = zip(samples, samples.dropFirst()).map { abs($1 - $0) }
let worstAtJoin = jumps[(joinIndex - 32)..<(joinIndex + 32)].max() ?? 0
let typical = jumps[(joinIndex - 1024)..<(joinIndex + 1024)].sorted()[1024]
// assert worstAtJoin < 4 * typical
```

  - **Loudness continuity:** momentary loudness (0.4 s window) and short-term loudness (3 s window), per EBU Tech 3341 (assets.md section 2). Assert no dip or bump beyond 1 LU relative to the level before the join, for both windows (starting value, synthesis; calibrate on the known-good set).
  - **Beat offset in samples:** on offline renders, the cross-correlation lag of the exact-join check replaces onset detection. On device recordings an onset method is needed; name it when it is used (its method is not sourced here). Tolerance: about +-2 ms = +-96 samples at 48 kHz (computed; calibrate on known-good renders). Assert it on the rendered output, not on the schedule. The same 96 samples is the pair tolerance of transitions.md section 2.
  - **Gaps:** no run of exact zeros or samples below −90 dBFS longer than 20 ms at the join, unless the design calls for a cut (starting value; synthesis).
  - **Exact length:** each delivered segment decodes to the expected frame count (assets.md sections 4 and 5a). This is a build gate.
  - **Known-good set (synthesis):** calibration uses (1) self-crossfades of each piece into itself, whose content is known exactly, and (2) pairs whose listening verdict passed (section 5). Name the set in the test fixture and calibrate only from it.
- **Golden files:** store rendered outputs with tolerances. Re-render and compare on every change to the transition code.
- **Render on the target too.** Offline results do not prove device timing. Run the same matrix on hardware at least once per release candidate (sceptic-noted gap; synthesis).

## 2. Scheduler Tests on a Fake Clock

- Abstract the clock as a sample counter the tests can set. Feed the state machine events and advance the clock.
- Assert the scheduled start sample for each deck, the escalation at the next phrase boundary of the outgoing piece, minimum dwell, hysteresis on numeric thresholds (exit below entry), and that overlapping waves and the tail keep the tier until the last wave ends.
- Use event-sequence tables as test data: each row is a list of enemy spawns, deaths, wave starts and clock advances, plus the expected tier sequence.
- **Re-entrant rows (synthesis; transitions.md section 4.1):** (a) a request during an overlap starts nothing and cuts nothing; (b) two requests during one overlap leave only the newer one pending; (c) a pending request equal to the new master is dropped; (d) A to B to A requested during the A-to-B overlap starts a new overlap from B at its next phrase boundary; (e) E = 0 with W > 0 keeps the tier (tail); (f) tail time is not counted in the calm count; (g) an early-released strong wave never re-latches.
- No published method for music-scheduler unit tests on a fake clock was found. This is an engineering approach (synthesis), not a named method.

## 3. A/B Frame-Rate Protocol

Use this before changing music code to answer "is the music the cost?"

1. Same build, same device, same mission and seed. Record thermal state and Low Power Mode.
2. Two arms: music on, and music off with no engine running and no player nodes created.
3. Run each arm several times: at least 5 whole runs per arm (synthesis minimum, not from Apple).
4. Plot frame rate against live-entity count for both arms. If the two curves overlay, audio is ruled out for that load band.
5. Count displayed frames, not scene updates. A recorder that counts scene-update callbacks (for example RealityKit scene-update deliveries) is not a displayed-frame counter; calibrate it against a display-side measure before trusting FPS numbers (synthesis).
6. Acceptance checks that require audio will fail a no-audio arm by design. Keep the log for comparison and mark the arm in the report.
7. Only after the A/B shows that music costs frames: profile the music path (section 4).

Interpretation (synthesis): frame rate tracking ship count is consistent with render and simulation cost. Audio alone rarely shows a sustained slope against entity count; it shows up as one-off hitches (file open, hashing, engine start or stop).

## 4. Instruments, Signposts and System Tools

- **Time Profiler:** samples periodically; cannot explain gaps on its own (WWDC23 session 10248, "Analyze hangs with Instruments"; sceptic-confirmed).
- **Thread States (Thread State Trace):** explains blocking. Use it with Time Profiler to tell a gap from a busy thread (same session).
- **System Trace** (WWDC26 session 268; not sceptic-checked): when and why the OS pauses the app, including synchronous file I/O on the main thread. This is where the main-thread file open and hash would show.
- **Allocations:** page faults and buffer sizes. **Hangs:** main-thread stalls.
- **Metal System Trace** (WWDC18 session 612): the GPU template. An Audio template in Instruments was **not confirmed**.
- **OSSignposter** (iOS 15, macOS 12) and the os_signpost instrument around scheduling calls (WWDC19 session 414, "always end the intervals you begin"; WWDC18 session 405, one signpost ID per overlapping interval).
- Third-party write-ups warn that reused interval names across async tasks can mispair in Instruments (unofficial).
- **macOS audio I/O overload:** the message `HALC_ProxyIOContext::IOWorkLoop: skipping cycle due to overload` means the audio I/O thread missed its deadline. Reports pair it with coreaudiod overload reports and page faults on the I/O thread. Capture it with `log stream` filtered for audio messages (user reports, not Apple documentation; exact predicate not verified).
- Measure on hardware. Simulator timing can differ.

## 5. Listening Tests

- **ABX per transition pair** with a hidden reference. For 16 trials (computed, binomial): 12 correct gives one-sided p ≈ 0.038; 13 correct gives p ≈ 0.011.
- **MUSHRA** for intermediate quality (ITU-R BS.1534-3, 10/2015, in force; hidden reference and hidden anchor). **BS.1116** is a triple-stimulus hidden-reference method for small impairments. ABX is a different method with a binomial test (secondary source).
- **Checklist per transition:** timing (beat and bar), harmony, level, spectral balance, groove.
- Groove and harmony are judged by people. Sample-level and beat-grid checks cannot prove them (sceptic-noted; synthesis).
- **Archive the verdicts:** save the rendered file for every pair with the listener's decision, so the review can be repeated after code changes.

## 6. Runtime Telemetry

Proposed design (not sourced from one authority):
- State changes with a host-time or monotonic timestamp.
- Scheduled lead time (time between scheduling and the planned start).
- Underruns and configuration-change events.
- Decision inputs: enemies alive, threat value, latched wave, base health, current tier.
- Transition start and end as sample positions on the shared timeline.
- Play time per piece per session, to inform the rotation rule (state-design.md section 7).
- Write to a preallocated buffer off the render thread and flush off the main thread.
