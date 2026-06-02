#!/usr/bin/env python3
"""Curated Bond US keywords from Astro research (pop/difficulty + search intent)."""
from __future__ import annotations

# ASC keyword field — max 100 chars, comma-separated, no spaces.
# Exclude words already in name/subtitle (Apple ignores duplicates).
ASC_KEYWORDS = (
    "relationship,tracker,anniversary,partner,widget,watch,spouse,distance,"
    "milestone,nudge,counter,paired"
)

# Phrases: high intent + pop/diff >= ~0.3 or strong competitor signal
CURATED_PHRASES = [
    # Tier 1 — best pop/diff + search intent (couples/reminder/love language)
    "couples app",
    "relationship app",
    "relationship reminder",
    "relationship tracker",
    "partner app",
    "couples widget",
    "long distance relationship",
    "love language",
    "love language app",
    "five love languages",
    "love languages app",
    "love language reminder",
    "couple app",
    "couple check in",
    "love counter",
    "love nudge",
    "anniversary tracker",
    "anniversary countdown",
    # Tier 2 — solid intent, moderate volume
    "partner reminder",
    "couples reminder",
    "couple reminder app",
    "long distance couples",
    "paired app couples",
    "love app",
    "love counter relationship",
    "relationship counter",
    "cozy couples",
    "love spouse",
    "anniversary counter",
    "apple watch couples",
    "widget couple",
    "free couples app",
    "couples relationship",
    "marriage reminder",
    "date night reminder",
    "shared calendar couples",
    # Tier 3 — love-language positioning (lower volume, high relevance)
    "acts of service",
    "words of affirmation",
    "quality time",
    "physical touch",
    "receiving gifts",
    # Name-aligned (keep one; avoid prayer-app SERP phrases)
    "husband wife app",
]

# Removed after research — wrong SERP or pop<10 with bad intent
REMOVED_PHRASES = [
    "husband & wife reminder",
    "bond",
    "husband & wife reminder - bond",
    "husband wife",
    "wife reminder",
    "reminder bond",
    "husband wife reminder",
    "husband and wife",
    "remind my husband",
    "remind my wife",
    "marriage app",
    "milestone tracker",
    "daily check in",
    "bond app couples",
    "pairing app couples",
    "location reminder",
    "surprise reminder",
    "notification reminder",
    "shared reminders",
    "thoughtful reminder",
    "nurture relationship",
    "relationship goals",
    "love language tracker",
    "couples reminder app",
    "widget reminder",
    "apple watch reminder",
    "spouse reminder",
    "couple notification",
    "wedding anniversary",
    "love note reminder",
    "reminder app",
    "marriage app",
]
