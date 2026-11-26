// VISUAL review renders of the redesigned T2 teacher pages (Tea2Analysis, Tea2Money, Tea2Account devices,
// Tea2Certs, Tea2Teach): 390x844 and 1360x900, Arabic and English, light, CAST demo data
// (test/support/redesign/t2_fakes.dart). Compared by eye with D:/platform/redesign-ref/ref/teacher/*.png. Not a CI
// suite.
//
//   flutter test test/visual/redesign/t2/t2_screens_golden_test.dart --update-goldens [--plain-name payouts]
@Tags(['visual'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/analytics/teacher/flags/teacher_read_flags_screen.dart';
import 'package:flutter_education_app/features/certificates/certificate_requests_screen.dart';
import 'package:flutter_education_app/features/certificates/designer/certificate_designs_screen.dart';
import 'package:flutter_education_app/features/profile/teacher/payout/teacher_payouts_screen.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_screen.dart';
import 'package:flutter_education_app/features/quran/quran_teacher_hub.dart';
import 'package:flutter_education_app/features/store/manage/store_manage_pages.dart';
import 'package:flutter_education_app/features/teachers/teacher_onboarding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_api.dart';
import '../../../support/redesign/t2_fakes.dart';
import '../../../ui/teachers_models_test.dart' show packageJson, profileJson;
import '../kit_golden_harness.dart';

Map<String, FakeHandler> _extra() => {
      'GET /api/v1/me/teacher-profile': (_) => {...profileJson(), 'name': 'أ. ماجد الشهري', 'subjects': ['tahsili', 'qudurat']},
      'GET /api/v1/me/packages': (_) => [packageJson(), packageJson(seatsTaken: 10, overbook: 'none')],
      'GET /api/v1/me/quran/teacher-profile': (_) => {
            'user_id': 7,
            'name': 'أ. ماجد الشهري',
            'gender': 'm',
            'status': 'published',
            'courses': [
              {'id': 24, 'name_ar': 'حلقة الفجر', 'name_en': 'Dawn circle', 'fees': 100, 'currency': 'SAR', 'delivery_mode': 'online'},
              {'id': 25, 'name_ar': 'تثبيت جزء عم', 'name_en': 'Juz Amma revision', 'fees': 80, 'currency': 'SAR', 'delivery_mode': 'online'},
            ],
          },
      'GET /api/v1/quran/meta': (_) => {'surahs': <dynamic>[], 'juz': <dynamic>[], 'total_ayahs': 6236},
      'GET /api/v1/edu/countries': (_) => <dynamic>[],
    };

void main() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  Future<void> render(WidgetTester tester, String name, Widget Function() build) async {
    await t2SetUp(t2Api(extra: _extra()));
    await kitRender(
      tester,
      't2/$name',
      () => ChangeNotifierProvider<TeacherDeviceRequestsProvider>(create: (_) => TeacherDeviceRequestsProvider(), child: build()),
      storage: storage,
      modes: const [false],
      scaffold: false,
    );
  }

  testWidgets('t2 flags', (t) => render(t, 'flags', () => const TeacherReadFlagsScreen(courseId: 41, courseTitle: 'الرياضيات ٣ ث، أ')));
  testWidgets('t2 payouts', (t) => render(t, 'payouts', () => const TeacherPayoutsScreen()));
  testWidgets('t2 devices', (t) => render(t, 'devices', () => const TeacherDeviceRequestsScreen()));
  testWidgets('t2 cert requests', (t) => render(t, 'cert_requests', () => const CertificateRequestsScreen()));
  testWidgets('t2 cert designs', (t) => render(t, 'cert_designs', () => const CertificateDesignsScreen()));
  testWidgets('t2 ads', (t) => render(t, 'ads', () => const TeacherAdsPage()));
  testWidgets('t2 store', (t) => render(t, 'store', () => const StoreManagePage()));
  testWidgets('t2 teach hub', (t) => render(t, 'teach_hub', () => const TeacherHubPage()));
  testWidgets('t2 quran', (t) => render(t, 'quran', () => const QuranTeacherHubPage()));
}
