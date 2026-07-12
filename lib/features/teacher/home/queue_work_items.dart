// ── Teacher Schedule Queue ────────────────────────────────────────────────────

import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_provider.dart';
import 'package:flutter_education_app/features/teacher/sessions/model/live_response_model.dart';
import 'package:provider/provider.dart';

import '../../../config/theme/app_theme.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/helpers.dart';
import '../sessions/live/prejoin.dart';
import '../sessions/sessions_provider.dart';
import '../sessions/sessions_screen.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Parses 'HH:MM' from [session] fields and combines with [session.scheduledDate]
/// to produce concrete UTC DateTimes for start and end.
({DateTime start, DateTime end}) _sessionDateTimes(ScheduleSession session) {
  final parts = session.startTime.split(':');
  final eParts = session.endTime.split(':');
  final base = session.scheduledDate??DateTime.now();

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
  late Timer _ticker;

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
        context.read<TeacherProvider>().init();
      }
    }

    setState(() {}); // rebuild all countdown displays
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sessions.isEmpty) return const _EmptyQueue();

    final now = DateTime.now().toUtc();

    final sorted = [...widget.sessions]
      ..sort((a, b) {
        if (a.isOngoing != b.isOngoing) return a.isOngoing ? -1 : 1;
        if (a.isToday != b.isToday) return a.isToday ? -1 : 1;
        final dc = a.scheduledDate!.compareTo(b.scheduledDate!);
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
          (e) => _DayGroup(dayLabel: e.key, sessions: e.value, now: now),
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
  final DateTime now;

  const _DayGroup({
    required this.dayLabel,
    required this.sessions,
    required this.now,
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
        ...sessions.map((s) => ScheduleSessionCard(session: s, now: now)),
      ],
    );
  }
}

// ── Session card ──────────────────────────────────────────────────────────────

class ScheduleSessionCard extends StatelessWidget {
  final ScheduleSession session;
  final DateTime now;
  final Color? background;
  const ScheduleSessionCard({
    super.key,
    required this.session,
    required this.now, this.background,
  });

  Color get _accent {
    if (session.isOngoing) return const Color(0xFFE24B4A);
    if (session.isToday) return const Color(0xFF378ADD);
    return const Color(0xFF1D9E75);
  }

  @override
  Widget build(BuildContext context) {
    final TeacherCourse course = TeacherCourse.dummy(session.courseId);
    final (:start, :end) = _sessionDateTimes(session);
    final untilStart = start.difference(now);
    final untilEnd = end.difference(now);

    // Recompute live flags locally so they stay accurate between API refreshes
    final isOngoing = now.isAfter(start) && now.isBefore(end);
    final isUpcoming = !isOngoing && untilStart.inSeconds > 0;

    return ChangeNotifierProvider(
      create: (_) => TeacherCourseScreenProvider(initialCourse: course),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Container(
          decoration: BoxDecoration(
            color: background??context.colors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOngoing
                  ? _accent.withValues(alpha: 0.5)
                  : context.colors.divider,
              width: isOngoing ? 1.2 : 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: isOngoing ? 0.12 : 0.05),
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
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChangeNotifierProvider(
                        create: (_) =>
                            TeacherCourseScreenProvider(initialCourse: course),
                        child: TeacherSessionsScreen(expandDetails: true),
                      ),
                    ),
                  );
                },
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
                              _TimeBlock(session: session, accent: _accent),
                              const SizedBox(width: 10),
                              //_CourseImage(session: session),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _CourseInfo(
                                  session: session,
                                  accent: _accent,
                                  isOngoing: isOngoing,
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
                          accent: _accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Countdown / progress row ──────────────────────────────────────
              if (isOngoing || (session.isToday && isUpcoming))
                _CountdownBar(
                  accent: _accent,
                  isOngoing: isOngoing,
                  untilStart: untilStart,
                  untilEnd: untilEnd,
                  totalMinutes: session.durationMinutes??-1,
                ),
            ],
          ),
        ),
      ),
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
    if (session.canJoinNow) {
      _openPreJoin(context);
    } else {
      Helpers.showAddSessionSheet(
        context,
        TeacherCourse.dummy(session.courseId),
        openLive: true,
      );
      // _openCreationSheet(context);
    }
  }

  void _openPreJoin(BuildContext context) {
    final teacher = context.read<TeacherProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreJoinPage(
          args: JoinArgs(
            sessionId: session.sessionId!,
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
            onEnd: () => teacher.endLiveSession(session.sessionId!),
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

  const _TimeBlock({required this.session, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
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
  final bool isOngoing;

  const _CourseInfo({
    required this.session,
    required this.accent,
    required this.isOngoing,
  });

  @override
  Widget build(BuildContext context) {
    final dur = session.durationMinutes! > 0
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
            if (isOngoing) ...[const SizedBox(width: 5), _LiveDot()],
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
        Divider(),
        _StatusBadge(session: session, accent: accent, isOngoing: isOngoing),
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

class _CreateSessionSheet extends StatefulWidget {
  final ScheduleSession session;

  const _CreateSessionSheet({required this.session});

  @override
  State<_CreateSessionSheet> createState() => _CreateSessionSheetState();
}

class _CreateSessionSheetState extends State<_CreateSessionSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _durCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.session.defaultSessionName);
    _descCtrl = TextEditingController();
    _durCtrl = TextEditingController(
      text: widget.session.durationMinutes! > 0
          ? '${widget.session.durationMinutes}'
          : '60',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _durCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (mounted) setState(() => _submitting = true);
    final duration =
        int.tryParse(_durCtrl.text.trim()) ?? widget.session.durationMinutes;
    final sessionId = await context.read<TeacherProvider>().createSession(
      courseId: widget.session.courseId,
      name: _nameCtrl.text.trim(),
      durationMinutes: duration!,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
    );
    if (context.mounted) {
      context.read<TeacherCourseScreenProvider>().startLive(sessionId);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: context.colors.primaryGradient,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.videocam_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('إنشاء حصة وبدء البث', style: context.colors.h2),
                      Text(
                        widget.session.courseName,
                        style: context.colors.caption.copyWith(
                          color: context.colors.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.colors.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    color: context.colors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.session.dayLabel}  '
                    '${widget.session.startTime} — ${widget.session.endTime}',
                    style: context.colors.label.copyWith(
                      color: context.colors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _nameCtrl,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontFamily: 'bahji', fontSize: 14),
              validator: (v) => (v?.isEmpty ?? true) ? 'أدخل اسم الحصة' : null,
              decoration: InputDecoration(
                labelText: 'اسم الحصة',
                labelStyle: context.colors.caption,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _durCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontFamily: 'bahji', fontSize: 14),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return (n == null || n <= 0) ? 'أدخل مدة صحيحة' : null;
              },
              decoration: InputDecoration(
                labelText: 'المدة (بالدقائق)',
                labelStyle: context.colors.caption,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _submitting ? null : _submit,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: context.colors.primaryGradient,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.primary.withValues(alpha: 0.38),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'إنشاء الحصة وبدء البث 🚀',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            fontFamily: 'bahji',
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: Text(
                'إلغاء',
                style: context.colors.label.copyWith(
                  color: context.colors.textMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
