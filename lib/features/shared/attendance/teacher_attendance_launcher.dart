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

import 'attendance_strings.dart';
import 'attendance_widgets.dart';
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
  const TeacherAttendanceLauncher({super.key, required this.sessions});

  /// In course order (1 … n). The list is shown inverted.
  final List<LauncherSession> sessions;

  @override
  Widget build(BuildContext context) => AppButton.tonal(
        size: AppButtonSize.sm,
        icon: CupertinoIcons.qrcode_viewfinder,
        label: attT('att_launch_btn'),
        onPressed: () => showSessionPickerSheet(context, sessions),
      );
}

Future<void> showSessionPickerSheet(BuildContext context, List<LauncherSession> sessions) {
  final now = DateTime.now().toUtc();
  final inverted = launcherOrder(sessions, nowUtc: now); // today's, then upcoming soonest first, then past newest first
  final focusId = launcherFocusId(sessions, nowUtc: now); // on top, so the sheet opens on it
  return showAppModalSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      builder: (_, scroll) => Column(children: [
          AppSheetHeader(attT('att_launch_title')),
          Expanded(
            child: inverted.isEmpty
                ? AppEmpty(icon: CupertinoIcons.calendar, title: attT('att_launch_empty'))
                : ListView.separated(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
                    itemCount: inverted.length,
                    separatorBuilder: (_, _) => AppSpace.gapXs,
                    itemBuilder: (_, i) {
                      final s = inverted[i];
                      final isToday = launcherIsToday(s, nowUtc: now);
                      final focus = s.id == focusId;
                      final when = s.date == null ? null : AppTime.date(s.date!, pattern: 'EEE d MMM');
                      final tag = isToday ? attT('att_launch_today') : (focus ? attT('att_launch_next') : null);
                      return _LessonRow(
                        number: s.number,
                        name: s.name,
                        tag: tag,
                        when: when,
                        marked: isToday || focus,
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
  );
}


/// One lesson in the picker: the number in a quiet well, the name, the tag + date. The lesson the teacher most likely
/// wants (today's, else the next) sits on the sky schedule tone; the rest are paper on a hairline.
class _LessonRow extends StatelessWidget {
  const _LessonRow({
    required this.number,
    required this.name,
    required this.marked,
    required this.onTap,
    this.tag,
    this.when,
  });

  final int number;
  final String name;
  final String? tag;
  final String? when;
  final bool marked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = marked ? c.blockSky : c.cardBg;
    final b = AppBlockColors.of(context, marked ? AppBlockTone.sky : AppBlockTone.paper);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: marked ? BorderSide.none : BorderSide(color: c.divider, width: AppBorder.hairline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.primary),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.sm),
            child: Row(children: [
              Container(
                width: AppTouch.min - AppSpace.xs,
                height: AppTouch.min - AppSpace.xs,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: marked ? c.cardBg : c.inputBg, shape: BoxShape.circle),
                child: Text('$number', style: AppType.figure(context).copyWith(color: c.textDark)),
              ),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: b.ink)),
                  if (tag != null || when != null)
                    Text(
                      [?tag, ?when].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta(context).copyWith(
                          color: marked ? b.accentInk(c.primary) : b.muted,
                          fontWeight: marked ? FontWeight.w600 : FontWeight.w400),
                    ),
                ]),
              ),
              AppSpace.gapXs,
              Icon(CupertinoIcons.forward, size: AppIconSize.sm, color: b.muted),
            ]),
          ),
        ),
      ),
    );
  }
}
