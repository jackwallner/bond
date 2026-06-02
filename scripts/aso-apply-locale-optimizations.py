#!/usr/bin/env python3
"""Apply optimized Bond ASO metadata for all fastlane locales (go pipeline).

Dedupes keywords against name + subtitle (Apple indexes all three).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"

# ≤30 chars — brand-first love-language positioning
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
    "bn-BD": "Bond: Love Language Reminders",
    "gu-IN": "Bond: Love Language Reminders",
    "kn-IN": "Bond: Love Language Reminders",
    "ml-IN": "Bond: Love Language Reminders",
    "mr-IN": "Bond: Love Language Reminders",
    "or-IN": "Bond: Love Language Reminders",
    "pa-IN": "Bond: Love Language Reminders",
    "ta-IN": "Bond: Love Language Reminders",
    "te-IN": "Bond: Love Language Reminders",
    "ur-PK": "Bond: Love Language Reminders",
    "sl-SI": "Bond: Jeziki ljubezni",
}

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
    "bn-BD": "Couples · Watch · Anniversary",
    "gu-IN": "Couples · Watch · Anniversary",
    "kn-IN": "Couples · Watch · Anniversary",
    "ml-IN": "Couples · Watch · Anniversary",
    "mr-IN": "Couples · Watch · Anniversary",
    "or-IN": "Couples · Watch · Anniversary",
    "pa-IN": "Couples · Watch · Anniversary",
    "ta-IN": "Couples · Watch · Anniversary",
    "te-IN": "Couples · Watch · Anniversary",
    "ur-PK": "Couples · Watch · Anniversary",
    "sl-SI": "Par · Watch · Obletnica",
}

# Omit terms in name/subtitle (bond, love, language, reminders, couples, watch, anniversary, etc.)
KEYWORDS: dict[str, str] = {
    "en-US": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin,marriage,cupla,between",
    "en-GB": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin,marriage,cupla,between",
    "en-AU": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin,marriage,cupla,between",
    "en-CA": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin,marriage,cupla,between",
    "de-DE": "beziehung,tracker,partner,widget,ehepartner,fernbeziehung,meilenstein,erinnerung,zähler,gepaart,pärchen,ehe,checkin",
    "fr-FR": "relation,tracker,partenaire,widget,conjoint,distance,jalon,rappel,compteur,paired,couple,mariage,checkin",
    "fr-CA": "relation,tracker,partenaire,widget,conjoint,distance,jalon,rappel,compteur,paired,couple,mariage,checkin",
    "es-ES": "relación,tracker,pareja,widget,cónyuge,distancia,hito,recordatorio,contador,paired,checkin,matrimonio",
    "es-MX": "relación,tracker,pareja,widget,cónyuge,distancia,hito,recordatorio,contador,paired,checkin,matrimonio",
    "ca": "relació,tracker,parella,widget,cònjuge,distància,fita,recordatori,comptador,paired,checkin",
    "it": "relazione,tracker,partner,widget,coniuge,distanza,pietra,promemoria,contatore,paired,coppia,checkin",
    "pt-BR": "relacionamento,tracker,parceiro,widget,cônjuge,distância,marco,lembrete,contador,paired,casal,checkin",
    "pt-PT": "relacionamento,tracker,parceiro,widget,cônjuge,distância,marco,lembrete,contador,paired,casal,checkin",
    "nl-NL": "relatie,tracker,partner,widget,echtgenoot,afstand,mijlpaal,herinnering,teller,paired,stel,checkin",
    "pl": "związek,tracker,partner,widget,małżonek,dystans,kamień,przypomnienie,licznik,paired,para,checkin",
    "sv": "relation,tracker,partner,widget,maka,avstånd,milstolpe,påminnelse,räknare,paired,par,checkin",
    "da": "forhold,tracker,partner,widget,ægtefælle,afstand,milepæl,påmindelse,tæller,paired,par,checkin",
    "no": "forhold,tracker,partner,widget,ektefelle,avstand,milepæl,påminnelse,teller,paired,par,checkin",
    "fi": "suhde,tracker,kumppani,widget,puoliso,etäisyys,virstanpylväs,muistutus,laskuri,paired,pariskunta",
    "cs": "vztah,tracker,partner,widget,manžel,vzdálenost,milník,připomínka,počítadlo,paired,pár,checkin",
    "sk": "vzťah,tracker,partner,widget,manžel,vzdialenosť,míľnik,pripomienka,počítadlo,paired,pár,checkin",
    "hu": "kapcsolat,tracker,partner,widget,házastárs,távolság,mérföldkő,emlékeztető,számláló,paired,pár",
    "ro": "relație,tracker,partener,widget,soț,distanță,reper,reminder,contor,paired,cuplu,checkin",
    "hr": "veza,tracker,partner,widget,suprug,udaljenost,prekretnica,podsjetnik,brojač,paired,par",
    "el": "σχέση,tracker,σύντροφος,widget,σύζυγος,απόσταση,ορόσημο,υπενθύμιση,μετρητής,paired,ζευγάρι",
    "tr": "ilişki,tracker,partner,widget,eş,mesafe,dönüm,noktası,hatırlatıcı,sayaç,paired,çift,checkin",
    "ru": "отношения,tracker,партнёр,widget,супруг,расстояние,веха,напоминание,счётчик,paired,пара",
    "uk": "стосунки,tracker,партнер,widget,подружжя,відстань,віха,нагадування,лічильник,paired,пара",
    "ja": "関係,tracker,パートナー,widget,配偶者,遠距離,マイルストーン,リマインダー,カウンター,paired,カップル,チェックイン",
    "ko": "관계,tracker,파트너,widget,배우자,장거리,마일스톤,알림,카운터,paired,커플,체크인",
    "zh-Hans": "关系,tracker,伴侣,widget,配偶,异地,里程碑,提醒,计数器,paired,情侣,签到",
    "zh-Hant": "關係,tracker,伴侶,widget,配偶,遠距,里程碑,提醒,計數器,paired,情侶,簽到",
    "ar-SA": "علاقة,tracker,شريك,widget,زوج,مسافة,معلم,تذكير,عداد,paired,أزواج,تسجيل",
    "he": "מערכת,tracker,בן,זוג,widget,בן,זוג,מרחק,אבן,תזכורת,מונה,paired,זוגות",
    "hi": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin,marriage",
    "th": "ความสัมพันธ์,tracker,คู่,widget,คู่สมรส,ระยะทาง,หมุด,เตือน,นับ,paired,คู่รัก,เช็คอิน",
    "vi": "mối,quan,hệ,tracker,đối,tác,widget,vợ,chồng,khoảng,cách,cột,mốc,nhắc,đếm,paired,cặp,đôi",
    "id": "hubungan,tracker,pasangan,widget,pasangan,jarak,tonggak,pengingat,penghitung,paired,checkin",
    "ms": "hubungan,tracker,pasangan,widget,pasangan,jarak,tonggak,peringatan,pembilang,paired,checkin",
    "bn-BD": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin",
    "gu-IN": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin",
    "kn-IN": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin",
    "ml-IN": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin",
    "mr-IN": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin",
    "or-IN": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin",
    "pa-IN": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin",
    "ta-IN": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin",
    "te-IN": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin",
    "ur-PK": "relationship,tracker,partner,widget,spouse,distance,milestone,nudge,counter,paired,checkin",
    "sl-SI": "razmerje,tracker,partner,widget,zakonec,razdalja,mejnik,opomnik,števec,paired,par",
}

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

Privacy-first — Sign in with Apple, no ads, no third-party analytics.
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
• Apple Watch & Widgets
• Bond+ — tägliche Check-ins, Insights, smarte Orts-Erinnerungen, Vorlagen

Warum Bond? Schmaler als Social-Feed-Apps: Liebessprachen leben, Meilensteine feiern, einmal täglich einchecken.

Kostenlos starten. Bond+ für das volle Erlebnis. Datenschutz zuerst — Sign in with Apple, keine Werbung.""",
    "fr-FR": """Restez intentionnels dans votre couple avec Bond — rappels des langages de l'amour, jalons partagés et check-ins quotidiens sur iPhone et Apple Watch.

• Rappels par langage d'amour — actes, mots, temps, cadeaux, toucher
• Jalons et compte à rebours anniversaire sur Watch et widget
• Associez votre partenaire pour synchroniser les rappels
• Complications Apple Watch et widgets
• Bond+ — check-ins, insights, rappels intelligents, modèles

Gratuit pour commencer. Bond+ pour l'expérience complète. Confidentialité — Sign in with Apple, sans pub.""",
    "es-ES": """Cuidad vuestra relación con Bond — recordatorios de lenguajes del amor, hitos compartidos y check-ins diarios en iPhone y Apple Watch.

• Recordatorios por lenguaje del amor
• Hitos y cuenta atrás de aniversario en Watch y widget
• Emparejad con vuestra pareja
• Complicaciones y widgets de Apple Watch
• Bond+ — check-ins, insights, recordatorios inteligentes

Gratis para empezar. Bond+ para la experiencia completa. Privacidad — Sign in with Apple.""",
    "ja": """Bondでカップルの「愛の言語」を習慣に。リマインダー、共有マイルストーン、Apple Watch対応のデイリーチェックイン。

• 5つの愛の言語でリマインダー
• 記念日カウントダウンとウィジェット
• パートナーとペアリングして同期
• Apple Watch対応
• Bond+ — チェックイン、インサイト、スマートリマインダー

無料で始められます。Bond+で全機能。Sign in with Apple、広告なし。""",
    "zh-Hans": """用 Bond 让爱的五种语言成为习惯——情侣提醒、共享里程碑、Apple Watch 每日签到。

• 五种爱的语言提醒
• 纪念日倒计时与小组件
• 与伴侣配对同步
• Apple Watch 表盘与小组件
• Bond+ — 每日签到、洞察、智能提醒

免费开始，Bond+ 解锁完整体验。Sign in with Apple，无广告。""",
}


def indexed_terms(name: str, subtitle: str) -> set[str]:
    text = f"{name} {subtitle}".lower()
    terms: set[str] = set()
    for w in re.findall(r"[a-z0-9\u0080-\uffff]+", text, flags=re.I):
        if len(w) >= 2:
            terms.add(w)
    return terms


def dedupe_keywords(name: str, subtitle: str, keywords_csv: str) -> str:
    indexed = indexed_terms(name, subtitle)
    kept: list[str] = []
    for raw in keywords_csv.replace(" ", "").split(","):
        kw = raw.strip().lower()
        if not kw:
            continue
        if kw in indexed:
            continue
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
            "keywords": {"old": old_kw, "new": new_kw, "len": len(new_kw)},
            "subtitle": {"old": old_sub, "new": new_sub, "len": len(new_sub)},
            "description": {"old_len": len(old_desc), "new_len": len(new_desc)},
        }
    out = ROOT / "scripts" / "aso-locale-optimization-report.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"Updated {len(report)} locales → {out}")


if __name__ == "__main__":
    main()
