// The self-view rules (D-092, lib/features/live/live_self_view.dart): where my camera goes, how big the box
// is, where a drop settles, what is remembered, and the controls bar's show / hide rule.
import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_education_app/features/live/live_self_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('selfViewSpot', () {
    test('camera off or the room minimized: nothing', () {
      expect(selfViewSpot(camOn: false, stageHasOther: true), SelfViewSpot.none);
      expect(selfViewSpot(camOn: true, stageHasOther: true, parked: true), SelfViewSpot.none);
    });

    test('someone else on the stage: the box, never the stage too', () {
      expect(selfViewSpot(camOn: true, stageHasOther: true), SelfViewSpot.box);
      // "Fill the screen while alone" does not apply when I am not alone.
      expect(selfViewSpot(camOn: true, stageHasOther: true, aloneOnStage: true), SelfViewSpot.box);
    });

    test('alone: the box by default, the stage when asked', () {
      expect(selfViewSpot(camOn: true, stageHasOther: false), SelfViewSpot.box);
      expect(selfViewSpot(camOn: true, stageHasOther: false, aloneOnStage: true), SelfViewSpot.stage);
    });

    test('swapped: the stage (the stage content goes to the box)', () {
      expect(selfViewSpot(camOn: true, stageHasOther: true, swapped: true), SelfViewSpot.stage);
    });

    test('hidden: the chip, except where I fill the stage anyway', () {
      expect(selfViewSpot(camOn: true, stageHasOther: true, hidden: true), SelfViewSpot.hiddenChip);
      expect(selfViewSpot(camOn: true, stageHasOther: false, hidden: true), SelfViewSpot.hiddenChip);
      expect(selfViewSpot(camOn: true, stageHasOther: false, hidden: true, aloneOnStage: true), SelfViewSpot.stage);
      expect(selfViewSpot(camOn: true, stageHasOther: true, hidden: true, swapped: true), SelfViewSpot.stage);
    });
  });

  group('selfViewBoxSize', () {
    const phone = Size(390, 640);
    const desk = Size(1100, 700);

    test('portrait box on phones, 16:9 on wide stages, circles are round', () {
      final p = selfViewBoxSize(shape: SelfViewShape.box, size: SelfViewSize.small, stage: phone);
      expect(p, const Size(96, 128));
      final d = selfViewBoxSize(shape: SelfViewShape.box, size: SelfViewSize.medium, stage: desk);
      expect(d.width / d.height, closeTo(16 / 9, 0.02));
      final c = selfViewBoxSize(shape: SelfViewShape.circle, size: SelfViewSize.medium, stage: phone);
      expect(c.width, c.height);
      expect(c.width, 120);
    });

    test('medium is bigger than small', () {
      for (final shape in SelfViewShape.values) {
        for (final stage in [phone, desk]) {
          final s = selfViewBoxSize(shape: shape, size: SelfViewSize.small, stage: stage);
          final m = selfViewBoxSize(shape: shape, size: SelfViewSize.medium, stage: stage);
          expect(m.width, greaterThan(s.width));
        }
      }
    });

    test('a small stage scales the box down (≤ 42 % wide, ≤ 34 % high)', () {
      const tiny = Size(240, 260);
      final b = selfViewBoxSize(shape: SelfViewShape.box, size: SelfViewSize.medium, stage: tiny);
      expect(b.width, lessThanOrEqualTo(tiny.width * 0.42 + 0.01));
      expect(b.height, lessThanOrEqualTo(tiny.height * 0.34 + 0.01));
      expect(b.width / b.height, closeTo(124 / 165, 0.01));
    });
  });

  group('position and snapping', () {
    const stage = Size(400, 700);
    const box = Size(96, 128);
    const keep = SelfViewKeepOut(base: EdgeInsets.fromLTRB(12, 12, 12, 58), topRight: 120);

    test('the box hugs the chosen side, the badge column pushes it down on the right only', () {
      final r0 = selfViewOffset(stage: stage, box: box, keepOut: keep, side: SelfViewSide.right, y: 0);
      expect(r0, const Offset(400 - 12 - 96, 132));
      final l0 = selfViewOffset(stage: stage, box: box, keepOut: keep, side: SelfViewSide.left, y: 0);
      expect(l0, const Offset(12, 12));
      final r1 = selfViewOffset(stage: stage, box: box, keepOut: keep, side: SelfViewSide.right, y: 1);
      expect(r1.dy, 700 - 58 - 128);
    });

    test('a drop goes to the nearer side; near an end it snaps into the corner', () {
      final left = selfViewSnap(stage: stage, box: box, keepOut: keep, topLeft: const Offset(60, 300));
      expect(left.side, SelfViewSide.left);
      expect(left.y, greaterThan(0));
      expect(left.y, lessThan(1));
      final corner = selfViewSnap(stage: stage, box: box, keepOut: keep, topLeft: const Offset(260, 500));
      expect(corner, (side: SelfViewSide.right, y: 1.0));
      final top = selfViewSnap(stage: stage, box: box, keepOut: keep, topLeft: const Offset(20, 30));
      expect(top, (side: SelfViewSide.left, y: 0.0));
    });

    test('a fling carries the box across', () {
      final flung = selfViewSnap(
        stage: stage,
        box: box,
        keepOut: keep,
        topLeft: const Offset(120, 300),
        velocity: const Offset(1800, 0),
      );
      expect(flung.side, SelfViewSide.right);
    });

    test('the settled fraction lands back where the box was dropped', () {
      final s = selfViewSnap(stage: stage, box: box, keepOut: keep, topLeft: const Offset(30, 300));
      final at = selfViewOffset(stage: stage, box: box, keepOut: keep, side: s.side, y: s.y);
      expect(at.dy, closeTo(300, 0.5));
    });

    test('a shorter stage (keyboard, rotation) keeps the side and the fraction, inside the stage', () {
      const short = Size(400, 300);
      final at = selfViewOffset(stage: short, box: box, keepOut: keep, side: SelfViewSide.right, y: 1);
      expect(at.dy + box.height, lessThanOrEqualTo(short.height));
      expect(at.dy, greaterThanOrEqualTo(0));
    });

    test('dragging is clamped to the stage', () {
      expect(selfViewDragClamp(stage: stage, box: box, topLeft: const Offset(-50, 900)), const Offset(0, 700 - 128));
    });
  });

  group('prefs', () {
    test('json round trip; garbage falls back to the defaults', () {
      const p = SelfViewPrefs(
        shape: SelfViewShape.circle,
        size: SelfViewSize.medium,
        side: SelfViewSide.left,
        y: 0.25,
        aloneOnStage: true,
      );
      expect(SelfViewPrefs.fromJson(jsonDecode(jsonEncode(p.toJson()))), p);
      expect(SelfViewPrefs.fromJson('nope'), const SelfViewPrefs());
      expect(SelfViewPrefs.fromJson({'shape': 'hexagon', 'y': 7}), const SelfViewPrefs(y: 1));
    });

    test('the store loads what was saved and saves what changes', () async {
      SharedPreferences.setMockInitialValues({
        SelfViewStore.storageKey: jsonEncode(const SelfViewPrefs(shape: SelfViewShape.circle).toJson()),
      });
      final store = SelfViewStore.instance..resetForTest();
      await store.load();
      expect(store.value.shape, SelfViewShape.circle);
      await store.update(store.value.copyWith(size: SelfViewSize.medium, side: SelfViewSide.left));
      final sp = await SharedPreferences.getInstance();
      final saved = SelfViewPrefs.fromJson(jsonDecode(sp.getString(SelfViewStore.storageKey)!));
      expect(saved.size, SelfViewSize.medium);
      expect(saved.side, SelfViewSide.left);
      expect(saved.shape, SelfViewShape.circle);
      store.resetForTest();
    });
  });

  group('the controls bar', () {
    test('a tap shows a hidden bar and restarts its timer', () {
      expect(liveControlsAfterTap(visible: false, autoHide: true), (visible: true, restartTimer: true));
      expect(liveControlsAfterTap(visible: false, autoHide: false), (visible: true, restartTimer: true));
    });

    test('a tap hides a shown bar only where it auto-hides', () {
      expect(liveControlsAfterTap(visible: true, autoHide: true), (visible: false, restartTimer: false));
      expect(liveControlsAfterTap(visible: true, autoHide: false), (visible: true, restartTimer: true));
    });

    test('the idle timer hides it only where it auto-hides', () {
      expect(liveControlsAfterIdle(visible: true, autoHide: true), isFalse);
      expect(liveControlsAfterIdle(visible: true, autoHide: false), isTrue);
      expect(liveControlsAfterIdle(visible: false, autoHide: true), isFalse);
    });
  });
}
