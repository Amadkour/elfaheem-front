// VISUAL review renders (not a CI suite): the kit's headers, tabs, chrome chips and grouped settings on the Warm
// Editorial default (D-612) — an AppHeader page (tabs, paper chips, refresh action, pill and underline tabs), an
// AppPageHeader with every slot over an AppSection, and an AppSettingsPage — at 390x844 and 1440x900, ar / en,
// light / dark, into test/visual/goldens/kit_headers_*.png. Compared by eye.
//
//   flutter test test/visual/kit_headers_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/chrome_button.dart';
import 'package:flutter_test/flutter_test.dart';

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
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// AppHeader as the app bar, with tabs; the body shows the kit's chips, tabs and sections.
class _HeaderPage extends StatefulWidget {
  const _HeaderPage();

  @override
  State<_HeaderPage> createState() => _HeaderPageState();
}

class _HeaderPageState extends State<_HeaderPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  int _pill = 1;
  int _line = 0;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppHeader(
        title: _tr('الطلاب', 'Students'),
        subtitle: _tr('كل الأقسام · ١٬٢٠٤ طالبًا', 'All departments · 1,204 students'),
        actions: [
          AppRefreshAction(onRefresh: () async {}, always: true),
          IconButton(tooltip: 'x', onPressed: () {}, icon: Icon(Icons.ios_share_rounded, color: c.textMedium)),
        ],
        bottom: TabBar(controller: _tabs, tabs: [
          Tab(text: _tr('الكل', 'All')),
          Tab(text: _tr('نشط', 'Active')),
          Tab(text: _tr('مؤرشف', 'Archived')),
        ]),
      ),
      body: ListView(padding: EdgeInsets.symmetric(horizontal: g), children: [
        AppSection(
          title: _tr('التبويبات', 'Tabs'),
          subtitle: _tr('حبّة زمردية للمختار، وخط حبر تحت تبويبات الصفحة', 'An emerald pill for the chosen one; an ink rule under page tabs'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppTabs(
              items: [
                AppTabItem(_tr('الكل', 'All')),
                AppTabItem(_tr('نشط', 'Active'), count: 12),
                AppTabItem(_tr('بانتظار', 'Pending'), count: 3),
                AppTabItem(_tr('مرفوض', 'Rejected')),
              ],
              index: _pill,
              onChanged: (i) => setState(() => _pill = i),
            ),
            AppSpace.gapMd,
            AppUnderlineTabs(
              items: [
                AppTabItem(_tr('نظرة عامة', 'Overview'), icon: Icons.dashboard_rounded),
                AppTabItem(_tr('الحضور', 'Attendance'), count: 4),
                AppTabItem(_tr('الدرجات', 'Grades')),
              ],
              index: _line,
              onChanged: (i) => setState(() => _line = i),
            ),
          ]),
        ),
        AppSection(
          title: _tr('رقائق الواجهة', 'Chrome chips'),
          trailing: TextButton(onPressed: () {}, child: Text(_tr('عرض الكل', 'See all'))),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const AppBackButton(),
            ChromeIconButton(icon: Icons.event_rounded, label: 'cal', onTap: () {}),
            ChromeIconButton(icon: Icons.notifications_rounded, label: 'bell', onTap: () {}, badge: 7),
            ChromeIconButton(icon: Icons.chat_bubble_rounded, label: 'chat', onTap: () {}, badge: 120),
            ChromeIconButton(icon: Icons.sync_rounded, label: 'busy', onTap: () {}, busy: true),
            AppHeaderTray(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'a', onPressed: () {}, icon: Icon(Icons.download_rounded, color: c.textMedium)),
                IconButton(tooltip: 'b', onPressed: () {}, icon: Icon(Icons.filter_list_rounded, color: c.textMedium)),
              ]),
            ),
            AppGradientSurface(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xs),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const AppBackButton(onHero: true),
                  ChromeBar(child: ChromeIconButton(icon: Icons.event_rounded, label: 'cal', onTap: () {}, badge: 2)),
                ]),
              ),
            ),
          ]),
        ),
        AppSection(
          title: _tr('قائمة طويلة لتجربة الطيّ', 'A long list to try the collapse'),
          child: Column(children: [
            for (var i = 0; i < 12; i++)
              ListTile(title: Text(_tr('الطالب رقم $i', 'Student $i')), subtitle: Text(_tr('القسم العلمي', 'Science'))),
          ]),
        ),
      ]),
    );
  }
}

/// AppPageHeader with every slot, in a list, over sections.
class _PageHeaderPage extends StatefulWidget {
  const _PageHeaderPage();

  @override
  State<_PageHeaderPage> createState() => _PageHeaderPageState();
}

class _PageHeaderPageState extends State<_PageHeaderPage> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: c.background,
      body: ListView(children: [
        AppPageHeader(
          title: _tr('المدفوعات والسحوبات', 'Payments & payouts'),
          subtitle: _tr('كل التحويلات وطلبات السحب في مكان واحد', 'Every transfer and payout request in one place'),
          icon: Icons.account_balance_wallet_rounded,
          breadcrumbs: [_tr('المؤسسة', 'Organization'), _tr('المالية', 'Finance')],
          onBack: () {},
          updatedAt: DateTime.now().subtract(const Duration(minutes: 3)),
          onRefresh: () {},
          actions: [AppIconButton(icon: Icons.ios_share_rounded, tooltip: _tr('تصدير', 'Export'), onPressed: () {})],
          primaryAction: AppButton.primary(label: _tr('طلب جديد', 'New request'), icon: Icons.add_rounded, onPressed: () {}),
          search: AppSearchField(onChanged: (_) {}, hint: _tr('ابحث بالاسم', 'Search by name')),
          bottom: AppUnderlineTabs(
            items: [
              AppTabItem(_tr('بانتظار المراجعة', 'Pending'), count: 4),
              AppTabItem(_tr('السجل', 'History')),
              AppTabItem(_tr('الإعدادات', 'Settings')),
            ],
            index: _section,
            onChanged: (i) => setState(() => _section = i),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: g),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSection(
              title: _tr('هذا الشهر', 'This month'),
              trailing: TextButton(onPressed: () {}, child: Text(_tr('عرض الكل', 'See all'))),
              child: AppBlock(
                tone: AppBlockTone.sky,
                child: Text(_tr('١٨ تحويلًا مكتملًا و٤ بانتظار المراجعة.', '18 transfers completed and 4 pending review.'),
                    style: AppType.body(context)),
              ),
            ),
            AppSection(
              title: _tr('عنوان قسم طويل جدًا يلتف على سطرين على الهاتف ليختبر القطع', 'A very long section title that wraps to two lines on a phone to test the ellipsis'),
              subtitle: _tr('سطر ثانٍ', 'A second line'),
              child: AppCard(child: Text(_tr('محتوى', 'Content'), style: AppType.body(context))),
            ),
            const SizedBox(height: AppSpace.xl),
            AppPageHeader(title: _tr('بسيط', 'Plain'), accent: false),
            const SizedBox(height: AppSpace.xl),
          ]),
        ),
      ]),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: AppSettingsPage(
        header: AppSettingsHeader(
          name: _tr('سارة محمود عبد الرحمن', 'Sara Mahmoud'),
          role: 'teacher',
          email: 'sara@example.test',
          username: 'sara',
          onEdit: () {},
        ),
        groups: [
          AppSettingsGroup(title: _tr('الحساب', 'Account'), icon: Icons.account_circle_rounded, children: [
            AppSettingsTile(icon: Icons.manage_accounts_rounded, label: _tr('تحديث الحساب', 'Update account'), onTap: () {}),
            AppSettingsTile(
                icon: Icons.lock_reset_rounded,
                label: _tr('تغيير كلمة المرور', 'Change password'),
                subtitle: _tr('آخر تغيير قبل ٣ أشهر', 'Last changed 3 months ago'),
                onTap: () {}),
            AppSettingsTile(
                icon: Icons.dark_mode_rounded,
                label: _tr('الوضع الداكن', 'Dark mode'),
                trailing: AppSwitch(value: c.isDark, onChanged: (_) {}, semanticLabel: 'dark')),
          ]),
          AppSettingsGroup(
              title: _tr('التعليم', 'Teaching'),
              subtitle: _tr('الدورات والجلسات والامتحانات', 'Courses, sessions and exams'),
              icon: Icons.school_rounded,
              children: [
                AppSettingsTile(icon: Icons.menu_book_rounded, label: _tr('دوراتي', 'My courses'), color: c.accent2, badge: 3, onTap: () {}),
                AppSettingsTile(icon: Icons.videocam_rounded, label: _tr('الجلسات المباشرة', 'Live sessions'), color: c.danger, onTap: () {}),
                AppSettingsTile(icon: Icons.quiz_rounded, label: _tr('الامتحانات', 'Exams'), color: c.success, badge: 120, onTap: () {}),
                AppSettingsTile(icon: Icons.workspace_premium_rounded, label: _tr('الشهادات', 'Certificates'), color: c.warning, onTap: () {}),
              ]),
          AppSettingsGroup(title: _tr('الخروج', 'Exit'), icon: Icons.exit_to_app_rounded, danger: true, children: [
            AppSettingsTile(icon: Icons.logout_rounded, label: _tr('تسجيل الخروج', 'Sign out'), color: c.danger, onTap: () {}),
          ]),
        ],
        footer: Text('NextBrain 2.4.0', textAlign: TextAlign.center, style: AppType.meta(context)),
      ),
    );
  }
}

Future<void> _render(WidgetTester tester, String name, Widget page) async {
  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    for (final lang in const ['ar', 'en']) {
      for (final dark in const [false, true]) {
        AppConfig.lang = lang;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(size.width, size.width > 900 ? 1100 : 1700);
        final theme = ThemeConfigProvider(api: ApiClient());
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(ThemeConfigScope(
          provider: theme,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.materialTheme(dark: false),
            darkTheme: theme.materialTheme(dark: true),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, w) => Directionality(
                textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                child: DefaultTextStyle.merge(style: TextStyle(fontFamilyFallback: AppFonts.fallback), child: w!)),
            home: RepaintBoundary(key: _shot, child: page),
          ),
        ));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final e = tester.takeException();
        expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
        await expectLater(
            find.byKey(_shot), matchesGoldenFile('goldens/kit_headers_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
      }
    }
  }
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  testWidgets('kit headers, tabs, chips and settings', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      await _render(tester, 'header', const _HeaderPage());
      await _render(tester, 'page', const _PageHeaderPage());
      await _render(tester, 'settings', const _SettingsPage());
    } finally {
      AppConfig.lang = prevLang;
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
