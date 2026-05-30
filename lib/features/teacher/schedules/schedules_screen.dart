library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart' show TeacherCourse, CourseSchedule;
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/primary_button.dart';
import 'schedules_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  ScheduleTabBody
// ══════════════════════════════════════════════════════════════════════════════

class ScheduleTabBody extends StatefulWidget {
  final ChangeNotifier provider;
  final ScheduleResponse?  Function()        getData;
  final Future<void>       Function()        onRefresh;
  final DateTime?          Function()        getLastFetched;
  final String title;
  final String emptyMessage;

   const ScheduleTabBody({
    super.key,
    required this.provider,
    required this.getData,
    required this.onRefresh,
    required this.getLastFetched,
    this.title       = 'time-table',
    this.emptyMessage ='no-time-table',
  });

  @override
  State<ScheduleTabBody> createState() => _ScheduleTabBodyState();
}

class _ScheduleTabBodyState extends State<ScheduleTabBody>
    with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;

  // Local 1-second ticker — only for the live countdown inside cards
  Timer? _tick;
  int    _epoch = 0;
  int    _ongoingSecondsLeft = 0;

  // Whether a manual refresh is in flight (drives the spinning icon)
  bool _refreshing = false;

  String? _selectedDay;

  @override
  void initState() {
    super.initState();
    // Lightweight tick — just for the countdown display, not network calls
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _epoch++;
        if (_ongoingSecondsLeft > 0) _ongoingSecondsLeft--;
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _syncOngoing(ScheduleResponse? data) {
    if (data == null) return;
    final ongoing = data.todaySlots.where((s) => s.isOngoing).firstOrNull;
    if (ongoing != null && _ongoingSecondsLeft == 0) {
      _ongoingSecondsLeft = (ongoing.minutesUntilEnd ?? 0) * 60;
    }
  }

  Future<void> _doRefresh() async {
    if (_refreshing) return;
    if(mounted) setState(() => _refreshing = true);
    await widget.onRefresh();
    if (mounted) if(mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return  ListenableBuilder(
          listenable: widget.provider,
          builder: (_, __) {
            final data        = widget.getData();
            final lastFetched = widget.getLastFetched();
            _syncOngoing(data);

            if (data == null) {
              return _LoadingState(onRefresh: _doRefresh);
            }

            final activeDays = data.activeDays;
            _selectedDay ??= data.todayDay.isEmpty ? null : data.todayDay;

            final dayHasSlots = _selectedDay != null &&
                activeDays.contains(_selectedDay);
            final shownSlots  = dayHasSlots
                ? data.slotsForDay(_selectedDay!)
                : <ScheduleSlot>[];

            return RefreshIndicator(
              color: context.colors.primary,
              onRefresh: _doRefresh,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: [

                  // ── Header ────────────────────────────────────────
                  SliverToBoxAdapter(child: _Header(
                    title:              widget.title.tr,
                    todayLabel:         data.todayLabel,
                    nextSlot:           data.nextSlot,
                    epoch:              _epoch,
                    ongoingSecondsLeft: _ongoingSecondsLeft,
                    lastFetched:        lastFetched,
                    isRefreshing:       _refreshing,
                    onRefresh:          _doRefresh,
                  )),

                  // ── Week strip ────────────────────────────────────
                  SliverToBoxAdapter(child: _WeekStrip(
                    activeDays:  activeDays,
                    todayDay:    data.todayDay,
                    selectedDay: _selectedDay ?? data.todayDay,
                    onSelect:    (d) { if(mounted) setState(() => _selectedDay = d);},
                    slotsForDay: data.slotsForDay,
                  )),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // ── Slot list ─────────────────────────────────────
                  if (shownSlots.isEmpty)
                    SliverToBoxAdapter(child: _EmptyDay(
                      day:     _selectedDay != null ? slotDayLabel(_selectedDay!) : '',
                      isToday: _selectedDay == data.todayDay,
                      message: activeDays.isEmpty ? widget.emptyMessage : null,
                    ))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverList.separated(
                        itemCount: shownSlots.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => ScheduleSlotCard(
                          slot:               shownSlots[i],
                          isSelectedDay:      _selectedDay == data.todayDay,
                          ongoingSecondsLeft: _ongoingSecondsLeft,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String        title;
  final String        todayLabel;
  final ScheduleSlot? nextSlot;
  final int           epoch;
  final int           ongoingSecondsLeft;
  final DateTime?     lastFetched;
  final bool          isRefreshing;
  final VoidCallback  onRefresh;

  const _Header({
    required this.title,
    required this.todayLabel,
    required this.epoch,
    required this.ongoingSecondsLeft,
    required this.isRefreshing,
    required this.onRefresh,
    this.nextSlot,
    this.lastFetched,
  });

  String _lastFetchedLabel() {
    if (lastFetched == null) return 'not-refreshed'.tr;
    final diff = DateTime.now().difference(lastFetched!);
    if (diff.inSeconds < 60)  return 'moments-ago'.tr;
    if (diff.inMinutes < 60)  return 'since ${diff.inMinutes}m'.tr;
    if (diff.inHours   < 24)  return 'since ${diff.inHours}hours'.tr;
    return 'since ${diff.inDays} day'.tr;
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Row(children: [
          // Title + date
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.tr, style: context.colors.h1),
              const SizedBox(height: 2),
              Text(todayLabel, style: context.colors.caption.copyWith(fontSize: 12)),
            ],
          )),

        ]),
      ),

      // Last-updated chip
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Row(children: [
          Icon(Icons.history_rounded,
              size: 13,
              color: context.colors.textLight.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(
            _lastFetchedLabel(),
            style: context.colors.caption.copyWith(
                fontSize: 11,
                color: context.colors.textLight.withValues(alpha: 0.8)),
          ),
        ]),
      ),

      // Next session banner
      if (nextSlot != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: _NextBanner(
              slot: nextSlot!, ongoingSecondsLeft: ongoingSecondsLeft),
        ),
    ]);
  }
}

// ── Next session banner ───────────────────────────────────────────────────────

class _NextBanner extends StatelessWidget {
  final ScheduleSlot slot;
  final int ongoingSecondsLeft;

  const _NextBanner({required this.slot, required this.ongoingSecondsLeft});

  @override
  Widget build(BuildContext context) {
    final isNow    = slot.isOngoing;
    final gradient = isNow
        ? const LinearGradient(
        colors: [Color(0xFFB71C1C), Color(0xFFEF5350)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight)
        : context.colors.primaryGradient;

    return Container(
      decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: context.colors.primaryShadow),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(children: [
          // Decorative circles
          Positioned(right: -20, top: -20,
              child: _GlassCircle(size: 110)),
          Positioned(left: -30, bottom: -30,
              child: _GlassCircle(size: 90)),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, isOngoingConst ? 22 : 18),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // Info
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status label
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      isNow ? '🔴 ${'play-now'.tr}' : '🕐 ${'next-lesson'.tr}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFamily: 'bahji',
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(slot.courseName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontFamily: 'bahji',
                          fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.access_time_rounded,
                        color: Colors.white70, size: 13),
                    const SizedBox(width: 4),
                    Text('${slot.startTime}  —  ${slot.endTime}',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFamily: 'bahji')),
                    if (slot.calcDuration > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text('${slot.calcDuration}د',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontFamily: 'bahji')),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 10),
                  // Countdown pill
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      slot.countdownLabel(ongoingSecondsLeft),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontFamily: 'bahji',
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              )),

              const SizedBox(width: 14),

              // Right widget: progress ring or bell
              if (isNow)
                _ProgressRing(
                    progress: slot.progressFraction(ongoingSecondsLeft))
              else
                Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.notifications_active_rounded,
                        color: Colors.white, size: 30)),
            ]),
          ),

          // Bottom progress bar (ongoing)
          if (isNow)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: ClipRRect(
                borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(20)),
                child: LinearProgressIndicator(
                  value: slot.progressFraction(ongoingSecondsLeft),
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                  minHeight: 4,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ignore: constant_identifier_names
const isOngoingConst = false; // placeholder to satisfy Positioned inline const

class _GlassCircle extends StatelessWidget {
  final double size;

  const _GlassCircle({required this.size});


  @override
  Widget build(BuildContext context) =>


      Container(
      width: size, height: size,
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          shape: BoxShape.circle));
}

class _ProgressRing extends StatelessWidget {
  final double progress;
  const _ProgressRing({required this.progress});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 60, height: 60,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
                size: const Size(60, 60),
                painter: _RingPainter(progress)),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${(progress * 100).toInt()}%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'bahji')),
               Text('completed'.tr,
                  style: TextStyle(
                      color: Colors.white60,
                      fontSize: 9,
                      fontFamily: 'bahji')),
            ]),
          ]));
}

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 5;
    canvas.drawCircle(c, r,
        Paint()
          ..color       = Colors.white.withValues(alpha: 0.2)
          ..strokeWidth = 5
          ..style       = PaintingStyle.stroke);
    if (progress > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          -math.pi / 2,
          2 * math.pi * progress,
          false,
          Paint()
            ..color       = Colors.white
            ..strokeWidth = 5
            ..style       = PaintingStyle.stroke
            ..strokeCap   = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ── Week strip ────────────────────────────────────────────────────────────────

class _WeekStrip extends StatelessWidget {
  final List<String> activeDays;
  final String todayDay;
  final String selectedDay;
  final void Function(String) onSelect;
  final List<ScheduleSlot> Function(String) slotsForDay;

  const _WeekStrip({
    required this.activeDays,
    required this.todayDay,
    required this.selectedDay,
    required this.onSelect,
    required this.slotsForDay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: kDayOrder.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final day        = kDayOrder[i];
            final isActive   = activeDays.contains(day);
            final isToday    = day == todayDay;
            final isSel      = day == selectedDay;
            final count      = slotsForDay(day).length;
            final hasOngoing = slotsForDay(day).any((s) => s.isOngoing);

            return GestureDetector(
              onTap: isActive ? () => onSelect(day) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 56,
                decoration: BoxDecoration(
                  gradient: isSel
                      ? context.colors.primaryGradient
                      : isToday
                      ? LinearGradient(colors: [
                    context.colors.primary.withValues(alpha: 0.13),
                    context.colors.primary.withValues(alpha: 0.06),
                  ])
                      : null,
                  color: isSel || isToday ? null : context.colors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(

                      color: isSel
                          ? Colors.transparent
                          : isToday
                          ? context.colors.primary.withValues(alpha: 0.4)
                          : isActive
                          ? context.colors.divider
                          : context.colors.divider.withValues(alpha: 0.35),
                      width: isSel ? 0 : 1,
                    ),


                  boxShadow: isSel ? context.colors.primaryShadow : null,
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        slotDayShort(day),
                        style: TextStyle(
                          fontFamily: 'bahji',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isSel
                              ? Colors.white
                              : isToday
                              ? context.colors.primary
                              : isActive
                              ? context.colors.textDark
                              : context.colors.textLight,
                        ),
                      ),
                      const SizedBox(height: 5),
                      // Dot indicator
                      if (isActive && count > 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: hasOngoing
                                    ? (isSel ? Colors.white : context.colors.danger)
                                    : isSel
                                    ? Colors.white.withValues(alpha: 0.8)
                                    : isToday
                                    ? context.colors.primary
                                    : context.colors.textLight,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        )
                      else
                        const SizedBox(width: 6, height: 6),
                    ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ScheduleSlotCard
// ══════════════════════════════════════════════════════════════════════════════

class ScheduleSlotCard extends StatelessWidget {
  final ScheduleSlot slot;
  final bool isSelectedDay;
  final int  ongoingSecondsLeft;
  final bool showCourseName;

  const ScheduleSlotCard({
    super.key,
    required this.slot,
    this.isSelectedDay      = true,
    this.ongoingSecondsLeft = 0,
    this.showCourseName     = true,
  });

  @override
  Widget build(BuildContext context) {
    final isNow   = slot.isOngoing;
    final isToday = slot.isToday;

    final accentColor = isNow
        ? context.colors.danger
        : isToday
        ? context.colors.success
        : context.colors.primary;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: context.colors.cardShadow,
        border: Border(
          right: BorderSide(
            color: isNow
                ? context.colors.danger
                : isToday
                ? context.colors.success
                : context.colors.primaryBlue,
            width: isNow ? 4 : isToday ? 4 : 4,
          ),

        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [


        // ── Main row ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Time block ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                Text(slot.startTime,
                    style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: accentColor)),
                Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    width: 1.5, height: 14,
                    color: accentColor.withValues(alpha: 0.3)),
                Text(slot.endTime,
                    style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 11,
                        color: accentColor.withValues(alpha: 0.7))),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                width: 1,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

            // ── Info ─────────────────────────────────────────────────────
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showCourseName)
                    Text(slot.courseName,
                        style: context.colors.h3.copyWith(fontSize: 15),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis)
                  else
                    Text(slot.dayLabelStr, style: context.colors.label),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    _InfoChip(Icons.access_time_rounded,
                        '${slot.calcDuration}${'m'.tr}', accentColor.withValues(alpha: 0.8)),
                    if (slot.maxStudents != null)
                      _InfoChip(Icons.people_outline_rounded,
                          'حتى ${slot.maxStudents}', context.colors.textLight),
                    if (slot.scheduledDate != null && !isToday)
                      _InfoChip(Icons.calendar_today_rounded,
                          slot.scheduledDate!, context.colors.textLight),
                  ]),
                  const SizedBox(height: 8),
                  _StatusRow(
                      slot: slot,
                      ongoingSecondsLeft: ongoingSecondsLeft,
                      accentColor: accentColor),
                ])),

            // ── Badge ─────────────────────────────────────────────────────
            const SizedBox(width: 8),
            _StatusBadge(slot: slot),
          ]),
        ),

        // ── Progress bar (ongoing only) ──────────────────────────────────
        if (isNow)
          LinearProgressIndicator(
            value: slot.progressFraction(ongoingSecondsLeft),
            backgroundColor: context.colors.danger.withValues(alpha: 0.1),
            valueColor:  AlwaysStoppedAnimation(context.colors.danger),
            minHeight: 4,
          ),
      ]),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final ScheduleSlot slot;
  final int          ongoingSecondsLeft;
  final Color        accentColor;

  const _StatusRow({
    required this.slot,
    required this.ongoingSecondsLeft,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (slot.isOngoing) {
      final pct = ((slot.progressFraction(ongoingSecondsLeft)) * 100).toInt();
      return Row(children: [
         Icon(Icons.timer_outlined, size: 13, color: context.colors.danger),
        const SizedBox(width: 4),
        Text(slot.countdownLabel(ongoingSecondsLeft),
            style:  TextStyle(
                fontFamily: 'bahji',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.colors.danger)),
        const SizedBox(width: 8),
        Text('$pct%',
            style: context.colors.caption.copyWith(color: context.colors.danger)),
      ]);
    }
    if (slot.isToday) {
      return Row(children: [
        Icon(Icons.play_circle, size: 13, color: accentColor),
        const SizedBox(width: 4),
        Text(slot.countdownLabel(0),
            style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accentColor)),
      ]);
    }
    return Row(children: [
       Icon(Icons.calendar_month_outlined,
          size: 13, color: context.colors.textLight),
      const SizedBox(width: 4),
      Text(slot.dayLabelStr,
          style: context.colors.caption.copyWith(fontWeight: FontWeight.w600)),
    ]);
  }
}

class _StatusBadge extends StatelessWidget {
  final ScheduleSlot slot;
  const _StatusBadge({required this.slot});

  @override
  Widget build(BuildContext context) {
    if (slot.isOngoing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color:  context.colors.danger.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: context.colors.danger.withValues(alpha: 0.3))),
        child:  Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 7, color: context.colors.danger),
          SizedBox(width: 4),
          Text('session_type_live'.tr,
              style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: context.colors.danger)),
        ]),
      );
    }
    if (slot.isToday) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color:  context.colors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            // border: Border.all(
            //     color: context.colors.success.withValues(alpha: 0.3))
               ),
        child:  Text('today'.tr,
            style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: context.colors.success)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8)),
      child: Text(slotDayShort(slot.day),
          style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: context.colors.primary.withValues(alpha: 0.8))),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _InfoChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext _) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color:  AppTheme.textLight),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontFamily: 'bahji', fontSize: 11, color: AppTheme.textLight)),
      ]);
}

// ── Empty states ──────────────────────────────────────────────────────────────

class _EmptyDay extends StatelessWidget {
  final String  day;
  final bool    isToday;
  final String? message;

  const _EmptyDay(
      {required this.day, required this.isToday, this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
    child: Container(
      padding:
      const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(20),
          boxShadow: context.colors.cardShadow),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: context.colors.primary.withValues(alpha: 0.07),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isToday
                ? Icons.wb_sunny_outlined
                : Icons.calendar_today_outlined,
            size: 34,
            color: context.colors.primary.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          message ??
              (isToday
                  ? '${'no-lessons-today'.tr} 🎉'
                  : '${'no-lessons'.tr}$day'),
          style: context.colors.body.copyWith(color: context.colors.textMedium),
          textAlign: TextAlign.center,
        ),
        if (isToday) ...[
          const SizedBox(height: 6),
           Text('rest-follow'.tr,
              style: context.colors.caption, textAlign: TextAlign.center),
        ],
      ]),
    ),
  );
}

class _LoadingState extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _LoadingState({required this.onRefresh});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
       CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(context.colors.primary)),
      const SizedBox(height: 16),
       Text('loading-schedule'.tr,
          style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 13,
              color: context.colors.textMedium)),
      const SizedBox(height: 20),
      GestureDetector(
        onTap: onRefresh,
        child: Text('retry'.tr,
            style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 13,
                color: context.colors.primary,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: context.colors.primary)),
      ),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  TeacherSchedulesScreen
// ══════════════════════════════════════════════════════════════════════════════

class TeacherSchedulesScreen extends StatefulWidget {
  final TeacherCourse course;
  const TeacherSchedulesScreen({super.key, required this.course});
  static void openAddScheduleScreenSheet(BuildContext context,) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<TeacherSchedulesProvider>(),
      child: const AddScheduleSheet(),
    ),
  );
  @override
  State<TeacherSchedulesScreen> createState() =>
      _TeacherSchedulesScreenState();
}

class _TeacherSchedulesScreenState extends State<TeacherSchedulesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        context
            .read<TeacherSchedulesProvider>()
            .fetchSchedules(widget.course));
  }



  @override
  Widget build(BuildContext context) {

    final provider = context.watch<TeacherSchedulesProvider>();
    return BasePage(
      useWebCard: true,
      child:
    SafeArea(child: Column(children: [
          ScreenAppBar(
            title: '${'appointment'.tr}$widget.course.title.tr',
            actions: [_AddBtn(onTap:()=> TeacherSchedulesScreen.openAddScheduleScreenSheet(context))],
          ),

          // Info banner
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: context.colors.primary.withValues(alpha: 0.15))),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child:  Icon(Icons.repeat_rounded,
                      color: context.colors.primary, size: 15),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'appointment-repeat'.tr,
                    style: context.colors.caption.copyWith(
                        color: context.colors.primary, height: 1.5),
                  ),
                ),
              ]),
            ),
          ),

          Expanded(
            child: provider.isLoading && provider.schedules.isEmpty
                ?  Center(
                child: CircularProgressIndicator(
                    valueColor:
                    AlwaysStoppedAnimation(context.colors.primary)))
                : provider.schedules.isEmpty
                ? _ManageEmptyState(onAdd: ()=>TeacherSchedulesScreen.openAddScheduleScreenSheet(context))
                : _ManageList(schedules: provider.schedules),
          ),
        ])),
    );
  }
}

class _ManageList extends StatelessWidget {
  final List<CourseSchedule> schedules;
  const _ManageList({required this.schedules});

  List<CourseSchedule> get _sorted => [...schedules]..sort((a, b) {
    final di =
    slotDayOrder(a.day).compareTo(slotDayOrder(b.day));
    if (di != 0) return di;
    return a.startTime.compareTo(b.startTime);
  });

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
    physics: const BouncingScrollPhysics(),
    itemCount: _sorted.length,
    separatorBuilder: (_, __) => const SizedBox(height: 10),
    itemBuilder: (ctx, i) => _ManageCard(schedule: _sorted[i]),
  );
}

class _ManageCard extends StatelessWidget {
  final CourseSchedule schedule;
  const _ManageCard({required this.schedule});

  @override
  Widget build(BuildContext context) => Container(
    padding:
    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.colors.cardShadow),
    child: Row(children: [
      // Day badge
      Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
            gradient: context.colors.primaryGradient,
            borderRadius: BorderRadius.circular(14)),
        child: Center(
          child: Text(
            slotDayShort(schedule.day),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFamily: 'bahji'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(slotDayLabel(schedule.day),
                  style: context.colors.h3.copyWith(fontSize: 15)),
              const SizedBox(height: 5),
              Row(children: [
                 Icon(Icons.access_time_filled_rounded,
                    size: 14, color: context.colors.primary),
                const SizedBox(width: 5),
                Text(
                    '${schedule.startTime}  —  ${schedule.endTime}',
                    style: context.colors.label.copyWith(
                        color: context.colors.textDark, fontSize: 13)),
              ]),
            ]),
      ),
      // Delete
      GestureDetector(
        onTap: () => _confirmDelete(context, schedule),
        child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: context.colors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: context.colors.danger.withValues(alpha: 0.2))),
            child:  Icon(Icons.delete_outline_rounded,
                color: context.colors.danger, size: 18)),
      ),
    ]),
  );

  Future<void> _confirmDelete(
      BuildContext ctx, CourseSchedule s) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (BuildContext context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title:  Text('appointment-delete'.tr,
                style: TextStyle(
                    fontFamily: 'bahji',
                    fontWeight: FontWeight.w700)),
            content: Text(
                '${'appointment-delete'.tr}$slotDayLabel(s.day)$s.startTime؟',

                style: const TextStyle(fontFamily: 'bahji')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child:  Text('cancel'.tr,
                      style: TextStyle(
                          fontFamily: 'bahji',
                          color: context.colors.textMedium))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.danger,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () => Navigator.pop(ctx, true),
                child:  Text('delete'.tr,
                    style: TextStyle(
                        fontFamily: 'bahji',
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          )),
    );
    if (ok == true && ctx.mounted) {
      ctx.read<TeacherSchedulesProvider>().removeSchedule(s.id);
    }
  }
}

class _ManageEmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _ManageEmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) =>
      Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
                gradient: context.colors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: context.colors.primaryShadow),
            child: const Icon(Icons.calendar_month_rounded,
                color: Colors.white, size: 44)),
        const SizedBox(height: 20),
         Text('no-appointment'.tr, style: context.colors.h3),
        const SizedBox(height: 6),
         Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'add-weekly-appointment-for-student'.tr,
            style: context.colors.caption,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
                gradient: context.colors.primaryGradient,
                borderRadius: BorderRadius.circular(26),
                boxShadow: context.colors.primaryShadow),
            child:  Text('add-weekly-appointment'.tr,
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'bahji',
                    fontSize: 14)),
          ),
        ),
      ]));
}

// ── Add Schedule Sheet ────────────────────────────────────────────────────────

class AddScheduleSheet extends StatefulWidget {
  const AddScheduleSheet({super.key});
  @override
  State<AddScheduleSheet> createState() => _AddScheduleSheetState();
}

class _AddScheduleSheetState extends State<AddScheduleSheet> {
  static const _days = [
    ('monday',    'الاثنين'),
    ('tuesday',   'الثلاثاء'),
    ('wednesday', 'الأربعاء'),
    ('thursday',  'الخميس'),
    ('friday',    'الجمعة'),
    ('saturday',  'السبت'),
    ('sunday',    'الأحد'),
  ];
  String    _day   = 'monday';
  TimeOfDay _start = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _end   = const TimeOfDay(hour: 12, minute: 0);

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _valid =>
      _end.hour * 60 + _end.minute > _start.hour * 60 + _start.minute;

  Future<void> _pick(bool isStart) async {
    final p = await showTimePicker(
        context: context, initialTime: isStart ? _start : _end);
    if (p == null || !mounted) return;
    if(mounted) setState(() => isStart ? _start = p : _end = p);
  }

  Future<void> _submit() async {
    if (!_valid) return;
    final existing =
        context.read<TeacherSchedulesProvider>().schedules;
    final conflict = existing.any((s) => s.day == _day);
    if (conflict) {
      final ok = await showDialog<bool>(
          context: context,
          builder: (_) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title:  Text('duplicate-schedule'.tr,
                    style: TextStyle(
                        fontFamily: 'bahji',
                        fontWeight: FontWeight.w700)),
                content:  Text(
                    'same-day-schedule-exists'.tr,
                    style: TextStyle(fontFamily: 'bahji')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child:  Text('cancel'.tr,
                          style: TextStyle(
                              fontFamily: 'bahji',
                              color: context.colors.textMedium))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    onPressed: () => Navigator.pop(context, true),
                    child:  Text('add'.tr,
                        style: TextStyle(
                            fontFamily: 'bahji',
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              )));
      if (ok != true || !mounted) return;
    }

    final r = await context
        .read<TeacherSchedulesProvider>()
        .addSchedule(
        day: _day,
        startTime: _fmt(_start),
        endTime: _fmt(_end));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            r != null ? 'appointment-added-successfully'.tr : 'something-went-wrong'.tr,
            style: const TextStyle(
                fontFamily: 'bahji', color: Colors.white)),
        backgroundColor:
        r != null ? context.colors.success : context.colors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading =
        context.watch<TeacherSchedulesProvider>().isLoading;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32),
        decoration:  BoxDecoration(
            color: context.colors.cardBg,
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: context.colors.divider,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 18),
             Text('add-weekly-appointment'.tr, style: context.colors.h2),
            const SizedBox(height: 20),

            // Day chips
            Text('today'.tr,
                style: context.colors.label.copyWith(
                    color: context.colors.textDark,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final (v, l) = _days[i];
                  final sel = _day == v;
                  return GestureDetector(
                    onTap: () { if(mounted) setState(() => _day = v);},
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        gradient:
                        sel ? context.colors.primaryGradient : null,
                        color:
                        sel ? null : context.colors.background,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: sel
                                ? Colors.transparent
                                : context.colors.divider),
                        boxShadow:
                        sel ? context.colors.primaryShadow : null,
                      ),
                      child: Text(l,
                          style: context.colors.label.copyWith(
                              color: sel
                                  ? Colors.white
                                  : context.colors.textMedium,
                              fontWeight: sel
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // Time pickers
            Row(children: [
              Expanded(
                  child: _TimePicker(
                      label: 'start-time'.tr,
                      time: _start,
                      onTap: () => _pick(true))),
              const SizedBox(width: 12),
              Expanded(
                  child: _TimePicker(
                      label: 'end-time'.tr,
                      time: _end,
                      onTap: () => _pick(false),
                      hasError: !_valid)),
            ]),
            if (!_valid) ...[
              const SizedBox(height: 6),
              Text('end-time-must-be-after-start-time'.tr,
                  style: context.colors.caption
                      .copyWith(color: context.colors.danger)),
            ],
            const SizedBox(height: 24),
            MyPrimaryButton(
                label: 'add-appointment'.tr,
                isLoading: loading,
                onPressed: _valid ? _submit : null),
          ],
        ),
      ),
    );
  }
}

class _TimePicker extends StatelessWidget {
  final String    label;
  final TimeOfDay time;
  final VoidCallback onTap;
  final bool      hasError;
  const _TimePicker(
      {required this.label,
        required this.time,
        required this.onTap,
        this.hasError = false});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: context.colors.label.copyWith(
                color: context.colors.textDark,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius:
                BorderRadius.circular(context.colors.radiusMedium),
                border: Border.all(
                    color: hasError
                        ? context.colors.danger
                        : context.colors.divider,
                    width: hasError ? 1.5 : 1)),
            child: Row(children: [
              Icon(Icons.access_time_rounded,
                  size: 18,
                  color:
                  hasError ? context.colors.danger : context.colors.primary),
              const SizedBox(width: 8),
              Text(
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: context.colors.h3.copyWith(fontSize: 18)),
            ]),
          ),
        ),
      ]);
}

class _AddBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _AddBtn({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
            gradient: context.colors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: context.colors.primaryShadow),
        child: const Icon(Icons.add_rounded,
            color: Colors.white, size: 22)),
  );
}