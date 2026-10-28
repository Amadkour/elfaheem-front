// The org-admin home (org_dashboard_home.dart) at 320x640 and 1400x900, Arabic + English, textScaler 1.3:
// the full payload (members, trends, queue, shortcuts, units, activity), an older server's payload (no members /
// series → the tiles hide), an empty organization, the loading skeleton and the failed state's hero.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppTrendTile;
import 'package:flutter_education_app/design/home_kit.dart' show HomeShortcut;
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
        {'summary': 'Approved a join request', 'created_at': '2026-10-28T08:00:00'},
      ],
    };

OrgHeroSpec hero({bool full = true}) => OrgHeroSpec(
      name: AppConfig.lang == 'ar' ? longAr : longEn,
      typeLabel: AppConfig.lang == 'ar' ? 'جامعة' : 'University',
      typeIcon: Icons.account_balance_rounded,
      statusLabel: AppConfig.lang == 'ar' ? 'مفعّلة' : 'Active',
      roleLabel: AppConfig.lang == 'ar' ? 'مدير المؤسسة' : 'Organization admin',
      color: const Color(0xFF1F6F5C),
      onCalendar: () {},
      onJoinCode: full ? () {} : null,
      onSwitch: full ? () {} : null,
      onEdit: full ? () {} : null,
      onSubOrg: full ? () {} : null,
      onPersonal: () {},
    );

List<HomeShortcut> shortcuts() => [
      for (final (icon, ar, en) in [
        (Icons.groups_rounded, 'الأعضاء', 'Members'),
        (Icons.how_to_reg_rounded, 'طلبات الانضمام', 'Join requests'),
        (Icons.apartment_rounded, 'الإدارات', 'Departments'),
        (Icons.menu_book_rounded, 'المقررات', 'Courses'),
        (Icons.calendar_month_rounded, 'الجدول', 'Timetable'),
        (Icons.campaign_rounded, 'الإعلانات', 'News'),
        (Icons.support_agent_rounded, 'الشكاوى', 'Complaints'),
        (Icons.assignment_rounded, 'النماذج', 'Forms'),
        (Icons.tune_rounded, 'الإعدادات', 'Settings'),
      ])
        HomeShortcut(icon: icon, label: AppConfig.lang == 'ar' ? ar : en, badge: icon == Icons.how_to_reg_rounded ? 17 : 0, onTap: () {}),
    ];

OrgHomeBody body(OrgHomeData d, {bool full = true}) => OrgHomeBody(
      data: d,
      hero: hero(full: full),
      cards: [for (final a in d.attention) ?OrgAttentionSpec.of(a, () {})],
      shortcuts: full ? shortcuts() : const [],
      unitsTitle: AppConfig.lang == 'ar' ? 'الإدارات والأقسام' : 'Departments',
      onOpenUnit: (_) {},
      onSeeAllUnits: () {},
      onActivityLog: () {},
    );

/// Pumps [w] once at the default test size (the harness ends on an empty tree) so finders see it.
Future<void> showOnce(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(layoutHost(w));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('full payload: hero figures, queue with pending_total, trends, shortcuts, units, activity', (tester) async {
    await expectNoLayoutErrors(tester, () => body(OrgHomeData.fromJson(payload())!));
    // the harness clears the tree when it ends: pump once more to look at what was drawn
    await showOnce(tester, body(OrgHomeData.fromJson(payload())!));
    // drawn once: the three trend tiles and the five known cards (the unknown key is skipped)
    expect(find.byType(AppTrendTile), findsNWidgets(3));
    expect(find.byType(OrgAttentionCard), findsNWidgets(5));
    expect(find.text('31'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('older payload (no members / series): the tiles hide, the hero shows the kpis', (tester) async {
    await expectNoLayoutErrors(tester, () => body(OrgHomeData.fromJson(payload(members: false, series: false))!));
    await showOnce(tester, body(OrgHomeData.fromJson(payload(members: false, series: false))!));
    expect(find.byType(OrgHomeBody), findsOneWidget);
    expect(find.byType(AppTrendTile), findsNothing);
    expect(find.byType(OrgTrendRow), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty organization: all good, no units, no activity; the overflow opens', (tester) async {
    await expectNoLayoutErrors(tester, () => body(OrgHomeData.empty, full: false));
    await showOnce(tester, body(OrgHomeData.empty, full: false));
    expect(find.byType(OrgAllGood), findsOneWidget);
    expect(find.byType(OrgAttentionCard), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await expectNoLayoutErrors(tester, () => body(OrgHomeData.empty),
        act: (t) => t.tap(find.byIcon(Icons.more_horiz_rounded)));
  });

  testWidgets('skeleton and the hero alone (failed state) lay out', (tester) async {
    await expectNoLayoutErrors(tester, () => OrgHomeSkeleton(hero: hero()));
    await expectNoLayoutErrors(tester, () => ListView(children: [OrgHero(spec: hero(), figures: const (12840, 380, 125, null))]));
  });

  testWidgets('a trend row alone at every width', (tester) async {
    final d = OrgHomeData.fromJson(payload())!;
    await expectNoLayoutErrors(tester, () => ListView(children: [OrgTrendRow(trends: d.trends)]));
  });
}
