# Sources, Corrections and Open Claims

Research base: a web and documentation pass dated 2026-11-12 on six topics (DJ transitions, Apple two-deck playback, platform behaviour, state design, assets and loudness, testing and measuring). Each topic had a separate sceptic pass with a verdict per claim (confirmed, refuted, outdated, unconfirmed). Status column: **confirmed** = sceptic-confirmed; **corrected** = the claim was wrong or overstated and the corrected form is used; **unconfirmed** = labelled or left out; **not checked** = single source, not sceptic-checked.

## 1. Transitions and DJ Practice

| URL | Date / access | Supports | Status |
|---|---|---|---|
| https://manual.mixxx.org/2.4/en/chapters/djing_with_mixxx | Mixxx 2.4 manual, accessed 2026-11-12 | Auto DJ modes and shorter-section crossfade (section 12.8); beatmatch definition, key lock and automatic key detection (not among the sceptic claims); Sync Lock with Dynamic Tempo (sections 12.3-12.4, reported, not re-fetched) | confirmed (section 12.8 only); the rest not sceptic-checked |
| https://manual.mixxx.org/2.4/de/chapters/djing_with_mixxx | Mixxx 2.4 manual (German), undated | beatmatch as tempo plus phase; key lock | not checked |
| https://github.com/mixxxdj/mixxx/issues/14067 | date not confirmed | proposal for incremental tempo ramping of both tracks (feature request, not shipped) | not checked |
| https://newsroom.spotify.com/2025-08-19/mix-your-favorite-playlists-seamlessly-by-adding-your-own-transitions/ | 2025-08-19 | Auto and customisable transition presets; waveform transition points | not checked |
| https://arxiv.org/html/2007.08411v1 | Zehren, Alunno, Bientinesi, ISMIR 2020 | switch-point rules; 4-bar downbeat; precision 86% and recall 49% on 134 tracks at 99-147 BPM; 95.8% usable with listening (section 5.3); no tempo or key method | confirmed; subjective figure added by corrections |
| https://arxiv.org/html/2407.06823v1 | submitted 2024-07-09 | CUE-DETR precision 0.38 (r16; r8 0.32) vs Automix 0.14 and Mixed In Key 0.20; 4,710 tracks; 101-track test split, 607 annotations | confirmed numbers; author attribution unconfirmed |
| https://mixedinkey.com/wiki/harmonic-mixing-explained-everything-you-need-to-know/ | undated, vendor | Camelot compatibility rules | vendor convention; not peer-reviewed |
| https://dj.studio/blog/compatible-keys | undated, vendor | two-step energy boost of two semitones with clash warning | corrected (section 8, item 1) |
| https://dj.studio/blog/workflow-benchmark-mashup-mixing-software | 2026 in title; no date in fetch | tempo change ±4-8%; harmonic ±1-4 semitones; vocals reveal tuning | unconfirmed (vendor assertion) |
| https://dj.studio/blog/daw-audio-quality-playbook-engines-summing | 2026, undated in fetch | ±3-5 BPM safe in high-quality stretch; engine choice | not checked (vendor) |

## 2. Apple Two-Deck Playback, Scheduling and Gain

| URL | Date / access | Supports | Status |
|---|---|---|---|
| https://developer.apple.com/documentation/avfaudio/avaudioplayernode | current, accessed 2026-11-12 | `when` parameter: nil, sample time, host time; `nodeTime(forPlayerTime:)`; `stop()` resets to sample 0; `prepare(withFrameCount:)` | confirmed |
| https://developer.apple.com/forums/thread/14138 | old, undated | start two players together from a reference `lastRenderTime` | not checked (secondary) |
| https://github.com/AudioKit/AudioKit/issues/940 | third-party issue | do not call `stop()` in a completion handler (deadlock) | corrected: not Apple's statement |
| https://developer.apple.com/documentation/audiotoolbox/auscheduleparameterblock | 2026 | parameter-block signature; ramp value at end; non-rampable parameters ignore ramp; 4096-frame offset for render-observer scheduling | confirmed; "only" in one reading was overstated |
| https://developer.apple.com/documentation/avfaudio/avaudiomixing/volume | 2026 | volume implemented by EnvironmentNode and MixerNode; no ramp documented | confirmed; PlayerNode conformance noted |
| https://developer.apple.com/forums/thread/781313 | date not shown | crackling when outputVolume is stepped every 10 ms; Feedback report | not checked (anecdotal) |
| https://developer.apple.com/documentation/avfoundation/avaudiomixinputparameters | 2026 | linear volume ramps for asset-based mixing (not the engine path) | not checked |
| https://developer.apple.com/documentation/avfaudio/performing-offline-audio-processing | title only fetched | offline manual rendering (WWDC 2017 session 501) | not checked |
| https://developer.apple.com/documentation/avfaudio/avaudioengine/enablemanualrenderingmode(_:format:maximumframecount:) | current | signature; engine renders on request; stop engine first; PCM format | confirmed; precondition added |
| https://developer.apple.com/forums/thread/111249 | date unknown | offline rendering silent at start | unconfirmed (anecdotal) |
| https://developer.apple.com/documentation/avfaudio/avaudioengine | 2026 | real-time default; manual mode for faster-than-real-time | not checked |
| https://asciiwwdc.com/2017/sessions/501 | 2017-06, mirror | WWDC 2017 session 501, offline rendering | not checked (mirror) |
| https://developer.apple.com/library/archive/qa/qa1715/_index.html | dated 2013-10-04 | render thread rules; blocking calls; no audio-session calls in render callback | confirmed; scope narrowed; "take locks" not explicit |
| http://www.rossbencina.com/code/real-time-audio-programming-101-time-waits-for-nothing | 2011 | no allocation, locks or disk I/O on audio thread | not checked |
| https://github.com/bradhowes/LPF/blob/main/Documentation/APPLE_README.md | undated, third-party | no Swift or Objective-C runtime on render | not checked |
| https://www.hsu-hh.de/ant/wp-content/uploads/sites/699/2017/10/Fink-Holters-Zölzer-2016-Signal-matched-power-complementary-cross-fading-and-dry-wet-mixing.pdf | 2016; read via search excerpt | correlation-dependent curves | -3/-6 dB figures unconfirmed |
| https://dafx.de/paper-archive/details/gUO-U6xEDk0Z_m4S-PivJQ | DAFx archive abstract | correlation-based fading design derived | confirmed abstract only |
| https://developer.apple.com/documentation/avfaudio/avaudiounittimepitch/rate | current | rate 1/32 to 32; default 1.0 | confirmed |
| https://developer.apple.com/documentation/avfaudio/avaudiounittimepitch | 2026 | rate and pitch properties; overlap | pitch unit (cents) unconfirmed |
| https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification | current | notification fires on channel-count or sample-rate change; engine stops; reconnect | confirmed; earlier wording corrected |
| https://stackoverflow.com/questions/66923293/avaudioengine-audio-stops-when-switching-the-audio-output-device | c. 2021 | restart as usual fix (relayed Apple support answer) | unconfirmed as Apple guidance |
| https://developer.apple.com/documentation/avfoundation/building-an-audio-sequencer-to-arrange-and-play-clips | sample; macOS 27.0+ / Xcode 27.0+ | host-time scheduling; reschedule each loop; 50 ms resync; volume set 0 then 1 (not a ramp); Varispeed; Music Understanding for BPM and beats | confirmed; corrected (no ramp; macOS-only as listed) |
| https://developer.apple.com/documentation/avfaudio/avaudioplayernodebufferoptions | current | `loops` option is for buffers | not checked |
| https://developer.apple.com/documentation/avfaudio/avaudiosequencer | current | AVAudioSequencer bar and beat sequencing | not checked |
| https://developer.apple.com/documentation/phase | iOS 15+ | spatial audio framework (not bar-synced music) | not checked |
| https://developer.apple.com/documentation/coreaudiotypes/kaudioformatopus | current | Opus format identifier | not checked |
| https://developer.apple.com/documentation/audiotoolbox/1620452-hardware-codec-capabilities | iOS 3 era | hardware codec capability query | not checked; old |
| https://web.dev/articles/audio-scheduling | last updated 2013-01-09 | look-ahead scheduling: about 25 ms timer, about 100 ms ahead | not checked (Web Audio; principle only) |
| https://forums.steinberg.net/t/zipper-noise-on-channel-and-master-faders/753010 | vendor forum | zipper noise and per-sample smoothing | not checked (not authoritative) |

## 3. Adaptive Music and Middleware

| URL | Date / access | Supports | Status |
|---|---|---|---|
| https://www.audiokinetic.com/en/public-library/2025.1.12_9287/?source=Help&id=transitions_tab_music_objects | Wwise 2025.1 help | music switch exit and entry options; post-exit rule | not checked |
| https://www.audiokinetic.com/en/public-library/2025.1.12_9287/?source=Help&id=using_transition_segments | Wwise 2025.1 help | transition segments with pre-entry, post-exit, fades | not checked |
| https://www.audiokinetic.com/library/2025.1.8_9170/?source=Help&id=ErrorCode_CannotScheduleMusicSwitch | Wwise 2025.1 | error when fades do not fit the rule | not checked |
| https://www.audiokinetic.com/qa/11238/musictransitions-paste-out-of-order | Wwise 2023.1.10 community | rule order changes on paste | unconfirmed as a rule-order fact |
| https://www.audiokinetic.com/qa/1068/interactive-custom-transitions-trigger-before-activated | undated community | exit cues behave as gates | unconfirmed in current Wwise |
| https://www.mixonline.com/technology/field-test-audiokinetic-wwise-20071-videogame-software-370316 | c. 2008, review of Wwise 2007.1 | first-match rule order | outdated; not used as a basis |
| https://www.audiokinetic.com/learn/videos/zvnt3tbl3ou/ | undated | horizontal and vertical music structures | not checked; transcript did not show the technique |
| https://www.audiokinetic.com/en/community/blog/free-wwise-for-indie-developers/ | undated | Wwise indie terms | not checked; verify current terms |
| https://www.gamedeveloper.com/audio/design-with-music-in-mind-a-guide-to-adaptive-audio-for-game-designers | 2003-05-28 (Whitmore) | transition matrix; "musical slide show"; MIDI-style material for key changes | not checked (old) |
| https://www.gamedeveloper.com/game-platforms/pure-vertical-layering-for-game-music-composers-from-spyder-to-sackboy-gdc-2021- | GDC 2021 (Phillips); exact article date unconfirmed | vertical layering definition | not checked |
| https://starchild.music/blog/how-video-game-music-adapts | undated | layering cannot change harmony or form | not checked |
| https://www.fmod.com/docs/2.04/studio/authoring-events.html | FMOD 2.04 docs; date unconfirmed | quantised transition regions; transition timelines | not checked |
| https://www.fmod.com/licensing | current | FMOD licence thresholds | not checked; verify current terms |
| https://www.joffwinks.com/blog/2023/2/25/the-sound-of-arctic-awakening-adaptive-music-in-video-games | 2023-02-25 | 120 BPM; a transition point every 5 beats (the article's 2 s wait does not match 5 beats: 2.5 s, computed; see section 8 item 27) | not checked |
| https://www.austinhaynesmusic.com/wwise-music-loop-reverb-tail | undated; tested on Wwise 2025.1 | keep tails in the file; loop-point checks | not checked (single source) |
| https://gdcvault.com/play/1012601/Adaptive-Music-The-Secret-Lies | year not in excerpt | adaptive transitions framed by melody, harmony, rhythm, form | not checked |
| https://www.gdcvault.com/play/mediaProxy.php?sid=1015511 | year unconfirmed | automated audio testing (Audiokinetic talk) | unconfirmed |

## 4. State Design and Shipped Examples

| URL | Date / access | Supports | Status |
|---|---|---|---|
| https://steamcdn-a.akamaihd.net/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf | GDC 2009 slides (Booth) | four states; Sustain Peak 3-5 s; Relax 30-45 s; Peak Fade rationale; max intensity across survivors | confirmed (primary) |
| https://www.cs.drexel.edu/~santi/teaching/2012/CS680/papers/11%20Secrets%20about%20LEFT%204%20DEAD%E2%80%99s%20AI%20Director%20and%20its%20Procedural%20Zombie%20Population%20%7C%20AiGameDev.com.pdf | 2009-10-07 transcription | "another mob" wording | secondary; the wording is not in the primary slides |
| https://sifter.com.au/post/the-ingredients-of-doom-composer-mick-gordon-on-the-soundtrack-of-doom-eternal | 2020 interview | four DOOM Eternal music categories | confirmed as the source of the categories (corrected attribution) |
| https://gamedeveloper.com/audio/at-gdc-2017-get-a-behind-the-scenes-look-at-composing-music-for-i-doom-i- | GDC 2017 listing | DOOM (2016) talk page | does not contain the Eternal categories |
| https://plantsvszombies.fandom.com/wiki/Music | undated, fan wiki | horde theme | unconfirmed |
| https://gdcvault.com/play/1023974/Always-Be-Composing-The-Flexible | 2017; login-gated | Plants vs. Zombies Heroes music system | unconfirmed |
| https://www.theouterhaven.net/2021/09/in-discussion-supergiant-games-greg-kasavin/ | 2021-09 interview | variable dwell time in a piece | not checked; single interview |

## 5. Loudness, Measurement and Assets

| URL | Date / access | Supports | Status |
|---|---|---|---|
| http://gameaudiopodcast.com/ASWG-R001.pdf | v1.10, August 2013 | −24 LKFS home, −18 LKFS portable, −1 dBTP, 30-minute measurement | confirmed; Sony-specific; applicability to iOS unconfirmed |
| https://www.airwiggles.com/c/gameaudio/peak-level-and-lufs-for-game-audio | 2025-01-23 forum | "−24 LUFS, −1 dBTP" practice; "−18" for portable | unconfirmed (anecdotal) |
| https://www.soundbridge.io/loudness-normalization-a-mixing-and-mastering-guide | 2026-07-12 | EBU R 128 −23 LUFS | secondary |
| https://www.ffmpeg-micro.com/blog/ffmpeg-loudnorm-filter-ebu-r128 | undated | loudnorm option values | unconfirmed |
| https://tech.ebu.ch/docs/tech/tech3341.pdf | V4, November 2023 | momentary 0.4 s; short-term 3 s; ungated in EBU Mode | confirmed; date now known |
| https://tech.ebu.ch/docs/tech/tech3343-v2.pdf | date not confirmed | advice against LRA under one minute | not checked |
| https://en.wikipedia.org/wiki/EBU_R_128 | undated | disputed gating (resolved for EBU Mode by Tech 3341) | superseded by Tech 3341 |
| https://www.itu.int/rec/R-REC-BS.1534 | BS.1534-3, 10/2015, in force | MUSHRA, hidden reference and anchor | confirmed |
| https://www.forasoft.com/learn/audio-for-video/articles-audio/subjective-testing-mushra-mos-ab-abx | undated secondary | BS.1116; ABX binomial test | not checked (secondary) |
| https://developer.apple.com/library/archive/qa/qa1636/_index.html | revised 2013-08-09; original 2009-02-20 | gapless AAC: priming, remainder, packet count; Audio Queue trimming; afinfo format | confirmed; Audio Queue scope only |
| https://github.com/breakfastquay/rubberband | 2024 copyright | GPL version 2 or later; commercial licence; App Store note; R3 quality and CPU | confirmed |
| https://thebreakfastpost.com/2022/09/30/performance-improvements-in-rubber-band-library/ | 2022-09-30 | performance notes | not checked |
| https://github.com/Signalsmith-Audio/signalsmith-stretch | current | MIT licence; quality range | not checked |
| https://www.practicesession.app/blog/signalsmith-stretch-deep-dive/ | undated | stretch quality notes | not checked |
| https://ffmpeg.org/ffmpeg-filters.html | current | atempo range 0.5 to 100; skipping above 2x | confirmed |
| https://librosa.org/doc/main/auto_tutorials/03-advanced/plot_dynamic_beat.html | current | beat_track; ISC licence (repo) | accuracy unconfirmed |
| https://github.com/CPJKU/madmom/blob/main/LICENSE | current | BSD-style code; CC BY-NC-SA 4.0 models and data | confirmed |
| https://essentia.upf.edu/licensing_information.html | current | models CC BY-NC-SA 4.0 | not checked; library licence unconfirmed |
| https://github.com/mixxxdj/libkeyfinder | current | GPL version 3 | not checked |
| https://aubio.org/ | current | GPL | not checked |
| https://en.wikipedia.org/wiki/Opus_(audio_format) | undated | native Opus encode and decode from iOS 17 | not checked (secondary) |

## 6. Platform, Session and Delivery

| URL | Date / access | Supports | Status |
|---|---|---|---|
| https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/soloambient | current | default category; silenced by screen lock and Silent switch; nonmixable by default; "Deprecated" marker | confirmed; marker scope unclear |
| https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback | current | ignores Silent switch; plays in background; mixWithOthers | not checked |
| https://developer.apple.com/design/human-interface-guidelines/playing-audio | last changed 2023-06-21 | category mapping for games; do not stop another app's music (quote) | confirmed (mapping and quote only); silent mode, system volume, auto-resume and macOS notification mixing not sceptic-checked |
| https://developer.apple.com/documentation/avfaudio/avaudiosession/silencesecondaryaudiohintnotification | current | secondary-audio hint and begin and end notifications | not checked |
| https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions | cached 2026-11-11 | iOS 27 notifications on main queue; DeactivationContext; legacy notification for iOS 26 and earlier | confirmed; "needed" wording |
| https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes | undated | newDeviceAvailable and oldDeviceUnavailable | not checked |
| https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification | undated | reset behaviour; no auto-restart | not checked |
| https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback | cached 2026-11-10 | background audio mode and active session; macOS control | not checked |
| https://support.apple.com/en-us/105118 | current | Game Mode on iOS 18+ and Mac Game Overlay | not checked |
| https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled | current | Low Power Mode reduces CPU and GPU | not checked |
| https://developer.apple.com/design/human-interface-guidelines/accessibility | undated | audio cues paired with haptics | not checked |
| https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html | archived; date unconfirmed | App Nap exemption for user-initiated work | not checked (archived) |
| https://developer.apple.com/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes/ | current | build size limits; no cellular figure | not checked |
| https://www.idownloadblog.com/2019/05/31/app-store-cellular-download-limit-200-mb/ | 2019 | 200 MB cellular limit announcement | unconfirmed as current |
| https://support.apple.com/en-lb/guide/iphone/iphab21972d/ios | current | Books help: download prompt over 200 MB | not checked |
| https://www.gummicube.com/blog/ios-13-removes-mobile-app-download-limits/ | 2019 | iOS 13 lifted the cellular limit (blog) | unconfirmed |
| https://developer.apple.com/help/app-store-connect/reference/app-uploads/on-demand-resources-size-limits/ | current | ODR deprecation from iOS 27 and migration to Background Assets | wording not sceptic-checked |
| https://developer.apple.com/documentation/backgroundassets | current | Background Assets (iOS 16+; tvOS 18.4+) | not checked |
| https://developer.apple.com/videos/play/wwdc2025/325/ | WWDC25 session 325 | Background Assets; Apple-hosted limits; IAP-unlocked packs | not checked |

## 7. Testing and Profiling

| URL | Date / access | Supports | Status |
|---|---|---|---|
| https://developer.apple.com/videos/play/wwdc2023/10248/ | WWDC23, "Analyze hangs with Instruments" | Time Profiler limits; Thread States | confirmed (title and instrument name corrected) |
| https://developer.apple.com/videos/play/wwdc2026/268/ | WWDC26 session 268 | System Trace; main-thread file I/O | not checked |
| https://developer.apple.com/videos/play/wwdc2019/414/ | 2019-06 | always end intervals | not checked |
| https://developer.apple.com/videos/play/wwdc2018/405/ | 2018-06 | one signpost ID per overlapping interval | not checked |
| https://developer.apple.com/videos/play/wwdc2018/612/ | 2018-06 | Metal System Trace | not checked |
| https://developer.apple.com/forums/tags/core-audio | date unknown | forum statement that render callbacks must not allocate or do I/O | not checked |
| https://medium.com/ios-ic-weekly/ossignposter-what-apples-docs-don-t-tell-you-ef63f939a43a | undated, unofficial | interval name mispairing | not checked (unofficial) |
| https://github.com/flyingrobots/AI-TTS/issues/82 | undated, user reports | HALC overload message and capture | not checked (user reports) |

## 8. Corrected Claims

These are claims from the research that were wrong or overstated. The corrected form is what the skill uses.

1. **"+2 semitone energy boost is not confirmed by any source."** Refuted. DJ.Studio's compatible-keys page describes a two-step Camelot move (9B to 11B) as shifting the key centre up two semitones, with a clash warning. Vendor taxonomy, not peer-reviewed.
2. **"Apple warns not to call stop() inside a completion handler (deadlock)."** Refuted as an Apple statement. The warning is from a third-party AudioKit issue (#940).
3. **AUScheduleParameterBlock "buffer offset under 4096 frames applies only when scheduling from a render observer."** Overstated. The documentation describes the offset for scheduling such as from a render observer.
4. **AVAudioEngineConfigurationChange "fires when the engine's configuration changes; restart is the usual fix."** Corrected: it fires when the I/O hardware channel count or sample rate changes; the engine stops and uninitialises; nodes stay attached; reconnect if formats change. The restart advice remains a secondary-source claim.
5. **Fink, Holters and Zölzer: equal power −3 dB and linear −6 dB for correlated material.** Unconfirmed. The abstract confirms a correlation-based design only.
6. **QA1715 "must not take locks" and the older `/library/ios/` path.** Scope narrowed: the document is about Audio Session APIs and blocking calls in the render callback (archive path; 2013-10-04). "Take locks" is implied, not stated.
7. **Manual rendering: "must come before touching mainMixerNode, inputNode or outputNode."** Not on Apple's page; dropped. The confirmed precondition is to stop the engine first.
8. **EBU Tech 3341 short-term and momentary windows.** Momentary is 0.4 s and short-term is 3 s. Both are ungated in EBU Mode. The research had called gating "disputed"; that is resolved for EBU Mode, not for the base BS.1770 text.
9. **BS.1534 edition.** BS.1534-3, 10/2015, in force.
10. **WWDC23 session 10248.** Titled "Analyze hangs with Instruments"; the instrument is Thread States (Thread State Trace).
11. **Apple's sequencer sample "ramps volume from zero to avoid clicks".** Corrected: it sets volume to zero, schedules, then sets it to one, relying on engine smoothing (about 5 ms by the sample's comment). It is listed for macOS 27.0+ only.
12. **QA1636 for AVAudioEngine priming and remainder.** Corrected: Audio Queue Services only. The engine path is unverified.
13. **Solo ambient as "the default" without caveat.** Apple calls it the default category; its page shows a "Deprecated" marker whose scope is unclear. Confirm before use.
14. **Interruption notification "required" for iOS 26 and earlier.** Corrected to "needed".
15. **madmom "free".** Corrected: code is BSD-style; models and data are CC BY-NC-SA 4.0.
16. **Sony ASWG as a general iOS target.** Corrected: Sony-specific, console and portable categories; no iOS coverage; the 30-minute rule is a minimum over representative gameplay.
17. **Mixxx Auto DJ footer date "Nov 11, 2026".** Unverified: the fetched page has no footer date. The page header lists 2.5 as the latest release; cite the 2.5 manual if currency matters.
18. **Mixxx "no beatmatch" reading of Auto DJ.** Inference only. The manual says Auto DJ aligns intro and outro boundaries in time; silence in its text is not evidence that tempo is not matched.
19. **Zehren et al. precision 86%.** Strict-window figure. Expert listening judged 95.8% of candidates usable.
20. **CUE-DETR precision 0.38.** The r16 variant; r8 gives 0.32. Measured on a 101-track test split of 607 annotations.
21. **Left 4 Dead Peak Fade "until fights resolve".** Corrected: "until a natural break in the action". "Dramatic music named in the source" is not supported by the slides. "Then got another mob" is only in the secondary transcript.
22. **DOOM Eternal's four categories "presented at GDC 2017".** Corrected: from a 2020 Sifter interview about DOOM Eternal.
23. **"Pieces about 3.3 minutes each" as a general budget.** Not a general property; piece lengths vary. The research's "about 380 MB for five pieces" assumed five 3.3-minute pieces. Compute from the actual lengths.
24. **"138 pre-rendered transitions" (earlier research pass).** Not supported by the project code or ADR, which give 122 directed cues. Not used.
25. **"880 MB bridge set" (research).** Not verified as the bridge set alone. Arithmetic: 122 bridges of about 15.35 s as 48 kHz float32 stereo come to about 720 MB, so the 880 MB figure includes other files or differs in composition. Not used as a fact in the skill.
26. **Apple ODR and Background Assets limits, Opus in CAF.** Not sceptic-checked; treated as unconfirmed where used.
27. **"Every 5 beats at 120 BPM caps the wait at 2 s" (joffwinks).** Arithmetic: 5 beats at 120 BPM is 2.5 s (computed). The 2 s figure does not match and is not used. Check the article before citing it.

## 9. Unconfirmed Claims

Labelled wherever used, or left out. Do not state these as facts without a test or a primary-source check.

- Vendor tempo range ±4-8%, semitone range ±1-4, "vocals reveal tuning first" (dj.studio).
- ±3-5 BPM as a safe stretch range (dj.studio, not checked).
- Typical DJ blend lengths in bars and bass-swap timing (no primary source found).
- Automix's four rules (not described in the sources read).
- Author attribution of CUE-DETR ("Argüello et al.").
- Fink et al. numbers (−3 dB and −6 dB by correlation).
- Whether Apple's mixers honour player-volume or parameter ramps; reports of ramps having no effect.
- Whether `outputVolume` is ramped or stepped.
- `AVAudioUnitTimePitch.pitch` unit (cents).
- AVAudioUnitTimePitch and Varispeed latency figures (forum, anecdotal).
- `outputLatency` meaning.
- `AVAudioSourceNode` render-block contract; `AVAudioUnitEQ` behaviour; streaming versus preloading cost in AVAudioFile; threading of completion handlers; whether scheduleFile streams or decodes on a background thread.
- Whether AVAudioFile trims AAC priming and remainder automatically.
- Opus in CAF; Opus decode in AVAudioEngine; hardware stream limits.
- Current App Store cellular threshold; ODR on TestFlight.
- ASWG applicability to iOS; the "−24 LUFS / −1 dBTP" console practice; the "−18" portable forum figure.
- ffmpeg `loudnorm` option values; `ebur128` true-peak option; `afclip`.
- SoundTouch licence (LGPL licence); élastique licence; ffmpeg rubberband filter.
- Essentia library licence; Apple Music Understanding licence and accuracy.
- Whether GPL tools run offline on the authoring machine create obligations for generated audio.
- Wwise rule order (first match); exit cues as on/off gates in current Wwise.
- Plants vs. Zombies horde theme; Hades combat states; Kingdom Rush; Bloons; They Are Billions.
- Hysteresis and minimum-dwell values for music states; the fatigue guess (about 2 minutes unchanged).
- Audio template in Instruments; the macOS HALC predicate for `log stream`.
- Ducking under voice or SFX; separate music and SFX volume guidance; Reduce Motion for audio; thermal-state rules for audio; Bluetooth latency compensation.
- "Restart is the usual fix" for engine configuration changes (secondary).
- Audiokinetic GDC talk content and year.
- Key-detection and beat-tracking accuracy of librosa, madmom, Essentia, libKeyFinder and aubio.
- Mixxx Sync Lock with Dynamic Tempo (reported by the sceptic pass; not re-fetched).
- Mixxx beatmatch definition, key lock and automatic key detection (not sceptic-checked).
- HIG silent mode, system volume, auto-resume and macOS notification mixing (not sceptic-checked).
- Media-services reset wording, route-change reason keys, secondary-audio hint, background-mode and macOS control wording, Game Mode (not sceptic-checked; labelled in platform.md).
- Timeline that the `when` sample time refers to; `lastRenderTime` as the live anchor; overlap-gain and bass-swap mechanisms (spike-pending; apple-engine.md sections 2, 3 and 5).
- EBU R 128 advice against LRA under one minute (not checked).
