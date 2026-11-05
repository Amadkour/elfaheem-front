// VISUAL review renders of the joining / people / access screens (org-flow overhaul, agent r1): the real pages over a
// fake server, 390x844 and 1440x900, ar / en, light / dark, as PNGs into $OF_RENDERS (default ../of_r1_renders).
// Not a CI suite and not goldens: files to look at.
//
//   OF_RENDERS=<dir> [OF_ONLY=390_en_light,...] flutter test test/visual/of_r1_joining_golden_test.dart [--plain-name members]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/features/org/org_access_joining.dart';
import 'package:flutter_education_app/features/org/org_access_page.dart';
import 'package:flutter_education_app/features/org/org_dashboard_screen.dart';
import 'package:flutter_education_app/features/org/org_invitations_pages.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/org_pages_samples.dart';
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

const _uni = {
  'id': 4, 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University', 'type': 'university',
  'status': 'approved', 'color': '#1F6F5C', 'my_role': 'org_admin', 'is_admin': true, 'access': 'admin', 'depth': 0,
};

bool _wanted(String variant) {
  final only = Platform.environment['OF_ONLY'];
  return only == null || only.isEmpty || only.split(',').contains(variant);
}

Map<String, dynamic> _codes() => {
      'items': [
        {'id': 1, 'code': 'NILE4K7P', 'label': 'دفعة 2026 — علوم الحاسب', 'status': 'active', 'state': 'active', 'is_active': true,
         'default_role': 'student', 'default_program_id': null, 'join_mode': 'approval', 'max_uses': 200, 'uses': 143,
         'valid_from': null, 'valid_until': '2027-01-31T00:00:00'},
        {'id': 2, 'code': 'TEACH9XQ', 'label': 'Faculty onboarding', 'status': 'active', 'state': 'active', 'is_active': true,
         'default_role': 'teacher', 'join_mode': 'auto', 'max_uses': 1, 'uses': 0, 'valid_from': null, 'valid_until': null},
        {'id': 3, 'code': 'OLD2025A', 'label': 'Open day 2025', 'status': 'revoked', 'state': 'revoked', 'is_active': false,
         'default_role': 'student', 'join_mode': 'auto', 'max_uses': null, 'uses': 61, 'valid_from': null, 'valid_until': '2025-10-01T00:00:00'},
      ],
    };

Map<String, dynamic> _roles() => {
      'items': [
        {'id': 1, 'name': 'Registrar', 'name_ar': 'مسجّل', 'name_en': 'Registrar', 'color': '#2F6FDE', 'is_system': false,
         'description': 'Student records and grades', 'holders': 3, 'inherited': false, 'permissions': {'students': ['view', 'edit'], 'academic': ['view']}},
        {'id': 2, 'name': 'Librarian', 'name_ar': 'أمين مكتبة', 'name_en': 'Librarian', 'color': '#B8860B', 'is_system': false,
         'description': '', 'holders': 1, 'inherited': false, 'permissions': {'materials': ['view', 'edit', 'delete']}},
        {'id': 3, 'name': 'Org admin', 'name_ar': 'مدير المؤسسة', 'name_en': 'Org admin', 'color': '#1F6F5C', 'is_system': true,
         'description': '', 'holders': 2, 'inherited': false, 'permissions': {}},
      ],
    };

Map<String, dynamic> _invitations() => {
      'total': 3, 'page': 1, 'size': 20, 'pages': 1,
      'items': [
        {'id': 1, 'channel': 'email', 'contact': 'nour.salem@gmail.com', 'role': 'student', 'status': 'pending',
         'created_at': '2026-11-01T09:00:00', 'expires_at': '2026-11-15T09:00:00', 'invited_by': {'name': 'Mona Adel'}, 'sent_count': 2},
        {'id': 2, 'channel': 'phone', 'contact': '+201001234567', 'role': 'teacher', 'status': 'pending',
         'created_at': '2026-11-02T09:00:00', 'expires_at': '2026-11-20T09:00:00', 'invited_by': {'name': 'Mona Adel'}, 'sent_count': 1},
        {'id': 3, 'channel': 'email', 'contact': 'karim@school.edu.eg', 'role': 'student', 'status': 'pending',
         'created_at': '2026-10-01T09:00:00', 'expires_at': '2026-10-20T09:00:00', 'invited_by': {'name': 'Mona Adel'}, 'sent_count': 1},
      ],
    };

Future<void> _save(WidgetTester tester, String name) async {
  final dir = Directory(Platform.environment['OF_RENDERS'] ?? '../of_r1_renders')..createSync(recursive: true);
  await tester.runAsync(() async {
    final b = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage();
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _render(WidgetTester tester, String name, String section, String? sub,
    {Widget Function()? push, Future<void> Function(WidgetTester)? act}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          final variant = '${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}';
          if (!_wanted(variant)) continue;
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          SharedPreferences.setMockInitialValues({});
          final storage = await StorageService.getInstance();
          await storage.saveUser({'id': 7, 'name': 'Mona Adel', 'gmail': 'mona@example.com', 'role': 'org-admin'});
          AttentionService.instance.orgTabRequest.value = OrgTabRequest(4, section, sub);
          final theme = ThemeConfigProvider(api: ApiClient());
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(MultiProvider(
            providers: appProviders(storage: storage, api: ApiClient()),
            child: ThemeConfigScope(
              provider: theme,
              child: MaterialApp(
                navigatorKey: navigatorKey,
                debugShowCheckedModeBanner: false,
                theme: theme.materialTheme(dark: false),
                darkTheme: theme.materialTheme(dark: true),
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                builder: (context, w) => Directionality(
                  textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                  child: RepaintBoundary(key: _shot, child: w!),
                ),
                home: const OrgDashboardScreen(),
              ),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (push != null) {
            final s = Provider.of<OrgSession>(navigatorKey.currentContext!, listen: false);
            navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => ChangeNotifierProvider.value(value: s, child: push())));
            for (var i = 0; i < 20; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          if (act != null) {
            await act(tester);
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          expect(tester.takeException(), isNull);
          await _save(tester, '${name}_$variant');
          await tester.pumpWidget(const SizedBox());
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(seconds: 1));
          }
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  FakeApi? fake;

  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  void install() {
    fake = FakeApi({
      'GET /api/v1/org/mine': (_) => {'items': [_uni], 'can_create_root': false},
      'GET /api/v1/org/orgs/4/dashboard': (_) => payload('org_dashboard.json'),
      'GET /api/v1/notifications': (_) => {'items': [], 'total': 0, 'unread': 3},
      'GET /api/v1/me/attention': (_) => {'counts': {}, 'total': 0, 'items': []},
      ...orgPageRoutes(),
      'GET /api/v1/org/orgs/4/members': (o) {
        final role = '${o.queryParameters['role'] ?? ''}';
        final rows = role == 'student' ? students() : staff();
        // a removed member (D-282): the row is kept, the status says so
        final removed = {...rows.first, 'id': 999, 'status': 'removed', 'effective_status': 'removed', 'is_live': false};
        return {'total': rows.length + 1, 'page': 1, 'size': 20, 'pages': 1, 'items': [...rows, removed]};
      },
      'GET /api/v1/org/orgs/4/join/codes': (_) => _codes(),
      'GET /api/v1/org/orgs/4/access/roles': (_) => _roles(),
      'GET /api/v1/org/orgs/4/invitations': (_) => _invitations(),
    }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{})
      ..install();
  }

  setUp(() {
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
  });

  tearDown(() => fake?.uninstall());

  Future<void> page(WidgetTester t, String name, String section, String? sub,
      {Widget Function()? push, Future<void> Function(WidgetTester)? act}) async {
    install();
    await _render(t, name, section, sub, push: push, act: act);
  }

  testWidgets('members', (t) => page(t, 'members', 'people', 'members'));
  testWidgets('departments', (t) => page(t, 'departments', 'people', 'departments'));
  testWidgets('join requests', (t) => page(t, 'join_requests', 'people', 'join_requests'));
  testWidgets('joining requests tab', (t) => page(t, 'joining_requests', 'people', 'members', push: () => const Scaffold(body: OrgAccessJoiningPage())));
  testWidgets('roles', (t) => page(t, 'roles', 'people', 'members', push: () => const OrgAccessPage()));
  testWidgets('invitations', (t) => page(t, 'invitations', 'people', 'members',
      push: () => const OrgInvitationsPage(orgId: 4, orgName: 'Nile National University')));
}
