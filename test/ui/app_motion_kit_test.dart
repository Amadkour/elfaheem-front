// The motion kit (D-580 .. D-586): numbers, one-shot entrances, the platform switch, the 3D tilt at rest.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/design/app_display.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _app(Widget child, {bool reduce = false}) => layoutHost(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: Center(child: child),
        ),
      ),
      scale: 1,
    );

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppCountUp.resetMemory();
  });

  group('AppNumberText', () {
    test('keeps prefix, suffix, grouping and decimals', () {
      final p = AppNumberText.parse('EGP 1,240.50')!;
      expect(p.number, 1240.5);
      expect(p.format(999.4), 'EGP 999.40');
      expect(p.format(12345), 'EGP 12,345.00');
      expect(AppNumberText.parse('84%')!.format(42), '42%');
      expect(AppNumberText.parse('1.2K')!.format(0.6), '0.6K');
      expect(AppNumberText.parse('-4')!.format(2), '-2');
    });

    test('leaves times, fractions, dates and words alone', () {
      for (final s in ['12:30', '3/5', '2026-11-10', '—', 'Free', '1,23']) {
        expect(AppNumberText.parse(s), isNull, reason: s);
      }
    });
  });

  testWidgets('AppCountUp counts up, holds the final size and reads the final value', (t) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(_app(const AppCountUp('1,240', memoryKey: 'k')));
    await t.pump(const Duration(milliseconds: 300));
    // mid-count: the final text holds the space and is the only one a screen reader gets
    expect(find.text('1,240'), findsOneWidget);
    expect(find.bySemanticsLabel('1,240'), findsOneWidget);
    final moving = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).where((s) => s != '1,240');
    expect(moving, hasLength(1));
    await t.pumpAndSettle();
    expect(find.byType(Text), findsOneWidget);
    expect(find.text('1,240'), findsOneWidget);

    // shown again under the same key (a revisit / refresh): no count from zero
    await t.pumpWidget(_app(const SizedBox()));
    await t.pumpWidget(_app(const AppCountUp('1,240', memoryKey: 'k')));
    expect(find.byType(Text), findsOneWidget);

    // a change glides old -> new
    await t.pumpWidget(_app(const AppCountUp('1,300', memoryKey: 'k')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(Text), findsNWidgets(2));
    await t.pumpAndSettle();
    expect(find.text('1,300'), findsOneWidget);
    sem.dispose();
  });

  testWidgets('AppCountUp does not move under Reduce motion', (t) async {
    await t.pumpWidget(_app(const AppCountUp('75%'), reduce: true));
    expect(find.byType(Text), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('AppReveal plays once per route and index, and only for the first screenful', (t) async {
    Widget list(int n) => Column(children: [
          for (var i = 0; i < n; i++) AppReveal(index: i, group: 'g', child: Text('item $i')),
        ]);
    await t.pumpWidget(_app(list(10)));
    expect(find.descendant(of: find.byType(Column), matching: find.byType(FadeTransition)), findsNWidgets(8)); // the cap: items 8 and 9 just appear
    await t.pumpAndSettle();
    // rebuilt from scratch in the same route (a refresh, a scroll back): no replay
    await t.pumpWidget(_app(const SizedBox()));
    await t.pumpWidget(_app(list(10)));
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('the Super Admin switch makes every account reduce motion, live', (t) async {
    final settings = DisplaySettings.instance;
    late bool off;
    AppConfig.setDisableList(const []);
    await t.pumpWidget(MaterialApp(
      builder: (context, child) => AppDisplayScope(settings: settings, child: child!),
      home: Builder(builder: (context) {
        off = appMotionOff(context);
        return Text('${Theme.of(context).pageTransitionsTheme.builders[TargetPlatform.android].runtimeType}');
      }),
    ));
    expect(off, isFalse);
    AppConfig.setDisableList(const [kAnimationsFeatureKey]);
    await t.pump();
    expect(off, isTrue);
    expect(find.text('AppNoPageTransitions'), findsOneWidget);
    AppConfig.setDisableList(const []);
    await t.pump();
    expect(off, isFalse);
  });

  testWidgets('AppTilt is the identity at rest and sinks on a press', (t) async {
    await t.pumpWidget(_app(const SizedBox(width: 300, height: 120, child: AppTilt(child: ColoredBox(color: Colors.blue)))));
    Matrix4 m() => t.widget<Transform>(find.descendant(of: find.byType(AppTilt), matching: find.byType(Transform)).first).transform;
    expect(m(), Matrix4.identity());
    final g = await t.startGesture(t.getCenter(find.byType(AppTilt)) + const Offset(100, 0));
    await t.pumpAndSettle();
    expect(m() == Matrix4.identity(), isFalse);
    await g.up();
    await t.pumpAndSettle();
    expect(m(), Matrix4.identity());

    // the mouse: tilts toward the pointer while it is over the surface, settles back when it leaves
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(t.getCenter(find.byType(AppTilt)) + const Offset(120, -40));
    await t.pumpAndSettle();
    expect(m() == Matrix4.identity(), isFalse);
    await mouse.moveTo(Offset.zero);
    await t.pumpAndSettle();
    expect(m(), Matrix4.identity());
    await mouse.removePointer();
  });
}
