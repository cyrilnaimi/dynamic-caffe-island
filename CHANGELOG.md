# Changelog

All notable changes to Dynamic Caffe Island are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

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

- Island never rendered (leftover debug view in the panel).
- Possible deadlock reading `pmset`/`defaults` output (pipe drained after
  waiting for exit).
- `build-release.sh` could package a stale build after a failed compile.
- Stray dot on the empty progress ring; French chip labels wrapping.
- Hardened runtime enabled (required for notarization; blocks unsigned
  plugin bundles).
