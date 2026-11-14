// The org-admin home and department dashboard models (org_dashboard_model.dart): one payload each, trends from
// `series`, an older server without `members` / `series`, an empty organization, the attention texts.
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_dashboard_model.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> series30() => [
      for (var i = 0; i < 30; i++)
        {
          'date': '2026-10-${(i + 1).toString().padLeft(2, '0')}',
          'joins': i,
          'attendance': 10,
          'complaints': i % 3,
          'work_items': 1,
        },
    ];

Map<String, dynamic> fullPayload() => {
      'organization': {'id': 4, 'name_ar': 'جامعة', 'name_en': 'University', 'type': 'university'},
      'my_role': 'org_admin',
      'kpis': {'students': 1200, 'teachers': 80, 'staff': 25, 'courses': 140, 'active_enrollments': 3100, 'departments': 6, 'programs': 4, 'sub_organizations': 2},
      'members': {'students': 1200, 'teachers': 80, 'staff': 25, 'pending_join': 7},
      'pending_total': 12,
      'attention_total': 12,
      'attention': [
        {'key': 'open_complaints', 'count': 5, 'severity': 'danger', 'overdue': 2},
        {'key': 'org_join_requests', 'count': 7, 'severity': 'warning'},
      ],
      'series': series30(),
      'departments': [
        {'id': 1, 'unit_type': 'dept', 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs', 'team': 4, 'waiting': 3},
      ],
      'programs': [
        {'id': 9, 'unit_type': 'program', 'code': 'CS', 'name_ar': 'علوم الحاسب', 'name_en': 'Computer science', 'students': 300, 'waiting': 0},
      ],
      'recent_activity': [
        {'summary': 'Approved a join request', 'created_at': '2026-10-28T08:00:00'},
      ],
      'generated_at': '2026-10-28T09:00:00',
    };

Map<String, dynamic> olderPayload() {
  final m = fullPayload();
  m.remove('members');
  m.remove('series');
  m.remove('pending_total');
  return m;
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('OrgHomeData', () {
    test('full payload: members, pending_total, trends from series', () {
      final d = OrgHomeData.fromJson(fullPayload())!;
      expect(d.myRole, 'org_admin');
      expect(d.kpi('students'), 1200);
      expect(d.members, isNotNull);
      expect(d.members!.pendingJoin, 7);
      expect(d.figures, (1200, 80, 25, 7));
      expect(d.pendingTotal, 12);
      expect(d.attention.length, 2);
      expect(d.count('open_complaints'), 5);
      expect(d.attentionOf('open_complaints')!.overdue, 2);
      expect(d.count('nothing'), 0);
      expect(d.hasTrends, isTrue);
      expect(d.trends.map((x) => x.key), ['joins', 'attendance', 'complaints']);
      final joins = d.trend('joins')!;
      expect(joins.value, 182);                         // 23 + … + 29
      expect(joins.delta, closeTo(36.84, 0.01));         // vs 16 + … + 22 = 133
      expect(joins.spark.length, 30);
      expect(joins.spark.first, 0);
      expect(joins.spark.last, 29);
      expect(d.trend('attendance')!.value, 70);
      expect(d.trend('attendance')!.delta, 0);
      expect(d.trend('complaints')!.value, 8);
      expect(d.trend('complaints')!.delta, closeTo(14.29, 0.01));
      expect(d.units.length, 2);
      expect(d.units.first['unit_type'], 'dept');
      expect(d.recentActivity.length, 1);
      expect(d.generatedAt, isNotNull);
    });

    test('older server: no members / series → tiles hide, figures from the kpis, attention_total', () {
      final d = OrgHomeData.fromJson(olderPayload())!;
      expect(d.members, isNull);
      expect(d.series, isNull);
      expect(d.hasTrends, isFalse);
      expect(d.trends, isEmpty);
      expect(d.trend('joins'), isNull);
      expect(d.figures, (1200, 80, 25, null));
      expect(d.pendingTotal, 12);
    });

    test('empty organization and a non-map answer', () {
      final d = OrgHomeData.fromJson(const <String, dynamic>{})!;
      expect(d.kpis, isEmpty);
      expect(d.members, isNull);
      expect(d.pendingTotal, 0);
      expect(d.attention, isEmpty);
      expect(d.units, isEmpty);
      expect(d.recentActivity, isEmpty);
      expect(d.hasTrends, isFalse);
      expect(d.figures, (0, 0, 0, null));
      expect(OrgHomeData.fromJson('oops'), isNull);
      expect(OrgHomeData.fromJson(null), isNull);
      expect(OrgHomeData.empty.pendingTotal, 0);
    });

    test('pending_total falls back to the sum of the items', () {
      final d = OrgHomeData.fromJson({
        'attention': [
          {'key': 'pending_forms', 'count': 3},
          {'key': 'unit_join_requests', 'count': '4'},
        ],
      })!;
      expect(d.pendingTotal, 7);
      expect(d.attention.first.severity, 'info');
    });
  });

  group('OrgTrend', () {
    test('short series: no previous window → no delta; an empty previous window → no delta', () {
      expect(OrgTrend.of('x', [1, 2, 3]).value, 6);
      expect(OrgTrend.of('x', [1, 2, 3]).delta, isNull);
      expect(OrgTrend.of('x', [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1]).value, 7);
      expect(OrgTrend.of('x', [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1]).delta, isNull);
      expect(OrgTrend.of('x', [2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1]).delta, -50);
      expect(OrgTrend.of('x', const []).value, 0);
    });

    test('series rows keep every numeric column and skip the rest', () {
      final r = OrgSeriesRow.fromJson({'date': '2026-10-01', 'joins': 3, 'note': 'x', 'ratio': '7'})!;
      expect(r.date, '2026-10-01');
      expect(r.values, {'joins': 3, 'ratio': 7});
      expect(OrgSeriesRow.listFrom('no'), isNull);
      expect(OrgSeriesRow.listFrom([1, {'date': 'd', 'a': 1}])!.length, 1);
    });
  });

  group('orgAttentionText', () {
    test('known keys in both languages, unknown keys null', () {
      final a = OrgAttentionItem({'key': 'open_complaints', 'count': 5, 'severity': 'danger', 'overdue': 2});
      final en = orgAttentionText(a)!;
      expect(en.icon, Icons.support_agent_rounded);
      expect(en.title, '5 open complaints');
      expect(en.subtitle, contains('2 are past their reply time'));
      expect(en.action, 'Reply');
      AppConfig.lang = 'ar';
      expect(orgAttentionText(a)!.title, '5 شكوى مفتوحة');
      expect(orgAttentionText(OrgAttentionItem({'key': 'something_new', 'count': 1})), isNull);
    });

    test('terms without a timetable list the terms; memberships carry the days', () {
      final terms = OrgAttentionItem({
        'key': 'term_without_timetable',
        'count': 1,
        'terms': [
          {'id': 3, 'year_label': '2026/2027', 'kind': 'term1', 'status': 'current'},
        ],
      });
      expect(terms.terms.length, 1);
      expect(orgAttentionText(terms)!.title, 'A term has no timetable yet');
      expect(orgAttentionText(terms)!.subtitle, contains('2026/2027'));
      final exp = OrgAttentionItem({'key': 'expiring_memberships', 'count': 4, 'days': 14, 'items': [{'member_id': 1}]});
      expect(orgAttentionText(exp)!.title, '4 memberships end within 14 days');
      expect(exp.items.length, 1);
    });
  });

  group('OrgUnitData', () {
    final payload = {
      'unit': {'id': 3, 'unit_type': 'dept', 'name_ar': 'الإرشاد', 'name_en': 'Advising', 'color': '#2563EB'},
      'manager': {'name': 'Dr. A'},
      'features': ['forms', 'complaints'],
      'can': {'decide_requests': true, 'view_users': false, 'manage_team': 'yes'},
      'stats': {'users': 40, 'staff': null, 'courses': 2, 'pending_join_requests': 3, 'pending_forms': 1, 'pending_program_choices': null},
      'requests': [{'id': 1}],
      'forms': [],
      'users': [{'user': {'id': 9}}],
      'team': [],
      'sub_units': [{'id': 7}],
    };

    test('typed once: can, stats (null = hidden), waiting, lists', () {
      final d = OrgUnitData.fromJson(payload)!;
      expect(d.isDept, isTrue);
      expect(d.cap('decide_requests'), isTrue);
      expect(d.cap('view_users'), isFalse);
      expect(d.cap('manage_team'), isFalse);     // only a real true counts
      expect(d.cap('unknown'), isFalse);
      expect(d.stat('users'), 40);
      expect(d.hidden('users'), isFalse);
      expect(d.stat('staff'), 0);
      expect(d.hidden('staff'), isTrue);
      expect(d.hidden('never_sent'), isFalse);
      expect(d.waiting, 4);
      expect(d.features, ['forms', 'complaints']);
      expect(d.requests.length, 1);
      expect(d.users.length, 1);
      expect(d.subUnits.length, 1);
      expect(d.manager['name'], 'Dr. A');
      expect(d.series, isNull);
      expect(d.trends, isEmpty);
      expect(OrgUnitData.fromJson(null), isNull);
    });

    test('a server that adds series gets one trend per numeric column', () {
      final d = OrgUnitData.fromJson({
        ...payload,
        'series': [for (var i = 0; i < 14; i++) {'date': 'd$i', 'users': i, 'requests': 2}],
      })!;
      expect(d.trends.map((x) => x.key), ['users', 'requests']);
      expect(d.trends.first.value, 7 + 8 + 9 + 10 + 11 + 12 + 13);
      expect(d.trends.last.delta, 0);
    });
  });
}
