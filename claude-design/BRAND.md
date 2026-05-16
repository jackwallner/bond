# Bond — Brand & Visual Tokens

These are the tokens used today. Propose changes only with rationale; default to additions, not replacements.

## Typography
- System font (SF Pro). No custom fonts.
- Hierarchy via SwiftUI text styles only: `.largeTitle`, `.title`, `.title2`, `.title3`, `.headline`, `.subheadline`, `.body`, `.callout`, `.caption`, `.caption2`, `.footnote`.
- Bold: `.bold()` on headlines and primary metrics only.
- Monospaced digits (`.monospacedDigit()`) for countdowns and streaks.

## Color
**System-driven, light+dark mode native.** One brand accent.

| Token | Value (today) | Used for |
|---|---|---|
| Brand accent | `.pink` (SwiftUI system pink) | Primary CTAs, hearts, gate icons, brand moments |
| Surface | `Color(.systemBackground)` | App backgrounds |
| Card | `Color.gray.opacity(0.08)` and `.regularMaterial` | Question cards, choice cards |
| Text primary | `Color(.label)` | Default |
| Text secondary | `Color(.secondaryLabel)` via `.foregroundStyle(.secondary)` | Subtitles, captions |
| Success | `.green` | Acted/done state |
| Warning | `.orange` | Best streak; balance score mid |
| Error | `.red` | Inline error footers |

**Love-language tints** (do not change without proposing a full alternative set):

| Language | Tint | Symbol |
|---|---|---|
| Words of Affirmation | `.pink` | `quote.bubble.fill` |
| Acts of Service | `.orange` | `hands.sparkles.fill` |
| Receiving Gifts | `.purple` | `gift.fill` |
| Quality Time | `.blue` | `clock.fill` |
| Physical Touch | `.red` | `hand.raised.fingers.spread.fill` |

Note: Words and Touch are both warm hues — they read similarly in low light. If you redesign tints, address this.

## Iconography
- SF Symbols only. Prefer `.fill` variants for love-language icons, outline for navigation/utility.
- Size mapping:
  - `.font(.system(size: 56))` for gate hero icons
  - `.font(.system(size: 72))` for onboarding hero
  - `.font(.title)` / `.title2` for in-context affordances
- Multicolor variants OK on iOS 18, but rendered with `.foregroundStyle(<lang>.tint)` for consistency.

## Corner radius & material
- Cards: `RoundedRectangle(cornerRadius: 16)` for hero cards, `cornerRadius: 10` for inline content.
- Material: `.regularMaterial` for choice cards, `.ultraThinMaterial` reserved for sheet headers if introduced.
- Buttons: `.buttonStyle(.borderedProminent)` for primary, `.plain` for tappable rows, `.bordered` for secondary actions.

## Motion
- Tab transitions: `.easeOut(duration: 0.35)`, `.opacity` or `.opacity.combined(with: .move(edge:))`.
- No springs > 0.6 damping.
- Respect `UIAccessibility.isReduceMotionEnabled` — fall back to `.opacity` only.
- No persistent loops. No bouncing hearts. No confetti.

## Copy voice — micro-rules
- Sentence case in buttons ("Save", "Unlock Premium", not "SAVE").
- Active voice ("Pair with your partner", not "Partner pairing available").
- Specific second person ("you", "your partner") — never "users."
- Numbers: spell out one through nine in body, numerals 10+. Always numerals for streaks, counts, dates.
- No exclamation points except for genuine celebration (paywall purchase, milestone hit). One per screen max.
- No emoji in product UI. The one exception is the pairing share message (`ShareLink` subject), where 💕 is acceptable because it's outgoing iMessage copy.

## Existing patterns to honor
- **Premium gate** = SF Symbol (56pt, .pink) + headline + subtitle + `Button("Unlock Premium")` (borderedProminent). Currently in 4 places: `MilestonesView`, `StatsView`, `DailyCheckInView`, `ReminderTemplatesView`. We want to evolve this — see BRIEF Job 2.
- **Empty state** = `ContentUnavailableView` with SF Symbol + headline + description. Already used in Reminders, Milestones, Stats.
- **Inline error** = small red footnote under a Form section. Used in Pairing, Editor, Onboarding.
- **Toolbar** = `.topBarTrailing` for "add" affordances; `+` symbol.
