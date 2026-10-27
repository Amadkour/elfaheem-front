// Grouped settings (lib/design/app_settings.dart): header + groups + tiles at 320x640 and 1400x900, Arabic +
// English, textScaler 1.3; the search field appears only past 8 tiles and filters the rows.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة والتكنولوجيا';

List<AppSettingsGroup> groups({bool many = true}) => [
      AppSettingsGroup(title: 'account'.tr, icon: Icons.account_circle_rounded, children: [
        AppSettingsTile(icon: Icons.manage_accounts_rounded, label: 'update_account'.tr, onTap: () {}),
        AppSettingsTile(icon: Icons.lock_reset_rounded, label: 'change_password'.tr, subtitle: longAr, onTap: () {}),
        AppSettingsTile(icon: Icons.language_rounded, label: 'change_language'.tr, keywords: 'لغة language', onTap: () {}),
        AppSettingsTile(
          icon: Icons.dark_mode_rounded,
          label: 'dark_mode'.tr,
          trailing: AppSwitch(value: true, onChanged: (_) {}, semanticLabel: 'dark_mode'.tr),
        ),
      ]),
      if (many)
        AppSettingsGroup(title: longAr, subtitle: longAr, icon: Icons.settings_rounded, children: [
          for (var i = 0; i < 6; i++)
            AppSettingsTile(icon: Icons.extension_rounded, label: 'Service $i', badge: i * 40, onTap: () {}),
        ]),
      AppSettingsGroup(title: 'exit'.tr, icon: Icons.exit_to_app_rounded, danger: true, children: [
        AppSettingsTile(icon: Icons.logout_rounded, label: 'logout'.tr, featureKey: 'profile.logout', onTap: () {}),
      ]),
    ];

Widget page({bool many = true}) => AppSettingsPage(
      header: AppSettingsHeader(name: longAr, role: 'org-admin', email: 'someone@example.com', onEdit: () {}),
      groups: groups(many: many),
      footer: const Text('v1.0'),
    );

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('settings page lays out at both sizes and languages', (tester) async {
    await expectNoLayoutErrors(tester, () => page());
    await expectNoLayoutErrors(tester, () => page(many: false));
  });

  testWidgets('search appears past 8 tiles and filters the rows', (tester) async {
    AppConfig.lang = 'en';
    await tester.pumpWidget(layoutHost(page(many: false)));
    await tester.pump();
    expect(find.byType(TextField), findsNothing, reason: '5 tiles: no search');

    await tester.pumpWidget(layoutHost(page()));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget, reason: '11 tiles: search');
    expect(find.text('Service 3'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'langu');
    await tester.pump();
    expect(find.text('change_language'.tr), findsOneWidget);
    expect(find.text('Service 3'), findsNothing);
    expect(find.text('logout'.tr), findsNothing);
    expect(find.byType(AppSettingsHeader), findsNothing, reason: 'the header steps aside while searching');

    await tester.enterText(find.byType(TextField), 'لغة');
    await tester.pump();
    expect(find.text('change_language'.tr), findsOneWidget, reason: 'keywords match the other language');

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('settings_no_match'.tr), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('Service 3'), findsOneWidget);
    expect(find.byType(AppSettingsHeader), findsOneWidget);
    expect(find.text('80'), findsOneWidget, reason: 'the badge pill');
  });
}
