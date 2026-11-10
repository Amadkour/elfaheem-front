// VISUAL review renders (not a CI suite): the kit's cards, KPIs, stat tiles, badges, charts, skeletons and the empty /
// error states on the Warm Editorial default palette (D-610 – D-613), at 390x844 and 1440x900, ar / en, light / dark,
// into test/visual/goldens/kit_cards_*.png. Compared by eye.
//
//   flutter test test/visual/kit_cards_golden_test.dart --update-goldens
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

class _Sample extends StatelessWidget {
  const _Sample();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width > 900;
    Widget section(String ar, String en, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(_tr(ar, en), style: AppType.section(context)),
            ),
            child,
          ]),
        );

    final kpis = AppKpiGrid(children: [
      AppKpiCard(
        label: _tr('الإيرادات · 30 يومًا', 'Revenue · 30 days'),
        value: '48,210',
        icon: Icons.payments_rounded,
        delta: 0.12,
        spark: const [3, 4, 3.5, 5, 6, 5.5, 7, 8],
        highlight: true,
        onTap: () {},
      ),
      AppKpiCard(label: _tr('الطلاب', 'Students'), value: '1,204', icon: Icons.school_rounded, delta: 0.04, spark: const [10, 11, 11, 12, 12.5, 13]),
      AppKpiCard(label: _tr('سحوبات معلّقة', 'Pending payouts'), value: '3', icon: Icons.hourglass_top_rounded, delta: -0.25, deltaGoodWhenUp: false),
      AppKpiCard(label: _tr('الشكاوى', 'Complaints'), value: '7', icon: Icons.support_agent_rounded, delta: 0.4, deltaGoodWhenUp: false, onTap: () {}),
    ]);

    final stats = AppGrid(padding: EdgeInsets.zero, children: [
      AppStatTile(icon: Icons.bolt_rounded, label: _tr('أحداث · 24 ساعة', 'Events · 24 h'), value: appCompactNumber(12840)),
      AppStatTile(icon: Icons.check_circle_rounded, label: _tr('مهام ناجحة', 'Jobs succeeded'), value: 312, color: c.success),
      AppStatTile(icon: Icons.error_rounded, label: _tr('مهام فشلت', 'Jobs failed'), value: 2, color: c.danger, onTap: () {}),
      AppStatTile(icon: Icons.support_agent_rounded, label: _tr('شكاوى · 30 يومًا', 'Complaints · 30 days'), value: 7, color: c.warning),
    ]);

    final actions = Column(children: [
      AppActionCard(
        icon: Icons.people_alt_rounded,
        title: _tr('الأشخاص', 'People'),
        subtitle: _tr('الطلاب والمعلمون وأولياء الأمور في مكان واحد', 'Students, teachers and parents in one place'),
        badge: 12,
        onTap: () {},
      ),
      AppSpace.gapSm,
      AppActionCard(
        icon: Icons.event_rounded,
        title: _tr('الجدول الدراسي', 'Timetable'),
        subtitle: _tr('الفصل الثاني · 14 شعبة', 'Second term · 14 sections'),
        color: c.accent2,
        onTap: () {},
        trailing: AppStatusBadge(label: _tr('منشور', 'Published'), tone: AppTone.success, dot: true),
      ),
    ]);

    final badges = Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
      AppStatusBadge(label: _tr('نشط', 'Active'), tone: AppTone.success, dot: true),
      AppStatusBadge(label: _tr('بانتظار', 'Pending'), tone: AppTone.warning, dot: true),
      AppStatusBadge(label: _tr('مرفوض', 'Rejected'), tone: AppTone.danger, icon: Icons.close_rounded),
      AppStatusBadge(label: _tr('أعلى درجة', 'Top mark'), tone: AppTone.gold, icon: Icons.workspace_premium_rounded),
      AppStatusBadge(label: _tr('مسودة', 'Draft')),
      AppStatusBadge(label: _tr('معلومة', 'Info'), tone: AppTone.info, dense: true),
      AppStatusBadge(label: _tr('مميّز', 'Featured'), tone: AppTone.brand, dense: true),
      const AppCountBadge(count: 150, child: Icon(Icons.notifications_rounded, size: AppIconSize.lg)),
      const AppCountBadge(count: 3),
      AppBadgePill(_tr('ذهبي', 'Gold'), color: c.accent2, icon: Icons.star_rounded),
    ]);

    final charts = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: AppTrendTile(
              label: _tr('الطلاب النشطون', 'Active students'), value: appCompactNumber(1284), delta: 12.5, spark: const [3, 5, 4, 8, 9, 7, 12], onTap: () {}),
        ),
        AppSpace.gapSm,
        Expanded(
          child: AppTrendTile(
              label: _tr('الغياب', 'Absences'), value: '48', delta: -3.0, upIsGood: false, icon: Icons.event_busy_rounded, spark: const [9, 8, 7, 7, 6]),
        ),
      ]),
      AppSpace.gapSm,
      AppCard(
        child: AppBarChart(
          title: _tr('التسجيلات', 'Enrolments'),
          series: [
            AppChartSeries(_tr('الطلاب', 'Students'), const [120, 340, 220, 980, 1284, 640]),
            AppChartSeries(_tr('المعلمون', 'Teachers'), const [12, 34, 22, 98, 128, 64]),
            AppChartSeries(_tr('أولياء الأمور', 'Parents'), const [40, 60, 50, 120, 200, 90]),
          ],
          labels: [_tr('سبتمبر', 'Sep'), _tr('أكتوبر', 'Oct'), _tr('نوفمبر', 'Nov'), _tr('ديسمبر', 'Dec'), _tr('يناير', 'Jan'), _tr('فبراير', 'Feb')],
        ),
      ),
      AppSpace.gapSm,
      AppCard(
        child: AppDonut(title: _tr('الأشخاص', 'People'), parts: [
          AppChartPart(_tr('طلاب', 'Students'), 820),
          AppChartPart(_tr('معلمون', 'Teachers'), 64),
          AppChartPart(_tr('أولياء أمور', 'Parents'), 120),
          AppChartPart(_tr('موظفون', 'Staff'), 30),
          AppChartPart(_tr('ضيوف', 'Guests'), 12),
        ]),
      ),
    ]);

    final states = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        padding: EdgeInsets.zero,
        child: AppEmpty(
          icon: Icons.menu_book_rounded,
          title: _tr('لا توجد دورات بعد', 'No courses yet'),
          message: _tr('أنشئ أول دورة لك وسيظهر الطلاب هنا بعد انضمامهم.', 'Create your first course; students appear here once they join.'),
          actionLabel: _tr('أنشئ دورة', 'Create a course'),
          onAction: () {},
        ),
      ),
      AppSpace.gapSm,
      AppCard(
        padding: EdgeInsets.zero,
        child: AppErrorState(message: _tr('انتهت مهلة الاتصال بالخادم.', 'The server took too long to answer.'), onRetry: () {}),
      ),
      AppSpace.gapSm,
      AppErrorState(compact: true, message: _tr('تعذّر تحديث القائمة.', 'The list could not be refreshed.'), onRetry: () {}),
      AppSpace.gapSm,
      const AppKpiGrid(maxColumns: 2, children: [AppKpiCard(label: 'a', value: '0', loading: true), AppKpiCard(label: 'b', value: '0', loading: true)]),
      AppSpace.gapSm,
      const AppListSkeleton(items: 2, padding: EdgeInsets.zero),
    ]);

    final left = [
      section('المؤشرات', 'Key figures', kpis),
      section('أرقام صغيرة', 'Counters', stats),
      section('بطاقات الإجراء', 'Action cards', actions),
      section('الشارات', 'Badges', badges),
    ];
    final right = [
      section('الرسوم', 'Charts', charts),
      section('الحالات', 'States', states),
    ];
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(children: left)),
          AppSpace.gapLg,
          Expanded(child: Column(children: right)),
        ])
      else ...[
        ...left,
        ...right,
      ],
    ]);
  }
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  testWidgets('kit cards sample', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final size in const [Size(390, 844), Size(1440, 900)]) {
        for (final lang in const ['ar', 'en']) {
          for (final dark in const [false, true]) {
            AppConfig.lang = lang;
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(size.width, size.width > 900 ? 1900 : 3600);
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
                home: RepaintBoundary(
                  key: _shot,
                  child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: const _Sample())),
                ),
              ),
            ));
            for (var i = 0; i < 12; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(tester.takeException(), isNull);
            await expectLater(find.byKey(_shot),
                matchesGoldenFile('goldens/kit_cards_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
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
