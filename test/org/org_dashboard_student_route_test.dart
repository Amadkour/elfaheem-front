// The organization dashboard opened by a student (D-103, "dashboard only"): the real screen over the fake backend
// lands on "This dashboard is for staff", and its button leads back to the person's own home. Two ways in: a student
// whose organizations are all student memberships, and a staff member whose role became student while the dashboard
// was open (the server answers 403 student_forbidden, the session reloads /org/mine). The web build never shows this
// page (a typed URL is redirected home by web_entry_route.dart); phones reach it through a stale notification or an
// attention item, so this is where it is checked end to end. Its own file = its own isolate (fresh singletons).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/features/org/org_dashboard_screen.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../perf/home_requests_harness.dart' show homeRoutes;
import '../support/fake_api.dart';

const _org = {'id': 1, 'status': 'approved', 'type': 'faculty', 'name_ar': 'كلية', 'name_en': 'Agg U'};

final _studentOverview = {
  'items': [
    {
      'organization': _org,
      'roles': ['student'],
      'manage': null,
      'todo': {'total': 0},
      'approvals': {'total': 0},
      'news': 0,
    },
  ],
  'default_org_id': 1,
  'suggested_mode': 'organization',
  'pending_total': 0,
};

Future<FakeApi> _open(WidgetTester tester, {required String role, required Map<String, FakeHandler> routes}) async {
  translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  SharedPreferences.setMockInitialValues({});
  mockRequestPlugins();
  AppConfig.lang = 'en';
  final storage = await StorageService.getInstance();
  await storage.saveUser({'id': 7, 'name': 'Test User', 'gmail': 'user@example.com', 'role': role});
  final api = FakeApi({...homeRoutes(memberOfOrg: true), ...routes}, fallback: (_) => const <String, dynamic>{})
    ..install();
  addTearDown(api.uninstall);
  AppModeController.applyContext = (_) {};
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final theme = ThemeConfigProvider(api: ApiClient());
  Widget home(BuildContext _) => const Scaffold(body: Text('my own home'));
  await tester.pumpWidget(MultiProvider(
    providers: appProviders(storage: storage, api: ApiClient()),
    child: ThemeConfigScope(
      provider: theme,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        initialRoute: '/org_dashboard',
        routes: {'/': home, '/dashboard': home, '/org_dashboard': (_) => const OrgDashboardScreen()},
      ),
    ),
  ));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return api;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 70; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('a student lands on "This dashboard is for staff" and goes back home with one tap', (tester) async {
    await _open(tester, role: 'student', routes: {
      'GET /api/v1/org/mine': (_) => {'items': [], 'can_create_root': false},
      'GET /api/v1/org/public/me/overview': (_) => _studentOverview,
    });
    expect(find.text('This dashboard is for staff'), findsOneWidget);
    expect(find.byType(OrgStaffOnlyPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('org.staff_only.home')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('my own home'), findsOneWidget);
    expect(find.byType(OrgDashboardScreen), findsNothing);
    await _settle(tester);
  });

  testWidgets('a role changed to student while the dashboard is open: 403 student_forbidden → the staff-only page',
      (tester) async {
    var student = false;
    await _open(tester, role: 'org-staff', routes: {
      'GET /api/v1/org/mine': (_) => {
            'items': [
              if (!student) {..._org, 'my_role': 'teacher', 'access': 'staff', 'member_role': 'teacher', 'permissions': {}},
            ],
            'can_create_root': false,
          },
      'GET /api/v1/org/public/me/overview': (_) => _studentOverview,
      'GET /api/v1/org/orgs/1/dashboard': (_) => student
          ? const FakeResponse(403, {
              'detail': {'code': 'student_forbidden', 'message': 'لوحة المؤسسة لفريق العمل فقط'},
            })
          : {...(jsonDecode(File('test/fixtures/payloads/org_dashboard.json').readAsStringSync()) as Map), 'access': 'staff'},
    });
    expect(find.byType(OrgStaffOnlyPage), findsNothing);

    student = true; // the membership became a student one; the next org call says so
    final refresh = find.byTooltip('Refresh');
    expect(refresh, findsWidgets);
    await tester.tap(refresh.first);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('This dashboard is for staff'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _settle(tester);
  });
}
