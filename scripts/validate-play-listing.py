#!/usr/bin/env python3
"""Validate Google Play listing copy under android/play-assets/metadata/android.

Checks every locale folder for Play's limits (title 30, short 80, full 4000),
the house rules (no em dashes, no prices, no Apple wording, no promo words in
the title, no medical claims), the brand in every title, the Google Play billing
line and, for every non-English locale, a plain statement that the app is in
English (the Android app is not localized). en-US must match the live listing in
.play-live-listing.json when that file is present. Exit 1 on any failure.

Usage: scripts/validate-play-listing.py [--app bond]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "android/play-assets/metadata/android"
LIMITS = {"title.txt": 30, "short_description.txt": 80, "full_description.txt": 4000}
# Play language codes accepted by the Publishing API (fastlane supply list).
PLAY_LANGS = set(
    "af am ar az-AZ be bg bn-BD ca cs-CZ da-DK de-DE el-GR en-AU en-CA en-GB en-IN "
    "en-SG en-US en-ZA es-419 es-ES es-US et eu-ES fa fi-FI fil fr-CA fr-FR gl-ES "
    "hi-IN hr hu-HU hy-AM id is-IS it-IT iw-IL ja-JP ka-GE km-KH kn-IN ko-KR ky-KG "
    "lo-LA lt lv mk-MK ml-IN mn-MN mr-IN ms ms-MY my-MM ne-NP nl-NL no-NO pl-PL "
    "pt-BR pt-PT rm ro ru-RU si-LK sk sl sr sv-SE sw ta-IN te-IN th tr-TR uk vi "
    "zh-CN zh-HK zh-TW zu".split()
)
TITLE_BANNED = re.compile(r"\b(free|best|top|#1|new|sale)\b", re.I)
PRICE = re.compile(r"[$€£¥₹]\s?\d|\d[.,]\d\d\s?(?:€|zł|kr|lei|Kč|₺|₽|₴)")
APPLE = re.compile(r"Apple|App Store|iPhone|iCloud|Apple Watch", re.I)
URL_OK = re.compile(r"https://jackwallner\.github\.io/\S+")
LIVE = Path(__file__).resolve().parent.parent / ".play-live-listing.json"
BRAND = "Little Gestures"
# Positive treat/cure/diagnose claims in English copy; the "does not provide ... diagnosis or
# treatment" disclaimer is allowed.
MEDICAL = re.compile(r"\b(cures?|heals?|treats? (?:your|anxiety|depression)|diagnoses)\b", re.I)
# The live en-US copy names what the Android build lacks (Apple Watch, iOS
# widgets, iPhone arrival alerts). It is kept verbatim as the source of truth,
# so Apple wording is allowed there and nowhere else.
APPLE_ALLOWED = {"en-US"}
# Phrase that says "the app is in English" in each non-English listing.
ENGLISH_NOTE = {
    "de": "Die App ist auf Englisch", "fr": "L'appli est en anglais", "es": "La app está en inglés",
    "pt-BR": "O app está em inglês", "pt-PT": "A app está em inglês", "it": "L'app è in inglese",
    "nl": "De app is in het Engels", "sv": "Appen är på engelska", "no": "Appen er på engelsk",
    "da": "Appen er på engelsk", "fi": "Sovellus on englanninkielinen",
    "pl": "Aplikacja jest w języku angielskim", "cs": "Aplikace je v angličtině",
    "sk": "Aplikácia je v angličtine", "sl": "Aplikacija je v angleščini",
    "hr": "Aplikacija je na engleskom jeziku", "hu": "Az alkalmazás angol nyelvű",
    "ro": "Aplicația este în limba engleză", "el": "Η εφαρμογή είναι στα αγγλικά",
    "tr": "Uygulama İngilizcedir", "ru": "Приложение на английском языке",
    "uk": "Застосунок англійською мовою", "ar": "التطبيق باللغة الإنجليزية",
    "iw": "האפליקציה באנגלית", "hi": "यह ऐप अंग्रेज़ी में है", "bn": "অ্যাপটি ইংরেজিতে",
    "mr": "हे ॲप इंग्रजीत आहे", "ta": "இந்த ஆப் ஆங்கிலத்தில் உள்ளது",
    "te": "ఈ యాప్ ఇంగ్లీష్‌లో ఉంది", "kn": "ಈ ಆ್ಯಪ್ ಇಂಗ್ಲಿಷ್‌ನಲ್ಲಿದೆ", "ml": "ഈ ആപ്പ് ഇംഗ്ലീഷിലാണ്",
    "id": "Aplikasi ini berbahasa Inggris", "ms": "Aplikasi ini dalam bahasa Inggeris",
    "th": "แอปนี้เป็นภาษาอังกฤษ", "vi": "Ứng dụng này bằng tiếng Anh", "ja": "アプリは英語のみです",
    "ko": "앱은 영어로 제공됩니다", "zh-CN": "本应用为英文界面", "zh-TW": "本 App 為英文介面",
    "zh-HK": "本 App 為英文介面", "ca": "L'app està en anglès",
}


def english_note(loc: str) -> str | None:
    if loc.startswith("en"):
        return None
    return ENGLISH_NOTE.get(loc) or ENGLISH_NOTE.get(loc.split("-")[0])


def live_listing() -> dict[str, dict]:
    if not LIVE.exists():
        return {}
    return {x["language"]: x for x in json.loads(LIVE.read_text(encoding="utf-8"))["listings"]}


def check(locale_dir: Path, app: str) -> list[str]:
    errs: list[str] = []
    loc = locale_dir.name
    if loc not in PLAY_LANGS:
        errs.append(f"unknown Play language code {loc}")
    for name, limit in LIMITS.items():
        p = locale_dir / name
        if not p.exists():
            errs.append(f"missing {name}")
            continue
        text = p.read_text(encoding="utf-8").strip()
        n = len(text)
        if n == 0 or n > limit:
            errs.append(f"{name} {n}/{limit}")
        if "\u2014" in text:
            errs.append(f"{name} has an em dash")
        if re.search("[\u00ad\u200b\ufeff]", text):
            errs.append(f"{name} has an invisible character")
        if PRICE.search(text):
            errs.append(f"{name} looks like it has a price: {PRICE.search(text).group(0)!r}")
        if loc not in APPLE_ALLOWED and APPLE.search(URL_OK.sub("", text)):
            errs.append(f"{name} mentions Apple wording: {APPLE.search(text).group(0)!r}")
        if loc.startswith("en") and MEDICAL.search(text):
            errs.append(f"{name} makes a medical claim: {MEDICAL.search(text).group(0)!r}")
        if name != "full_description.txt" and "\n" in text:
            errs.append(f"{name} spans lines")
    title = (locale_dir / "title.txt").read_text(encoding="utf-8") if (locale_dir / "title.txt").exists() else ""
    if TITLE_BANNED.search(title):
        errs.append(f"title has a promo word: {title.strip()!r}")
    full = (locale_dir / "full_description.txt").read_text(encoding="utf-8") if (locale_dir / "full_description.txt").exists() else ""
    if "Google Play" not in full:
        errs.append("full description lacks the Google Play billing paragraph")
    if app == "bond" and not title.startswith(BRAND):
        errs.append(f"title does not lead with {BRAND!r}")
    note = english_note(loc)
    if not loc.startswith("en") and (note is None or note not in full):
        errs.append("full description does not say the app is in English")
    live = live_listing().get(loc)
    if live:
        pairs = [("title", title), ("shortDescription", (locale_dir / "short_description.txt").read_text(encoding="utf-8")), ("fullDescription", full)]
        for key, text in pairs:
            if live[key].strip() != text.strip():
                errs.append(f"{key} differs from the live listing")
    return errs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", choices=["bond"], default="bond")
    ap.add_argument("--root", type=Path, default=ROOT)
    args = ap.parse_args()
    bad = 0
    dirs = sorted(d for d in args.root.iterdir() if d.is_dir())
    expected = 50
    for d in dirs:
        errs = check(d, args.app)
        t = (d / "title.txt").read_text(encoding="utf-8").strip() if (d / "title.txt").exists() else ""
        s = (d / "short_description.txt").read_text(encoding="utf-8").strip() if (d / "short_description.txt").exists() else ""
        f = (d / "full_description.txt").read_text(encoding="utf-8").strip() if (d / "full_description.txt").exists() else ""
        status = "OK " if not errs else "BAD"
        print(f"{status} {d.name:7} t{len(t):>3} s{len(s):>3} f{len(f):>5}  {t}")
        for e in errs:
            print(f"      - {e}")
        bad += bool(errs)
    print(f"\n{len(dirs)} locales, {bad} with problems")
    if len(dirs) != expected:
        print(f"expected {expected} locales")
        return 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
