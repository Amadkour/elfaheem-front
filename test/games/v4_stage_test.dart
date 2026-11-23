// Games v4 T37: QuestionStage + Challenge Quiz, DragBoard + Verse Builder: layout harness and play-throughs.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/bases/drag_board.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';
import 'package:flutter_education_app/features/games/templates/challenge_quiz/challenge_quiz.dart';
import 'package:flutter_education_app/features/games/templates/verse_builder/verse_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

/// Text the stage is checked with: the words of one long ayah with full tashkeel (illustration for layout only).
const kLongAyah = [
  'ٱللَّهُ', 'لَآ', 'إِلَٰهَ', 'إِلَّا', 'هُوَ', 'ٱلْحَىُّ', 'ٱلْقَيُّومُ', 'لَا', 'تَأْخُذُهُۥ', 'سِنَةٌ', 'وَلَا', 'نَوْمٌ',
];

GameItem mcq(int n, {int answer = 1, bool sacred = false, String? explain}) => GameItem.fromJson({
      'type': 'mcq',
      'sacred': sacred,
      'prompt': {'ar': 'ما عاصمة مصر؟', 'en': 'What is the capital of Egypt?'},
      'explain': {'ar': explain, 'en': explain},
      'body': {
        'options': [
          {'text': 'Alexandria'},
          {'text': 'Cairo'},
          {'text': 'Giza'},
          {'text': 'Luxor'},
        ],
        'answer': answer,
        'show': [0, 1, 2, 3],
      },
    }, n: n)!;

GameItem tf(int n) => GameItem.fromJson({
      'type': 'true_false',
      'prompt': {'ar': 'الشمس نجم', 'en': 'The sun is a star'},
      'body': {'answer': true},
    }, n: n)!;

GameItem selectAll(int n, {bool sacred = false}) => GameItem.fromJson({
      'type': 'select_all',
      'sacred': sacred,
      'prompt': {'ar': 'اختر الأعداد الزوجية', 'en': 'Pick the even numbers'},
      'body': {
        'options': [
          {'text': '2'},
          {'text': '3'},
          {'text': '4'},
          {'text': '7'},
        ],
        'answers': [0, 2],
        'show': [0, 1, 2, 3],
      },
    }, n: n)!;

/// A sequence item. [blanks] null = every slot (`order`); [show] null = the extras first, then the tokens reversed.
GameItem seq(int n, List<String> tokens,
    {List<int>? blanks, List<String> extra = const [], List<int>? show, bool sacred = false, List<Map<String, dynamic>>? audio}) {
  final classes = <String, int>{};
  final eq = [for (final tk in tokens) classes.putIfAbsent(tk, () => classes.length)];
  final b = blanks ?? [for (var i = 0; i < tokens.length; i++) i];
  final all = [...tokens, ...extra];
  final sh = show ?? [for (var i = all.length - 1; i >= 0; i--) if (i >= tokens.length || b.contains(i)) i];
  return GameItem.fromJson({
    'type': 'sequence',
    'sacred': sacred,
    'prompt': {'ar': 'رتّب كلمات الآية', 'en': 'Put the words of the ayah in order'},
    'media': {'image': null, 'audio': audio},
    'source': sacred ? {'kind': 'quran', 'ref': '2:255', 'label': {'ar': 'البقرة ٢٥٥', 'en': 'Al-Baqarah 255'}} : null,
    'body': {
      'mode': blanks == null ? 'order' : 'complete',
      'unit': 'word',
      'tokens': tokens,
      'eq': eq,
      'blanks': b,
      'extra': extra,
      'show': sh,
    },
  }, n: n)!;
}

List<Map<String, dynamic>> audioOf(String ref) => [
        {'ref': ref, 'url': 'https://example.test/a.mp3', 'start_ms': 0, 'end_ms': null, 'reciter': 'alafasy'},
    ];

Future<GameReciterList> _fakeReciters() async => const GameReciterList(
      items: [GameReciter(key: 'alafasy', nameAr: 'العفاسي', nameEn: 'Alafasy'), GameReciter(key: 'husary', nameAr: 'الحصري', nameEn: 'Husary')],
      effective: 'alafasy',
    );

/// Pumps [ms] in steps, so a timer that starts an animation and the animation itself both run.
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

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    GameFeedback.instance.reset();
  });

  GameSession session(List<GameItem> items, {bool sacred = false, GameSettings settings = const GameSettings()}) =>
      GameSession(items: items, sacred: sacred, settings: settings, templateKey: 'x')..start();

  group('layout', () {
    testWidgets('Challenge Quiz: mcq, select_all, sacred, long options', (tester) async {
      await expectNoLayoutErrors(tester, () => ChallengeQuizGame(session: session([mcq(0), selectAll(1), tf(2)]), silent: true), scaffold: false);
      await expectNoLayoutErrors(
          tester, () => ChallengeQuizGame(session: session([mcq(0, sacred: true)], sacred: true, settings: GameSettings.fromJson(null, sacred: true)), silent: true),
          scaffold: false);
    });

    testWidgets('Verse Builder: a long ayah with tashkeel, order and complete', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => VerseBuilderGame(
                session: session([seq(0, kLongAyah, sacred: true, extra: ['ٱلصَّمَدُ', 'كُفُوًا'], audio: audioOf('2:255'))], sacred: true),
                silent: true,
                reciters: _fakeReciters,
              ),
          scaffold: false);
      await expectNoLayoutErrors(
          tester,
          () => VerseBuilderGame(
                session: session([seq(0, ['One', 'small', 'step', 'for', 'man'], blanks: [1, 3], extra: ['giant'])]),
                silent: true,
              ),
          scaffold: false);
    });

    testWidgets('DragBoard: line and buckets with plain values', (tester) async {
      for (final layout in DragBoardLayout.values) {
        await expectNoLayoutErrors(
            tester,
            () => Material(
                  child: SingleChildScrollView(
                    child: DragBoard(
                      theme: AgeTheme.build(GameAge.kids),
                      layout: layout,
                      slots: [
                        for (var i = 0; i < 3; i++)
                          DragSlotData(id: i, label: 'Bucket $i', number: i + 1, capacity: 4, tokens: [DragToken(id: i, text: 'token $i')]),
                      ],
                      tray: [for (var i = 3; i < 9; i++) DragToken(id: i, text: 'a longer token $i')],
                      onDrop: (_, _) {},
                    ),
                  ),
                ),
            scaffold: false);
      }
    });
  });

  testWidgets('DragBoard: pieces and buckets with pictures (the builder draws them)', (tester) async {
    var drawn = 0;
    for (final layout in DragBoardLayout.values) {
      await expectNoLayoutErrors(
          tester,
          () => Material(
                child: SingleChildScrollView(
                  child: DragBoard(
                    theme: AgeTheme.build(GameAge.kids),
                    layout: layout,
                    imageBuilder: (context, url, size) {
                      drawn++;
                      return ColoredBox(color: Theme.of(context).colorScheme.primary, child: SizedBox.square(dimension: size));
                    },
                    slots: [
                      for (var i = 0; i < 3; i++)
                        DragSlotData(id: i, label: 'Bucket $i', image: 'https://x/b$i.png', number: i + 1, capacity: 4, tokens: [DragToken(id: i, text: 'token $i', image: 'https://x/$i.png')]),
                    ],
                    tray: [
                      for (var i = 3; i < 7; i++) DragToken(id: i, text: i.isEven ? '' : 'a longer picture label $i', image: 'https://x/$i.png'),
                      const DragToken(id: 9, text: 'words only'),
                    ],
                    onDrop: (_, _) {},
                  ),
                ),
              ),
          scaffold: false);
    }
    expect(drawn, greaterThan(0));
  });

  group('Challenge Quiz play-through', () {
    testWidgets('right answers score, advance and finish', (tester) async {
      final s = session([mcq(0, explain: 'Cairo is the capital.'), tf(1), selectAll(2)]);
      await tester.pumpWidget(layoutHost(ChallengeQuizGame(session: s, silent: true), scaffold: false));
      await spin(tester, 600);
      await tester.tap(find.byKey(const ValueKey('opt-1')));
      await spin(tester, 300);
      expect(s.score, 1);
      expect(find.text('Cairo is the capital.'), findsOneWidget);
      await spin(tester, 2000);
      // true_false: key 1 = true
      await tester.tap(find.byKey(const ValueKey('opt-1')));
      await spin(tester, 2500);
      expect(s.score, 2);
      // select_all: pick 0 and 2, check
      await tester.tap(find.byKey(const ValueKey('opt-0')));
      await tester.tap(find.byKey(const ValueKey('opt-2')));
      await spin(tester, 100);
      await tester.tap(find.byKey(const ValueKey('check')));
      await spin(tester, 3000);
      expect(s.finished, isTrue);
      expect(s.score, s.maxScore);
      expect(s.trace.where((e) => e['i'] != -1).length, 3);
      expect(s.trace[2]['a'], [0, 2]);
      await spin(tester, 1000);
    });

    testWidgets('a wrong answer reveals the right one and moves on; the hint dims a wrong option', (tester) async {
      final s = session([mcq(0), mcq(1)]);
      await tester.pumpWidget(layoutHost(ChallengeQuizGame(session: s, silent: true), scaffold: false));
      await spin(tester, 600);
      await tester.tap(find.byKey(const ValueKey('opt-0')));
      await spin(tester, 300);
      expect(s.score, 0);
      expect(s.trace.single['a'], 0);
      await spin(tester, 3000);
      // second question: ask a hint through the shell's lamp, the next answer carries h
      await tester.tap(find.byIcon(Icons.lightbulb_outline_rounded));
      await spin(tester, 300);
      await tester.tap(find.byKey(const ValueKey('opt-1')));
      await spin(tester, 3000);
      expect(s.trace.last['h'], isTrue);
      expect(s.finished, isTrue);
      expect(s.score, 0);
      await spin(tester, 1000);
    });

    testWidgets('a sacred wrong answer is a quiet retry: reported once, nothing lost', (tester) async {
      final s = session([mcq(0, sacred: true)], sacred: true, settings: GameSettings.fromJson({'penalty': 'lives', 'lives': 3}, sacred: true));
      await tester.pumpWidget(layoutHost(ChallengeQuizGame(session: s, silent: true), scaffold: false));
      await spin(tester, 600);
      await tester.tap(find.byKey(const ValueKey('opt-0')));
      await spin(tester, 300);
      await tester.tap(find.byKey(const ValueKey('opt-2')));
      await spin(tester, 300);
      expect(s.finished, isFalse, reason: 'sacred: no life lost, the round goes on');
      expect(s.trace.length, 1, reason: 'a retry is local');
      await tester.tap(find.byKey(const ValueKey('opt-1')));
      await spin(tester, 3000);
      expect(s.finished, isTrue);
      expect(s.score, 0, reason: 'first try wrong');
      await spin(tester, 1000);
    });
  });

  group('Verse Builder play-through', () {
    testWidgets('order: tap every word in order, full score, then the round ends', (tester) async {
      phone(tester);
      final tokens = ['In', 'the', 'name', 'of'];
      final s = session([seq(0, tokens, extra: ['never'])]);
      await tester.pumpWidget(layoutHost(VerseBuilderGame(session: s, silent: true, advanceMs: 100), scaffold: false));
      await spin(tester, 700);
      for (var k = 0; k < tokens.length; k++) {
        await tester.tap(find.byKey(ValueKey('tray-$k')));
        await spin(tester, 250);
      }
      await spin(tester, 2000);
      expect(s.finished, isTrue);
      expect(s.score, 4);
      expect(s.trace.map((e) => e['a']).toList().sublist(0, 4), [[0, 0], [1, 1], [2, 2], [3, 3]]);
      await spin(tester, 1000);
    });

    testWidgets('a wrong word flies back, the retry is not reported, the place scores 0', (tester) async {
      phone(tester);
      final tokens = ['a', 'b', 'c'];
      final s = session([seq(0, tokens, extra: ['z'])]);
      await tester.pumpWidget(layoutHost(VerseBuilderGame(session: s, silent: true, advanceMs: 100), scaffold: false));
      await spin(tester, 700);
      await tester.tap(find.byKey(const ValueKey('tray-3'))); // the extra into slot 0
      await spin(tester, 200);
      expect(s.trace.single['a'], [0, 3]);
      expect(s.score, 0);
      await spin(tester, 1000);
      // retry: the right word, and the rest
      for (var k = 0; k < 3; k++) {
        await tester.tap(find.byKey(ValueKey('tray-$k')));
        await spin(tester, 250);
      }
      await spin(tester, 2000);
      expect(s.finished, isTrue);
      expect(s.score, 2, reason: 'slots 1 and 2 were first-try right');
      expect(s.trace.length, 3, reason: 'slot 0 reported once (the wrong try), then slots 1 and 2');
    });

    testWidgets('complete: only the blanks are open, a dragged word snaps in', (tester) async {
      phone(tester);
      final s = session([seq(0, ['One', 'small', 'step', 'for', 'man'], blanks: [1, 3], extra: ['giant'])]);
      await tester.pumpWidget(layoutHost(VerseBuilderGame(session: s, silent: true, advanceMs: 100), scaffold: false));
      await spin(tester, 700);
      expect(find.text('One'), findsOneWidget);
      expect(find.byKey(const ValueKey('tray-0')), findsNothing, reason: 'a given word is not in the tray');
      final tok = find.byKey(const ValueKey('tray-1'));
      final slot = find.byKey(const ValueKey('slot-1'));
      final gesture = await tester.startGesture(tester.getCenter(tok));
      await spin(tester, 50);
      await gesture.moveTo(tester.getCenter(slot));
      await spin(tester, 100);
      await gesture.up();
      await spin(tester, 600);
      expect(s.trace.single['a'], [1, 1]);
      expect(s.score, 1);
      await tester.tap(find.byKey(const ValueKey('tray-3')));
      await spin(tester, 2000);
      expect(s.finished, isTrue);
      expect(s.score, 2);
      await spin(tester, 1000);
    });

    testWidgets('a sacred wrong word replays the ayah and the reciter switch lists the voices', (tester) async {
      phone(tester);
      GameAudio.instance.fetchAudio = (refs, reciter) async => {};
      final s = session([seq(0, ['x', 'y'], sacred: true, extra: ['q'], audio: audioOf('1:1'))], sacred: true);
      await tester.pumpWidget(layoutHost(VerseBuilderGame(session: s, silent: true, reciters: _fakeReciters, advanceMs: 100), scaffold: false));
      await spin(tester, 700);
      await tester.tap(find.byKey(const ValueKey('tray-2')));
      await spin(tester, 300);
      expect(s.finished, isFalse);
      expect(s.trace.single['a'], [0, 2]);
      await spin(tester, 1000);
      await tester.tap(find.byIcon(Icons.record_voice_over_rounded));
      await spin(tester, 500);
      expect(find.text('Husary'), findsOneWidget);
      await spin(tester, 1000);
    });
  });
}
