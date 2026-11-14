import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_reactions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  testWidgets('reactions overlay with many bubbles + open picker never overflows', (tester) async {
    LiveReactionsController? ctrl;
    await expectNoLayoutErrors(tester, () {
      ctrl?.dispose();
      final c = LiveReactionsController(minInterval: Duration.zero);
      ctrl = c;
      for (var i = 0; i < 40; i++) {
        c.add(kLiveReactionEmojis[i % kLiveReactionEmojis.length],
            i.isEven ? 'طالب رقم $i باسم طويل جدًا جدًا' : 'Student number $i with a long name');
      }
      c.togglePicker();
      return Stack(children: [
        const ColoredBox(color: Colors.black, child: SizedBox.expand()),
        LiveReactionsOverlay(controller: c, senderName: 'Me'),
      ]);
    }, act: (t) async {
      await t.tap(find.byKey(const ValueKey('live_reaction.pick.👍')));
    });
    expect(ctrl!.bubbles.length, lessThanOrEqualTo(30));
    ctrl!.dispose();
  });

  testWidgets('picker alone fits a narrow box', (tester) async {
    await expectNoLayoutErrors(tester,
        () => Center(child: SizedBox(width: 200, child: LiveReactionPicker(onPick: (_) {}, onClose: () {}))));
  });

  test('controller: rate limit, cap, decode', () {
    final sent = <List<int>>[];
    final c = LiveReactionsController(onSend: (b) async => sent.add(b));
    expect(c.send('👍', 'A'), isTrue);
    expect(c.send('👍', 'A'), isFalse); // within 400ms
    expect(sent.length, 1);
    expect(c.receive(LiveReactionsController.encode('🎉', 'B')), isTrue);
    expect(c.bubbles.last.name, 'B');
    expect(c.receive(LiveReactionsController.encode('<script>', 'X')), isTrue); // swallowed, not shown
    expect(c.bubbles.length, 2);
    expect(c.receive('hello'.codeUnits), isFalse);
    for (var i = 0; i < 50; i++) {
      c.add('👏', 'x');
    }
    expect(c.bubbles.length, 30);
    c.dispose();
  });
}
