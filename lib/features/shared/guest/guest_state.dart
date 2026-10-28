// lib/utils/widget/guest_state.dart   (NEW)
//
// Student "guest mode": browse the catalogue without an account, strictly read-only.
//
//  • GuestState      – singleton flag (same pattern as ViewAsState).
//  • GuestGuard      – ONE place that blocks every action needing an identity and
//                      opens the "log in to continue" sheet. Call it from UI buttons
//                      and from ApiClient (401 / any non-GET while guest).
//  • GuestBanner     – top header over EVERY screen while guest (wrap the app in main.dart's
//                      `builder`, exactly like ViewAsBanner). Has a Login button.
//  • GuestGate       – wraps a tab/screen that has no meaning for a guest (my courses,
//                      schedule, analytics, profile) and shows a locked placeholder.
//  • GuestPromoCard  – replaces the "upcoming session" card on the guest home.
//
// The SERVER stays the source of truth: a guest sends no token, so every write endpoint
// (get_current_user) answers 401 by itself. Guest mode never needs a "write" permission.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../auth/auth_provider.dart';
import '../../auth/login_screen.dart';
import '../../auth/register_screen.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class GuestState extends ChangeNotifier {
  GuestState._();
  static final GuestState instance = GuestState._();

  bool _active = false;

  /// Read by ApiClient / providers.
  static bool get active => instance._active;

  void start() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  void stop() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }
}

/// Enters guest mode and lands on the student shell. ONE entry point (login screen button).
void startGuest(NavigatorState nav) {
  GuestState.instance.start();
  nav.pushNamedAndRemoveUntil('/dashboard', (r) => false);
}

// ─────────────────────────────────────────────────────────────────────────────
// Guard
// ─────────────────────────────────────────────────────────────────────────────

class GuestGuard {
  GuestGuard._();

  /// `true` → the caller may continue. `false` → guest: the login sheet is already shown.
  static bool ensure(
    BuildContext context, {
    String reasonKey = 'guest_reason_generic',
  }) {
    if (!GuestState.active) return true;
    _showSheet(context, reasonKey);
    return false;
  }

  /// `onPressed: () => GuestGuard.run(context, doThing)`.
  /// Returns Future<void> so it fits both VoidCallback and Future<void> Function().
  static Future<void> run(
    BuildContext context,
    FutureOr<void> Function() action, {
    String reasonKey = 'guest_reason_generic',
  }) async {
    if (!ensure(context, reasonKey: reasonKey)) return;
    await action();
  }

  /// For code with no BuildContext (ApiClient interceptor on 401 / blocked write).
  static void promptLogin({String reasonKey = 'guest_reason_generic'}) {
    final ctx = _rootNavigator()?.overlay?.context;
    if (ctx != null && GuestState.active) _showSheet(ctx, reasonKey);
  }

  /// Leaves guest mode and opens the real login screen.
  static void goToLogin() => _leaveTo(const LoginScreen(), '/login');

  static void goToRegister() => _leaveTo(const RegisterScreen(), '/register');

  static void _leaveTo(Widget page, String name) {
    GuestState.instance.stop();
    _rootNavigator()?.pushAndRemoveUntil(
      MaterialPageRoute(settings: RouteSettings(name: name), builder: (_) => page),
      (route) => false,
    );
  }

  static bool _sheetOpen = false;

  static Future<void> _showSheet(BuildContext context, String reasonKey) async {
    if (_sheetOpen) return; // several taps / parallel 401s → one sheet
    _sheetOpen = true;
    try {
      await showModalBottomSheet<void>(
      useSafeArea: true,
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _GuestLoginSheet(reasonKey: reasonKey),
      );
    } finally {
      _sheetOpen = false;
    }
  }

  /// The app's root Navigator (the banner lives ABOVE it, so it has no Navigator context).
  static NavigatorState? _rootNavigator() {
    NavigatorState? nav;
    void visit(Element e) {
      if (nav != null) return;
      if (e is StatefulElement && e.state is NavigatorState) {
        nav = e.state as NavigatorState;
        return;
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return nav;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Banner (top header)
// ─────────────────────────────────────────────────────────────────────────────

class GuestBanner extends StatelessWidget {
  const GuestBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A real login (from the banner / sheet) ends guest mode by itself.
    final signedIn = context.select<MyAuthProvider, bool>((a) => a.isAuthenticated);
    if (signedIn && GuestState.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => GuestState.instance.stop());
    }

    return ListenableBuilder(
      listenable: GuestState.instance,
      builder: (_, _) {
        final active = GuestState.active;
        final c = context.colors;
        return Column(
          children: [
            if (active)
              Directionality(
                textDirection:
                    AppConfig.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(gradient: c.primaryGradient),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.explore_rounded, color: c.onHero, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'guest_banner'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.onHero,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: AppFonts.family,
                                  decoration: TextDecoration.none,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: c.onHero,
                                foregroundColor: c.primary,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              icon: const Icon(DirIcons.login, size: 18),
                              label: Text(
                                'login'.tr,
                                style: TextStyle(
                                  fontFamily: AppFonts.family,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                              onPressed: GuestGuard.goToLogin,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Keyed so the Navigator keeps its state when the banner appears / disappears.
            // The banner already covers the status bar → the page below drops that padding.
            Expanded(
              key: const ValueKey('app_content_guest'),
              child: MediaQuery.removePadding(
                context: context,
                removeTop: active,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Login sheet
// ─────────────────────────────────────────────────────────────────────────────

class _GuestLoginSheet extends StatelessWidget {
  const _GuestLoginSheet({required this.reasonKey});

  final String reasonKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: c.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 22),
            _GradientIcon(icon: Icons.lock_open_rounded, size: 64),
            const SizedBox(height: 16),
            Text(
              'guest_login_required'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: c.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              reasonKey.tr,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: AppFonts.family, fontSize: 14, height: 1.5, color: c.textLight),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(DirIcons.login),
                label: Text(
                  'login'.tr,
                  style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  GuestGuard.goToLogin();
                },
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                GuestGuard.goToRegister();
              },
              child: Text(
                'create_account'.tr,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontWeight: FontWeight.w700,
                  color: c.primary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'guest_keep_browsing'.tr,
                style: TextStyle(fontFamily: AppFonts.family, color: c.textLight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientIcon extends StatelessWidget {
  const _GradientIcon({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: context.colors.primaryGradient,
      boxShadow: [
        BoxShadow(
          color: context.colors.primary.withValues(alpha: 0.35),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Icon(icon, color: context.colors.onHero, size: size * 0.46),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Locked tab
// ─────────────────────────────────────────────────────────────────────────────

/// Shows [child] normally; for a guest shows a locked placeholder INSTEAD (the child is not
/// even built, so none of its providers fire authenticated requests).
class GuestGate extends StatelessWidget {
  const GuestGate({
    super.key,
    required this.child,
    required this.icon,
    required this.messageKey,
  });

  final Widget child;
  final IconData icon;
  final String messageKey;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: GuestState.instance,
    builder: (_, _) =>
        GuestState.active ? _GuestLocked(icon: icon, messageKey: messageKey) : child,
  );
}

class _GuestLocked extends StatelessWidget {
  const _GuestLocked({required this.icon, required this.messageKey});

  final IconData icon;
  final String messageKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GradientIcon(icon: icon, size: 84),
                  const SizedBox(height: 20),
                  Text(
                    'guest_locked_title'.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: c.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    messageKey.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      fontSize: 14,
                      height: 1.5,
                      color: c.textLight,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.primary,
                      minimumSize: const Size(200, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(DirIcons.login),
                    label: Text(
                      'login'.tr,
                      style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800),
                    ),
                    onPressed: GuestGuard.goToLogin,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home promo card (replaces the "upcoming session" banner for guests)
// ─────────────────────────────────────────────────────────────────────────────

class GuestPromoCard extends StatelessWidget {
  const GuestPromoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: c.primaryGradient,
          borderRadius: BorderRadius.circular(c.radiusXL),
          boxShadow: [
            BoxShadow(
              color: c.primary.withValues(alpha: 0.38),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'guest_promo_title'.tr,
                    style: TextStyle(
                      color: c.onHero,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      fontFamily: AppFonts.display,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'guest_promo_sub'.tr,
                    style: TextStyle(
                      color: c.onHero.withValues(alpha: 0.85),
                      fontSize: 12.5,
                      height: 1.4,
                      fontFamily: AppFonts.family,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.onHero,
                      foregroundColor: c.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: GuestGuard.goToRegister,
                    child: Text(
                      'create_account'.tr,
                      style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: c.onHero.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.school_rounded, color: c.onHero, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}
