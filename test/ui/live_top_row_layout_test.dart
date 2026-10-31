// The live room's top row (D-095, LiveTopRow) at 320×640 and 1400×900, Arabic and English, text scale 1.3: every
// state stays on ONE line without overflow — a student, a guest, a course's teacher recording / paused, a meeting
// creator before / while recording, the server's recording, the countdown with Upgrade, everything at once — and
// the recording control's menu offers exactly what the device had on the bar (Pause / Resume; Stop for a meeting).
// D-108: with a whiteboard on the stage its title, page and controls join the SAME line (the board draws no bar of
// its own); what does not fit goes into ⋮ — LIVE, REC and the page number never leave the line, nothing wraps.
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
      'full view (focused)': () => _room(LiveTopRow(
            onInfo: _noop,
            liveFor: const Duration(minutes: 12),
            recording: _rec(LiveRecPhase.recording),
            onFocus: _noop,
            focused: true,
            onMinimize: _noop,
          )),
      // D-108: the board's header on the recording's line (it drew its own bar over the page before).
      'board: presenter recording': () => _room(_boardRow(presenting: true)),
      'board: presenter, everything at once': () => _room(_boardRow(presenting: true, crowded: true)),
      'board: viewer allowed to draw, server REC': () => _room(LiveTopRow(
            onInfo: _noop,
            liveFor: const Duration(minutes: 33, seconds: 2),
            recording: const LiveTopRecording(phase: LiveRecPhase.server),
            board: const LiveTopBoard(
                presenting: false, pageIndex: 4, pageCount: 12, presenterName: 'Dr. Mona Elsayed Abdelrahman', canDraw: true),
            onFocus: _noop,
            onMinimize: _noop,
          )),
      'board: host stops a student board, focused': () => _room(LiveTopRow(
            onInfo: _noop,
            liveFor: const Duration(hours: 1, minutes: 2, seconds: 3),
            recording: _rec(LiveRecPhase.paused),
            board: const LiveTopBoard(presenting: false, pageIndex: 0, pageCount: 1, presenterName: 'سارة أحمد', onStop: _noop),
            onFocus: _noop,
            focused: true,
            onMinimize: _noop,
          )),
    };

LiveTopRow _boardRow({required bool presenting, bool crowded = false}) => LiveTopRow(
      onInfo: _noop,
      liveFor: const Duration(hours: 1, minutes: 2, seconds: 3),
      limit: crowded ? _limitWarn : null,
      netLowered: crowded,
      locked: crowded,
      onLocked: _noop,
      recording: _rec(LiveRecPhase.recording, stop: crowded),
      board: LiveTopBoard(
        presenting: presenting,
        pageIndex: 1,
        pageCount: 3,
        onPrevious: _noop,
        onNext: _noop,
        onAddPage: _noop,
        onOptions: presenting ? _noop : null,
        onStop: _noop,
      ),
      onFocus: _noop,
      onMinimize: _noop,
    );

/// A piece the row draws (a folded / moved one is still built, for measuring, but takes no taps).
Finder _k(String key) => find.byKey(ValueKey(key)).hitTestable();

/// Every text the row draws sits on ONE line: the row is 48 px and their centres share its middle.
void _expectOneLine(WidgetTester t) {
  final rows = find.byKey(const ValueKey('live_room.top_row'));
  for (final r in rows.evaluate()) {
    final row = find.byWidget(r.widget);
    expect(t.getSize(row).height, LiveTopRow.height, reason: 'one 48 px line');
    final mid = t.getCenter(row).dy;
    final texts = find.descendant(of: row, matching: find.byType(Text)).hitTestable();
    expect(texts, findsWidgets, reason: 'the row draws something');
    for (final e in texts.evaluate()) {
      final c = t.getCenter(find.byWidget(e.widget).first).dy;
      expect((c - mid).abs() < 3, isTrue, reason: '"${(e.widget as Text).data}" is off the line: $c vs $mid');
    }
    final box = t.getRect(row);
    for (final e in find.descendant(of: row, matching: find.byType(Icon)).hitTestable().evaluate()) {
      final r = t.getRect(find.byWidget(e.widget).first);
      expect(r.top >= box.top - 0.5 && r.bottom <= box.bottom + 0.5 && r.left >= box.left - 0.5 && r.right <= box.right + 0.5, isTrue,
          reason: 'an icon outside the row: $r in $box');
    }
  }
}

void main() {
  for (final e in _states.entries) {
    testWidgets('${e.key}: one line, no overflow (phone / web, ar / en, 1.3x)', (tester) async {
      await expectNoLayoutErrors(tester, e.value, act: (t) async => _expectOneLine(t));
    });
  }

  testWidgets('board on a phone: LIVE, REC and the page stay on the line; the rest is in ⋮; nothing in ⋮ on the web', (tester) async {
    var next = 0;
    await expectNoLayoutErrors(tester, () => _room(LiveTopRow(
          onInfo: _noop,
          liveFor: const Duration(hours: 1, minutes: 2, seconds: 3),
          limit: _limitWarn,
          netLowered: true,
          locked: true,
          onLocked: _noop,
          recording: _rec(LiveRecPhase.recording, stop: true),
          board: LiveTopBoard(presenting: true, pageIndex: 0, pageCount: 3, onPrevious: _noop, onNext: () => next++, onAddPage: _noop, onOptions: _noop, onStop: _noop),
          onFocus: _noop,
          onMinimize: _noop,
        )), act: (t) async {
      final phone = t.view.physicalSize.width < kLiveTopRowCompactWidth;
      for (final k in ['live_room.info', 'live_room.rec_control', 'board.page_label']) {
        expect(_k(k), findsOneWidget, reason: '$k stays on the line');
      }
      expect(find.text('1 / 3').hitTestable(), findsOneWidget);
      if (!phone) {
        expect(_k('live_room.top_more'), findsNothing, reason: 'a wide screen has room for everything');
        for (final k in ['board.page_prev', 'board.page_next', 'board.page_add', 'board.options', 'board.stop', 'live_room.focus', 'live_room.minimize']) {
          expect(_k(k), findsOneWidget, reason: k);
        }
        await t.tap(_k('board.page_next'));
        return;
      }
      expect(_k('live_room.top_more'), findsOneWidget);
      await t.tap(_k('live_room.top_more'));
      await _settleMenu(t);
      expect(_k('live_room.top_more.page_prev'), findsOneWidget, reason: 'the arrows moved into ⋮');
      await t.tap(_k('live_room.top_more.page_next'));
      await t.pump(const Duration(milliseconds: 400));
    });
    expect(next, 4, reason: 'next page once per size × language, from the row or from ⋮');
  });

  testWidgets('board: the presenter\'s pieces sit on one line with the REC control (no second bar)', (tester) async {
    await expectNoLayoutErrors(tester, _states['board: presenter recording']!, act: (t) async {
      final keys = ['live_room.info', 'board.page_label', 'live_room.rec_control'];
      final ys = {for (final k in keys) t.getCenter(_k(k)).dy.round()};
      expect(ys.length, 1, reason: 'one line: $ys');
    });
  });

  testWidgets('full view: the button reads Exit and calls back', (tester) async {
    var exits = 0;
    await expectNoLayoutErrors(tester, () => _room(LiveTopRow(liveFor: const Duration(minutes: 1), onFocus: () => exits++, focused: true)),
        act: (t) async {
      expect(_k('live_room.focus'), findsNothing);
      await t.tap(_k('live_room.focus_exit'));
    });
    expect(exits, 4);
  });

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
      // A 320 px phone at 1.3x has no room for Full view / Minimize beside the network and lock pills: they are in ⋮.
      final wide = t.view.physicalSize.width >= kLiveTopRowCompactWidth;
      final last = wide ? 'live_room.minimize' : 'live_room.top_more';
      final keys = ['live_room.info', 'live_room.live_time', 'live_room.rec_control', if (wide) 'live_room.focus', last];
      final ys = {for (final k in keys) t.getCenter(_k(k)).dy.round()};
      expect(ys.length, 1, reason: 'one line: $ys');
      final rtl = AppConfig.lang == 'ar';
      final info = t.getCenter(_k('live_room.info')).dx;
      final minimize = t.getCenter(_k(last)).dx;
      expect(rtl ? info > minimize : info < minimize, isTrue, reason: 'info at the start, minimize at the end');
      for (final k in keys.where((k) => k != 'live_room.live_time')) {
        final s = t.getSize(_k(k));
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
      await t.tap(_k('live_room.rec_control'));
      await _settleMenu(t);
      expect(_k('live_room.rec_menu.pause'), findsOneWidget);
      expect(_k('live_room.rec_menu.stop'), findsNothing);
      expect(_k('live_room.rec_menu.resume'), findsNothing);
      await t.tap(_k('live_room.rec_menu.pause'));
      await t.pump(const Duration(milliseconds: 400));
    });
    expect(paused, 4, reason: 'once per size × language');
    await expectNoLayoutErrors(tester, () => _room(LiveTopRow(
          recording: LiveTopRecording(phase: LiveRecPhase.paused, onResume: () => resumed++),
        )), act: (t) async {
      await t.tap(_k('live_room.rec_control'));
      await _settleMenu(t);
      expect(_k('live_room.rec_menu.pause'), findsNothing);
      await t.tap(_k('live_room.rec_menu.resume'));
      await t.pump(const Duration(milliseconds: 400));
    });
    expect(resumed, 4);
  });

  testWidgets('meeting creator: Record, then Pause + Stop in the menu', (tester) async {
    var recorded = 0, stopped = 0;
    await expectNoLayoutErrors(tester, () => _room(LiveTopRow(
          recording: LiveTopRecording(phase: LiveRecPhase.offer, onRecord: () => recorded++),
        )), act: (t) async {
      expect(_k('live_room.rec_control'), findsNothing);
      await t.tap(_k('live_room.record'));
    });
    expect(recorded, 4);
    await expectNoLayoutErrors(tester, () => _room(LiveTopRow(
          recording: LiveTopRecording(phase: LiveRecPhase.recording, onPause: _noop, onStop: () => stopped++),
        )), act: (t) async {
      await t.tap(_k('live_room.rec_control'));
      await _settleMenu(t);
      expect(_k('live_room.rec_menu.pause'), findsOneWidget);
      await t.tap(_k('live_room.rec_menu.stop'));
      await t.pump(const Duration(milliseconds: 400));
    });
    expect(stopped, 4);
  });

  testWidgets('server recording and a guest: REC without controls; nothing when nobody records', (tester) async {
    await expectNoLayoutErrors(tester, _states['guest + server REC']!, act: (t) async {
      expect(_k('live_room.rec_server'), findsOneWidget);
      expect(_k('live_room.minimize'), findsNothing);
      await t.tap(_k('live_room.rec_server'));
      await t.pump(const Duration(milliseconds: 400));
      expect(_k('live_room.rec_menu.pause'), findsNothing);
    });
    await expectNoLayoutErrors(tester, _states['student']!, act: (t) async {
      for (final k in ['live_room.rec_server', 'live_room.rec_control', 'live_room.record']) {
        expect(_k(k), findsNothing, reason: k);
      }
    });
  });

  testWidgets('labels on wide screens, icons on phones; the times stay', (tester) async {
    await expectNoLayoutErrors(tester, _states['teacher recording']!, act: (t) async {
      final wide = t.view.physicalSize.width >= kLiveTopRowCompactWidth;
      final en = AppConfig.lang == 'en';
      expect(find.text('03:21').hitTestable(), findsOneWidget);
      expect(find.text('1:02:03').hitTestable(), findsOneWidget);
      if (en) {
        expect(find.text('Minimize').hitTestable(), wide ? findsOneWidget : findsNothing);
        expect(find.text('Full view').hitTestable(), wide ? findsOneWidget : findsNothing);
        expect(find.text('Locked').hitTestable(), wide ? findsOneWidget : findsNothing);
      }
    });
  });

  testWidgets('countdown: Upgrade taps through', (tester) async {
    var upgrades = 0;
    await expectNoLayoutErrors(tester, () => _room(LiveTopRow(
          limit: LiveTopLimit(remaining: const Duration(minutes: 1), tone: LiveLimitTone.warn, showUpgrade: true, onUpgrade: () => upgrades++),
        )), act: (t) async {
      await t.tap(_k('live_room.time_limit.upgrade'));
    });
    expect(upgrades, 4);
  });
}
