// VISUAL review renders of the organization home (D-103) and the department page with the server's tabs: the REAL
// OrgHomePage over the real OrgDashController on a fake server (one GET …/dashboard shaped like the spec's payload,
// test/ui/org_home_v3_layout_test.dart), the admin (insights_first) and the member (actions_first) homes, an empty
// member home, and the department page for an admin (Waiting first, every tab) and a member (Team · News · Library).
// Real fonts, 390x844 and 1440x900, ar / en, light / dark, into test/visual/goldens/org_home_v3_*.png. Not a CI
// suite; compared by eye.
//
//   flutter test test/visual/org_home_v3_golden_test.dart --update-goldens [--plain-name admin]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/home/org_home_logic.dart' show OrgDeptTab;
import 'package:flutter_education_app/features/org/org_dashboard_home.dart';
import 'package:flutter_education_app/features/org/org_dashboard_screen.dart' show OrgTabs;
import 'package:flutter_education_app/features/org/org_department_dashboard.dart';
import 'package:flutter_education_app/features/org/org_page_header.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/org_home_v3_layout_test.dart' show adminPayload, deptPayload, emptyMemberPayload, memberPayload, session;
import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(
        key: _shot,
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: context.colors.background,
            // a desktop window: the shell's sidebar takes ~260 px, the page card is centred at most 1100 wide
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, box) => box.maxWidth >= 1000
                    ? Row(children: [
                        Container(width: 260, color: context.colors.cardBg),
                        Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: child))),
                      ])
                    : child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

/// The real Home: session · dashboard controller (loads from the fake server) · sections · the page's refresh scope.
Widget _home({required bool admin}) {
  final s = session(admin: admin);
  final dash = OrgDashController()..ensure(s);
  final tabs = OrgTabs()
    ..keys = admin ? const ['home', 'people', 'academics', 'timetable', 'services', 'settings'] : const ['home', 'settings'];
  final refresh = OrgPageRefresh();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider()),
      ChangeNotifierProvider<OrgSession>.value(value: s),
      ChangeNotifierProvider<OrgDashController>.value(value: dash),
      ChangeNotifierProvider<OrgTabs>.value(value: tabs),
    ],
    child: OrgPageRefreshScope(controller: refresh, child: const OrgHomePage()),
  );
}

Map<String, dynamic> _adminDept() => {
      ...deptPayload(),
      'unit': {'id': 1, 'unit_type': 'dept', 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs', 'color': '#2563EB', 'icon': 'support',
        'location': 'Main building, ground floor', 'office_hours': 'Sun–Thu 9:00–15:00', 'email': 'students@nile.edu.eg'},
      'manager': {'id': 5, 'name': 'Mona Adel'},
      'can': {'view_team': true, 'manage_team': true, 'view_users': true, 'remove_users': true, 'decide_requests': true, 'configure_join': true,
        'view_forms': true, 'review_forms': true, 'edit_unit': true},
      'stats': {'users': 1240, 'staff': 4, 'courses': 6, 'pending_join_requests': 2, 'pending_forms': 1, 'pending_program_choices': 0},
      'requests': [
        {'id': 31, 'user': {'id': 52, 'name': 'Ahmed Ali', 'email': 'ahmed.ali@nile.edu.eg'}, 'created_at': '2026-10-29T08:00:00', 'via': 'code', 'answers': {'Student ID': '20231187'}},
        {'id': 32, 'user': {'id': 53, 'name': 'Nour Hassan', 'email': 'nour.h@nile.edu.eg'}, 'created_at': '2026-10-30T14:00:00', 'answers': {}},
      ],
      'forms': [
        {'id': 77, 'form_title': 'Enrollment certificate', 'user': {'id': 60, 'name': 'Mona Adel'}, 'ref': 'REQ-0077', 'status': 'submitted', 'created_at': '2026-10-31T06:00:00', 'answers': {'Purpose': 'Scholarship application'}},
      ],
    };

Widget _dept({required bool admin}) {
  final unit = admin
      ? (adminPayload()['departments'] as List).first as Map<String, dynamic>
      : (memberPayload()['departments'] as List).first as Map<String, dynamic>;
  return ChangeNotifierProvider<OrgSession>.value(
    value: session(admin: admin),
    child: OrgDepartmentDashboard(unitType: 'dept', unitId: asIntOf(unit['id']), seed: unit, tabs: OrgDeptTab.listFrom(unit['tabs'])),
  );
}

int asIntOf(dynamic v) => v is int ? v : int.parse('$v');

void main() {
  late FakeApi fake;
  var homePayload = adminPayload();

  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
    fake = FakeApi({
      'GET /api/v1/org/orgs/4/dashboard': (_) => homePayload,
      'GET /api/v1/org/orgs/4/units/dept/1/dashboard': (_) => _adminDept(),
      'GET /api/v1/org/orgs/4/units/dept/3/dashboard': (_) => deptPayload(),
    }, latency: Duration.zero, fallback: (_) => {'items': const [], 'total': 0});
    fake.install();
  });

  tearDown(() => fake.uninstall());

  testWidgets('org home admin', (t) {
    homePayload = adminPayload();
    return _render(t, 'org_home_v3_admin', () => _home(admin: true));
  });
  testWidgets('org home member', (t) {
    homePayload = memberPayload();
    return _render(t, 'org_home_v3_member', () => _home(admin: false));
  });
  testWidgets('org home empty', (t) {
    homePayload = emptyMemberPayload();
    return _render(t, 'org_home_v3_empty', () => _home(admin: false));
  });
  testWidgets('org dept admin', (t) => _render(t, 'org_home_v3_dept_admin', () => _dept(admin: true)));
  testWidgets('org dept member', (t) => _render(t, 'org_home_v3_dept_member', () => _dept(admin: false)));
}
