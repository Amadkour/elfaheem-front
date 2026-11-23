// Games v4 T44: I'rab Hunter: layout at every size / language, and a scripted play-through checking the trace
// (the 2-entry for the bucket, then the 3-entry for the case, first tries only).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';
import 'package:flutter_education_app/features/games/templates/irab_hunter/irab_hunter.dart';
import 'package:flutter_education_app/features/games/templates/register_all.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

/// "ذهب الطالبُ إلى المدرسةِ": verb, noun (marfu'), particle, noun (majrur). `show` scrambles the tray.
GameItem irabItem(int n, {List<int> show = const [3, 1, 0, 2]}) => GameItem.fromJson({
      'type': 'classify',
      'prompt': {'ar': 'أعرِب كلمات الجملة: صنّفها ثم اختر حركتها', 'en': "Parse the sentence: sort each word, then pick its case"},
      'explain': {'ar': null, 'en': null},
      'source': null,
      'body': {
        'buckets': [
          {'key': 'noun', 'label': {'ar': 'اسم', 'en': 'Noun'}},
          {'key': 'verb', 'label': {'ar': 'فعل', 'en': 'Verb'}},
          {'key': 'particle', 'label': {'ar': 'حرف', 'en': 'Particle'}},
        ],
        'tokens': [
          {'text': 'ذَهَبَ', 'bucket': 'verb', 'case': null},
          {'text': 'ٱلطَّالِبُ', 'bucket': 'noun', 'case': 'raf'},
          {'text': 'إِلَى', 'bucket': 'particle', 'case': null},
          {'text': 'ٱلْمَدْرَسَةِ', 'bucket': 'noun', 'case': 'jar'},
        ],
        'cases': [
          {'key': 'raf', 'label': {'ar': 'مرفوع', 'en': 'Nominative'}},
          {'key': 'nasb', 'label': {'ar': 'منصوب', 'en': 'Accusative'}},
          {'key': 'jar', 'label': {'ar': 'مجرور', 'en': 'Genitive'}},
          {'key': 'jazm', 'label': {'ar': 'مجزوم', 'en': 'Jussive'}},
        ],
        'show': show,
      },
    }, n: n)!;

GameSession irabSession(List<GameItem> items) =>
    GameSession(items: items, settings: GameSettings.fromJson({'timer_s': 0}, sacred: false), templateKey: 'irab_hunter')..start();

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    GameFeedback.instance.reset();
  });

  test('registered, and refuses a sacred draw', () {
    expect(kReadyTemplates.any((t) => t.key == 'irab_hunter'), isTrue);
    expect(kIrabHunter.sacredAllowed, isFalse);
    final sacred = GameSession(items: [irabItem(0)], sacred: true, settings: GameSettings.fromJson(null, sacred: true), templateKey: 'irab_hunter');
    expect(IrabHunterTemplate.refuses(sacred), isTrue);
  });

  testWidgets('layout: phone and desktop, ar and en, text scale 1.3 (also with the case panel)', (tester) async {
    await expectNoLayoutErrors(tester, () => IrabHunterGame(session: irabSession([irabItem(0)]), silent: true), scaffold: false);
    await expectNoLayoutErrors(tester, () => IrabHunterGame(session: irabSession([irabItem(0)]), silent: true), scaffold: false,
        act: (t) async {
      await t.ensureVisible(find.byKey(const ValueKey('tray-1')));
      await t.tap(find.byKey(const ValueKey('tray-1')));
      await t.pump(const Duration(milliseconds: 200));
      await t.ensureVisible(find.byKey(const ValueKey('pick-0')));
      await t.tap(find.byKey(const ValueKey('pick-0')));
    });
    await expectNoLayoutErrors(tester, () => const IrabHunterRefused(), scaffold: true);
  });

  testWidgets('play-through: bucket then case; retries are local; the trace is exact', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final s = irabSession([irabItem(0)]);
    await tester.pumpWidget(layoutHost(IrabHunterGame(session: s, silent: true, advanceMs: 100), scaffold: false));
    await tester.pump(const Duration(milliseconds: 600));

    Future<void> tapWord(int k) async {
      await tester.ensureVisible(find.byKey(ValueKey('tray-$k')));
      await tester.tap(find.byKey(ValueKey('tray-$k')));
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> pick(String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump(const Duration(milliseconds: 900));
    }

    // word 1 (noun, raf): wrong bucket first (verb = 1), then the right one, then a wrong case, then the right one
    await tapWord(1);
    await pick('pick-1');
    await tapWord(1);
    await pick('pick-0');
    expect(find.byKey(const ValueKey('case-panel')), findsOneWidget);
    await pick('case-1'); // wrong
    await pick('case-0'); // right
    expect(find.byKey(const ValueKey('case-panel')), findsNothing);
    // word 0 (verb, no case): right at once, no case panel
    await tapWord(0);
    await pick('pick-1');
    expect(find.byKey(const ValueKey('case-panel')), findsNothing);
    // word 2 (particle), word 3 (noun, jar)
    await tapWord(2);
    await pick('pick-2');
    await tapWord(3);
    await pick('pick-0');
    await pick('case-2');
    await tester.pump(const Duration(seconds: 2));

    final trace = [for (final e in s.trace) e['a']];
    expect(trace, [
      [1, 1], // wrong bucket (the retry [1, 0] is local, never sent)
      [1, 0, 1], // wrong case
      [0, 1],
      [2, 2],
      [3, 0],
      [3, 0, 2],
    ]);
    expect(s.finished, isTrue);
    expect(s.result!.score, 4, reason: "word 1: the first bucket try and the first case try were wrong");
    expect(s.result!.maxScore, 6);
  });

  testWidgets('a drag to the right basket places the word', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final s = irabSession([irabItem(0)]);
    await tester.pumpWidget(layoutHost(IrabHunterGame(session: s, silent: true), scaffold: false));
    await tester.pump(const Duration(milliseconds: 600));
    final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('tray-0'))));
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveTo(tester.getCenter(find.byKey(const ValueKey('slot-1'))));
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await tester.pump(const Duration(milliseconds: 600));
    expect([for (final e in s.trace) e['a']], [
      [0, 1],
    ]);
  });
}
