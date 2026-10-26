// The second login step for an account with two-step verification (TOTP): the 6-digit code of the authenticator
// app, or one of the recovery codes. [MfaCodeForm] is the presentational body (tested by the layout harness);
// [MfaVerifyScreen] drives it through MyAuthProvider.verifyMfa. [openMfaStep] opens whatever a login answer asked
// for: this screen, or the enrollment page when the role must use MFA and the account has none yet.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show t;
import '../admin/admin_mfa_page.dart';
import 'auth_provider.dart';
import 'mfa.dart';

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

/// The code entry, from plain values.
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
  });

  final TextEditingController controller;
  final bool useRecovery, busy, dead;
  final String? error;
  final int? attemptsLeft;
  final VoidCallback? onSubmit, onToggleRecovery, onRestart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(useRecovery ? Icons.key_rounded : Icons.shield_rounded, color: c.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(t('التحقق بخطوتين', 'Two-step verification'),
                  style: appText(17, w: FontWeight.w800, c: c.textDark)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            useRecovery
                ? t('اكتب أحد رموز الاسترداد التي حفظتها عند التفعيل. كل رمز يعمل مرة واحدة فقط.',
                    'Type one of the recovery codes you saved when you turned this on. Each code works once.')
                : t('افتح تطبيق المصادقة (Google Authenticator أو Microsoft Authenticator أو غيرهما) واكتب الرمز المكوّن من 6 أرقام.',
                    'Open your authenticator app (Google Authenticator, Microsoft Authenticator, …) and type the 6-digit code.'),
            style: appText(13, c: c.textMedium, h: 1.5),
          ),
          const SizedBox(height: 16),
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
              inputFormatters: useRecovery
                  ? [LengthLimitingTextInputFormatter(24)]
                  : [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹ ]')), LengthLimitingTextInputFormatter(7)],
              style: appText(useRecovery ? 18 : 24, w: FontWeight.w800, c: c.textDark)
                  .copyWith(letterSpacing: useRecovery ? 1.5 : 6),
              decoration: InputDecoration(
                hintText: useRecovery ? 'XXXX-XXXX-XXXX-XXXX' : '000000',
                counterText: '',
              ),
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
                style: appText(12, w: FontWeight.w700, c: c.warning)),
          ],
          const SizedBox(height: 16),
          if (dead)
            AppPrimaryButton(
                label: t('تسجيل الدخول مرة أخرى', 'Sign in again'), icon: Icons.login_rounded, onPressed: onRestart)
          else
            AppPrimaryButton(
                label: t('تحقق', 'Verify'),
                icon: Icons.verified_user_rounded,
                busy: busy,
                onPressed: busy ? null : onSubmit),
          if (!dead) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.center,
              child: TextButton(
                onPressed: busy ? null : onToggleRecovery,
                child: Text(
                  useRecovery
                      ? t('استخدام رمز تطبيق المصادقة', 'Use the authenticator code')
                      : t('لا أستطيع الوصول إلى التطبيق؟ استخدم رمز استرداد', 'No access to the app? Use a recovery code'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ]),
      ),
    ]);
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
      nav.pushNamedAndRemoveUntil(auth.homeRoute, (_) => false);
    } else {
      _code.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<MyAuthProvider>();
    return BasePage(
      useWebCard: true,
      maxWith: 560,
      appBar: ScreenAppBar(title: t('التحقق بخطوتين', 'Two-step verification')),
      child: MfaCodeForm(
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
