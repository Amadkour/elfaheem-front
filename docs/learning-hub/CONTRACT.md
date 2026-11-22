# Learning Hub — contract

Core Alembic is at 0100. All routes are under `/api/v1`. Errors use the existing coded shape (`code`, `message`, `message_en`). Times are naive UTC. Every `String` is sized for its longest value: PostgreSQL enforces lengths, SQLite does not (Phase 1). `names` below = `name_ar String(120)`, `name_en String(120)`; `std` = `sort Integer default 0`, `active Boolean default true`, `created_at`, `updated_at`.

## 1. Phase 1 — migration 0101
`org_onboarding_cases.nid_kind` `String(10)` → `String(20)` (+ any column the audit of literals finds). No API change.

## 2. Phase 2 — education levels (migration 0102)

### 2.1 Tables
| Table | Columns |
|---|---|
| `edu_countries` | `code String(2) PK`, names, `currency String(3)`, `vat_percent Numeric(5,2) default 0`, `prices_include_vat Boolean default true`, `minor_age SmallInteger default 18`, `phone_code String(6)`, `geo_labels JSON` (`{"1": {ar, en}, "2": {ar, en}}`), `disabled_features JSON default []`, `contact_whatsapp String(20) NULL`, std |
| `edu_stages` | `id`, `country_code FK`, `key String(40)`, names, `kind String(20)` (school \| university \| international \| other), `has_grades Boolean`, `contact_only Boolean default false` (university: collect name + college + subject, then WhatsApp), std; unique `(country_code, key)` |
| `edu_grades` | `id`, `stage_id FK CASCADE`, `key String(40)`, names, `number SmallInteger`, `tracks JSON NULL` (`[{key, name_ar, name_en}]`), std; unique `(stage_id, key)` |
| `edu_subjects` | `id`, `country_code FK NULL` (NULL = every country), `key String(40)`, names, std; unique `(country_code, key)` |
| `edu_grade_subjects` | `grade_id FK CASCADE`, `subject_id FK CASCADE`, PK both |
| `geo_areas` | `id`, `country_code FK`, `parent_id FK geo_areas NULL`, `level SmallInteger` (1 \| 2), `key String(60)`, names, std; unique `(country_code, parent_id, key)`; index `(country_code, level, parent_id)` |
`categories` + `country_code String(2) NULL` (NULL = all).

### 2.2 Public
- `GET /edu/countries` → `[{code, name_ar, name_en, currency, vat_percent, prices_include_vat, geo_labels}]` (active only).
- `GET /edu/catalog?country=EG` → `{country, stages: [{id, key, name_ar, name_en, kind, has_grades, contact_only, grades: [{id, key, name_ar, name_en, number, tracks, subject_ids}]}], subjects: [{id, key, name_ar, name_en}], version}`; `ETag` = version; cache 300 s.
- `GET /edu/areas?country=EG&parent_id=` → `[{id, key, name_ar, name_en, level, has_children}]`.

### 2.3 Super admin (`/admin/edu`, super admin only; each write audited and bumps the catalog version)
`GET /admin/edu/countries` (incl. inactive) · `POST /admin/edu/countries {code, …, copy_from?}` · `PATCH /admin/edu/countries/{code}` · `POST|PATCH|DELETE /admin/edu/stages[/{id}]` · `POST|PATCH|DELETE /admin/edu/grades[/{id}]` · `POST|PATCH|DELETE /admin/edu/subjects[/{id}]` · `PUT /admin/edu/grades/{id}/subjects {subject_ids}` · `POST|PATCH|DELETE /admin/edu/areas[/{id}]` · `PUT /admin/edu/order {entity: stages|grades|subjects|areas, ids: []}`.
`DELETE` = hard when unused, else `active=false` and the answer says `{deactivated: true, in_use: n}`. Codes: `edu_key_taken` 409, `edu_not_found` 404, `edu_country_unknown` 422.

### 2.4 Seed file (`back/data/edu_seed/XX.json`)
`{country: {…}, stages: [{key, name_ar, name_en, kind, has_grades, grades: [{key, name_ar, name_en, number, tracks?, subjects: [subject_key]}]}], subjects: [{key, name_ar, name_en}], areas: [{key, name_ar, name_en, children: [{key, name_ar, name_en}]}]}`.

Kill switch: `admin.edu_levels` (the admin page).

## 3. Phase 3 — registration and course setup (migration 0103)

| Table | Change |
|---|---|
| `student_study_profiles` | + `country_code String(2) NULL`, `stage_id FK NULL`, `grade_id FK NULL`, `area_id FK geo_areas NULL`, `gender String(1) NULL`. `stage` / `grade` / `governorate` are still written (stage key, grade number, level-1 area key). Widths after the 2.R fix (in 0102): `stage` 40, `track` 40, `governorate` 60. 0103 backfills: `country_code = 'EG'` where a stage is set, then `stage_id` / `grade_id` / `area_id` from (EG, stage key, grade number, governorate key); a row with no match keeps NULL ids |
| `teacher_teaching_levels` | `id`, `user_id FK CASCADE`, `stage_id FK`, `grade_id FK NULL` (NULL = the whole stage); unique `(user_id, stage_id, grade_id)`; index `(grade_id)`, `(stage_id)` |
| `parent_consents` | `id`, `parent_id FK`, `student_id FK`, `kind String(30)` (`minor_account`), `text_version String(20)`, `granted_at`, `ip String(64)`, `user_agent String(300)`, `revoked_at NULL`; index `(student_id, kind)` |
| `courses` | + `country_code String(2) NULL`, `delivery_mode String(12) NOT NULL default 'online'` (online \| in_person \| both), `subject_id FK edu_subjects NULL`, `area_id FK geo_areas NULL`, `area_parent_id FK geo_areas NULL`, `address String(300) NULL`, `program_kind String(12) NOT NULL default 'course'` (course \| quran) |
| `course_targets` | `course_id FK CASCADE`, `stage_id FK`, `grade_id FK NULL`; unique `(course_id, stage_id, grade_id)` |

Rules from the 2.R review (what Phase 2 built):
- The table and column names above are fixed: `edu_service.REFS` already counts `student_study_profiles.stage_id|grade_id|area_id`, `teacher_teaching_levels.stage_id|grade_id`, `course_targets.stage_id|grade_id`, `courses.subject_id|area_id|area_parent_id` for "in use". Once 0103 has backfilled, B3 removes the old-key counts added in 2.R.
- Old keys: a write with `stage` / `grade` / `governorate` and no ids resolves the ids against the profile's `country_code` (default `EG`); a key with no row (e.g. `university` + year 3, which has no grade rows) is saved as before with NULL ids. A write with ids also writes the keys (stage key, grade number, level-1 area key; a level-2 area writes its parent's key). `track` is checked against the grade's `tracks`.
- A stage with `has_grades = false`: `grade_id` must be NULL. A `contact_only` stage saves the profile the same way; the WhatsApp hand-off is the front's, with the country's `contact_whatsapp`.
- `GET /edu/countries` adds `minor_age`, `phone_code`, `contact_whatsapp` (registration needs them before sign-in). `disabled_features` stays admin-only until Phase 6.
- The catalog: the app never sends `If-None-Match` (its answers are encrypted per session, so the server answers it `private, no-store` and no 304); ETag / 304 / `public, max-age=300` serve callers without `X-Enc-Session` (the landing, Phase 4).
- The student's country: the profile's `country_code`; before one exists, the first row of `GET /edu/countries` (sort order), changeable in the picker.

Routes:
- `GET|PUT /me/study-profile` (the existing route): accepts and returns `country_code, stage_id, grade_id, area_id, gender` next to the old fields; ids win when both are sent. 422 `edu_grade_mismatch` when the grade is not of the stage.
- `GET|PUT /me/teaching-levels` → `{levels: [{stage_id, grade_id|null}]}` (teacher only).
- Parent child link (existing routes; the `/parent/children/…` paths in this file are placeholders: B3 uses the existing parent router's prefix and writes the real paths here): `+ stage_id, grade_id` for a child the parent creates; `POST /parent/children/{student_id}/consent {accepted: true, text_version}` → 201; `GET …/consent`. A child under the country's `minor_age` with no consent: `needs_consent: true` in the child's payload (enforced in Phase 10).
- Course create / update (existing): `+ country_code, delivery_mode, subject_id, area_id, address, targets: [{stage_id, grade_id|null}]` (the list replaces the old one). Rules: `in_person | both` needs `area_id` → 422 `course_area_required`; `area_parent_id` is set by the server. `CourseResponse` adds `delivery_mode, country_code, subject: {id, name_ar, name_en}|null, area: {id, name_ar, name_en, parent: {…}}|null, targets: [{stage_id, stage_ar, stage_en, grade_id, grade_ar, grade_en}]`; `address` only for the teacher, admins and enrolled students.

## 4. Phase 4 — search and landing (migration 0104: indexes only)

Indexes: `ix_course_targets_grade (grade_id, course_id)`, `ix_course_targets_stage (stage_id, course_id)`, `ix_courses_country_delivery (country_code, delivery_mode) WHERE is_published`, `ix_courses_area_parent`, `ix_courses_area`, `ix_courses_subject`; PostgreSQL only: `CREATE EXTENSION IF NOT EXISTS pg_trgm` + GIN `gin_trgm_ops` on `name_ar`, `name_en` (inside a savepoint; a failure is logged and skipped).

- `GET /courses` adds `country, stage_id, grade_id, subject_id, delivery (online|in_person), kind (live|recorded), area_id, program_kind`. `delivery=online` matches `online | both`; `in_person` matches `in_person | both`. `grade_id` matches a target of that grade OR a whole-stage target of its stage. `country` also matches a course with no `country_code` (every course made before Phase 3; 4.R). Old params unchanged. Answer shape unchanged. Every list keeps `CourseResponse` (`address` only through `address_view`, 3.R). A student's default filters are the profile's `stage_id` / `grade_id` (backfilled by `features/edu/backfill.py` on every seed, 3.R).
- `GET /public/landing/options?country=` adds `countries`, `stages` (with grades) and `families` (the category tree) next to `subjects`.
- `GET /public/landing/match` adds `country, stage_id, grade_id, delivery, area_id`.
- Registration through `/join`: a teacher's levels ride in `POST /auth/teacher-profile` as `teaching_levels: [{stage_id, grade_id|null}]` (3.R); a parent's redeem answers 422 `consent_required` for a minor (no DOB = a minor unless the stage is university / graduate, 3.R).
- App routes: `/join?role=student|teacher|parent|org`; `PendingIntent` JSON `{v: 1, kind, id, plan, filters, at}` under the SharedPreferences key `pending_intent`, TTL 2 h, cleared on logout and when guest mode starts again (4.R). `JoinDraft` (`join_draft`) carries `at`, expires after 7 days, is cleared on logout and once the account exists; nothing in it is sent before sign-up.
- `GET /teacher/student-dashboard` (4.R) takes the `GET /courses` filters (`country, stage_id, grade_id, subject_id, delivery, area_id`) + `level=profile` (a signed-in student's profile level when no filter is sent) for `other_courses` / `other_courses_total`; adds `applied_filters` and `study_level: {country, stage_id, grade_id}|null`.

Kill switches: `join.flow` (off = the old guest search), `courses.filters` (the filter bar).

## 5. Phase 5 — store (migration 0105)

| Table | Columns |
|---|---|
| `store_items` | `id`, `owner_id FK users`, `org_id FK NULL`, `country_code String(2) NULL`, `kind String(12)` (ebook \| summary \| notes \| other), `title_ar/en String(200)`, `description_ar/en Text`, `cover_url String(1000)`, `file_ref String(400)` (private), `preview_ref String(400) NULL`, `file_name String(200)`, `file_size BigInteger`, `sha256 String(64)`, `pages Integer NULL`, `price Numeric(10,2)`, `points_price Integer NULL`, `currency String(3)`, `vat_exempt Boolean default false`, `stage_id NULL`, `grade_id NULL`, `subject_id NULL`, `category_id NULL`, `status String(12)` (draft \| pending \| published \| hidden), `sales_count Integer default 0`, `is_demo Boolean default false`, timestamps; index `(status, country_code, grade_id)`, `(subject_id)`, `(category_id)` |
| `store_orders` | `id`, `user_id FK`, `status String(12)` (pending \| paid \| failed \| cancelled \| refunded), `country_code`, `currency`, `subtotal`, `vat_percent Numeric(5,2)`, `vat_amount`, `total` (Numeric(10,2)), `method String(12)` (card \| points \| free), `provider String(20) NULL`, `checkout_token String(64) unique`, `payment_id String(255) NULL`, `idempotency_key String(64)`, `points_spent Integer NULL`, `meta JSON`, `failure_reason String(200) NULL`, `paid_at`, `created_at`; unique `(user_id, idempotency_key)`; unique `(provider, payment_id)` where not null |
| `store_order_items` | `id`, `order_id FK CASCADE`, `item_id FK`, `title String(200)`, `unit_net`, `unit_vat`, `unit_gross`; unique `(order_id, item_id)` |
| `store_library` | `id`, `user_id FK`, `item_id FK`, `order_id FK`, `granted_at`, `revoked_at NULL`; unique `(user_id, item_id)` |
| `store_download_grants` | `id`, `user_id`, `item_id`, `token_hash String(64) unique`, `expires_at`, `used_at NULL`, `ip String(64)`, `device_id String(128) NULL`, `created_at`; index `(user_id, item_id, created_at)` |

Tax (`store_tax.quote`): per line, `vat_exempt` or a 0 rate → `vat = 0`; inclusive: `gross = price`, `net = gross / (1 + r)`; exclusive: `net = price`, `gross = net × (1 + r)`; 2 dp ROUND_HALF_UP; `vat = gross − net`. The order stores the sums.

Routes:
- `GET /store/items?country&stage_id&grade_id&subject_id&category_id&kind&search&skip&limit` (optional auth) → `{items: [{id, kind, title_ar, title_en, cover_url, price: {net, vat, gross, currency, vat_percent, includes_vat}, points_price, stage_id, grade_id, subject_id, pages, owned}], total, has_more}`.
- `GET /store/items/{id}` → the item + descriptions + `preview_url` (signed, short) + `owned`.
- `POST /store/quote {item_ids}` → `{lines, subtotal, vat_amount, total, currency, vat_percent, points_total|null}`. 409 `store_mixed_currency`, `store_already_owned`.
- `POST /store/orders {item_ids, method, provider?}` + header `Idempotency-Key` → `{order: {id, status, total, …}, checkout: {url, token}|null}`; free and points settle at once (`status: paid`). 402 `points_insufficient`.
- `GET /store/orders/{id}` (owner) · `GET /store/orders` (purchase history) · gateway return `GET /store/checkout/return?token=` and the existing webhook route → both call `settle`.
- `GET /store/library` → owned items + `last_download_at`.
- `POST /store/library/{item_id}/download` → `{url, expires_in: 120}`. 403 `store_not_owned`, 429 `store_download_limit`.
- `GET /store/dl/{token}` → 302 to the signed file URL; 410 `store_link_expired`; single use.
- Manage: `GET|POST|PATCH|DELETE /store/manage/items[/{id}]`, `POST /store/manage/items/{id}/file` (presigned private upload), `POST /store/manage/items/{id}/publish`; super admin: `GET /admin/store/items?status=pending`, `POST /admin/store/items/{id}/review {approve, note}`, `GET /admin/store/orders`.
- `module_settings` `store`: `download_daily_limit` (10), `points_enabled` (false), `teacher_items` (false), `review_required` (false).

Kill switches: `student_tab_store`, `store.buy`, `store.points`, `store.manage`, `admin.store`.

## 6. Phase 6 — tabs, switches, games, Quran, nahw (migrations 0106, 0107)

**Switches.** `module_settings`: `id`, `module String(20)`, `scope String(10)` (platform \| country \| org), `scope_key String(20)`, `values JSON`, `updated_by`, `updated_at`; unique `(module, scope, scope_key)`. `GET /module-settings/{module}?org_id=` → the resolved values (signed-in: the user's country); `GET|PUT /admin/module-settings/{module}?scope=&scope_key=`. Country kill switches: `PUT /admin/edu/countries/{code}/features {disabled: [keys]}`; the theme response takes `?country=` (guest) or the user's country and merges it into the disable list.

**Games (0106).** `games`: `id`, `key String(60) unique`, `engine String(12)`, `title_ar/en`, `config JSON`, `country_code NULL`, `stage_id`, `grade_id`, `subject_id`, `points_reward Integer default 0`, `status`, `is_demo`, std. `game_plays`: `id`, `user_id`, `game_id`, `client_id String(36)`, `score`, `max_score`, `stars SmallInteger`, `duration_s`, `played_at`; unique `(user_id, client_id)`. `game_progress`: PK `(user_id, game_id)`, `best_score`, `stars`, `plays`, `last_played_at`. `badges` (`key PK String(40)`, names, `icon String(40)`, `rule JSON`), `user_badges` (unique `(user_id, badge_key)`).
`GET /games?stage_id&grade_id&subject_id` · `GET /games/{id}` (with `config`) · `POST /games/{id}/plays {client_id, score, max_score, duration_s, played_at}` → `{progress, new_badges, points_awarded}` (same `client_id` = the first answer again) · `GET /me/games/progress` · `GET /parent/children/{id}/games` · admin `…/admin/games` CRUD. Settings `games`: `points_rewards` (false), `points_daily_cap` (20).

**Quran (0107).** `quran_teacher_profiles`: `user_id PK`, `gender String(1)`, `bio Text`, `ijazah String(300) NULL`, `goals JSON`, `session_types JSON`, `country_code`, `status String(12)` (draft \| pending \| published), `verified_at`, `verified_by`, `is_demo`. `quran_progress`: `id`, `student_id`, `teacher_id NULL`, `course_id NULL`, `surah SmallInteger`, `from_ayah`, `to_ayah`, `kind String(14)` (memorization \| tajweed \| revision), `grade SmallInteger NULL` (1–5), `note String(500)`, `client_id String(36)`, `recorded_by`, `recorded_at`; unique `(recorded_by, client_id)`; index `(student_id, surah)`.
`GET /quran/teachers?gender&goal&session_type&country` → teachers with their `program_kind='quran'` courses · `GET /quran/teachers/{id}` · `GET|PUT /me/quran/teacher-profile` · `GET /me/quran/progress` → `{surahs: [{surah, memorized_ayahs, total_ayahs}], juz: [{juz, percent}], recent}` · `POST /quran/progress` (the teacher of the student's course, or the student as a self-log) · `GET /quran/meta` (surah names, ayah counts, juz boundaries). Booking = enrolling in the teacher's quran course. Settings `quran`: `teacher_verification_required` (false), `content_review_required` (false), `gender_matching` (`off`), `self_log` (true). Codes: 403 `quran_gender_rule`, `quran_teacher_unverified`.

**Nahw (0107).** `nahw_levels` (`id`, `key`, titles, `stage_id NULL`, `grade_id NULL`, std), `nahw_lessons` (`id`, `level_id`, titles, `body_ar Text`, std), `nahw_exercises` (`id`, `lesson_id`, `kind String(12)`, `prompt Text`, `data JSON`, `answer JSON`, `explanation Text`, `sort`), `nahw_progress` (PK `(user_id, lesson_id)`, `best_score`, `attempts`, `completed_at`).
`GET /nahw/levels` (with lessons + my progress) · `GET /nahw/lessons/{id}` (with exercises and answers) · `POST /nahw/lessons/{id}/attempts {client_id, score, max_score, answers}` · admin CRUD.

Kill switches: `student_tab_games`, `student_tab_quran`, `student_tab_nahw`, `games.rewards`, `quran.teacher_apply`, `admin.modules`. All four tab keys are organization-manageable.

## 7. Phase 7 — sync (migration 0108) — detailed at the Phase 6 review (2026-11-21)
`sync_ops`: `id`, `user_id`, `op_id String(36)`, `kind String(30)`, `status String(12)`, `code String(40) NULL`, `applied_at`; unique `(user_id, op_id)`.
- `POST /sync/push {ops: [{id, kind, payload, client_ts, base_updated_at?}]}` (≤ 100) → `{results: [{id, status: applied|duplicate|rejected, code?, entity?}], server_time}`. Kinds: `game_play`, `nahw_attempt`, `quran_progress`, `study_profile`.
- `GET /sync/pull?since=<iso>&kinds=` → `{changes: {<kind>: [rows with updated_at]}, deleted: {<kind>: [ids]}, cursor}`.
Every cached GET keeps answering `updated_at` / `ETag`.

**Rules for `push`:**
- An op's `id` IS the entity's `client_id` (8–36 of `A-Za-z0-9_.:-`). The sync service calls the SAME service functions as the routes (`games_service.record_play`, `nahw_service.attempt`, `quran_service.record`), so an op pushed and the same `client_id` posted to the route give one row. `sync_ops` records the answer; the entity's own unique index stays the guard.
- Ops are applied in the order sent, each in its own transaction (a SAVEPOINT per op on PostgreSQL): one rejected op never undoes the others. The answer keeps the order.
- `duplicate` = the op id was applied before; it answers the first `entity` again.
- `rejected` carries the route's own code (`feature_disabled`, `quran_self_log_off`, `quran_not_your_student`, `quran_bad_range`, `game_not_found`, `nahw_lesson_not_found`, `game_bad_score`, …) or `sync_bad_op` / `sync_unknown_kind` / `sync_stale`. A rejected op is final: the app drops it from the outbox and shows it once. Only a transport failure or a 5xx is retried.
- `client_ts` is the device's time of the action. `game_play` stores it as `played_at` (already clamped: not in the future, not older than 60 days). `quran_progress` stores it as `recorded_at` under the same clamp (today the route drops the device's time: B8 changes `quran_service.record` to take it). `nahw_attempt` ignores it.
- The user is the token's. A payload naming another user is `rejected` `sync_bad_op`, except `quran_progress.student_id` from a teacher, which `record` checks.

**Payloads:**
| Kind | Payload | Applies through |
|---|---|---|
| `game_play` | `{game_id, score, max_score, duration_s?}` | `record_play` (points and badges as on the route; `entity` = the route's answer) |
| `nahw_attempt` | `{lesson_id, score, max_score, answers?}` | `attempt` |
| `quran_progress` | `{student_id?, course_id?, surah, from_ayah, to_ayah, kind, grade?, note?}` | `record` |
| `study_profile` | the fields of the study-profile PUT (CONTRACT §3) + the op's `base_updated_at` | the profile service; `base_updated_at` older than the row's `updated_at` → `rejected` `sync_stale` with `entity` = the server's row (D-1352) |

**`pull`:** kinds `game_progress`, `user_badges`, `nahw_progress`, `quran_progress`, `study_profile`, each row with `updated_at`; `since` absent = everything of the caller; `cursor` = the `server_time` to send as the next `since`. `deleted` stays empty for these kinds in v1 (none is deleted by another device). `game_progress` and `nahw_progress` need an `updated_at` column (0108).

Money is never an op (D-1351): store orders, course checkout and points stay online. Kill switch `sync.offline` (off = the app posts straight to the routes, as Phase 6 does).

## 8. Phases 8–10 — outline
- Releases: `releases.json` gains per-platform file kinds `exe`, `appimage`, `dmg` (same entry shape: `url, size, sha256, min_os`); `GET /app/downloads` unchanged.
- Privacy: audit rows (the existing audit tables) for: consent granted / revoked, a child's data viewed by a parent, address viewed by staff, store download grant, edu catalog edit, module setting change, quran teacher verified.
- Demo data: `is_demo` on new tables; users seeded with gmail `…@demo.nextbrain.invalid`; courses tagged `tags: ["demo"]`; `seed_learning_hub_demo.py --remove` deletes by those marks only.
