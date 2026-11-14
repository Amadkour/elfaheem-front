// D-106 on the pre-join page: a calendar meeting's page says «اجتماع» / "meeting" everywhere (title fallback, Join,
// the recording note, the listen-only banner, the role tag), a course session's keeps «الحصة» / "session"; the
// layout holds at 320×640 and 1400×900, ar + en, text 1.3×. The Join button is the focused primary action (Enter
// presses it), and PreJoinPage never joins by itself — even when an older caller still passes autoJoin.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/live/live_room.dart';
import 'package:flutter_education_app/features/shared/points/points_api.dart' show LivePlanDeclined;
import 'package:flutter_education_app/features/live/room/prejoin.dart';
import 'package:flutter_education_app/features/live/room/prejoin_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

const _mics = <PreJoinDevice>[('m1', 'Default - Microphone Array (Realtek(R) Audio)'), ('m2', 'USB Microphone')];
const _cams = <PreJoinDevice>[('c1', 'Integrated Camera (04f2:b6d0) front facing')];

Widget _layout({
  required LiveRoomKind kind,
  bool isTeacher = false,
  bool? isHost,
  bool isGuest = false,
  bool canPublish = true,
  String title = 'Weekly sync with the design team — a long name that has to wrap',
  VoidCallback? onJoin,
  bool busy = false,
}) =>
    PreJoinLayout(
      title: title,
      roomKind: kind,
      isTeacher: isTeacher,
      isHost: isHost,
      isGuest: isGuest,
      canPublish: canPublish,
      userName: 'Sara Ahmed',
      preview: null,
      micOn: true,
      camOn: false,
      onToggleMic: () {},
      onToggleCam: () {},
      mics: _mics,
      cams: _cams,
      selectedMic: 'm1',
      selectedCam: 'c1',
      onMicChanged: (_) {},
      onCamChanged: (_) {},
      busy: busy,
      onJoin: onJoin ?? () {},
      onBack: () {},
    );

/// Every visible string of the tree.
List<String> _texts(WidgetTester t) => [
      for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? w.textSpan?.toPlainText() ?? '',
    ];

final _sessionAr = RegExp('حص|جلس');
final _sessionEn = RegExp(r'\b(session|class|lesson)\b', caseSensitive: false);

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() {
    AppConfig.disableList = [];
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a meeting (participant): every text says meeting, never session', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _layout(kind: LiveRoomKind.meeting, isHost: false, title: 'Live meeting'),
      act: (t) async {
        final ar = AppConfig.lang == 'ar';
        expect(find.text(ar ? 'انضم للاجتماع' : 'Join meeting'), findsOneWidget);
        expect(find.text(ar ? 'قد يتم تسجيل هذا الاجتماع' : 'This meeting may be recorded'), findsOneWidget);
        expect(find.text(ar ? 'مشارك' : 'Participant'), findsOneWidget);
        for (final s in _texts(t)) {
          expect(ar ? _sessionAr.hasMatch(s) : _sessionEn.hasMatch(s), isFalse, reason: 'session wording: "$s"');
        }
      },
    );
  });

  testWidgets('a meeting host (Meet now): Host tag, no "may be recorded" note', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _layout(kind: LiveRoomKind.meeting, isHost: true),
      act: (t) async {
        final ar = AppConfig.lang == 'ar';
        expect(find.text(ar ? 'المضيف' : 'Host'), findsOneWidget);
        expect(find.text(ar ? 'قد يتم تسجيل هذا الاجتماع' : 'This meeting may be recorded'), findsNothing);
        expect(find.text(ar ? 'انضم للاجتماع' : 'Join meeting'), findsOneWidget);
      },
    );
  });

  testWidgets('a listen-only guest of a meeting: the banner says meeting', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _layout(kind: LiveRoomKind.meeting, isGuest: true, canPublish: false),
      act: (t) async {
        final ar = AppConfig.lang == 'ar';
        expect(find.textContaining(ar ? 'في هذا الاجتماع' : 'in this meeting'), findsOneWidget);
        expect(find.text(ar ? 'ضيف' : 'Guest'), findsWidgets);
      },
    );
  });

  testWidgets('a course session keeps الحصة / session and Teacher / Student', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _layout(kind: LiveRoomKind.session, title: 'Advanced Algorithms — week 7'),
      act: (t) async {
        final ar = AppConfig.lang == 'ar';
        expect(find.text(ar ? 'انضم للحصة' : 'Join Session'), findsOneWidget);
        expect(find.text(ar ? 'قد يتم تسجيل هذه الحصة' : 'This session may be recorded'), findsOneWidget);
        expect(find.text(translate('student')), findsOneWidget);
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => _layout(kind: LiveRoomKind.session, isTeacher: true, busy: true),
      act: (t) async => expect(find.text(translate('teacher')), findsOneWidget),
    );
  });

  testWidgets('Join holds the focus and Enter presses it; nothing is pressed by itself', (tester) async {
    AppConfig.lang = 'en';
    var joins = 0;
    await tester.pumpWidget(layoutHost(_layout(kind: LiveRoomKind.meeting, onJoin: () => joins++)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(joins, 0, reason: 'the layout never joins by itself');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'prejoin.join');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(joins, 1);
    await tester.ensureVisible(find.byKey(const ValueKey('prejoin.join')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('prejoin.join')));
    await tester.pump();
    expect(joins, 2);
  });

  testWidgets('PreJoinPage waits for Join even when an older caller passes autoJoin', (tester) async {
    AppConfig.lang = 'ar';
    var starts = 0;
    final page = PreJoinPage(
      args: JoinArgs(
        sessionId: -7,
        roomRef: const LiveRoomRef.meeting(7),
        courseId: 0,
        isTeacher: false,
        isHost: false,
        guest: true,
        canPublish: false, // listen-only: no devices, the page is ready at once
        userName: 'Sara',
        userId: -1,
        apiClient: ApiClient(),
        // ignore: deprecated_member_use_from_same_package
        autoJoin: true,
        onStart: () async {
          starts++;
          throw const LivePlanDeclined(); // swallowed quietly by the page: stays on pre-join
        },
        onEnd: () async {},
      ),
    );
    await tester.pumpWidget(layoutHost(page, scaffold: false));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(starts, 0, reason: 'the page must not join by itself (D-106)');
    expect(find.text('اجتماع مباشر'), findsOneWidget, reason: 'an untitled meeting is a «اجتماع مباشر»');
    expect(find.text('انضم للاجتماع'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('prejoin.join')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('prejoin.join')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(starts, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
