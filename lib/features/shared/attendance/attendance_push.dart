/// features/attendance/attendance_push.dart
///
/// Reacts to the SILENT pushes the backend sends for attendance (nothing is shown by the OS):
///   attendance_opened            → students: the course button appears at once
///   attendance_closed            → students: the course button disappears at once
///   attendance_location_request  → teacher's MOBILE: a web session needs the classroom location;
///                                  the phone shares it automatically (alert only if that fails)
///
/// notification_service.dart forwards these in its foreground handler; main.dart calls [bind].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_notice.dart';

import 'attendance_store.dart';
import 'attendance_strings.dart';
import 'teacher_attendance_controller.dart';

class AttendanceEvent {
  AttendanceEvent(this.type, this.courseId) : stamp = DateTime.now().microsecondsSinceEpoch;
  final String type; // attendance_opened | attendance_closed
  final int? courseId;
  final int stamp; // makes every event distinct for ValueNotifier

  bool get closed => type == 'attendance_closed';
}

class AttendancePush {
  AttendancePush._();
  static final AttendancePush instance = AttendancePush._();

  GlobalKey<NavigatorState>? _nav;
  void bind(GlobalKey<NavigatorState> navigatorKey) => _nav = navigatorKey;

  /// Student course buttons listen to this and refresh (or hide) themselves.
  final ValueNotifier<AttendanceEvent?> events = ValueNotifier<AttendanceEvent?>(null);

  Future<void> handle(Map<String, dynamic> data) async {
    switch (data['type']) {
      case 'attendance_opened':
      case 'attendance_closed':
        final course = int.tryParse('${data['course_id']}');
        if (data['type'] == 'attendance_closed' && course != null) {
          await AttendanceStore.instance.removeCourseWindows(course);
        }
        events.value = AttendanceEvent(data['type'] as String, course);
      case 'attendance_location_request':
        await _shareForWeb();
    }
  }

  Future<void> _shareForWeb() async {
    if (kIsWeb) return; // only a phone can answer
    final t = TeacherAttendanceController.instance..markWebRequest(true);
    final ok = await t.shareLocationForWeb();
    final ctx = _nav?.currentState?.overlay?.context;
    if (ok) {
      t.markWebRequest(false);
      if (ctx != null && ctx.mounted) {
        showAppNotice(attT('att_t_shared_auto'));
      }
      return;
    }
    // Could not read the position by itself (permission / GPS off): ask the teacher.
    if (ctx == null || !ctx.mounted) return;
    await showDialog<void>(
      context: ctx,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.location_searching_rounded),
        title: Text(attT('att_t_web_asks_title'), style: const TextStyle(fontFamily: 'tajawal')),
        content: Text(attT('att_t_web_asks_body'), style: const TextStyle(fontFamily: 'tajawal')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(attT('att_later'))),
          FilledButton(
            onPressed: () async {
              Navigator.pop(d);
              if (await t.shareLocationForWeb()) t.markWebRequest(false);
            },
            child: Text(attT('att_t_share_now')),
          ),
        ],
      ),
    );
  }
}
