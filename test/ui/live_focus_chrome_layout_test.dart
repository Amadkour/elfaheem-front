// Full view's bars (D-108, LiveFocusChrome) at 320×640 and 1400×900, Arabic and English, text scale 1.3: hidden,
// only the content is drawn (the bars are off screen, see-through and take no taps, so a tap reaches the content);
// shown, the top row slides in at the top and the bar at the bottom, over the content (the content never moves);
// the top row stays ONE 48 px line; the hint pill fits; Reduce motion moves them at once.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_focus_chrome.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_top_row.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void _noop() {}

const _row = LiveTopRow(
  onInfo: _noop,
  liveFor: Duration(minutes: 24, seconds: 51),
  recording: LiveTopRecording(phase: LiveRecPhase.recording, elapsed: Duration(minutes: 18, seconds: 7), onPause: _noop),
  board: LiveTopBoard(presenting: true, pageIndex: 1, pageCount: 3, onPrevious: _noop, onNext: _noop, onAddPage: _noop, onOptions: _noop, onStop: _noop),
  onFocus: _noop,
  focused: true,
  onMinimize: _noop,
);

Widget _bar() => Container(
      key: const ValueKey('test.bar'),
      height: 64,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFF1B2233), borderRadius: BorderRadius.circular(32)),
    );

Widget _scene({required bool shown, bool hint = false, VoidCallback? onContent, bool handle = false, VoidCallback? onHandle}) =>
    Stack(fit: StackFit.expand, children: [
      GestureDetector(
        key: const ValueKey('test.content'),
        behavior: HitTestBehavior.opaque,
        onTap: onContent,
        child: const ColoredBox(color: Color(0xFFF6F7FB)),
      ),
      LiveFocusChrome(
        shown: shown,
        hint: hint,
        top: const Padding(padding: EdgeInsets.fromLTRB(10, 4, 10, 4), child: _row),
        bottom: _bar(),
        handle: handle,
        onHandle: onHandle,
      ),
    ]);

void main() {
  testWidgets('hidden: only the content; a tap reaches it; the hint fits', (tester) async {
    var taps = 0;
    await expectNoLayoutErrors(tester, () => _scene(shown: false, hint: true, onContent: () => taps++), act: (t) async {
      final h = t.view.physicalSize.height;
      expect(t.getRect(find.byKey(const ValueKey('live_room.top_row'))).bottom <= 0.5, isTrue, reason: 'the row is above the screen');
      expect(t.getRect(find.byKey(const ValueKey('test.bar'))).top >= h - 0.5, isTrue, reason: 'the bar is below the screen');
      expect(find.byKey(const ValueKey('live_room.focus_exit')).hitTestable(), findsNothing);
      expect(find.byKey(const ValueKey('live_room.focus_hint')), findsOneWidget);
      // A tap where the row would be reaches the content (the hidden bars take no taps).
      await t.tapAt(const Offset(160, 24));
      await t.tapAt(Offset(160, h - 30));
    });
    expect(taps, 8, reason: 'two taps per size × language');
  });

  testWidgets('shown: the row on top (one line), the bar at the bottom, over the content', (tester) async {
    var taps = 0;
    await expectNoLayoutErrors(tester, () => _scene(shown: true, onContent: () => taps++), act: (t) async {
      final size = t.view.physicalSize;
      final row = t.getRect(find.byKey(const ValueKey('live_room.top_row')));
      expect(row.height, LiveTopRow.height, reason: 'one 48 px line');
      expect(row.top >= 0 && row.top < 12, isTrue, reason: 'at the top: $row');
      final bar = t.getRect(find.byKey(const ValueKey('test.bar')));
      expect(bar.bottom <= size.height && bar.bottom > size.height - 40, isTrue, reason: 'at the bottom: $bar');
      expect(t.getRect(find.byKey(const ValueKey('test.content'))), Offset.zero & size, reason: 'the content does not move');
      expect(find.byKey(const ValueKey('live_room.focus_exit')).hitTestable(), findsOneWidget);
      await t.tapAt(Offset(size.width / 2, size.height / 2));
    });
    expect(taps, 4, reason: 'the middle of the content still takes the tap');
  });

  testWidgets('the bars slide (200 ms), at once under Reduce motion', (tester) async {
    Widget host(bool shown, {bool still = false}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(400, 800), disableAnimations: still),
            child: Scaffold(body: _scene(shown: shown)),
          ),
        );
    await tester.pumpWidget(host(false));
    await tester.pumpWidget(host(true));
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester.getRect(find.byKey(const ValueKey('live_room.top_row'))).top;
    expect(mid < 0, isTrue, reason: 'half way down after 100 ms: $mid');
    await tester.pump(kLiveFocusChromeDuration);
    expect(tester.getRect(find.byKey(const ValueKey('live_room.top_row'))).top >= 0, isTrue);

    await tester.pumpWidget(host(false, still: true));
    await tester.pumpWidget(host(true, still: true));
    await tester.pump();
    expect(tester.getRect(find.byKey(const ValueKey('live_room.top_row'))).top >= 0, isTrue, reason: 'Reduce motion: no slide');
  });

  test('a tap shows hidden bars and hides shown ones', () {
    expect(liveFocusBarsAfterTap(false), isTrue);
    expect(liveFocusBarsAfterTap(true), isFalse);
  });

  // Drawing on the board in full view (D-108, round 7): a tap on the page is ink, so the bars come with a chip.
  testWidgets('drawing: the Controls chip at the top centre while hidden; its tap asks for the bars', (tester) async {
    var asks = 0, taps = 0;
    await expectNoLayoutErrors(tester, () => _scene(shown: false, hint: true, handle: true, onHandle: () => asks++, onContent: () => taps++),
        act: (t) async {
      final w = t.view.physicalSize.width;
      final chip = find.byKey(const ValueKey('live_room.focus_handle')).hitTestable();
      expect(chip, findsOneWidget);
      final r = t.getRect(chip);
      expect(r.top >= 0 && r.bottom <= 72, isTrue, reason: 'at the top: $r');
      expect(r.center.dx, closeTo(w / 2, 1), reason: 'centred: $r');
      expect(r.height >= 48 && r.width >= 48, isTrue, reason: 'a 48 px target: $r');
      final hint = t.getRect(find.byKey(const ValueKey('live_room.focus_hint')));
      expect(hint.top >= r.bottom, isTrue, reason: 'the hint is under the chip: $hint / $r');
      await t.tap(chip);
      // Elsewhere the content still gets its touch (the board draws there).
      await t.tapAt(Offset(w / 2, t.view.physicalSize.height / 2));
    });
    expect(asks, 4, reason: 'one per size × language');
    expect(taps, 4);
  });

  testWidgets('drawing, bars shown: the chip steps aside (Exit is on the row)', (tester) async {
    await expectNoLayoutErrors(tester, () => _scene(shown: true, handle: true, onHandle: () {}), act: (t) async {
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('live_room.focus_handle')).hitTestable(), findsNothing);
      expect(find.byKey(const ValueKey('live_room.focus_exit')).hitTestable(), findsOneWidget);
    });
  });

  testWidgets('not drawing: no chip', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _scene(shown: false)));
    expect(find.byKey(const ValueKey('live_room.focus_handle')), findsNothing);
  });
}
