// ─────────────────────────────────────────────────────────────────────────────
// features/auth/google_auth_flow.dart
//
// "Join / Continue with Google":
//   • GoogleAuthSection  – drop-in block (button + "or" divider) for login/register
//   • continueWithGoogle – the whole flow (Google popup → role sheet → account → login)
//   • showGoogleRoleSheet – the premium role-selection bottom sheet
//
// Register screen : role sheet first, then Google, then the server creates the account.
// Login screen    : Google first; the role sheet only appears if the e-mail is new.
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../utils/helpers.dart';
import '../../design/app_notice.dart';
import '../../utils/widget/parent_component.dart';
import '../../utils/widget/primary_button.dart';
import 'auth_provider.dart';
import 'biometric_widgets.dart' show maybeOfferBiometric;
import 'username.dart';
import 'username_field.dart';
import 'mfa_verify_screen.dart';
import 'auth_widgets.dart';
import '../../design/app_blocks.dart';
import '../../design/app_charts.dart' show appInk;
import '../../design/app_motion_kit.dart' show AppEase, AppPressScale;
import '../../design/app_tokens.dart';
import 'verified_screen.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

// ── Text helper ───────────────────────────────────────────────────────────────
// Uses your translation key when it exists, otherwise the built-in en/ar text,
// so everything works before the keys are added.
bool get _isAr => AppConfig.lang.toLowerCase().startsWith('ar');

String _t(String key, String en, String ar) {
  final v = key.tr;
  return v == key ? (_isAr ? ar : en) : v;
}

// ══════════════════════════════════════════════════════════════════════════════
//  Flow
// ══════════════════════════════════════════════════════════════════════════════

/// What the user picked in the role sheet.
class GoogleRoleChoice {
  final String role; // student | teacher | parent
  final String? phone;

  /// The optional @username for the new account (normalized; null = none).
  final String? username;

  const GoogleRoleChoice({required this.role, this.phone, this.username});
}

const _cancelCodes = {
  'canceled',
  'cancelled',
  'popup-closed-by-user',
  'cancelled-popup-request',
  'web-context-canceled',
  'web-context-cancelled',
  'user-cancelled',
};

/// Opens the Google account chooser and returns a Firebase ID token (null = user backed out).
Future<String?> _googleIdToken() async {
  final provider = GoogleAuthProvider()
    ..addScope('email')
    ..addScope('profile')
    ..setCustomParameters({'prompt': 'select_account'});
  try {
    final cred = kIsWeb
        ? await FirebaseAuth.instance.signInWithPopup(provider)
        : await FirebaseAuth.instance.signInWithProvider(provider);
    return await cred.user?.getIdToken();
  } on FirebaseAuthException catch (e) {
    debugPrint('Google sign-in: ${e.code} | ${e.message}');
    if (_cancelCodes.contains(e.code)) return null; // closed / went back: not an error
    rethrow;
  }
}

/// Loading state of ONE Google button. Every [GoogleAuthSection] owns its own, so the
/// login and register buttons never share a spinner.
class GoogleFlowController {
  final ValueNotifier<bool> busy = ValueNotifier(false);

  /// True while the Google window is open and we are waiting for the user.
  bool inWindow = false;

  int _epoch = 0;

  /// Gives up on the running flow (user came back without finishing): the button is
  /// usable again and a late answer from Google is ignored.
  void cancel() {
    _epoch++;
    inWindow = false;
    busy.value = false;
  }
}

/// [askRoleFirst] = true on the register screen (sheet → Google). On the login screen it
/// is false: an existing account just signs in, a new e-mail gets the sheet afterwards.
///
/// [flow] is the button's own loading state. Pass the same controller the button listens to.
///
/// [teacherStepBuilder]: the screen a teacher must finish (profile + documents) before using
/// the app. When null, everyone goes to their dashboard.
Future<void> continueWithGoogle(
    BuildContext context, {
      bool askRoleFirst = false,
      WidgetBuilder? teacherStepBuilder,
      GoogleFlowController? flow,
    }) async {
  final fc = flow ?? GoogleFlowController();
  if (fc.busy.value) return;

  final auth = context.read<MyAuthProvider>();
  final nav = Navigator.of(context);
  final myEpoch = ++fc._epoch;
  bool stale() => myEpoch != fc._epoch;

  if (!auth.policyLoaded) await auth.loadPolicy();
  if (!context.mounted || stale()) return;

  GoogleRoleChoice? choice;
  if (askRoleFirst) {
    choice = await showGoogleRoleSheet(context, needPhone: false);
    if (choice == null || !context.mounted || stale()) return; // sheet dismissed
  }

  fc.busy.value = true;
  try {
    fc.inWindow = true;
    final idToken = await _googleIdToken();
    fc.inWindow = false;
    if (idToken == null || stale()) return; // closed the window, or gave up earlier

    var result = await auth.googleAuth(
      idToken: idToken,
      role: choice?.role,
      phone: choice?.phone,
      username: choice?.username,
    );

    // Brand-new e-mail on the login screen: ask for the role, then finish.
    if (result == GoogleAuthResult.roleRequired) {
      if (!context.mounted || stale()) return;
      fc.busy.value = false; // no spinner while the sheet is open
      choice = await showGoogleRoleSheet(
        context,
        needPhone: false,
        name: auth.googleName,
        email: auth.googleEmail,
      );
      if (choice == null || !context.mounted || stale()) return; // dismissed
      fc.busy.value = true;
      result = await auth.googleAuth(
        idToken: idToken,
        role: choice.role,
        phone: choice.phone,
        username: choice.username,
      );
    }

    // The new account's @username was refused (taken / reserved / invalid) before anything was created: the sheet
    // comes back with the error and the server's suggestions on the field, then the same Google token is reused.
    for (var tries = 0;
        tries < 3 && result == GoogleAuthResult.failed && auth.usernameError != null && choice != null;
        tries++) {
      if (!context.mounted || stale()) return;
      fc.busy.value = false;
      final again = await showGoogleRoleSheet(
        context,
        needPhone: false,
        name: auth.googleName,
        email: auth.googleEmail,
        initial: choice,
        usernameError: auth.usernameError,
      );
      if (again == null || !context.mounted || stale()) return; // dismissed
      choice = again;
      fc.busy.value = true;
      result = await auth.googleAuth(
        idToken: idToken,
        role: again.role,
        phone: again.phone,
        username: again.username,
      );
    }
    if (!context.mounted || stale()) return;

    switch (result) {
      case GoogleAuthResult.success:
        auth.loadCachedUser();
        if (choice != null) {
          Helpers.showMessage(
            _t(
              'google_welcome',
              'Welcome aboard! Your account is ready.',
              'أهلاً بك! تم إنشاء حسابك بنجاح',
            ),
            isError: false,
          );
        }
        final user = auth.currentUser;
        final step = user?.registrationStep;
        final teacherOwesStep =
            user?.role == 'teacher' &&
                (step == 'pending_profile' || step == 'pending_documents');
        // an existing account signing in: offer fingerprint sign-in once (D-082); a new account settles in first
        if (choice == null && !teacherOwesStep) {
          fc.busy.value = false;
          await maybeOfferBiometric(context, auth);
          if (!context.mounted || stale()) return;
        }
        if (teacherOwesStep && teacherStepBuilder != null) {
          nav.pushAndRemoveUntil(
            MaterialPageRoute(builder: teacherStepBuilder),
                (_) => false,
          );
        } else {
          nav.pushNamedAndRemoveUntil(auth.homeRoute, (_) => false);
        }
        break;

      case GoogleAuthResult.mfa:
        await openMfaStep(nav, auth);
        break;

      case GoogleAuthResult.needsVerification:
      // Same screen the password login uses for an unverified account.
        Helpers.showMessage('account_not_verified'.tr, isError: false);
        nav.push(
          MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
              email: auth.pendingGmail ?? auth.googleEmail ?? '',
              channels: auth.pendingChannels,
              phoneNumber: auth.pendingPhoneMasked,
              role: auth.pendingRole ?? choice?.role ?? 'student',
              flow: OtpFlowEnum.registration,
            ),
          ),
        );
        break;

      case GoogleAuthResult.roleRequired:
      case GoogleAuthResult.failed:
        Helpers.showMessage(
          auth.errorMessage ??
              _t(
                'google_failed',
                'Google sign-in failed, please try again',
                'تعذّر تسجيل الدخول بجوجل، حاول مرة أخرى',
              ),
          isError: true,
        );
        break;
    }
  } on FirebaseAuthException catch (e) {
    if (!stale()) {
      Helpers.showMessage(
        '${e.message ?? _t('google_failed', 'Google sign-in failed, please try again', 'تعذّر تسجيل الدخول بجوجل، حاول مرة أخرى')} (${e.code})',
        isError: true,
      );
    }
  } catch (e) {
    debugPrint('Google sign-in failed: $e');
    if (!stale()) {
      Helpers.showMessage(
        _t(
          'google_failed',
          'Google sign-in failed, please try again',
          'تعذّر تسجيل الدخول بجوجل، حاول مرة أخرى',
        ),
        isError: true,
      );
    }
  } finally {
    // Always stop this button's spinner (unless a newer attempt already owns it).
    if (!stale()) {
      fc.inWindow = false;
      fc.busy.value = false;
    }
    // The app keeps its own JWT session; the Firebase one is not needed afterwards.
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Drop-in section for login / register
// ══════════════════════════════════════════════════════════════════════════════

/// [joining] = true  → premium "join in one tap" card (register screen), then an
///                      "or fill in the form" divider.
/// [joining] = false → "or continue with" divider, a circular icon button and a short
///                      trust line (login).
/// The admin can hide it with the feature key `google_auth` (same disableList as guest_mode).
/// Each instance has its own loading state.
class GoogleAuthSection extends StatefulWidget {
  const GoogleAuthSection({
    super.key,
    required this.joining,
    this.smallIcon=false,
    this.teacherStepBuilder,
  });

  final bool joining;
  final bool smallIcon;
  final WidgetBuilder? teacherStepBuilder;

  @override
  State<GoogleAuthSection> createState() => _GoogleAuthSectionState();
}

class _GoogleAuthSectionState extends State<GoogleAuthSection>
    with WidgetsBindingObserver {
  final _flow = GoogleFlowController();
  Timer? _grace;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _grace?.cancel();
    _flow.cancel(); // a late answer from Google must not touch a closed screen
    super.dispose();
  }

  /// Mobile: the user closed the Google browser tab with "back" and returned to the app.
  /// If Google has not answered shortly after coming back, stop the spinner.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb || state != AppLifecycleState.resumed) return;
    if (!_flow.inWindow || !_flow.busy.value) return;
    _grace?.cancel();
    _grace = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && _flow.inWindow && _flow.busy.value) _flow.cancel();
    });
  }

  void _start() => continueWithGoogle(
    context,
    askRoleFirst: widget.joining,
    teacherStepBuilder: widget.teacherStepBuilder,
    flow: _flow,
  );

  @override
  Widget build(BuildContext context) {
    if (AppConfig.disableList.contains('google_auth')) {
      return const SizedBox.shrink();
    }
    final c = context.colors;

    if (!widget.smallIcon) {
      return _Entrance(
        index: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _flow.busy,
              builder: (_, busy, __) => _JoinCard(
                button: GoogleAuthButton(
                  label: _t('join_with_google', 'Join with Google',
                      'الانضمام عبر جوجل'),
                  loading: busy,
                  onPressed: _start,
                ),
              ),
            ),
            const SizedBox(height: 22),
            AuthOrDivider(
              label: _t('or_fill_form', 'or fill in the form',
                  'أو املأ البيانات يدوياً'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    }

    return _Entrance(
      index: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthOrDivider(
            label: _t('or_continue_with', 'or continue with', 'أو تابع باستخدام'),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<bool>(
            valueListenable: _flow.busy,
            builder: (_, busy, __) => GoogleAuthButton(
              label: _t('continue_with_google_btn', 'Continue with Google',
                  'المتابعة عبر جوجل'),
              loading: busy,
              onPressed: _start,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_outlined, size: 14, color: c.success),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _t(
                    'google_login_hint',
                    'Fast and secure. We never see your password.',
                    'سريع وآمن. لا نطّلع على كلمة المرور أبداً.',
                  ),
                  textAlign: TextAlign.center,
                  style: AppType.meta(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Register-screen lead: a sky block (information, system.md §5) with "the fastest way" heading, the Google button and
/// three short facts — vector checks in the success ink, no capsules.
class _JoinCard extends StatelessWidget {
  const _JoinCard({required this.button});

  final Widget button;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppBlock(
      tone: AppBlockTone.sky,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Builder(builder: (context) {
        final ink = AppBlock.colorsOf(context);
        Widget fact(IconData icon, String text) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: AppIconSize.sm, color: ink.accentInk(c.success)),
                const SizedBox(width: AppSpace.xxs),
                Flexible(child: Text(text, style: AppType.meta(context).copyWith(color: ink.ink, fontWeight: FontWeight.w500))),
              ],
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: AppTouch.min - AppSpace.xxs,
                  height: AppTouch.min - AppSpace.xxs,
                  decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.controlAll),
                  child: Icon(Icons.bolt_rounded, color: ink.ink, size: AppIconSize.lg),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('google_join_title', 'Join in one tap', 'انضم بضغطة واحدة'),
                        style: AppType.section(context).copyWith(color: ink.ink),
                      ),
                      Text(
                        _t('google_join_sub', 'The fastest way to create your account', 'أسرع طريقة لإنشاء حسابك'),
                        style: AppType.meta(context).copyWith(color: ink.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            button,
            const SizedBox(height: AppSpace.sm),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpace.md,
              runSpacing: AppSpace.xs,
              children: [
                fact(Icons.verified_rounded, _t('google_chip_verified', 'Verified e-mail', 'بريد موثّق')),
                fact(Icons.key_off_rounded, _t('google_chip_nopass', 'No password', 'بدون كلمة مرور')),
                fact(Icons.touch_app_rounded, _t('google_chip_role', 'Pick your role', 'اختر دورك')),
              ],
            ),
          ],
        );
      }),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Google button
// ══════════════════════════════════════════════════════════════════════════════

/// "Continue with Google" in the kit's secondary language (system.md §3a): paper, an ink hairline, radius 14, 48
/// high, the G mark at the start and the label centred in ink. The emerald stays on the form's one primary action;
/// no rainbow ring, no light sweep. A press sinks it to 0.97.
class GoogleAuthButton extends StatefulWidget {
  const GoogleAuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;

  @override
  State<GoogleAuthButton> createState() => _GoogleAuthButtonState();
}

class _GoogleAuthButtonState extends State<GoogleAuthButton> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hairline = Color.lerp(c.divider, c.textDark, _down ? 0.6 : 0.35)!;
    final fill = _down
        ? Color.lerp(c.cardBg, c.textDark, 0.06)!
        : _hover
            ? Color.lerp(c.cardBg, c.textDark, 0.03)!
            : c.cardBg;
    return Semantics(
      button: true,
      enabled: !widget.loading,
      label: widget.label,
      excludeSemantics: true,
      child: AppPressScale(
        scale: 0.97,
        enabled: !widget.loading,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.controlAll,
            side: BorderSide(color: hairline, width: AppBorder.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.loading ? null : widget.onPressed,
            onHighlightChanged: (v) => setState(() => _down = v),
            onHover: (v) => setState(() => _hover = v),
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            child: SizedBox(
              height: AppTouch.min + AppSpace.xxs,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: widget.loading
                    ? Center(
                        child: SizedBox(
                          width: AppIconSize.md,
                          height: AppIconSize.md,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: appInk(context, c.primary)),
                        ),
                      )
                    : Row(
                        children: [
                          const _GoogleG(size: AppIconSize.md),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                              child: Text(
                                widget.label,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.bodyStrong(context).copyWith(fontSize: 15, height: 1.2),
                              ),
                            ),
                          ),
                          // balances the mark so the label is truly centred
                          const SizedBox(width: AppIconSize.md),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon-only Google button: the same paper and hairline as [GoogleAuthButton] on a circle, with a tooltip and a
/// screen-reader label.
class GoogleCircleButton extends StatefulWidget {
  const GoogleCircleButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.loading = false,
    this.size = 58,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final bool loading;
  final double size;

  @override
  State<GoogleCircleButton> createState() => _GoogleCircleButtonState();
}

class _GoogleCircleButtonState extends State<GoogleCircleButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: AnimatedScale(
          scale: _down ? 0.94 : 1,
          duration: AppMotion.of(context).fast,
          curve: AppEase.out,
          child: Material(
            color: c.cardBg,
            shape: CircleBorder(side: BorderSide(color: Color.lerp(c.divider, c.textDark, 0.35)!, width: AppBorder.hairline)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.loading ? null : widget.onPressed,
              onHighlightChanged: (v) => setState(() => _down = v),
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: AppMotion.of(context).base,
                    child: widget.loading
                        ? SizedBox(
                            key: const ValueKey('busy'),
                            width: AppIconSize.lg,
                            height: AppIconSize.lg,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: appInk(context, c.primary)),
                          )
                        : _GoogleG(key: const ValueKey('g'), size: widget.size * 0.42),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The official Google "G" (vector paths from the brand mark), drawn in code, no asset.
class _GoogleG extends StatelessWidget {
  const _GoogleG({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const _GoogleGPainter());
}

class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 48; // the mark is designed on a 48 × 48 grid
    Path p;
    // blue
    p = Path();
    p.moveTo(45.12*k,24.5*k);
    p.cubicTo(45.12*k,22.94*k,44.98*k,21.44*k,44.72*k,20*k);
    p.lineTo(24*k,20*k);
    p.lineTo(24*k,28.51*k);
    p.lineTo(35.84*k,28.51*k);
    p.cubicTo(35.33*k,31.26*k,33.78*k,33.59*k,31.45*k,35.15*k);
    p.lineTo(31.45*k,40.67*k);
    p.lineTo(38.56*k,40.67*k);
    p.cubicTo(42.72*k,36.84*k,45.12*k,31.2*k,45.12*k,24.5*k);
    p.close();
    canvas.drawPath(p, Paint()..color = _blue..isAntiAlias = true);
    // green
    p = Path();
    p.moveTo(24*k,46*k);
    p.cubicTo(29.94*k,46*k,34.92*k,44.03*k,38.56*k,40.67*k);
    p.lineTo(31.45*k,35.15*k);
    p.cubicTo(29.48*k,36.47*k,26.96*k,37.25*k,24*k,37.25*k);
    p.cubicTo(18.27*k,37.25*k,13.42*k,33.38*k,11.69*k,28.18*k);
    p.lineTo(4.34*k,28.18*k);
    p.lineTo(4.34*k,33.88*k);
    p.cubicTo(7.96*k,41.07*k,15.4*k,46*k,24*k,46*k);
    p.close();
    canvas.drawPath(p, Paint()..color = _green..isAntiAlias = true);
    // yellow
    p = Path();
    p.moveTo(11.69*k,28.18*k);
    p.cubicTo(11.25*k,26.86*k,11*k,25.45*k,11*k,24*k);
    p.cubicTo(11*k,22.55*k,11.25*k,21.14*k,11.69*k,19.82*k);
    p.lineTo(11.69*k,14.12*k);
    p.lineTo(4.34*k,14.12*k);
    p.cubicTo(2.85*k,17.09*k,2*k,20.45*k,2*k,24*k);
    p.cubicTo(2*k,27.55*k,2.85*k,30.91*k,4.34*k,33.88*k);
    p.lineTo(11.69*k,28.18*k);
    p.close();
    canvas.drawPath(p, Paint()..color = _yellow..isAntiAlias = true);
    // red
    p = Path();
    p.moveTo(24*k,10.75*k);
    p.cubicTo(27.23*k,10.75*k,30.13*k,11.86*k,32.41*k,14.04*k);
    p.lineTo(38.72*k,7.73*k);
    p.cubicTo(34.91*k,4.18*k,29.93*k,2*k,24*k,2*k);
    p.cubicTo(15.4*k,2*k,7.96*k,6.93*k,4.34*k,14.12*k);
    p.lineTo(11.69*k,19.82*k);
    p.cubicTo(13.42*k,14.62*k,18.27*k,10.75*k,24*k,10.75*k);
    p.close();
    canvas.drawPath(p, Paint()..color = _red..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════════════
//  Role sheet
// ══════════════════════════════════════════════════════════════════════════════

/// Shows the role sheet. Returns null when dismissed.
/// [name]/[email] are shown as "you are joining as …" when Google already told us who it is.
///
/// [initial] / [usernameError]: the sheet comes back after the server refused the new account's @username.
Future<GoogleRoleChoice?> showGoogleRoleSheet(
    BuildContext context, {
      bool needPhone = false,
      String? name,
      String? email,
      GoogleRoleChoice? initial,
      UsernameError? usernameError,
    }) {
  return showAppSideSheet<GoogleRoleChoice>(
    context,
    withCloseBar: true,
    builder: (_) => _GoogleRoleSheet(
      roles: context.read<MyAuthProvider>().roles
          .map((r) => r['text']!)
          .toList(growable: false),
      needPhone: needPhone,
      name: name,
      email: email,
      initial: initial,
      usernameError: usernameError,
    ),
  );
}

class _RoleMeta {
  const _RoleMeta(this.icon, this.en, this.ar);

  final IconData icon;
  final String en;
  final String ar;
}

const _roleMeta = {
  'student': _RoleMeta(
    Icons.school_rounded,
    'Join live sessions, courses and exams',
    'احضر الحصص المباشرة والكورسات والاختبارات',
  ),
  'teacher': _RoleMeta(
    Icons.cast_for_education_rounded,
    'Teach, publish courses and grow your audience',
    'درّس وانشر كورساتك وابنِ جمهورك',
  ),
  'parent': _RoleMeta(
    Icons.family_restroom_rounded,
    "Follow your children's progress and reports",
    'تابع تقدّم أبنائك وتقاريرهم',
  ),
};

class _GoogleRoleSheet extends StatefulWidget {
  const _GoogleRoleSheet({
    required this.roles,
    required this.needPhone,
    this.name,
    this.email,
    this.initial,
    this.usernameError,
  });

  final List<String> roles;
  final bool needPhone;
  final String? name;
  final String? email;
  final GoogleRoleChoice? initial;
  final UsernameError? usernameError;

  @override
  State<_GoogleRoleSheet> createState() => _GoogleRoleSheetState();
}

class _GoogleRoleSheetState extends State<_GoogleRoleSheet> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _username = TextEditingController();
  UsernameStatus _usernameStatus = UsernameStatus.empty;
  String? _role;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null && widget.roles.contains(init.role)) _role = init.role;
    _phone.text = init?.phone ?? '';
    _username.text = widget.usernameError?.username ?? init?.username ?? '';
  }

  @override
  void dispose() {
    _phone.dispose();
    _username.dispose();
    super.dispose();
  }

  bool get _usernameOn => !AppConfig.disableList.contains(kUsernameFeatureKey);

  void _pick(String role) {
    HapticFeedback.selectionClick();
    setState(() => _role = role);
  }

  void _submit() {
    if (_role == null) return;
    if (widget.needPhone && !(_formKey.currentState?.validate() ?? false)) return;
    final phone = _phone.text.trim();
    final handle = _usernameOn ? UsernameRules.normalize(_username.text) : '';
    if (handle.isNotEmpty && _usernameStatus.blocksSubmit) {
      showAppNotice(
        _usernameStatus == UsernameStatus.checking ? 'username_wait_check'.tr : 'username_fix_first'.tr,
        error: _usernameStatus != UsernameStatus.checking,
      );
      return;
    }
    Navigator.of(context).pop(
      GoogleRoleChoice(
        role: _role!,
        phone: widget.needPhone && phone.isNotEmpty ? phone : null,
        username: handle.isEmpty ? null : handle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final hasIdentity = (widget.email ?? '').isNotEmpty;

    return ClipRect(
        child: Stack(
          children: [
            // Soft brand glow behind the header
            PositionedDirectional(
              top: -90,
              end: -70,
              child: IgnorePointer(child: _Glow(color: c.primary, size: 260)),
            ),
            PositionedDirectional(
              top: -60,
              start: -90,
              child: IgnorePointer(
                child: _Glow(color: const Color(0xFF4285F4), size: 200, opacity: 0.10),
              ),
            ),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + inset),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: context.colors.onHero,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: context.colors.heroShade.withValues(alpha: 0.10),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Center(child: _GoogleG(size: 28)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _t(
                                  'google_role_title',
                                  'How will you use NextBrain?',
                                  'كيف ستستخدم NextBrain؟',
                                ),
                                style: TextStyle(
                                  fontFamily: AppFonts.family,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: c.textDark,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _t(
                                  'google_role_sub',
                                  'Pick your role to finish creating your account.',
                                  'اختر دورك لإكمال إنشاء حسابك.',
                                ),
                                style: TextStyle(
                                  fontFamily: AppFonts.family,
                                  fontSize: 13,
                                  color: c.secondText,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Who is joining (login flow only: Google already told us)
                    if (hasIdentity) ...[
                      const SizedBox(height: 18),
                      _IdentityChip(name: widget.name, email: widget.email!),
                    ],
                    const SizedBox(height: 22),

                    // Role cards (staggered entrance)
                    for (var i = 0; i < widget.roles.length; i++)
                      _Entrance(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _RoleCard(
                            id: widget.roles[i],
                            selected: _role == widget.roles[i],
                            onTap: () => _pick(widget.roles[i]),
                          ),
                        ),
                      ),

                    // Phone (only when the admin verifies accounts by phone)
                    AnimatedSize(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: widget.needPhone && _role != null
                          ? Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 8),
                        child: IconTextField(
                          controller: _phone,
                          label: 'phone_with_country_code'.tr,
                          icon: Icons.phone_outlined,
                          keyboard: TextInputType.phone,
                        ),
                      )
                          : const SizedBox(width: double.infinity),
                    ),

                    // Optional @username of the new account (D-071 v2; the server ignores it for an existing one)
                    ParentComponent(
                      featureKey: kUsernameFeatureKey,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 8),
                        child: UsernameField(
                          controller: _username,
                          error: widget.usernameError,
                          onStatusChanged: (s) => setState(() => _usernameStatus = s),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),
                    PrimaryButton(
                      isLoading: false,
                      label: _t(
                        'google_role_continue',
                        'Continue with Google',
                        'المتابعة عبر جوجل',
                      ),
                      icon: Icons.arrow_forward_rounded,
                      enable: _role != null,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 14),

                    // Reassurance
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 14, color: c.textLight),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _t(
                              'google_privacy',
                              'Google only confirms your e-mail. We never see your password.',
                              'جوجل يؤكد بريدك فقط. لا نطّلع على كلمة المرور أبداً.',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppFonts.family,
                              fontSize: 11.5,
                              color: c.textLight,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────────

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size, this.opacity = 0.22});

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
      ),
    ),
  );
}

/// Fade + slide-up, delayed by [index].
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 380 + index * 110),
    curve: Curves.easeOutCubic,
    builder: (_, v, w) => Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, (1 - v) * 22), child: w),
    ),
    child: child,
  );
}

class _IdentityChip extends StatelessWidget {
  const _IdentityChip({required this.name, required this.email});

  final String? name;
  final String email;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = (name ?? '').trim().isNotEmpty ? name!.trim() : email;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: c.primary.withValues(alpha: 0.14),
            child: Text(
              shown.isEmpty
                  ? '?'
                  : String.fromCharCode(shown.runes.first).toUpperCase(),
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontWeight: FontWeight.w800,
                color: c.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((name ?? '').trim().isNotEmpty)
                  Text(
                    shown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: c.textDark,
                    ),
                  ),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    fontSize: 12,
                    color: c.secondText,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.verified_rounded, size: 18, color: c.success),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.id,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = _roleMeta[id];
    final radius = BorderRadius.circular(20);

    return AnimatedScale(
      scale: selected ? 1.0 : 0.985,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: selected ? c.primaryWash : c.inputBg,
          border: Border.all(
            color: selected ? c.primary : c.divider,
            width: selected ? 2 : 1.4,
          ),
          boxShadow: selected
              ? [
            BoxShadow(
              color: c.primary.withValues(alpha: 0.20),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      gradient: selected ? c.primaryGradient : null,
                      color: selected ? null : c.primaryWash,
                    ),
                    child: Icon(
                      meta?.icon ?? Icons.person_rounded,
                      size: 24,
                      color: selected ? context.colors.onHero : c.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          id.tr,
                          style: TextStyle(
                            fontFamily: AppFonts.family,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: selected ? c.primary : c.textDark,
                          ),
                        ),
                        if (meta != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            _isAr ? meta.ar : meta.en,
                            style: TextStyle(
                              fontFamily: AppFonts.family,
                              fontSize: 12.5,
                              color: c.secondText,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? c.primary : Colors.transparent,
                      border: Border.all(
                        color: selected ? c.primary : c.textLight,
                        width: 1.6,
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (w, a) =>
                          ScaleTransition(scale: a, child: w),
                      child: selected
                          ? Icon(
                        Icons.check_rounded,
                        key: ValueKey('on'),
                        size: 16,
                        color: context.colors.onHero,
                      )
                          : const SizedBox(key: ValueKey('off')),
                    ),
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