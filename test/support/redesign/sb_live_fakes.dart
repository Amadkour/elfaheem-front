// The student's live and attendance routes over FakeApi (S-B): the private room's hand and question (backend
// D-1950) and the student's own attendance record, with the CAST demo data (Faisal, أ. ماجد الشهري, الرياضيات).
import 'dart:convert';

import 'package:dio/dio.dart';

import '../fake_api.dart';

Map<String, dynamic> _body(RequestOptions o) {
  final d = o.data;
  if (d is Map) return Map<String, dynamic>.from(d);
  if (d is String && d.isNotEmpty) return Map<String, dynamic>.from(jsonDecode(d) as Map);
  return {};
}

/// The demo attendance of Faisal's maths course (`GET /sessions/41/course_attendance/me`): five past classes, one
/// late, one missed, and one still to come.
List<Map<String, dynamic>> demoMyCourseAttendance() {
  Map<String, dynamic> row(int id, String name, String at, bool present, [String? checkIn]) => {
        'session': {'id': id, 'name': name, 'scheduled_at': at, 'type': 'live', 'course_id': 41},
        'students': [
          {'student_id': 7, 'student_name': 'فيصل العنزي', 'is_attended': present, 'join_date': ?checkIn},
        ],
      };
  return [
    row(1, 'مدخل إلى الدوال', '2026-11-08T16:30:00', true, '2026-11-08T16:31:00'),
    row(2, 'المجال والمدى', '2026-11-12T16:30:00', false),
    row(3, 'تحويلات الدوال', '2026-11-15T16:30:00', true, '2026-11-15T16:52:00'),
    row(4, 'الدوال العكسية', '2026-11-19T16:30:00', true, '2026-11-19T16:30:00'),
    row(5, 'مراجعة الوحدة الأولى', '2026-11-22T16:30:00', true, '2026-11-22T16:32:00'),
    row(6, 'الدوال الأسية', '2099-12-01T16:30:00', false),
  ];
}

/// Routes for the private room of session 77: what was sent is kept for the asserts.
class LiveFakeStore {
  final hands = <bool>[];
  final questions = <String>[];

  Map<String, FakeHandler> get routes => {
        'POST /api/v1/live/session/77/hand': (o) {
          final raised = _body(o)['raised'] == true;
          hands.add(raised);
          return {'raised': raised};
        },
        'POST /api/v1/live/session/77/ask': (o) {
          questions.add('${_body(o)['text']}');
          return {'sent': true};
        },
        'GET /api/v1/sessions/41/course_attendance/me': (_) => demoMyCourseAttendance(),
      };
}
