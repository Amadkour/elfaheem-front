# API: the student's notebook, دفتر المادة (WP10)

Backend branch `rd/be-games`. Migration `0151_student_notebook`. Kill switch `course.notebook` (403
`feature_disabled`). Test `tests/redesign/e2e_games_notebook.py`.

A page belongs to ONE user (any role may keep one; the design shows it for students). Nobody else can read it, not
the teacher, not an admin through these routes, unless the owner shares that page with the course's teacher.
Another user's page id answers 404 `note_not_found` (never 403: no existence leak).

## Page

```
{id, client_id, subject_id | null, course_id | null, lesson_id | null, title, kind: "typed" | "ink" | "mixed",
 blocks: [{t, x}] (typed), ink: {w, h, s: [[tool, color, width, [x0, y0, dx1, dy1, ...]], ...]} | null,
 shared: bool, version, created_at, updated_at, deleted: bool}
```
- A page needs `subject_id` (an `edu_subjects` id) or `course_id` (a course the caller is enrolled in or teaches, else 403 `course_forbidden`)
  or both; `lesson_id` (a lesson = a session id of that course) needs `course_id` (422 `note_invalid` otherwise). `subject_id` defaults to the course's subject.
- `blocks[].t` ∈ `h` (heading) · `p` (paragraph) · `li` (bullet) · `hl` (highlighted) · `eq` (equation, plain text) ·
  `sticky` (the coloured sticky note); `x` is plain text. ≤ 400 blocks, ≤ 20 000 characters in all.
- `ink`: `w`, `h` = the canvas size the points refer to (1..4096). Each stroke = `[tool, color, width, points]`:
  tool `pen` | `hl` (highlighter; the eraser removes strokes on the device, only what is left is saved), color
  `#RRGGBB`, width 1..64, points = integers, the first pair absolute and the rest DELTAS from the previous point,
  each in -32768..32767, an even count ≥ 2. ≤ 3 000 strokes, ≤ 120 000 numbers, ≤ 512 KB as JSON.
  422 `note_too_large {limit}` / `note_invalid {field}` otherwise.
- `title` ≤ 120 characters (may be empty).
- ≤ 2 000 live pages per user: 422 `notebook_full`.

## Routes (prefix `/api/v1/me/notebook`)

```
GET    /summary                              → {items: [{subject_id, course_id, pages, updated_at}]}  one GROUP BY
GET    /pages?subject_id=&course_id=&lesson_id=&since=&full=&limit=&before=&before_id=
        → {items: [page], server_time, has_more}
        Newest first (updated_at desc, id desc), limit ≤ 100 (default 50); next page = `before` (the last item's
        `updated_at`) + `before_id` (its id). Without `full=true` the items carry no
        `blocks` / `ink` (a `preview` of the first 140 typed characters and `strokes` = the stroke count instead).
        `since` (ISO, naive UTC) = sync: every page changed after it, deleted ones INCLUDED (`deleted: true`, no
        content); without `since` deleted pages are left out.
GET    /pages/{id}                           → page (full)
POST   /pages {client_id, subject_id?, course_id?, lesson_id?, title?, kind, blocks?, ink?}
        → 201 page. Idempotent on (user, client_id): the same client_id again answers 200 with the stored page
        (nothing changes). `client_id` = 8..64 characters [A-Za-z0-9_-] (a UUID from the device).
PUT    /pages/{id} {base_version, title?, kind?, blocks?, ink?, lesson_id?}
        → page with version + 1. 409 note_stale {page} when base_version is not the stored version (the device
        merges and sends again). A deleted page answers 404.
DELETE /pages/{id}                           → {deleted: true}   a tombstone kept for sync (content wiped)
POST   /pages/{id}/share {shared: bool}      → page   the course's teacher may read it; needs course_id
                                                      (422 note_needs_course)
```

## Teacher side (only what a student shared)

```
GET /api/v1/teacher/courses/{course_id}/notebook/shared?limit=&before_id=
  → {items: [page + student: {id, name}], has_more}    the course's teacher or a platform admin; else 403
     course_forbidden. Only pages whose owner is enrolled in that course and shared them.
```

Not built: a picture from the board inside a typed page ("صورة من السبورة") needs a file upload; open point.
