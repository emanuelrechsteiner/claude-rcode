# Platform: Audio Session, Interruptions, Lifecycle, macOS

Scope: how a game's music behaves with the system, with the player's own music, and with interruptions. iOS and iPadOS use `AVAudioSession`; macOS has no session object, and the app controls its own output (general knowledge; check current docs).

Labels: **confirmed** = sceptic-checked against the primary source; **unconfirmed (test on device)** = not checked, do not design on it without a test; other statements are labelled in place.

## 1. Session Categories for Games

- **Solo ambient** (`soloAmbient`): the default session category. Silenced by the Silent switch and by screen lock. Nonmixable by default, so activating it interrupts other nonmixable audio (Apple; confirmed in a sceptic pass). **The Apple page shows a "Deprecated" marker whose scope is unclear** (category or page). Confirm before using soloAmbient as the default.
- **Playback** (`playback`): ignores the Silent switch and plays in the background. It mixes with other audio only if `mixWithOthers` is set (Apple; not sceptic-checked).
- **Ambient** (`ambient`): named in the HIG mapping below for a game that lets the player's own music continue. Its mixing and silence behaviour was **not checked** in the sources; confirm on its category page before relying on it.
- **HIG mapping** (Apple Human Interface Guidelines, playing audio, last changed 2023-06-21; confirmed): a game with a soundtrack uses Solo ambient; a game that lets players use music from another app during play uses Ambient. "Don't make people stop listening to music from another app if you don't need to."
- The HIG also says game soundtracks and effects are expected to go silent in silent mode; the system volume governs the final output, and apps set relative levels. (Not sceptic-checked: silent mode, system volume and relative levels.)

Choice (synthesis from the above):

| Situation | Category |
|---|---|
| Game with its own soundtrack | Solo ambient (HIG) |
| Game that lets the player's own music keep playing | Ambient, plus the secondary-audio hint (section 2); confirm category behaviour first |
| Game audio must continue with the screen locked | Playback (it then ignores the Silent switch); check against the HIG before choosing |

## 2. Secondary-Audio Hint

- `secondaryAudioShouldBeSilencedHint` is true while a nonmixable app is playing. `silenceSecondaryAudioHintNotification` reports when it begins and ends (Apple page, current; not sceptic-checked; the older QA1882 is archived).
- Its meaning: the app should silence its own secondary audio while the hint is true. A game that prefers the player's music observes it, silences its music while true, and resumes on the end notification (reading of the Apple page; check the exact policy against the HIG).

## 3. Interruptions

- **iOS 27 and later:** the session posts `didBecomeActive`, `didBecomeInactive` (with a `DeactivationContext` that says whether the app or the system caused it) and `resumptionRecommendation`, all on the main queue (Apple; confirmed).
- **Legacy `interruptionNotification`:** deprecated from iOS 27 but needed for iOS 26 and earlier. A deployment target below 27 needs it.
- **HIG:** a game may resume automatically after an interruption, because it plays audio without an explicit user choice (not sceptic-checked).
- **Media-services reset** (`mediaServicesWereReset`; Apple, undated; not checked): reinitialise players, engines and converters, and reset the category, options and mode. The rule that playback must not restart without user action is **unconfirmed (test on device)**. Until the Apple page is checked, choose between restart and wait by test, not by this note.
- Plan for: phone calls, alarms, Siri, another app taking the session, and a reset during play.

## 4. Route Changes

- Observe route changes. The reason keys to check are `newDeviceAvailable` and `oldDeviceUnavailable` (Apple "responding to audio route changes", undated; not sceptic-checked).
- Headphones connected: keep playing. Headphones removed: pause at once (unconfirmed; test on device).
- Bluetooth and AirPods latency compensation for transitions heard on headphones: **unconfirmed**. Test transitions on the output the player actually uses.

## 5. Engine Configuration Change

- `AVAudioEngineConfigurationChange` fires when the I/O unit observes a change to hardware channel count or sample rate. The engine stops and uninitialises itself; nodes stay attached; reconnect nodes if formats must change (Apple; confirmed). The broader wording "fires when the configuration changes" is wrong.
- Restart as the usual fix: secondary sources only; **unconfirmed** as Apple guidance.
- Rebuild or reconnect, restart, and reschedule both decks from the current musical position (apple-engine.md section 9).

## 6. Lifecycle and Background

- iOS background audio needs the "Audio, AirPlay, and Picture in Picture" background mode and an active session (Apple, cached 2026-11-10; unconfirmed; test on device).
- macOS: the same doc says control is mostly left to the app (unconfirmed; test on device).
- **Low Power Mode:** read with `ProcessInfo.isLowPowerModeEnabled`; it reduces CPU and GPU performance (Apple; not sceptic-checked). Check the music budget under Low Power Mode.
- **Game Mode:** on iPhone and iPad it needs iOS 18 or later. On Mac it is set in the Game Overlay (Command-Esc on macOS Tahoe 26 or later), and quitting the game turns it off (Apple support page; unconfirmed; test on device).
- **App Nap** (archived Apple guide; date unconfirmed; not checked): an app that tells the system a user-initiated long operation must finish is not put into App Nap. Relevant to macOS music that must keep running in the background.
- **Thermal state** and audio: no audio-specific guidance found; **unconfirmed**.

## 7. macOS Differences

- No `AVAudioSession`. The app controls its output and mixing; device and sample-rate changes arrive as the configuration-change notification (section 5).
- Notification sounds mix with other audio by default (HIG, 2023; not sceptic-checked).
- Sample-rate change handling beyond the secondary sources: **unconfirmed**.
- Frame timing and audio I/O overload on macOS: testing.md section 4.

## 8. Volumes, Buses and Ducking

- Keep **music and SFX on separate buses** into the mixer, with separate volumes, so the player can set one without the other (synthesis). Apple guidance on separate music and SFX volumes was **not found**.
- **Ducking** (lowering music under voice or SFX): no Apple source was gathered. **Unconfirmed**. Do not claim a platform ducking behaviour without a test.
- **Reduce Motion as applied to audio:** **unconfirmed**.
- If audio cues carry information, pair them with haptics (HIG accessibility guidance, undated; not sceptic-checked).

## 9. Device Checklist

Test on hardware, not only the simulator (testing.md section 6):
- Interruption: phone call, alarm, another app taking the session, reset.
- Route: unplug headphones in the middle of a transition.
- Lifecycle: lock the screen; background and return.
- Configuration: switch output device, change sample rate.
- Low Power Mode on.
- Silent switch on (for the chosen category).
