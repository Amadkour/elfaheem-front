// Visual review renders of the brand gradient roles (D-136) on the shared widgets that carry them: the primary
// buttons (PrimaryButton, AppPrimaryButton, the Filled / Elevated button theme, OrgPrimaryButton), the FAB, the
// heroes (AppHero, HomeHeroCard), the selected chip and the shell's active tab / sidebar item. Compared by eye like
// the other test/visual files:
//
//   flutter test test/visual/brand_gradient_golden_test.dart --update-goldens
//
// → test/visual/goldens/brand_<default|prod>_<width>_<lang>_<light|dark>.png at 390×844 (bottom bar) and
//   1440×900 (sidebar), with the built-in palette and the production one (fixtures/theme_production.json).
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
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/org/org_page_kit.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
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
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

void main() {
  late StorageService storage;
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    AppConfig.disableList = [];
  });

  Widget host({required bool dark, required bool prod}) {
    final theme = ThemeConfigProvider(api: ApiClient());
    if (prod) {
      theme.debugUseColors(
          jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>);
    }
    final rtl = AppConfig.lang == 'ar';
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
        ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
      ],
      child: ThemeConfigScope(
        provider: theme,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.materialTheme(dark: false),
          darkTheme: theme.materialTheme(dark: true),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
          home: RepaintBoundary(key: _shot, child: const _Shell()),
        ),
      ),
    );
  }

  for (final prod in const [false, true]) {
    testWidgets('brand gradient ${prod ? 'prod' : 'default'}', (tester) async {
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
              await tester.pumpWidget(host(dark: dark, prod: prod));
              for (var i = 0; i < 10; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
              expect(tester.takeException(), isNull);
              await expectLater(
                find.byKey(_shot),
                matchesGoldenFile(
                    'goldens/brand_${prod ? 'prod' : 'default'}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
              );
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
    });
  }
}

class _Shell extends StatelessWidget {
  const _Shell();

  @override
  Widget build(BuildContext context) {
    final items = [
      DashboardItem(Icons.home_outlined, Icons.home_rounded, 'home', null, const _Gallery(), badge: 2),
      DashboardItem(Icons.menu_book_outlined, Icons.menu_book_rounded, 'my_courses', null, const SizedBox()),
      DashboardItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'my_schedule', null, const SizedBox()),
      DashboardItem(Icons.person_outline_rounded, Icons.person_rounded, 'my_profile', null, const SizedBox()),
    ];
    return LayoutBuilder(
      builder: (context, c) => AppShell(width: c.maxWidth, currentIndex: 0, onTap: (_) {}, items: items),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget gap() => const SizedBox(height: 14);
    return Scaffold(
      backgroundColor: c.background,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () {},
        icon: const Icon(Icons.add_rounded),
        label: Text(_tr('إضافة', 'Add')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 96),
        children: [
          AppHero(
            title: _tr('مرحبًا سارة', 'Welcome, Sara'),
            subtitle: _tr('4 جلسات اليوم · 6 مطلوب منك', '4 sessions today · 6 to do'),
            icon: Icons.auto_awesome_rounded,
            stats: [
              AppHeroStat(icon: Icons.menu_book_rounded, value: '12', label: _tr('كورسات', 'Courses')),
              AppHeroStat(icon: Icons.check_circle_rounded, value: '86%', label: _tr('حضور', 'Attendance')),
            ],
          ),
          HomeHeroCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_tr('التالي · 12:40', 'NEXT UP · 12:40'),
                  style: appText(11.5, w: FontWeight.w600, c: c.onHero.withValues(alpha: 0.8))),
              const SizedBox(height: 6),
              Text(_tr('مراجعة الفصل الثالث', 'Chapter 3 review'),
                  style: appText(19, w: FontWeight.w600, c: c.onHero)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              PrimaryButton(isLoading: false, label: _tr('تسجيل الدخول', 'Sign in'), onPressed: () {}),
              gap(),
              Row(children: [
                Expanded(child: PrimaryButton(isLoading: false, label: _tr('معطل', 'Disabled'), onPressed: null)),
                const SizedBox(width: 12),
                Expanded(child: PrimaryButton(isLoading: true, label: 'x', onPressed: () {})),
              ]),
              gap(),
              AppPrimaryButton(label: _tr('حفظ التغييرات', 'Save changes'), icon: Icons.check_rounded, onPressed: () {}),
              gap(),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton(onPressed: () {}, child: Text(_tr('متابعة', 'Continue'))),
                ElevatedButton(onPressed: () {}, child: Text(_tr('إرسال', 'Send'))),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: c.danger),
                  onPressed: () {},
                  child: Text(_tr('حذف', 'Delete')),
                ),
                FilledButton(onPressed: null, child: Text(_tr('معطل', 'Disabled'))),
                OrgPrimaryButton(
                  action: OrgPrimaryAction(icon: Icons.person_add_alt_1_rounded, label: _tr('إضافة عضو', 'Add member'), onTap: () {}),
                ),
                OutlinedButton(onPressed: () {}, child: Text(_tr('إلغاء', 'Cancel'))),
              ]),
              gap(),
              Wrap(spacing: 8, runSpacing: 8, children: [
                AppChoiceChip(label: _tr('الكل', 'All'), selected: true, onTap: () {}),
                AppChoiceChip(label: _tr('نشط', 'Active'), selected: false, onTap: () {}),
                AppChoiceChip(label: _tr('مؤرشف', 'Archived'), selected: false, onTap: () {}),
              ]),
              gap(),
              AppProgressBar(value: 64, color: c.primary),
              gap(),
              const LinearProgressIndicator(value: 0.42),
            ]),
          ),
        ],
      ),
    );
  }
}
