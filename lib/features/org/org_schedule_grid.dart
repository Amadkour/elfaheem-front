// lib/features/org/org_schedule_grid.dart — the studio grid's ONE filter bar and its pure helpers.
//
//   GridFilter        pure: which slots a filter keeps (program/level · instructor · TA · room · group · student)
//   indexSlots        pure: (day, period) → slots, built once per build (cells never scan every slot)
//   conflictCells     pure: the cells a conflict covers (every period it overlaps), for the single conflict marker
//   conflictSlots     pure: slot id → worst severity, for the per-session marker
//   sessionKind*      one colour / label / icon per session type (lecture · lab · section)
//   TimetableFilterBar the bar on ONE line: filter-by menu · value picker · clear (+ a trailing widget)
//   TimetableLegend   the colour key
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../admin/admin_common.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

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

/// Session type → its one colour (grid item, legend, details header). Lecture · lab (practical) · section (tutorial).
Color sessionKindColor(ThemeConfigProvider c, Object? kind) => switch ('$kind') {
  'lab' => c.purple,
  'section' || 'tutorial' => c.accent,
  _ => c.primary,
};

String sessionKindLabel(Object? kind) => switch ('$kind') {
  'lab' => t('عملي', 'Lab'),
  'section' || 'tutorial' => t('سكشن', 'Section'),
  _ => t('محاضرة', 'Lecture'),
};

IconData sessionKindIcon(Object? kind) => switch ('$kind') {
  'lab' => Icons.science_rounded,
  'section' || 'tutorial' => Icons.groups_2_rounded,
  _ => Icons.menu_book_rounded,
};

/// slot id → 'error' | 'warning' (an error wins): the exact sessions a conflict names, for the per-session marker.
Map<int, String> conflictSlots(Iterable<Map<String, dynamic>> conflicts) {
  final out = <int, String>{};
  for (final x in conflicts) {
    final sev = x['severity'] == 'error' ? 'error' : 'warning';
    for (final id in ((x['slot_ids'] as List?) ?? const []).map(asInt)) {
      if (out[id] != 'error') out[id] = sev;
    }
  }
  return out;
}

/// The ONE filter bar: one line — what to filter by (menu) · which one (picker) · clear.
class TimetableFilterBar extends StatelessWidget {
  const TimetableFilterBar({super.key, required this.filter, required this.options, required this.onChanged, this.studentLabel, this.trailing});
  final GridFilter filter;

  /// kind → value → label (student values are searched by the caller and passed in once chosen)
  final Map<GridFilterKind, Map<String, String>> options;
  final ValueChanged<GridFilter> onChanged;

  /// the chosen student's name (the student filter is searched by the caller)
  final String? studentLabel;

  /// e.g. the grid / courses view switch, kept on the same line
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final values = options[filter.kind] ?? const {};
    final kinds = [
      for (final k in GridFilterKind.values)
        if (k == GridFilterKind.all || k == GridFilterKind.student || (options[k]?.isNotEmpty ?? false)) k,
    ];
    final active = filter.kind != GridFilterKind.all && filter.value != null;
    final style = TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w700, color: c.textDark);

    final Widget value = switch (filter.kind) {
      GridFilterKind.all => Text(
        t('كل الحصص', 'All sessions'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(color: c.textMedium),
      ),
      GridFilterKind.student => InkWell(
        onTap: () => onChanged(const GridFilter(GridFilterKind.student)),
        child: Text(
          studentLabel ?? t('اختر طالباً…', 'Choose a student…'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(color: studentLabel == null ? c.textLight : c.textDark),
        ),
      ),
      _ =>
        values.isEmpty
            ? Text('—', style: style)
            : DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  isDense: true,
                  value: values.containsKey(filter.value) ? filter.value : null,
                  hint: Text(
                    t('اختر ${gridFilterLabel(filter.kind)}', 'Choose ${gridFilterLabel(filter.kind).toLowerCase()}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.copyWith(color: c.textLight),
                  ),
                  style: style,
                  dropdownColor: c.cardBg,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  items: [
                    for (final e in values.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => onChanged(GridFilter(filter.kind, v)),
                ),
              ),
    };

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, end: AppSpace.xxs),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: active ? c.primary.withValues(alpha: 0.6) : c.divider),
            ),
            child: Row(
              children: [
                PopupMenuButton<GridFilterKind>(
                  tooltip: t('تصفية حسب', 'Filter by'),
                  initialValue: filter.kind,
                  onSelected: (k) => onChanged(GridFilter(k)),
                  itemBuilder: (_) => [
                    for (final k in kinds)
                      PopupMenuItem(
                        value: k,
                        child: Row(
                          children: [
                            Icon(k == filter.kind ? Icons.check_rounded : Icons.filter_alt_outlined, size: AppIconSize.md, color: k == filter.kind ? c.primary : c.textLight),
                            const SizedBox(width: AppSpace.sm),
                            Flexible(child: Text(gridFilterLabel(k), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 150),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                    decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.chip)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.filter_list_rounded, size: AppIconSize.sm, color: c.primary),
                        const SizedBox(width: AppSpace.xs),
                        Flexible(
                          child: Text(
                            gridFilterLabel(filter.kind),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(color: c.primary, fontSize: 12.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down_rounded, size: AppIconSize.md, color: c.primary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: value),
                if (filter.kind != GridFilterKind.all)
                  IconButton(
                    tooltip: t('مسح التصفية', 'Clear filter'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textMedium),
                    onPressed: () => onChanged(GridFilter.none),
                  ),
              ],
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: AppSpace.xs), trailing!],
      ],
    );
  }
}

/// Colour key under the filter bar: session types present + the conflict and pinned markers.
class TimetableLegend extends StatelessWidget {
  const TimetableLegend({super.key, this.kinds = const {'lecture', 'lab'}, this.conflicts = 0});
  final Set<String> kinds;

  /// hard conflicts in view (0 hides nothing — the key stays, the count is added when > 0)
  final int conflicts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, fontWeight: FontWeight.w700, color: c.textMedium);
    Widget item(Widget mark, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: AppSpace.xxs),
        Flexible(child: Text(label, style: style)),
      ],
    );
    Widget swatch(Color col) => Container(
      width: 14,
      height: 10,
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: BorderDirectional(start: BorderSide(color: col, width: 3)),
      ),
    );
    final order = ['lecture', 'lab', 'section'];
    final shown = [
      for (final k in order)
        if (kinds.contains(k) || (k == 'section' && kinds.contains('tutorial'))) k,
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final k in shown.isEmpty ? const ['lecture'] : shown) item(swatch(sessionKindColor(c, k)), sessionKindLabel(k)),
        item(Icon(Icons.error_rounded, size: AppIconSize.xs, color: c.danger), conflicts > 0 ? t('تعارض ($conflicts)', 'Conflict ($conflicts)') : t('تعارض', 'Conflict')),
        item(Icon(Icons.push_pin_rounded, size: AppIconSize.xs, color: c.textMedium), t('مثبتة', 'Pinned')),
      ],
    );
  }
}
