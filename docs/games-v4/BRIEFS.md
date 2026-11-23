# Games v4: task briefs (Fable, 2026-11-23)

One brief per task T10–T85 of `PLAN.md` §7. `C§n` = `CONTRACT.md` section n. Read only the sections your brief names.

**Rules for every task**
- Worktrees: front `_wt/g4-front`, back `_wt/g4-back`, branch `feature/games-v4`. One commit per task with `git commit --only <your paths>` (other agents commit in the same tree).
- Read the repo's `CLAUDE.md` first. Never run `dart format`. Router files and `main.py`: append only.
- Front: UI kit and tokens only (`lib/design/`), `context.colors`, `appText`, `AppTime`, both `ar` + `en` strings in `assets/translation.json`, every new widget through `expectNoLayoutErrors`, decorative loops through `syncMotionLoop`.
- Back: errors with the games module's `err`; naive UTC; String sizes exact; no schema change outside T10 (ask the lead).
- Run only your own tests + the analyzer on your paths (`flutter analyze --no-fatal-infos --fatal-warnings <paths>`; back: `PYTHONUTF8=1 .venv312/Scripts/python tests/games_v4/<file>.py` with a per-run SQLite `DATABASE_URL`).
- Vectors: `docs/games-v4/grading_vectors_v4.json` (front, master) = `back/docs/games_v4/grading_vectors_v4.json`. `reference_grader.py` is the planner's reference of C§5–§7.
- Report in ≤ 10 lines: files, tests run, anything that differs from the contract.

## Wave 1

**T10 (B, sonnet): models + migrations 0126–0128.** Sole owner of the schema.
Files: `data/games_models.py`, `data/games_text_models.py` (new), `data/rewards_models.py`, `migrations/versions/0126_games_v4_content.py`, `0127_games_v4_texts.py`, `0128_games_v4_rewards.py`.
Read: C§12 (every column), C§9 seeded reciters, C§10 seeded subjects, C§11 seeded rule, C§2 template keys.
Do: the tables and alters exactly as C§12; seed rows in the migrations (17 templates, 10 subjects, 3 reciters, 8 cosmetics, the reward rule); downgrade for each.
Tests: `tests/games_v4/pg_migrations.py` on the `nb-pg` container (upgrade from 0125, downgrade, upgrade again; String sizes hold the longest values) + SQLite create_all.
Done: head 0128 on PostgreSQL and SQLite; old `games` rows untouched; no other task needs a column.

**T11 (F, sonnet): packages + FlameHost.** (started: `lib/features/games/core/flame_host.dart`, `test/ui/games_v4_flame_host_test.dart`)
Files: `pubspec.yaml`, `pubspec.lock`, `core/flame_host.dart`.
Do: add `flame`, `flutter_animate`, `sensors_plus`; the lock file gains only these and their own deps, nothing downgraded; `FlameHost` hides Flame behind one widget (pause, resume, reduce motion, a Ticker + CustomPainter fallback).
Tests: the host test; `flutter build web --release` compiles.
Done: lock-file diff reviewed in the report; web compiles; tilt code is behind `!kIsWeb`.

**T12 (F, sonnet): `core/` interface and models.**
Files: `core/game_template.dart`, `game_session.dart`, `game_items.dart`, `game_grade.dart`, `test/games/v4_grading_test.dart`.
Read: C§2, C§4 (snapshot), C§5, C§6, C§7; PLAN §1 (interface).
Do: item models from the snapshot JSON; `GameSession` (items, settings, trace with the end entry, score, lives, timer, calm, pause, `finish()`); Dart grading that mirrors C§6–§7; the adapter that registers templates in `kGameEngines`.
Tests: every case of `grading_vectors_v4.json` (score, max, per_item, counted, stars, rank_points, ghost, too_fast, refused traces, `program_runs`, `age_bands`).
Done: all vectors pass in Dart; a template needs only `core/` + `bases/`.

**T13 (B, sonnet): dataset fetch + vendored texts.**
Files: `scripts/dev/fetch_games_datasets.py`, `data/games_seed/quran_uthmani.txt`, `quran-data.xml`, `hadith_bukhari.json`, `hadith_muslim.json`, `MANIFEST.json`.
Read: C§13 (URLs, licences, hadith facts, cross-check rule), C§9 (words, segments).
Do: fetch once; keep the Tanzil file unchanged with its copyright block; MANIFEST = source URL, licence text, version, SHA-256, row counts, `crosscheck_diffs` against Quran.com v4; no Al-Haj timings exist to fetch (T85 makes them).
Tests: `tests/games_v4/datasets_unit.py`: checksums match, 6,236 ayat, 114 surahs, hadith row counts, no empty text kept.
Done: seeding needs no network; the diff list is in the report for gate G1.

## Wave 2

Gate G1 (2026-11-23) changed C§9 (the basmala), C§12 (seed values of record), C§13 (hadith facts, the cross-check result) and C§14 items 12–15: read them before the lines below.

**T20 (B, sonnet): templates, subjects, settings, catalog.**
Files: `features/games/templates.py`, `api/games_admin_v4_router.py` (new), `games_config.py` (accept template engines with `config {}`), `features/platform/module_settings.py`, `features/platform/feature_catalog.py`, `main.py`.
Read: C§1, C§2, C§10 (hub, templates, subjects rows; the Levels paragraph).
Do: the registry (kinds as a list per template, accepts, `sacred_allowed`, code defaults; `game_templates` rows are seeded with `defaults {}`, so every default lives in code), settings merge + sacred override, templates / subjects CRUD, the new `GameIn` fields with `bad_item_source` / `template_not_sacred` / `bad_template_settings`, six kill switches, eight module settings.
Tests: `tests/games_v4/e2e_templates.py`.
Done: a v4 level can be created through `/admin/games`; classic games unchanged.

**T21 (B, sonnet): item schema + bank CRUD + review.**
Files: `features/games/items_schema.py` (pure), `items_service.py`, admin router (items, bulk, check, review, reviewers).
Read: C§3, C§4 (snapshot body table), C§10 item rows.
Do: `check(item)` → 422 `bad_game_item {field, why}`; `resolve(item, seed)` → the snapshot form (`show`, `eq`, `blanks`, `extra`); status rules; soft delete; `rev`; `can_review`.
Tests: `tests/games_v4/items_unit.py` (every limit of C§3, `fixtures/items_stored.json` all valid) + `e2e_items.py`.
Done: an edited approved item of a review subject returns to `pending_review`; resolve is deterministic per seed.

**T22 (B, sonnet): grading.**
Files: `features/games/items_grade.py` (pure), `tests/games_v4/grading_unit.py`, `tests/games_v4/grading_vectors_v4.json` (a copy).
Read: C§5, C§6, C§7; `docs/games_v4/reference_grader.py`.
Do: `grade(items, trace)`, `simulate`, `stars`, `rank_points`, `age_band`, SRS step, coins per star: your own code, checked against the vectors.
Tests: every case of the vectors, the constants block included.
Done: 75 cases + program runs + age bands + srs + coins pass.

**T23 (B, sonnet): Quran / Hadith load, resolver, pickers, reciters.**
Files: `features/games/seeds/quran.py`, `hadith.py`, `features/games/texts.py` (token resolver, audio resolver), learner router (`GET /games/reciters`, `GET /games/quran/audio`), admin router (quran, hadith, reciters, timings).
Read: C§9, C§10 (quran / hadith / reciters rows), C§13.
Do: load the vendored files (checksum per ayah, abort a surah on mismatch); split the basmala off ayah 1 with the fetch script's `split_basmala` rule (C§9: import or mirror it, 112 lines, abort the surah when one does not split); `words` + `segments`; hadith: skip empty and sub-numbered rows, `arabic_number` whole numbers only, `chapter` from `metadata.sections` (C§13); reciter rows come from migration 0127, never from `reciters.json`; `@quran` / `@hadith` references; audio entries for both source kinds with the silent fallback; timings GET / PUT; matn marking.
Tests: `tests/games_v4/texts_unit.py` (2:1, 95:1 and 97:1 load without the basmala; 1:1 and 9:1 load whole; 6,236 ayat; Bukhari loads 7,554 rows) + `e2e_reciters.py` (fallback, unknown reciter 422, `bad_timings`).
Done: no text is typed anywhere in code or tests; a disabled reciter never appears.

**T24 (F, sonnet): `game_audio.dart`.**
Files: `core/game_audio.dart`, `core/recitation_cache.dart`.
Read: C§4 (`media.audio`), C§9 (reciters, resolver, the quick switch).
Do: play a playlist of `{url, start_ms, end_ms}` (seek, stop at `end_ms`); music and every SFX silent while a recitation plays; file cache per reciter (one file per ayah, one per surah for `surah_files`); web streams with range requests; `switchReciter(key)` re-resolves through `GET /games/quran/audio` and replays the current ayah.
Tests: `test/games/v4_audio_test.dart` with a fake player (SFX muted during recitation, stop at `end_ms`, switch replays).
Done: a segment of a 32 MB surah file starts without downloading the whole file on the web.

**T25 (F, sonnet): art.** Files: `core/age_theme.dart`, `game_art.dart`, `game_character.dart`.
Read: C§8 (age band → theme), PLAN §1 (art).
Do: three themes (kids, teen, adult) and a calm sacred palette, all from `context.colors` + a per-theme palette; procedural backgrounds; the character rig with the four cosmetic slots (draw by `slot` + `key`, with a default look for a key the app does not know; the seeded keys are in C§12; no religious dress or symbol on the character).
Tests: layout harness + a golden per theme under `test/visual/`.
Done: no hard-coded colour, no raw size; loops use `syncMotionLoop`.

**T26 (F, sonnet): fx + shell.** Files: `core/game_fx.dart`, `shell/game_shell.dart`.
Read: C§2 settings, C§5 (end entry, `h`).
Do: lives, timer, hints, pause and calm mode in the shell (a template names its mechanics in `GameTemplate.kinds`, a set); right / wrong / combo / finish effects; sacred rounds: no buzzer, no explosion, no life lost.
Tests: `test/games/v4_shell_test.dart` + layout harness.
Done: the shell writes the end entry (`timer`, `lives`, `quit`, `done`).

**T27 (F, haiku): sounds.** Done (`db7e6e17`).

## Wave 3

**T30 (B, sonnet): draw, pool, SRS, unlock.**
Files: `features/games/draw.py`, learner router `api/games_v4_router.py` (`draw`, `pool`), `games_service.list_games` (`v=4`, `locked`).
Read: C§4, C§7 (SRS), C§8 (`GET /games?v=4`).
Do: filters and tiers, the seeded shuffle, the snapshot row, the ranked round call, preview and review modes, the challenge seed, rate limit, level stats `starts`.
Tests: `tests/games_v4/e2e_draw.py` (tiers, age filter, sacred filter, `no_items`, `level_locked`, old list hides v4).
Done: two draws with one seed give the same items; a classic app's `GET /games` is unchanged.

**T32 (B, sonnet): import.** Files: `features/games/items_import.py`, admin router (`import`, `import/template`).
Read: C§3, C§10 import rows, `fixtures/admin_content.json` ("import file columns").
Do: CSV / XLSX (openpyxl) / JSON → items through `items_schema.check`; dry run and commit; row errors.
Tests: `tests/games_v4/e2e_import.py` with one file per format.
Done: a religious row lands `pending_review`; a bad row never blocks the good ones.

**T33 (B, haiku): math generators.** Files: `features/games/seeds/math_gen.py`.
Read: C§3 (`mcq`, `fraction`, `program` limits).
Do: deterministic by seed: arithmetic `mcq`, fractions (shape, add, sub), robot grids with a solver that sets `par`; difficulty 1–5 and ages.
Tests: `tests/games_v4/math_gen_unit.py` (same seed same items; every item passes the schema; each grid is solvable at `par`).

**T34 (B, sonnet): curated religious banks.** Files: `data/games_seed/banks/fiqh.json`, `tafsir_balagha.json`, `nahw.json`, `irab.json`, `features/games/seeds/banks.py`.
Read: C§3, PLAN §6. Every item has a `source` note; all `pending_review`; I'rab sentences are never ayat; no Quran or Hadith text typed (references only).
Tests: `tests/games_v4/banks_unit.py` (schema, unique `seed_key`, source present).

**T35 (B, sonnet): curated general banks.** Files: `data/games_seed/banks/science.json`, `general.json`, `culture_fun.json`.
Read: C§3. Source note per item; ages and difficulty set; `approved`; include `combine` and `pair` items.
Tests: the same `banks_unit.py`.

**T36 (F, sonnet): API + cache.** Files: `content/games_v4_api.dart`, `content/level_cache.dart`, `test/contract/` entries.
Read: C§4, C§8, C§9; `fixtures/learner_*.json`, `reciters.json`.
Do: typed calls for every learner route; parsers tested against the fixtures; the pool cache in the local DB (not on web: `kDownloadsAvailable` rule); audio of the chosen reciter only; re-download on Wi-Fi after a reciter change.
Tests: `test/games/v4_api_test.dart` over `FakeApi`.

**T37 (F, sonnet): QuestionStage + DragBoard, Challenge Quiz, Verse Builder.**
Files: `bases/question_stage.dart`, `bases/drag_board.dart`, `templates/challenge_quiz/`, `templates/verse_builder/`.
Read: C§2, C§4 (`show`), C§5 (`mcq`, `select_all`, `sequence`), C§9 quick switch.
Do: the two bases and the two reference templates; Verse Builder's top bar has the reciter quick switch.
Tests: trace tests per template (the vectors' item shapes) + layout harness.
Done: a wrong answer on a sacred item replays the ayah and lets the learner retry.

**T38 (F, sonnet): LaneRunner + FloatingTokens, Car Race, Balloon Pop.**
Files: `bases/lane_runner.dart`, `bases/floating_tokens.dart`, `templates/car_race/`, `templates/balloon_pop/`.
Read: C§2, C§5 (`mcq`, `sequence` `next_word`, `select_all`). Car Race Quran mode: calm palette, words on signs, the reciter quick switch.
Tests: plain-values presentational widgets through the layout harness; trace tests.
Done: 60 fps on the profile build in the report; Balloon Pop refuses a sacred draw in code.

## Wave 4

**T40 (B, sonnet): play save.** Files: `games_service.record_play`, `ranked.py`, `features/games/level_stats.py`, `cosmetics.py` (coins award only), learner router (`ghost`).
Read: C§8 (plays, ghost), C§6, C§7.
Do: the four steps of C§8; `draw_invalid`, `preview`, pool + `picked`; seen, SRS, stats, coins with the daily cap, ghost, `unlocked`.
Tests: `tests/games_v4/e2e_plays.py`.
Done: a duplicate `client_id` pays no coins twice; a v3 play is unchanged.

**T48 (F, sonnet): play page wiring.** Files: `game_play_page.dart`, `learner/result_sheet.dart`.
Read: C§4, C§8. Draw → session → play; offline: pool → outbox; the result (stars, coins, unlocked level); the "needs a newer version" fallback for an unknown template.

**T42–T47 (F, sonnet), one agent each:** Map Adventure (`map_adventure`, QuestionStage), Growing Tree (`growing_tree`, QuestionStage, reciter switch), I'rab Hunter (`irab_hunter`, DragBoard, 2-entry then 3-entry), Drag-to-Place (`drag_place`, DragBoard, `board.spots`), Space Rocket (`space_rocket`, LaneRunner), Word Fishing (`word_fishing`, FloatingTokens, pearls when sacred).
Files: `templates/<key>/`. Read: C§2, C§5 for your item types. Tests: a trace test + layout harness per template.

## Wave 5

**T41 (B, sonnet): seed runner + auto-split.** Files: `features/games/seeds/runner.py`, `auto_split.py`, admin router (`seed`, `seed/run`, `levels/auto-split`).
Read: C§10 (seed, auto-split), C§3 (long ayah rule), PLAN §6 (starter surahs).
Do: idempotent by `seed_key`; never overwrite `edited_by_admin`, never restore deleted; Quran starter levels (Juz 30, 1, 2:255, 2:285–286, 18, 36, 55).
Tests: `tests/games_v4/e2e_seed.py` (run twice = no change).

**T50 (B, sonnet): analytics.** Files: `features/games/analytics.py`, admin router. Read: C§10 analytics rows. Tests: `e2e_analytics.py`.

**T51 (B, sonnet): rewards.** Files: `features/rewards/issue.py`, `coupon_service.py`, `referrals.py`, `admin_service.py`, `features/games/champions.py`.
Read: C§11, C§1 (events, notifications). Tests: `tests/games_v4/e2e_locked_coupons.py` (lock, progress, unlock, deadline, wrong course, age scope).

**T52–T56 (F, sonnet), one agent each:** Word Train (`word_train`, reciter switch), Platform Jumper (`platform_jumper`, refuses sacred), Science Lab (`science_lab`), Fractions Farm (`fractions_farm`), Robot Coding (`robot_coding`, the simulator of C§6 in Dart).
Files: `templates/<key>/`. Read: C§2, C§5, C§6 for your types. Tests: trace test + layout harness.

## Wave 6

**T60 (B, sonnet): challenges, suggest, parent, breaks.** Files: `features/games/challenges.py`, `suggest.py`, learner router, `games_service.child_progress`. Read: C§8 (challenges, breaks, parent). Tests: `e2e_challenges.py`.

**T61 (B, sonnet): profile, reciter choice, cosmetics.** Files: `features/games/profile.py`, `cosmetics.py`, learner + admin routers.
Read: C§8 (profile, cosmetics), C§9 (`reciter_key`, effective reciter), C§7 coins.
Do: `GET / PUT /me/games/profile` (age band rules, `reciter_key` with 422 `reciter_unknown`, `equipped`), `home`, cosmetics list / buy, admin cosmetics.
Tests: `e2e_profile.py` (the vectors' `age_bands`, reciter fallback to kids / default, `age_fixed`).

**T62 (F, sonnet): Constellation.** `templates/constellation/` (own Flame; `sequence` order + `pair`; the finished picture joins `profile.sky`; reciter switch). Read: C§5.

**T63 (F, sonnet): Ghost Duel.** `templates/ghost_duel/`. Read: C§8 (ghost). The bot when `ghost` is null.

**T64 (F, sonnet): admin hub, templates, subjects.** `admin/v4/hub_page.dart`, `templates_page.dart`, `subjects_page.dart`. Read: C§10 first rows. `OrgPageBody`-style cards, `AppSwitchTile`, help ids.

**T65 (F, sonnet): content bank + editors + pickers.** `admin/v4/bank_page.dart`, `editors/` (one per type), `quran_picker.dart`, `hadith_picker.dart`, `reciters_page.dart`. Read: C§3, C§9, C§10. Sacred text is picked, never typed; reciter cards show licence and permission.

**T66 (F, sonnet): review queue + import wizard.** `admin/v4/review_page.dart`, `import_wizard.dart`. Read: C§10.

**T67 (F, sonnet): levels wizard + preview.** `admin/v4/levels_page.dart`, `level_wizard.dart`. Read: C§2, C§4 (preview), C§10 (levels, auto-split).

## Wave 7

**T70 (F, sonnet): admin analytics.** `admin/v4/analytics_page.dart` with `app_charts.dart`. Read: C§10.
**T71 (F, sonnet): admin rewards, breaks, parents, seed console.** `admin_rewards_page.dart` (new rule fields), `admin/v4/breaks_page.dart`, `seed_page.dart`. Read: C§1, C§10, C§11.
**T72 (F, sonnet): games tab v4.** `learner/games_home_v4.dart`, `level_map.dart`, `learner/games_settings_sheet.dart`. Read: C§8 (home, profile), C§9. One `home` call; Review chip; the age-band ask; the reciter picker (name + 3 s sample) in the settings sheet; the About sheet credits Tanzil.net with its link and the reciters' sources (C§13).
**T73 (F, sonnet): coins + wardrobe.** `learner/wardrobe.dart`. Read: C§8 cosmetics.
**T74 (F, sonnet): locked-coupon card + trophy.** `learner/coupon_unlock_card.dart`, `trophy.dart`. Read: C§11, `fixtures/rewards.json`.
**T75 (F, sonnet): Play now, study timer, reminders.** `breaks/`. Read: C§8 breaks. Local notifications only.
**T76 (F, sonnet): challenges UI.** `learner/challenges.dart`, a deep link in `AppNavigator`. Read: C§8.
**T77 (F, haiku): parent summary.** The child games card shows the four numbers. Read: C§8 parent.

## Wave 8

**T80 (B, sonnet): e2e.** `tests/games_v4/e2e_full.py`: seed → draw → play → SRS → coins → champion by age → locked coupon → unlock.
**T81 (both, haiku): snapshots.** `export_api_paths.py --front`; contract tests pass.
**T82 (both, haiku): guide, help, strings.** `data/app_features_guide.json`, help pages, translation audit.
**T83 (F, haiku): layout + a11y sweep** over `lib/features/games/`.
**T84 (both, haiku): DECISIONS + docs.** Fold C§14 and PLAN §8 into both `DECISIONS.md`.
**T85 (F, sonnet): ayah timing tool.** `admin/v4/timing_tool.dart`. Read: C§9, C§10 (timings rows). Tap at each ayah's end while the surah plays; nudge ±100 ms; replay a mark; save per surah; the list shows marked / total. Needed: Mukhtar Al-Haj is per surah (C§13).
