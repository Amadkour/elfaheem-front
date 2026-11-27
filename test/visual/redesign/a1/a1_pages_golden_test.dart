// VISUAL review renders of redesign group A1: the admin pages moved onto the frame (parent linking, send message,
// categories, device settings, data center, accounts waiting, exports): 390x844 and 1360x900, Arabic, light, CAST
// demo data. Compared by eye with D:/platform/redesign-ref/ref/admin/0{29,30,35,40,49,50,52}*. Not a CI suite.
//
//   flutter test test/visual/redesign/a1/a1_pages_golden_test.dart --update-goldens [--plain-name devices]
@Tags(['visual'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/features/admin/admin_account_approval.dart';
import 'package:flutter_education_app/features/admin/admin_categories_page.dart';
import 'package:flutter_education_app/features/admin/admin_datacenter_page.dart';
import 'package:flutter_education_app/features/admin/admin_devices_page.dart';
import 'package:flutter_education_app/features/admin/admin_parent_linking_page.dart';
import 'package:flutter_education_app/features/admin/admin_send_message_page.dart';
import 'package:flutter_education_app/features/exports/exports_center_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_api.dart';
import '../../../support/redesign/a1_fakes.dart';
import '../kit_golden_harness.dart';

void main() {
  Future<void> render(WidgetTester tester, String name, Widget Function() build) async {
    final storage = await kitGoldenSetUp();
    await a1SignIn();
    mockRequestPlugins();
    final fake = FakeApi(a1Routes(), latency: const Duration(milliseconds: 10))..install();
    addTearDown(fake.uninstall);
    await kitRender(tester, 'a1/$name', build, storage: storage, modes: const [false], langs: const ['ar'], grow: false, scaffold: false);
  }

  testWidgets('a1 parent linking', (t) => render(t, 'parent_linking', () => const AdminParentLinkingPage()));
  testWidgets('a1 send message', (t) => render(t, 'send_message', () => const AdminSendMessagePage()));
  testWidgets('a1 categories', (t) => render(t, 'categories', () => const AdminCategoriesPage()));
  testWidgets('a1 devices', (t) => render(t, 'devices', () => const AdminDevicesPage()));
  testWidgets('a1 data center', (t) => render(t, 'datacenter', () => const DataCenterPage()));
  testWidgets('a1 accounts', (t) => render(t, 'accounts', () => const AdminPendingAccountsPage()));
  testWidgets('a1 exports', (t) => render(t, 'exports', () => const ExportsCenterPage(admin: true)));
}
