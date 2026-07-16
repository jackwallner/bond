# Bond — Astro global ASO phase B report

**Date:** 2026-05-25  
**Pipeline:** `astro-global-aso-go-2026.md`  
**ASC draft version:** `1.0` (`PREPARE_FOR_SUBMISSION`)

## Summary

| Item | Result |
|------|--------|
| ASC locales optimized | **50** |
| Char limits (name/subtitle/keywords) | **All OK** |
| API metadata PATCH | **50/50 success** |
| fastlane deliver (appInfo + version) | **Success** (50 locales) |
| Astro store sync (91 target) | See `_summary.json` when sync completes |
| Astro app ID | `101` (temporary; ASC `6768514177`) |

## Pull backup

`fastlane/metadata.bak.20260525-190656/` — captured before pull; en-US had prior optimized copy (`Bond: Love Language Reminders`).

## Pre-upload backup

`fastlane/metadata.bak.pre-upload-20260525-190909/` — full optimized tree before ASC upload.

## en-US (primary)

| Field | Before (ASC pull) | After | Len |
|-------|-------------------|-------|-----|
| Name | Husband & Wife Reminder - Bond | Bond: Love Language Reminders | 29 |
| Subtitle | (empty / old) | Couples · Watch · Anniversary | 29 |
| Keywords | (varied) | relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin,marriage,cupla,between | ≤100 |

## All locales

Full before/after JSON: `scripts/aso-locale-optimization-report.json`

Highlights:

- Replaced **Husband & Wife Reminder** naming globally (wrong SERP: prayer apps, wife games).
- Native **keywords** and **subtitles** for Tier-1 (de, fr, es, it, pt-BR, ja, ko, zh-Hans/Hant, ar, etc.).
- **Descriptions** added for en-*, de-DE, fr-FR, es-ES, ja, zh-Hans; English fallback for remaining locales.

## Upload confirmation

```
./scripts/asc-finish-missed.sh
  → asc-upload-metadata: Patched 50 locale(s)
  → deliver: finished successfully (SKIP_SCREENSHOTS=true)
```

Draft has **50** `appInfo` localizations. Attach a build to version `1.0` and submit when ready.

## Astro

- Competitor research (prior): `scripts/astro-research-competitors.json`
- US curated list: `scripts/astro-keywords-us.json` (58 phrases)
- Live competitor scan: `scripts/astro-competitor-research.json` (if `astro-competitor-scan.py` completed)

## Recommended ASC languages not yet prioritized

All **50** deliver-supported locales are on disk. No additional ASC folders required for deliver 2.234.

For **Astro-only** countries without a dedicated ASC locale, keywords sync via `fallbackLocales` in `scripts/astro-stores-2026.json` (e.g. `bg`, `ee`, `nz` → `en-GB`).

## Next: go refine

Calendar reminder **~2026-06-08** (14 days after metadata is live):

1. `./scripts/pull-appstore-metadata.sh`
2. `./scripts/astro-optimize.py --all-stores`
3. Tune fastlane from rank data → prune → `./scripts/asc-finish-missed.sh`
