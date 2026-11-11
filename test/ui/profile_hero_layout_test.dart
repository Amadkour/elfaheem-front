// The Account page's hero block (ProfileHero, Warm Editorial) at 320x640 and 1400x900, Arabic + English, textScaler
// 1.3: a long name with every chip (the masthead on wide windows, the centred stack on phones), a name without a
// picture or username, an empty name, and no edit action; plus the old SettingsGroup / SettingsTile names, which now
// draw the kit's settings group.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_group.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_title.dart';
import 'package:flutter_education_app/features/shared/profile/profile_hero.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longName = 'عبد الرحمن محمد عبد العزيز الشريف Abdulrahman Mohammed Abdulaziz Alsharif';

void main() {
  Widget page(Widget hero) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: hero,
      );

  testWidgets('long name, every chip, edit action', (tester) async {
    var edits = 0;
    await expectNoLayoutErrors(
      tester,
      () => page(ProfileHero(
        name: _longName,
        role: 'teacher',
        email: 'abdulrahman.mohammed.alsharif@a-very-long-school-domain.example.test',
        username: 'abdulrahman.mohammed_alsharif',
        onEdit: () => edits++,
      )),
    );
  });

  testWidgets('no picture, no username, no edit', (tester) async {
    await expectNoLayoutErrors(tester, () => page(const ProfileHero(name: 'Sara', role: 'student')));
  });

  testWidgets('empty name', (tester) async {
    await expectNoLayoutErrors(tester, () => page(ProfileHero(name: '', onEdit: () {})));
  });

  testWidgets('the edit action opens from the avatar', (tester) async {
    var edits = 0;
    await expectNoLayoutErrors(
      tester,
      () => page(ProfileHero(name: 'Mariam Adel', role: 'student', onEdit: () => edits++)),
      act: (t) async {
        expect(find.text('Mariam Adel'), findsOneWidget);
        await t.tap(find.byIcon(Icons.photo_camera_rounded));
      },
    );
    expect(edits, greaterThan(0));
  });

  testWidgets('the older SettingsGroup / SettingsTile', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => page(SettingsGroup(title: 'Cloud — connected drives and recordings', icon: Icons.cloud_rounded, children: [
        SettingsTile(
          icon: Icons.cloud_sync_rounded,
          iconBg: Colors.transparent,
          iconColor: Colors.teal,
          label: 'Connected drives for meeting recordings and their exports',
          onTap: () {},
        ),
      ])),
    );
  });
}
