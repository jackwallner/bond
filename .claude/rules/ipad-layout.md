---
paths:
  - "Bond/DesignSystem/ReadableColumn.swift"
  - "Bond/DesignSystem/UnfoldedSplit.swift"
  - "Bond/BondApp.swift"
  - "project.yml"
  - "Bond/Info.plist"
---

# Little Gestures: iPad layout (added 2026-11-12)

The app is universal (`TARGETED_DEVICE_FAMILY: "1,2"` on `Bond` and `BondWidgets`;
the watch app is untouched). iPad runs all four orientations
(`UISupportedInterfaceOrientations~ipad`); iPhone stays portrait. Once a build
with iPad support ships it can never be removed, so every screen has to look
designed for iPad.

## One column, centred
- The iPhone Duo split (`UnfoldedSplit`, brand panel, full-screen sheets) is for
  the Duo only. `UnfoldedSplit.isRegular` is false on iPad, because a regular
  width there would otherwise split a 13-inch screen into two phone panes.
  Never gate Duo behaviour on size class alone.
- `readableColumn()` (`ReadableColumn.swift`) centres scrolling content (List,
  Form, ScrollView, pushed screens included) at `BondColumn.list` (700 pt) by
  growing the scroll content margins; the navigation bar stays full width. It
  is applied once, on the tab content in `MainTabView`.
- `readablePage()` caps a page that does not scroll at `BondColumn.page`
  (560 pt): onboarding, invite, pairing success.
- Both are no-ops at phone widths and in a narrow Split View or Slide Over.
- Sheets stay system sheets (`unfoldedSheet` is a plain sheet off the Duo), so
  iPad shows its own form sheet. Do not add `presentationDetents` that assume a
  phone height without checking the iPad frame.

## Proving a change
Portrait: `gh-sim all --scheme Bond --device 'iPad Pro 13-inch (M5)'` with one
`--screen` per surface: `-BondScreenshotSeed -DuoScreen <reminders|checkin|
milestones|insights|settings|editor>`, `-BondOnboardingSeed`,
`-PaywallSnapshot trial`. Landscape: a launch argument cannot rotate the
device, so run `gh-sim all --scheme BondUITests --device 'iPad Pro 13-inch (M5)'
--only BondUITests/IPadLandscapeCaptureTests`. Its attachments come back
2064x2752 with the content rotated 90 degrees clockwise; `sips -r 270` turns
them upright (2752x2064). The plan paywalls show "Couldn't Load Plans" on a
simulator (no RevenueCat products), so only the trial offer can be captured.
Never set the production RevenueCat `appl_` key on a simulator.
