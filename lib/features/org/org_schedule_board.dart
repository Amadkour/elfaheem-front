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
import 'org_schedule_grid.dart' show sessionKindColor, sessionKindIcon, sessionKindLabel;
import 'org_schedule_insights.dart' show WhyHere, WhyHereSection;
import 'org_ui.dart';
import 'org_v3.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

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
    this.today,
  });

  final List<String> days;
  final List<Map<String, dynamic>> periods;
  final String Function(String day) dayLabel;
  final Widget Function(Map<String, dynamic> period) periodLabel;

  /// period id → the most sessions in one of its cells (row height)
  final int Function(int periodId) rowSessions;
  final Widget Function(String day, Map<String, dynamic> period, double height) cell;
  final double cellWidth, firstWidth;

  /// the day key to accent in the header (today), if it is shown
  final String? today;

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
    final line = BorderSide(color: c.divider.withValues(alpha: 0.7));
    final header = Row(
      children: [
        for (final d in widget.days)
          SizedBox(
            width: widget.cellWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                decoration: d == widget.today ? BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)) : null,
                child: Text(
                  widget.dayLabel(d),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, fontSize: 13, color: d == widget.today ? c.primary : c.textDark),
                ),
              ),
            ),
          ),
      ],
    );
    final heights = {for (final p in widget.periods) asInt(p['id']): boardRowHeight(widget.rowSessions(asInt(p['id'])), scale)};
    return Column(
      children: [
        // sticky day header (stays while the periods scroll) — its bar scrolls the grid sideways
        Container(
          decoration: BoxDecoration(
            color: c.cardBg,
            border: Border(bottom: line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: widget.firstWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Icon(Icons.schedule_rounded, size: 18, color: c.textLight),
                ),
              ),
              Expanded(
                child: AppHScroll(
                  controller: _head,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(width: width, child: header),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 40),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // sticky period column (stays while the days scroll)
                Container(
                  width: widget.firstWidth,
                  decoration: BoxDecoration(
                    color: c.cardBg,
                    border: BorderDirectional(end: line),
                  ),
                  child: Column(
                    children: [
                      for (final p in widget.periods)
                        Container(
                          height: heights[asInt(p['id'])],
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(border: Border(bottom: line)),
                          child: Center(child: widget.periodLabel(p)),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: AppHScroll(
                    controller: _body,
                    thumbVisibility: false,
                    padding: EdgeInsets.zero,
                    child: SizedBox(
                      width: width,
                      child: Column(
                        children: [
                          for (final (i, p) in widget.periods.indexed)
                            Container(
                              height: heights[asInt(p['id'])],
                              decoration: BoxDecoration(
                                color: i.isOdd ? c.inputBg.withValues(alpha: 0.35) : null,
                                border: Border(bottom: line),
                              ),
                              child: Row(
                                children: [for (final d in widget.days) SizedBox(width: widget.cellWidth, child: widget.cell(d, p, heights[asInt(p['id'])]!))],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Session details
// ═════════════════════════════════════════════════════════════════════════════

/// The periods of [slot]'s block (a double session spans several), in time order.
List<Map<String, dynamic>> blockPeriods(Map<String, dynamic> slot, List<Map<String, dynamic>> slots, List<Map<String, dynamic>> periods) {
  final same = slot['block_id'] == null
      ? [slot]
      : [
          for (final x in slots)
            if (x['block_id'] == slot['block_id'] && x['day'] == slot['day'] && asInt(x['course_id']) == asInt(slot['course_id'])) x,
        ];
  final ids = {for (final x in same) asInt(x['period_id'])};
  return [
    for (final p in periods)
      if (ids.contains(asInt(p['id']))) p,
  ]..sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}'));
}

/// Weekly sessions (blocks) and periods of one course / kind / group.
(int, int) groupWeekly(Map<String, dynamic> slot, List<Map<String, dynamic>> slots) {
  bool mine(Map<String, dynamic> x) => asInt(x['course_id']) == asInt(slot['course_id']) && (x['kind'] ?? 'lecture') == (slot['kind'] ?? 'lecture') && x['group_no'] == slot['group_no'];
  final own = slots.where(mine).toList();
  return ({for (final x in own) '${x['day']}|${x['block_id'] ?? x['id']}'}.length, own.length);
}

Future<void> showSessionDetails(
  BuildContext context,
  OrgScheduleProvider p,
  Map<String, dynamic> slot, {
  required Map<int, String> courseNames,
  required Map<int, String> people,
  VoidCallback? onEdit,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _SessionDialog(p: p, slot: slot, courseNames: courseNames, people: people, onEdit: onEdit),
  );
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
  WhyHere? why; // GET …/slots/{id}/why (null until loaded; whyMissing on an old server)
  bool whyLoading = true, whyMissing = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadWhy();
  }

  Future<void> _loadWhy() async {
    final p = widget.p;
    final sid = p.schedule?['id'], id = widget.slot['id'];
    if (sid == null || id == null) {
      if (mounted) setState(() => whyLoading = false);
      return;
    }
    final r = await orgCall(() => p.api.get('${p.base}/schedules/$sid/slots/$id/why'), quiet: true);
    if (!mounted) return;
    setState(() {
      whyLoading = false;
      whyMissing = !r.ok;
      why = r.ok ? WhyHere.of(r.map) : null;
    });
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
      group = [
        for (final g in asMapList(r.map['groups']))
          if ((g['kind'] ?? 'lecture') == kind && asInt(g['group_no'], 1) == no) g,
      ].firstOrNull;
      if (group == null) {
        note = r.ok ? t('لا مجموعة مسجلة بعد — تُنشأ المجموعات عند نشر الجدول.', 'No registered group yet — groups are created when the timetable is published.') : orgErrorText(r.error!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.p;
    final s = widget.slot;
    final room = p.rooms.firstWhere((r) => asInt(r['id']) == asInt(s['room_id']), orElse: () => const {});
    final pers = blockPeriods(s, p.slots, p.periods);
    final time = pers.isEmpty ? '—' : AppTime.clockRange('${pers.first['start_time']}', '${pers.last['end_time']}');
    final (sessions, periods) = groupWeekly(s, p.slots);
    final students = asMapList(group?['students']);
    final enrolled = group == null ? null : asInt(group!['enrolled'], students.length);
    final cap = room.isEmpty ? null : asInt(room['capacity']);
    final over = enrolled != null && cap != null && enrolled > cap;
    String? person(Object? id) => id == null ? null : (widget.people[asInt(id)] ?? '#$id');

    final col = sessionKindColor(c, s['kind']);
    final id = asInt(s['id']);
    final mine = [
      for (final x in p.conflicts)
        if (((x['slot_ids'] as List?) ?? const []).map(asInt).contains(id)) x,
    ]..sort((a, b) => (a['severity'] == 'error' ? 0 : 1).compareTo(b['severity'] == 'error' ? 0 : 1));

    // one fact: small label over its value, two per row when there is room
    Widget fact(IconData icon, String label, String value, {Color? color}) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.inputBg.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color ?? c.textMedium),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: orgText(context, size: 11.5, color: c.textMedium),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: orgText(context, size: 13, w: FontWeight.w700, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    Widget pill(String text, Color color, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: orgText(context, size: 11.5, w: FontWeight.w800, color: color),
            ),
          ),
        ],
      ),
    );

    final facts = [
      fact(Icons.schedule_rounded, t('الموعد', 'When'), '${dayLabelOf(s['day'])} · $time'),
      fact(Icons.meeting_room_rounded, t('القاعة', 'Room'), room.isEmpty ? '—' : '${room['name']}${cap == null ? '' : ' · ${t('سعة', 'cap.')} $cap'}'),
      fact(Icons.person_rounded, t('المدرس', 'Instructor'), person(s['teacher_id']) ?? '—'),
      if (s['assistant_id'] != null) fact(Icons.person_outline_rounded, t('المعيد', 'TA'), person(s['assistant_id'])!),
      fact(
        Icons.event_seat_rounded,
        t('السعة / المسجلون', 'Capacity / enrolled'),
        '${cap ?? '—'} / ${enrolled ?? '—'}${over ? '  ${t('(أكبر من السعة)', '(over capacity)')}' : ''}',
        color: over ? c.danger : null,
      ),
      fact(Icons.insights_rounded, t('أسبوعياً', 'Weekly'), t('$sessions حصة · $periods فترة', '$sessions session(s) · $periods period(s)')),
    ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      backgroundColor: c.cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // header band in the session type's colour
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 8, 14),
              decoration: BoxDecoration(
                color: col.withValues(alpha: 0.10),
                border: BorderDirectional(start: BorderSide(color: col, width: 5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: col.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                    child: Icon(sessionKindIcon(s['kind']), color: col, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.courseNames[asInt(s['course_id'])] ?? '#${s['course_id']}', style: orgText(context, size: 17, w: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            pill(sessionKindLabel(s['kind']), col),
                            pill(s['group_no'] == null ? t('مجموعة واحدة', 'Single group') : '${t('مجموعة', 'Group')} ${s['group_no']}', c.textMedium),
                            if (s['locked'] == true) pill(t('مثبتة', 'Pinned'), c.textMedium, icon: Icons.push_pin_rounded),
                            if (mine.isNotEmpty) pill(t('${mine.length} تعارض', '${mine.length} conflict(s)'), mine.first['severity'] == 'error' ? c.danger : c.warning, icon: Icons.error_rounded),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t('إغلاق', 'Close'),
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: c.textMedium),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LayoutBuilder(
                      builder: (context, box) {
                        final two = box.maxWidth >= 380;
                        final w = two ? (box.maxWidth - 8) / 2 : box.maxWidth;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final f in facts) SizedBox(width: w, child: f)],
                        );
                      },
                    ),
                    if (mine.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final x in mine)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (x['severity'] == 'error' ? c.danger : c.warning).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: (x['severity'] == 'error' ? c.danger : c.warning).withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(x['severity'] == 'error' ? Icons.error_rounded : Icons.warning_amber_rounded, size: 18, color: x['severity'] == 'error' ? c.danger : c.warning),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  x['text_ar'] != null ? t('${x['text_ar']}', '${x['text_en'] ?? x['text_ar']}') : conflictTypeText('${x['type']}'),
                                  style: orgText(context, size: 12.5, w: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 6),
                    // why here: what the engine saw for this session (every other session fixed)
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        initiallyExpanded: true,
                        leading: Icon(Icons.psychology_alt_rounded, color: c.textMedium),
                        title: Text(t('لماذا هنا؟', 'Why here?'), style: orgText(context, w: FontWeight.w800)),
                        children: [
                          if (whyLoading) const LinearProgressIndicator(),
                          if (!whyLoading && whyMissing)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(t('التفسير يحتاج تحديث الخادم.', 'Explanations need a server update.'), style: orgText(context, size: 12.5, color: c.textMedium)),
                            ),
                          if (why != null)
                            WhyHereSection(
                              why: why!,
                              periodLabel: (pid) => '${p.periods.where((x) => asInt(x['id']) == pid).map((x) => x['label']).firstOrNull ?? 'P$pid'}',
                            ),
                        ],
                      ),
                    ),
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        initiallyExpanded: students.isNotEmpty && students.length <= 8,
                        leading: Icon(Icons.groups_rounded, color: c.textMedium),
                        title: Text(t('طلاب المجموعة', 'Students of the group') + (students.isEmpty ? '' : ' (${students.length})'), style: orgText(context, w: FontWeight.w800)),
                        children: [
                          if (loading) const LinearProgressIndicator(),
                          if (!loading && note != null)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(note!, style: orgText(context, size: 12.5, color: c.textMedium)),
                            ),
                          if (!loading && group != null && students.isEmpty)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(t('لا طلاب في هذه المجموعة بعد.', 'No students in this group yet.'), style: orgText(context, size: 12.5, color: c.textMedium)),
                            ),
                          for (final (i, st) in students.indexed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 30,
                                    child: Text('${i + 1}.', style: orgText(context, size: 12, color: c.textLight)),
                                  ),
                                  Expanded(
                                    child: Text('${asMap(st['student'])['name'] ?? ''}', overflow: TextOverflow.ellipsis, style: orgText(context, size: 13)),
                                  ),
                                  if (st['student_code'] != null) Text('${st['student_code']}', style: orgText(context, size: 12, color: c.textMedium)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 6,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(t('إغلاق', 'Close'))),
                  if (widget.onEdit != null)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onEdit!();
                      },
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: Text(t('تعديل الحصة', 'Edit session')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String dayLabelOf(Object? day) => dayLabels()['$day'] ?? '$day';
