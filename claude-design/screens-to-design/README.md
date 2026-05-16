# Screens to design

Each markdown file in this folder is one screen brief. Numbered roughly by priority.

| # | File | Priority | Notes |
|---|---|---|---|
| 01 | `01_onboarding.md` | P0 | First impression |
| 02 | `02_preference_choice.md` | P0 | Just me / With someone fork |
| 03 | `03_pairing.md` | P0 | Highest-friction moment in MVP |
| 04 | `04_pairing_success.md` | P1 | New interstitial — does not exist today |
| 05 | `05_reminders_empty.md` | P1 | First-run home + filtered empty state |
| 06 | `06_settings.md` | P0 | Does not exist today — blocks TestFlight QA |
| 07 | `07_notification_primer.md` | P1 | Pre-system-prompt context screen |
| 08 | `08_premium_gate.md` | P0 | Revenue surface — used in 4 places |
| 09 | `09_paywall.md` | P0 | Revenue surface — RevenueCat remote config spec |
| 10 | `10_daily_check_in.md` | P0 | The "magic feature" — needs the most thought |

## If you only have time for some

- Top 3 by impact: **01 + 08 + 10**
- Top 3 by ease: **02 + 04 + 05**
- Top 3 by user pain: **03 + 06 + 07**

## Things deliberately not on this list (do not design)
- Reminder Editor — let SwiftUI `Form` do its thing; you may suggest section-header copy in `copy/`
- Milestones list / editor — same as above
- Insights / Stats charts — current Charts framework usage is fine; suggest visual hierarchy tweaks in HANDOFF_NOTES
- Widgets — minimal by design
- Watch app — separate scope
- Reminder Row component — already iterated; we like it
