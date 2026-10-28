/// features/attendance/teacher_attendance_launcher.dart
///
/// Teacher button for the course/session profile header. Opens a bottom sheet listing the
/// course's lessons (number + name) NEWEST FIRST (n … 1); tapping one opens the attendance sheet
/// where the teacher chooses the classmate-signal count (default 0) and sees the live
/// present counter (default 0).
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'attendance_strings.dart';
import 'attendance_widgets.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

/// Plain data so this file does not depend on the teacher model classes.
class LauncherSession {
  const LauncherSession({required this.id, required this.number, required this.name});
  final int id;
  final int number; // 1-based position in the course
  final String name;
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
  final inverted = sessions.reversed.toList(); // newest first: n, n-1, … 1
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
              style: TextStyle(fontFamily: AppFonts.family, fontSize: 17, fontWeight: FontWeight.w800)),
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
                      final c = Theme.of(sheetCtx).colorScheme.primary;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: c.withValues(alpha: 0.18))),
                        leading: CircleAvatar(
                          backgroundColor: c.withValues(alpha: 0.12),
                          child: Text('${s.number}',
                              style: TextStyle(color: c, fontWeight: FontWeight.w800)),
                        ),
                        title: Text(s.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
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
