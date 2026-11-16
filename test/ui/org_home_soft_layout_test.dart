// The soft-wash organization home (D-1081): with `home_stats` the page opens with the greeting line and the four
// counts with their 8-week bars, "Needs me" wears the highlight edge, and no forest hero is drawn. Every state
// (empty · partial · full · worst case) through expectNoLayoutErrors (320×640 and 1400×900, ar / en, text ×1.3).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppHighlightEdge, AppMiniBars, AppStatCard;
import 'package:flutter_education_app/features/org/org_dashboard_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';
import 'org_home_premium_layout_test.dart' show body, worstPayload;
import 'org_home_v3_layout_test.dart' show adminPayload, emptyMemberPayload;

Map<String, dynamic> withStats(Map<String, dynamic> m, Map<String, dynamic> stats) => {...m, 'home_stats': stats};

const _empty = {
  'votes_waiting': 0,
  'requests_open': 0,
  'requests_overdue': 0,
  'members': 0,
  'votes_weeks': [0, 0, 0, 0, 0, 0, 0, 0],
  'requests_weeks': [0, 0, 0, 0, 0, 0, 0, 0],
  'members_weeks': [0, 0, 0, 0, 0, 0, 0, 0],
  'next_session': null,
};

const _full = {
  'votes_waiting': 6,
  'requests_open': 9,
  'requests_overdue': 3,
  'members': 48,
  'votes_weeks': [3, 2, 4, 3, 5, 4, 6, 6],
  'requests_weeks': [8, 11, 9, 14, 12, 16, 13, 18],
  'members_weeks': [30, 33, 35, 38, 40, 43, 45, 48],
  'next_session': {'id': 7, 'title': 'مجلس القسم', 'at': '2026-11-22T08:00:00', 'council_ar': 'مجلس القسم', 'council_en': 'Department council'},
};

const _worst = {
  'votes_waiting': 99999,
  'requests_open': 1284000,
  'requests_overdue': 98765,
  'members': 1284000,
  'votes_weeks': [0, 99999, 0, 99999, 0, 99999, 0, 99999],
  'requests_weeks': [1284000, 0, 0, 0, 0, 0, 0, 1],
  'members_weeks': [1, 2, 3, 4, 5, 6, 7, 1284000],
  'next_session': {
    'id': 1,
    'title': 'الجلسة الاستثنائية الطارئة لمجلس الكلية لمناقشة اللائحة الداخلية الجديدة للدراسات العليا',
    'at': '2026-12-31T21:30:00',
    'council_ar': 'مجلس كلية الحاسبات والمعلومات وتكنولوجيا الاتصالات',
    'council_en': 'Council of the Faculty of Computers, Information and Communication Technology',
  },
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
  });

  test('home_stats parses; an older server has none', () {
    final s = OrgHomeData.fromJson(withStats(adminPayload(), _full))!.homeStats!;
    expect(s.requestsOverdue, 3);
    expect(s.membersWeeks.last, 48);
    expect(s.nextSessionAt, DateTime.utc(2026, 11, 22, 8));
    AppConfig.lang = 'en';
    expect(s.nextSessionCouncil, 'Department council');
    expect(OrgHomeData.fromJson(adminPayload())!.homeStats, isNull);
  });

  testWidgets('soft home: four counts with bars, a greeting line, the one highlighted card, no hero', (tester) async {
    AppConfig.lang = 'en';
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(layoutHost(body(withStats(adminPayload(), _full))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('org.home.greeting')), findsOneWidget);
    expect(find.byKey(const ValueKey('org.home.hero')), findsNothing);
    expect(find.byType(AppStatCard), findsNWidgets(4));
    expect(find.byType(AppMiniBars), findsNWidgets(3), reason: 'the next session has no bars');
    expect(find.byType(AppHighlightEdge), findsOneWidget);
    final requests = tester.widget<AppStatCard>(find.byKey(const ValueKey('org.home.stat.requests')));
    expect(requests.warn, isTrue);
  });

  testWidgets('soft home: empty', (tester) async {
    await expectNoLayoutErrors(tester, () => body(withStats(emptyMemberPayload(), _empty), admin: false, name: ''));
  });

  testWidgets('soft home: full', (tester) async {
    await expectNoLayoutErrors(tester, () => body(withStats(adminPayload(), _full)));
  });

  testWidgets('soft home: worst case (huge counts, long names)', (tester) async {
    await expectNoLayoutErrors(tester, () => body(withStats(worstPayload(), _worst), name: 'Bartholomew-Fitzgerald'));
  });
}
