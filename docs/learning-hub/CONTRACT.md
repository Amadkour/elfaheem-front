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
| `student_study_profiles` | + `country_code String(2) NULL`, `stage_id FK NULL`, `grade_id FK NULL`, `area_id FK geo_areas NULL`, `gender String(1) NULL`. `stage` / `grade` / `governorate` are still written (stage key, grade number, level-1 area key) |
| `teacher_teaching_levels` | `id`, `user_id FK CASCADE`, `stage_id FK`, `grade_id FK NULL` (NULL = the whole stage); unique `(user_id, stage_id, grade_id)`; index `(grade_id)`, `(stage_id)` |
| `parent_consents` | `id`, `parent_id FK`, `student_id FK`, `kind String(30)` (`minor_account`), `text_version String(20)`, `granted_at`, `ip String(64)`, `user_agent String(300)`, `revoked_at NULL`; index `(student_id, kind)` |
| `courses` | + `country_code String(2) NULL`, `delivery_mode String(12) NOT NULL default 'online'` (online \| in_person \| both), `subject_id FK edu_subjects NULL`, `area_id FK geo_areas NULL`, `area_parent_id FK geo_areas NULL`, `address String(300) NULL`, `program_kind String(12) NOT NULL default 'course'` (course \| quran) |
| `course_targets` | `course_id FK CASCADE`, `stage_id FK`, `grade_id FK NULL`; unique `(course_id, stage_id, grade_id)` |

Routes:
- `GET|PUT /me/study-profile` (the existing route): accepts and returns `country_code, stage_id, grade_id, area_id, gender` next to the old fields; ids win when both are sent. 422 `edu_grade_mismatch` when the grade is not of the stage.
- `GET|PUT /me/teaching-levels` → `{levels: [{stage_id, grade_id|null}]}` (teacher only).
- Parent child link (existing routes; the `/parent/children/…` paths in this file are placeholders: B3 uses the existing parent router's prefix and writes the real paths here): `+ stage_id, grade_id` for a child the parent creates; `POST /parent/children/{student_id}/consent {accepted: true, text_version}` → 201; `GET …/consent`. A child under the country's `minor_age` with no consent: `needs_consent: true` in the child's payload (enforced in Phase 10).
- Course create / update (existing): `+ country_code, delivery_mode, subject_id, area_id, address, targets: [{stage_id, grade_id|null}]` (the list replaces the old one). Rules: `in_person | both` needs `area_id` → 422 `course_area_required`; `area_parent_id` is set by the server. `CourseResponse` adds `delivery_mode, country_code, subject: {id, name_ar, name_en}|null, area: {id, name_ar, name_en, parent: {…}}|null, targets: [{stage_id, stage_ar, stage_en, grade_id, grade_ar, grade_en}]`; `address` only for the teacher, admins and enrolled students.

## 4. Phase 4 — search and landing (migration 0104: indexes only)

Indexes: `ix_course_targets_grade (grade_id, course_id)`, `ix_course_targets_stage (stage_id, course_id)`, `ix_courses_country_delivery (country_code, delivery_mode) WHERE is_published`, `ix_courses_area_parent`, `ix_courses_area`, `ix_courses_subject`; PostgreSQL only: `CREATE EXTENSION IF NOT EXISTS pg_trgm` + GIN `gin_trgm_ops` on `name_ar`, `name_en` (inside a savepoint; a failure is logged and skipped).

- `GET /courses` adds `country, stage_id, grade_id, subject_id, delivery (online|in_person), kind (live|recorded), area_id, program_kind`. `delivery=online` matches `online | both`; `in_person` matches `in_person | both`. `grade_id` matches a target of that grade OR a whole-stage target of its stage. Old params unchanged. Answer shape unchanged.
- `GET /public/landing/options?country=` adds `countries`, `stages` (with grades) and `families` (the category tree) next to `subjects`.
- `GET /public/landing/match` adds `country, stage_id, grade_id, delivery, area_id`.
- App routes: `/join?role=student|teacher|parent|org`; `PendingIntent` JSON `{v: 1, kind, id, plan, filters, at}` under the SharedPreferences key `pending_intent`.

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

## 7. Phase 7 — sync (migration 0108) — outline, detailed at the Phase 6 review
`sync_ops`: `id`, `user_id`, `op_id String(36)`, `kind String(30)`, `status String(12)`, `code String(40) NULL`, `applied_at`; unique `(user_id, op_id)`.
- `POST /sync/push {ops: [{id, kind, payload, client_ts, base_updated_at?}]}` (≤ 100) → `{results: [{id, status: applied|duplicate|rejected, code?}], server_time}`. Kinds: `game_play`, `nahw_attempt`, `quran_progress`, `study_profile`.
- `GET /sync/pull?since=<iso>&kinds=` → `{changes: {<kind>: [rows with updated_at]}, deleted: {<kind>: [ids]}, cursor}`.
Every cached GET keeps answering `updated_at` / `ETag`.

## 8. Phases 8–10 — outline
- Releases: `releases.json` gains per-platform file kinds `exe`, `appimage`, `dmg` (same entry shape: `url, size, sha256, min_os`); `GET /app/downloads` unchanged.
- Privacy: audit rows (the existing audit tables) for: consent granted / revoked, a child's data viewed by a parent, address viewed by staff, store download grant, edu catalog edit, module setting change, quran teacher verified.
- Demo data: `is_demo` on new tables; users seeded with gmail `…@demo.nextbrain.invalid`; courses tagged `tags: ["demo"]`; `seed_learning_hub_demo.py --remove` deletes by those marks only.
