---
paths:
  - "Bond/**"
  - "Shared/**"
  - "BondWatch/**"
  - "BondWidgets/**"
  - "BondTests/LocalizationTests.swift"
  - "Tools/Localization/**"
---

# Little Gestures: localization (added 2026-11-04)

All user-facing copy is routed through one string catalog. The app ships in
English only for now; other languages are written in separate runs by adding
`localizations` to the catalog, so nothing in code should need to change then.

## Setup
- One catalog, `Shared/Localizable.xcstrings` (source `en`, every key
  `extractionState: manual`). `Shared/` is a source of the app, the Watch app
  and the widgets, so all three compile it. XcodeGen 2.39+ reads its languages
  into `knownRegions` (`project.yml` pins `minimumXcodeGenVersion: 2.39.0` and
  `developmentLanguage: en`).
- Info.plist purpose strings live in `Bond/InfoPlist.xcstrings` and
  `BondWatch/InfoPlist.xcstrings`. The display name is the brand and stays
  plain.
- Do not add other languages to `CFBundleLocalizations` until their
  translations are in the catalog.
- `python3 Tools/Localization/check.py` (repo root, no Xcode needed) fails on
  a source literal with no key, a `return "..."`, switch arm, ternary of
  literals or error/status assignment that skips the catalog, a malformed
  plural, or a purpose string with no entry. Add each new language to `LANGS`
  in the script when it is added to the catalog, so a missing translation
  fails. Mark a deliberate non-copy line `// l10n-ignore`.
- `BondTests/LocalizationTests.swift` proves the catalog compiles to every
  `.lproj` in its `languages` list and that plural forms pick the right text.

## Adding or changing copy
- `Text("literal")`, `Button`, `Label`, `Section`, `navigationTitle`, `alert`
  and friends localize themselves. Copy held in a `String` (view parameters,
  enums, models, notifications, errors, widget placeholders) must be
  `String(localized: "...")`. Logs, analytics, RevenueCat ids, stored keys and
  tags stay plain.
- Keys are the English sentence. Whole sentences only, never spliced fragments;
  branch and give each variant its own key (see
  `LoveLanguage.leastExpressedInsight`, one sentence per language, so no
  translated title is lowercased or spliced).
- Counts go in plural variations (`%lld reminders`), never `n == 1 ? "x" : "xs"`.
  A label drawn beside a separately rendered number cannot be a plural key, so
  `PluralLabel` asks the catalog's `"%lld plural category"` key for the CLDR
  category and picks one whole key per category (`"day streak"`,
  `"day streak (few)"`, `"day streak (many)"`). Give the `(few)`/`(many)` keys
  an `en` value so English never shows the key.
- No `.capitalized`/`.lowercased()` on translated text. A title-case variant
  gets its own keys (`bondIntroOfferBadge`).
- Dates, numbers, percents and durations go through Foundation:
  `formatted(.percent)`, `formatted(.number...)`, `Duration.formatted(.units...)`,
  `DateComponentsFormatter` (`Package.durationPhrase`). Prices come only from
  StoreKit (`localizedPriceString`); trial lengths come from the package's
  `introductoryDiscount`, never from parsing a label.
- Stored English values stay English in the store (`kind`, `triggerType`,
  `rrule`, `status`). They are translated at display time
  (`MilestoneDTO.kindTitle(_:)`, `RecurrencePreset.title`).
- Brand stays untranslated: Little Gestures, Little Gestures+ (`BondBrand`).
- Reminder and daily-question copy that arrives from Supabase is shown as is.
  The templates, starter chips and the offline fallback question ship in the
  app, so they are keyed; a template copied into a new reminder is saved in the
  language it was picked in.
- `Shared/` code runs in the widget and Watch too: use `String(localized:)`
  with the default bundle, and compute catalog-backed statics (templates,
  chips) as `var`, not `let`, so they follow the active language.

## Proving a change
`python3 Tools/Localization/check.py`, then `gh-sim test --scheme Bond`. For a
language, `gh-sim all` with `--screen "-AppleLanguages (de) -AppleLocale de_DE"`
plus the existing screenshot switches. Never set the production RevenueCat
`appl_` key on a simulator run.
