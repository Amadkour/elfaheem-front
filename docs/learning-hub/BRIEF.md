# Learning Hub job: the owner's brief (verbatim) + the context the lead collected

Received 2026-11-20. Worktrees: front `D:\platform\nextbrain\_wt\lh-front`, back `D:\platform\nextbrain\_wt\lh-back`, branch `feature/learning-hub` in both, cut from origin/production (front 72c211c4, back 7a1fd7f; core migrations at 0100).

## Context collected by the lead (facts, not instructions)

- **Part 1 evidence.**
  - Screenshot `ref/1.png`: an org admin on the web is in the new onboarding wizard (step 1 of 6, "الهوية"), adding a student: name أحمد محمد / Ahmed Mohamed, nationality مصري, national ID 29609221601851 (parsed: الغربية, 22 Sep 1996, male), email ahmed.mohamed@gmail.com, mobile 01110672299. The red banner reads "Something went wrong on our side. Please try again later".
  - The server's nginx access log has `POST /api/api/v1/org/orgs/1/onboarding/cases` → **500** twice, at 2026-11-20 04:45:34 and 04:45:47 UTC, right after a 200 on `GET …/onboarding/types`.
  - `docker logs edu_api` for that window printed nothing, so the traceback must be reproduced locally (the e2e harness under back `tests/org_v2/e2e_onboarding_*.py`) or found in another log.
  - The feature is the member-onboarding job (D-1200..D-1210, front `docs/onboarding/PLAN.md` + `CONTRACT.md`), live since 2026-11-19. The 500 may come from data only production has: org 1's real types and members, an existing user with that e-mail, `PII_KEY` now set (added 2026-11-20), presets seeded lazily on a real org, etc.
  - The "add teacher" / "add member" paths also open this wizard now (D-1210). The legacy forms remain behind the `org.onboarding` kill switch.
- **Reference apps.** `ref/2.png` shows the app icons: فهيم (Faheem), هدفك للقدرات, Abwaab, معلمي (Moalimy), AlGooru, GAGA. URLs:
  - https://www.faheemapp.com/
  - https://gaga-app.com/individual
  - https://play.google.com/store/apps/details?id=com.app.vclassesapp.hadafakforkodrat&hl=ar
  - https://abwaabegypt.com/
  - https://moalimy.com/
  - https://alrrabbaniyeenacademy.com/

  "Faheem" here is a competitor app, unrelated to the owner's separate Alfaheem product. NEVER put Alfaheem material into NextBrain.
- **Flow sheets** (handwritten, Saudi example), `ref/4.png` and `ref/5.png`:
  - Landing buttons: انضم كطالب / انضم كمعلم / أضف مؤسستك.
  - **(1) الدورات:**
    - قدرات (أدبي، علمي), GAT, قدرات بالإنجليزي
    - تحصيلي (أدبي: إدارة أعمال، شرعي؛ علمي: عام، هندسي، صحي), SAAT, STEP
    - تعلم الإنجليزية من الصفر حتى التأهيل الجامعي, تعلم المحادثة من الصفر حتى الاحتراف
    - قدرات جامعيين, قدرات معرفية, رخصة مهنية, مهارات الحاسب الآلي, دورات تطويرية
    - Each splits into حضوري (in-person, then city المدينة → district الحي) or عن بعد (remote, then مباشر live / مسجل recorded).
  - **(2) المواد الدراسية:**
    - روضة: تأسيس عربي / رياضيات / إنجليزي
    - ابتدائي: grades 1–6
    - متوسط: grades 1–3
    - ثانوي: grades 1–3
    - Each grade has subjects: تأسيس, قرآن, رياضيات, علوم, لغتي, إنجليزي, اجتماعيات, and in secondary also كيمياء, فيزياء, أحياء, قانون, فقه, حديث, توحيد, تقنية رقمية, نحو, كفايات لغوية.
    - دولي: Math, Science
    - جامعة: university name + college + subject → contact on WhatsApp
  - **(3) متجر الكتب والملخصات** by stage/grade/subject + قدرات/تحصيلي/STEP, marked قابلة للتعديل (editable).
  - **(4) ألعاب تعليمية**
  - **(5) تحفيظ القرآن** for all ages, رجال / نساء
  - **(6) تعلم النحو**
- **What already exists that overlaps this brief** (verify before planning; don't trust these notes blindly):
  - org academic levels / programs (`OrgProgram`, `academic_config.level_keys`)
  - courses with prices, `CourseListCard`, `CourseSpace`, the roadmap
  - subscriptions / course access (D-210..212)
  - billing and points, a Paymob contract
  - `VersionCheckService` (`GET /app/version-check`), app releases with a direct-download publisher (`scripts/release/`, D-137, D-143..146, owner's free runner `tools/runner/`), Codemagic for store uploads
  - offline video downloads + offline attendance / exam sync (`lib/core/offline/`), `AppConnectivity`
  - the landing site (`landing/`, Astro) at `/` with the app under `/app/`
  - kill switches per platform / org (`AppConfig.disableList`, `feature_catalog.py`)
  - the help system and the features guide
  - the design system (`lib/design/`)
- **Owner's standing rules** (from earlier sessions):
  - Token-saving: few agents per wave, short briefs and reports.
  - Run only the tests around the change + the analyzer on changed paths; never the full suites unless asked.
  - Commit with `git commit --only <paths>` (shared index). Never `dart format` existing files.
  - Keep the current theme: no new palettes.
  - UI quality is the top priority (render and look at it; verify in the real web app).
  - The owner delegates UX calls: "best practice, premium and smart", consolidate rather than delete.
  - Deploy: when work is merged to `production`, `D:/platform/nextbrain/back/.venv312/Scripts/python D:/platform/nextbrain/deploy/deploy.py backend --no-env-check`, then `… deploy.py frontend` (the web build takes >10 min).
  - Repo conventions: decisions go in front `docs/DECISIONS.md` as D-nnn (latest D-1210; reserve a block); a multi-session job keeps its own tracker (here `docs/learning-hub/PROGRESS.md`); every org API change goes in back `FLUTTER_API_CHANGES.md`; every user-facing feature goes in back `data/app_features_guide.json`; every kill switch goes in back `services/feature_catalog.py` + the snapshots.

---

## The owner's brief (verbatim)

# Task: Fix the "Add Student" Error, then Build Interactive Onboarding, Configurable Education Levels, Course Discovery, Student Home Tabs (Store, Educational Games, Quran Memorization, Arabic Grammar), and Native Offline-First Apps with Direct Download Distribution for the Educational App

## Autonomy Rules (read first)
Work from start to finish on your own. Don't stop for approval or questions.
- When a decision is unclear, choose the safest reasonable option, log it with the reason in `DECISIONS.md`, and continue.
- Keep `PROGRESS.md` updated after every step. If the session is interrupted or the context resets, read it first and resume from the last completed step.
- **Permissions and tooling:** if you need any permission, package, skill, SDK, or tool (browser automation, design skill, search skill, build toolchains), **install, enable, or configure it yourself** and continue. Log what you installed in `DECISIONS.md`. Use any skills you already have if they help, and log which ones.
- Back up before big changes and work in small, reviewable steps.
- If a step fails, retry once with a different approach, log it, and move on. Never let one blocked item (for example iOS signing) stop the rest of the work.
- Never commit secrets, keystores, or signing keys to the repository. Use environment variables or a secure secrets store.

## Tech Stack
- **Frontend: Flutter** (single codebase for web, Windows, Linux, macOS, Android, iOS).
- **Backend: Python.**
Follow the existing architecture, state management, and conventions already in the repo.

## Token-Saving Strategy (strict, applies to everything)
- **Fable (strongest model) is used ONLY for:** planning, architecture, critical decisions, reviewing the work of smaller models, and the final quality review. It must **not** do bulk coding, formatting, signing, builds, file generation, or any repetitive or mechanical work.
- **Small, cheap models or sub-agents do ALL execution:** screens, forms, routes, validators, translations, seed data, build configs, signing key generation, release scripts, lint and type fixes. Give each a short, self-contained brief with only the files and rules it needs. Never pass the whole conversation or codebase.
- For especially complex pieces (data model, search and filters, tax and payment logic, permissions, offline sync, release pipeline), Fable designs them, Claude-level help may be used for the hardest parts, and implementation stays with small models.
- Read only the files you need, avoid re-reading, keep outputs and logs short.
- **Testing is minimal:** write and run **only the necessary tests**: the core flow, payment and download protection, permissions, and offline sync. Nothing extra.

## Reference Material Rule (important)
I will provide images or documents showing the intended **flow and layout**. Some of them use **Saudi Arabia as the example**. Treat every such example as a **template, not a one-country spec**:
- Separate the **general logic** (steps, screens, behavior) from **country-specific details** (stage names, regions, cities, tax, currency, language labels, terminology).
- Everything shown for Saudi Arabia must work the **same way for Egypt**, and for any country added later, through configuration and data, never hardcoding.
- Log in `DECISIONS.md` how you generalized each example.

## Part 1: Fix the Error First
When I try to **add a new student to an organization**, the app shows an error. Screenshot: ref/1.png.
- Read the exact message and code, reproduce it, find the root cause (Flutter, Python API, validation, database, or permissions), and fix it with the smallest safe change. Verify it works.
- Check the add-teacher and add-member flows for the same bug.
- Log cause and fix in `DECISIONS.md`.

## Part 2: Research Reference Apps
Reference applications: see the URLs above. Flow images: ref/2.png, ref/4.png, ref/5.png.
- Study onboarding, education levels, course discovery and filters, booking, digital stores, Quran memorization, educational games, and Arabic grammar learning. Use browser automation if available to walk through the real flows.
- Search the web for the best platforms in this space.
- Write a concise comparison to `RESEARCH.md`: strengths, weaknesses, and implied requirements.
- The goal is a product **better, more polished, and more premium than all of them**. Keep research focused.

## Part 3: Configurable Education Levels
- Stages containing years or grades, fully **data-driven**, not hardcoded.
- **Pre-seeded defaults** (verify with a quick web check, not memory):
  - **Egypt:** nursery/KG, primary, preparatory, secondary, university, with real years.
  - **Saudi Arabia:** kindergarten/rawdah, primary, intermediate, secondary, university, with real years.
- **Super admin control:** add, remove, rename, or reorder a whole stage or a single year, and create a set for a new country.
- **Registration capture:** students give stage and year; teachers give the stages and years they teach; parents link children, each with a stage and year, and must give consent for minors.

## Part 4: Course Setup
- A course chooses the **stages and years** it serves, and can serve **multiple**.
- Delivery mode: **online**, **in-person**, or **both**.
- In-person courses store location (governorate/city and address).

## Part 5: Interactive Landing Page Flow
1. **"Join us as":** Student, Teacher, or Parent.
2. Student picks **stage and year**.
3. **Online or in-person?**
4. If in-person: a **location picker** with the real governorates and areas of the user's country (configurable), plus address.
5. Basic personal info, with minimal friction.
6. **Confirm** runs the **search** with the choices as filters and shows matching courses.
7. Opening a course: a **registered user** can book directly; a **non-registered user** is prompted to log in or sign up, then returns to the same course and completes the booking without losing their place.
8. The same filters (stage, year, delivery mode, location, subject) are available on the **Home Screen**.
9. Search and filters must stay fast with many courses: use proper database indexes.

## Part 6: Main Student Tabs
The student's main navigation includes these tabs, organized cleanly and consistently. The **super admin can enable or disable any tab per country or organization**.

**6.1 Digital Store (Books and Study Materials)**
- E-books, summaries, and study notes. Each item can optionally be tied to a stage and year, or left general, with an optional category.
- **Tax and currency** configurable per country (VAT differs between Egypt and Saudi Arabia). Show price with and without tax.
- **Protected downloads:** files are never publicly linkable. Access is granted only after payment, through secure expiring links, and recorded in a purchase history.
- Premium UX: browsing, filters, item pages, cart or quick purchase, and a "My Library" for purchased items.

**6.2 Educational Games**
- A tab of educational games, filterable by stage, year, and subject.
- A simple, extensible game framework (a game catalog plus a few starter games such as quizzes, matching, and memory games) with progress, scores, and rewards such as points and badges.
- No ads, and parents can see their child's progress.

**6.3 Quran Memorization (Tahfeez)**
- The student chooses a teacher and can **filter by teacher gender** (male or female).
- Session type: individual or group. Goal: memorization, tajweed, or revision.
- Simple progress tracking by surah and juz, with booking and scheduling that fit the existing course and booking system.
- **Constraints are light by default.** The following are **switches in the super admin settings, off or relaxed by default**, adjustable per country or organization:
  - Mandatory teacher verification and profile review.
  - Content review before publishing.
  - Gender matching rules between student and teacher (for example, same-gender only for minors).
  - Any other restriction added later.
- Never hardcode these rules. Implement them as configuration flags.
- Don't add Quran text or tafsir without a reliable source, keep it minimal, and log the source in `DECISIONS.md`.

**6.4 Arabic Grammar (Nahw)**
- Structured levels from beginner to advanced, with interactive exercises and instant feedback, not explanation only.
- Progress tracking per level and lesson, linkable to the student's stage and year.

## Part 7: Native Installable Apps, Offline-First, Direct Download

**Real installable apps, not a website wrapper.** Use Flutter's native builds from the same codebase.

**Offline-first behavior:**
- Data lives **locally on the device** (a local database such as SQLite via Drift or similar) so the app works without internet as much as practical.
- Actions taken offline are **saved in a local queue** and **synced automatically** when the connection returns, with sensible conflict handling.
- A visible **status indicator** showing "Working locally, offline" versus "Online", and "Syncing..." automatically when the connection comes back.
- Sensitive local data is stored securely, and paid downloads remain protected, with access rules still enforced by the server.
- The Python backend exposes sync-friendly endpoints (timestamps or versioning, idempotent writes).

**Direct download distribution (no app stores).** I do not want to wait for any app store. Every platform must have a **ready, installable build available for direct download now**, hosted by us:
- **Windows:** `.exe` or `.msix` installer. Sign it if a certificate is available; otherwise ship unsigned and document the SmartScreen "More info, Run anyway" steps.
- **Linux:** `AppImage` and `.deb`.
- **Android:** a properly **signed APK** (and AAB), a real native app and not a TWA or web wrapper, with install instructions for allowing unknown sources.
- **macOS:** `.dmg`. Sign and notarize if an Apple Developer account is available; otherwise ship unsigned and document the right-click, Open steps for Gatekeeper.
- **iOS:** Apple does not allow normal direct installs outside the App Store. Build the release pipeline for **TestFlight first** (a public link, fastest route), keep **Ad Hoc** as an option for registered devices, and document exactly what I must provide from my Apple Developer account. Do not block other work on it.

**Android signing (do it yourself):**
- A **small model** generates the Android signing keystore, configures Flutter's release signing, and builds the signed APK and AAB. Do not ask me for anything.
- Store the keystore and its passwords **outside the repository** (for example in a local `secrets/` folder that is gitignored, or environment variables), and record where they are in `FINAL_REPORT.md`, never the passwords inside the repo.
- Remind me in `FINAL_REPORT.md` to **back up the keystore safely**, since losing it means I can never publish updates to the same app.

**Downloads page and release process:**
- A clean, premium **Downloads page** on our website with a button per platform, version number, file size, release date, and a short install guide. Auto-detect the visitor's device and highlight the right download.
- Host files on our own server or object storage with stable URLs, and publish a **SHA-256 checksum** next to each file.
- One script builds all artifacts, uploads them, and updates the version and links. Add a short `BUILD.md`.
- **In-app update checker:** the app reads a small version file from our server and shows an "Update available" prompt linking to the right download.

## Part 8: Privacy and Permissions
- Student data, especially minors, and addresses are sensitive: enforce role-based access and expose only what each role needs.
- Parent consent for minors, and an audit trail for sensitive actions.

## Part 9: Seed Data
Create ready-made demo data (students, teachers, parents, courses across levels, store items, games, Quran teachers of both genders, and grammar lessons) so the whole flow can be tried immediately. Mark it clearly as demo data so it can be removed easily.

## Part 10: Phased Delivery
Execute in this order, verifying each phase before the next:
1. Fix the add-student error.
2. Education levels system.
3. Registration capture and course setup.
4. Landing page flow, search, and home filters.
5. Digital store, tax, and protected downloads.
6. Educational games, Quran memorization, and Arabic grammar tabs, with super admin switches.
7. Offline-first and sync.
8. Native builds for all platforms, including Android signing.
9. Direct download builds, Downloads page, and update checker.
10. Privacy polish and seed data.

## Final Quality Gate (Fable reviews)
- The core flow works end to end: landing page, choices, search, course, login, booking, and store purchase.
- Permissions and protected downloads behave correctly.
- Education levels are editable by the super admin and drive every screen.
- Every tab can be enabled or disabled by the super admin, and all Quran rules are configurable switches.
- Offline actions queue and sync correctly, and the status indicator is accurate.
- Each platform has a real installable artifact on the Downloads page with a checksum, and the Android APK is properly signed.
- Saudi examples were generalized: Egypt works with the same logic and nothing is hardcoded to one country.
- The UI is consistent, premium, and RTL/Arabic and English friendly.
- Only the necessary tests exist, and they pass.

Finish by writing `FINAL_REPORT.md`: what was built, what was installed, key decisions, where the signing keystore is stored (not its passwords), and a short list of the steps that truly need my accounts (Apple Developer, any paid signing certificates).

## Constraints
- Follow the existing design system, code conventions, and architecture.
- Don't break existing functionality.
- Make minimal, reviewable changes.
- Don't hardcode country-specific rules; keep them configurable.
- Do not ask me questions. Decide, log, and continue until the end.
