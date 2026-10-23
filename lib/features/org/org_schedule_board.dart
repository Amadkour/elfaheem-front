// lib/features/org/org_schedule_board.dart — the studio's wide weekly grid and the session details dialog.
//
//   TimetableBoard       periods × days with a sticky day header and a sticky period column; horizontal scrolling
//                        through AppHScroll (visible draggable bar under the header, mouse drag, shift + wheel)
//   boardRowHeight       pure: one row's height from the most sessions in one of its cells
//   showSessionDetails   tap a session: course, type, group, its exact students, staff, room, start / end (AppTime),
//                        capacity vs enrolment, weekly stats — Edit only with permission
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppHScroll, AppTime;

import '../admin/admin_common.dart';
import 'org_common.dart' show dayLabels;
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_v3.dart';

/// Height of a grid row whose fullest cell holds [maxSessions] sessions (text scale included).
double boardRowHeight(int maxSessions, double textScale) => (maxSessions <= 1 ? 76.0 : 14.0 + 56.0 * maxSessions) * textScale.clamp(1.0, 2.0);

class TimetableBoard extends StatefulWidget {
  const TimetableBoard({
    super.key,
    required this.days,
    required this.periods,
    required this.dayLabel,
    required this.periodLabel,
    required this.rowSessions,
    required this.cell,
    this.cellWidth = 150,
    this.firstWidth = 82,
  });

  final List<String> days;
  final List<Map<String, dynamic>> periods;
  final String Function(String day) dayLabel;
  final Widget Function(Map<String, dynamic> period) periodLabel;
  /// period id → the most sessions in one of its cells (row height)
  final int Function(int periodId) rowSessions;
  final Widget Function(String day, Map<String, dynamic> period, double height) cell;
  final double cellWidth, firstWidth;

  @override
  State<TimetableBoard> createState() => _TimetableBoardState();
}

class _TimetableBoardState extends State<TimetableBoard> {
  final _head = ScrollController(), _body = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    void link(ScrollController from, ScrollController to) => from.addListener(() {
          if (_syncing || !to.hasClients || !from.hasClients) return;
          _syncing = true;
          to.jumpTo(from.offset.clamp(to.position.minScrollExtent, to.position.maxScrollExtent));
          _syncing = false;
        });
    link(_head, _body);
    link(_body, _head);
  }

  @override
  void dispose() {
    _head.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final width = widget.cellWidth * widget.days.length;
    final header = Row(children: [
      for (final d in widget.days)
        SizedBox(
          width: widget.cellWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(widget.dayLabel(d), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
          ),
        ),
    ]);
    final heights = {for (final p in widget.periods) asInt(p['id']): boardRowHeight(widget.rowSessions(asInt(p['id'])), scale)};
    return Column(children: [
      // sticky day header (stays while the periods scroll) — its bar scrolls the grid sideways
      Container(
        color: c.cardBg,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: widget.firstWidth),
          Expanded(child: AppHScroll(controller: _head, padding: const EdgeInsets.only(bottom: 12), child: SizedBox(width: width, child: header))),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // sticky period column (stays while the days scroll)
            SizedBox(
              width: widget.firstWidth,
              child: Column(children: [
                for (final p in widget.periods) SizedBox(height: heights[asInt(p['id'])], child: Center(child: widget.periodLabel(p))),
              ]),
            ),
            Expanded(
              child: AppHScroll(
                controller: _body,
                thumbVisibility: false,
                padding: EdgeInsets.zero,
                child: SizedBox(
                  width: width,
                  child: Column(children: [
                    for (final p in widget.periods)
                      SizedBox(
                        height: heights[asInt(p['id'])],
                        child: Row(children: [
                          for (final d in widget.days) SizedBox(width: widget.cellWidth, child: widget.cell(d, p, heights[asInt(p['id'])]!)),
                        ]),
                      ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Session details
// ═════════════════════════════════════════════════════════════════════════════

/// The periods of [slot]'s block (a double session spans several), in time order.
List<Map<String, dynamic>> blockPeriods(Map<String, dynamic> slot, List<Map<String, dynamic>> slots, List<Map<String, dynamic>> periods) {
  final same = slot['block_id'] == null
      ? [slot]
      : [for (final x in slots) if (x['block_id'] == slot['block_id'] && x['day'] == slot['day'] && asInt(x['course_id']) == asInt(slot['course_id'])) x];
  final ids = {for (final x in same) asInt(x['period_id'])};
  return [for (final p in periods) if (ids.contains(asInt(p['id']))) p]..sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}'));
}

/// Weekly sessions (blocks) and periods of one course / kind / group.
(int, int) groupWeekly(Map<String, dynamic> slot, List<Map<String, dynamic>> slots) {
  bool mine(Map<String, dynamic> x) =>
      asInt(x['course_id']) == asInt(slot['course_id']) && (x['kind'] ?? 'lecture') == (slot['kind'] ?? 'lecture') && x['group_no'] == slot['group_no'];
  final own = slots.where(mine).toList();
  return ({for (final x in own) '${x['day']}|${x['block_id'] ?? x['id']}'}.length, own.length);
}

Future<void> showSessionDetails(BuildContext context, OrgScheduleProvider p, Map<String, dynamic> slot,
    {required Map<int, String> courseNames, required Map<int, String> people, VoidCallback? onEdit}) {
  return showDialog<void>(context: context, builder: (ctx) => _SessionDialog(p: p, slot: slot, courseNames: courseNames, people: people, onEdit: onEdit));
}

class _SessionDialog extends StatefulWidget {
  const _SessionDialog({required this.p, required this.slot, required this.courseNames, required this.people, this.onEdit});
  final OrgScheduleProvider p;
  final Map<String, dynamic> slot;
  final Map<int, String> courseNames, people;
  final VoidCallback? onEdit;

  @override
  State<_SessionDialog> createState() => _SessionDialogState();
}

class _SessionDialogState extends State<_SessionDialog> {
  Map<String, dynamic>? group; // the registrar group of this session (students, enrolled, capacity)
  bool loading = true;
  String? note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = widget.p;
    final term = p.schedule?['term_id'];
    if (term == null) {
      setState(() {
        loading = false;
        note = t('اربط الجدول بفصل دراسي لعرض طلاب المجموعة.', 'Link the timetable to a term to see the group\'s students.');
      });
      return;
    }
    final base = '${p.base.replaceFirst(RegExp(r'/$'), '')}/registrar';
    final r = await orgCall(() => p.api.get('$base/terms/$term/groups/${widget.slot['course_id']}'), quiet: true);
    if (!mounted) return;
    final kind = widget.slot['kind'] ?? 'lecture';
    final no = asInt(widget.slot['group_no'], 1);
    setState(() {
      loading = false;
      group = [for (final g in asMapList(r.map['groups'])) if ((g['kind'] ?? 'lecture') == kind && asInt(g['group_no'], 1) == no) g].firstOrNull;
      if (group == null) {
        note = r.ok
            ? t('لا مجموعة مسجلة بعد — تُنشأ المجموعات عند نشر الجدول.', 'No registered group yet — groups are created when the timetable is published.')
            : orgErrorText(r.error!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.p;
    final s = widget.slot;
    final lab = s['kind'] == 'lab';
    final room = p.rooms.firstWhere((r) => asInt(r['id']) == asInt(s['room_id']), orElse: () => const {});
    final pers = blockPeriods(s, p.slots, p.periods);
    final time = pers.isEmpty ? '—' : AppTime.clockRange('${pers.first['start_time']}', '${pers.last['end_time']}');
    final (sessions, periods) = groupWeekly(s, p.slots);
    final students = asMapList(group?['students']);
    final enrolled = group == null ? null : asInt(group!['enrolled'], students.length);
    final cap = room.isEmpty ? null : asInt(room['capacity']);
    final over = enrolled != null && cap != null && enrolled > cap;
    String? person(Object? id) => id == null ? null : (widget.people[asInt(id)] ?? '#$id');

    Widget line(IconData icon, String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: color ?? c.textMedium),
            const SizedBox(width: 8),
            SizedBox(width: 96, child: Text(label, style: orgText(context, size: 12.5, color: c.textMedium))),
            Expanded(child: Text(value, style: orgText(context, size: 13, w: FontWeight.w700, color: color))),
          ]),
        );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(widget.courseNames[asInt(s['course_id'])] ?? '#${s['course_id']}', style: orgText(context, size: 17, w: FontWeight.w800)),
            const SizedBox(height: 8),
            line(lab ? Icons.science_rounded : Icons.menu_book_rounded, t('النوع', 'Type'), lab ? t('عملي (سكشن)', 'Practical (lab)') : t('نظري (محاضرة)', 'Theory (lecture)')),
            line(Icons.groups_2_rounded, t('المجموعة', 'Group'), s['group_no'] == null ? t('مجموعة واحدة', 'Single group') : '${s['group_no']}'),
            line(Icons.person_rounded, t('المدرس', 'Instructor'), person(s['teacher_id']) ?? '—'),
            if (s['assistant_id'] != null) line(Icons.person_outline_rounded, t('المعيد', 'TA'), person(s['assistant_id'])!),
            line(Icons.meeting_room_rounded, t('القاعة', 'Room'), room.isEmpty ? '—' : '${room['name']}${cap == null ? '' : ' · ${t('سعة', 'capacity')} $cap'}'),
            line(Icons.schedule_rounded, t('الموعد', 'Time'), '${dayLabelOf(s['day'])} · $time'),
            line(Icons.event_seat_rounded, t('السعة / المسجلون', 'Capacity / enrolled'),
                '${cap ?? '—'} / ${enrolled ?? '—'}${over ? '  ${t('(أكبر من السعة)', '(over capacity)')}' : ''}', color: over ? c.danger : null),
            line(Icons.insights_rounded, t('أسبوعياً', 'Weekly'),
                t('$sessions حصة · $periods فترة لهذه المجموعة', '$sessions session(s) · $periods period(s) for this group')),
            if (s['locked'] == true) line(Icons.push_pin_rounded, t('مثبتة', 'Pinned'), t('لا يحركها التوليد', 'Generation keeps it in place')),
            const Divider(height: 22),
            Text(t('طلاب المجموعة', 'Students of the group') + (students.isEmpty ? '' : ' (${students.length})'), style: orgText(context, w: FontWeight.w800)),
            const SizedBox(height: 6),
            if (loading) const LinearProgressIndicator(),
            if (!loading && note != null) Text(note!, style: orgText(context, size: 12.5, color: c.textMedium)),
            if (!loading && group != null && students.isEmpty) Text(t('لا طلاب في هذه المجموعة بعد.', 'No students in this group yet.'), style: orgText(context, size: 12.5, color: c.textMedium)),
            for (final (i, st) in students.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 30, child: Text('${i + 1}.', style: orgText(context, size: 12, color: c.textLight))),
                  Expanded(child: Text('${asMap(st['student'])['name'] ?? ''}', overflow: TextOverflow.ellipsis, style: orgText(context, size: 13))),
                  if (st['student_code'] != null) Text('${st['student_code']}', style: orgText(context, size: 12, color: c.textMedium)),
                ]),
              ),
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              if (widget.onEdit != null)
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onEdit!();
                  },
                  icon: const Icon(Icons.edit_rounded),
                  label: Text(t('تعديل', 'Edit')),
                ),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(t('إغلاق', 'Close'))),
            ]),
          ]),
        ),
      ),
    );
  }
}

String dayLabelOf(Object? day) => dayLabels()['$day'] ?? '$day';
