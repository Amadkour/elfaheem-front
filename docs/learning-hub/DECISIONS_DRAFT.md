# Learning Hub — decisions to merge into `docs/DECISIONS.md`

Block reserved: D-1300 – D-1399. All entries · 2026-11-20 · proposed. Numbers not listed are free for the phase that owns the range (PLAN.md §5).

## D-1300 — Learning Hub job: file names follow the repo, not the brief's root names
The brief names root files `DECISIONS.md`, `PROGRESS.md`, `RESEARCH.md`, `BUILD.md`, `FINAL_REPORT.md`. The repo already has a root `PROGRESS.md` (the platform-polish job) and keeps decisions in `docs/DECISIONS.md`. So: decisions here as D-1300+, the tracker `docs/learning-hub/PROGRESS.md`, `RESEARCH.md` and `FINAL_REPORT.md` in `docs/learning-hub/`, `BUILD.md` in `docs/release/`. Nothing of the brief is dropped; only the place changes.

## D-1301 — The add-student 500: `nid_kind` was VARCHAR(10), `national_id` is 11 characters
PostgreSQL rejects the insert; SQLite ignores the length, so the e2e scripts passed. Fix: widen to 20 (migration 0101). The same row is created by add-teacher and add-member, so one fix covers all three. (The Phase 1 agent replaces this text with the confirmed traceback.)

## D-1302 — Each phase's e2e runs once on PostgreSQL before a merge
SQLite stays the fast default for agents. The lead runs the phase's scripts on the test container once, because lengths, transaction aborts and partial indexes behave differently.

## D-1303 — Research (brief Part 2) runs beside Phase 1
The brief's phase list has no research step. It is one agent in parallel with the fix; Phase 2's seeds wait for its verified stages and VAT rates.

## D-1310 — Education levels are tables per country; the old constants become the fallback
`edu_countries → edu_stages → edu_grades`, `edu_subjects`, `geo_areas`. `STAGES`, `TRACKS` and `GOVERNORATES` in `student_profile_service.py` are used only while the tables are empty. Consolidated, not deleted: `student_study_profiles.stage / grade / governorate` are still written with the same keys.

## D-1311 — How the Saudi sheet generalises
| On the sheet (Saudi) | General rule | Egypt |
|---|---|---|
| روضة / ابتدائي 1–6 / متوسط 1–3 / ثانوي 1–3 | stages and grades are rows of a country | KG 1–2 / ابتدائي 1–6 / إعدادي 1–3 / ثانوي 1–3 |
| subjects listed under each grade (لغتي, توحيد, فقه, …) | `edu_subjects` + which grades offer them | عربي, دراسات, … |
| دولي: Math, Science | a stage of kind `international` | IG / American as stages |
| جامعة: name + college + subject → WhatsApp | a stage with `contact_only`; the number is `edu_countries.contact_whatsapp` | same |
| حضوري → المدينة → الحي | `geo_areas`, two levels, labels per country | المحافظة → المدينة / المنطقة |
| عن بعد → مباشر / مسجل | `delivery_mode` + the existing `courses.type` | same |
| قدرات, تحصيلي, GAT, SAAT, STEP, رخصة مهنية | categories with a `country_code` (course families), not stages | no rows, or its own families |
| VAT 15 %, SAR | `edu_countries.vat_percent`, `currency` | 14 %, EGP |
| رجال / نساء (Quran) | a filter on the teacher's gender; matching rules are flags, off | same |
Nothing in code names a country.

## D-1312 — Tracks (علمي / أدبي) live on the grade
`edu_grades.tracks` is a short list; the existing `student_study_profiles.track` keeps its value. The sheet's تحصيلي sub-tracks (إدارة أعمال, شرعي, هندسي, صحي) are child categories.

## D-1313 — A stage or grade in use is deactivated, never deleted
Profiles and courses point at it. The admin sees how many rows use it.

## D-1320 — Remote "live / recorded" is the existing course type
No new column: `delivery_mode` says where, `type` says how. `mode=center` in `GET /courses` keeps meaning "an organization's course".

## D-1321 — An in-person course shows its area publicly, its address after enrollment
An address can be a home. Teacher, staff and enrolled students see it. Safest default; a per-course "show address" switch can follow.

## D-1322 — "Booking" is the existing enrollment and checkout
No bookings table. An in-person course is booked by enrolling (card, manual transfer or free), as an online one.

## D-1323 — The join flow is a Flutter screen; the Astro landing only links to it
One implementation for web and the native apps. The landing's buttons are Student, Teacher, Parent (the brief) plus "Add your organization" (the sheet). The old guest search stays as "just browse".

## D-1324 — Guest → login → same course: a stored pending intent
`PendingIntent` in SharedPreferences (24 h), resumed once by `MyAuthProvider` after sign-in or registration, so it survives a full page reload. It holds ids and filters only, never personal data.

## D-1330 — Store orders use the points top-up card pattern, not the `payments` table
`payments.course_id` is NOT NULL and its reports assume a course. The store reuses the providers, the webhook route and the points wallet, with its own order rows.

## D-1331 — Tax is a country setting, snapshotted on the order
`vat_percent`, `prices_include_vat`, per item `vat_exempt`. Rates in the seeds come from RESEARCH.md's sources and are editable. The price is always shown with and without tax.

## D-1332 — Protected download: library check → single-use token → 60-second signed URL
The file key never leaves the server. Each grant is a row (the download history). A daily limit per user and item is a setting (10).

## D-1333 — The cart is on the device
One order call carries the item ids. No cart table; nothing to sync.

## D-1334 — Store v1 sells platform and organization items; teacher payouts for store sales come later
The owner id is stored and `teacher_items` is a flag (off). Earnings need the ledger and payout rules: out of this job's scope, listed in FINAL_REPORT.

## D-1340 – D-1349 — numbering fixed at the Phase 6 review (2026-11-21)
The two repositories keep separate `docs/DECISIONS.md` files, and a number may be a back half and a front half (as D-1339 is). B6 wrote back D-1340 – D-1342 with their own subjects, so the entries below follow what is committed and what the code comments cite. `[back]` goes in `back/docs/DECISIONS.md`, `[front]` in the front's.

## D-1340 [front] — Nine student tabs: the phone bar draws five slots, with a "Learn" slot
`student_tab_store|games|quran|nahw` are kill-switch keys, organization-manageable. The tab list does not change; only the phone bar folds tabs that share a `mobileGroup` into one slot when there are more than five. The student's bar is Home · My courses · Learn · Schedule · Profile; Learn opens a sheet with Store, Games, Quran, Grammar and Analysis. A group with one visible member draws that tab; any role with more than five slots gets a built-in "More". The sidebar and the rail still list every tab. The exact rules are in PROGRESS "6.R code review".

## D-1340 [back] — Module rule flags: one registry, platform ← country ← organization rows, one resolver (written by B6)
Kill switches hide; flags change rules. Every Quran constraint is a flag and all are off or relaxed by default, as the brief asks. Only the super admin writes any scope.

## D-1341 [back] — Per-country switches: one more layer of the disable list (written by B6)
`edu_countries.disabled_features` joins platform + organization. Every layer only adds keys, so a super-admin OFF still wins everywhere.

## D-1342 [back] — Games: content as data, idempotent plays, server-side stars, capped point rewards (written by B6)
Point rewards are off by default: points buy services (the live plan), so free points are a cost. Stars and badges are always on; points have a daily cap when switched on, checked in the play's own transaction.

## D-1343 [back] — A Quran offering is a course (`program_kind = 'quran'`); its rules are checked on every enrolment
Enrollment, payment, sessions, calendar and live are reused. Only the teacher's Quran profile and the progress log are new. The gender and verification rules apply to whoever creates the enrolment, the student or staff; `program_kind` is locked once a course has students.

## D-1344 [back] — Nahw and game answers ship to the device; attempts are idempotent on `client_id`
Low stakes; it gives instant feedback and works offline. Exams keep their server-side checking.

## D-1345 [back] — No Quran text in the app
Only surah names, ayah counts and juz boundaries, from Tanzil Quran Metadata v1.0 (CC BY 3.0, recorded in `data/learn_seed/quran_meta.json` and its README). Progress is numbers.

## D-1346 – D-1349 [front] — learn kit + games (1346), Quran (1347), module switches page (1348), nahw (1349)
One entry each, as the commit messages and the code comments already cite them.

## D-1351 — Offline-first v1: a generic outbox for four kinds; money is never offline
`game_play`, `nahw_attempt`, `quran_progress`, `study_profile`. The attendance and exam queues stay as they are and report into the same status.

## D-1352 — Conflicts: append-only kinds dedupe by client id; the profile is last-write-wins with a stale check
Simple and predictable. A rejected op is dropped and the screen refetches.

## D-1353 — `sqflite` (+ `sqflite_common_ffi` on desktop), no encrypted database
`sqflite` is already in the lock file. Drift and SQLCipher add build weight on six platforms. Instead: nothing sensitive is cached (no identity numbers, no addresses of others), paid files are AES-CTR encrypted, tokens stay in secure storage, logout wipes the database. The web build stays online-only.

## D-1360 — The Android release keystore already exists and is NOT regenerated
`~/.nextbrain-keys/nextbrain-release.jks` signs the installed apps (D-137). A new key would block every update. The brief's "generate a keystore" is met by the existing one; FINAL_REPORT reminds the owner to back it up.

## D-1361 — Windows ships an unsigned Inno Setup installer
MSIX needs a certificate to install at all. The Downloads page documents "More info → Run anyway".

## D-1362 — macOS and iOS are built on Codemagic, not this PC
Workflows and `docs/release/APPLE.md` are written; the builds wait for the owner's Apple Developer account. Logged as a gap, never blocking.

## D-1363 — No new update checker
`VersionCheckService` and `releases.json` already do it; Phase 9 only teaches them the new file kinds.

## D-1370 — Parent consent is a row with the text version, IP and time
Required for a student under the country's `minor_age` (data, default 18). Captured in Phase 3, enforced in Phase 10.

## D-1380 — Demo data is marked three ways and removed by one command
`is_demo` on new tables, `@demo.nextbrain.invalid` e-mails, a `demo` course tag. `seed_learning_hub_demo.py --remove` deletes only those.
