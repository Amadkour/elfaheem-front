// Two-step verification (TOTP): parsing of the server answers, the input helpers, the bilingual code texts, the
// teacher onboarding token holder, and every MFA widget on every screen size (layout harness).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_mfa_page.dart';
import 'package:flutter_education_app/features/auth/mfa.dart';
import 'package:flutter_education_app/features/auth/mfa_verify_screen.dart';
import 'package:flutter_education_app/features/auth/teacher_onboarding_token.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _uri = 'otpauth://totp/ElFaheem:admin%40x.io?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=ElFaheem'
    '&algorithm=SHA1&digits=6&period=30';

class _FakeApi implements MfaApi {
  _FakeApi(this.current);
  MfaStatus current;
  int setups = 0;
  String? lastPassword;

  @override
  Future<MfaStatus> status() async => current;

  @override
  Future<MfaSetupInfo> setup({String? password}) async {
    setups++;
    lastPassword = password;
    return const MfaSetupInfo(secret: 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP', otpauthUri: _uri, issuer: 'ElFaheem',
        account: 'admin@x.io');
  }

  @override
  Future<Map<String, dynamic>> confirm(String code) async => {'recovery_codes': ['AAAA-BBBB-CCCC-DDDD']};

  @override
  Future<void> disable({required String password, String? code, String? recoveryCode}) async {}

  @override
  Future<List<String>> regenerateRecoveryCodes(String code) async => const ['AAAA-BBBB-CCCC-DDDD'];
}

final _codes = List.generate(10, (i) => 'AB${i}C-DEFG-HJKL-MNP$i');

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('login answers', () {
    test('mfa_required → verify step; tokens → none', () {
      final s = MfaLoginStep.fromLogin(const {'mfa_required': true, 'mfa_token': 'tok', 'expires_in': 300, 'attempts_left': 5});
      expect(s.kind, MfaStepKind.verify);
      expect(s.token, 'tok');
      expect(s.expiresIn, 300);
      expect(s.attemptsLeft, 5);
      expect(MfaLoginStep.fromLogin(const {'access_token': 'a', 'refresh_token': 'r', 'user': {}}).kind, MfaStepKind.none);
      expect(MfaLoginStep.fromLogin(null).kind, MfaStepKind.none);
      expect(MfaLoginStep.fromLogin(const {'mfa_required': true}).kind, MfaStepKind.none, reason: 'no token, no step');
    });

    test('mfa_enrollment_required → enroll step', () {
      final s = MfaLoginStep.fromLogin(const {'mfa_enrollment_required': true, 'mfa_enroll_token': 'e', 'expires_in': '900'});
      expect(s.kind, MfaStepKind.enroll);
      expect(s.token, 'e');
      expect(s.expiresIn, 900);
    });

    test('status and setup parsing never throw; naive times are UTC', () {
      final s = MfaStatus.fromJson(const {
        'enabled': true, 'pending': false, 'allowed': true, 'required': true, 'recovery_codes_left': '7',
        'confirmed_at': '2026-10-26T08:00:00'
      });
      expect(s.enabled && s.allowed && s.required, isTrue);
      expect(s.recoveryCodesLeft, 7);
      expect(s.confirmedAt, DateTime.utc(2026, 10, 26, 8));
      expect(MfaStatus.fromJson('x').enabled, isFalse);
      expect(MfaStatus.fromJson(const {'confirmed_at': 'garbage'}).confirmedAt, isNull);
      final i = MfaSetupInfo.fromJson(const {'secret': 'ABC', 'otpauth_uri': _uri});
      expect(i.secret, 'ABC');
      expect(i.otpauthUri, _uri);
      expect(MfaSetupInfo.fromJson(null).secret, '');
      expect(recoveryCodesOf(const {'recovery_codes': ['a', 'b']}), ['a', 'b']);
      expect(recoveryCodesOf(const {}), isEmpty);
    });
  });

  group('input helpers', () {
    test('codes', () {
      expect(groupSecret('JBSWY3DPEHPK3PXPJ'), 'JBSW Y3DP EHPK 3PXP J');
      expect(normalizeTotp('١٢٣ ٤٥٦'), '123456');
      expect(normalizeTotp('۱۲۳۴۵۶'), '123456');
      expect(isTotpCode('123456'), isTrue);
      expect(isTotpCode('123 456'), isTrue);
      expect(isTotpCode('١٢٣٤٥٦'), isTrue);
      expect(isTotpCode('12345'), isFalse);
      expect(isTotpCode('12345a'), isFalse);
      expect(isTotpCode('1234567'), isFalse);
      expect(looksLikeRecoveryCode('ABCD-EFGH-JKLM-NPQR'), isTrue);
      expect(looksLikeRecoveryCode('abcd efgh jklm npqr'), isTrue);
      expect(looksLikeRecoveryCode('ABCD-EFGH'), isFalse);
    });

    test('every server code has both languages', () {
      const codes = ['mfa_code_invalid', 'mfa_token_invalid', 'mfa_token_used', 'mfa_token_expired', 'mfa_token_locked',
        'too_many_attempts', 'mfa_unavailable', 'mfa_already_enabled', 'mfa_not_pending', 'mfa_not_enabled',
        'mfa_not_available', 'password_invalid', 'mfa_enrollment_required', 'mfa_reset_self'];
      final seen = <String, Set<String>>{};
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        for (final c in codes) {
          final txt = mfaCodeText(c, 'FALLBACK');
          expect(txt, isNot('FALLBACK'), reason: '$c / $lang');
          seen.putIfAbsent(c, () => {}).add(txt);
        }
        expect(mfaCodeText('other', 'FALLBACK'), 'FALLBACK');
      }
      for (final e in seen.entries) {
        expect(e.value.length, 2, reason: '${e.key}: Arabic and English must differ');
      }
      expect(mfaStepIsDead('mfa_token_expired'), isTrue);
      expect(mfaStepIsDead('mfa_code_invalid'), isFalse, reason: 'a wrong code can be retried');
    });

    test('teacher onboarding token: kept, renewed and dropped by the server answers', () {
      TeacherOnboardingToken.clear();
      expect(TeacherOnboardingToken.headers, isNull);
      TeacherOnboardingToken.readFrom(const {'onboarding_token': 'abc'});
      expect(TeacherOnboardingToken.headers, {'X-Onboarding-Token': 'abc'});
      TeacherOnboardingToken.readFrom(const {'message': 'no field'});
      expect(TeacherOnboardingToken.value, 'abc', reason: 'an answer without the field keeps it');
      TeacherOnboardingToken.readFrom(const {'onboarding_token': null});
      expect(TeacherOnboardingToken.value, isNull, reason: 'onboarding finished');
    });
  });

  group('layout', () {
    testWidgets('MfaCodeForm: code, recovery, error, attempts, dead step', (t) async {
      final ctl = TextEditingController(text: '123456');
      addTearDown(ctl.dispose);
      await expectNoLayoutErrors(t, () => MfaCodeForm(controller: ctl, onSubmit: () {}, onToggleRecovery: () {}));
      await expectNoLayoutErrors(
          t,
          () => MfaCodeForm(
              controller: ctl,
              useRecovery: true,
              error: 'The code is not correct — and a long message that has to wrap on a narrow phone screen',
              attemptsLeft: 2));
      await expectNoLayoutErrors(t, () => MfaCodeForm(controller: ctl, busy: true));
      await expectNoLayoutErrors(t, () => MfaCodeForm(controller: ctl, dead: true, error: 'Please sign in again'));
    });

    testWidgets('MfaCodeForm buttons', (t) async {
      final ctl = TextEditingController();
      addTearDown(ctl.dispose);
      var submit = 0, toggle = 0, restart = 0;
      await t.pumpWidget(layoutHost(MfaCodeForm(
          controller: ctl, onSubmit: () => submit++, onToggleRecovery: () => toggle++, onRestart: () => restart++)));
      await t.tap(find.text('Verify'));
      await t.tap(find.text('No access to the app? Use a recovery code'));
      expect((submit, toggle), (1, 1));
      await t.pumpWidget(layoutHost(MfaCodeForm(controller: ctl, dead: true, onRestart: () => restart++)));
      expect(find.text('Verify'), findsNothing);
      await t.tap(find.text('Sign in again'));
      expect(restart, 1);
      await t.pumpWidget(const SizedBox());
    });

    final states = <String, MfaStatus>{
      'off': const MfaStatus(allowed: true),
      'required': const MfaStatus(allowed: true, required: true),
      'on': MfaStatus(enabled: true, allowed: true, recoveryCodesLeft: 9, confirmedAt: DateTime.utc(2026, 10, 1, 9)),
      'on, few codes': const MfaStatus(enabled: true, allowed: true, required: true, recoveryCodesLeft: 1),
      'not allowed': const MfaStatus(),
    };
    for (final e in states.entries) {
      testWidgets('MfaStatusView ${e.key}', (t) async {
        await expectNoLayoutErrors(
            t, () => MfaStatusView(status: e.value, onSetup: () {}, onRegenerate: () {}, onDisable: () {}));
      });
    }

    testWidgets('MfaStatusView loading / busy / error', (t) async {
      await expectNoLayoutErrors(t, () => const MfaStatusView(status: MfaStatus.empty, loading: true));
      await expectNoLayoutErrors(
          t,
          () => MfaStatusView(
              status: states['on']!, busy: true, error: 'Two-step verification is unavailable right now', onRetry: () {}));
    });

    testWidgets('MfaSetupView', (t) async {
      final ctl = TextEditingController(text: '12');
      addTearDown(ctl.dispose);
      const info = MfaSetupInfo(
          secret: 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP', otpauthUri: _uri, issuer: 'ElFaheem', account: 'a.very.long.admin.address@university.example.edu');
      await expectNoLayoutErrors(t, () => MfaSetupView(info: info, code: ctl, onConfirm: () {}, onCancel: () {}));
      await expectNoLayoutErrors(t, () => MfaSetupView(info: info, code: ctl, busy: true, error: 'The code is not correct'));
    });

    testWidgets('MfaRecoveryCodesView', (t) async {
      await expectNoLayoutErrors(t, () => MfaRecoveryCodesView(codes: _codes, onCopy: () {}, onDone: () {}));
    });

    testWidgets('AdminMfaPage: status, then setup asks for the password', (t) async {
      final api = _FakeApi(const MfaStatus(allowed: true));
      await expectNoLayoutErrors(t, () => AdminMfaPage(api: api), scaffold: false);
      await t.pumpWidget(layoutHost(AdminMfaPage(api: api), scaffold: false));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.text('Turn on two-step verification'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('mfa.password')), findsOneWidget, reason: 'a normal session confirms the password');
      await t.enterText(find.byKey(const ValueKey('mfa.password')), 'Secret123!');
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(api.setups, 1);
      expect(api.lastPassword, 'Secret123!');
      expect(find.byKey(const ValueKey('mfa.qr')), findsOneWidget);
      expect(find.text('JBSW Y3DP EHPK 3PXP JBSW Y3DP EHPK 3PXP'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('AdminMfaPage with an enrollment token goes straight to the QR code, no password', (t) async {
      final api = _FakeApi(const MfaStatus(allowed: true, required: true));
      await expectNoLayoutErrors(t, () => AdminMfaPage(api: api, enrollToken: 'e'), scaffold: false);
      await t.pumpWidget(layoutHost(AdminMfaPage(api: api, enrollToken: 'e'), scaffold: false));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('mfa.qr')), findsOneWidget);
      expect(api.lastPassword, isNull);
      expect(find.text('Cancel'), findsNothing, reason: 'a forced enrollment cannot be cancelled');
      await t.pumpWidget(const SizedBox());
    });
  });
}
