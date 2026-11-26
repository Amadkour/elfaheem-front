# Booking and groups API (redesign, BACKEND.md §4 + the in-person part of §5)

Backend branch `rd/be-booking` (worktree `_wt/rd-be-booking`), migration `0140` (`0140_booking_groups.py`). Design:
`BookFlow.dc.html` (BookM1..M6 / BookW1..W6) and `SubjectProfile.dc.html`. Rules: RULES.md §1 – §3.

## Principles

- **Reuse.** A group IS a teacher package (`packages`, Learning Hub v2) with `booking_kind = "group"`; an
  individual booking IS a one-seat package (`booking_kind = "individual"`). Seats, the waitlist (offer 24 h), the
  30-minute payment hold, the card checkout (`package_payments`: Moyasar / Paymob, the store's checkout shape),
  coupons, the calendar series and the teacher's roster are the existing package machinery. Booking packages never
  show in `GET /packages` (the Learning Hub list).
- **A class (حصة) is 50 minutes**, always (`class_minutes` in every reply; no other length is accepted).
- **Groups are 5 to 10 students and boys-only or girls-only.** The teacher's gender must match the group's: girls'
  groups → a female teacher, boys' groups → a male teacher. Individual bookings follow the same matching
  (student gender = teacher gender).
- **Every instant is UTC ISO-8601 with `Z`** (`2026-12-01T16:30:00Z`). The app shows it in the viewer's zone through
  `AppTime`. Weekly items repeat every 7 days from their instant.
- **No class counts.** No reply carries a number of classes per week or month, `sessions_count`, or a schedule
  count. The price is per month (`price_period: "month"`).
- **Privacy.** Student-facing replies never carry classmates: no names, no seat counts, no waitlist length or
  position. A group's seats are a level: `availability` = `open` (متاح) · `few` (آخر مقاعد) · `full` (مكتمل).
  Staff routes (`/admin/booking/…`, the existing `/packages/{id}/enrollments`) still show counts and rosters.
- Errors: `{"detail": {"code", "message" (ar), "message_en", …extra}}` like the rest of the API.
- Kill switches (super admin, enforced on the server too: 403 `feature_disabled {feature}`):
  `booking` (the whole flow), `booking.in_person` (حضوري), `booking.individual` (فردي),
  `booking.proposals` ("ما فيه وقت يناسبك؟ اقترح أوقاتك").

Mode keys: `remote` (عن بعد) · `in_person` (حضوري). Kind keys: `group` (مجموعة) · `individual` (فردي).
Gender keys: `boys` · `girls` (a group), `male` · `female` (a teacher). Weekday numbers are Python's: Monday 0 …
Sunday 6 (so the Saudi school week Sunday – Thursday is `6, 0, 1, 2, 3`).

## Student side (steps 1 – 6)

Steps 1 – 3 work signed out (optional login; send the token when there is one); `quote` works signed out too.
`confirm`, `me`, `pay`, `cancel` and `notify` need a signed-in **student** (403 `students_only`).

### Step 0 · `GET /api/v1/booking/options?subject_id=&grade_id=&country=&gender=`

Everything steps 1 – 2 need. `gender` (`boys` | `girls`) is only used when signed out or when the profile has none;
`country` likewise (default: the profile's, else `SA`).

```json
{
  "subject": {"id": 12, "name_ar": "الرياضيات", "name_en": "Mathematics"},
  "grade": {"id": 34, "name_ar": "الصف الثاني الثانوي", "name_en": "Grade 11"},
  "class_minutes": 50, "group_size": {"min": 5, "max": 10},
  "gender": "boys",                         // the student's (profile), null = unknown (ask before confirm)
  "currency": "SAR", "price_period": "month",
  "modes": [
    {"key": "remote", "available": true},
    {"key": "in_person", "available": false, "reason": "no_centre_here"}   // reason: no_centre_here | feature_off
  ],
  "kinds": [
    {"key": "group", "available": true, "prices": {"remote": 199, "in_person": 299}},
    {"key": "individual", "available": true, "prices": {"remote": 449, "in_person": 599}}
  ],
  "proposals": true,                        // the "propose your times" link
  "proposal_hours": 24                      // "نثبّت لك الموعد خلال ٢٤ ساعة"
}
```
`in_person` is available only when the student's city (profile `area_id`, or its parent) has an active centre; with
no city on the profile, when the country has one. Hide the option when `available` is false (RULES §3 "Location").
404 `subject_not_found` / `grade_not_found`.

### Step 1 · `GET /api/v1/booking/centres?country=SA`

The "وين موقعك؟" lists: only cities and districts that have an active centre.

```json
{
  "country": "SA",
  "here_city_id": 101,                     // the student's city when it has a centre, else null
  "cities": [
    {"id": 101, "name_ar": "الرياض", "name_en": "Riyadh",
     "districts": [
       {"id": 1011, "name_ar": "النرجس", "name_en": "Al Narjis",
        "centres": [{"id": 3, "name_ar": "فرع النرجس", "name_en": "Al Narjis branch",
                     "address_ar": "طريق الأمير سعود", "address_en": "Prince Saud Rd", "lat": 24.83, "lng": 46.66}]}
     ]}
  ]
}
```
A centre may sit on a city with no district (`district` null): it is listed in a district entry with `id: null`.
The optional "تفاصيل إضافية" text is sent with `quote` / `confirm` as `details` (≤ 500 chars).

### Step 3 (group) · `GET /api/v1/booking/groups?subject_id=&grade_id=&mode=remote|in_person&centre_id=&gender=`

The groups of the subject + grade for the student's gender (`gender` param only when signed out / unknown), mode
and centre (`centre_id` required for `in_person`). Ordered by first class.

```json
{
  "class_minutes": 50, "single": false,      // single = exactly one group (the "هذا موعد المجموعة" screen)
  "items": [
    {"id": 41, "label": "أ", "gender": "boys", "mode": "remote", "centre": null,
     "teacher": {"user_id": 7, "name": "أ. ماجد الشهري", "gender": "male", "avatar_url": null},
     "weekdays": [6, 1],                     // Sunday and Tuesday (Python weekday numbers)
     "times": ["2026-12-06T16:30:00Z", "2026-12-01T16:30:00Z"],   // one weekly instant per weekday
     "starts_at": "2026-12-01T16:30:00Z",    // the first class
     "ends_on": null,
     "availability": "open",                 // open | few | full
     "price": 199, "currency": "SAR", "price_period": "month",
     "mine": null}                            // or {"booking_id", "status"} when the student already booked it
  ]
}
```
A `full` group offers "نبّهني إذا فضى مقعد" (`POST /booking/groups/{id}/notify`).

### Step 3 (individual) · `GET /api/v1/booking/slots?subject_id=&grade_id=&mode=&centre_id=&gender=`

The free weekly slots of teachers of the student's gender (girls → female teachers, boys → male teachers),
grouped by teacher. Each slot's `starts_at` is its NEXT occurrence; it repeats weekly.

```json
{
  "class_minutes": 50,
  "items": [
    {"teacher": {"user_id": 7, "name": "أ. ماجد الشهري", "gender": "male", "avatar_url": null},
     "price": 449, "currency": "SAR", "price_period": "month",
     "slots": [{"id": 90, "starts_at": "2026-11-29T13:00:00Z", "weekly": true}]}
  ]
}
```
The app lets the student pick one slot per day (the design's rule), all from ONE teacher.

### Proposal (individual, no slot fits) — no list call

"وش الأوقات اللي تناسبك؟" sends `proposal` in `quote` / `confirm`:
`{"weekdays": [6, 1], "periods": ["evening"], "tz": "Asia/Riyadh"}` — periods `morning` (٩ – ١٢),
`afternoon` (٣ – ٥), `evening` (٧:٣٠ – ٩), `night` (٩ – ١١), local to `tz`. At least 2 weekdays and 1 period
(the design's rule). The server stores the windows as UTC instants too (`windows`).

### Step 4 · `POST /api/v1/booking/quote` (review, "راجع حجزك")

Body (the same body is sent to `confirm`):
```json
{"subject_id": 12, "grade_id": 34, "mode": "remote", "centre_id": null, "details": null,
 "kind": "group", "group_id": 41}
// individual: "kind": "individual", "slot_ids": [90, 95]     or     "kind": "individual", "proposal": {...}
// signed out / no gender on the profile: "gender": "boys"
```
Reply — the review rows and the money; nothing is held:
```json
{
  "subject": {...}, "grade": {...}, "kind": "group", "mode": "remote", "centre": null, "details": null,
  "teacher": {"user_id": 7, "name": "أ. ماجد الشهري", "gender": "male", "avatar_url": null},  // null for a proposal
  "group": {"id": 41, "label": "أ", "weekdays": [6, 1], "times": [...], "starts_at": "..."},     // group only
  "slots": [{"id": 90, "starts_at": "..."}],                                                     // individual only
  "proposal": {"weekdays": [6, 1], "periods": ["evening"], "tz": "Asia/Riyadh", "windows": [...]},
  "class_minutes": 50,
  "price": 199, "currency": "SAR", "price_period": "month",
  "pay_now": true,                         // false for a proposal (paid once the team fixes the time)
  "providers": ["moyasar"],                // card providers that can take this currency now (may be [])
  "availability": "open"                   // group only
}
```
Errors (quote and confirm): 422 `bad_value {field}`; 404 `group_not_found` / `slot_not_found` /
`centre_not_found`; 409 `gender_required` (no gender anywhere), `gender_mismatch` (a boys' group for a girl, a slot
of a teacher of the other gender), `mode_unavailable` (in-person with no centre / switched off), `slot_taken`,
`slots_mixed_teachers`; 403 `feature_disabled`.

### Step 4 → 5 · `POST /api/v1/booking/confirm` (student) — "أكّد وادفع"

Body: the quote body + `"provider": "moyasar" | "paymob"` (optional) + `"coupon_code"` (optional) + `"gender"`
(saved on the student's study profile when it has none).

```json
{"booking": { ...BookingView... }, "checkout": {"url", "token", "provider", "amount_minor", "is_sandbox"} | null}
```
- **group**: a seat by the package rules → `status` `pending_payment` (+ `checkout`, 30 min hold),
  `active` (price 0) or 409 `group_full` (use `notify`). 409 `already_booked` when the student holds this group.
- **individual with slots**: the slots are taken at once (compare-and-set, 409 `slot_taken` when someone was
  faster), a one-seat package is made for the teacher, and the seat is `pending_payment` + `checkout`. Unpaid after
  30 min the seat expires and the slots are free again.
- **individual with a proposal**: `status` `proposed`, no checkout; the team fixes the time within
  `proposal_hours` (the student is notified), then the student pays with `POST /booking/{id}/pay`.
- `checkout` null + 409 `card_unavailable {providers}` from the package checkout when no card provider takes the
  currency: the booking is then cancelled and nothing is held.

### Step 6 / subject page · `GET /api/v1/booking/me?subject_id=`

The student's bookings (newest first; `subject_id` filters). One **BookingView**:
```json
{
  "id": 501, "kind": "group", "mode": "remote",
  "status": "active",     // proposed | scheduled | pending_payment | active | waitlisted | offered | expired |
                          // cancelled | declined | notify
  "subject": {...}, "grade": {...}, "centre": null, "details": null,
  "teacher": {"user_id": 7, "name": "أ. ماجد الشهري", "gender": "male", "avatar_url": null},
  "group": {"id": 41, "label": "أ", "weekdays": [6, 1], "times": [...], "starts_at": "..."},
  "slots": [], "proposal": null,
  "next_class_at": "2026-12-01T16:30:00Z",   // the next class (null until scheduled / paid)
  "class_minutes": 50,
  "price": 199, "currency": "SAR", "price_period": "month",
  "hold_until": null,                         // pending_payment / offered / scheduled: pay or accept before this;
                                              // proposed: the team fixes the time by then
  "checkout": null,                           // the open checkout of a pending_payment seat
  "created_at": "2026-11-26T09:00:00Z"
}
```
`status` of a group / slot booking mirrors its package seat. `scheduled` = a proposal the team fixed: `slots` now
hold the fixed weekly times and `hold_until` is the deadline to pay.

### `POST /api/v1/booking/{id}/pay {provider?, coupon_code?}` (student)

Opens (or reuses) the checkout of a `scheduled`, `pending_payment` or `offered` booking →
`{"booking": BookingView, "checkout": {...} | null}`. 409 `not_payable`.

### `POST /api/v1/booking/{id}/cancel` (student)

Leaves the seat (the package rules: no automatic refund, the seat is offered to the waitlist) or withdraws a
proposal; taken slots are freed. → `{"booking": BookingView}` with `status: cancelled`. 409 `not_cancellable`.

### Full group · `POST /api/v1/booking/groups/{id}/notify` · `DELETE …/notify` (student)

"نبّهني إذا فضى مقعد": joins the group's waitlist (never charged). When a seat frees, the student is offered it for
24 h (push "تحرر لك مقعد"), then `pay`. 409 `group_not_full` (book it instead). → `{"booking": BookingView}`
with `status: waitlisted` (no position: privacy). DELETE leaves the waitlist.

### Another time · `POST /api/v1/booking/notify-other-time`

"الموعد ما يناسبك؟ نبّهني بموعد ثاني" (the one-group screen): body `{subject_id, grade_id, mode, centre_id?,
gender?}` → `{"booking": BookingView}` with `status: notify` (one per subject + grade + mode; a second call returns
the same row). The team sees it in the requests list.

## Teacher side

`GET /api/v1/booking/teacher/slots` → `{"items": [TeacherSlot]}`;
`POST /api/v1/booking/teacher/slots` `{edu_subject_id, grade_id?, mode, centre_id?, starts_at, weekly: true}` → 201
TeacherSlot; `DELETE /api/v1/booking/teacher/slots/{id}` → `{"ok": true}` (409 `slot_taken` when booked).

`TeacherSlot` = `{id, edu_subject_id, grade_id, mode, centre_id, starts_at (the first instant), next_at,
weekly, minutes: 50, status: open | taken | removed, booking_id, student: {user_id, name} | null}`.
A teacher needs an approved teacher card with a gender (403 `not_approved`, 409 `teacher_gender_unknown`);
`starts_at` in the future (422), no overlap with the teacher's other open / taken slots (409 `slot_overlap`).
The teacher's groups and their rosters are the existing `GET /me/packages` and `GET /packages/{id}/enrollments`.

## Super admin side (platform admins)

- `GET | PUT /api/v1/admin/booking/settings` —
  `{prices: {remote: {group, individual}, in_person: {group, individual}}, currency, few_seats_at,
  proposal_hours, class_minutes: 50 (read-only), group_size: {min: 5, max: 10} (read-only)}`. `currency` defaults to
  the monthly subscription plan's, else SAR.
- Centres: `GET /api/v1/admin/booking/centres?country=` · `POST` · `PUT /{id}` · `DELETE /{id}` (deactivates) —
  `{country_code, city_id, district_id?, name_ar, name_en, address_ar?, address_en?, lat?, lng?, active, sort}`;
  `city_id` / `district_id` are `geo_areas` ids (`GET /edu/areas`), the district must be a child of the city.
- Groups: `GET /api/v1/admin/booking/groups?subject_id=&grade_id=&status=` (staff view: `seats_taken`,
  `waiting`, `below_minimum`) · `POST /api/v1/admin/booking/groups`
  `{teacher_id, edu_subject_id, grade_id, gender, mode, centre_id?, label, max_students (5–10), weekdays,
  start_time "19:30", tz "Asia/Riyadh", start_date, end_date?, price?, title?}` → 201, published (its calendar
  series is made); 409 `teacher_gender_mismatch` / `teacher_gender_unknown`, 403 `not_approved`, 422
  `bad_value {field}`. Status changes (pause / close) are the existing `POST /packages/{id}/status`.
- Requests: `GET /api/v1/admin/booking/requests?status=proposed|notify|scheduled` (with the student) ·
  `POST /api/v1/admin/booking/requests/{id}/schedule {teacher_id, starts_at: [instant, …]}` (fixes a proposal: one
  weekly slot per instant, a one-seat package; the student is notified to pay within `proposal_hours`) ·
  `POST /api/v1/admin/booking/requests/{id}/decline {reason}` (notified).

## Not here (other work packages)

Payment methods per country, VAT lines and the monthly renewal of a booking are the payments package; the
privacy sweep of the existing package / course payloads is the privacy package; country, time zone and curriculum
lists are the international package.
