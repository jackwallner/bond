# Astro ASO setup — Bond

> Process: [`astro-setup-process.md`](astro-setup-process.md) · Playbook: [`astro-global-aso-go-2026.md`](astro-global-aso-go-2026.md)

Last full **go** run: **2026-05-25**

## App

| Field | Value |
|-------|-------|
| App Store name | Bond: Love Language Reminders |
| Bundle ID | `com.jackwallner.bond` |
| ASC app ID | `6768514177` |
| Astro app | **Bond** (temporary) — ID `101` |
| Draft version | `1.0` (`PREPARE_FOR_SUBMISSION`) |
| Astro stores target | **91** |

## US listing (ASC)

| Field | Limit | Chars | Value |
|-------|-------|-------|-------|
| **Name** | 30 | 29 | `Bond: Love Language Reminders` |
| **Subtitle** | 30 | 29 | `Couples · Watch · Anniversary` |
| **Keywords** | 100 | ≤100 | `relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin,marriage,cupla,between` |

**Rules:** comma-separated, no spaces; no repeats of name/subtitle tokens (Apple indexes all three).

Files: `fastlane/metadata/en-US/{name,subtitle,keywords,description}.txt`

## Research summary

### Removed (wrong SERP)

- Prayer / wife games: `husband wife reminder`, `wife reminder`, `remind my husband/wife`
- Other apps: headache/migraine, calorie, GLP, baseball, sober trackers (pruned in Astro)

### Tier 1 — track in Astro

| Phrase | Why |
|--------|-----|
| `couples app` | Core category SERP |
| `relationship reminder` | Vera, Love Nudge niche |
| `love language app` | Category anchor |
| `anniversary tracker` | My Love, counters |
| `couple check in` | Paired |
| `long distance relationship` | Strong couples intent |

### Competitors

Paired, Between, Cupla, Love Nudge, Couple Joy, Evergreen, Vera — see `scripts/astro-research-competitors.json`.

## Scripts

| Script | Purpose |
|--------|---------|
| `./scripts/pull-appstore-metadata.sh` | Pull ASC → `fastlane/metadata/` (+ backup) |
| `./scripts/aso-apply-locale-optimizations.py` | Native keyword pass (50 locales) |
| `./scripts/astro-sync-all-stores.sh` | MCP sync → 91 Astro stores |
| `./scripts/astro-prune-all-stores.sh` | Remove junk per store |
| `./scripts/astro-tier1-second-pass.py` | Suggestions for Tier-1 stores |
| `./scripts/asc-finish-missed.sh` | Draft version + API PATCH + deliver |

## Astro tracking

| Artifact | Path |
|----------|------|
| Config | `scripts/.astro-app.json` |
| US curated | `scripts/astro-keywords-us.json` |
| Per-store sync | `scripts/astro-keywords-by-store/` |
| Locale report | `scripts/aso-locale-optimization-report.json` |
| Phase B report | `docs/astro-phase-b-report.md` |

## After App Store launch

1. Register Bond in Astro with real App Store ID (replace temporary `101`).
2. `./scripts/astro-setup.sh --skip-pull`
3. **go refine** in 7–14 days when rank data exists.

## ASC experiments (next)

1. Screenshots — pairing, notification, love-language tags.
2. Promotional text — test “Bond+ daily check-in” vs anniversary angle.
3. Localized screenshots for de/fr/es/ja when traffic warrants.
