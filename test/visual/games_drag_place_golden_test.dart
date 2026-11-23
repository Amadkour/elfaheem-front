// VISUAL review renders of Drag-to-Place (Games v4 T45): kids and adult, phone and desktop, Arabic, a body board
// part-way through, the clean board, the pair mode and the calm Quran mode, into test/visual/goldens/games_dragplace_*.png.
// Not a CI suite; compared by eye.
//
//   flutter test test/visual/games_drag_place_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/templates/drag_place/drag_place.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';
import 'home_screens_golden_test.dart' show pubspecFonts;

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  final sdk = '${root != null && root.isNotEmpty ? root : exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

GameItem _body({bool image = true}) => GameItem(
      n: 0,
      type: ItemType.classify,
      prompt: const GameText('ضع كل عضو في مكانه من الجسم', 'Put each organ in its place'),
      body: {
        'buckets': [
          {'key': 'head', 'label': {'ar': 'الرأس', 'en': 'Head'}},
          {'key': 'chest', 'label': {'ar': 'الصدر', 'en': 'Chest'}},
          {'key': 'belly', 'label': {'ar': 'البطن', 'en': 'Belly'}},
        ],
        'tokens': [
          {'text': 'المعدة', 'bucket': 'belly'},
          {'text': 'القلب', 'bucket': 'chest'},
          {'text': 'الدماغ', 'bucket': 'head'},
          {'text': 'الرئتان', 'bucket': 'chest'},
        ],
        'show': [0, 1, 2, 3],
        'board': {
          'image': image ? 'https://example.test/body.png' : null,
          'spots': {'head': [0.5, 0.14], 'chest': [0.5, 0.45], 'belly': [0.5, 0.78]},
        },
      },
    );

GameItem _pair() => GameItem(
      n: 0,
      type: ItemType.pair,
      prompt: const GameText('صِل كل دولة بعاصمتها', 'Match each country to its capital'),
      body: {
        'pairs': [
          {'a': 'مصر', 'b': 'القاهرة'},
          {'a': 'الأردن', 'b': 'عمّان'},
          {'a': 'تونس', 'b': 'تونس'},
          {'a': 'المغرب', 'b': 'الرباط'},
        ],
        'show_a': [0, 1, 2, 3],
        'show_b': [2, 3, 0, 1],
      },
    );

/// A stand-in for the author's picture: a simple figure, drawn with the theme's colours.
Widget _figure(BuildContext context, String url, double size) {
  final c = Theme.of(context).colorScheme;
  return CustomPaint(painter: _Figure(c.primary.withValues(alpha: 0.25), c.primary.withValues(alpha: 0.5)), size: Size.square(size));
}

class _Figure extends CustomPainter {
  const _Figure(this.fill, this.edge);
  final Color fill, edge;
  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height, w = size.width * 0.75; // a portrait picture (3:4) inside the square the builder gets
    final top = 0.0;
    final f = Paint()..color = fill, e = Paint()..color = edge..style = PaintingStyle.stroke..strokeWidth = 3;
    final head = Rect.fromCenter(center: Offset(w / 2, top + h * 0.14), width: h * 0.2, height: h * 0.22);
    final torso = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w / 2, top + h * 0.6), width: h * 0.34, height: h * 0.62), const Radius.circular(36));
    canvas
      ..translate((size.width - w) / 2, 0)
      ..drawOval(head, f)
      ..drawOval(head, e)
      ..drawRRect(torso, f)
      ..drawRRect(torso, e);
  }

  @override
  bool shouldRepaint(_Figure old) => false;
}

final _shot = GlobalKey();

void main() {
  setUpAll(_loadFonts);
  const sizes = {'phone': Size(390, 780), 'desktop': Size(1280, 800)};

  Future<void> shoot(WidgetTester tester, Size size, Widget Function() build, String name, {Future<void> Function(WidgetTester)? act}) async {
    AppConfig.lang = 'ar';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(layoutHost(RepaintBoundary(key: _shot, child: build()), scale: 1, scaffold: false));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (act != null) await act(tester);
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_dragplace_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  Future<void> placeTwo(WidgetTester tester) async {
    for (final (tok, slot) in [(2, 0), (1, 1)]) {
      await tester.tap(find.byKey(ValueKey('tray-$tok')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(ValueKey('slot-$slot')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  }

  Widget game(GameItem item, AgeTheme t, {bool sacred = false, bool image = true}) => Material(
        child: AgeThemeScope(
          theme: t,
          child: DragPlaceGame(
            session: GameSession(items: [item], sacred: sacred, settings: sacred ? GameSettings.fromJson(null, sacred: true) : const GameSettings(), templateKey: 'drag_place')..start(),
            silent: true,
            boardAspect: 0.75,
            imageBuilder: _figure,
          ),
        ),
      );

  for (final s in sizes.entries) {
    for (final age in [GameAge.kids, GameAge.adult]) {
      testWidgets('body board ${age.name} ${s.key}', (tester) async {
        await shoot(tester, s.value, () => game(_body(), AgeTheme.build(age)), 'body_${age.name}_${s.key}', act: placeTwo);
      });
    }
  }

  testWidgets('clean board kids phone', (tester) async {
    await shoot(tester, sizes['phone']!, () => game(_body(image: false), AgeTheme.build(GameAge.kids)), 'clean_kids_phone');
  });

  testWidgets('pair adult desktop and kids phone', (tester) async {
    await shoot(tester, sizes['desktop']!, () => game(_pair(), AgeTheme.build(GameAge.adult)), 'pair_adult_desktop');
    await shoot(tester, sizes['phone']!, () => game(_pair(), AgeTheme.build(GameAge.kids)), 'pair_kids_phone');
  });

  testWidgets('teen night phone', (tester) async {
    await shoot(tester, sizes['phone']!, () => game(_body(), AgeTheme.build(GameAge.teen)), 'body_teen_phone', act: placeTwo);
  });
}
