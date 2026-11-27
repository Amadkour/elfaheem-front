// The teacher's live screens (T1 Live): the prejoin page, the ended page, the lobby sheet and the hands queue at
// every layout size, in both languages, with the large text scale; the plain values behind them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/live/live_lobby_sheets.dart' show LobbyBody;
import 'package:flutter_education_app/features/live/live_room.dart' show LobbyRequest;
import 'package:flutter_education_app/features/live/live_self_view.dart' show SelfViewShape;
import 'package:flutter_education_app/features/live/room/prejoin_layout.dart' show PreJoinIssue;
import 'package:flutter_education_app/features/live/room/prejoin_teacher.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_hands.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_teacher_ended.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void _loadStrings() {
  translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  for (final f in Directory('docs/redesign/strings').listSync().whereType<File>()) {
    if (f.path.endsWith('.json')) translation.addAll(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
  }
}

Widget _prejoin({bool busy = false, PreJoinIssue? issue, int? waiting = 7, bool camOn = false, bool note = true}) =>
    TeacherPreJoinLayout(
      lessonTitle: 'المتتابعات الهندسية',
      userName: 'أ. ماجد الشهري',
      classLine: 'الرياضيات ٣ ثانوي، مجموعة أ',
      timeLine: 'اليوم ٧:٣٠ م',
      liveNow: true,
      waitingCount: waiting,
      micOn: true,
      camOn: camOn,
      micLevel: 0.6,
      onToggleMic: () {},
      onToggleCam: () {},
      busy: busy,
      onJoin: () {},
      onBack: () {},
      joinLabel: 'ادخل الحين',
      issue: issue,
      onRetry: () {},
      mics: const [('a', 'AirPods Pro'), ('b', 'Built-in microphone')],
      cams: const [('c', 'FaceTime HD'), ('d', 'USB camera')],
      selectedMic: 'a',
      selectedCam: 'c',
      onMicChanged: (_) {},
      onCamChanged: (_) {},
      previewShape: SelfViewShape.box,
      onPreviewShape: (_) {},
      recordingNote: note,
    );

void main() {
  setUp(_loadStrings);

  group('teacher prejoin', () {
    testWidgets('lays out at every size', (t) => expectNoLayoutErrors(t, () => _prejoin()));
    testWidgets(
        'busy, an issue, no waiting count, no note',
        (t) => expectNoLayoutErrors(
            t, () => _prejoin(busy: true, issue: PreJoinIssue.permissionDenied, waiting: null, note: false)));
    testWidgets('the join button joins; the waiting pill hides at zero', (t) async {
      var joined = 0;
      AppConfig.lang = 'ar';
      await t.pumpWidget(layoutHost(
        TeacherPreJoinLayout(
          lessonTitle: 'x',
          userName: 'y',
          waitingCount: 0,
          micOn: true,
          camOn: false,
          onToggleMic: () {},
          onToggleCam: () {},
          busy: false,
          onJoin: () => joined++,
          onBack: () {},
          joinLabel: 'ادخل الحين',
        ),
      ));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('prejoin.waiting')), findsNothing);
      await t.ensureVisible(find.byKey(const ValueKey('prejoin.join')));
      await t.tap(find.byKey(const ValueKey('prejoin.join')));
      expect(joined, 1);
    });
  });

  group('teacher ended page', () {
    const summary = LiveEndSummary(
      title: 'المتتابعات الهندسية',
      subtitle: 'الرياضيات ٣ ثانوي، مجموعة أ',
      duration: Duration(minutes: 50),
      attended: 7,
      guests: 2,
      recorded: true,
    );
    testWidgets('lays out at every size',
        (t) => expectNoLayoutErrors(t, () => TeacherEndedView(summary: summary, onBack: () {}, onAddMaterials: () {})));
    testWidgets(
        'no recording, no materials, a long hour count',
        (t) => expectNoLayoutErrors(
            t,
            () => TeacherEndedView(
                summary: const LiveEndSummary(title: 'x', duration: Duration(hours: 12, minutes: 5), attended: 0), onBack: () {})));
    test('the duration reads in minutes, then hours and minutes', () {
      _loadStrings();
      AppConfig.lang = 'en';
      expect(liveDurationText(const Duration(minutes: 50)), '50m');
      expect(liveDurationText(const Duration(minutes: 125)), '2h 5m');
      expect(liveDurationText(Duration.zero), '1m');
    });
    test('the hand-off gives the summary once', () {
      LiveEndHandoff.put(summary);
      expect(LiveEndHandoff.take(), same(summary));
      expect(LiveEndHandoff.take(), isNull);
    });
  });

  group('lobby', () {
    final waiting = [
      LobbyRequest(id: 'r1', name: 'خالد الحربي', requestedAt: DateTime.utc(2026, 11, 20, 10, 3)),
      const LobbyRequest(id: 'r2', name: 'أ. عبدالرحمن', isGuest: true),
      const LobbyRequest(id: 'r3', name: 'تركي السبيعي'),
    ];
    Widget lobby({bool courseClass = true}) => LobbyBody(
          loading: false,
          error: null,
          waiting: waiting,
          courseClass: courseClass,
          everyoneNeedsApproval: false,
          guestsJoinAutomatically: false,
          onAdmit: (_) {},
          onReject: (_) {},
          onAdmitAll: () {},
          onRefresh: () {},
          onEveryoneNeedsApproval: (_) {},
          onGuestsJoinAutomatically: (_) {},
        );
    testWidgets('a course class lobby lays out', (t) => expectNoLayoutErrors(t, () => lobby()));
    testWidgets('a meeting lobby lays out', (t) => expectNoLayoutErrors(t, () => lobby(courseClass: false)));
    testWidgets('the course switch is the approval switch read the other way round', (t) async {
      bool? asked;
      AppConfig.lang = 'ar';
      await t.pumpWidget(layoutHost(LobbyBody(
        loading: false,
        error: null,
        waiting: const [],
        courseClass: true,
        everyoneNeedsApproval: false,
        guestsJoinAutomatically: false,
        onAdmit: (_) {},
        onReject: (_) {},
        onAdmitAll: () {},
        onRefresh: () {},
        onEveryoneNeedsApproval: (v) => asked = v,
        onGuestsJoinAutomatically: (_) {},
      )));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const ValueKey('lobby.everyone_approval')));
      expect(asked, isTrue, reason: 'students were direct; switching it off means everyone needs approval');
    });
  });

  group('hands queue with stage', () {
    testWidgets('a student hand offers bring on stage; a guest keeps allow speak', (t) async {
      final c = LiveHandsController(localIdentity: () => 'teacher_1')
        ..add(const LiveHand(identity: 'student_5', name: 'فيصل العنزي', ts: 1))
        ..add(const LiveHand(identity: 'guest:abc', name: 'ضيف', ts: 2));
      String? staged, allowed;
      AppConfig.lang = 'ar';
      await t.pumpWidget(layoutHost(LiveHandsPanel(
        controller: c,
        isTeacher: true,
        onLower: c.lower,
        onStage: (id) => staged = id,
        onAllowSpeak: (id) => allowed = id,
      )));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('live_hands.stage.guest:abc')), findsNothing);
      await t.tap(find.byKey(const ValueKey('live_hands.stage.student_5')));
      expect(staged, 'student_5');
      await t.tap(find.byKey(const ValueKey('live_hands.allow.guest:abc')));
      expect(allowed, 'guest:abc');
    });
  });
}
