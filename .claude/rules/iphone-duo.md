---
paths:
  - "Bond/BondApp.swift"
  - "Bond/DesignSystem/UnfoldedSplit.swift"
  - "Bond/Features/Stats/StatsView.swift"
  - "Bond/Utilities/BondScreenshotSeed.swift"
  - "BondTests/UnfoldedSplitTests.swift"
---

# Bond: iPhone Duo (2026-10-21)

- Unfolded (regular width, room for two panes of at least 360 pt),
  `MainTabView` puts the tab view (Reminders, Check-In, Milestones, Settings
  and the tab bar) on the leading side of the fold and Insights (`StatsView`)
  in its own pane on the trailing side; the Insights tab leaves the bar while
  split. Pane edges come from `GeometryProxy.verticalFold()` (iOS 27.1
  `reservedRegions(.division)`), else an even split (`UnfoldedSplit`, tested
  in `UnfoldedSplitTests`). The folded Duo, every phone in portrait and the
  unfolded Duo held in portrait keep the single column.
- Folding only moves frames: the `TabView` is never rebuilt, so each tab keeps
  its pushed screens. Insights has no state worth carrying between its tab and
  its pane. If it gains some, lift it into `MainTabView`.
- Each tab's content and the Insights pane get `horizontalSizeClass = .compact`
  so they lay out as on a phone. Never set it on the `TabView` itself (other
  fleet apps saw the bar flip placement on a tab switch).
- `unfoldedBars(isSplit:)`: while split, a hard bottom scroll edge under the
  floating tab bar. Bar placement stays with the system. Never force it with
  `toolbarVerticalBehavior(.disabled)`: that inset the whole app 42 pt from
  both edges of the 951 pt inner display, and the strips captured pure white
  (no window paint reached them). Bond, Quit Zyn and Electrician all hit it.
- Measured unfolded (`BONDDUOTOUR`): root 867 pt with the status bar as an
  84 pt column on the display's trailing edge, fold 455.5...495.5, so the
  panes are 455.5 and 371.5 pt. iOS picks the tab bar per launch: a vertical
  bar against the fold inside the leading pane (titles level across the fold)
  or the floating bottom bar, where the leading pane's titles sit about 57 pt
  lower than Insights'. That offset is not a safe-area inset (both measured
  0), so padding Insights by the difference does nothing.
- Onboarding, invite welcome and pairing success use `.unfoldedLeadingPane`,
  with `UnfoldedBrandPanel` in the trailing pane. Sheets (editor, templates,
  paywall, pairing) are still system form sheets centred on the inner display.
- Captures: `gh-sim all --scheme Bond --device 'iPhone Duo' --args
  "-BondScreenshotSeed -BondDuoTour" --wait 6` plus `--url noop://1` through
  `noop://12` (they fail fast and only pace shots). `-BondDuoTour` (DEBUG)
  moves 8 s after launch, then every 14 s; gh-sim relaunches after unfolding,
  so it restarts there. `BONDDUOTOUR` lines in app.log map shots to stops and
  log the measured width and fold. The seed skips the notification primer and
  never touches Supabase or RevenueCat.
