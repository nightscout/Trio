# Turkish Localization Glossary (tr)

Reference for translating `Trio/Sources/Localizations/Main/Localizable.xcstrings`
and `Trio/Resources/InfoPlist.xcstrings` into Turkish. Keep new translations
consistent with the terms below.

## Principles

- **Abbreviations stay English.** IOB, COB, ISF, CR, SMB, CGM, TDD, DIA, TBR,
  TIR, GMI, UAM are the terms the Turkish diabetes community and pump/CGM
  displays already use. Spell the meaning out in Turkish on first or
  explanatory use — `Aktif İnsülin (IOB)` — and use the bare abbreviation
  afterwards.
- **Address the user with "siz"** (`dokunun`, `kontrol edin`), never "sen".
- **One term, one translation.** `Glucose` is always `Glukoz` — never `Glikoz`
  or `KŞ`.
- **Format specifiers are untouchable.** `%@`, `%1$@`, `%lld`, `%.1f` must
  appear in the translation exactly as in the source, same order and count.
  Positional (`%1$@`) specifiers may be reordered only by changing the index.
- **Keep leading/trailing whitespace, newlines and symbols** (`•`, `◦`, `⚠️`,
  `→`) exactly as in the source; UI layout depends on them.
- **Product and feature names are not translated:** Trio, Nightscout, Autosens,
  Apple Watch, Live Activity, Widget, Pod, Loop (as a product), oref.

## Core terms

| English | Turkish |
|---|---|
| Glucose | Glukoz |
| Blood Glucose | Kan Glukozu |
| Eventual Glucose | Öngörülen Glukoz |
| Glucose Target | Glukoz Hedefi |
| Temp Target | Geçici Hedef |
| Basal | Bazal |
| Basal Rate | Bazal Hız |
| Temporary Basal Rate (TBR) | Geçici Bazal Hız (TBR) |
| Bolus | Bolus |
| Super Micro Bolus (SMB) | SMB |
| Carbs / Carbohydrates | Karbonhidrat |
| Carb Ratio (CR) | Karbonhidrat Oranı (CR) |
| Insulin Sensitivity Factor (ISF) | İnsülin Duyarlılık Faktörü (ISF) |
| Insulin on Board (IOB) | Aktif İnsülin (IOB) |
| Carbs on Board (COB) | Aktif Karbonhidrat (COB) |
| Total Daily Dose (TDD) | Toplam Günlük Doz (TDD) |
| Duration of Insulin Action (DIA) | İnsülin Etki Süresi (DIA) |
| Time in Range (TIR) | Hedef Aralıkta Süre (TIR) |
| Closed / Open Loop | Kapalı / Açık Döngü |
| Loop cycle | Döngü turu |
| Pump | Pompa |
| Reservoir | Rezervuar |
| Cannula | Kanül |
| Prime | Dolum |
| Site change | Set değişimi |
| Sensor | Sensör |
| Transmitter | Verici |
| Calibration | Kalibrasyon |
| Suspend / Resume | Duraklat / Sürdür |
| Enact | Uygula |
| Delivery | İnsülin verme |
| Override | Geçersiz Kılma |
| Preset | Ön Ayar |
| Meal | Öğün |
| Fat / Protein | Yağ / Protein |
| Alert | Uyarı |
| Notification | Bildirim |
| Settings | Ayarlar |
| Preferences | Tercihler |
| Forecast / Prediction | Tahmin |
| Trend | Eğilim |
| Reading | Ölçüm |
| Low / High (glucose) | Düşük / Yüksek |
| Below / Above Range | Aralık Altı / Aralık Üstü |

## Units

Unit symbols are kept as displayed by pumps and CGMs: `U`, `U/hr`, `g`, `g/U`,
`mg/dL`, `mmol/L`, `%`. Do not translate them to `Ü` or `IU`.
