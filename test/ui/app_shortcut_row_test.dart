// Profile E on the personal account page (D-1081): the kit's shortcut tiles (AppShortcutRow) lay out on every screen
// size with long labels, a kill-switched tile leaves no hole, and every tile stays tappable.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'شهاداتي ودرجاتي في كل الكورسات التي أكملتها هذا العام';

List<AppShortcut> _tiles(List<String> tapped) => [
      for (final (k, icon, label, key) in [
        ('grades', Icons.workspace_premium_rounded, _longAr, 'profile.my_certificates'),
        ('fav', Icons.favorite_rounded, 'My favourite courses', 'profile.my_favorite'),
        ('points', Icons.stars_rounded, 'محفظة النقاط', 'points.wallet'),
        ('pay', Icons.receipt_long_rounded, 'Payments and subscriptions', 'profile.my_payments'),
      ])
        AppShortcut(key: 'shortcut.$k', featureKey: key, icon: icon, label: label, hint: label, onTap: () => tapped.add(k)),
    ];

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });
  tearDown(() => AppConfig.disableList = []);

  testWidgets('the shortcut tiles lay out on every screen size', (t) async {
    await expectNoLayoutErrors(t, () => Column(children: [AppShortcutRow(items: _tiles([])), const AppVersionLine()]));
  });

  testWidgets('a switched-off tile leaves no hole and the others still tap', (t) async {
    final tapped = <String>[];
    AppConfig.disableList = ['profile.my_favorite'];
    await t.pumpWidget(layoutHost(AppShortcutRow(items: _tiles(tapped)), scale: 1));
    expect(find.byKey(const ValueKey('shortcut.fav')), findsNothing);
    expect(find.byType(InkWell), findsNWidgets(3));
    await t.tap(find.byKey(const ValueKey('shortcut.pay')));
    expect(tapped, ['pay']);
  });

  testWidgets('every tile switched off draws nothing', (t) async {
    AppConfig.disableList = ['profile.my_certificates', 'profile.my_favorite', 'points.wallet', 'profile.my_payments'];
    await t.pumpWidget(layoutHost(AppShortcutRow(items: _tiles([])), scale: 1));
    expect(find.byType(InkWell), findsNothing);
  });
}
