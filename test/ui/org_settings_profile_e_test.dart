// Profile E (D-1081): the organization settings page's profile card (with the organization chip and Switch), the
// shortcut tiles, the quiet red exit rows and the two-column settings page, through expectNoLayoutErrors (320×640
// and 1400×900, ar / en, text ×1.3) with long names and labels.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/features/org/org_dashboard_settings.dart' show OrgProfileCard, OrgShortcut, OrgShortcutRow;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'كلية الحاسبات والمعلومات وتكنولوجيا الاتصالات بجامعة العلمين الجديدة للدراسات العليا';

List<OrgShortcut> _tiles() => [
      for (final (k, icon, label) in [
        ('a', Icons.workspace_premium_rounded, 'تصميمات الشهادات المعتمدة'),
        ('b', Icons.ios_share_rounded, 'Exports and shared links'),
        ('c', Icons.notifications_active_rounded, 'الإشعارات'),
        ('d', Icons.text_fields_rounded, 'Display'),
      ])
        OrgShortcut(key: k, icon: icon, label: label, hint: label, onTap: () {}),
    ];

List<AppSettingsGroup> _groups() => [
      for (var g = 0; g < 4; g++)
        AppSettingsGroup(title: 'Group $g', icon: Icons.settings_rounded, children: [
          for (var i = 0; i < 3 + g; i++) AppSettingsTile(icon: Icons.extension_rounded, label: '$_longAr $i', onTap: () {}),
        ]),
      AppSettingsGroup(title: 'exit'.tr, icon: Icons.exit_to_app_rounded, children: [
        AppSettingsTile(key: const ValueKey('leave'), icon: Icons.logout_rounded, danger: true, label: 'Leave', subtitle: _longAr, onTap: () {}),
        AppSettingsTile(icon: Icons.logout_rounded, danger: true, label: 'logout'.tr, onTap: () {}),
      ]),
    ];

Widget _page() => AppSettingsPage(
      columns: true,
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OrgProfileCard(name: _longAr, role: 'org-admin', email: 'someone.with.a.long.address@example-university.edu.eg', imageUrl: '', org: _longAr, onSwitch: () {}),
        const SizedBox(height: 16),
        OrgShortcutRow(items: _tiles()),
      ]),
      groups: _groups(),
    );

void main() {
  setUp(() => AppConfig.lang = 'ar');

  test('two columns of about the same height, in order', () {
    final g = _groups();
    final cols = appSettingsColumns(g);
    expect([...cols[0], ...cols[1]], g);
    expect(cols[0], isNotEmpty);
    expect(cols[1], isNotEmpty);
  });

  testWidgets('profile E lays out on every size (card, tiles, two columns, exit rows)', (tester) async {
    await expectNoLayoutErrors(tester, () => _page());
  });

  testWidgets('an exit row has no chevron; a normal row has one', (tester) async {
    await tester.pumpWidget(layoutHost(_page(), scale: 1));
    await tester.pumpAndSettle();
    final leave = find.byKey(const ValueKey('leave'));
    expect(find.descendant(of: leave, matching: find.byIcon(Icons.chevron_right_rounded)), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
  });

  testWidgets('a switched-off shortcut leaves no hole', (tester) async {
    AppConfig.setDisableList(['export.studio']);
    addTearDown(() => AppConfig.setDisableList(const []));
    await tester.pumpWidget(layoutHost(OrgShortcutRow(items: [
      OrgShortcut(key: 'x', icon: Icons.ios_share_rounded, label: 'Exports', hint: 'Exports', featureKey: 'export.studio', onTap: () {}),
      OrgShortcut(key: 'y', icon: Icons.text_fields_rounded, label: 'Display', hint: 'Display', onTap: () {}),
    ]), scale: 1));
    expect(find.byKey(const ValueKey('x')), findsNothing);
    expect(find.byKey(const ValueKey('y')), findsOneWidget);
  });
}
