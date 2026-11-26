// Depth and motion pieces (D-620 / D-621): the subtle list tilt, the flip, the parallax cover, the rolling figure,
// the expanding card, the slide-in panel and the sheet's motion. Every one is pumped through the layout harness,
// checked still under Reduce motion, and turned around mid-way (no exception, it carries on from where it is).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _app(Widget child, {bool reduce = false}) => layoutHost(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: child,
        ),
      ),
      scale: 1,
    );

/// A host that flips a bool with a button, for the widgets driven by a property.
class _Toggle extends StatefulWidget {
  const _Toggle({required this.builder});

  final Widget Function(bool on) builder;

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool on = false;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        TextButton(onPressed: () => setState(() => on = !on), child: const Text('toggle')),
        widget.builder(on),
      ]);
}

/// Counts the layouts of its child (a moving part must repaint, never lay out again).
class _LayoutProbe extends SingleChildRenderObjectWidget {
  const _LayoutProbe({super.child});

  static int layouts = 0;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLayoutProbe();
}

class _RenderLayoutProbe extends RenderProxyBox {
  @override
  void performLayout() {
    _LayoutProbe.layouts++;
    super.performLayout();
  }
}

/// Taps the host's button and pumps the frame that starts the animation (the clock runs from the next one).
Future<void> _tapToggle(WidgetTester t) async {
  await t.tap(find.text('toggle'));
  await t.pump();
}

Widget _flip(bool on) => SizedBox(
      width: 260,
      child: AppFlip3D(
        flipped: on,
        front: const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Question'))),
        back: const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Answer: photosynthesis'))),
      ),
    );

Widget _expand(bool on) => AppExpandCard(
      expanded: on,
      header: const Text('Lesson 1 · Cells'),
      child: const Text('Every living thing is made of cells. A long body text that wraps on a phone at 320 px.'),
    );

Widget _slide(bool on) => SizedBox(
      height: 160,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AppSlideIn(
          visible: on,
          child: const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Correct'))),
        ),
      ),
    );

Matrix4 _matrixOf(WidgetTester t, Finder face) =>
    t.widget<Transform>(find.ancestor(of: face, matching: find.byType(Transform)).first).transform;

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppCountUp.resetMemory();
  });

  group('layout (320 x 640 and 1400 x 900, ar / en, text x 1.3)', () {
    testWidgets('AppFlip3D', (t) async {
      await expectNoLayoutErrors(t, () => _Toggle(builder: _flip), act: _tapToggle);
    });

    testWidgets('AppExpandCard', (t) async {
      await expectNoLayoutErrors(t, () => _Toggle(builder: _expand), act: _tapToggle);
    });

    testWidgets('AppSlideIn', (t) async {
      await expectNoLayoutErrors(t, () => _Toggle(builder: _slide), act: _tapToggle);
    });

    testWidgets('AppParallaxImage in a list and on its own', (t) async {
      await expectNoLayoutErrors(
        t,
        () => ListView(children: [
          for (var i = 0; i < 6; i++)
            SizedBox(height: 140, child: AppParallaxImage(image: ColoredBox(color: Colors.teal.shade200))),
          const AspectRatio(aspectRatio: 16 / 9, child: AppParallaxImage(image: ColoredBox(color: Colors.orange))),
        ]),
        act: (t) => t.drag(find.byType(ListView), const Offset(0, -200)),
      );
      await expectNoLayoutErrors(t, () => const SizedBox(height: 120, child: AppParallaxImage(image: Placeholder())));
    });

    testWidgets('AppOdometer and AppTilt.subtle', (t) async {
      await expectNoLayoutErrors(
        t,
        () => _Toggle(
          builder: (on) => AppTilt.subtle(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AppOdometer(on ? '12,480 pts' : '9,960 pts', style: const TextStyle(fontSize: 28)),
              ),
            ),
          ),
        ),
        act: (t) async {
          await _tapToggle(t);
          await t.pump(const Duration(milliseconds: 120));
        },
      );
    });
  });

  group('AppTilt.subtle', () {
    testWidgets('touch is a press depth only, and moving it lays nothing out', (t) async {
      await t.pumpWidget(_app(ListView(children: [
        for (var i = 0; i < 12; i++)
          Padding(
            padding: const EdgeInsets.all(8),
            child: AppTilt.subtle(
              key: ValueKey(i),
              child: const _LayoutProbe(child: SizedBox(height: 120, child: ColoredBox(color: Colors.blue))),
            ),
          ),
      ])));
      Matrix4 m() => t
          .widget<Transform>(find.descendant(of: find.byKey(const ValueKey(1)), matching: find.byType(Transform)).first)
          .transform;
      expect(m(), Matrix4.identity());
      _LayoutProbe.layouts = 0;
      final g = await t.startGesture(t.getTopLeft(find.byKey(const ValueKey(1))) + const Offset(30, 20));
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      final pressed = m();
      expect(pressed == Matrix4.identity(), isFalse);
      expect(pressed.entry(0, 2), 0, reason: 'no turn around Y on touch');
      expect(pressed.entry(1, 2), 0, reason: 'no turn around X on touch');
      expect(pressed.entry(0, 0), closeTo(0.985, 1e-6));
      expect(_LayoutProbe.layouts, 0, reason: 'the press repaints, it never lays the card out');
      await g.up();
      await t.pumpAndSettle();
      expect(m(), Matrix4.identity());

      // a scroll through the list: the card under the finger lets go, nothing throws
      await t.drag(find.byType(ListView), const Offset(0, -300));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('does not move under Reduce motion', (t) async {
      await t.pumpWidget(_app(const Center(
        child: SizedBox(width: 300, height: 120, child: AppTilt.subtle(child: ColoredBox(color: Colors.blue))),
      ), reduce: true));
      final g = await t.startGesture(t.getCenter(find.byType(AppTilt)));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.widget<Transform>(find.descendant(of: find.byType(AppTilt), matching: find.byType(Transform)).first).transform,
          Matrix4.identity());
      expect(t.hasRunningAnimations, isFalse);
      await g.up();
    });
  });

  group('AppFlip3D', () {
    testWidgets('turns over, the reader hears the visible face only, and it is the identity at rest', (t) async {
      final sem = t.ensureSemantics();
      await t.pumpWidget(_app(Center(child: _Toggle(builder: _flip))));
      expect(find.semantics.byLabel('Question'), findsOneWidget);
      expect(find.semantics.byLabel('Answer: photosynthesis'), findsNothing);
      await _tapToggle(t);
      await t.pump(const Duration(milliseconds: 40));
      final turning = _matrixOf(t, find.text('Question'));
      expect(turning.entry(0, 2), isNot(0), reason: 'mid-flip the front turns around Y');
      await t.pumpAndSettle();
      expect(find.semantics.byLabel('Answer: photosynthesis'), findsOneWidget);
      expect(find.semantics.byLabel('Question'), findsNothing);
      expect(_matrixOf(t, find.text('Answer: photosynthesis')), Matrix4.identity());
      expect(_matrixOf(t, find.text('Question')), Matrix4.identity());
      sem.dispose();
    });

    testWidgets('a second toggle mid-flip turns it back from where it is', (t) async {
      await t.pumpWidget(_app(Center(child: _Toggle(builder: _flip))));
      await _tapToggle(t);
      await t.pump(const Duration(milliseconds: 60));
      final before = _matrixOf(t, find.text('Question')).entry(0, 0); // cos of the angle (front still showing)
      await _tapToggle(t);
      await t.pump(const Duration(milliseconds: 16));
      final after = _matrixOf(t, find.text('Question')).entry(0, 0);
      expect(t.takeException(), isNull);
      expect(before, lessThan(1));
      expect((after - before).abs(), lessThan(0.25), reason: 'no jump back to the start');
      await t.pumpAndSettle();
      expect(_matrixOf(t, find.text('Question')), Matrix4.identity());
      expect(find.semantics.byLabel('Question'), findsOneWidget);
    });

    testWidgets('turns the other way in Arabic', (t) async {
      Future<double> sinAt(String lang) async {
        AppConfig.lang = lang;
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(_app(Center(child: _Toggle(builder: _flip))));
        await _tapToggle(t);
        await t.pump(const Duration(milliseconds: 40));
        final v = _matrixOf(t, find.text('Question')).entry(0, 2);
        await t.pumpAndSettle();
        return v;
      }

      final en = await sinAt('en');
      final ar = await sinAt('ar');
      expect(en.sign, -ar.sign);
    });

    testWidgets('Reduce motion: a crossfade, nothing turns', (t) async {
      await t.pumpWidget(_app(Center(child: _Toggle(builder: _flip)), reduce: true));
      await _tapToggle(t);
      await t.pump(const Duration(milliseconds: 60));
      expect(_matrixOf(t, find.text('Question')), Matrix4.identity());
      expect(_matrixOf(t, find.text('Answer: photosynthesis')), Matrix4.identity());
      final fades = t
          .widgetList<Opacity>(find.descendant(of: find.byType(AppFlip3D), matching: find.byType(Opacity)))
          .map((o) => o.opacity);
      expect(fades.any((o) => o > 0 && o < 1), isTrue, reason: 'mid-crossfade');
      await t.pumpAndSettle();
      expect(find.text('Answer: photosynthesis').hitTestable(), findsOneWidget);
    });
  });

  group('AppParallaxImage', () {
    testWidgets('drifts at most maxShift each way while the list scrolls, without a rebuild', (t) async {
      var builds = 0;
      const image = ValueKey('cover');
      await t.pumpWidget(_app(ListView(children: [
        const SizedBox(height: 300),
        SizedBox(
          height: 140,
          child: AppParallaxImage(
            image: Builder(builder: (_) {
              builds++;
              return const ColoredBox(key: image, color: Colors.teal);
            }),
          ),
        ),
        const SizedBox(height: 1200),
      ])));
      double shift() => t.getTopLeft(find.byKey(image)).dy - t.getTopLeft(find.byType(AppParallaxImage)).dy;
      final a = shift();
      await t.drag(find.byType(ListView), const Offset(0, -250));
      await t.pump();
      final b = shift();
      expect(a, inInclusiveRange(-16, 0));
      expect(b, inInclusiveRange(-16, 0));
      expect(b, greaterThan(a), reason: 'scrolled up, the picture lags behind its card');
      expect(builds, 1, reason: 'scrolling repaints, it never rebuilds the picture');
      expect(t.getSize(find.byKey(image)).height, 140 + 16);
    });

    testWidgets('the offset covers the box at both ends', (t) async {
      expect(AppParallaxImage.offsetFor(-1, 8), 0);
      expect(AppParallaxImage.offsetFor(0, 8), -8);
      expect(AppParallaxImage.offsetFor(1, 8), -16);
      expect(AppParallaxImage.offsetFor(5, 8), -16);
    });

    testWidgets('just the picture outside a Scrollable and under Reduce motion', (t) async {
      await t.pumpWidget(_app(const Center(child: SizedBox(height: 120, child: AppParallaxImage(image: Placeholder())))));
      expect(find.byType(Flow), findsNothing);
      await t.pumpWidget(_app(
        ListView(children: const [SizedBox(height: 120, child: AppParallaxImage(image: Placeholder()))]),
        reduce: true,
      ));
      expect(find.byType(Flow), findsNothing);
    });
  });

  group('AppOdometer', () {
    testWidgets('rolls on a change, reads the final value, remembers it, and turns around mid-roll', (t) async {
      final sem = t.ensureSemantics();
      Widget figure(String v) => _app(Center(child: AppOdometer(v, memoryKey: 'streak', style: const TextStyle(fontSize: 28))));
      await t.pumpWidget(figure('12'));
      await t.pumpAndSettle();
      await t.pumpWidget(figure('19'));
      await t.pump(const Duration(milliseconds: 120));
      expect(find.descendant(of: find.byType(AppOdometer), matching: find.byType(CustomPaint)), findsWidgets);
      expect(find.bySemanticsLabel('19'), findsOneWidget);
      // interrupted: a third value mid-roll carries on, no exception
      await t.pumpWidget(figure('21'));
      await t.pump(const Duration(milliseconds: 16));
      expect(t.takeException(), isNull);
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byType(AppOdometer), matching: find.byType(CustomPaint)), findsNothing);
      expect(find.text('21'), findsOneWidget);
      // shown again under the same key: still
      await t.pumpWidget(_app(const SizedBox()));
      await t.pumpWidget(figure('21'));
      expect(t.hasRunningAnimations, isFalse);
      sem.dispose();
    });

    testWidgets('keeps its width while it rolls (tabular digits)', (t) async {
      await t.pumpWidget(_app(const Center(child: AppOdometer('1,111', style: TextStyle(fontSize: 28)))));
      await t.pumpAndSettle();
      final w = t.getSize(find.byType(AppOdometer)).width;
      await t.pumpWidget(_app(const Center(child: AppOdometer('8,888', style: TextStyle(fontSize: 28)))));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.getSize(find.byType(AppOdometer)).width, closeTo(w, 0.01));
    });

    testWidgets('does not move under Reduce motion', (t) async {
      await t.pumpWidget(_app(const Center(child: AppOdometer('40')), reduce: true));
      await t.pumpWidget(_app(const Center(child: AppOdometer('45')), reduce: true));
      expect(t.hasRunningAnimations, isFalse);
      expect(find.descendant(of: find.byType(AppOdometer), matching: find.byType(CustomPaint)), findsNothing);
      expect(find.text('45'), findsOneWidget);
    });
  });

  group('AppExpandCard', () {
    double bodyHeight(WidgetTester t) => t.getSize(find.descendant(of: find.byType(AppExpandCard), matching: find.byType(ClipRect)).first).height;

    testWidgets('a 48 px button with an expanded state, opened by Enter', (t) async {
      final sem = t.ensureSemantics();
      await t.pumpWidget(_app(Center(child: _expand(false))));
      expect(t.getSize(find.byType(InkWell)).height, greaterThanOrEqualTo(48));
      expect(t.getSemantics(find.text('Lesson 1 · Cells')), isSemantics(isButton: true, hasExpandedState: true, isExpanded: false));
      expect(find.bySemanticsLabel(RegExp('Every living thing')), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(t.getSemantics(find.text('Lesson 1 · Cells')), isSemantics(isButton: true, hasExpandedState: true, isExpanded: true));
      expect(find.bySemanticsLabel(RegExp('Every living thing')), findsOneWidget);
      sem.dispose();
    });

    testWidgets('closing mid-opening carries on from the current height', (t) async {
      await t.pumpWidget(_app(Center(child: _expand(false))));
      await t.tap(find.text('Lesson 1 · Cells'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      final h1 = bodyHeight(t);
      expect(h1, greaterThan(0));
      await t.tap(find.text('Lesson 1 · Cells'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 16));
      final h2 = bodyHeight(t);
      expect(t.takeException(), isNull);
      expect(h2, lessThanOrEqualTo(h1 + 1));
      expect(h2, greaterThan(h1 * 0.5), reason: 'no jump to closed');
      await t.pumpAndSettle();
      expect(find.text('Every living thing is made of cells. A long body text that wraps on a phone at 320 px.').hitTestable(), findsNothing);
    });

    testWidgets('Reduce motion: opens at once', (t) async {
      await t.pumpWidget(_app(Center(child: _expand(false)), reduce: true));
      final full = await () async {
        await t.pumpWidget(_app(Center(child: _expand(true)), reduce: true));
        return bodyHeight(t);
      }();
      await t.pumpWidget(_app(const SizedBox(), reduce: true));
      await t.pumpWidget(_app(Center(child: _expand(false)), reduce: true));
      await t.tap(find.text('Lesson 1 · Cells'));
      await t.pump();
      expect(bodyHeight(t), full, reason: 'open in the same frame');
      expect(find.textContaining('Every living thing').hitTestable(), findsOneWidget);
    });
  });

  group('AppSlideIn', () {
    Finder slide() => find.descendant(of: find.byType(AppSlideIn), matching: find.byType(FractionalTranslation));
    double dy(WidgetTester t) => t.widget<FractionalTranslation>(slide()).translation.dy;

    testWidgets('slides in, turns around mid-way, and leaves the tree when gone', (t) async {
      await t.pumpWidget(_app(Center(child: _Toggle(builder: _slide))));
      expect(find.text('Correct'), findsNothing);
      await _tapToggle(t);
      await t.pump(const Duration(milliseconds: 40));
      final a = dy(t);
      expect(a, inExclusiveRange(0, 1));
      await _tapToggle(t);
      await t.pump(const Duration(milliseconds: 16));
      final b = dy(t);
      expect(t.takeException(), isNull);
      expect((b - a).abs(), lessThan(0.3), reason: 'it leaves from where it is');
      expect(find.text('Correct').hitTestable(), findsNothing, reason: 'leaving, it cannot be tapped');
      await t.pumpAndSettle();
      expect(find.text('Correct'), findsNothing);
      await _tapToggle(t);
      await t.pumpAndSettle();
      expect(dy(t), 0);
      expect(find.text('Correct').hitTestable(), findsOneWidget);
    });

    testWidgets('Reduce motion: a fade, no movement', (t) async {
      await t.pumpWidget(_app(Center(child: _Toggle(builder: _slide)), reduce: true));
      await _tapToggle(t);
      await t.pump(const Duration(milliseconds: 60));
      expect(slide(), findsNothing);
      final o = t.widget<Opacity>(find.descendant(of: find.byType(AppSlideIn), matching: find.byType(Opacity)).first).opacity;
      expect(o, inExclusiveRange(0, 1), reason: 'mid-fade');
      await t.pumpAndSettle();
      expect(find.text('Correct'), findsOneWidget);
    });
  });

  group('showAppSheet motion', () {
    Future<ModalRoute<dynamic>> open(WidgetTester t, {bool reduce = false}) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      late ModalRoute<dynamic> route;
      await t.pumpWidget(_app(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showAppSheet<void>(context, (ctx) {
                route = ModalRoute.of(ctx)!;
                return const AppSheetContent(title: 'Filters', children: [SizedBox(height: 320, child: Text('sheet body'))]);
              }),
              child: const Text('open'),
            ),
          ),
        ),
        reduce: reduce,
      ));
      await t.tap(find.text('open'));
      await t.pump();
      return route;
    }

    // KIT_SPEC 5.8 (M14): the sheet rises in 500 ms with the peek overshoot (was 280 ms, D-621)
    testWidgets('500 ms in, 200 ms out; a drag catches it mid-way and a fling down dismisses it', (t) async {
      final route = await open(t);
      expect(route.transitionDuration, const Duration(milliseconds: 500));
      expect(route.reverseTransitionDuration, const Duration(milliseconds: 200));
      // a third of the 500 ms rise: the body is on screen (at 90 ms it was still below the fold, so the press hit the scrim)
      await t.pump(const Duration(milliseconds: 160));
      expect(route.animation!.value, inExclusiveRange(0, 1));
      // caught while still rising, let go short of the dismiss point: it settles open
      final g = await t.startGesture(t.getCenter(find.text('sheet body')));
      for (var i = 0; i < 8; i++) {
        await g.moveBy(const Offset(0, 5));
        await t.pump(const Duration(milliseconds: 40)); // slow: 125 px/s, no fling
      }
      await t.pump(const Duration(milliseconds: 200)); // hold still before letting go
      await g.up();
      await t.pumpAndSettle();
      expect(route.animation!.value, 1);
      expect(find.text('sheet body'), findsOneWidget);
      // a fast fling down
      await t.fling(find.text('sheet body'), const Offset(0, 200), 2500);
      await t.pumpAndSettle();
      expect(find.text('sheet body'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('Reduce motion: no slide', (t) async {
      final route = await open(t, reduce: true);
      expect(route.transitionDuration, Duration.zero);
      expect(find.text('sheet body'), findsOneWidget);
    });
  });
}
