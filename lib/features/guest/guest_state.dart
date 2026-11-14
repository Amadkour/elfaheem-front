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
import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/login_screen.dart';
import 'package:flutter_education_app/features/auth/register_screen.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

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
      await showAppModalSheet<void>(
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
                  color: c.blockSky,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: c.divider, width: AppBorder.hairline)),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
                        child: Row(
                          children: [
                            Icon(Icons.explore_rounded, color: c.blockInk, size: AppIconSize.md),
                            const SizedBox(width: AppSpace.xs),
                            Expanded(
                              child: Text(
                                'guest_banner'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.label(context).copyWith(
                                  color: c.blockInk,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpace.xs),
                            AppButton.primary(
                              size: AppButtonSize.sm,
                              icon: DirIcons.login,
                              label: 'login'.tr,
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
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.lg + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpace.md),
            const _GradientIcon(icon: Icons.lock_open_rounded, size: AppTouch.primary + AppSpace.xs),
            const SizedBox(height: AppSpace.md),
            Semantics(
              header: true,
              child: Text('guest_login_required'.tr, textAlign: TextAlign.center, style: AppType.headline(context)),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              reasonKey.tr,
              textAlign: TextAlign.center,
              style: AppType.body(context).copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpace.lg),
            AppButton.primary(
              size: AppButtonSize.lg,
              expand: true,
              icon: DirIcons.login,
              label: 'login'.tr,
              onPressed: () {
                Navigator.of(context).pop();
                GuestGuard.goToLogin();
              },
            ),
            const SizedBox(height: AppSpace.xs),
            AppButton.ghost(
              expand: true,
              label: 'create_account'.tr,
              onPressed: () {
                Navigator.of(context).pop();
                GuestGuard.goToRegister();
              },
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: c.textMedium),
              child: Text('guest_keep_browsing'.tr, style: AppType.label(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientIcon extends StatelessWidget {
  const _GradientIcon({required this.icon, required this.size});

  // (the name stays; the look is the emerald block tint since the editorial theme, D-612)

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone = AppBlockColors.of(context, AppBlockTone.emerald);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tone.surface,
        border: tone.border == null ? null : Border.all(color: tone.border!, width: AppBorder.hairline),
      ),
      child: Icon(icon, color: tone.accentInk(context.colors.primary), size: size * 0.42),
    );
  }
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
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.form.max * 0.7),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GradientIcon(icon: icon, size: AppTouch.primary + AppSpace.lg),
                  const SizedBox(height: AppSpace.md),
                  Semantics(
                    header: true,
                    child: Text('guest_locked_title'.tr, textAlign: TextAlign.center, style: AppType.headline(context)),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    messageKey.tr,
                    textAlign: TextAlign.center,
                    style: AppType.body(context).copyWith(height: 1.5),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  AppButton.primary(
                    icon: DirIcons.login,
                    label: 'login'.tr,
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

  /// A peach block (learning, system.md §5): the invitation in the editorial section role, one line under it, the
  /// ONE emerald action, and the subject's mark on a paper disc — no gradient, no glow.
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: AppBlock(
        tone: AppBlockTone.peach,
        child: Builder(builder: (context) {
          final ink = AppBlock.colorsOf(context);
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('guest_promo_title'.tr, style: AppType.section(context).copyWith(color: ink.ink)),
                    const SizedBox(height: AppSpace.xxs),
                    Text('guest_promo_sub'.tr, style: AppType.label(context).copyWith(color: ink.muted, height: 1.4)),
                    const SizedBox(height: AppSpace.sm),
                    AppButton.primary(size: AppButtonSize.sm, label: 'create_account'.tr, onPressed: GuestGuard.goToRegister),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Container(
                width: AppTouch.primary,
                height: AppTouch.primary,
                decoration: BoxDecoration(color: c.cardBg, shape: BoxShape.circle),
                child: Icon(Icons.school_rounded, color: ink.ink, size: AppIconSize.lg),
              ),
            ],
          );
        }),
      ),
    );
  }
}
