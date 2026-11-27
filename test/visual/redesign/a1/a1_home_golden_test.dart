// VISUAL review renders of redesign group A1 (admin): the home (admin and super admin), the hubs, the requests
// inbox and the analytics: 390x844 and 1360x900, Arabic (and English for the main states), light, CAST demo data
// (test/support/redesign/a1_fakes.dart). Compared by eye with D:/platform/redesign-ref/ref/admin/*.png and
// ref/super/001_SupHome*, 005_SupHome*. Not a CI suite.
//
//   flutter test test/visual/redesign/a1/a1_home_golden_test.dart --update-goldens [--plain-name inbox]
@Tags(['visual'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/admin/admin_analytics_page.dart';
import 'package:flutter_education_app/features/admin/admin_home_body.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_education_app/features/admin/admin_providers.dart' show AdminPendingPayoutsProvider;
import 'package:flutter_education_app/features/admin/admin_services_hub.dart';
import 'package:flutter_education_app/features/admin/approvals/admin_approvals_inbox.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_api.dart';
import '../../../support/redesign/a1_fakes.dart';
import '../kit_golden_harness.dart';

Widget _providers(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AdminPendingPayoutsProvider()),
        ChangeNotifierProvider(create: (_) => TeacherTransfersProvider()),
        ChangeNotifierProvider(create: (_) => TeacherDeviceRequestsProvider()),
        ChangeNotifierProvider(create: (_) => ComplaintProvider()),
      ],
      child: child,
    );

void main() {
  late StorageService storage;

  Future<void> render(WidgetTester tester, String name, Widget Function() build,
      {String role = 'admin', List<String> langs = const ['ar', 'en'], bool grow = true}) async {
    storage = await kitGoldenSetUp();
    await a1SignIn(role: role);
    mockRequestPlugins();
    final fake = FakeApi(a1Routes(), latency: const Duration(milliseconds: 10))..install();
    addTearDown(fake.uninstall);
    await kitRender(tester, 'a1/$name', () => _providers(build()),
        storage: storage, modes: const [false], langs: langs, grow: grow, scaffold: false);
  }

  final data = AdminHomeData.fromOverview(a1Overview());
  final actions = AdminHomeActions(
    openAlert: (_) {},
    openStudents: () {},
    openIncome: () {},
    openViewAs: () {},
    openAnalytics: () {},
    addStudent: () {},
    sendMessage: () {},
    exportData: () {},
    addCourse: () {},
  );

  testWidgets('a1 home admin', (t) => render(t, 'home_admin', () => AdminHomeBody(data: data, name: 'سلمان الدوسري', actions: actions, updatedAt: DateTime.now())));
  testWidgets('a1 home super',
      (t) => render(t, 'home_super', () => AdminHomeBody(data: data, name: 'م. سلطان الدوسري', pendingPayouts: 7, actions: actions), role: 'super-admin', langs: const ['ar']));
  testWidgets('a1 hub people', (t) => render(t, 'hub_people', () => const AdminServicesHub(groupId: 'people'), langs: const ['ar']));
  testWidgets('a1 hub approvals', (t) => render(t, 'hub_approvals', () => const AdminServicesHub(groupId: 'approvals'), langs: const ['ar']));
  testWidgets('a1 hub learning', (t) => render(t, 'hub_learning', () => const AdminServicesHub(groupId: 'learning'), langs: const ['ar']));
  testWidgets('a1 hub support', (t) => render(t, 'hub_support', () => const AdminServicesHub(groupId: 'support'), langs: const ['ar']));
  testWidgets('a1 inbox', (t) => render(t, 'inbox', () => const AdminApprovalsInboxPage(), grow: false));
  testWidgets('a1 analytics', (t) => render(t, 'analytics', () => AdminAnalyticsPage(data: data), role: 'super-admin', grow: false));
}
