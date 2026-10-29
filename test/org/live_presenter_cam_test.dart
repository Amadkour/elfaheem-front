// The presenter's camera over a share (D-094, lib/features/shared/live/live_presenter_cam.dart): which camera floats
// in the box and when, the bubbles inside the video budget, the unit's size, where it rests (never on the self-view)
// and what is remembered.
import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_education_app/features/shared/live/live_presenter_cam.dart';
import 'package:flutter_education_app/features/shared/live/live_self_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keep = SelfViewKeepOut(base: EdgeInsets.fromLTRB(12, 12, 12, 58));

void main() {
  group('presenterCamPlan', () {
    test('no share or board on the stage: nothing (the thumbnail strip is in charge)', () {
      expect(presenterCamPlan(presenter: null, me: 'me', cams: const [LiveCamFacts('t')]), PresenterCamPlan.none);
      expect(presenterCamPlan(presenter: '', me: 'me', cams: const [LiveCamFacts('t')]), PresenterCamPlan.none);
    });

    test('a viewer: the presenter\'s camera in the box', () {
      final plan = presenterCamPlan(presenter: 'teacher', me: 'student', cams: const [LiveCamFacts('teacher')]);
      expect(plan.main, 'teacher');
      expect(plan.bubbles, isEmpty);
      expect(plan.more, 0);
      expect(plan.any, isTrue);
    });

    test('the presenter themself sees nothing new (their own self-view)', () {
      final plan = presenterCamPlan(
        presenter: 'teacher',
        me: 'teacher',
        cams: const [LiveCamFacts('teacher'), LiveCamFacts('s1'), LiveCamFacts('s2')],
      );
      expect(plan, PresenterCamPlan.none);
    });

    test('the presenter\'s camera off: no box (never an empty one)', () {
      final plan = presenterCamPlan(presenter: 'teacher', me: 'student', cams: const [LiveCamFacts('teacher', camOn: false)]);
      expect(plan.main, isNull);
      expect(plan.any, isFalse);
    });

    test('presenter off, others on: bubbles only', () {
      final plan = presenterCamPlan(
        presenter: 'teacher',
        me: 'me',
        cams: const [LiveCamFacts('teacher', camOn: false), LiveCamFacts('s1'), LiveCamFacts('s2')],
      );
      expect(plan.main, isNull);
      expect(plan.bubbles, ['s1', 's2']);
    });

    test('suppressed (minimized without video, my camera on the stage): nothing', () {
      expect(
        presenterCamPlan(presenter: 'teacher', me: 'me', cams: const [LiveCamFacts('teacher')], suppressed: true),
        PresenterCamPlan.none,
      );
    });

    test('my own camera is never a bubble, duplicates are dropped', () {
      final plan = presenterCamPlan(
        presenter: 'teacher',
        me: 'me',
        cams: const [LiveCamFacts('teacher'), LiveCamFacts('me'), LiveCamFacts('s1'), LiveCamFacts('teacher')],
      );
      expect(plan.main, 'teacher');
      expect(plan.bubbles, ['s1']);
    });

    test('the video budget: the share and the box count; the rest is "+n"', () {
      const cams = [
        LiveCamFacts('teacher'),
        LiveCamFacts('s1'),
        LiveCamFacts('s2'),
        LiveCamFacts('s3'),
        LiveCamFacts('s4'),
        LiveCamFacts('s5'),
      ];
      // A phone (4): share + box + 2 bubbles.
      final phone = presenterCamPlan(presenter: 'teacher', me: 'me', cams: cams, budget: 4);
      expect(phone.bubbles, ['s1', 's2']);
      expect(phone.more, 3);
      // A desktop (9): at most 3 bubbles all the same.
      final desk = presenterCamPlan(presenter: 'teacher', me: 'me', cams: cams, budget: 9);
      expect(desk.bubbles, ['s1', 's2', 's3']);
      expect(desk.more, 2);
      // No room for any bubble: only "+n" next to the box.
      final tiny = presenterCamPlan(presenter: 'teacher', me: 'me', cams: cams, budget: 2);
      expect(tiny.main, 'teacher');
      expect(tiny.bubbles, isEmpty);
      expect(tiny.more, 5);
      // No box and no room: nothing at all (never "+n" alone).
      expect(
        presenterCamPlan(presenter: 'teacher', me: 'me', cams: const [LiveCamFacts('s1')], budget: 1),
        PresenterCamPlan.none,
      );
    });

    test('a pinned camera takes the box; the presenter becomes the first bubble', () {
      final plan = presenterCamPlan(
        presenter: 'teacher',
        me: 'me',
        cams: const [LiveCamFacts('teacher'), LiveCamFacts('s1'), LiveCamFacts('s2')],
        pinned: 's2',
      );
      expect(plan.main, 's2');
      expect(plan.bubbles, ['teacher', 's1']);
    });

    test('a pinned camera that went off: back to the presenter', () {
      final plan = presenterCamPlan(
        presenter: 'teacher',
        me: 'me',
        cams: const [LiveCamFacts('teacher'), LiveCamFacts('s1', camOn: false)],
        pinned: 's1',
      );
      expect(plan.main, 'teacher');
      expect(plan.bubbles, isEmpty);
    });
  });

  group('presenterDockSize', () {
    test('box alone, bubbles alone, both', () {
      const box = Size(96, 128);
      expect(presenterDockSize(box: box, bubbles: 0, bubble: 44), box);
      expect(presenterDockSize(box: Size.zero, bubbles: 2, bubble: 44), const Size(94, 44));
      expect(presenterDockSize(box: box, bubbles: 1, bubble: 44), const Size(96, 128 + kPresenterRowGap + 44));
      // A row wider than the box widens the unit.
      expect(presenterDockSize(box: box, bubbles: 3, bubble: 44).width, 3 * 44 + 2 * kPresenterBubbleGap);
    });

    test('bubble size follows the stage width', () {
      expect(presenterBubbleSize(390), 44);
      expect(presenterBubbleSize(1440), 52);
    });
  });

  group('presenterCamSpot', () {
    const stage = Size(390, 640);
    const unit = Size(96, 128);
    const self = SelfViewPrefs(); // right, bottom

    Rect rectOf(({SelfViewSide side, double y}) s) =>
        selfViewOffset(stage: stage, box: unit, keepOut: _keep, side: s.side, y: s.y) & unit;

    test('never moved: opposite the self-view, at the remembered height', () {
      final s = presenterCamSpot(
        stage: stage,
        unit: unit,
        keepOut: _keep,
        side: null,
        y: 1,
        selfSide: SelfViewSide.right,
        avoid: selfViewRect(stage: stage, prefs: self, keepOut: _keep),
      );
      expect(s.side, SelfViewSide.left);
      expect(s.y, 1);
      expect(rectOf(s).overlaps(selfViewRect(stage: stage, prefs: self, keepOut: _keep)), isFalse);
    });

    test('dropped onto the self-view: the other end of that side', () {
      final avoid = selfViewRect(stage: stage, prefs: self, keepOut: _keep);
      final s = presenterCamSpot(
        stage: stage,
        unit: unit,
        keepOut: _keep,
        side: SelfViewSide.right,
        y: 1,
        selfSide: SelfViewSide.right,
        avoid: avoid,
      );
      expect(s, (side: SelfViewSide.right, y: 0.0));
      expect(rectOf(s).overlaps(avoid), isFalse);
    });

    test('a stage too short for two boxes on one side: the other side', () {
      const short = Size(390, 300);
      final avoid = selfViewRect(stage: short, prefs: self, keepOut: _keep);
      final s = presenterCamSpot(
        stage: short,
        unit: unit,
        keepOut: _keep,
        side: SelfViewSide.right,
        y: 1,
        selfSide: SelfViewSide.right,
        avoid: avoid,
      );
      expect(s.side, SelfViewSide.left);
    });

    test('no self-view: the remembered spot as it is', () {
      final s = presenterCamSpot(
        stage: stage,
        unit: unit,
        keepOut: _keep,
        side: SelfViewSide.right,
        y: 0.4,
        selfSide: SelfViewSide.right,
      );
      expect(s, (side: SelfViewSide.right, y: 0.4));
    });

    test('the bubble row sits towards the stage centre', () {
      expect(presenterRowAbove(1), isTrue);
      expect(presenterRowAbove(0), isFalse);
    });

    test('the hidden self-view chip is kept clear of too', () {
      final chip = selfViewChipRect(stage: stage, prefs: self, keepOut: _keep);
      expect(chip.right, closeTo(stage.width - 12, 0.01));
      expect(chip.height, 40);
    });
  });

  group('PresenterCamPrefs', () {
    test('round trip and damaged values', () {
      const p = PresenterCamPrefs(shape: SelfViewShape.circle, size: SelfViewSize.medium, side: SelfViewSide.right, y: 0.3);
      expect(PresenterCamPrefs.fromJson(jsonDecode(jsonEncode(p.toJson()))), p);
      expect(PresenterCamPrefs.fromJson(null), const PresenterCamPrefs());
      expect(PresenterCamPrefs.fromJson({'shape': 'star', 'y': 'x'}), const PresenterCamPrefs());
      // Never moved: no side is stored.
      expect(const PresenterCamPrefs().toJson().containsKey('side'), isFalse);
      expect(PresenterCamPrefs.fromJson({'y': 7}).y, 1.0);
    });

    test('the store saves and loads', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PresenterCamStore.instance..resetForTest();
      await store.update(const PresenterCamPrefs(side: SelfViewSide.left, y: 0));
      store.resetForTest();
      await store.load();
      expect(store.value, const PresenterCamPrefs(side: SelfViewSide.left, y: 0));
      store.resetForTest();
    });
  });
}
