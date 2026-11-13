/// ─────────────────────────────────────────────────────────────────────────────
/// change_password_screen.dart
/// Premium change-password screen — works for both student and teacher.
///
/// Features:
///   • Live password strength bar (weak / fair / strong / very strong)
///   • Requirements checklist (min 6 chars, uppercase, digit, new ≠ old, match)
///   • Save button disabled until all requirements are met
///   • Web: centered card with security shield header
///   • Mobile: full-screen scroll with gradient badge
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/password_text_field.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/base_page.dart';
import '../../auth/auth_provider.dart';
import '../../auth/auth_widgets.dart';
import '../../auth/login_screen.dart';
import '../../student/courses/details/components/app_responsive.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase;

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen(
      {super.key, this.fromProfile = true, this.email, this.code});

  final bool fromProfile;
  final String? email;
  final String? code;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldCtrl  = TextEditingController();
  final _newCtrl  = TextEditingController();
  final _confCtrl = TextEditingController();

  bool _obscureOld  = true;
  bool _obscureNew  = true;
  bool _obscureConf = true;
  bool _busy = false; // loading state for the reset-password flow

  @override
  void initState() {
    super.initState();
    _oldCtrl.addListener(_rebuild);
    _newCtrl.addListener(_rebuild);
    _confCtrl.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  // ── Requirements ──────────────────────────────────────────────────────────

  String get _old  => _oldCtrl.text.trim();
  String get _new  => _newCtrl.text.trim();
  String get _conf => _confCtrl.text.trim();

  bool get _reqMinLength  => _new.length >= 8;
  bool get _reqUppercase  => _new.contains(RegExp(r'[A-Z]'));
  bool get _reqDigit      => _new.contains(RegExp(r'[0-9]'));
  bool get _reqDifferent  => _new.isNotEmpty && _new != _old;
  bool get _reqMatch      => _new.isNotEmpty && _new == _conf;

  bool get _canSubmit =>
      (_old.isNotEmpty || !widget.fromProfile) &&
          _reqMinLength &&
          _reqDifferent &&
          _reqMatch;

  // ── Strength 0..4 ─────────────────────────────────────────────────────────

  int get _strength {
    if (_new.isEmpty) return 0;
    int s = 0;
    if (_reqMinLength) s++;
    if (_reqUppercase) s++;
    if (_reqDigit) s++;
    if (_new.length >= 10) s++;
    return s;
  }

  Color _strengthColor(ThemeConfigProvider c) {
    switch (_strength) {
      case 1: return c.danger;
      case 2: return c.warning;
      case 3: return c.success;
      case 4: return c.primary;
      default: return c.divider;
    }
  }

  String _strengthLabel() {
    switch (_strength) {
      case 1: return 'strength_weak'.tr;
      case 2: return 'strength_fair'.tr;
      case 3: return 'strength_strong'.tr;
      case 4: return 'strength_very_strong'.tr;
      default: return '';
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final result = await context.read<ProfileProvider>().changePassword(
      oldPassword: _old,
      newPassword: _new,
    );

    if (!mounted) return;

    if (result != null) {
      _showSnack('password_changed_success'.tr, context.colors.success);
      Navigator.of(context).pop();
    } else {
      _showSnack('wrong_current_password'.tr, context.colors.danger);
    }
  }

  Future<void> _resetPassword() async {
    if (!_canSubmit) return;

    final authProvider = context.read<MyAuthProvider>();
    setState(() => _busy = true);
    // Send the same trimmed value that the validation rules checked.
    final success = await authProvider.changePassword(
      email: widget.email!,
      password: _new,
      code: widget.code!,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (success) {
      _showSnack('password_changed_success'.tr, context.colors.success);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    } else {
      Helpers.showMessage(
        authProvider.errorMessage ?? 'error_occurred'.tr,
        isError: true,
      );
    }
  }

  void _showSnack(String msg, Color color) =>
      showAppNotice(msg);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c      = context.colors;
    final p      = context.watch<ProfileProvider>();
    final isWide = context.showSidebar;

    return BasePage(
      appBar: ScreenAppBar(helpPageId: 'account.change_password', title: 'change_password'.tr),
      // the sign-in sidebar belongs to the password-reset flow (signed out); from the Account page the form
      // stands alone in its centred column
      child: SafeArea(child: isWide && !widget.fromProfile ? _webLayout(p, c) : _mobileLayout(p, c)),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WEB — centered card
  // ══════════════════════════════════════════════════════════════════════════

  Widget _webLayout(ProfileProvider p, ThemeConfigProvider c) {
    Widget w = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl, vertical: AppSpace.xl),
        child: Center(child: _buildForm(p, c)),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthSidebar(),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding:
              const EdgeInsets.symmetric(horizontal: AppSpace.xxl, vertical: AppSpace.xl),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.form.max),
                child: w,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MOBILE — full scroll
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildForm(ProfileProvider p, ThemeConfigProvider c) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // ── The lead: the hint beside a quiet lock well. The page title is the app bar's alone (it was repeated here
      // as a headline, word for word) ──
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: AppTouch.min,
          height: AppTouch.min,
          decoration: BoxDecoration(
            color: appTintOn(context, c.primary),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Icon(Icons.lock_rounded,
              size: AppIconSize.lg, color: appInkOn(context, c.primary, appTintOn(context, c.primary))),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Text('change_password_hint'.tr, style: AppType.body(context)),
        ),
      ]),
      const SizedBox(height: AppSpace.lg),

      _PasswordCard(
        p: p,
        c: c,
        oldCtrl:       _oldCtrl,
        newCtrl:       _newCtrl,
        confCtrl:      _confCtrl,
        obscureOld:    _obscureOld,
        obscureNew:    _obscureNew,
        obscureConf:   _obscureConf,
        onToggleOld:  () { if (mounted) setState(() => _obscureOld  = !_obscureOld); },
        onToggleNew:  () { if (mounted) setState(() => _obscureNew  = !_obscureNew); },
        onToggleConf: () { if (mounted) setState(() => _obscureConf = !_obscureConf); },
        strength:       _strength,
        strengthColor:  _strengthColor(c),
        strengthLabel:  _strengthLabel(),
        reqMinLength:   _reqMinLength,
        reqUppercase:   _reqUppercase,
        reqDigit:       _reqDigit,
        reqDifferent:   _reqDifferent,
        reqMatch:       _reqMatch,
        canSubmit:      _canSubmit && !_busy,
        busy:           _busy,
        onSubmit:       _submit,
        onSubmitForget: _resetPassword,
        fromProfile:    widget.fromProfile,
      ),
    ],
  );

  Widget _mobileLayout(ProfileProvider p, ThemeConfigProvider c) {
    final side = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(side, AppSpace.lg, side, AppSpace.xl),
        child: Center(
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: AppWidth.form.max), child: _buildForm(p, c)),
        ));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _PasswordCard — the main form (used in both layouts)
// ═════════════════════════════════════════════════════════════════════════════

class _PasswordCard extends StatelessWidget {
  final ProfileProvider p;
  final ThemeConfigProvider c;
  final TextEditingController oldCtrl;
  final TextEditingController newCtrl;
  final TextEditingController confCtrl;
  final bool obscureOld;
  final bool obscureNew;
  final bool obscureConf;
  final VoidCallback onToggleOld;
  final VoidCallback onToggleNew;
  final VoidCallback onToggleConf;
  final int strength;
  final Color strengthColor;
  final String strengthLabel;
  final bool reqMinLength;
  final bool reqUppercase;
  final bool reqDigit;
  final bool reqDifferent;
  final bool reqMatch;
  final bool canSubmit;
  final bool busy;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onSubmitForget;
  final bool fromProfile;

  const _PasswordCard({
    required this.p,
    required this.c,
    required this.oldCtrl,
    required this.newCtrl,
    required this.confCtrl,
    required this.obscureOld,
    required this.obscureNew,
    required this.obscureConf,
    required this.onToggleOld,
    required this.onToggleNew,
    required this.onToggleConf,
    required this.strength,
    required this.strengthColor,
    required this.strengthLabel,
    required this.reqMinLength,
    required this.reqUppercase,
    required this.reqDigit,
    required this.reqDifferent,
    required this.reqMatch,
    required this.canSubmit,
    this.busy = false,
    required this.onSubmit,
    this.fromProfile = true,
    required this.onSubmitForget,
  }) ;

  @override
  Widget build(BuildContext context) {
    final allMet = reqMinLength && reqUppercase && reqDigit && (reqDifferent || !fromProfile) && reqMatch;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Section: Current password ─────────────────────────────────────
          if (fromProfile) ...[
            AppFieldLabel('current_password_section'.tr),
            MyPasswordTextField(
              controller: oldCtrl,
              label: 'current_password'.tr,
              obscurePassword: obscureOld,
              onPressed: onToggleOld,
            ),
            const SizedBox(height: AppSpace.lg),
          ],

          // ── Section: New password ─────────────────────────────────────────
          AppFieldLabel('new_password_section'.tr),
          MyPasswordTextField(
            controller: newCtrl,
            label: 'new_password'.tr,
            obscurePassword: obscureNew,
            onPressed: onToggleNew,
          ),

          // ── Strength bar ──────────────────────────────────────────────────
          if (newCtrl.text.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            StrengthBar(
              strength: strength,
              strengthColor: strengthColor,
              strengthLabel: strengthLabel,
              c: c,
            ),
          ],

          const SizedBox(height: AppSpace.sm),
          MyPasswordTextField(
            controller: confCtrl,
            label: 'confirm_new_password'.tr,
            obscurePassword: obscureConf,
            onPressed: onToggleConf,
          ),

          const SizedBox(height: AppSpace.lg),

          // ── Requirements checklist: a sky block that turns emerald once every rule is met (the feedback) ──
          AppBlock(
            tone: allMet ? AppBlockTone.emerald : AppBlockTone.sky,
            padding: const EdgeInsets.all(AppSpace.md),
            child: Builder(builder: (context) {
              final b = AppBlock.colorsOf(context);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('requirements_label'.tr, style: AppType.label(context).copyWith(color: b.ink)),
                  const SizedBox(height: AppSpace.xs),
                  PasswordReq(met: reqMinLength, label: 'req_min_length'.tr,  c: c),
                  PasswordReq(met: reqUppercase, label: 'req_uppercase'.tr,   c: c),
                  PasswordReq(met: reqDigit,     label: 'req_digit'.tr,       c: c),
                  if (fromProfile)
                    PasswordReq(met: reqDifferent, label: 'req_different'.tr, c: c),
                  PasswordReq(met: reqMatch,     label: 'req_match'.tr,       c: c),
                ],
              );
            }),
          ),

          const SizedBox(height: AppSpace.lg),

          // ── Submit (the kit's disabled look until the rules are met) ─────────
          AppButton.primary(
            expand: true,
            size: AppButtonSize.lg,
            label: 'change_password'.tr,
            busy: p.isLoading || busy,
            onPressed: canSubmit ? (fromProfile ? onSubmit : onSubmitForget) : null,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// StrengthBar
// ═════════════════════════════════════════════════════════════════════════════

class StrengthBar extends StatelessWidget {
  final int strength;
  final Color strengthColor;
  final String strengthLabel;
  final ThemeConfigProvider c;

  const StrengthBar({
    super.key,
    required this.strength,
    required this.strengthColor,
    required this.strengthLabel,
    required this.c,
  });

  /// The bar's thickness.
  static const double _bar = AppSpace.xxs + AppSpace.xxs / 2;

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          // the bar glides from where it is to the new strength (interruptible: driven from the current value)
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: strength / 4),
            duration: motion.base,
            curve: AppEase.out,
            builder: (_, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: _bar,
              backgroundColor: c.divider,
              color: strengthColor,
            ),
          ),
        ),
      ),
      const SizedBox(width: AppSpace.sm),
      AnimatedSwitcher(
        duration: motion.fast,
        child: Text(
          strengthLabel,
          key: ValueKey(strengthLabel),
          style: AppType.label(context).copyWith(color: c.blockAccentInk(strengthColor, c.cardBg)),
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PasswordReq — single requirement row
// ═════════════════════════════════════════════════════════════════════════════

class PasswordReq extends StatelessWidget {
  final bool met;
  final String label;
  final ThemeConfigProvider c;

  const PasswordReq(
      {super.key, required this.met, required this.label, required this.c});

  /// A check settles in from this scale (never from nothing).
  static const double _popFrom = 0.8;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xxs),
      child: Row(children: [
        AnimatedSwitcher(
          duration: AppMotion.of(context).fast,
          transitionBuilder: (child, a) =>
              FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: _popFrom, end: 1.0).animate(a), child: child)),
          child: Icon(
            met
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            key: ValueKey(met),
            size: AppIconSize.sm,
            color: met ? b.accentInk(c.success) : b.muted,
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text(
            label,
            style: AppType.meta(context).copyWith(
              color: met ? b.ink : b.muted,
              fontWeight: met ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ]),
    );
  }
}
