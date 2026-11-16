// The Studio's scrub, trim and seek engine (D-1080): the seek queue never floods or locks, a clip edge follows the
// finger while the page feeds its live trim back, and a drag cut short always releases the page's scrub.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/records/studio_project.dart';
import 'package:flutter_education_app/features/records/studio_seeker.dart';
import 'package:flutter_education_app/features/records/studio_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

/// Holds the edit like the page does: every trim move comes back as the timeline's [StudioTimelineView.edit].
class _PageLikeHost extends StatefulWidget {
  const _PageLikeHost({required this.edit, required this.onCommit});
  final StudioEdit edit;
  final ValueChanged<double?> onCommit;

  @override
  State<_PageLikeHost> createState() => _PageLikeHostState();
}

class _PageLikeHostState extends State<_PageLikeHost> {
  StudioEdit? _live;

  @override
  Widget build(BuildContext context) {
    final base = widget.edit;
    return StudioTimelineView(
      edit: _live ?? base,
      position: 0,
      sourceDuration: 1000,
      selectedClip: 0,
      onScrub: (_) {},
      onTrim: (i, start, s) => setState(() => _live = start ? base.trimStart(i, s) : base.trimEnd(i, s, 1000)),
      onTrimEnd: (i, start, s) {
        setState(() => _live = null);
        widget.onCommit(s);
      },
    );
  }
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('StudioSeeker', () {
    test('latest wins: requests while a seek runs replace the target, nothing queues', () async {
      final sent = <double>[];
      final gates = <Completer<void>>[];
      final s = StudioSeeker(seek: (v) {
        sent.add(v);
        final c = Completer<void>();
        gates.add(c);
        return c.future;
      });
      s.request(1);
      for (var i = 2; i <= 50; i++) {
        s.request(i.toDouble());
      }
      expect(sent, [1]);
      gates.last.complete();
      await Future<void>.delayed(Duration.zero);
      expect(sent, [1, 50], reason: 'the 48 targets in between are never sent');
      gates.last.complete();
      await Future<void>.delayed(Duration.zero);
      expect(s.busy, isFalse);
    });

    test('watchdog: a seek that never answers releases the queue', () async {
      final sent = <double>[];
      final s = StudioSeeker(timeout: const Duration(milliseconds: 30), seek: (v) {
        sent.add(v);
        return Completer<void>().future; // never answers
      });
      s.request(5);
      s.request(9);
      expect(s.busy, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(sent, [5, 9]);
      expect(s.busy, isFalse, reason: 'never locked for good');
    });

    test('a seek that throws does not lock the queue either', () async {
      var calls = 0;
      final s = StudioSeeker(seek: (v) {
        calls++;
        throw StateError('player gone');
      });
      s.request(1);
      await Future<void>.delayed(Duration.zero);
      s.request(2);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      expect(s.busy, isFalse);
    });

    test('scrub: throttled, and flush sends the last target at once', () async {
      final sent = <double>[];
      final s = StudioSeeker(scrubGap: const Duration(seconds: 5), seek: (v) async => sent.add(v));
      s.request(1, scrub: true);
      await Future<void>.delayed(Duration.zero);
      s.request(2, scrub: true);
      s.request(3, scrub: true);
      await Future<void>.delayed(Duration.zero);
      expect(sent, [1], reason: 'inside the gap: waiting');
      s.flush();
      await Future<void>.delayed(Duration.zero);
      expect(sent, [1, 3]);
    });

    test('then runs once the queue is empty; reset ignores the old player', () async {
      final gates = <Completer<void>>[];
      final landed = <double>[];
      var thens = 0;
      final s = StudioSeeker(
        onLanded: landed.add,
        seek: (v) {
          final c = Completer<void>();
          gates.add(c);
          return c.future;
        },
      );
      s.request(1, then: () => thens++);
      s.request(2);
      gates[0].complete();
      await Future<void>.delayed(Duration.zero);
      expect(thens, 0, reason: '2 is still on its way');
      gates[1].complete();
      await Future<void>.delayed(Duration.zero);
      expect(thens, 1);
      expect(landed, [1, 2]);
      s.request(3);
      s.reset();
      gates[2].complete();
      await Future<void>.delayed(Duration.zero);
      expect(landed, [1, 2], reason: 'a late answer from a replaced player is dropped');
      expect(s.busy, isFalse);
    });
  });

  group('timeline drags', () {
    testWidgets('trim end follows the finger while the page feeds the live trim back (it ran away before)', (t) async {
      t.view.physicalSize = const Size(1128, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      double? committed;
      // 1 px = 1 s; clip 0 is 0–500, its end grip at x = 18 + 500
      await t.pumpWidget(layoutHost(_PageLikeHost(edit: StudioEdit.original(1000).split(500), onCommit: (s) => committed = s), scale: 1));
      final box = t.getRect(find.byKey(const ValueKey('studio.timeline')));
      final g = await t.startGesture(Offset(box.left + 18 + 500 + 6, box.top + StudioLanes.ruler + 30));
      for (var i = 0; i < 20; i++) {
        await g.moveBy(const Offset(-3, 0));
        await t.pump();
      }
      await g.up();
      await t.pump();
      expect(committed, isNotNull);
      expect(committed!, closeTo(440, 4), reason: '60 px dragged = 60 s shorter, not 20 moves × the distance so far');
    });

    testWidgets('trim start follows the finger with the live trim fed back', (t) async {
      t.view.physicalSize = const Size(1128, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      double? committed;
      await t.pumpWidget(layoutHost(_PageLikeHost(edit: StudioEdit.original(1000).split(500), onCommit: (s) => committed = s), scale: 1));
      final box = t.getRect(find.byKey(const ValueKey('studio.timeline')));
      final g = await t.startGesture(Offset(box.left + 18 - 6, box.top + StudioLanes.ruler + 30));
      for (var i = 0; i < 20; i++) {
        await g.moveBy(const Offset(4, 0));
        await t.pump();
      }
      await g.up();
      await t.pump();
      expect(committed!, closeTo(80, 4));
    });

    testWidgets('the timeline closing mid-scrub releases the page (the playhead froze for good before)', (t) async {
      var ends = 0;
      final show = ValueNotifier(true);
      addTearDown(show.dispose);
      await t.pumpWidget(layoutHost(
          ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, on, _) => on
                ? StudioTimelineView(edit: StudioEdit.original(100), position: 0, sourceDuration: 100, onScrubStart: () {}, onScrub: (_) {}, onScrubEnd: () => ends++)
                : const SizedBox(),
          ),
          scale: 1));
      final box = t.getRect(find.byKey(const ValueKey('studio.timeline')));
      final g = await t.startGesture(Offset(box.left + 100, box.top + 10));
      await g.moveBy(const Offset(40, 0));
      show.value = false; // a phone opens a tool's panel in the timeline's place
      await t.pump();
      expect(ends, 1);
      await g.up();
      await t.pump();
      expect(ends, 1, reason: 'released once');
    });

    testWidgets('a cancelled pointer ends the scrub and is never taken for a tap', (t) async {
      var ends = 0;
      int? selected = -1;
      await t.pumpWidget(layoutHost(
          StudioTimelineView(
            edit: StudioEdit.original(100),
            position: 0,
            sourceDuration: 100,
            onScrub: (_) {},
            onScrubEnd: () => ends++,
            onSelectClip: (i) => selected = i,
          ),
          scale: 1));
      final box = t.getRect(find.byKey(const ValueKey('studio.timeline')));
      final g = await t.startGesture(Offset(box.left + 100, box.top + StudioLanes.ruler + 30));
      await g.cancel();
      await t.pump();
      expect(ends, 1);
      expect(selected, -1, reason: 'a cancel selects nothing');
    });

    testWidgets('a long fast scrub back and forth never leaves the timeline stuck', (t) async {
      final got = <double>[];
      var ends = 0;
      await t.pumpWidget(layoutHost(
          StudioTimelineView(edit: StudioEdit.original(3600).split(1200).split(2400), position: 0, sourceDuration: 3600, onScrub: got.add, onScrubEnd: () => ends++),
          scale: 1));
      final box = t.getRect(find.byKey(const ValueKey('studio.timeline')));
      for (var round = 0; round < 5; round++) {
        final g = await t.startGesture(Offset(box.left + 40, box.top + 10));
        for (var i = 0; i < 60; i++) {
          await g.moveBy(Offset(i.isEven ? 25 : -12, 0));
        }
        await g.up();
        await t.pump();
      }
      expect(ends, 5);
      got.clear();
      await t.tapAt(Offset(box.left + box.width / 2, box.top + 10));
      expect(got, isNotEmpty, reason: 'still answers after the long scrub');
    });
  });

  testWidgets('the timeline still lays out on every screen size', (t) async {
    await expectNoLayoutErrors(
      t,
      () => StudioTimelineView(edit: StudioEdit.original(600).split(200), position: 120, sourceDuration: 600, selectedClip: 0, onScrub: (_) {}),
    );
  });
}
