// The chart primitives (lib/design/app_charts.dart) at 320x640 and 1400x900, Arabic + English, textScaler 1.3,
// in light AND dark mode — plus the pure parts: the compact figure, the palette's lightness band, the semantics
// label that carries the values, and a tap that opens a bar group's values.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_charts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة';
const longEn = 'Office of Student Affairs, Graduate Studies and Scientific Research';

final series2 = [
  const AppChartSeries('Students', [120, 340, 220, 980, 1284, 640]),
  const AppChartSeries('Teachers', [12, 34, 22, 98, 128, 64]),
];
const labels6 = ['Sep', 'Oct', 'Nov', 'Dec', 'Jan', 'Feb'];

Widget gallery() => ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
          child: AppTrendTile(
              label: 'Active students', value: appCompactNumber(1284), delta: 12.5, spark: const [3, 5, 4, 8, 9, 7, 12]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AppTrendTile(
              label: longAr, value: '4.2M', delta: -3.0, upIsGood: false, icon: Icons.school_rounded, spark: const [9, 8, 7, 7, 6]),
        ),
      ]),
      const SizedBox(height: 16),
      const AppSparkline([1, 3, 2, 5, 4, 6, 8, 7], label: 'Views'),
      const SizedBox(height: 16),
      AppBarChart(series: series2, labels: labels6, title: 'Enrolments'),
      const SizedBox(height: 16),
      AppBarChart(series: [const AppChartSeries('Revenue', [5, 9, 2, 7])], labels: const [longEn, longAr, 'c', 'd'], height: 140),
      const SizedBox(height: 16),
      const AppBarChart(series: [], labels: [], title: 'Nothing'),
      const SizedBox(height: 16),
      const AppDonut(parts: [
        AppChartPart('Students', 820),
        AppChartPart('Teachers', 64),
        AppChartPart('Parents', 120),
        AppChartPart('Staff', 30),
        AppChartPart('Guests', 12),
        AppChartPart('Other', 5),
      ], title: 'People'),
      const SizedBox(height: 16),
      const AppDonut(parts: [AppChartPart('Only', 3)], size: 80, thickness: 10),
      const SizedBox(height: 16),
      const AppDonut(parts: [], legend: false),
      const SizedBox(height: 16),
      const AppLegend([AppLegendEntry('A', Colors.blue), AppLegendEntry(longAr, Colors.green)]),
    ]);

Widget themed(bool dark, Widget child) => Theme(
      data: ThemeData(brightness: dark ? Brightness.dark : Brightness.light, useMaterial3: true),
      child: Builder(builder: (context) => Material(color: Theme.of(context).scaffoldBackgroundColor, child: child)),
    );

void main() {
  setUp(() => AppConfig.lang = 'ar');

  test('appCompactNumber', () {
    expect(appCompactNumber(0), '0');
    expect(appCompactNumber(12), '12');
    expect(appCompactNumber(3.456), '3.5');
    expect(appCompactNumber(1284), '1.3K');
    expect(appCompactNumber(12900), '13K');
    expect(appCompactNumber(4200000), '4.2M');
    expect(appCompactNumber(-2500), '-2.5K');
    expect(appCompactNumber(1e9), '1B');
  });

  testWidgets('charts lay out at both sizes, both languages, light and dark', (tester) async {
    await expectNoLayoutErrors(tester, () => themed(false, gallery()));
    await expectNoLayoutErrors(tester, () => themed(true, gallery()));
  });

  testWidgets('palette: five slots inside the lightness band in light and dark', (tester) async {
    for (final dark in [false, true]) {
      late List<Color> palette;
      await tester.pumpWidget(layoutHost(themed(dark, Builder(builder: (context) {
        palette = appChartPalette(context);
        return const SizedBox();
      }))));
      await tester.pump();
      expect(palette.length, 5);
      expect(palette.toSet().length, 5, reason: 'distinct slots');
      final lo = dark ? 0.50 : 0.45, hi = dark ? 0.65 : 0.72;
      for (final c in palette) {
        final l = oklabLightness(c);
        expect(l, inInclusiveRange(lo - 0.011, hi + 0.011), reason: 'dark=$dark ${c.toARGB32().toRadixString(16)} L=$l');
      }
      // ignore: avoid_print
      print('palette dark=$dark: ${palette.map((c) => '#${c.toARGB32().toRadixString(16).substring(2)}').join(',')}');
    }
  });

  testWidgets('semantics carry the values; a tap opens a bar group', (tester) async {
    AppConfig.lang = 'en';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(layoutHost(Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        AppBarChart(series: series2, labels: labels6, title: 'Enrolments'),
        const AppDonut(parts: [AppChartPart('Students', 75), AppChartPart('Teachers', 25)], title: 'People'),
        const AppTrendTile(label: 'Active', value: '1.3K', delta: 12.5),
      ]),
    )));
    await tester.pump();
    final bar = tester.getSemantics(find.byType(AppBarChart));
    expect(bar.label, contains('Enrolments'));
    expect(bar.label, contains('Jan: Students 1.3K, Teachers 128'));
    final donut = tester.getSemantics(find.byType(AppDonut));
    expect(donut.label, contains('Students: 75 (75%)'));
    final tile = tester.getSemantics(find.byType(AppTrendTile));
    expect(tile.label, contains('Active: 1.3K, +12.5% ${'chart_vs_previous'.tr}'));

    final box = tester.getRect(find.byType(CustomPaint).first);
    await tester.tapAt(Offset(box.left + box.width * 0.5, box.top + box.height * 0.5));
    await tester.pump();
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
