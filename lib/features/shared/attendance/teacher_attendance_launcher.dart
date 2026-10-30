/// features/attendance/teacher_attendance_launcher.dart
///
/// Teacher button for the course/session profile header. Opens a bottom sheet listing the
/// course's lessons (number + name + date) — today's first, then the upcoming ones soonest first, then the past ones
/// newest first (N13 / L9); the first one (today's, else the next) is marked. Tapping one opens the attendance sheet
/// where the teacher chooses the classmate-signal count (default 0) and sees the live
/// present counter (default 0).
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';

import 'attendance_strings.dart';
import 'attendance_widgets.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

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
  const TeacherAttendanceLauncher({super.key, required this.sessions});

  /// In course order (1 … n). The list is shown inverted.
  final List<LauncherSession> sessions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors.primary;
    return GestureDetector(
      onTap: () => showSessionPickerSheet(context, sessions),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.qrcode_viewfinder, color: c, size: 17),
          const SizedBox(width: 6),
          Text(attT('att_launch_btn'),
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w700, fontFamily: AppFonts.family, fontSize: 12)),
        ]),
      ),
    );
  }
}

Future<void> showSessionPickerSheet(BuildContext context, List<LauncherSession> sessions) {
  final now = DateTime.now().toUtc();
  final inverted = launcherOrder(sessions, nowUtc: now); // today's, then upcoming soonest first, then past newest first
  final focusId = launcherFocusId(sessions, nowUtc: now); // on top, so the sheet opens on it
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: Theme.of(sheetCtx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              decoration: BoxDecoration(
                  color: context.colors.textLight.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
          Text(attT('att_launch_title'),
              style: TextStyle(fontFamily: AppFonts.family, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Expanded(
            child: inverted.isEmpty
                ? Center(
                    child: Text(attT('att_launch_empty'),
                        style: TextStyle(fontFamily: AppFonts.family, color: context.colors.textMedium)))
                : ListView.separated(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: inverted.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final s = inverted[i];
                      final cc = context.colors;
                      final c = cc.primary;
                      final isToday = launcherIsToday(s, nowUtc: now);
                      final focus = s.id == focusId;
                      final marked = isToday || focus;
                      final when = s.date == null ? null : AppTime.date(s.date!, pattern: 'EEE d MMM');
                      final tag = isToday ? attT('att_launch_today') : (focus ? attT('att_launch_next') : null);
                      return ListTile(
                        tileColor: marked ? c.withValues(alpha: 0.06) : null,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: marked ? c.withValues(alpha: 0.45) : cc.divider, width: focus ? 1.5 : 1)),
                        leading: CircleAvatar(
                          backgroundColor: c.withValues(alpha: 0.12),
                          child: Text('${s.number}',
                              style: TextStyle(fontFamily: AppFonts.family, color: c, fontWeight: FontWeight.w600)),
                        ),
                        title: Text(s.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w500, color: cc.textDark)),
                        subtitle: when == null && tag == null
                            ? null
                            : Text(
                                [?tag, ?when].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontFamily: AppFonts.family,
                                    fontSize: 12,
                                    fontWeight: marked ? FontWeight.w600 : FontWeight.w400,
                                    color: marked ? c : cc.textMedium),
                              ),
                        trailing: const Icon(CupertinoIcons.forward, size: 16),
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          showTeacherAttendanceSheet(context, s.id, title: s.name);
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    ),
  );
}
