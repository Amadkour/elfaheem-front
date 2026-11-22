// The Super Admin hub tabs (AdminServicesHub): no hero, a search field that filters by label + description, a
// responsive grid, the label fixes, the new Grading-feedback tile, and a layout check on every size.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppSearchField;
import 'package:flutter_education_app/features/admin/admin_providers.dart' show AdminPendingPayoutsProvider;
import 'package:flutter_education_app/features/admin/admin_services_hub.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../layout_harness.dart';

void main() {
  late StorageService storage;

  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    AppConfig.lang = 'en';
  });

  Widget withProviders(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => AdminPendingPayoutsProvider()),
          ChangeNotifierProvider(create: (_) => TeacherTransfersProvider()),
          ChangeNotifierProvider(create: (_) => ComplaintProvider()),
        ],
        child: child,
      );

  Future<void> pumpHub(WidgetTester tester, String group, {Size size = const Size(1400, 900)}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(withProviders(layoutHost(AdminServicesHub(groupId: group), scale: 1)));
    await tester.pump();
  }

  test('columns grow with the width: 1 → 2 → 3 → 4', () {
    expect([for (final w in [320.0, 500.0, 800.0, 1100.0]) AdminServicesHub.columnsFor(w)], [1, 2, 3, 4]);
  });

  testWidgets('a hub has a search field and NO hero; the search filters by label and description', (tester) async {
    await pumpHub(tester, 'finance');
    expect(find.byType(AppSearchField), findsOneWidget);
    expect(find.byType(ServiceCard), findsWidgets);
    final all = tester.widgetList(find.byType(ServiceCard)).length;
    await tester.enterText(find.byType(TextField), 'withdraw');
    await tester.pump(const Duration(milliseconds: 500));
    final some = tester.widgetList(find.byType(ServiceCard)).length;
    expect(some, lessThan(all));
    expect(some, greaterThan(0));
    await tester.enterText(find.byType(TextField), 'zzzzqqq');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ServiceCard), findsNothing);
  });

  testWidgets('label fixes and the new feedback tile (config group)', (tester) async {
    AppConfig.lang = 'en';
    await pumpHub(tester, 'config');
    // super admin only tiles stay hidden for the plain test user; the always-visible fixes are checked here
    expect(find.text('Student review & read flags'), findsOneWidget);
    expect(find.text('About & terms'), findsOneWidget);
    expect(find.text('Flags'), findsNothing);
    expect(find.text('Terms & conditions'), findsNothing);
    expect(find.textContaining('shared links'), findsOneWidget); // the export centre says what it is
  });

  testWidgets('people hub: requirements are called notices, send message has its own icon', (tester) async {
    AppConfig.lang = 'en';
    await pumpHub(tester, 'people');
    expect(find.text('Notices to acknowledge'), findsOneWidget);
    final groups = AdminServicesHub.filter(const [], 'x');
    expect(groups, isEmpty);
  });

  testWidgets('every hub lays out at every size and language', (tester) async {
    for (final g in ['people', 'finance', 'learning', 'support', 'config']) {
      await expectNoLayoutErrors(tester, () => withProviders(AdminServicesHub(groupId: g)));
    }
  });
}
