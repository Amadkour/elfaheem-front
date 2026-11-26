// Games v4 T72: the learner's games home (subjects, level map, Review chip, coins) and the settings sheet on a phone and a
// wide window, ar / en, text 1.3. Also the hooks: locked tap, kill switch, Tanzil credit.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/learner/games_home_v4.dart';
import 'package:flutter_education_app/features/games/learner/games_settings_sheet.dart';
import 'package:flutter_education_app/features/games/learner/level_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> level(int id, int no, {int stars = 0, bool locked = false}) => {
      'id': id,
      'key': 'k$id',
      'engine': 'verse_builder',
      'title_ar': 'سورة الإخلاص ومعها عنوان طويل جدا $no',
      'title_en': 'Surah Al-Ikhlas with a very long title $no',
      'template': 'verse_builder',
      'game_subject_id': 1,
      'topic': 'juz_30/112',
      'level_no': no,
      'unlock': {'mode': 'prev', 'min_stars': 1},
      'locked': locked,
      'sacred': true,
      'progress': stars == 0 ? null : {'game_id': id, 'best_score': 4, 'stars': stars, 'plays': 1, 'attempts': 1},
    };

V4Home homeOf({String band = '10-13'}) => V4Home({
      'profile': {'age_band': band, 'age_source': 'dob', 'needs_age': false, 'coins': 54, 'equipped': {}, 'sky': [], 'reciter_key': null, 'reciter_effective': 'alafasy', 'can_review': false},
      'subjects': [
        {'id': 1, 'key': 'quran', 'name_ar': 'القرآن الكريم', 'name_en': 'Quran', 'icon': 'menu_book', 'color': '#2E7D6B', 'sacred': true, 'levels': 7, 'done': 3, 'stars': 7},
        {'id': 2, 'key': 'math', 'name_ar': 'الرياضيات', 'name_en': 'Math', 'icon': 'calculate', 'color': '#3B6FD4', 'sacred': false, 'levels': 12, 'done': 0, 'stars': 0},
        {'id': 3, 'key': 'science', 'name_ar': 'العلوم', 'name_en': 'Science', 'icon': 'science', 'color': '#C2562E', 'sacred': false, 'levels': 9, 'done': 9, 'stars': 24},
      ],
      'templates': [],
      'continue': level(14, 4),
      'review_due': 6,
      'review_levels': [{'game_id': 11, 'due': 4}],
      'flags': {'cosmetics': true},
    });

List<V4Level> levelsOf() => [
      V4Level(level(11, 1, stars: 3)),
      V4Level(level(12, 2, stars: 2)),
      V4Level(level(13, 3, stars: 1)),
      V4Level(level(14, 4)),
      V4Level(level(15, 5, locked: true)),
      V4Level(level(16, 6, locked: true)),
      V4Level(level(17, 7, locked: true)),
    ];

Widget view({String band = '10-13', List<V4Level>? levels, ValueChanged<V4Level>? onOpen}) =>
    GamesHomeV4View(home: homeOf(band: band), levels: levels ?? levelsOf(), subjectId: 1, onOpen: onOpen, showCoins: true);

void main() {
  testWidgets('home: no layout errors, every age', (tester) async {
    for (final band in ['6-9', '10-13', '18+']) {
      await expectNoLayoutErrors(tester, () => view(band: band), scaffold: true);
    }
  });

  testWidgets('home: empty and loading levels', (tester) async {
    await expectNoLayoutErrors(tester, () => GamesHomeV4View(home: homeOf(), levels: const [], subjectId: 1));
    await expectNoLayoutErrors(tester, () => GamesHomeV4View(home: homeOf(), levels: null, subjectId: 1, levelsLoading: true));
  });

  testWidgets('tapping an open node plays it, a locked one only explains', (tester) async {
    AppConfig.lang = 'en';
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    V4Level? opened;
    final sem = tester.ensureSemantics();
    addTearDown(sem.dispose);
    await tester.pumpWidget(layoutHost(view(onOpen: (l) => opened = l)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('games.v4.node.12')));
    expect(opened?.id, 12);
    opened = null;
    await tester.tap(find.byKey(const ValueKey('games.v4.node.16')));
    expect(opened, isNull);
    expect(find.byKey(const ValueKey('games.v4.tanzil')), findsOneWidget);
    // what the tap can open (review_levels), not every due item
    expect(find.bySemanticsLabel('Review, 4 due'), findsOneWidget);
    expect(find.byKey(const ValueKey('games.v4.coins')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('unlock rule text and the current node', () {
    AppConfig.lang = 'en';
    final nodes = levelNodes(levelsOf());
    expect(nodes[4].unlockText, 'Earn 1 star in level 4 to open this one');
    expect(currentNodeId(nodes), 14);
    expect(currentNodeId(nodes, preferred: 13), 13);
  });

  testWidgets('settings body: reciters, sample, fixed age, credits', (tester) async {
    final rs = [
      GameReciter(key: 'alafasy', nameAr: 'مشاري العفاسي', nameEn: 'Mishary Alafasy', sample: const RecitationSegment(url: 'https://x/a.mp3')),
      const GameReciter(key: 'husary_muallim', nameAr: 'الحصري (المعلّم)', nameEn: 'Al-Husary (Muallim)'),
    ];
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: GamesSettingsBody(reciters: rs, selectedReciter: 'alafasy', onReciter: (_) {}, onSample: (_) {}, ageBand: '10-13', ageEditable: false),
            ));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: GamesSettingsBody(reciters: null, selectedReciter: null, ageBand: null, ageEditable: true, onAge: (_) {})));
  });
}
