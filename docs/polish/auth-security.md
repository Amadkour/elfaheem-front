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
