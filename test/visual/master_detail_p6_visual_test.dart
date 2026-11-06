// VISUAL review renders of phase 6 (D-290): the real admin Teachers and Categories pages over a FakeApi with the real
// entity payloads, a teacher's panel (management unfolded) and a category's panel with its tabs, at 1440 x 900 and the
// phone's 390 x 844, ar / en, light / dark, into test/visual/goldens/md_p6_*.png. Not a CI suite; compared by eye. The
// strings of keys_p6.json are read from there, so the renders show real text before they are merged.
//
//   flutter test test/visual/master_detail_p6_visual_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/design/app_tabs.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:flutter_education_app/features/admin/admin_categories_page.dart';
import 'package:flutter_education_app/features/admin/admin_users_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../ui/admin_ds/people_support.dart';
import '../ui/master_detail/md_teachers_categories_test.dart' show adminRoutes, hosted;
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

final _prodColors =
    jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prodColors);
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => RepaintBoundary(
          key: _shot, child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!)),
      home: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
    ),
  );
}

Future<void> _pump(WidgetTester tester, [int n = 16]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(_loadFonts);

  Future<void> render(
    WidgetTester tester,
    String name,
    Widget page,
    Future<void> Function(EntityPanelController panel) act, {
    List<Size> sizes = const [Size(1440, 900), Size(390, 844)],
  }) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final size in sizes) {
        for (final lang in const ['ar', 'en']) {
          for (final dark in const [false, true]) {
            AppConfig.lang = lang;
            EntitiesApi.instance.invalidate();
            final api = FakeApi(adminRoutes(), latency: const Duration(milliseconds: 20));
            final auth = await peopleSetUp(api);
            translation.addAll(jsonDecode(File('docs/master_detail/keys_p6.json').readAsStringSync()) as Map<String, dynamic>);
            await _loadFonts();
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(hosted(auth, _host(page, dark: dark)));
            await _pump(tester);
            await act(tester.widget<MasterDetailScaffold>(find.byType(MasterDetailScaffold)).controller);
            await _pump(tester);
            expect(tester.takeException(), isNull, reason: '$name ${size.width.toInt()} $lang');
            await expectLater(find.byKey(_shot),
                matchesGoldenFile('goldens/${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
            api.uninstall();
          }
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }

  testWidgets('the categories list', (tester) async {
    await render(tester, 'md_p6_categories', const AdminCategoriesPage(), (_) async {});
  });

  testWidgets('a category open on its Students tab', (tester) async {
    await render(tester, 'md_p6_category', const AdminCategoriesPage(), (panel) async {
      panel.open(panel.siblings.first);
      await _pump(tester);
      final tabs = tester.widget<AppUnderlineTabs>(find.byType(AppUnderlineTabs));
      tabs.onChanged(2);
    });
  });

  testWidgets('a teacher with management unfolded', (tester) async {
    await render(tester, 'md_p6_teacher', const AdminUsersPage(role: 'teacher', embedded: true), (panel) async {
      panel.open(panel.siblings[1]);
      await _pump(tester);
    });
  });

  testWidgets('a tall teacher panel: every section', (tester) async {
    await render(tester, 'md_p6_teacher_tall', const AdminUsersPage(role: 'teacher', embedded: true), (panel) async {
      panel.open(panel.siblings[1]);
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('md.manage')));
    }, sizes: const [Size(1440, 2400)]);
  });
}
