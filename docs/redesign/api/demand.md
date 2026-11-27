# API: teacher demand numbers on the landing page (BACKEND.md §2; backend WP9)

Backend branch `rd/be-money`, migration `0162`. Design: `LandingW.dc.html` → "أنا معلم" → a subject → "شوف الطلب
على مادتك". Aggregates only: no name, id or row of a person ever leaves the server.

## 1. The card

### `GET /api/v1/public/teacher-demand?subject=<key>&country=XX&curriculum=XX`

(The same answer is also served at `/api/v1/public/landing/teacher-demand`.)

Public, no sign-in (the same answer signed in), rate limited with the other landing routes (super admin's
`landing.rate_limit`, 429 `rate_limited` + `Retry-After`), cached 300 s in the process and sent with
`Cache-Control: public, max-age=300`.

- `subject` (required): a subject key or id, `^[a-z0-9_]{1,40}$` (the catalog's `edu_subjects.key`, e.g. `math`, or a
  Learning Hub subject such as `quran`). 422 otherwise.
- `country`: the teacher's country of residence filter (ISO-2) — students living there. Absent = every country.
- `curriculum`: the curriculum country (ISO-2) — students following that curriculum. Absent = every curriculum.

```json
{
  "available": true,
  "subject": "math", "country": "SA", "curriculum": "SA",
  "as_of": "2026-11-26", "computed_at": "2026-11-26T02:10:00", "updated_at": "2026-11-26T02:10:00",
  "waiting_students": 120,
  "booked_classes_30d": 600,
  "groups_waiting": null,
  "rounded": true,
  "note_ar": "الأرقام من حجوزات المنصة الفعلية، وتتحدّث كل يوم.",
  "note_en": "Numbers come from real bookings on the platform and update daily."
}
```

- `updated_at` (= `computed_at`): when the snapshot was computed.
- `waiting_students`: students on the teacher waiting list for the subject (open requests, §3).
- `booked_classes_30d`: classes booked (paid seats in a teacher's offer) in the 30 days before the snapshot.
- `groups_waiting`: new groups waiting for a teacher: open requests grouped by (subject, curriculum, grade, gender,
  mode); each bucket counts `floor(waiting / group_min)` groups (`group_min` default 5).
- Each number is `null` when it is below the threshold (default 5) and otherwise rounded DOWN (to 5 under 100, to
  10 under 1 000, to 50 above). `null` = hide that line; the app never fills it in.
- When no number can be produced the answer is still HTTP 200:
  `{"available": false, "reason": "feature_off" | "no_snapshot" | "stale" | "below_threshold", "subject": …}`;
  the landing then removes the card. `stale` = the newest snapshot is older than `stale_days` (default 2).
  `below_threshold` = every number is hidden.
- Kill switch `landing.teacher_demand` (off on the web platform → `feature_off`).

## 2. How the numbers are made

A snapshot job (`teacher_demand_tick`, hourly, works once per UTC day: the day's snapshot rows are the claim)
writes raw counts into `teacher_demand_snapshots` (day, subject, country, curriculum; `*` = all). The threshold and
rounding apply on read, so an admin change takes effect at once and raw small counts never leave the server. Other
features (group booking) add their own counts through `demand_service.register_source(fn)` instead of a second job.

Super admin:
- `GET /api/v1/admin/teacher-demand/settings` → `{"threshold": 5, "group_min": 5, "stale_days": 2, "last_day":
  "2026-11-26"}`; `PUT` with any of the three numbers (1–100, 1–50, 1–30; 422 `demand_settings_invalid`).
- `POST /api/v1/admin/teacher-demand/recompute` → recomputes today's snapshot now → `{"day", "rows"}`.

## 3. The student's waiting list

`POST /api/v1/me/teacher-waitlist` (student) body `{"subject": "math", "grade_id"?: 12, "curriculum"?: "SA",
"gender"?: "boys" | "girls", "mode"?: "remote" | "in_person"}` → 201 `{"id", "subject", "status": "waiting",
"created_at", "created": true}`. Idempotent: an open request for the same subject + curriculum + grade answers
200 with `created: false`. `curriculum` defaults to the study profile's curriculum country; the residence country is
read from the account. 403 for non-students, 422 `subject_invalid`.

`GET /api/v1/me/teacher-waitlist` → `{"items": [...]}` (own open requests only).
`DELETE /api/v1/me/teacher-waitlist/{id}` → 204 (own only, 404 otherwise). A request leaves the list when the
student cancels it or is booked with a teacher for that subject (`matched`).

Kill switch `teacher_waitlist`.
