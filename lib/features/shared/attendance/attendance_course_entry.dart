/// features/attendance/attendance_course_entry.dart
///
/// ONE attendance entry per COURSE (replaces the per-lesson buttons):
///   [AttendanceCourseEntry]        student — premium bar for the course profile
///   [TeacherAttendanceCourseEntry] teacher — premium card for the teacher course profile
///
/// Student: glows green and pulses while an attendance is open for the course; shows the
/// Bluetooth icon when the phone is offline ("check in via classmate"). On the WEB it only
/// appears when the teacher allowed web attendance for the open session.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';

import 'attendance_models.dart';
import 'attendance_offline_sync.dart';
import 'attendance_store.dart';
import 'attendance_strings.dart';
import 'attendance_widgets.dart';
import 'teacher_attendance_controller.dart';
import 'teacher_attendance_launcher.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Shared premium surface (gradient + shimmer + optional pulse)
// ════════════════════════════════════════════════════════════════════════════

class _PremiumSurface extends StatefulWidget {
  const _PremiumSurface({
    required this.onTap,
    required this.from,
    required this.to,
    required this.child,
    this.live = false,
    this.height = 48,
  });

  final VoidCallback onTap;
  final Color from;
  final Color to;
  final Widget child;
  final bool live;
  final double height;

  @override
  State<_PremiumSurface> createState() => _PremiumSurfaceState();
}

class _PremiumSurfaceState extends State<_PremiumSurface> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  bool _pressed = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations; // respect "reduce motion"
    if (still && _c.isAnimating) _c.stop();
    if (!still && !_c.isAnimating) _c.repeat();

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 110),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final pulse = widget.live && !still ? (0.5 - 0.5 * math.cos(_c.value * 2 * math.pi)) : 0.0;
            return Container(
              height: widget.height,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: [widget.from, widget.to],
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.to.withValues(alpha: 0.30 + 0.22 * pulse),
                    blurRadius: 14 + 10 * pulse,
                    spreadRadius: 1.5 * pulse,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(children: [
                  if (!still)
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment(-1.8 + 3.6 * _c.value, 0),
                        child: Transform.rotate(
                          angle: 0.35,
                          child: Container(width: 22, height: widget.height * 2, color: Colors.white.withValues(alpha: 0.18)),
                        ),
                      ),
                    ),
                  child!,
                ]),
              ),
            );
          },
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: widget.child),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Student
// ════════════════════════════════════════════════════════════════════════════

class AttendanceCourseEntry extends StatefulWidget {
  const AttendanceCourseEntry({super.key, required this.courseId, this.title});
  final int courseId;
  final String? title;

  @override
  State<AttendanceCourseEntry> createState() => _AttendanceCourseEntryState();
}

class _AttendanceCourseEntryState extends State<AttendanceCourseEntry> {
  OpenWindow? _window;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    AppConnectivity.instance.online.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    AppConnectivity.instance.online.removeListener(_refresh);
    super.dispose();
  }

  /// Online: ask the server and STORE the answer. Offline: use what was stored before.
  Future<void> _refresh() async {
    OpenWindow? w;
    if (AppConnectivity.instance.isOnline) {
      w = await AttendanceOfflineSync.instance.warm(courseId: widget.courseId);
    } else {
      w = await AttendanceStore.instance.windowForCourse(widget.courseId);
    }
    if (!mounted) return;
    setState(() {
      _window = w;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = _window;
    // WEB: only when the teacher explicitly allowed it for the open session.
    if (kIsWeb && !(w?.allowWeb ?? false)) return const SizedBox.shrink();
    final open = w != null;
    final c = context.colors;

    return ValueListenableBuilder<bool>(
      valueListenable: AppConnectivity.instance.online,
      builder: (_, online, _) => _PremiumSurface(
        live: open,
        from: open ? c.success : c.primary,
        to: open ? c.success.withValues(alpha: 0.78) : c.primary.withValues(alpha: 0.72),
        onTap: () async {
          await showStudentCheckInSheet(context, courseId: widget.courseId, title: widget.title);
          if (mounted) _refresh();
        },
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(online ? Icons.how_to_reg_rounded : Icons.bluetooth_searching_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                !online
                    ? attT('att_btn_checkin_offline')
                    : (open ? attT('att_btn_checkin_now') : attT('att_btn_checkin')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'tajawal', fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              if (_checked)
                Text(
                  open ? attT('att_entry_open') : attT('att_entry_closed'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'tajawal', fontSize: 10.5, color: Colors.white.withValues(alpha: 0.85)),
                ),
            ]),
          ),
          if (open)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(8)),
              child: Text(attT('att_btn_live'),
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.6)),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Teacher
// ════════════════════════════════════════════════════════════════════════════

/// Teacher course profile: one card. While an attendance is running it shows the live code and
/// counter and reopens the sheet; otherwise it opens the lesson picker (newest first).
class TeacherAttendanceCourseEntry extends StatelessWidget {
  const TeacherAttendanceCourseEntry({super.key, required this.sessions});

  /// Course order 1…n (the picker shows them inverted).
  final List<LauncherSession> sessions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: TeacherAttendanceController.instance,
      builder: (_, _) {
        final t = TeacherAttendanceController.instance;
        final running = t.isOpen;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: _PremiumSurface(
            height: 60,
            live: running,
            from: running ? c.success : c.primary,
            to: running ? c.success.withValues(alpha: 0.78) : c.purple,
            onTap: () {
              if (running) {
                showTeacherAttendanceSheet(context, t.sessionId!);
              } else {
                showSessionPickerSheet(context, sessions);
              }
            },
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: Icon(running ? Icons.sensors_rounded : Icons.qr_code_2_rounded, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(running ? attT('att_t_running') : attT('att_launch_btn'),
                      style: const TextStyle(
                          fontFamily: 'tajawal', fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white)),
                  Text(
                    running
                        ? '${attT('att_t_present')}: ${t.code?.presentCount ?? 0}'
                        : attT('att_t_entry_sub'),
                    style: TextStyle(fontFamily: 'tajawal', fontSize: 11, color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ]),
              ),
              if (running)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(10)),
                  child: Text(t.code?.code ?? '------',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 24),
            ]),
          ),
        );
      },
    );
  }
}
