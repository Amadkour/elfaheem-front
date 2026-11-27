# Privacy API (backend D-1950)

The server half of the privacy contract (`../DESIGN_SYSTEM.md` §1.2, `../RULES.md` §1.7, `../BACKEND.md` §3).
Backend branch `rd/be-privacy` (worktree `_wt/rd-be-privacy`), no migration, the decision is D-1950 in
`../back/docs/DECISIONS.md`, the short changelog `../back/FLUTTER_API_CHANGES.md` (2026-11-26). Tests:
`../back/tests/redesign/e2e_privacy.py` (student vs teacher view of every item below).

"Learner" = a viewer whose role is not teacher / admin / super-admin / developer / org-admin / org-staff (students,
parents, signed-out visitors). Every changed route keeps its path and shape: a hidden value is `null`, never a renamed
or missing key; new keys are additive. Staff answers are unchanged.

## What the app must do

- **Live room (student / guest):** connect with the token as is. Expect to see only the teacher and on-stage people;
  the local participant is hidden until brought on stage, so do not offer camera / mic until
  `ParticipantPermissionsChanged` gives `canPublish`. Draw the room as `أنت والمعلمة` (no counts). Hand-raise and
  questions call `POST /live/{kind}/{id}/hand` / `ask` (guests: `/public/live/hand` / `ask` with their LiveKit token),
  never the data channel (it is closed for them). Use `private` from the join answer to pick this mode.
- **Live room (host):** the LiveKit participant list no longer shows hidden students; build the roster and the hands
  list from `GET /live/{kind}/{id}/people` (poll or on `nb.hand` / `nb.ask` data messages, topic names below), and use
  `…/participants/{identity}/stage {on}` for "bring on stage" / "take off stage". The guest allow-speak route now means
  the same as stage.
- **Course group chat:** draw it as `إعلانات المعلم`. A learner's composer sends to the group route as before; when the
  answer has `redirected: true`, open / refresh `conversation_id` (the private chat with the teacher). Attachments: send
  them in that private chat (`chat_reply_attachments` otherwise). Hide the member count when `member_count` is null.
- **Counts:** treat `null` as "do not show" for `students_count`, `enrollments_count`, `seats_taken`,
  `waitlist_count`, `page.counts.students`, `top_courses[].students`; packages show `full` instead of seats.
- **Reviews:** show `reviewer_first_name` (the grade is not served yet); `student_id` is null for learners.
- **Pickers:** the calendar people picker and @mention suggestions return no classmates for a learner; an exact
  `@username` still resolves (the "invite by username" flow).

## Contract changes

super-admin / developer / org-admin / org-staff (students, parents, signed-out visitors). Staff answers are unchanged.

Live rooms (LiveKit)
- A student in a course session, a student invited to a meeting a staff member owns, and every guest get a PRIVATE token:
  `hidden: true`, `canPublish: false`, `canPublishData: false`, `canUpdateOwnMetadata: false`, name `طالب` (guests
  `ضيف`), no photo, metadata `{"privacy": "private"}` (guests `{"privacy": "private", "role": "guest"}`). They see and
  hear the host and whoever is on stage; nobody sees them until the host brings them on stage. The course's assistants /
  staff joining as `student_<id>` and the people a STUDENT invited to his own meeting stay visible (O-2).
- `GET /live-sessions/{id}/join` and the meeting joins (`POST /me/calendar/meetings/{id}/join`, the share-link member
  door, the lobby poll) gain `private: bool`. The guest join's `can_publish` is now always false (allow-speak = stage).
- NEW `POST /api/v1/live/{kind}/{id}/participants/{identity}/stage {on}` (host) → `{identity, on_stage}`; on = visible +
  camera / microphone (still no data), off = hidden + nothing; the person's phone follows. 409
  `participant_not_in_room`, 403 `not_host`, 409 `cannot_moderate_host`.
- NEW `GET /api/v1/live/{kind}/{id}/people` (host) → `{kind, id, items: [{identity, user_id, name, image_url, guest,
  companion, host, private, on_stage, hand_raised}], hands}` — hidden people included, real names. The host's room list
  must come from here (hidden participants are not in the LiveKit participant list).
- NEW `POST /api/v1/live/{kind}/{id}/hand {raised}` → `{raised}` and `POST /api/v1/live/{kind}/{id}/ask {text ≤ 500}` →
  `{sent}` (members: enrolled students / invitees; 403 `not_enrolled` / `not_invited`, 429 after 20 a minute). The
  server sends a LiveKit data message to the HOST identities only: topic `nb.hand` `{type: "hand", identity, raised,
  user_id, name}` / `nb.ask` `{type: "ask", identity, text, at, user_id, name}`.
- NEW guest versions `POST /api/v1/public/live/hand {token, raised}` / `POST /api/v1/public/live/ask {token, text}` with
  the guest's own LiveKit token (401 `bad_token`, 403 `participant_removed`; payload `user_id: null, guest: true`).
- `…/permissions`, `mute-all`, the guest mute / mute-all keep a private participant hidden (or on stage) as they are and
  never give back the data channel; `guests/{identity}/allow-speak {allow}` now brings the guest on stage / off stage.
- Chat typing in a course group (`chat_typing`) by a learner reaches the group's staff only.

Payloads
- `students_count`, `enrollments_count` of every course payload CourseService builds (`GET /courses`, `/courses/{id}`,
  `/my-enrolled-courses`, `/my-favorites`, the public profile's courses): null for a learner (type `int | null`); the
  teacher's own lists and write answers keep them.
- Packages (`GET /packages`, `/packages/{id}`, `/me/packages`): `seats_taken`, `waitlist_count` null for a learner
  (the package's teacher and staff keep them); NEW `full: bool` for everyone.
- Ratings lists (`GET /courses|sessions|materials|doctors/{id}/ratings`, the course detail's and session's `rate`, the
  materials list): `student_id` null for a learner / visitor; NEW `reviewer_first_name`.
- Course profile page (`GET /course-profile/{id}` → `page.counts.students`): null for a learner / visitor.
- Public profile (`GET /public/u/{username}`): `stats.top_courses[].students` is null.
- `GET /me/calendar/people` for a learner: staff only, plus a learner whose EXACT `@username` was typed (`q`).
  `GET /me/mentions/suggest?context=meeting` the same (in a staff meeting: the staff only).
- `GET /me/calendar/meetings/{id}` for a student invited to a staff member's meeting: `attendees` = the staff + himself,
  `counts` over those. In a student's own meeting the invitees still see each other.
- The "attendance open" notification no longer says "through a nearby classmate" (O-6).

Course chat
- A course group is the teacher's announcements. For a learner: `GET /chat/conversations/{id}/messages` = the staff's
  messages (+ his own older ones), a quote of a classmate's message comes as `reply_to {…, body: null, sender_id: null,
  sender_name: null, hidden: true}`; `…/members` = the staff only; the thread's `member_count` null; list rows'
  `last_message` / `unread` follow the staff-only view. Thread gains `announce_only: true` and `private_reply: bool`.
- `POST /chat/conversations/{group}/messages` by a learner is delivered to the TEACHER in the course's direct chat
  (created on the first reply): answer `{message, created, redirected: true, conversation_id: <the direct chat>}`;
  with attachments 422 `chat_reply_attachments` (upload them in the direct chat); a teacher's block answers as there.
- Student ↔ student direct chats stay off unless the teacher's / organization's `student_dm` switch is on (unchanged).

## Phase 9 addendum: the public live page

`GET /api/v1/public/live/{token}` now returns `guests_joined: null` for everyone (the page never learns how many guests are in; the host reads the count from the guest-link payload) and a new `full: bool`, true when the guest limit (`max_guests`) is reached. Show "room is full" from `full`; `max_guests` stays for the limit itself.
