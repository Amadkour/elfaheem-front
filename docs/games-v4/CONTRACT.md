# Games v4: contract (T00, Fable, 2026-11-23)

The JSON every Games v4 task builds against. `PLAN.md` holds the reasons, `BRIEFS.md` the tasks. Test numbers:
`grading_vectors_v4.json` (made by `reference_grader.py`, the planner's reference of §5–§7). Example payloads: `fixtures/`.
The backend copy of this file is `back/docs/games_v4/CONTRACT.md`; the front copy is the master.

Conventions (the same as Games v3):
- Base path `/api/v1`. Errors are `{"detail": {"code", "message", …}}` (the games module's `err`).
- Datetimes are naive UTC ISO strings. `T|null` = always present, may be null. `T?` = may be absent.
- Old apps keep working: every new request field is optional, every new response field is additive.
- A kill switch that is off answers 403 `feature_disabled` with `feature: "<key>"`.
- Bilingual text is `{"ar": string|null, "en": string|null}`; at least one side is filled.
- Lists answer `{items, total, has_more}` with `skip` / `limit` (default 50, max 200) unless a route says otherwise.

Contents: 1 switches and settings · 2 templates · 3 items (stored) · 4 draw and the snapshot · 5 trace · 6 grading ·
7 stars, rank points, coins, SRS · 8 learner routes · 9 Quran, Hadith and reciters · 10 admin routes ·
11 rewards and champions · 12 migrations · 13 datasets and licences · 14 changes to the plan.

## 1. Kill switches, settings, events

**Kill switches** (new, `feature_catalog.py`; the existing `student_tab_games`, `games.champions`, `games.leaderboard`, `games.sounds`, `admin.games` keep their meaning):

| Key | Off means |
|---|---|
| `games.templates_v4` | no v4 levels in any list, `draw` / `pool` / `home` refused; classic games keep working |
| `games.challenges` | no challenge routes, no Ghost Duel challenge link, no class board |
| `games.breaks` | no "Play now" button, no study timer, no break reminders; `suggest` refused |
| `games.cosmetics` | no coins shown, no wardrobe, `buy` refused (coins are still recorded) |
| `admin.games_content` | the super admin's v4 hub hidden (classic editor stays under `admin.games`) |
| `parent.games_summary` | the parent's child games summary hidden; the route answers 403 |

**Module settings** (`module_settings.REGISTRY["games"]`, read by `GET /module-settings/games`, written by `PUT /admin/module-settings/games`):

| Key | Type | Default | Note |
|---|---|---|---|
| `champions_daily_scope` | `platform` / `age` | `"age"` | §11 |
| `play_now` | bool | `true` | the course page's button |
| `break_reminders` | bool | `true` | |
| `study_minutes` | int 10..180 | `45` | study time before a reminder |
| `break_max_minutes` | int 3..30 | `10` | the break timer shown while playing from a break |
| `parent_summary` | bool | `true` | with `parent.games_summary` |
| `srs` | bool | `true` | spaced repetition (§7) |
| `coins_daily_cap` | int 0..10000 | `200` | coins a user can earn a day; 0 = no coins |

Server constants, not settings: `MIN_STEP_MS = 400`, draw life 2 h, pool life 30 days, draws rate limit 60 an hour, `PROGRAM_RUNS = 3`, SRS share of a draw 30 %, "seen recently" 7 days.

**Reviewers.** `games.review` is not a kill switch: it is `game_profiles.can_review`. Platform admins always review; they grant others with `PUT /admin/games/v4/reviewers`.

**Attention.** No new tab key. The Review chip reads `review_due` from `GET /games/v4/home`.

**LiveEvents.** No new names. `rewards` gains two `kind` values: `coupon_progress` (`{coupon_id, have, need}`) and `coupon_unlocked` (`{coupon_id}`). `games_champions` gains `scope_kind: "age"`.

**Notifications.** `reward_coupon` is also sent when a locked coupon unlocks and 3 hours before an unlocked one expires (instead of 3 days when `valid_hours` ≤ 72). Break reminders are local notifications made by the device; the server sends none.

## 2. Templates

A v4 level is a `games` row whose `engine` is a template key. `config` is `{}` for it. The registry is `features/games/templates.py` (server) and `kGameTemplates` (app); `sacred_allowed` is fixed in code on both sides and no route can change it.

| Key (`games.engine`) | Kinds | Accepts item types | `sacred_allowed` |
|---|---|---|---|
| `car_race` | choose, sequence | `mcq`, `true_false`, `sequence` (`next_word`) | yes |
| `word_fishing` | sequence | `sequence` (`order`) | yes |
| `map_adventure` | choose | `mcq`, `true_false` | yes |
| `science_lab` | combine, choose | `combine`, `mcq` | no |
| `fractions_farm` | fraction | `fraction` | no |
| `drag_place` | classify, pair | `classify`, `pair` | yes |
| `robot_coding` | program | `program` | no |
| `challenge_quiz` | choose, select_all | `mcq`, `true_false`, `select_all` | yes |
| `irab_hunter` | classify | `classify` (with `cases`) | no (curated sentences only) |
| `verse_builder` | sequence | `sequence` (`order`, `complete`) | yes |
| `space_rocket` | choose | `mcq`, `true_false` | yes |
| `platform_jumper` | sequence | `sequence` (`order`) | **no** |
| `balloon_pop` | select_all | `select_all` | **no** |
| `word_train` | sequence | `sequence` (`order`) | yes |
| `growing_tree` | choose, sequence | `mcq`, `true_false`, `sequence` (`next_word`, `complete`) | yes |
| `constellation` | sequence, pair | `sequence` (`order`), `pair` | yes |
| `ghost_duel` | choose | `mcq`, `true_false` | no |

An item is sacred when its subject has `sacred: true` or its `source.kind` is `quran` / `hadith`. A draw is `sacred` when any of its items is. A template with `sacred_allowed: false` never receives a sacred item: the level editor refuses the source (422 `template_not_sacred`) and the draw filters such items out.

**Settings** (template defaults in code ← `game_templates.defaults` ← the level's `template_settings`; the draw answers the merged object):

| Key | Type | Default |
|---|---|---|
| `timer_s` | int 0..900, 0 = no timer | 0 (`challenge_quiz` 120, `car_race` / `space_rocket` / `balloon_pop` 90) |
| `lives` | int 0..9, 0 = unlimited | 0 (`car_race`, `space_rocket`, `platform_jumper` 3) |
| `speed` | int 1..5 | 3 |
| `penalty` | `none` / `soft` / `lives` | `soft` |
| `theme` | `auto` / `kids` / `teen` / `adult` | `auto` |
| `music` | bool | `true` |
| `hints` | bool | `true` |
| `tilt` | bool | `false` |
| `count` | int 1..30: items in a round | 8 (`robot_coding` 3, `fractions_farm` 6) |

Sacred override, applied by the server in the draw answer (and again by `GameSession`): `penalty: lives` becomes `soft`, `timer_s` stays but pays no time bonus, `calm: true` is added. `growing_tree` always answers `timer_s: 0`, `lives: 0`, `penalty: none`.

## 3. Items as stored (`game_items`)

```json
{"id": 812, "rev": 1, "subject_id": 1, "subject": "quran", "topic": "juz_30/112", "type": "sequence",
 "difficulty": 1, "age_min": 6, "age_max": 30, "lang": "ar", "status": "approved",
 "prompt": {"ar": "رتّب كلمات الآية", "en": "Put the words of the ayah in order"},
 "media": {"image": null, "audio": {"kind": "quran"}},
 "body": {"mode": "order", "unit": "word", "tokens": "@quran:112:1", "distractors": 2},
 "explain": {"ar": null, "en": null}, "source": {"kind": "quran", "ref": "112:1", "note": null}, "tags": [],
 "seed_key": "quran/112/1/order", "edited_by_admin": false, "reviewed_by": null, "reviewed_at": null,
 "review_note": null, "created_at": "…", "updated_at": "…"}
```

Common limits: `topic` ≤ 80; `type` one of the nine below; `difficulty` 1..5; `age_min` 4..99 ≤ `age_max` ≤ 99; `lang` `ar` / `en` / `both`; `prompt` each side ≤ 500; `explain` each side ≤ 1000; `tags` ≤ 10 of ≤ 30; `media.image` a platform image URL ≤ 1000 or null; `media.audio` null, `{"kind": "quran"}` (resolved from the tokens) or `{"kind": "url", "url"}`; `source` = `{kind: "quran" / "hadith" / "book" / "generated" / "curated", ref?: ≤ 120, note?: ≤ 300}`. Any text ≤ 200 unless said. `rev` goes up by 1 on every change of `body`, `prompt` or `media`.

Validation failures are 422 `bad_game_item` with `field` (path of the first bad value, e.g. `body.options[2].text`) and `why` (`text`, `empty`, `too_long`, `count_2_6`, `duplicate`, `out_of_range`, `unknown`, `ref`, `too_long_for_order`, `sacred_text`).

| `type` | Stored `body` | Limits |
|---|---|---|
| `mcq` | `{options: [{text, image?}], answer}` | 2..6 options, unique texts; `answer` an index |
| `true_false` | `{answer}` | bool |
| `select_all` | `{options: [{text, image?}], answers}` | 3..8 options; `answers` 1..(n−1) unique indices, stored sorted |
| `sequence` | `{mode, unit, tokens, blanks?, given?, distractors?, extra?}` | below |
| `classify` | `{buckets: [{key, label}], tokens: [{text, bucket, case?}], cases?: [{key, label}], board?: {image, spots: {<bucket key>: [x, y]}}}` | 2..6 buckets, keys `[a-z0-9_]{1,24}` unique; 2..12 tokens; `bucket` a bucket key; `cases` 2..6 when present and then `case` is a case key or null; `spots` x, y in 0..1 |
| `pair` | `{pairs: [{a, b, image?}]}` | 2..8 pairs; `a` sides unique, `b` sides unique |
| `fraction` | `{shape, n, d}` or `{op, a: [n, d], b: [n, d]}` | `shape` `pizza` / `bar` / `field`, `d` 2..12, `n` 1..`d`; `op` `add` / `sub`, denominators 1..12, numerators 0..24, the result ≥ 0 |
| `program` | `{w, h, start: [x, y, dir], goal: [x, y], walls: [[x, y]], cmds, max, par}` | `w`, `h` 3..8; `dir` 0 N, 1 E, 2 S, 3 W; ≤ 20 walls, none on start or goal; `cmds` a subset of `F`, `L`, `R`, `LOOP` holding `F`; `par` 1..`max` ≤ 30; the server checks the goal is reachable within `par` tokens only for generated items |
| `combine` | `{ingredients: [{key, label, image?}], answer, fx, result?}` | 3..8 ingredients, unique keys; `answer` 2..4 ingredient keys; `fx` `fizz` / `color` / `glow` / `smoke` / `freeze`; `result` bilingual |

`label` is bilingual. Grid `x` grows to the right and `y` grows down in data, in every language: the board is never mirrored.

**`sequence`**
- `mode`: `order` (place every token), `complete` (fill the `blanks`), `next_word` (the first `given` tokens are shown, the rest are picked one at a time).
- `unit`: `word` (default), `letter` (tokens are the letters of one word), `ayah` (each token is a whole ayah of a passage), `segment` (the waqf segments of one ayah, §9).
- `tokens`: a list of 2..12 strings, or one reference string: `@quran:<surah>:<ayah>`, `@quran:<surah>:<from>-<to>` (unit `ayah`, 2..8 ayat), `@hadith:<collection>:<number>`.
- `blanks`: `complete` only, 1..6 slot indices. `given`: `next_word` only, 1..(n−1); at most 6 tokens are left to pick.
- `distractors`: 0..4, how many wrong tokens the draw adds. `extra`: for a typed list, the wrong tokens themselves (≤ 4). For a reference the server takes them from the same surah (Quran) or the same collection's short hadith: they are always real words of the same text, never invented.
- An `order` item of unit `word` over a reference of more than 12 words is refused (`too_long_for_order`): use `complete`, `next_word` or `segment` (PLAN §10).
- Sacred text is never typed: an item whose `source.kind` is `quran` / `hadith` must use a reference (`sacred_text`).

**Status.** `draft` → `pending_review` (when its subject has `requires_review`) or `approved`. `rejected` and `pending_review` items are never drawn for a learner. Editing the `body` / `prompt` of an approved item of a `requires_review` subject sends it back to `pending_review`.

## 4. Draw and the snapshot

### `POST /games/{id}/draw`

Request (all optional): `{"mode": "play" | "review" | "preview", "reciter": "<key>", "challenge": "<code>"}`.

200:
```json
{"draw_id": "9f1c…uuid", "seed": 482913, "kind": "round", "sacred": true, "template": "verse_builder",
 "settings": {"timer_s": 0, "lives": 0, "speed": 3, "penalty": "soft", "theme": "auto", "music": true,
              "hints": true, "tilt": false, "count": 8, "calm": true},
 "items": [item], "max_score": 31, "round_id": "5b0e…uuid", "ranked_left": 2,
 "reciter": {"key": "alafasy", "name_ar": "مشاري العفاسي", "name_en": "Mishary Alafasy"},
 "issued_at": "2026-11-23T10:00:00"}
```
- `round_id`: `string|null`. The draw calls the v3 ranked round itself when `games.champions` is on and an attempt is left; null otherwise, and the round is played unranked. `ranked_left`: as v3.
- `reciter`: the learner's effective reciter, null when the draw has no Quran audio.
- Errors: 404 `game_not_found`; 422 `not_a_v4_game`; 403 `feature_disabled` (`student_tab_games`, `games.templates_v4`; `games.challenges` with `challenge`); 403 `level_locked`; 403 `template_off`; 409 `no_items` (nothing left after the filters); 422 `reciter_unknown`; 404 `challenge_not_found`; 409 `challenge_closed` and 403 `challenge_not_joined` (with `challenge`); 429 `too_many_attempts`.
- `mode: "preview"`: platform admins only (403 `admin_required`). Unapproved items are included and carry `status`; `round_id` is null; a play that names a preview draw is graded and answered but nothing is saved (§8).
- `mode: "review"`: due SRS items of this level's source come first with no 30 % cap.

**Which items.** From the level's `item_source`:
- `{mode: "fixed", item_ids}`: those items in that order, cut to `count`;
- `{mode: "pool", subject_id?, topic?, types?, difficulty: [lo, hi], count?}`: `subject_id` defaults to the level's `game_subject_id`; `topic` matches the item's topic or a prefix ending at `/`; `types` defaults to what the template accepts.

Filters, in this order: the template accepts the type (and the sequence mode); status `approved` (on every subject, reviewed or not); the learner's age band overlaps `[age_min, age_max]`; not sacred when the template is not `sacred_allowed`; `lang` fits the app language (`both` always fits; Quran / Hadith items always fit).

Order: (1) SRS items due, at most 30 % of `count` (`srs` on); (2) never seen; (3) not seen in 7 days; (4) the rest, oldest seen first. Inside a tier the order is a shuffle seeded by `seed`. A `challenge` draw skips the tiers: it uses the challenge's `seed` over the whole filtered set, so every player gets the same items in the same order.

The draw writes `game_draws` (the snapshot exactly as answered), bumps `game_level_stats.starts`, and does not touch `seen` (the play does).

### The snapshot item

```json
{"n": 0, "id": 812, "rev": 1, "type": "sequence", "sacred": true, "status": "approved",
 "prompt": {"ar": "رتّب كلمات الآية", "en": "Put the words of the ayah in order"},
 "media": {"image": null,
           "audio": [{"ref": "112:1", "url": "https://everyayah.com/data/Alafasy_64kbps/112001.mp3",
                      "start_ms": 0, "end_ms": null, "reciter": "alafasy"}]},
 "body": {"mode": "order", "unit": "word", "tokens": ["قُلْ", "هُوَ", "ٱللَّهُ", "أَحَدٌ"], "eq": [0, 1, 2, 3],
          "blanks": [0, 1, 2, 3], "extra": ["ٱلصَّمَدُ", "كُفُوًا"], "show": [3, 5, 0, 2, 4, 1]},
 "explain": {"ar": null, "en": null}, "source": {"kind": "quran", "ref": "112:1", "label": {"ar": "الإخلاص ١", "en": "Al-Ikhlas 1"}},
 "max": 4}
```
- `n` is the item's position in the draw and the trace's `i`. `status` is present only in a preview.
- `media.audio`: `null` or a playlist (one entry per ayah of the reference, in order). `end_ms: null` = to the end of the file. `reciter` is the reciter actually used for that entry: it differs from the draw's `reciter` when the fallback applied (§9).
- The answers are in the snapshot, as in v3: the app grades offline and the server grades again from the trace.
- Every index in a trace points into the snapshot's arrays as stored (canonical order). `show` is only the order on screen, fixed by the draw: a permutation the template must follow.

Resolved `body` per type (what differs from §3):

| `type` | Snapshot `body` |
|---|---|
| `mcq` | + `show`: a permutation of the option indices |
| `true_false` | unchanged |
| `select_all` | + `show` |
| `sequence` | `tokens` always a list (the right sequence); `eq`: one class id per token, equal strings share a class; `blanks`: the slots to fill, ascending (`order`: every slot; `next_word`: `given`..n−1); `extra`: the distractor strings, token indices n..n+k−1; `show`: a permutation of the choice indices (`order`: all tokens + extras; else the blanks' tokens + extras) |
| `classify` | + `show`: a permutation of the token indices |
| `pair` | + `show_a`, `show_b`: permutations of the pair indices |
| `fraction`, `program` | unchanged |
| `combine` | + `show`: a permutation of the ingredient indices |

`max` per item: `mcq`, `true_false`, `fraction`, `combine` 1; `select_all` the number of `answers`; `sequence` the number of `blanks`; `classify` the tokens + the tokens that have a `case`; `pair` the pairs; `program` 2. The round's `max_score` is the sum over its items, answered or not.

### `GET /games/{id}/pool` (offline)

200: `{draw_id, kind: "pool", seed, sacred, template, settings, items: [item], count, reciter, expires_at}`: up to 3 × `count` items in snapshot form, drawn with the same filters and tiers. Errors as `draw` (no `mode`, no `round_id`). Phones and desktop only: the web never calls it.
- The device stores the pool in its local DB (`level_cache.dart`) with the audio files of its items, for the learner's chosen reciter only.
- An offline round picks `count` items from the pool: unseen-on-this-device first, then a shuffle. The play names the pool's `draw_id` and sends `picked` (the pool `n` of each item, in round order). The trace's `i` is then the position inside `picked`.
- A pool is reusable until `expires_at` (30 days). A play on a pool is never ranked (`no_round`).

## 5. Trace

`trace = [{i, a, ms, h?}]`, in the order things happened, at most 500 entries.
- `ms`: int ≥ 0 since the round first showed, never decreasing.
- `i`: the item's position in the round (0..N−1), or `−1` for the end entry.
- The end entry is optional and must be last: `{"i": -1, "a": "done" | "timer" | "lives" | "quit", "ms"}`. Without it the round ended as `done`. A round the timer or the lives ended is valid: items with no entry score 0.
- `h: true` on an entry: a hint was used for that unit before this try; the unit scores 0.
- Entries may repeat (retries). Only the first counted entry of a unit scores (`program`: the first three runs, the best counts).
- `duration_ms` = the last entry's `ms`.

| `type` | `a` | Unit (what "first try" is counted by) | Refused (`bad_trace`) when |
|---|---|---|---|
| `mcq` | option index | the item | not an int in range |
| `true_false` | `0` false / `1` true | the item | not 0 or 1 |
| `select_all` | list of picked option indices (may be empty), sent once at Check or at the end | the item | not a list, a duplicate, out of range |
| `sequence` | `[slot, token]` | the slot | `slot` not in `blanks`; `token` not in 0..n+k−1 |
| `classify` | `[token, bucket]`, then `[token, bucket, case]` | the token's bucket; the token's case | out of range; a 3-entry when the item has no `cases` or the token has no `case` |
| `pair` | `[a index, b index]` | the `a` index | out of range |
| `fraction` | `[n, d]` | the item | `n` not 0..999, `d` not 1..999 |
| `program` | the command list: `"F"`, `"L"`, `"R"`, `{"loop": 2..9, "do": ["F" | "L" | "R", …1..10]}` | one run | empty, more than 60 tokens, a command outside `cmds`, a loop inside a loop |
| `combine` | list of ingredient indices, 1..n | the item | empty, a duplicate, out of range |

The whole trace is refused when it is not a list, is empty, has more than 500 entries, has an entry that is not an object, a bad `ms` or `i`, an end entry that is not last or has an unknown value, a bad `a` (above), or no counted entry at all.

## 6. Grading (`items_grade.grade(items, trace) → score, max_score, counted, per_item, ghost, end`)

| `type` | Points |
|---|---|
| `mcq` | 1 when `a == answer` |
| `true_false` | 1 when `(a == 1) == answer` |
| `select_all` | `max(0, hits − wrong)`: `hits` = picked ∩ `answers`, `wrong` = picked − `answers` |
| `sequence` | per blank slot: 1 when `token < n` and `eq[token] == eq[slot]` (a distractor is always wrong; equal words are interchangeable). Indices are compared, never strings |
| `classify` | per token: 1 when `buckets[bucket].key == token.bucket` on its first 2-entry; 1 more when `cases[case].key == token.case` on its first 3-entry |
| `pair` | per `a` index: 1 when `a index == b index` |
| `fraction` | 1 when `a[0] × rd == rn × a[1]`; `rn / rd` = `n / d`, or `a + b`, or `a − b` (cross-multiplied, never reduced, never a float) |
| `program` | each of the first 3 runs is simulated: 0 when the goal is not reached or the program is longer than `max`; 1 when reached; 2 when reached with length ≤ `par`. The item's points are the best run |
| `combine` | 1 when the picked ingredients' keys equal `answer` as a set |

**Program simulation.** Loops are expanded first. The robot starts at `start`. `L` / `R` turn 90°. `F` moves one cell: N is `y − 1`, E `x + 1`, S `y + 1`, W `x − 1`. A move into a wall or off the grid ends the run (not reached). Entering the goal ends the run (reached). At most 200 steps run. `length` counts every token of the program as written, run or not: a basic command is 1, a loop is 1 + its body.

`counted` = the entries that were a unit's first try (a program's first run counts once). `ghost` = `[[ms, 1 | 0]]`, one pair per counted entry (1 when it scored), at most 200.

A drawn item that is deleted or edited later changes nothing: the play is graded against the draw's snapshot.

## 7. Stars, rank points, coins, SRS

```
stars       = 3 if score/max ≥ 0.9, 2 if ≥ 0.6, 1 if ≥ 0.3, else 0            (unchanged)
base        = (200 × score + max) // (2 × max)
par_ms      = 1000 × Σ over the round's items of par_s(item)
bonus       = 0 when the draw is sacred or the template is growing_tree,
              else max(0, 200 − (100 × D) // par_ms)
rank_points = 0 when stars == 0, else (base × difficulty × (1000 + bonus) + 50000) // 100000
```
- `par_s(item)`: `mcq` 12, `true_false` 8, `select_all` 15, `fraction` 20, `program` 45, `combine` 15; `sequence` 4 × blanks, `classify` 5 × `max`, `pair` 6 × pairs.
- `difficulty`: the level's `games.difficulty`: easy 100, medium 125, hard 150. An item difficulty of 1–2 is easy, 3 medium, 4–5 hard.
- `D` = `duration_ms`. `too_fast` when `D < counted × MIN_STEP_MS`.

**Coins** (`game_coin_ledger`, unique on user + reason + ref, so a repeat pays nothing):
- a level pays each of its three stars once: reason `level_star`, ref `"<game_id>:<star>"`; stars 1 and 2 pay `coins_reward // 3`, star 3 pays the rest. Default `coins_reward` 9;
- a Ghost Duel win pays 2: reason `duel_win`, ref the `draw_id`. The SERVER decides the win (§8 "The duel", gate G2); nothing the app sends can claim it;
- a preview or a duplicate play pays nothing; the day's total stops at `coins_daily_cap` (the user's own day, as the champions day);
- a purchase is a negative row: reason `buy`, ref the cosmetic key. `game_profiles.coins` is the running sum and can never go below 0.

**SRS** (`game_item_srs`, when `srs` is on). An item is "right" when its points equal its `max`.
- Wrong: box 1, due the next day, `lapses + 1` (the row is made if missing).
- Right with a row: box + 1 up to 5; due after 1, 3, 7, 14, 30 days for boxes 1..5.
- Right without a row: nothing (only a miss starts the ladder).
- An item never shown in the round (timer ended before it) is untouched, and so is its `seen` row.

## 8. Learner routes

### `GET /games?v=4`

Without `v=4` the list answers classic games only (engines `quiz` … `word_puzzle`), so an old app never sees a level it cannot play. With `v=4` it also answers v4 levels; filters `game_subject_id`, `template`. A v4 level is the v3 game object plus:
```json
{"template": "verse_builder", "game_subject_id": 1, "topic": "juz_30/112", "level_no": 3, "age_min": 6,
 "age_max": 99, "unlock": {"mode": "prev", "min_stars": 1}, "locked": false, "sacred": true, "coins_reward": 9,
 "items_count": 8}
```
- `locked`: `unlock.mode == "prev"` and the level with the next lower `level_no` of the same template and subject has fewer than `min_stars` stars for this user. The first level is never locked.
- Levels outside the learner's age band, of a template that is off or hides the subject, or of a subject that is off, are left out.
- `GET /games/{id}` answers the same object (`config: {}`).

### `GET /games/v4/home`

One call for the games tab:
```json
{"profile": profile,
 "subjects": [{"id": 1, "key": "quran", "name_ar": "القرآن الكريم", "name_en": "Quran", "icon": "menu_book",
               "color": "#2E7D6B", "sacred": true, "levels": 42, "done": 5, "stars": 13}],
 "templates": [{"key": "verse_builder", "levels": 20}],
 "continue": level|null, "review_due": 6, "review_levels": [{"game_id": 31, "due": 4}],
 "flags": {"cosmetics": true, "challenges": true, "breaks": true, "champions": true}}
```
`done` = levels with at least 1 star. `continue` = the first unlocked level without 3 stars in the subject played last. Errors: 403 `feature_disabled`.

### Game profile

`profile` =
```json
{"age_band": "10-13", "age_source": "dob", "needs_age": false, "coins": 54,
 "equipped": {"hat": null, "outfit": "explorer_blue", "vehicle": null, "trail": null},
 "sky": [{"key": "c_112", "at": "…"}], "reciter_key": null, "reciter_effective": "alafasy", "can_review": false}
```
- `age_band`: `6-9` / `10-13` / `14-17` / `18+` / null. From `users.dob` (age in full years today; under 10 is `6-9`, 10–13, 14–17, 18 and over), else `grade + 5` as the age, else what the learner chose. `age_source`: `dob` / `grade` / `asked` / null. `needs_age` is true when all three are missing: the app asks once (the band only).
- A band covers ages 6–9, 10–13, 14–17, 18–99; a level or item fits when its `[age_min, age_max]` overlaps it. Null band = no age filter. Theme `auto`: `6-9` kids, `10-13` and `14-17` teen, `18+` adult.
- `reciter_key`: the learner's choice, null = the platform default. `reciter_effective`: the choice when it is still enabled, else the kids reciter for the `6-9` band, else the default.
- `GET /me/games/profile` → `profile`.
- `PUT /me/games/profile {age_band?, reciter_key?, equipped?}` → `profile`. `age_band` is accepted only while `age_source` is `asked` or null (409 `age_fixed`; 422 `bad_age_band`). `reciter_key`: null clears; an unknown or disabled key is 422 `reciter_unknown`. `equipped`: every key must be owned and fit its slot (422 `cosmetic_not_owned`).

### `POST /games/{id}/plays` (v3 route, more fields)

Request adds `draw_id: string?`, `picked: [int]?` (pool plays only), `calm: bool?`. `round_id` and `trace` as v3.
Response adds, at the top level: `"coins_awarded": 6, "coins": 60, "unlocked": [32], "srs_due": 5`.

With a `draw_id` the server:
1. loads the draw: this user's, this game's; a `round` draw unused and at most 2 h old, a `pool` draw not expired. Else the play is saved as v3 saves a play without a gradable trace (`unranked_reason: "draw_invalid"`);
2. grades the trace against the snapshot (§6). A refused trace: saved unranked (`bad_trace`), the body's score kept, no seen / SRS / stats / coins;
3. stores `score = min(body, server)`; ranks it with the v3 rules, with two changes: step 3 is `D ≥ counted × MIN_STEP_MS`, and the rank points are §7's;
4. marks the draw used; writes `seen` for the items that have an entry, SRS, `game_item_stats` (`shown + 1`, `correct + 1` when right, `total_ms` + the time from the previous counted entry of the round to this item's first entry), `game_level_stats` (`finishes`, `score_sum`, `max_sum`, `ms_sum`), coins, and the play's `ghost` when the draw is a `round`.

A `preview` draw: steps 1–3 are answered (`play.id: null`, `ranked: false`, `unranked_reason: "preview"`), nothing is written. A duplicate `client_id` answers the first play again, as v3. `unlocked`: the levels this play unlocked.

### `GET /games/{id}/ghost`

`{"ghost": {"name": "Sara A.", "score": 6, "max_score": 8, "duration_ms": 41000, "events": [[4000, 1], [9000, 0]]} | null}`: a random ghost of this level from the last 30 days, by another user of the same age band who is not opted out of the leaderboards. Null when there is none: the app then plays a built-in training partner (70 % right, par pace). The duel is between the two progress lines; the items are the learner's own draw. The ghost carries `"id"`: the ghost play's id, which the app sends back as `ghost_play_id`.

**The duel (gate G2).** A `ghost_duel` play adds `ghost_play_id: int|null` to the request (null = the training partner) and gets `"duel": {"won": bool, "opponent": "ghost" | "bot"} | null` in the answer. The server decides, from what it graded itself:
- no duel result (`duel: null`, no coins) unless the play was graded against its `round` draw (not `draw_invalid`, `bad_trace`, a preview, a pool play or a duplicate), is not flagged `too_fast`, and has 1+ star;
- me = `(score, max_score, duration_ms)` of the server's own grading (§6); the ghost = the same three of the stored ghost play. `ghost_play_id` must be a play of this level, by another user, with a stored `ghost`, from the last 30 days; anything else is treated as the bot (never an error);
- the bot = 70 % right at par pace: `(7, 10, par_ms of my draw)` (§7);
- `won` = `my_score × their_max > their_score × my_max`, or the two sides equal and `my_duration_ms < their_duration_ms`. A tie on both is not a win;
- a win pays the 2 coins once per `draw_id`. A client `duel_won` field is not read (T40 shipped one; it is removed).
The app draws the race with the same rule, shows the server's `duel.won` when it is online, and its own result (no coins promised) for an offline play.

### Cosmetics (`games.cosmetics`)

- `GET /games/cosmetics` → `{coins, items: [{key, slot, name_ar, name_en, price_coins, owned, equipped, locked: null | {"type": "stars", "count": 30, "have": 12}}]}`. `slot`: `hat` / `outfit` / `vehicle` / `trail`. `unlock_rule` types: `stars` (total stars), `levels` (levels with 1+ star), `champion` (won once).
- `POST /games/cosmetics/{key}/buy` → `{coins, item}`. 404 `cosmetic_not_found`, 409 `cosmetic_owned`, 409 `not_enough_coins`, 409 `cosmetic_locked`.
- Wearing is `PUT /me/games/profile {equipped}`.

### Challenges (`games.challenges`)

- `POST /games/challenges {game_id}` → `challenge` (201). `challenge` = `{id, code, kind: "friends", game: level, seed, owner: "First L.", week_start, closes_at, status: "open" | "closed", link: "https://nextbrain.site/app/games/challenge/<code>", board: [{rank, name, score, max_score, duration_ms, is_me}], joined: bool}`. `code`: 8 characters of the coupon alphabet. A challenge closes 7 days after it was made: `closes_at` (naive UTC ISO 8601 `YYYY-MM-DDTHH:MM:SS[.ffffff]`, as `issued_at`). 429 `too_many_challenges` (10 a day).
- `GET /games/challenges/{code}` → `challenge` (404 `challenge_not_found`). `POST /games/challenges/{code}/join` → `challenge` (409 `challenge_closed`; at most 30 members: 409 `challenge_full`).
- `GET /me/games/challenges` → `{items: [challenge without board]}`, open first, the last 20.
- Playing is `POST /games/{id}/draw {challenge: code}`; the board takes each member's first play of that draw (never ranked twice, never better by replaying), made before `closes_at`.
- A challenge draw needs the challenge open (409 `challenge_closed`) and the caller joined (403 `challenge_not_joined`). It skips `level_locked` (never `template_off`), and its items are filtered by the OWNER's age band so every member gets the same items.
- A challenge play on a level still locked for that player counts for the board and pays coins (§7), but leaves `game_progress` untouched (no stars, `unlocked: []`), so it never unlocks a later level.
- Class board: `GET /games/class-board?course_id=` → `{week_start, mine: row|null, items: [{rank, course_id, title, points_avg, players, is_mine}]}`. A class is a course. `points_avg` = the week's rank points of its students ÷ its students who played a ranked game that week; courses with fewer than 3 such students are left out; top 20. 403 `not_enrolled`.

### Smart breaks (`games.breaks`)

- `GET /games/breaks/config` → `{play_now, break_reminders, study_minutes, break_max_minutes}` (the module settings; all false / 0 when the switch is off).
- `GET /games/suggest?course_id=&subject_id=&topic=` → `{game: level|null}`: a random published, unlocked v4 level for the learner's age band. Match order: the course's `subject_id` through `game_subjects.edu_subject_ids` (+ `topic` prefix), then the subject alone, then any subject. Null when there is none.

### Parent

`GET /parent/children/{student_id}/games` now answers `{student_id, summary: {minutes_7d, finished_7d, minutes_30d, finished_30d}, games: [], badges: [], totals: {plays, stars, games, perfect}}` (`games` and `badges` stay as empty lists for old apps). 403 `feature_disabled` (`parent.games_summary`, or the setting `parent_summary` off). Minutes come from `duration_s`.

## 9. Quran, Hadith and reciters

**Text.** `quran_ayat.text` is the Tanzil Uthmani text, byte for byte. `words` = the text split on spaces, where a token made only of Quranic annotation signs (U+06D6–U+06ED, the waqf marks, sajdah and rub marks) joins the word before it (a leading U+06DE joins the word after it). `segments` = `[[from, to]]` word ranges cut after every word that carries a waqf mark (U+06D6–U+06DB); an ayah without one has a single segment. No other cut exists.

**The basmala (gate G1).** Tanzil's file writes the basmala in front of ayah 1 of every surah but 1 and 9 (112 lines). It is not part of that ayah: the loader cuts the unchanged line at its fourth space, and only when those four words compare equal to 1:1 (`split_basmala` in `scripts/dev/fetch_games_datasets.py`; 95:1 and 97:1 carry a shadda on the ba). `quran_ayat.text`, `words`, `segments` and `checksum` are of the ayah without it; the vendored file stays byte for byte. A line of the 112 that does not split this way aborts its surah. The basmala is never a game token outside 1:1; in a surah file, the timing of ayah 1 starts after it (T85).

**References.**
- `@quran:112:1` → the ayah's `words` (unit `word`), its `segments` (unit `segment`).
- `@quran:112:1-4` → one token per ayah (unit `ayah`).
- `@hadith:bukhari:1` → the hadith's words: `words[matn_from:matn_to]` when a reviewer marked the matn, else all of it. Only a hadith whose resolved token list is 2..25 words feeds a sequence item.
- A reference that does not resolve is 422 `bad_game_item` (`why: "ref"`) at save time and the item is skipped at draw time.

**Reciters** (`quran_reciters`). `reciter` =
```json
{"key": "alafasy", "name_ar": "مشاري العفاسي", "name_en": "Mishary Alafasy", "riwayah": "hafs",
 "audience": "all", "source_kind": "ayah_files", "coverage": {"surahs": 114, "of": 114},
 "sample": {"ref": "1:2", "url": "…/001002.mp3", "start_ms": 0, "end_ms": null, "reciter": "alafasy"}}
```
- `GET /games/reciters` → `{items: [reciter], default_key, kids_key, mine: string|null, effective: string}`: enabled reciters only, by `sort`. A `surah_files` reciter is listed only when it has timings for at least one surah; `coverage.surahs` counts its timed surahs. `sample` is null when 1:2 has no audio for it. The app plays 3 seconds of the sample.
- The learner's choice is `PUT /me/games/profile {reciter_key}`. A draw's optional `reciter` is a one-round override.
- `GET /games/quran/audio?refs=112:1,112:2&reciter=<key>` → `{reciter, items: {"112:1": audio entry}}`, at most 60 refs, 422 `reciter_unknown`, 422 `bad_ref`. The quick switch in a Quran template calls it, replays the current ayah with the new voice and saves the choice; the score and the trace do not change. The offline cache calls it to re-download a cached level's audio after a change (on Wi-Fi).

**Audio resolver** (one function, used by the draw, the pool and the route above):
- `ayah_files`: `url_pattern` with `{sss}` and `{aaa}` (3-digit surah and ayah) → `{url, start_ms: 0, end_ms: null}`;
- `surah_files`: `url_pattern` with `{sss}` + the ayah's row in `quran_ayah_timings` → `{url, start_ms, end_ms}`;
- an ayah with no audio for the chosen reciter (no timing row, or the reciter was disabled) falls back to the default reciter, silently; each entry's `reciter` says who was used;
- a reciter can be enabled only when `permission_status` is `verified`.

Seeded reciters (§13 has the evidence):

| `key` | `source_kind` | `url_pattern` | `audience` | Flags |
|---|---|---|---|---|
| `alafasy` | `ayah_files` | `https://everyayah.com/data/Alafasy_64kbps/{sss}{aaa}.mp3` | all | default, enabled |
| `husary_muallim` | `ayah_files` | `https://everyayah.com/data/Husary_Muallim_128kbps/{sss}{aaa}.mp3` | kids | kids default, enabled |
| `mukhtar_alhaj` | `surah_files` | `https://cdn.mp3quran.net/audio/mukhtar-haj/r1/{sss}.mp3` | all | enabled; plays only the surahs timed in the tool (T85) |

## 10. Admin routes (`/api/v1/admin/games/v4`, platform admins: 403 `admin_required`; 403 `feature_disabled` for `admin.games_content`)

| Route | Body → answer |
|---|---|
| `GET /hub?days=7` | → `{plays_today, players_today, completion_pct, avg_score_pct, pending_review, items_total, levels_published, by_day: [{day, starts, finishes}]}` |
| `GET /templates` | → `{items: [template]}` |
| `PUT /templates/{key}` | `{enabled?, defaults?, age_min?, age_max?, hidden_subject_ids?, sort?}` → `template`; 422 `bad_template_settings` (`field`) |
| `GET /subjects` · `POST /subjects` (201) · `PUT /subjects/{id}` | `subject` fields → `subject`; 409 `subject_key_taken`; 422 `bad_subject` |
| `DELETE /subjects/{id}` | → `{deleted}`; 409 `subject_in_use` (it has items or levels: switch it off instead) |
| `GET /items?subject_id=&topic=&type=&status=&difficulty=&q=&seeded=&skip=&limit=` | → items (§3) |
| `POST /items` (201) · `GET /items/{id}` · `PUT /items/{id}` | the item's fields → the item + `resolved` (its snapshot form, for the live preview); 422 `bad_game_item` |
| `POST /items/check` | an item → `{resolved}` without saving (the editor's live preview) |
| `DELETE /items/{id}` | → `{deleted}`; a seeded item is remembered as deleted so a re-seed never restores it |
| `POST /items/bulk` | `{ids (≤ 500), set?: {topic?, difficulty?, age_min?, age_max?, status?, tags?}, delete?: true}` → `{changed, skipped: [{id, why}]}` |
| `GET /review?subject_id=&skip=&limit=` | → the `pending_review` items, oldest first (needs `can_review` or admin) |
| `POST /items/{id}/review` | `{decision: "approve" / "reject", note?}` → the item; 403 `review_required`; 409 `not_pending` |
| `GET /reviewers` · `PUT /reviewers` | `{user_ids}` → `{items: [{id, name, username}]}` |
| `GET /import/template?type=&format=csv / xlsx / json` | → the file (one sheet or array per item type, a header row and two example rows) |
| `POST /import?dry_run=true / false` | multipart `file` (≤ 5 MB, ≤ 2000 rows) + `subject_id` → `{rows, ok, errors: [{row, field, why}], created, pending}`; `dry_run` (default true) saves nothing; a commit saves the valid rows only; rows of a `requires_review` subject land as `pending_review`, the others as `draft`; 422 `bad_import_file` |
| `GET /quran/surahs` | → `{items: [{number, name_ar, name_en, ayat, juz_from, revelation}]}` |
| `GET /quran/ayat?surah=&from=&to=&reciter=` | → `{items: [{surah, ayah, text, words, word_count, segments, audio: audio entry|null}]}`, at most 300 ayat |
| `GET /hadith?collection=&number=&q=&max_words=&skip=&limit=` | → items of `{id, collection, number, book, chapter, text_ar, word_count, matn_from, matn_to, grade, grade_source}` (`q` searches the text without tashkeel) |
| `PUT /hadith/{id}/matn` | `{matn_from, matn_to}` (word indices, or both null) → the hadith; needs `can_review` or admin |
| `GET /reciters` | → `{items: [reciter + {enabled, is_default, sort, url_pattern, source_url, licence, permission_status, permission_note}]}` |
| `PUT /reciters/{key}` | `{enabled?, is_default?, audience?, sort?, permission_status?, permission_note?}` → the same; 409 `reciter_not_verified` (enable without `verified`); 409 `default_required` (the default cannot be switched off) |
| `GET /reciters/{key}/timings` | → `{items: [{surah, name_ar, ayat, marked}]}` |
| `GET /reciters/{key}/timings/{surah}` | → `{url, ayat: [{ayah, text, start_ms, end_ms, source}]}` (unmarked: nulls) |
| `PUT /reciters/{key}/timings/{surah}` | `{ayat: [{ayah, start_ms, end_ms}]}` → the same as GET; 422 `bad_timings` (not ascending, overlap, an unknown ayah); `source: "admin"`, `marked_by`, `marked_at` are set |
| `GET /levels?template=&game_subject_id=&status=` | → v4 levels as the admin game object + the §8 fields + `item_source`, `template_settings`, `stats: {starts, finishes, avg_score_pct}` |
| `POST /levels/auto-split` | `{template, game_subject_id, topic?, types?, per_level (3..30), difficulty_steps?: bool, title_ar, title_en, publish?: false}` → `{created: [level], skipped}`: `fixed` levels cut from the pool by difficulty then topic, numbered after the last `level_no`; `{n}` in a title is the level number |
| `GET /analytics/overview?from=&to=&game_subject_id=&template=` | → `{plays, players, completion_pct, avg_score_pct, avg_ms, by_day: [{day, starts, finishes, avg_score_pct}], by_template: [{key, plays, completion_pct}]}` |
| `GET /analytics/levels?…&sort=plays / completion / score` | → items of `{game_id, title_ar, title_en, template, starts, finishes, completion_pct, avg_score_pct, avg_ms}` |
| `GET /analytics/items/hardest?game_subject_id=&type=&min_shown=20&limit=` | → items of `{id, type, prompt, subject, topic, shown, correct, correct_pct, avg_ms}`, lowest `correct_pct` first |
| `GET /seed` | → `{items: [{subject, key, seeded, approved, pending, levels, last_run_at}], datasets: [{key, version, sha256, licence, ok}]}` |
| `POST /seed/run` | `{subjects?: [key], more?: false, levels?: true}` → `{created, updated, skipped, levels_created, errors: []}`; idempotent by `seed_key`; never overwrites `edited_by_admin` items, never restores deleted ones |
| `GET /cosmetics` · `POST /cosmetics` (201) · `PUT /cosmetics/{key}` | `{key, slot, name_ar, name_en, price_coins, unlock_rule?, enabled, sort}` → the cosmetic; 409 `cosmetic_key_taken` |

- `template` = `{key, name_ar, name_en, kinds, accepts, sacred_allowed, enabled, defaults, code_defaults, age_min, age_max, hidden_subject_ids, sort, levels}`.
- `subject` = `{id, key, name_ar, name_en, icon, color, enabled, sacred, requires_review, edu_subject_ids, sort, items, levels}`. `key`: `[a-z0-9_]{2,24}`. `sacred` cannot be changed on a seeded sacred subject (`quran`, `hadith`).
- Seeded subjects: `quran` (sacred, review), `hadith` (sacred, review), `tafsir_balagha` (review), `fiqh` (review), `nahw` (review), `irab` (review), `math`, `science`, `general`, `culture_fun`.
- **Levels** are created and edited with the existing `POST / PUT / DELETE /admin/games`, whose body gains: `engine` (a template key), `game_subject_id`, `topic`, `level_no`, `age_min`, `age_max`, `template_settings`, `item_source`, `unlock`, `coins_reward` (0..300). For a template engine `config` must be `{}` or absent. New errors: 422 `bad_item_source` (`field`), 422 `template_not_sacred`, 422 `bad_template_settings`, 409 `no_items` on publish when the source resolves to fewer than 1 approved item. Reorder stays `POST /admin/games/reorder` and also rewrites `level_no` in the given order.
- **Preview** is `POST /games/{id}/draw {mode: "preview"}` on a draft or published level.
- **Rewards, breaks, parents** use the existing `/admin/rewards/*` (§11) and `/admin/module-settings/games`.

## 11. Rewards and champions

**Champions.** `SCOPE_KINDS` gains `age`; `key` = an age band. Who counts: the `platform` cohort (eligible students in no organization) split by age band. Gate G2: nobody is left out for a missing age. The band a learner competes in is the profile's band, else the one their date of birth or grade gives (the daily job writes it into `game_profiles` for every ranked player before it closes the day, so a classic app's players are grouped too), else the open group `18+`: a learner of unknown age never competes among younger children, and the app's one-time age question moves them to their own group. With `champions_daily_scope: "age"` the daily job closes one period per band instead of the `platform` daily period; weekly periods and the `category` / `org` scopes are unchanged. `GET /games/champions/standings?scope=age` without `key` uses the caller's band (the open group when they have none; 422 `champions_bad_scope` only for an unknown `key`). A user's home scope (rounds, `rank_today`) is `org`, else `age` when the daily scope is `age`, else `platform`.

**Rules.** `rule` gains `valid_hours: int|null` (1..720; when set it replaces `valid_days` and counts from the unlock), `unlock_referrals: int|null` (1..50; null = issued active as today), `unlock_days: int` (1..30, default 7), `course_ids: [int]|null` (null = any course; needs `applies_to: "course"`). `scope_kind` accepts `age`. 422 `reward_bad_rule` as today.

**Coupons.** `coupon` gains `status: "locked"`, and `unlock: {"need": 3, "have": 1, "deadline": "…", "unlocked_at": null} | null`, `course_ids: [int]|null`, `valid_hours: int|null`.
- A rule with `unlock_referrals` issues the coupon `locked`, `expires_at` null, `unlock.deadline = issued_at + unlock_days`.
- `have` = the owner's referrals that reached `qualified` with `qualified_at ≥ issued_at` (the existing qualification and anti-fraud, unchanged: `self`, `device_seen`, `ip_burst`, the month cap, the 48 h rule).
- At `have ≥ need`: `status: "active"`, `unlocked_at = now`, `expires_at = now + valid_hours` (or `valid_days`). Checked in `referrals.after_qualified` and again on `GET /me/rewards`.
- A locked coupon past its deadline becomes `expired`.
- `POST /coupons/quote` and the checkouts: 409 `coupon_locked`; 409 `coupon_wrong_course` when `course_ids` is set and the target is another course or not a course.
- Seeded rule (migration 0128, `active: false`, `seed_key: "v4_daily_age_winner"`): `champion_daily`, `scope_kind: "age"`, ranks 1–1, `coupon_percent` 20, `max_discount` 200, `applies_to: "course"`, `valid_hours` 24, `unlock_referrals` 3, `unlock_days` 7, `per_user_month_cap` 4.
- Admin: `GET /admin/rewards/coupons?status=locked` works; the coupon rows carry `unlock`. `GET /admin/rewards/champions?scope=age` works.

## 12. Migrations (one owner: T10; head today 0125)

String sizes are exact (PostgreSQL enforces them). Every new column on an old table is nullable or has a server default.

**0126 `games_v4_content`**

| Table | Columns |
|---|---|
| `game_templates` | `key` String(24) PK · `enabled` Boolean default true · `defaults` JSON · `age_min` SmallInteger null · `age_max` SmallInteger null · `hidden_subject_ids` JSON · `sort` Integer default 0 · `updated_at` |
| `game_subjects` | `id` PK · `key` String(24) unique · `name_ar` String(120) · `name_en` String(120) · `icon` String(40) · `color` String(9) · `enabled` Boolean default true · `sacred` Boolean default false · `requires_review` Boolean default false · `edu_subject_ids` JSON · `sort` Integer default 0 · `seed_key` String(40) unique null · `created_at` · `updated_at` |
| `game_items` | `id` PK · `subject_id` FK `game_subjects` · `topic` String(80) null · `type` String(12) · `difficulty` SmallInteger default 1 · `age_min` SmallInteger default 6 · `age_max` SmallInteger default 99 · `lang` String(4) default `ar` · `status` String(16) default `draft` · `prompt` JSON · `media` JSON null · `body` JSON · `explain` JSON null · `source` JSON null · `tags` JSON null · `rev` Integer default 1 · `seed_key` String(80) unique null · `edited_by_admin` Boolean default false · `deleted_at` DateTime null · `reviewed_by` Integer null · `reviewed_at` DateTime null · `review_note` String(300) null · `created_by` Integer null · `created_at` · `updated_at` · index (`subject_id`, `status`, `type`, `difficulty`) · index (`subject_id`, `topic`) |
| `game_draws` | `id` String(36) PK · `user_id` FK users CASCADE · `game_id` FK games CASCADE · `kind` String(8) (`round` / `pool` / `preview`) · `seed` Integer · `items` JSON · `settings` JSON · `sacred` Boolean · `round_id` String(36) null · `challenge_id` Integer null · `reciter_key` String(24) null · `issued_at` · `expires_at` DateTime · `used_at` DateTime null · index (`user_id`, `issued_at`) · index (`expires_at`) |
| `game_item_seen` | (`user_id` FK CASCADE, `item_id` FK CASCADE) PK · `seen_at` |
| `game_item_srs` | (`user_id`, `item_id`) PK, both CASCADE · `box` SmallInteger · `due_at` DateTime · `lapses` Integer default 0 · index (`user_id`, `due_at`) |
| `game_item_stats` | `item_id` PK FK CASCADE · `shown` Integer default 0 · `correct` Integer default 0 · `total_ms` BigInteger default 0 |
| `game_level_stats` | (`game_id` FK CASCADE, `day` Date) PK · `starts` · `finishes` · `score_sum` · `max_sum` Integer default 0 · `ms_sum` BigInteger default 0 |
| `games` (alter) | `engine` → String(24) · + `game_subject_id` Integer FK `game_subjects` null · `topic` String(80) null · `level_no` Integer null · `age_min` SmallInteger null · `age_max` SmallInteger null · `template_settings` JSON null · `item_source` JSON null · `unlock` JSON null · `coins_reward` Integer default 0 · index (`engine`, `game_subject_id`, `level_no`) |
| `game_plays` (alter) | + `draw_id` String(36) null · `ghost` JSON null · `coins_awarded` Integer default 0 · `unranked_reason` → String(16) stays (`draw_invalid`, `preview` fit) |

A deleted item is a soft delete (`deleted_at`): it leaves every list and draw, and its `seed_key` stays taken so a re-seed skips it. A daily prune deletes `game_draws` past `expires_at` + 1 day and clears `game_plays.ghost` after 30 days.

**0127 `games_v4_texts`**

| Table | Columns |
|---|---|
| `quran_surahs` | `number` SmallInteger PK · `name_ar` String(40) · `name_en` String(40) · `ayat` SmallInteger · `revelation` String(8) · `juz_from` SmallInteger |
| `quran_ayat` | (`surah`, `ayah`) SmallInteger PK · `text` Text · `words` JSON · `word_count` SmallInteger · `segments` JSON · `juz` SmallInteger · `checksum` String(64) |
| `quran_reciters` | `key` String(24) PK · `name_ar` String(80) · `name_en` String(80) · `riwayah` String(20) default `hafs` · `source_kind` String(12) (`ayah_files` / `surah_files`) · `url_pattern` String(300) · `source_url` String(300) · `licence` String(300) · `permission_status` String(10) (`verified` / `pending` / `denied`) · `permission_note` String(500) null · `audience` String(6) (`all` / `kids`) · `enabled` Boolean default false · `is_default` Boolean default false · `sort` Integer default 0 |
| `quran_ayah_timings` | (`reciter_key` String(24) FK CASCADE, `surah`, `ayah`) PK · `start_ms` Integer · `end_ms` Integer · `source` String(8) (`dataset` / `admin`) · `marked_by` Integer null · `marked_at` DateTime null |
| `hadith` | `id` PK · `collection` String(10) (`bukhari` / `muslim`) · `number` Integer · `numbering` String(16) (`hadith-api`) · `arabic_number` Integer null · `book` SmallInteger null · `book_hadith` Integer null · `chapter` String(200) null · `text_ar` Text · `words` JSON · `word_count` SmallInteger · `matn_from` SmallInteger null · `matn_to` SmallInteger null · `matn_by` Integer null · `grade` String(10) (`sahih`) · `grade_source` String(120) · `checksum` String(64) · unique (`collection`, `numbering`, `number`) · index (`collection`, `word_count`) |

**0128 `games_v4_rewards`**

| Table | Columns |
|---|---|
| `game_profiles` | `user_id` PK FK CASCADE · `age_band` String(6) null · `age_source` String(6) null · `coins` Integer default 0, CHECK ≥ 0 · `equipped` JSON null · `sky` JSON null · `reciter_key` String(24) null (no FK: a removed reciter reads as null) · `can_review` Boolean default false · `updated_at` |
| `game_coin_ledger` | `id` PK · `user_id` FK CASCADE · `delta` Integer · `reason` String(16) · `ref` String(60) · `created_at` · unique (`user_id`, `reason`, `ref`) · index (`user_id`, `created_at`) |
| `game_cosmetics` | `key` String(40) PK · `slot` String(8) · `name_ar` String(80) · `name_en` String(80) · `price_coins` Integer default 0 · `unlock_rule` JSON null · `enabled` Boolean default true · `sort` Integer default 0 |
| `user_cosmetics` | (`user_id` FK CASCADE, `cosmetic_key` String(40)) PK · `bought_at` |
| `game_challenges` | `id` PK · `kind` String(8) (`friends`; `class` reserved) · `game_id` FK CASCADE · `seed` Integer · `owner_id` FK CASCADE · `code` String(8) unique · `week_start` Date · `status` String(8) default `open` · `created_at` · `closes_at` DateTime |
| `game_challenge_teams` | `id` PK · `challenge_id` FK CASCADE · `user_id` FK CASCADE null · `course_id` Integer null · `play_id` Integer null · `score` Integer null · `max_score` Integer null · `duration_ms` Integer null · `joined_at` · unique (`challenge_id`, `user_id`) |
| `reward_rules` (alter) | + `valid_hours` Integer null · `unlock_referrals` Integer null · `unlock_days` Integer default 7 · `course_ids` JSON null; + the seeded rule of §11 |
| `coupons` (alter) | + `unlock_need` Integer null · `unlock_deadline` DateTime null · `unlocked_at` DateTime null · `course_ids` JSON null · `valid_hours` Integer null (`status` String(10) already fits `locked`) |

Seed rows written by the migrations themselves: the 17 `game_templates` (`defaults {}`, the §2 order), the 10 `game_subjects`, the 3 `quran_reciters`, 8 `game_cosmetics`, the reward rule. The values of record are the migrations' (reviewed at gate G1): reciter names `مشاري العفاسي` / `محمود خليل الحصري (المعلّم)` / `مختار الحاج`, `sort` 0..2 (`data/games_seed/reciters.json` is the evidence copy, never loaded); cosmetics `hat_explorer` 30, `hat_crown` (champion 1), `outfit_traveller` 60, `outfit_astro` (stars 30), `vehicle_rocket` 80, `vehicle_racer` (levels 10), `trail_stars` 40, `trail_comet` 100. No cosmetic borrows religious dress or a symbol. The Quran and Hadith text is loaded by the seed runner (T23 / T41), not by a migration.

## 13. Datasets and licences (checked 2026-11-23 by HTTP from the dev machine)

| Dataset | URL | Checked | Licence / terms | How we comply |
|---|---|---|---|---|
| Quran text, Tanzil Uthmani 1.1 | `https://tanzil.net/pub/download/index.php?quranType=uthmani&marks=true&outType=txt-2&agree=true` (pause marks on: `marks=true`, gate G2; no sajdah or rub marks); metadata `https://tanzil.net/res/text/metadata/quran-data.xml` | 200, the copyright block is in the file | Creative Commons Attribution 3.0. Verbatim copies only: "changing it is not allowed"; the source must be clearly indicated with a link to tanzil.net; the copyright notice stays in every copy and in files derived from it | Vendored unchanged with its notice; `words` / `segments` are indexes over the unchanged text; the app shows "Quran text: Tanzil.net" with the link in the games About sheet; the MANIFEST keeps the notice and the SHA-256 |
| Quran cross-check, Quran.com API v4 | `https://api.quran.com/api/v4/quran/verses/uthmani?chapter_number=<n>` | 200, `verses[].text_uthmani` + `verse_key` | Quran Foundation API terms (public content API; no text is stored from it) | Used once by the dev fetch script to cross-check; nothing from it is stored or shown |
| Hadith, `fawazahmed0/hadith-api` v1 | `https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions/ara-bukhari.min.json`, `…/ara-muslim.min.json` | 200; Bukhari 7,589 rows (9 empty), Muslim 7,563 rows (203 empty); fields `hadithnumber`, `arabicnumber` (Bukhari only), `text`, `grades` (empty), `reference {book, hadith}`; `metadata.sections` | The Unlicense (public domain) | Vendored with the SHA-256; text stored byte for byte; attribution in the About sheet although not required |
| Recitation, Mishary Alafasy | `https://everyayah.com/data/Alafasy_64kbps/{sss}{aaa}.mp3` | 200 `audio/mpeg`, CORS `*`, ranges | everyayah.com publishes per-ayah files for free download and use in Quran software; no formal licence text; the rights of the recitation stay with the reciter | Streamed from the source, never re-hosted; devices cache for offline play; credit in the reciter card |
| Recitation, Al-Husary (Muallim) | `https://everyayah.com/data/Husary_Muallim_128kbps/{sss}{aaa}.mp3` | 200 (112:1 and 36:83), CORS `*`, ranges | as above | as above |
| Recitation, Mukhtar Al-Haj | `https://cdn.mp3quran.net/audio/mukhtar-haj/r1/{sss}.mp3`; listed by `https://www.mp3quran.net/api/v3/reciters?language=eng` (id 47, Hafs, 114 surahs) | 200 `audio/mpeg`, CORS `*`, range request 206; 112 = 0.35 MB, 18 = 32 MB. `…/api/v3/ayat_timing?surah=112&read=47` answers `[]`: no timings; not on everyayah.com | mp3quran.net is a free public Quran audio library with a public API; no formal licence text | Streamed from the source with range requests, never re-hosted; ayah timings are our own data (T85) |

**Reciter decision (owner rule, 2026-11-23).** Mukhtar Al-Haj is used: his full recitation is public and free to stream for everyone on mp3quran.net. It exists per surah only, so he ships as `surah_files` + `quran_ayah_timings` and the timing tool T85 stays. Yasser Al-Dosari was checked as the replacement and is not seeded: `https://everyayah.com/data/Yasser_Ad-Dussary_128kbps/{sss}{aaa}.mp3` answers 200 (112:1, 18:110), and mp3quran has timings for him (read 92). If Al-Haj has to be dropped, the change is one `quran_reciters` row and T85 is cancelled.

**Hadith facts that shape the seed.**
- `grades` is empty in both Arabic editions: the grade is set by collection, `grade: "sahih"`, `grade_source: "Sahih al-Bukhari"` / `"Sahih Muslim"`.
- The text holds the isnad and the matn together. Only 147 (Bukhari) + 407 (Muslim) rows have 25 words or fewer, isnad included. So: `matn_from` / `matn_to` let a reviewer mark the matn as a slice of the unchanged text; the launch seed makes sequence items only from rows of ≤ 25 words as they are, `pending_review`.
- Muslim has no `arabicnumber`: `number` is the dataset's `hadithnumber` and `numbering` says so.
- Empty rows are skipped.
- Bukhari has 26 sub-numbered rows (`hadithnumber` 402.2, 1390.3, …: a second narration under one number). `hadith.number` is an integer and `@hadith:<collection>:<number>` stays whole: the loader skips them (MANIFEST `sub_numbered`).
- `arabic_number` is stored only when the dataset's value is a whole number (Bukhari); Muslim's are strings such as `8.01`: null.
- `chapter` is the dataset's section title (`metadata.sections[reference.book]`), which is English only (longest 98 characters; String(200) stays). The pickers show it as a secondary line; no Arabic title is typed by hand.

**Cross-check rule (T13).** Tanzil is what we store. For every ayah the script compares Tanzil and Quran.com after `normalize` (the v3 function: marks and tatweel dropped, alef forms folded) and with the annotation signs removed. The MANIFEST lists every difference in `crosscheck_diffs`. A surah with a difference is seeded `pending_review` and Fable clears the list at gate G1; no ayah text is ever edited to make the check pass.

**Gate G1 result (2026-11-23).** All 112 differences were one kind: the basmala prefix on ayah 1 (§9), a file format, not an encoding, mark or wording difference. With the prefix split off, 6,236 of 6,236 ayat compare equal: `crosscheck_diffs` is empty, `crosscheck.basmala_prefixed` is 112, and no surah is held back by the cross-check (Quran items still pass review as every sacred item does).

## 14. What this contract changes in `PLAN.md`

1. `select_all` pays `max(0, hits − wrong)` out of the number of right answers, on every template (the plan had "1 if exact" for the kind and "right − wrong" for Balloon Pop: one rule now).
2. `program` counts the best of the first three runs, not only the first (a child's first program is rarely right).
3. A trace may end with an end entry `{i: −1, a}`; `too_fast` uses the counted entries, not `max_score`.
4. `game_draws.kind` (`round` / `pool` / `preview`) replaces the `preview` flag; a pool is a reusable draw and offline plays name it with `picked`.
5. New columns: `game_items.deleted_at`, `game_plays.coins_awarded`, `hadith.matn_from / matn_to / matn_by`, `quran_surahs`, `quran_ayat.segments`, `game_profiles.reciter_key` and `can_review`, `coupons.valid_hours`.
6. `games.review` is `game_profiles.can_review` (the backend has no permission table to hang it on).
7. The class board is computed from the week's plays; `game_challenges` holds friends challenges only.
8. Reviewed sacred items: every item needs `approved` to be drawn, on every subject; seeds of subjects without review are written `approved`.
9. `@hadith:<collection>:<number>` instead of `@hadith:<id>` (stable across databases).
10. Mukhtar Al-Haj is seeded `verified` and enabled (owner rule: public and free to stream), not `pending`.
11. Learner-chosen reciter (owner, 2026-11-23): `GET /games/reciters`, `reciter_key` on the profile, the draw's `reciter`, `GET /games/quran/audio`.

Gate G1 (2026-11-23, after wave 1):

12. The basmala in front of ayah 1 in Tanzil's file is split off by the loader and is not part of `quran_ayat` (§9); the 112 cross-check differences were only this, so the list is empty.
13. Hadith: the 26 sub-numbered Bukhari rows are skipped, `arabic_number` is whole numbers only, `chapter` is the English section title and stays String(200) (§13).
14. Seed values of record are the migrations' (§12). Changed at the gate: Al-Husary's full name; `outfit_scholar` → `outfit_traveller` (no scholar's dress on a game character); `trail_rainbow` → `trail_comet`.
15. App: `GameTemplate.kinds` is a set (a template can play two mechanics, §2); `test/games/` is a CI suite.

Gate G2 (2026-11-23, after wave 3):

16. Quran text: the vendored Tanzil file is the edition WITH pause marks (`marks=true`, sha256 `54ea3b2f…`). It is the earlier file plus 4,359 mark tokens and nothing else (checked: removing them gives the earlier file byte for byte; the cross-check is still 0 differences). §9's `words` / `segments` rule is unchanged and now has marks to cut at: 2,057 of the 2,620 ayat over 12 words split into segments. A database loaded from the earlier file reloads `quran_ayat` (the loader reports `stored_row_changed`).
17. Quran face: Amiri Quran Regular (OFL), family `uiQuran`, drawn only through `quranTextStyle` (app: `bases/stage_kit.dart` over `AppFonts.quranFamily`), one weight, lazy on the web. Hadith text uses the same role.
18. Seeded Quran items stay `approved` although the subject requires review: the text is the checksummed ayah (a reference, never typed) and the item is mechanical (order / complete / next word / segments at the text's own marks), so there is nothing for a reviewer to judge. The review rule still holds for anything a person writes: an edit of such an item, or a new item on the subject, lands `pending_review`. Hadith items stay `pending_review` (a person confirms the matn range).
19. Daily champions by age: no learner is dropped for a missing age (§11).
20. Ghost Duel: the server decides the win (§8 "The duel"); `ghost.id`, `ghost_play_id`, `duel`.
