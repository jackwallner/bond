# Little Gestures: Google Play listing

Source of truth for the Play Console store listing text. en-US is the live
listing copied verbatim (it names what the Android build lacks: Apple Watch,
iOS widgets, iPhone arrival alerts). No prices in copy: Play shows them.

## Listing text

Title, short and full description per locale live in
`metadata/android/<locale>/` (fastlane supply layout), uploaded with:

    fastlane supply --json_key <service account> --package_name com.jackwallner.bond \
      --metadata_path android/play-assets/metadata/android --track internal \
      --skip_upload_apk true --skip_upload_aab true --skip_upload_changelogs true \
      --skip_upload_images true --skip_upload_screenshots true

Locales (50): en-US (default), en-GB/AU/CA/IN, de-DE, fr-FR/CA, es-ES/419/US,
pt-BR/PT, it-IT, nl-NL, sv-SE, no-NO, da-DK, fi-FI, pl-PL, cs-CZ, sk, sl, hr,
hu-HU, ro, el-GR, tr-TR, ru-RU, uk, ar, iw-IL, hi-IN, bn-BD, mr-IN, ta-IN,
te-IN, kn-IN, ml-IN, id, ms, ms-MY, th, vi, ja-JP, ko-KR, zh-CN/TW/HK, ca
(the same set as Sober). Search terms per locale come from the matching iOS
`fastlane/metadata/<locale>/keywords.txt`, `name.txt` and `subtitle.txt`.
Titles keep "Little Gestures" and add the local couples phrase (Paare & Liebe,
En pareja, Para casais, Для пар, カップル・夫婦, 情侣恋爱提醒); short
descriptions open with the local "couples app". Every non-English description
says the app is in English (the Android app is not localized). Other locales
leave out the Apple wording and say arrival alerts, a watch app and home-screen
widgets are not on Android.

Check with `scripts/validate-play-listing.py` (Play limits, no em dashes, no
prices, no Apple wording outside the live en-US copy, no promo words in titles,
brand in every title, Google Play billing line, the English-only note, and
en-US equal to `.play-live-listing.json` when that file is present).
