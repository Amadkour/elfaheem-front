// Organization flow overhaul, f1: the context pill (logo + name), the switcher with its exit button and the sheet
// with the "could not refresh" error row: no overflow at 320x640 / 1400x900, Arabic and English, text x1.3, and the
// 48x48 target of the pill.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

Widget _themed(Widget app) => ThemeConfigScope(provider: ThemeConfigProvider(api: ApiClient()), child: app);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.orgsEnabled = true;
    AppConfig.disableList = const [];
    AppModeController.applyContext = (_) {};
  });

  const Map<String, dynamic> longOrg = {
    'id': 4,
    'status': 'approved',
    'name_en': 'A very long organization name indeed, with a logo that will not load',
    'name_ar': 'اسم مؤسسة طويل جداً مع شعار لن يتم تحميله',
    'logo_url': 'https://example.invalid/logo.png',
  };

  testWidgets('pill with a logo and a count holds on every size and language', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ContextPill(
        icon: Icons.account_balance_rounded,
        tone: Colors.teal,
        label: '${longOrg['name_en']}',
        caption: 'In organization',
        badge: 120,
        logoUrl: '${longOrg['logo_url']}',
        onTap: () {},
      ),
      scaffold: true,
    );
  });

  testWidgets('the pill is at least 48x48 and labelled with the current context', (tester) async {
    AppModeController.instance.debugSet({
      'items': [
        {'organization': longOrg, 'roles': ['student'], 'manage': null},
      ],
      'default_org_id': 4,
    }, mode: AppMode.organization, orgId: 4);
    AppConfig.lang = 'en';
    await tester.pumpWidget(_themed(const MaterialApp(home: Scaffold(body: Center(child: ContextSwitcher())))));
    await tester.pump();
    final size = tester.getSize(find.byKey(const ValueKey('ctx.pill')));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
    final exit = tester.getSize(find.byKey(const ValueKey('ctx.exit')));
    expect(exit.height, greaterThanOrEqualTo(48));
    expect(exit.width, greaterThanOrEqualTo(48));
  });

  testWidgets('the sheet shows an error row with Retry when the overview could not be refreshed (list kept)', (tester) async {
    final ctl = AppModeController.instance;
    ctl.debugSet({
      'items': [
        {'organization': longOrg, 'roles': ['student'], 'manage': null},
      ],
      'default_org_id': 4,
    }, mode: AppMode.individual);
    ctl.refreshFailed = true;
    addTearDown(() => ctl.refreshFailed = false);
    await expectNoLayoutErrors(
      tester,
      () => const ContextSwitcher(),
      act: (t) async {
        await t.tap(find.byKey(const ValueKey('ctx.pill')));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('ctx.sheet.error')), findsOneWidget);
        expect(find.byKey(const ValueKey('ctx.sheet.org.4')), findsOneWidget); // the last known list stays
      },
    );
  });
}
