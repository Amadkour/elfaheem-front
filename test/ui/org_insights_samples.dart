// Realistic Insights / palette data for the layout tests and the visual renders: a university mid-term — the SHAPE of
// the real captures in test/fixtures/payloads/org_insights*.json, with the figures of a busy organization (the local
// demo has a handful of rows only).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/insights/org_insights.dart';
import 'package:flutter_education_app/features/org/org_command_palette_logic.dart';

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 30 daily points ending 2026-10-31; Fridays and Saturdays without classes (null) for attendance.
List<Map<String, Object?>> _series(double Function(int i) f, {bool weekends = false}) {
  final start = DateTime.utc(2026, 10, 2);
  return [
    for (var i = 0; i < 30; i++)
      () {
        final d = start.add(Duration(days: i));
        final off = weekends && (d.weekday == DateTime.friday || d.weekday == DateTime.saturday);
        return {'date': _iso(d), 'value': off ? null : f(i)};
      }(),
  ];
}

Map<String, Object?> sampleInsightsJson({bool scoped = false, bool fewMetrics = false}) => {
      'period': {
        'term_id': null,
        'label_ar': 'آخر 30 يومًا',
        'label_en': 'Last 30 days',
        'from': '2026-10-02',
        'to': '2026-10-31',
        'previous_from': '2026-09-02',
        'previous_to': '2026-10-01',
        'granularity': 'day',
      },
      'scope': {'org_wide': !scoped, 'dept_ids': scoped ? [6] : null},
      'terms': [
        {'id': 4, 'label_ar': 'الفصل الثاني 2026/2027', 'label_en': 'Term 2 2026/2027', 'status': 'upcoming'},
        {'id': 3, 'label_ar': 'الفصل الأول 2026/2027', 'label_en': 'Term 1 2026/2027', 'status': 'current'},
        {'id': 2, 'label_ar': 'الفصل الصيفي 2025/2026', 'label_en': 'Summer 2025/2026', 'status': 'finished'},
      ],
      'metrics': [
        {
          'key': 'attendance',
          'available': true,
          'value': 82.4,
          'unit': 'percent',
          'previous': 87.1,
          'series': _series((i) => 88 - i * 0.25 + (i % 3 == 0 ? -4 : (i % 2 == 0 ? 2 : 0)), weekends: true),
          'sessions': 214,
        },
        {
          'key': 'enrollment',
          'available': true,
          'value': 46,
          'unit': 'count',
          'previous': 38,
          'series': _series((i) => (i < 6 ? 4 : (i % 4 == 0 ? 2 : (i % 5 == 0 ? 3 : 1))).toDouble()),
          'total': 1240,
        },
        if (!fewMetrics)
          {'key': 'completion', 'available': true, 'value': 71.0, 'unit': 'percent', 'previous': 68.0, 'series': [], 'runs': 38},
        if (!fewMetrics)
          {'key': 'grades', 'available': true, 'value': 74.6, 'unit': 'score', 'previous': 76.2, 'series': [], 'coverage': 88.0},
        {
          'key': 'pending',
          'available': true,
          'value': 14,
          'unit': 'count',
          'previous': null,
          'series': [],
          'parts': {'org_join_requests': 6, 'pending_forms': 5, 'open_complaints': 3},
          'oldest_days': 9,
        },
      ],
      'suggestions': [
        {
          'key': 'unplaced_sessions',
          'severity': 'risk',
          'metric': null,
          'value': 5,
          'link': {'section': 'timetable', 'sub': 'unplaced', 'dept_id': null, 'kind': 'org_schedule', 'id': 12},
        },
        {
          'key': 'pending_backlog',
          'severity': 'watch',
          'metric': 'pending',
          'value': 14,
          'oldest_days': 9,
          'link': {'section': 'people', 'sub': 'join_requests', 'dept_id': null, 'kind': null, 'id': null},
        },
        {
          'key': 'grades_missing',
          'severity': 'watch',
          'metric': 'grades',
          'value': 6,
          'term_id': 2,
          'link': {'section': 'academics', 'sub': 'registrar', 'dept_id': null, 'kind': 'org_term', 'id': 2},
        },
      ],
      'generated_at': '2026-10-31T08:15:00',
    };

OrgInsights sampleInsights({bool scoped = false, bool fewMetrics = false}) =>
    OrgInsights.fromJson(sampleInsightsJson(scoped: scoped, fewMetrics: fewMetrics));

/// The org shell's pages as the wiring builds them.
List<OrgPaletteEntry> samplePalettePages(bool ar) {
  OrgPaletteEntry p(String key, String label, IconData icon, [String? group]) =>
      OrgPaletteEntry(key: key, label: label, icon: icon, group: group, onOpen: () {});
  final people = ar ? 'الأعضاء' : 'People', academics = ar ? 'الأكاديمي' : 'Academics', services = ar ? 'الخدمات' : 'Services';
  return [
    p('home', ar ? 'الرئيسية' : 'Home', Icons.dashboard_rounded),
    p('people', people, Icons.groups_rounded),
    p('people/members', ar ? 'الأعضاء' : 'Members', Icons.groups_rounded, people),
    p('people/departments', ar ? 'الإدارات والأقسام' : 'Departments', Icons.apartment_rounded, people),
    p('people/join_requests', ar ? 'طلبات الانضمام للأقسام' : 'Department join requests', Icons.how_to_reg_rounded, people),
    p('academics/courses', ar ? 'المقررات' : 'Courses', Icons.menu_book_rounded, academics),
    p('academics/structure', ar ? 'الهيكل الأكاديمي' : 'Academic structure', Icons.account_tree_rounded, academics),
    p('academics/registrar', ar ? 'التسجيل والدرجات' : 'Registrar', Icons.how_to_reg_rounded, academics),
    p('timetable', ar ? 'الجدول' : 'Timetable', Icons.calendar_month_rounded),
    p('services/announcements', ar ? 'الإعلانات' : 'News', Icons.campaign_rounded, services),
    p('services/complaints', ar ? 'الشكاوى' : 'Complaints', Icons.support_agent_rounded, services),
    p('settings', ar ? 'الإعدادات' : 'Settings', Icons.tune_rounded),
  ];
}

const sampleSearch = OrgSearchResult(
  departments: [
    OrgPaletteDept(id: 6, nameAr: 'قسم علوم الحاسب', nameEn: 'Computer Science Department'),
    OrgPaletteDept(id: 7, nameAr: 'مجلس قسم علوم الحاسب', nameEn: 'Computer Science Department Council'),
    OrgPaletteDept(id: 1, unitType: 'program', nameAr: 'علوم الحاسب', nameEn: 'Computer Science'),
  ],
  people: [
    OrgPalettePerson(userId: 21, name: 'Dr. Comfort Mensah', memberRole: 'teacher'),
    OrgPalettePerson(userId: 34, name: 'Computer Lab Assistant', memberRole: 'teacher_assistant'),
    OrgPalettePerson(userId: 58, name: 'Sara Comlan', memberRole: 'student'),
  ],
);

const samplePaletteRecents = [
  OrgPaletteRecent(kind: OrgPaletteKind.page, key: 'timetable'),
  OrgPaletteRecent(
      kind: OrgPaletteKind.dept, key: 'dept:6', dept: OrgPaletteDept(id: 6, nameAr: 'قسم علوم الحاسب', nameEn: 'Computer Science Department')),
  OrgPaletteRecent(kind: OrgPaletteKind.page, key: 'academics/registrar'),
  OrgPaletteRecent(
      kind: OrgPaletteKind.person, key: 'person:21', person: OrgPalettePerson(userId: 21, name: 'Dr. Comfort Mensah', memberRole: 'teacher')),
];
