// AppKpiCard / AppKpiGrid / AppPageHeader / AppSection at 320 / 1400 wide, ar + en, textScaler 1.3.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_badges.dart';
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_kpi.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppTilt;
import 'package:flutter_education_app/design/app_page_header.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

const _longAr = 'لوحة متابعة الطلاب والمعلمين والحضور والغياب في جميع الأقسام والفصول الدراسية';

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');

  testWidgets('page header with every slot and a long Arabic title', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        AppPageHeader(
          title: _longAr,
          subtitle: _longAr,
          icon: Icons.dashboard_rounded,
          primaryAction: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('Add a new student')),
          actions: [
            IconButton(tooltip: 'a', onPressed: () {}, icon: const Icon(Icons.download_rounded)),
            IconButton(tooltip: 'b', onPressed: () {}, icon: const Icon(Icons.filter_list_rounded)),
          ],
          search: const TextField(),
          breadcrumbs: const ['Organization', 'Departments', 'Computer science and engineering'],
          onBack: () {},
          updatedAt: DateTime.now().subtract(const Duration(minutes: 3)),
          onRefresh: () {},
          bottom: const SizedBox(height: 40),
        ),
        const AppPageHeader(title: 'Plain', accent: false),
        AppSection(title: _longAr, subtitle: _longAr, trailing: TextButton(onPressed: () {}, child: const Text('See all')), child: const SizedBox(height: 40)),
      ]),
    );
  });

  testWidgets('page header: the more button opens the secondary actions on phones', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => AppPageHeader(
        title: 'T',
        actions: [IconButton(tooltip: 'a', onPressed: () {}, icon: const Icon(Icons.download_rounded))],
      ),
      act: (tester) async {
        final more = find.byIcon(Icons.more_horiz_rounded);
        if (more.evaluate().isNotEmpty) await tester.tap(more);
      },
    );
  });

  testWidgets('KPI grid with four cards', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        AppKpiGrid(children: [
          AppKpiCard(
              label: _longAr,
              value: '1,240,000',
              icon: Icons.people_alt_rounded,
              delta: 0.12,
              spark: const [3, 5, 4, 8, 7, 10],
              footnote: _longAr,
              highlight: true,
              onTap: () {}),
          const AppKpiCard(label: 'Absences', value: '48', icon: Icons.event_busy_rounded, delta: -0.045, deltaGoodWhenUp: false),
          const AppKpiCard(label: 'Loading', value: '0', loading: true),
          AppKpiCard(label: _longAr, value: '98.6%', delta: 0, deltaLabel: _longAr, spark: const [1, 2, 3], onTap: () {}),
          const AppKpiCard(label: 'Streak', value: '7', highlight: true, tone: AppBlockTone.gold, delta: 0.5, footnote: _longAr),
        ]),
        const SizedBox(height: 16),
        const AppKpiGrid(maxColumns: 2, children: [AppKpiCard(label: 'One', value: '1'), AppKpiCard(label: 'Two', value: '2'), AppKpiCard(label: 'Three', value: '3')]),
      ]),
    );
  });

  group('behaviour', () {
    testWidgets('delta 0.12 shows +12 and a bad delta uses the danger colour', (tester) async {
      await tester.pumpWidget(layoutHost(const SingleChildScrollView(
        child: Column(children: [
          AppKpiCard(label: 'Up', value: '1', delta: 0.12),
          AppKpiCard(label: 'Down', value: '2', delta: -0.08),
          AppKpiCard(label: 'Fewer absences', value: '3', delta: -0.08, deltaGoodWhenUp: false),
        ]),
      )));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(ltrIsolate('+12%')), findsOneWidget);
      expect(find.text(ltrIsolate('-8%')), findsNWidgets(2) ,reason: '-8.0 rounds to 8 under the one-decimal rule');
      final ctx = tester.element(find.text(ltrIsolate('+12%')));
      Color fgOf(Finder chip) => tester.widget<Text>(find.descendant(of: chip, matching: find.byType(Text))).style!.color!;
      // the ink is the tone itself where it reads on its tint, else the tone darkened until it does (hue kept)
      expect(fgOf(find.byKey(const ValueKey('kpi.delta.good')).first), appToneInk(ctx, AppTone.success));
      final bad = find.byKey(const ValueKey('kpi.delta.bad'));
      expect(bad, findsOneWidget);
      expect(fgOf(bad), appToneInk(ctx, AppTone.danger));
    });

    testWidgets('the highlight card is a block in its tone; the others are paper', (tester) async {
      await tester.pumpWidget(layoutHost(const SingleChildScrollView(
        child: Column(children: [
          AppKpiCard(label: 'Key', value: '1', highlight: true),
          AppKpiCard(label: 'Gold', value: '7', highlight: true, tone: AppBlockTone.gold),
          AppKpiCard(label: 'Paper', value: '2'),
        ]),
      )));
      await tester.pump(const Duration(milliseconds: 100));
      final blocks = tester.widgetList<AppBlock>(find.byType(AppBlock)).toList();
      expect(blocks.map((b) => b.tone), [AppBlockTone.peach, AppBlockTone.gold]);
      expect(find.byType(AppTilt), findsNWidgets(2), reason: 'only the key figures lean; paper cards stay flat');
    });

    testWidgets('semantics read "label: value"', (tester) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(layoutHost(AppKpiCard(label: 'Students', value: '1240', onTap: () {})));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Students: 1240'), findsOneWidget);
      h.dispose();
    });
  });
}
