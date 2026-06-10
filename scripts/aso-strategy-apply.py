#!/usr/bin/env python3
"""Apply optimized ASO strategy for Bond based on pop/diff research.

Strategy:
- Title: "Bond: Love Language Reminders" (29) — KEEP. Indexes "love language" + "reminders".
- Subtitle: "Couples · Watch · Anniversary" (29) — KEEP. Indexes "couples" + "watch" + "anniversary".
- Keywords: Optimized single tokens with best pop/diff ratio for an indie app.
  Removed low-value terms (cupla, between, counter, nudge).
  Added high-opportunity terms (lovemo pop=42/diff=19, inlove pop=39/diff=45).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"

# =============================================================================
# US KEYWORD STRATEGY
# =============================================================================
# Title indexes: bond, love, language, reminders
# Subtitle indexes: couples, watch, anniversary
# Keywords must NOT repeat any of those.

# Pop/diff analysis from competitor research:
#   lovemo         pop=42  diff=19  ratio=2.21  ← EXTREMELY winnable (indie sweet spot)
#   love messages  pop=43  diff=37  ratio=1.16  ← Very winnable
#   love letter    pop=24  diff=23  ratio=1.04  ← Winnable
#   love spouse    pop=50  diff=58  ratio=0.86  ← Good opportunity
#   inlove         pop=39  diff=45  ratio=0.87  ← Good opportunity
#   paired         pop=58  diff=62  ratio=0.94  ← Competitor name, good traffic
#   relationship   pop=33  diff=70  ratio=0.47  ← Core need, high diff but essential
#   anniversary tracker pop=33 diff=60 ratio=0.55 ← Niche, winnable

# Keywords field (100 chars max, comma-separated):
# relationship(12),tracker(7),partner(7),widget(6),spouse(6),milestone(9),
# paired(6),marriage(8),checkin(7),lovemo(6),inlove(6),distance(8)
# = 88 + 11 commas = 99 chars
US_KEYWORDS = "relationship,tracker,partner,widget,spouse,milestone,paired,marriage,checkin,lovemo,inlove,distance"

# Tracked phrases for Astro (monitoring, not the ASC keywords field)
TRACKED_PHRASES = [
    "couples app", "love language", "relationship app", "relationship reminder",
    "anniversary tracker", "partner app", "love language app", "couples widget",
    "long distance relationship", "couple check in", "paired app couples",
    "love spouse", "lovemo", "inlove", "apple watch couples",
    "love counter relationship", "marriage reminder", "date night reminder",
    "milestone", "words of affirmation", "acts of service",
    "quality time", "physical touch", "receiving gifts",
    "free couples app", "husband wife app", "love letter",
    "couples questions", "couple tracker", "love tracker",
]

# =============================================================================
# NAMES (≤30 chars)
# =============================================================================
NAMES: dict[str, str] = {
    "en-US": "Bond: Love Language Reminders",
    "en-GB": "Bond: Love Language Reminders",
    "en-AU": "Bond: Love Language Reminders",
    "en-CA": "Bond: Love Language Reminders",
    "de-DE": "Bond: Liebessprachen-Tipps",
    "fr-FR": "Bond: Langages de l'amour",
    "fr-CA": "Bond: Langages de l'amour",
    "es-ES": "Bond: Lenguajes del amor",
    "es-MX": "Bond: Lenguajes del amor",
    "ca": "Bond: Llenguatges de l'amor",
    "it": "Bond: Linguaggi dell'amore",
    "pt-BR": "Bond: Linguagens do amor",
    "pt-PT": "Bond: Linguagens do amor",
    "nl-NL": "Bond: Love Language Reminders",
    "pl": "Bond: Języki miłości",
    "sv": "Bond: Kärleksspråk påminn",
    "da": "Bond: Kærlighedssprog tips",
    "no": "Bond: Kjærlighetsspråk tips",
    "fi": "Bond: Rakkauden kielet",
    "cs": "Bond: Jazyky lásky",
    "sk": "Bond: Jazyky lásky",
    "hu": "Bond: Szeretetnyelvek",
    "ro": "Bond: Limbaje ale iubirii",
    "hr": "Bond: Jezici ljubavi",
    "el": "Bond: Γλώσσες αγάπης",
    "tr": "Bond: Sevgi Dilleri",
    "ru": "Bond: Языки любви",
    "uk": "Bond: Мови кохання",
    "ja": "Bond：愛の言語リマインダー",
    "ko": "Bond: 사랑의 언어 알림",
    "zh-Hans": "Bond：爱的五种语言提醒",
    "zh-Hant": "Bond：愛的五種語言提醒",
    "ar-SA": "Bond: لغات الحب",
    "he": "Bond: שפות אהבה",
    "hi": "Bond: Love Language Reminders",
    "th": "Bond: ภาษารัก",
    "vi": "Bond: Ngôn ngữ tình yêu",
    "id": "Bond: Bahasa Cinta",
    "ms": "Bond: Bahasa Kasih Sayang",
}

# =============================================================================
# SUBTITLES (≤30 chars)
# =============================================================================
# "Couples · Watch · Anniversary" — indexes couples, watch, anniversary
# Using · as separator (multi-purpose bullet) — Apple indexes each word
SUBTITLES: dict[str, str] = {
    "en-US": "Couples · Watch · Anniversary",
    "en-GB": "Couples · Watch · Anniversary",
    "en-AU": "Couples · Watch · Anniversary",
    "en-CA": "Couples · Watch · Anniversary",
    "de-DE": "Paar · Watch · Jahrestag",
    "fr-FR": "Couples · Montre · Anniversaire",
    "fr-CA": "Couples · Montre · Anniversaire",
    "es-ES": "Pareja · Watch · Aniversario",
    "es-MX": "Pareja · Watch · Aniversario",
    "ca": "Parella · Watch · Aniversari",
    "it": "Coppia · Watch · Anniversario",
    "pt-BR": "Casal · Watch · Aniversário",
    "pt-PT": "Casal · Watch · Aniversário",
    "nl-NL": "Koppel · Watch · Jubileum",
    "pl": "Para · Watch · Rocznica",
    "sv": "Par · Watch · Årsdag",
    "da": "Par · Watch · Jubilæum",
    "no": "Par · Watch · Jubileum",
    "fi": "Pariskunta · Watch · Vuosi",
    "cs": "Pár · Watch · Výročí",
    "sk": "Pár · Watch · Výročie",
    "hu": "Pár · Watch · Évforduló",
    "ro": "Cuplu · Watch · Aniversar",
    "hr": "Par · Watch · Godišnjica",
    "el": "Ζευγάρι · Watch · Επέτειος",
    "tr": "Çift · Watch · Yıldönümü",
    "ru": "Пара · Watch · Годовщина",
    "uk": "Пара · Watch · Річниця",
    "ja": "カップル · Watch · 記念日",
    "ko": "커플 · Watch · 기념일",
    "zh-Hans": "情侣 · Watch · 纪念日",
    "zh-Hant": "情侶 · Watch · 紀念日",
    "ar-SA": "أزواج · Watch · ذكرى",
    "he": "זוגות · Watch · יום שנה",
    "hi": "Couples · Watch · Anniversary",
    "th": "คู่รัก · Watch · ครบรอบ",
    "vi": "Cặp đôi · Watch · Kỷ niệm",
    "id": "Pasangan · Watch · Ulang tahun",
    "ms": "Pasangan · Watch · Ulang tahun",
}

# =============================================================================
# KEYWORDS (≤100 chars, comma-separated, no spaces, no name/subtitle repeats)
# =============================================================================
KEYWORDS: dict[str, str] = {}

# English locales — optimized US keyword list
for loc in ["en-US", "en-GB", "en-AU", "en-CA", "hi", "bn-BD", "gu-IN", "kn-IN",
            "ml-IN", "mr-IN", "or-IN", "pa-IN", "ta-IN", "te-IN", "ur-PK"]:
    KEYWORDS[loc] = US_KEYWORDS

# German
KEYWORDS["de-DE"] = "beziehung,tracker,partner,widget,ehepartner,fernbeziehung,meilenstein,erinnerung,zähler,gepaart,pärchen,ehe"
# French
KEYWORDS["fr-FR"] = "relation,tracker,partenaire,widget,conjoint,distance,jalon,rappel,compteur,paired,couple,mariage"
KEYWORDS["fr-CA"] = "relation,tracker,partenaire,widget,conjoint,distance,jalon,rappel,compteur,paired,couple,mariage"
# Spanish
for loc in ["es-ES", "es-MX"]:
    KEYWORDS[loc] = "relación,tracker,pareja,widget,cónyuge,distancia,hito,recordatorio,contador,paired,matrimonio"
# Catalan
KEYWORDS["ca"] = "relació,tracker,parella,widget,cònjuge,distància,fita,recordatori,comptador,paired"
# Italian
KEYWORDS["it"] = "relazione,tracker,partner,widget,coniuge,distanza,pietra,promemoria,contatore,paired,coppia"
# Portuguese
for loc in ["pt-BR", "pt-PT"]:
    KEYWORDS[loc] = "relacionamento,tracker,parceiro,widget,cônjuge,distância,marco,lembrete,contador,paired,casal"
# Dutch
KEYWORDS["nl-NL"] = "relatie,tracker,partner,widget,echtgenoot,afstand,mijlpaal,herinnering,teller,paired,stel"
# Polish
KEYWORDS["pl"] = "związek,tracker,partner,widget,małżonek,dystans,kamień,przypomnienie,licznik,paired,para"
# Swedish
KEYWORDS["sv"] = "relation,tracker,partner,widget,maka,avstånd,milstolpe,påminnelse,räknare,paired,par"
# Danish
KEYWORDS["da"] = "forhold,tracker,partner,widget,ægtefælle,afstand,milepæl,påmindelse,tæller,paired,par"
# Norwegian
KEYWORDS["no"] = "forhold,tracker,partner,widget,ektefelle,avstand,milepæl,påminnelse,teller,paired,par"
# Finnish
KEYWORDS["fi"] = "suhde,tracker,kumppani,widget,puoliso,etäisyys,virstanpylväs,muistutus,laskuri,paired,pariskunta"
# Czech
KEYWORDS["cs"] = "vztah,tracker,partner,widget,manžel,vzdálenost,milník,připomínka,počítadlo,paired,pár"
# Slovak
KEYWORDS["sk"] = "vzťah,tracker,partner,widget,manžel,vzdialenosť,míľnik,pripomienka,počítadlo,paired,pár"
# Hungarian
KEYWORDS["hu"] = "kapcsolat,tracker,partner,widget,házastárs,távolság,mérföldkő,emlékeztető,számláló,paired,pár"
# Romanian
KEYWORDS["ro"] = "relație,tracker,partener,widget,soț,distanță,reper,reminder,contor,paired,cuplu"
# Croatian
KEYWORDS["hr"] = "veza,tracker,partner,widget,suprug,udaljenost,prekretnica,podsjetnik,brojač,paired,par"
# Greek
KEYWORDS["el"] = "σχέση,tracker,σύντροφος,widget,σύζυγος,απόσταση,ορόσημο,υπενθύμιση,μετρητής,paired,ζευγάρι"
# Turkish
KEYWORDS["tr"] = "ilişki,tracker,partner,widget,eş,mesafe,dönüm,noktası,hatırlatıcı,sayaç,paired,çift"
# Russian
KEYWORDS["ru"] = "отношения,tracker,партнёр,widget,супруг,расстояние,веха,напоминание,счётчик,paired,пара"
# Ukrainian
KEYWORDS["uk"] = "стосунки,tracker,партнер,widget,подружжя,відстань,віха,нагадування,лічильник,paired,пара"
# Japanese
KEYWORDS["ja"] = "関係,tracker,パートナー,widget,配偶者,遠距離,マイルストーン,リマインダー,カウンター,paired,カップル"
# Korean
KEYWORDS["ko"] = "관계,tracker,파트너,widget,배우자,장거리,마일스톤,알림,카운터,paired,커플"
# Chinese
for loc in ["zh-Hans", "zh-Hant"]:
    KEYWORDS[loc] = "关系,tracker,伴侣,widget,配偶,异地,里程碑,提醒,计数器,paired,情侣"
# Arabic
KEYWORDS["ar-SA"] = "علاقة,tracker,شريك,widget,زوج,مسافة,معلم,تذكير,عداد,paired,أزواج"
# Hebrew
KEYWORDS["he"] = "מערכת,tracker,בן,זוג,widget,בן,זוג,מרחק,אבן,תזכורת,מונה,paired,זוגות"
# Thai
KEYWORDS["th"] = "ความสัมพันธ์,tracker,คู่,widget,คู่สมรส,ระยะทาง,หมุด,เตือน,นับ,paired,คู่รัก"
# Vietnamese
KEYWORDS["vi"] = "mối,quan,hệ,tracker,đối,tác,widget,vợ,chồng,khoảng,cách,cột,mốc,nhắc,đếm,paired,cặp,đôi"
# Indonesian
KEYWORDS["id"] = "hubungan,tracker,pasangan,widget,pasangan,jarak,tonggak,pengingat,penghitung,paired"
# Malay
KEYWORDS["ms"] = "hubungan,tracker,pasangan,widget,pasangan,jarak,tonggak,peringatan,pembilang,paired"
# Slovenian
KEYWORDS["sl-SI"] = "razmerje,tracker,partner,widget,zakonec,razdalja,mejnik,opomnik,števec,paired,par"

# =============================================================================
# DESCRIPTIONS
# =============================================================================
DESCRIPTION_EN = """Stay intentional in your relationship with Bond — love-language reminders, shared milestones, and daily check-ins for couples on iPhone and Apple Watch.

WHAT YOU GET
• Love-language reminders — tag acts of service, words of affirmation, quality time, gifts, and touch
• Shared milestones and anniversary countdown on your wrist and home screen
• Pair with your partner to sync reminders and celebrate wins together
• Apple Watch complications and widgets — see what's next at a glance
• Bond+ — daily check-ins, insights, smart location reminders, and template packs

WHY BOND
Most couples apps feel like another social feed. Bond is narrower: help two people remember to act on love languages, celebrate milestones, and check in once a day.

Free to start. Bond+ when you want the full experience.

Privacy-first — Sign in with Apple, no ads, no data sold.
"""

DESCRIPTIONS: dict[str, str] = {
    "en-US": DESCRIPTION_EN,
    "en-GB": DESCRIPTION_EN,
    "en-AU": DESCRIPTION_EN,
    "en-CA": DESCRIPTION_EN,
    "de-DE": """Bleibt bewusst füreinander da — mit Bond: Erinnerungen in den Liebessprachen, gemeinsame Meilensteine und Check-ins für Paare auf iPhone und Apple Watch.

WAS IHR BEKOMMT
• Erinnerungen nach den 5 Liebessprachen — Taten, Worte, Zeit, Geschenke, Berührung
• Gemeinsame Meilensteine und Jahrestags-Countdown auf Watch und Widget
• Partner verbinden und Erinnerungen teilen
• Apple Watch Komplikationen und Widgets — ein Blick genügt
• Bond+ — tägliche Check-ins, Insights, smarte Orts-Erinnerungen, Vorlagen

WARUM BOND?
Die meisten Apps für Paare fühlen sich wie ein weiterer Social Feed an. Bond ist schmaler: zwei Menschen dabei helfen, Liebessprachen zu leben, Meilensteine zu feiern und einmal täglich innezuhalten.

Kostenlos starten. Bond+ für das volle Erlebnis.

Datenschutz zuerst — Sign in with Apple, keine Werbung.""",
    "fr-FR": """Restez intentionnels dans votre couple avec Bond — rappels des langages de l'amour, jalons partagés et check-ins quotidiens sur iPhone et Apple Watch.

CE QUE VOUS OBTENEZ
• Rappels par langage d'amour — actes, paroles, temps, cadeaux, toucher
• Jalons partagés et compte à rebours d'anniversaire sur Apple Watch et widget
• Associez votre partenaire pour synchroniser les rappels
• Complications Apple Watch et widgets — tout voir d'un coup d'œil
• Bond+ — check-ins, insights, rappels intelligents

POURQUOI BOND ?
La plupart des apps de couple ressemblent à un fil social. Bond est plus précis : aider deux personnes à vivre leurs langages d'amour, célébrer les jalons et faire un check-in par jour.

Gratuit. Bond+ pour l'expérience complète.

Confidentialité — Sign in with Apple, pas de pub.""",
    "es-ES": """Cuidad vuestra relación con Bond — recordatorios de lenguajes del amor, hitos compartidos y check-ins diarios en iPhone y Apple Watch.

LO QUE OBTIENES
• Recordatorios por lenguaje del amor — actos, palabras, tiempo, regalos, tacto
• Hitos compartidos y cuenta atrás de aniversario en Watch y widget
• Empareja con tu pareja para sincronizar
• Complicaciones y widgets de Apple Watch
• Bond+ — check-ins, insights, recordatorios inteligentes

GRATIS PARA EMPEZAR. Bond+ para la experiencia completa.

Privacidad primero — Sign in with Apple, sin anuncios.""",
    "ja": """Bondでカップルの「愛の言語」を習慣に。リマインダー、共有マイルストーン、Apple Watch対応のデイリーチェックイン。

• 5つの愛の言語でリマインダー
• 記念日カウントダウンとホーム画面ウィジェット
• パートナーとペアリングして同期
• Apple Watch コンプリケーションとウィジェット
• Bond+ — チェックイン、インサイト、スマートリマインダー

無料で始められます。Bond+で全機能。Sign in with Apple、広告なし。""",
    "zh-Hans": """用 Bond 让爱的五种语言成为习惯——情侣提醒、共享里程碑、Apple Watch 每日签到。

• 五种爱的语言提醒
• 纪念日倒计时与桌面小组件
• 与伴侣配对同步
• Apple Watch 表盘与小组件
• Bond+ — 每日签到、洞察、智能提醒

免费开始，Bond+ 解锁完整体验。Sign in with Apple，无广告。""",
}


# =============================================================================
# HELPERS
# =============================================================================
def indexed_terms(name: str, subtitle: str) -> set[str]:
    """Return set of individual words from name and subtitle (Apple indexes all three)."""
    text = f"{name} {subtitle}".lower()
    terms: set[str] = set()
    for w in re.findall(r"[a-z0-9\u0080-\uffff]+", text, flags=re.I):
        if len(w) >= 2:
            terms.add(w)
    return terms


def dedupe_keywords(name: str, subtitle: str, keywords_csv: str) -> str:
    """Remove keywords that repeat words already in name or subtitle."""
    indexed = indexed_terms(name, subtitle)
    kept: list[str] = []
    for raw in keywords_csv.replace(" ", "").split(","):
        kw = raw.strip().lower()
        if not kw:
            continue
        if kw in indexed:
            continue
        # Also check substring overlap for 4+ char words
        if any(kw == t or (len(kw) >= 4 and kw in t) or (len(t) >= 4 and t in kw) for t in indexed):
            continue
        kept.append(kw)
    return ",".join(kept)


def trim_keywords(s: str, limit: int = 100) -> str:
    s = s.replace(" ", "")
    if len(s) <= limit:
        return s
    parts = s.split(",")
    while parts and len(",".join(parts)) > limit:
        parts.pop()
    return ",".join(parts)


def trim_field(s: str, limit: int) -> str:
    return s[:limit] if len(s) > limit else s


def main() -> None:
    report: dict[str, dict] = {}
    for loc_dir in sorted(META.iterdir()):
        if not loc_dir.is_dir() or loc_dir.name == "review_information":
            continue
        loc = loc_dir.name
        if loc not in KEYWORDS:
            print(f"Skip {loc} (no keyword mapping)")
            continue

        name_path = loc_dir / "name.txt"
        sub_path = loc_dir / "subtitle.txt"
        kw_path = loc_dir / "keywords.txt"
        desc_path = loc_dir / "description.txt"

        old_name = name_path.read_text(encoding="utf-8").strip() if name_path.exists() else ""
        old_sub = sub_path.read_text(encoding="utf-8").strip() if sub_path.exists() else ""
        old_kw = kw_path.read_text(encoding="utf-8").strip() if kw_path.exists() else ""
        old_desc = desc_path.read_text(encoding="utf-8").strip() if desc_path.exists() else ""

        new_name = trim_field(NAMES.get(loc, NAMES["en-US"]), 30)
        new_sub = trim_field(SUBTITLES.get(loc, SUBTITLES["en-US"]), 30)
        raw_kw = KEYWORDS[loc]
        new_kw = trim_keywords(dedupe_keywords(new_name, new_sub, raw_kw))
        new_desc = DESCRIPTIONS.get(loc, DESCRIPTION_EN)

        name_path.write_text(new_name + "\n", encoding="utf-8")
        sub_path.write_text(new_sub + "\n", encoding="utf-8")
        kw_path.write_text(new_kw + "\n", encoding="utf-8")
        desc_path.write_text(new_desc + "\n", encoding="utf-8")

        report[loc] = {
            "name": {"old": old_name, "new": new_name, "len": len(new_name)},
            "subtitle": {"old": old_sub, "new": new_sub, "len": len(new_sub)},
            "keywords": {"old": old_kw, "new": new_kw, "len": len(new_kw)},
            "description": {"old_len": len(old_desc), "new_len": len(new_desc)},
        }

    out = ROOT / "scripts" / "aso-locale-optimization-report.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")

    # Verify all char limits
    errors = []
    for loc, data in report.items():
        if data["name"]["len"] > 30:
            errors.append(f"{loc}/name: {data['name']['len']} > 30")
        if data["subtitle"]["len"] > 30:
            errors.append(f"{loc}/subtitle: {data['subtitle']['len']} > 30")
        if data["keywords"]["len"] > 100:
            errors.append(f"{loc}/keywords: {data['keywords']['len']} > 100")

    if errors:
        print("\nCHAR LIMIT ERRORS:")
        for e in errors:
            print(f"  {e}")
    else:
        print("\nAll char limits OK ✓")

    print(f"\nUpdated {len(report)} locales → {out}")

    # Print US summary
    us = report.get("en-US", {})
    print(f"\n=== US SUMMARY ===")
    print(f"Name: {us.get('name', {}).get('new','')} ({us.get('name', {}).get('len',0)} chars)")
    print(f"Subtitle: {us.get('subtitle', {}).get('new','')} ({us.get('subtitle', {}).get('len',0)} chars)")
    print(f"Keywords: {us.get('keywords', {}).get('new','')} ({us.get('keywords', {}).get('len',0)} chars)")


if __name__ == "__main__":
    main()
