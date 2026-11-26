# API: nicknames and leaderboards (WP4, owner decision O-3)

Backend branch `rd/be-games`. Migration `0150_game_nicknames`. Test `tests/redesign/e2e_games_notebook.py`.

Rule: no leaderboard, champions list, challenge board or ghost ever returns a real name, user id, avatar image,
e-mail, phone or username of another learner. A row carries `nickname` + `avatar` only (and `is_me` where the old
row had it). The scope is the whole platform or the learner's grade, never a class, course or section.

## Nickname

Every learner has ONE nickname, unique on the platform (compared after normalising: Arabic diacritics, tatweel,
alef / ya / ta marbuta forms, case, spaces and punctuation are ignored). It is generated the first time the learner
opens it (Arabic, the style of the design: «صقر الأرقام», «نسر نجد»), and the learner may change it.

```
GET  /api/v1/me/games/nickname
  → {nickname, avatar: {icon, color}, source: "generated" | "custom", can_change_at: ISO | null,
     icons: [..], colors: [..]}
  First call creates it (generated). `can_change_at` null = may change now.

GET  /api/v1/me/games/nickname/suggestions          → {items: [nickname, ...]}   5 free generated names

PUT  /api/v1/me/games/nickname {nickname?, avatar?: {icon?, color?}}
  → the same shape as GET.
  The avatar may change any time. A typed nickname goes through moderation:
  422 nickname_invalid {reason, message}
      reason: too_short | too_long | bad_chars | contact (4+ digits in a row, "@", a link, an e-mail) |
              blocked (word list) | own_name (contains the learner's real first or last name) | reserved
  409 nickname_taken {suggestions: [..]}
  429 nickname_change_too_soon {can_change_at}     one custom change per 14 days (picking a suggestion counts)
  Length 3..20 characters; letters (Arabic / Latin), digits, space, "_", "-", ".".
```

`icon` ∈ `bolt star rocket moon target crown fire sparkle heart leaf`; `color` ∈ `b y o n p t k g` (the design's
gradient keys).

A learner who never opened the games has no stored nickname yet: boards show a stable stand-in «لاعب ‎#K7Q2M»
(derived from the account, never reversible to it, never a stored nickname: the prefix «لاعب» is reserved).

## Per-game leaderboard

```
GET /api/v1/games/{id}/leaderboard?period=week|all&scope=platform|grade&page=
  → {items: [{rank, nickname, avatar, best_score, stars, duration_s}], me (same row | null), visible,
     period, scope, scope_label: {name_ar, name_en} | null, page, size, total, has_more}
```
- `scope=platform` (default): every active student on the platform (organization members included).
- `scope=grade`: students whose study profile has the caller's grade (`student_study_profiles.grade_id`);
  `scope_label` is that grade («ثاني ثانوي»). 422 `grade_unknown` when the caller has no grade.
- CHANGED: `first_name` is gone; the board is no longer limited to the caller's organization.

## Champions (daily / weekly)

`GET /api/v1/games/champions/standings?scope=&key=&period=` and `GET /api/v1/games/champions` (past) keep their
shape, but
every row's `name` is now the nickname and each row gains `avatar`. Past winners are always shown with their
CURRENT nickname (a stored row's old name is never sent).
- NEW scope `grade` (key = grade id, optional: defaults to the caller's grade; 403 `not_in_scope` for another grade):
  standings, past winners (computed by the same job, daily + weekly, rewards rules with `scope_kind` `grade` or any).
  `scopes` lists `{scope: "grade", key, name_ar, name_en}` when the caller has a grade.
- `org` is unchanged for now (an organization's own champions, when its admin turned them on). Owner to decide.

## Challenges and ghost

- `GET /api/v1/games/challenges/{code}` → `owner` = the owner's nickname (+ `owner_avatar`); `board[]` rows
  `{rank, name (= nickname), avatar, score, max_score, duration_ms, is_me}`.
- `GET /api/v1/games/{id}/ghost` → `ghost.name` = the nickname, + `ghost.avatar`.

## Class board (per-class) — no longer served to students

`GET /api/v1/games/class-board?course_id=` → 403 `class_board_staff_only` for a student. The course's teacher and
platform admins still get it (code path kept; the owner decides later whether to delete it).

## Stickers

Not built: the designs (Stu2Games, Stu2Store) show badges and wardrobe cosmetics, which exist
(`/games/cosmetics`, badges in `/games/v4/home`), and no sticker list.
