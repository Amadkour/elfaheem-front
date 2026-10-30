// The presenter's camera over a share (D-094, widgets/presenter_cam_box.dart): the box in both shapes and sizes, with
// bubbles and "+n", bubbles alone, the minimized pill, at 320×640 and 1400×900, Arabic and English, text scale 1.3 (no
// overflow); then the behaviour — a tap beside the box reaches the stage (the bars toggle), the box takes its own tap,
// a bubble pins, "–" minimizes, the pill brings it back, a drop never rests on my self-view.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/live/live_presenter_cam.dart';
import 'package:flutter_education_app/features/shared/live/live_self_view.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_palette.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/presenter_cam_box.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _keep = SelfViewKeepOut(base: EdgeInsets.fromLTRB(12, 12, 12, 84), topRight: 90);

Widget _cam() => const DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF6B5A4E), Color(0xFF26252E)])),
    );

PresenterCamItem _item(String id, String name, {bool video = true, bool micOn = true, bool hand = false}) =>
    PresenterCamItem(id: id, name: name, video: video ? _cam() : null, micOn: micOn, handUp: hand, speaking: id == 't');

Widget _stage({
  PresenterCamPrefs prefs = const PresenterCamPrefs(),
  bool main = true,
  int bubbles = 0,
  int more = 0,
  bool collapsed = false,
  bool chrome = true,
  bool hand = false,
  bool selfView = true,
  VoidCallback? onStageTap,
  VoidCallback? onTap,
  VoidCallback? onCollapse,
  VoidCallback? onExpand,
  ValueChanged<String>? onPin,
  void Function(SelfViewSide, double)? onMoved,
  double? shareAspect,
}) =>
    Builder(builder: (context) {
      LivePalette.sync(context);
      const self = SelfViewPrefs();
      return ColoredBox(
        color: LivePalette.bg,
        child: Stack(fit: StackFit.expand, children: [
          GestureDetector(
            key: const ValueKey('test.stage'),
            behavior: HitTestBehavior.opaque,
            onTap: onStageTap,
            child: const SizedBox.expand(),
          ),
          Positioned.fill(
            child: PresenterCamLayer(
              prefs: prefs,
              keepOut: _keep,
              selfSide: self.side,
              avoid: selfView ? (stage) => selfViewRect(stage: stage, prefs: self, keepOut: _keep) : null,
              main: main ? _item('t', 'د. منى السيد عبد الرحمن', hand: hand) : null,
              bubbles: [
                for (var i = 0; i < bubbles; i++) _item('s$i', 'Student number $i', micOn: i.isEven, video: i != 1, hand: hand),
              ],
              more: more,
              collapsed: collapsed,
              showChrome: chrome,
              onTap: onTap,
              onMenu: () {},
              onCollapse: onCollapse ?? () {},
              onExpand: onExpand,
              onPin: onPin,
              onMore: () {},
              onMoved: onMoved ?? (_, _) {},
              content: shareAspect == null ? null : (stage) => shareContentRect(stage, shareAspect),
            ),
          ),
        ]),
      );
    });

void main() {
  group('layout', () {
    for (final shape in SelfViewShape.values) {
      for (final size in SelfViewSize.values) {
        testWidgets('${shape.name} ${size.name} with bubbles', (tester) async {
          await expectNoLayoutErrors(
            tester,
            () => _stage(prefs: PresenterCamPrefs(shape: shape, size: size), bubbles: 2, more: 4, hand: true),
          );
        });
      }
    }

    testWidgets('box alone, top-right, bar hidden', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _stage(prefs: const PresenterCamPrefs(side: SelfViewSide.right, y: 0), chrome: false),
      );
    });

    testWidgets('bubbles alone (the presenter\'s camera off)', (tester) async {
      await expectNoLayoutErrors(tester, () => _stage(main: false, bubbles: 3, more: 2));
    });

    testWidgets('minimized to a name', (tester) async {
      await expectNoLayoutErrors(tester, () => _stage(collapsed: true, bubbles: 2, more: 1));
      await expectNoLayoutErrors(tester, () => _stage(collapsed: true, prefs: const PresenterCamPrefs(side: SelfViewSide.right, y: 0.3)));
    });
  });

  group('over the shared picture (D-105)', () {
    for (final aspect in [540 / 1170, 16 / 9]) {
      testWidgets('aspect ${aspect.toStringAsFixed(2)}: no overflow, with bubbles', (tester) async {
        await expectNoLayoutErrors(tester, () => _stage(shareAspect: aspect, bubbles: 2, more: 1));
      });
    }

    testWidgets('a portrait share on a wide stage: the box sits on the picture, not in the side bars', (tester) async {
      tester.view.physicalSize = const Size(1280, 660);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(layoutHost(_stage(shareAspect: 540 / 1170)));
      await tester.pumpAndSettle();
      final box = tester.getRect(find.byKey(const ValueKey('presenter_cam.box')));
      final content = shareContentRect(const Size(1280, 660), 540 / 1170)!;
      expect(content.contains(box.topLeft) && content.contains(box.bottomRight), isTrue, reason: '$box in $content');
    });
  });

  group('behaviour', () {
    testWidgets('nothing to show: nothing drawn, the stage keeps every tap', (tester) async {
      var stage = 0;
      await tester.pumpWidget(layoutHost(_stage(main: false, onStageTap: () => stage++)));
      expect(find.byKey(const ValueKey('presenter_cam.box')), findsNothing);
      await tester.tapAt(const Offset(60, 400));
      expect(stage, 1);
    });

    testWidgets('a tap beside the box reaches the stage; the box takes its own', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      var stage = 0, box = 0;
      await tester.pumpWidget(layoutHost(_stage(onStageTap: () => stage++, onTap: () => box++)));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const ValueKey('presenter_cam.box')));
      // Unmoved: opposite my self-view (which is on the right).
      expect(rect.left, lessThan(195));
      await tester.tapAt(rect.center);
      expect((stage, box), (0, 1));
      await tester.tapAt(const Offset(200, 300));
      expect((stage, box), (1, 1));
    });

    testWidgets('a bubble pins, "–" minimizes, the pill brings it back', (tester) async {
      String? pinned;
      var collapsed = 0, expanded = 0;
      await tester.pumpWidget(layoutHost(_stage(bubbles: 2, onPin: (id) => pinned = id, onCollapse: () => collapsed++)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('presenter_cam.bubble.s1')));
      expect(pinned, 's1');
      await tester.tap(find.byKey(const ValueKey('presenter_cam.collapse')));
      expect(collapsed, 1);
      await tester.pumpWidget(layoutHost(_stage(collapsed: true, onExpand: () => expanded++)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('presenter_cam.box')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('presenter_cam.pill')));
      expect(expanded, 1);
    });

    testWidgets('a drop onto my self-view moves on to a free spot', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      ({SelfViewSide side, double y})? moved;
      await tester.pumpWidget(layoutHost(_stage(onMoved: (s, y) => moved = (side: s, y: y))));
      await tester.pumpAndSettle();
      final box = find.byKey(const ValueKey('presenter_cam.box'));
      // Drag it to the bottom-right corner, where my self-view rests.
      await tester.drag(box, const Offset(400, 400));
      await tester.pumpAndSettle();
      expect(moved, isNotNull);
      expect(moved!.side, SelfViewSide.right);
      expect(moved!.y, 0.0);
    });

    testWidgets('chrome hidden: no "–" button', (tester) async {
      await tester.pumpWidget(layoutHost(_stage(chrome: false)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('presenter_cam.collapse')), findsNothing);
    });
  });
}
