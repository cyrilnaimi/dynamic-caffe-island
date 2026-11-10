# Localization guide

Dynamic Caffe Island ships in **English** (source language) and **French**.
Adding a language is one of the most welcome contributions — no Swift
knowledge needed for translators.

## Where strings live

| File | What | Format |
|---|---|---|
| `App/Localizable.xcstrings` | Every UI string: island, menu, Until window, Spotlight/Shortcuts action titles and dialogs | Xcode String Catalog (JSON) |
| `App/<lang>.lproj/AppShortcuts.strings` | Siri / Spotlight *phrases* ("Start ${applicationName}") | classic `.strings` — String Catalogs for App Shortcuts need macOS 14, we support 13 |

Durations ("30 min", "1 h 30 min"), clock times ("19:45" / "7:45 PM") and
dates are formatted by Foundation and are localized automatically — they are
**not** in the catalog.

## Add a language (translators)

1. Fork the repo and create a branch `i18n/<code>` (e.g. `i18n/de`).
2. Open `DynamicCaffeIsland.xcodeproj` in Xcode (run `xcodegen generate`
   first), select `Localizable.xcstrings`, click **+** at the bottom of the
   language list and pick your language. Translate every row until the
   language shows **100 %**.
   - No Xcode? Edit the JSON directly: add a `"<code>"` entry under each
     key's `localizations`, copying the shape of the `"fr"` entries, with
     `"state": "translated"`.
3. Copy `App/en.lproj/AppShortcuts.strings` to `App/<code>.lproj/` and
   translate the right-hand side of each line.
4. Check your work (see below) and open a pull request with a screenshot of
   the expanded island and the Until window in your language.

## Rules for translators

- **Keep placeholders exactly**: `%@`, `%lld`, `${duration}`, `${minutes}`,
  `${time}`, `${applicationName}`. You may move them inside the sentence,
  never drop or rename them. The lint below fails on mismatches.
- **Never translate the product name** "Caffe Island" / "Dynamic Caffe
  Island".
- **Island chips are tiny** (`15m`, `30m`, `1h`, `2h`, `Until…`, `Stop`):
  stay within ~8 characters. Use your language's usual short unit
  ("15 min", "1 Std.").
- **One action, one word**: the verb used for `Stop` must be the same in
  the island, menu and Spotlight actions.
- Read the **comment** attached to a key in the catalog — it explains where
  the text appears and what `%@` stands for.
- Use typographic punctuation for your language (French uses `’` and a
  space before `:`; German `„…“`, etc.).
- Siri/Spotlight phrases must sound natural when spoken and **must keep
  `${applicationName}`** (Apple requirement).

## Rules for developers

- SwiftUI `Text("…")`, `Button("…")`, `.help("…")` with **string literals**
  are localized automatically. A `String` *variable* passed to `Text` is
  **not** — use `LocalizedStringKey` parameters (see `Chip` in
  `NotchIslandView.swift`) or `Text(verbatim:)` for genuinely non-translatable
  text (e.g. a formatted time).
- Outside SwiftUI views use `String(localized: "…")`, with interpolation for
  dynamic parts: `String(localized: "until \(time)")` → key `until %@`.
- **Never concatenate** translated fragments ("Display sleeps" + " in " +
  time). Write the whole sentence as one key so word order can change
  (`Format.eventPhrase` shows the pattern).
- Durations: use `CaffeinationSession.Duration.durationText(_:)`
  (`DateComponentsFormatter`), never hand-built "min"/"h".
- Times: `date.formatted(date: .omitted, time: .shortened)` — honours 12/24 h.
- Add a `comment` in the catalog for any key whose context isn't obvious.
- App Intents: `LocalizedStringResource` titles/descriptions and `dialog:`
  literals are catalog keys too. A new App Shortcut phrase must be added to
  **every** `AppShortcuts.strings`.

## Check your work

```bash
xcodegen generate
xcodebuild -project DynamicCaffeIsland.xcodeproj -scheme DynamicCaffeIsland \
  -configuration Debug -derivedDataPath build/dd build
python3 scripts/i18n-check.py          # missing / stale / untranslated / placeholder lint
```

Run the app in your language without changing the system language:

```bash
open build/dd/Build/Products/Debug/DynamicCaffeIsland.app --args -AppleLanguages "(de)"
open -g "caffe://peek"                 # expanded island
open -g "caffe://start?minutes=30"     # start toast + live pill
open -g "caffe://pick"                 # Until window
```

Also try Xcode's **pseudo-languages** (Scheme › Run › Options › App
Language › *Double-Length Pseudolanguage* / *Right-to-Left*) to catch
truncation and layout issues before real translations exist.

`scripts/capture-manual.sh` regenerates the manual screenshots; add your
language to its `for lang in …` loop to produce yours.

CI runs `scripts/i18n-check.py` on every pull request.
