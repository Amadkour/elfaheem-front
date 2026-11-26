# API: student private meetings and the subject's assistant (WP11, owner decision O-2)

Backend branch `rd/be-games`. No migration. Test `tests/redesign/e2e_games_notebook.py`.

## Private meetings a student hosts

The student types who to invite (design: «مين تبي تدعي؟ اسم المستخدم أو الجوال…», «يوصلهم طلب، وتشوف مين قبل»).
The server never suggests anyone to a student.

```
POST /api/v1/me/calendar/meetings  {..., mode: "online", audience: {usernames: ["sultan.m", "@x"], phones: ["0553214478"]}}
POST /api/v1/me/calendar/busy      the same audience shape
```
- NEW `audience.usernames` (≤ 20, with or without "@") and `audience.phones` (≤ 20, any local or international
  form; the server normalises it). Resolved on the server to active accounts.
- A student may now invite with `usernames` / `phones` ONLY (still online only). `user_ids`, `dept_ids`,
  `head_dept_ids`, `course_ids` from a student → 422 `student_meeting_online_private` as before. Staff may use
  `usernames` / `phones` too; for them the organization reach rule still applies (403 `not_reachable`).
- 422 `invitee_not_found {kind: "username" | "phone", value}` for a value that matches no active account (the value
  is the one the caller typed). Failed lookups are throttled: 429 `too_many_attempts` after 20 misses an hour.
- The typed values are NEVER stored or echoed: the meeting's `audience` keeps only `{"typed": n}`.
- Students are never told who is busy: for a student caller `/busy` answers `{busy: [], count: 0, invitees: n}` and
  create / move never answer 409 `attendees_busy`.

```
GET /api/v1/me/calendar/people   → for a student: {people: [], departments: [], courses: [], typed_only: true}
```

`GET /api/v1/me/calendar/meetings/{id}` for a viewer who is neither the owner nor the acting host, when the viewer or
the owner is a student: `attendees` holds only the viewer's own row, `counts` is null and `audience` is `{}` (an
invitee never sees who else was invited). The owner keeps the full list with each invitee's answer (name + picture,
never a phone or username).

Not changed: recurring series (`/series`) still refuse a student's audience.

## The subject's assistant (Bot)

The assistant itself is the existing RAG chat: `POST /api/v1/rag/ask {question, course_id, org_id?}` already scopes
the answer to that course's library. NEW: one call that tells the app whether the subject page may show it, and
which scope to send.

```
GET /api/v1/me/assistant/subject?course_id=   (or ?subject_id= : the caller's newest active course of that subject)
  → {state: "on" | "locked",
     reason: null | "feature_off" | "not_subscribed" | "not_enrolled",
     message_ar, message_en,              (null when on; e.g. «المساعد مقفل في هالمادة الحين. نعلمك أول ما يشتغل.»)
     scope: {course_id, org_id, subject_id} | null,
     title_ar, title_en}                  (the course title, for «مساعدك في …»)
```
- `feature_off`: the super admin (or the organization) switched off `rag.assistant` or the new key
  `rag.subject_bot`.
- `not_subscribed`: the platform paywall is on and the student has no active subscription, or the course
  enrolment expired.
- `not_enrolled`: no active enrolment in that course (or, with `subject_id`, in any course of that subject). The
  course's teacher and platform admins are always `on`.
- 404 `course_not_found` for an unknown course id.

The suggestion chips («أعطني مثال ثاني», «اختبرني بسؤال», «لخّص لي الدرس») are fixed app strings.

## Stickers

Not built: no sticker list in the designs (badges and cosmetics already exist).
