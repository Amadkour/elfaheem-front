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

### 4.R re-check (planner, 2026-11-20): verified
All 7 must-fix items are in back 72edf8e and front f465e887 as written (diffs read; test results as the lead reported). Back: `country` also matches NULL; `student-dashboard` takes the filters + `level=profile`, answers `applied_filters` / `study_level`; `join.flow` + `courses.filters` in the catalog, guide and snapshots. Front: PendingIntent TTL 2 h, cleared by `GuestState.start` and logout; JoinDraft `at` + 7 days, cleared on logout and after a child link; the home sends the filters on the dashboard call and a bar change asks `GET /api/v1/courses` only; empty state "No courses for this level yet"; `/join` with `join.flow` off → guest search; the bar under `ParentComponent(courses.filters)`, params dropped when off. Nice-to-haves above stay open. Phase 5 briefs (PLAN Phase 5 incl. the 4.R F7 additions, CONTRACT §5) are ready to run.

### 5.R back review (planner, 2026-11-20) — back 939d377
**Verdict: not yet.** The settle core is right:
- Decimal + ROUND_HALF_UP throughout `store_tax`, with snapshots on the order and its lines.
- The amount AND the currency are checked before `paid`. The move to paid is a compare-and-set under `FOR UPDATE`.
- Webhook replays are deduplicated by `claim_event`, and `settle` is idempotent.
- `uq_store_orders_payment` stops one transaction paying two store orders.
- The points debit is in the same transaction as the library insert.
- `Idempotency-Key` is unique per user (`uq_store_orders_user_idem`, and `_existing` filters by user).
- Download grants are SHA-256-hashed, valid 120 s and single use by compare-and-set. The redirect is a 302 to a 60 s signed URL with `no-store` + `no-referrer`.
- Another user's token gets 403. The daily limit and `require_device` are in place.
- `file_ref` / `preview_ref` never reach JSON (`public_item` / `manage_item` / `order_dict` name their fields).

The `/api/v1/store/` entries in both `_OPEN_PREFIXES` only skip the subscription paywall and the (dead) device guard. Every store route keeps its own auth dependency, and `/api/v1/admin/store/` is not under the prefix, so nothing paid or private became public.

There are eight must-fixes. Two of them are double-spend holes across products.

#### Must-fix — brief for one Opus agent
Work in `_wt/lh-back`, on top of 939d377. Don't reformat whole files. Test only around the change: `tests/learning_hub/e2e_store.py` on SQLite, then the PostgreSQL run once at the end.

1. **Moyasar: bind the payment to THIS store order, strictly.**
   - Problem: `features/store/orders.py:389-392` (`settle_moyasar`) accepts a re-fetched paid payment whose `metadata` has NO `store_token`.
   - Attack:
     1. Pay a points top-up (or a course) of the same amount by Moyasar.
     2. Call `POST /store/checkout/moyasar/attach {token, id}` with that payment id. It needs no login.
     3. Open `/store/checkout/return?token=…&id=<that id>&status=paid`.
     
     The store order now settles from money that already bought points. The reuse check only looks at `store_orders`.
   - Change: `if str(meta.get("store_token") or "") != o.checkout_token: return "not_linked"`. Also refuse when `points_token` / `payment_token` / `fee_token` is present.
   - Nothing legitimate breaks: every store payment is made by our `pay_page`, which always sets `store_token`.
   - Test: a paid Moyasar payment with `metadata={"points_token": …}`, attached and returned, and the same payment through the webhook. Each answers `not_linked`; the order stays `pending` with no library row.
2. **Paymob: fail closed on the order binding.**
   - Problem: `orders.py:206-208` keeps `gateway_order_id` only when `intention_order_id` is in the session. Without it, `order_linked` (`payment_webhook_service.py:86-90`) returns True for ANY signed callback. The redirect's `token` query param is not covered by the HMAC, so a signed redirect from any other Paymob payment of the same amount, plus `&token=<store order>`, settles the order.
   - Change (a): in `_open_checkout`, when the provider is `paymob` and there is no `intention_order_id`, call `db.rollback()` and answer 502 `gateway_error`. No order is opened unbound.
   - Change (b): `card_return` (`orders.py:448`) and `webhook_paymob` (`orders.py:490`) use a strict check: `stored = (o.meta or {}).get("gateway_order_id")`; if `not stored or str(order_id or "") != stored`, answer failed / `"not_linked"`. Store orders are new, so there are no legacy rows to tolerate.
   - Tests:
     - A correctly signed redirect naming another order id, plus this token → `failed`; the order stays `pending`.
     - A session without `intention_order_id` → 502 and no order row.
3. **Two orders for the same item charge twice.**
   - Problem: `priced` (`store_service.py:218-220`) checks ownership before the order, but two concurrent orders with different keys both pass. The second order's `grant_library` (`orders.py:286-288`) just `continue`s on the owned item, and `_settle` still answers `paid`. The points are debited (or the card charged) for nothing.
   - Change in `_settle` (`orders.py:350-351`): `granted = grant_library(db, o)`; `lines = count(StoreOrderItem where order_id)`. If `granted < lines`:
     - for `method == "points"` (or `free`): `db.rollback()` and return `"already_owned"`. `create_order` (`orders.py:178-180`) maps that to 409 `store_already_owned`, with nothing debited and no order;
     - for `card`: keep `paid` (the money moved), but write `meta.duplicate_item_ids` and `log.warning`; `admin_orders` shows `needs_refund: true`.
   - Test: own an item through a library row inserted directly, then place a points order for it with `svc.owned_ids` patched to return `set()`. Expect 409, the balance unchanged and no order row.
4. **Magic bytes on upload confirm.**
   - Problem: `store_service.py:450-456` trusts the content type from `stat_object`, which is whatever the uploader sent with the PUT.
   - Change: add a seam `head_bytes(key, n=64)` (`get_object(bucket, key, offset=0, length=n)`) and detect the type from the bytes:
     - PDF: starts with `b"%PDF-"`;
     - EPUB: starts with `b"PK\x03\x04"` and `data[30:58] == b"mimetypeapplication/epub+zip"`;
     - JPEG: starts with `b"\xff\xd8\xff"`;
     - PNG: starts with `b"\x89PNG\r\n\x1a\n"`;
     - WEBP: `data[:4] == b"RIFF" and data[8:12] == b"WEBP"`.
   - The detected type must be in `FILE_TYPES[kind]`. Otherwise remove the object and answer 422 `store_bad_file_type`.
   - The size is still checked from `stat_object` (> 0 and ≤ 200 MB).
   - Test: PNG bytes uploaded as `application/pdf` for `kind=file` → 422, and `remove` is called. A real `%PDF-` file passes.
5. **Only the super admin reviews.**
   - Problem: `require_store_admin` (`store_service.py:488-491`) uses `is_admin`, which lets `admin`, `super-admin` and `developer` in.
   - Change: import `is_super_admin` from `features.platform.feature_catalog` and answer 403 `admin_required` when `not is_super_admin(user.role)`. This guards `admin_items`, `review` and `admin_orders`. Leave `require_manager` on `is_admin`.
   - Test: the role `admin` gets 403 on `POST /admin/store/items/{id}/review`; the super admin gets 200.
6. **An approved item can be changed without re-review.**
   - Problem: `update_item` (`store_service.py:349-360`) and `file_confirm` (`:457-466`) let a teacher swap the file, price or text of a `published` item.
   - Change: set `it.status = "pending"` when ALL of these hold:
     - `not is_admin(user)`;
     - `settings(db)["review_required"]` is on;
     - `it.status in ("published", "pending")`;
     - a file or preview was confirmed, or any of these fields changed: `title_ar/en`, `description_ar/en`, `cover_url`, `price`, `points_price`, `currency`, `vat_exempt`, `kind`, `country_code`.
   - Test: approve an item, then the teacher PATCHes the price → the item is `pending` and gone from `GET /store/items`. Buyers keep their library rows and downloads.
7. **Minor units per currency.**
   - Problem: `store_tax.minor_units` (`store_tax.py:274-276`) always multiplies by 100, and `_apply` (`store_service.py:321-324`) accepts any 3-letter code. A KWD/BHD/OMR/JOD price (3 decimals) or a JPY price (0 decimals) would be wrong, and `Numeric(10,2)` cannot hold 3 decimals.
   - Change:
     - add `MINOR_DIGITS = {"EGP": 2, "SAR": 2, "AED": 2, "USD": 2, …}` to `store_tax`;
     - `minor_units(amount, currency)` uses it and raises `ValueError` for an unknown code (callers: `orders.py:96, 324, 424`);
     - `_apply` refuses a currency that is not in `MINOR_DIGITS` or whose digits are not 2 → 422 `store_bad_currency`.
   - Test: `currency: "KWD"` → 422; SAR 114.00 → 11400.
8. **Settings resolution ready for `module_settings`.**
   - Problem: `settings()` (`store_service.py:61-71`) falls back to the code defaults on any exception, at `debug` level, so a broken resolver would go unnoticed.
   - Change:
     - catch `ImportError` / `AttributeError` (the module is not there yet) at `debug`, and log any other exception at `log.warning`;
     - the buyer's calls resolve per country: `orders.py:136` and `store_service.py:241` pass `country=user_country(db, user)`;
     - add a line to the B6 brief: the store already calls `module_settings.resolve(db, "store", country=, org_id=)`, and `store_service.DEFAULTS` is the registry entry for the module `store`.

**Gates:**
- Run `PYTHONUTF8=1 DATABASE_URL=sqlite:///…/store.db python tests/learning_hub/e2e_store.py`, then once on PostgreSQL.
- Run `export_api_paths.py` only if a route changed (none should).
- Add a `D-` entry for items 1–3: strict binding of store card payments, and the duplicate-item settle.

**Must-fix 1–8: fixed** in back 18185ae (D-1338, back `docs/DECISIONS.md`). `e2e_store.py` 482 checks on SQLite and 486 on PostgreSQL; the new checks fail on 939d377. `e2e_payments_review`, `e2e_points_live_plan` and `e2e_access_hooks` pass. No route change, so no snapshot regeneration. Extra: the Moyasar webhook never routes a payment tagged `points_token` / `payment_token` / `fee_token` to a store order, so that product's own handler still gets it. API notes are in `FLUTTER_API_CHANGES.md` "Store 5.R fixes". The #8 B6 line is in the `store_service` docstring; the B6 brief itself is still owed in the front docs.

#### Nice to have
- The Moyasar decline path in `card_return` (`orders.py:459-463`) fails the order from the unverified query string. Re-fetch the payment when an `id` is present before failing it. A verified success repairs the order today, but the page says "failed".
- `cover_url` accepts any string. Require `https://`, or a URL our storage made.
- `POST /store/checkout/moyasar/attach` needs no login and has no rate limit. Add the usual IP limiter.
- VAT follows the buyer's self-declared study-profile country (`vat_country`). That's fine for now; note it in D-1331 so finance knows.
- `order_dict` shows the buyer a `failure_reason` with the `expected=/actual=` amounts. Map it to a code for the buyer and keep the detail for `admin_orders`.
- When the super admin turns `teacher_items` on, consider turning `review_required` on by default. The contract default is false, so this is an owner decision.

### 5.R back re-check (planner, 2026-11-20): verified — back 18185ae
I read the diff of all 8 must-fix items; they are in as written. I didn't run the suite; the test counts are the lead's: 482 checks on SQLite, 486 on PostgreSQL.
- Moyasar: `settle_moyasar` is strict on `store_token` and refuses the foreign tokens.
- Paymob: `paymob_linked` is strict, and `_open_checkout` fails closed (502) when there's no `intention_order_id`.
- Duplicates: a points or free order rolls back with `already_owned` → 409 and nothing debited; a card order keeps `paid` and records `duplicate_item_ids` / `needs_refund`.
- Uploads: `sniff_type(head_bytes())` decides the type, never the uploader's Content-Type.
- Review: `require_store_admin` is `is_super_admin`.
- Re-review: `back_to_review` runs on a changed reviewed field and on a confirmed file.
- Currency: `MINOR_DIGITS` + `minor_units(amount, currency)`, and `_apply` accepts 2-digit currencies only.
- Settings: `ImportError` / `AttributeError` stay at debug, anything else is a warning; the buyer's calls resolve per country.

The addition beyond the brief is correct. `order_for_moyasar` returns None for a payment tagged `points_token` / `payment_token` / `fee_token`, so the webhook falls through to that product's own handler instead of answering `store:not_linked` and swallowing the event. `D-1338` is recorded.

### 5.R front review (planner, 2026-11-20) — front c997df11 (F7) + ce2a84de (F8)
**Verdict: good, with five must-fixes.**

What's right:
- No screen, model or test fixture reads or shows `file_ref` / `preview_ref` (grep over `lib/features/store/` and `lib/features/admin/edu/`).
- Encrypted library on phone / desktop (`store_vault_io.dart`):
  - the file is encrypted while it downloads (AES-256-CTR, "EFV1" | nonce | ciphertext, the offline-video scheme), so no plain copy is ever written;
  - one random key per file in the Keystore / Keychain (`unlocked_this_device`);
  - the SHA-256 is checked before the copy is kept;
  - the reader decrypts into memory only.
- `StoreReaderPage` uses `ScreenSecurity.instance.protect(this)` / `release(this)` (D-083), never the plugin.
- On the web nothing is kept; the library opens the 120 s link in the browser. That is an accepted gap: the web has no screen protection anyway.
- Checkout: one `Idempotency-Key` per attempt, and `store_already_owned` lands in the library. The card path goes through `openPointsPaymentPage`, then polls `GET /store/orders/{id}` for at most 2 min. That poll is on a timer like the points top-up it copies; acceptable, see the nice-to-haves.
- `buyStoreItem` resumes through `resumeStoreBuy`. The store tab follows `student_tab_store`. The admin hub card is `admin.store` for the super admin and `store.manage` for others, which matches the back.
- `pubspec.lock` gains only `pdfrx` 3.0.0 and its own deps (`pdfrx_engine`, `pdfium_dart`, `pdfium_flutter`, `native_toolchain_c`, `glob`, `process`); nothing is downgraded.

The points you asked about:
- **`pdfrx` on web and desktop.** It's OK.
  - Mobile and desktop use PDFium through a build hook (`pdfium_dart/hook/build.dart`). The hook downloads the prebuilt binary from `github.com/bblanchon/pdfium-binaries` at BUILD time, so the owner's runner, Codemagic and CI need GitHub access during the build. Each ABI or desktop target gains about 5–6 MB (the PDFium library).
  - On the web the package ships `assets/pdfium.wasm` (5.2 MB) + `pdfium_worker.js` (108 KB) into `build/web/assets`. The browser fetches them only when a `PdfViewer` opens, and on the web the reader never opens (no vault), so this costs deploy size, not page load.
  - Nice to have: put `store_reader.dart` behind the same conditional import as the vault, so the web build drops the wasm.
- **Covers through `/api/v1/org/public/uploads`.** Not acceptable; must-fix 1.
  - That route lives under the org prefix: with organizations switched off it answers 403 `orgs_disabled`, so a non-org teacher (and the super admin) can't set a cover.
  - The file lands under `org-member-files/{user}` with no image check.
  - `cover_url` stays free text.
- **No "rejected" status.** Rejected → draft is acceptable; the review queue stays simple. But the reason only travels in the push notification, so the manage page shows a plain "Draft". Nice to have: a `review_note` on the item, in the next store migration.
- **No help ids.** Must-fix 3: the CLAUDE.md rule is that every page has its "i", and `help_ids_test.dart` guards it.
- **At rest and on sign-out.** The files are encrypted at rest, but sign-out doesn't wipe them. The keys are named per item, not per user, and `wipe()` says "Phase 7". On a shared phone the next account keeps the previous buyer's copies and keys. Must-fix 2.
- **Housekeeping.** The uncommitted changes to the `linux/` and `windows/` `generated_plugin_registrant*` / `generated_plugins.cmake` files come from a local `flutter pub get` (they add plugins that predate the store). Don't commit them with the store; restore them with `git checkout -- linux windows`, or commit them separately on purpose.

#### Must-fix — brief for one Opus agent (both repos)
Work in `_wt/lh-back` and `_wt/lh-front`, on top of back 18185ae and front 6c4fc456. Don't run `dart format`. Test only around the change. Commit per repo; don't push.

1. **A store cover upload of its own (back + front).**
   - Back: add `POST /api/v1/store/manage/items/{item_id}/cover`, multipart `file`, in `features/store/api/store_manage_router.py`:
     - `require_manager` + `managed_item` (owner or admin);
     - read at most 2 MB and check the type with `store_service.sniff_type`: jpeg / png / webp only, else 422 `store_bad_file_type`;
     - store it through the existing public image upload helper (the one `store_upload` in `org_member_router.py:214` wraps), under `store-covers/{item_id}/`;
     - set `cover_url` and call `back_to_review`;
     - answer `manage_item`.
   - Back, `_apply`: accept a `cover_url` only when it is empty or starts with the public storage base URL (or `https://`); otherwise 422 `store_bad_cover`.
   - Back, docs: regenerate the route snapshot (`export_api_paths.py --front ../nextbrain-front`, pointed at `_wt/lh-front`) and add a line to `FLUTTER_API_CHANGES.md`.
   - e2e: a PNG → 200 with `cover_url` set; PDF bytes → 422; another teacher's item → 404; a teacher's change to a published item with `review_required` → `pending`.
   - Front: in `lib/features/store/manage/store_manage_api.dart:385`, replace `/api/v1/org/public/uploads` with the new route. Upload after the item exists; on create, save first and then upload.
2. **Wipe the kept files on sign-out (front).**
   - In `MyAuthProvider.logout()`, next to `clearGuestHandoff()`, call `await StoreVault.instance.wipe()` (the stub is a no-op on the web).
   - On load, `store_library.dart` also removes kept copies whose item is no longer in the library (a revoked row).
   - Update the `wipe()` doc comment (it now runs at sign-out, not "Phase 7").
   - Test in `test/store/`: `StoreVault.test(dir:)` keeps 2 files; `wipe()` leaves no `.enc` and no keys. Reaching logout through a seam is enough.
3. **Help ids (back seed + front).**
   - Back: add the pages `store.browse`, `store.item`, `store.library`, `store.manage`, `admin.store` to `../back/data/help_seed.json` (Arabic + English, short).
   - Front: regenerate `assets/help/help_index.json` (`dart run tool/gen_help_index.dart ../lh-back/data/help_seed.json`).
   - Front: pass `helpPageId:` on the store tab header, the item page, My Library, the manage page and the admin store hub.
   - Gate: `test/ui/help_ids_test.dart`, `test/ui/help_index_test.dart`.
4. **No raw failure text for the buyer (back + front).**
   - Back: `order_dict` (`features/store/orders.py`) gains `failure_code`: `declined` | `amount_mismatch` | `currency_mismatch` | `transaction_reused` | null. Derive it from the prefix of `failure_reason`. Keep `failure_reason` only in `admin_orders`; the buyer's `my_order` / `my_orders` / `create_order` answers drop it.
   - Front: `StoreOrder.failureCode`, and `store_checkout.dart` shows `storeCodeText(code)` with bilingual texts. Today it shows `a.order.failureReason` (e.g. `declined: …` or `amount_mismatch expected=11400 actual=…`).
   - Update the contract fixture or payload if `test/contract/` holds one.
5. **Keep the Idempotency-Key across a lost answer (front).**
   - `store_checkout.dart:146-160`: the generic `catch` sets `_key = null`. Reset the key only on a definite server answer (an `ApiException` with a status), not on a timeout or offline error. Then a retry after a lost response returns the same order instead of opening a second one.
   - Test in `test/store/`: a fake API that throws a timeout once and then answers; both calls carry the same key.

**Gates:**
- Back: `tests/learning_hub/e2e_store.py` on SQLite (PostgreSQL once at the end), plus the snapshot export.
- Front: `flutter analyze --no-fatal-infos --fatal-warnings lib/features/store lib/features/auth`, and `flutter test test/store/ test/ui/store_layout_test.dart test/ui/store_manage_layout_test.dart test/ui/help_ids_test.dart test/ui/help_index_test.dart test/contract/`.

#### Nice to have
- `pdfrx` off the web build: a conditional import for `store_reader.dart` (stub on web), which saves the 5.2 MB wasm in `build/web`.
- The order wait (`pollStoreOrder`, every 3 s for up to 2 min) is a timer poll, like the points top-up. Later: a `store_order` live event from `settle` (paid / failed) and `JobWatch` with a slow poll fallback (CLAUDE.md real-time rule).
- A `review_note` on `store_items` (next store migration), shown on the manage card as "Returned: …".
- The item page opens the preview in an external browser. On phones, consider the in-app reader without caching.

#### Status (lead, 2026-11-20): must-fix 1–5 fixed, plus the QA_PHASE5 high / medium items — back + front D-1339
1. **Fixed.** `POST /store/manage/items/{id}/cover` (JPEG / PNG / WEBP by the bytes, ≤ 2 MB, owner / admin, re-review), stored in the public images bucket (a lasting absolute URL, not the org member upload); `_apply` refuses a `cover_url` that is not `https://` or ours (422 `store_bad_cover`). Front: the editor saves a new item first, then uploads.
2. **Fixed.** `MyAuthProvider.logout` → `wipeStoreFiles` (every `.enc` + every `store_file_key_*`); My Library prunes copies of revoked rows; `wipe()` doc updated. Test `test/store/store_review_fixes_test.dart`.
3. **Fixed.** `store.browse`, `store.item`, `store.library`, `store.manage`, `admin.store` in `help_seed.json`, `help_index.json` regenerated, wired on the five pages.
4. **Fixed.** `failure_code` for buyers (`failure_reason` only in `admin_orders`); `storeFailureText` in the checkout and the purchases list.
5. **Fixed.** The checkout drops the key only on a definite server answer (`storeDefiniteAnswer`); test: a timeout then a retry carries the same key.
QA: admin cannot publish another seller's item / skip review (`store_not_owner`, only the super admin skips review); VAT by the item's country; covers absolute; header icons; pinned Buy bar on phones; device refusal explained + switch dialog; `/store/<id>` and `/store/library` routes; settings read from `module_settings` rows when the table exists (no shim). Tests: `e2e_store.py` 626 checks SQLite / 630 PostgreSQL; front store tests, `pending_intent_test`, `test/contract/` (snapshots regenerated), help tests, analyzer 0. Re-walk: `QA_PHASE5.md` "Re-test".

### Phase 6 briefs: ready
PLAN Phase 6 (waves A/B: B6, B7, S1, then F9, F10, F11) and CONTRACT §6 are complete enough to start. Add three lines to the briefs:
1. **B6:** `module_settings.resolve(db, module, *, country=None, org_id=None) -> dict` is the signature the store already calls. The code registry holds `store_service.DEFAULTS` as module `store` (10 / false / false / false). The country layer reads the buyer's study-profile country.
2. **B6 / F11:** the module switches page lists the `store` flags, `points_enabled` / `teacher_items` / `review_required` / `download_daily_limit`, with `review_required` explained next to `teacher_items`.
3. **F9–F11:** the student tab count has grown with `store`. The "nine student tabs on a phone" decision (D-1340) is taken at the Phase 6 review, with the store counted.

### 5.R re-check (planner, 2026-11-20): verified — back ad2be80, front b0cd782c
I read the diffs of all five front must-fixes; they are in as written. I didn't run the tests; the results are the lead's: e2e_store 626 checks on SQLite and 630 on PostgreSQL, the front store / contract / help tests pass, the analyzer is clean.
1. **Cover route.** `POST /store/manage/items/{id}/cover`: 404 for someone else's item before reading the body; at most 2 MB + 1 bytes read; the type comes from `sniff_type`; the file goes to the public images bucket under `store-covers/{id}/`; then `back_to_review`. `_apply` takes a `cover_url` only when it is `https://` or one of our image URLs (`store_bad_cover`). The front calls the new route; the org upload route is gone.
2. **Sign-out wipe.** `MyAuthProvider.wipeStoreFiles()` runs in `logout`. `wipe()` also clears leftover keys and part files, and `prune(owned)` runs when the library loads.
3. **Help ids.** `store.browse`, `store.item`, `store.library`, `store.manage` and `admin.store` are in the back seed, `help_index.json` and the fixture, and all five pages wire them.
4. **Failure codes.** `failure_code` comes from the reason's prefix; `failure_reason` is sent only to `admin_orders`; the front shows `storeFailureText(code)`.
5. **Idempotency key.** It is reset only on a definite answer (`storeDefiniteAnswer`).

The extras are sound:
- **Review.** Only the owner submits, and only the super admin skips review. That closes the "hide, then publish" bypass.
- **VAT.** VAT follows the item's country. A cart with items from two countries gets a 409. An item with no country takes the buyer's country only when that country prices in the item's currency.
- **Store settings.** The store reads `module_settings` rows directly until the module exists, and checks for the table with the inspector, so a missing table never aborts a PostgreSQL transaction.

Card checkout and the phone reader were not re-walked (no provider keys locally), and stay on the deploy checklist. The `linux/` / `windows/` plugin registrant files are still uncommitted local `pub get` output; leave them out of the store commits.

### Phase 6 — run plan (planner, 2026-11-20): all Opus, waves of at most 3
This replaces the agent and model lines of PLAN Phase 6. The scope and CONTRACT §6 are unchanged.

| Wave | Agents (Opus) | Starts when |
|---|---|---|
| **6A — back** | B6 (switches + games), B7 (Quran + nahw), S1 (seed data) | now |
| **6B — front** | F9 (learn kit + games), F10 (Quran), F11 (nahw + module switches) | 6A is merged into `_wt/lh-back` and the contract snapshots are exported |

**Shared rules for every brief:**
- Work only in your own files.
- Use plain `def` routes (D-016).
- Back: run e2e on SQLite, and the lead runs PostgreSQL once before merging. Front: run the analyzer on your paths and only your own tests.
- Don't run `dart format`.
- Commit per repo; don't push.
- Take D-numbers from D-1340 – D-1349. B6 owns D-1340 – D-1342, B7 D-1343 – D-1345, the front agents D-1346 – D-1349.

#### B6 — `module_settings` + country layer + games (migration 0106)
**Owns:**
- `features/platform/module_settings.py` and its routes;
- the country layer in `feature_policy.py` and the theme response;
- `features/platform/feature_catalog.py`: ALL six Phase 6 keys (`student_tab_games`, `student_tab_quran`, `student_tab_nahw`, `games.rewards`, `quran.teacher_apply`, `admin.modules`). B7 adds none;
- `features/games/`;
- migration `0106` (`down_revision = "0105"`);
- `tests/learning_hub/e2e_module_settings.py` and `e2e_games.py`;
- the snapshot export.

**Compatibility with the store.** The store already reads this table itself; read `features/store/store_service.py` (`settings`, `_rows_resolve`, `_coerce`, `_settings_table`) before writing anything. Build EXACTLY this:
1. **Table `module_settings`.** Columns are named literally `id`, `module String(20)`, `scope String(10)`, `scope_key String(20) NOT NULL`, `values JSON`, `updated_by`, `updated_at`. The store's raw SQL is `SELECT scope, scope_key, "values" FROM module_settings WHERE module = :m`, so don't rename `values`.
   - Unique `(module, scope, scope_key)`.
   - `scope_key` values:
     - `platform` rows: `''`, never NULL (PostgreSQL treats NULLs as distinct, so the unique index would let two platform rows in);
     - `country` rows: the upper-case 2-letter code;
     - `org` rows: `str(org_id)`.
   - `values` is a JSON object of partial values, for example `{"points_enabled": true}`.
2. **Resolver.** `module_settings.resolve(db, module: str, *, country: Optional[str] = None, org_id: Optional[int] = None) -> Dict[str, Any]`.
   - The result is the registry defaults ← the platform row ← the country row ← the org row (org wins).
   - Unknown keys are dropped. Missing rows or a missing table give the defaults, and never raise.
   - The store calls exactly this, and from the moment the module exists it stops reading rows itself. A raise there only logs a warning and falls back to the defaults, which would silently switch off a super admin's choice.
3. **Registry.** `REGISTRY: Dict[str, Dict[str, Any]]` holds:
   - `store`: imported lazily from `features.store.store_service.DEFAULTS` (`download_daily_limit` 10, `points_enabled` false, `teacher_items` false, `review_required` false). Don't copy the values: one source;
   - `games`: `points_rewards` false, `points_daily_cap` 20;
   - `quran`: `teacher_verification_required` false, `content_review_required` false, `gender_matching` `"off"`, `self_log` true.
4. **Types.** Validate on `PUT` by the default's type, the same way the store's `_coerce` reads it:
   - bool: a JSON bool;
   - int: an int ≥ 0;
   - str: one of the allowed values, e.g. `gender_matching` is `off` | `same` | `prefer`. Confirm the set against RESEARCH.md / PLAN §3.
   
   Anything else is 422 `module_setting_bad_value`; an unknown module is 404 `module_unknown`; an unknown key is 422.
5. **Routes.**
   - `GET /api/v1/module-settings/{module}?org_id=`: the resolved values for the caller's study-profile country, or `?country=` for a guest.
   - `GET|PUT /api/v1/admin/module-settings/{module}?scope=&scope_key=`: super admin only (`is_super_admin`), kill switch `admin.modules`. A PUT replaces that scope's `values`; a body of `{}` deletes the row.
6. **Caching.** Keep a short in-process cache keyed by `(module, country, org_id)` (≤ 30 s), cleared on every PUT. The store calls `settings()` on every download and order.
7. **e2e, with the store wired through:**
   - a platform `download_daily_limit: 2` → the third `POST /store/library/{id}/download` that day is 429;
   - a country `SA` `points_enabled: true` → an SA buyer can pay with points while an EG buyer gets 403 `store_points_off`;
   - an org row beats the country row;
   - a bad type → 422.
   
   `tests/learning_hub/e2e_store.py` must stay green unchanged.

**Country layer:**
- `edu_countries.disabled_features` (add it in 0106 if it is missing) and `PUT /admin/edu/countries/{code}/features {disabled}`.
- `feature_policy.effective_disable_list` adds the country's keys: the study profile's country when signed in, `?country=` for a guest on the theme route.
- A super-admin OFF still wins.
- Test: a tab key in a country's list is hidden for that country only.

**Games:** CONTRACT §6 tables and routes.
- `POST /games/{id}/plays` is idempotent on `(user_id, client_id)`.
- Points only when `games.points_rewards` and the `games.rewards` switch are on, capped per day by `points_daily_cap`, through `points_service` in the same transaction.
- `GET /parent/children/{id}/games` works only for a linked child; otherwise 404.

Also add the `app_features_guide.json` entries for games and module switches.

#### B7 — Quran + nahw (migration 0107)
**Owns:**
- `features/quran/` and `features/nahw/`;
- migration `0107` (`down_revision = "0106"`, written against B6's revision id; until B6 lands, test on the SQLite `create_all` harness);
- `tests/learning_hub/e2e_quran_rules.py` and `e2e_nahw.py`;
- the `app_features_guide.json` entries for Quran and nahw.

**Rules:**
- Read the Quran flags with `module_settings.resolve(db, "quran", country=…, org_id=…)`. Until B6's module exists, put a local `try: … except ImportError: defaults` shim in ONE helper, so the lead can delete it at merge.
- `gender_matching`:
  - `same` blocks (403 `quran_gender_rule`) a booking or enrolment in a quran course whose teacher's gender differs from the student's;
  - `off` allows it;
  - `prefer` only sorts.
- `teacher_verification_required` hides unverified teachers and answers 403 `quran_teacher_unverified` on booking.
- `POST /quran/progress`:
  - allowed for the teacher of the student's course, or for the student only when `self_log` is on;
  - idempotent on `(recorded_by, client_id)`;
  - `surah` 1–114 and `from_ayah ≤ to_ayah ≤` that surah's ayah count, from S1's metadata.
- `GET /quran/meta` is served from S1's file.
- Nahw: `GET /nahw/lessons/{id}` sends the answers (the client grades offline, D-1343). Attempts are idempotent on `client_id`.

#### S1 — seed data (`back/data/learn_seed/`)
**Owns** only that folder plus a loader `scripts/dev/load_learn_seed.py` (idempotent, every row `is_demo=false` except the sample games).

**Files:**
- `quran_meta.json`: 114 surahs with `number`, `name_ar`, `name_en`, `ayahs`, and the 30 juz boundaries as `{juz, start: {surah, ayah}}`. Source: Tanzil quran-data, with the source and licence in `README.md`.
- `nahw.json`: 3 levels × 3 lessons × 5 exercises, in the CONTRACT §6 shapes, with `kind` from `choose` | `fill` | `classify`.
- `games.json`: 6 starter games over the 3 engines F9 builds. Agree the engine keys with this brief: `match`, `order`, `quiz`; the `config` shapes are in PLAN §3.5.

**Checks:** a JSON schema check in the loader. The ayah counts sum to 6236.

#### F9 — `lib/features/learn_kit/` + `lib/features/games/`
**Owns:**
- the games tab (`student_tab_games`);
- the three engines;
- progress, badges and the parent view;
- `learn_kit`: the shared question / result / progress widgets.

**Order of work:** commit `learn_kit` FIRST, as its own commit with a header comment naming its public API. F11 builds the nahw exercises on it.

**Rules:**
- A `client_id` UUID per play, kept until the server answers.
- Every widget goes through `expectNoLayoutErrors`.
- Perf: the student home's request budget doesn't move.

#### F10 — `lib/features/quran/`
**Owns:**
- the teacher list, with gender / goal / session-type filters through `CourseFilterBar`'s pattern (not a second filter kit);
- the teacher profile;
- booking = the existing course checkout;
- progress by surah and juz (from `GET /quran/meta`);
- the teacher's record sheet (`POST /quran/progress`, `client_id`);
- the `student_tab_quran` tab.

`quran_gender_rule` and `quran_teacher_unverified` get bilingual texts.

#### F11 — `lib/features/nahw/` + `lib/features/admin/modules/`
**Owns:**
- the nahw levels, lessons and exercises, on F9's `learn_kit`. Start with the reading screens and the admin page, and wire the exercises after F9's `learn_kit` commit;
- the module switches page.

**Module switches page:**
- Scope picker: platform / country / org.
- One section per registry module: `store`, `games`, `quran`.
- Each field typed from the GET answer: `AppSwitchTile` for bools, a number field for ints, `AppDropdown` for `gender_matching`.
- `review_required` is explained next to `teacher_items`.
- The country kill-switch editor uses `PUT /admin/edu/countries/{code}/features`.
- Kill switch `admin.modules`; super admin only.

**Review after 6B:**
- The switch model.
- The phone layout with every student tab: home, courses, store, games, Quran, nahw, … (decision D-1340, store counted).
- The planner reads `module_settings.py` against the store's reader.
