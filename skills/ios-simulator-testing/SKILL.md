---
name: ios-simulator-testing
description: Documents the iOS Simulator toolchain (MCP simulator control + build tools, xcrun simctl, xcodebuild) for building, launching, and interacting with native iOS apps in the Simulator across any project on this Mac. Use when the user wants to run, test, or debug an app on the iOS Simulator. Triggers on "iOS simulator", "run on iPhone", "test on simulator", "simulator testen", "app im simulator", "nativ testen", "iphone testen", "simulator screenshot", "xcodebuild", "simctl".
allowed-tools: Read, Glob, Grep, Bash(xcrun *), Bash(xcodebuild *), Bash(pod install*), Bash(xcode-select -p), mcp__Claude_Code_iOS_Simulator__control, mcp__Claude_Code_iOS_Simulator__build
---

# iOS Simulator Testing Skill

Documents the iOS Simulator toolchain available on this Mac: two MCP tools plus the
underlying `xcrun`/`xcodebuild` layer. Simulator-only — no physical-device control.
If the user wants a real device ("auf meinem iPhone"), use normal build/deploy tooling
instead and say the live panel only covers simulators.

## 1. Tool Inventory

### `mcp__Claude_Code_iOS_Simulator__control`
Actions: `attach`, `launch`, `screenshot`, `tap`/`swipe`/`touch_path`/`touch2_path`/`text`/`button`,
`open_url` (deep links), `detach`.

- **`attach` first, always** — opens the live panel so the user can watch. Call it
  BEFORE build/launch, as early as possible: on a booted simulator it opens instantly;
  on nothing booted it returns a harmless error (boot or build, then retry it). Do not
  skip the early call just because `launch` also re-attaches.
- **`launch`** installs and launches a built `.app` (path comes from the `build` tool).
- **`screenshot` and all input actions work headless** — they don't need the panel open.
  Skip `attach` only when the user has no interest in watching.
- Coordinates are device **points**, origin top-left. `attach`/`launch` report the
  device's point dimensions (e.g. iPhone 17: 402×874).
- **Point vs. pixel:** `screenshot` output (and `xcrun simctl io screenshot`) is in
  **pixels**, not points — modern iPhones render at 3× scale (e.g. iPhone 17:
  1206×2622px for a 402×874pt screen). Deriving a tap target from screenshot pixel
  coordinates without dividing by the scale factor misses the target.
- **Edge-gesture trap:** a `swipe`/`touch_path` whose start point is ≤4pt from a screen
  edge triggers the OS gesture instead of a plain drag (left=back, top=notification
  shade, bottom=home/app-switcher, right=Control Center). Start >4pt from the edge to
  scroll/drag content near the bezel.

### `mcp__Claude_Code_iOS_Simulator__build`
`{action:"build", workspace_path|project_path, scheme, udid}` starts a headless
`xcodebuild` and returns a `build_id` immediately (does not block). Poll with
`{action:"build_status", build_id}`. Headless builds run with `-skipMacroValidation`.
The build log path is included in the result — read it directly rather than re-running
xcodebuild yourself if you need more detail.

### Desktop-app equivalent
Claude Code **Desktop** has its own iOS Simulator pane (Public Beta — docs:
code.claude.com/docs, "Test iOS apps in the simulator"). The CLI/this skill reaches the
simulator through the two MCP tools above instead. Concepts are analogous (per-device
consent, one simulator per session).

## 2. Standard Workflow

1. `control{action:"attach"}` — early, so the user sees the panel.
2. Nothing booted? → `xcrun simctl list devices available` → `xcrun simctl boot <udid>`
   → `attach` again.
3. `build{action:"build", ...}` → poll `build{action:"build_status", build_id:...}`.
   First build: minutes. Incremental: fast. Wait via a background Bash + Monitor
   loop, e.g. `until grep -qE "BUILD SUCCEEDED|BUILD FAILED" <log>; do sleep 3; done`
   — don't busy-poll with short sleeps in the foreground.
4. `control{action:"launch", app_path:<.app from build_status>, bundle_id:...}`.
5. Interact: `tap`/`swipe`/`text`; verify with `screenshot`.
6. For fast full-app capture (e.g. screenshotting every screen), prefer a cold
   deep-link per screen (`open_url` / `xcrun simctl openurl`) over navigating through
   the UI — far more reliable than `type`. Don't assume it skips confirm dialogs: on
   iOS 26.5, a deep link fired after `terminate` still surfaces the "Open in `<App>`?"
   system dialog, so budget one `tap` on its confirm button per launch (see §3).

## Testing-Strategie (Loop)

Testing here is a loop, not a linear script — findings can (and should) reach back to
any earlier stage.

- **Log-first, filtered:** read logs error-first (`--level=error` / `grep -i error`);
  drop to unfiltered/wildcard reading only when actively exploring an unknown symptom.
  The dev-server log (Metro/etc.) is JS truth; `log stream` is native truth — they
  answer different questions, don't substitute one for the other.
- **Agentic human-testing (default for functional testing):** navigate the app
  yourself as a user would. Screenshot after every step that matters, and actually
  read the screenshot's content — don't just confirm a screenshot was taken. A
  screenshot nobody looked at proves nothing.
- **Deterministic navigation (screenshot/mass-capture only):** for bulk screenshot
  capture across many screens/states (e.g. a flowgraph rebuild), prefer a cold
  deep-link per screen/state over chained taps through the UI — taps accumulate
  drift (missed element, stale screen, wrong offset) and a deep link reproduces the
  same state every time. Precedence: this is a capture shortcut, not a substitute for
  the agentic navigation above — don't use it to skip exploratory functional testing.
- **Evidence trail:** number screenshots in the scratchpad (`01-`, `02-`, …) and map
  every finding to the screenshot(s) that show it. A finding without a screenshot
  reference is not yet evidence.
- **JS-only changes skip the rebuild:** a JS/business-logic edit reloads via Metro —
  no `xcodebuild`/`build` round-trip needed. Rebuild only for native-layer changes.
- **Clean-slate discipline:** app state can survive a cold start. When a fresh install
  is the actual test condition, `xcrun simctl uninstall <udid> <bundle_id>` first —
  don't assume terminate+relaunch is equivalent to a fresh user.
- **The loop, not the line:** a finding may reach back to ANY earlier stage — a bug
  fixes code, a concept error fixes design, a toolchain surprise gets written into
  this skill immediately (don't let the next session rediscover it). Log every
  backward jump (what triggered it, where it landed). Anti-spin: the same backward
  jump twice with no new information is a signal to stop and escalate to the human,
  not to try a third variation.

Project-specific steps (stage names, ports, presets, cycle definitions) belong in the
target project's own DEV-LOOP doc — check its `CLAUDE.md`/memory for the pointer,
don't guess.

## 3. Console & Logs

- **JS console (React Native / Expo apps):** runs through Metro, not the simulator
  tools. Start Metro as the dev/preview server and read its logs — in the Claude Code
  context this is the Preview-Server log stream of that launch config, not a Bash
  command, so this skill's `allowed-tools` doesn't need to cover it. Debug builds load
  JS from Metro — without it running, the app shows an error screen, not a blank one.
  This stream (and any other stdout-based dev-server log the project runs alongside it,
  e.g. a backend/API dev server) has no `--level` flag — filter by reading, e.g.
  `grep -i error` over the captured output, and drop to a full unfiltered read only
  when actively exploring an unknown symptom.
- **Native logs:** read error-first by default; escalate to the unfiltered/wildcard
  form only when actively exploring an unknown symptom.
  ```bash
  # Default — error-filtered
  xcrun simctl spawn booted log stream --level=error \
    --predicate 'processImagePath CONTAINS "<app-name>"'

  # Escalation — unknown symptom, need the full stream
  xcrun simctl spawn booted log stream --level=debug \
    --predicate 'processImagePath CONTAINS "<app-name>"'
  ```
- **Deep-link launch:**
  ```bash
  xcrun simctl openurl booted "<scheme>://<route>"
  ```
  On iOS 26.5 this still triggers the "Open in `<App>`?" system confirmation dialog
  after a `terminate` — a cold start does NOT bypass it on this OS version (earlier
  assumption to the contrary was wrong). Plan a `control{action:"tap"}` on the dialog's
  confirm button as part of the launch sequence.

## 4. Troubleshooting (all encountered in practice)

| Symptom | Cause / Fix |
|---|---|
| **"Xcode is installed but not selected"** | User must run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` themselves — this needs `sudo`, the agent cannot run it (system-settings change, prohibited). State the exact command, wait for confirmation, retry `attach`. Note: `xcode-select -p` in the agent's own shell can already show the right path while the MCP tool still throws this error — **the tool's error is authoritative**, not the shell check. |
| **"No booted simulator found"** | `xcrun simctl list devices available` → `xcrun simctl boot <udid>`. |
| **RN + pnpm workspace: `Cannot find module '@react-native/codegen/package.json'`** during the "Generate Specs" Xcode build phase | Two stacked causes. (a) pnpm doesn't hoist codegen flat → add `public-hoist-pattern[]=*react-native*` to the root `.npmrc`, then `pnpm install`. (b) The Generate-Specs script phase can run with CWD outside the repo → Node `[eval]` resolution fails. Fix: in the Podfile's `post_install`, prepend `cd "$PODS_ROOT/.."` to that script phase (idempotent), then `pod install`. |
| **`.xcode.env` / `.xcode.env.local` stale `NODE_BINARY`** (nvm path drift) | These files are hook-protected on this Mac — the user edits them manually. Check for a stale Node path before assuming the fix is elsewhere. |
| **CocoaPods 1.16 / Ruby 3.4 crashes without UTF-8 locale** | `LANG=en_US.UTF-8 pod install`. |
| **pnpm hangs with `ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY`** | Non-interactive shell → `CI=true pnpm install`. |
| **`text` action is flaky** | Prefer on-screen-keyboard taps over the `text` action for reliability. |
| **Screen overlays (e.g. LookAway) block computer-use clicks** | Does NOT affect the MCP simulator tools — they inject input directly, bypassing screen-level overlays. |
| **Project-specific values (env presets, ports, deep-link schemes)** | Always pull from the target project's `CLAUDE.md` / memory — never guess. |
| **MCP `build` tool fails at the "Generate Specs" Xcode phase (`Cannot find module '@react-native/codegen/package.json'`) while the identical build succeeds via direct `xcodebuild`** | Observed on a pnpm-workspace React Native project living on an external volume, with the codegen-hoist and Podfile-CWD fixes already applied (see row above) — the standalone generated phase script also passes. Root cause narrows to the MCP tool's own child-process environment, not the project. Workaround: call MCP `build` once anyway, purely to read its `-derivedDataPath` from the result; then run the equivalent build directly via Bash — `xcodebuild -workspace <ws> -scheme <scheme> -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath <path-from-mcp-result> build` — and feed the resulting `.app` (`<DerivedData>/Build/Products/Debug-iphonesimulator/<Scheme>.app`) to `control{action:"launch"}`. Launch/tap/screenshot/logs are unaffected once launched this way. |

## 5. For Subagents / Workflows

The two MCP tools are session-connected and appear as deferred tools for subagents.
A general-purpose or workflow subagent must load them first:

```
ToolSearch: select:mcp__Claude_Code_iOS_Simulator__control,mcp__Claude_Code_iOS_Simulator__build
```

Specialized agents without MCP access (e.g. `backend-agent`) cannot reach these tools —
delegate simulator steps to the orchestrator / a `general-purpose` agent instead. When
no MCP access is available at all, the deterministic fallback is direct `xcrun simctl`
+ `xcodebuild` via Bash (slower, no live panel, but fully scriptable).
