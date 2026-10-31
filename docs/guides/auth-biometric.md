# MFA and fingerprint / Face ID sign-in

Moved verbatim from the root `CLAUDE.md` (which keeps a short summary and the rules a session must never miss). Keep this file in step with the code.

- Fingerprint / Face ID sign-in (D-082, Android 9+ / iOS, never web, kill switch `auth.biometric`): `lib/features/auth/biometric.dart` (`BiometricAuth.instance`: a device-bound Ed25519 key in `BiometricKeyStore` (token_storage.dart), which a sign-out keeps; `local_auth` with `biometricOnly`; `/auth/biometric/enroll` with the login answer's `biometric_enroll_token` or the password, `/challenge` + `/login`, whose answer is the password login's, MFA step included) and `biometric_widgets.dart` (the login card's quick sign-in, the once-per-account offer `maybeOfferBiometric`); the switch sits in `MfaSettingsEntry`'s Security group. `MainActivity` is a `FlutterFragmentActivity` for it.

The settings entry for every role the server allows is `MfaSettingsEntry` (`lib/features/auth/mfa_entry.dart`, feature key `profile.mfa`). MFA: `lib/features/auth/mfa.dart` (API + code texts), `mfa_verify_screen.dart` (`openMfaStep`, the login step), `lib/features/admin/admin_mfa_page.dart` (enrolment / status).
