---
paths:
  - "Bond/BondApp.swift"
  - "Bond/DesignSystem/UnfoldedSplit.swift"
  - "Bond/DesignSystem/BondStyle.swift"
  - "Bond/Features/ReminderEditor/ReminderEditorView.swift"
  - "Bond/Features/Stats/StatsView.swift"
  - "Bond/Utilities/BondScreenshotSeed.swift"
  - "BondTests/UnfoldedSplitTests.swift"
---

# Bond: iPhone Duo (2026-10-21, revised 2026-10-23)

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
- Split, each tab applies `clearsFloatingTabBar`: content ends 12 pt above
  the floating tab bar, and a row that line would slice is hidden whole
  (`PaneCut`, tested). Rows report their frames: every `bondWarmRow()`
  (through its row background, so a cut between rows of one card rounds its
  bottom corners), every `BondSectionHeader` (it goes with its first row)
  and the Reminders hero cards (`.paneRow()`). A new card in a split tab
  that is neither needs `.paneRow()`, or the line slices it. Clipping at the
  bar (run5, 2026-10-23) was rejected: the bar cut the Up next row's chips
  and Settings' Pink row mid-glyph. A hard scroll edge before that let rows
  read through the bar. Folded the mask is fully open and nothing reports.
- Split, Reminders' add button sits in the bar (as on Milestones), not
  floating over the pane's last row, and Settings takes a large title like
  the other tabs. Folded both are unchanged.
- The tab view first lays out once the width and fold are measured. Since
  then every inner launch (38 of 38 across six runs, 2026-10-23) got the
  floating bottom bar in the leading pane; before, iOS sometimes chose a
  vertical bar against the fold.
- That bottom-bar tab pane has a horizontal navigation bar, with a row above
  each large title. Insights took the vertical behaviour with no row, so its
  title sat 57 pt higher. `horizontalNavigationBar()` disables vertical bars
  on the Insights pane only (iOS 27.1); the titles are now level, and the
  status bar moves from an 84 pt trailing column to a top row over Insights.
  Never disable vertical bars on the root: that inset the whole app 42 pt
  from both edges of the inner display and left white strips (Bond, Quit Zyn
  and Electrician all hit it). A compact size class on the `TabView` did not
  remove the row.
- Sheets go through `unfoldedSheet` (never `.sheet`). While split
  (`isUnfoldedSplit`, measured once at the root by
  `unfoldedSplitEnvironment()`, because panes report compact) it presents a
  full-screen cover with the content in the leading pane and
  `UnfoldedBrandPanel` beside it. A system sheet was centred on the display
  with the fold through the form. The reminder editor passes
  `splitsItself` and fills the other pane with a live preview (the
  notification, its list row, its love language); the review rejected the
  brand splash there as placeholder content. The preview has no navigation
  bar: a NavigationStack there with `horizontalNavigationBar()` inset the
  whole cover 42 pt from both display edges (inside a cover the modifier
  acts like it does on the root). Its title is placed by hand with its
  baseline at the form's large title (117.7 pt). The form takes
  `clearsFloatingTabBar` too, so its last rows end whole above the home
  indicator. Its love-language chips wrap (`FlowLayout`) while split
  instead of running off the card edge.
- Onboarding, invite welcome and pairing success use `.unfoldedLeadingPane`,
  with `UnfoldedBrandPanel` in the trailing pane.
- Captures: one `gh-sim all --scheme Bond --device 'iPhone Duo' --args
  "-BondScreenshotSeed -BondDuoTour" --record-seconds 20` with one
  `--screen "-DuoScreen <surface>"` per surface (reminders, checkin,
  milestones, insights, settings, editor). gh-sim relaunches the app per
  screen, folded and unfolded. `-DuoScreen` (DEBUG, `DuoScreen` in
  `BondScreenshotSeed.swift`) sets the launch tab; `editor` opens "Book dinner
  at Lucia's" through the notification route. Never use `--url`: iOS 27.1
  puts an "Open in" alert over every custom-scheme link. `-BondDuoTour` only
  walks the tabs when no surface is named, so the recording shows real tab
  changes. `BONDDUO` NSLog lines record the measured width and fold, but
  gh-sim's app.log came back with empty message bodies on 2026-10-23, so
  measure from the PNGs (3 px per pt). The
  seed skips the notification primer and never touches Supabase or
  RevenueCat.
