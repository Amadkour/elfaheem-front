# Games v3: contract (S0, 2026-11-22)

The JSON that S1, S2 and S3 build against. `PLAN.md` holds the reasons. Test numbers: `grading_vectors.json`.

Conventions:
- Base path `/api/v1`. Errors are `{"detail": {"code", "message", …}}` (the games module's `err`).
- Datetimes are naive UTC ISO strings (`2026-11-22T21:00:00`), as the games routes answer today. Money is a float in major units.
- `T|null` = always present, may be null. `T?` = may be absent. Old apps keep working: every new request field is optional.
- A kill switch that is off answers 403 `feature_disabled` with `feature: "<key>"`.

## 1. Kill switches, settings, badges, events

**Kill switches** (new, in `feature_catalog.py`):

| Key | Off means |
|---|---|
| `games.champions` | no rounds, no champions routes, no strip, no home line; plays are saved unranked |
| `rewards.coupons` | no My rewards coupons, `quote` refused, `coupon_code` ignored by the checkouts |
| `rewards.referral` | `ref` / `invited_by` ignored, no invite card |
| `admin.rewards` | the super admin's Rewards page hidden |
| `games.sounds` | haptics only (front only) |

**Module settings** (`module_settings.REGISTRY`):

| Module | Key | Type | Default |
|---|---|---|---|
| `games` | `champions_daily`, `champions_weekly` | bool | `true` |
| `games` | `champions_top_n` | int 1..10 | `3` |
| `games` | `champions_min_players` | int | `5` |
| `games` | `ranked_attempts_per_game` | int | `3` |
| `games` | `games_per_day_cap` | int | `20` |
| `games` | `week_start` | `sat` / `sun` / `mon` | `"sat"` |
| `rewards` | `auto_issue` | bool | `true` |
| `rewards` | `referral_qualify` | `verified` / `activity` / `purchase` | `"activity"` |
| `rewards` | `referral_month_cap` | int | `20` |
| `rewards` | `coupon_max_percent` | int 1..100 | `50` |
| `rewards` | `share_guest_day_cap` | int | `10` |

The org setting `games.champions` (org scope, bool, default `false`) switches the `org` scope on.
Server constants, not settings: `MIN_STEP_MS = 400`, round life 2 h, rounds rate limit 60 per hour.

**Attention.** Tab key `rewards` (`AttentionTabs.rewards`, server `TABS`). Count = the user's `active` coupons with `seen_at` null. `GET /me/rewards` sets `seen_at`.

**LiveEvents** (`live_update_service.py` and `LiveEvents`, both in `serverTypes`):

| Name | Dart constant | Payload | Sent to |
|---|---|---|---|
| `games_champions` | `gamesChampions` | `{period_id, period_kind, scope_kind, scope_key}` | the winners and their linked parents |
| `rewards` | `rewards` | `{kind: "coupon_issued" / "coupon_used" / "coupon_expiring" / "referral_qualified", coupon_id?}` | the owner |

**Notifications.** The server's link answer names `module` and `id`; `AppNavigator` opens:

| `type` | `module` | `id` and extra data | Opens |
|---|---|---|---|
| `games_champion` | `games_champions` | champion id; `scope_kind`, `scope_key`, `period_kind` | Hall of Champions on that scope and period (the winner sheet when the win is mine) |
| `games_champion` (parent) | `parent_child` | child id | the child's report (existing target) |
| `reward_coupon` | `rewards` | coupon id | My rewards on that coupon |
| `referral_qualified` | `rewards` | none; `section: "invite"` | My rewards on the invite card |

`reward_coupon` is sent on issue and 3 days before expiry. Quiet hours and the one-a-day rule: `ANALYSIS.md`.

## 2. Ranked rounds

### `POST /games/{id}/rounds` (no body)

200:
```json
{"round_id": "5b0e…uuid" , "issued_at": "2026-11-22T10:00:00", "ranked_left": 2}
```
- `round_id`: `string|null`. Null when no ranked attempt is left today (`ranked_left: 0`); the round is then played unranked.
- `ranked_left`: ranked attempts left for this game today, counting this round.
- Errors: 404 `game_not_found`, 403 `feature_disabled` (`student_tab_games` or `games.champions`), 429 `too_many_attempts`.
- Any error, or no network: the app plays the round unranked. It never blocks play.

### `POST /games/{id}/plays`

Request (today's fields, plus two):
```json
{"client_id": "…", "score": 3, "max_score": 4, "duration_s": 41, "played_at": "…",
 "round_id": "5b0e…uuid", "trace": [{"i": 0, "a": 2, "ms": 4000}]}
```
- `round_id`: `string?|null`, at most 36 characters. `trace`: `array?|null`, at most 500 entries.
- A bad `round_id` or `trace` never fails the request: the play is saved unranked.

Response (today's fields, plus five at the top level):
```json
{"play": {…}, "progress": {…}, "new_badges": [], "points_awarded": 0, "duplicate": false,
 "ranked": true, "rank_points": 145, "rank_today": 4, "unranked_reason": null, "ranked_left": 2}
```
- `ranked`: bool. `rank_points`: int, 0 when unranked.
- `rank_today`: `int|null`. The user's place in today's daily standings of their own scope (`org` when their organization has champions on, else `platform`), among every eligible player with points; the minimum activity is not applied. Null when unranked, opted out, or `games.champions` is off.
- `unranked_reason`: `string|null`, one of `no_round`, `round_invalid` (unknown, another user's, another game's, used, older than 2 h), `bad_trace`, `too_fast`, `too_late`, `attempts_used`, `grade_mismatch`, `feature_off`.
- A duplicate `client_id` answers the first play's values again.

### When a play is ranked

With `T` = server receive time and `D` = `trace[-1].ms`, all of these hold:
1. the round is this user's, this game's, unused, and `T − issued_at ≤ 2 h`;
2. the trace is valid and complete (§3);
3. `D ≥ max_score × MIN_STEP_MS` (else `too_fast`, flag `too_fast`);
4. `D − 5 s ≤ T − issued_at ≤ D + 10 min` (else `bad_trace` on the left side: the round lasted longer than the time since it was issued; `too_late` on the right);
5. it is within the day's first `ranked_attempts_per_game` ranked plays of this game;
6. the body's `max_score` equals the server's, and the body's `score` equals `server_score` (else `grade_mismatch`, flag `grade_mismatch`).

The round is marked used by any play that names it. The stored `score` is `min(body score, server_score)` whenever the trace graded; without a gradable trace it stays the body's score, as today.

## 3. Trace

`trace = [{i, a, ms}]`, in the order things happened.
- `ms`: int ≥ 0, milliseconds since the engine first showed; never decreasing along the array.
- `i` and `a` are content indices into the stored `config`, never screen positions. A stored config passed `games_config.check`, so the Dart "playable" lists equal the raw arrays.
- `max_score` = the number of units (`questions`, `pairs`, `items`, `words`).
- An invalid or incomplete trace is refused as a whole (`bad_trace`).

| Engine | One entry per | `i` | `a` | Valid and complete when |
|---|---|---|---|---|
| `quiz` | answered question | question index | picked option index (into `options`) | each question exactly once, any order; `a` in range |
| `match` | pairing try | pair index of the left (`a` side) tile | pair index of the picked `b` tile | neither side already matched; at the end every pair is matched |
| `order` | final position, written at Check | position `0..n−1`, ascending | item index placed there | the `a` values are a permutation; every `ms` is the Check time |
| `memory` | second card of a try | card id of the first card | card id of the second card | card id = `2 × pair + (0 for a, 1 for b)`; `i ≠ a`; neither card's pair already matched; at the end every pair is matched |
| `fill_blank` | answered item | item index, ascending | string: the picked option as written, or the typed text | each item exactly once; `a` not empty after trim |
| `word_puzzle` | check of a full word | word index, never decreasing | array of letter indices in placed order; optional `h: true` on the entry when Hint was used on this word before this check | `a` is a permutation of the word's letters (§4); every word has at least one entry; no entry after a word's right one |

## 4. Grading (`games_config.grade(engine, config, trace) → (server_score, max_score)`)

It mirrors the Dart scoring of today.

| Engine | `server_score` |
|---|---|
| `quiz` | entries with `a == questions[i].answer` |
| `match` | `n` − the number of different `i` that have an entry with `a ≠ i` (a pair scores only on a first-try match) |
| `order` | positions where `items[a] == items[i]` as strings |
| `memory` | `misses` = entries where `i // 2 ≠ a // 2`; score = `clamp(n − max(0, misses − n), 0, n)` |
| `fill_blank` | right items (below) |
| `word_puzzle` | words whose FIRST entry is right and has no `h` |

**`fill_blank`, an item is right when:**
- it has options (`options` is a non-empty list): `trim(a) == trim(answer)`, compared as written, tashkeel included (D-1676). So "العلمَ" or "العلم" for the answer "العلمِ" is wrong;
- it has none (typed): `same(a, answer)`.

**`word_puzzle`, an entry is right when** `same(join(letters[k] for k in a), join(letters))`. So equal letters are interchangeable ("باب") and so are alef forms ("أنا" as [2,1,0]).

**`letters(word)`:** the grapheme clusters of the trimmed word, whitespace dropped (Dart `characters`). The server's rule: a code point of Unicode category `M*`, or U+200C / U+200D, joins the letter before it; every other code point starts a letter. The two agree for Arabic and Latin text.

**`same(given, expected)`** = `normalize(given)` is not empty and equals `normalize(expected)`.

**`normalize(s)`** (`game_text.dart`), by code point:
1. trim, then lower-case;
2. drop the marks U+0610–061A, U+064B–065F, U+0670, U+06D6–06DC, U+06DF–06E8, U+06EA–06ED and the tatweel U+0640;
3. U+0020, U+0009, U+000A, U+000D, U+00A0: a run becomes one space, and none at the start or the end;
4. U+0622, U+0623, U+0625, U+0671, U+0672, U+0673 become U+0627.

Nothing else is folded: taa marbuta and haa stay different.

## 5. Stars and `rank_points`

Integer arithmetic only (`//` is floor division), so Dart and Python agree:

```
stars       = 3 if score/max ≥ 0.9, 2 if ≥ 0.6, 1 if ≥ 0.3, else 0        (stars_for, unchanged)
base        = (200 × server_score + max) // (2 × max)                      (round(100 × score ÷ max), half up)
par_ms      = max × par_step_s × 1000
bonus       = 0 for category quran / tajweed, else max(0, 200 − (100 × D) // par_ms)      (per mille, 0..200)
rank_points = 0 when stars == 0, else (base × difficulty × (1000 + bonus) + 50000) // 100000
```

- `difficulty`: easy 100, medium 125, hard 150. `D` = `trace[-1].ms`. The range is 0..180.
- `par_step_s`: quiz 12, match 6, order 6, memory 8, fill_blank 15, word_puzzle 20.
- The bonus is 20 % at once, 10 % at par, and 0 from twice par.

## 6. Champions

Query values: `scope` = `platform` (default) / `category` / `org`; `key` = a category (`quran`, `tajweed`, `fiqh`, `nahw`, `general`) or the org id, absent for `platform`; `period` = `daily` (default) / `weekly`.

Errors on both routes: 422 `champions_bad_scope`, 422 `champions_bad_period`, 403 `not_a_member` (another org), 403 `feature_disabled` (`games.champions`; also for an org with the setting off, with `feature: "org"`).

Who counts: `platform` and `category` = eligible students in no organization (`category` counts only that category's games); `org` = that organization's students.

`row` = `{rank: int, name: "First L.", points: int, games: int, is_me: bool}`. No user id, no avatar.

### `GET /games/champions/standings?scope=&key=&period=`

The running period:
```json
{"scope": "platform", "key": null, "period": "daily",
 "period_start": "2026-11-21T21:00:00", "period_end": "2026-11-22T21:00:00",
 "items": [row], "me": row, "total": 37,
 "eligible": false, "needs": {"games": 2, "days": 0},
 "min_games": 3, "min_days": 1, "min_players": 5, "visible": true}
```
- `items`: the top 20 of the players who already meet the minimum activity. `total`: how many those are.
- `me`: `row|null`, my row even below the minimum (`rank` is then null); null when I am not in this scope or opted out.
- `eligible`: I meet the minimum. `needs`: what I still lack. Weekly: `min_games` 10, `min_days` 3.
- `visible`: my leaderboard opt-in (`PUT /me/games/leaderboard`).

### `GET /games/champions?scope=&key=&period=&page=`

Past winners, newest first, 10 periods a page:
```json
{"scope": "platform", "key": null, "period": "daily",
 "items": [{"id": 12, "period_kind": "daily", "period_start": "…", "period_end": "…",
            "status": "computed", "winners": [row]}],
 "page": 1, "size": 10, "total": 31, "has_more": true,
 "scopes": [{"scope": "platform", "key": null, "name_ar": "الجميع", "name_en": "Everyone"}]}
```
- `status`: `computed` or `empty` (`winners: []`). Void periods are left out.
- `scopes`: the chips this user may open (platform, the 5 categories, their organization when it is on).

### Strip and home

- `GET /games` gains `champions`: `null`, or
  `{"scope", "key", "period": "daily", "period_end", "top": [row], "me": row|null}` (`top` = 3 rows of the running standings).
- `GET /me/home` gains `champion`: `null`, or my newest win whose period ended in the last 2 days (daily) or 7 days (weekly):
  `{"champion_id": 55, "period_kind": "daily", "scope_kind": "platform", "scope_key": null, "rank": 1,
    "period_start": "…", "period_end": "…", "reward_status": "issued", "coupon_id": 9}`.
  `reward_status`: `none` / `pending` / `issued` / `revoked`. `coupon_id`: `int|null`.
- "Shown once" for the winner sheet is kept on the device, by `champion_id`.

## 7. Rewards and coupons

`coupon` =
```json
{"id": 9, "code": "K7M2PQ4XTH", "status": "active", "kind": "percent", "value": 30.0,
 "currency": "EGP", "max_discount": 300.0, "applies_to": "any", "min_order": 0.0,
 "source": "champion_weekly", "issued_at": "…", "expires_at": "…", "redeemed_at": null,
 "target": null}
```
- `status`: `active` / `reserved` / `redeemed` / `expired` / `revoked`. `kind`: `percent` / `fixed`.
- `currency`, `max_discount`, `redeemed_at`: nullable. `target`: `{"type": "course" / "package" / "store", "id": int}|null`.
- `source`: the rule's trigger, or `manual`.
- Codes: 10 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`. Input is trimmed and upper-cased.

### `GET /me/rewards`

```json
{"enabled": {"coupons": true, "referral": true},
 "coupons": [coupon],
 "wins": [{"champion_id": 55, "period_kind": "daily", "scope_kind": "platform", "scope_key": null,
           "rank": 1, "period_start": "…", "reward_status": "issued", "coupon_id": 9}],
 "referral": {"link": "https://nextbrain.site/app/?ref=123", "username": "ahmed",
              "pending": 1, "qualified": 2, "qualified_this_month": 2,
              "tiers": [tier]},
 "shares": {"unique_opens": 14, "tiers": [tier]}}
```
- `tier` = `{rule_id, threshold, window, reward_kind, value, currency, max_discount, count, issued: bool}`; only active rules. `count` is my number in that window.
- `referral` and `shares` are null when `rewards.referral` is off. `username` is nullable. `wins`: the last 20.
- Coupons: active first, then the rest, newest first, at most 50.

### `POST /coupons/quote`

Request:
```json
{"code": "K7M2PQ4XTH", "target_type": "course", "target_id": 31, "plan": "monthly", "item_ids": null}
```
- `target_type`: `course` (`target_id` = course id, `plan?`), `package` (`target_id` = package id), `store` (`item_ids`, no `target_id`).

Response: `{"coupon": coupon, "currency": "EGP", "price": 400.0, "discount": 120.0, "price_after": 280.0}`.
- `price`: the item's price after its own discount, before fees, VAT and tax (store: the net subtotal).

**Discount.**
- `percent`: `price × value ÷ 100`. `fixed`: `value`.
- Then capped by `max_discount` (when set) and by `price × coupon_max_percent ÷ 100`; rounded to 2 places.
- A coupon with a `currency` applies only to a target in that currency.

**Errors** (the same codes from the three checkouts):

| HTTP | `code` | When |
|---|---|---|
| 404 | `coupon_not_found` | no such code |
| 403 | `coupon_not_yours` | another user's coupon |
| 409 | `coupon_used` | reserved or redeemed |
| 410 | `coupon_expired` | past `expires_at` |
| 410 | `coupon_revoked` | revoked |
| 422 | `coupon_not_applicable` | `applies_to` does not cover the target; a store order paid with points; a free target |
| 422 | `coupon_min_order` | `price < min_order` (with `min_order`) |
| 422 | `coupon_currency` | the currencies differ (with `expected`) |
| 403 | `feature_disabled` | `rewards.coupons` is off (quote only; the checkouts ignore the code) |

### Checkouts: optional `coupon_code`

| Route | Where |
|---|---|
| `POST /payments/create-web-session`, `/payments/record-sdk-payment`, `/payments/create-wallet-session` | body field |
| `POST /payments` (saved card), `GET /payments/fees/preview` | query parameter |
| `POST /packages/{id}/enroll` | body `{provider?, coupon_code?}` |
| `POST /store/quote`, `POST /store/orders` | body field |

- Every answer that carries a price gains `coupon_discount: float` (0.0 without a coupon) and `coupon_code: string|null`.
- The coupon comes off the price before fees, VAT and tax. Without a code every number is unchanged.
- A waiting-list enrolment keeps the code and reserves the coupon only when its checkout opens.
- A store idempotency replay answers the first order, whatever code the replay carries.

## 8. Sign-up and referrals

`POST /auth/register` gains:
- `ref`: `int|string?`: the referrer's user id from a link.
- `invited_by`: `string?`: a username, with or without `@`.

Neither can fail a sign-up: an unknown, invalid or self value is ignored. When both resolve, `invited_by` wins. The answer is unchanged.

`POST /courses/{id}/share-click` is unchanged in shape; it now stores `ip_hash`. `/app/?ref=<uid>` records no click: it is only kept for sign-up.

## 9. Admin (`/admin/rewards`, platform admins; 403 `admin_required`; lists answer `{items, total, has_more}` with `skip` / `limit`)

`rule` =
```json
{"id": 1, "trigger": "champion_weekly", "scope_kind": "platform", "rank_from": 1, "rank_to": 1,
 "threshold": null, "window": null, "reward_kind": "coupon_percent", "value": 30.0, "currency": "EGP",
 "max_discount": 300.0, "applies_to": "any", "min_order": 0.0, "valid_days": 30,
 "per_user_month_cap": 2, "month_budget": null, "country_code": null, "active": false,
 "created_at": "…", "updated_at": "…"}
```
- `trigger`: `champion_daily` / `champion_weekly` / `referrals` / `shares` / `referee_welcome`.
- `scope_kind`: `platform` / `category` / `org` / null (any); champion triggers only.
- `window`: `month` / `lifetime`; threshold triggers only. `reward_kind`: `coupon_percent` / `coupon_fixed` / `points`.

| Route | Body → answer |
|---|---|
| `GET /rules` | → `{items: [rule]}` |
| `POST /rules` (201), `PUT /rules/{id}` | the rule's fields → `rule`; 422 `reward_bad_rule` (with `field`) |
| `DELETE /rules/{id}` | → `{deleted: true}`; 409 `reward_rule_used` when coupons came from it (switch it off instead) |
| `GET /champions?period=&scope=&status=&flagged=` | → items of `admin_champion` |
| `POST /champions/{id}/award` | `{rule_id?}` → `admin_champion`; 409 `reward_already_issued` |
| `POST /champions/{id}/revoke` | `{reason}` → `admin_champion`; 409 `coupon_used` |
| `POST /periods/{id}/void` | `{reason}` → `{id, status: "void", recomputed_id: int|null}`; 409 `coupon_used` |
| `GET /coupons?q=&status=&user_id=` | → items of `coupon` + `user: {id, name, username}`, `issue_key`, `revoke_reason` |
| `POST /coupons` (201) | `{user_id, kind, value, currency?, max_discount?, applies_to?, min_order?, valid_days?, note?}` → the same |
| `POST /coupons/{id}/revoke` | `{reason}` → the same; 409 `coupon_used` |
| `GET /referrals?status=` | → items of `referral` |
| `POST /referrals/{id}/approve`, `…/reject` | `{reason?}` → `referral`; 409 `referral_decided` |

- `admin_champion` = `row` fields + `{id, user: {id, name, username}, period: {id, period_kind, scope_kind, scope_key, period_start, period_end, status}, accuracy, duration_ms, flags: [string], reward_status, coupon_id, notified_at}`.
- Flags: `too_fast`, `grade_mismatch`, `burst`, `shared_device`.
- `referral` = `{id, referrer: {id, name, username}, referee: {id, name, username}, source: "link" / "username", status, reason, created_at, qualified_at}`.
- `status`: `pending` / `review` / `qualified` / `rejected`. `reason`: `self` / `device_seen` / `ip_burst` / `referrer_inactive` / `admin` / null.

## 10. Seeded `reward_rules` (migration 0125, all `active: false`)

Common to every row: `reward_kind: coupon_percent`, `applies_to: any`, `min_order: 0`, `valid_days: 30`, `currency: "EGP"`, `month_budget: null`, `country_code: null`.

| # | `trigger` | `scope_kind` | ranks | `threshold` | `window` | `value` | `max_discount` | `per_user_month_cap` |
|---|---|---|---|---|---|---|---|---|
| 1 | `champion_weekly` | `platform` | 1–1 | | | 30 | 300 | 2 |
| 2 | `champion_weekly` | `platform` | 2–3 | | | 15 | 150 | 2 |
| 3 | `champion_daily` | `platform` | 1–1 | | | 10 | 100 | 4 |
| 4 | `referrals` | | | 3 | `month` | 10 | 100 | 1 |
| 5 | `referrals` | | | 10 | `month` | 25 | 250 | 1 |
| 6 | `shares` | | | 25 | `lifetime` | 5 | 50 | 1 |

The percentages are O2. The currency, the `max_discount` amounts, the caps and the windows are S0's defaults: the super admin edits them before switching a rule on.
