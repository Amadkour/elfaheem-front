# Learning Hub: reference-app research (2026-11-20)

Method note: WebFetch read static HTML only. faheemapp, moalimy and the AlGooru search gave real content; gaga-app, the Play Store page, abwaabegypt and alrrabbaniyeenacademy are JS-rendered and returned only a title. Cells marked "n/s" = not seen, not "absent". Walk those flows in a browser before the final review.

## Comparison

| App | Onboarding | Levels | Discovery + filters | Booking | Store / Quran / games / nahw |
|---|---|---|---|---|---|
| Faheem (faheemapp.com) | 3 steps: form, advisor calls in 24 h, first session | KG to university, all subjects | No tutor search; vetted tutors, advisor builds a plan | Form, 1:1 live; recording kept in account | Store n/s; Quran n/s; games n/s; nahw n/s. "Golden guarantee": first session free, instant tutor swap |
| Moalimy (moalimy.com) | 3 steps: register, pick package + tutor, pay; classroom opens on payment | Primary, intermediate, secondary, international, university, Qiyas, skills | Browse by stage and subject; pick session times; change tutor fast | 60-min sessions: 8/month, 2/week, or urgent same-day; Tamara/Tabby; gift cards | Quran is a subject; AI "capabilities coach" error analysis; WhatsApp reminders; AR/EN/FR |
| AlGooru (القورو, Saudi) | App-first tutor marketplace | School and university | Find a private tutor; AI matching (self-reported) | Online and offline sessions; 150k+ sessions claimed | n/s. Raised $4M pre-Series A (Dec 2024) |
| GAGA (gaga-app.com/individual) | n/s | n/s | n/s | n/s | n/s |
| هدفك للقدرات (Play) | n/s; title says Qudurat prep | Test prep | n/s | n/s | n/s |
| Abwaab (abwaabegypt.com) | n/s ("integrated learning environment") | n/s | n/s | n/s | n/s |
| Al-Rabbaniyeen Academy | n/s | n/s | n/s | n/s | n/s |
| Nafham (search result) | Free, no sign-up wall | K-12, Egypt + Saudi + others curricula | By country, grade, subject | Not a tutoring market | 23k short videos; no store |
| Edraak (search result) | Account for courses | K-12 plus adult, MENA-aligned | Catalog | n/a | Free courses |
| Sahlah (search result) | Trial-led | Arabic and Islamic studies K-12 | Course pages | Paid classes | Quran classes for kids |

## Strengths and weaknesses

- Strengths seen: very short funnels (3 steps); trust devices (free first session, instant tutor swap, vetting); flexible package maths (per-week, urgent same-day); BNPL and gift cards; WhatsApp reminders; session recordings; AI diagnosis of mistakes; Arabic first with several languages.
- Weaknesses: single-purpose silos (tutoring only, or video only, or test prep only); no visible country/curriculum switch on the tutoring apps (Saudi-centric stage lists); filters shallow (stage + subject only; no delivery mode, city/district, gender); no combined store, games, Quran and nahw in one account; no parent view of games progress; no offline use; no org/school mode.
- Our handwritten flow sheets go further than all of these: stage, grade and subject trees plus city and district for in-person, and live vs recorded for remote.

## Implied requirements

1. Stages and grades are data per country (Egypt and Saudi differ), editable by super admin; never hardcoded. [phase 2]
2. A "country set" can be cloned to start a new country; subjects hang off stage and grade, with a "general" bucket for tests (Qudurat, Tahsili, STEP) and international Math/Science. [2]
3. Course categories beyond school: tests (with tracks such as literary/scientific), English from zero, professional licence, computer skills, development; each is data, not code. [2, 3]
4. Students give stage + grade; teachers give the stages, grades and subjects they teach; parents link children each with stage + grade and give consent for minors. [3]
5. A course serves many stages/grades, a delivery mode (online live, online recorded, in-person, both), and in-person courses store governorate/city, district and address. [3]
6. Landing: three entries (student, teacher, organization) and a short wizard that ends in a search; keep a visible step count, at most 5 taps to results. [4]
7. Filters stage, grade, subject, delivery mode, city/district, price, teacher gender; same component on landing and home; composite indexes on those columns. [4]
8. Guest opens a course, is sent to login/sign-up and returns to the same course and booking step with choices kept. [4]
9. Trust devices at booking: free or refundable first session, easy teacher change, session reminders. [4]
10. Store: price shown with and without tax, tax rate and currency per country, items tied to stage/grade/subject or general, protected expiring downloads, My Library, purchase history. [5]
11. Games: catalog filterable by stage/grade/subject, ad-free, scores and badges, parent-visible progress; framework extensible so new game types plug in. [6]
12. Quran: teacher filter by gender, individual or group, goal (memorization, tajweed, revision), progress by surah and juz; verification, content review and gender-matching are config flags, relaxed by default. [6]
13. Nahw: ordered levels, exercises with instant feedback, progress per lesson, linked to stage/grade. [6]
14. Each student tab is switchable per country or organization by super admin through the existing kill-switch layers. [2 to 6]

## How we beat them

1. One account, one app: courses, store, games, Quran, nahw. Competitors cover one slice each.
2. Country packs: Egypt and Saudi stage sets, cities, VAT and currency switch with one setting; adding a country is data entry.
3. Search that matches the paper flow: stage, grade, subject, mode, city and district, gender, price in one sheet with live result count.
4. Resume-anywhere funnel: guest choices survive login, and the booking opens on the exact course.
5. Offline-first and installable (Android, Windows, Linux, macOS), with a visible "working offline / syncing" status. None of the references show this.
6. Parent mode: consent for minors, per-child progress across courses, games and Quran in one view.
7. Premium store: price with/without tax, instant secure download, expiring links, My Library, editable summaries.
8. Instant-feedback nahw and Quran trackers (surah/juz map), plus ad-free games with badges; AI mistake diagnosis as in Moalimy, but tied to the student's grade.

## Verified facts

Egypt stages (verify against the Ministry for any 2024+ reform; one 2024 press article reports restructuring):
- KG: 2 years, ages 4 to 5 (KG1, KG2), voluntary. Primary: 6 years (ages 6 to 11). Preparatory: 3 years, Grades 7 to 9, compulsory. General secondary: 3 years, Grades 10 to 12 (technical secondary up to 5). University follows.
- Sources: [ADEA country profile Egypt](https://knowledgehub.adeanet.org/country-profiles/egypt), [WENR Egypt secondary](https://wenr.wes.org/country-profiles/secondary-sections/egypt-secondary-education/), [UNICEF Egypt](https://www.unicef.org/egypt/education).

Saudi Arabia stages (Ministry of Education):
- Kindergarten/rawdah: 3 years, ages 3 to 5, optional, outside the official ladder. Primary: 6 years (Grades 1 to 6). Intermediate: 3 years (Grades 7 to 9). Secondary: 3 years (Grades 10 to 12). University follows. Exact ages vary by source, so store grades, not ages.
- Sources: [TIMSS encyclopedia, Saudi Arabia](https://isc.bc.edu/timss2019/encyclopedia/pdf/Saudi%20Arabia.pdf), [Saudipedia](https://saudipedia.com/en/education-in-saudi-arabia), [UNESCO IBE](https://webarchive.unesco.org/web/20160810124912/http://www.ibe.unesco.org/sites/default/files/Saudi_Arabia.pdf).

VAT (rates verified; book treatment only from secondary sources, confirm with the tax authorities before launch):
- Egypt: standard 14%. Printed books are listed as exempt; e-books and digital downloads fall under the 14% digital regime (one guide's wording on e-book subscriptions is ambiguous). Sources: [Andersen Egypt VAT regulations](https://eg.andersen.com/wp-content/uploads/2024/09/VAT-Regulations-in-egypt-1.pdf), [Quaderno Egypt VAT guide](https://quaderno.io/guides/egypt-vat-guide), [Egyptian Tax Authority](https://www.eta.gov.eg).
- Saudi Arabia: standard 15%. Books and e-books appear in no zero-rated or exempt list found; digital supplies are taxable at 15%. Treat both as 15% by default, configurable. Sources: [ZATCA VAT Implementing Regulations](https://zatca.gov.sa/en/RulesRegulations/Taxes/Documents/Implmenting%20Regulations%20of%20the%20VAT%20Law_EN.pdf), [KPMG on 2025 amendments](https://kpmg.com/us/en/taxnewsflash/news/2025/04/saudi-arabia-vat-amendments-approved-effective.html).
- Design consequence: tax rate and an "exempt" flag per country and per item type, never a constant.

Quran metadata only (surah names, ayah counts, juz boundaries): [Tanzil Quran metadata](https://tanzil.net/docs/Quran_Metadata) (quran-data.xml). Licence: header of quran-data.js reads Creative Commons Attribution 3.0 (attribution required); confirm on tanzil.net before shipping. The Tanzil Quran TEXT has a separate no-modification licence; do not ship text without a source decision logged in DECISIONS.md. Do not use hablullah/data-quran (CC BY-NC-ND 4.0).
