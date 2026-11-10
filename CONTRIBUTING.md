# Contributing

Thanks for helping! Quick map:

- **Translations** → [docs/LOCALIZATION.md](docs/LOCALIZATION.md)
- **Bugs / ideas** → open an issue with macOS version, Mac model (Intel /
  Apple silicon, notch or not) and steps to reproduce.

## Develop

```bash
brew install xcodegen
xcodegen generate                       # creates DynamicCaffeIsland.xcodeproj
swift test --package-path Packages      # unit + contract tests
scripts/build-release.sh --install      # universal build → /Applications
scripts/e2e.sh                          # end-to-end test of the installed app
```

`scripts/e2e.sh` needs Screen Recording permission for your terminal (window
titles + screenshots). `scripts/smoke-test.sh <app>` is the headless subset CI
runs on Intel and Apple silicon.

## Guidelines

- Keep the idle footprint tiny: no polling, no looping animations in the
  always-visible pill (measure with `scripts/measure-idle.sh`).
- Every feature must be reachable from the menu, a `caffe://` URL, and (when
  it makes sense) an App Intent — all routed through `CaffeCommand` /
  `AppRuntime`.
- New user-facing strings follow [docs/LOCALIZATION.md](docs/LOCALIZATION.md).
- Code is MIT. Don't paste code from GPL projects.
