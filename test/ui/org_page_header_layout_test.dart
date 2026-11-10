// The organization dashboard's page header (org_page_header.dart, D-103) and its staff-only page: no overflow at
// 320x640 and 1400x900, Arabic and English, text x1.3 — with a long organization name, a subtitle, a primary
// action, the switcher sheet open, and without an organization / refresh scope.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_keyboard.dart' show AppCommandPaletteScope;
import 'package:flutter_education_app/design/context_switcher.dart' show ContextPill;
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

  testWidgets('pushed page: Back + long name + subtitle + Edit, its own refresh, the pill on a phone', (tester) async {
    final refresh = OrgPageRefresh();
    addTearDown(refresh.dispose);
    final session = _session();
    await expectNoLayoutErrors(
      tester,
      () => _wrap(
        OrgPushedPage(
          title: 'Computer Science Department Council — undergraduate and postgraduate programmes',
          subtitle: 'Service department · CSDC · Part of the Faculty of Engineering, Technology and Computer Science',
          refresh: refresh,
          primaryAction: OrgHeaderButton(icon: Icons.edit_rounded, label: 'Edit', onTap: () {}),
          child: ListView(children: const [SizedBox(height: 900)]),
        ),
        session: session,
      ),
      act: (tester) async {
        expect(find.byKey(const ValueKey('org.header.back')), findsOneWidget);
        expect(find.byKey(const ValueKey('org.header.switcher')), findsOneWidget);
      },
    );
  });

  testWidgets('narrow one-row header (600–1040 px): Back + primary action + Search + Refresh + pill fit, "Updated" under the title',
      (tester) async {
    final refresh = OrgPageRefresh();
    addTearDown(refresh.dispose);
    final session = _session();
    final prevLang = AppConfig.lang;
    addTearDown(() {
      AppConfig.lang = prevLang;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    // the harness only pumps 320 and 1400 px: this row's width band is set here, at the harness's 1.3 text scale
    for (final w in [600.0, 633.0, 753.0, 820.0, 900.0, 979.0, 1040.0, 1160.0]) {
      for (final lang in layoutLangs) {
        AppConfig.lang = lang;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 700);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(layoutHost(_wrap(
          AppCommandPaletteScope(
            onOpen: () {},
            child: Column(children: [
              OrgPageHeader(
                title: 'Computer Science Department Council — undergraduate and postgraduate programmes',
                subtitle: 'Service department · CSDC',
                back: true,
                primaryAction: OrgHeaderButton(icon: Icons.add_rounded, label: 'New request', onTap: () {}),
              ),
              const Expanded(child: SizedBox()),
            ]),
          ),
          session: session,
          refresh: refresh,
        )));
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull, reason: 'layout error at $w / $lang');
        expect(find.byKey(const ValueKey('org.header.search')), findsOneWidget);
        expect(find.byKey(const ValueKey('org.header.updated')), findsOneWidget);
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('pill: one line, two lines, then the mark alone — never an overflow', (tester) async {
    const name = 'Faculty of Engineering, Technology and Computer Science — Nile National University';
    for (final w in [100.0, 180.0, 280.0]) {
      await expectNoLayoutErrors(
        tester,
        () => Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(
            width: w,
            child: ContextPill(icon: Icons.account_balance_rounded, tone: Colors.teal, label: name, onTap: () {}),
          ),
        ),
        act: (tester) async {
          // below the threshold the name is in the tooltip / screen-reader label only
          expect(find.text(name), w < ContextPill.markOnlyBelow ? findsNothing : findsOneWidget);
          expect(find.byTooltip(name), findsOneWidget);
        },
      );
    }
  });

  testWidgets('staff-only page', (tester) async {
    await expectNoLayoutErrors(tester, () => const OrgStaffOnlyPage());
  });
}
