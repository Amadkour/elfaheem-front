// The student's live and attendance screens (S-B): the prejoin page, the private room (normal + full screen), the
// attend page and the check-in sheet at every layout size; the privacy rule (no count, no classmate); Reduce motion
// parks the breathing avatar; the token's privacy flag, the hand / question routes and the student's own rows.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/attendance/analysis/teacher/attendance_model.dart' show FullAttendance;
import 'package:flutter_education_app/features/attendance/student_ui/student_attend_view.dart';
import 'package:flutter_education_app/features/attendance/student_ui/student_checkin_view.dart';
import 'package:flutter_education_app/features/live/live_room.dart' show LiveRoomRef;
import 'package:flutter_education_app/features/live/room/prejoin_layout.dart' show PreJoinIssue;
import 'package:flutter_education_app/features/live/room/prejoin_student.dart';
import 'package:flutter_education_app/features/live/room/student/student_live_api.dart';
import 'package:flutter_education_app/features/live/room/student/student_room_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../support/redesign/sb_live_fakes.dart';
import 'layout_harness.dart';

Widget _prejoin({bool busy = false, PreJoinIssue? issue}) => StudentPreJoinLayout(
      lessonTitle: 'الدوال الأسية',
      teacherName: 'أ. ماجد الشهري',
      userName: 'فيصل العنزي',
      classLine: 'الرياضيات، حصة مباشرة ٥٠ دقيقة',
      startedMinutes: 12,
      micOn: true,
      camOn: false,
      micLevel: 0.6,
      onToggleMic: () {},
      onToggleCam: () {},
      busy: busy,
      onJoin: () {},
      onBack: () {},
      issue: issue,
      onRetry: () {},
      mics: const [('a', 'Built-in microphone'), ('b', 'Headset')],
      cams: const [('c', 'Front camera'), ('d', 'USB camera')],
      onMicChanged: (_) {},
      onCamChanged: (_) {},
    );

Widget _room({bool full = false, bool allowed = false}) => StudentRoomView(
      lessonTitle: 'الدوال الأسية',
      teacherName: 'أ. ماجد الشهري',
      liveFor: '05:12',
      stage: const ColoredBox(color: Color(0xFF203040)),
      micOn: false,
      micAllowed: allowed,
      handUp: false,
      fullScreen: full,
      onToggleFullScreen: () {},
      onToggleMic: () {},
      onToggleHand: () {},
      onAsk: () {},
      onLeave: () {},
      onMinimize: () {},
    );

const _rows = [
  StudentAttendRow(lesson: 'مراجعة الوحدة الأولى', status: StudentAttendStatus.present),
  StudentAttendRow(lesson: 'الدوال العكسية', status: StudentAttendStatus.present),
  StudentAttendRow(lesson: 'تحويلات الدوال', status: StudentAttendStatus.late),
  StudentAttendRow(lesson: 'المجال والمدى', status: StudentAttendStatus.absent),
];

Widget _attend({bool open = true, List<StudentAttendRow> rows = _rows, bool loading = false, String? error}) =>
    StudentAttendView(
      kicker: 'الرياضيات، ثاني ثانوي',
      open: open
          ? const StudentAttendOpen(lesson: 'الدوال الأسية', teacherName: 'أ. ماجد', minutesLeft: 8)
          : null,
      onCheckIn: () {},
      rows: rows,
      loading: loading,
      error: error,
      onRetry: () {},
      onBack: () {},
    );

Widget _checkIn(StudentCheckInPhase phase) => SingleChildScrollView(
      child: StudentCheckInView(
        phase: phase,
        code: TextEditingController(),
        onSubmit: () {},
        onRetry: () {},
        onClose: () {},
        doneAt: '7:32 PM',
        error: 'The code is not right',
      ),
    );

void main() {
  group('layout', () {
    testWidgets('prejoin: student page, busy, with a device issue', (t) async {
      await expectNoLayoutErrors(t, _prejoin);
      await expectNoLayoutErrors(t, () => _prejoin(busy: true, issue: PreJoinIssue.permissionDenied));
    });

    testWidgets('private room: normal, mic allowed, full screen', (t) async {
      await expectNoLayoutErrors(t, _room);
      await expectNoLayoutErrors(t, () => _room(allowed: true));
      await expectNoLayoutErrors(t, () => _room(full: true));
    });

    testWidgets('attend: open, closed, loading, empty, error', (t) async {
      await expectNoLayoutErrors(t, _attend);
      await expectNoLayoutErrors(t, () => _attend(open: false));
      await expectNoLayoutErrors(t, () => _attend(rows: const [], loading: true));
      await expectNoLayoutErrors(t, () => _attend(rows: const []));
      await expectNoLayoutErrors(t, () => _attend(rows: const [], error: 'offline'));
    });

    testWidgets('check-in sheet: code, running, done, failed', (t) async {
      for (final p in StudentCheckInPhase.values) {
        await expectNoLayoutErrors(t, () => _checkIn(p));
      }
    });
  });

  group('privacy', () {
    testWidgets('the student room and prejoin show the teacher and "you", never a count or a classmate', (t) async {
      AppConfig.lang = 'ar';
      await t.pumpWidget(layoutHost(_room(), scale: 1));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('sb_live_you_and_teacher'.tr), findsOneWidget);
      expect(find.byIcon(Icons.people_rounded), findsNothing);
      expect(find.byIcon(Icons.groups_rounded), findsNothing);
      await t.pumpWidget(layoutHost(_prejoin(), scale: 1));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.people_rounded), findsNothing);
      // no bare number anywhere (a participant count is a bare number on a badge)
      final bare = t.widgetList<Text>(find.byType(Text)).map((w) => (w.data ?? '').trim()).where((s) => RegExp(r'^[0-9٠-٩]+$').hasMatch(s));
      expect(bare, isEmpty);
    });
  });

  group('motion', () {
    testWidgets('Reduce motion parks the breathing teacher avatar (the page settles)', (t) async {
      AppConfig.lang = 'ar';
      await t.pumpWidget(layoutHost(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StudentClassCard(lessonTitle: 'الدوال الأسية', teacherName: 'أ. ماجد الشهري', userName: 'فيصل', busy: false, onJoin: () {}),
        ),
        scale: 1,
      ));
      await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      expect(t.binding.hasScheduledFrame, isFalse);
    });
  });

  group('logic', () {
    test('the token marks a private learner; a guest and staff are not this mode', () {
      expect(liveTokenIsPrivate('{"privacy": "private"}'), isTrue);
      expect(liveTokenIsPrivate('{"privacy": "private", "role": "guest"}'), isFalse);
      expect(liveTokenIsPrivate('{"role": "teacher"}'), isFalse);
      expect(liveTokenIsPrivate(''), isFalse);
      expect(liveTokenIsPrivate('not json'), isFalse);
    });

    test('rows: own record only, newest first, late after ten minutes, future classes left out', () {
      final list = [for (final m in demoMyCourseAttendance()) FullAttendance.fromJson(m)];
      final rows = studentAttendRows(list, now: DateTime.utc(2026, 11, 25));
      expect(rows.map((r) => r.lesson).first, 'مراجعة الوحدة الأولى');
      expect(rows, hasLength(5));
      expect(rows.where((r) => r.status == StudentAttendStatus.late).single.lesson, 'تحويلات الدوال');
      expect(rows.where((r) => r.status == StudentAttendStatus.absent).single.lesson, 'المجال والمدى');
      expect(studentAttendPercent(rows), 80);
    });

    group('server routes', () {
      late LiveFakeStore store;
      late FakeApi fake;
      setUp(() {
        SharedPreferences.setMockInitialValues({});
        mockRequestPlugins();
        store = LiveFakeStore();
        fake = FakeApi(store.routes, latency: Duration.zero)..install();
      });
      tearDown(() => fake.uninstall());

      test('the hand and the question go to the server, not the data channel', () async {
        final api = StudentLiveApi(const LiveRoomRef.session(77));
        expect(await api.hand(true), isTrue);
        expect(await api.ask('  ليش ٢ أس صفر يساوي ١؟ '), isTrue);
        expect(await api.ask('   '), isFalse);
        expect(store.hands, [true]);
        expect(store.questions, ['ليش ٢ أس صفر يساوي ١؟']);
        expect(fake.unmatched, isEmpty);
      });
    });

    group('guest routes', () {
      final sent = <String, Map<String, dynamic>>{};
      late FakeApi fake;
      setUp(() {
        SharedPreferences.setMockInitialValues({});
        mockRequestPlugins();
        sent.clear();
        Map<String, dynamic> body(RequestOptions o) =>
            o.data is Map ? Map<String, dynamic>.from(o.data as Map) : Map<String, dynamic>.from(jsonDecode('${o.data}') as Map);
        fake = FakeApi({
          'POST /api/v1/public/live/hand': (o) {
            sent['hand'] = body(o);
            return {'raised': body(o)['raised'] == true};
          },
          'POST /api/v1/public/live/ask': (o) {
            sent['ask'] = body(o);
            return {'sent': true};
          },
        }, latency: Duration.zero)
          ..install();
      });
      tearDown(() => fake.uninstall());

      test("a guest's hand and question go to the PUBLIC routes with his LiveKit token", () async {
        final api = GuestStudentLiveApi(const LiveRoomRef.meeting(9), token: () => 'lk-guest-token-123');
        expect(await api.hand(true), isTrue);
        expect(await api.ask(' متى نبدأ؟ '), isTrue);
        expect(sent['hand'], {'token': 'lk-guest-token-123', 'raised': true});
        expect(sent['ask'], {'token': 'lk-guest-token-123', 'text': 'متى نبدأ؟'});
        expect(fake.unmatched, isEmpty);
      });
    });
  });

  group('guest room', () {
    test('every guest gets the private room; staff and hosts the full one', () {
      expect(liveRoomIsPrivate(isTeacher: false, isGuest: true, host: false, metadata: null), isTrue);
      expect(liveRoomIsPrivate(isTeacher: false, isGuest: true, host: false, metadata: '{"privacy": "private", "role": "guest"}'), isTrue);
      expect(liveRoomIsPrivate(isTeacher: false, isGuest: false, host: false, metadata: '{"privacy": "private"}'), isTrue);
      expect(liveRoomIsPrivate(isTeacher: true, isGuest: false, host: true, metadata: null), isFalse);
      expect(liveRoomIsPrivate(isTeacher: false, isGuest: false, host: true, metadata: '{"privacy": "private"}'), isFalse);
      expect(liveRoomIsPrivate(isTeacher: false, isGuest: false, host: false, metadata: null), isFalse);
    });

    testWidgets("the guest's room shows no head count and no participant list", (t) async {
      AppConfig.lang = 'en';
      await t.pumpWidget(layoutHost(_room(), scale: 1));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.people_rounded), findsNothing);
      expect(find.byIcon(Icons.groups_rounded), findsNothing);
      final bare = t.widgetList<Text>(find.byType(Text)).map((w) => (w.data ?? '').trim()).where((s) => RegExp(r'^[0-9٠-٩]+$').hasMatch(s));
      expect(bare, isEmpty);
    });
  });

  group('check-in errors', () {
    setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
    tearDownAll(() => translation = {});

    test('the relay, witness and Bluetooth failures read neutral: no classmate, witness or Bluetooth', () {
      final banned = RegExp(r'classmate|witness|bluetooth|nearby|زميل|زملاء|شهود|بلوتوث|البلوتوث', caseSensitive: false);
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        for (final k in ['att_err_no_relay', 'att_err_witnesses', 'att_err_bluetooth_off']) {
          final s = studentCheckInErrorText(k);
          expect(s, isNot(k), reason: '$lang $k has a text');
          expect(s.startsWith('sb_att_'), isFalse, reason: '$lang $k is translated');
          expect(banned.hasMatch(s), isFalse, reason: '$lang $k: $s');
        }
      }
      AppConfig.lang = 'en';
      expect(studentCheckInErrorText('att_err_code_format'), 'att_err_code_format'.tr);
    });

    testWidgets('the failed sheet shows the neutral text', (t) async {
      await expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
          child: StudentCheckInView(phase: StudentCheckInPhase.failed, onRetry: () {}, onClose: () {}, error: studentCheckInErrorText('att_err_no_relay')),
        ),
        act: (t) async => expect(find.text(studentCheckInErrorText('att_err_no_relay')), findsOneWidget),
      );
    });
  });
}
