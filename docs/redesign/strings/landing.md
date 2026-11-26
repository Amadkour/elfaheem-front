# Landing persona pages: copy notes (phase 7)

Pages: `/ar|en/students/`, `/ar|en/parents/`, `/ar|en/teachers/` (`landing/src/components/PersonaPage.astro`, copy in
`landing/src/i18n/personas.ts`). The Arabic is the approved copy of `LandingW` / `LandingM` / `LandingTeacher*`, with
these changes and their reasons.

## Changed for RULES.md §3 (NextBrain's default market is Egypt; nothing Saudi-only shown to everyone)

| Where | Design | Here | Why |
|---|---|---|---|
| Course showcase lead | برمجة وذكاء اصطناعي، ولغات، وقدرات وتحصيلي. | برمجة وذكاء اصطناعي، ولغات، ومواد المدرسة. | قدرات / تحصيلي are Saudi-curriculum only |
| Parent "subjects" lead | … والقرآن، والقدرات والتحصيلي، ودورات … | … والقرآن، ودورات … | same |
| Parent FAQ "كيف يكون الدفع؟" | شامل الضريبة، وتدفع بمدى أو Apple Pay أو STC Pay أو البطاقة، وتقدر تقسّط مع تابي أو تمارا | وتدفع بطرق الدفع المتاحة في بلدك، وتشوف المبلغ كامل قبل ما تدفع | مدى / STC Pay / تابي / تمارا / VAT are Saudi-only; payment methods are per country |
| Teacher FAQ "كيف ينحسب دخلي؟" | لحسابك البنكي | لحسابك | payouts accept other methods than a bank account |
| Teacher demand steps | أنشئ حسابك (أو بنفاذ) | أنشئ حسابك | نفاذ is Saudi-only |
| Teacher board example | دخلك هذا الشهر ٨٬٤٠٠ ريال | تقييم طلابك 4.8 من 5 | no currency on a page every country sees |
| Grade picker | روضة / ابتدائي / متوسط / ثانوي / جامعة + الصف | the grades from `GET /public/landing/options` | the stage list is Saudi; grades come from the server per country |
| Teacher subject chips | رياضيات، علوم، … (fixed) | the subjects from `/options` | real list |
| Student / parent pick label | أنت في أي مرحلة؟ / ابنك في أي مرحلة؟ | أنت في أي صف؟ / ابنك في أي صف؟ | the picker is one level (grade), not stage + grade |
| Digits | Arabic-Indic (١٢٬٤٠٠) | Latin (12,400) | KIT_SPEC §3.6: NextBrain's `digits` default is `latin` |

## Not shown (never invented numbers or people)

- Course prices, lesson counts and the "الأكثر طلبًا / جديد" badges on the showcase cards: the showcase shows the real
  courses of `/highlights` (title, mode, rating, students, teacher) and is hidden when there are none.
- The stats bands (12,400 / 380 / 240 ألف ساعة / 4.9 / 7,500 ريال …): only the real `/stats` numbers (students,
  teachers, courses) are shown; the band is hidden without them.
- The four teacher cards (أ. ماجد الشهري …) and the three quotes per page: the teachers section keeps its heading,
  lead and vetting chips; reviews come from `src/content/testimonials.json` and `/highlights` and the section is hidden
  when there are none.
- "دورات تناسب صفك" with prices: the results card lists the grade's real subjects with their course counts and links
  to the app's explore page.
- Teacher demand numbers: `GET /api/v1/public/teacher-demand?subject=` (BACKEND.md §2; the contract file
  `docs/redesign/api/demand.md` was not written yet when this was built, so the page codes against
  `{available, waiting_students, booked_classes_30d, groups_waiting, updated_at}`). The numbers and the subject picker
  appear only when the endpoint answers `available: true` with at least one number; otherwise the card is the plain
  "كيف تبدأ" steps + "أنشئ حسابك كمعلم". `country` is not sent (the server's default market applies).

## Left out of the design on purpose

- Background music and its "شغّل الصوت" toggle (no audio asset; autoplaying sound on a public page).
- The in-page course profile and the sign-up sheets: course cards open the app's course page (`/app/courses/{id}`),
  sign-up buttons open the app's join flow (`/app/join?role=…`).
- Noto Naskh Arabic / Aref Ruqaa from Google Fonts: the landing self-hosts IBM Plex Sans Arabic / Inter (no
  third-party requests).

## Dialect

Strings in the Saudi voice (`dialect.md` list): وش، يدوّرون، هالمادة، تبي، الحين، إيه، زين، سوا، لين. Kept as approved.

## English

Every string has an English version in `enP` (same file). English pages use Inter and LTR mirroring (logical
properties; the path illustration is mirrored in LTR).
