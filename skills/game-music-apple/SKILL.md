---
name: game-music-apple
description: "Game music on iOS/macOS: beat-matched DJ-style crossfades, music states, AVAudioEngine on the audio clock, LUFS, gapless formats, tests. Use for Spielmusik, Musikübergang, Überblendung, Spannungsmusik, Musikstufen, crossfade, BPM, Tonart, music frame drops or app size."
allowed-tools: Read, Glob, Grep
---

# Game Music on Apple Platforms

Reference knowledge for designing and building adaptive game music on iOS, iPadOS and macOS. Read only the reference file for the step you are on.

## When to Use

- Making one piece hand over to another seamlessly (any-to-any, and back), or replacing bridge files
- Designing music states, intensity tiers, stingers or vertical layers
- Writing or reviewing AVAudioEngine / AVAudioPlayerNode playback, scheduling or gain curves
- Diagnosing music-related hitches or frame drops, or main-thread file work
- Choosing formats, loudness targets, app-size strategy or Background Assets
- Audio session behaviour: the player's own music, interruptions, route changes

Not for SFX-only design. Wwise and FMOD are named only for comparison.

German terms (the owner writes German): Spielmusik = game music; Musikübergang or Übergang zwischen Stücken = handover between pieces; Überblendung = crossfade; Spannungsmusik = tension music; Musikstufen = music tiers; Tonart = key; Lautheit = loudness.

## Project Profiles

A game may keep its measured music facts in `docs/engineering/MUSIC-PROFILE.md`. Read it first if present. This skill is general; project numbers and owner decisions belong in that file.

## Decision Path

1. **Measure the music.** Per piece: tempo, downbeat offset (in samples), measured samples per bar, bar count, last-bar length, key estimate with its confidence gap, integrated loudness, true peak, bass share. Check any manifest BPM against the audio.
2. **Choose the transition model** (`references/transitions.md`). Pair inside the tolerance: bar-aligned two-deck overlap. Outside it: stretch offline with pitch kept, then re-measure. Key clash: sparse section, shorter blend, filter, and offline pitch shift only as a last resort. Section types decide which bar pairs may overlap.
3. **Transport on the audio clock** (`references/apple-engine.md`). Both decks on one sample timeline, scheduled ahead. Never start, fade or decide from a frame timer or the main thread.
4. **State logic** (`references/state-design.md`). Evaluate at a low fixed rate from cheap counters; hysteresis on numeric signals, dwell and counts on booleans; every change executes at a phrase boundary.
5. **Assets and format** (`references/assets.md`). Bar-cut material of identical length, loudness-matched, sample-exact after encoding. Restricted-licence tools stay out of the shipped app.
6. **Test and measure** (`references/testing.md`). Render every ordered pair offline and assert on signals; run an A/B frame-rate test before optimising; listen with ABX; archive rendered files.

Platform rules (`references/platform.md`) apply at step 3 and throughout.

## Hard Rules

1. Never start, fade or decide a transition from a frame timer or the main thread. Schedule ahead on the audio clock.
2. Never open, decode, read or hash a music file on the main thread at decision time. Load and decode off the main thread before any decision needs the file.
3. Render thread: no file or network I/O, no allocation, no locks, no Objective-C or Swift runtime calls.
4. Compute bar positions as downbeatOffset + (N − 1) × samplesPerBar, with samplesPerBar measured per piece and stored in the cue table (576000/7 is exact only at 140 BPM and 48 kHz), rounded once. Never sum rounded bar lengths.
5. Every join starts on a phrase boundary of both pieces: bar 1 + k × P, with P per piece from the cue table (4, 8 or 16 bars; default 8, synthesis), counted from the measured bar 1, not from file start. The term is defined in `references/transitions.md` section 2.
6. Store per piece: downbeat offset in samples, bar count, last-bar length. Never derive entry or exit points from file length.
7. Escalate fast: at the next phrase boundary of the outgoing piece, at most P bars away (P = 4 for escalation sources). De-escalate slowly: minimum dwell, a calm count, and a tail until the wave is really over. Numeric signals get exit thresholds on the safe side of the entry thresholds; booleans are debounced by dwell and counts.
8. Prefer a generic rule-based two-deck overlap for any-to-any over pre-rendered bridge files per pair. Write a bridge only for a specific pair a composer wants.
9. Loudness-match all pieces to one target with a fixed per-piece gain offset, not a time-varying normaliser. Measure the spread before deciding a cause.
10. Default to equal-power gains for two different pieces. Test a correlated pair before assuming the curve.
11. Verify sample-exact lengths after encoding: the decoded frame count must equal the expected count. Do not trust encoder padding metadata alone.
12. Prove or rule out audio as a frame-rate cause with an A/B run (music on vs off, same seed, several runs) before optimising music code.
13. Pieces share a timeline without runtime stretching only inside the pair tolerance: |samplesPerBar A − samplesPerBar B| × overlap bars ≤ 96 samples at 48 kHz (`references/transitions.md` section 2). Any tempo change outside it is an offline step, verified by analysis and by ear.
14. Keep audio-session, interruption, route-change and engine-configuration handling in one place. Rebuild the graph after a configuration change.
15. Keep GPL, non-commercial (CC BY-NC-SA) and other restricted tools and models out of the shipped bundle. Check licences before shipping any dependency.

## Anti-Patterns Seen in Practice

- Fixed-length bridge files (about 15 s) between every pair of pieces. They sound like a switch phrase, ignore tempo and key, and grow as N × (N − 1).
- Bridge lengths that do not match the bar grid (a 15 s file is about 8.75 bars at 140 BPM).
- A 60 Hz main-thread timer deciding transitions, and a per-frame decision loop that re-requests the same state every frame.
- Opening and SHA-256 hashing whole music files on first use, on the main thread, at the moment a transition is requested, with no prefetch.
- Reserving the tension tier for the last wave or low health, so the calm track carries most of the combat.
- Blaming loudness for an audible switch without measuring the spread. Key and phase mismatches are the first things to check (synthesis).
- Dead asset sets and unused decode paths kept in the bundle and in docs after the code moved on.
- Calling a transition fixed on a passing unit test, without rendering it and listening.

## Evidence Labels

- **(confirmed)**: checked against the primary source in a sceptic pass.
- **(unconfirmed)**: not confirmed. Use only with a test or a check against the primary source.
- **(synthesis)**: engineering recommendation, not from a source.
- **(computed)**: arithmetic from stated inputs.

A **synthesis default** is a starting value to measure or tune, not a sourced fact; each one states its reason in the same sentence.

Several Apple API details came from secondary or archived pages. Check current Apple documentation before shipping. `sources.md` lists every URL with its date, the corrected claims and the unconfirmed claims.

## Reference Index

- `references/transitions.md`: DJ craft, phase and phrase alignment (phrase boundary, pair tolerance), bar arithmetic table, any-to-any recipe with re-entrant requests and section types, key clashes, blend types, middleware models, failure modes.
- `references/apple-engine.md`: AVAudioEngine two-deck transport, scheduling, gain automation, curves, bass swap, time-pitch limits, threading, memory, configuration changes, manual rendering.
- `references/state-design.md`: gameplay to tiers, counters, the generic transition matrix, tail and dwell, hysteresis, escalation timing, stingers, layering, evaluation rate.
- `references/assets.md`: loudness targets and measurement, authoring rules, gapless verification, formats with sizes, analysis and stretch tools with licences, app size and Background Assets.
- `references/platform.md`: session categories, secondary-audio hint, interruptions, route changes, lifecycle, macOS differences, volumes and ducking.
- `references/testing.md`: offline transition tests, signal assertions, fake-clock tests, A/B frame-rate protocol, Instruments and signposts, listening tests, runtime telemetry.
- `sources.md`: URLs and dates, supported claims, corrected claims, unconfirmed claims.
