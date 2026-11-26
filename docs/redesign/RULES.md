# Product rules for the redesign

These rules come from the client and the design review. They apply to every screen, every role, and both the app and the landing site. When the design and this file disagree, this file wins.

## 1. Client decisions (fixed)

1. Booking wording:
   - The question is "كيف تبي تدرس؟", with no subtitle under it.
   - عن بعد: "شرح مباشر ويتم حفظ الشرح للرجوع إليه."
   - حضوري: "يكون وجهًا لوجه مع المعلم أو المعلمة."
   - Use "تفاصيل إضافية" and "فردي مع المعلم".
   - No description under "وين موقعك؟" and none under "اختر مواعيد حصصك".
2. "لحالك" is never used. The word is "فردي" everywhere.
3. A group is 5 to 10 students (طلاب أو طالبات). A class (حصة) is 50 minutes.
4. Never state how many classes a week or a month: no "مرتين في الأسبوع", no "٨ حصص في الشهر".
5. Subject book:
   - The hint is "اضغط على الكتاب لمعرفة التفاصيل".
   - The phrases "الكتاب هذا لك" and "المادة في أرقام" are not used.
6. "كشكول" is renamed "دفتر" everywhere (دفتر المادة).
7. **Privacy:** a student must never be able to know who else is in his group, class, meeting or live room. Only the teacher sees participants. This is enforced on the server too (BACKEND.md §3), not only hidden in the UI. See DESIGN_SYSTEM.md "Privacy contract" for the exact allowed and forbidden items.
8. Language and vocabulary:
   - Saudi dialect, masculine address by default; feminine in flows for a female student.
   - "دورة", never "كورس".
   - "مجاني" is never used as a selling point.
   - "عن بعد", never "أونلاين".
   - حصة means a live class; درس means a recorded or reading item. Do not use "جلسة" in student UI.
9. Owner decisions O-1 to O-6 (DESIGN_SYSTEM.md, last section) are taken. Leaderboards use nicknames.

## 2. Saudi market (the primary market)

- **School week:** Sunday to Thursday; the weekend is Friday and Saturday. No regular class on Friday midday. Avoid placing a class at Maghrib.
- **Gender:** groups are boys-only or girls-only, never mixed. Show the teacher's gender (معلم / معلمة). Girls' groups are taught by female teachers. Avatars are initials or illustrations, never student photos, and never a girl's photo.
- **Curriculum:**
  - Saudi grades: الأول ابتدائي … الثالث ثانوي.
  - Secondary tracks: المسار العام، علوم الحاسب والهندسة، الصحة والحياة، إدارة الأعمال، الشرعي.
  - قدرات and تحصيلي; STEP for English.
- **Money:**
  - Prices in ريال.
  - Payment by مدى، Apple Pay، STC Pay، بطاقة ائتمان، تحويل بنكي.
  - تابي / تمارا may appear.
  - A total includes ١٥٪ ضريبة القيمة المضافة.
- **Identity:**
  - Phone +966 5X XXX XXXX.
  - National ID / إقامة only through the parent.
  - نفاذ may appear for parents and teachers.
- **Dates:** Gregorian, with an optional Hijri line where it helps (exams, Ramadan). Ramadan has its own timetable. Eid pauses classes.
- **Faith:** Quran screens have no music or sound effects, and no images of living beings.

## 3. International users (any nationality, any country)

Saudi Arabia is the default and primary market. But a student, parent or teacher can be of any nationality and can sign up from any country. The app must never assume Saudi nationality or residence.

- **Country of residence, not nationality:**
  - Sign-up asks for the country of residence. The design's list is: السعودية، الكويت، الإمارات، البحرين، قطر. Add "دولة أخرى" with a searchable full list.
  - The app never asks for nationality unless the law or the payment gateway needs it.
  - The app never infers nationality from a name, a phone number or a language.
- **Phone:** use a country-code picker that defaults to +966 and accepts any country. Validate per country (E.164), not with a Saudi-only pattern. Any OTP or WhatsApp step must work for non-Saudi numbers.
- **Curriculum and grades:**
  - Grade and subject lists come from the server per country.
  - The Saudi curriculum is the default, and the choice the app suggests for a Saudi resident.
  - A user anywhere may choose the Saudi curriculum, for example a Saudi family living abroad, or a non-Saudi family in KSA.
  - قدرات / تحصيلي / هيئة تقويم التعليم والتدريب are shown only for the Saudi curriculum.
- **Time:**
  - Store every class time in UTC.
  - Show it in the viewer's time zone through `AppTime`: the profile time zone, else the device time zone.
  - A teacher in Egypt and a student in Riyadh see the same class at their own local times. The schedule screen says which time zone it shows when it differs from the platform time zone.
  - The weekend and the Maghrib hint follow the user's country and city. Keep this as data, not code.
- **Money:**
  - Prices are stored in the platform currency (SAR).
  - When the user's country differs, a converted "≈" amount may be shown, but the charge stays in the gateway currency. Say so on the payment screen.
  - Payment methods are filtered by country: مدى and STC Pay only in KSA; cards, Apple Pay and Google Pay elsewhere; other local methods when the gateway supports them.
  - VAT follows the seller's rules; do not show "١٥٪" to someone it does not apply to.
- **Teachers:**
  - A teacher can be of any nationality and live in any country.
  - Teacher verification accepts a passport, an iqama or a national ID, never only a Saudi ID.
  - Payouts accept an IBAN of any country, or the other methods the backend supports.
  - The teacher's profile shows their country only if the teacher chooses to show it.
- **Location (حضوري):** in-person classes are offered only where the platform has centres. The city and district lists come from the server. Outside those areas, "حضوري" is hidden or says it is not available in the user's city.
- **Language:**
  - Arabic is the default and English is supported; every string has both (`assets/translation.json`).
  - The Saudi dialect is the voice, but it never mocks or excludes other Arab dialects or nationalities.
  - Examples and placeholders stay neutral: no "مواطن", no "هويتك الوطنية" as a requirement.
- **Gender rules** (boys-only and girls-only groups, a matching teacher gender) apply to everyone, whatever the country.
