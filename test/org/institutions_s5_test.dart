// Institutions S5 (D-979): the faculty overview's payload (`faculty` in GET …/governance/dashboard?scope=faculty),
// the items-list filter behind a row and its figures (incl. the new `escalated` axis), the home flag
// `can_faculty_overview`, and the layout of the home card and the overview body (cards on phones, a table on wide).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/governance/gov_faculty_overview.dart';
import 'package:flutter_education_app/features/org/governance/gov_filter.dart';
import 'package:flutter_education_app/features/org/org_dashboard_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> row(int id, String ar, String en, {String kind = 'service', String? level, List<int> n = const [0, 0, 0, 0, 0]}) => {
      'id': id,
      'name_ar': ar,
      'name_en': en,
      'kind': kind,
      'icon': null,
      'color': null,
      'template_key': null,
      'council_level': level,
      'has_council': level != null,
      'open': n[0],
      'overdue': n[1],
      'escalated': n[2],
      'council_pending': n[3],
      'sessions_closing': n[4],
    };

Map<String, dynamic> dashboardJson({String scope = 'all'}) => {
      'pending': 9,
      'overdue': 2,
      'faculty': {
        'scope': scope,
        'portfolios': scope == 'portfolio' ? ['vice_dean_postgraduate_research'] : <String>[],
        'closing_hours': 48,
        'generated_at': '2026-11-15T10:00:00',
        'totals': {'open': 9, 'overdue': 2, 'escalated': 2, 'council_pending': 3, 'sessions_closing': 1},
        'departments': [
          row(3, 'شئون الطلاب والخريجين ورعاية الشباب — اسم طويل جداً', 'Student affairs, graduates and youth care — a very long name', n: [3, 2, 1, 0, 0]),
          row(7, 'قسم الرياضيات', 'Mathematics', kind: 'scientific', level: 'department', n: [3, 0, 0, 2, 1]),
          row(9, 'مجلس الكلية', 'Faculty council', kind: 'council', level: 'faculty', n: [1, 0, 0, 1, 0]),
          row(11, 'المكتبة', '', n: [0, 0, 0, 0, 0]),
        ],
      },
    };

void main() {
  setUp(() => AppConfig.lang = 'ar');

  group('payload', () {
    test('the faculty block parses; absent = null', () {
      final f = FacultyOverview.fromDashboard(dashboardJson())!;
      expect(f.scope, 'all');
      expect(f.isPortfolio, isFalse);
      expect(f.totals, {'open': 9, 'overdue': 2, 'escalated': 2, 'council_pending': 3, 'sessions_closing': 1});
      expect(f.rows.map((r) => r.id).toList(), [3, 7, 9, 11]);
      final math = f.rows[1];
      expect(math.count('council_pending'), 2);
      expect(math.councilLevel, 'department');
      expect(math.hasCouncil, isTrue);
      expect(f.rows[2].isCouncil, isTrue);
      expect(f.rows[3].isQuiet, isTrue);
      expect(FacultyOverview.fromDashboard({'pending': 1}), isNull);
      expect(FacultyOverview.fromDashboard(dashboardJson(scope: 'portfolio'))!.portfolios, ['vice_dean_postgraduate_research']);
    });

    test('names follow the language, falling back to the other one', () {
      final lib = FacultyRow.fromJson(row(11, 'المكتبة', ''));
      expect(lib.name, 'المكتبة');
      AppConfig.lang = 'en';
      expect(lib.name, 'المكتبة');
      expect(FacultyRow.fromJson(row(7, 'قسم الرياضيات', 'Mathematics')).name, 'Mathematics');
      expect(FacultyRow.fromJson(row(5, '', '')).name, '#5');
    });

    test('the home flag', () {
      expect(OrgHomeData.fromJson({'can_faculty_overview': true})!.canFacultyOverview, isTrue);
      expect(OrgHomeData.fromJson(const <String, dynamic>{})!.canFacultyOverview, isFalse);
    });
  });

  group('row → items filter', () {
    test('each figure opens the list on its state', () {
      expect(facultyRowFilter(3).toQuery(), {'status': 'open,in_review,pending_approval,in_council,postponed', 'dept_id': 3});
      expect(facultyRowFilter(3, 'overdue').toQuery(), {'dept_id': 3, 'overdue': true});
      expect(facultyRowFilter(3, 'escalated').toQuery(), {'dept_id': 3, 'escalated': true});
      expect(facultyRowFilter(7, 'council_pending').toQuery(), {'status': 'in_council', 'dept_id': 7});
    });

    test('the escalated axis round-trips, counts, has a chip and clears', () {
      const f = ItemFilter(escalated: true);
      expect(ItemFilter.fromQuery(f.toQuery()), f);
      expect(ItemFilter.fromQuery({'escalated': '1'}).escalated, isTrue);
      expect(f.activeCount, 1);
      expect(f.chips().map((c) => c.key), ['escalated']);
      expect(f.without('escalated').isEmpty, isTrue);
      expect(f.copyWith(q: 'x').escalated, isTrue);
    });
  });

  group('layout', () {
    testWidgets('home card', (tester) async {
      await expectNoLayoutErrors(tester, () => Padding(padding: const EdgeInsets.all(16), child: OrgFacultyOverviewCard(onOpen: () {})));
    });

    testWidgets('overview body (phone cards / wide table), portfolio note, empty', (tester) async {
      await expectNoLayoutErrors(tester, () => FacultyOverviewBody(data: FacultyOverview.fromDashboard(dashboardJson())!, onOpen: (_, _) {}));
      await expectNoLayoutErrors(tester, () => FacultyOverviewBody(data: FacultyOverview.fromDashboard(dashboardJson(scope: 'portfolio'))!));
      await expectNoLayoutErrors(tester, () => const FacultyOverviewBody(data: FacultyOverview()));
    });

    testWidgets('a tap reports the row and the figure', (tester) async {
      final taps = <String>[];
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(layoutHost(FacultyOverviewBody(
          data: FacultyOverview.fromDashboard(dashboardJson())!, onOpen: (r, m) => taps.add('${r.id}:${m ?? '-'}'))));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('متأخرة 2'));
      await tester.tap(find.text('قسم الرياضيات'));
      expect(taps, ['3:overdue', '7:-']);
    });
  });
}
