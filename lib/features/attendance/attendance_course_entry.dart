/// features/attendance/attendance_course_entry.dart
///
/// ONE attendance entry per COURSE (replaces the per-lesson buttons):
///   [AttendanceCourseEntry]        student — an emerald block on the course profile
///   [TeacherAttendanceCourseEntry] teacher — a block on the teacher course profile
///
/// Student: an emerald block with a breathing live dot while an attendance is open for the course (offline too: the
/// way through a classmate is never named to the student, O-6). On the WEB it only
/// appears when the teacher allowed web attendance for the open session.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';

import 'package:flutter_education_app/features/attendance/attendance_models.dart';
import 'package:flutter_education_app/features/attendance/attendance_live_screen.dart';
import 'package:flutter_education_app/features/attendance/attendance_offline_sync.dart';
import 'package:flutter_education_app/features/attendance/attendance_push.dart';
import 'package:flutter_education_app/features/attendance/attendance_store.dart';
import 'package:flutter_education_app/features/attendance/attendance_strings.dart';
import 'package:flutter_education_app/features/attendance/attendance_widgets.dart';
import 'package:flutter_education_app/features/attendance/teacher_attendance_controller.dart';
import 'package:flutter_education_app/features/attendance/teacher_attendance_launcher.dart';
import 'package:flutter_education_app/features/attendance/attendance_ui.dart';
import 'package:flutter_education_app/features/attendance/student_ui/student_checkin_view.dart' show showStudentAttendCheckIn;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;

// ════════════════════════════════════════════════════════════════════════════
//  Shared entry surface (Warm Editorial: a tinted block, no gradient, no shine)
// ════════════════════════════════════════════════════════════════════════════

/// The course profile's attendance entry: a whole block that is a button. Emerald while attendance is open (the one
/// moment that matters: "you can check in now"), paper otherwise. It presses in; the live dot carries the motion.
class _EntrySurface extends StatelessWidget {
  const _EntrySurface({required this.onTap, required this.live, required this.child});

  final VoidCallback onTap;
  final bool live;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppPressScale(
        child: AppBlock(
          tone: live ? AppBlockTone.emerald : AppBlockTone.paper,
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.sm, AppSpace.sm),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: child,
        ),
      );
}

/// Title + one quiet line, both in the block's ink; they flex and ellipsize.
class _EntryText extends StatelessWidget {
  const _EntryText({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: b.ink)),
      if (subtitle != null)
        Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
    ]);
  }
}

/// The "live" tag: the breathing dot and the word, in the block's accent ink.
class _LiveTag extends StatelessWidget {
  const _LiveTag();

  @override
  Widget build(BuildContext context) {
    final ink = AppBlock.colorsOf(context).accentInk(context.colors.success);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AttLiveDot(color: ink),
      Text(attT('att_btn_live'), maxLines: 1, style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
    ]);
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
      builder: (_, online, _) => _EntrySurface(
        live: true,
        onTap: () async {
          await showStudentAttendCheckIn(context, courseId: widget.courseId, title: widget.title);
          if (mounted) _refresh();
        },
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Row(children: [
            // O-6 (redesign S-B): the offline path through a classmate stays, but the student never sees it named
            AttIconWell(icon: Icons.how_to_reg_rounded, color: c.primary, fill: true),
            AppSpace.gapSm,
            Expanded(
              child: _EntryText(
                title: attT('att_btn_checkin_now'),
                subtitle: _checked ? attT('att_entry_open') : null,
              ),
            ),
            AppSpace.gapXs,
            const _LiveTag(),
            Icon(Icons.chevron_right_rounded, color: b.muted, size: AppIconSize.lg),
          ]);
        }),
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
      this.padding = const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xs)});

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
              AppSpace.gapXs,
            ],
            _EntrySurface(
            live: running,
            onTap: () {
              if (running) {
                openAttendanceLive(context);
              } else if (target != null) {
                showTeacherAttendanceSheet(context, target!.id, title: target!.name);
              } else {
                showSessionPickerSheet(context, sessions);
              }
            },
            child: Builder(builder: (context) {
              final b = AppBlock.colorsOf(context);
              return Row(children: [
                AttIconWell(icon: running ? Icons.sensors_rounded : Icons.qr_code_2_rounded, color: c.primary, fill: running),
                AppSpace.gapSm,
                Expanded(
                  child: _EntryText(
                    title: running ? attT('att_t_running') : attT('att_launch_btn'),
                    subtitle: running
                        ? '${attT('att_t_present')}: ${t.code?.presentCount ?? 0}'
                        : (target?.name ?? attT('att_t_entry_sub')),
                  ),
                ),
                if (running) ...[
                  AppSpace.gapXs,
                  // the running code reads left to right in both languages
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
                      decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.chipAll),
                      child: Text(t.code?.code ?? '------',
                          style: AppType.figure(context).copyWith(color: c.textDark, letterSpacing: AppSpace.xxs / 2)),
                    ),
                  ),
                ],
                Icon(Icons.chevron_right_rounded, color: b.muted, size: AppIconSize.lg),
              ]);
            }),
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
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = appTintOn(context, c.warning);
    final ink = appInkOn(context, c.warning, tint);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.xs, AppSpace.xs),
      decoration: BoxDecoration(color: tint, borderRadius: AppRadius.cardAll),
      child: Row(children: [
        Icon(Icons.location_searching_rounded, color: ink, size: AppIconSize.md),
        AppSpace.gapSm,
        Expanded(
          child: Text(attT('att_t_web_asks_body'),
              style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
        ),
        AppSpace.gapXs,
        AppButton.primary(size: AppButtonSize.sm, busy: _busy, label: attT('att_t_share_now'), onPressed: _busy ? null : _share),
      ]),
    );
  }
}
