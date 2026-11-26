# API: the parent creates the child's account; the child signs in with a code (BACKEND.md §1; backend WP7)

Backend branch `rd/be-intl`, migration `0131`. Design: `Pa2Gate.dc.html?screen=done&kid=new`,
`Stu1Auth.dc.html?screen=login` ("عندك كود من ولي أمرك؟"), `Stu1Auth.dc.html?screen=kidcode` (`state=found`,
`state=pass`).

Both directions work and share one link table (`parent_student_links`) and one code table (`parent_link_codes`,
new column `purpose`):
- **link** (existing, unchanged): a student makes an 8-character code, a parent redeems it
  (`POST /student/parent-link/code`, `POST /parent/link/redeem`).
- **child_login** (new): the parent creates the student account; the server makes a 6-digit code the child signs in
  with once.

Kill switches: `parent.create_child` (the parent's "add a child" and its codes) and `auth.child_code` (the child's
"I have a code from my parent"). Off on every platform → 403 `feature_disabled` on the routes below.

## Parent side (signed in, role parent)

During sign-up the app keeps the child's details and sends them right after the parent's verification step answers
(the parent has a session then); after sign-up the same route adds more children.

### `POST /api/v1/parent/children` → 201

```json
{"first_name": "سارة", "last_name": "أحمد", "curriculum_country_code": "SA", "stage_id": 12, "grade_id": 40,
 "track": null, "delivery": "online", "gender": "f", "dob": "2014-05-01"}
```

- `first_name` required (1-60), `last_name` optional (0-60).
- The grade: `stage_id` + `grade_id` of `GET /edu/catalog?country=<curriculum_country_code>` (the same checks as the
  study profile: 422 `study_stage_required`, `study_grade_required`, `edu_grade_mismatch`, `study_track_invalid`).
  `curriculum_country_code` defaults to the parent's residence when it has a catalog, else the platform default.
- `delivery` = the study mode: `online` · `in_person` · null (either). `gender` `m` · `f` · null.
- Limits: 5 children a day per parent (429 `child_create_limit`).

The server creates a student account (no e-mail, no phone, an unusable password, a generated `@username`), its study
profile, an active link to this parent (consent recorded: the parent created it) and the first login code.

```json
{
  "child": {"id": 381, "name": "سارة أحمد", "first_name": "سارة", "last_name": "أحمد", "username": "sara.ahmed",
            "stage_id": 12, "grade_id": 40, "grade_name_ar": "الصف الرابع الابتدائي", "grade_name_en": "Grade 4",
            "created_by_me": true, "claimed": false},
  "login_code": {"code": "482917", "code_display": "482 917", "expires_at": "2026-11-28T09:00:00Z",
                 "ttl_seconds": 172800,
                 "share_text_ar": "…", "share_text_en": "…"}
}
```

`code` is shown ONCE (only a keyed hash is stored). `share_text_*` is ready for a WhatsApp share (the app opens
`https://wa.me/?text=<urlencoded>`): the child's first name, the code, how long it lasts, and where to enter it.

### `POST /api/v1/parent/children/{child_id}/login-code` → 201

A new code (`login_code` object above); the previous unused one stops working. Only for a child THIS parent created
(403 `child_not_created_by_you`; 404 `LINK_NOT_FOUND` when not linked). A child who already set a password can be
given a new code too (forgotten password): claiming it sets a new password and signs the old sessions out.
10 codes an hour per child (429 `CODE_RATE_LIMIT`).

### `GET /api/v1/parent/children/{child_id}/login-code`

`{"active": true, "expires_at": "…Z", "seconds_left": 170000}` or `{"active": false}` (never the code).

### `GET /api/v1/parent/children` (existing)

Each child gains `created_by_me` (bool) and `claimed` (bool: the child has set a password; always true for a linked
existing student).

## Child side (no account yet; no sign-in, past the paywall / device guards)

### `POST /api/v1/auth/child-code/lookup` `{"code": "482 917"}`

Spaces, dashes and Arabic-Indic digits are accepted. Answers ONLY what the "هذا حسابك؟" card needs:

```json
{"first_name": "سارة", "last_name": "أحمد", "grade_name_ar": "الصف الرابع الابتدائي", "grade_name_en": "Grade 4",
 "parent_name": "أحمد محمد"}
```

### `POST /api/v1/auth/child-code/claim` `{"code": "482917", "password": "…", "username": "sara.a"}`

Consumes the code (single use, compare-and-set), sets the password (`WEAK_PASSWORD` policy), optionally changes the
generated username (`USERNAME_*` codes as on sign-up), and answers exactly like `POST /auth/login`
(`access_token`, `refresh_token`, `user`, `device`, `account_setup`, …). Later sign-ins use the username (shown in
`user.username`) and that password.

### Throttles and lockout (both routes)

- Wrong codes: 10 per IP and 10 per device (`X-Device-Id`) in 15 minutes → 429 `too_many_attempts`
  (`retry_after_minutes`, `Retry-After`).
- Per code: a code that was looked up 10 times is burnt (the parent makes a new one).
- A code lives 48 hours, works once, and a new code revokes the old one.

## Errors

| HTTP | code | when |
|---|---|---|
| 400 | `child_code_invalid` | unknown, expired, used, revoked or burnt code (one answer for all) |
| 429 | `too_many_attempts` | the throttles above |
| 403 | `feature_disabled` | `parent.create_child` / `auth.child_code` off |
| 403 | `ROLE_PARENT_ONLY` | the parent routes, another role |
| 403 | `child_not_created_by_you` | a new code for a child the parent only linked |
| 422 | `child_name_required` | no first name |
| 429 | `child_create_limit` / `CODE_RATE_LIMIT` | the daily / hourly limits |

Each error carries `message` (Arabic) and `message_en`.
