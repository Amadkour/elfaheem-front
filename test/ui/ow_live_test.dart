// Owner decisions 2026-11-27: the attendance QR payload, the check-in sheet's two extra ways in (scan, a classmate's
// help) at every layout size, a classmate's hidden quote in the announcements, and the class the Add materials page
// opens on.

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/attendance/student_ui/student_checkin_view.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show TeacherSessionItem;
import 'package:flutter_education_app/features/home/teacher/add_class_materials_page.dart' show pickDefaultSession;
import 'package:flutter_education_app/features/messaging/chat/chat_bubble.dart' show chatReplyPreview;
import 'package:flutter_education_app/features/messaging/chat/chat_models.dart' show ChatReplyRef;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _sheet(StudentCheckInPhase phase) => SingleChildScrollView(
      child: StudentCheckInView(
        phase: phase,
        code: TextEditingController(),
        onSubmit: () {},
        onRetry: () {},
        onClose: () {},
        onScan: () {},
        onViaClassmate: () {},
        error: 'No internet',
      ),
    );

TeacherSessionItem _session(int id, DateTime at) => TeacherSessionItem.fromJson({
      'id': id,
      'course_id': 1,
      'name': 'S$id',
      'scheduled_at': at.toIso8601String(),
      'created_at': at.toIso8601String(),
    });

void main() {
  test('attendance QR: the bare 6 digits or a link with ?code=, nothing else', () {
    expect(parseAttendanceQr('123456'), '123456');
    expect(parseAttendanceQr(' 654321 '), '654321');
    expect(parseAttendanceQr('https://nextbrain.site/app/att?code=111222'), '111222');
    expect(parseAttendanceQr('12345'), isNull);
    expect(parseAttendanceQr('ABCD-2345'), isNull);
    expect(parseAttendanceQr(null), isNull);
  });

  testWidgets('check-in sheet: code with scan + classmate, and the classmate on a failure', (t) async {
    await expectNoLayoutErrors(t, () => _sheet(StudentCheckInPhase.code), act: (t) async {
      expect(find.byKey(const ValueKey('att.scan_qr')), findsOneWidget);
      expect(find.byKey(const ValueKey('att.via_classmate')), findsOneWidget);
    });
    await expectNoLayoutErrors(t, () => _sheet(StudentCheckInPhase.failed), act: (t) async {
      expect(find.byKey(const ValueKey('att.via_classmate')), findsOneWidget);
    });
  });

  test('a hidden quote names nobody', () {
    final r = ChatReplyRef.fromJson({'id': 3, 'body': null, 'sender_id': null, 'sender_name': null, 'hidden': true})!;
    expect(r.hidden, isTrue);
    expect(r.senderName, isNull);
    expect(chatReplyPreview(r), 'ow_chat_hidden_quote'); // no translations loaded: the key
  });

  test('Add materials opens on the asked class, else the latest started one', () {
    final now = DateTime(2026, 11, 27, 12);
    final all = [
      _session(1, now.subtract(const Duration(days: 7))),
      _session(2, now.subtract(const Duration(hours: 2))),
      _session(3, now.add(const Duration(days: 1))),
    ];
    expect(pickDefaultSession(all, sessionId: 3, now: now)?.id, 3);
    expect(pickDefaultSession(all, now: now)?.id, 2);
    expect(pickDefaultSession(const [], now: now), isNull);
  });
}
