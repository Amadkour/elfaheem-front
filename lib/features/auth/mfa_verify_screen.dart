// The second login step for an account with two-step verification (TOTP): the 6-digit code of the authenticator
// app, or one of the recovery codes. [MfaCodeForm] is the presentational body (tested by the layout harness);
// [MfaVerifyScreen] drives it through MyAuthProvider.verifyMfa. [openMfaStep] opens whatever a login answer asked
// for: this screen, or the enrollment page when the role must use MFA and the account has none yet.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show t;
import '../admin/admin_mfa_page.dart';
import 'auth_provider.dart';
import 'biometric_widgets.dart' show maybeOfferBiometric;
import 'auth_shell.dart';
import 'auth_widgets.dart';
import 'mfa.dart';
import 'package:flutter_education_app/design/app_icons.dart';

/// Opens the screen the login answer asked for ([MyAuthProvider.mfaStep]); after it the user lands on their home.
Future<void> openMfaStep(NavigatorState nav, MyAuthProvider auth) async {
  final step = auth.mfaStep;
  switch (step.kind) {
    case MfaStepKind.verify:
      await nav.push(MaterialPageRoute(builder: (_) => const MfaVerifyScreen()));
    case MfaStepKind.enroll:
      await nav.push(MaterialPageRoute(
        builder: (_) => AdminMfaPage(
          enrollToken: step.token,
          onDone: (ctx) => Navigator.of(ctx).pushNamedAndRemoveUntil(auth.homeRoute, (_) => false),
        ),
      ));
    case MfaStepKind.none:
      break;
  }
}

/// The code entry, from plain values. [embedded] = inside the auth page chrome (the hero already says
/// "Two-step verification"): a plain column, no card, no scrolling of its own.
class MfaCodeForm extends StatelessWidget {
  const MfaCodeForm({
    super.key,
    required this.controller,
    this.useRecovery = false,
    this.busy = false,
    this.error,
    this.attemptsLeft,
    this.dead = false,
    this.onSubmit,
    this.onToggleRecovery,
    this.onRestart,
    this.embedded = false,
  });

  final TextEditingController controller;
  final bool useRecovery, busy, dead, embedded;
  final String? error;
  final int? attemptsLeft;
  final VoidCallback? onSubmit, onToggleRecovery, onRestart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = c.isDark ? c.primaryLight : c.primary;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!embedded) ...[
          Row(children: [
            const ScreenIcon(icon: Icons.shield_rounded),
            const SizedBox(width: 14),
            Expanded(
              child: Text(t('التحقق بخطوتين', 'Two-step verification'),
                  style: authText(19, w: FontWeight.w800, c: c.textDark, h: 1.25)),
            ),
          ]),
          const SizedBox(height: 12),
        ],
        AnimatedSwitcher(
          duration: authDuration(context, 220),
          child: Row(
            key: ValueKey(useRecovery),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (embedded) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c.primary.withValues(alpha: c.isDark ? 0.20 : 0.10), shape: BoxShape.circle),
                  child: Icon(useRecovery ? Icons.key_rounded : Icons.phonelink_lock_rounded, size: 20, color: ink),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  useRecovery
                      ? t('اكتب أحد رموز الاسترداد التي حفظتها عند التفعيل. كل رمز يعمل مرة واحدة فقط.',
                          'Type one of the recovery codes you saved when you turned this on. Each code works once.')
                      : t('افتح تطبيق المصادقة (Google Authenticator أو Microsoft Authenticator أو غيرهما) واكتب الرمز المكوّن من 6 أرقام.',
                          'Open your authenticator app (Google Authenticator, Microsoft Authenticator, …) and type the 6-digit code.'),
                  style: authText(14, c: c.textMedium, h: 1.55),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            key: const ValueKey('mfa.code'),
            controller: controller,
            enabled: !dead && !busy,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: useRecovery ? TextInputType.visiblePassword : TextInputType.number,
            textCapitalization: useRecovery ? TextCapitalization.characters : TextCapitalization.none,
            autofillHints: useRecovery ? null : const [AutofillHints.oneTimeCode],
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: useRecovery
                ? [LengthLimitingTextInputFormatter(24)]
                : [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹ ]')), LengthLimitingTextInputFormatter(7)],
            style: authText(useRecovery ? 18 : 26, w: FontWeight.w700, c: c.textDark, h: 1.2).copyWith(
              letterSpacing: useRecovery ? 1.5 : 8,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            cursorColor: c.primary,
            decoration: authInputDecoration(context, hint: useRecovery ? 'XXXX-XXXX-XXXX-XXXX' : '000000')
                .copyWith(counterText: ''),
            onSubmitted: (_) => onSubmit?.call(),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
        ],
        if (!dead && attemptsLeft != null && attemptsLeft! < 5) ...[
          const SizedBox(height: 8),
          Text(t('المحاولات المتبقية: $attemptsLeft', 'Attempts left: $attemptsLeft'),
              textAlign: TextAlign.center, style: authText(12.5, w: FontWeight.w700, c: c.warning)),
        ],
        const SizedBox(height: 20),
        if (dead)
          AuthButton(label: t('تسجيل الدخول مرة أخرى', 'Sign in again'), icon: DirIcons.login, onPressed: onRestart)
        else
          AuthButton(
              label: t('تحقق', 'Verify'),
              icon: Icons.verified_user_rounded,
              iconBefore: true,
              loading: busy,
              onPressed: busy ? null : onSubmit),
        if (!dead) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.center,
            child: TextButton(
              onPressed: busy ? null : onToggleRecovery,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: ink),
              child: Text(
                useRecovery
                    ? t('استخدام رمز تطبيق المصادقة', 'Use the authenticator code')
                    : t('لا أستطيع الوصول إلى التطبيق؟ استخدم رمز استرداد', 'No access to the app? Use a recovery code'),
                textAlign: TextAlign.center,
                style: authText(13.5, w: FontWeight.w700, c: ink, h: 1.4),
              ),
            ),
          ),
        ],
      ],
    );
    if (embedded) return body;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [AppCard(child: body)]);
  }
}

class MfaVerifyScreen extends StatefulWidget {
  const MfaVerifyScreen({super.key});

  @override
  State<MfaVerifyScreen> createState() => _MfaVerifyScreenState();
}

class _MfaVerifyScreenState extends State<MfaVerifyScreen> {
  final _code = TextEditingController();
  bool _recovery = false;
  String? _localError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<MyAuthProvider>();
    final raw = _code.text.trim();
    if (_recovery ? !looksLikeRecoveryCode(raw) : !isTotpCode(raw)) {
      setState(() => _localError = _recovery
          ? t('رمز الاسترداد مكوّن من 16 حرفاً ورقماً', 'A recovery code has 16 letters and digits')
          : t('اكتب الرمز المكوّن من 6 أرقام', 'Type the 6-digit code'));
      return;
    }
    setState(() => _localError = null);
    final nav = Navigator.of(context);
    final ok = await auth.verifyMfa(code: _recovery ? null : raw, recoveryCode: _recovery ? raw : null);
    if (!mounted) return;
    if (ok) {
      await maybeOfferBiometric(context, auth); // once per account and phone (D-082)
      nav.pushNamedAndRemoveUntil(auth.homeRoute, (_) => false);
    } else {
      _code.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<MyAuthProvider>();
    return AuthScaffold(
      title: t('التحقق بخطوتين', 'Two-step verification'),
      subtitle: t('خطوة أمان أخيرة قبل فتح حسابك.', 'One last security step before your account opens.'),
      builder: (context, isWide) => MfaCodeForm(
        embedded: true,
        controller: _code,
        useRecovery: _recovery,
        busy: auth.isVerifyingMfa,
        error: _localError ?? auth.mfaError,
        attemptsLeft: auth.mfaAttemptsLeft,
        dead: auth.mfaStepDead,
        onSubmit: _submit,
        onToggleRecovery: () => setState(() {
          _recovery = !_recovery;
          _localError = null;
          _code.clear();
        }),
        onRestart: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
