# AVAudioEngine Two-Deck Transport

Goal: two decks (A and B) on one engine timeline, starts placed on exact sample positions, gain curves that do not depend on the main thread, and no file work at decision time. Code below is sketch, not compiled. Check each API name against the current SDK.

Labels: **spike-pending** = the design depends on it and no source settles it; run the spike in section 2 before building on it.

## 1. Topology (Sketch)

```swift
// sketch, not compiled
let engine = AVAudioEngine()
let deckA = AVAudioPlayerNode()
let deckB = AVAudioPlayerNode()
engine.attach(deckA)
engine.attach(deckB)
engine.connect(deckA, to: engine.mainMixerNode, format: format)  // one sample rate, e.g. 48 kHz
engine.connect(deckB, to: engine.mainMixerNode, format: format)
```

- One engine, two player nodes, one mixer. Keep every piece at one sample rate so no per-file conversion happens mid-show.
- Per-deck EQ for the bass swap sits between each player and the mixer, only if the runtime-EQ route in section 5 is chosen. Its behaviour is **unconfirmed** in the sources read; the default bass swap does not use it.

## 2. Shared Timeline and Scheduling

### Anchor, timeline and queue (decide before building)

- **Anchor (spike-pending).** Apple's manual-rendering page names `lastRenderTime` on `AVAudioNode` for tracking rendered data (research summary, not sceptic-checked). Its use as the live "now" comes from an old forum thread (14138; secondary, not checked). Do not build on it until the spike below passes.
- **Timeline of `when` (spike-pending).** The sources confirm that a sample time is used as given. They do not say whether it counts on the player timeline or the engine timeline. The sketch below assumes the player timeline.
- **Queue (synthesis).** One dedicated serial queue owns the scheduler (segment scheduling and the look-ahead timer) and the state evaluator (state-design.md section 2). The main thread posts intents and shows state. It schedules nothing that decides a transition and does no file work. This settles section 7 against SKILL.md Hard rule 1.
- **Spike (must pass before the transport is built).** Deck A plays. Deck B is scheduled at engine sample N on the chosen timeline. Offline: the first non-zero sample of deck B is at N. On device: record the output, measure the start offset in samples, and record the result in this file. Until then, sample-accurate start of a second deck is unproven.

### Scheduling facts

- `scheduleBuffer`, `scheduleFile` and `scheduleSegment` take an optional `AVAudioTime` (`when`). `nil` plays after the previous command. A sample time is used as given. A host time is ignored unless the sample time is invalid while rendering to a device (Apple AVAudioPlayerNode page; confirmed).
- `nodeTime(forPlayerTime:)` and `playerTime(forNodeTime:)` convert between the engine and player timelines; the player timeline is offset by start and pause intervals (Apple; confirmed in principle).
- `stop()` returns the player timeline to sample 0 (Apple; confirmed). Plan starts after a stop with that in mind.
- `prepare(withFrameCount:)` prepares regions before playback (Apple page).
- **Which thread completion handlers run on is unconfirmed.** Do not assume main or render thread.
- The built-in loop option (`AVAudioPlayerNodeBufferOptions.loops`) is documented for buffers, not for files. A gapless loop from a file needs a PCM buffer or a reschedule at the loop point.
- Apple's sequencer sample avoids built-in looping because of drift. It reschedules each loop at the previous loop's end host time, runs a resync timer every 50 ms, and reschedules within 100 ms of a loop boundary. The sample is listed for macOS 27.0+ and Xcode 27.0+ only; iOS support is unverified (sceptic-confirmed).
- **Warning:** do not call `stop()` inside a completion handler. The deadlock warning comes from a third-party AudioKit issue (#940), **not** from Apple's documentation.
- Older forum guidance (undated; secondary) starts two players together from a reference player's `lastRenderTime` plus an offset, passed as a shared `AVAudioTime` to `play(at:)`.

```swift
// sketch, not compiled; assumes the player timeline (spike-pending)
// Schedule a segment of deck B at a sample position on the player timeline.
func scheduleEntry(_ deck: AVAudioPlayerNode, file: AVAudioFile,
                   startFrame: AVAudioFramePosition, frames: AVAudioFrameCount,
                   atSample: AVAudioFramePosition, sampleRate: Double) {
    let when = AVAudioTime(sampleTime: atSample, atRate: sampleRate)
    deck.scheduleSegment(file, startingFrame: startFrame, frameCount: frames, at: when)
}
// Keep the next segment ready before the current one ends (look-ahead),
// via the completion handler or by scheduling early. Mind the thread caveat above.
```

**Look-ahead (synthesis):** schedule 100 ms or more ahead, with a timer that wakes about every 25 ms. The timer runs on the dedicated queue, never the main thread (Chris Wilson's Web Audio guidance, web.dev, last updated 2013-01-09; the principle transfers, the API does not).

## 3. Gain Automation Without the Main Thread

What is documented (confirmed in a sceptic pass unless noted):

- `AVAudioMixing.volume` is implemented by `AVAudioEnvironmentNode` and `AVAudioMixerNode`. No ramping or smoothing is documented. `AVAudioPlayerNode` also conforms, so "implements" is ambiguous.
- A forum thread reports crackling when `outputVolume` is stepped in 10 ms increments; Apple asked for a Feedback report. Whether `outputVolume` is ramped or stepped is **unconfirmed**.
- `AUScheduleParameterBlock` (AudioToolbox): takes `eventSampleTime`, `rampDurationSampleFrames`, `parameterAddress` and `value` (the value at the end of the ramp). Non-rampable parameters ignore a nonzero ramp. The 4096-frame buffer offset is described for scheduling such as from a render observer.
- Apple's own mixers reportedly honour ramps on rampable parameters (secondhand, WWDC 2017 session 508). Several developers report ramps on `scheduleParameterBlock` had no effect. **Unconfirmed**: test before relying on it.
- `AVAudioMixInputParameters` (AVFoundation, asset-based, not the engine path) documents linear volume ramps. It is not usable for this engine graph.
- Apple's sequencer sample sets a node's volume to zero, schedules, then sets it to one, relying on engine smoothing (its comment says about 5 ms). It does not ramp. Do not copy that as a fade.
- Zipper noise from stepped gain is a general DSP problem; per-sample smoothing is the usual fix (vendor forum, not authoritative).

### Default: pre-computed fade buffers (synthesis)

1. **Prepare.** On the prepare queue (not the main thread, not the render thread), as soon as a transition is scheduled and before its start: decode the outgoing exit window of A and the incoming entry window of B to PCM, if they are not resident (Hard rule 2). Multiply each window by its equal-power curve (outgoing cos, incoming sin; section 4) into preallocated buffers of identical length. The window length in bars is data; 2-4 bars is a starting point, not a sourced value.
2. **Cut over.** Schedule the faded outgoing buffer on deck A and the faded incoming buffer on deck B at the same engine sample: the bar-grid sample of the overlap start (SKILL.md Hard rule 4). No gain automation runs during the overlap.
3. **Memory.** The prepared windows are resident in addition to the next-transition budget in section 8. Release them when the overlap ends.
4. **Spike and verify.** Render the faded overlap offline and assert that the first non-zero sample of the incoming buffer lands on the planned cut-over sample and that the summed gain follows the chosen curve. On device, check for a click at the cut-over sample. Then verify offline (testing.md section 1) before anyone listens.

This is the default because it needs no automation call and can be checked offline. Its cost is the decoded-PCM path in section 8. Whether the window is prepared early enough is a design value and **spike-pending**.

### Options not used by default

- **Render-side gain** (a render-safe source or tap driven by a sample counter): the `AVAudioSourceNode` render-block contract is **unconfirmed**. Spike before use; follow section 7.
- **Scheduled volume steps** on `node.volume`: expect zipper noise; not used without a test.
- **AUScheduleParameterBlock** on a rampable parameter: documented semantics, but device behaviour is unconfirmed and developers report ramps with no effect. Spike before use.

Do not drive gains from a 60 Hz timer or a per-frame call.

## 4. Curves

- Equal power: outgoing cos(θ), incoming sin(θ), θ from 0 to π/2. Constant summed power; 0.707 each at the midpoint (−3.01 dB, computed).
- Linear: outgoing 1 − t, incoming t. Constant summed amplitude; 0.5 each at the midpoint (−6.02 dB, computed).
- Use equal power for two different pieces by default (uncorrelated material). Test the aligned bars before choosing. The correlation-to-curve mapping from DAFx-16 is **unconfirmed** (transitions.md section 7).
- **Correlated-pair test (Hard rule 10; synthesis, spike-pending):** render the overlap with each candidate curve twice: once for a correlated pair (one piece crossfaded with itself, offset by one bar), once for a decorrelated pair (two different pieces). Measure momentary loudness (0.4 s, EBU Tech 3341) across the join. The curve with the smaller dip on the correlated pair is the one to use. The dip tolerance is not sourced; calibrate it on known-good renders.

```swift
// sketch, not compiled: pre-compute the gains for one overlap
func equalPowerFade(frames: Int) -> (out: [Float], inn: [Float]) {
    (0..<frames).reduce(into: ([Float](), [Float]())) { acc, i in
        let theta = Float(i) / Float(max(frames - 1, 1)) * .pi / 2
        acc.0.append(cos(theta)); acc.1.append(sin(theta))
    }
}
```

## 5. Bass Swap

Idea: at a phrase boundary inside the overlap, cut the outgoing deck's low end and raise the incoming deck's low end, so only one bass line is audible at a time (DJ practice; the timing and blend lengths are **unconfirmed** in the sources).

### Default: pre-computed split, no runtime EQ (synthesis)

1. **Prepare.** On the prepare queue, split each prepared overlap window (section 3) into a low band and a remainder with an offline crossover. The filter type and cut-off (the sketch below uses about 150 Hz) are synthesis; **spike-pending**. Keep both bands as buffers of identical length.
2. **Cut over.** The outgoing low band ends and the incoming low band starts at the phrase-boundary sample inside the overlap, on the same sample grid as section 3. The remainders keep the section 3 curves.
3. **Verify** in the offline test: measure the low-band level across the join per band, not by ear alone (testing.md section 1).

The runtime EQ route is not the default. AVAudioUnitEQ behaviour is unconfirmed, and the sources name no scheduling call for its band gain. Sketch for reference only:

```swift
// sketch, not compiled; alternative only, not the default
let eqA = AVAudioUnitEQ(numberOfBands: 1)
eqA.bands[0].filterType = .lowShelf
eqA.bands[0].frequency = 150          // Hz; choice is synthesis
eqA.bands[0].gain = 0                 // no sample-scheduled call for this gain is named in the sources; spike before changing it
```

Insert `eqA` and `eqB` between each player node and the mixer only if this route is chosen. Behaviour of AVAudioUnitEQ was not confirmed in the sources; check its page.

## 6. Time Stretch and Pitch Limits

- `AVAudioUnitTimePitch`: `rate` accepts 1/32 to 32, default 1.0 (Apple; confirmed). `pitch` is documented in cents; **the unit was not checked** (unconfirmed). A forum post reports about 0.09 s latency (anecdotal).
- `AVAudioUnitVarispeed`: couples pitch and rate, like tape. Forum posts report lower latency than TimePitch (anecdotal; Apple not confirmed). Apple's sequencer sample uses Varispeed for tempo matching, so the pitch moves with the tempo.
- Quality of either unit under music-grade stretch is **unconfirmed**. Measure.
- **Rubber Band** (offline; GPL or commercial, see assets.md section 7): R3 gives better quality than R2 at much more CPU (README, confirmed).
- **Signalsmith Stretch** (MIT licence): reported best between 0.75x and 1.5x, degrading gradually beyond (repo and blog; not sceptic-checked).
- Rule: for a shared tempo, no runtime stretch. Any stretch to a target tempo is offline and verified (for example, stretch a piece to exact tempo with pitch kept, then re-measure the bar positions on the output).

## 7. Threading and Real-Time Rules

- Render thread (Apple QA1715, dated 2013-10-04, archived; scope confirmed): no synchronous file or network I/O, no memory allocation, no Objective-C messaging, no blocking APIs, no audio-session calls in the render callback. "Take locks" is not named there explicitly; it is implied by blocking APIs.
- Ross Bencina, "Real-time audio programming 101" (2011): no allocation, locks or disk I/O on the audio thread; lock-free queues to the control thread.
- Third-party AUv3 README (undated): rendering must not touch the Swift or Objective-C runtime.
- The sources found no current Apple guide on real-time safety for Swift. Use the rules above until one is found.
- Main thread: UI and intents only. The scheduler and state evaluator run on the dedicated queue (section 2). The main thread schedules nothing that decides a transition and does no file work. The earlier allowance for a director on the main actor is withdrawn, because it conflicts with SKILL.md Hard rule 1.
- Measure with System Trace (testing.md section 4): main-thread file I/O appears there.

## 8. Streaming Versus Preloaded Buffers

Memory (computed; decimal MB):
- Float32, stereo, 48 kHz: 384,000 bytes/s = 23.0 MB per minute.
- Int16, stereo, 48 kHz: 192,000 bytes/s = 11.5 MB per minute.
- A 198.4 s piece as float32: about 76 MB; as int16: about 38 MB.
- Example: five pieces totalling 772.7 s come to about 297 MB float32 and about 148 MB int16. Budget from the actual lengths, not from "five 3.3-minute pieces": some pieces in a score may be about 75 s.

Choices:
- **Stream from disk** (`scheduleSegment` from an `AVAudioFile`): low memory, but the I/O must be kept off the main thread. Apple does not document whether it streams or decodes on a background thread (**unconfirmed**); measure with Time Profiler.
- **Decode to PCM buffers at load**: memory cost is the table above; no I/O at decision time. Keep at least the pieces needed for the next transition resident.
- **Pre-open and prefetch** off the main thread at load. Never hash the file as a precondition for playing it.
- Keep decoded data out of the render thread's allocation path: allocate at load, reuse buffers.
- Whether `AVAudioFile` trims AAC priming and remainder frames automatically is **unconfirmed** (assets.md section 4).

## 9. Engine Configuration Changes

- `AVAudioEngineConfigurationChange` (Apple notification page; confirmed): posted when the I/O unit observes a change to the hardware channel count or sample rate. The engine stops and uninitialises itself; nodes stay attached; reconnect nodes if formats must change.
- "A restart is the usual fix" comes from secondary sources only (a Stack Overflow answer relaying Apple tech support, c. 2021; a forum thread). **Unconfirmed as Apple guidance.**
- Action: observe the notification on iOS and macOS, rebuild or reconnect the graph with the new format, restart the engine, and reschedule both decks from the current transport position.

```swift
// sketch, not compiled
NotificationCenter.default.addObserver(
    forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
) { _ in
    // stop the transport, reconnect nodes with the new format, restart the engine,
    // then reschedule from the current musical position
}
```

## 10. Manual Rendering for Tests

- `enableManualRenderingMode(.offline, format:, maximumFrameCount:)` and `renderOffline(_:to:)`: Apple's reference confirms the signature and that the engine renders on request (WWDC 2017 session 501; confirmed).
- **Precondition:** stop the engine before calling `enableManualRenderingMode` (Apple reference; confirmed in a sceptic pass). The render format must be PCM and match the buffer.
- Forum reports say a player node can return silence at the start of offline rendering (user reports; anecdotal). Check that the first render block is non-silent before measuring.
- The claim that the call must come before touching `mainMixerNode`, `inputNode` or `outputNode` is **not** on Apple's page; it came from a third-party header quote. Dropped; check the header if you rely on it.
- Keep the transition math as a pure function over sample buffers. Test that function directly, and test the player node only as an integration step (testing.md section 1).
- Default engine mode renders in real time. Manual mode is for faster-than-real-time work (Apple AVAudioEngine page).
