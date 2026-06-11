# Paste this prompt into Claude Design (repo linked via "Link local code")

---

Produce exactly 6 finished PNGs and nothing else. No preamble, no
explanations, no alternates, no manifest, no follow-up questions.

## The one rule that overrides everything else

**Composite the raw screenshots in `claude-design/raw/` into each frame
AS-IS. Do not redraw, recreate, retype, restyle, or "improve" a single
pixel of the app UI.** The raws are the app; your job is only the
packaging around them — canvas, device frame, and caption text. If a raw
looks imperfect, ship it anyway. A recreated screen is a failed output
even if it looks better.

## Canvas — exact App Store pixels

- Every iPhone output: **1320 × 2868 px portrait** (6.9" slot), PNG, sRGB,
  no transparency. This is non-negotiable; if your tooling can't hit exact
  pixels, match the 1320:2868 aspect exactly at maximum resolution and
  never crop or letterbox.
- The raws are themselves 1320×2868 iPhone 17 Pro Max captures. Scale each
  raw down uniformly to fit inside the device frame — no stretching, no
  cropping beyond the frame's screen cutout corners.

## Frame anatomy — identical on all 6 so the set reads as one family

- Background: warm cream `#F8E2C6`, with a very soft radial peach glow
  (`#F2CFAE`) behind the device. Flat, calm, no patterns.
- Headline: Plus Jakarta Sans Bold (or closest geometric-humanist sans),
  near-black warm brown `#3B2A1F`, centered, top ~7% of canvas.
- Subline: same face regular, warm brown `#7A5B48`, directly under the
  headline.
- Device: a simple modern iPhone mockup frame (dark titanium, thin
  bezels, Dynamic Island) holding the raw, centered, ~72–76% of canvas
  height, bottom edge allowed to bleed off-canvas on frames 2–6 if it
  helps the raw read larger. Soft warm shadow `#73381A` at low opacity.
- Accent moments (underline, small heart glyph) use terracotta `#BE5048`
  or the brand gradient `#E0845A → #C0506B`. Sparingly — one per frame max.

## Frames (raw → output, captions verbatim)

1. `raw-1-home.png` → `store-1-reminders.png`
   Headline: "Love language reminders"
   Subline: "Show up for your partner — right on time"
2. `raw-2-checkin.png` → `store-2-checkin.png`
   Headline: "One check-in, two answers"
   Subline: "Answer today's question, then reveal theirs"
3. `raw-3-milestones.png` → `store-3-milestones.png`
   Headline: "Never miss a milestone"
   Subline: "Anniversaries and big days, counted down"
4. `raw-4-widgets.png` → `store-4-widgets.png`
   Headline: "Widgets that keep love close"
   Subline: "Countdowns and reminders on your Home Screen"
5. `raw-5-templates.png` → `store-5-templates.png`
   Headline: "Date nights to long distance"
   Subline: "Ready-made reminder packs for every couple"
6. `raw-6-insights.png` → `store-6-insights.png`
   Headline: "See how you show up"
   Subline: "Streaks and balance across love languages"

If a listed raw is missing from `claude-design/raw/`, skip that frame and
produce the rest — do not invent a screen to fill the slot.

Watch raws (`raw-w1-*.png`, 410×502) are NOT yours to frame — Apple wants
watch screenshots near-raw. Ignore them.

---

# After Claude Design returns (Jack / Claude Code)

1. Download outputs to `claude-design/output/store/`.
2. Verify: `sips -g pixelWidth -g pixelHeight claude-design/output/store/*.png`
   — every file must be exactly 1320×2868. Fix drift with
   `sips -z 2868 1320 <file>` (height first).
3. Place finals in `fastlane/screenshots/en-US/`, copy `raw-w1-*.png` to
   `fastlane/screenshots/en-US/` watch slots, then run
   `./scripts/upload-appstore-metadata.sh`.

ASC size reference (looked up 2026-06-11): 6.9" iPhone portrait accepts
1320×2868, 1290×2796, or 1260×2736 — we standardize on 1320×2868. Watch
accepts one consistent size; Ultra captures are 410×502.
