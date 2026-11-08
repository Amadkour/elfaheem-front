// D-313: a meeting's board / shared screen fills the room and its controls float over it (LiveStageOverlay) — at
// 320×640 and 1400×900, Arabic and English, text scale 1.3: shown, the top row is at the top and the bar at the
// bottom OVER the content (the content keeps the whole screen), the toggle under the row; hidden, only the toggle is
// left (a 48 px target) with the recording's dot / pause glyph, the bars take no taps; the toggle flips it; the
// "⏸ Not recording · ● Record" chip of the top row (D-313 (5)) fits everywhere.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_stage_overlay.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_top_row.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void _noop() {}

LiveTopRow _row({LiveRecPhase phase = LiveRecPhase.offer}) => LiveTopRow(
      onInfo: _noop,
      liveFor: const Duration(minutes: 4, seconds: 2),
      recording: LiveTopRecording(phase: phase, onRecord: _noop, elapsed: const Duration(minutes: 1, seconds: 3)),
      board: const LiveTopBoard(presenting: true, pageIndex: 0, pageCount: 2, onPrevious: _noop, onNext: _noop, onAddPage: _noop, onOptions: _noop, onStop: _noop),
      onMinimize: _noop,
    );

Widget _bar() => Container(
      key: const ValueKey('test.bar'),
      height: 64,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFF1B2233), borderRadius: BorderRadius.circular(32)),
    );

Widget _scene({required bool shown, VoidCallback? onToggle, VoidCallback? onContent, LiveOverlayRec rec = LiveOverlayRec.none}) =>
    Stack(fit: StackFit.expand, children: [
      GestureDetector(
        key: const ValueKey('test.content'),
        behavior: HitTestBehavior.opaque,
        onTap: onContent,
        child: const ColoredBox(color: Color(0xFFF6F7FB)),
      ),
      LiveStageOverlay(
        shown: shown,
        onToggle: onToggle ?? _noop,
        rec: rec,
        top: Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), child: _row()),
        bottom: _bar(),
      ),
    ]);

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('shown: the row on top, the bar at the bottom, over the content; the toggle hides', (tester) async {
    var toggles = 0;
    await expectNoLayoutErrors(tester, () => _scene(shown: true, onToggle: () => toggles++), act: (t) async {
      final size = t.getSize(find.byKey(const ValueKey('test.content')));
      expect(size, t.view.physicalSize / t.view.devicePixelRatio, reason: 'the content keeps the whole screen');
      final row = t.getRect(find.byKey(const ValueKey('live_room.top_row')));
      final bar = t.getRect(find.byKey(const ValueKey('test.bar')));
      final toggle = t.getRect(find.byKey(const ValueKey('live_room.overlay_toggle')));
      expect(row.top, lessThan(12));
      expect(bar.bottom, greaterThan(size.height - 20));
      expect(toggle.top, greaterThanOrEqualTo(row.bottom - 0.5), reason: 'under the row');
      expect(toggle.height, greaterThanOrEqualTo(48));
      expect(toggle.width, greaterThanOrEqualTo(48));
      expect(find.byKey(const ValueKey('live_room.record')).hitTestable(), findsWidgets);
      await t.tap(find.byKey(const ValueKey('live_room.overlay_toggle')));
    });
    expect(toggles, 4, reason: 'once per size × language');
  });

  testWidgets('hidden: only the toggle (with the recording state); a tap where the bars were reaches the content',
      (tester) async {
    var taps = 0, toggles = 0;
    for (final rec in [LiveOverlayRec.recording, LiveOverlayRec.paused, LiveOverlayRec.notYet]) {
      await expectNoLayoutErrors(
          tester, () => _scene(shown: false, rec: rec, onContent: () => taps++, onToggle: () => toggles++), act: (t) async {
        await t.pump(const Duration(milliseconds: 400));
        final h = t.view.physicalSize.height / t.view.devicePixelRatio;
        expect(find.byKey(const ValueKey('live_room.top_row')).hitTestable(), findsNothing);
        expect(find.byKey(const ValueKey('test.bar')).hitTestable(), findsNothing);
        expect(find.byKey(const ValueKey('live_room.overlay_rec')), findsOneWidget);
        final toggle = t.getRect(find.byKey(const ValueKey('live_room.overlay_toggle')));
        expect(toggle.top, lessThan(8), reason: 'the toggle moved up with the row');
        await t.tapAt(Offset(40, h - 30)); // where the bar was
        await t.tap(find.byKey(const ValueKey('live_room.overlay_toggle')));
      });
    }
    expect(taps, 12);
    expect(toggles, 12);
  });

  testWidgets('the top row\'s paused "Not recording · Record" chip fits; a tap records', (tester) async {
    var recorded = 0;
    await expectNoLayoutErrors(
      tester,
      () => ColoredBox(
        color: const Color(0xFF0B1020),
        child: Align(
          alignment: Alignment.topCenter,
          child: LiveTopRow(
            onInfo: _noop,
            liveFor: const Duration(seconds: 1),
            recording: LiveTopRecording(phase: LiveRecPhase.offer, onRecord: () => recorded++),
            onMinimize: _noop,
          ),
        ),
      ),
      act: (t) async {
        expect(find.byIcon(Icons.pause_rounded), findsWidgets);
        final wide = t.view.physicalSize.width / t.view.devicePixelRatio >= kLiveTopRowCompactWidth;
        final ar = AppConfig.lang == 'ar';
        if (wide) expect(find.text(ar ? 'لا يُسجَّل' : 'Not recording'), findsWidgets);
        expect(find.text(ar ? 'تسجيل' : 'Record'), findsWidgets);
        await t.tap(find.byKey(const ValueKey('live_room.record')).first);
      },
    );
    expect(recorded, 4);
  });

  testWidgets('Reduce motion: hiding is at once', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600), disableAnimations: true),
        child: Scaffold(body: _scene(shown: false)),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('live_room.top_row')).hitTestable(), findsNothing);
  });
}
