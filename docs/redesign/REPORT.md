# Redesign report (NextBrain, 2026-11-27)

Branches: front `feature/redesign` (Amadkour/nextbrain-front), back `feature/redesign` (nextbrain back). Nothing is
merged to `production` or `main`, nothing is deployed. Alfaheem gets the same code through its sync after this report
(its own palette and Saudi defaults, D-1810).

## 1. What was built

| Phase | Groups | Result |
|---|---|---|
| 1 Kit | tokens, NextBrain palette from the logo (green + gold), area accents, motion M1–M16, hero, cards, tabs, states, live, sheets, shells, inputs, switch, tables, gallery `/kit_gallery` | merged; theme seed in the back (migration `0135`) |
| 2 Student | S-A auth, kid code, join, home, discover (+ S-A2 bodies); S-B subject page, learn, live join, attendance, notebook; S-C exams, analysis, messages, schedule, assistant; S-D wallet, payments, store, teachers, Quran, games, rewards, profile | merged |
| 3 Booking | booking flow 1–5, pre-enrol page, subject chat / assistant / schedule panels | merged |
| 4 Parent | home, children, child sign-up step in the join flow, child code, pay, per-child invoices (WP13) | merged |
| 5 Teacher | T1 home, courses, wizard, course page, class, live (bring on stage); T2 analysis, money, certificates, exams, Data Lab, teaching; T2b schedule, account, complaints, chat; booking times | merged |
| 6 Admin | A1 home, More hub, approvals inbox, analytics, people pages; A2 finance, platform, AI, site, releases, ads, store; consoles for booking, teacher demand, payment markets | merged |
| 7 Landing | persona pages (students, parents, teachers), demand card | merged |
| 8 International | payment methods by the payer's country (server + app), VAT only when it applies, world phone fields, `AppTime`, digits, the language's own comma | merged |
| 9 Audit + fixes | parity by diff (nothing lost), privacy fixes, brand separation, vocabulary, kit requests, unwired routes | merged; CI test fixes in progress |

Backend packages WP1–WP13 are merged (migrations up to `0162`, then `0135`; one head).

## 2. Privacy (students never see classmates)

- Live rooms: students and guests get the private room (no participant list, no head count); hand and question go to
  the teacher only (`/public/live/hand|ask` for guests). The public live info no longer carries `guests_joined`; it
  carries `full`.
- Course chat is the teacher's announcements plus a private chat; the new-message picker lists no classmates.
- Booking shows a seat level ("آخر مقاعد"), never a count. Course pages show no student count to a learner.
- Games: nicknames and avatars only; the class board is staff only; a learner can set the nickname.
- Check-in errors no longer mention classmates, witnesses or Bluetooth.

## 3. Decisions taken for the owner (change any of them)

1. The class games board is kept for teachers and staff, hidden from students.
2. Organisation-wide champions boards stay (they show nicknames only).
3. A full guest room says "the room is full, try again shortly" instead of a count.
4. Parent invoices, the games nickname editor and the admin consoles (booking, demand, payment markets) were built now.
5. The 45 s roster refresh in the live room stays as a fallback; the roster also refreshes on join, leave, hand and ask.
6. Package seats keep the server's 1–500 (the design says 5–10).
7. "Get an exam from a nearby phone" stays visible to students.
8. Gold kicker contrast: home, me and admin heroes start on the logo green `#186848`; the gold on dark is `#E6D1B1`
   (BRANDS.md).

## 4. Owner questions (open)

1. Should a booking also enrol the student in the course? Today "افتح المادة" returns to the course page.
2. Bank transfer is hidden in booking: show it?
3. Should a parent book and pay for a child? (The parent booking page shows subjects and prices; the button is off.)
4. Should the interests a student picks at sign-up be saved (`interest_ids` on the study profile)?
5. Guest live name hint: the design says only the host sees it; today other participants see it. Which is true?
6. Should students scan the attendance QR?
7. Which page opens "أضف مواد للحصة" from the teacher home?
8. A course publish-approval queue, an admin audit log, a roles editor: wanted? (No backend yet.)
9. Teachers can add remote booking times only (no teacher route lists centres): add in-person times?
10. Earlier open items: Israel in the country list, an Egyptian-dialect copy for NextBrain, Arabic-Indic digits for
    NextBrain, the exam identifier (O-4), privacy inside organisations, student 2FA, daily lessons inside Quran.

## 5. Differences from the reference we could not close

- The design's brand (logo, name, blue/navy/apricot) is replaced by NextBrain's green and gold everywhere, by design.
- Tabs and the search target are 48 px (touch rule), not 44.
- Seat counts, joined-guest counts and classmates are never shown (privacy contract wins over the drawing).
- No map picker for centres; no inline OTP sign-in in the booking sheet (the server has no OTP sign-in).
- No "صورة من السبورة" in the notebook (no upload route); sharing and deleting a notebook page sit behind a long press.
- Phone hero stats show as 2×2 to keep labels readable.
- The teacher phone week view is still the time grid; some sheets have no goldens (the harness does not capture routes).
- Data the server does not send is not drawn: device list, ranking points, coupon count, assistant add, transcript
  preview, recommendation "hidden courses", analytics funnels / cohorts / cities, the live session list for admins.
- The week start still follows the language (no server field for it).

## 6. Owed before release

- CI test fixes (agent `rd/fx-tests`), then one clean full run.
- Sync to Alfaheem (its palette and Saudi defaults, `platform_settings.digits=arabic_indic`), then its gates.
- Hidden LiveKit participants have not been tried on a real LiveKit server.
- Backend: booking monthly renewal, expired holds swept only on reads, no admin notification for booking proposals,
  STC Pay / Tabby / Tamara / Egypt wallets have no checkout flow (flags off), identity types seed inactive on existing
  databases, RAG chat does not check `rag.subject_bot`.
- The owner runs the deploy (migrations `0130`–`0162`, `0135`) after merging to production.
