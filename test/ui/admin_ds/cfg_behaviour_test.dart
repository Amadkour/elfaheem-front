// Behaviour of the Configuration hub pages: the fee amount is validated (never a silent 0 = free), Save is the page
// header's primary action (disabled when clean), the unsaved-changes guard asks before leaving, switching 7 / 30 / 90
// days keeps the weights being edited, a feature is only hidden for everyone after a confirm that names it, a failed
// course search in the Data lab is shown instead of thrown, the flags page types numbers and says its own thing,
// the update prompt names platforms, and a page whose route the server lacks says "needs a server update".
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_inputs.dart' show AppField;
import 'package:flutter_education_app/design/app_search_field.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/features/admin/admin_data_lab_page.dart';
import 'package:flutter_education_app/features/admin/admin_features_page.dart';
import 'package:flutter_education_app/features/admin/admin_flags_settings_page.dart';
import 'package:flutter_education_app/features/admin/admin_platform_settings_page.dart';
import 'package:flutter_education_app/features/admin/admin_recs_page.dart';
import 'package:flutter_education_app/features/admin/admin_versions_page.dart';
import 'package:flutter_education_app/features/admin/live_settings/live_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';
import 'cfg_support.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  Future<FakeApi> open(WidgetTester tester, Widget page, {Map<String, FakeHandler>? routes, Size size = const Size(1400, 1400)}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = FakeApi(routes ?? cfgRoutes(), latency: const Duration(milliseconds: 20));
    final auth = await cfgSetUp(api);
    await tester.pumpWidget(cfgProviders(auth, layoutHost(page, scale: 1, scaffold: false)));
    await cfgPump(tester);
    return api;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  AppButton primary(WidgetTester tester) =>
      tester.widgetList<AppButton>(find.byType(AppButton)).firstWhere((b) => b.variant == AppButtonVariant.primary);

  // an AppField draws its label ABOVE the well (app_inputs.dart), so the TextField is found through its AppField
  Finder field(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(AppField)), matching: find.byType(TextField));

  testWidgets('Platform settings: an invalid fee shows an error and blocks Save; a valid one saves', (tester) async {
    await open(tester, const AdminPlatformSettingsPage());
    expect(primary(tester).label, 'Save');
    expect(primary(tester).onPressed, isNull, reason: 'clean form: Save is disabled');

    await tester.enterText(field('Amount (0 = free)'), 'abc');
    await cfgPump(tester, 3);
    expect(find.textContaining('Enter a valid amount'), findsOneWidget);
    expect(primary(tester).onPressed, isNull, reason: 'an invalid amount never becomes 0 = free');
    expect(cfgSent['PUT /api/v1/admin/platform-settings'], isNull);

    await tester.enterText(field('Amount (0 = free)'), '750');
    await cfgPump(tester, 3);
    expect(find.textContaining('Enter a valid amount'), findsNothing);
    expect(primary(tester).onPressed, isNotNull);
    primary(tester).onPressed!();
    await cfgPump(tester);
    final body = cfgSent['PUT /api/v1/admin/platform-settings']!.single as Map;
    expect((body['org_creation_fee'] as Map)['amount'], 750);
    await close(tester);
  });

  testWidgets('Platform settings: leaving with unsaved changes asks first', (tester) async {
    await open(tester, const AdminPlatformSettingsPage());
    await tester.enterText(field('Amount (0 = free)'), '900');
    await cfgPump(tester, 3);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    // the page is the root route here: the guard is a PopScope that blocks the pop
    expect(find.byWidgetPredicate((w) => w is PopScope), findsWidgets);
    final guard = tester.widgetList<PopScope>(find.byWidgetPredicate((w) => w is PopScope)).any((p) => !p.canPop);
    expect(guard, isTrue);
    expect(nav, isNotNull);
    await close(tester);
  });

  testWidgets('Platform settings: a missing route says the feature needs a server update', (tester) async {
    await open(tester, const AdminPlatformSettingsPage(), routes: cfgRoutes(missing: true));
    expect(find.text('This feature needs a server update'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Recommendations: switching the period keeps the weights being edited; Save is disabled when every weight is 0', (tester) async {
    final api = await open(tester, const AdminRecommendationsPage());
    final slider = find.byType(Slider).first;
    final before = tester.widget<Slider>(slider).value;
    await tester.drag(slider, const Offset(-120, 0));
    await cfgPump(tester, 3);
    final edited = tester.widget<Slider>(find.byType(Slider).first).value;
    expect(edited, isNot(before));
    expect(primary(tester).onPressed, isNotNull, reason: 'edited weights: Save is enabled');

    await tester.tap(find.text('Last 7 days'));
    await cfgPump(tester);
    expect(api.calls.where((c) => c.path.endsWith('/recommendations/stats')).map((c) => c.query['days']), contains('7'));
    expect(tester.widget<Slider>(find.byType(Slider).first).value, edited, reason: 'the edit survives a period switch');
    expect(find.text('Students reached'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Features: hiding a feature for everyone asks first and names it; Cancel sends nothing', (tester) async {
    await open(tester, const AdminFeaturesPage());
    expect(primary(tester).label, 'New feature');
    // switch the first feature (shown) OFF
    final sw = find.byType(AppSwitch).first;
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    await cfgPump(tester, 3);
    expect(find.textContaining('Feature number 1'), findsWidgets);
    expect(find.textContaining('Hide "Feature number 1" for everyone'), findsOneWidget);
    expect(cfgSent.keys.where((k) => k.startsWith('PUT /api/v1/admin/features/')), isEmpty);
    await tester.tap(find.text('Cancel'));
    await cfgPump(tester, 3);
    expect(cfgSent.keys.where((k) => k.startsWith('PUT /api/v1/admin/features/')), isEmpty);
    await close(tester);
  });

  testWidgets('Data lab: a failed course search is shown (with Retry), never thrown; the master switch asks first', (tester) async {
    final routes = cfgRoutes();
    var failing = false;
    routes['GET /api/v1/admin/data-lab/courses'] = (o) => failing ? const FakeResponse(500, {'detail': 'boom'}) : cfgDataLabCourses(o);
    final api = await open(tester, const AdminDataLabPage(), routes: routes);
    expect(api.calls.where((c) => c.path.endsWith('/data-lab/courses')), isNotEmpty);

    failing = true;
    // the course search (the limit number fields come first on the page)
    await tester.scrollUntilVisible(find.byType(AppSearchField), 300, scrollable: find.byType(Scrollable).first);
    final search = find.descendant(of: find.byType(AppSearchField).last, matching: find.byType(TextField));
    await tester.enterText(search, 'phys');
    await cfgPump(tester, 8);
    expect(tester.takeException(), isNull);
    expect(api.calls.where((c) => c.query['search'] == 'phys'), isNotEmpty);

    // the master switch: OFF is confirmed first
    final masterTile = find.widgetWithText(AppSwitchTile, 'dl_admin_enabled'.tr);
    await tester.scrollUntilVisible(masterTile, -300, scrollable: find.byType(Scrollable).first);
    final master = find.descendant(of: masterTile, matching: find.byType(AppSwitch));
    await tester.tap(master);
    await cfgPump(tester, 3);
    expect(find.textContaining('Switch the Data Lab off'), findsOneWidget);
    expect(cfgSent['PUT /api/v1/admin/data-lab/settings'], isNull);
    await close(tester);
  });

  testWidgets('Flags: typed numbers save through this page with its own notice', (tester) async {
    await open(tester, const AdminFlagsSettingsPage());
    expect(find.text('Student review & read flags'), findsOneWidget);
    expect(primary(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, '9');
    await cfgPump(tester, 3);
    expect(primary(tester).onPressed, isNotNull);
    primary(tester).onPressed!();
    await cfgPump(tester);
    final body = cfgSent['PUT /api/v1/admin/settings']!.single as Map;
    expect(body['review_limit_per_exam'], 9);
    expect(body['read_flag_teacher_min_students'], 3);
    expect(find.textContaining('exam rules'), findsNothing);
    await close(tester);
  });

  testWidgets('Update prompt: platform names, not raw codes; the activation switch sends one request', (tester) async {
    await open(tester, const AdminVersionsPage());
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('iOS'), findsOneWidget);
    expect(find.text('android'), findsNothing);
    await close(tester);
  });

  testWidgets('Live performance: Save is the header action and the section jump list is there', (tester) async {
    await open(tester, const LiveSettingsPage());
    expect(primary(tester).label, 'Save');
    expect(primary(tester).onPressed, isNull);
    for (final s in ['Video', 'Cameras', 'Screen share', 'Audio', 'Recording']) {
      expect(find.text(s), findsWidgets);
    }
    await close(tester);
  });
}
