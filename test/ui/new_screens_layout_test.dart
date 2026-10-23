// Phase-2 UI audit: the new screens' building blocks at 320x640 and 1400x900, Arabic + English, textScaler 1.3.
// Only widgets that render without the network (ApiClient is a singleton and can't be faked).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_table_export.dart';
import 'package:flutter_education_app/features/admin/admin_platform_widgets.dart';
import 'package:flutter_education_app/features/org/org_announcements.dart';
import 'package:flutter_education_app/features/org/org_levels.dart';
import 'package:flutter_education_app/features/org/org_levels_pages.dart';
import 'package:flutter_education_app/features/org/org_schedule_board.dart';
import 'package:flutter_education_app/features/org/org_schedule_generate.dart';
import 'package:flutter_education_app/features/org/org_schedule_grid.dart';
import 'package:flutter_education_app/features/org/org_schedule_hub.dart';
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة والتكنولوجيا';
const longEn = 'Office of Student Affairs, Graduate Studies and Scientific Research, Faculty of Engineering';

String iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');

InboxItem inboxItem(String kind, {String segment = 'todo', Duration? due, bool mandatory = false, String status = ''}) => InboxItem({
      'key': '$kind-$segment',
      'kind': kind,
      'segment': segment,
      'title': '$longAr — $longEn',
      'subtitle': longEn,
      'org_id': 3,
      'organization': {'id': 3, 'name_ar': longAr, 'name_en': longEn},
      'department': {'id': 4, 'name_ar': longAr, 'name_en': longEn},
      'due_at': due == null ? null : iso(DateTime.now().add(due)),
      'created_at': iso(DateTime.now().subtract(const Duration(hours: 1))),
      'mandatory': mandatory,
      'status': status,
      'data': {'count': 128},
    });

void main() {
  testWidgets('inbox segments and cards', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        InboxSegments(
          value: InboxSegment.values.first,
          counts: {for (final s in InboxSegment.values) s: 1234},
          onChanged: (_) {},
        ),
        InboxCard(item: inboxItem('form', due: const Duration(hours: 5), mandatory: true), onTap: () {}),
        InboxCard(item: inboxItem('form', due: const Duration(hours: -30)), onTap: () {}),
        InboxCard(item: inboxItem('approval'), onTap: () {}),
        InboxCard(item: inboxItem('request', segment: 'done', status: 'approved'), onTap: () {}),
        InboxCard(item: inboxItem('announcement', segment: 'news'), onTap: () {}),
      ]),
    );
  });

  testWidgets('generation live panel', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        GenerationLivePanel(run: const {
          'status': 'running',
          'progress': 50,
          'summary': {'live': true, 'round': 3, 'rounds_max': 6, 'unplaced': 12, 'top': [{'reason': 'students_busy_elsewhere', 'n': 7}, {'reason': 'no_room_fits', 'n': 5}]},
        }, onCancel: () {}),
        GenerationLivePanel(run: {'status': 'failed', 'error': '$longEn $longAr'}),
      ]),
    );
  });

  testWidgets('timetable conflicts panel', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        ConflictsPanel(conflicts: const [], onTap: () {}),
        ConflictsPanel(conflicts: [
          for (final x in ['room_double_booked', 'staff_busy_elsewhere', 'preference_not_preferred', 'room_missing_capabilities'])
            {'type': x, 'severity': x.startsWith('pref') ? 'warning' : 'error'},
        ], onTap: () {}),
      ]),
    );
  });

  testWidgets('timetable board: sticky header and period column, seven days', (tester) async {
    const days = ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday'];
    final periods = [for (var i = 0; i < 7; i++) {'id': i + 1, 'label': 'P${i + 1} $longEn', 'start_time': '0${i + 1}:00'}];
    await expectNoLayoutErrors(
      tester,
      () => TimetableBoard(
        days: days,
        periods: periods,
        dayLabel: (d) => '$d $longAr',
        periodLabel: (p) => Text('${p['label']}', maxLines: 1, overflow: TextOverflow.ellipsis),
        rowSessions: (pid) => pid == 2 ? 3 : 1,
        cell: (d, p, h) => SingleChildScrollView(
          child: Column(children: [for (var i = 0; i < (asIntOr(p['id']) == 2 ? 3 : 1); i++) Text('$longEn $longAr', maxLines: 2, overflow: TextOverflow.ellipsis)]),
        ),
      ),
    );
  });

  testWidgets('timetable next-step banner and filter bar', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        NextStepBanner(title: '$longAr $longEn', body: '$longEn. $longAr', action: 'إصلاح التعارضات الآن', tone: 2, onAction: () {}),
        const SizedBox(height: 12),
        TimetableFilterBar(
          filter: const GridFilter(GridFilterKind.teacher, '1'),
          options: {
            GridFilterKind.cohort: {'1|L1': '$longAr · L1'},
            GridFilterKind.teacher: {'1': longEn},
            GridFilterKind.room: {'2': longAr},
          },
          onChanged: (_) {},
        ),
      ]),
    );
  });

  testWidgets('platform settings: section header and region editor', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        PlatformSectionHeader(icon: Icons.public_rounded, title: longAr, subtitle: longEn, trailing: TextButton(onPressed: () {}, child: const Text('Reset'))),
        RegionEditor(
          zone: 'Africa/Cairo',
          timeFormat: '12h',
          onZone: (_) {},
          onFormat: (_) {},
          inheritLabel: 'الإعداد الافتراضي للمنصة',
          inheritedZone: 'Asia/Riyadh',
          inheritedFormat: '24h',
        ),
      ]),
    );
  });

  testWidgets('prerequisite rules editor', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        PrereqRulesEditor(
          rules: [
            PrereqRule('courses_passed', {'course_ids': [1, 2], 'min_count': 2}),
            PrereqRule('level_courses', {'percent': 75}),
            PrereqRule('min_courses', {'count': 4}),
          ],
          courses: const [
            {'id': 1, 'name_ar': longAr, 'name_en': longEn},
            {'id': 2, 'name_ar': 'مقدمة', 'name_en': 'Intro'},
          ],
          onChanged: () {},
        ),
      ]),
    );
  });

  testWidgets('enrolment block sheet', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(builder: (context) => Center(child: TextButton(onPressed: () => showEnrollBlock(context, _reason), child: const Text('open')))),
      act: (tester) => tester.tap(find.text('open')),
    );
  });

  testWidgets('roadmap prerequisites sheet', (tester) async {
    final roadmap = {
      'code': 'roadmap_prerequisites',
      'blocked': [
        for (final i in [1, 2]) {'course_id': i, 'name_ar': longAr, 'name_en': longEn, 'code': 'CS20$i', 'reason': _reason},
      ],
      'course_names': _reason['course_names'],
    };
    await expectNoLayoutErrors(
      tester,
      () => Builder(builder: (context) => Center(child: TextButton(onPressed: () => showEnrollBlock(context, roadmap), child: const Text('open')))),
      act: (tester) => tester.tap(find.text('open')),
    );
  });

  testWidgets('announcement cards', (tester) async {
    Map<String, dynamic> ann(int id, {String category = 'news', bool pinned = false}) => {
          'id': id,
          'title': '$longAr $longEn',
          'body': '$longEn. $longAr. $longEn.',
          'category': category,
          'is_pinned': pinned,
          'likes': 12345,
          'dislikes': 678,
          'publish_at': iso(DateTime.now().subtract(const Duration(hours: 3))),
          'organization': {'id': 3, 'name_ar': longAr, 'name_en': longEn},
          'department': {'id': 4, 'name_ar': longAr, 'name_en': longEn},
          'me': {'viewed': false},
        };
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        AnnouncementCard(item: ann(1, category: 'urgent', pinned: true)),
        const SizedBox(height: 12),
        AnnouncementCard(item: ann(2), compact: true),
      ]),
    );
  });

  testWidgets('export sheet', (tester) async {
    final export = AppTableExport(
      id: 'layout.test',
      title: '$longAr — $longEn',
      filters: const {'Status': 'All', 'Department': longEn},
      columns: [
        const AppExportColumn('name', 'الاسم الكامل للطالب', locked: true),
        for (var i = 0; i < 12; i++) AppExportColumn('c$i', '$longEn $i'),
      ],
      rows: [
        for (var r = 0; r < 5; r++) {'name': longAr, for (var i = 0; i < 12; i++) 'c$i': '$r-$i'},
      ],
    );
    await expectNoLayoutErrors(
      tester,
      () => Builder(builder: (context) => Center(child: TextButton(onPressed: () => showAppExportSheet(context, export), child: const Text('open')))),
      act: (tester) => tester.tap(find.text('open')),
    );
  });
}

final _reason = <String, dynamic>{
  'program': {'id': 1, 'name_ar': longAr, 'name_en': longEn},
  'course_names': {'1': longAr, '2': longEn},
  'unmet': [
    {'type': 'courses_passed', 'params': {'course_ids': [1, 2], 'min_count': 2}, 'met': false, 'have': 1, 'need': 2, 'missing_course_ids': [2]},
    {'type': 'level_courses', 'params': {'percent': 75}, 'met': false, 'have': 40, 'need': 75, 'unit': '%'},
  ],
  'missing_course_ids': [2],
};

int asIntOr(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
