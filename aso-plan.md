# aso-plan.md — Bond ASO Metadata Update + Rollout Plan

> Written 2026-06-25. App: **Bond: Love Language Reminders** (ID `6768514177`, repo `~/bond`). Methodology: `~/Desktop/aso.md`.

---

## 0. TL;DR

- **Positioning:** love-language reminder nudges for couples — NOT Paired/Cozy couples chat, NOT My Love relationship counter.
- **Owns #1** on `love language reminders`; breakout term `love language` #22 (pop 16).
- **Problem:** subtitle + keywords scream "couples counter / Paired clone" — wrong SERP neighborhood.
- **US edit:** subtitle → `Daily Love Language Nudges`; swap `paired,relationship,tracker` → `nudge,spouse,milestone` (~29%).
- **Ship on next build**, manual release.

---

## STEP 0 — Re-pull

`pull-appstore-metadata.sh` · Astro `get_app_keywords(appId="6768514177", store="us")` · SERP on `love language`, `couples app`, `paired`.

---

## 1. Positioning

- **IS:** scheduled love-language nudges, partner reminders, anniversary/milestone prompts.
- **IS NOT:** couples messaging app, LDR chat, daily question games, relationship counter widget.

---

## 2. Competitor tiers

| Tier | Apps |
|---|---|
| **WALL** | Love Nudge (18k★ official), Paired (203k★), Cozy Couples (40k★), My Love (912k★), Widgetable |
| **WINNABLE PEERS** | lovelee couples, LYD, Kindest, Love Fuel, Vera, A Propos (sub-1k★ reminder apps) |
| **ADJACENT** | Evergreen, Lasting (therapy/marriage counseling) |

---

## 3. US metadata change (staged)

**Current:**
- subtitle: `Couple Counter · Anniversary`
- keywords: `relationship,tracker,countdown,long,distance,messages,notes,date,partner,questions,marriage,paired`

**Change to:**
- subtitle → `Daily Love Language Nudges`
- keywords → `countdown,long,distance,messages,notes,date,partner,questions,marriage,nudge,spouse,milestone`

| Edit | Rationale |
|---|---|
| Subtitle | Stops counter-SERP bleed; aligns with Love Nudge neighborhood |
| OUT `paired` | Paired brand homograph |
| OUT `relationship`, `tracker` | My Love / relationship-app wall |
| IN `nudge`, `spouse`, `milestone` | Product-fit + peer SERP vocabulary |

98→100 chars · ~29% swap.

**Next cycle (if counter terms stay 1000):** consider dropping `countdown`/`long`/`distance` from field.

---

## 4. Astro state (done 2026-06-25, tag migration complete)

**US:** 31 keywords · **global:** ~486 (non-US pop-5 @ 1000 junk pruned).

| Tag | Keywords |
|---|---|
| `deployed` | countdown, long, distance, messages, notes, date, partner, questions, marriage, nudge, spouse, milestone |
| `target` | love language, love language app, love languages, love reminder, love language reminder(s), relationship reminders, marriage reminder, partner reminder, bond love |
| `wall` | love nudge, couples app, paired, relationship tracker, anniversary countdown, love counter, cozy couples |

---

## 5. Product-gated

`five love languages` / `love language test` (no quiz), `couples widget`, `couples questions`, `long distance relationship` (no LDR chat), Apple Watch.

---

## 6. Rollout

Standard ASC pipeline in repo. Manual release. Re-verify subtitle landed — high-leverage single edit.
