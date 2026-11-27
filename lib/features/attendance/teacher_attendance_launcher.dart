/// features/attendance/teacher_attendance_launcher.dart
///
/// Teacher button for the course/session profile header. Opens the "Take attendance" sheet (attendance_take_panel.dart):
/// the course's lessons — today's first, then the upcoming ones soonest first, then the past ones newest first
/// (N13 / L9), the first one (today's, else the next) already chosen — and the way to take it. Start opens the
/// attendance sheet (code or QR) where the teacher chooses the classmate-signal count and sees the live present
/// counter, or the manual register.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:flutter_education_app/features/attendance/attendance_strings.dart';
import 'package:flutter_education_app/features/attendance/analysis/teacher/teacher_attendance_screen.dart' show TeacherAttendanceScreen;
import 'package:flutter_education_app/features/attendance/attendance_take_panel.dart';
import 'package:flutter_education_app/features/attendance/attendance_ui.dart' show AttView;
import 'package:flutter_education_app/features/attendance/attendance_widgets.dart';
import 'package:flutter_education_app/design/app_kit.dart';

/// Plain data so this file does not depend on the teacher model classes.
class LauncherSession {
  const LauncherSession({required this.id, required this.number, required this.name, this.date});
  final int id;
  final int number; // 1-based position in the course
  final String name;

  /// When the lesson is scheduled (UTC), when known: shown under the name, and today's lesson goes first (L9).
  final DateTime? date;
}

/// The picker's order (N13 / L9): today's lessons first, then the upcoming ones soonest first, then the past ones
/// newest first, then the undated ones (n … 1). The lesson the teacher most likely wants is always on top.
List<LauncherSession> launcherOrder(List<LauncherSession> sessions, {DateTime? nowUtc}) {
  final now = nowUtc ?? DateTime.now().toUtc();
  bool today(LauncherSession s) => launcherIsToday(s, nowUtc: now);
  final todays = [for (final s in sessions) if (today(s)) s]..sort((a, b) => a.date!.compareTo(b.date!));
  final upcoming = [for (final s in sessions) if (s.date != null && !today(s) && s.date!.isAfter(now)) s]
    ..sort((a, b) => a.date!.compareTo(b.date!));
  final past = [for (final s in sessions) if (s.date != null && !today(s) && !s.date!.isAfter(now)) s]
    ..sort((a, b) => b.date!.compareTo(a.date!));
  final undated = [for (final s in sessions.reversed) if (s.date == null) s];
  return [...todays, ...upcoming, ...past, ...undated];
}

/// The lesson the picker marks (N13): today's first one, else the next upcoming one; null when neither exists.
int? launcherFocusId(List<LauncherSession> sessions, {DateTime? nowUtc}) {
  final now = nowUtc ?? DateTime.now().toUtc();
  final ordered = launcherOrder(sessions, nowUtc: now);
  if (ordered.isEmpty) return null;
  final first = ordered.first;
  final d = first.date;
  if (d == null) return null;
  return launcherIsToday(first, nowUtc: now) || d.isAfter(now) ? first.id : null;
}

/// Is [s] scheduled today (in the platform / organization zone)?
bool launcherIsToday(LauncherSession s, {DateTime? nowUtc}) {
  final d = s.date;
  if (d == null) return false;
  final now = AppTime.toZone(nowUtc ?? DateTime.now().toUtc());
  final w = AppTime.toZone(d);
  return w.year == now.year && w.month == now.month && w.day == now.day;
}

class TeacherAttendanceLauncher extends StatelessWidget {
  const TeacherAttendanceLauncher({super.key, required this.sessions, this.courseId, this.courseTitle});

  /// In course order (1 … n). The list is shown inverted.
  final List<LauncherSession> sessions;

  /// With the course, the picker also offers the manual register (its own page).
  final int? courseId;
  final String? courseTitle;

  @override
  Widget build(BuildContext context) => AppButton.tonal(
        size: AppButtonSize.sm,
        icon: CupertinoIcons.qrcode_viewfinder,
        label: attT('att_launch_btn'),
        onPressed: () => showSessionPickerSheet(context, sessions, courseId: courseId, courseTitle: courseTitle),
      );
}

/// The "Take attendance" sheet: pick the lesson and the way (code · QR · manual), then Start. [courseId] adds the
/// manual register to the ways (it opens [TeacherAttendanceScreen] on the chosen lesson).
Future<void> showSessionPickerSheet(BuildContext context, List<LauncherSession> sessions, {int? courseId, String? courseTitle}) {
  return showAppModalSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.lg),
        children: [
          AttendanceTakePanel(
            sessions: sessions,
            manualAvailable: courseId != null,
            onStart: (s, view) {
              Navigator.of(sheetCtx).pop();
              if (view == AttView.manual && courseId != null) {
                Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => TeacherAttendanceScreen(courseId: courseId, courseTitle: courseTitle ?? s.name, sessionId: s.id)));
                return;
              }
              showTeacherAttendanceSheet(context, s.id, title: s.name, view: view);
            },
          ),
        ],
      ),
    ),
  );
}
