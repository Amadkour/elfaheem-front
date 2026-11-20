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
| 3.1 | Back: profile ids, teaching levels, consent, course fields (0103) | B3 | todo | |
| 3.2 | Front: registration capture (student, teacher, parent) | F3 | todo | |
| 3.3 | Front: course form + profile block | F4 | todo | |
| 3.R | Review: real web app, three registrations + one in-person course | planner | todo | |
| 4.1 | Back: search filters, indexes (0104), landing options / match | B4 | todo | |
| 4.2 | Front: join flow + PendingIntent hand-off | F5 | todo | |
| 4.3 | Landing: four entry buttons | L1 | todo | |
| 4.4 | Front: filter bar on explorer + student home | F6 | todo | |
| 4.R | Review: landing → join → course → login → checkout walk | planner | todo | |
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
