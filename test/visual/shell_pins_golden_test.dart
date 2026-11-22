// VISUAL review renders of pins and colour boxes (D-1170): the desktop sidebar with coloured tabs and a "Pinned"
// group, the phone's Home strip over a bar with coloured tabs, and the Customize tabs sheet — ar / en, light / dark,
// into test/visual/goldens/shell_pins_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/shell_pins_golden_test.dart --update-goldens
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
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/design/shell_pins.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

ShellPinState _state() => const ShellPinState()
    .add(const ShellPin(id: 'a', title: 'Rooms & halls'))
    .add(const ShellPin(id: 'b', title: 'Grade review'))
    .add(const ShellPin(id: 'c', title: 'Attendance today'))
    .withColor('home', ShellTabColor.primary)
    .withColor('my_courses', ShellTabColor.amber)
    .withColor('my_schedule', ShellTabColor.sky);

List<DashboardItem> _items() => [
      DashboardItem(Icons.home_outlined, Icons.home_rounded, 'home', null, const _Page('Home')),
      DashboardItem(Icons.book_outlined, Icons.book_rounded, 'my_courses', null, const _Page('Courses')),
      DashboardItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'my_schedule', null, const _Page('Schedule')),
      DashboardItem(Icons.analytics_outlined, Icons.analytics, 'analysis', null, const _Page('Analysis')),
      DashboardItem(Icons.person_outline, Icons.person, 'my_profile', null, const _Page('Profile')),
    ];

class _Page extends StatelessWidget {
  const _Page(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: context.colors.background,
        child: Center(child: Text(name, style: Theme.of(context).textTheme.headlineSmall)),
      );
}

void main() {
  setUpAll(_loadFonts);

  for (final lang in const ['en', 'ar']) {
    for (final dark in const [false, true]) {
      final tag = '${lang}_${dark ? 'dark' : 'light'}';
      for (final (name, size) in const [('wide', Size(1440, 900)), ('phone', Size(390, 844))]) {
        testWidgets('shell pins $name $tag', (tester) async {
          SharedPreferences.setMockInitialValues({'ui.shell_tabs.v1.0|v': jsonEncode(_state().toJson())});
          ShellPins.debugReset();
          final storage = await StorageService.getInstance();
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prodColors);
          await tester.pumpWidget(ThemeConfigScope(
            provider: theme,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.materialTheme(dark: false),
              darkTheme: theme.materialTheme(dark: true),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              builder: (context, w) =>
                  Directionality(textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr, child: w!),
              home: RepaintBoundary(
                key: _shot,
                child: MultiProvider(
                  providers: [
                    ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
                    ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
                  ],
                  child: AppShell(width: size.width, currentIndex: 1, onTap: (_) {}, items: _items(), pinScope: 'v'),
                ),
              ),
            ),
          ));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (name == 'phone') {
            // the strip lives on Home: show Home, then also render the Customize sheet
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(ThemeConfigScope(
              provider: theme,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.materialTheme(dark: false),
                darkTheme: theme.materialTheme(dark: true),
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                builder: (context, w) =>
                    Directionality(textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr, child: w!),
                home: RepaintBoundary(
                  key: _shot,
                  child: MultiProvider(
                    providers: [
                      ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
                      ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
                    ],
                    child: AppShell(width: size.width, currentIndex: 0, onTap: (_) {}, items: _items(), pinScope: 'v'),
                  ),
                ),
              ),
            ));
            for (var i = 0; i < 12; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/shell_pins_${name}_$tag.png'));
          if (name == 'phone') {
            await tester.tap(find.byKey(const ValueKey('shell.strip.customize')));
            for (var i = 0; i < 12; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/shell_pins_sheet_$tag.png'));
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
