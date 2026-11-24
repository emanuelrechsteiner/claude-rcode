# State Design: Gameplay to Music

Goal: the music follows the fight without flickering, without lagging behind it, and without wearing the listener out. Most rules below are engineering synthesis; sourced items are marked.

## 1. Examples From Shipped Games (Verified Subset)

- **Left 4 Dead AI Director** (Mike Booth, GDC 2009 slides; primary source, confirmed in a sceptic pass). A four-state machine: Build Up, Sustain Peak, Peak Fade, Relax. It tracks the maximum intensity across survivors. Sustain Peak lasts 3-5 s; Relax 30-45 s. Peak Fade exists because "current combat engagement can play out without using up entire Relax period"; Relax does not start until a natural break in the action. The slides contain no dramatic-music content.
- **DOOM Eternal** (Mick Gordon, 2020 Sifter interview). Four categories: high-level combat, medium combat, incidental combat, exploration. Attributed to that interview, **not** to GDC 2017 (the GDC 2017 talk covered the 2016 DOOM score).
- **Not used (unconfirmed):** Plants vs. Zombies horde theme (fan wiki only); Hades combat states; Kingdom Rush; Bloons; They Are Billions. A Hades interview remark (a player's time in one piece cannot be controlled, so design for variable dwell) is a single interview, not sceptic-checked.

## 2. Signals and Counters

For a wave-based game, keep counters updated on events, not per-entity loops:
- **Enemies alive (E)**: a live count of hostile entities, incremented on spawn and decremented on death or removal.
- **Threat budget**: a health or strength budget of each wave's primary spawns (for example count times health). A strong class is a threshold on that budget, set from the wave table. How many waves count as strong is a project decision and lives in the project profile (synthesis).
- **Strong wave latch (L)**: a wave that starts strong with unfinished work latches at its first observation, per wave, until it is cleared or released early (section 3).
- **Waves in progress (W)**: a wave is in progress from its first spawn event until its spawners are exhausted and its last enemy is dead. An unbounded or offspring producer keeps its wave open (synthesis). W is separate from E: overlapping waves need both.
- **Base or station health (H)**: for player protection. A low-health warning can be a stinger or a layer instead of a tier (synthesis).
- **Bar clock**: dwell and calm counts run in bars, where bars = elapsed samples on the audio clock / samplesPerBar. Never count frames (synthesis; reason: frame rate varies with load, the audio clock does not).

**Evaluation (synthesis):** evaluate the state at 2-4 Hz from those counters. Do not loop over all entities per frame, and do not re-request the same music state every frame. A per-frame path that does both is the first thing to remove.

## 3. Generic State Matrix (example: three tiers, wave-based game)

Example tier set: Calm (no threat), Tension (enemies on the field), Strong (a latched strong wave). No separate critical tier; a low-health warning sits on top as a stinger or layer. The tier count, the dwell values (D, in bars) and the thresholds are project decisions: the D and threshold names below are placeholders, and the project's measured values go in its profile.

One guard per edge, using the counters of section 2. A request whose guard no longer holds at its execution point is dropped, so a one-beat blip cannot start an overlap (synthesis).

| From to | Guard | Executes at | Dwell |
|---|---|---|---|
| Calm to Tension | E ≥ 1 | next phrase boundary of the outgoing piece | none: escalate at once |
| Calm to Strong | L non-empty | same | none |
| Tension to Strong | L non-empty | same | none |
| Tension to Calm | E = 0, W = 0 and calm count C ≥ D_calm | next phrase boundary | dwell in Tension ≥ D_tension |
| Strong to Tension | L empty and (E ≥ 1 or W > 0) | next phrase boundary | dwell in Strong ≥ D_strong |
| Strong to Calm | not an edge | not applicable | passes through Tension (synthesis; reason: enemies usually remain after a strong wave) |

Rules attached to the matrix:
- **Tail (sourced rationale, Booth):** Tail = (E = 0 and W > 0). The current tier holds through the tail whatever E does, and the tail ends only when W = 0. Booth's Peak Fade has the same purpose: stay until the wave is actually dead, not until a count drops below a threshold.
- **Calm count and dwell are separate counters.** C counts bars with E = 0 and W = 0, starting when the tail ends, so tail time does not count (synthesis). Dwell counts bars since the tier's overlap began. A switch down needs both to be satisfied.
- **Overlapping waves:** E and W are separate signals. Do not leave a tier while any wave is in progress.
- **Strong latch release (synthesis):** a latched wave releases when its work is done, or early when base health is at or above H_rel and the wave's remaining enemies are at or below R_rel of its initial count, with dwell in Strong at least D_strong and no unbounded producer of that wave live. Starting values, to calibrate from the wave table: H_rel 0.5, R_rel 0.05. Early release is one-way: a released wave never re-latches (reason: prevents flicker).
- **Numeric thresholds with hysteresis (synthesis):** the exit sits on the safe side of the entry. Example: a low-health stinger enters at base health at or below 0.30 and leaves at or above 0.40 (starting values). Booleans (E, W, L) have no gap; they are debounced by dwell and the calm count, because a threshold gap cannot apply to a yes-or-no signal.
- **Escalation grid (synthesis):** escalation waits for the next phrase boundary of the outgoing piece, so the wait is below P bars. Pieces that can be escalated from use P = 4 (transitions.md section 2).

## 4. Hysteresis and Minimum Dwell

- **Separate enter and exit thresholds** for each numeric signal: the exit sits on the safe side of the entry, so a value hovering near the line does not flip the state (synthesis; no sourced music-state values were found). Booleans have no threshold gap; section 3 debounces them by dwell and counts.
- **Minimum dwell**: a tier holds at least its dwell before the next switch. Take dwell values from the project's own measurements and check that the design notes do not contradict each other; mismatched dwell values are a common source of inconsistent behaviour.
- **Timing**: every state change executes at a phrase boundary of the outgoing piece (section 3). Only stingers and one-shot accents use the bar or beat grid (section 5).
- **Fatigue**: no sourced numbers. A working guess is to cap unchanged play of one piece near 2 minutes and rotate calm pieces. **Unconfirmed guess**; test with listeners.

## 5. Stingers

- Short phrases placed over the current music for one-off events: a strong wave arriving, a wave cleared, a base warning.
- A stinger does not change state. Keep it on the bar grid so it does not clash with the music underneath.
- Wwise has a "Using Stingers" topic; not read.

## 6. Vertical Layering as the Escalation Alternative

- Instead of switching to another piece for the strong tier, add a percussion or lead stem on the same grid (Phillips, GDC 2021; secondary article). Stems share tempo and length; the layer fades in over bars.
- Layers change intensity, not harmony or form. Use them with horizontal changes, not instead of them, when the harmony must change.
- This matches the category approach in section 1 (synthesis).

## 7. Listener Fatigue and Variety

- Calm pieces repeat for minutes in a wave-based game. Rotate among calm pieces and keep their entry and exit points distinct.
- Measure the distribution of play time per piece across a session in telemetry (testing.md section 6) before deciding on a rotation rule.

## 8. Telemetry for the State Logic

- Log each state change with a host-time or monotonic timestamp, the decision inputs (enemies alive, threat value, latched wave, base health), the scheduled lead time, and any underrun.
- Log transitions as sample positions on the shared timeline so they can be compared to rendered output (testing.md section 1).
- Logging must not block the render thread or the main thread: write into a preallocated ring and flush elsewhere.
