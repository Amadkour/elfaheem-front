// Review renders of the S-A auth screens (Stu1Auth) at 390x844 and 1360x900, Arabic (and English for the main
// states), next to D:/platform/redesign-ref/ref/student/0xx_Stu1Auth_*.png. Not a CI suite.
//
//   flutter test test/visual/redesign/sa --update-goldens [--plain-name login]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/features/auth/auth_shell.dart';
import 'package:flutter_education_app/features/auth/forget_screen.dart';
import 'package:flutter_education_app/features/auth/kid_code/kid_code_api.dart';
import 'package:flutter_education_app/features/auth/kid_code/kid_code_screen.dart';
import 'package:flutter_education_app/features/auth/login_screen.dart';
import 'package:flutter_education_app/features/auth/register_screen.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_api.dart';
import '../kit_golden_harness.dart';

late StorageService _storage;

Widget _providers(Widget child) =>
    MultiProvider(providers: appProviders(storage: _storage, api: ApiClient()), child: child);

/// The kid-code page at one step, from plain values (AuthLayout + the step's view).
Widget kidStep(KidCodeStep step) {
  final code = TextEditingController(text: step == KidCodeStep.enter ? '482917' : '');
  final pass = TextEditingController(text: 'Faisal2026x');
  const account = KidCodeAccount(
      firstName: 'فيصل', lastName: 'العنزي', gradeAr: 'الثاني ثانوي', gradeEn: 'Grade 11', parentName: 'أحمد العنزي');
  final (title, sub, glyph) = switch (step) {
    KidCodeStep.enter => ('sa_kid_enter_title'.tr, 'sa_kid_enter_sub'.tr, Icons.key_rounded),
    KidCodeStep.found => ('sa_kid_found_title'.tr, 'sa_kid_found_sub'.tr, null),
    KidCodeStep.pass => ('sa_kid_pass_title'.tr, 'sa_kid_pass_sub'.tr, Icons.lock_outline_rounded),
  };
  return AuthLayout(
    kicker: 'sa_kid_kicker'.tr,
    heroTitle: 'sa_kid_hero'.tr,
    squiggle: 'sa_kid_squiggle'.tr,
    title: title,
    subtitle: sub,
    glyph: glyph,
    actions: (onHero) => AuthLangButton(arabic: AppConfig.lang == 'ar', onHero: onHero, onTap: () {}),
    body: (context, wide) => switch (step) {
      KidCodeStep.enter => KidCodeEnterView(controller: code, onSubmit: () {}, onBack: () {}),
      KidCodeStep.found => KidCodeFoundView(account: account, onYes: () {}, onNo: () {}),
      KidCodeStep.pass => KidCodePassView(controller: pass, onSubmit: () {}),
    },
  );
}

void main() {
  late FakeApi api;
  setUpAll(() async {
    _storage = await kitGoldenSetUp();
    mockRequestPlugins();
    api = FakeApi({
      'GET /api/v1/auth/policy': (_) => {'login_identifier': 'either', 'verification_method': 'phone', 'verify_ways': ['sms']},
    }, fallback: (_) => const <String, dynamic>{})
      ..install();
  });
  tearDownAll(() => api.uninstall());

  testWidgets('login', (tester) async {
    await kitRender(tester, 'sa_login', () => _providers(const LoginScreen()), storage: _storage, modes: const [false]);
  });

  testWidgets('kid code', (tester) async {
    for (final s in KidCodeStep.values) {
      await kitRender(tester, 'sa_kid_${s.name}', () => kidStep(s),
          storage: _storage, modes: const [false], langs: s == KidCodeStep.enter ? const ['ar', 'en'] : const ['ar']);
    }
  });

  testWidgets('forgot', (tester) async {
    await kitRender(tester, 'sa_forgot', () => _providers(const ForgetScreen()), storage: _storage, modes: const [false], langs: const ['ar']);
  });

  testWidgets('register', (tester) async {
    await kitRender(tester, 'sa_register', () => _providers(const RegisterScreen()), storage: _storage, modes: const [false], langs: const ['ar'], grow: false);
  });
}
