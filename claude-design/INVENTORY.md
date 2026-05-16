# Screen Inventory

Every user-facing screen in the app today, in roughly the order a new user encounters them. Lines link to the source in `code-references/` (a snapshot at handoff time).

| # | Screen | File | One-line |
|---|---|---|---|
| 1 | Onboarding (Sign in with Apple) | `code-references/OnboardingView.swift` | Hero + SIWA button. Currently the SIWA button is decorative (B2 in MVP_TRIAGE). |
| 2 | Preference Choice | `code-references/PreferenceChoiceView.swift` | "Just me" / "With someone" — two cards. |
| 3 | Pairing | `code-references/PairingView.swift` | Form with generate-link + manual-code-entry sections. |
| 4 | Loading | `code-references/BondApp.swift` (inline) | Full-screen ProgressView. No branding. |
| 5 | Reminders list | `code-references/ReminderListView.swift` | Empty state + grouped Upcoming/Past lists. Toolbar: templates + add. Segmented "All / For Me" filter when paired. Swipe-to-done, swipe-to-delete. |
| 6 | Reminder Editor | `code-references/ReminderEditorView.swift` | Form: title, note, love language, target picker, trigger type (4 kinds with premium lock badges). |
| 7 | Reminder Row | `code-references/ReminderRow.swift` | The list-cell component. |
| 8 | Templates | `code-references/ReminderTemplatesView.swift` | Premium gate or list of 6 template groups; detail screen with "Add N reminders" CTA. |
| 9 | Daily Check-In | `code-references/DailyCheckInView.swift` | Premium gate / solo state / loading / today's question card + answer flow + partner reveal. |
| 10 | Milestones | `code-references/MilestonesView.swift` | Premium gate / empty state / list with countdown chip per row. |
| 11 | Milestone Editor | `code-references/MilestoneEditorView.swift` | Form: label, kind picker, date, repeat-yearly toggle. |
| 12 | Stats / Insights | `code-references/StatsView.swift` | Premium gate / streak triple-metric / balance score circle / distribution bar chart / weekly trend chart / insights list / summary metrics. |
| 13 | Paywall | `code-references/PaywallView.swift` | Wraps `RevenueCatUI.PaywallView`. Layout is remote-configured. |
| 14 | Premium Gate (shared) | `code-references/PremiumGateView.swift` | Icon + title + subtitle + Unlock button. Used as a fallback when not premium. |
| 15 | Widgets — Upcoming Reminder | `code-references/BondWidgetsBundle.swift` | Small/medium. Title + love-language symbol + relative time. |
| 16 | Widgets — Anniversary Countdown | `code-references/BondWidgetsBundle.swift` | Small. Days-to-go counter. |
| 17 | Watch — Dictate | `code-references/DictateView.swift` | TextField + LoveLanguage picker + Send button. One screen. |

## Screens that don't exist yet but should
- Settings / Account (see `screens-to-design/06_settings.md`)
- Notification permission primer (see `screens-to-design/07_notification_primer.md`)
- Pairing Success interstitial (see `screens-to-design/04_pairing_success.md`)

## Things the user can do but the UI doesn't surface well
- Sign out (you can't, currently — must delete the app)
- See who you're paired with (no display anywhere — `partnerProfile` is loaded but never shown)
- Unpair / leave a couple
- Recover a deleted reminder
- Re-roll a random-window reminder
- Mark a one-time reminder complete (event row inserts but reminder stays in list)
