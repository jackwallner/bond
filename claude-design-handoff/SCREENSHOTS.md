# App Store Screenshots — Design Handoff

This is a **screenshot-only** handoff. Do not make icons, visual systems, tokens, or redesigns. Only produce the `_screenshots_project/` tool and the screenshot PNGs as described below.

## What we need

6 iPhone + 3 Apple Watch screenshots for the App Store listing. The format matches what we did for Total Calories (see `~/Desktop/Total Calories/vitals/_screenshots_project/`).

The screenshots tool is a React app rendered as a local HTML page:
- `_screenshots_project/design-canvas.jsx` — shared design canvas component
- `_screenshots_project/image-slot.js` — image placeholder component
- `_screenshots_project/ios-frame.jsx` — iPhone frame (device bezel)
- `_screenshots_project/screenshots/` — actual screenshots (user provides these)
- `_screenshots_project/screens/` — screen layout definitions (one per direction)
- `_screenshots_project/screenshots-app/` — app-specific screen content + devices + panels + app entry

## Workflow

1. Open the existing `vitals/_screenshots_project` to see the format. It uses React + Babel standalone + a `design-canvas.jsx` canvas that renders phone frames with overlaid copy.

2. **Do not build a new tool from scratch.** Copy the `_screenshots_project/` **tooling** from vitals (`~/Desktop/Total Calories/vitals/_screenshots_project/`) — node_modules, package.json, design-canvas.jsx, image-slot.js, ios-frame.jsx, render.js, render.html, export.html, App Store Screenshots.html, etc. — those are the shared scaffolding. Only the files in `screenshots-app/` and `screens/` need to be rewritten for Bond.

3. I will provide the actual screenshots as PNGs in `_screenshots_project/screenshots/`. You design the layouts.

## Screens to capture (what the screenshots should show)

### iPhone (6 screenshots, 6.7" display, 1290×2796)

| # | Screen | What it shows | Why for ASO |
|---|--------|---------------|-------------|
| 1 | **Dashboard / Today** | The main view when you open Bond — a scrollable feed of reminders you've sent/received, daily check-in prompt at top, next milestone. Shows the app's core loop at a glance. | **Hero screenshot.** This is what the app *is*. Warm, paired, intentional. |
| 2 | **Send a Reminder** | The compose sheet — pick a love-language tag (acts of service / words of affirmation / quality time / gifts / physical touch), type your message, send to partner. | Shows the differentiation: love-language framing, not generic to-dos. |
| 3 | **Milestones** | Shared anniversary countdown + milestone list with dates (e.g. "Trip to Japan — 43 days away"). Home Screen widget concept shown in mockup. | Anniversary tracker is in our keywords. Proves the "shared milestones" value prop. |
| 4 | **Daily Check-In** | Check-in prompt card with partner's answer revealed (two avatars, both responses visible). The "sealed" state before reveal, then the reveal. | Emotional hook. Shows the daily ritual that makes Bond sticky. |
| 5 | **Apple Watch** | Phone screenshot with Watch inset or hand showing the Watch app — complication face with next reminder, dictation screen. | "Watch" is in our subtitle. Apple Watch is a key differentiator vs web-only couples apps. |
| 6 | **Pair / Profile** | The pairing screen (QR code or code entry) showing two profiles connected, or the "Your Partner" profile card. | Shows the paired nature. Keywords include "partner", "paired". |

### Apple Watch (3 screenshots, ~368×448)

| # | Screen | What it shows |
|---|--------|---------------|
| 1 | **Complication face** | A watch face with the Bond complication showing next reminder count |
| 2 | **Dictate reminder** | "New Reminder" screen with voice dictation active |
| 3 | **Today's overview** | List of today's reminders with check-off |

## Copy requirements for overlay text

Each screenshot gets:
- **Headline** (2–5 words, bold, left-aligned over or beside the phone)
- **Subhead** (5–10 words, lighter weight, explaining the feature)
- **Background** (gradient, brand-consistent, warm — use the bond accent palette: terracotta, blush, cream, soft gold)

The wireframe for each layout goes in `screenshots-app/phone-screens.jsx` (screen positioning, copy overlays, device frame config).

## What NOT to do

- Do not design app icons or visual systems here (that's in the main PROMPT.md).
- Do not redesign app screens — we're capturing what exists.
- Do not write Swift code or design tokens.
- Do not propose marketing copy beyond the screenshot headlines/subheads.

## Output

After you build out `screenshots-app/` and `screens/`:

1. Open `App Store Screenshots.html` in a browser to verify layout.
2. Export each iPhone screen + each Watch screen as individual PNGs (use `export.html` or render script from vitals).
3. Place the exported PNGs in `_screenshots_project/app-store-pngs/`.
4. I'll take these and upload to ASC via fastlane deliver.

That's it — 6 iPhone + 3 Watch PNGs, ready for the App Store listing.
