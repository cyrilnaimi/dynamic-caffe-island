# Dynamic Caffe Island

A lightweight SwiftUI macOS app that renders a Dynamic-Island-style pill at the
top of your display. It keeps your Mac awake on demand (via the system's
power-assertion mechanism, à la `caffeinate`) and shows a live countdown until
the next sleep or screensaver event.

Designed with a pluggable "profile" architecture so new event sources and
animations can be added without modifying the core binary.

## Status

Early, pre-alpha. No builds are published yet; the Xcode project and source
will land once the animation vocabulary, UI concept, and plugin architecture
are locked down.

## Features

- **Keep awake**: menu-driven caffeinate with presets (5 min, 15 min, 30 min,
  1 h, 2 h, 5 h, "until a chosen time", and "indefinite") and one-click
  cancel.
- **Sleep countdown**: ambient display of the time remaining until display
  sleep, screensaver, or system sleep — whichever comes first.
- **Pluggable profiles**: third-party profiles discovered at launch so the
  island can surface any event source with its own animation vocabulary.

## Goals

- Minimum CPU and RAM footprint while idle.
- First-class accessibility: Reduce Motion, Increase Contrast, VoiceOver.
- macOS only; no kernel extensions; no network features in v1.

## Build

Not yet — the Xcode project is still being designed.

## License

[MIT](./LICENSE)
