// lib/features/courses/course_profile/course_attendance_flag.dart
//
// Attendance on/off (D-1110): the course's switch and each session's. Turning the course on turns every session on;
// turning it off turns every session off EXCEPT the ones that already have attendance (they stay on, so the records
// already kept still count). A session's own switch lives in its ⋮ menu; the server refuses to turn off a session
// that already has attendance (409 attendance_already_taken). Hidden by the kill switch `course.attendance_flag`.
//
// `CourseAttendanceFlagView` is the plain-values body (what the layout harness tests); the sheet loads the summary,
// confirms with what will happen, writes, and calls `onChanged` so the page reloads.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_page_api.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_page_models.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_screen.dart' show cpErrorMessage;

/// The kill switch that hides both switches.
const kCourseAttendanceFlagKey = 'course.attendance_flag';

bool get courseAttendanceFlagAvailable => !AppConfig.disableList.contains(kCourseAttendanceFlagKey);

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

String _sessions(int n) => countText(n,
    ar1: 'جلسة واحدة', ar2: 'جلستين', arFew: '{n} جلسات', arMany: '{n} جلسة', en1: '1 session', en: '{n} sessions');

/// What turning the course switch to [turnOn] will do, for the confirm.
String courseAttendanceConfirmText(CourseAttendanceFlag s, {required bool turnOn}) {
  if (turnOn) {
    if (s.wouldTurnOn == 0) return _t('الحضور مُفعّل بالفعل في كل الجلسات.', 'Attendance is already on in every session.');
    return _t('سيُشغَّل الحضور في ${_sessions(s.wouldTurnOn)}، فتصبح كل جلسات الكورس تأخذ الحضور.',
        'Attendance will be turned on for ${_sessions(s.wouldTurnOn)}, so every session of the course takes it.');
  }
  final off = s.wouldTurnOff == 0
      ? _t('لن تتغير أي جلسة الآن.', 'No session changes now.')
      : _t('سيُوقف الحضور في ${_sessions(s.wouldTurnOff)}.', 'Attendance will be turned off for ${_sessions(s.wouldTurnOff)}.');
  final kept = s.wouldKeepTaken == 0
      ? ''
      : ' ${_t('وتبقى ${_sessions(s.wouldKeepTaken)} سُجّل فيها حضور بالفعل كما هي.', '${_sessions(s.wouldKeepTaken)} that already have attendance stay on.')}';
  return '$off$kept ${_t('الجلسات المتوقفة لا تُحسب في الحضور ولا الغياب.', "Sessions that are off don't count in attendance or absences.")}';
}

/// The notice after a course change.
String courseAttendanceDoneText(CourseAttendanceFlagResult r) => r.enabled
    ? (r.turnedOn == 0
        ? _t('الحضور مُفعّل في كل الجلسات', 'Attendance is on in every session')
        : _t('شُغّل الحضور في ${_sessions(r.turnedOn)}', 'Attendance turned on for ${_sessions(r.turnedOn)}'))
    : (r.keptTaken == 0
        ? _t('أُوقف الحضور في ${_sessions(r.turnedOff)}', 'Attendance turned off for ${_sessions(r.turnedOff)}')
        : _t('أُوقف الحضور في ${_sessions(r.turnedOff)}، وبقيت ${_sessions(r.keptTaken)} سُجّل فيها حضور',
            'Attendance turned off for ${_sessions(r.turnedOff)}; ${_sessions(r.keptTaken)} with attendance stay on'));

/// The plain-values body: the switch, one line of where things stand, and what the switch does.
class CourseAttendanceFlagView extends StatelessWidget {
  const CourseAttendanceFlagView({super.key, required this.summary, required this.onChanged, this.busy = false});

  final CourseAttendanceFlag summary;
  final ValueChanged<bool>? onChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = summary;
    final status = s.sessions == 0
        ? _t('لا جلسات بعد؛ الجلسات الجديدة تأخذ هذا الإعداد', 'No sessions yet; new sessions take this setting')
        : _t('يأخذ الحضور في ${s.on} من ${_sessions(s.sessions)}${s.taken > 0 ? ' · ${_sessions(s.taken)} فيها حضور' : ''}',
            'Takes attendance in ${s.on} of ${_sessions(s.sessions)}${s.taken > 0 ? ' · ${_sessions(s.taken)} with attendance' : ''}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSwitchTile(
          key: const ValueKey('course_attendance_flag.switch'),
          icon: Icons.how_to_reg_rounded,
          title: _t('أخذ الحضور في هذا الكورس', 'Take attendance in this course'),
          subtitle: status,
          value: s.enabled,
          onChanged: busy ? null : onChanged,
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          _t('الإيقاف يوقف الحضور في كل جلسة لم يُسجَّل فيها حضور بعد، والجلسات التي سُجّل فيها حضور تبقى كما هي. '
                  'التشغيل يشغّله في كل الجلسات. وتستطيع تغيير جلسة واحدة من قائمة ⋮ بجانبها.',
              'Off stops attendance in every session that has none yet; sessions that already have attendance stay on. '
                  'On turns it on in every session. You can still change one session from the ⋮ next to it.'),
          style: AppType.meta(context).copyWith(color: c.textLight),
        ),
      ],
    );
  }
}

Future<void> showCourseAttendanceFlagSheet(BuildContext context, {required int courseId, VoidCallback? onChanged}) =>
    showAppSheet<void>(context, (_) => _FlagSheet(api: CoursePageApi(courseId), onChanged: onChanged));

class _FlagSheet extends StatefulWidget {
  const _FlagSheet({required this.api, this.onChanged});

  final CoursePageApi api;
  final VoidCallback? onChanged;

  @override
  State<_FlagSheet> createState() => _FlagSheetState();
}

class _FlagSheetState extends State<_FlagSheet> {
  CourseAttendanceFlag? _s;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.attendanceFlag();
      if (mounted) {
        setState(() {
          _s = s;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = cpErrorMessage(e));
    }
  }

  Future<void> _change(bool on) async {
    final s = _s;
    if (s == null) return;
    final ok = await appConfirm(
      context,
      message: courseAttendanceConfirmText(s, turnOn: on),
      danger: !on,
      confirmLabel: on ? _t('تشغيل الحضور', 'Turn attendance on') : _t('إيقاف الحضور', 'Turn attendance off'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await widget.api.setAttendanceFlag(on);
      showAppNotice(courseAttendanceDoneText(r));
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      showAppNotice(cpErrorMessage(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return AppSheetContent(
      title: _t('الحضور في الكورس', 'Course attendance'),
      icon: Icons.how_to_reg_rounded,
      children: [
        if (_error != null)
          AppEmpty(icon: Icons.error_outline_rounded, title: _error!, actionLabel: _t('إعادة المحاولة', 'Retry'), onAction: _load)
        else if (s == null)
          const AppListSkeleton(items: 2)
        else
          CourseAttendanceFlagView(summary: s, busy: _busy, onChanged: _change),
      ],
    );
  }
}

/// One session's switch, from its ⋮ menu. Turning it off asks first. True when the server took the change.
Future<bool> setSessionAttendanceFlag(BuildContext context, {required int courseId, required int sessionId, required bool enabled}) async {
  if (!enabled) {
    final ok = await appConfirm(
      context,
      message: _t('إيقاف الحضور في هذه الجلسة؟ لن يُؤخذ فيها حضور ولن تُحسب في نسب الحضور ولا الغياب.',
          "Turn off attendance for this session? No attendance is taken in it and it won't count in attendance or absences."),
      confirmLabel: _t('إيقاف الحضور', 'Turn attendance off'),
    );
    if (!ok) return false;
  }
  try {
    await CoursePageApi(courseId).setSessionAttendance(sessionId, enabled);
    showAppNotice(enabled
        ? _t('شُغّل الحضور في هذه الجلسة', 'Attendance is on for this session')
        : _t('أُوقف الحضور في هذه الجلسة', 'Attendance is off for this session'));
    return true;
  } catch (e) {
    showAppNotice(cpErrorMessage(e), error: true);
    return false;
  }
}
