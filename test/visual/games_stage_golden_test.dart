// Visual review of the Games v4 stage bases (T37): Challenge Quiz and Verse Builder per age theme, phone and desktop,
// Arabic, a long ayah with tashkeel. Compared by eye:
//
//   flutter test test/visual/games_stage_golden_test.dart --update-goldens
//
// → test/visual/goldens/games_stage_<scene>.png
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';
import 'package:flutter_education_app/features/games/templates/challenge_quiz/challenge_quiz.dart';
import 'package:flutter_education_app/features/games/templates/verse_builder/verse_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../games/v4_stage_test.dart' show kLongAyah, selectAll, seq;
import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

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
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

const _phone = Size(390, 844);
const _desktop = Size(1280, 800);
final _shot = GlobalKey();

GameItem _mcqAr(int n, {bool sacred = false}) => GameItem.fromJson({
      'type': 'mcq',
      'sacred': sacred,
      'prompt': {'ar': sacred ? 'ما الآية التي تلي: «قُلْ هُوَ ٱللَّهُ أَحَدٌ»؟' : 'ما هي عاصمة مصر؟', 'en': 'What is the capital of Egypt?'},
      'explain': {'ar': null, 'en': null},
      'source': sacred ? {'kind': 'quran', 'ref': '112:2', 'label': {'ar': 'الإخلاص', 'en': 'Al-Ikhlas'}} : null,
      'body': {
        'options': sacred
            ? [
                {'text': 'ٱللَّهُ ٱلصَّمَدُ'},
                {'text': 'لَمْ يَلِدْ وَلَمْ يُولَدْ'},
                {'text': 'وَلَمْ يَكُن لَّهُۥ كُفُوًا أَحَدٌۢ'},
              ]
            : [
                {'text': 'الإسكندرية'},
                {'text': 'القاهرة'},
                {'text': 'الجيزة'},
                {'text': 'الأقصر'},
              ],
        'answer': 1,
        'show': sacred ? [0, 1, 2] : [0, 1, 2, 3],
      },
    }, n: n)!;

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  setUp(() {
    AppConfig.lang = 'ar';
    GameFeedback.instance.reset();
  });

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    required Size size,
    required GameAge age,
    required Widget Function(GameSession) game,
    required GameSession session,
    bool calm = false,
    bool dark = false,
    Future<void> Function()? act,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    final theme = ThemeConfigProvider(api: ApiClient());
    await tester.pumpWidget(ThemeConfigScope(
      provider: theme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme(dark: false),
        darkTheme: theme.materialTheme(dark: true),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, w) => Directionality(textDirection: AppConfig.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr, child: w!),
        home: Scaffold(
          body: RepaintBoundary(
            key: _shot,
            child: AgeThemeScope(theme: AgeTheme.build(age, calm: calm, night: dark), child: game(session)),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (act != null) {
      await act();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(tester.takeException(), isNull);
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_stage_$name.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  GameSession mk(List<GameItem> items, {bool sacred = false, GameSettings? settings}) => GameSession(
        items: items,
        sacred: sacred,
        settings: settings ?? GameSettings.fromJson({'timer_s': 0}, sacred: sacred),
      )..start();

  testWidgets('quiz kids phone: a right answer', (tester) async {
    await shoot(tester, 'quiz_kids_phone',
        size: _phone,
        age: GameAge.kids,
        session: mk([_mcqAr(0), _mcqAr(1)]),
        game: (s) => ChallengeQuizGame(session: s, silent: true),
        act: () async => tester.tap(find.byKey(const ValueKey('opt-1'))));
  });

  testWidgets('quiz adult desktop: select all', (tester) async {
    AppConfig.lang = 'en';
    await shoot(tester, 'quiz_adult_desktop',
        size: _desktop,
        age: GameAge.adult,
        session: mk([selectAll(0), selectAll(1)]),
        game: (s) => ChallengeQuizGame(session: s, silent: true),
        act: () async {
          await tester.tap(find.byKey(const ValueKey('opt-0')));
          await tester.tap(find.byKey(const ValueKey('opt-3')));
        });
  });

  testWidgets('quiz calm phone: a sacred wrong pick is amber', (tester) async {
    await shoot(tester, 'quiz_calm_phone',
        size: _phone,
        age: GameAge.adult,
        calm: true,
        session: mk([_mcqAr(0, sacred: true)], sacred: true),
        game: (s) => ChallengeQuizGame(session: s, silent: true),
        act: () async => tester.tap(find.byKey(const ValueKey('opt-0'))));
  });

  testWidgets('verse calm phone: a long ayah, four words placed', (tester) async {
    await shoot(tester, 'verse_calm_phone',
        size: _phone,
        age: GameAge.adult,
        calm: true,
        session: mk([seq(0, kLongAyah, sacred: true, extra: ['ٱلصَّمَدُ', 'كُفُوًا'])], sacred: true),
        game: (s) => VerseBuilderGame(session: s, silent: true),
        act: () async {
          for (var k = 0; k < 4; k++) {
            await tester.tap(find.byKey(ValueKey('tray-$k')));
            await tester.pump(const Duration(milliseconds: 300));
          }
        });
  });

  testWidgets('verse kids phone: complete mode with a wrong flash', (tester) async {
    await shoot(tester, 'verse_kids_phone',
        size: _phone,
        age: GameAge.kids,
        session: mk([seq(0, ['الشمس', 'نجم', 'كبير', 'جدا'], blanks: [1, 2], extra: ['صغير', 'بعيد'])]),
        game: (s) => VerseBuilderGame(session: s, silent: true),
        act: () async {
          await tester.tap(find.byKey(const ValueKey('tray-4')));
          await tester.pump(const Duration(milliseconds: 150));
        });
  });

  testWidgets('verse teen phone: order', (tester) async {
    await shoot(tester, 'verse_teen_phone',
        size: _phone,
        age: GameAge.teen,
        session: mk([seq(0, ['العلم', 'نور', 'والجهل', 'ظلام'], extra: ['قوة'])]),
        game: (s) => VerseBuilderGame(session: s, silent: true),
        act: () async {
          await tester.tap(find.byKey(const ValueKey('tray-0')));
          await tester.pump(const Duration(milliseconds: 300));
        });
  });

  testWidgets('verse adult desktop: a long ayah', (tester) async {
    await shoot(tester, 'verse_adult_desktop',
        size: _desktop,
        age: GameAge.adult,
        calm: true,
        session: mk([seq(0, kLongAyah, sacred: true, extra: ['ٱلصَّمَدُ', 'كُفُوًا'])], sacred: true),
        game: (s) => VerseBuilderGame(session: s, silent: true),
        act: () async {
          for (var k = 0; k < 3; k++) {
            await tester.tap(find.byKey(ValueKey('tray-$k')));
            await tester.pump(const Duration(milliseconds: 300));
          }
        });
  });
}
