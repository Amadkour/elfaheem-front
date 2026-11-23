// VISUAL review renders of the winner trophy and the locked / unlocked coupon card (Games v4 T74): kids and adult,
// phone and desktop, Arabic, into test/visual/goldens/games_unlock_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/games_unlock_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/champions/trophy.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/learner/coupon_unlock_card.dart';
import 'package:flutter_education_app/features/rewards/rewards_models.dart';
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
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll(String.fromCharCode(92), '/');
  final sdk = '${root != null && root.isNotEmpty ? root : exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _now = DateTime.utc(2026, 11, 24, 10);
final _shot = GlobalKey();

Coupon _coupon({required bool locked}) => Coupon.fromJson({
      'id': 9, 'code': 'K7M2PQ4XTH', 'status': locked ? 'locked' : 'active', 'kind': 'percent', 'value': 20.0, 'currency': 'EGP',
      'max_discount': 200.0, 'applies_to': 'course', 'source': 'champion_daily', 'issued_at': '2026-11-23T10:00:00',
      'expires_at': locked ? null : '2026-11-25T09:30:00',
      'unlock': {'need': 3, 'have': locked ? 2 : 3, 'deadline': '2026-11-30T10:00:00', 'unlocked_at': locked ? null : '2026-11-24T09:30:00'},
      'course_ids': null, 'valid_hours': 24,
    });

void main() {
  setUpAll(_loadFonts);
  const sizes = {'phone': Size(390, 780), 'desktop': Size(1280, 800)};

  Future<void> shoot(WidgetTester tester, Size size, Widget Function() build, String name, {bool pad = true}) async {
    AppConfig.lang = 'ar';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(layoutHost(RepaintBoundary(key: _shot, child: build()), scale: 1, scaffold: pad));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_unlock_$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  for (final s in sizes.entries) {
    for (final age in [GameAge.kids, GameAge.adult]) {
      final th = AgeTheme.build(age);
      testWidgets('trophy ${age.name} ${s.key}', (tester) async {
        await shoot(
          tester,
          s.value,
          () => Material(
            child: AgeThemeScope(
              theme: th,
              child: WinTrophyScene(theme: th, headline: 'ما شاء الله، أنت بطل اليوم', line: 'الأطفال ٦–٩ · ٢٣ نوفمبر ٢٠٢٦', onContinue: () {}),
            ),
          ),
          'trophy_${age.name}_${s.key}',
          pad: false,
        );
      });
    }
    for (final locked in [true, false]) {
      testWidgets('card ${locked ? 'locked' : 'unlocked'} ${s.key}', (tester) async {
        await shoot(
          tester,
          s.value,
          () => Material(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: CouponUnlockCard(coupon: _coupon(locked: locked), now: _now, onShare: () {}, onChooseCourse: () {}),
                ),
              ),
            ),
          ),
          'card_${locked ? 'locked' : 'unlocked'}_${s.key}',
        );
      });
    }
  }
}
