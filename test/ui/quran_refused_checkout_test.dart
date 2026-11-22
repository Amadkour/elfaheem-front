// R1 (6.R): a Quran program's booking refused at checkout (403 `quran_gender_rule` / `quran_teacher_unverified`,
// from the free enrol or from the hosted checkout's session) shows the server's reason in the person's language
// (apiErrorText), "Back to the course" and NO retry — never "payment failed". Over FakeApi, through the real
// EnrollmentScreen and EnrollmentProvider.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_screen.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_widgets.dart' show EnrollScaffold;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

Map<String, dynamic> _refusal(String code, [Map<String, dynamic> extra = const {}]) => {
      'detail': {'code': code, 'message': 'رفض', 'message_en': 'Refused', ...extra},
    };

FakeApi _api({required bool paid, required String path, required Map<String, dynamic> refusal}) => FakeApi({
      'GET /api/v1/payments/transfer-status': (_) => <String, dynamic>{},
      'GET /api/v1/config': (_) => {
            'provider': 'paymob',
            'currency': 'EGP',
            'payment_methods': [
              {'type': 'card', 'label': 'Card', 'enabled': true},
            ],
          },
      'GET /api/v1/payments/price-options': (_) => {
            'currency': 'EGP',
            'default_plan': 'yearly',
            'options': paid
                ? [
                    {'plan': 'yearly', 'duration_days': 365, 'price': 300, 'final_price': 300},
                  ]
                : <Object>[],
          },
      'GET /api/v1/payments/fees/preview': (_) => {'course_price': 300, 'total': 300},
      'POST $path': (_) => FakeResponse(403, refusal),
    }, latency: const Duration(milliseconds: 10));

CourseModel _course(bool paid) => CourseModel.fromJson({'id': 41, 'title_ar': 'حفظ', 'title_en': 'Hifz', 'fees': paid ? 300 : 0, 'is_enrolled': false, 'is_published': true});

Future<EnrollmentProvider> _refuse(WidgetTester tester, {required bool paid}) async {
  await tester.pumpWidget(layoutHost(EnrollmentScreen(course: _course(paid)), scale: 1));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  final ctx = tester.element(find.byType(EnrollScaffold));
  final p = ctx.read<EnrollmentProvider>();
  expect(p.isFree, !paid);
  expect(p.canConfirm, isTrue);
  unawaited(p.confirm(ctx));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return p;
}

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  final cases = [
    (name: 'free enrol, gender rule', paid: false, path: '/api/v1/courses/41/enroll', refusal: _refusal('quran_gender_rule', {'reason': 'gender_differs'})),
    (name: 'free enrol, unverified teacher', paid: false, path: '/api/v1/courses/41/enroll', refusal: _refusal('quran_teacher_unverified')),
    (name: 'hosted checkout, gender rule', paid: true, path: '/api/v1/payments/create-web-session', refusal: _refusal('quran_gender_rule', {'reason': 'gender_differs'})),
  ];

  for (final c in cases) {
    for (final lang in const ['ar', 'en']) {
      testWidgets('${c.name} ($lang): the reason, "Back to the course", no retry', (tester) async {
        SharedPreferences.setMockInitialValues({});
        mockRequestPlugins();
        final prev = AppConfig.lang;
        AppConfig.lang = lang;
        addTearDown(() => AppConfig.lang = prev);
        final api = _api(paid: c.paid, path: c.path, refusal: c.refusal)..install();
        addTearDown(api.uninstall);

        final p = await _refuse(tester, paid: c.paid);
        expect(api.calls.where((x) => x.method == 'POST' && x.path == c.path), hasLength(1), reason: 'refused once, not retried');
        expect(p.refused, isTrue);
        expect(p.step, EnrollStep.failed);

        final code = (c.refusal['detail'] as Map)['code'] as String;
        final reason = apiErrorText(ApiException(statusCode: 403, message: '', code: code, body: c.refusal));
        expect(p.failureReason, reason);
        expect(find.text(reason), findsOneWidget);
        expect(find.text('enroll_refused_title'.tr), findsOneWidget);
        expect(find.text('enroll_refused_back'.tr), findsOneWidget);
        expect(find.text('try_again_payment'.tr), findsNothing);
        expect(find.text('payment_failed_message_generic'.tr), findsNothing);
        expect(find.text('payment_session_create_failed'.tr), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }

  testWidgets('the refusal page: no layout errors', (tester) async {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    final api = _api(paid: false, path: '/api/v1/courses/41/enroll', refusal: _refusal('quran_gender_rule', {'reason': 'gender_unknown'}))
      ..install();
    addTearDown(api.uninstall);
    await expectNoLayoutErrors(
      tester,
      () => EnrollmentScreen(course: _course(false)),
      frames: 6,
      act: (tester) async {
        final ctx = tester.element(find.byType(EnrollScaffold));
        unawaited(ctx.read<EnrollmentProvider>().confirm(ctx));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(ctx.read<EnrollmentProvider>().refused, isTrue);
      },
    );
  });
}
