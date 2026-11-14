# Track A1 analysis — registration, authentication, authorization (2026-10-28, read-only)

Paths: back = `../back`, front = this repo.

## Flow map

- Register: `POST /auth/register` → `services/auth_service.py:297` (student / teacher / parent, `is_active=False` until verified) · `auth/register_screen.dart`, `auth_provider.dart`.
- Verify: `POST /auth/verify-otp`, `/resend-otp` (`routers/auth.py:142–183`; OTP 6 digits / 10 min / 5 tries, `auth_security.py:122`); link verification `/auth/phone-link/start|status` + Telegram / WhatsApp webhooks (`phone_link_service.py`) · `verified_screen.dart`, `verify_way.dart`.
- Teacher onboarding: `POST /auth/teacher-profile` (+ documents) via `onboarding_user` (`auth_service.py:159`, `X-Onboarding-Token`) · `additional_register_screen.dart`.
- Login: `POST /auth/login` → `_find_for_login` / `_start_session` (`auth_service.py:413–548`; students: `token_version++` and every refresh token revoked = single session); Google `POST /auth/google`; MFA `/auth/mfa/*` · `login_screen.dart`, `google_auth_flow.dart`, `mfa_verify_screen.dart`.
- Refresh: `POST /auth/refresh` → `rotate_refresh_token` (`auth_security.py:188`: opaque, hashed, family reuse detection, CAS, 10 s grace) · `core/api_client.dart:1017–1170` (one de-duplicated refresh, retry once, 4xx → login).
- Logout: `POST /auth/logout` (this family or all) · `profile_provider.dart:219` sends the refresh token; `MyAuthProvider.logout` (`auth_provider.dart:949`) is local only.
- Change / reset password: `PUT /auth/change-password`, `POST /forgot-password` → `/verify-reset-otp` → `PUT /reset-password` (`auth.py:639–693`); both bump `token_version` + revoke refresh tokens · `forget_screen.dart`.
- Delete / export: `DELETE /auth/me` (14-day soft delete, cancelled by login or `POST /me/cancel-deletion`); `/api/v1/me/data-export` (`privacy_router.py`).
- Session check: `get_current_user` (`auth_service.py:67` → `get_user_from_token:666`: token type, strict `token_version`, `is_active`, MFA gate) then `resolve_view_as` (super-admin only, GET/HEAD/OPTIONS, never another super-admin, audited).
- Tokens: HS256, access 60 min, refresh 7 d (`config.py:53–56`); `token_storage.dart` (Keychain / EncryptedSharedPreferences; **web localStorage**); `storage_service.dart` caches the user JSON; `main.dart` `homeRoute` from the cached role.

## Findings (ranked)

| # | sev | where | what | fix |
|---|---|---|---|---|
| S1 | High | `routers/auth.py:709–720` `PUT /auth/me` | `phone` stored raw: no normalize, no uniqueness, `phone_verified` untouched → set a victim's phone (two rows → victim's phone login / OTP / reset fail = lockout), or verify X then swap to unverified Y and stay "verified" | normalize, 409 `PHONE_TAKEN` (as `data_lab_import.account_setup_save:434`), reset `phone_verified` and require an OTP |
| S2 | High | `routers/auth.py:128` `POST /auth/register` | no throttle; each call creates a user and sends e-mail / paid SMS / WhatsApp | per-IP `otp_send`-style throttle + S4 |
| S3 | High | `services/phone_otp_service.py:172,183` | `OTP_PROVIDER` defaults to `log`: with the variable unset every phone OTP (registration and reset) is written to the server log | refuse provider `log` when `APP_ENV` ∉ (development, test), like the `SECRET_KEY` check (`config.py:308`) |
| S4 | Medium | `auth_service.py:322, 745–748` | unverified-account squatting: register victim@x first → victim gets "already registered" and forgot-password refuses ("not active"); only Google frees it | on register re-own an unverified account (replace password, resend OTP), or let forgot / verify run for unverified accounts |
| S5 | Medium | `config.py:77`, `auth_service.py:146–212` | `TEACHER_ONBOARDING_EMAIL_FALLBACK` defaults true: without a token, teacher-profile / documents act on any onboarding teacher found by e-mail (SECURITY_SCAN F2 open) | default false (the app already sends `X-Onboarding-Token`) |
| S6 | Medium | `auth_service.py:871–881` `get_user_by_gmail` | 404 "User not found" in verify-otp, resend-otp, verify-reset-otp, reset-password, phone-link/start and before forgot-password's neutral message → account enumeration | uniform answer, lookup after throttle |
| S7 | Medium | `routers/auth.py:186–202` `/auth/phone-link/start|status` | no auth, no throttle; start adds an OTPCode row per call for anyone; status leaks `pending_channels` / `is_verified` / step for a token | `throttle("otp_send", key=gmail, ip)` |
| S8 | Medium | `token_storage.dart:31–36`, `config.py:55`, `firebase.json` | web keeps the access + 7-day refresh token in localStorage with no CSP on hosting → one XSS = renewable 7-day session | CSP header on hosting, shorter web access TTL, access token in memory on web |
| S9 | Medium | `routers/auth.py:757`, `auth_service.py:809` | `DELETE /auth/me` needs no re-auth and does not revoke refresh tokens (cancel-deletion revives every device); `PUT /auth/me` phone change also without re-auth | re-auth (password / MFA) for both, `revoke_user_tokens` on deletion |
| S10 | Medium | `routers/crypto_handshake.py:25`, `helpers/crypto_session.py:96` | unauthenticated, unthrottled handshake writes a 12 h Redis key per call → Redis exhaustion | per-IP throttle, shorter TTL |
| S11 | Low | `data/schemas.py:44,117,128` | password policy length ≥ 6 only | ≥ 8 + common-password list |
| S12 | Low | `config.py:61` | `MFA_REQUIRED_ROLES` empty by default | default `super-admin,admin` |
| S13 | Low | `subscription_service.py:356`, `device_security_service.py:406`, `orgs_switch.py:63` | guards trust the JWT `role` claim for ≤ 60 min; inert today (no route changes `User.role`) | any future role-change route bumps `token_version` |
| S14 | Low | `auth_provider.dart:854` | `getMe()` has no callers: cached role / flags never refresh after start | call once after bootstrap when online |
| S15 | Low | `auth_provider.dart:949` | `MyAuthProvider.logout` never posts `/auth/logout` → refresh family valid 7 days | post logout with the refresh token |
| S16 | Low | `auth_security.py:57`, `api_client.dart:1163` | login 30 failures / 15 min per IP locks every account behind one NAT; the app treats 429 on `/auth/refresh` as rejected and logs out | raise per-IP, rely on per-(key, ip); treat 429 as `failed` |
| S17 | Low | `storage_service.dart:21` | user JSON in plain SharedPreferences (allowBackup=false) | acceptable; note only |

Verified OK: only 3 routes lack `Depends` (WhatsApp verify challenge, handshake, signed org file links); admin router guarded at router level (`admin_panel.py:97`, `_can_manage`); parent routes use `assert_child`; `X-View-As` as documented; reset / change-password / MFA enable revoke all sessions; `redactForLog` and the backend never log codes.

## Existing tests

back `tests/org_v2`: `spec_auth.py`, `e2e_auth_security.py`, `e2e_auth_sync_routes.py`, `spec_mfa.py`, `e2e_mfa.py`, `e2e_mfa_services.py`, `e2e_privacy_export.py`, `privacy_export_open_and_sweep.py`, `e2e_security_p10.py`, `stub_onboarding_user.py`, `e2e_teacher_doc_delete.py`. front `test/auth/*`, `test/contract/api_paths_test.dart`.

## Open questions

- Production values of `OTP_PROVIDER`, `TEACHER_ONBOARDING_EMAIL_FALLBACK`, `MFA_REQUIRED_ROLES`, `TRUSTED_PROXIES` (`.env.production` not read) — S3 / S5 / S12 hinge on them; the fixes make the safe value the default regardless.
- Whether the reverse proxy adds a per-IP request rate (app has only DB throttles on named routes + a concurrency cap).
- Imported-student temporary passwords (`data_lab_import.py:303`) and the synthetic-login path: expiry not reviewed.
- `/api/v1/devices/*` switch-request approval flow not audited.

## Residual audit 2026-10-28

Scope: the four open questions above plus an IDOR sweep (back branch `feature/platform-polish`, not committed). Tests:
`../back/tests/org_v2/e2e_auth_residual.py` (12 checks; the R1 / R2 / R4 fixes were reverted once each to see their
check fail).

### Findings

| # | sev | where | what | status |
|---|---|---|---|---|
| R1 | High | `routers/sessions.py` `POST /sessions/{sid}/materials/{mid}/play` | the enrollment check ran only for non-"staff"; `is_staff` includes **parent** (self-registrable), org-admin / org-staff and every teacher → a playable link to any paid video by id | fixed: `_may_read_session` for every role (platform admin · course staff via `course_profile.material_reader` · enrolled · free first session) |
| R2 | High | `services/exam_service.py` `get_questions_for_user` (`GET /exams/{id}/questions`) | any teacher / admin token got the whole pool **with correct answers** of any exam | fixed: course teacher (`_assert_course_teacher`) or super admin |
| R3 | High | `services/data_lab_import.py` `reset_login` (`POST /data-lab/courses/{cid}/rows/{rid}/login`) | a course's teacher (or org staff with course `update`) could set a new password on ANY enrolled student — self-registered accounts included — and was handed it: account takeover | fixed: only an import-made account the student has not taken over (placeholder e-mail, or account setup still open), else 409 `SELF_SERVICE_RESET` |
| R4 | Medium | `services/device_security_service.py` `list_for_teacher` / `_owned_pending` | only role `teacher` was scoped to `teacher_id`; parent, org-admin, org-staff, developer listed every pending switch request (student name + phone) and could approve / reject any | fixed: `REVIEW_ALL_ROLES` = admin, super-admin; everyone else only the requests addressed to them; someone else's id → 404 |
| R5 | Medium | `GET /sessions/{sid}/materials`, `GET /modules/{id}/materials` | signed 1 h links to the PDFs / documents of any session or module for any signed-in user | fixed: rows stay as an outline, links (and captions) null for non-readers; the module list answers 403 |
| R6 | Medium | `data_lab_import._new_account` / `reset_login`, login | temporary passwords never expired; "choose your own password" is enforced by the app only (the API works with the temporary password) | fixed: `IMPORT_TEMP_PASSWORD_DAYS` (30) → 403 `TEMP_PASSWORD_EXPIRED`, only after the password matched. A server-side forced change is left to the app (a global guard would 403 the app's start-up calls): residual, accepted |
| R7 | Low | `GET /courses/{id}/enrolled-students` | any teacher passed (names + photos of another course); a `session_id` of another course was mixed in | fixed: `course_profile.resolve` role admin / instructor / ta, or enrolled; a foreign session is ignored |
| R8 | Low | `services/exam_flags_service.py` `add_review_flag` | an enrolled student could flag any pool question id; after submitting, `GET /student/review-flags` returned them with answers (questions never on his paper) | fixed: the question must be on one of his papers when paper rules are active |
| R9 | Low | `PATCH …/governance/entities/{id}`, `POST·PUT …/departments` | `program_id` stored without checking the organization (cross-tenant reference) | fixed: `entities.check_program` → 404 `program_not_found` |
| R10 | Low | `exam_engine/authz.py`, `rag_service/authz.py` whoami cache | a deactivated / signed-out / re-roled account kept engine + RAG access for ≤ 30 s (`AUTHZ_CACHE_SECONDS`) | fixed for whoami: `services/authz_bust.py` deletes the `exam:authz:` / `rag:authz:` whoami keys after the commit (exact keys, no SCAN). Membership / course-role answers keep 30 s, org_state 10 s — documented in `docs/DEPLOY.md` |
| R11 | Info | `deploy/nginx/nextbrain.conf.example` | no per-IP request rate at the proxy (open question 2) | fixed: `nb_auth` 20 r/m burst 30 (login, register, google, OTP, reset, change-password, phone-link/start, MFA verify / confirm, account-setup codes), `nb_session` 60 r/m burst 60 (refresh, link status, handshake), `nb_tunnel` 10 r/s (`/secure/t`); `docs/DEPLOY.md` "Rate limits" |

Verified OK (no change): switch-request replay (the request must be `pending`, 400 afterwards; the student row is locked
and `last_device_switch_at` re-checked); switch-request flooding (one pending row per student, refreshed in place); the
old device after a switch (the student's login on the new phone already bumped `token_version` and revoked every refresh
token, and the approval unbinds the old device from paid content); temporary passwords are 10 chars of `token_urlsafe`
(~60 bits), returned once (the commit answer; the staged import row is deleted) or in the invitation e-mail, never
logged; guessing them falls under the login throttle (10 / 15 min per account + IP, 30 per IP) and now nginx; the
synthetic ID login (`_find_for_login`, `<id>@<DATA_LAB_ID_DOMAIN>`) needs the password, fails like any wrong login, and
is tried before the `login_identifier` policy on purpose (ID-only students).

Residual notes: a pending switch request can be refreshed with another device id until it is decided (the teacher
approves the latest one). The flag keys (`allow_review_flags`, …) had been dropped from `AppSettingsService`, so review
flags answered 403 for everyone; they are real settings again (default on, admin "Flags" page; off answers 403
`review_flags_disabled`), and `e2e_auth_residual.py` no longer patches them.

### IDOR sweep (route → guard → status): 50 routes checked, 11 fixed

| route | guard | status |
|---|---|---|
| `POST /devices/teacher/switch-requests/{id}/approve·reject`, `GET …/switch-requests` | `_owned_pending` / `list_for_teacher` | fixed (R4) |
| `GET /exams/{id}/questions` | none for staff | fixed (R2) |
| `GET /courses/{id}/enrolled-students` | role only | fixed (R7) |
| `POST /sessions/{sid}/materials/{mid}/play` | skipped for staff | fixed (R1) |
| `GET /sessions/{sid}/materials` · `GET /modules/{id}/materials` | none for attachments | fixed (R5) |
| `POST /student/review-flags/{qid}` | enrollment only | fixed (R8) |
| `POST /data-lab/courses/{cid}/rows/{rid}/login` | course staff, any enrolled student | fixed (R3) |
| `PATCH …/governance/entities/{id}` · `PUT …/departments/{id}` (`program_id`) | org-scoped row, body id unchecked | fixed (R9) |
| `GET /exams/{id}/export·results/all·attendance-results`, exam / question CRUD | `_assert_course_teacher` | ok |
| `GET /exams/{id}/paper·results` (student) | active enrollment, own rows | ok |
| `GET /exams/{id}/deadline-status` | none (own counters + the exam's end date only) | ok (low, no other user's data) |
| `GET·PUT /complaints/{id}`, `POST …/replies` | `_assert_access` (`_visibility`) | ok |
| `POST /transfers/{payment_id}/approve·reject` | `_get_reviewable` (course teacher / admin, pending only) | ok |
| `GET /payments/{id}` | `get_payment_for` (owner / admin) | ok |
| `PUT /notifications/{id}/read`, `GET …/{id}/target` | `user_id` filter | ok |
| `GET /live/recordings/{rid}`, `…/chunk·stop·retry`, `GET /live/{kind}/{id}/recordings` | `visible` / `owned` / host or attendee | ok |
| `GET /live/requests/{id}`, `/public/live/requests/{id}`, lobby admit / reject | own `user_id` / secret / `_host` + room-scoped request | ok |
| `GET /live-sessions/{id}/join·recording`, `POST …/end` | enrolled or course teacher / course teacher | ok |
| `GET /live-sessions/{id}/participants·force_attend`, `/sessions/{cid}/course_attendance` | `assert_session_manager` / `assert_course_manager` | ok |
| `GET /courses/{id}/students`, `/certificates/{id}/issuances`, `/sessions/{id}/attendance` | course teacher / admin | ok |
| `POST /certificate-requests/{id}/approve·reject` | `_get_request_for_teacher` | ok |
| `/certificate-designs/{id}…`, `/certificates/{id}/design` | `can_view` / `can_edit` / `_assert_course_access` | ok |
| `GET·PATCH·DELETE /calendar/meetings/{mid}` | `get_visible` / `_own` | ok |
| `GET /parent/children/{sid}/report·profile` | `assert_child` | ok |
| `DELETE /teacher-documents/{id}`, `GET /{teacher_id}/public` | the caller's profile / public filter | ok |
| `GET /attendance/sessions/{att_id}/code`, `POST …/close` | `_owned_attendance` | ok |
| `GET /data-lab/courses/{cid}/students/{sid}/profile`, `/data-lab/students/{sid}/profile` | `_course` + enrolled / the teacher's courses | ok |
| `POST /messages/dialogs/{rid}/seen`, `GET /teacher/courses/{cid}/read-flags`, `DELETE /materials/{id}` | own row / course teacher / owner | ok |
| org sample (10): `GET /org/public/announcements/{aid}`, `PUT …/{aid}/reaction`, `GET /orgs/{o}/announcements/{aid}/analytics`, `PUT·DELETE …/reports/templates/{tid}`, `PUT …/governance/categories/{cid}`, `PUT·DELETE …/periods/{pid}`, `GET …/departments/{id}`, `GET·PUT …/registrar/terms/{tid}/grades/{cid}` | `_visible` / audience; rows filtered by `org_id = ctx.org.id` + `org_ctx(module, action)` / `_require(dept)` / `_manages`; registrations of the org's term | ok |

Contract notes for the app: `../back/FLUTTER_API_CHANGES.md` "Auth residual audit" (new codes `TEMP_PASSWORD_EXPIRED`,
`SELF_SERVICE_RESET`; 404 on someone else's switch request; null links for non-readers). App follow-up: show the
server's `message` for `TEMP_PASSWORD_EXPIRED` / `SELF_SERVICE_RESET` (it is user-readable); no other app change needed.
