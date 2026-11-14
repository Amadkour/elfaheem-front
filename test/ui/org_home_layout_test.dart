// The organization home body (org_dashboard_home.dart) on an OLDER server's payload — no `tasks` / `layout` /
// `tabs` (D-103 adds them; test/ui/org_home_v3_layout_test.dart covers those) — at 320x640 and 1400x900, Arabic +
// English, textScaler 1.3: every attention item as a row (the unknown key skipped), the departments, an empty
// organization, and the trend row the department page still draws. test/ui/a11y_guidelines_test.dart reuses
// [payload] and [body].
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/home/org_home_departments.dart';
import 'package:flutter_education_app/features/org/home/org_home_tasks.dart';
import 'package:flutter_education_app/features/org/org_dashboard_home.dart';
import 'package:flutter_education_app/features/org/org_dashboard_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'جامعة العلوم التطبيقية والتكنولوجيا الحديثة للدراسات العليا والبحث العلمي';
const longEn = 'University of Applied Sciences, Modern Technology, Graduate Studies and Scientific Research';

Map<String, dynamic> payload({bool members = true, bool series = true}) => {
      'organization': {'id': 4, 'name_ar': longAr, 'name_en': longEn, 'type': 'university'},
      'my_role': 'org_admin',
      'kpis': {'students': 12840, 'teachers': 380, 'staff': 125, 'courses': 140, 'departments': 6, 'programs': 4, 'sub_organizations': 2},
      if (members) 'members': {'students': 12840, 'teachers': 380, 'staff': 125, 'pending_join': 17},
      'pending_total': 31,
      'attention': [
        {'key': 'open_complaints', 'count': 5, 'severity': 'danger', 'overdue': 2},
        {'key': 'org_join_requests', 'count': 17, 'severity': 'warning'},
        {'key': 'schedule_unplaced', 'count': 9, 'severity': 'warning', 'schedules': [{'name': longAr}, {'name': longEn}]},
        {'key': 'expiring_memberships', 'count': 4, 'severity': 'info', 'days': 14, 'items': []},
        {'key': 'term_without_timetable', 'count': 1, 'severity': 'warning', 'terms': [{'id': 3, 'year_label': '2026/2027', 'kind': 'term1', 'status': 'current'}]},
        {'key': 'not_known_here', 'count': 2, 'severity': 'info'},
      ],
      if (series)
        'series': [
          for (var i = 0; i < 30; i++)
            {'date': '2026-10-${(i + 1).toString().padLeft(2, '0')}', 'joins': (i * 7) % 11, 'attendance': 120 + (i * 13) % 40, 'complaints': i % 4, 'work_items': 1},
        ],
      'departments': [
        {'id': 1, 'unit_type': 'dept', 'name_ar': longAr, 'name_en': longEn, 'team': 4, 'waiting': 3, 'color': '#2563EB', 'icon': 'support'},
        {'id': 2, 'unit_type': 'dept', 'name_ar': 'الإرشاد', 'name_en': 'Advising', 'team': 2, 'waiting': 0},
      ],
      'programs': [
        {'id': 9, 'unit_type': 'program', 'code': 'CS', 'name_ar': 'علوم الحاسب', 'name_en': 'Computer science', 'students': 3000, 'waiting': 12},
      ],
      'recent_activity': [
        {'summary': '$longAr $longEn', 'created_at': DateTime.now().toUtc().toIso8601String()},
      ],
    };

OrgHomeBody body(OrgHomeData d) => OrgHomeBody(
      data: d,
      alerts: [for (final a in d.alerts) ?OrgAttentionSpec.of(a, () {})],
      onOpenUnit: (_) {},
      onSeeAllUnits: () {},
    );

/// Pumps [w] once at the default test size (the harness ends on an empty tree) so finders see it.
Future<void> showOnce(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(layoutHost(w));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('older payload: every known attention item is a row (the unknown key skipped), departments as cards', (tester) async {
    await expectNoLayoutErrors(tester, () => body(OrgHomeData.fromJson(payload())!));
    await showOnce(tester, body(OrgHomeData.fromJson(payload())!));
    expect(find.byType(OrgAlertRow), findsNWidgets(5));
    expect(find.byType(OrgTaskRow), findsNothing);
    expect(find.byType(OrgDeptCard), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no members / series: the body is unchanged (the figures and trends live in Insights now)', (tester) async {
    await expectNoLayoutErrors(tester, () => body(OrgHomeData.fromJson(payload(members: false, series: false))!));
  });

  testWidgets('empty organization: all caught up, departments folded to one line', (tester) async {
    await expectNoLayoutErrors(tester, () => body(OrgHomeData.empty));
    await showOnce(tester, body(OrgHomeData.empty));
    expect(find.byType(OrgAllCaughtUp), findsOneWidget);
    expect(find.byType(OrgAlertRow), findsNothing);
    expect(find.byType(OrgDeptCard), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the trend row (the department page draws it) at every width', (tester) async {
    final d = OrgHomeData.fromJson(payload())!;
    await expectNoLayoutErrors(tester, () => ListView(children: [OrgTrendRow(trends: d.trends)]));
  });
}
