// The organization dashboard's page header (org_page_header.dart, D-103) and its staff-only page: no overflow at
// 320x640 and 1400x900, Arabic and English, text x1.3 — with a long organization name, a subtitle, a primary
// action, the switcher sheet open, and without an organization / refresh scope.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/org_dashboard_screen.dart' show OrgStaffOnlyPage;
import 'package:flutter_education_app/features/org/org_page_header.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

OrgSession _session() => OrgSession()
  ..loaded = true
  ..items = [
    {
      'id': 4,
      'name_ar': 'كلية الهندسة والتكنولوجيا وعلوم الحاسب بجامعة النيل الأهلية',
      'name_en': 'Faculty of Engineering, Technology and Computer Science — Nile National University',
      'type': 'faculty',
      'status': 'approved',
      'my_role': 'org_admin',
      'access': 'admin',
      'depth': 0,
    },
    {'id': 9, 'name_ar': 'قسم الحاسب', 'name_en': 'Computer department', 'type': 'department', 'depth': 1,
        'status': 'approved', 'access': 'member', 'member_role': 'teacher'},
  ]
  ..currentId = 4;

Widget _wrap(Widget child, {OrgSession? session, OrgPageRefresh? refresh}) {
  Widget w = child;
  if (refresh != null) w = OrgPageRefreshScope(controller: refresh, child: w);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider()),
      if (session != null) ChangeNotifierProvider<OrgSession>.value(value: session),
    ],
    child: w,
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
  });

  testWidgets('header: long title + subtitle + primary action, refresh scope, organization pill', (tester) async {
    final refresh = OrgPageRefresh();
    addTearDown(refresh.dispose);
    final session = _session();
    await expectNoLayoutErrors(
      tester,
      () => _wrap(
        Column(children: [
          OrgPageHeader(
            title: 'الأعضاء والإدارات والأقسام العلمية People, departments and scientific sections',
            subtitle: 'Everyone who works or studies here, by department, with their rights and their join requests',
            primaryAction: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add member'),
            ),
          ),
          const Expanded(child: SizedBox()),
        ]),
        session: session,
        refresh: refresh,
      ),
    );
  });

  testWidgets('header: title only, no organization, no refresh scope', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _wrap(const Column(children: [OrgPageHeader(title: 'Timetable'), Expanded(child: SizedBox())])),
    );
  });

  testWidgets('header: Refresh spins, then "Updated just now"; the switcher sheet opens without overflow',
      (tester) async {
    final refresh = OrgPageRefresh();
    addTearDown(refresh.dispose);
    final session = _session();
    await expectNoLayoutErrors(
      tester,
      () => _wrap(
        const Column(children: [OrgPageHeader(title: 'Settings'), Expanded(child: SizedBox())]),
        session: session,
        refresh: refresh,
      ),
      act: (tester) async {
        expect(find.byKey(const ValueKey('org.header.updated')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('org.header.refresh')));
        await tester.pump();
        expect(refresh.generation.value, greaterThan(0));
        await tester.tap(find.byKey(const ValueKey('org.header.switcher')));
      },
    );
  });

  testWidgets('staff-only page', (tester) async {
    await expectNoLayoutErrors(tester, () => const OrgStaffOnlyPage());
  });
}
