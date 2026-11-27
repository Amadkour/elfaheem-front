# Admin governance API (owner decisions 2026-11-27)

Backend: `features/admin_gov/` (back), migrations 0180 (audit log), 0181 (roles), 0182 (course review columns),
test `tests/redesign/e2e_admin_governance.py`. Front: `lib/features/admin/governance/`.

Kill switches (app side, they hide the pages; the routes stay reachable and the log keeps recording):
`admin.publish_queue`, `admin.audit_log`, `admin.roles`.

Errors are the coded shape `{detail: {code, message, message_en}}`.

## 1. Course publish review

Platform setting `platform.publish_review` (app_settings), **default off** = today's behaviour: a teacher's publish
goes live at once.

On: `POST /api/v1/courses/{id}/publish` by a teacher, on a **personal** course (an organization course follows its
organization; an admin's own publish is never queued), answers the course with `is_published: false` and
`review_status: "pending_review"`. A second send: 409 `already_pending`. `POST …/unpublish` withdraws a waiting course
(`review_status: null`).

Every `CourseResponse` / `TeacherCourseResponse` carries:

| field | values |
|---|---|
| `review_status` | `null` (never reviewed) · `pending_review` · `approved` · `rejected` |
| `review_reason` | the reviewer's reason when `rejected`, else `null` |

The teacher's card shows "Under review" (and "Withdraw from review" in its menu) or "Not approved" with the reason;
publishing again after a rejection sends it back to the queue.

Routes (permission `courses.review`, §3; a super admin always has it):

- `GET /api/v1/admin/publish-queue?status=pending_review|approved|rejected&page=1&size=20` →
  `{items: [{course_id, name_ar, name_en, image_url, fees, currency, teacher: {id, name}|null, review_status,
  review_reason, submitted_at, decided_at, decided_by, is_published}], total, page, size, has_more, require_review}`.
  Waiting courses oldest first; decided ones newest first. 422 `bad_status`.
- `POST /api/v1/admin/publish-queue/{course_id}/approve` → the item (`is_published: true`).
- `POST /api/v1/admin/publish-queue/{course_id}/reject` `{reason}` (3–500 characters) → the item. 422
  `reason_required`.
- Both: 404 `course_not_found`, 409 `not_pending` (already decided: compare-and-set, the first reviewer wins).
- `GET /api/v1/admin/publish-queue/settings` (any admin) → `{require_review, pending}`;
  `PUT` `{require_review: bool}` super admin only (403 `super_admin_only`, 422 `bad_require_review`).

Notifications (`notify_user`, push data `{type: "course_review", id, status}`) and the live event
**`course_review`** `{course_id, status}`: to the reviewers (admins holding `courses.review`) on a submission, to the
teacher on a decision. The queue page and the teacher's course list reload on the event; the approvals inbox lists
waiting courses as the kind "Course to publish".

## 2. Admin audit log

Recorded by ONE middleware (`AdminAuditMiddleware`, inside the encryption middleware): every POST / PUT / PATCH /
DELETE that passed `require_admin` / `require_super_admin` / an admin permission, plus any write under
`/api/v1/admin/` by a signed-in admin. Refused writes are recorded too (`status_code`). Reads are not.

A row keeps: actor (id, name and role snapshots), method, route template, action (the route's own name, e.g.
`publish_queue.approve`, else `"PUT /admin/x/{id}"`), target (type + id, from the path), status, IP (trusted
`client_ip`), user agent, request id, a summary (≤ 500) and `changes`: the JSON body's top-level fields, scalars cut
to 80 characters, objects / lists as their size, and every secret-looking field (password, token, secret, otp, pin,
key, card, iban, signature, …) as `"***"`. Upload bodies are never read.

- `GET /api/v1/admin/audit-log?actor_id=&action=&q=&date_from=&date_to=&ok=&page=1&size=50` (permission
  `audit.view`) → `{items: [{id, at, actor: {id, name, role}, method, path, action, target: {type, id}|null,
  status_code, ok, ip, user_agent, request_id, summary, changes}], total, page, size, has_more}`, newest first.
  `action` and `q` match part of the text; `date_from` / `date_to` are ISO instants or bare days (a bare `date_to`
  includes the whole day, UTC). 422 `bad_date`.
- `GET /api/v1/admin/audit-log/facets` → `{actors: [{id, name, count}], actions: [{action, count}]}` (the filters'
  choices, at most 200 each).

## 3. Admin roles and permissions

- A super admin has every permission, always, and is the only one who edits roles (403 `super_admin_only`).
- An admin has the built-in `admin` role (every permission) unless given a custom role, which then gives exactly its
  set.
- Built-in roles `super_admin` and `admin` are listed but locked: 409 `builtin_role` on edit or delete. Deleting a
  custom role sends its admins back to `admin`.
- Every admin route group maps to a permission and ONE app-wide dependency enforces it (§3.4). The publish queue
  and the audit log also keep their own `admin_perm("…")`.

Permission catalog (groups, 32 keys; labels come from the server in both languages): courses (`courses.review`,
`courses.manage`, `categories.manage`, `certificates.manage`, `exams.policy`) · people (`users.manage`,
`accounts.approve`, `devices.manage`, `students.manage`, `teachers.manage`, `parents.manage`) · money
(`finance.view`, `payments.review`, `payouts.manage`, `fees.manage`, `markets.manage`, `booking.manage`,
`store.manage`) · content (`content.manage`, `ads.manage`, `help.manage`, `landing.manage`, `learning.manage`,
`broadcast.send`) · platform (`settings.manage`, `features.manage`, `orgs.manage`, `ai.manage`, `releases.manage`,
`data.manage`, `demand.view`) · oversight (`audit.view`). `roles.manage` is the super admin's alone.

- `GET /api/v1/admin/roles` → `{roles: [{id, key, name_ar, name_en, builtin, permissions, admins_count}], catalog:
  [{id, title_ar, title_en, items: [{key, title_ar, title_en}]}], admins: [{id, name, role, role_id, is_active}]}`.
- `POST /api/v1/admin/roles` `{name_ar, name_en, permissions: [key]}` → 201 the role (`key: "custom_<id>"`).
- `PUT /api/v1/admin/roles/{id}` (any of the three fields) → the role. `DELETE /api/v1/admin/roles/{id}` →
  `{deleted: true, admins_moved}`.
- 422 `bad_name` (2–120 characters), `bad_permissions`, `unknown_permission`; 404 `role_not_found`.
- `PUT /api/v1/admin/roles/assignments/{user_id}` `{role_id | null}` (null or the built-in admin role = no custom
  role) → `{user_id, role_id, permissions}`. 404 `admin_not_found` (not an admin), 409 `super_admin_fixed`.
- `GET /api/v1/admin/roles/me` (any admin) → `{role: {id, key, name_ar, name_en, builtin}, permissions,
  can_edit_roles}`.

### 3.4 Custom roles gate the admin area (rd/ow-roles)

- `ADMIN_ROUTE_RULES` (back `features/admin_gov/admin_rbac.py`) maps each admin route group to one permission; the
  first match wins. `admin_area_guard`, an app-wide FastAPI dependency in `main.py`, refuses ONLY an admin holding a
  custom role that lacks it: 403 `{code: "permission_denied", message, message_en, permission}`. A super admin and a
  plain admin (built-in role, no assignment) pass exactly as before; non-admins fall through to the route's own check.
- Map (under `/api/v1/admin/` unless noted): `users`, `usernames`, `admins` → `users.manage` (but `users/{id}/devices`
  · `reset-devices` → `devices.manage`, `users/{id}/approve|reject` → `accounts.approve`, `users/{id}/enroll…` ·
  `courses…` · `subscription…` → `students.manage`; the list `GET /admin/users?role=student|teacher` also accepts
  `students.manage` / `teachers.manage`) · `accounts`, `required-documents`, `requirements` → `accounts.approve` ·
  `teachers` → `teachers.manage` (`teachers/{id}/earnings` → `payouts.manage`) · `course-students`, `subscriptions`,
  `study-profile` → `students.manage` · `parent-link` → `parents.manage` · `publish-queue` → `courses.review` ·
  `courses`, `course-trash`, `recommendations`, `packages` → `courses.manage` · `categories` → `categories.manage` ·
  `certificates` → `certificates.manage` · `exam-policy`, `grades` → `exams.policy` · `finance`,
  `overview/income-breakdown` → `finance.view` · `payouts`, `withdrawals` → `payouts.manage` · `payments/catalog|
  currency-rates|vat-rules` → `markets.manage` · other `payments`, `payment-methods` and `/api/v1/payments/transfers/…`
  · refunds · verify → `payments.review` · `fees`, `points`, `subscription-plans` → `fees.manage` · `booking` →
  `booking.manage` · `store` → `store.manage` · `teacher-demand` → `demand.view` · `ads` → `ads.manage` · `help`,
  `features/guide` → `help.manage` · `content`, `legal`, writes on `/api/v1/app-content/about|terms` →
  `content.manage` · `landing` → `landing.manage` · `edu`, `games`, `nahw`, `quran`, `self-learning`, `rewards`,
  `badges` → `learning.manage` · `messages`, `chat` → `broadcast.send` · `features`, writes on
  `/api/v1/disable-items` → `features.manage` · `settings`, `platform-settings`, `live-settings`, `module-settings`,
  `themes`, writes on `/api/v1/theme` → `settings.manage` · `orgs` → `orgs.manage` · `ai-controls` → `ai.manage` ·
  `app-releases`, writes on `/app/…` → `releases.manage` · `data-lab`, `/api/v1/datacenter`, `/admin/excel`,
  `/admin/seed` → `data.manage` · `audit-log` → `audit.view`.
- Open to every admin: `/admin/me`, `/admin/profile`, `/admin/overview`, `/admin/search`, `/admin/lookup`,
  `/admin/roles/me`. The RAG console and the model hub run in their own services and are not gated there yet: the app
  hides them by `ai.manage`.
- The caller's effective set: `GET /api/v1/admin/roles/me` → `permissions` (and `role.builtin`), and
  `GET /api/v1/auth/me` → `admin_permissions` (null for a non-admin).
- App: `AdminPerms.instance` (`lib/features/admin/governance/admin_perms.dart`) reads `/admin/roles/me` once when the
  admin home opens; only a custom role (`builtin: false`) limits anything. Each More-hub service carries `perm`
  (`AdminService.perm`, filtered in `visibleServices`); the Students / Courses / Teachers tabs need
  `users.manage|students.manage` / `courses.manage` / `users.manage|teachers.manage`; a hub tab with no allowed
  service is hidden. The roles editor draws the server catalog, so every key above is listed, grouped, in both
  languages.
- e2e: back `tests/redesign/e2e_admin_role_scope.py`.
