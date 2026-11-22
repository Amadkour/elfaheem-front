# Games v3: build plan (2026-11-22)

Scope: motion in every engine, sounds, daily / weekly champions, rewards that become discount coupons, and referrals. The reasons are in `ANALYSIS.md`.

Setup:
- Base is production (front be975f36, back 56098f66; migration head 0120).
- Branch `feature/games-v3`, worktrees `_wt/g3-front` and `_wt/g3-back`.
- Decisions D-1740..D-1779; migrations 0122..0125. 0121 is taken by the course-meetings branch; whichever merges second re-points its `down_revision`.

## 0. Owner decisions (2026-11-22; the owner delegated these UX/business calls)

| # | Decision |
|---|---|
| O1 | **Sounds: yes.** Our own synthesized set (§11), package `audioplayers`. On by default; the mute toggle turns them off |
| O2 | Reward values (seeded INACTIVE; the super admin switches them on): weekly rank 1 = 30 %, ranks 2–3 = 15 %; daily rank 1 = 10 %; 3 qualified referrals = 10 %, 10 = 25 %; 25 unique link opens = 5 %; each with a max discount amount, valid 30 days |
| O3 | The platform pays for a coupon; teacher earnings stay on the pre-coupon price |
| O4 | Coupons are auto-issued to clean winners; flagged winners wait for the super admin |
| O5 | A referral qualifies after a verified account + 3 ranked games on 2 different days (setting `verified` / `activity` / `purchase`) |
| O6 | The week starts Saturday (setting); the daily cut is 00:00 platform time |
| O7 | No speed bonus in `quran` / `tajweed` (accuracy only) |
| O8 | Coupons work for courses, packages and the store (money, not points) from day one, after the item's own discount; one coupon per order; total coupon discount capped at 50 % |

## 1. Motion spec (stream S1)

### Rules for every engine

**Tokens only.** A new file, `lib/features/games/shell/game_motion.dart`, derives every value from `AppMotion.of(context)`, so everything is 0 under Reduce motion.

| Name | Value | Use |
|---|---|---|
| `tap` | fast, 180 ms | colour changes, drag lift |
| `snap` | base, 220 ms | drops, pulses, retractions |
| `settle` | slow, 300 ms | returns, flips, draw-ins |
| `celebrate` | slow × 2, 600 ms | the total deal-in |
| `stagger` | fast ÷ 3, 60 ms | gap between items in a sequence |
| `hold` | slow × 2 | how long a wrong state stays |

- **Curves:**
  - `AppEase.out` for moves;
  - `AppMotion.emphasized` for a return or a flip;
  - `Curves.easeOutBack` for a pop.
- **Sizes:**
  - shake amplitude `AppSpace.xs`;
  - strokes from `AppBorder`. Add `AppBorder.line = 3`.

**States are colour + icon + one move, never colour alone.**
- **Correct:** `c.success` tint + a check icon (`AppPopIn`) + a scale pulse 1 → 1.06 → 1 (`snap`, easeOutBack).
- **Wrong:** `c.danger` tint + a cross icon + a horizontal shake of 3 decaying cycles of ±`AppSpace.xs` (`settle`), back to idle after `hold`.
- Colours tween over `tap`.

**Drag.**
- **Lift:** scale 1.04 + shadow from `AppElevation` 1 → 3 over `tap`. Cross-fade two prebuilt shadow layers; never animate blur.
- **Follow:** 1:1 with the finger through a `ValueNotifier<Offset>` + `Transform.translate`, with no `setState` and no easing.
- **Drop on a target:** `snap`.
- **Drop elsewhere:** return over `settle`, emphasized.
- **Hover:** the target under the dragged centre gets a `c.primary` border.

**Tap stays.** Every drag keeps the existing tap path, plus Semantics actions and keyboard support.

**Reduce motion / `app.animations` off.** No shake, flight, flip or particles. The end state (colour, icon, full line) appears at once. Idle loops go through `syncMotionLoop`.

**Low-end safe.**
- Animate only transform, opacity and colour.
- No shaders, `BackdropFilter`, `saveLayer` or animated blur.
- At most 24 particles.
- `RepaintBoundary` around the board and around each painter.
- Painters repaint from a `Listenable`, with an exact `shouldRepaint`.

**Quran / tajweed.** Nothing is drawn over the text (the burst stays in the header). A tile that holds an ayah gets no shake, only the red border and icon.

### Shared widgets

New, in `lib/features/games/shell/`:
- `GameTile`, with states idle / selected / correct / wrong / locked / hint. It wraps the look of `LearnOptionTile`; the learn kit itself is not changed.
- `GameShake`, `GamePulse`, `GameDraggable`, `GameFlight`, `GameComboChip`.

### Per engine

**match: connectors**
- **Painter:** `MatchConnectorPainter` in a `Stack` over both columns (inside the same scrollable, `IgnorePointer`).
- **Anchors:** taken from each tile's rect (`GlobalKey` → `RenderBox`). Use the two facing edge mid-points, chosen by comparing the rects' `dx`, so RTL needs no branch.
- **Curve:** cubic, `P1 = P0 + (Δx/2, 0)`, `P2 = P3 − (Δx/2, 0)`.
- **Draw-in:** `PathMetric.extractPath(0, len × t)` over `settle`; stroke `AppBorder.line`, round caps, end dots that pop.
- **While dragging:** a live line follows the finger (`c.primary` at 60 %).
- **Right pair:** the line stays, in one of 5 tones cycled from `AppTone`, and both tiles pulse.
- **Wrong pair:** the line is drawn in `c.danger`, both tiles shake, and the line retracts over `snap`.
- Tap-tap pairing stays.

**order**
- Drag to reorder with reflow: neighbours slide over `snap` when the dragged centre passes their middle.
- Tap-to-place stays.
- After Check, items are revealed top to bottom, `stagger` apart: pulse if right, shake if wrong.
- "Show the right order" glides each item to its place over `settle`.

**memory**
- 3D flip: `Matrix4.identity()..setEntry(3, 2, 0.0015)..rotateY(π × t)`, with the face swapped at `t = 0.5`, over `settle`. The rotation sign follows `Directionality`.
- Deal-in: `AppPopIn` per card, `stagger` apart.
- A pair pulses; a miss shakes and flips back after `hold`.

**quiz**
- Options enter with `AppReveal`, `stagger` apart.
- Right: fill + pulse.
- Wrong: shake, then the right option fills green after `tap`.

**fill_blank**
- The chosen chip flies into the blank (`GameFlight`, `snap`), and the underline takes the state colour.
- A wrong chip shakes and flies back.

**word_puzzle**
- A letter flies from the pool to its slot (`snap`), and the slot pops.
- Solved: a wave (scale 1.12, `stagger` apart), then green.
- Wrong: the word shakes and the tiles return.
- The built word stays ONE `Text` (D-1670).

**shell**
- After 3 right answers in a row, `GameComboChip` "×3" bumps and the burst grows from 16 to 24 particles. The combo adds no points.
- Finish view: a second burst, `AppCountUp` for the points, and a "Rank 4 today" line.

Engines also record a **trace** for ranked rounds (§2.1): `[{i, a, ms}]`, made of content indices, never screen positions.

## 2. Champions (back: S3, front: S2)

### 2.1 Ranked rounds

**Routes.**
- `POST /games/{id}/rounds` → `{round_id, issued_at, ranked_left}`. Online only; rate limit 60 per hour.
- `POST /games/{id}/plays` gains optional `round_id` + `trace`.

**Server grading.** The server re-grades every trace with `games_config.grade(engine, config, trace)`, which mirrors the Dart scoring, including the Arabic normalisation in `game_text.dart`.

**A play is ranked only when all of these hold:**
- the round belongs to this user and this game, is unused, and is less than 2 h old;
- the trace is complete, with rising `ms`;
- `duration ≤ (received − issued_at) + 5 s`;
- `duration ≥ steps × min_step_ms` (400 ms by default);
- the play arrives within 10 min of finishing;
- it is within the first 3 ranked rounds of that game that day.

**Anything else** is saved as it is today, with `ranked=false`.
- Offline play never ranks.
- Progress uses `min(client score, server score)`, and a mismatch sets a flag.

**Points.** `rank_points` = `round(100 × server_score ÷ max)`, then:
- × the difficulty multiplier: easy 100 %, medium 125 %, hard 150 %;
- + a speed bonus of at most 20 %: `1 − (duration ÷ par) ÷ 2`, bounded, where `par = steps × par_step_s`. No speed bonus for `quran` / `tajweed`.
- 0 stars always gives 0 points.

### 2.2 Periods, scopes, score

**Scopes.**
- `platform`: students in no organization (today's board rule).
- `category`: the 5 categories.
- `org`: when the org's `games.champions` setting is on.

**Periods.** Daily and weekly. The bounds are local midnight in the scope's zone, turned into UTC with `wall_to_utc` (DST-safe). The server's `created_at` decides which period a play belongs to.

**Score.**
- For each day: the best `rank_points` per game, summed over at most 20 different games.
- For a week: the sum of the days.

**Minimum activity.**
- Daily: at least 3 different games.
- Weekly: at least 10 different games on at least 3 days.
- A scope with fewer than 5 eligible players has no champion (`empty`).

**Eligible players:** active, visible on leaderboards (opting out of the leaderboard also opts out of champions), and with parental consent where D-1371 requires it.

**Tie-break, in order:**
1. points;
2. more different games;
3. higher accuracy;
4. less total time;
5. reaching the final total earlier;
6. lower user id.

**Winners:** the top 3 (max 10). The display name is stored as a snapshot, "First L.". No avatar.

### 2.3 The job: `_games_champions_tick`, every 10 min

1. Find the periods that ended at least 15 min ago with no row yet: within the last 3 days for daily periods, 2 weeks for weekly ones. This is also the catch-up after downtime.
2. Claim the period with `live_claims.claim_many(["games.champ:{kind}:{scope}:{key}:{start}"])`.
3. Compute and insert in ONE transaction:
   - `game_champion_periods` (UNIQUE scope + kind + start);
   - `game_champions`.
4. Rewards (§3), with `issue_key="champ:{id}"`. The reward goes to `pending` when:
   - the winner has a flag;
   - two winners share a device in the same period;
   - auto-issue is off.
5. Notify each winner once, the linked parent too, and emit the LiveEvent `games_champions`.

**Flags:** `too_fast`, `grade_mismatch`, `burst` (more than 40 ranked rounds a day), `shared_device`.

**Void:** an admin can void a period and recompute it while none of its coupons has been used.

### 2.4 Screens (S2)

**Hall of Champions** (`lib/features/games/champions/`):
- scope chips: Everyone / a category / My organization;
- Today / This week / Past winners;
- a podium (an initial in a theme tone, no avatar);
- standings: the top 20, with my row pinned;
- a countdown formatted with `AppTime`;
- `AppEmpty` when there is no champion yet;
- help page `games.champions`.

**Games tab:** a champions strip, fed from the games list call (no new request).

**Winner sheet:** shown once per win. A laurel, "ما شاء الله، أنت بطل اليوم", the coupon and a "Use it" button; one burst.

**Home:** a champion line inside `/me/home`.

## 3. Rewards → discounts (back: S3, front: S2)

### 3.1 Rules and coupons

**`reward_rules` (a table):**

| Field | Values |
|---|---|
| `trigger` | `champion_daily`, `champion_weekly`, `referrals`, `shares`, `referee_welcome` |
| scope and range | `scope_kind`, `rank_from..rank_to`, `threshold`, `window` (`month` / `lifetime`) |
| reward | `reward_kind` (`coupon_percent`, `coupon_fixed`, `points`), `value`, `currency`, `max_discount` |
| where it applies | `applies_to` (`any`, `course`, `package`, `store`), `min_order` |
| limits | `valid_days`, `per_user_month_cap`, `month_budget`, `country_code`, `active` |

**Coupons.**
- Personal and single use.
- A 10-character code with no look-alike letters.
- Statuses: active → reserved → redeemed, or expired / revoked.
- A `points` reward goes straight to `points_service.credit` instead of a coupon.

**`features/rewards/coupon_service.py`:**
- `quote` returns the discount or an error code.
- `reserve` does `UPDATE … SET status='reserved' WHERE id=:id AND status='active'` and requires `rowcount == 1`. This is the "once" guarantee. It also writes a `coupon_redemptions` row.
- `consume` runs on settlement.
- `release` runs on failure or when the hold expires.
- A refund does not give the coupon back.

**Checkout hooks:**
- `PaymentService._calc_fees`: the coupon comes off the plan price, before fees and VAT.
- `package_service`: `final_price` and `enroll`.
- `store/orders.create_order`: money methods only, before tax.

Each checkout body gains `coupon_code`. Teacher earnings use the price before the coupon.

**Error codes**, each with text in `apiErrorText`: `coupon_not_found`, `coupon_not_yours`, `coupon_used`, `coupon_expired`, `coupon_revoked`, `coupon_not_applicable`, `coupon_min_order`, `coupon_currency`.

### 3.2 Referrals and shares

**Capture.**
- A `ref` from any start URL (`/c/<id>?ref=`, or the new `/app/?ref=<uid>`) is kept on the device for 30 days (first touch wins) and sent at sign-up.
- Sign-up also has an optional, collapsed "Invited by @username" field.

**At sign-up:** one `referrals` row per referee (UNIQUE `referee_id`), either `pending` or `rejected` with a reason:
- `self`;
- `device_seen`;
- `ip_burst`: more than 3 per IP hash in 24 h;
- `referrer_inactive`.

**Qualification:**
- by O5, never earlier than 48 h after sign-up;
- more than 20 a month go to review.

**Shares:** count unique openers. Signed-in users by `clicker_id`, guests by `ip_hash`, at most 10 guests a day. Taps on a share button are not counted.

**Thresholds:** each tier is issued once per user per window, with `issue_key="ref:{user}:{rule}:{window}"`.

**Screens:**
- **My rewards** (`lib/features/rewards/`, a Profile item): coupons, an invite card with progress (`AppFill`), Share, and "How it works".
- **`CouponField`** in the course payment sheet, the package enrol sheet and the store cart.

### 3.3 Super admin

Page `admin.rewards` (`lib/features/admin/rewards/`), with these tabs:
- **Rules**
- **Champions:** periods, flags, Award / Revoke / Void
- **Coupons:** search, give one by hand, revoke with a reason
- **Referrals:** the review queue

Module settings:

| Module | Setting | Default |
|---|---|---|
| `games` | `champions_daily`, `champions_weekly` | on |
| `games` | `champions_top_n` | 3 |
| `games` | `champions_min_players` | 5 |
| `games` | `ranked_attempts_per_game` | 3 |
| `games` | `games_per_day_cap` | 20 |
| `games` | `week_start` | `sat` |
| `rewards` | `auto_issue` | on |
| `rewards` | `referral_qualify` | `activity` |
| `rewards` | `referral_month_cap` | 20 |
| `rewards` | `coupon_max_percent` | 50 |
| `rewards` | `share_guest_day_cap` | 10 |

## 4. Data model (after 0120; 0121 belongs to the course-meetings branch)

| Migration | Contents |
|---|---|
| `0122_games_ranked` | `game_rounds` (uuid, user_id, game_id, issued_at, used_at). `game_plays` gains `round_id`, `ranked`, `rank_points`, `server_score`, `flags` JSON, and `trace` JSON (nulled after 14 days) |
| `0123_games_champions` | `game_champion_periods` (UNIQUE scope_kind + scope_key + period_kind + period_start; status `computed` / `empty` / `void`). `game_champions` (UNIQUE period + rank, UNIQUE period + user; `reward_status`, `coupon_id`, `notified_at`) |
| `0124_rewards_coupons` | `reward_rules`, `coupons` (code UNIQUE, issue_key UNIQUE), `coupon_redemptions` (UNIQUE target_type + target_id). `payments`, package enrolments and `store_orders` gain `coupon_id` and `coupon_discount` |
| `0125_referrals` | `referrals` (referee_id UNIQUE). `course_share_clicks` gains `ip_hash`. Seeds the default `reward_rules` INACTIVE |

Every change is the model AND the Alembic revision, with a downgrade that refuses to drop live rows (`refuse_downgrade_if_rows`).

## 5. API routes (`/api/v1`)

**Games:**
- `POST /games/{id}/rounds`
- `POST /games/{id}/plays`, which gains `round_id` and `trace`; the answer gains `ranked`, `rank_points` and `rank_today`
- `GET /games/champions?scope=&key=&period=&page=`
- `GET /games/champions/standings?scope=&key=&period=`

**Rewards:**
- `GET /me/rewards`
- `POST /coupons/quote`
- the three checkout bodies gain `coupon_code`

**Sign-up:** `POST /auth/register` gains `ref` and `invited_by`.

**Admin:**
- `/admin/rewards/rules[/{id}]` (CRUD)
- `/admin/rewards/champions` (+ `…/{id}/award`, `…/{id}/revoke`), `/admin/rewards/periods/{id}/void`
- `/admin/rewards/coupons` (+ `…/{id}/revoke`)
- `/admin/rewards/referrals` (+ `…/{id}/approve`, `…/{id}/reject`)

**Also:**
- `FLUTTER_API_CHANGES.md`;
- an `AttentionTabs` key `rewards`, on both sides;
- LiveEvents `games_champions` and `rewards`;
- notification types `games_champion`, `reward_coupon` and `referral_qualified`, with `AppNavigator` targets;
- entries in `app_features_guide.json`;
- help pages `games.champions`, `rewards.mine` and `admin.rewards`.

## 6. Kill switches

New:
- `games.champions`
- `rewards.coupons`
- `rewards.referral`
- `admin.rewards`
- `games.sounds`

Existing ones still apply: `student_tab_games`, `games.leaderboard`, `games.rewards`, `app.animations`.

After adding the keys, regenerate the contract snapshots.

## 7. Decisions

| Range | Area |
|---|---|
| D-1740..1749 | motion and sounds (S1) |
| D-1750..1759 | ranked rounds and champions (S3) |
| D-1760..1769 | coupons and referrals (S3) |
| D-1770..1779 | champions and rewards UI (S2) |

Each stream writes its decisions into a sidecar file `docs/games-v3/DEC_<stream>.md`; the lead folds them into `docs/DECISIONS.md`.

## 8. Streams

| Stream | Worktree / branch | Owns | Depends on |
|---|---|---|---|
| S0 contract (Fable) | `_wt/g3-front` | `docs/games-v3/CONTRACT.md` (the JSON of §5, the trace shape per engine, error codes) + `grading_vectors.json` (shared by the Dart and Python tests) | — |
| S1 front motion + sounds | `_wt/g3-s1` feature/g3-motion | `game_motion.dart`, the shared widgets, the 6 engines, the connector painter, trace recording, the round start in `game_play_page.dart`, sounds (§11) | S0 |
| S2 front champions + rewards UI | `_wt/g3-s2` feature/g3-rewards | Hall, strip, winner sheet, My rewards, `CouponField` ×3, sign-up "Invited by", `ref` capture, the admin page, translations | S0 (`FakeApi` until S3) |
| S3 back | `_wt/g3-back` feature/games-v3 | migrations 0122→0125, grading, champions + job, coupons + checkout hooks, referrals, catalog, guide, help seed, snapshots | S0 |

- S1 never touches checkout or admin files. S2 never touches `engines/`.
- The shared files are `game_play_page.dart` (S1) and `games_tab.dart` (S2).
- Merge order: S3 → S1 → S2, then one walk in the real app.
- Phase 2, not now: streaks with a weekly freeze, league tiers, friend quests.

## 9. Risks

| Risk | Answer |
|---|---|
| The client and server grade differently | the shared `grading_vectors.json`; on a mismatch the play is unranked and flagged, never a crash |
| A script that knows the answers fakes a trace | time floors, attempt caps, flags, admin review, capped coupons, a monthly budget (offline play stays a requirement) |
| Siblings share a phone | `shared_device` only sends the reward to review |
| Coupon cost | `max_discount`, the 50 % cap, `month_budget`, expiry; the rules are seeded inactive |
| A coupon stuck in `reserved` | holds expire, the tick releases them, `consume` is idempotent |
| Jank | the low-end rules in §1; a profile-mode check is part of S1 |
| The job runs twice or misses a day | the claim + the UNIQUE period row + the catch-up window |
| Three checkouts changed at once | one helper; with no coupon code, every price is unchanged (a test) |

## 10. Tests that matter

### Back (`tests/games_v3/`, on SQLite; concurrency also on the nb-pg container)

**Idempotency:** run the tick twice, and two workers at once. There must be one period row, one set of winners, one coupon and one notification each. A missed day is caught up.

**Time zones:**
- plays at 23:59 and at 00:01;
- a DST change day;
- an org in another zone;
- the week starting on `sat` vs `sun`.

**Tie-breaks:** one test per step.

**Minimums:**
- 2 games is not eligible;
- 4 players gives `empty`;
- an opted-out student is absent.

**Ranked rules.** Each case is saved but unranked:
- a play that is too fast;
- a reused round;
- another user's round;
- an incomplete trace;
- a 4th attempt;
- an offline play.

Also: `rank_points` equals the vectors, and there is no speed bonus for `quran`.

**Referral fraud:**
- self-referral, same device, an IP burst;
- a second referrer for the same referee;
- qualifying before 48 h;
- the monthly cap;
- a tier issued only once per window.

**Coupon used once:**
- two checkouts at the same moment: one wins, the other gets `coupon_used`;
- release, then reuse;
- consume twice = one redemption;
- someone else's coupon, an expired one, a revoked one, the wrong target, the wrong currency;
- no coupon = an unchanged price;
- teacher earnings follow O3.

### Front

**Layout:** `expectNoLayoutErrors` for `GameTile` states, the match board with connectors, Hall, the podium, My rewards, `CouponField` and the admin tabs.

**Reduce motion:** in each engine, after a right and a wrong answer, no controller is still running and the end state shows.

**Connector anchors:** a pure function, tested in LTR and RTL.

**Traces:** each engine's trace matches `grading_vectors.json`.

**Contract and existing suites:** the contract tests, `help_ids_test`, `rtl_icons_test` and the perf budgets.

**Sounds:**
- `GameFeedback` with a fake player:
  - when muted, nothing plays;
  - a combo replaces correct;
  - `quran` skips the wrong sound;
  - a player that throws does not fail the round.
- An asset test: the 8 files exist and each is under 12 KB.

## 11. Sounds (S1, D-1741)

**The set:** `tap`, `correct`, `wrong`, `combo`, `snap`, `flip`, `finish`, `champion`.
- Made by `tool/gen_game_sounds.py` (numpy + soundfile, all synthesized; no downloaded or stock audio).
- Output is `assets/sounds/games/<name>.mp3`, **MP3 only**: it plays on Android, iOS and the web, so there is no per-platform switch. That is about 29 KB in total.
- Add `- assets/sounds/games/` to `pubspec.yaml`.
- Regenerate with `py -3.12 tool/gen_game_sounds.py` (add this line to CLAUDE.md). If `soundfile` is missing, use a throwaway venv.
- The script enforces at most 600 ms per sound (the champion fanfare at most 2 s), at most 150 KB in total, and one loudness level for the set.

**Package:** `audioplayers`. A dry run showed the lock gains only the 7 `audioplayers*` packages and nothing is downgraded. Check again at the real `pub add`.

**One seam:**
- `GameFeedback.cue(bool)` becomes `play(GameSound)` plus the existing haptic.
- Engines never import the package.
- The new file is `lib/features/games/shell/game_sounds.dart`.

**Loading:**
- Nothing loads at app start.
- The first shell to open with sound on creates the low-latency players and preloads the 7 short sounds; `champion` loads when the winner sheet opens.
- On the web, the preload waits for the first tap (the browser's autoplay rule).
- The players are released when the last shell closes.
- A failure is swallowed.

**Mute:** the existing toggle mutes sound and vibration together. Sounds are on by default; muted means no player is created.

**Silent mode:**
- iOS: the audio session is `ambient`, which follows the silent switch and mixes with other audio.
- Android: usage `game`, with no audio-focus request.
- Reduce motion does not mute.

**Never:**
- the `wrong` sound over an ayah in `quran` / `tajweed` (haptic + colour only);
- any sound in the editor preview;
- any sound while a live room or a video is open.

**Rate:**
- `tap` is dropped if the last one played less than 60 ms ago.
- `combo` replaces `correct` on the 3rd right answer; they never play together.

**Kill switch `games.sounds`:** off = haptics only.

## 12. Release (owner 2026-11-22: deploy automatically once done)

After S3 → S1 → S2 are merged and the lead's own Chrome walk passes:

1. **Gates.**
   - Back: `tests/games_v3/` and the touched billing / store / package suites; `alembic upgrade head` on the nb-pg container.
   - Front: the analyzer, the CI suites, `flutter build web --release`, and the regenerated contract snapshots.
2. **Production.** Make a backup tag `pre-games-v3-<date>` in both repos, then fast-forward or merge into `production` and push. Never force.
3. **Deploy NextBrain:**
   - `D:/platform/nextbrain/back/.venv312/Scripts/python D:/platform/nextbrain/deploy/deploy.py backend --no-env-check` (it takes a database backup first);
   - then `… deploy.py frontend`.
4. **Alfaheem:** sync + gates + push + deploy, using the memory recipe `alfaheem-deploy`.
5. **Smoke on production:**
   - one ranked round and the standings;
   - a coupon used once in a checkout and refused the second time;
   - a sign-up through `?ref=`;
   - sounds on the web.
6. **Switch on.** The reward rules are seeded INACTIVE; the super admin switches them on (the defaults in O2).
7. **Mobile.** The audio package needs a new app build. Old apps keep working, because `round_id`, `trace` and `coupon_code` are optional.

**Rollback:**
- the web swap rolls the front back;
- the kill switches turn each part off without a deploy;
- migrations 0122..0125 only add tables and nullable columns.
