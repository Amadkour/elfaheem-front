// VISUAL review renders of the organization dashboard's section pages on the shared page anatomy (D-103,
// org_page_kit.dart: header · ONE primary action · ONE search / filter · content): the real OrgDashboardScreen over
// the real providers on a fake server (test/ui/org_pages_samples.dart, real-server shapes), opened on each page,
// 390x844 and 1440x900, ar / en, light / dark, into test/visual/goldens/org_page_*.png. Not a CI suite; by eye.
//
//   flutter test test/visual/org_pages_golden_test.dart --update-goldens [--plain-name members]
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

/// ORG_PAGES_ONLY=390_ar_light,1440_en_dark renders only those variants (the full set is 8 per page).
bool _wanted(String variant) {
  final only = Platform.environment['ORG_PAGES_ONLY'];
  return only == null || only.isEmpty || only.split(',').contains(variant);
}

Future<void> _render(WidgetTester tester, String name, String section, String? sub,
    {Future<void> Function(WidgetTester)? act}) async {
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
          if (act != null) {
            await act(tester);
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/${name}_$variant.png'));
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

  void install({bool empty = false}) {
    fake = FakeApi({
      'GET /api/v1/org/mine': (_) => {'items': [_uni], 'can_create_root': false},
      'GET /api/v1/org/orgs/4/dashboard': (_) => payload('org_dashboard.json'),
      'GET /api/v1/notifications': (_) => {'items': [], 'total': 0, 'unread': 3},
      'GET /api/v1/me/attention': (_) => {'counts': {}, 'total': 0, 'items': []},
      ...orgPageRoutes(empty: empty),
    }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{})
      ..install();
  }

  setUp(() {
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
  });

  tearDown(() => fake?.uninstall());

  Future<void> page(WidgetTester t, String name, String section, String? sub, {bool empty = false}) async {
    install(empty: empty);
    await _render(t, name, section, sub);
  }

  testWidgets('members', (t) => page(t, 'org_page_members', 'people', 'members'));
  testWidgets('members empty', (t) => page(t, 'org_page_members_empty', 'people', 'members', empty: true));
  testWidgets('departments', (t) => page(t, 'org_page_departments', 'people', 'departments'));
  testWidgets('join requests', (t) => page(t, 'org_page_join', 'people', 'join_requests'));
  testWidgets('courses', (t) => page(t, 'org_page_courses', 'academics', 'courses'));
  testWidgets('structure', (t) => page(t, 'org_page_structure', 'academics', 'structure'));
  testWidgets('registrar', (t) => page(t, 'org_page_registrar', 'academics', 'registrar'));
  testWidgets('news', (t) => page(t, 'org_page_news', 'services', 'announcements'));
  testWidgets('forms', (t) => page(t, 'org_page_forms', 'services', 'forms'));
  testWidgets('complaints', (t) => page(t, 'org_page_complaints', 'services', 'complaints'));
  testWidgets('library', (t) => page(t, 'org_page_library', 'services', 'materials'));
  testWidgets('settings', (t) => page(t, 'org_page_settings', 'settings', null));
}
