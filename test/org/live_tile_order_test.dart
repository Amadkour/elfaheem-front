// The room's tile order and re-layout throttle (widgets/live_tile_order.dart, D21): speakers stay on top in their
// places for 2 s, the order is total and stable, and the throttle runs at most twice a second with the last
// change always applied.
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_tile_order.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 10, 29, 10);

LiveTileFacts<String> _tile(String id,
        {bool speaking = false, DateTime? spoke, bool video = true, int joined = 0}) =>
    LiveTileFacts(
      item: id,
      id: id,
      speaking: speaking,
      lastSpokeAt: spoke,
      hasVideo: video,
      joinedAt: _t0.subtract(Duration(minutes: 60 - joined)),
    );

void main() {
  group('LiveSpeakerOrder', () {
    test('nobody speaks: recent speaker, cameras on, who joined first, then the id', () {
      final o = LiveSpeakerOrder();
      final order = o.order([
        _tile('d', joined: 4),
        _tile('c', video: false, joined: 1),
        _tile('b', spoke: _t0.subtract(const Duration(minutes: 1)), joined: 3),
        _tile('a', joined: 2),
        _tile('e', joined: 2),
      ], _t0);
      expect(order, ['b', 'a', 'e', 'd', 'c']);
      expect(o.recheckAt, isNull);
    });

    test('the same input always gives the same order', () {
      final tiles = [_tile('x', joined: 1), _tile('y', joined: 1), _tile('z', joined: 1)];
      final a = LiveSpeakerOrder().order(tiles, _t0);
      final b = LiveSpeakerOrder().order(tiles.reversed.toList(), _t0);
      expect(a, b);
    });

    test('two people taking turns keep their places while both are within the hold', () {
      final o = LiveSpeakerOrder();
      var now = _t0;
      // A speaks first and goes on top.
      expect(o.order([_tile('a', speaking: true, spoke: now), _tile('b'), _tile('c')], now).first, 'a');
      // B answers 500 ms later: A is still held, B joins the speaking group BELOW A (no swap).
      now = now.add(const Duration(milliseconds: 500));
      expect(o.order([_tile('a', spoke: _t0), _tile('b', speaking: true, spoke: now), _tile('c')], now),
          ['a', 'b', 'c']);
      // A again, B still held: the order does not move.
      now = now.add(const Duration(milliseconds: 500));
      expect(o.order([_tile('a', speaking: true, spoke: now), _tile('b', spoke: now), _tile('c')], now),
          ['a', 'b', 'c']);
      expect(o.recheckAt, _t0.add(const Duration(milliseconds: 2500)), reason: 'B leaves the group when its hold ends');
    });

    test('after the hold, a quiet speaker drops to the idle group (most recent first)', () {
      final o = LiveSpeakerOrder();
      final spoke = _t0;
      o.order([_tile('a'), _tile('b', speaking: true, spoke: spoke)], spoke);
      final later = spoke.add(const Duration(milliseconds: 1500));
      expect(o.order([_tile('a', speaking: true, spoke: later), _tile('b', spoke: spoke)], later), ['b', 'a']);
      final after = later.add(const Duration(milliseconds: 2500));
      // a still speaking → top; b is idle now.
      expect(o.order([_tile('a', speaking: true, spoke: later), _tile('b', spoke: spoke)], after), ['a', 'b']);
      expect(o.recheckAt, isNull);
    });

    test('people who left are forgotten', () {
      final o = LiveSpeakerOrder();
      o.order([_tile('a', speaking: true, spoke: _t0), _tile('b')], _t0);
      expect(o.order([_tile('b')], _t0.add(const Duration(milliseconds: 100))), ['b']);
      expect(o.previous, ['b']);
      expect(o.recheckAt, isNull);
    });
  });

  group('LiveUpdateThrottle', () {
    testWidgets('first at once, then one trailing run per interval', (tester) async {
      var now = _t0;
      var runs = 0;
      final th = LiveUpdateThrottle(const Duration(milliseconds: 500), () => runs++, clock: () => now);
      addTearDown(th.dispose);

      th.request();
      expect(runs, 1);
      // A burst inside the window: nothing now, one trailing run at the end of the window.
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(milliseconds: 20));
        th.request();
      }
      expect(runs, 1);
      expect(th.pending, isTrue);
      now = now.add(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(runs, 2, reason: 'the last change is applied');
      expect(th.pending, isFalse);

      // Quiet for longer than the interval: the next request runs at once.
      now = now.add(const Duration(seconds: 1));
      th.request();
      expect(runs, 3);
    });

    testWidgets('nothing runs after dispose', (tester) async {
      var now = _t0;
      var runs = 0;
      final th = LiveUpdateThrottle(const Duration(milliseconds: 500), () => runs++, clock: () => now);
      th.request();
      now = now.add(const Duration(milliseconds: 100));
      th.request();
      th.dispose();
      await tester.pump(const Duration(seconds: 1));
      th.request();
      expect(runs, 1);
    });
  });
}
