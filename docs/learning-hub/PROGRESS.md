# Learning Hub — progress

Resume rule: read this file, continue the first step that is not `done` / `verified`. Status: `todo` · `doing` · `done` (agent finished, tests pass) · `verified` (planner reviewed) · `gap` (logged, not blocking). Plan: `PLAN.md`. Contract: `CONTRACT.md`.

| # | Step | Agent | Status | Notes |
|---|---|---|---|---|
| 0.1 | RESEARCH.md (reference apps, verified stages + VAT) | R1 | done | 4 JS-rendered sites only titles; book VAT + Tanzil licence flagged |
| 1.1 | Reproduce the 500 on PostgreSQL (`e2e_onboarding_prod_case.py`) | A1 | done | PG: StringDataRightTruncation varchar(10) |
| 1.2 | Migration 0101: `nid_kind` width + literal audit | A1 | done | back e2c804f, no other overflow |
| 1.3 | Teacher + staff types pass; where 500 refs are logged | A1 | done | teacher+staff pass on PG; errors: `docker logs edu_api 2>&1 \| grep -A40 "ref=<REF>"` |
| 1.R | Review: traceback + migration | planner | verified | lead checked; hotfix pushed to production + backend deploy 2026-11-20 |
| 2.1 | Back: edu tables, seeder, public + admin routes (0102) | B1 | done | back tables + seeder + routes (0102) with the 2.R fixes |
| 2.2 | Seeds EG.json, SA.json | B2 | done | EG + SA seeds hash-loaded by the seeder |
| 2.3 | Front: `EduCatalog` + pickers | F1 | done | EduCatalog (no If-None-Match) + pickers |
| 2.4 | Front: super admin levels page | F2 | done | levels page under admin.edu_levels |
| 2.R | Review: data model + seeds | planner | verified | all 8 fixes confirmed in back 9e61711 + front 4fabbd1e (diffs read; tests as the lead reported) |
| 3.1 | Back: profile ids, teaching levels, consent, course fields (0103) | B3 | done | e2e_registration 85 checks, e2e_edu 55, PG up/down OK; consent rides on redeem (consent + text_version), address via address_view |
| 3.2 | Front: registration capture (student, teacher, parent) | F3 | done | levels steps, study profile ids, parent consent (D-1311) |
| 3.3 | Front: course form + profile block | F4 | done | CourseSetupSection in the form (targets chips, subject, delivery, area + address), CourseWhoWhereBlock in the About tab; setup sent only after the detail loads; test/ui/course_setup_test.dart |
| 3.R | Review: real web app, three registrations + one in-person course | planner | verified | 7 must-fix + 4 QA fixes in back a9a12a4 + front 2bc2bebe (diffs read); phone-width create form re-walked at 4.R |
| 3.F | Phase 3 review + QA fixes (D-1315) | F/B fix | done | the 7 must-fix items + the 4 QA findings, see "3.F fixes" under 3.R; e2e_registration 106 checks, e2e_edu 55, PG backfill on seeded data OK; QA re-walk in QA_PHASE3.md |
| 4.1 | Back: search filters, indexes (0104), landing options / match | B4 | todo | |
| 4.2 | Front: join flow + PendingIntent hand-off | F5 | todo | |
| 4.3 | Landing: four entry buttons | L1 | todo | |
| 4.4 | Front: filter bar on explorer + student home | F6 | todo | |
| 4.R | Review: landing → join → course → login → checkout walk | planner | todo | |
| 4.F | Phase 4 review + QA fixes (D-1326) | F/B fix | done | the 7 must-fix items + the QA fails / highs / mediums, see "4.F fixes" under 4.R; e2e_course_search 128 checks, e2e_registration 106; QA re-walk in QA_PHASE4.md |
| 5.1 | Back: store, tax, orders, settle, downloads (0105) | B5 | todo | |
| 5.2 | Front: store tab, cart, checkout, My Library | F7 | todo | |
| 5.3 | Front: store management + country VAT fields | F8 | todo | |
| 5.R | Review: `orders.py`, `downloads.py`, payment + download tests | planner | todo | |
| 6.1 | Back: module settings, country switches, games (0106) | B6 | todo | |
| 6.2 | Back: Quran + nahw (0107) | B7 | todo | |
| 6.3 | Seeds: surah metadata, nahw lessons, starter games | S1 | todo | |
| 6.4 | Front: learn kit + games tab | F9 | todo | |
| 6.5 | Front: Quran tab | F10 | todo | |
| 6.6 | Front: nahw tab + admin switches page | F11 | todo | |
| 6.R | Review: switch model, phone layout of the tabs, §7 contract detail | planner | todo | |
| 7.1 | Back: sync push / pull (0108) | B8 | todo | |
| 7.2 | Front: LocalDb, Outbox, SyncEngine, status chip | F12 | todo | |
| 7.3 | Front: wire entities + caches + offline library | F13 | todo | |
| 7.R | Review: `sync_engine.dart`, `features/sync/service.py` | planner | todo | |
| 8.1 | Android: verify keystore, APK + AAB | N1 | todo | |
| 8.2 | Windows installer | N2 | todo | |
| 8.3 | Linux AppImage; macOS + iOS workflows; APPLE.md | N3 | todo | |
| 9.1 | Downloads page (ar / en) | L2 | todo | |
| 9.2 | `build_all.py`, manifest kinds, BUILD.md | N4 | todo | |
| 9.3 | Update check on desktop | N5 | todo | |
| 9.R | Review: the live Downloads page | planner | todo | |
| 10.1 | Privacy pass + consent enforcement + audit rows | B9 | todo | |
| 10.2 | Demo seed script (+ `--remove`) | S2 | todo | |
| 10.3 | Features guide, help ids, API changes, FINAL_REPORT.md | D1 | todo | |
| 10.R | Final quality gate | planner | todo | |

## Gaps (logged, not blocking)
| Item | Reason | Owner action |
|---|---|---|
| | | |

## Installed tools / packages
| What | Phase | Why |
|---|---|---|
| | | |

## 2.R review (planner, 2026-11-20) — verdict: needs fixes

Read: back `e2c804f..55446a1`, front `603698d3..0ad3535a`. The reviewer ran no test (the agents' results are taken as reported).

Sound: the tables match CONTRACT §2.1 (+ `edu_meta`, accepted); admin routes are super admin only (`require_admin` + `is_super_admin`), each write audited and versioned; `GET /admin/edu/catalog` and the hash-gated seeder accepted; seed stages match RESEARCH.md (EG KG 2 / 6 / 3 / 3, SA KG 3 / 6 / 3 / 3), VAT 14 / 15; per-stage grade numbers keep the old profile keys valid; the 27 old governorate keys + `other` are present; the longest seed key is 16 characters; `contact_only` is true on university only; the front files use tokens, `context.colors`, `AppDropdown`, bilingual text and no raw colour.

### Must fix (one brief)

Back, `_wt/lh-back`:
1. **Encrypted clients + caching** — `features/edu/api/edu_router.py:35-36`. The app sends `X-Enc-Session`, so `helpers/encryption_middleware.py:235-251` wraps the answer per session: a 304 gets a body, and `public, max-age=300` lets a browser replay an envelope of an older session. Change: read `x_enc_session: Optional[str] = Header(None)`; add `"Vary": "X-Enc-Session"` to `headers`; when the header is present use `Cache-Control: private, no-store` and never answer 304. Add both cases to `tests/learning_hub/e2e_edu.py`.
2. **Column widths (the Phase 1 bug class)** — `data/student_profile_models.py:29,31,33`: `stage` `String(20)` → `String(40)`, `track` `String(20)` → `String(40)`, `governorate` `String(40)` → `String(60)` (stage / track keys are 40, area keys 60, and `options()` now accepts table keys). Add the three `batch_alter_table` widenings to `migrations/versions/0102_edu_levels.py` the way 0101 does (0102 is not deployed), with the downgrade.
3. **Old university grades are dropped** — `features/profiles/student_profile_service.py:106-107`: the EG seed has `university.has_grades = false`, the old constant is `range(1, 8)`, so an old app's university year is silently saved as NULL. Change line 107 to `out[st.key] = STAGES.get(st.key)` (a legacy range wins for a legacy key; a new key gets None). Add an e2e check: `university` + grade 3 is kept.
4. **Seeder race** — `features/edu/seeder.py:102`: PostgreSQL treats NULL as distinct, so `uq_geo_areas_country_parent_key` does not guard level-1 areas; two workers loading a changed file double them. After `S.meta(db)`, lock the row (`db.query(EduMeta).filter(EduMeta.id == 1).with_for_update().one()`) and read `seeded` from the locked row.
5. **Delete ignores old-key use** — `features/edu/edu_service.py:409-417`: `REFS` counts id columns that do not exist until 0103, so a stage / governorate used by many profiles is hard deleted. For a stage of country `EG` add the count of `student_study_profiles` where `stage = row.key`; for a level-1 `EG` area, where `governorate = row.key`.
6. **PATCH with an explicit null answers 500** — `features/edu/api/admin_edu_router.py:159-160`: `_patch` keeps `null`, then NOT NULL fails. Drop None values except for `currency`, `phone_code`, `geo_labels`, `contact_whatsapp`, `number`, `tracks`.

Front, `_wt/lh-front`:
7. `lib/core/edu/edu_catalog.dart:239-240`: stop sending `If-None-Match` (pass no `headers`); keep the stored copy as the first paint and the fallback. Update the header comment (lines 3, 6-7) and `test/core/edu_catalog_test.dart`.
8. The contract snapshots were not regenerated: `test/contract/api_paths.json` has no `/edu/` route and `feature_keys.json` no `admin.edu_levels`. From `lh-back`: `.venv312/Scripts/python scripts/contract/export_api_paths.py --front ../lh-front`, then run `flutter test test/contract/`.

### Nice to have
- SA level 1 mixes regions and cities under the label "City" (`jeddah`, `dammam` next to `asir`, `qassim`; no Eastern Province entry for Khobar / Ahsa): relabel `geo_labels.1` "Region or city" and add `eastern`, or log it under Gaps.
- SA secondary has no tracks (the Saudi tracks system is not in RESEARCH.md): log under Gaps; the super admin can add them.
- `0102`: partial unique indexes for the NULL cases (`geo_areas` level 1, global `edu_subjects`).
- `edu_router.py:33`: compare the version before building the catalog; cache `options()` by `edu_meta.version` (it adds 3 queries to every `/me/home`).
- `seeder.py:102-115`: a bad file stops the files after it and rolls back the ones before it.
- `test/ui/help_ids_test.dart:34` `knownMissing`: add `admin.edu_levels` to `back/data/help_seed.json` and the features guide in 10.3, then remove the entry.
- `edu_levels_page.dart:96,181,257`: three raw layout breakpoints (900 / 520).

### Contract changes made for Phase 3 (CONTRACT §3)
Profile widths moved to 0102; 0103 backfills the ids from the old keys; legacy keys resolve against the profile's country; `GET /edu/countries` gains `minor_age`, `phone_code`, `contact_whatsapp`; a stage without grades takes `grade_id` NULL; the app never sends `If-None-Match`; the ref table / column names are fixed by `edu_service.REFS`.

### 2.R re-check (planner, 2026-11-20): verified
All 8 must-fix items are in back 9e61711 and front 4fabbd1e as written. The nice-to-have list stays open. PLAN.md Phase 3 briefs updated to CONTRACT §3 (B3 also owns `features/edu/` for the countries fields and the old-key counts; F3 gets the `contact_only` hand-off and the country rule).

## 3.R code review (planner, 2026-11-20) — verdict: needs fixes

Read: back `9e61711..f085a08`, front `4fabbd1e..5eae7f59`. No test run by the reviewer. The real-app walk is QA_PHASE3.md (separate).

Sound: CONTRACT §3 tables / columns / routes as written; `course_levels.apply` touches only the keys sent and `update_course` uses `exclude_unset`, so old apps and the other PUT callers (status, roadmap) never touch the new fields; the address is fail-closed (`CourseResponse.address` reads `address_view`, hidden unless the service marked the viewer) and no other serializer, `/me/home` card, public profile or export carries `address`; the course relationships are `selectin` (no N+1 on lists); consent rides on redeem (`gate` before the mode branch, row + audit committed with the link) and `GET|POST /parent/children/{id}/consent` covers an already linked child: accepted, since no parent-creates-child route exists.
Path check (phases 2–3): every new front call carries `/api/v1` (`kAdminEduPath`, teaching-levels, consent, redeem, study profile, course form, `EduCountries`); only `EduCatalog` went through the helper (fixed in 5eae7f59; item 7 makes its paths visible to the contract scanner).
Course PUT data loss: one path left (item 6). The detail call shows the address to exactly the people the PUT accepts (the course's teacher, admins), so `'address': null` cannot wipe an address the editor could not see.

### Must fix (one brief, Sonnet, both repos; don't `dart format`)

Back, `_wt/lh-back`:
1. **The 0103 backfill is a no-op in production.** The seed loads at app start (`features/edu/seeder.ensure_seeded`), after the migration; 0102 and 0103 deploy together, so `edu_stages` / `geo_areas` are empty when 0103 runs and every profile keeps NULL ids. `student_profile_service._values` resolves on read but never saves, so the Phase 4 search / home filters would see no student's level. Change: new `features/edu/backfill.py` with `PROFILE_SQL` (the four statements) and `backfill_profile_ids(db)`; `migrations/versions/0103_registration_course_targets.py:471-483` runs the same strings; `features/edu/seeder.py:123` calls `backfill_profile_ids(db)` just before `db.commit()` on every `seed_all` (under the `EduMeta` lock; cheap: every statement filters `... _id IS NULL`). SQL fixes in the same strings:
   - `SELECT MIN(s.id)` / `SELECT MIN(a.id)` in the stage and area subqueries (PostgreSQL: the unique index does not cover level-1 areas with a NULL parent; a duplicate makes the scalar subquery fail and aborts the deploy);
   - match on `LOWER(TRIM(student_study_profiles.stage))` / `LOWER(TRIM(student_study_profiles.governorate))`;
   - `country_code = 'EG'` also where `governorate IS NOT NULL` (an area without a stage);
   - unknown keys, NULLs and `university` + a year keep NULL ids (as now).
   e2e (`tests/learning_hub/e2e_registration.py`): insert profile rows with keys BEFORE seeding (`secondary`/2, `' Primary '`/3, `university`/3, `cairo` only, `nosuchkey`, NULL stage), call `seed_all`, check the ids; once on PostgreSQL with a duplicated level-1 area.
2. **Consent: an unknown date of birth must not mean adult.** The student sign-up sends no `dob` (`toBody(withDob: false)`), so today almost no child ever needs consent. `features/parents/consent_service.py:55-57` becomes: with a DOB, `age < minor_age`; without one, a minor unless the profile's stage key (the `stage_id` row's key, else `stage`) is in `ADULT_STAGES = {"university", "graduate"}` (no profile, `other` or a school stage = minor). `view()` adds `minor_basis: "dob" | "stage" | "unknown"`. Update the module docstring (lines 6-9) and `FLUTTER_API_CHANGES.md` ("A child with no date of birth is not a minor" → this rule). e2e: no DOB + secondary → 422 `consent_required`; no DOB + university → linked; DOB 30 years ago + secondary → linked. (Already linked school-age children will show `needs_consent: true`: intended, the parent sees the notice; enforcement stays Phase 10.)
3. **Teacher levels inside the registration.** `data/schemas.py:122` `TeacherProfileCreate` + `teaching_levels: Optional[List[CourseTargetIn]] = Field(None, max_length=200)` (move `CourseTargetIn` above it or add a `LevelIn`). Split `features/edu/teacher_levels.save` into `replace(db, user_id, pairs)` (check + delete + add, no commit) and `save` (role check + `replace` + commit); `features/auth/auth_service.py:474` `complete_teacher_profile` calls `replace` when the list is not None, in the same commit, before anything is written (a 422 leaves no half profile). `FLUTTER_API_CHANGES.md` + e2e (register with 2 levels → `GET /me/teaching-levels` after login returns them; a bad grade → 422).

Front, `_wt/lh-front`:
4. `lib/features/auth/auth_provider.dart:673` `completeTeacherProfile` takes `List<TeachingLevel> levels = const []` and sends `'teaching_levels': [for (final l in levels) l.toJson()]` when not empty; `additional_register_screen.dart:95` passes `_levels` and drops `PendingTeachingLevels.store` (~line 103). Delete `PendingTeachingLevels` (`register_levels_step.dart:239-268`) and its flush in `_persistTokens` (`auth_provider.dart:1152`): it was not per user (the next account to sign in on that device received the levels) and was lost on another device or a reinstall. Update the file header (lines 7-8) and `test/ui/registration_capture_test.dart`.
5. `lib/features/courses/teacher/course_form_provider.dart:242-250`: the country comes from `pickEduCountry(await EduCountries.load(), null)?.code ?? 'EG'` (one cached call, the registration's rule) instead of the raw `/edu/countries` call.
6. `course_form_provider.dart:274-286` (`_loadSetupFor`): (a) when the detail call fails, `_setupReady` stays false and every later edit of the section is silently not sent: add `bool setupLoadFailed`, set it in the catch, and in `course_form_screen.dart` (the `course_form.audience` card) show an error line with Retry (re-runs `_loadSetupFor`) instead of the editable section; (b) the detail must not overwrite edits made while it loaded: `if (!_setupDirty) _applySetup(...)`, and set `_addressCtrl.text` from `p.address` after the load. Add the failed-load case to `test/ui/course_setup_test.dart`.
7. `lib/core/edu/edu_catalog.dart:206,238,259,275`: write the full literal paths at the call sites (`'/api/v1/edu/catalog'`, `'/api/v1/edu/countries'`, `'/api/v1/edu/areas'`) and drop the `startsWith('/api/')` prefix in `_apiFetch`, so `test/contract/` sees them (the helper hid the bug). Adjust the fake fetch in `test/core/edu_catalog_test.dart` if it matches the short path.

Gates: back `e2e_registration.py` + `e2e_edu.py` (SQLite; item 1 also on PostgreSQL); front `flutter analyze --no-fatal-infos --fatal-warnings` on the changed paths, `flutter test test/ui/registration_capture_test.dart test/ui/course_setup_test.dart test/core/edu_catalog_test.dart test/contract/`. No new route, so no snapshot change expected.

### Nice to have
- Advanced link mode: the consent row is written when the request is filed; a rejected request keeps it. Revoke it on reject (`revoked_at`), or record it on approval.
- `features/profiles/student_profile_service.py:403`: a line joined by a run of spaces (a lost continuation); rewrap.
- `may_see_address`: an organization's managers of an org course (and `developer`) don't see the address; decide in Phase 10's privacy pass.
- `parent_link_screen.dart`: check the first 422 `consent_required` shows no error toast before the consent dialog.
- A teacher with no levels (signed up before F3) gets no prompt; a home nudge in Phase 10.
- `/parent/children`: 3 queries per child for `needs_consent`; batch in Phase 10.

### 3.F fixes (D-1315, 2026-11-20) — for the reviewer to verify
Must-fix items:
1. Fixed: `features/edu/backfill.py` (`PROFILE_SQL`, `backfill_profile_ids`); 0103 runs the same strings; `seed_all` runs it before its commit under the `EduMeta` lock. SQL: `MIN(id)` for stage and area, `LOWER(TRIM(...))` on both keys, EG also for governorate-only rows; the stage / area match the profile's own `country_code` (EG for every old row, so the same as the literal). e2e: 6 key-only rows before seeding (secondary/2, " Primary "/3, university/3, " Cairo " only, nosuchkey, all NULL). PostgreSQL (nb-pg, reset, 0102, EG + a duplicated level-1 `cairo`, 7 rows, upgrade, `seed_all`): every id as expected, the 0103 area statement survived the duplicate (MIN).
2. Fixed: `consent_service.minor_basis` (dob, else `ADULT_STAGES` by the stage row's key or the old key, else minor); `view()` adds `minor_basis`; docstring + `FLUTTER_API_CHANGES.md`. e2e: no DOB + secondary -> 422, no DOB + no profile -> 422, no DOB + university -> linked, DOB 30 years + secondary -> linked.
3. Fixed: `TeacherProfileCreate.teaching_levels`; `teacher_levels.replace` (no commit) + `save`; `complete_teacher_profile` replaces first (a 422 leaves no profile). e2e lifts the real method out of `auth_service.py` (the harness stubs the module): 2 levels saved, a bad grade -> 422 with no profile / rows, no list -> no levels.
4. Fixed: `completeTeacherProfile(levels:)` sends `teaching_levels` when not empty; `PendingTeachingLevels` and its flush deleted. Test: the body carries the list, and leaves the key out when empty.
5. Fixed: the form's country is `pickEduCountry(await EduCountries.load(), null)`.
6. Fixed: `setupLoadFailed` + `retrySetup()`; the form shows `CourseSetupLoadError` (error line + Retry) instead of the section; the detail applies only when `!_setupDirty`; the address field is refilled after a retry. Tests: the real form over FakeApi (detail 500 -> Retry -> section with the address).
7. Fixed: literal `/api/v1/edu/...` paths at the call sites, no prefixing in `_apiFetch`; test fake matches the full paths.

QA findings: the create-form blocker (see QA_PHASE3.md re-test), the area reopen (`_resolveArea` looks `area_id` up level 1, then the governorate's children), the consent-refused toast (`plToast` is error-toned, success passes `error: false`; the course form's `_showSnack` now honours the danger colour), the teacher's Details tab draws `CourseWhoWhereBlock` (address included). `courseAreaRequiredText` matches the server's wording.


### 3.R re-check (planner, 2026-11-20): verified
All 7 must-fix items are in back a9a12a4 and front 2bc2bebe as written. I read the diffs; the test results are as the lead reported: e2e_registration 106 checks, e2e_edu 55, the backfill on PostgreSQL, the phase 3 front tests, contract and the analyzer. Backfill: shared `PROFILE_SQL` with MIN / LOWER(TRIM) / the area-only country, run by 0103 and by `seed_all` under the lock. Consent: `minor_basis`, where no date of birth counts as a minor unless the stage is university or graduate. Teacher levels: `replace` runs before the profile is written, `PendingTeachingLevels` is gone. Course form: `setupLoadFailed` + Retry, and edits made while the detail loads win. EduCatalog: literal `/api/v1` paths.
One nit, not blocking: the `consent_service.py` docstring lists `minor_basis` as "dob | stage" but the code also returns `unknown`.
The create form's "chips don't respond" at phone width was not reproduced; it does not block Phase 4, which doesn't touch the course form. **4.R adds a step:** create an in-person course with 2 targets at 360 px width in the real web app.


### 4.R code review (planner, 2026-11-20) — the code half (the real-app walk is QA_PHASE4.md)
Read: back `a9a12a4..670dfc8`, front `ab56f289..55ab6ff4`. No test run by the reviewer.

**Verdict: not ready to close Phase 4.** The search, indexes, `/options` v2 and `/match` follow CONTRACT §4 and are clean (`learning_filters` is one function for both routes; the whole-stage, `both` and level-1 area rules are right; `CourseResponse` is kept). `PendingIntent` is sound on the main path. Four gaps block: legacy courses vanish behind the `country` filter, the home filters a list that is almost always empty, both contract kill switches are missing, and the join draft keeps a guest's name / phone forever.

Answers to the checkpoint questions:
- **Counts ~22 ms with a seq scan on 20 k courses: accepted.** A low-selectivity filter (`delivery=online`, a country) matches most rows, where a seq scan is the right plan; production has a small fraction of 20 k, and the page queries use the indexes. No new index, no estimate.
- **PendingIntent:** taken once (read + clear before `open`, `_taking` guard); only an int-parsed id is routed, to `CoursePageLoader` (no open redirect: `filters` / `plan` never become a route); survives the reload (SharedPreferences, saved before the login page opens); cleared on logout; checkout opens only for a student not yet enrolled. Gap: a guest who opens the login sheet, then goes back to browsing, leaves it for whoever signs in next within 24 h (item 4).
- **Home scope: no.** The strip holds `OTHER_COURSES = 6` newest courses (`dashboard.py:27`, not 8); filtering those by the profile level is empty for nearly every student, and the count shown is misleading. "The same filters on the Home Screen" means server-filtered (items 2, 6).
- **Join kill switch: yes.** CONTRACT §4 names `join.flow` and `courses.filters`; neither exists (items 3, 7).
- **Guest privacy:** nothing the join flow captures is sent before sign-up (it only reads `EduCatalog`). Name, phone, address and child code sit in SharedPreferences (`localStorage` on the web) under `join_draft` with no expiry, are not cleared on logout, and stay forever for a guest who only browses (item 5).
- **`/api/v1`:** every new call is a literal `/api/v1/...` (`/courses`, `EduCatalog`); the landing links are app routes. OK.

### Must fix (one brief, Opus, both repos; don't `dart format`; commit per repo, don't push)

Back, `_wt/lh-back`:
1. **Legacy courses must not vanish.** Every course made before Phase 3 has `country_code` NULL and no targets, and the join flow always sends `country`, so the explorer is empty in production. `features/courses/course_service.py:124` becomes `out.append(or_(Course.country_code == cc, Course.country_code.is_(None)))` (a countryless course matches every country: the categories' / subjects' rule). Update the `learning_filters` docstring, `FLUTTER_API_CHANGES.md` (phase 4 block: "A course with no `country_code` ... never matches `country`" → "matches every country") and `tests/learning_hub/e2e_course_search.py` (a NULL-country course appears under `country=EG` and `country=SA`; still absent under a `stage_id` / `grade_id` filter). Stage / grade stay strict (an untargeted course matches no level); the front's empty state covers it (item 6).
2. **The home's filtered strip, server side.** `features/home/api/dashboard.py:72-98` `student_dashboard` takes the same optional params as `GET /courses` (`country, stage_id, grade_id, subject_id, delivery, area_id`, same `Query` patterns) plus `level: Optional[str] = Query(None, pattern="^profile$")`. `conds = learning_filters(...)`; when no filter param is given, `level == "profile"` and the caller is a student whose study profile has a `stage_id`, use the profile's `country_code / stage_id / grade_id`. Pass `and_(cond, *conds)` to `get_other_courses` so `other_courses_total` is filtered too. The response adds `applied_filters` (only the keys used, `{}` when none) and, for a signed-in student, `study_level: {country, stage_id, grade_id} | null`. Guests: `level` ignored. `FLUTTER_API_CHANGES.md` + e2e (profile grade + `level=profile` → only that grade's / whole-stage courses and total; explicit params beat `level`; guest unchanged).
3. **Kill switches** (CONTRACT §4): `features/platform/feature_catalog.py` gains `join.flow` (ar "مسار الانضمام من الصفحة الرئيسية", en "Landing join flow") and `courses.filters` (ar "فلاتر البحث عن الكورسات", en "Course search filters"); `data/app_features_guide.json` gains the join flow and the filter bar (D-052 fields; kill keys as above). Regenerate the snapshots with `scripts/contract/export_api_paths.py --front <path of _wt/lh-front>`.

Front, `_wt/lh-front`:
4. **PendingIntent left behind.** `lib/features/guest/guest_state.dart:47` `start()` also runs `unawaited(PendingIntent.clear())` (a guest who backs out of the login to browse again drops it). `lib/core/routing/pending_intent.dart:41` `ttl = Duration(hours: 2)` (CONTRACT §4 updated): a Google round trip or a registration with verification fits; the next person on a shared device a day later does not. Tests in `test/core/pending_intent_test.dart`: saved → `GuestState.instance.start()` → `take()` is null; saved, clock + 2 h 1 min → null. Update the header comment (TTL).
5. **JoinDraft privacy.** `lib/features/onboarding/join/join_draft.dart`: add `at` (UTC, written by `save()`); `load()` drops and removes a draft older than 7 days or without `at`. `MyAuthProvider.logout()` (`auth_provider.dart:1116`) also `await JoinDraft.clear()`. After a successful `_linkChild` (`join_flow_screen.dart` ~:220) clear name / phone / child code from the draft. Header comment: "kept on this device only, never sent before the account is created; 7 days". Tests: an expired draft loads as null and is removed; logout clears it.
6. **The home filters on the server.** `lib/features/home/student/home_provider.dart:160-168`: send the remembered filters (`CourseFilterStore.initial(user)` when `known`) as query params, else `level: 'profile'` (signed-in students only, never guests); read `applied_filters` as the bar's start value and `study_level` into `CourseFilterStore.rememberProfile` (the profile level then reaches the explorer without opening the study-profile page). `home_screen.dart:821`: drop the client-side `filters.matches` filtering; a bar change calls `GET /api/v1/courses` (`limit: 12`, the home's `modeCourseScopeQuery()`, the filters), drops enrolled ids, shows the first 6 and the server's `total` as the count, without reloading the dashboard. `test/perf/home_requests_student_test.dart` stays green with no budget change (open = still one dashboard call). Empty state on the home and the explorer (`categories_screen.dart`): "No courses for this level yet" + a "Show every level" action that clears stage / grade only.
7. **Wire the kill switches.** `main.dart:914`: with `join.flow` in `AppConfig.disableList`, `/join` goes to `/guest-search` (the `role=org` branch above stays). `CourseFilterBar` is wrapped in `ParentComponent(featureKey: 'courses.filters')` on the explorer and the home; with the key off neither sends the bar's params (the join flow's start filters still apply to the explorer). Tests: `/join` with the key off; the bar hidden.

Gates: back `e2e_course_search.py` + the dashboard e2e (SQLite), the snapshot export; front `flutter analyze --no-fatal-infos --fatal-warnings` on the changed paths, `flutter test test/core/pending_intent_test.dart test/ui/course_filters_test.dart test/ui/join_flow_layout_test.dart test/perf/home_requests_student_test.dart test/contract/`.

### Nice to have
- `main.dart` `_Guard`: `resumePendingIntent` runs right after `SignInReturn.consume()` / `DeepLinkService.consumePending()`; a guest with both a pending URL and an intent gets two pushes. Skip the intent when one of them opened a page.
- `CourseFilterStore` keeps guest filters under the shared `guest` key; harmless, but never seed a new account from it.
- `/options` v2 caches per raw `country` (at most 676 keys) while unknown codes resolve to the default country: key the cache by the resolved code.
- The landing counter still uses the old `subject` / `level` params of `/match`; move it to `stage_id` / `grade_id` in the Phase 10 copy pass.
- `consent_service.py` docstring `minor_basis` (3.R nit) is still open.

### 4.F fixes (D-1326, 2026-11-20) — for the reviewer to verify
Must-fix items:
1. Fixed: `learning_filters` country = that country OR `country_code IS NULL`; docstring + `FLUTTER_API_CHANGES.md`. e2e: a NULL-country course appears under `country=EG` and `country=SA` (also `/match`), absent under `stage_id` / `grade_id`.
2. Fixed: `student_dashboard` takes `country, stage_id, grade_id, subject_id, delivery, area_id` + `level=profile` (same `Query` patterns); filters `other_courses` and `other_courses_total`; answers `applied_filters` and, signed in, `study_level` (null for non-students / no stage). e2e: profile + `level=profile`, no params, explicit params beat `level`, guest (level ignored, explicit filters apply), no profile, enrolled course left out, 422s.
3. Fixed: `join.flow` + `courses.filters` in `feature_catalog.py` (tab home), `app_features_guide.json` gains `join_flow` and `course_filters`; snapshots regenerated.
4. Fixed: `GuestState.start()` clears the intent; TTL 2 h (header comment). Tests: start → take null; 2 h 1 min → null.
5. Fixed: `JoinDraft.at` (written by `save`), `load` drops a draft older than 7 days or without `at`; `MyAuthProvider.clearGuestHandoff()` (intent + draft) is the first step of `logout`; after `_linkChild` name / phone / child code are cleared. Tests in `join_flow_layout_test.dart`.
6. Fixed: `HomeProvider` sends the remembered filters (else `level=profile` for a signed-in student, never guests, nothing with `courses.filters` off), reads `applied_filters` as the bar's value and `study_level` into `rememberProfile`; a bar change = `GET /api/v1/courses` (`limit: 12`, mode scope, filters), enrolled dropped, first 6, server total (minus enrolled on that page) as the count; no dashboard reload. `CourseFilterScope` is now controlled (`value` / `onChanged`). `CourseFilterEmpty` ("No courses for this level yet" + "Show every level", clears stage / grade only) on the home and the explorer. Perf budget unchanged. Test: `test/ui/home_filters_test.dart`.
7. Fixed: `/join` → `/guest-search` with `join.flow` off (`JoinRequest.switchedOff`); the bar is under `ParentComponent(featureKey: 'courses.filters')` on both pages, and with the key off the explorer ignores remembered / profile filters (the join flow's start filters still apply). Tests in `course_filters_test.dart`.

QA fixes: explorer cards (`CategoryCourseModel` reads `name_ar` / `name_en` and keeps the raw `CourseResponse` for `CourseModel.fromJson`), root register "Sign in" (`pushReplacementNamed('/login')` when nothing to pop), verify-otp → login as the only route named `/login` (also after the teacher's extra step), the guest sheet's background, the study step's area (the draft's study profile carries the governorate key), checkout currency from `price-options.currency`. Re-walk: QA_PHASE4.md "Re-test".
