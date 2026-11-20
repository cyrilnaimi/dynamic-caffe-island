# Changelog

All notable changes to Caffe Island are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Changed

- Renamed to **Caffe Island** (app, menu, Spotlight, DMG volume, release
  assets). Bundle id and `caffe://` scheme are unchanged.
- Menu bar icon is now the app's mug (template glyph from
  `scripts/make-icon.swift --menubar`); classic cup and timer-only styles.
- ⌃⌥C and `caffe toggle` use the default duration from Settings.

### Added

- Settings window (⌘,, menu, `caffe://settings`, re-opening the app).
- Island styles: notch, floating pill below the menu bar, automatic; hide
  when idle with a top-centre hot zone.
- Multiple displays: main display, display with the pointer / active window,
  or all displays, each with its own notch / no-notch geometry.
- The island hides while a full-screen app is in front (event-driven; hide,
  alerts only or show).
- Keep awake while a process or app runs: `caffe -- CMD`, `caffe -w PID`,
  `caffe --app NAME`, `caffe://while?pid=|app=`, menu submenu, Spotlight
  action. Ends within moments of the exit with a message.
- Battery guard: stop below 10/20/30 % or when unplugged.
- Open at login (`SMAppService`), never starting a session by itself.
- ⏻ Quit button in the expanded island; it ends a running session first,
  so it works even with the menu bar item hidden.
- Show the app in the menu bar, the Dock, both, or the island only (no
  relaunch). Dock mode adds ⌘⇥, an App menu (Settings… ⌘,, Quit ⌘Q), a
  Dock menu with the menu bar's commands, and an optional remaining-time
  badge updated once a minute.
- Option to hide the menu bar item.
- Plugin bundles are verified before loading: valid code signature against
  a Developer ID team requirement, user-owned non-writable directory, no
  escaping symlinks, user approval hook.
- Accessibility: VoiceOver labels for the island strip, toast and countdown,
  Reduce Motion for toasts and steam, higher-contrast secondary text, rolling
  digits on macOS 14+.

- Phase 1 scaffolding — repo layout, SwiftPM workspace (`Packages/`) with six
  library targets (`ProfileKit`, `AnimationKit`, `IslandCore`,
  `PowerAssertions`, `SleepClock`, `BuiltInProfiles`), XcodeGen spec
  (`project.yml`), minimal `App/` target stub, `swift-format` config,
  `scripts/format.sh`, `scripts/measure-idle.sh` for SC-004 budgets, GitHub
  Actions matrix CI across `macos-13` + `macos-14`.
- Notch island: a black notch-shaped island hanging from the top edge of the
  primary display — wraps the hardware notch on notched MacBooks, simulates
  one everywhere else. Idle → live timer wings → toast on start/stop →
  hover-expanded panel with progress ring, presets (15m/30m/1h/2h/∞), +15m
  and Stop. Click-through outside the shape.
- Spotlight / Siri / Shortcuts via App Intents: "Keep Mac Awake" (duration
  enum), "Keep Mac Awake for Minutes", "Let Mac Sleep".
- `caffe://` URL scheme (`start?minutes=N`, `N`, `indefinite`, `stop`,
  `toggle`, `peek`) and `scripts/caffe` CLI wrapper.
- ⌃⌥C global hotkey toggles a 30-minute session.

### Fixed

- A session ending on its own could end a session started at that moment;
  expiry and process exit now only end the session they belong to.
- The island and menus could show idle while the Mac was still being kept
  awake (state changes from two threads arriving out of order).
- Timed sessions now end at the time shown even if the Mac slept during
  them, and the Dock badge is corrected right after wake.
- A failed start (e.g. the watched process had just quit) no longer hides
  Stop for the session that is still running; the failure shows as a
  message instead.
- The battery guard now applies as soon as a session starts, not only at
  the next power-source change.
- "Keep Mac Awake While App Runs" reports what really happened, and a quick
  double ⌃⌥C starts then stops.
- The sleep countdown uses the battery settings on battery and the adapter
  settings on AC, and follows plugging in or unplugging.
- The countdown no longer freezes after a display sleeps and wakes.
- `kill` and Ctrl-C always end the app (the signal handler could hang it);
  macOS releases the power assertion with the process.
- The built-in profiles are created once at launch, not twice (`pmset` ran
  twice and observers were duplicated).
- Switching to Dock mode from Settings shows the App menu right away.
- The Dock badge no longer shows one minute too many for a whole minute.
- Stop stays in the menu bar and Dock menus during a session's last seconds.
- ⌘, is handled by the App menu in Dock mode and by a key monitor otherwise,
  not both.
- `scripts/build-release.sh [--install]` — universal (arm64 + x86_64) Release
  build, ad-hoc signed, optionally installed to /Applications.
- "Keep awake until" window redesigned (Today/Tomorrow, time remaining, quick
  picks); a time already passed today now means tomorrow instead of "in one
  minute". Reachable from the island, menu, `caffe://pick` and a new
  "Keep Mac Awake Until" Spotlight action; `caffe://until?time=HH:MM`.
- `CaffeCommand`: one tested parser for every external command.
- Localization: String Catalog, complete French translation,
  `scripts/i18n-check.py` lint, `docs/LOCALIZATION.md` contributor guide.
- App icon (`scripts/make-icon.swift`, reproducible CoreGraphics render).
- User manual `docs/manual/` (EN/FR) with app-window-only screenshots
  (`scripts/capture-manual.sh`).
- Tests: `scripts/e2e.sh` (end-to-end on the installed app),
  `scripts/smoke-test.sh` (headless, CI), 7 new unit tests.
- GitHub Actions: CI on `macos-15-intel` + `macos-15`; tag-driven release
  (universal build → smoke test on both archs → DMG/ZIP/SHA256, optional
  Developer ID signing + notarization); Dependabot for actions.

### Fixed

- Menu bar timer changed width as digits changed, and froze during a
  session; it now has a fixed width and ticks.
- A session started during the 0.6 s expiry dwell of the previous one was
  cancelled.

- Island never rendered (leftover debug view in the panel).
- Possible deadlock reading `pmset`/`defaults` output (pipe drained after
  waiting for exit).
- `build-release.sh` could package a stale build after a failed compile.
- Stray dot on the empty progress ring; French chip labels wrapping.
- Hardened runtime enabled (required for notarization; blocks unsigned
  plugin bundles).
