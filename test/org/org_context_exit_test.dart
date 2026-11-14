// Item 6 — leaving an organization / department for the personal space: the org context is cleared, org pages are
// closed (an org root page is replaced by the personal dashboard) and the choice is remembered per user.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/layout_harness.dart';

final overview = {
  'items': [
    {'organization': {'id': 4, 'status': 'approved', 'name_en': 'Uni'}, 'manage': null},
  ],
  'default_org_id': 4,
};

Widget _themed(Widget app) => ThemeConfigScope(provider: ThemeConfigProvider(api: ApiClient()), child: app);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.orgsEnabled = true;
    AppModeController.applyContext = (_) {};
  });

  test('applyOrgContext in Individual mode clears the management dashboard context', () {
    final applied = <int?>[];
    final ctl = AppModeController.instance;
    ctl.debugSet(overview, mode: AppMode.individual);
    AppModeController.applyContext = applied.add;
    ctl.applyOrgContext();
    expect(applied, [null]);
  });

  test('cold-start home of org roles follows the remembered personal choice', () {
    expect(AppModeController.orgRoleHome('/org_dashboard'), '/org_dashboard');
    expect(AppModeController.orgRoleHome('/org_member', personal: false), '/org_member');
    expect(AppModeController.orgRoleHome('/org_dashboard', personal: true), AppModeController.personalRoute);
    expect(AppModeController.isOrgRoute('/org_member'), isTrue);
    expect(AppModeController.isOrgRoute('/dashboard'), isFalse);
    expect(AppModeController.personalHomeKey(7), 'app_mode_personal.7');
  });

  testWidgets('exit button on an org root page lands on the personal dashboard', (tester) async {
    final ctl = AppModeController.instance;
    ctl.debugSet(overview, mode: AppMode.organization, orgId: 4);
    await tester.pumpWidget(_themed(MaterialApp(
      initialRoute: '/org_member',
      onGenerateInitialRoutes: (name) => [
        MaterialPageRoute(
            settings: RouteSettings(name: name),
            builder: (_) => Scaffold(appBar: AppBar(actions: const [ContextExitButton()]), body: const Text('org'))),
      ],
      onGenerateRoute: (s) => MaterialPageRoute(settings: s, builder: (_) => Text('home ${s.name}')),
    )));
    await tester.tap(find.byKey(const ValueKey('ctx.leave')));
    await tester.pumpAndSettle();
    expect(ctl.isOrg, isFalse);
    expect(find.text('home /dashboard'), findsOneWidget);
    expect(find.text('org'), findsNothing);
  });

  testWidgets('exit from a pushed org page pops back to the personal home', (tester) async {
    final ctl = AppModeController.instance;
    ctl.debugSet(overview, mode: AppMode.organization, orgId: 4);
    await tester.pumpWidget(_themed(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(appBar: AppBar(actions: const [ContextExitButton()]), body: const Text('dept')))),
          child: const Text('personal'),
        ),
      ),
    )));
    await tester.tap(find.text('personal'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ctx.leave')));
    await tester.pumpAndSettle();
    expect(find.text('dept'), findsNothing);
    expect(find.text('personal'), findsOneWidget);
    expect(ctl.isOrg, isFalse);
  });

  testWidgets('exit button lays out everywhere', (tester) async {
    await expectNoLayoutErrors(tester, () => const Align(alignment: AlignmentDirectional.topEnd, child: ContextExitButton()));
  });
}
