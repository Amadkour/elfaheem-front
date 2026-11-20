# Learning Hub — plan

Branch `feature/learning-hub` in both worktrees (`_wt/lh-front`, `_wt/lh-back`). Contract: `CONTRACT.md`. Tracker: `PROGRESS.md`. Decisions: `DECISIONS_DRAFT.md` (D-1300+). Brief: `BRIEF.md`.

Rules for every agent (the lead pastes this line under each brief): *work only in the files you own; read `CONTRACT.md` §<n> first; no `dart format`; UI from `lib/design/` with tokens, `context.colors`, `t(ar,en)` / `translation.json` in both languages; new widgets pass `expectNoLayoutErrors`; run only your own tests + `flutter analyze --no-fatal-infos --fatal-warnings <paths>`; back: Python 3.12, `PYTHONUTF8=1`, per-script SQLite `DATABASE_URL`; do not commit; report ≤ 120 words (files, tests run, open points).*

## 1. Inventory: what exists, what each part builds on

| Brief part | Already there (verified in code) | The job does |
|---|---|---|
| Add-student 500 | `features/org/onboarding/` (0099), wizard `lib/features/org/onboarding/` | One-column fix (§2) |
| Education levels | `student_study_profiles` (0077: `stage`, `grade`, `track`, `governorate`, `city`) with **hard-coded** `STAGES` / `TRACKS` / `GOVERNORATES` in `features/profiles/student_profile_service.py`; front `lib/features/profile/study_profile/`, admin `admin_study_profile_settings_page.dart`; `users.country` (free text); org side `OrgProgram` / `academic_config` (untouched) | Tables replace the constants; the same keys are seeded so old rows and old apps keep working |
| Courses | `courses` (`type` live / recorded / both, `category_id`, `currency` SAR/EGP/USD, `level`, `tags`), `categories` (parent → child), `GET /courses` (`search`, `category_id`, `mode=any|online|center` where center = an organization course), `CourseListCard`, `CourseSpace`, course profile | New columns + `course_targets`; new query params on the SAME route |
| Landing / guest | Astro `landing/` (`Landing.astro`, `scripts/landing.ts`, `data/remote.ts`); `GET /public/landing/{stats,options,match,highlights}` (cached, rate limited); app: `lib/features/onboarding/` (`guest_search_screen`, `explore_launcher`, `start_route`), `GuestState` / `GuestGuard`, `DeepLinkService` `/c/<id>` | The guest search grows into the join flow; a pending-intent store adds the hand-off |
| Booking | Enrollment + checkout (`features/billing/payment_service.py`, `api/checkout.py`), manual transfer, subscriptions, course access grants | "Book" = the existing enroll / pay flow (D-1322) |
| Payments, points | `payment_providers/` (Moyasar, Paymob), `payment_webhook_service.py`, `payments` (course-bound: `course_id NOT NULL`), points wallet + ledger + **card top-up by token** (`points_service.start_card_checkout` / `card_topup_by_token`) | Store orders copy the top-up card pattern and use `points_service.debit` |
| Private files | `features/storage/private_storage.py` (`put_bytes`, `signed_url`, TTL), presigned uploads | Store files live there; a token route in front |
| Kill switches | `feature_catalog.py`, `feature_policy.effective_disable_list` (platform + org chain), `AppConfig.disableList`, `student_tab_*` keys, `OrgPlatformPrefs.disabled_features` | A country layer + `module_settings` for rule flags |
| Offline | `lib/core/offline/` (connectivity, AES-CTR offline videos), offline attendance + exam sittings with their own queues, `topRouteObserver` reconnect hook; `sqflite` already in `pubspec.lock` (transitive) | A generic outbox + read cache + status chip; the old queues report into the same status |
| Releases | `scripts/release/` (`publish_release.py`: 3 signed APKs, `releases.json` with size + SHA-256; `build_linux.sh` / `package_linux.sh`: .deb + .tar.gz), `tools/runner/`, `codemagic.yaml` (android-store, android-website, ios-store, web, linux, windows zip), `features/platform/app_release_*` + `GET /app/downloads`, **release keystore `~/.nextbrain-keys/nextbrain-release.jks` already exists** | Windows installer, AppImage, AAB, macOS / iOS workflows, the Downloads page |
| Update check | `VersionCheckService` (manifest + `GET /app/version-check`, `desktop_check`), `GetAppBanner`, `AppDownloadBanner` | Verify on desktop; no new checker |
| Parents | `features/parents/parent_link_service.py` (links to student accounts); no consent record | `parent_consents` |

## 2. Phase 1 diagnosis (the add-student 500)

**Pinpointed by reading.** `data/onboarding_models.py:93` and `migrations/versions/0099_member_onboarding.py`: `nid_kind = String(10)`. `service._set_nid` writes `"national_id"`, which is **11 characters**. PostgreSQL rejects it (`value too long for type character varying(10)`) at the autoflush inside `duplicates()` → unhandled `DataError` → 500 `server_error`. SQLite ignores VARCHAR lengths, so every e2e passes. `"passport"` (8) fits, so only Egyptians with a national ID fail: exactly the screenshot. Add-teacher and add-member create the same case row, so they fail the same way.

Ranked hypotheses (the agent confirms #1 on PostgreSQL first, then rules out the rest):
1. `nid_kind` VARCHAR(10) overflow (above). Near certain.
2. Another short column on the same path with a real-world value (`org_audit_log.entity` = `"onboarding_case"`, `action`, `org_case_events.kind`, `source`): check every literal against its column width.
3. An existing `users` row with the same e-mail: affects `activate` / `approve_now`, not the draft create; test anyway.
4. `PII_KEY` set to a value that is not a Fernet key: `_fernet_for` hashes it, so it works; a key CHANGE makes old `nid_enc` undecryptable (`decrypt` → None, then `UserIdentityValue.norm == None`): no 500, but duplicate detection silently stops. Report, don't fix here.
5. A swallowed failing query (`approver_ids` has `except Exception`) leaves a PostgreSQL transaction aborted, so the next query 500s. Only if something fails first.

Why `docker logs` was empty: `server_error_response` logs with `log.error` and returns `ref` (also header `X-Request-Id`). The agent finds where the `helpers.error_handling` logger writes in production (file handler / level) and says how to read a ref.

## 3. Architecture

### 3.1 Education levels (country-configurable)
`edu_countries` (currency, VAT, minor age, geo level labels, `disabled_features`) → `edu_stages` → `edu_grades` (+ optional `tracks`); `edu_subjects` + `edu_grade_subjects` (which subjects a grade offers); `geo_areas` (2 levels, a self-FK: EG governorate → city / area, SA city → district; the labels of each level are data on the country). One read `GET /edu/catalog?country=XX` (public, cached 300 s, ETag) feeds every picker; the super admin edits through `/admin/edu/…`. Seeds are JSON files (`back/data/edu_seed/EG.json`, `SA.json`) loaded by an idempotent seeder that never overwrites an edited row. The EG stage keys equal the old `STAGES` keys and the EG level-1 area keys equal the old `GOVERNORATES` codes, so `student_study_profiles.stage / grade / governorate` stay valid and are still written (old apps read them). Deleting a stage or grade in use = soft (`active=false`). Test-prep families (قدرات, تحصيلي, STEP, GAT, SAAT, professional licence, …) stay **categories** (`categories.country_code` added), not stages.

### 3.2 Course targeting, delivery, location, search
`courses` gains `country_code`, `delivery_mode` (online | in_person | both), `subject_id`, `area_id` (leaf), `area_parent_id` (denormalised level 1), `address`. `course_targets (course_id, stage_id, grade_id NULL = the whole stage)`. Remote sub-mode (مباشر / مسجل) is the existing `courses.type`. `GET /courses` gains `country, stage_id, grade_id, subject_id, delivery, kind, area_id` (an `area_id` of level 1 matches `area_parent_id`). The filter is `EXISTS` on `course_targets`. Indexes: `course_targets (grade_id, course_id)`, `(stage_id, course_id)`; `courses (country_code, delivery_mode)` partial on `is_published`, `(area_parent_id)`, `(area_id)`, `(subject_id)`; PostgreSQL only: `pg_trgm` GIN on `name_ar`, `name_en` for `search` (skipped with a log when the extension cannot be created). The public list shows the area names; the full address only to the teacher, staff and enrolled students (D-1321).

### 3.3 Landing flow and the hand-off
Astro landing: four entry buttons (Student, Teacher, Parent, Add your organization) → `/app/join?role=…`. The flow itself is ONE Flutter screen set (`lib/features/onboarding/join/`), so web and native share it: role → country (default from the platform setting, changeable) → stage + grade → online / in-person → area (+ optional address text) → name + phone (skippable) → confirm → the existing explorer with the filters applied. The choices live in `JoinDraft` (SharedPreferences). `guest_search_screen` stays as the "skip, just browse" entry and opens the same explorer.
Hand-off: `PendingIntent` (`lib/core/routing/pending_intent.dart`, SharedPreferences, 24 h TTL): `{kind: book_course | buy_store_item, id, plan, filters}`. `GuestGuard` writes it before opening login / register; `MyAuthProvider` calls `PendingIntent.resume()` after a sign-in or a finished registration (also after a full page reload: Google sign-in on web); it opens the course profile and its checkout sheet, then clears. Registration prefills from `JoinDraft` and saves the study profile.

### 3.4 Store: tax, payment, protected downloads
`store_items` (file in `private_storage`, cover public), `store_orders` + `store_order_items` (price / VAT snapshots), `store_library`, `store_download_grants`. Tax = `edu_countries.vat_percent` + `prices_include_vat`, per item `vat_exempt`; Decimal, ROUND_HALF_UP, one pure function `store_tax.quote(items, country)` used by the item page, the cart and the order. The cart is client-side; the order is created with item ids and an `Idempotency-Key`.
Payment: card = the points top-up pattern (`checkout_token`, provider verify, one gateway transaction pays one order, webhook + redirect both land in ONE `store_orders.settle(order)` that locks the row and is safe to call twice); points = `points_service.debit(ref_type='store_order')` in the same transaction; free = settled at once. `payments` is not reused (course-bound).
Download: `POST /store/library/{item}/download` checks the library row, a per-user daily limit and device, writes a grant (token hash, 120 s) → `GET /store/dl/{token}` (no auth header needed, single use) answers 302 to a 60 s `private_storage.signed_url`. `file_ref` never appears in any JSON. Native apps keep the file AES-CTR encrypted (the offline-video scheme) and open it in-app under `ScreenSecurity.protect`; the web opens the short link.

### 3.5 Games, Quran, nahw, switches
- **Switches.** Tabs are kill-switch keys (`student_tab_store|games|quran|nahw`). A country layer joins the effective list: `edu_countries.disabled_features` (signed-in: the study profile's country; guest: `?country=`). Rule flags (not hide / show) are `module_settings (module, scope platform | country | org, scope_key, values)`; a code registry holds the defaults; resolution = defaults ← platform ← country ← org.
- **Games.** `games` (engine quiz | match | memory | order + `config` JSON content), `game_plays` (append-only, `client_id`), `game_progress`, `badges` / `user_badges`. Flutter: a `GameEngine` registry; content is data. Point rewards go through `points_service.credit`, OFF by default with a daily cap (points buy services). Parents read `GET /parent/children/{id}/games`.
- **Quran.** A tahfeez offering IS a course (`courses.program_kind = 'quran'`), so enrollment, payment, sessions, calendar and live are reused. `quran_teacher_profiles` (gender, goals, session types, verification), `quran_progress` (surah, ayah range, kind, grade; juz derived). Flags: `teacher_verification_required`, `content_review_required`, `gender_matching` (off | minors_same_gender | same_gender), all off. No Quran text: only surah names, ayah counts and juz boundaries (Tanzil metadata, D-1345).
- **Nahw.** `nahw_levels` → `nahw_lessons` → `nahw_exercises` (mcq | fill | order | classify), `nahw_progress`. Answers ship with the lesson: instant feedback, works offline. Games and nahw share the exercise widgets (`lib/features/learn_kit/`).

### 3.6 Offline-first sync (what is realistic)
New `lib/core/offline/sync/`: `LocalDb` (`sqflite`; `sqflite_common_ffi` on Windows / Linux; a memory stub on web, which stays online-only), `ReadCache` (GET snapshots: edu catalog, home, my courses, library, games, nahw, quran progress), `Outbox`, `SyncEngine` (runs on reconnect through `topRouteObserver`, on resume and after an enqueue; sequential, backoff), `SyncStatus` (offline | online | syncing + pending count) drawn by `SyncStatusChip` in `AppShell`. The existing attendance and exam queues are NOT rewritten: they report their pending counts into `SyncStatus`.
Writable offline v1: `game_play`, `nahw_attempt`, `quran_progress`, `study_profile`. Never offline: money, purchases, enrollment, anything an admin approves.
Server: `POST /sync/push` (ops with a client UUID; `sync_ops` unique `(user_id, op_id)` → `applied | duplicate | rejected`), `GET /sync/pull?since=`. Conflicts: append-only kinds cannot conflict (dedupe by id; aggregates recomputed with max); `study_profile` is last-write-wins with `base_updated_at` → `stale` = the client drops the op and refetches. Local data: tokens in secure storage (as today), no identity numbers cached, paid files encrypted, the DB wiped on logout (D-1352).

### 3.7 Release pipeline per platform
| Platform | Today | Added | Built where |
|---|---|---|---|
| Android | 3 signed APKs published | AAB built and kept in `build/releases/` (not published) | this PC |
| Windows | zip | Inno Setup `.exe` installer (unsigned + SmartScreen steps) | this PC |
| Linux | .deb + .tar.gz | AppImage | server / WSL (`build_linux.sh`) |
| macOS | none | `macos-website` Codemagic workflow → unsigned `.dmg` | **needs a Mac**: Codemagic minutes |
| iOS | `ios-store` workflow | TestFlight lane + Ad Hoc notes | **needs the Apple Developer account** |
One command: `scripts/release/build_all.py` wraps `publish_release.py`; each platform it cannot build here is printed as `SKIPPED (reason)` and logged, never an error. Downloads page: `landing/src/pages/{ar,en}/download.astro`, reading `releases.json` at runtime.

## 4. Phases

Model per agent in brackets. Review checkpoint = the lead calls the planner with the diff summary + test output before the next phase.

### Phase 0 (parallel with Phase 1) — research · 1 agent
- **R1 [sonnet]** owns `docs/learning-hub/RESEARCH.md`. Brief: "Read BRIEF.md 'Reference apps' and look at ref/2.png. Visit each URL (WebFetch; browser automation if available) plus 3 more leading Arabic K-12 / tutoring platforms you find by search. Write RESEARCH.md ≤ 120 lines: a table per app (onboarding, levels, discovery + filters, booking, store, Quran, games, grammar), strengths, weaknesses, then 'Implied requirements' as a numbered list tagged with the phase (2–6) it affects. Also verify with official sources and append: Egypt and Saudi school stages + grade counts, Egypt VAT and Saudi VAT rates and whether books are exempt. Never mention or use Alfaheem."

### Phase 1 — fix the add-student error · 1 agent
- **A1 [sonnet]** owns back `data/onboarding_models.py`, `migrations/versions/0101_*.py`, `tests/org_v2/e2e_onboarding_prod_case.py`, `FLUTTER_API_CHANGES.md` (one line). Brief: "PLAN.md §2 has the diagnosis. (1) Write `tests/org_v2/e2e_onboarding_prod_case.py` (copy the harness of `e2e_onboarding_a.py`): `PII_KEY` set to a non-Fernet 40-char string, an existing user with gmail `ahmed.mohamed@gmail.com`, then `POST /orgs/{o}/onboarding/cases` with `type_key` student and fields `{full_name:'أحمد محمد', name_en:'Ahmed Mohamed', nationality:'EG', national_id:'29609221601851', nid_kind:'national_id', birth_date:'1996-09-22', gender:'m', email:'ahmed.mohamed@gmail.com', phone:'01110672299'}`; repeat for the teacher and staff types; then submit + approve_now. Run it on SQLite AND on the PostgreSQL test container (`postgresql://nbtest:nbtest@localhost:55432/nbtest`, it wipes schema public); it must fail on PostgreSQL before the fix. (2) Fix: `nid_kind` → `String(20)` in the model and a new migration 0101 (`alter_column`, idempotent, downgrade too). (3) Compare every string literal written to the onboarding tables and to `org_audit_log` on these paths with its column width; widen in the same migration if any overflows. (4) Find where `helpers.error_handling.api_errors` log output goes in production and write the one command to read a `ref`. Report the PostgreSQL traceback before and the passing run after."
- Tests: the new e2e on PostgreSQL + `e2e_onboarding_a.py` on SQLite. Done: 201 for the three types on PostgreSQL. Review: the traceback and the migration.

### Phase 2 — education levels · 4 agents
- Wave A: **B1 [sonnet]** owns back `data/edu_models.py`, `features/edu/` (service, seeder, `api/edu_router.py`, `api/admin_edu_router.py`), `migrations/versions/0102_*`, router registration, `tests/learning_hub/e2e_edu.py`. Brief: "Build CONTRACT §2 exactly. Seeder loads `data/edu_seed/*.json`, inserts missing rows only. Admin routes need the super admin guard used by `features/platform/api/platform_settings_router.py`. `student_profile_service`: read stages / tracks / governorates from the tables, keep the constants as the fallback when the tables are empty. Size every String column for its longest value (PostgreSQL enforces lengths)." · **B2 [haiku]** owns back `data/edu_seed/EG.json`, `SA.json`. Brief: "Write the two seed files in the shape of CONTRACT §2.4 from RESEARCH.md's verified stages. EG stage keys MUST be `kg, primary, preparatory, secondary, university` (+ existing `graduate`, `other`) and level-1 area keys MUST equal `GOVERNORATES` in `features/profiles/student_profile_service.py`. SA: `kg, primary, intermediate, secondary, university`, 13 regions' main cities with districts for Riyadh, Jeddah, Makkah, Madinah, Dammam. Subjects from BRIEF.md flow sheet (2). Arabic + English names."
- Wave B: **F1 [sonnet]** owns `lib/core/edu/` (`edu_catalog.dart` service + models, cached), `lib/design/edu_pickers.dart` (`EduStageGradePicker`, `EduAreaPicker`, `EduCountryPicker`), tests. · **F2 [sonnet]** owns `lib/features/admin/edu/` (super admin page: countries, stages, grades, subjects, areas; add / rename / reorder / deactivate; new country = copy from another), its dashboard entry, help id, translations.
- Tests: `e2e_edu.py` (seed idempotent, CRUD, reorder, a non-admin gets 403, old profile keys still validate); layout harness for the pickers. Done: the admin page edits a stage and the picker shows it. Review: the data model + the seeds.

### Phase 3 — registration capture and course setup · 3 agents
- Wave A: **B3 [sonnet]** owns back `migrations/versions/0103_*`, `data/` additions of CONTRACT §3, `features/profiles/student_profile_service.py`, `features/edu/teacher_levels.py`, `features/parents/consent_service.py` + routes, `features/courses/` create / update / response (targets, delivery, location), tests. Brief: "CONTRACT §3. Keep every old field working; `mode=center` keeps its meaning."
- Wave B: **F3 [sonnet]** owns `lib/features/auth/additional_register_screen.dart` (+ a new `register_levels_step.dart`), `lib/features/profile/study_profile/`, parent child-link UI with the consent checkbox. · **F4 [sonnet]** owns the course form under `lib/features/courses/teacher/` (targets multi-select, delivery mode, area + address), the course profile's "Who it's for / Where" block.
- Tests: back e2e (student, teacher, parent + consent, course with 2 targets, in-person without area → 422). Done + review: the three registrations and one in-person course in the real web app.

### Phase 4 — landing flow, search, home filters · 4 agents
- Wave A: **B4 [sonnet]** owns `features/courses/course_service.py` + `api/courses.py` (the new filters), `migrations/versions/0104_*` (indexes), `features/platform/api/public_landing_router.py` (`/options` v2, `/match` params), `tests/learning_hub/e2e_course_search.py` (+ an EXPLAIN check on PostgreSQL with 20 k seeded courses). · **F5 [sonnet]** owns `lib/features/onboarding/join/`, `lib/core/routing/pending_intent.dart`, the hooks in `GuestGuard` and `MyAuthProvider`, route `/join`, tests (`pending_intent_test.dart`: saved, resumed once, expired). · **L1 [haiku]** owns `landing/src/components/Landing.astro`, `landing/src/i18n/`, `scripts/landing.ts`: the four entry buttons → `/app/join?role=`.
- Wave B: **F6 [sonnet]** owns `lib/features/courses/course_filters.dart` (ONE filter bar: stage, grade, subject, delivery, area) used by the explorer and the student home (`home_screen.dart` slot), filters remembered per user.
- Tests: search e2e; pending-intent unit test; one Playwright walk: landing → join → results → course → login → back on the same course's checkout. Review: that walk's screenshots.

### Phase 5 — store, tax, protected downloads · 3 agents
- Wave A: **B5 [sonnet]** owns back `data/store_models.py`, `features/store/` (`store_tax.py`, `store_service.py`, `orders.py`, `downloads.py`, `api/`), `migrations/versions/0105_*`, webhook dispatch line in `payment_webhook_service.py`, `tests/learning_hub/e2e_store.py`. Brief: "CONTRACT §5 and PLAN §3.4. `settle` is idempotent under a row lock. Tests: tax EG 14 % / SA 15 % inclusive + exclusive + exempt; card settle twice = one library row; amount or currency mismatch = not settled; points debit fails → no library row; download without a library row 403; token single use; expired token 410; `file_ref` absent from every response; another user's token 403."
- Wave B: **F7 [sonnet]** owns `lib/features/store/` student side (tab, browse + filters, item page with price net / VAT / gross, cart, checkout sheet, My Library, in-app reader), `student_tab_store`. · **F8 [sonnet]** owns `lib/features/store/manage/` (super admin / teacher: items CRUD, upload to private storage, review queue) and the country VAT fields on the Phase 2 admin page.
- Review: the planner reads `orders.py` and `downloads.py` itself.

### Phase 6 — games, Quran, nahw, switches · 6 agents
- Wave A: **B6 [sonnet]** owns `features/platform/module_settings.py` + routes, the country layer in `feature_policy.py` / theme response, catalog keys, `features/games/`, migration 0106. · **B7 [sonnet]** owns `features/quran/`, `features/nahw/`, migration 0107, `e2e_quran_rules.py`. · **S1 [haiku]** owns `back/data/learn_seed/` (surah metadata from Tanzil, 3 nahw levels × 3 lessons × 5 exercises, 6 starter games).
- Wave B: **F9 [sonnet]** `lib/features/learn_kit/` + `lib/features/games/` (tab, 3 engines, progress, badges, parent view). · **F10 [sonnet]** `lib/features/quran/` (teacher list with gender / goal / session filters, teacher profile, book = course checkout, progress by surah and juz, teacher's record sheet). · **F11 [sonnet]** `lib/features/nahw/` + `lib/features/admin/modules/` (switches per country / org, the Quran flags).
- Tests: permissions only (flags resolve org > country > platform; `gender_matching` blocks when on, allows when off; a tab key in a country's list hides it; a parent sees only a linked child). Review: the switch model + the phone layout of 9 tabs (D-1340).

### Phase 7 — offline-first and sync · 3 agents
- Wave A: **B8 [sonnet]** `features/sync/` + migration 0108 + `e2e_sync.py` (same op twice = duplicate; stale profile rejected; a foreign user's op rejected). · **F12 [sonnet]** `lib/core/offline/sync/` + `SyncStatusChip` in `AppShell` + logout wipe + tests with a fake clock and a fake API (queue survives restart, drains in order, retries, status transitions).
- Wave B: **F13 [sonnet]** wires games, nahw, quran progress, study profile and the read caches; offline library files.
- Review: the planner reads `sync_engine.dart` and `features/sync/service.py`.

### Phase 8 — native builds · 3 agents
- **N1 [haiku]** Android: verify `~/.nextbrain-keys` works, do NOT create a keystore (D-1360), add `--aab` to `publish_release.py`, build APK + AAB, print `apksigner verify`. · **N2 [sonnet]** Windows: `windows/installer/nextbrain.iss`, Inno Setup install (winget), `scripts/release/package_windows.ps1`, the runner + `codemagic.yaml` `windows-website` step, `sqflite_common_ffi` check on a real run. · **N3 [sonnet]** Linux AppImage in `package_linux.sh`; `macos-website` + `ios-testflight` workflows in `codemagic.yaml`; `docs/release/APPLE.md` (what the owner provides).
- Done: files exist in `build/releases/<v>/` for Android + Windows; Linux on the server; macOS / iOS logged as gaps. No tests.

### Phase 9 — downloads page, publish, update check · 3 agents
- **L2 [sonnet]** `landing/src/pages/{ar,en}/download.astro` + component (device detect, version, size, date, SHA-256, install guides incl. SmartScreen / unknown sources / Gatekeeper). · **N4 [haiku]** `scripts/release/build_all.py`, manifest entries for the new file kinds (`release_manifest.py`, `releases_manifest.dart`), `docs/release/BUILD.md`. · **N5 [haiku]** `VersionCheckService` on Windows / Linux / macOS: the offer picks the installer; unit test for the three platforms.
- Review: the live page after the lead publishes.

### Phase 10 — privacy polish and seed data · 3 agents
- **B9 [sonnet]** privacy pass: each new response per role (address, phone, dob, child data), consent enforced for minors, audit rows for sensitive actions (CONTRACT §8), `e2e_privacy.py`. · **S2 [haiku]** `scripts/dev/seed_learning_hub_demo.py` (+ `--remove`; every row tagged demo, D-1380). · **D1 [haiku]** `app_features_guide.json`, help ids, `FLUTTER_API_CHANGES.md`, contract snapshots, `docs/learning-hub/FINAL_REPORT.md`.
- Final gate: the planner runs the brief's quality gate list against the real web app.

## 5. D-number block
Reserve **D-1300 – D-1399**: 1300–1309 job + Phase 1 · 1310–1319 levels · 1320–1329 courses, landing · 1330–1339 store · 1340–1349 tabs, games, Quran, nahw · 1350–1359 offline · 1360–1369 releases · 1370–1379 privacy · 1380–1389 seed data · 1390–1399 spare.

## 6. Risks
- **macOS / iOS cannot be built on this Windows PC.** Write the workflows and `APPLE.md`, mark `SKIPPED` in `build_all.py`, list in FINAL_REPORT. The Downloads page shows "coming soon" for a platform with no manifest entry. Never blocks a phase.
- **Windows signing**: no certificate → unsigned installer + documented SmartScreen steps.
- **SQLite hides PostgreSQL errors** (Phase 1's cause). From now on the lead runs each phase's e2e once on the PostgreSQL container before merging.
- **New packages** (`sqflite_common_ffi`): check `pubspec.lock` gains only that; if it downgrades anything, fall back to a JSON-file store behind the same `LocalDb` interface.
- **Nine student tabs on a phone**: decided at the Phase 6 review (D-1340).
- **Store teacher payouts** are out of v1 (D-1334). **Legal**: VAT rates and book exemption come from RESEARCH.md's sources and stay editable.
- **Old apps**: every changed route keeps its old fields; the contract test snapshots are regenerated per phase.
- **Scope**: if a phase overruns, cut in this order: badges, AppImage, store review queue, nahw `classify` exercises.

## 7. Needs the owner's accounts
Apple Developer (TestFlight, notarised .dmg), Codemagic macOS minutes, a Windows code-signing certificate (optional), payment gateway live keys for the store's currency per country.
