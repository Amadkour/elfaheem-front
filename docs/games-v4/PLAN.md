# Games v4: plan (planner: Fable, 2026-11-23). Waiting for the owner's approval; no code yet.

Base: `origin/production`, front `ec8dddd7` and back `242b14ce`. Branch `feature/games-v4` in both repos.
The spec is `REQUEST.md`. `DRAFT_OPUS.md` is the first draft; this plan checked it against the code and supersedes it.

## 0. Verified facts and corrections to the draft

| Draft assumption | What the code says | Plan change |
|---|---|---|
| Learner age from a profile birth date | `users.dob` exists (Date, nullable). `student_study_profiles` has `grade` / `grade_id`. | Age band from `dob`, else `grade + 5`, else asked once (band only). Stored in `game_profiles.age_band`. |
| Referral anti-fraud must be built | Already live in `features/rewards/referrals.py`: `self`, `device_seen`, `ip_burst`, month cap, qualify modes. | No new anti-fraud code, only tests and an unlock counter. |
| A 24 h coupon unlocked by N referrals | A referral never qualifies within 48 h of sign-up, and `reward_rules.valid_days` counts in days, so a 24 h coupon could never unlock. | Two timers: an unlock window (default 7 days), then `valid_hours` from the unlock (default 24). |
| Rounds return the items | `ranked.start_round` answers 403 when `games.champions` is off, and `round_id: null` when no ranked attempt is left. | A new `POST /games/{id}/draw` returns the items and calls the ranked round internally when it is allowed. |
| openpyxl is needed | `openpyxl==3.1.2` is already in `requirements.txt`. | XLSX import needs no new package. |
| Coins can reuse points | `user_points` is a money wallet (card top-ups; buys the live plan). | Coins are a separate wallet with no money value. |
| Class challenges use org classes | No class entity exists, only `org_sections` (course + term). | A class is a course; class challenges are course vs course. |
| `engine` is String(12) | True, and `platform_jumper` / `fractions_farm` do not fit. `category` is String(10). | Widen `engine` to 24; new levels use `game_subject_id`. |
| A trace must be complete | v3 `grade()` raises `BadTrace("incomplete")`. | The v4 kinds accept a round that the timer or lives ended; unanswered items count as wrong. |
| Winners, coupons and referrals history is new | `/admin/rewards/*` and `admin_rewards_page.dart` exist. | Extend them, don't rebuild them. |
| Parallel backend agents can each add migrations | The Alembic head is 0125. | One agent owns all schema changes (0126–0128) as a gate. |
| Seeders call APIs at seed time | — | A dev script fetches the datasets once; they are vendored with a SHA-256 manifest, so seeding on the server needs no network. |
| KFGQPC font with Tanzil text | The two encodings differ in places. | Text and font come from one matched pair (decision 6). |
| Free LottieFiles characters | Agents cannot design these or fetch them reliably. | Characters are drawn in code; add `lottie` only when a real asset exists. |

T00 checks the rest: dataset URLs and licences, Flame on Flutter 3.47.7, whether courses carry `subject_id` for smart breaks, and a per-ayah audio source for Mukhtar Al-Haj.

## 1. Architecture and folders

```
back/
  data/games_models.py            + GameTemplate, GameSubject, GameItem, GameDraw, GameItemSeen, GameItemSrs,
                                    GameItemStat, GameLevelStat, GameProfile, GameCoinLedger, GameCosmetic,
                                    UserCosmetic, GameChallenge, GameChallengeTeam
  data/games_text_models.py       QuranAyah, QuranReciter, QuranAyahTiming, Hadith (read-only after seeding)
  data/games_seed/                vendored datasets + MANIFEST.json (sha256, source, licence) + curated banks
  features/games/
    templates.py                  17 template keys: kind, accepted item types, sacred_allowed, defaults
    items_schema.py               shared item schema validation (pure)
    items_grade.py                grading of the 8 kinds (pure, vector-tested)
    items_service.py              bank CRUD, review states, token resolver (@quran / @hadith)
    items_import.py               csv / json / xlsx dry-run + commit
    draw.py                       draw, SRS, seen, offline pool
    level_stats.py  analytics.py  suggest.py  challenges.py  cosmetics.py
    seeds/                        runner.py quran.py hadith.py math_gen.py banks.py auto_split.py
    api/games_v4_router.py        learner routes
    api/games_admin_v4_router.py  /api/v1/admin/games/v4/...
  features/rewards/               + age scope, locked coupons, valid_hours, course list
  migrations/versions/            0126_games_v4_content, 0127_games_v4_texts, 0128_games_v4_rewards

front/lib/features/games/
  core/       game_template.dart, game_session.dart, game_items.dart, game_audio.dart, age_theme.dart,
              game_art.dart, game_character.dart, game_fx.dart, flame_host.dart
  bases/      question_stage.dart, drag_board.dart, lane_runner.dart, floating_tokens.dart
  content/    games_v4_api.dart, level_cache.dart
  templates/  <one folder per template key>/
  engines/ shell/ champions/     existing (shell gains lives, timer, calm mode)
  admin/v4/   hub, templates, subjects, bank, editors/, review, import, levels, preview, analytics, seed, settings
  learner/    games_home_v4.dart, level_map.dart, wardrobe.dart, coupon_unlock_card.dart, trophy.dart, challenges.dart
  breaks/     play_now_button.dart, study_timer.dart, break_reminder.dart
```

Template interface. A template imports only `core/` and `bases/`:

```dart
abstract class GameTemplate {
  String get key;
  MechanicKind get kind;        // choose | select_all | sequence | classify | pair | fraction | program | combine
  Set<ItemType> get accepts;
  bool get sacredAllowed;       // fixed in code
  Widget build(GameSession s);
}
```

`GameSession` owns the items, settings, trace, score, lives, timer, calm mode, pause and `finish()`. A template only draws the game and reports `s.answer(i, a)`. Templates register in the existing `kGameEngines` registry through an adapter, so `GamePlayPage`, the leaderboard and the "needs a newer version" fallback keep working.

Shared bases:

| Base | Tech | Templates |
|---|---|---|
| `QuestionStage` | widgets | Challenge Quiz, Map Adventure, Growing Tree, Ghost Duel |
| `DragBoard` | widgets | Verse Builder, I'rab Hunter, Drag-to-Place, Science Lab |
| `LaneRunner` | Flame | Car Race, Space Rocket |
| `FloatingTokens` | Flame | Balloon Pop, Word Fishing, Word Train, Platform Jumper |
| own | painter / Flame | Fractions Farm, Robot Coding, Constellation |

Packages:
- `flame`;
- `flutter_animate`, its loops wrapped with `syncMotionLoop`;
- `sensors_plus` for tilt (phones only, behind a setting).

Audio stays on `audioplayers`. If Flame conflicts with the lock file, the fallback is a Ticker + CustomPainter loop behind the same `FlameHost` seam.

Art is procedural (gradients, soft shadows, parallax, character rigs) and themed by age: kids 6–9 vivid cartoon, teen 10–17, adult 18+ muted. Colours come from `context.colors` plus a per-theme game palette; sizes come from tokens.

## 2. Database and the shared content schema

### 2.1 New tables

| Migration | Table | Key columns |
|---|---|---|
| 0126 | `game_templates` | `key` PK, `enabled`, `defaults` JSON, `age_min`, `age_max`, `hidden_subject_ids` JSON, `sort` |
| 0126 | `game_subjects` | `id`, `key` (24) unique, `name_ar/en`, `icon`, `color`, `enabled`, `sacred`, `requires_review`, `edu_subject_ids` JSON, `sort` |
| 0126 | `game_items` | `id`, `subject_id`, `topic` (80), `type` (12), `difficulty` 1–5, `age_min`, `age_max`, `lang`, `status` (draft / pending_review / approved / rejected), `prompt` / `media` / `body` / `explain` / `source` / `tags` JSON, `rev`, `seed_key` (unique, nullable), `edited_by_admin`, `reviewed_by`, `reviewed_at`, `review_note`, timestamps; index (subject_id, status, type, difficulty) |
| 0126 | `game_draws` | `id` (36), `user_id`, `game_id`, `seed`, `items` JSON (snapshot as shown), `round_id` (nullable), `preview`, `issued_at`, `used_at`; pruned after 30 days |
| 0126 | `game_item_seen` | (`user_id`, `item_id`) PK, `seen_at` |
| 0126 | `game_item_srs` | (`user_id`, `item_id`) PK, `box` 1–5, `due_at`, `lapses` |
| 0126 | `game_item_stats` | `item_id` PK, `shown`, `correct`, `total_ms` |
| 0126 | `game_level_stats` | (`game_id`, `day`) PK, `starts`, `finishes`, `score_sum`, `max_sum`, `ms_sum` |
| 0127 | `quran_ayat` | (`surah`, `ayah`) PK, `text`, `words` JSON, `juz`, `checksum` |
| 0127 | `quran_reciters` | `key` PK, `name_ar/en`, `source_kind` (`per_ayah` / `per_surah_timed`), `url_pattern`, `licence_note`, `enabled`, `is_default`, `for_kids` |
| 0127 | `quran_ayah_timings` | (`reciter`, `surah`, `ayah`) PK, `start_ms`, `end_ms`, plus optional word timings, for per-surah reciters |
| 0127 | `hadith` | `id`, `collection` (bukhari / muslim), `number`, `numbering`, `book`, `chapter`, `text_ar`, `words` JSON, `word_count`, `grade`, `grade_source`, `checksum`; unique (collection, numbering, number) |
| 0128 | `game_profiles` | `user_id` PK, `age_band`, `age_source` (dob / grade / asked), `coins` (CHECK ≥ 0), `equipped` JSON, `sky` JSON |
| 0128 | `game_coin_ledger` | `id`, `user_id`, `delta`, `reason`, `ref`; unique (user_id, reason, ref), which makes awards idempotent |
| 0128 | `game_cosmetics`, `user_cosmetics` | `key`, names, `slot` (hat / outfit / vehicle / trail), `price_coins`, `unlock_rule` JSON, `enabled`; the rows a user owns |
| 0128 | `game_challenges`, `game_challenge_teams` | `id`, `kind` (friends / class), `game_id`, `seed`, `owner_id`, `code` unique, `week_start`, `status`; a team is a `course_id` or a friends list |

Changes to existing tables are all additive, so old rows keep playing:

| Table | Change |
|---|---|
| `games` | `engine` widened to String(24); new `game_subject_id`, `topic`, `level_no`, `age_min`, `age_max`, `template_settings` JSON, `item_source` JSON, `unlock` JSON, `coins_reward` |
| `game_plays` | new `draw_id`, `ghost` JSON (`[[ms, right]]`, kept 30 days) |
| `reward_rules` | new `valid_hours`, `unlock_referrals`, `unlock_days`, `course_ids` JSON |
| `coupons` | new status `locked`; new `unlock_need`, `unlock_deadline`, `unlocked_at`, `course_ids` JSON |
| champions | `SCOPE_KINDS` gains `age` (`6-9`, `10-13`, `14-17`, `18+`); no column change |

`item_source` is `{mode: "fixed", item_ids}` or `{mode: "pool", topic?, types, difficulty: [lo, hi], count}`. `unlock` is `{mode: "open"}` or `{mode: "prev", min_stars: 1}`. Item difficulty maps to the existing rank-points levels: 1–2 easy, 3 medium, 4–5 hard.

### 2.2 Shared content JSON

```json
{
  "id": 812, "rev": 1, "type": "sequence", "subject": "quran", "topic": "juz_30/112",
  "difficulty": 1, "age_min": 6, "age_max": 30, "lang": "ar", "status": "approved",
  "prompt": {"ar": "رتّب كلمات الآية", "en": "Put the words of the ayah in order"},
  "media": {"image": null, "audio": {"kind": "quran", "reciter": "default"}},
  "body": {"mode": "order", "tokens": "@quran:112:1", "distractors": 2},
  "explain": {"ar": null, "en": null},
  "source": {"kind": "quran", "ref": "112:1"}, "tags": []
}
```

| `type` | `body` | Trace `a` | Points |
|---|---|---|---|
| `mcq` | `{options: [{text, image?}], answer}` | option index | 1, first try |
| `true_false` | `{answer}` | 0 / 1 | 1, first try |
| `select_all` | `{options, answers}` | sorted index list | 1 if the set is exact |
| `sequence` | `{mode: order / complete / next_word, tokens: [..] or "@quran:s:a[-b]" or "@hadith:id", blanks?, distractors?}` | `[slot, token]` | 1 per slot, first try |
| `classify` | `{buckets: [{key, label}], tokens: [{text, bucket, case?}], cases?}` | `[token, bucket, case?]` | 1 per bucket, +1 per case |
| `pair` | `{pairs: [{a, b, image?}]}` | `[a, b]` | 1 per pair, first try |
| `fraction` | `{shape, n, d}` or `{op, a: [n, d], b: [n, d]}` | `[n, d]` | 1 if equivalent |
| `program` | `{w, h, start, goal, walls, cmds, max, par}` | command list | 1 for reaching the goal, +1 at par or better |
| `combine` | `{ingredients: [{key, label, image?}], answer, fx}` | sorted key list | 1, first try |

Rules:
- The trace stays `{i, a, ms}`. An item may have several entries; only the first attempt scores.
- A round the timer or lives ended is still valid.
- The server resolves `@quran` and `@hadith` tokens from the stored text and compares token indices, never strings.
- The draw fixes the order of options and tokens.

### 2.3 Play flow

| Step | Route | Notes |
|---|---|---|
| Draw | `POST /games/{id}/draw` → `{draw_id, seed, sacred, settings, items, round_id or null, ranked_left}` | Order: SRS items that are due (≤ 30 %), then never seen, then not seen in 7 days, then the rest. Filters: approved only when the subject requires review; the learner's age band; the template's accepted types. |
| Play | existing `POST /games/{id}/plays` + `draw_id` | Grades against the snapshot. Updates seen, SRS (wrong → box 1, due the next day; right → 1, 3, 7, 14, 30 days), item and level stats, coins and the ghost. |
| Offline | `GET /games/{id}/pool` → up to 3 × count items + audio URLs | Cached in the existing local DB; the device draws; the play goes through the existing outbox, unranked. The web stays online-only. |
| Old apps | `GET /games` lists v4 levels only with `?v=4` | Older builds never see levels they cannot play. |

## 3. Templates

Settings on every template, overridable per level:
- `timer_s`;
- `lives` (0 = unlimited);
- `speed` 1–5;
- `penalty`: none, soft or lives;
- `theme`: auto, kids, teen or adult;
- `music`, `hints`, `tilt`.

Stars use the existing 90 / 60 / 30 % thresholds.

| # | Template | Base | Kind | Mechanics | Scoring | Quran / Hadith |
|---|---|---|---|---|---|---|
| 1 | Car Race | LaneRunner | choose, sequence | Lanes carry the answers; swipe, tap or tilt. In Quran mode the ayah plays, then the road forks and each road has a word on a sign. | 1 per right lane, plus a speed boost | yes: calm palette, no speed bonus |
| 2 | Word Fishing | FloatingTokens | sequence | Fish carry letters or words; catch them in order. | 1 per catch in order | yes: the tokens become pearls |
| 3 | Map Adventure | QuestionStage | choose | Stations along a path; a right answer opens a chest. | 1 per station, first try | yes |
| 4 | Science Lab | DragBoard | combine, choose | Drag ingredients into a flask: fizz, colour or glow, then a cause-and-effect question. | 1 per right mix | no |
| 5 | Fractions Farm | own | fraction | Slice a pizza or a field, plant the parts, harvest. | 1 for an equivalent fraction | no |
| 6 | Drag-to-Place | DragBoard | classify, pair | Drag labels to slots on a picture or board. | 1 per slot | yes |
| 7 | Robot Coding | own Flame grid | program | Arrange arrows (and LOOP), then press Run. | goal + par bonus; the server simulates the run | no |
| 8 | Challenge Quiz | QuestionStage | choose | Timed, streak combos, leaderboard, badges. | right answers + time bonus | yes: no time bonus |
| 9 | I'rab Hunter | DragBoard | classify | Drag each word into its basket, then set its case ending. | 1 for the basket + 1 for the case | curated sentences only |
| 10 | Verse Builder | DragBoard | sequence | Hear the ayah and arrange its shuffled words; Complete mode fills the blanks. | 1 per slot | yes (the main Quran template) |
| 11 | Space Rocket | LaneRunner | choose | Steer through the planet that holds the right answer. | 1 per planet | yes: calm palette |
| 12 | Platform Jumper | FloatingTokens | sequence | Jump on word platforms in order. | 1 per platform | **no, locked in code** |
| 13 | Balloon Pop | FloatingTokens | select_all | Pop only the right balloons. | right − wrong, never below 0 | **no, locked in code** |
| 14 | Word Train | FloatingTokens | sequence | Couple the arriving wagons in order. | 1 per wagon | yes |
| 15 | Growing Tree | QuestionStage | choose, sequence | Calm and untimed; each right answer grows a branch and a fruit. | right answers; never a penalty | yes |
| 16 | **Constellation** (new) | own Flame | sequence, pair | A night sky: draw from star to star in the right order. A finished set reveals a picture that joins the learner's personal sky. | 1 per link, first try | yes |
| 17 | **Ghost Duel** (new) | QuestionStage | choose | Tug-of-war against the replayed trace of a real player of the same level and age band. | right answers; a win pays coins | no |

Ghost Duel needs no real-time server: it replays `game_plays.ghost`, shows the name as "First L." and respects the leaderboard opt-out. It also drives the challenges.

Quran respect rules live in `GameSession` / `GameAudio`, not in each template:
- during a recitation the music stops and every SFX is silent;
- sacred content never gets `penalty: lives`, a time bonus, a buzzer or an explosion;
- a wrong answer replays the ayah and lets the learner retry;
- the text is read-only in the admin: picked by reference, never typed;
- Hadith follows the same calm rules.

## 4. Super Admin screens (entry `admin.games`)

The current games editor stays as "Classic games", behind a new hub.

| # | Screen | What the admin does |
|---|---|---|
| 1 | Hub | KPI cards (plays today, completion, average score), the "waiting for review" count |
| 2 | Templates | 17 cards with on/off; defaults (timer, lives, speed, penalty, theme, music); age range; hidden subjects |
| 3 | Subjects | List, add, on/off (Culture & fun included), the requires-review flag, linked course subjects |
| 4 | Content bank | Filters; one editor per item type with a live preview; Quran picker (surah, ayah range, reciter, audio check); Hadith picker (collection + number, text read-only); bulk edit; delete |
| 5 | Review queue | Approve or reject pending religious items with a note; permission `games.review` |
| 6 | Import wizard | Template file (CSV / XLSX / JSON) → upload → dry run with row errors → commit; religious rows land as pending |
| 7 | Levels | Per template and subject, drag to order. Wizard: template → content (fixed items or a pool) → difficulty, age, unlock rule → settings → Preview → Publish. "Auto-split" turns a pool into N levels. |
| 8 | Preview | Plays the level in the app, unranked, nothing saved; unapproved items carry a badge |
| 9 | Analytics | Plays, completion %, average score and time; the hardest items, each linking to its editor |
| 10 | Rewards (existing page, extended) | Coins, badges, outfits; daily winner scope; discount %, validity in hours, any or selected courses, referrals needed to unlock; history |
| 11 | Breaks and parents | Play now, reminders, study minutes, max break, parent summary |
| 12 | Seed console | Per subject: seeded / approved / pending; Run seed; Add more |

New kill switches: `games.templates_v4`, `games.challenges`, `games.breaks`, `games.cosmetics`, `admin.games_content`, `parent.games_summary`. Culture & fun is switched by its subject row.

New `games` module settings: `champions_daily_scope`, `play_now`, `break_reminders`, `study_minutes`, `break_max_minutes`, `parent_summary`, `srs`.

## 5. Rewards, winner, breaks, parents, challenges

| Feature | Design |
|---|---|
| Daily winner | The champions job gains the `age` scope; `champions_daily_scope` is platform or age, default age. The winner sheet shows a trophy animation on the next app open; the Hall of Champions stays the public board. |
| Discount | The coupon is issued `locked` with `unlock_need = N` and an unlock deadline. Referrals qualified after the issue date count. At N it becomes active for `valid_hours`, and the winner picks one course (any, or from `course_ids`). |
| Winner card | "2 of 5 friends joined" and a countdown: to the deadline while locked, to the expiry once unlocked. |
| Coins and outfits | Coins per level, spent only on cosmetics, worn by the explorer, car, rocket and robot. |
| Spaced repetition | §2.3, plus a "Review" chip on the games tab when items are due. |
| Challenges | Friends: a link fixes the level and the seed. Class: course vs course, with a weekly board by average rank points per active member. |
| Smart breaks | `GET /games/suggest?subject_id=&topic=` returns a random published level. "Play now" sits on the course page. A device study timer triggers a local notification or an in-app card. |
| Parent | The existing child report is cut to time played + games finished, behind `parent_summary`. |

## 6. Seeds, sources and review rules

| Subject | Source | How | Status |
|---|---|---|---|
| Quran text | Tanzil Uthmani, cross-checked against Quran.com API v4 | A dev script fetches once; files are vendored with SHA-256; a mismatch on any ayah aborts that surah. The whole text is stored. | approved |
| Quran starter levels (owner, 2026-11-23) | — | Juz 30, Al-Fatiha, Ayat al-Kursi, the last two ayat of Al-Baqarah, **Al-Kahf (18), Ya-Sin (36), Ar-Rahman (55)** | — |
| Recitation (owner, 2026-11-23) | **Mishary Alafasy** (default), **Al-Husary muallim** (kids), **Mukhtar Al-Haj** | Alafasy and Husary: per-ayah MP3 from everyayah.com by URL pattern. Al-Haj was not found on everyayah / mp3quran; Midad has him per surah. T00 looks for a per-ayah source; the fallback is per-surah files + `quran_ayah_timings` (from a timings source, or marked once in an admin timing tool). Every reciter gets a licence / permission note. Devices cache the files. | — |
| Hadith | Sahih al-Bukhari + Sahih Muslim, Arabic, open `hadith-api` dataset | Verbatim with collection, number, numbering scheme, grade `sahih` and grade source; only hadith of ≤ 25 words feed sequence games | text approved; questions about a hadith pending |
| Fiqh, Tafsir & Balagha | curated JSON bank | a `source` note per item | pending_review |
| Nahw, I'rab | curated sentences, never ayat | a basket + a case per word | pending_review |
| Math | generated by code | deterministic by seed | approved |
| Science, General, Culture & fun | curated bank with a source note | Fable spot-checks a sample at the gate | approved |

- No Quran or Hadith text is ever typed, generated or paraphrased; it is copied from the vendored files and checked against the checksums.
- Seeds are idempotent by `seed_key`. A re-run never overwrites `edited_by_admin` items and never restores deleted ones.
- `auto_split` builds the starter levels.

## 7. Task list (Fable = plan, contract, gates; sonnet = building; haiku = simple)

| Wave | ID | Repo | Task | Model | Depends on |
|---|---|---|---|---|---|
| 0 | T00 | both | CONTRACT.md; verify dataset URLs and licences and a per-ayah source for Al-Haj; agent briefs | Fable | — |
| 0 | T01 | both | `grading_vectors_v4.json` + payload fixtures | Fable | T00 |
| 1 | T10 | B | Models + migrations 0126–0128 on PostgreSQL (sole owner of schema) | sonnet | T00 |
| 1 | T11 | F | `flame`, `flutter_animate`, `sensors_plus`; lock-file check; `flame_host.dart`; web compile | sonnet | T00 |
| 1 | T12 | F | `core/`: GameTemplate, GameSession, trace, item models | sonnet | T01 |
| 1 | T13 | B | Dataset fetch script; vendored Quran / Hadith + MANIFEST; reciter timings for Al-Haj if needed | sonnet | T00 |
| G1 | — | both | Review the schema and the core interface | Fable | wave 1 |
| 2 | T20 | B | templates.py, subjects CRUD, template settings, module settings, catalog keys | sonnet | T10 |
| 2 | T21 | B | items_schema + bank CRUD + review states + `games.review` | sonnet | T10 |
| 2 | T22 | B | items_grade: 8 kinds, grid simulator, vectors | sonnet | T01 |
| 2 | T23 | B | Quran / Hadith seeders, token resolver, pickers, reciter sources (per-ayah / per-surah timed) | sonnet | T10, T13 |
| 2 | T24 | F | game_audio: recitation (both source kinds), music, SFX silence, cache | sonnet | T12 |
| 2 | T25 | F | age_theme, game_art, game_character | sonnet | T12 |
| 2 | T26 | F | game_fx + shell: lives, timer, hints, calm mode | sonnet | T12 |
| 2 | T27 | F | New sounds (gen_game_sounds.py) | haiku | — |
| 3 | T30 | B | draw.py: draw, SRS, seen, pool, level fields, unlock | sonnet | T21, T22 |
| 3 | T32 | B | Import CSV / JSON / XLSX | sonnet | T21 |
| 3 | T33 | B | Math generator, fractions, robot grids | haiku | T21 |
| 3 | T34 | B | Curated Fiqh, Tafsir & Balagha, Nahw, I'rab (pending) | sonnet | T21 |
| 3 | T35 | B | Curated Science, General, Culture & fun | sonnet | T21 |
| 3 | T36 | F | games_v4_api, level_cache, contract tests | sonnet | T12 |
| 3 | T37 | F | QuestionStage + DragBoard, with Challenge Quiz and Verse Builder | sonnet | T24–T26 |
| 3 | T38 | F | LaneRunner + FloatingTokens, with Car Race and Balloon Pop | sonnet | T11, T24–T26 |
| G2 | — | both | Review the four reference templates from PNGs (kids / adult, ar / en, phone / desktop) before fan-out | Fable | wave 3 |
| 4 | T40 | B | Play save: grade from the draw, stats, coins, ghost | sonnet | T30 |
| 4 | T48 | F | Play page wiring: draw, session, offline pool, result | sonnet | T36, T37 |
| 4 | T42–T47 | F | Map Adventure, Growing Tree, I'rab Hunter, Drag-to-Place, Space Rocket, Word Fishing | sonnet | G2 |
| 5 | T41 | B | Seed runner, auto_split, seed console routes | sonnet | T23, T30, T33–T35 |
| 5 | T50 | B | Analytics | sonnet | T40 |
| 5 | T51 | B | Rewards: age scope, locked coupons, valid_hours, course list | sonnet | T10 |
| 5 | T52–T56 | F | Word Train, Platform Jumper, Science Lab, Fractions Farm, Robot Coding | sonnet | G2 |
| 6 | T60 | B | Challenges, ghost pick, suggest, parent summary, break settings | sonnet | T40 |
| 6 | T61 | B | Cosmetics, coin shop, game profile / age band | sonnet | T40 |
| 6 | T62 | F | Constellation | sonnet | G2 |
| 6 | T63 | F | Ghost Duel | sonnet | T48 |
| 6 | T64 | F | Admin hub, Templates, Subjects | sonnet | T20 |
| 6 | T65 | F | Content bank, editors, Quran / Hadith pickers, ayah timing tool | sonnet | T21, T23 |
| 6 | T66 | F | Review queue + import wizard | sonnet | T32 |
| 6 | T67 | F | Levels wizard + preview | sonnet | T30, T48 |
| G3 | — | both | Review all 17 templates and the admin flows | Fable | wave 6 |
| 7 | T70 | F | Admin analytics | sonnet | T50 |
| 7 | T71 | F | Admin rewards, breaks, parents, seed console | sonnet | T41, T51, T60 |
| 7 | T72 | F | Games tab v4: subjects, level map, unlocks, Review chip, age-band ask | sonnet | T48, T61 |
| 7 | T73 | F | Coins + wardrobe | sonnet | T61 |
| 7 | T74 | F | Locked-coupon card + trophy | sonnet | T51 |
| 7 | T75 | F | Play now, study timer, reminders | sonnet | T60 |
| 7 | T76 | F | Challenges UI | sonnet | T60, T63 |
| 7 | T77 | F | Parent summary cut | haiku | T60 |
| 8 | T80 | B | Backend e2e `tests/games_v4/` | sonnet | wave 7 |
| 8 | T81 | both | Regenerate contract snapshots | haiku | wave 7 |
| 8 | T82 | both | Feature guide, help pages, translation audit | haiku | wave 7 |
| 8 | T83 | F | Layout-harness + a11y sweep | haiku | wave 7 |
| 8 | T84 | both | DECISIONS + docs | haiku | wave 7 |
| S9 | — | both | One full check: analyzer, suites, e2e, real web app with screenshots; merge | Fable | wave 8 |

At most 8 agents per wave. Every agent reads only the contract section its brief names, never runs `dart format`, uses the UI kit and tokens only, adds both ar + en strings, makes one commit per task, and only appends to router files.

Deploy: migrations 0126–0128 are additive, but they run on the production database, so **the deploy waits for the owner's explicit confirmation**.

## 8. Decisions taken

1. A level is a `games` row, so plays, progress, champions and reports need no new code.
2. Items come from a new draw route, not from the ranked-round route.
3. 17 templates use 8 grading kinds and 4 shared bases; only the first attempt scores; the timer or lives may end a round.
4. Coins are a separate wallet with no money value.
5. Datasets are vendored with checksums; seeding in production never calls the network.
6. Quran text is Tanzil Uthmani with a font built for that encoding (Amiri Quran, OFL), not KFGQPC; a render test over hard ayat guards the tashkeel.
7. Characters are drawn in code; no Lottie or Rive until real assets exist.
8. No Quran or Hadith in Platform Jumper or Balloon Pop, locked in code; Hadith gets the same calm rules as Quran.
9. Age is a band: from `dob`, else from the grade, else asked once.
10. A class is a course.
11. Break reminders are local notifications from the device.
12. The daily winner is per age group by default; the discount unlock reuses the existing referral qualification and anti-fraud.
13. One agent owns every migration; Fable reviews at three gates.
14. (Owner) Reciters: Alafasy, Husary muallim, Mukhtar Al-Haj. Starter surahs include Al-Kahf, Ya-Sin, Ar-Rahman.
17. (Gate G2, 2026-11-23) The Tanzil edition with pause marks is the vendored text; Amiri Quran is wired as the one Quran face; seeded Quran items stay approved (mechanical, checksummed); a learner without an age competes in the open group 18+; the server decides a Ghost Duel win. Details: CONTRACT §14 items 16–20; the polish bar for templates: BRIEFS.

## 9. Open questions (the default applies if there is no answer)

1. The winner's discount: referrals can't qualify within 48 h of sign-up today. Keep that, with 7 days to gather friends and 24 h to use the discount after it unlocks? Default: yes.
2. Car Race and Word Fishing with Quran words, using calm skins (words on signs, pearls)? Default: yes; only Jumper and Balloon Pop stay blocked.
3. Who reviews religious items? Default: the super admin and anyone they grant `games.review`.
4. Recitation audio: stream or mirror? Default: stream the per-ayah reciters from the public source; mirror a per-surah reciter to our storage once permission is confirmed.
5. Should this go to Alfaheem after NextBrain? Default: yes.
6. Mukhtar Al-Haj needs permission from the publisher (Midad or his office) before we stream or mirror his recitation. Will you get it? Default: he is seeded disabled, and launch runs on Alafasy + Husary.

## 10. Addendum (Fable, after the owner's Quran decisions)

**Reciters, migration 0127**
- `quran_reciters` gains: `riwayah`, `source_kind` (`ayah_files` / `surah_files`), `url_pattern`, `source_url`, `licence`, `permission_status` (verified / pending / denied), `permission_note`, `audience` (all / kids), `enabled`, `is_default`, `sort`.
- `quran_ayah_timings`: (`reciter_key`, `surah`, `ayah`) PK, `start_ms`, `end_ms`, `source` (dataset / admin), `marked_by`, `marked_at`.
- The draw always answers audio as `{url, start_ms, end_ms}`.
- A reciter can be enabled only when its permission is `verified`.
- An ayah with no audio for the chosen reciter falls back to the default reciter, silently.
- Per-surah files are cached once per surah on the device. On the web they need range requests + CORS, else mirroring.
- Seeded: Alafasy (default, ayah files), Husary muallim (kids, ayah files), Mukhtar Al-Haj (ayah files if T00 finds a source, else Midad per-surah + timings; seeded `pending` and disabled).

**Admin timing tool (screen 13)**
- The admin taps at the end of each ayah while the surah plays; each mark can be nudged ±100 ms and replayed.
- The surah list shows marked / total ayat.
- In the fallback case the launch scope is about 1,100 ayat, a few hours of tapping. An unmarked surah plays with the default reciter.

**Long ayat**
- An ayah of more than 12 words is never a full word-ordering item. It is played as complete the ayah, next word, or segments cut only at the waqf marks in the stored text. No cut is ever invented.
- Passages also get an "order the ayat" item.

**Task changes**
- T00: Al-Haj source + licences of all three reciters.
- T10: the timings table + the new reciter columns.
- T23: seed the reciters, the audio resolver with the fallback, timing routes.
- T24: segment playback (seek, stop at `end_ms`) + per-surah cache.
- T41: `auto_split` covers the launch scope and the long-ayah rule.
- T65: reciter cards show the licence and permission.
- T85 (new, wave 8, sonnet): the timing tool.

**Learner picks the reciter (owner, 2026-11-23)**
- Stored in `game_profiles.reciter_key`; null = the default, or the kids reciter for the 6–9 band.
- `GET /games/reciters` lists the enabled reciters; `PUT /me/games/profile` saves the choice; the draw takes a one-round override.
- Picker with a sample in the games settings, plus a quick switch in the Quran templates' top bar. Switching mid-round replays the ayah in the new voice and never changes the score.
- An ayah missing for the chosen reciter falls back to the default reciter.
- Offline audio is cached for the chosen reciter only.

**Decisions 15–16**: the reciter source abstraction with a permission gate per reciter; long ayat split only at the text's own waqf marks.
