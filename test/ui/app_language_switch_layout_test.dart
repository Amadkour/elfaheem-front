// The inline language switch (lib/design/app_language_switch.dart, D-088): the segmented pill and the settings row
// at 320x640 / 1400x900, Arabic + English, text x1.3; each segment is a 48 dp target; a tap on the other language
// reports it (the current one is inert).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/design/app_language_switch.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

void main() {
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    AppConfig.lang = 'ar';
  });

  testWidgets('segmented switch: no overflow, 48 dp segments, the other language is the tap', (tester) async {
    final picked = <String>[];
    await expectNoLayoutErrors(
      tester,
      () => Center(child: AppLanguageSegmented(current: 'ar', onChanged: picked.add)),
      act: (t) async {
        final en = find.bySemanticsLabel('English');
        expect(t.getSize(en).height, greaterThanOrEqualTo(48));
        expect(t.getSize(en).width, greaterThanOrEqualTo(48));
        await t.tap(en);
        await t.tap(find.bySemanticsLabel('العربية')); // the current one: inert
      },
    );
    expect(picked, isNotEmpty);
    expect(picked.toSet(), {'en'});
  });

  testWidgets('the settings row holds the switch on every size and language', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ChangeNotifierProvider(
        create: (_) => LangProvider(storage: storage),
        child: const AppSettingsGroup(title: 'x', icon: Icons.settings_rounded, children: [AppLanguageTile()]),
      ),
    );
  });
}
