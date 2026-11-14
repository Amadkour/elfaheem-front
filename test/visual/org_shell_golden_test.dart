// VISUAL review renders of the organization dashboard's shell frame and its ONE page header (D-103,
// org_page_header.dart): the real OrgDashboardScreen over the real providers on a fake server, opened on a section
// page (People: the header + the section's chips; Settings), 390x844 and 1440x900, ar / en, light / dark, into
// test/visual/goldens/org_shell_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/org_shell_golden_test.dart --update-goldens [--plain-name people]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/features/org/org_dashboard_screen.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
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
  'id': 4,
  'name_ar': 'جامعة النيل الأهلية',
  'name_en': 'Nile National University',
  'type': 'university',
  'status': 'approved',
  'color': '#1F6F5C',
  'my_role': 'org_admin',
  'is_admin': true,
  'access': 'admin',
  'depth': 0,
};
const _faculty = {
  'id': 7,
  'name_ar': 'كلية الهندسة',
  'name_en': 'Faculty of Engineering',
  'type': 'faculty',
  'status': 'approved',
  'my_role': 'teacher',
  'access': 'member',
  'member_role': 'teacher',
  'depth': 1,
  'permissions': <String, dynamic>{},
  'dept_permissions': <String, dynamic>{},
};

Future<void> _render(WidgetTester tester, String name, String section, {bool sheet = false}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(820, 1100), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          SharedPreferences.setMockInitialValues({});
          final storage = await StorageService.getInstance();
          await storage.saveUser({'id': 7, 'name': 'Mona Adel', 'gmail': 'mona@example.com', 'role': 'org-admin'});
          AttentionService.instance.orgTabRequest.value = OrgTabRequest(4, section, null);
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
          if (sheet) {
            await tester.tap(find.byKey(const ValueKey('org.header.switcher')));
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
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
  late FakeApi fake;

  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  setUp(() {
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
    fake = FakeApi({
      'GET /api/v1/org/mine': (_) => {
            'items': [_uni, _faculty],
            'can_create_root': false,
          },
      'GET /api/v1/org/orgs/4/dashboard': (_) => payload('org_dashboard.json'),
      'GET /api/v1/notifications': (_) => {'items': [], 'total': 0, 'unread': 3},
      'GET /api/v1/me/attention': (_) => {'counts': {}, 'total': 0, 'items': []},
    }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{});
    fake.install();
  });

  tearDown(() => fake.uninstall());

  testWidgets('org shell people', (t) => _render(t, 'org_shell_people', 'people'));
  testWidgets('org shell settings', (t) => _render(t, 'org_shell_settings', 'settings'));
  testWidgets('org shell switcher', (t) async {
    AppModeController.instance.debugSet({
      'items': [
        {'organization': _uni, 'roles': <String>[], 'manage': {'is_admin': true}, 'todo': {'total': 0}, 'approvals': {'total': 4}},
        {'organization': _faculty, 'roles': ['teacher'], 'manage': null},
        {
          'organization': {'id': 12, 'name_ar': 'أكاديمية النور', 'name_en': 'Al-Noor Academy', 'type': 'academy', 'status': 'approved', 'color': '#7C3AED'},
          'roles': ['student'],
          'manage': null,
          'todo': {'total': 2},
        },
      ],
    }, mode: AppMode.individual);
    addTearDown(() => AppModeController.instance.debugSet(const {}, mode: AppMode.individual));
    await _render(t, 'org_shell_switcher', 'people', sheet: true);
  });
}
