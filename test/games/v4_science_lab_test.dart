// Games v4 T54: Science Lab (combine + mcq): layout at every size, and a scripted play-through (drag, tap-to-place, a
// wrong mix, a right mix with its reaction, the mcq, the round's score).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';
import 'package:flutter_education_app/features/games/templates/register_all.dart';
import 'package:flutter_education_app/features/games/templates/science_lab/science_lab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

GameItem combine(int n, {String fx = 'fizz', bool image = false}) => GameItem.fromJson({
      'type': 'combine',
      'prompt': {'ar': 'اصنع بركانًا صغيرًا', 'en': 'Make a tiny volcano'},
      'body': {
        'ingredients': [
          {'key': 'vinegar', 'label': {'ar': 'خل', 'en': 'Vinegar'}, if (image) 'image': 'https://x/v.png'},
          {'key': 'soda', 'label': {'ar': 'بيكنج صودا', 'en': 'Baking soda'}},
          {'key': 'salt', 'label': {'ar': 'ملح', 'en': 'Salt'}},
          {'key': 'oil', 'label': {'ar': 'زيت', 'en': 'Oil'}},
        ],
        'answer': ['vinegar', 'soda'],
        'fx': fx,
        'result': {'ar': 'غاز ثاني أكسيد الكربون يتصاعد!', 'en': 'Carbon dioxide gas bubbles up!'},
        'show': [2, 1, 3, 0],
      },
    }, n: n)!;

GameItem mcq(int n) => GameItem.fromJson({
      'type': 'mcq',
      'prompt': {'ar': 'ما الغاز الناتج؟', 'en': 'Which gas was made?'},
      'explain': {'ar': 'ثاني أكسيد الكربون', 'en': 'Carbon dioxide'},
      'body': {
        'options': [
          {'text': 'Oxygen'},
          {'text': 'Carbon dioxide'},
          {'text': 'Helium'},
        ],
        'answer': 1,
        'show': [0, 1, 2],
      },
    }, n: n)!;

GameSession session(List<GameItem> items) => GameSession(items: items, settings: const GameSettings(), templateKey: 'science_lab')..start();

Future<void> spin(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1100);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget paint(BuildContext c, String url, double size) => ColoredBox(color: Theme.of(c).colorScheme.primary, child: SizedBox.square(dimension: size));

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    GameFeedback.instance.reset();
  });

  test('registered once', () {
    expect(kReadyTemplates.where((t) => t.key == 'science_lab').length, 1);
    expect(kScienceLab.sacredAllowed, isFalse);
  });

  testWidgets('layout: every fx, a picture, the mcq', (tester) async {
    for (final fx in ['fizz', 'color', 'glow', 'smoke', 'freeze']) {
      await expectNoLayoutErrors(tester, () => ScienceLabGame(session: session([combine(0, fx: fx, image: fx == 'fizz')]), silent: true, imageBuilder: paint), scaffold: false);
    }
    await expectNoLayoutErrors(tester, () => ScienceLabGame(session: session([mcq(0)]), silent: true), scaffold: false);
  });

  testWidgets('play-through: wrong mix, tap-to-place, drag, right mix, mcq', (tester) async {
    phone(tester);
    final s = session([combine(0), mcq(1)]);
    await tester.pumpWidget(layoutHost(ScienceLabGame(session: s, silent: true, advanceMs: 1500), scaffold: false));
    await spin(tester, 700);
    // Mix is off while the flask is empty
    await tester.tap(find.byKey(const ValueKey('lab-mix')));
    await spin(tester, 100);
    expect(s.trace, isEmpty);
    // tap jar Salt (2), tap the flask; Oil (3) too: a wrong mix, reported once with 0
    for (final k in [2, 3]) {
      await tester.tap(find.byKey(ValueKey('tray-$k')));
      await spin(tester, 100);
      await tester.tap(find.byKey(const ValueKey('slot-0')));
      await spin(tester, 200);
    }
    await tester.tap(find.byKey(const ValueKey('lab-mix')));
    await spin(tester, 300);
    expect(s.trace.single['a'], [2, 3]);
    expect(s.score, 0);
    expect(find.byKey(const ValueKey('lab-fail')), findsOneWidget);
    await spin(tester, 1500);
    // the flask emptied: Vinegar (0) dragged in, Soda (1) tapped in
    final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('tray-0'))));
    await spin(tester, 50);
    await g.moveTo(tester.getCenter(find.byKey(const ValueKey('slot-0'))));
    await spin(tester, 100);
    await g.up();
    await spin(tester, 300);
    await tester.tap(find.byKey(const ValueKey('tray-1')));
    await spin(tester, 100);
    await tester.tap(find.byKey(const ValueKey('slot-0')));
    await spin(tester, 200);
    await tester.tap(find.byKey(const ValueKey('lab-mix')));
    await spin(tester, 300);
    expect(find.byKey(const ValueKey('lab-result')), findsOneWidget);
    expect(s.trace.length, 1, reason: 'only the first mix is reported');
    await spin(tester, 1600);
    // the mcq: a wrong tile, then the right one; only the first tap counts
    expect(find.text('Which gas was made?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('opt-0')));
    await spin(tester, 200);
    await tester.tap(find.byKey(const ValueKey('opt-1')));
    await spin(tester, 1600);
    expect(s.trace.last['a'], 0);
    expect(s.finished, isTrue);
    expect(s.score, 0);
  });

  testWidgets('a right first mix and a right first answer score full', (tester) async {
    phone(tester);
    final s = session([combine(0, fx: 'freeze'), mcq(1)]);
    await tester.pumpWidget(layoutHost(ScienceLabGame(session: s, silent: true, advanceMs: 100), scaffold: false));
    await spin(tester, 700);
    for (final k in [1, 0]) {
      await tester.tap(find.byKey(ValueKey('tray-$k')));
      await spin(tester, 100);
      await tester.tap(find.byKey(const ValueKey('slot-0')));
      await spin(tester, 200);
    }
    await tester.tap(find.byKey(const ValueKey('lab-mix')));
    await spin(tester, 800);
    await tester.tap(find.byKey(const ValueKey('opt-1')));
    await spin(tester, 1600);
    expect(s.score, 2);
    expect(s.finished, isTrue);
  });
}
