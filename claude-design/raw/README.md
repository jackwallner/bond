# Raw store-screenshot captures — what Jack shoots, and how

These raws are composited UNTOUCHED into framed store images by Claude
Design (see `../SCREENSHOT-PROMPT.md`). They are never redrawn, so what you
capture is exactly what ships inside the device frame.

## Capture setup (iPhone)

- Simulator: **iPhone 17 Pro Max** (its native capture is 1320×2868 — the
  exact 6.9" ASC size, so the composite is 1:1 with no scaling artifacts).
- Light mode, terracotta accent (the default).
- Status bar: `xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`
- Capture: `xcrun simctl io booted screenshot claude-design/raw/raw-N-<slug>.png`
- Seed friendly data first — real partner name ("Sam" or similar), a few
  upcoming reminders with warm titles ("Bring her coffee in bed Saturday",
  "Ask about the big presentation"), no past-due rows, no empty states.

## Shots needed (in store order)

| File | Screen | Data to stage before capturing |
|---|---|---|
| `raw-1-home.png` | Reminders home | 4–5 upcoming reminders across love languages, check-in card visible, no past due |
| `raw-2-checkin.png` | Daily Check-In (revealed) | Both answers visible — this needs your paired test account |
| `raw-3-milestones.png` | Milestones | Anniversary + birthday with day counts |
| `raw-4-widgets.png` | Home Screen with Bond widgets | Countdown + reminders widgets placed on the simulator Home Screen |
| `raw-5-templates.png` | Templates browser | Premium unlocked so packs show full |
| `raw-6-insights.png` | Insights | Needs a week-plus of events; skip if data looks thin |
| `raw-w1-dictate.png` | Watch DictateView | Capture on **Apple Watch Ultra** sim (410×502 — store-ready as-is, goes straight to `output/watch/`) |

Five strong iPhone frames beat six padded ones — drop `raw-6` if Insights
looks sparse.
