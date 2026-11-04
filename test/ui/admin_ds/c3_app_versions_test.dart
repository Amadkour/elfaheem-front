// C-round: App versions is ONE page (Build & publish + Update prompt). A super admin sees two tabs, a plain admin only
// the update prompt (no tab bar), the kill switch `admin.app_releases` hides Build, the update prompt still saves the
// same PATCH body, and no layout error at any size.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_app_versions_page.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_page.dart' show kAppReleasesFeatureKey;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';
import 'cfg_support.dart';

void main() {
  late List<String> savedDisable;
  setUp(() {
    AppConfig.lang = 'en';
    savedDisable = [...AppConfig.disableList];
    AppConfig.disableList = [];
  });
  tearDown(() => AppConfig.disableList = savedDisable);

  Future<void> open(WidgetTester tester, Widget page, {String role = 'super-admin'}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = FakeApi(cfgRoutes(), latency: const Duration(milliseconds: 20));
    final auth = await cfgSetUp(api, role: role);
    await tester.pumpWidget(cfgProviders(auth, layoutHost(page, scale: 1, scaffold: false)));
    await cfgPump(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('super admin: two tabs, Build first; Update prompt shows the list', (tester) async {
    await open(tester, const AdminAppVersionsPage());
    expect(find.byType(AppTabs), findsOneWidget);
    expect(find.text('Open App versions'), findsOneWidget);
    expect(find.text('Android'), findsNothing);
    await tester.tap(find.descendant(of: find.byType(AppTabs), matching: find.text('Update prompt')));
    await cfgPump(tester, 4);
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('Add update prompt'), findsOneWidget);
    await close(tester);
  });

  testWidgets('the banner button of the update prompt switches to the Build tab', (tester) async {
    await open(tester, const AdminAppVersionsPage(showUpdatePrompt: true));
    expect(find.text('Android'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin_versions.open_build')));
    await cfgPump(tester, 4);
    expect(find.text('Open App versions'), findsOneWidget);
    await close(tester);
  });

  testWidgets('plain admin: only the update prompt, no tab bar', (tester) async {
    await open(tester, const AdminAppVersionsPage(), role: 'admin');
    expect(find.byType(AppTabs), findsNothing);
    expect(find.text('Open App versions'), findsNothing);
    expect(find.text('Android'), findsOneWidget);
    await close(tester);
  });

  testWidgets('kill switch off: even a super admin gets no Build tab', (tester) async {
    AppConfig.disableList = [kAppReleasesFeatureKey];
    await open(tester, const AdminAppVersionsPage());
    expect(find.byType(AppTabs), findsNothing);
    expect(find.text('Android'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Update prompt: editing sends the same PATCH body as before', (tester) async {
    await open(tester, const AdminAppVersionsPage(showUpdatePrompt: true));
    await tester.tap(find.text('Edit').first);
    await cfgPump(tester, 5);
    await tester.tap(find.text('Save'));
    await cfgPump(tester, 5);
    final key = cfgSent.keys.firstWhere((k) => k.startsWith('PATCH ') && k.endsWith('/app/1'), orElse: () => 'none: ${cfgSent.keys}');
    final body = cfgSent[key]!.single as Map;
    expect(body, {
      'force_update': false,
      'recommend_update': true,
      'is_active': true,
      'min_supported': '1.3.0',
      'release_notes_ar': 'تحسينات في البث المباشر',
      'release_notes_en': 'Live class improvements',
    });
    await close(tester);
  });

  for (final role in ['super-admin', 'admin']) {
    testWidgets('layout ($role)', (tester) async {
      final api = FakeApi(cfgRoutes(), latency: const Duration(milliseconds: 10));
      final auth = await cfgSetUp(api, role: role);
      await expectNoLayoutErrors(tester, () => cfgProviders(auth, const AdminAppVersionsPage()), scaffold: false, frames: 10);
    });
  }
}
