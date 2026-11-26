// Review renders of the parent's Children pages (Pa2Kids: list, detail, course, locked, consent, revoke) with the CAST
// family, 390x844 and 1360x900, next to D:/platform/redesign-ref/ref/parent/005_* … 013_*. Not a CI suite.
//
//   flutter test test/visual/redesign/pa/pa_kids_golden_test.dart --update-goldens [--plain-name detail]
@Tags(['visual'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
import 'package:flutter_education_app/features/parent/pa_child_pages.dart';
import 'package:flutter_education_app/features/parent/parent_consent.dart';
import 'package:flutter_education_app/features/parent/parent_dashboard_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/redesign/pa_fakes.dart';
import '../kit_golden_harness.dart';
import 'pa_golden_harness.dart';

void main() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  Future<void> kidsTab(WidgetTester t) => paTap(t, const ValueKey('nav.children'));

  testWidgets('pa kids list', (t) => paRender(t, 'kids', () => const ParentDashboardScreen(), storage: storage, act: (t) async {
        await t.tap(find.text(t.any(find.text('الأبناء')) ? 'الأبناء' : 'Children').last, warnIfMissed: false);
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }));
  testWidgets('pa kids detail', (t) => paRender(t, 'kid_detail', () => const ParentChildPage(childId: paReem), storage: storage, pushed: true));
  testWidgets('pa kids course', (t) => paRender(t, 'kid_course', () => ParentChildCoursePage(
        childId: paReem,
        childName: 'ريم العنزي',
        course: DlCourseBlock.fromJson((paProfile(paReem)['courses'] as List).first as Map<String, dynamic>),
      ), storage: storage, pushed: true));
  testWidgets('pa kids locked', (t) => paRender(t, 'kid_locked', () => ConsentRequiredView(childName: 'سارة العنزي', onGive: () {}), storage: storage, pushed: true));
  testWidgets('pa kids consent', (t) => paRender(t, 'kid_consent', () => Builder(builder: (c) => GestureDetector(
        key: const ValueKey('open'), onTap: () => showParentConsentDialog(c, childName: 'سارة العنزي', grade: 'الصف الرابع الابتدائي'),
        child: const SizedBox.expand())), storage: storage, pushed: true, grow: false, langs: const ['ar'], act: (t) => paTap(t, const ValueKey('open'))));
  testWidgets('pa kids revoke', (t) => paRender(t, 'kid_revoke', () => Builder(builder: (c) => GestureDetector(
        key: const ValueKey('open'), onTap: () => revokeParentConsentFlow(c, paReem, 'ريم العنزي'),
        child: const SizedBox.expand())), storage: storage, pushed: true, grow: false, langs: const ['ar'],
        api: paApi(extra: {'GET /api/v1/parent/children/$paReem/consent': (_) => {'granted': true}}), act: (t) => paTap(t, const ValueKey('open'))));
  // keeps the helper referenced (tab keys differ per shell kind)
  test('helper', () => kidsTab);
}
