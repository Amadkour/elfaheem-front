// The live room's self-view (D-092) and the stage-tap fix: SelfViewTile / SelfViewLayer / SelfViewOptions /
// SelfViewChip and the pre-join preview card in both shapes at 320×640 and 1400×900, Arabic and English, text scale
// 1.3 (no overflow); then the behaviour — a tap beside the box reaches the stage, the box takes its own tap, drag +
// snap, long-press, the hidden chip — and LiveVideoShell: the renderer's own tap detector (livekit's
// VideoTrackRenderer wraps a LOCAL track in one) no longer wins the tap, and a parent rebuild no longer rebuilds the
// renderer (the rebuild count the room's once-a-second clock used to cost).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/live/live_self_view.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/prejoin_layout.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_palette.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_video_view.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/self_view_pip.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _keep = SelfViewKeepOut(base: EdgeInsets.fromLTRB(12, 12, 12, 58), topRight: 90);

Widget _fakeCamera() => const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF6B5A4E), Color(0xFF26252E)]),
      ),
    );

Widget _stage({
  SelfViewPrefs prefs = const SelfViewPrefs(),
  bool hidden = false,
  bool chrome = true,
  bool micOn = true,
  bool handUp = false,
  bool video = true,
  VoidCallback? onStageTap,
  VoidCallback? onBoxTap,
  VoidCallback? onLongPress,
  VoidCallback? onShow,
  void Function(SelfViewSide, double)? onMoved,
}) =>
    Builder(builder: (context) {
      LivePalette.sync(context);
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
            child: SelfViewLayer(
              prefs: prefs,
              keepOut: _keep,
              hidden: hidden,
              onShow: onShow,
              onTap: onBoxTap,
              onLongPress: onLongPress,
              onMoved: onMoved ?? (_, _) {},
              tile: SelfViewTile(
                shape: prefs.shape,
                name: 'أحمد حمدي مدكور',
                video: video ? _fakeCamera() : null,
                micOn: micOn,
                handUp: handUp,
                showChrome: chrome,
                onMenu: () {},
              ),
            ),
          ),
        ]),
      );
    });

void main() {
  group('layout', () {
    for (final shape in SelfViewShape.values) {
      for (final size in SelfViewSize.values) {
        testWidgets('${shape.name} ${size.name}', (tester) async {
          await expectNoLayoutErrors(tester, () => _stage(prefs: SelfViewPrefs(shape: shape, size: size)));
        });
      }
    }

    testWidgets('muted, hand up, no picture yet, chrome hidden, top-left', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _stage(
          prefs: const SelfViewPrefs(side: SelfViewSide.left, y: 0),
          micOn: false,
          handUp: true,
          video: false,
          chrome: false,
        ),
      );
      await expectNoLayoutErrors(
        tester,
        () => _stage(prefs: const SelfViewPrefs(shape: SelfViewShape.circle), micOn: false, handUp: true),
      );
    });

    testWidgets('the hidden chip', (tester) async {
      await expectNoLayoutErrors(tester, () => _stage(hidden: true));
      await expectNoLayoutErrors(tester, () => _stage(hidden: true, prefs: const SelfViewPrefs(side: SelfViewSide.left, y: 0.4)));
    });

    testWidgets('the options sheet', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => Builder(builder: (context) {
          LivePalette.sync(context);
          return ColoredBox(
            color: LivePalette.surfaceHi,
            child: SelfViewOptions(
              prefs: const SelfViewPrefs(shape: SelfViewShape.circle, aloneOnStage: true),
              onChanged: (_) {},
              onHide: () {},
              onToStage: () {},
            ),
          );
        }),
      );
    });

    testWidgets('the pre-join preview in both shapes, with the shape switch', (tester) async {
      for (final shape in SelfViewShape.values) {
        await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
            child: PreJoinPreviewCard(
              preview: _fakeCamera(),
              camOn: true,
              micOn: true,
              hasCamera: true,
              userName: 'Ahmed Hamdy',
              shape: shape,
              onShape: (_) {},
            ),
          ),
        );
      }
    });
  });

  group('behaviour', () {
    Future<void> pump(WidgetTester tester, Widget w) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(layoutHost(w, scale: 1));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a tap beside the box reaches the stage; the box takes its own tap', (tester) async {
      var stage = 0, box = 0;
      await pump(tester, _stage(onStageTap: () => stage++, onBoxTap: () => box++));
      await tester.tapAt(const Offset(60, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(stage, 1);
      expect(box, 0);
      await tester.tap(find.byKey(const ValueKey('self_view.box')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(box, 1);
      expect(stage, 1);
    });

    testWidgets('a drag to the left half settles on the left edge and is reported', (tester) async {
      (SelfViewSide, double)? moved;
      await pump(tester, _stage(onMoved: (s, y) => moved = (s, y)));
      final box = find.byKey(const ValueKey('self_view.box'));
      final before = tester.getTopLeft(box);
      expect(before.dx, greaterThan(200)); // starts bottom-right
      await tester.drag(box, const Offset(-260, -200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(moved?.$1, SelfViewSide.left);
      final after = tester.getTopLeft(box);
      expect(after.dx, 12); // the keep-out's left edge
    });

    testWidgets('long-press opens the options; the hidden chip brings the box back', (tester) async {
      var menu = 0, shown = 0;
      await pump(tester, _stage(onLongPress: () => menu++));
      await tester.longPress(find.byKey(const ValueKey('self_view.box')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(menu, 1);

      await pump(tester, _stage(hidden: true, onShow: () => shown++));
      expect(find.byKey(const ValueKey('self_view.box')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('self_view.hidden_chip')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(shown, 1);
    });
  });

  group('LiveVideoShell (the renderer wrapper)', () {
    // A stand-in for livekit's VideoTrackRenderer around a LOCAL track on a phone: its own onTapDown (focus) and
    // scale (zoom) detector.
    Widget sdkLikeRenderer(VoidCallback onInnerTap) => GestureDetector(
          onTapDown: (_) => onInnerTap(),
          onScaleStart: (_) {},
          onScaleUpdate: (_) {},
          child: const ColoredBox(color: Color(0xFF334455), child: SizedBox.expand()),
        );

    testWidgets('without the shell the renderer wins the tap (the bug); with it the stage gets it', (tester) async {
      var stage = 0, inner = 0;
      Widget host(bool shell) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => stage++,
            child: shell
                ? LiveVideoShell(identity: const ['cam'], builder: (_) => sdkLikeRenderer(() => inner++))
                : sdkLikeRenderer(() => inner++),
          );

      await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: host(false)));
      await tester.tapAt(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(inner, 1);
      expect(stage, 0, reason: 'the inner detector swallowed the stage tap (the reported bug)');

      await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: host(true)));
      await tester.tapAt(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(stage, 1);
      expect(inner, 1, reason: 'no focus call, no exception per tap');
    });

    testWidgets('a parent rebuilding every second does not rebuild the renderer', (tester) async {
      var builds = 0;
      final tick = ValueNotifier<int>(0);
      final identity = ValueNotifier<String>('track-a');
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: ListenableBuilder(
          listenable: Listenable.merge([tick, identity]),
          builder: (_, _) => Column(children: [
            Text('${tick.value}'),
            Expanded(
              child: LiveVideoShell(
                identity: [identity.value, 'cover'],
                builder: (_) {
                  builds++;
                  return const SizedBox.expand();
                },
              ),
            ),
          ]),
        ),
      ));
      for (var i = 0; i < 30; i++) {
        tick.value++;
        await tester.pump(const Duration(seconds: 1));
      }
      expect(builds, 1, reason: '30 parent rebuilds, one renderer build');
      identity.value = 'track-b';
      await tester.pump();
      expect(builds, 2, reason: 'a new track builds a new renderer');
      tick.dispose();
      identity.dispose();
    });
  });
}
