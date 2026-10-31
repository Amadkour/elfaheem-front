# Boot splash

Moved verbatim from the root `CLAUDE.md` (which keeps a short summary and the rules a session must never miss). Keep this file in step with the code.

The splash itself is `lib/design/boot_splash.dart` (`BootSplash`, `SplashHandOff`): frame 1 matches the native splash, then the mark floats and tilts in 3D, the tagline from `AppIdentity` appears, and the footer the super admin set ("Powered by …" line + small logo, `splash_footer_*` / `splash_logo_url` on the identity endpoint, edited on the admin Content page, logo bytes cached) shows at the bottom, a greeting with the cached user's first name and a status line driven by `SplashState.instance` (`_safe` reports each step; `SplashPacing` remembers the device's usual boot time to pace the bar); test `test/ui/boot_splash_layout_test.dart`.
