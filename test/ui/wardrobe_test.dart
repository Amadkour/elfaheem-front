// Games v4 T73: the wardrobe (character preview, tabs by slot, owned / price / locked cards) and the coins pill.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/learner/wardrobe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> item(String key, String slot, String ar, String en, int price, {bool owned = false, bool equipped = false, Map<String, dynamic>? locked}) =>
    {'key': key, 'slot': slot, 'name_ar': ar, 'name_en': en, 'price_coins': price, 'owned': owned, 'equipped': equipped, 'locked': locked};

List<V4CosmeticItem> itemsOf() => [
      for (final m in [
        item('hat_explorer', 'hat', 'قبعة المستكشف', 'Explorer hat', 30, owned: true, equipped: true),
        item('hat_crown', 'hat', 'تاج البطل', 'Champion crown', 0, locked: {'type': 'champion', 'count': 1, 'have': 0}),
        item('hat_cap', 'hat', 'قبعة رياضية طويلة الاسم جدا', 'A sporty cap with a very long name', 500),
        item('outfit_traveller', 'outfit', 'ثوب المسافر', 'Traveller outfit', 60),
        item('outfit_astro', 'outfit', 'بدلة رائد الفضاء', 'Astronaut suit', 0, locked: {'type': 'stars', 'count': 30, 'have': 12}),
        item('vehicle_rocket', 'vehicle', 'صاروخ', 'Rocket', 80),
        item('vehicle_racer', 'vehicle', 'سيارة سباق', 'Racer', 0, locked: {'type': 'levels', 'count': 10, 'have': 3}),
        item('trail_stars', 'trail', 'أثر النجوم', 'Star trail', 40),
      ])
        V4CosmeticItem(m),
    ];

Widget view({String band = '10-13', int tab = 0, int coins = 54, ValueChanged<V4CosmeticItem>? onBuy, ValueChanged<V4CosmeticItem>? onTry, ValueChanged<V4CosmeticItem>? onEquip}) {
  final theme = AgeTheme.build(GameAge.fromBand(band));
  return AgeThemeScope(
    theme: theme,
    child: WardrobeView(
      coins: coins,
      items: itemsOf(),
      equipped: const {'hat': 'hat_explorer'},
      theme: theme,
      tab: tab,
      onBuy: onBuy,
      onTry: onTry,
      onEquip: onEquip,
    ),
  );
}

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('wardrobe: no layout errors, every age and slot', (tester) async {
    for (final band in ['6-9', '18+']) {
      for (var tab = 0; tab < 4; tab++) {
        await expectNoLayoutErrors(tester, () => view(band: band, tab: tab), scaffold: true);
      }
    }
  });

  testWidgets('coins pill: no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => AgeThemeScope(theme: AgeTheme.build(GameAge.kids), child: const CoinsPill(coins: 123456)), scaffold: true);
  });

  testWidgets('cards: wear, buy, locked has no button, too poor is disabled', (tester) async {
    AppConfig.lang = 'en';
    final log = <String>[];
    await tester.pumpWidget(layoutHost(view(onBuy: (i) => log.add('buy ${i.key}'), onEquip: (i) => log.add('equip ${i.key}'), onTry: (i) => log.add('try ${i.key}')), scale: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Take off'), findsOneWidget);
    expect(find.byKey(const ValueKey('games.wardrobe.buy.hat_crown')), findsNothing);
    expect(find.text('Champion crown'), findsOneWidget);
    expect(find.text('Win a championship once'), findsOneWidget);
    expect(find.text('Need 446 more'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('games.wardrobe.equip.hat_explorer')));
    await tester.tap(find.byKey(const ValueKey('games.wardrobe.item.hat_cap')));
    expect(log, ['equip hat_explorer', 'try hat_cap']);
  });

  testWidgets('buy is enabled when the coins cover the price', (tester) async {
    AppConfig.lang = 'en';
    final log = <String>[];
    await tester.pumpWidget(layoutHost(view(tab: 1, coins: 100, onBuy: (i) => log.add(i.key)), scale: 1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('games.wardrobe.buy.outfit_traveller')));
    expect(log, ['outfit_traveller']);
    expect(find.text('Stars: 12 / 30'), findsOneWidget);
  });

  testWidgets('coins pill counts down and floats the spend', (tester) async {
    AppConfig.lang = 'en';
    final theme = AgeTheme.build(GameAge.kids);
    Widget host(int n) => layoutHost(AgeThemeScope(theme: theme, child: Center(child: CoinsPill(coins: n))), scale: 1);
    await tester.pumpWidget(host(100));
    await tester.pumpWidget(host(60));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('-40'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('60'), findsOneWidget);
    expect(find.text('-40'), findsNothing);
  });
}
