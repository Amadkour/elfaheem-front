// The redesigned Overview (AdminHomeBody): greeting hero + search, ONE greeting hero, the figures as stat cards, students and teachers counted
// apart, "Needs your attention" as one list, "Nothing waits" only when nothing does, and a layout check.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppGreetingHero, AppStatCard;
import 'package:flutter_education_app/features/admin/admin_global_search.dart';
import 'package:flutter_education_app/features/admin/admin_home_body.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_test/flutter_test.dart';

import '../admin_home_layout_test.dart' as base;
import '../layout_harness.dart';

Future<void> _pump(WidgetTester tester, Widget w, {Size size = const Size(1400, 900)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(layoutHost(w, scale: 1));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');

  testWidgets('shows the greeting with the name, the search field and exactly one hero', (tester) async {
    final data = AdminHomeData.fromOverview(base.fullPayload());
    await _pump(tester, AdminHomeBody(data: data, name: 'Ahmed', pendingPayouts: 3));
    expect(find.textContaining('Ahmed'), findsWidgets);
    expect(find.byType(AdminSearchLauncher), findsOneWidget);
    final cards = tester.widgetList<AppStatCard>(find.byType(AppStatCard)).toList();
    // revenue · students · teachers · courses + subscribers, then the four health counts (soft-wash cards since D-1081)
    expect(cards.length, 9);
    expect(find.byType(AppGreetingHero), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('students and teachers are separate KPIs, each opening its own tab', (tester) async {
    final data = AdminHomeData.fromOverview(base.fullPayload());
    var opened = '';
    await _pump(
        tester,
        AdminHomeBody(
            data: data,
            name: 'A',
            actions: AdminHomeActions(openStudents: () => opened = 'students', openTeachers: () => opened = 'teachers')));
    final cards = tester.widgetList<AppStatCard>(find.byType(AppStatCard)).toList();
    final students = cards.firstWhere((c) => c.value == '128.4K' || c.value.contains('128'));
    final teachers = cards.firstWhere((c) => c.value.contains('8.4K') || c.value == '8,400');
    students.onTap!();
    expect(opened, 'students');
    teachers.onTap!();
    expect(opened, 'teachers');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('"Nothing waits for you" is shown only when nothing waits', (tester) async {
    final quiet = AdminHomeData.fromOverview({'students': 3, 'teachers': 1, 'courses': 2});
    await _pump(tester, AdminHomeBody(data: quiet, name: 'A'));
    expect(find.text('admin_home_all_clear'.tr), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));

    final busy = AdminHomeData.fromOverview({
      'students': 3,
      'alerts': [
        {'key': 'transfers_pending', 'severity': 'warning', 'count': 2}
      ],
    });
    await _pump(tester, AdminHomeBody(data: busy, name: 'A', pendingPayouts: 1));
    expect(find.text('admin_home_all_clear'.tr), findsNothing);
    expect(find.text('admin_pending_transfers'.tr), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('lays out at every size and language (full, older server, empty)', (tester) async {
    await expectNoLayoutErrors(
        tester, () => AdminHomeBody(data: AdminHomeData.fromOverview(base.fullPayload()), name: base.longName, pendingPayouts: 240));
    await expectNoLayoutErrors(tester, () => AdminHomeBody(data: AdminHomeData.fromOverview(base.legacyPayload()), name: 'A'));
    await expectNoLayoutErrors(tester, () => AdminHomeBody(data: AdminHomeData.fromOverview(const {}), name: ''));
  });
}
