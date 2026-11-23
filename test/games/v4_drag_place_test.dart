// Games v4 T45: Drag-to-Place (classify on a board / in buckets, pair) and the DragBoard `board` layout.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/games/bases/drag_board.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';
import 'package:flutter_education_app/features/games/templates/drag_place/drag_place.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

/// A body puzzle: three spots on a picture, the labels to drag onto them.
GameItem body(int n, {bool board = true, bool image = true, bool sacred = false}) => GameItem.fromJson({
      'type': 'classify',
      'sacred': sacred,
      'prompt': {'ar': 'ضع كل عضو في مكانه', 'en': 'Put each organ in its place'},
      'body': {
        'buckets': [
          {'key': 'head', 'label': {'ar': 'الرأس', 'en': 'Head'}},
          {'key': 'chest', 'label': {'ar': 'الصدر', 'en': 'Chest'}},
          {'key': 'belly', 'label': {'ar': 'البطن', 'en': 'Belly'}},
        ],
        'tokens': [
          {'text': 'Brain', 'bucket': 'head'},
          {'text': 'Heart', 'bucket': 'chest'},
          {'text': 'Lungs', 'bucket': 'chest'},
          {'text': 'Stomach', 'bucket': 'belly'},
        ],
        'show': [3, 1, 0, 2],
        if (board)
          'board': {
            'image': image ? 'https://example.test/body.png' : null,
            'spots': {'head': [0.5, 0.12], 'chest': [0.5, 0.42], 'belly': [0.5, 0.75]},
          },
      },
    }, n: n)!;

GameItem pair(int n) => GameItem.fromJson({
      'type': 'pair',
      'prompt': {'ar': 'صِل كل دولة بعاصمتها', 'en': 'Match each country to its capital'},
      'body': {
        'pairs': [
          {'a': 'Egypt', 'b': 'Cairo'},
          {'a': 'Jordan', 'b': 'Amman'},
          {'a': 'Tunisia', 'b': 'Tunis'},
        ],
        'show_a': [0, 1, 2],
        'show_b': [2, 0, 1],
      },
    }, n: n)!;

Widget Function(BuildContext, String, double) paint() => (context, url, size) =>
    ColoredBox(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3), child: SizedBox.square(dimension: size));

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

  GameSession session(List<GameItem> items, {bool sacred = false}) =>
      GameSession(items: items, sacred: sacred, settings: sacred ? GameSettings.fromJson(null, sacred: true) : const GameSettings(), templateKey: 'drag_place')..start();

  group('layout', () {
    testWidgets('DragBoard board layout: picture, clean board, spots near every edge', (tester) async {
      for (final image in ['https://x/b.png', null]) {
        await expectNoLayoutErrors(
            tester,
            () => Material(
                  child: SingleChildScrollView(
                    child: DragBoard(
                      theme: AgeTheme.build(GameAge.kids),
                      layout: DragBoardLayout.board,
                      boardImage: image,
                      imageBuilder: paint(),
                      slots: [
                        DragSlotData(id: 0, label: 'Corner', number: 1, at: Offset.zero),
                        DragSlotData(id: 1, label: 'Far corner', number: 2, at: const Offset(1, 1)),
                        DragSlotData(id: 2, label: 'Middle', number: 3, at: const Offset(0.5, 0.5), tokens: [const DragToken(id: 1, text: 'Heart')], state: DragSlotState.correct),
                      ],
                      tray: [for (var i = 3; i < 8; i++) DragToken(id: i, text: 'a longer token $i')],
                      onDrop: (_, _) {},
                    ),
                  ),
                ),
            scaffold: false);
      }
    });

    testWidgets('Drag-to-Place: body board, buckets without a board, pair, calm', (tester) async {
      await expectNoLayoutErrors(tester, () => DragPlaceGame(session: session([body(0)]), silent: true, boardAspect: 1.2, imageBuilder: paint()), scaffold: false);
      await expectNoLayoutErrors(tester, () => DragPlaceGame(session: session([body(0, image: false)]), silent: true), scaffold: false);
      await expectNoLayoutErrors(tester, () => DragPlaceGame(session: session([body(0, board: false)]), silent: true), scaffold: false);
      await expectNoLayoutErrors(tester, () => DragPlaceGame(session: session([pair(0)]), silent: true), scaffold: false);
      await expectNoLayoutErrors(tester, () => DragPlaceGame(session: session([body(0, sacred: true)], sacred: true), silent: true, boardAspect: 1.2, imageBuilder: paint()),
          scaffold: false);
    });
  });

  group('play-through', () {
    testWidgets('body board: drag to the spot, a wrong drop flies back, taps place, round ends with the full score', (tester) async {
      phone(tester);
      final s = session([body(0)]);
      await tester.pumpWidget(layoutHost(DragPlaceGame(session: s, silent: true, advanceMs: 100, boardAspect: 1.2, imageBuilder: paint()), scaffold: false));
      await spin(tester, 700);
      // Brain (token 0) dragged to the head spot (slot 0)
      final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('tray-0'))));
      await spin(tester, 50);
      await g.moveTo(tester.getCenter(find.byKey(const ValueKey('slot-0'))));
      await spin(tester, 100);
      await g.up();
      await spin(tester, 600);
      expect(s.trace.single['a'], [0, 0]);
      expect(s.score, 1);
      // Heart (1) tapped, then the BELLY (2): wrong, flies back, reported once with 0
      await tester.tap(find.byKey(const ValueKey('tray-1')));
      await spin(tester, 100);
      await tester.tap(find.byKey(const ValueKey('slot-2')));
      await spin(tester, 200);
      expect(s.trace.last['a'], [1, 2]);
      expect(s.score, 1);
      await spin(tester, 1000);
      expect(find.byKey(const ValueKey('tray-1')), findsOneWidget);
      // the retry on the chest is not reported again; the rest are first tries
      for (final (tok, slot) in [(1, 1), (2, 1), (3, 2)]) {
        await tester.tap(find.byKey(ValueKey('tray-$tok')));
        await spin(tester, 100);
        await tester.tap(find.byKey(ValueKey('slot-$slot')));
        await spin(tester, 300);
      }
      await spin(tester, 2500);
      expect(s.finished, isTrue);
      expect(s.score, 3, reason: 'Brain, Lungs and Stomach on the first try; Heart missed once');
      expect(s.trace.where((e) => e['i'] == 0).length, 4);
    });

    testWidgets('pair: tap a capital, tap its country', (tester) async {
      phone(tester);
      final s = session([pair(0)]);
      await tester.pumpWidget(layoutHost(DragPlaceGame(session: s, silent: true, advanceMs: 100), scaffold: false));
      await spin(tester, 700);
      for (final k in [0, 1, 2]) {
        await tester.tap(find.byKey(ValueKey('tray-$k')));
        await spin(tester, 100);
        await tester.tap(find.byKey(ValueKey('slot-$k')));
        await spin(tester, 300);
      }
      await spin(tester, 2500);
      expect(s.finished, isTrue);
      expect(s.score, 3);
      expect(s.trace.map((e) => e['a']).toList().sublist(0, 3), [[0, 0], [1, 1], [2, 2]]);
    });

    testWidgets('a spot is at least AppTouch.min', (tester) async {
      phone(tester);
      await tester.pumpWidget(layoutHost(DragPlaceGame(session: session([body(0)]), silent: true, boardAspect: 1.2, imageBuilder: paint()), scaffold: false));
      await spin(tester, 700);
      for (final k in [0, 1, 2]) {
        final r = tester.getRect(find.byKey(ValueKey('slot-$k')));
        expect(r.width, greaterThanOrEqualTo(AppTouch.min));
        expect(r.height, greaterThanOrEqualTo(AppTouch.min));
      }
    });
  });
}
