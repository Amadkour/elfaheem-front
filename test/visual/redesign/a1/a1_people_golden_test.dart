// VISUAL review renders of redesign group A1, people: the students and teachers lists and the new-account sheet,
// 390x844 and 1360x900, CAST demo data. Compared by eye with D:/platform/redesign-ref/ref/admin/005*, 011*, 014*.
// Not a CI suite.
//
//   flutter test test/visual/redesign/a1/a1_people_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/features/admin/admin_users_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_api.dart';
import '../../../support/redesign/a1_fakes.dart';
import '../kit_golden_harness.dart';

void main() {
  Future<void> render(WidgetTester tester, String name, Widget Function() build,
      {List<String> langs = const ['ar'], Future<void> Function(WidgetTester t)? act}) async {
    final storage = await kitGoldenSetUp();
    await a1SignIn();
    mockRequestPlugins();
    final fake = FakeApi(a1Routes(), latency: const Duration(milliseconds: 10))..install();
    addTearDown(fake.uninstall);
    await kitRender(tester, 'a1/$name', build, storage: storage, modes: const [false], langs: langs, grow: false, scaffold: false, act: act);
  }

  testWidgets('a1 students', (t) => render(t, 'students', () => const AdminUsersPage(role: 'student', embedded: true), langs: const ['ar', 'en']));
  testWidgets('a1 teachers', (t) => render(t, 'teachers', () => const AdminUsersPage(role: 'teacher', embedded: true)));
  // the new-account sheet opens in the root overlay, outside the captured boundary: its layout is in the A1 tests
}
