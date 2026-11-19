// The Account page's hero block (ProfileHero, Warm Editorial) at 320x640 and 1400x900, Arabic + English, textScaler
// 1.3: a long name with every chip (the masthead on wide windows, the centred stack on phones), a name without a
// picture or username, an empty name, and no edit action; plus the old SettingsGroup / SettingsTile names, which now
// draw the kit's settings group.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/profile/components/setting_group.dart';
import 'package:flutter_education_app/features/profile/components/setting_title.dart';
import 'package:flutter_education_app/features/profile/profile_hero.dart';
import 'package:flutter_education_app/features/profile/profile_screen.dart' show profileSectionColumns;
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

  testWidgets('figures and both actions (D-713)', (tester) async {
    var shares = 0;
    var exits = 0;
    await expectNoLayoutErrors(
      tester,
      () => page(ProfileHero(
        name: _longName,
        role: 'teacher',
        email: 'abdulrahman.mohammed.alsharif@a-very-long-school-domain.example.test',
        username: 'abdulrahman',
        onEdit: () {},
        onShare: () => shares++,
        // the exits in the header (D-1190): four buttons at 320 px and text 1.3 still fit
        onLogout: () => exits++,
        onDeleteAccount: () => exits++,
        stats: const [
          ProfileHeroStat(icon: Icons.menu_book_rounded, value: '128', label: 'Courses and learning paths'),
          ProfileHeroStat(icon: Icons.groups_rounded, value: '1250000', label: 'Students'),
          ProfileHeroStat(icon: Icons.star_rounded, value: '4.9', label: 'Rating'),
          ProfileHeroStat(icon: Icons.star_rounded, value: '9', label: 'A fourth figure is never drawn'),
        ],
      )),
      act: (t) async {
        expect(find.text('A fourth figure is never drawn'), findsNothing);
        await t.tap(find.byIcon(Icons.ios_share_rounded));
        await t.tap(find.byKey(const ValueKey('profile.hero.logout')));
        await t.tap(find.byKey(const ValueKey('profile.hero.delete')));
      },
    );
    expect(shares, greaterThan(0));
    expect(exits, greaterThan(1));
  });

  test('profile sections split into two columns of about the same height', () {
    expect(profileSectionColumns([6, 4, 2, 4, 6, 7, 2], 1), [
      [0, 1, 2, 3, 4, 5, 6],
    ]);
    final cols = profileSectionColumns([6, 4, 2, 4, 6, 7, 2], 2);
    expect(cols.expand((c) => c).toList()..sort(), [0, 1, 2, 3, 4, 5, 6]);
    double h(List<int> c) => c.fold(0.0, (a, i) => a + 1.5 + [6, 4, 2, 4, 6, 7, 2][i]);
    expect((h(cols[0]) - h(cols[1])).abs(), lessThanOrEqualTo(8.5), reason: 'never more than one section apart');
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
