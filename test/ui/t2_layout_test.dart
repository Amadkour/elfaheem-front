// Redesign group T2 (teacher: analysis, money, certificates, exams, teaching) on a phone and a wide window, ar / en,
// text 1.3, over the CAST demo data (test/support/redesign/t2_fakes.dart): every rebuilt page with its hero, the
// sheets of the payouts page, the wizards' step cards, and the shared T2 frame pieces.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/analytics/teacher/analytics_hub_screen.dart';
import 'package:flutter_education_app/features/analytics/teacher/flags/teacher_read_flags_screen.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/certificates/certificate_requests_screen.dart';
import 'package:flutter_education_app/features/certificates/designer/certificate_designs_screen.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/payout/teacher_payouts_screen.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_screen.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart';
import 'package:flutter_education_app/features/quran/quran_teacher_hub.dart';
import 'package:flutter_education_app/features/store/manage/store_manage_pages.dart';
import 'package:flutter_education_app/features/teachers/teacher_onboarding.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_api.dart';
import '../support/redesign/t2_fakes.dart';
import 'layout_harness.dart';
import 'teachers_models_test.dart' show packageJson, profileJson;

Map<String, FakeHandler> _extra() => {
      'GET /api/v1/me/teacher-profile': (_) => profileJson(),
      'GET /api/v1/me/packages': (_) => [packageJson(), packageJson(seatsTaken: 10, overbook: 'none')],
      'GET /api/v1/me/quran/teacher-profile': (_) => {
            'user_id': 7,
            'name': 'ماجد الشهري',
            'gender': 'm',
            'status': 'published',
            'courses': [
              {'id': 24, 'name_ar': 'حلقة الفجر', 'name_en': 'Dawn circle', 'fees': 100, 'currency': 'SAR', 'delivery_mode': 'online'},
            ],
          },
      'GET /api/v1/quran/meta': (_) => {'surahs': <dynamic>[], 'juz': <dynamic>[], 'total_ayahs': 6236},
      'GET /api/v1/edu/countries': (_) => <dynamic>[],
    };

void main() {
  late MyAuthProvider auth;

  setUp(() async {
    AppConfig.lang = 'ar';
    auth = await t2SetUp(t2Api(extra: _extra()));
  });

  Widget host(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<MyAuthProvider>.value(value: auth),
          ChangeNotifierProvider<TeacherCoursesProvider>(create: (_) => T2CoursesProvider()),
          ChangeNotifierProvider<TeacherDeviceRequestsProvider>(create: (_) => TeacherDeviceRequestsProvider()),
        ],
        child: child,
      );

  Future<void> page(WidgetTester t, Widget Function() build) =>
      expectNoLayoutErrors(t, () => host(build()), scaffold: false, frames: 8);

  testWidgets('analytics hub', (t) => page(t, () => const TeacherAnalyticsHubScreen()));
  testWidgets('hard questions', (t) => page(t, () => const TeacherReadFlagsScreen(courseId: 41, courseTitle: 'الرياضيات ٣ ث، أ')));
  testWidgets('earnings and withdrawals', (t) => page(t, () => const TeacherPayoutsScreen()));
  testWidgets('device change requests', (t) => page(t, () => const TeacherDeviceRequestsScreen()));
  testWidgets('certificate requests', (t) => page(t, () => const CertificateRequestsScreen()));
  testWidgets('certificate designs', (t) => page(t, () => const CertificateDesignsScreen()));
  testWidgets('my ads', (t) => page(t, () => const TeacherAdsPage()));
  testWidgets('my store items', (t) => page(t, () => const StoreManagePage()));
  testWidgets('teacher profile and packages', (t) => page(t, () => const TeacherHubPage()));
  testWidgets('Quran teaching', (t) => page(t, () => const QuranTeacherHubPage()));

  testWidgets('payouts: the request and the account sheets open', (t) async {
    await expectNoLayoutErrors(t, () => host(const TeacherPayoutsScreen()), scaffold: false, frames: 8, act: (t) async {
      final request = find.byKey(const ValueKey('teacher_payouts.request'));
      // an open request blocks a second one: the sheet is reached through "Add" instead
      expect(request, findsOneWidget);
      final add = find.byKey(const ValueKey('teacher_payouts.add_account'));
      await t.ensureVisible(add);
      await t.tap(add);
    });
  });

  testWidgets('T2 frame pieces', (t) async {
    await expectNoLayoutErrors(
      t,
      () => T2Scope(
        child: SingleChildScrollView(
          child: Column(children: [
            T2Steps(labels: const ['الملف', 'المواد والمؤهلات', 'المستندات', 'المراجعة'], index: 1, onTap: (_) {}),
            T2TileGrid(children: [
              for (var i = 0; i < 4; i++)
                T2InsightTile(icon: Icons.star_outline_rounded, title: 'أقوى فصل: قدرات كمي $i', subtitle: 'تقدّم 79%', link: 'التفاصيل', onTap: () {}),
            ]),
          ]),
        ),
      ),
    );
  });
}
