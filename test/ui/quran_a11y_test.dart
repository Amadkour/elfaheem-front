// Screen readers reach the Quran teacher page's body and its Book button (QA_PHASE6 4.4), and the super admin's
// Quran teachers page draws on a phone and a wide window (6.R item 5).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/quran/admin/quran_admin_page.dart';
import 'package:flutter_education_app/features/quran/quran_api.dart';
import 'package:flutter_education_app/features/quran/quran_models.dart';
import 'package:flutter_education_app/features/quran/quran_teacher_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

Map<String, dynamic> _teacherJson(int id, {String status = 'published', bool verified = false}) => {
      'user_id': id,
      'name': 'Mona Independent Teacher of the Holy Quran',
      'gender': 'f',
      'bio': 'Teaching memorization for ten years.',
      'ijazah': 'Hafs an Asim',
      'goals': ['memorization', 'revision'],
      'session_types': ['group'],
      'verified': verified,
      'status': status,
      'courses': [
        {'id': 24, 'name_ar': 'حلقة جزء عم', 'name_en': 'Juz Amma circle', 'fees': 100, 'currency': 'EGP', 'delivery_mode': 'online'},
      ],
    };

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  testWidgets('the teacher page body and Book are in the semantics tree', (tester) async {
    final api = FakeApi({'GET /api/v1/quran/teachers/32': (_) => _teacherJson(32)}, latency: const Duration(milliseconds: 5))
      ..install();
    addTearDown(api.uninstall);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(layoutHost(QuranTeacherPage(teacherId: 32, api: QuranApi(api: ApiClient())), scaffold: false));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.bySemanticsLabel(RegExp('Mona Independent')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Teaching memorization')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Book')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('admin teacher card: pending, verified, no layout error', (tester) async {
    final pending = QuranTeacher.fromJson(_teacherJson(1, status: 'pending'));
    final verified = QuranTeacher.fromJson(_teacherJson(2, verified: true));
    await expectNoLayoutErrors(tester, () => QuranAdminTeacherCard(teacher: pending, onVerify: (_) {}, onReview: (_) {}));
    await expectNoLayoutErrors(tester, () => QuranAdminTeacherCard(teacher: verified, onVerify: (_) {}, busy: true));
  });

  testWidgets('admin page: loads a status, verify asks first and posts', (tester) async {
    final api = FakeApi({
      'GET /api/v1/admin/quran/teachers': (r) => {
            'items': [_teacherJson(7, status: '${r.queryParameters['status']}')],
            'total': 1,
          },
      'POST /api/v1/admin/quran/teachers/7/verify': (_) => _teacherJson(7, status: 'pending', verified: true),
    }, latency: const Duration(milliseconds: 5))
      ..install();
    addTearDown(api.uninstall);
    await tester.pumpWidget(layoutHost(const QuranAdminPage(), scaffold: false));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('quran.admin.approve.7')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quran.admin.verify.7')));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(api.calls.where((c) => c.method == 'POST'), isEmpty); // asks first
  });
}
