// The organization dashboard's Insights (lib/features/org/insights/), D-103: the parser against REAL server captures
// (test/fixtures/payloads/org_insights.json = the default period, org_insights_term.json = ?term_id=1, from the local
// stack), the card choice, the plain-language sentences in both languages, the suggestions, the period choice, and the
// live section's states over a fake source.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/insights/org_insights.dart';
import 'package:flutter_education_app/features/org/insights/org_insights_api.dart';
import 'package:flutter_education_app/features/org/insights/org_insights_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/layout_harness.dart' show layoutHost;

Object? _fixture(String name) => jsonDecode(File('test/fixtures/payloads/$name').readAsStringSync());

OrgInsightMetric _m(String key, {double? value, double? previous, String unit = 'percent', Map<String, Object?> extra = const {}}) =>
    OrgInsightMetric.fromJson({'key': key, 'available': true, 'value': value, 'previous': previous, 'unit': unit, 'series': [], ...extra});

const _term = OrgInsightPeriod(termId: 3);
final _days30 = OrgInsightPeriod(from: DateTime.utc(2026, 10, 2), to: DateTime.utc(2026, 10, 31));

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('parser (real captures)', () {
    test('default period: last 30 days, five metrics, one suggestion', () {
      final d = OrgInsights.fromJson(_fixture('org_insights.json'));
      expect(d.period.termId, isNull);
      expect(d.period.granularity, 'day');
      expect(d.period.days, 30);
      expect(d.period.previousTo, DateTime.utc(2026, 10, 1));
      expect(d.orgWide, isTrue);
      expect(d.terms.map((x) => x.id), [2, 1]);
      expect(d.terms.first.status, 'upcoming');
      expect(d.metrics.map((m) => m.key), ['attendance', 'enrollment', 'completion', 'grades', 'pending']);
      final att = d.metric('attendance')!;
      expect(att.shown, isTrue);
      expect(att.value, 25.0);
      expect(att.sessions, 4);
      expect(att.series.length, 30);
      // days without a session carry null: left out of the line, never drawn as 0
      expect(att.points.length, lessThan(att.series.length));
      expect(att.points.every((p) => p.value != null), isTrue);
      expect(d.metric('enrollment')!.total, 20);
      expect(d.metric('completion')!.shown, isFalse);
      expect(d.metric('pending')!.parts, {'work_pending': 1});
      expect(d.suggestions.single.key, 'attendance_drop');
      expect(d.suggestions.single.link.section, 'academics');
      expect(d.suggestions.single.link.sub, 'courses');
      expect(d.generatedAt, isNotNull);
    });

    test('a term period: weekly series; grades available without a value is not drawn', () {
      final d = OrgInsights.fromJson(_fixture('org_insights_term.json'));
      expect(d.period.termId, 1);
      expect(d.period.granularity, 'week');
      final g = d.metric('grades')!;
      expect(g.available, isTrue);
      expect(g.value, isNull);
      expect(g.shown, isFalse);
      expect(g.coverage, 0.0);
      expect(d.metric('completion')!.runs, 0);
      expect(orgInsightCards(d).map((m) => m.key), ['enrollment', 'pending']);
    });

    test('a broken or empty payload never throws', () {
      final d = OrgInsights.fromJson({'metrics': 'x', 'terms': [1, {'id': 'a'}], 'suggestions': [{'key': ''}]});
      expect(d.metrics, isEmpty);
      expect(d.terms, isEmpty);
      expect(d.suggestions, isEmpty);
      expect(OrgInsights.fromJson(null).period.days, 0);
    });

    test('suggestions: risk first', () {
      final d = OrgInsights.fromJson({
        'suggestions': [
          {'key': 'low_completion', 'severity': 'watch', 'value': 45},
          {'key': 'unplaced_sessions', 'severity': 'risk', 'value': 3, 'link': {'section': 'timetable', 'sub': 'unplaced', 'kind': 'org_schedule', 'id': 9}},
        ],
      });
      expect(d.suggestions.map((s) => s.key), ['unplaced_sessions', 'low_completion']);
    });
  });

  group('cards', () {
    test('at most four, in the fixed order, only with a figure', () {
      final d = OrgInsights(metrics: [
        _m('pending', value: 3, unit: 'count'),
        _m('grades', value: 74, unit: 'score'),
        _m('attendance', value: 82),
        _m('completion', value: 60),
        _m('enrollment', value: 12, unit: 'count'),
      ]);
      expect(orgInsightCards(d).map((m) => m.key), ['attendance', 'enrollment', 'completion', 'grades']);
    });

    test('figures', () {
      expect(orgInsightFigure(_m('attendance', value: 82.4)), '82%');
      expect(orgInsightFigure(_m('attendance', value: 7.25)), '7.3%');
      expect(orgInsightFigure(_m('enrollment', value: 1284, unit: 'count')), '1.3K');
      expect(orgInsightFigure(_m('enrollment', value: 12, unit: 'count')), '12');
    });
  });

  group('change in plain words', () {
    test('percent: points, rounded; up is good except the queue', () {
      final c = orgInsightChange(_m('attendance', value: 82, previous: 87))!;
      expect(c.text, '5 points lower');
      expect(c.short, '5 points');
      expect(c.direction, -1);
      expect(c.good, isFalse);
      expect(orgInsightChange(_m('attendance', value: 83, previous: 82))!.text, '1 point higher');
      expect(orgInsightChange(_m('attendance', value: 82.3, previous: 82))!.direction, 0);
      expect(orgInsightChange(_m('attendance', value: 82)), isNull);
      expect(orgInsightChange(_m('pending', value: 9, previous: 4, unit: 'count'))!.good, isFalse);
    });

    test('count: more / fewer', () {
      expect(orgInsightChange(_m('enrollment', value: 12, previous: 8, unit: 'count'))!.text, '4 more');
      expect(orgInsightChange(_m('enrollment', value: 2, previous: 8, unit: 'count'))!.text, '6 fewer');
    });

    test('Arabic', () {
      AppConfig.lang = 'ar';
      expect(orgInsightChange(_m('attendance', value: 82, previous: 87))!.text, 'أقل بـ5 نقاط');
      expect(orgInsightChange(_m('attendance', value: 83, previous: 82))!.text, 'أعلى بنقطة واحدة');
      expect(orgInsightChange(_m('attendance', value: 84, previous: 82))!.text, 'أعلى بنقطتين');
      expect(orgInsightChange(_m('attendance', value: 70, previous: 82))!.text, 'أقل بـ12 نقطة');
      expect(orgInsightChange(_m('enrollment', value: 12, previous: 8, unit: 'count'))!.text, 'أكثر بـ4');
    });
  });

  group('summary sentence', () {
    test('English', () {
      expect(orgInsightSummary(_m('attendance', value: 82, previous: 87), _term),
          'Attendance is 82%, 5 points lower than the previous term.');
      expect(orgInsightSummary(_m('attendance', value: 82, previous: 82.2), _days30),
          'Attendance is 82%, about the same as the previous 30 days.');
      expect(orgInsightSummary(_m('attendance', value: 25, extra: {'sessions': 4}), _days30), 'Attendance is 25% across 4 sessions.');
      expect(orgInsightSummary(_m('enrollment', value: 12, previous: 8, unit: 'count'), _days30),
          '12 new enrollments, 4 more than the previous 30 days.');
      expect(orgInsightSummary(_m('enrollment', value: 0, unit: 'count', extra: {'total': 320}), _days30),
          'No new enrollments in this period; 320 students are enrolled now.');
      expect(orgInsightSummary(_m('completion', value: 64, previous: 61), _term),
          '64% of students passed, 3 points higher than the previous term.');
      expect(orgInsightSummary(_m('grades', value: 74, unit: 'score', extra: {'coverage': 80}), _term),
          'The average grade is 74%; 80% of grades are in so far.');
      expect(orgInsightSummary(_m('pending', value: 7, unit: 'count', extra: {'oldest_days': 9}), _days30),
          '7 items are waiting for a decision; the oldest for 9 days.');
      expect(orgInsightSummary(_m('pending', value: 0, unit: 'count'), _days30), 'Nothing is waiting for a decision.');
    });

    test('Arabic', () {
      AppConfig.lang = 'ar';
      expect(orgInsightSummary(_m('attendance', value: 82, previous: 87), _term), 'نسبة الحضور 82%، أقل بـ5 نقاط من الفصل السابق.');
      expect(orgInsightSummary(_m('attendance', value: 25, extra: {'sessions': 4}), _days30), 'نسبة الحضور 25% في 4 جلسات.');
      expect(orgInsightSummary(_m('attendance', value: 25, extra: {'sessions': 14}), _days30), 'نسبة الحضور 25% في 14 جلسة.');
      expect(orgInsightSummary(_m('enrollment', value: 12, previous: 8, unit: 'count'), _days30),
          'التسجيلات الجديدة: 12، أكثر بـ4 من الأيام الـ30 السابقة.');
      expect(orgInsightSummary(_m('pending', value: 7, unit: 'count', extra: {'oldest_days': 2}), _days30),
          'بانتظار القرار: 7، أقدمها منذ يومين.');
      expect(orgInsightSummary(_m('pending', value: 7, unit: 'count', extra: {'oldest_days': 12}), _days30),
          'بانتظار القرار: 7، أقدمها منذ 12 يومًا.');
    });

    test('the compared period follows the window', () {
      expect(orgInsightCompared(const OrgInsightPeriod(termId: 1)), 'the previous term');
      expect(orgInsightCompared(_days30), 'the previous 30 days');
      expect(orgInsightCompared(OrgInsightPeriod(from: DateTime.utc(2026), to: DateTime.utc(2026, 12, 31))), 'the previous period');
    });

    test('Arabic counts', () {
      String n(int x) => arCount(x, one: 'جلسة واحدة', two: 'جلستين', few: 'جلسات', many: 'جلسة');
      expect([n(1), n(2), n(3), n(10), n(11), n(103)], ['جلسة واحدة', 'جلستين', '3 جلسات', '10 جلسات', '11 جلسة', '103 جلسات']);
      expect(arSinceDays(1), 'منذ يوم');
      expect(arSinceDays(5), 'منذ 5 أيام');
    });
  });

  group('suggestions', () {
    final d = OrgInsights(terms: const [OrgInsightTerm(id: 4, labelAr: 'الفصل الأول 2026/2027', labelEn: 'Term 1 2026/2027', status: 'finished')]);

    test('sentences and their one action', () {
      const drop = OrgInsightSuggestion(key: 'attendance_drop', severity: 'risk', value: 25, previous: 40);
      expect(orgSuggestionText(drop, d), 'Attendance fell to 25% from 40% — see which courses are losing students.');
      expect(orgSuggestionAction(drop), 'Review courses');
      expect(orgSuggestionText(const OrgInsightSuggestion(key: 'attendance_drop', value: 25), d),
          'Attendance is only 25% — see which courses are losing students.');
      const grades = OrgInsightSuggestion(key: 'grades_missing', value: 6, termId: 4);
      expect(orgSuggestionText(grades, d), 'Grades are still missing for 6 courses in Term 1 2026/2027.');
      const unplaced = OrgInsightSuggestion(key: 'unplaced_sessions', value: 1);
      expect(orgSuggestionText(unplaced, d), '1 session still has no place in the timetable.');
      expect(orgSuggestionAction(unplaced), 'Open timetable');
      const backlog = OrgInsightSuggestion(key: 'pending_backlog', value: 23, oldestDays: 9, link: OrgInsightLink(section: 'services', sub: 'complaints'));
      expect(orgSuggestionText(backlog, d), '23 items are waiting for a decision, the oldest for 9 days.');
      expect(orgSuggestionAction(backlog), 'Open complaints');
      expect(orgSuggestionAction(const OrgInsightSuggestion(key: 'pending_backlog', link: OrgInsightLink(section: 'people', sub: 'join_requests'))),
          'Review requests');
      expect(orgSuggestionText(const OrgInsightSuggestion(key: 'something_new'), d), 'Something here needs a look.');
      AppConfig.lang = 'ar';
      expect(orgSuggestionText(unplaced, d), 'حصة واحدة بلا مكان في الجدول بعد.');
      expect(orgSuggestionText(const OrgInsightSuggestion(key: 'unplaced_sessions', value: 5), d), '5 حصص بلا مكان في الجدول بعد.');
      expect(orgSuggestionText(grades, d), 'لم تُرصد درجات 6 مقررات في الفصل الأول 2026/2027.');
    });

    test('links → the org shell', () {
      expect(orgInsightTarget(const OrgInsightLink(section: 'timetable', sub: 'unplaced', kind: 'org_schedule', id: 9)), ('timetable', 'open:9'));
      expect(orgInsightTarget(const OrgInsightLink(section: 'academics', sub: 'registrar', kind: 'org_term', id: 4)), ('academics', 'registrar'));
      expect(orgInsightTarget(const OrgInsightLink(section: 'academics', sub: 'courses')), ('academics', 'courses'));
      expect(orgInsightTarget(const OrgInsightLink()), isNull);
    });
  });

  group('period choice', () {
    const terms = [
      OrgInsightTerm(id: 3, status: 'upcoming'),
      OrgInsightTerm(id: 2, status: 'current'),
      OrgInsightTerm(id: 1, status: 'finished'),
    ];
    final today = DateTime.utc(2026, 10, 31);

    test('chips follow the terms', () {
      expect(orgPeriodKinds(terms), OrgPeriodKind.values);
      expect(orgPeriodKinds(const [OrgInsightTerm(id: 1, status: 'upcoming')]), [OrgPeriodKind.last30, OrgPeriodKind.custom]);
    });

    test('queries', () {
      expect(const OrgPeriodChoice(OrgPeriodKind.thisTerm).query(terms, today), {'term_id': '2'});
      expect(const OrgPeriodChoice(OrgPeriodKind.lastTerm).query(terms, today), {'term_id': '1'});
      expect(const OrgPeriodChoice(OrgPeriodKind.last30).query(terms, today), {'date_from': '2026-10-02', 'date_to': '2026-10-31'});
      expect(OrgPeriodChoice(OrgPeriodKind.custom, from: DateTime.utc(2026, 9, 1), to: DateTime.utc(2026, 9, 30)).query(terms, today),
          {'date_from': '2026-09-01', 'date_to': '2026-09-30'});
      expect(const OrgPeriodChoice(OrgPeriodKind.thisTerm).query(const [], today), isNull);
    });

    test('saved form round-trips; a broken one is dropped', () {
      final c = OrgPeriodChoice(OrgPeriodKind.custom, from: DateTime.utc(2026, 9, 1), to: DateTime.utc(2026, 9, 30));
      expect(OrgPeriodChoice.fromJson(jsonDecode(jsonEncode(c.toJson()))), c);
      expect(OrgPeriodChoice.fromJson({'kind': 'custom', 'from': '2026-09-30', 'to': '2026-09-01'}), isNull);
      expect(OrgPeriodChoice.fromJson({'kind': 'nope'}), isNull);
      expect(OrgPeriodChoice.fromJson('x'), isNull);
    });

    test('the selected chip of a default answer', () {
      expect(orgPeriodKindOf(const OrgInsights(), null), OrgPeriodKind.last30);
      expect(orgPeriodKindOf(const OrgInsights(period: OrgInsightPeriod(termId: 2), terms: terms), null), OrgPeriodKind.thisTerm);
      expect(orgPeriodKindOf(const OrgInsights(period: OrgInsightPeriod(termId: 1), terms: terms), null), OrgPeriodKind.lastTerm);
      expect(orgPeriodKindOf(const OrgInsights(), const OrgPeriodChoice(OrgPeriodKind.custom)), OrgPeriodKind.custom);
    });
  });

  group('the live section', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> pump(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(layoutHost(SingleChildScrollView(child: w), scale: 1));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('loads after the first frame, draws the cards and the suggestion', (tester) async {
      final asked = <Map<String, String>?>[];
      final data = OrgInsights.fromJson(_fixture('org_insights.json'));
      await pump(
        tester,
        OrgInsightsSection(
          orgId: 1,
          source: (o, q) async {
            asked.add(q);
            return OrgInsightsLoad.ok(data);
          },
          onOpenLink: (_) {},
        ),
      );
      expect(asked, [null]); // the server's default, once
      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('Attendance'), findsOneWidget);
      expect(find.text('25%'), findsWidgets); // the big figure (and the chart's read-out of the last day)
      expect(find.text('Review courses'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking a chip asks again and is remembered per organization', (tester) async {
      final asked = <Map<String, String>?>[];
      final data = OrgInsights.fromJson(_fixture('org_insights.json'));
      await pump(tester, OrgInsightsSection(orgId: 7, source: (o, q) async {
        asked.add(q);
        return OrgInsightsLoad.ok(data);
      }));
      await tester.tap(find.text('Last 30 days'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(asked.length, 2);
      expect(asked.last!.keys, containsAll(['date_from', 'date_to']));
      final p = await SharedPreferences.getInstance();
      expect(jsonDecode(p.getString('org_insights_period_7')!)['kind'], 'last30');
    });

    testWidgets('an older server keeps the fallback; 403 draws nothing; an error offers Retry', (tester) async {
      await pump(tester, OrgInsightsSection(orgId: 1, fallback: const Text('old trends'), source: (o, q) async => const OrgInsightsLoad.missing()));
      expect(find.text('old trends'), findsOneWidget);
      await pump(tester, OrgInsightsSection(orgId: 2, fallback: const Text('old trends'), source: (o, q) async => const OrgInsightsLoad.forbidden('org_forbidden')));
      expect(find.text('Insights'), findsNothing);
      expect(find.text('old trends'), findsNothing);
      var calls = 0;
      await pump(tester, OrgInsightsSection(orgId: 3, source: (o, q) async {
        calls++;
        return calls == 1 ? const OrgInsightsLoad.failed('Network down') : const OrgInsightsLoad.ok(OrgInsights());
      }));
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, 2);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('the kill switch hides it', (tester) async {
      final prev = List<String>.from(AppConfig.disableList);
      addTearDown(() => AppConfig.disableList = prev);
      AppConfig.disableList = [...prev, orgInsightsFeatureKey];
      await pump(tester, OrgInsightsSection(orgId: 1, source: (o, q) async => const OrgInsightsLoad.ok(OrgInsights())));
      expect(find.text('Insights'), findsNothing);
    });
  });
}
