# Networking (`ApiClient`)

Moved verbatim from the root `CLAUDE.md` (which keeps a short summary and the rules a session must never miss). Keep this file in step with the code.

**Networking (`lib/core/api_client.dart`)** — `ApiClient` is a singleton (`ApiClient()` returns `ApiClient.instance`) on Dio, with `get/post/put/patch/delete/postForm/postMultipart`. Things it does for every request:
- Throws only `ApiException` (`message` is safe to show to the user; `code` holds server codes such as `DEVICE_MISMATCH`, `VIEW_LIMIT_REACHED`). In UI: `ApiException.from(e).message`.
- Refreshes tokens and redirects to login on 401. Tokens live in `lib/core/token_storage.dart` (secure storage on mobile, SharedPreferences on web); `POST /auth/refresh` sends the refresh token in the body and returns a NEW pair, which is stored (rotation: an old token is dead after one use). `StorageService` keeps only the cached user and UI preferences.
- App-layer envelope encryption (X25519 → HKDF → AES-256-GCM, `{"n","ct"}` bodies) and public-key pinning on mobile (`lib/core/cert_pin.dart`, D-946): the server key's SPKI SHA-256, plus Let's Encrypt intermediates as a signature-checked backup. Renew the server certificate with `certbot renew --reuse-key`; a new key needs a new app build first.
- Sends device-ID headers (device binding / blocked-device dialog lives in `features/courses/student/security/`).
- Adds `X-View-As: <id>` while super-admin "view as" mode is active (`utils/widget/view_as_state.dart`).
- Adds `X-Onboarding-Token` to teacher onboarding routes (`isTeacherOnboardingPath`; token kept in memory by `lib/features/auth/teacher_onboarding_token.dart`), and opens `AdminMfaPage` on 403 `mfa_enrollment_required` (`shouldOpenMfaEnrollment`: never two at once, again only 30 s after the user left it). Debug request logs go through `redactForLog`: add any new secret field to `logSensitiveKeys`. MFA files: `docs/guides/auth-biometric.md`. Every method takes an optional `headers:`.
- Fingerprint / Face ID sign-in (D-082, never web, kill switch `auth.biometric`): `lib/features/auth/biometric.dart` + `biometric_widgets.dart`; details in the same guide.
- Maps 503 `server_busy` (the Exam Engine / RAG in-flight cap) to `ApiMessages.serverBusyAr/En`; coded errors outside org screens get bilingual text in `lib/core/api_error_text.dart` (`apiErrorText`).

Cleartext is refused on devices except `127.0.0.1` / `localhost` (the offline-video loopback server) and `10.0.2.2` (emulator → local stack): `android/app/src/main/res/xml/network_security_config.xml` and iOS `NSAllowsLocalNetworking` (D-010). Every server, media and LiveKit URL must be https / wss.
