// Two-step verification (TOTP) of the signed-in admin: turn it on (QR code or the secret typed by hand), see the
// status, make new recovery codes, turn it off. Server: back/services/mfa_service.py (see features/auth/mfa.dart).
//
//   Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminMfaPage()));
//
// With [enrollToken] it is the forced enrollment a login opens when the role must use MFA: the token replaces the
// session, no password is asked, and confirming the first code IS the login ([onDone] then opens the home page).
// The presentational parts ([MfaStatusView], [MfaSetupView], [MfaRecoveryCodesView]) take plain values and are what
// test/auth/mfa_test.dart pumps under the layout harness.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../auth/auth_provider.dart';
import '../auth/mfa.dart';
import 'admin_common.dart' show t;
import 'admin_page.dart';
import 'package:flutter_education_app/design/app_icons.dart';

/// The settings entry's label.
String mfaEntryLabel() => t('التحقق بخطوتين', 'Two-step verification');

Widget _iconBox(BuildContext context, IconData icon, Color color) => Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Icon(icon, color: color),
    );

/// Status card: on / off, recovery codes left, the actions.
class MfaStatusView extends StatelessWidget {
  const MfaStatusView({
    super.key,
    required this.status,
    this.loading = false,
    this.busy = false,
    this.known = true,
    this.error,
    this.onSetup,
    this.onRegenerate,
    this.onDisable,
    this.onRetry,
    this.onSignInAgain,
  });

  final MfaStatus status;
  final bool loading, busy;

  /// False when the status could not be loaded: the card is not shown, so nothing (not even "not available for
  /// this account") is claimed about the account.
  final bool known;
  final String? error;
  final VoidCallback? onSetup, onRegenerate, onDisable, onRetry;

  /// A forced enrollment that cannot go on (its token is no longer valid, or MFA is already on): the only action
  /// left is signing in again, so the manage actions (which need a real session) are hidden.
  final VoidCallback? onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = status;
    return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.lg), physics: const AlwaysScrollableScrollPhysics(), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _iconBox(context, Icons.shield_rounded, s.enabled ? c.success : c.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(mfaEntryLabel(), style: AppType.section(context).copyWith(color: c.textDark))),
          ]),
          const SizedBox(height: AppSpace.sm),
          Text(
              t('بعد كلمة المرور يُطلب رمز من 6 أرقام يظهر في تطبيق المصادقة على هاتفك، فلا يكفي معرفة كلمة المرور وحدها للدخول إلى حسابك.',
                  'After your password you type a 6-digit code from the authenticator app on your phone, so a password alone is not enough to get into your account.'),
              style: AppType.meta(context).copyWith(color: c.textMedium, height: 1.5)),
        ]),
      ),
      const SizedBox(height: AppSpace.sm),
      if (loading)
        const SizedBox(height: 140, child: AppListSkeleton(items: 2))
      else ...[
        if (error != null) ...[
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
          if (onRetry != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: onRetry, child: Text(t('إعادة المحاولة', 'Retry'))),
            ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (known && s.required && !s.enabled && onSignInAgain == null) ...[
          AppBanner(
              icon: Icons.policy_rounded,
              color: c.warning,
              text: t('حسابك يجب أن يستخدم التحقق بخطوتين. فعّله للمتابعة.',
                  'Your account must use two-step verification. Turn it on to continue.')),
          const SizedBox(height: AppSpace.sm),
        ],
        if (known) AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(t('الحالة', 'Status'), style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
              AppBadgePill(s.enabled ? t('مفعّل', 'On') : t('غير مفعّل', 'Off'),
                  color: s.enabled ? c.success : c.textMedium),
              if (s.required) AppBadgePill(t('مطلوب', 'Required'), color: c.warning),
            ]),
            const SizedBox(height: AppSpace.sm),
            if (s.enabled && s.confirmedAt != null)
              AppInfoRow(Icons.event_available_rounded, '${t('فُعّل في', 'Turned on')}: ${AppTime.dateTime(s.confirmedAt!)}'),
            if (s.enabled)
              AppInfoRow(Icons.key_rounded,
                  '${t('رموز الاسترداد المتبقية', 'Recovery codes left')}: ${s.recoveryCodesLeft} / 10'),
            if (s.enabled && s.recoveryCodesLeft <= 2)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text(t('بقي القليل من رموز الاسترداد، أنشئ رموزاً جديدة.', 'Few recovery codes left: make new ones.'),
                    style: AppType.meta(context).copyWith(color: c.warning, fontWeight: FontWeight.w600)),
              ),
            if (!s.enabled && !s.allowed)
              AppInfoRow(Icons.info_outline_rounded,
                  t('التحقق بخطوتين غير متاح لهذا الحساب', 'Two-step verification is not available for this account')),
            if (s.enabled && onSignInAgain != null)
              AppInfoRow(DirIcons.login,
                  t('التحقق بخطوتين مفعّل لهذا الحساب. سجّل الدخول مرة أخرى بالرمز من تطبيق المصادقة.',
                      'Two-step verification is on for this account. Sign in again with the code from your authenticator app.')),
            const SizedBox(height: AppSpace.md),
            if (onSignInAgain == null && !s.enabled && s.allowed)
              AppPrimaryButton(
                  label: t('تفعيل التحقق بخطوتين', 'Turn on two-step verification'),
                  icon: Icons.qr_code_2_rounded,
                  busy: busy,
                  onPressed: busy ? null : onSetup),
            if (onSignInAgain == null && s.enabled) ...[
              AppPrimaryButton(
                  label: t('إنشاء رموز استرداد جديدة', 'Make new recovery codes'),
                  icon: Icons.refresh_rounded,
                  busy: busy,
                  onPressed: busy ? null : onRegenerate),
              const SizedBox(height: AppSpace.xs),
              Align(
                alignment: AlignmentDirectional.center,
                child: TextButton(
                  onPressed: busy ? null : onDisable,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.remove_moderator_rounded, color: c.danger, size: 18),
                    const SizedBox(width: AppSpace.xs),
                    Flexible(
                      child: Text(t('إيقاف التحقق بخطوتين', 'Turn off two-step verification'),
                          textAlign: TextAlign.center, style: AppType.label(context).copyWith(color: c.danger, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ],
          ]),
        ),
        if (onSignInAgain != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppPrimaryButton(
              key: const ValueKey('mfa.sign_in_again'),
              label: t('تسجيل الدخول مرة أخرى', 'Sign in again'),
              icon: DirIcons.login,
              onPressed: busy ? null : onSignInAgain),
        ],
      ],
    ]);
  }
}

/// Enrollment: scan the QR code (or type the secret), then confirm with the first code.
class MfaSetupView extends StatelessWidget {
  const MfaSetupView({
    super.key,
    required this.info,
    required this.code,
    this.busy = false,
    this.error,
    this.onConfirm,
    this.onCopySecret,
    this.onCancel,
  });

  final MfaSetupInfo info;
  final TextEditingController code;
  final bool busy;
  final String? error;
  final VoidCallback? onConfirm, onCopySecret, onCancel;

  Widget _step(BuildContext context, int n, String title) {
    final c = context.colors;
    return Row(children: [
      CircleAvatar(
          radius: 13,
          backgroundColor: c.primary,
          child: Text('$n', style: AppType.meta(context).copyWith(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.w600))),
      const SizedBox(width: AppSpace.sm),
      Expanded(child: Text(title, style: AppType.bodyStrong(context).copyWith(color: c.textDark))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final qr = (box.maxWidth - 96).clamp(140.0, 220.0);
      return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.lg), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _step(context, 1, t('امسح الرمز بتطبيق المصادقة', 'Scan the code with an authenticator app')),
            const SizedBox(height: AppSpace.xs),
            Text(
                t('مثل Google Authenticator أو Microsoft Authenticator أو 1Password.',
                    'For example Google Authenticator, Microsoft Authenticator or 1Password.'),
                style: AppType.meta(context).copyWith(color: c.textMedium, height: 1.5)),
            const SizedBox(height: AppSpace.sm),
            // The QR code stays dark-on-white in both themes on purpose: authenticator scanners need that contrast.
            if (info.otpauthUri.isNotEmpty)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSpace.sm),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.card)),
                  child: QrImageView(
                    key: const ValueKey('mfa.qr'),
                    data: info.otpauthUri,
                    size: qr,
                    backgroundColor: Colors.white,
                    semanticsLabel: t('رمز QR للتحقق بخطوتين', 'Two-step verification QR code'),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: AppSpace.sm),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _step(context, 2, t('أو اكتب المفتاح يدوياً', 'Or type the key by hand')),
            const SizedBox(height: AppSpace.sm),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(children: [
                Expanded(
                  child: SelectableText(groupSecret(info.secret),
                      key: const ValueKey('mfa.secret'),
                      style: AppType.figure(context).copyWith(color: c.textDark, letterSpacing: 1.2)),
                ),
                IconButton(
                    tooltip: t('نسخ المفتاح', 'Copy the key'),
                    onPressed: onCopySecret,
                    icon: const Icon(Icons.copy_rounded)),
              ]),
            ),
            if (info.account.isNotEmpty || info.issuer.isNotEmpty)
              AppInfoRow(Icons.person_outline_rounded,
                  [info.issuer, info.account].where((e) => e.isNotEmpty).join(' · '), ltr: true),
            AppInfoRow(Icons.timer_outlined, t('نوع المفتاح: حسب الوقت · 6 أرقام · كل 30 ثانية', 'Time-based · 6 digits · every 30 seconds')),
          ]),
        ),
        const SizedBox(height: AppSpace.sm),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _step(context, 3, t('اكتب الرمز الذي يظهر في التطبيق', 'Type the code the app shows')),
            const SizedBox(height: AppSpace.sm),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                key: const ValueKey('mfa.confirm_code'),
                controller: code,
                enabled: !busy,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹ ]')),
                  LengthLimitingTextInputFormatter(7),
                ],
                style: AppType.figureLarge(context).copyWith(color: c.textDark, letterSpacing: 6),
                decoration: const InputDecoration(hintText: '000000', counterText: ''),
                onSubmitted: (_) => onConfirm?.call(),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpace.sm),
              AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
            ],
            const SizedBox(height: AppSpace.md),
            AppPrimaryButton(
                label: t('تأكيد وتفعيل', 'Confirm and turn on'),
                icon: Icons.verified_user_rounded,
                busy: busy,
                onPressed: busy ? null : onConfirm),
            if (onCancel != null)
              Align(
                alignment: AlignmentDirectional.center,
                child: TextButton(onPressed: busy ? null : onCancel, child: Text(t('إلغاء', 'Cancel'))),
              ),
          ]),
        ),
      ]);
    });
  }
}

/// The recovery codes, shown once.
class MfaRecoveryCodesView extends StatelessWidget {
  const MfaRecoveryCodesView({super.key, required this.codes, this.onCopy, this.onDone, this.doneLabel});

  final List<String> codes;
  final VoidCallback? onCopy, onDone;
  final String? doneLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.lg), children: [
      AppBanner(
          icon: Icons.warning_amber_rounded,
          color: c.warning,
          text: t('احفظ هذه الرموز في مكان آمن الآن، فلن تظهر مرة أخرى. كل رمز يدخلك مرة واحدة إذا فقدت هاتفك.',
              'Save these codes somewhere safe now: they are not shown again. Each one signs you in once if you lose your phone.')),
      const SizedBox(height: AppSpace.sm),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _iconBox(context, Icons.key_rounded, c.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
                child: Text(t('رموز الاسترداد', 'Recovery codes'), style: AppType.section(context).copyWith(color: c.textDark))),
          ]),
          const SizedBox(height: AppSpace.sm),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final code in codes)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                  decoration: BoxDecoration(
                    color: c.primaryWash,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    border: Border.all(color: c.divider),
                  ),
                  child: SelectableText(code,
                      style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600).copyWith(letterSpacing: 0.8)),
                ),
            ]),
          ),
          const SizedBox(height: AppSpace.md),
          AppPrimaryButton(label: t('نسخ الرموز', 'Copy the codes'), icon: Icons.copy_rounded, onPressed: onCopy),
          const SizedBox(height: AppSpace.xs),
          Align(
            alignment: AlignmentDirectional.center,
            child: TextButton(onPressed: onDone, child: Text(doneLabel ?? t('حفظتها، تم', 'I saved them, done'))),
          ),
        ]),
      ),
    ]);
  }
}

enum _Stage { status, setup, codes }

class AdminMfaPage extends StatefulWidget {
  const AdminMfaPage({super.key, this.api, this.enrollToken, this.onDone});

  /// For tests; defaults to [RemoteMfaApi] (with [enrollToken] when given).
  final MfaApi? api;

  /// The enrollment token of a login that requires MFA (see the file header).
  final String? enrollToken;

  /// Called after the recovery codes of a forced enrollment were seen.
  final void Function(BuildContext context)? onDone;

  @override
  State<AdminMfaPage> createState() => _AdminMfaPageState();
}

class _AdminMfaPageState extends State<AdminMfaPage> {
  late final MfaApi _api = widget.api ?? RemoteMfaApi(enrollToken: widget.enrollToken);
  final _code = TextEditingController();
  MfaStatus _status = MfaStatus.empty;
  MfaSetupInfo? _setup;
  List<String> _codes = const [];
  _Stage _stage = _Stage.status;
  bool _loading = true, _busy = false;

  /// The status was loaded at least once (a failed load shows only the error, never "not available").
  bool _known = false;

  /// Forced enrollment whose token the server no longer accepts (expired, other device, account changed).
  bool _dead = false;
  String? _error;

  bool get _forced => widget.enrollToken != null;

  /// A forced enrollment cannot go on: the token is dead, or the account already has MFA (the manage routes need a
  /// real session, which this page does not have). The way out is a new sign-in.
  bool get _mustSignInAgain => _forced && (_dead || _status.enabled);

  /// True (and the page switched to "sign in again") when [e] says the enrollment token is no longer valid.
  bool _forcedTokenDead(Object e) {
    final ex = ApiException.from(e);
    if (!_forced || !(ex.statusCode == 401 || mfaStepIsDead(ex.code))) return false;
    final code = mfaStepIsDead(ex.code) ? ex.code : 'mfa_token_invalid';
    setState(() {
      _dead = true;
      _stage = _Stage.status;
      _error = mfaCodeText(code, ex.message);
    });
    return true;
  }

  void _signInAgain() => Navigator.of(context).maybePop();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _text(Object e) {
    final ex = ApiException.from(e);
    return mfaCodeText(ex.code, ex.message);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _api.status();
      if (!mounted) return;
      setState(() {
        _status = s;
        _known = true;
      });
      if (_forced && !s.enabled) await _startSetup();      // forced: straight to the QR code
    } catch (e) {
      if (mounted && !_forcedTokenDead(e)) setState(() => _error = _text(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _ask({required String title, bool password = false, bool code = false, bool recovery = false}) {
    final pw = TextEditingController(), cd = TextEditingController();
    return showAppSheet<String>(context, (ctx) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader(title),
          if (password) ...[
            const SizedBox(height: AppSpace.sm),
            TextField(
              key: const ValueKey('mfa.password'),
              controller: pw,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(labelText: t('كلمة المرور', 'Password')),
            ),
          ],
          if (code) ...[
            const SizedBox(height: AppSpace.sm),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                key: const ValueKey('mfa.sheet_code'),
                controller: cd,
                keyboardType: recovery ? TextInputType.visiblePassword : TextInputType.number,
                decoration: InputDecoration(
                    labelText: recovery
                        ? t('رمز التطبيق أو رمز استرداد', 'App code or a recovery code')
                        : t('رمز التطبيق (6 أرقام)', 'App code (6 digits)')),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          AppPrimaryButton(
            label: t('متابعة', 'Continue'),
            icon: Icons.arrow_forward_rounded,
            onPressed: () => Navigator.of(ctx).pop('${pw.text}\u0000${cd.text}'),
          ),
        ]),
      );
    });
  }

  Future<void> _startSetup() async {
    String? password;
    if (!_forced) {
      final r = await _ask(title: t('أكّد كلمة المرور', 'Confirm your password'), password: true);
      if (r == null || !mounted) return;
      password = r.split('\u0000').first;
      if (password.isEmpty) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await _api.setup(password: password);
      if (!mounted) return;
      setState(() {
        _setup = info;
        _code.clear();
        _stage = _Stage.setup;
      });
    } catch (e) {
      final ex = ApiException.from(e);
      if (ex.code == 'mfa_already_enabled') {
        await _load();
      } else if (mounted && !_forcedTokenDead(e)) {
        setState(() => _error = _text(e));
        if (_stage == _Stage.status) appToast(_text(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (!isTotpCode(_code.text)) {
      setState(() => _error = t('اكتب الرمز المكوّن من 6 أرقام', 'Type the 6-digit code'));
      return;
    }
    final auth = context.read<MyAuthProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.confirm(_code.text);
      // every other session ended: the answer carries this device's new token pair — save it before anything else
      if (r['access_token'] != null) await auth.completeSession(r);
      if (!mounted) return;
      setState(() {
        _codes = recoveryCodesOf(r);
        _stage = _Stage.codes;
      });
    } catch (e) {
      if (mounted && !_forcedTokenDead(e)) setState(() => _error = _text(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _regenerate() async {
    final r = await _ask(title: t('رموز استرداد جديدة', 'New recovery codes'), code: true);
    if (r == null || !mounted) return;
    final code = r.split('\u0000').last;
    setState(() => _busy = true);
    try {
      final codes = await _api.regenerateRecoveryCodes(code);
      if (!mounted) return;
      setState(() {
        _codes = codes;
        _stage = _Stage.codes;
      });
    } catch (e) {
      appToast(_text(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final r = await _ask(
        title: t('إيقاف التحقق بخطوتين', 'Turn off two-step verification'), password: true, code: true, recovery: true);
    if (r == null || !mounted) return;
    final parts = r.split('\u0000');
    final code = parts.last.trim();
    setState(() => _busy = true);
    try {
      await _api.disable(
          password: parts.first,
          code: isTotpCode(code) ? code : null,
          recoveryCode: isTotpCode(code) ? null : code);
      appToast(t('تم إيقاف التحقق بخطوتين', 'Two-step verification is off'));
      await _load();
    } catch (e) {
      appToast(_text(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    if (_forced && widget.onDone != null) {
      widget.onDone!(context);
      return;
    }
    setState(() {
      _stage = _Stage.status;
      _codes = const [];
      _setup = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_stage) {
      _Stage.setup when _setup != null => MfaSetupView(
          info: _setup!,
          code: _code,
          busy: _busy,
          error: _error,
          onConfirm: _confirm,
          onCopySecret: () {
            Clipboard.setData(ClipboardData(text: _setup!.secret));
            appToast(t('تم نسخ المفتاح', 'Key copied'));
          },
          onCancel: _forced ? null : () => setState(() => _stage = _Stage.status),
        ),
      _Stage.codes => MfaRecoveryCodesView(
          codes: _codes,
          doneLabel: _forced ? t('حفظتها، متابعة', 'I saved them, continue') : null,
          onCopy: () {
            Clipboard.setData(ClipboardData(text: _codes.join('\n')));
            appToast(t('تم نسخ الرموز', 'Codes copied'));
          },
          onDone: _done,
        ),
      _ => MfaStatusView(
          status: _status,
          loading: _loading,
          busy: _busy,
          known: _known && !_dead,
          error: _error,
          onSetup: _startSetup,
          onRegenerate: _regenerate,
          onDisable: _disable,
          onRetry: _dead ? null : _load,
          onSignInAgain: _mustSignInAgain ? _signInAgain : null,
        ),
    };
    return PopScope(
      // the forced enrollment cannot be skipped once the codes are on screen (the session already exists)
      canPop: !(_forced && _stage == _Stage.codes),
      child: AdminPage(
        key: const ValueKey('admin.mfa'),
        title: mfaEntryLabel(),
        icon: Icons.verified_user_rounded,
        maxWidth: 760,
        onRefresh: _dead ? null : _load,
        body: body is MfaStatusView && !_dead ? AppRefresh(onRefresh: _load, child: body) : body,
      ),
    );
  }
}

/// Label of the super-admin action that removes another user's two-step verification.
String mfaResetLabel() => t('إعادة تعيين التحقق بخطوتين', 'Reset two-step verification');

/// Super admin: asks, then removes the two-step verification of user [userId] ([name] in the question), for a user
/// who lost both the phone and the recovery codes. The server signs that user out everywhere. Returns true when it
/// was removed; server refusals (`mfa_not_enabled`, `mfa_reset_self`, …) are shown as a toast. [reset] is for tests.
Future<bool> confirmResetUserMfa(BuildContext context,
    {required int userId, required String name, Future<void> Function(int userId)? reset}) async {
  final ok = await appConfirm(context,
      danger: true,
      confirmLabel: t('إعادة التعيين', 'Reset'),
      message: t(
          'إزالة التحقق بخطوتين من حساب "$name"؟ سيُسجَّل خروجه من كل الأجهزة، وإن كان دوره يتطلب التحقق بخطوتين فسيُطلب منه إعداده من جديد عند الدخول. استخدم هذا فقط بعد التأكد من هويته.',
          'Remove two-step verification from "$name"? They are signed out on every device and, if their role requires it, set it up again at their next sign-in. Only do this after you have confirmed who they are.'));
  if (!ok) return false;
  try {
    await (reset ?? resetUserMfa)(userId);
    appToast(t('تمت إزالة التحقق بخطوتين من الحساب', 'Two-step verification was removed from the account'));
    return true;
  } catch (e) {
    final ex = ApiException.from(e);
    appToast(mfaCodeText(ex.code, ex.message), error: true);
    return false;
  }
}
