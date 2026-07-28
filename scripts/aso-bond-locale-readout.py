#!/usr/bin/env python3
"""Generate full Bond ASC locale readout: title/subtitle/keywords + Astro rationale."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASTRO = Path("/tmp/aso_en_pop_bond_full.json")
if not ASTRO.exists():
    ASTRO = Path("/tmp/aso_en_keyword_pop_checkpoint.json")

LOCALE_TO_STORE = {
    "ar-SA": "sa", "bn-BD": "in", "ca": "es", "cs": "cz", "da": "dk",
    "de-DE": "de", "el": "gr", "en-AU": "au", "en-CA": "ca", "en-GB": "gb",
    "en-US": "us", "es-ES": "es", "es-MX": "mx", "fi": "fi", "fr-CA": "ca",
    "fr-FR": "fr", "gu-IN": "in", "he": "il", "hi": "in", "hr": "hr",
    "hu": "hu", "id": "id", "it": "it", "ja": "jp", "kn-IN": "in", "ko": "kr",
    "ml-IN": "in", "mr-IN": "in", "ms": "my", "nl-NL": "nl", "no": "no",
    "or-IN": "in", "pa-IN": "in", "pl": "pl", "pt-BR": "br", "pt-PT": "pt",
    "ro": "ro", "ru": "ru", "sk": "sk", "sl-SI": "si", "sv": "se",
    "ta-IN": "in", "te-IN": "in", "th": "th", "tr": "tr", "uk": "ua",
    "ur-PK": "sa", "vi": "vn", "zh-Hans": "cn", "zh-Hant": "tw",
}

# Astro store when locale store missing from /tmp/aso_en_pop_bond_full.json
ASTRO_STORE_FALLBACK: dict[str, str] = {"si": "hr"}

# Bond-relevant EN seeds we may inject (never relationship/partner/love language abroad)
EN_CANDIDATES = [
    "countdown", "tracker", "couple", "reminder", "notes", "together", "paired",
    "date", "messages", "girlfriend", "watch", "gift",
    "widget", "calendar", "timer",  # generic high-pop fillers when Bond terms thin
]

# Extra native tail per locale when pool still under 94 chars after EN injection
EXTRA_NATIVE: dict[str, list[str]] = {
    "he": ["זוג", "אהבה", "יומולדת", "זיכרון", "בעל", "אישה", "חבר", "חברה", "זוגיות", "מחברת", "לוח", "שעון"],
    "ko": ["기념일", "알림", "질문", "메모", "캘린더", "위젯", "타이머", "기념", "사랑", "부부", "연애", "남자친구", "여자친구"],
    "ja": ["記念日", "リマインダー", "質問", "メモ", "カレンダー", "ウィジェット", "タイマー", "愛", "恋人", "夫", "妻", "彼氏", "彼女", "プレゼント"],
    "zh-Hans": ["周年", "提醒", "问题", "备忘", "日历", "小组件", "计时", "恋爱", "夫妻", "男友", "女友", "礼物", "配对", "一起"],
    "zh-Hant": ["週年", "提醒", "問題", "備忘", "日曆", "小組件", "計時", "戀愛", "夫妻", "男友", "女友", "禮物", "配對", "一起"],
    "tr": ["sevgili", "eş", "hatırlatma", "soru", "hediye", "takvim", "widget", "zamanlayıcı", "birlikte", "nişanlı"],
    "el": ["αγάπη", "ζευγάρι", "σύζυγος", "ημερολόγιο", "widget", "χρονόμετρο", "μαζί", "αρραβωνιαστικός"],
    "gu-IN": ["પ્રેમ", "યાદ", "કેલેન્ડર", "વિજેટ", "સાથે", "પ્રેમિકા"],
    "mr-IN": ["प्रेम", "स्मरण", "कॅलेंडर", "विजेट", "सोबत", "प्रिय"],
    "pa-IN": ["ਪਿਆਰ", "ਯਾਦ", "ਕੈਲੰਡਰ", "ਵਿਜੇਟ", "ਨਾਲ", "ਪ੍ਰੇਮਿਕਾ"],
    "sk": ["láska", "pripomienka", "kalendár", "widget", "spolu", "priateľka"],
}

# Native pools per locale (base keywords before EN + packing)
LOCALES: dict[str, dict[str, str]] = {
    "en-US": {"name": "Bond: Love Language Reminders", "subtitle": "Couple Counter · Anniversary",
              "native_kw": "relationship,tracker,countdown,long,distance,messages,notes,date,partner,questions,marriage,paired,gifts,boyfriend,girlfriend,watch,reminder,widget"},
    "en-AU": {"name": "Bond: Love Language Reminders", "subtitle": "Couple Counter · Anniversary",
              "native_kw": "relationship,tracker,countdown,long,distance,messages,notes,date,partner,questions,marriage,paired,gifts,boyfriend,girlfriend,watch,reminder,widget"},
    "en-CA": {"name": "Bond: Love Language Reminders", "subtitle": "Couple Counter · Anniversary",
              "native_kw": "relationship,tracker,countdown,long,distance,messages,notes,date,partner,questions,marriage,paired,gifts,boyfriend,girlfriend,watch,reminder,widget"},
    "en-GB": {"name": "Bond: Love Language Reminders", "subtitle": "Couple Counter · Anniversary",
              "native_kw": "relationship,tracker,countdown,long,distance,messages,notes,date,partner,questions,marriage,paired,gifts,boyfriend,girlfriend,watch,reminder,widget"},
    "es-ES": {"name": "Lenguajes del amor pareja", "subtitle": "Contador pareja · Aniversario",
              "native_kw": "relación,seguimiento,distancia,mensajes,notas,cita,preguntas,matrimonio,cónyuge,regalo,novio,novia,watch"},
    "es-MX": {"name": "Lenguajes del amor pareja", "subtitle": "Pareja · Watch · Aniversario",
              "native_kw": "relación,seguimiento,distancia,mensajes,notas,cita,preguntas,matrimonio,cónyuge,regalo,novio,novia"},
    "de-DE": {"name": "Liebessprachen Erinnerung", "subtitle": "Paar Zähler · Jahrestag · Fern",
              "native_kw": "beziehung,fernbeziehung,nachrichten,notizen,ehepartner,ehe,geschenk,fragen,geliebte"},
    "fr-FR": {"name": "Langages de l'amour couple", "subtitle": "Compteur couple · Anniversaire",
              "native_kw": "relation,suivi,distance,messages,notes,questions,partenaire,conjoint,mariage,cadeau,petite"},
    "fr-CA": {"name": "Langages de l'amour couple", "subtitle": "Compteur couple · Anniversaire",
              "native_kw": "relation,suivi,distance,messages,notes,questions,partenaire,conjoint,mariage,cadeau,petite"},
    "it": {"name": "Linguaggi dell'amore coppia", "subtitle": "Contatore coppia · Anniversario",
           "native_kw": "relazione,distanza,messaggi,note,appuntamento,domande,partner,coniuge,matrimonio,regalo"},
    "nl-NL": {"name": "Liefdestaal herinneringen", "subtitle": "Koppel teller · Jubileum",
              "native_kw": "relatie,afstand,berichten,notities,aftellen,vragen,echtgenoot,huwelijk,cadeau,date"},
    "pt-BR": {"name": "Linguagens do amor casal", "subtitle": "Contador casal · Aniversário",
              "native_kw": "relacionamento,distância,mensagens,notas,encontro,perguntas,parceiro,cônjuge,casamento,presente"},
    "pt-PT": {"name": "Linguagens do amor casal", "subtitle": "Contador casal · Aniversário",
              "native_kw": "relacionamento,distância,mensagens,notas,encontro,perguntas,parceiro,cônjuge,casamento,presente"},
    "ja": {"name": "愛の言語リマインダー・カップル用アプリ遠距離恋愛", "subtitle": "カップル · カウンター · 記念日 · 遠距離恋愛",
           "native_kw": "関係,パートナー,配偶者,遠距離,カウントダウン,メッセージ,メモ,デート,質問,結婚,恋人,夫婦,彼氏,彼女,贈り物,記念,リマインダー,カレンダー,ウィジェット"},
    "ko": {"name": "사랑의 언어 알림 및 커플 카운터 앱 도구용", "subtitle": "커플 · 카운터 · 기념일 · 장거리 연애앱",
           "native_kw": "관계,파트너,배우자,장거리,카운트다운,메시지,메모,데이트,질문,결혼,연인,부부,선물,남친,여친,기념,알림,캘린더,위젯,타이머"},
    "zh-Hans": {"name": "爱的五种语言情侣提醒应用与异地纪念日计数器帮手爱", "subtitle": "情侣异地计数器与纪念日礼物提醒恋爱关系配偶约会问",
                "native_kw": "关系,伴侣,配偶,异地,倒计时,消息,备忘,约会,问题,结婚,恋爱,夫妻,礼物,男友,女友,周年,提醒,日历,小组件,计时,配对"},
    "zh-Hant": {"name": "愛的五種語言情侶提醒應用與遠距紀念日計數器幫手愛", "subtitle": "情侶遠距計數器與紀念日禮物提醒戀愛關係配偶約會問",
                "native_kw": "關係,伴侶,配偶,遠距,倒數計時,訊息,備忘,約會,問題,結婚,戀愛,夫妻,禮物,男友,女友,週年,提醒,日曆,小組件,計時,配對"},
    "hi": {"name": "प्रेम भाषा याददाश्त कपल ऐप", "subtitle": "जोड़ा · काउंटर · सालगिरह · दूरी",
           "native_kw": "संबंध,ट्रैकर,काउंटडाउन,दूरी,संदेश,नोट,डेट,सवाल,विवाह,युगल,प्रेमी,पति,पत्नी,उपहार"},
    "bn-BD": {"name": "ভালোবাসার ভাষা: জোড়া ট্র্যাকার", "subtitle": "দম্পতি · কাউন্টার · বার্ষিকী · দূর",
              "native_kw": "সম্পর্ক,ট্র্যাকার,কাউন্টডাউন,দূরত্ব,বার্তা,নোট,ডেট,প্রশ্ন,বিবাহ,যুগল,প্রেমিক,স্বামী,স্ত্রী,উপহার"},
    "ar-SA": {"name": "لغات الحب والعلاقة للأزواج", "subtitle": "عداد الأزواج · ذكرى سنوية · بعيد",
              "native_kw": "علاقة,شريك,مسافة,تذكير,رسائل,ملاحظات,موعد,أسئلة,بعيدة,تنازلي,هدية,خطيبة,زوج,زوجة,حب,تقويم"},
    "he": {"name": "שפות אהבה וזוגיות לזוגות", "subtitle": "מונה זוגות · יום שנה · מרחק",
           "native_kw": "זוגיות,מרחק,תזכורת,הודעות,הערות,דייט,שאלות,נישואים,ספירה,מתנה,ארוסה,זוג,אהבה,יומולדת,בעל,אישה,חבר,חברה,מחברת,לוח"},
    "ru": {"name": "Языки любви для пары · Пара", "subtitle": "Счётчик пары · Годовщина · Дистанция",
           "native_kw": "отношения,партнёр,супруг,расстояние,напоминание,сообщения,заметки,свидание,вопросы,брак,отсчёт,подарок"},
    "pl": {"name": "Języki miłości para · Para", "subtitle": "Licznik pary · Rocznica · Dystans",
           "native_kw": "związek,partner,małżonek,dystans,przypomnienie,wiadomości,notatki,randka,pytania,prezent"},
    "sv": {"name": "Kärleksspråk påminnelser par", "subtitle": "Par räknare · Årsdag · Kalender",
           "native_kw": "relation,maka,avstånd,nedräkning,meddelanden,dejt,frågor,äktenskap,anteckningar,present"},
    "no": {"name": "Kjærlighetsspråk tips par", "subtitle": "Par teller · Jubileum · Kalender",
           "native_kw": "forhold,partner,ektefelle,avstand,nedtelling,meldinger,notater,date,spørsmål,ekteskap,gave"},
    "da": {"name": "Kærlighedssprog påmindelse", "subtitle": "Par tæller · Jubilæum · Kalender",
           "native_kw": "forhold,partner,ægtefælle,afstand,påmindelse,beskeder,noter,date,spørgsmål,ægteskab,gave"},
    "fi": {"name": "Rakkauden kielet parille", "subtitle": "Pari laskuri · Vuosipäivä",
           "native_kw": "suhde,kumppani,puoliso,etäisyys,muistutus,viestit,treffit,kysymykset,avioliitto,lahja"},
    "tr": {"name": "Sevgi dilleri çift · Hatırlatma", "subtitle": "Çift sayaç · Yıldönümü · Mesafe",
           "native_kw": "ilişki,partner,eş,mesafe,hatırlatıcı,mesajlar,notlar,randevu,sorular,evlilik,hediye,sevgili,hatırlatma,takvim,birlikte,nişanlı"},
    "th": {"name": "ภาษารักสำหรับคู่รัก · คู่", "subtitle": "ตัวนับคู่รัก · ครบรอบ · ระยะทาง",
           "native_kw": "ความสัมพันธ์,คู่สมรส,ระยะทาง,เตือน,ข้อความ,โน้ต,เดท,คำถาม,แต่งงาน,นับถอยหลัง,ของขวัญ"},
    "vi": {"name": "Ngôn ngữ tình yêu đôi · Nhắc", "subtitle": "Bộ đếm đôi · Kỷ niệm · Xa cách",
           "native_kw": "mối quan hệ,đối tác,vợ chồng,khoảng cách,nhắc nhở,tin nhắn,ghi chú,hẹn hò,câu hỏi,hôn nhân,quà"},
    "id": {"name": "Bahasa cinta pasangan · Pasang", "subtitle": "Penghitung pasangan · Ulang tahun",
           "native_kw": "hubungan,pasangan,jarak,pengingat,pesan,catatan,kencan,pertanyaan,pernikahan,hadiah"},
    "ms": {"name": "Bahasa kasih pasangan · Pasang", "subtitle": "Pembilang pasangan · Ulang tahun",
           "native_kw": "hubungan,pasangan,jarak,peringatan,mesej,nota,temujanji,soalan,perkahwinan,hadiah"},
    "uk": {"name": "Мови кохання для пари · Пара", "subtitle": "Лічильник пари · Річниця · Відстань",
           "native_kw": "стосунки,партнер,подружжя,відстань,нагадування,повідомлення,нотатки,побачення,запитання,шлюб,подарунок"},
    "cs": {"name": "Jazyky lásky pár · Připomínky", "subtitle": "Počítadlo páru · Výročí · Dárek",
           "native_kw": "vztah,partner,manžel,vzdálenost,připomínka,zprávy,poznámky,rande,otázky,manželství,dárek"},
    "sk": {"name": "Jazyky lásky pre pár · Pár", "subtitle": "Počítadlo páru · Výročie · Darček",
           "native_kw": "vzťah,partner,manžel,vzdialenosť,pripomienka,správy,poznámky,rande,otázky,manželstvo,darček,láska,kalendár,spolu,priateľka"},
    "sl-SI": {"name": "Jeziki ljubezni par · Par", "subtitle": "Števec para · Obletnica · Darilo",
              "native_kw": "razmerje,partner,zakonec,razdalja,opomnik,sporočila,beležke,zmenek,vprašanja,poroka,darilo,ljubezen,skupaj,prijateljica"},
    "hu": {"name": "Szeretetnyelvek párknak · Pár", "subtitle": "Pár számláló · Évforduló",
           "native_kw": "kapcsolat,partner,házastárs,távolság,emlékeztető,üzenetek,jegyzetek,randi,kérdések,házasság,ajándék"},
    "hr": {"name": "Jezici ljubavi par · Par", "subtitle": "Par brojač · Godišnjica · Dar",
           "native_kw": "veza,partner,suprug,udaljenost,podsjetnik,poruke,bilješke,spoj,pitanja,brak,poklon"},
    "ro": {"name": "Limbaje ale iubirii cuplu", "subtitle": "Contor cuplu · Aniversare",
           "native_kw": "relație,partener,soț,distanță,memento,mesaje,notițe,întâlnire,întrebări,căsătorie,cadou"},
    "el": {"name": "Γλώσσες αγάπης για ζευγάρι", "subtitle": "Μετρητής ζευγαριού · Επέτειος",
           "native_kw": "σχέση,σύντροφος,σύζυγος,απόσταση,υπενθύμιση,μηνύματα,σημειώσεις,ραντεβού,ερωτήσεις,γάμος,δώρο,αγάπη,ζευγάρι,ημερολόγιο,μαζί"},
    "ca": {"name": "Llenguatges de l'amor parella", "subtitle": "Comptador parella · Aniversari",
           "native_kw": "relació,cònjuge,distància,recordatori,missatges,notes,cita,preguntes,matrimoni,parelles,seguiment,regal"},
    "gu-IN": {"name": "પ્રેમ ભાષા યાદદાસ્ત જોડી એપ", "subtitle": "જોડી · કાઉન્ટર · વર્ષગાંઠ · દૂર",
              "native_kw": "સંબંધ,ટ્રેકર,કાઉન્ટડાઉન,દૂર,સંદેશ,નોંધ,ડેટ,પ્રશ્ન,લગ્ન,પ્રેમી,પતિ,પત્ની,ભેટ,પ્રેમ,યાદ,કેલેન્ડર,સાથે,પ્રેમિકા"},
    "kn-IN": {"name": "ಪ್ರೀತಿ ಭಾಷೆ ಜ್ಞಾಪಕ ಜೋಡಿ ಆ್ಯಪ್", "subtitle": "ಜೋಡಿ · ಕೌಂಟರ್ · ವಾರ್ಷಿಕೋ · ದೂರ",
              "native_kw": "ಸಂಬಂಧ,ಟ್ರ್ಯಾಕರ್,ಕೌಂಟ್ಡೌನ್,ದೂರ,ಸಂದೇಶ,ನೋಟ್,ಡೇಟ್,ಪ್ರಶ್ನೆ,ಮದುವೆ,ಪ್ರೇಮಿ,ಗಂಡ,ಹೆಂಡತಿ,ಉಡುಗೊರೆ"},
    "ml-IN": {"name": "സ്നേഹ ഭാഷ ഓർമ്മ ദമ്പതി ആപ്പ്", "subtitle": "ജോഡി · കൗണ്ടർ · വാർഷികം · ദൂരം",
              "native_kw": "ബന്ധം,ട്രാക്കർ,കൗണ്ട്ഡൗൺ,ദൂരം,സന്ദേശം,കുറിപ്പ്,ഡേറ്റ്,ചോദ്യം,വിവാഹം,പ്രേമി,ഭർത്താവ്,ഭാര്യ,സമ്മാനം"},
    "mr-IN": {"name": "प्रेम भाषा आठवण जोडी अॅप", "subtitle": "जोडी · काउंटर · वर्धापन · अंतर",
              "native_kw": "नाते,ट्रॅकर,काउंटडाउन,अंतर,संदेश,नोट,डेट,प्रश्न,लग्न,प्रिय,नवरा,बायको,भेट,प्रेम,स्मरण,कॅलेंडर,सोबत"},
    "or-IN": {"name": "ପ୍ରେମ ଭାଷା ସ୍ମରଣ ଯୋଡ଼ି ଆପ୍", "subtitle": "ଯୋଡ଼ି · କାଉଣ୍ଟର · ବାର୍ଷିକୀ",
              "native_kw": "ସମ୍ପର୍କ,ଟ୍ରାକର,କାଉଣ୍ଟଡାଉନ,ଦୂରତା,ବାର୍ତ୍ତା,ନୋଟ,ଡେଟ,ପ୍ରଶ୍ନ,ବିବାହ,ପ୍ରେମିକ,ସ୍ଵାମୀ,ସ୍ତ୍ରୀ,ଉପହାର"},
    "pa-IN": {"name": "ਪਿਆਰ ਭਾਸ਼ਾ ਯਾਦਦਾਸ਼ਤ ਜੋੜਾ ਐਪ", "subtitle": "ਜੋੜਾ · ਕਾਊਂਟਰ · ਸਾਲਗਿਰਹ · ਦੂਰੀ",
              "native_kw": "ਰਿਸ਼ਤਾ,ਟ੍ਰੈਕਰ,ਕਾਊਂਟਡਾਉਨ,ਦੂਰੀ,ਸੁਨੇਹਾ,ਨੋਟ,ਡੇਟ,ਸਵਾਲ,ਵਿਆਹ,ਪ੍ਰੇਮੀ,ਪਤੀ,ਪਤਨੀ,ਤੋਹਫ਼ਾ,ਪਿਆਰ,ਯਾਦ,ਕੈਲੰਡਰ,ਨਾਲ,ਪ੍ਰੇਮਿਕਾ"},
    "ta-IN": {"name": "அன்பு மொழி நினைவூட்ட ஜோடி", "subtitle": "ஜோடி · கவுண்டர் · ஆண்டுவிழா",
              "native_kw": "உறவு,ட்ராக்கர்,கவுண்டவுன்,தூரம்,செய்தி,குறிப்பு,டேட்,கேள்வி,திருமணம்,காதலன்,கணவன்,மனைவி,பரிசு"},
    "te-IN": {"name": "ప్రేమ భాష జ్ఞాపకం జంట యాప్", "subtitle": "జంట · కౌంటర్ · వార్షికో · దూరం",
              "native_kw": "సంబంధం,ట్రాకర్,కౌంట్డౌన్,దూరం,సందేశం,నోట్,డేట్,ప్రశ్న,వివాహం,ప్రేమికుడు,భర్త,భార్య,బహుమతి"},
    "ur-PK": {"name": "محبت کی زبان جوڑا یادداشت ایپ", "subtitle": "جوڑا · کاؤنٹر · سالگرہ · فاصلہ",
              "native_kw": "تعلق,ٹریکر,کاؤنٹ ڈاؤن,فاصلہ,پیغام,نوٹ,ڈیٹ,سوال,شادی,محبوب,شوہر,بیوی,تحفہ"},
}


def load_astro() -> dict:
    raw = json.loads(ASTRO.read_text())
    if "bond" in raw:
        return raw["bond"]
    return raw


def astro_pop(astro: dict, store: str, term: str) -> int | None:
    meta = astro.get(store, {}).get(term.lower()) or astro.get(store, {}).get(term)
    if not meta or meta.get("skipped"):
        return None
    p = meta.get("pop")
    if p is None:
        return None
    return int(p) if isinstance(p, (int, float)) else None


def indexed(name: str, subtitle: str) -> set[str]:
    out: set[str] = set()
    blob = f"{name} {subtitle}".lower()
    for w in re.findall(r"[a-z0-9']+", blob):
        if len(w) >= 2:
            out.add(w)
    for c in re.findall(r"[\u0600-\u06ff\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af\u0900-\u097f]+", name + subtitle):
        if len(c) >= 2:
            out.add(c)
    return out


def pack_keywords(tokens: list[str], limit: int = 100) -> str:
    out, n = [], 0
    seen: set[str] = set()
    for t in tokens:
        key = t.lower() if t.isascii() else t
        if key in seen:
            continue
        add = len(t) + (1 if out else 0)
        if n + add > limit:
            continue
        out.append(t)
        seen.add(key)
        n += add
    return ",".join(out)


def build_keywords(locale: str, name: str, subtitle: str, native: list[str], astro: dict, store: str) -> tuple[str, list[str]]:
    idx = indexed(name, subtitle)
    astro_store = ASTRO_STORE_FALLBACK.get(store, store)
    tokens: list[str] = []
    en_kept: list[str] = []

    for t in native:
        tl = t.lower() if t.isascii() else t
        if tl in idx or t in name or t in subtitle:
            continue
        tokens.append(t)

    existing = {t.lower() for t in tokens}

    if not locale.startswith("en-"):
        ranked = []
        for term in EN_CANDIDATES:
            p = astro_pop(astro, astro_store, term)
            if p is not None and p >= 6:
                ranked.append((p, term))
        ranked.sort(reverse=True)
        for p, term in ranked:
            if term.lower() not in existing and term.lower() not in idx:
                tokens.append(term)
                en_kept.append(f"{term}({p})")
                existing.add(term.lower())

    extra = EXTRA_NATIVE.get(locale, [])
    for t in extra:
        tl = t.lower() if t.isascii() else t
        if tl not in idx and tl not in existing:
            tokens.append(t)
            existing.add(tl)

    kw = pack_keywords(tokens, 100)
    if len(kw) < 94:
        # second pass: shorter EN terms with pop>=6 not yet added
        for term in EN_CANDIDATES:
            p = astro_pop(astro, astro_store, term)
            if p is None or p < 6:
                continue
            if term.lower() in existing or term.lower() in idx:
                continue
            trial = pack_keywords(tokens + [term], 100)
            if len(trial) > len(kw):
                tokens.append(term)
                existing.add(term.lower())
                if f"{term}({p})" not in en_kept:
                    en_kept.append(f"{term}({p})")
                kw = trial
            if len(kw) >= 94:
                break
    return kw, en_kept


def trim_field(s: str, limit: int) -> str:
    return s[:limit] if len(s) > limit else s


def main() -> None:
    astro = load_astro()
    report: dict = {}
    issues: list[str] = []

    for locale in sorted(LOCALES.keys()):
        spec = LOCALES[locale]
        store = LOCALE_TO_STORE.get(locale, "us")
        name = trim_field(spec["name"], 30)
        subtitle = trim_field(spec["subtitle"], 30)
        native = [t.strip() for t in spec["native_kw"].split(",") if t.strip()]
        kw, en_kept = build_keywords(locale, name, subtitle, native, astro, store)

        overlaps = [t for t in kw.split(",") if t.lower() in indexed(name, subtitle)]
        entry = {
            "store": store,
            "title": name,
            "subtitle": subtitle,
            "keywords": kw,
            "title_len": len(name),
            "subtitle_len": len(subtitle),
            "keywords_len": len(kw),
            "keyword_overlaps": overlaps,
            "astro_en_kept": en_kept,
            "astro_proof": (
                [f"EN loanwords Astro pop≥6: {', '.join(en_kept)}"] if en_kept
                else ["Native/transliterated keywords only; no EN loanwords met pop≥6 in this store."]
            ),
            "rationale": (
                f"{'Bond brand in title (en-*).' if locale.startswith('en-') else 'Localized title; Bond dropped outside en-*.'} "
                f"Keywords deduped vs title+subtitle, packed {len(kw)}/100."
            ),
            "ok": len(name) >= 24 and len(subtitle) >= 24 and len(kw) >= 94 and not overlaps,
        }
        if len(name) < 24:
            issues.append(f"{locale} title {len(name)}<24")
        if len(subtitle) < 24:
            issues.append(f"{locale} subtitle {len(subtitle)}<24")
        if len(kw) < 94:
            issues.append(f"{locale} keywords {len(kw)}<94")
        if overlaps:
            issues.append(f"{locale} kw overlaps: {overlaps}")
        report[locale] = entry

    out_json = ROOT / "scripts" / "aso-bond-locale-readout.json"
    out_md = ROOT / "scripts" / "aso-bond-locale-readout.md"
    out_json.write_text(json.dumps({"locales": report, "issues": issues}, ensure_ascii=False, indent=2))

    lines = ["# Bond — full locale readout (proposed ASC metadata)\n",
             "Policy: Bond in **title** for en-* only · keywords deduped vs title/subtitle · EN loanwords only if Astro pop≥6\n"]
    for loc, e in report.items():
        lines.append(f"## {loc} (store: `{e['store']}`)\n")
        lines.append(f"**Title** ({e['title_len']}/30): {e['title']}\n")
        lines.append(f"**Subtitle** ({e['subtitle_len']}/30): {e['subtitle']}\n")
        lines.append(f"**Keywords** ({e['keywords_len']}/100): {e['keywords']}\n")
        if e["astro_en_kept"]:
            lines.append(f"**Astro EN:** {', '.join(e['astro_en_kept'])}\n")
        lines.append(f"**Why:** {e['rationale']}\n")
        if e.get("astro_proof"):
            lines.append(f"**Astro proof:** {' '.join(e['astro_proof'])}\n")
    if issues:
        lines.append("\n## Warnings\n")
        for i in issues:
            lines.append(f"- {i}\n")
    out_md.write_text("".join(lines))
    print(f"Wrote {out_json}")
    print(f"Wrote {out_md}")
    print(f"Locales: {len(report)}, warnings: {len(issues)}")


if __name__ == "__main__":
    main()
