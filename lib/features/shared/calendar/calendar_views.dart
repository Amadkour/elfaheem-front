// lib/features/shared/calendar/calendar_views.dart — the day/week time grid and the month grid of the calendar.
//
// Both are pure views over a list of CalEvent: colour per source, side-by-side overlaps (calLayoutDay), the answer
// marker of meetings, a "now" line, tap a free slot to add, drag your own meetings to move them (long-press on touch,
// plain drag with a mouse). The screen (calendar_screen.dart) does the loading and the conflict checks.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'calendar_models.dart';

/// Lays [child] out with unbounded height and clips it to the box: text scaled up never throws an overflow.
class _Clip extends StatelessWidget {
  const _Clip({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: OverflowBox(
          alignment: AlignmentDirectional.topStart,
          minHeight: 0,
          maxHeight: double.infinity,
          child: child,
        ),
      );
}

Widget _draggable(CalEvent e, Size size, Widget child) {
  if (!e.editable || e.meetingId == null) return child;
  final feedback = Material(
    color: Colors.transparent,
    child: Opacity(opacity: 0.85, child: SizedBox(width: size.width, height: size.height, child: child)),
  );
  final ghost = Opacity(opacity: 0.3, child: child);
  return kIsWeb
      ? Draggable<CalEvent>(data: e, feedback: feedback, childWhenDragging: ghost, child: child)
      : LongPressDraggable<CalEvent>(data: e, feedback: feedback, childWhenDragging: ghost, child: child);
}

/// The coloured block of one event (time grid) or one chip (month grid).
class CalEventBlock extends StatelessWidget {
  const CalEventBlock({super.key, required this.event, this.compact = false, this.height = 60});
  final CalEvent event;
  final bool compact;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = event;
    final color = calEventColor(c, e);
    final pending = e.myStatus == 'pending' || e.myStatus == 'proposed';
    final title = Text(
      e.title,
      maxLines: compact ? 1 : (height > 60 ? 2 : 1),
      overflow: TextOverflow.ellipsis,
      style: appText(compact ? 10 : 11.5, w: FontWeight.w700, c: e.declined ? c.textLight : c.textDark).copyWith(
          decoration: e.declined ? TextDecoration.lineThrough : null),
    );
    final marker = e.isMeeting && !e.isOwner && e.myStatus != null
        ? Icon(calStatusIcon(e.myStatus), size: 12, color: calStatusColor(c, e.myStatus))
        : null;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: e.declined ? 0.06 : (pending ? 0.10 : 0.16)),
        borderRadius: BorderRadius.circular(compact ? 5 : 8),
        border: BorderDirectional(start: BorderSide(color: color, width: compact ? 2.5 : 3.5)),
      ),
      padding: EdgeInsetsDirectional.fromSTEB(compact ? 4 : 6, compact ? 1 : 3, 3, 1),
      child: _Clip(
        child: compact
            ? Row(children: [
                if (marker != null) ...[marker, const SizedBox(width: 2)],
                Expanded(child: title),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(child: title),
                  ?marker,
                ]),
                if (height > 34)
                  Text('${AppTime.time(e.start)} – ${AppTime.time(e.end)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(10, c: c.textMedium)),
                if (height > 52 && (e.location ?? e.subtitle ?? '').isNotEmpty)
                  Text(e.location ?? e.subtitle ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(10, c: c.textLight)),
                if (height > 70 && e.isOwner && e.counts.isNotEmpty) _Counts(counts: e.counts),
              ]),
      ),
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.counts});
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(spacing: 6, children: [
        for (final k in ['accepted', 'pending', 'proposed', 'declined'])
          if ((counts[k] ?? 0) > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(calStatusIcon(k), size: 11, color: calStatusColor(c, k)),
              const SizedBox(width: 2),
              Text('${counts[k]}', style: appText(10, w: FontWeight.w700, c: calStatusColor(c, k))),
            ]),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Day / week time grid
// ═════════════════════════════════════════════════════════════════════════════

class CalTimeGrid extends StatefulWidget {
  const CalTimeGrid({
    super.key,
    required this.days,
    required this.events,
    required this.onTapEvent,
    required this.onTapSlot,
    required this.onMove,
    this.onOpenDay,
    this.now,
    this.hourHeight = 56,
  });

  final List<DateTime> days; // wall days
  final List<CalEvent> events;
  final ValueChanged<CalEvent> onTapEvent;
  final ValueChanged<DateTime> onTapSlot; // wall start
  final void Function(CalEvent event, DateTime wallStart) onMove;
  final ValueChanged<DateTime>? onOpenDay;
  final DateTime? now; // wall; null = AppTime now
  final double hourHeight;

  @override
  State<CalTimeGrid> createState() => _CalTimeGridState();
}

class _CalTimeGridState extends State<CalTimeGrid> {
  late final ScrollController _scroll = ScrollController(initialScrollOffset: _firstHour() * widget.hourHeight);
  Timer? _tick;

  int _firstHour() {
    final starts = [
      for (final d in widget.days)
        for (final p in calLayoutDay(widget.events, d)) p.top ~/ 60,
    ];
    final first = starts.isEmpty ? 8 : starts.reduce((a, b) => a < b ? a : b);
    return ((first < 8 ? first : 8) - 1).clamp(0, 20); // an hour before the first event, 7:00 at the latest
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = widget.now ?? AppTime.toZone(DateTime.now().toUtc());
    final today = calDay(now);
    final hh = widget.hourHeight;
    return LayoutBuilder(builder: (context, box) {
      const gutter = 46.0;
      final colW = (box.maxWidth - gutter) / widget.days.length;
      return Column(children: [
        // sticky day headers
        Container(
          decoration: BoxDecoration(color: c.cardBg, border: Border(bottom: BorderSide(color: c.divider))),
          child: Row(children: [
            const SizedBox(width: gutter),
            for (final d in widget.days)
              SizedBox(
                width: colW,
                height: 54,
                child: InkWell(
                  onTap: widget.onOpenDay == null ? null : () => widget.onOpenDay!(d),
                  child: _DayHead(day: d, today: d == today),
                ),
              ),
          ]),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              child: SizedBox(
                height: 24 * hh,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: gutter,
                    child: Stack(children: [
                      for (var h = 1; h < 24; h++)
                        Positioned(
                          top: h * hh - 7,
                          left: 0,
                          right: 4,
                          child: Text(AppTime.clockMinutes(h * 60),
                              textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.clip, style: appText(9.5, c: c.textLight)),
                        ),
                    ]),
                  ),
                  for (final d in widget.days)
                    SizedBox(
                      width: colW,
                      child: _DayColumn(
                        day: d,
                        width: colW,
                        hourHeight: hh,
                        events: widget.events,
                        now: d == today ? now : null,
                        onTapEvent: widget.onTapEvent,
                        onTapSlot: widget.onTapSlot,
                        onMove: widget.onMove,
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

class _DayHead extends StatelessWidget {
  const _DayHead({required this.day, required this.today});
  final DateTime day;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final noon = AppTime.fromZone(DateTime(day.year, day.month, day.day, 12));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 1),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(AppTime.date(noon, pattern: 'EEE'), style: appText(11, w: FontWeight.w600, c: today ? c.primary : c.textLight)),
          const SizedBox(height: 2),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: today ? c.primary : Colors.transparent, shape: BoxShape.circle),
            child: Text('${day.day}', style: appText(14, w: FontWeight.w800, c: today ? Colors.white : c.textDark)),
          ),
        ]),
      ),
    );
  }
}

class _DayColumn extends StatefulWidget {
  const _DayColumn({
    required this.day,
    required this.width,
    required this.hourHeight,
    required this.events,
    required this.onTapEvent,
    required this.onTapSlot,
    required this.onMove,
    this.now,
  });

  final DateTime day;
  final double width, hourHeight;
  final List<CalEvent> events;
  final DateTime? now;
  final ValueChanged<CalEvent> onTapEvent;
  final ValueChanged<DateTime> onTapSlot;
  final void Function(CalEvent, DateTime) onMove;

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  final _key = GlobalKey();
  int? _hover; // minutes of the drop preview

  int _minutesAt(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    return calSnap(box.globalToLocal(global).dy, widget.hourHeight);
  }

  DateTime _at(int minutes) => DateTime(widget.day.year, widget.day.month, widget.day.day, minutes ~/ 60, minutes % 60);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hh = widget.hourHeight;
    final placed = calLayoutDay(widget.events, widget.day);
    return DragTarget<CalEvent>(
      onWillAcceptWithDetails: (d) => d.data.editable,
      onMove: (d) {
        final m = _minutesAt(d.offset);
        if (m != _hover) setState(() => _hover = m);
      },
      onLeave: (_) => setState(() => _hover = null),
      onAcceptWithDetails: (d) {
        final m = _minutesAt(d.offset);
        setState(() => _hover = null);
        widget.onMove(d.data, _at(m));
      },
      builder: (context, candidates, _) => GestureDetector(
        key: _key,
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => widget.onTapSlot(_at(calSnap(d.localPosition.dy - hh / 4, hh, step: 30))),
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter(hh, c.divider, widget.now != null ? c.primary.withValues(alpha: 0.03) : null))),
          if (_hover != null && candidates.isNotEmpty)
            Positioned(
              top: _hover! / 60 * hh,
              left: 2,
              right: 2,
              height: (candidates.first!.duration.inMinutes / 60 * hh).clamp(16, 24 * hh),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.primary, width: 1.5),
                ),
                child: _Clip(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Text(AppTime.clockMinutes(_hover!), maxLines: 1, style: appText(10, w: FontWeight.w700, c: c.primary)),
                  ),
                ),
              ),
            ),
          for (final p in placed)
            Builder(builder: (context) {
              final w = widget.width - 4;
              final top = p.top / 60 * hh;
              final h = ((p.bottom - p.top) / 60 * hh - 2).clamp(16.0, 24 * hh);
              final left = 1 + w * p.col / p.cols;
              final bw = w / p.cols - 1;
              return Positioned(
                top: top,
                left: left,
                width: bw,
                height: h,
                child: _draggable(
                  p.event,
                  Size(bw, h),
                  GestureDetector(
                    onTap: () => widget.onTapEvent(p.event),
                    child: Semantics(
                      button: true,
                      label: p.event.title,
                      child: CalEventBlock(event: p.event, height: h),
                    ),
                  ),
                ),
              );
            }),
          if (widget.now != null)
            Positioned(
              top: (widget.now!.hour * 60 + widget.now!.minute) / 60 * hh - 1,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle)),
                  Expanded(child: Container(height: 2, color: c.danger)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.hh, this.line, this.fill);
  final double hh;
  final Color line;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (fill != null) canvas.drawRect(Offset.zero & size, Paint()..color = fill!);
    final p = Paint()
      ..color = line
      ..strokeWidth = 1;
    final half = Paint()
      ..color = line.withValues(alpha: line.a * 0.45)
      ..strokeWidth = 1;
    for (var h = 0; h < 24; h++) {
      canvas.drawLine(Offset(0, h * hh), Offset(size.width, h * hh), p);
      canvas.drawLine(Offset(0, h * hh + hh / 2), Offset(size.width, h * hh + hh / 2), half);
    }
    canvas.drawLine(const Offset(0, 0), Offset(0, size.height), p);
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.hh != hh || old.line != line || old.fill != fill;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Month grid
// ═════════════════════════════════════════════════════════════════════════════

class CalMonthGrid extends StatelessWidget {
  const CalMonthGrid({
    super.key,
    required this.month,
    required this.days,
    required this.events,
    required this.onTapDay,
    required this.onTapEvent,
    required this.onMove,
    this.now,
  });

  final DateTime month;
  final List<DateTime> days; // 42
  final List<CalEvent> events;
  final ValueChanged<DateTime> onTapDay;
  final ValueChanged<CalEvent> onTapEvent;
  final void Function(CalEvent event, DateTime wallStart) onMove;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = calDay(now ?? AppTime.toZone(DateTime.now().toUtc()));
    return LayoutBuilder(builder: (context, box) {
      final colW = box.maxWidth / 7;
      final avail = box.maxHeight - 28;
      final cellH = (avail / 6).clamp(76.0, 160.0);
      final dense = colW < 76;
      final grid = Column(children: [
        for (var r = 0; r < 6; r++)
          SizedBox(
            height: cellH,
            child: Row(children: [
              for (var k = 0; k < 7; k++)
                SizedBox(
                  width: colW,
                  child: _MonthCell(
                    day: days[r * 7 + k],
                    inMonth: days[r * 7 + k].month == month.month,
                    today: days[r * 7 + k] == today,
                    events: calEventsOnDay(events, days[r * 7 + k]),
                    height: cellH,
                    dense: dense,
                    onTapDay: onTapDay,
                    onTapEvent: onTapEvent,
                    onMove: onMove,
                  ),
                ),
            ]),
          ),
      ]);
      return Column(children: [
        SizedBox(
          height: 28,
          child: Row(children: [
            for (var k = 0; k < 7; k++)
              SizedBox(
                width: colW,
                child: Center(
                  child: Text(AppTime.date(AppTime.fromZone(DateTime(days[k].year, days[k].month, days[k].day, 12)), pattern: 'EEE'),
                      maxLines: 1, overflow: TextOverflow.clip, style: appText(11, w: FontWeight.w700, c: c.textLight)),
                ),
              ),
          ]),
        ),
        Expanded(child: 6 * cellH > avail + 0.5 ? SingleChildScrollView(child: grid) : grid),
      ]);
    });
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.events,
    required this.height,
    required this.dense,
    required this.onTapDay,
    required this.onTapEvent,
    required this.onMove,
  });

  final DateTime day;
  final bool inMonth, today, dense;
  final List<CalEvent> events;
  final double height;
  final ValueChanged<DateTime> onTapDay;
  final ValueChanged<CalEvent> onTapEvent;
  final void Function(CalEvent, DateTime) onMove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fit = ((height - 30) / 19).floor().clamp(0, 6);
    final shown = events.length > fit ? events.take((fit - 1).clamp(0, fit)).toList() : events;
    final more = events.length - shown.length;
    return DragTarget<CalEvent>(
      onWillAcceptWithDetails: (d) => d.data.editable,
      onAcceptWithDetails: (d) {
        final w = d.data.wallStart;
        onMove(d.data, DateTime(day.year, day.month, day.day, w.hour, w.minute));
      },
      builder: (context, cand, _) => InkWell(
        onTap: () => onTapDay(day),
        child: Container(
          decoration: BoxDecoration(
            color: cand.isNotEmpty ? c.primary.withValues(alpha: 0.10) : (inMonth ? c.cardBg : c.background),
            border: Border.all(color: c.divider, width: 0.5),
          ),
          padding: const EdgeInsets.all(3),
          child: _Clip(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: AlignmentDirectional.topStart,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: today ? c.primary : Colors.transparent, shape: BoxShape.circle),
                  child: Text('${day.day}',
                      style: appText(11.5, w: FontWeight.w800, c: today ? Colors.white : (inMonth ? c.textDark : c.textLight))),
                ),
              ),
              const SizedBox(height: 2),
              if (dense)
                Wrap(spacing: 3, runSpacing: 3, children: [
                  for (final e in events.take(8))
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: calEventColor(c, e), shape: BoxShape.circle)),
                ])
              else ...[
                for (final e in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: SizedBox(
                      height: 17,
                      child: _draggable(
                        e,
                        const Size(120, 17),
                        GestureDetector(onTap: () => onTapEvent(e), child: CalEventBlock(event: e, compact: true, height: 17)),
                      ),
                    ),
                  ),
                if (more > 0)
                  Text('+$more ${t('أخرى', 'more')}', maxLines: 1, style: appText(10, w: FontWeight.w700, c: c.primary)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
