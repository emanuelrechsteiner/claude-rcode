# Transitions Between Pieces

Goal: a handover from any piece to any other piece, and back, that a listener does not hear as a switch. The owner's wording for the target: a DJ crossfade that matches speed, beat phase, key and pitch, and style.

## 1. What a DJ Does (the Craft to Copy)

- **Beatmatching** = match tempo, then align beat phase (Mixxx 2.4 manual; the definition was not sceptic-checked).
- **Sync Lock with Dynamic Tempo** (Mixxx 2.4 manual, sections 12.3-12.4; reported, not re-fetched, unconfirmed in sources.md section 9): the outgoing track's tempo drives the other during the transition; key lock keeps pitch fixed through a tempo change.
- **Auto DJ** (Mixxx 2.4 manual, section 12.8, confirmed): four crossfade modes: Full Intro + Outro (default), Fade At Outro Start, Full Track, Skip Silence. The crossfade length is the shorter of outro and intro. The manual says Auto DJ "does not take into account the volume of each track, nor the frequency content, nor the rhythms." Reading that as "no beatmatching" is inference only.
- **Spotify Mix** (newsroom, 2025-08-19): an Auto preset plus customisable presets such as Fade and Rise; transition points set on the waveform. A product example, not a method.
- Mapping to this skill: speed = tempo (section 4 and 3); beat phase = section 2; key and pitch = section 6; style = density and instrumentation per section (section 9).

## 2. Phase and Phrase Alignment

- **Switch points on 4-bar periods (the sourced period, P = 4).** Zehren, Alunno and Bientinesi (ISMIR 2020, arXiv:2007.08411; confirmed). A switch point needs novelty (rhythm, loudness, timbre or harmony), a downbeat at the start of a 4-bar period, and a salient section after it. On 134 EDM tracks at 99-147 BPM: precision 86% and recall 49% in the strict 0.5 s window. Expert listening judged 95.8% of generated candidates usable (their section 5.3). The method does no tempo matching and no key detection.
- **Cue spacing.** CUE-DETR (arXiv:2407.06823, submitted 2024-07-09; confirmed numbers). Precision 0.38 at ±1 beat for the r16 variant (r8: 0.32), against 0.14 for Automix and 0.20 for Mixed In Key. Measured on a 101-track test split with 607 annotations, out of 4,710 EDM tracks at 95-190 BPM. **Author attribution unconfirmed.** The sceptic pass reports that 16- and 8-bar phrasing dominates cue spacing in that paper; not independently checked.
- **Automix's four rules**: not described in the sources read. Unconfirmed; not used.
- **Phase** is where the beat sits inside the bar. Two pieces at the same tempo still clash if their bar 1 sits at different offsets. Measure the downbeat offset of every piece.

**Phrase boundary (the one term this skill uses).** Bar 1 + k × P, counted from the piece's measured bar 1, where P is the piece's phrase length in the cue table: 4, 8 or 16 bars. P = 4 is the period the sourced switch-point method uses (Zehren et al.). P = 8 is the default for generic music (synthesis; reason: CUE-DETR reports 16- and 8-bar phrasing as dominant in cue spacing, not independently checked; 8 is the shorter of the two and gives the finer join grid). Every join starts on a phrase boundary of the outgoing piece and of the incoming piece. Escalation executes at the next phrase boundary of the outgoing piece, so its wait is below P bars. A piece used as an escalation source needs P = 4 (synthesis; reason: an 8-bar wait is 13.7 s at 140 BPM, too long for a wave already on the field).

**Pair tolerance (synthesis; the 96-sample budget is the beat-offset tolerance of `testing.md` section 1).** Each piece's bars are placed from its own measured samplesPerBar, never from the nominal tempo. Two pieces may overlap for k bars without runtime stretching while |samplesPerBar(A) − samplesPerBar(B)| × k ≤ 96 samples at 48 kHz. A piece whose bars do not fit one samplesPerBar within 96 samples over its whole length is not steady and goes offline (stretch or re-cut) before use. Reason: a join test that allows 96 samples cannot pass a grid that drifts further than that, so the pair rule and the test use one budget.

### Bar arithmetic (computed; 48 kHz; nominal tempos only)

| BPM | Beat (s) | Beat (samples) | Bar (s) | Bar (samples) | 4 bars (s) | 8 bars (s) | 16 bars (s) | 32 bars (s) |
|---|---|---|---|---|---|---|---|---|
| 120 | 0.500000 | 24000 | 2.000000 | 96000 | 8.000 | 16.000 | 32.000 | 64.000 |
| 128 | 0.468750 | 22500 | 1.875000 | 90000 | 7.500 | 15.000 | 30.000 | 60.000 |
| 140 | 0.428571 | 20571.43 | 1.714286 | 82285.71 | 6.857 | 13.714 | 27.429 | 54.857 |
| 150 | 0.400000 | 19200 | 1.600000 | 76800 | 6.400 | 12.800 | 25.600 | 51.200 |

- At 140 BPM, 4 / 8 / 16 / 32 bars are 329142.86 / 658285.71 / 1316571.43 / 2633142.86 samples. Round once from N × samplesPerBar; do not accumulate.
- At 140 BPM, 7 bars = 576000 samples = 12.000 s exactly; 7 beats = 144000 samples = 3.000 s exactly. Seven-bar cut points are therefore sample-exact.
- 120, 128 and 150 BPM give integer-sample bars; 140 BPM does not.
- A 15 s bridge at 140 BPM is 8.75 bars, so it cannot start or end on a bar line.

**Position formula (synthesis):** sample position of bar N = downbeatOffsetSamples + (N − 1) × samplesPerBar, with samplesPerBar the measured value from the cue table (the exact rational only for a piece at exactly its nominal tempo), rounded once.

## 3. Tempo and Key Ranges (Vendor Assertions, Unconfirmed)

- DJ.Studio (vendor, no date in fetch): ±4-8% tempo change is "common DJ tempo matching"; ±1-4 semitones are "realistic harmonic-mixing intervals"; vocals and sustained instruments reveal tuning problems first. **Unconfirmed**: no data behind the figures. Label them as vendor assertions.
- DJ.Studio (second article, 2026, not sceptic-checked): ±3-5 BPM is usually safe in high-quality stretch modes. Vendor claim; engine choice matters more than the DAW's summing.
- For a shared tempo, no runtime stretch is needed. Treat these ranges only as a rough envelope for offline stretching.

## 4. Any-to-Any Recipe (Synthesis)

For pieces inside the pair tolerance (section 2) at one sample rate. No runtime time-stretch.

1. **Cue table per piece** (section 5): entry and exit bars on phrase boundaries, section type (4.2), measured samplesPerBar with its fit residual, key estimate with confidence.
2. **Precompute for every directed pair** (N × (N − 1) pairs) a compatible exit bar in A, an entry bar in B, the section code (4.2) and the clash rung (6). Store this as data, not as audio.
3. **Align the grid.** Schedule B so that its entry bar starts at the same timeline sample where A's exit bar starts. Both starts come from exact sample positions on one clock.
4. **Overlap k bars.** 2-4 bars is a starting point, not a sourced value. Equal-power gains: A down, B up.
5. **Bass swap** at a phrase boundary inside the overlap: the incoming deck takes the low end (apple-engine.md section 5).
6. **Tail or filter** on the outgoing deck where spectra clash (section 7).
7. **Hand over.** After the overlap, A stops; B's grid becomes the master.
8. **Round trip** reuses the same cue tables. No per-pair audio file.
9. **Verify offline** (testing.md section 1) before anyone listens.

### 4.1 Two-deck state and re-entrant requests (synthesis)

Two states: IDLE (one deck live) and OVERLAP (outgoing fading out, incoming fading in; the incoming grid is the master).

- A request in IDLE starts an overlap at the next phrase boundary of the outgoing piece.
- A request during OVERLAP changes nothing now and never cuts the overlap short. It replaces any pending request (newest wins; no queue). When the overlap ends, a pending request whose target differs from the new master starts an overlap from the new master at its next phrase boundary. A pending request equal to the new master is dropped.
- Reason: a cut overlap is the hard switch the owner reported; a queue of requests would play out stale states; newest-wins follows the current game state.
- Cost (accepted): an urgent escalation during an overlap waits for the overlap to end, plus up to P bars. Where that wait is too long, a shorter overlap for that pair (rung 2 of section 6) is the remedy, not a cut.

### 4.2 Section types and the pair decision (synthesis)

Closed set of section types: intro, groove, breakdown, build, peak. Density class: sparse = intro and breakdown; full = groove, build and peak. Each bar range of a piece gets one type in the cue table, labelled from the score (a composed score knows its sections; measurement only confirms). Intro is an entry type only.

Pair code from the exit type (rows) and the entry type (columns):

| Exit (rows) / entry (columns) | intro | groove | breakdown | build | peak |
|---|---|---|---|---|---|
| groove | S | O | S | O | O |
| breakdown | S | O | O | S | S |
| build | X | S | S | O | O |
| peak | X | S | S | S | O |

- **O**: bass-swap overlap of 2-4 bars (step 5 above).
- **S**: short overlap of 1-2 bars, or a blend carried by the sparse side (drums only or pads only).
- **X**: no direct join; route through a groove or breakdown section of one piece first.

Reason: full-to-full overlaps are the default; a full mix blended with a sparse section is the density mismatch of section 9, so the sparse side carries the blend; a build or peak into an intro leaves a dense-to-sparse gap that needs a breakdown first. No source settles this table; tune it by ear (synthesis). The pair table stores the code per pair. The key-clash rung (section 6) can downgrade O to S, never upgrade.

## 5. Cue Table (Per Piece)

Store next to the manifest: piece id, file, sample rate, downbeat offset (samples), measured samples per bar with its fit residual, bar count, last-bar length (samples), phrase length P (4, 8 or 16 bars), entry bars (section type from 4.2, strength), exit bars (section type, density, key), key estimate with confidence gap, tempo estimate with residual.

- A composed score knows its own grid and key. Measure to confirm, not to guess (synthesis).
- Measurements are heuristic. Verify the grid by ear at the joins; a manifest's BPM may not match the audio.

## 6. Key Clashes

- **Camelot-style rules are a vendor convention** (Mixed In Key and DJ.Studio guides; not peer-reviewed, not a standard). They are used here only as the compatibility test in the clash rule below: compatible when the keys are the same, on adjacent wheel numbers with the same letter, or relative major/minor (same number, other letter). A diagonal step is not compatible under this rule (computed from the rule).
- **Energy boost (corrected)**: the earlier research called a "+2 semitone energy boost" unconfirmed. The sceptic pass refuted that: DJ.Studio's compatible-keys page describes a two-step clockwise Camelot move (for example 9B to 11B) as shifting the key centre up two semitones, with a clash warning. It is a vendor taxonomy, not a Mixed In Key or peer-reviewed source.
- **Key estimates are heuristics.** A small gap between the top two key scores is not reliable. Set a reliability floor on that gap from measured data (synthesis; the project's floor is recorded in its profile, not here).
- **Clash test and rung selection (synthesis):**
  1. If either key is below the reliability floor, the pair status is open. Plan it as a clash until a listening check passes.
  2. Both keys reliable: compatible when the keys are equal or Camelot-compatible (above); otherwise a clash.
  3. Compatible: the section code (4.2) decides the join. Clash or open: take the first rung below whose check passes by ear.
  4. Ladder: rung 1, move the blend point into a sparse section (drums only, pads only, or a breakdown; section code S); rung 2, shorten the overlap to 1-2 bars; rung 3, filter the outgoing key (high-pass or low-pass sweep) so its pitched content is gone before the incoming key lands; rung 4, pitch-shift one piece offline to a compatible key and check by ear. Only then consider a runtime pitch shift (apple-engine.md section 6).
  5. Store the selected rung, both key estimates and their gap in the pair table. Rung 4 needs a pitched variant of that piece, an extra copy of its audio in the asset budget (assets.md section 5a).
  Reason for the order: rungs are ordered by added processing and asset cost, cheapest first (synthesis).

## 7. Blend Types

| Blend | How | Use when | Status |
|---|---|---|---|
| Long equal-power blend with bass swap | 2-4 bar overlap; low end moves at a phrase boundary | default for shared-tempo pieces | synthesis; typical DJ blend lengths unconfirmed |
| Filter sweep | high-pass on outgoing, low-pass on incoming | key clash, texture change | synthesis |
| Echo or reverb out | outgoing tail rings over the incoming start | hiding a hard cut or a spectral clash | synthesis |
| Cut on the one | incoming starts on a downbeat with no overlap | only compatible entries; grids must match | synthesis |

**Curves (computed unless stated):**
- Equal power: outgoing cos(θ), incoming sin(θ), θ from 0 to π/2. Summed power stays constant. At the midpoint each gain is 0.707, i.e. −3.01 dB.
- Linear: outgoing 1 − t, incoming t. Summed amplitude stays at 1. At the midpoint each gain is 0.5, i.e. −6.02 dB.
- Fink, Holters and Zölzer (DAFx-16) propose correlation-dependent curves. The −3 dB / −6 dB mapping to correlation is **unconfirmed**; the DAFx archive abstract confirms only that a correlation-based design is derived.
- Equal power keeps power, not perceived loudness. Pieces with different mastering still need loudness matching (assets.md).

## 8. Game-Middleware Transition Models

- **Horizontal re-sequencing with a transition matrix** (Wwise Music Switch containers; Whitmore, 2003-05-28). One rule per source and destination pair. The source exits at Next Grid, Next Beat, Next Bar, Next Cue, Next Custom Cue or Exit Cue; the destination enters at its Entry Cue or at the same time (Wwise 2025.1 help; not sceptic-checked).
- **Transition segments** (Wwise 2025.1 help; not sceptic-checked): a bridge between source and destination with optional pre-entry, post-exit and fades. Post-exit plays only if the source exits at its Exit Cue or fades at or past it, so an earlier exit skips it.
- **Rule order (first match)** in a Wwise matrix: **unconfirmed**. The 2008 review cited for it covers Wwise 2007.1 and is outdated.
- **Exit cues as on/off gates** (a community answer): **unconfirmed** in current Wwise.
- **FMOD Studio** (2.04 docs, date unconfirmed): transition regions quantised to beats or bars; transition timelines carry the playhead to the destination.
- **Vertical layering** (Phillips, GDC 2021; starchild.music, undated): stems of identical length and tempo, played in sync and faded by state. Changes intensity, not harmony or form, so most scores combine it with horizontal segments.
- **Stingers**: short phrases over the current music for one-off events. Wwise has a "Using Stingers" topic; not read.
- **Sync** (Whitmore, 2003): pure crossfades without bar or beat sync are "a musical slide show". Use bar or beat sync, or a dovetailed overlap.
- **Timing** (joffwinks, 2023-02-25; not sceptic-checked): at 120 BPM, a transition point every 5 beats is 2.5 s apart (computed; the article's 2 s figure does not match 5 beats), so the wait is up to 2.5 s. A finer grid shortens the wait.

| Model | Good for | Costs |
|---|---|---|
| Two-deck bar-synced overlap (any-to-any) | continuous music over pieces sharing a grid | cue tables, analysis, clash risk |
| Rule matrix with exit cues and transition segments | a few states; composer controls the handover | per-pair rules; middleware or an own engine |
| Pre-rendered per-pair bridges | a composer wants one specific phrase for one pair | N × (N − 1) files; not tempo-aware; large bundle |
| Vertical layering (stems) | intensity change without a key or tempo change | identical stem lengths; no harmony change |
| Stingers | one-off accent over the current music | not a state change |

## 9. What Makes a Transition Sound Bad, and the Fix

| Symptom | Usual cause | Fix |
|---|---|---|
| Audible intermediate track, "switch phrase" | pre-rendered bridge instead of an overlap | two live decks, bar-aligned overlap |
| Off-beat start, flam, drift | bar grid not exact, or downbeat offset not measured | exact sample positions; measured offsets; beat-offset assertion in tests |
| Level dip or bump | uneven loudness, wrong curve | loudness-match; equal power for uncorrelated material; check short-term loudness across the join |
| Hollow or phasey overlap | non-aligned grids overlapping | align first; shorten; filter |
| Click at the start | start at a non-zero sample with a step gain | ramp from zero; pre-computed fade (apple-engine.md section 3) |
| Long wait for an exit | phrase length P too long for an escalation source | P = 4 for that piece (section 2); exit cues in middleware |
| Missing tail | exit before the post-exit segment | keep the tail in the file; exit at the designed point |
| Key clash | incompatible keys | fallback ladder, section 6 |
| Late or stalled transition | decision on main thread; file opened at decision time | schedule ahead; pre-open; decode off the main thread |
| Tempo mismatch | pair tolerance exceeded, or a piece's bars not steady | offline stretch with pitch kept, then re-measure samplesPerBar |
| Second request during an overlap: abrupt cut, or requests stacking | overlap cut short, or pending requests queued | never cut; newest pending request only (4.1) |
| Density mismatch (style) | a dense section blended with a sparse one | blend at a section boundary, or use a sparse section. Measure onset rate and bass share: a flat onset rate can hide a bass-heavy versus light split |
