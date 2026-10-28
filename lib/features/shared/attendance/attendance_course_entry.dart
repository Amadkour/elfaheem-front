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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';

import 'attendance_models.dart';
import 'attendance_live_screen.dart';
import 'attendance_offline_sync.dart';
import 'attendance_push.dart';
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
                          child: Container(width: 22, height: widget.height * 2, color: context.colors.onHero.withValues(alpha: 0.18)),
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
    AttendancePush.instance.events.addListener(_onPush);
    _refresh();
  }

  @override
  void dispose() {
    AppConnectivity.instance.online.removeListener(_refresh);
    AttendancePush.instance.events.removeListener(_onPush);
    _expiry?.cancel();
    super.dispose();
  }

  Timer? _expiry;

  /// The teacher opened / closed attendance: react at once (no waiting for a refresh).
  void _onPush() {
    final e = AttendancePush.instance.events.value;
    if (e == null || (e.courseId != null && e.courseId != widget.courseId)) return;
    if (e.closed && mounted) setState(() => _window = null); // hide immediately
    _refresh(force: true);
  }

  /// Online: ask the server and STORE the answer. Offline: use what was stored before.
  Future<void> _refresh({bool force = false}) async {
    OpenWindow? w;
    if (AppConnectivity.instance.isOnline) {
      w = await AttendanceOfflineSync.instance.warm(courseId: widget.courseId, force: force);
    } else {
      w = await AttendanceStore.instance.windowForCourse(widget.courseId);
    }
    if (!mounted) return;
    setState(() {
      _window = (w == null || w.isOver) ? null : w;
      _checked = true;
    });
    // Hide by itself when the window runs out.
    _expiry?.cancel();
    final end = _window == null ? null : DateTime.tryParse('${_window!.expiresAt}Z');
    if (end != null) {
      final left = end.difference(DateTime.now().toUtc());
      if (!left.isNegative) {
        _expiry = Timer(left + const Duration(seconds: 1), () {
          if (mounted) setState(() => _window = null);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _window;
    // WEB: only when the teacher explicitly allowed it for the open session.
    if (kIsWeb && !(w?.allowWeb ?? false)) return const SizedBox.shrink();
    // Shown ONLY while an attendance is open for this course.
    if (!_checked || w == null || w.isOver) return const SizedBox.shrink();
    final c = context.colors;

    return ValueListenableBuilder<bool>(
      valueListenable: AppConnectivity.instance.online,
      builder: (_, online, _) => _PremiumSurface(
        live: true,
        from: c.success,
        to: c.success.withValues(alpha: 0.78),
        onTap: () async {
          await showStudentCheckInSheet(context, courseId: widget.courseId, title: widget.title);
          if (mounted) _refresh();
        },
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: context.colors.onHero.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(online ? Icons.how_to_reg_rounded : Icons.bluetooth_searching_rounded,
                color: context.colors.onHero, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                !online
                    ? attT('att_btn_checkin_offline')
                    : attT('att_btn_checkin_now'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'tajawal', fontSize: 14, fontWeight: FontWeight.w800, color: context.colors.onHero),
              ),
              if (_checked)
                Text(
                  attT('att_entry_open'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'tajawal', fontSize: 10.5, color: context.colors.onHero.withValues(alpha: 0.85)),
                ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: context.colors.onHero.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(8)),
            child: Text(attT('att_btn_live'),
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: context.colors.onHero, letterSpacing: 0.6)),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: context.colors.onHero, size: 22),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Teacher
// ════════════════════════════════════════════════════════════════════════════

/// Teacher course profile: one card. While an attendance is running it shows the live code and
/// counter and reopens the sheet; otherwise it opens [target] directly (the lesson happening now),
/// or the lesson picker (newest first) when there is none.
class TeacherAttendanceCourseEntry extends StatelessWidget {
  const TeacherAttendanceCourseEntry({super.key, required this.sessions, this.target,
      this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 8)});

  /// Course order 1…n (the picker shows them inverted).
  final List<LauncherSession> sessions;

  /// The lesson one tap opens (server-picked: live now / nearest today). Null → the picker.
  final LauncherSession? target;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: TeacherAttendanceController.instance,
      builder: (_, _) {
        final t = TeacherAttendanceController.instance;
        final running = t.isOpen;
        return Padding(
          padding: padding,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // The web app is waiting for the classroom location from this phone.
            if (t.webLocationRequested && !kIsWeb) ...[
              const _WebLocationRequestCard(),
              const SizedBox(height: 8),
            ],
            _PremiumSurface(
            height: 60,
            live: running,
            from: running ? c.success : c.primary,
            to: running ? c.success.withValues(alpha: 0.78) : c.purple,
            onTap: () {
              if (running) {
                openAttendanceLive(context);
              } else if (target != null) {
                showTeacherAttendanceSheet(context, target!.id, title: target!.name);
              } else {
                showSessionPickerSheet(context, sessions);
              }
            },
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: context.colors.onHero.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: Icon(running ? Icons.sensors_rounded : Icons.qr_code_2_rounded, color: context.colors.onHero, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(running ? attT('att_t_running') : attT('att_launch_btn'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'tajawal', fontSize: 14.5, fontWeight: FontWeight.w800, color: context.colors.onHero)),
                  Text(
                    running
                        ? '${attT('att_t_present')}: ${t.code?.presentCount ?? 0}'
                        : (target?.name ?? attT('att_t_entry_sub')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'tajawal', fontSize: 11, color: context.colors.onHero.withValues(alpha: 0.85)),
                  ),
                ]),
              ),
              if (running)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: context.colors.onHero.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(10)),
                  child: Text(t.code?.code ?? '------',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900, color: context.colors.onHero, letterSpacing: 2)),
                ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: context.colors.onHero, size: 24),
            ]),
          ),
          ]),
        );
      },
    );
  }
}

/// Shown on the teacher's MOBILE course profile while a web session asks for the location.
class _WebLocationRequestCard extends StatefulWidget {
  const _WebLocationRequestCard();
  @override
  State<_WebLocationRequestCard> createState() => _WebLocationRequestCardState();
}

class _WebLocationRequestCardState extends State<_WebLocationRequestCard> {
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    final t = TeacherAttendanceController.instance;
    final ok = await t.shareLocationForWeb();
    if (ok) t.markWebRequest(false);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [context.colors.warning, context.colors.heroEnd(context.colors.warning)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: context.colors.warning.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Row(children: [
          Icon(Icons.location_searching_rounded, color: context.colors.onHero),
          const SizedBox(width: 10),
          Expanded(
            child: Text(attT('att_t_web_asks_body'),
                style: TextStyle(fontFamily: 'tajawal', color: context.colors.onHero, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.onHero, foregroundColor: context.colors.heroEnd(context.colors.warning)),
            onPressed: _busy ? null : _share,
            child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(attT('att_t_share_now'), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}
