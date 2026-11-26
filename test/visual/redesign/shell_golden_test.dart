// VISUAL review renders of the redesigned shells (KIT_SPEC §6, §7.3): the student, teacher, parent and admin shells
// with five demo tabs (people and names from docs/redesign/CAST.md), the second tab open and one count, at 390x844
// (the phone bar, the phone top bar) and 1360x900 (the sidebar, the top bar), Arabic and English, light, text scale
// 1.0, Reduce motion ON (still frames). Into test/visual/redesign/goldens/shell_<role>_<w>_<lang>.png; compared by
// eye with D:/platform/redesign-ref/ref/*/001_*Home*. Not a CI suite.
//
//   flutter test test/visual/redesign/shell_golden_test.dart --update-goldens [--plain-name teacher]
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
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_header.dart';
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/chrome_button.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home_screens_golden_test.dart' show pubspecFonts;

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

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// One demo tab: its label, icons and area.
typedef _Tab = (String ar, String en, IconData icon, IconData on, AppArea? area);

final _roles = <String, ({String user, String role, List<_Tab> tabs})>{
  'student': (
    user: 'فيصل العنزي',
    role: 'student',
    tabs: [
      ('الرئيسية', 'Home', Icons.home_outlined, Icons.home_rounded, AppArea.home),
      ('دوراتي', 'My courses', Icons.menu_book_outlined, Icons.menu_book_rounded, AppArea.learn),
      ('جدولي', 'Schedule', Icons.calendar_month_outlined, Icons.calendar_month_rounded, AppArea.sched),
      ('العب وتعلّم', 'Play & learn', Icons.sports_esports_outlined, Icons.sports_esports_rounded, AppArea.games),
      ('حسابي', 'Me', Icons.person_outline_rounded, Icons.person_rounded, AppArea.me),
    ],
  ),
  'teacher': (
    user: 'أ. ماجد الشهري',
    role: 'teacher',
    tabs: [
      ('الرئيسية', 'Home', Icons.home_outlined, Icons.home_rounded, null),
      ('دوراتي', 'My courses', Icons.menu_book_outlined, Icons.menu_book_rounded, null),
      ('جدولي', 'Schedule', Icons.calendar_month_outlined, Icons.calendar_month_rounded, null),
      ('التحليلات', 'Analytics', Icons.bar_chart_outlined, Icons.bar_chart_rounded, null),
      ('حسابي', 'Me', Icons.person_outline_rounded, Icons.person_rounded, null),
    ],
  ),
  'parent': (
    user: 'أحمد سعد العنزي',
    role: 'parent',
    tabs: [
      ('اليوم', 'Today', Icons.today_outlined, Icons.today_rounded, null),
      ('الأبناء', 'Children', Icons.family_restroom_outlined, Icons.family_restroom_rounded, null),
      ('التقارير', 'Reports', Icons.insights_outlined, Icons.insights_rounded, null),
      ('المدفوعات', 'Payments', Icons.payments_outlined, Icons.payments_rounded, null),
      ('المزيد', 'More', Icons.more_horiz_rounded, Icons.more_horiz_rounded, null),
    ],
  ),
  'admin': (
    user: 'عبدالله المالكي',
    role: 'admin',
    tabs: [
      ('نظرة عامة', 'Overview', Icons.dashboard_outlined, Icons.dashboard_rounded, null),
      ('الأشخاص', 'People', Icons.people_outline_rounded, Icons.people_rounded, null),
      ('الدورات', 'Courses', Icons.menu_book_outlined, Icons.menu_book_rounded, null),
      ('المحتوى', 'Content', Icons.perm_media_outlined, Icons.perm_media_rounded, null),
      ('الدعم', 'Support', Icons.support_agent_outlined, Icons.support_agent_rounded, null),
    ],
  ),
};

/// A tab's first page: the page header (the phone bar below 700, folded into the shell's bar above) and a few cards.
Widget _page(String title) => BasePage(
      appBar: AppHeader(
        title: title,
        showBack: false,
        actions: [
          ChromeIconButton(icon: Icons.chat_bubble_outline_rounded, label: _t('الرسائل', 'Messages'), onTap: () {}, badge: 2),
          ChromeIconButton(icon: Icons.notifications_none_rounded, label: _t('الإشعارات', 'Notifications'), onTap: () {}, badge: 5),
        ],
      ),
      child: Builder(builder: (context) {
        final c = context.colors;
        return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          for (var i = 0; i < 4; i++)
            Container(
              height: 120,
              margin: const EdgeInsets.only(bottom: AppSpace.md),
              decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.card)),
            ),
        ]);
      }),
    );

void main() {
  late StorageService storage;

  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    ShellBadge.source = () => ValueNotifier(0);
    ShellBadge.countOf = (_, _) => 0;
  });
  tearDown(ViewAsState.instance.stop);

  for (final entry in _roles.entries) {
    testWidgets('shell ${entry.key}', (tester) async {
      final r = entry.value;
      for (final size in const [Size(390, 844), Size(1360, 900)]) {
        for (final lang in const ['ar', 'en']) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          final auth = MyAuthProvider(storage: storage);
          // View as keeps the demo person in memory only (no disk, no account refresh)
          ViewAsState.instance.start(id: 7, name: r.user, role: r.role);
          await auth.saveUserLocally(
              UserModel(id: 7, name: r.user, gmail: 'demo@example.com', role: r.role, lastLogin: DateTime(2026, 11, 25)));
          final items = [
            for (var i = 0; i < r.tabs.length; i++)
              DashboardItem(r.tabs[i].$3, r.tabs[i].$4, _t(r.tabs[i].$1, r.tabs[i].$2), () async {},
                  _page(_t(r.tabs[i].$1, r.tabs[i].$2)),
                  area: r.tabs[i].$5, badge: i == 3 ? 3 : 0),
          ];
          final theme = ThemeConfigProvider(api: ApiClient());
          final shot = GlobalKey();
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(ThemeConfigScope(
            provider: theme,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: auth),
                ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.materialTheme(dark: false),
                builder: (context, w) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(disableAnimations: true, textScaler: TextScaler.noScaling),
                  child: Directionality(
                      textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr, child: w!),
                ),
                home: RepaintBoundary(
                  key: shot,
                  child: AppShell(width: size.width, currentIndex: 1, onTap: (_) {}, items: items),
                ),
              ),
            ),
          ));
          // the app mark is an asset: decode it for real before the shot
          await tester.runAsync(() async {
            for (final e in find.byType(Image).evaluate()) {
              await precacheImage((e.widget as Image).image, e);
            }
          });
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await expectLater(find.byKey(shot),
              matchesGoldenFile('goldens/shell_${entry.key}_${size.width.toInt()}_$lang.png'));
          ViewAsState.instance.stop();
        }
      }
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
}
