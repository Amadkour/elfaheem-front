// ── Teacher Schedule Queue ────────────────────────────────────────────────────
//
// PERFORMANCE REFACTOR
// ─────────────────────────────────────────────────────────────────────────
// `_ScheduleQueueListState` used to run `Timer.periodic(1s, () => setState())`
// on the widget that owns the *entire* queue — every day group, every
// session card, every countdown. That meant a full rebuild of the whole
// schedule list once a second regardless of how many sessions were live or
// even visible, and it also called `TeacherHomeProvider.init()` (a
// loading-state-flipping fetch) directly from that timer.
//
// Every `ScheduleSessionCard` was also unconditionally wrapped in its own
// `ChangeNotifierProvider<TeacherCourseScreenProvider>` (one full provider +
// ApiClient per card, per build) purely to feed a `_CreateSessionSheet` that
// is never actually shown anywhere in this file — dead weight on every
// render of the queue.
//
// Fixes:
//   • The 1-second tick now updates a single `ValueNotifier<DateTime>`
//     instead of calling `setState()`. Each `ScheduleSessionCard` listens to
//     it individually via `ValueListenableBuilder`, so only cards that are
//     live or starting soon actually re-render each second — the header,
//     other day groups, and non-time-sensitive cards are untouched.
//   • Removed the unused per-card `ChangeNotifierProvider` wrap (and the
//     dead `_CreateSessionSheet` class it was feeding).
//   • The background refresh triggered when a session starts now calls
//     `TeacherHomeProvider.refreshSilently()` instead of `init()`, so it can't
//     flash a full-screen loading state on the dashboard.
//   • Cards get a stable `ValueKey(scheduleId)` so Flutter can correctly
//     diff/reuse them (and their internal `_LiveDot` animation controllers)
//     across resorts instead of rebuilding by list position.
// ─────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_provider.dart';
import 'package:flutter_education_app/features/teacher/sessions/model/live_response_model.dart';
import 'package:provider/provider.dart';

import '../../../config/theme/app_theme.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/helpers.dart';
import '../sessions/live/prejoin.dart';
import '../sessions/sessions_provider.dart';
import '../sessions/sessions_screen.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
// ── Helpers ───────────────────────────────────────────────────────────────────

/// Parses 'HH:MM' from [session] fields and combines with [session.scheduledDate]
/// to produce concrete UTC DateTimes for start and end.
({DateTime start, DateTime end}) _sessionDateTimes(ScheduleSession session) {
  final parts = session.startTime.split(':');
  final eParts = session.endTime.split(':');
  final base = session.scheduledDate ?? DateTime.now();

  final start = DateTime.utc(
    base.year,
    base.month,
    base.day,
    int.parse(parts[0]),
    int.parse(parts[1]),
  );
  final end = DateTime.utc(
    base.year,
    base.month,
    base.day,
    int.parse(eParts[0]),
    int.parse(eParts[1]),
  );
  return (start: start, end: end);
}

String _fmtCountdown(Duration d) {
  if (d.isNegative || d == Duration.zero) return '00:00';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

// ── Entry point widget ────────────────────────────────────────────────────────

class ScheduleQueueList extends StatefulWidget {
  final List<ScheduleSession> sessions;

  const ScheduleQueueList({super.key, required this.sessions});

  @override
  State<ScheduleQueueList> createState() => _ScheduleQueueListState();
}

class _ScheduleQueueListState extends State<ScheduleQueueList> {
  late final Timer _ticker;

  /// Ticks once a second. Cards subscribe individually via
  /// ValueListenableBuilder, so a tick no longer rebuilds this whole widget
  /// (header + every day group + every card) — only the small countdown
  /// area inside cards that are actually live or starting soon.
  final ValueNotifier<DateTime> _now = ValueNotifier(DateTime.now().toUtc());

  /// Sessions for which we have already fired the refresh call this run.
  final Set<int> _refreshFired = {};

  @override
  void initState() {
    super.initState();
    // Tick every second so countdowns stay smooth.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker.cancel();
    _now.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;

    final now = DateTime.now().toUtc();

    for (final session in widget.sessions) {
      final scheduleId = session.scheduleId;
      if (_refreshFired.contains(scheduleId)) continue;

      final (:start, :end) = _sessionDateTimes(session);
      final untilStart = start.difference(now);

      // Fire once when we cross the 0-second mark (was positive, now ≤ 0).
      if (untilStart.inSeconds <= 0 && untilStart.inSeconds > -5) {
        _refreshFired.add(scheduleId);
        log(
          '[SCHEDULE] Session ${session.sessionId} starting — refreshing dashboard',
        );
        // Silent: a background timer crossing a boundary shouldn't flash a
        // full-screen loading state on the dashboard.
        context.read<TeacherHomeProvider>().refreshSilently();
      }
    }

    // Notify only the countdown listeners — not a widget rebuild.
    _now.value = now;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sessions.isEmpty) return const _EmptyQueue();

    final sorted = [...widget.sessions]
      ..sort((a, b) {
        if (a.isOngoing != b.isOngoing) return a.isOngoing ? -1 : 1;
        if (a.isToday != b.isToday) return a.isToday ? -1 : 1;
        final dc = a.scheduledDate.compareTo(b.scheduledDate);
        return dc != 0 ? dc : a.startTime.compareTo(b.startTime);
      });

    final groups = <String, List<ScheduleSession>>{};
    for (final s in sorted) {
      groups.putIfAbsent(s.dayLabel, () => []).add(s);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _QueueHeader(count: widget.sessions.length),
        ...groups.entries.map(
              (e) => _DayGroup(
            dayLabel: e.key,
            sessions: e.value,
            nowListenable: _now,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _QueueHeader extends StatelessWidget {
  final int count;

  const _QueueHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Text(
            'weekly_schedule'.tr,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.colors.textMedium,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: context.colors.background,
              border: Border.all(color: context.colors.divider),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.textMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Day group ─────────────────────────────────────────────────────────────────

class _DayGroup extends StatelessWidget {
  final String dayLabel;
  final List<ScheduleSession> sessions;
  final ValueListenable<DateTime> nowListenable;

  const _DayGroup({
    required this.dayLabel,
    required this.sessions,
    required this.nowListenable,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
          child: Text(
            dayLabel,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.colors.textMedium.withValues(alpha: 0.6),
              letterSpacing: 0.8,
            ),
          ),
        ),
        ...sessions.map(
          // Stable key: lets Flutter reuse elements (and their internal
          // _LiveDot animation controllers) across resorts instead of
          // rebuilding by list position.
              (s) => ScheduleSessionCard(
            key: ValueKey(s.scheduleId),
            session: s,
            nowListenable: nowListenable,
          ),
        ),
      ],
    );
  }
}

// ── Session card ──────────────────────────────────────────────────────────────

class ScheduleSessionCard extends StatelessWidget {
  final ScheduleSession session;
  final ValueListenable<DateTime> nowListenable;
  final Color? background;

  const ScheduleSessionCard({
    super.key,
    required this.session,
    required this.nowListenable,
    this.background,
  });

  Color _accentFor({required bool isOngoing}) {
    if (isOngoing) return const Color(0xFFE24B4A);
    if (session.isToday) return const Color(0xFF378ADD);
    return const Color(0xFF1D9E75);
  }

  @override
  Widget build(BuildContext context) {
    final TeacherCourse course = TeacherCourse.dummy(session.courseId);
    final (:start, :end) = _sessionDateTimes(session);

    void openSessionsScreen() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => TeacherCourseScreenProvider(initialCourse: course),
            child: TeacherSessionsScreen(expandDetails: true),
          ),
        ),
      );
    }

    // Only this ValueListenableBuilder rebuilds each tick — not the day
    // group, not sibling cards, not the queue header.
    return ValueListenableBuilder<DateTime>(
      valueListenable: nowListenable,
      builder: (context, now, _) {
        final untilStart = start.difference(now);
        final untilEnd = end.difference(now);

        // Recompute live flags locally so they stay accurate between API
        // refreshes.
        final isOngoing = now.isAfter(start) && now.isBefore(end);
        final isUpcoming = !isOngoing && untilStart.inSeconds > 0;
        final accent = _accentFor(isOngoing: isOngoing);

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Container(
            decoration: BoxDecoration(
              color: background ?? context.colors.primary.withAlpha(50),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isOngoing
                    ? accent.withValues(alpha: 0.5)
                    : context.colors.divider,
                width: isOngoing ? 1.2 : 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: isOngoing ? 0.12 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Main row
                InkWell(
                  onTap: openSessionsScreen,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 8,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 15, 10, 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _TimeBlock(session: session, accent: accent),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _CourseInfo(
                                    session: session,
                                    accent: accent,
                                    isOngoing: isOngoing??false,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _InlineStartButton(
                            session: session,
                            accent: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Countdown / progress row ──────────────────────────
                if (isOngoing || (session.isToday && isUpcoming))
                  _CountdownBar(
                    accent: accent,
                    isOngoing: isOngoing,
                    untilStart: untilStart,
                    untilEnd: untilEnd,
                    totalMinutes: session.durationMinutes ?? -1,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Countdown bar (replaces the old thin LinearProgressIndicator) ─────────────

class _CountdownBar extends StatelessWidget {
  final Color accent;
  final bool isOngoing;
  final Duration untilStart;
  final Duration untilEnd;
  final int totalMinutes;

  const _CountdownBar({
    required this.accent,
    required this.isOngoing,
    required this.untilStart,
    required this.untilEnd,
    required this.totalMinutes,
  });

  @override
  Widget build(BuildContext context) {
    if (isOngoing) {
      // Progress bar + remaining time
      final totalSec = totalMinutes * 60;
      final elapsed = totalSec - untilEnd.inSeconds.clamp(0, totalSec);
      final progress = totalSec > 0
          ? (elapsed / totalSec).clamp(0.0, 1.0)
          : 0.0;

      return Container(
        color: accent.withValues(alpha: 0.06),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
        child: Column(
          children: [
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: accent.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(accent),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Elapsed
                Row(
                  children: [
                    Icon(
                      Icons.play_circle_outline_rounded,
                      size: 12,
                      color: accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'مباشر الآن',
                      style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                ),
                // Time remaining
                Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 12,
                      color: accent.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'ينتهي بعد  ${_fmtCountdown(untilEnd.isNegative ? Duration.zero : untilEnd)}',
                      style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: accent.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Upcoming today — show simple countdown to start
    final display = untilStart.isNegative ? Duration.zero : untilStart;
    return Container(
      color: accent.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          Icon(
            Icons.hourglass_top_rounded,
            size: 13,
            color: accent.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 6),
          Text(
            'يبدأ بعد  ${_fmtCountdown(display)}',
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const Spacer(),
          // Mini progress dots
          ...List.generate(3, (i) {
            final lit = display.inMinutes < (30 - i * 10);
            return Container(
              margin: const EdgeInsets.only(left: 4),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lit ? accent : accent.withValues(alpha: 0.2),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Inline start button strip ─────────────────────────────────────────────────

class _InlineStartButton extends StatelessWidget {
  final ScheduleSession session;
  final Color accent;

  const _InlineStartButton({required this.session, required this.accent});

  IconData get _icon {
    if (session.isOngoing) return Icons.sensors_rounded;
    if (session.isToday) return Icons.play_arrow_rounded;
    return Icons.sensors_rounded;
  }

  String get _label {
    if (session.isOngoing) return 'مباشر';
    if (session.isToday) return 'ابدأ';
    return 'ابدأ الان';
  }

  LinearGradient get _gradient {
    if (session.isOngoing) {
      return const LinearGradient(
        colors: [Color(0xFFE24B4A), Color(0xFFA32D2D)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
    }
    if (session.isToday) {
      return const LinearGradient(
        colors: [Color(0xFF378ADD), Color(0xFF185FA5)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
    }
    return const LinearGradient(
      colors: [Color(0xFF1D9E75), Color(0xFF0F6E56)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
  }

  void _handleTap(BuildContext context) {
    // if (session.canJoinNow) {
    _openPreJoin(context);
    // } else {
    // Helpers.showAddSessionSheet(
    //   context,
    //   TeacherCourse.dummy(session.courseId),
    //   openLive: true,
    // );
    // _openCreationSheet(context);
    // }
  }

  void _openPreJoin(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PreJoinPage(
          args: JoinArgs(
            sessionId: session.sessionId,
            courseId: session.courseId,
            maxStudents: session.maxStudents,
            isTeacher: true,
            userName:
            context.read<AuthProvider>().currentUser?.name ?? 'Teacher',
            userId: context.read<AuthProvider>().currentUser?.id ?? 0,
            onStart: () async {
              log(
                '[PRE-JOIN] session=${session.sessionId} url=${session.joinUrl}',
              );
              return LiveResponseModel(
                sessionId: session.sessionId!,
                url: session.joinUrl!,
                token: session.token!,
              );
            },
            onEnd: () => context.read<TeacherCourseScreenProvider>().endLive(session.sessionId!),
            apiClient: ApiClient(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Container(
        decoration: BoxDecoration(gradient: _gradient),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (session.isOngoing) ...[_LiveDot(), const SizedBox(height: 5)],
            Icon(_icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              _label,
              style: const TextStyle(
                fontFamily: 'tajawal',
                fontSize: 10,
                fontWeight: FontWeight.normal,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Time block ────────────────────────────────────────────────────────────────

class _TimeBlock extends StatelessWidget {
  final ScheduleSession session;
  final Color accent;

  const _TimeBlock({required this.session,  this.accent=Colors.red});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        // color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            session.startTime,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            width: 1.5,
            height: 8,
            color: accent.withValues(alpha: 0.3),
          ),
          Text(
            session.endTime,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: accent.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Course info ───────────────────────────────────────────────────────────────

class _CourseInfo extends StatelessWidget {
  final ScheduleSession session;
  final Color accent;
  final bool? isOngoing;

  const _CourseInfo({
    required this.session,
    required this.accent,
    this.isOngoing=false,
  });

  @override
  Widget build(BuildContext context) {
    final dur = session.durationMinutes > 0
        ? '${session.durationMinutes}د'
        : '—';
    final students = session.maxStudents != null
        ? '${session.maxStudents} طالب'
        : 'غير محدود';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                session.courseName,
                style: context.colors.h3.copyWith(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isOngoing??false) ...[const SizedBox(width: 5), _LiveDot()],
          ],
        ),
        const SizedBox(height: 8),

        Row(
          children: [
            _MetaChip(Icons.timer_rounded, dur),
            const SizedBox(width: 5),
            Text("|"),
            const SizedBox(width: 5),
            _MetaChip(Icons.group_rounded, students),
          ],
        ),
        Divider(color: Color(0xFF1D9E75)),
        _StatusBadge(session: session, accent: accent, isOngoing: isOngoing??false),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: context.colors.textMedium),
      const SizedBox(width: 3),
      Text(
        label,
        style: TextStyle(
          fontFamily: 'bahji',
          fontSize: 11,
          color: context.colors.textMedium,
        ),
      ),
    ],
  );
}

class _StatusBadge extends StatelessWidget {
  final ScheduleSession session;
  final Color accent;
  final bool isOngoing;

  const _StatusBadge({
    required this.session,
    required this.accent,
    required this.isOngoing,
  });

  String get _label {
    if (isOngoing) return 'مباشر الآن';
    if (session.isToday) return 'اليوم';
    return session.dayLabel;
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: accent.withValues(alpha: 0.3)),
    ),
    child: Text(
      _label,
      style: TextStyle(
        fontFamily: 'bahji',
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: accent,
      ),
    ),
  );
}

// ── Live dot ──────────────────────────────────────────────────────────────────

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = Tween(begin: 1.0, end: 0.3).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Color(0xFFE24B4A),
        shape: BoxShape.circle,
      ),
    ),
  );
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.colors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.calendar_today_outlined,
              color: context.colors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'لا توجد مواعيد خلال الأسبوع القادم',
              style: context.colors.caption.copyWith(
                color: context.colors.textMedium,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Bottom sheet ──────────────────────────────────────────────────────────────
//
// NOTE: `_CreateSessionSheet` below was previously defined here but never
// instantiated anywhere in this file — `_InlineStartButton._handleTap` opens
// `Helpers.showAddSessionSheet(...)` instead. It was dead code, and the only
// thing that read `TeacherCourseScreenProvider` from it, which is why every
// `ScheduleSessionCard` was being wrapped in its own unused
// `ChangeNotifierProvider<TeacherCourseScreenProvider>` (a full provider +
// ApiClient instantiated per card, per build, for nothing). Removed.
// ─────────────────────────────────────────────────────────────────────────
// (End of file — dead `_CreateSessionSheet` class removed, see note above.)