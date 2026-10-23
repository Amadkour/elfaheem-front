// lib/features/org/org_schedule_grid.dart — the studio grid's ONE filter bar and its pure helpers.
//
//   GridFilter        pure: which slots a filter keeps (program/level · instructor · TA · room · group · student)
//   indexSlots        pure: (day, period) → slots, built once per build (cells never scan every slot)
//   conflictCells     pure: the cells a conflict covers (every period it overlaps), for the single conflict marker
//   TimetableFilterBar the bar: a kind chip row + one value picker
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../admin/admin_common.dart';

enum GridFilterKind { all, cohort, teacher, assistant, room, group, student }

String gridFilterLabel(GridFilterKind k) => switch (k) {
      GridFilterKind.all => t('الكل', 'All'),
      GridFilterKind.cohort => t('البرنامج / المستوى', 'Program / level'),
      GridFilterKind.teacher => t('المدرس', 'Instructor'),
      GridFilterKind.assistant => t('المعيد', 'TA'),
      GridFilterKind.room => t('القاعة', 'Room'),
      GridFilterKind.group => t('المجموعة', 'Group'),
      GridFilterKind.student => t('الطالب', 'Student'),
    };

class GridFilter {
  const GridFilter(this.kind, [this.value]);
  final GridFilterKind kind;
  final String? value; // id, "programId|level", "lecture|2"; null = nothing chosen yet (keeps everything)

  static const none = GridFilter(GridFilterKind.all);

  /// [cohorts]: course id → {"programId|level"} · [studentGroups]: the chosen student's rows
  /// ({course_id, lecture_group, lab_group}, GET …/students/{uid}/groups).
  bool keeps(Map<String, dynamic> s, {Map<int, Set<String>> cohorts = const {}, List<Map<String, dynamic>> studentGroups = const []}) {
    if (kind == GridFilterKind.all || value == null) return true;
    String id(String k) => s[k] == null ? '' : '${asInt(s[k])}';
    return switch (kind) {
      GridFilterKind.teacher => id('teacher_id') == value,
      GridFilterKind.assistant => id('assistant_id') == value,
      GridFilterKind.room => id('room_id') == value,
      GridFilterKind.cohort => (cohorts[asInt(s['course_id'])] ?? const {}).contains(value),
      GridFilterKind.group => '${s['kind'] ?? 'lecture'}|${s['group_no'] ?? 1}' == value,
      GridFilterKind.student => studentGroups.any((g) {
          if (asInt(g['course_id']) != asInt(s['course_id'])) return false;
          final mine = s['kind'] == 'lab' ? g['lab_group'] : g['lecture_group'];
          return s['group_no'] == null || mine == null || asInt(mine) == asInt(s['group_no']);
        }),
      GridFilterKind.all => true,
    };
  }
}

Map<(String, int), List<Map<String, dynamic>>> indexSlots(Iterable<Map<String, dynamic>> slots) {
  final out = <(String, int), List<Map<String, dynamic>>>{};
  for (final s in slots) {
    (out[('${s['day']}', asInt(s['period_id']))] ??= []).add(s);
  }
  return out;
}

/// A conflict without a period covers its whole day (as the old per-cell check did).
Set<(String, int)> conflictCells(Iterable<Map<String, dynamic>> conflicts, Iterable<int> periodIds) {
  final out = <(String, int)>{};
  for (final x in conflicts) {
    final day = '${x['day']}';
    final ids = [...((x['period_ids'] as List?) ?? const []).map(asInt), if (x['period_id'] != null) asInt(x['period_id'])];
    for (final p in ids.isEmpty ? periodIds : ids) {
      out.add((day, p));
    }
  }
  return out;
}

class TimetableFilterBar extends StatelessWidget {
  const TimetableFilterBar({super.key, required this.filter, required this.options, required this.onChanged});
  final GridFilter filter;
  /// kind → value → label (student values are searched by the caller and passed in once chosen)
  final Map<GridFilterKind, Map<String, String>> options;
  final ValueChanged<GridFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = options[filter.kind] ?? const {};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final k in GridFilterKind.values)
            if (k == GridFilterKind.all || k == GridFilterKind.student || (options[k]?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(label: Text(gridFilterLabel(k)), selected: filter.kind == k, onSelected: (_) => onChanged(GridFilter(k))),
              ),
        ]),
      ),
      if (filter.kind != GridFilterKind.all && filter.kind != GridFilterKind.student && values.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: AppDropdown<String>(
            value: values.containsKey(filter.value) ? filter.value : null,
            hint: Text(gridFilterLabel(filter.kind)),
            items: [for (final e in values.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => onChanged(GridFilter(filter.kind, v)),
          ),
        ),
    ]);
  }
}
