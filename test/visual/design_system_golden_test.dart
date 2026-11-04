// VISUAL review renders of the design system (D-180, lib/design/README.md): one gallery page with every component
// (page header, KPI grid with the highlight card, buttons, badges, tabs, data table, states), at 390x844 and
// 1440x900, ar / en, light / dark, into test/visual/goldens/design_system_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/design_system_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
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
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

// the production palette (the teal brand), not the built-in fallback
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
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(
        key: _shot,
        child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

typedef _Row = (String name, String email, String status, int courses, double paid);

final _rows = <_Row>[
  ('سارة أحمد', 'sara@example.test', 'active', 3, 1250),
  ('Omar Khaled', 'omar@example.test', 'pending', 1, 0),
  ('ليلى محمود', 'laila@example.test', 'active', 5, 4380.5),
  ('Youssef Ali', 'youssef@example.test', 'inactive', 0, 0),
  ('منى إبراهيم', 'mona@example.test', 'active', 2, 900),
  ('Karim Nabil', 'karim@example.test', 'active', 4, 2100),
];

class _Gallery extends StatefulWidget {
  const _Gallery();

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _tab = 0;
  int _section = 1;

  @override
  Widget build(BuildContext context) {
    AppTone tone(String s) => switch (s) { 'active' => AppTone.success, 'pending' => AppTone.warning, _ => AppTone.neutral };
    String label(String s) => switch (s) {
          'active' => _tr('نشط', 'Active'),
          'pending' => _tr('بانتظار', 'Pending'),
          _ => _tr('غير نشط', 'Inactive'),
        };
    final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return ListView(children: [
      AppPageHeader(
        title: _tr('المدفوعات والسحوبات', 'Payments & payouts'),
        subtitle: _tr('كل التحويلات وطلبات السحب في مكان واحد', 'Every transfer and payout request in one place'),
        icon: Icons.account_balance_wallet_rounded,
        updatedAt: DateTime.now().subtract(const Duration(minutes: 3)),
        onRefresh: () {},
        actions: [AppIconButton(icon: Icons.ios_share_rounded, tooltip: _tr('تصدير', 'Export'), onPressed: () {})],
        primaryAction: AppButton.primary(label: _tr('طلب جديد', 'New request'), icon: Icons.add_rounded, onPressed: () {}),
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
        padding: EdgeInsets.fromLTRB(g, AppSpace.lg, g, AppSpace.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppKpiGrid(children: [
            AppKpiCard(
              label: _tr('الإيرادات · 30 يومًا', 'Revenue · 30 days'),
              value: '48,210',
              icon: Icons.payments_rounded,
              delta: 0.12,
              spark: const [3, 4, 3.5, 5, 6, 5.5, 7, 8],
              highlight: true,
            ),
            AppKpiCard(
              label: _tr('الطلاب', 'Students'),
              value: '1,204',
              icon: Icons.school_rounded,
              delta: 0.04,
              spark: const [10, 11, 11, 12, 12.5, 13],
            ),
            AppKpiCard(label: _tr('سحوبات معلّقة', 'Pending payouts'), value: '3', icon: Icons.hourglass_top_rounded, delta: -0.25, deltaGoodWhenUp: false),
            AppKpiCard(label: _tr('الشكاوى', 'Complaints'), value: '7', icon: Icons.support_agent_rounded, delta: 0.4, deltaGoodWhenUp: false),
          ]),
          AppSpace.gapLg,
          AppSection(
            title: _tr('الأزرار', 'Buttons'),
            child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
              AppButton.primary(label: _tr('حفظ', 'Save'), icon: Icons.check_rounded, onPressed: () {}),
              AppButton.secondary(label: _tr('معاينة', 'Preview'), onPressed: () {}),
              AppButton.tonal(label: _tr('تصدير', 'Export'), icon: Icons.ios_share_rounded, onPressed: () {}),
              AppButton.ghost(label: _tr('إلغاء', 'Cancel'), onPressed: () {}),
              AppButton.danger(label: _tr('حذف', 'Delete'), icon: Icons.delete_outline_rounded, onPressed: () {}),
              AppButton.danger(label: _tr('إيقاف', 'Suspend'), dangerOutline: true, onPressed: () {}),
              AppButton.primary(label: _tr('جارٍ الحفظ', 'Saving'), busy: true, onPressed: () {}),
              AppButton.primary(label: _tr('معطّل', 'Disabled'), onPressed: null),
              AppIconButton(icon: Icons.notifications_rounded, tooltip: 'bell', badge: 12, onPressed: () {}),
              AppIconButton(icon: Icons.edit_rounded, tooltip: 'edit', variant: AppIconButtonVariant.tonal, onPressed: () {}),
            ]),
          ),
          AppSpace.gapLg,
          AppSection(
            title: _tr('الحالات والتبويبات', 'Badges & tabs'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final t in AppTone.values) AppStatusBadge(label: t.name, tone: t, dot: true),
              ]),
              AppSpace.gapMd,
              AppTabs(
                items: [
                  AppTabItem(_tr('الكل', 'All')),
                  AppTabItem(_tr('نشط', 'Active'), count: 12),
                  AppTabItem(_tr('بانتظار', 'Pending'), count: 3),
                  AppTabItem(_tr('مرفوض', 'Rejected')),
                ],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ]),
          ),
          AppSpace.gapLg,
          AppSection(
            title: _tr('جدول البيانات', 'Data table'),
            child: AppDataTable<_Row>(
              shrinkWrap: true,
              rows: _rows,
              searchHint: _tr('ابحث بالاسم أو البريد', 'Search by name or email'),
              onSearch: (_) {},
              sortKey: 'paid',
              sortAscending: false,
              onSort: (_, _) {},
              filters: [
                AppTableFilter(
                  label: _tr('الحالة', 'Status'),
                  options: [('active', label('active')), ('pending', label('pending')), ('inactive', label('inactive'))],
                  onChanged: (_) {},
                ),
              ],
              columns: [
                AppTableColumn.text(key: 'name', label: _tr('الاسم', 'Name'), text: (r) => r.$1, primary: true, sortable: true, flex: 2),
                AppTableColumn.text(key: 'email', label: _tr('البريد', 'Email'), text: (r) => r.$2, flex: 2, showOnPhone: false),
                AppTableColumn(key: 'status', label: _tr('الحالة', 'Status'), cell: (_, r) => Align(alignment: AlignmentDirectional.centerStart, child: AppStatusBadge(label: label(r.$3), tone: tone(r.$3)))),
                AppTableColumn.text(key: 'courses', label: _tr('الكورسات', 'Courses'), text: (r) => '${r.$4}', numeric: true),
                AppTableColumn.text(key: 'paid', label: _tr('المدفوع', 'Paid'), text: (r) => r.$5.toStringAsFixed(0), numeric: true, sortable: true),
              ],
              rowActions: (r) => [
                AppRowAction(icon: Icons.visibility_rounded, label: _tr('عرض', 'View'), onTap: () {}),
                AppRowAction(icon: Icons.delete_outline_rounded, label: _tr('حذف', 'Delete'), onTap: () {}, danger: true),
              ],
              pagination: AppPagination(page: 2, pageCount: 9, onPage: (_) {}, total: 52, pageSize: 6),
            ),
          ),
          AppSpace.gapLg,
          AppSection(
            title: _tr('التحميل والأخطاء', 'Loading & errors'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppCard(child: AppErrorState(message: _tr('انتهت مهلة الاتصال بالخادم.', 'The server took too long to answer.'), onRetry: () {})),
              AppSpace.gapMd,
              const SizedBox(height: 220, child: AppLoadingState(shape: AppLoadingShape.kpis)),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  testWidgets('design system gallery', (tester) async {
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
            await tester.pumpWidget(_host(const _Gallery(), dark: dark));
            await _frames(tester);
            for (var i = 0; i < 4; i++) {
              var extra = 0.0;
              for (final e in find.byType(Scrollable).evaluate()) {
                final s = (e as StatefulElement).state as ScrollableState;
                if (s.position.axis == Axis.vertical && s.position.hasContentDimensions) {
                  extra = math.max(extra, s.position.maxScrollExtent);
                }
              }
              if (extra < 1) break;
              tester.view.physicalSize = Size(size.width, math.min(6000, tester.view.physicalSize.height + extra));
              await _frames(tester, 6);
            }
            final e = tester.takeException();
            expect(e, isNull, reason: '${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
            await expectLater(
              find.byKey(_shot),
              matchesGoldenFile('goldens/design_system_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
            );
          }
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
