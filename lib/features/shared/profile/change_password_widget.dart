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
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/password_text_field.dart';
import '../../../../utils/widget/primary_button.dart';
import '../../../config/app_config.dart';
import '../../../utils/widget/base_page.dart';
import '../../auth/auth_provider.dart';
import '../../auth/auth_widgets.dart';
import '../../auth/login_screen.dart';
import '../../student/courses/details/components/app_responsive.dart';

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
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confCtrl = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConf = true;

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

  String get _old => _oldCtrl.text.trim();

  String get _new => _newCtrl.text.trim();

  String get _conf => _confCtrl.text.trim();

  bool get _reqMinLength => _new.length >= 6;

  bool get _reqUppercase => _new.contains(RegExp(r'[A-Z]'));

  bool get _reqDigit => _new.contains(RegExp(r'[0-9]'));

  bool get _reqDifferent => _new.isNotEmpty && _new != _old;

  bool get _reqMatch => _new.isNotEmpty && _new == _conf;

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

  Color _strengthColor(AppColors c) {
    switch (_strength) {
      case 1:
        return c.danger;
      case 2:
        return c.warning;
      case 3:
        return c.success;
      case 4:
        return c.primaryBlue;
      default:
        return c.divider;
    }
  }

  String _strengthLabel() {
    switch (_strength) {
      case 1:
        return 'ضعيف';
      case 2:
        return 'مقبول';
      case 3:
        return 'قوي';
      case 4:
        return 'قوي جداً';
      default:
        return '';
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
      _showSnack('تم تغيير كلمة المرور بنجاح', context.colors.success);
      Navigator.of(context).pop();
    } else {
      _showSnack('كلمة المرور الحالية غير صحيحة', context.colors.danger);
    }
  }

  Future<void> _resetPassword() async {
    if (!_canSubmit) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.changePassword(
      email: widget.email!,
      password: _newCtrl.text,
      code: widget.code!, // adjust if backend expects old password
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } else {
      Helpers.showMessage(
        context,
        authProvider.errorMessage ?? 'Change failed',
        isError: true,
      );
    }
  }

  void _showSnack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ));

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.watch<ProfileProvider>();
    final isWide = context.showSidebar;

    return BasePage(
      child: SafeArea(
        child: Column(
          children: [
            ScreenAppBar(title: 'change_password'.tr),
            Expanded(
              child: isWide ? _webLayout(p, c) : _mobileLayout(p, c),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WEB — centered card
  // ══════════════════════════════════════════════════════════════════════════

  Widget _webLayout(ProfileProvider p, AppColors c) {
    Widget w = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        child: Center(child: _buildForm(p, c)),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthSidebar(),
        Expanded(
          child: SizedBox(width: 800, child: w),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MOBILE — full scroll
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildForm(ProfileProvider p, AppColors c) => Column(
        children: [
          // ── Security icon badge ──────────────────────────────────────────
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: c.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: c.primaryShadow,
            ),
            child:
                const Icon(Icons.lock_rounded, color: Colors.white, size: 38),
          ),
          const SizedBox(height: 14),
          Text('تغيير كلمة المرور', style: c.h3),
          const SizedBox(height: 4),
          Text('أدخل كلمتك الحالية ثم الجديدة', style: c.caption),
          const SizedBox(height: 28),

          _PasswordCard(
            p: p,
            c: c,
            oldCtrl: _oldCtrl,
            newCtrl: _newCtrl,
            confCtrl: _confCtrl,
            obscureOld: _obscureOld,
            obscureNew: _obscureNew,
            obscureConf: _obscureConf,
            onToggleOld: () => setState(() => _obscureOld = !_obscureOld),
            onToggleNew: () => setState(() => _obscureNew = !_obscureNew),
            onToggleConf: () => setState(() => _obscureConf = !_obscureConf),
            strength: _strength,
            strengthColor: _strengthColor(c),
            strengthLabel: _strengthLabel(),
            reqMinLength: _reqMinLength,
            reqUppercase: _reqUppercase,
            reqDigit: _reqDigit,
            reqDifferent: _reqDifferent,
            reqMatch: _reqMatch,
            canSubmit: _canSubmit,
            onSubmit: _submit,
            onSubmitForget: _resetPassword,
            fromProfile: widget.fromProfile,
          ),
        ],
      );

  Widget _mobileLayout(ProfileProvider p, AppColors c) {
    return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: _buildForm(p, c));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _PasswordCard — the main form (used in both layouts)
// ═════════════════════════════════════════════════════════════════════════════

class _PasswordCard extends StatelessWidget {
  final ProfileProvider p;
  final AppColors c;
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
  final Future<void> Function() onSubmit;
  final Future<void> Function() onSubmitForget;
  final bool fromProfile;
  final String? email;
  final String? code;

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
    required this.onSubmit,
    this.fromProfile = true,
    this.email,
    this.code,
    required this.onSubmitForget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: c.brLarge,
        boxShadow: c.cardShadow,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Section: Current password ─────────────────────────────────────
          if (fromProfile) ...[
            _SectionLabel(label: 'كلمة المرور الحالية', c: c),
            const SizedBox(height: 12),
            MyPasswordTextField(
              controller: oldCtrl,
              label: 'current_password'.tr,
              obscurePassword: obscureOld,
              onPressed: onToggleOld,
            ),
            const SizedBox(height: 24),
          ],

          // ── Section: New password ─────────────────────────────────────────
          _SectionLabel(label: 'كلمة المرور الجديدة', c: c),
          const SizedBox(height: 12),
          MyPasswordTextField(
            controller: newCtrl,
            label: 'new_password'.tr,
            obscurePassword: obscureNew,
            onPressed: onToggleNew,
          ),

          // ── Strength bar ──────────────────────────────────────────────────
          if (newCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            StrengthBar(
              strength: strength,
              strengthColor: strengthColor,
              strengthLabel: strengthLabel,
              c: c,
            ),
          ],

          const SizedBox(height: 14),
          MyPasswordTextField(
            controller: confCtrl,
            label: 'confirm_new_password'.tr,
            obscurePassword: obscureConf,
            onPressed: onToggleConf,
          ),

          const SizedBox(height: 24),

          // ── Requirements checklist ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.inputBg,
              borderRadius: c.brMedium,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المتطلبات', style: c.label.copyWith(fontSize: 12)),
                const SizedBox(height: 10),
                PasswordReq(met: reqMinLength, label: '٦ أحرف على الأقل', c: c),
                PasswordReq(
                    met: reqUppercase,
                    label: 'حرف كبير واحد على الأقل (A-Z)',
                    c: c),
                PasswordReq(met: reqDigit, label: 'رقم واحد على الأقل (0-9)', c: c),
                if (fromProfile)
                  PasswordReq(
                      met: reqDifferent,
                      label: 'مختلفة عن كلمة المرور الحالية',
                      c: c),
                PasswordReq(met: reqMatch, label: 'تطابق كلمة المرور الجديدة', c: c),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Submit ────────────────────────────────────────────────────────
          AnimatedOpacity(
            opacity: canSubmit ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 200),
            child: MyPrimaryButton(
              label: 'change_password'.tr,
              isLoading: p.isLoading,
              onPressed:
                  canSubmit ? (fromProfile ? onSubmit : onSubmitForget) : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _StrengthBar
// ═════════════════════════════════════════════════════════════════════════════

class StrengthBar extends StatelessWidget {
  final int strength;
  final Color strengthColor;
  final String strengthLabel;
  final AppColors c;

  const StrengthBar({super.key,
    required this.strength,
    required this.strengthColor,
    required this.strengthLabel,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: strength / 4,
                minHeight: 6,
                backgroundColor: c.divider,
                color: strengthColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              strengthLabel,
              key: ValueKey(strengthLabel),
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: strengthColor,
              ),
            ),
          ),
        ]),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _Req — single requirement row
// ═════════════════════════════════════════════════════════════════════════════

class PasswordReq extends StatelessWidget {
  final bool met;
  final String label;
  final AppColors c;

  const PasswordReq({super.key, required this.met, required this.label, required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            met
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            key: ValueKey(met),
            size: 16,
            color: met ? c.success : c.textLight,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 12,
            color: met ? c.textDark : c.textLight,
            fontWeight: met ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _SectionLabel
// ═════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String label;
  final AppColors c;

  const _SectionLabel({required this.label, required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 3,
        height: 16,
        decoration: BoxDecoration(
          gradient: c.primaryGradient,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(label, style: c.label.copyWith(fontSize: 13, color: c.textDark)),
    ]);
  }
}
