# Assets: Loudness, Authoring, Formats, Tools, App Size

## 1. Loudness Targets (Status of Each Number)

| Target | Source | Status |
|---|---|---|
| Home platforms: average −24 LKFS ±2 | Sony ASWG-R001 v1.10 (August 2013) | confirmed as document content; Sony-specific; does not cover iOS or macOS |
| Portable platforms: average −18 LKFS ±2 | same | confirmed as document content; whether it applies to iOS is unconfirmed |
| True peak at or below −1 dBTP | same | confirmed as document content |
| Measure at least 30 minutes | same | confirmed; a minimum over a representative cross-section of gameplay, not one pass |
| EBU R 128: −23 LUFS integrated | broadcast standard, via a vendor blog (2026-07-12) | secondary source |
| "−24 LUFS, −1 dBTP" for console and PC practice | practitioner claim | **unconfirmed** |
| "About −18" for mobile | a forum thread (2025-01-23) | anecdotal, **unconfirmed** |
| Apple game-loudness guidance | none found | not found |
| loudnorm `I=-16:TP=-1.5:LRA=11` | a third-party blog | **unconfirmed**; blog values, not targets |

Guidance (synthesis):
- Pick one integrated target for the whole score and apply a fixed per-piece gain offset. Do not use a time-varying normaliser inside a crossfade.
- Measure the spread first. If all pieces already sit within about 1 LU, loudness is unlikely to explain an audible switch; look at phase, key and grid first.
- Keep true peak at or below the chosen ceiling; check the peak after the offset is applied.

## 2. Measuring

- **EBU Tech 3341 (version 4, November 2023; confirmed):** momentary loudness uses a sliding rectangular window of 0.4 s; short-term loudness uses a sliding rectangular window of 3 s. In EBU Mode both are **ungated**; only integrated loudness uses BS.1770 gating (−70 LUFS absolute, −10 LU relative). Live meters update at least 10 times per second. The base ITU-R BS.1770 text was not checked.
- Use momentary (0.4 s) to see the join, and short-term (3 s) to see the level around it (testing.md section 1).
- **ffmpeg** (sketch; `ebur128` options were **unconfirmed** against the ffmpeg docs; check `ffmpeg -h filter=ebur128` first):

```sh
# sketch; verify options first
ffmpeg -nostats -i piece.wav -af ebur128=peak=true -f null - 2>&1 | tail -n 12
```

- The `afclip` filter and the two-pass `loudnorm` measurement mode: **unconfirmed**; no primary source found.

## 3. Authoring Requirements for the Composer

- **Cut on bar lines.** Loops, cue points and segment edges start on a bar line. At 140 BPM, 7 bars = 576000 samples = 12.000 s exactly (computed), so 7-bar cuts are sample-exact at 48 kHz at exactly 140 BPM only. Measured pieces are cut at their measured positions (transitions.md section 2), and the cut sample goes into the cue table. Cut points follow the phrase boundaries of the piece's P, not the 7-bar arithmetic.
- **Same tempo across pieces** and **identical stem length** (Phillips, GDC 2021; starchild.music, undated: stems share tempo and length; sourced as practice).
- **Keep the post-exit tail in the file** rather than cutting at the cue (Austin Haynes, undated, tested on Wwise 2025.1; single source).
- **Deliver exact sample counts** per segment. The engine places starts by sample position, so rounding in the file breaks the grid (synthesis).
- **Provide a cue table** with entry and exit bars, downbeat offset, bar count and last-bar length (transitions.md section 5).
- **Bridges** are not needed for a generic any-to-any overlap. Commission a bridge only for a specific pair the composer wants to write (synthesis).
- If a tempo change is unavoidable, do it offline and deliver the stretched file with its new sample count (stretch tools in section 7).

## 4. Gapless Playback and Exact Length

- **Apple QA1636** (archived; revised 2013-08-09; original 2009-02-20; confirmed in a sceptic pass): a gapless AAC stream needs three values: priming frames, remainder frames and packet count. Audio Queue Services trims them with `AudioQueueEnqueueBufferWithParameters` (`inTrimFramesAtStart`, `inTrimFramesAtEnd`).
- **Scope:** QA1636 covers Audio Queue Services only. It does not say how `AVAudioEngine` or `AVAudioPlayerNode` handles priming or remainder frames (sceptic correction). Whether `AVAudioFile` trims them automatically is **unconfirmed**.
- **Check with afinfo.** Its output reads `N valid frames + P priming + R remainder = total` (QA1636 example: 42998 valid + 2112 priming + 970 remainder = 46080).
- **Verification for the engine path (sceptic recommendation, not Apple guidance):** decode the delivered file to an `AVAudioPCMBuffer` and assert that the frame count equals the expected sample count from the cue table.

## 5. Format Decision

Sizes are computed from bit rate and are per minute of stereo at 48 kHz (decimal MB).

| Format | Size per minute | Notes |
|---|---|---|
| PCM float32 | 23.0 MB | no decode; largest; simplest for in-memory transitions |
| PCM int16 | 11.5 MB | half the size; check headroom and dither for the mix |
| AAC 256 kbit/s | 1.92 MB | score quality per a low-authority blog; test by ear |
| AAC 192 kbit/s | 1.44 MB | |
| AAC 128 kbit/s | 0.96 MB | often adequate for music (low-authority source) |
| ALAC (lossless, m4af) | **unconfirmed** | size depends on material; not sourced |
| Opus | **unconfirmed** | `kAudioFormatOpus` exists; a reading of Apple's page suggests CBR-only support in CAF at first (not sceptic-checked); decode in AVAudioEngine unconfirmed; native encode and decode reported from iOS 17 (Wikipedia) |
| IMA4 (4-bit ADPCM) | not sized | lower quality; no advantage here |

Recommendation (synthesis from the above):
- **Delivery:** AAC in CAF, if the length gate of section 5a passes for every segment. Otherwise the next option whose size budget allows.
- **Memory at runtime:** decode the pieces needed for the next transition into PCM buffers (budget: apple-engine.md section 8). Keep the delivered format and the runtime format separate.
- Opus: test before relying on it; AAC-in-CAF is the safer path given the unconfirmed CAF support.

### 5a. Length gate and size budget (synthesis)

Whether AVAudioFile trims AAC priming frames is unconfirmed (section 4), so the gate is the decision test, and it runs as a build step:

1. Encode the segment and read `afinfo` (valid, priming and remainder frames).
2. Decode it through the engine's own path (AVAudioFile to AVAudioPCMBuffer) and compare the frame count with the cue-table sample count.
3. Equal: pass. Not equal: correct the encoder trim so the valid frames equal the cue-table count, re-encode and repeat step 2. If the trim cannot be set, re-encode from a source cut at the exact sample count.
4. Still failing: fall back to an option the budget allows. ALAC in m4a has unconfirmed size and engine support, so test it first. 16-bit PCM has a computed size (section 5 table) and no listening test yet, so check headroom and dither by ear. Never ship a segment whose length does not match.

The build fails on any mismatch. Reason: a segment that is one sample off moves every later bar of its piece.

Size budget = delivered minutes × the per-minute size of the format (table in section 5). Compare the budget of each option for the whole set before choosing a format. The per-minute sizes are computed from bit rate, so the budget is arithmetic, not a measurement; measure the real files after encoding.

## 6. afconvert and afinfo

```sh
# AAC in CAF at 256 kbit/s (ss64 mirror of the afconvert man page; confirm flags with afconvert -h)
afconvert -d aac -b 256000 -f caff piece.wav piece.caf
# ALAC in M4A
afconvert -f m4af -d alac piece.wav piece.m4a
# priming, remainder and valid frames; then compare total with the cue table
afinfo piece.caf
```

- `afconvert -d 0` reportedly copies packets exactly (ss64; not sceptic-checked).
- The `-f caff -d aac` and `-f m4af -d alac` pairs are reported as supported; confirm on the build machine.

## 7. Analysis, Stretch and Key Tools (Licences)

| Tool | Use | Licence and status |
|---|---|---|
| Rubber Band | offline time-stretch and pitch shift; R3 better than R2, much more CPU | GPL version 2 or later; a commercial licence is needed for closed-source distribution; the README says it may not be distributed through the App Store without one (confirmed) |
| Signalsmith Stretch | time-stretch; best quality around 0.75x to 1.5x | MIT (repo; not sceptic-checked) |
| SoundTouch | time-stretch | LGPL (**unconfirmed**) |
| élastique | time-stretch | commercial (**unconfirmed**) |
| ffmpeg `atempo` | tempo 0.5 to 100; above 2x it skips samples rather than blending | ffmpeg licence; tempo range confirmed in current docs |
| librosa | beat tracking, tempo | ISC; `beat_track` exists; accuracy **unconfirmed** |
| madmom | beats, downbeats, tempo | code: BSD-style; **all model and data files CC BY-NC-SA 4.0**, non-commercial; commercial use needs the authors (confirmed) |
| Essentia | analysis | models CC BY-NC-SA 4.0 (not sceptic-checked); library licence **unconfirmed** |
| libKeyFinder | key detection | GPL version 3 (not sceptic-checked) |
| aubio | onset and beat | GPL (not sceptic-checked) |
| Apple Music Understanding framework | BPM and beat detection (used by Apple's sequencer sample) | licence and accuracy not evaluated |

Guidance (synthesis):
- **Licence gate for shipped stretched audio (synthesis):** until the owner records a licence decision for shipped output, the default offline stretch is Signalsmith Stretch (MIT licence). Rubber Band (GPL version 2 or later; commercial licence needed for closed-source distribution, confirmed) is used only after such a decision. Reason: an MIT tool raises no copyleft question, and small stretch ratios of a few percent sit inside the range the Signalsmith repository describes (not sceptic-checked; verify by analysis and by ear).
- Run GPL and non-commercial analysis or stretch tools on the authoring machine only; keep them out of the app bundle.
- Whether running a GPL tool offline to generate shipped audio creates obligations is **not verified** here. Get a licence review before shipping generated audio.
- Treat every analysis output (tempo, key, downbeat) as a hypothesis: check the bar grid by ear at each join, and check the key score gap (transitions.md section 6).

## 8. App Size and Delivery

- **Cellular download prompt:** a 200 MB figure appears in older sources (a 2019 announcement; a 2019 blog said iOS 13 lifted the limit; a Books help page). The current value is **unconfirmed**. Check Apple's current page before designing around a number.
- **On-Demand Resources:** Apple's current page (read in the research, not sceptic-checked) says ODR is deprecated from iOS 27, iPadOS 27, tvOS 27 and visionOS 27, with removal in future releases, and recommends Background Assets. Verify the exact sentence before quoting it.
- **Background Assets** (iOS 16+; tvOS 18.4+; not sceptic-checked): managed asset packs, or self-hosted unmanaged assets. Apple-hosted packs must be uploaded to App Store Connect before TestFlight or App Store distribution. Apple-hosted limits (200 GB, 200 packs per app) come from WWDC25 session 325; not sceptic-checked.
- **ODR on TestFlight:** **unconfirmed**. Do not rely on it for TestFlight testing.
- Optional content such as extra music packs can be unlocked by in-app purchase with Background Assets (WWDC25 325).
- Rule (synthesis): keep the core bundle small enough for the cellular prompt you can verify. Put optional music packs into Background Assets only if they are optional. Required music ships in the core bundle.
