// The live room's top row (D-095, LiveTopRow) at 320×640 and 1400×900, Arabic and English, text scale 1.3: every
// state stays on ONE line without overflow — a student, a guest, a course's teacher recording / paused, a meeting
// creator before / while recording, the server's recording, the countdown with Upgrade, everything at once — and
// the recording control's menu offers exactly what the device had on the bar (Pause / Resume; Stop for a meeting).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/live/live_time_limit.dart' show LiveLimitTone;
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_top_row.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/record/recorder_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void _noop() {}

/// The popup menu's open animation, then the frame that lets its items take taps.
Future<void> _settleMenu(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump();
}

Widget _room(Widget row) => ColoredBox(
      color: const Color(0xFF0B1020),
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), child: row),
      ),
    );

LiveTopRecording _rec(LiveRecPhase phase, {bool stop = false, bool busy = false}) => LiveTopRecording(
      phase: phase,
      elapsed: const Duration(minutes: 3, seconds: 21),
      detail: 'Part 7 · 12.4 MB',
      busy: busy,
      onRecord: _noop,
      onPause: phase == LiveRecPhase.recording ? _noop : null,
      onResume: phase == LiveRecPhase.paused ? _noop : null,
      onStop: stop ? _noop : null,
    );

const _limitWarn = LiveTopLimit(remaining: Duration(minutes: 2, seconds: 9), tone: LiveLimitTone.warn, showUpgrade: true, onUpgrade: _noop);

Map<String, Widget Function()> get _states => {
      'student': () => _room(const LiveTopRow(onInfo: _noop, liveFor: Duration(minutes: 12, seconds: 34), onFocus: _noop, onMinimize: _noop)),
      'guest + server REC': () => _room(const LiveTopRow(
            liveFor: Duration(minutes: 42, seconds: 5),
            recording: LiveTopRecording(phase: LiveRecPhase.server),
          )),
      'teacher recording': () => _room(LiveTopRow(
            onInfo: _noop,
            liveFor: const Duration(hours: 1, minutes: 2, seconds: 3),
            netLowered: true,
            locked: true,
            onLocked: _noop,
            recording: _rec(LiveRecPhase.recording),
            onFocus: _noop,
            onMinimize: _noop,
          )),
      'teacher paused': () => _room(LiveTopRow(
            onInfo: _noop,
            liveFor: const Duration(minutes: 20),
            recording: _rec(LiveRecPhase.paused),
            onMinimize: _noop,
          )),
      'teacher pausing (busy)': () => _room(LiveTopRow(liveFor: const Duration(minutes: 20), recording: _rec(LiveRecPhase.recording, busy: true))),
      'creator before recording + countdown': () => _room(LiveTopRow(
            onInfo: _noop,
            liveFor: const Duration(minutes: 13),
            limit: _limitWarn,
            recording: _rec(LiveRecPhase.offer),
            onMinimize: _noop,
          )),
      'creator recording + stop': () => _room(LiveTopRow(
            onInfo: _noop,
            liveFor: const Duration(minutes: 13),
            limit: const LiveTopLimit(remaining: Duration(minutes: 9), tone: LiveLimitTone.calm),
            recording: _rec(LiveRecPhase.recording, stop: true),
            onFocus: _noop,
            onMinimize: _noop,
          )),
      'starting / uploading / saved / error': () => _room(Column(mainAxisSize: MainAxisSize.min, children: [
            for (final p in [LiveRecPhase.starting, LiveRecPhase.uploading, LiveRecPhase.saved, LiveRecPhase.error])
              LiveTopRow(onInfo: _noop, liveFor: const Duration(minutes: 1), recording: _rec(p, stop: true), onMinimize: _noop),
          ])),
      'free time over': () => _room(const LiveTopRow(
            liveFor: Duration(minutes: 15),
            limit: LiveTopLimit(remaining: Duration.zero, tone: LiveLimitTone.over, showUpgrade: true, busy: true, onUpgrade: _noop),
          )),
      'everything at once': () => _room(LiveTopRow(
            onInfo: _noop,
            liveFor: const Duration(hours: 10, minutes: 59, seconds: 59),
            limit: _limitWarn,
            netLowered: true,
            netRecovering: true,
            locked: true,
            onLocked: _noop,
            recording: LiveTopRecording(
              phase: LiveRecPhase.recording,
              elapsed: const Duration(hours: 10, minutes: 1, seconds: 2),
              onPause: _noop,
              onStop: _noop,
            ),
            onFocus: _noop,
            onMinimize: _noop,
          )),
      'focus exit': () => Stack(children: [
            Positioned(right: 14, bottom: 14, child: LiveFocusExitButton(onTap: _noop, recording: true)),
            Positioned(left: 14, bottom: 14, child: LiveFocusExitButton(onTap: _noop, compact: true)),
          ]),
    };

void main() {
  for (final e in _states.entries) {
    testWidgets('${e.key}: one line, no overflow (phone / web, ar / en, 1.3x)', (tester) async {
      await expectNoLayoutErrors(tester, e.value, act: (t) async {
        final rows = find.byKey(const ValueKey('live_room.top_row'));
        for (final r in rows.evaluate()) {
          expect(t.getSize(find.byWidget(r.widget)).height, LiveTopRow.height, reason: 'one 48 px line');
        }
      });
    });
  }

  test('liveRecPhase: the device recorder wins, then pending, Record, the server', () {
    expect(liveRecPhase(), LiveRecPhase.none);
    expect(liveRecPhase(server: true), LiveRecPhase.server);
    expect(liveRecPhase(offer: true, server: true), LiveRecPhase.offer);
    expect(liveRecPhase(pending: true, offer: true), LiveRecPhase.starting);
    expect(liveRecPhase(state: RecState.idle, server: true), LiveRecPhase.server);
    expect(liveRecPhase(state: RecState.starting), LiveRecPhase.starting);
    expect(liveRecPhase(state: RecState.recording, server: true), LiveRecPhase.recording);
    expect(liveRecPhase(state: RecState.paused), LiveRecPhase.paused);
    expect(liveRecPhase(state: RecState.uploading), LiveRecPhase.uploading);
    expect(liveRecPhase(state: RecState.done), LiveRecPhase.saved);
    expect(liveRecPhase(state: RecState.error), LiveRecPhase.error);
  });

  test('showsRecorderControls: a teacher follows the record switch, anyone else follows recordsHere', () {
    expect(showsRecorderControls(isTeacher: true, recordingEnabled: true, recordsHere: false), isTrue);
    expect(showsRecorderControls(isTeacher: true, recordingEnabled: true, recordsHere: true), isTrue);
    expect(showsRecorderControls(isTeacher: true, recordingEnabled: false, recordsHere: true), isFalse);
    expect(showsRecorderControls(isTeacher: true, recordingEnabled: false, recordsHere: false), isFalse);
    expect(showsRecorderControls(isTeacher: false, recordingEnabled: true, recordsHere: true), isTrue);
    expect(showsRecorderControls(isTeacher: false, recordingEnabled: false, recordsHere: true), isTrue);
    expect(showsRecorderControls(isTeacher: false, recordingEnabled: true, recordsHere: false), isFalse);
  });

  testWidgets('every chip sits on the same line, the end group at the end', (tester) async {
    await expectNoLayoutErrors(tester, _states['teacher recording']!, act: (t) async {
      final keys = ['live_room.info', 'live_room.live_time', 'live_room.rec_control', 'live_room.focus', 'live_room.minimize'];
      final ys = {for (final k in keys) t.getCenter(find.byKey(ValueKey(k))).dy.round()};
      expect(ys.length, 1, reason: 'one line: $ys');
      final rtl = AppConfig.lang == 'ar';
      final info = t.getCenter(find.byKey(const ValueKey('live_room.info'))).dx;
      final minimize = t.getCenter(find.byKey(const ValueKey('live_room.minimize'))).dx;
      expect(rtl ? info > minimize : info < minimize, isTrue, reason: 'info at the start, minimize at the end');
      for (final k in keys.where((k) => k != 'live_room.live_time')) {
        final s = t.getSize(find.byKey(ValueKey(k)));
        expect(s.height >= 48 && s.width >= 48, isTrue, reason: '$k is a 48 px target: $s');
      }
    });
  });

  testWidgets('teacher: the REC control opens Pause (no Stop); paused opens Resume', (tester) async {
    var paused = 0, resumed = 0;
    await expectNoLayoutErrors(tester, () => _room(LiveTopRow(
          liveFor: const Duration(minutes: 5),
          recording: LiveTopRecording(phase: LiveRecPhase.recording, elapsed: const Duration(seconds: 61), onPause: () => paused++),
        )), act: (t) async {
      await t.tap(find.byKey(const ValueKey('live_room.rec_control')));
      await _settleMenu(t);
      expect(find.byKey(const ValueKey('live_room.rec_menu.pause')), findsOneWidget);
      expect(find.byKey(const ValueKey('live_room.rec_menu.stop')), findsNothing);
      expect(find.byKey(const ValueKey('live_room.rec_menu.resume')), findsNothing);
      await t.tap(find.byKey(const ValueKey('live_room.rec_menu.pause')));
      await t.pump(const Duration(milliseconds: 400));
    });
    expect(paused, 4, reason: 'once per size × language');
    await expectNoLayoutErrors(tester, () => _room(LiveTopRow(
          recording: LiveTopRecording(phase: LiveRecPhase.paused, onResume: () => resumed++),
        )), act: (t) async {
      await t.tap(find.byKey(const ValueKey('live_room.rec_control')));
      await _settleMenu(t);
      expect(find.byKey(const ValueKey('live_room.rec_menu.pause')), findsNothing);
      await t.tap(find.byKey(const ValueKey('live_room.rec_menu.resume')));
      await t.pump(const Duration(milliseconds: 400));
    });
    expect(resumed, 4);
  });

  testWidgets('meeting creator: Record, then Pause + Stop in the menu', (tester) async {
    var recorded = 0, stopped = 0;
    await expectNoLayoutErrors(tester, () => _room(LiveTopRow(
          recording: LiveTopRecording(phase: LiveRecPhase.offer, onRecord: () => recorded++),
        )), act: (t) async {
      expect(find.byKey(const ValueKey('live_room.rec_control')), findsNothing);
      await t.tap(find.byKey(const ValueKey('live_room.record')));
    });
    expect(recorded, 4);
    await expectNoLayoutErrors(tester, () => _room(LiveTopRow(
          recording: LiveTopRecording(phase: LiveRecPhase.recording, onPause: _noop, onStop: () => stopped++),
        )), act: (t) async {
      await t.tap(find.byKey(const ValueKey('live_room.rec_control')));
      await _settleMenu(t);
      expect(find.byKey(const ValueKey('live_room.rec_menu.pause')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('live_room.rec_menu.stop')));
      await t.pump(const Duration(milliseconds: 400));
    });
    expect(stopped, 4);
  });

  testWidgets('server recording and a guest: REC without controls; nothing when nobody records', (tester) async {
    await expectNoLayoutErrors(tester, _states['guest + server REC']!, act: (t) async {
      expect(find.byKey(const ValueKey('live_room.rec_server')), findsOneWidget);
      expect(find.byKey(const ValueKey('live_room.minimize')), findsNothing);
      await t.tap(find.byKey(const ValueKey('live_room.rec_server')));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('live_room.rec_menu.pause')), findsNothing);
    });
    await expectNoLayoutErrors(tester, _states['student']!, act: (t) async {
      for (final k in ['live_room.rec_server', 'live_room.rec_control', 'live_room.record']) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
    });
  });

  testWidgets('labels on wide screens, icons on phones; the times stay', (tester) async {
    await expectNoLayoutErrors(tester, _states['teacher recording']!, act: (t) async {
      final wide = t.view.physicalSize.width >= kLiveTopRowCompactWidth;
      final en = AppConfig.lang == 'en';
      expect(find.text('03:21'), findsOneWidget);
      expect(find.text('1:02:03'), findsOneWidget);
      if (en) {
        expect(find.text('Minimize'), wide ? findsOneWidget : findsNothing);
        expect(find.text('Full view'), wide ? findsOneWidget : findsNothing);
        expect(find.text('Locked'), wide ? findsOneWidget : findsNothing);
      }
    });
  });

  testWidgets('countdown: Upgrade taps through; the exit button calls back', (tester) async {
    var upgrades = 0, exits = 0;
    await expectNoLayoutErrors(tester, () => _room(LiveTopRow(
          limit: LiveTopLimit(remaining: const Duration(minutes: 1), tone: LiveLimitTone.warn, showUpgrade: true, onUpgrade: () => upgrades++),
        )), act: (t) async {
      await t.tap(find.byKey(const ValueKey('live_room.time_limit.upgrade')));
    });
    expect(upgrades, 4);
    await expectNoLayoutErrors(tester, () => Center(child: LiveFocusExitButton(onTap: () => exits++)), act: (t) async {
      await t.tap(find.byKey(const ValueKey('live_room.focus_exit')));
    });
    expect(exits, 4);
  });
}
