// lib/features/org/org_table_export.dart — organization tables routed through the generic exporter
// (lib/design/app_table_export.dart): Excel · Word · PDF with the column picker, instead of the old CSV files.
library;

import 'package:flutter/material.dart';

import '../../design/app_table_export.dart';
import '../../core/app_time.dart';
import 'org_schedule_versions.dart' show TimetableNames, dayLabelsPlain;
import '../admin/admin_common.dart' show t, asInt;

/// One row per session (the old timetableCsv columns). [memberKey] / [memberLabel]: a per-member column that groups
/// the rows (a block per teacher / room / group …).
AppTableExport timetableTableExport({
  required String id,
  required String title,
  required List<Map<String, dynamic>> slots,
  required TimetableNames names,
  List<String> meta = const [],
  String? memberKey,
  String? memberLabel,
}) {
  final days = dayLabelsPlain();
  return AppTableExport(
    id: id,
    title: title,
    meta: meta,
    groupBy: memberKey == null ? null : 'member',
    columns: [
      if (memberKey != null) AppExportColumn('member', memberLabel ?? t('العضو', 'Member')),
      AppExportColumn('day', t('اليوم', 'Day'), align: AppColAlign.center, width: 12),
      AppExportColumn('period', t('الفترة', 'Period'), align: AppColAlign.center),
      AppExportColumn('from', t('من', 'From'), align: AppColAlign.center, width: 11),
      AppExportColumn('to', t('إلى', 'To'), align: AppColAlign.center, width: 11),
      AppExportColumn('course', t('المقرر', 'Course'), locked: true, total: AppTotal.count),
      AppExportColumn('kind', t('النوع', 'Kind'), type: AppColType.status, statusTones: const {'محاضرة': AppStatusTone.info, 'Lecture': AppStatusTone.info, 'عملي': AppStatusTone.good, 'Lab': AppStatusTone.good}),
      AppExportColumn('group', t('المجموعة', 'Group'), type: AppColType.integer, width: 10),
      AppExportColumn('room', t('المكان', 'Room')),
      AppExportColumn('teacher', t('المدرس', 'Teacher')),
      AppExportColumn('assistant', t('المعيد', 'Assistant')),
    ],
    totalLabel: t('عدد الحصص', 'Sessions'),
    rows: [
      for (final s in slots)
        () {
          final p = names.periods[asInt(s['period_id'])] ?? const {};
          return <String, Object?>{
            if (memberKey != null) 'member': '${s[memberKey] ?? ''}',
            'day': days[s['day']] ?? s['day'],
            'period': p['label'] ?? '#${s['period_id']}',
            'from': p['start_time'] == null ? null : AppTime.clock('${p['start_time']}'),
            'to': p['end_time'] == null ? null : AppTime.clock('${p['end_time']}'),
            'course': names.course(s['course_id']),
            'kind': s['kind'] == 'lab' ? t('عملي', 'Lab') : t('محاضرة', 'Lecture'),
            'group': s['group_no'] ?? 1,
            'room': names.room(s['room_id']),
            'teacher': names.person(s['teacher_id']),
            'assistant': names.person(s['assistant_id'] ?? s['admin_assistant_id']),
          };
        }(),
    ],
  );
}

/// The export sheet for a list of timetable sessions.
Future<bool> showTimetableTableExport(
  BuildContext context, {
  required String id,
  required String title,
  required List<Map<String, dynamic>> slots,
  required TimetableNames names,
  List<String> meta = const [],
  String? memberKey,
  String? memberLabel,
}) =>
    showAppExportSheet(context, timetableTableExport(id: id, title: title, slots: slots, names: names, meta: meta, memberKey: memberKey, memberLabel: memberLabel));
