// App versions is ONE screen (D-309): a card per platform from GET /app/policy, "Build a version" as the super
// admin's primary action (hidden for a plain admin and by the kill switch `admin.app_releases`), the editor's live
// preview, the PUT body, the rules the preview mirrors (the server's check_version), and no layout error.
import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/version_check_service.dart' show UpdateDialog;
import 'package:flutter_education_app/features/admin/admin_app_versions_page.dart';
import 'package:flutter_education_app/features/admin/admin_update_policy.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_page.dart' show kAppReleasesFeatureKey;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';
import 'cfg_support.dart';

Map<String, dynamic> _policy() => {
      'platforms': [
        {
          'platform': 'android',
          'kind': 'versions',
          'enabled': true,
          'latest_version': '2.1.0',
          'min_supported': '1.5.0',
          'message_ar': 'تحسينات',
          'message_en': 'Faster live classes',
          'store_url': 'https://play.google.com/store/apps/details?id=com.doubley.alfaheem',
          'link_ok': true,
          'history_count': 3,
          'release': {'version': '2.2.0', 'build_number': 31, 'notes_en': 'New home', 'channel': 'store', 'source': 'google_play'},
          'suggestion': {'version': '2.2.0', 'message_en': 'New home', 'min_supported': '1.5.0'},
        },
        {'platform': 'ios', 'kind': 'versions', 'enabled': false, 'history_count': 0},
        {'platform': 'web', 'kind': 'versions', 'enabled': true, 'latest_version': '2.0.0', 'legacy_force': true, 'history_count': 1},
        {'platform': 'windows', 'kind': 'releases', 'enabled': true, 'latest_version': '1.0.0', 'link_ok': false},
        {'platform': 'macos', 'kind': 'releases', 'enabled': false},
        {'platform': 'linux', 'kind': 'releases', 'enabled': false},
      ],
    };

Map<String, FakeHandler> _routes() {
  Object? put(RequestOptions o) {
    (cfgSent['PUT ${o.uri.path.replaceFirst('/api/app', '/app')}'] ??= []).add(o.data);
    return {...(_policy()['platforms'] as List)[0] as Map, ...(o.data as Map)};
  }

  return {
    ...cfgRoutes(),
    'GET /app/policy': (_) => _policy(),
    'GET /api/app/policy': (_) => _policy(),
    'PUT /app/policy/*': put,
    'PUT /api/app/policy/*': put,
  };
}

UpdatePolicy _android() => UpdatePolicy.fromJson(Map<String, dynamic>.from((_policy()['platforms'] as List)[0] as Map));

void main() {
  late List<String> savedDisable;
  setUp(() {
    AppConfig.lang = 'en';
    savedDisable = [...AppConfig.disableList];
    AppConfig.disableList = [];
    cfgSent.clear();
  });
  tearDown(() => AppConfig.disableList = savedDisable);

  group('rules (the server check_version)', () {
    test('below the minimum blocks, between asks, the latest sees nothing', () {
      expect(updatePolicyAnswer('1.4.9', latest: '2.1.0', minimum: '1.5.0'), UpdateAsk.blocking);
      expect(updatePolicyAnswer('1.5.0', latest: '2.1.0', minimum: '1.5.0'), UpdateAsk.dismissible);
      expect(updatePolicyAnswer('2.1.0', latest: '2.1.0', minimum: '1.5.0'), UpdateAsk.none);
      expect(updatePolicyAnswer('3.0.0', latest: '2.1.0'), UpdateAsk.none);
      expect(updatePolicyAnswer('2.1.0', latest: '2.1.0', legacyForce: true), UpdateAsk.blocking);
      expect(updatePolicyAnswer('2.1', latest: '2.1.0'), UpdateAsk.none, reason: '2.1 == 2.1.0');
    });

    test('bands: three, two when the minimum is the latest, one with a legacy force', () {
      expect(updateBands(latest: '2.1.0', minimum: '1.5.0').map((b) => b.ask), [UpdateAsk.blocking, UpdateAsk.dismissible, UpdateAsk.none]);
      expect(updateBands(latest: '2.1.0', minimum: '2.1.0').map((b) => b.ask), [UpdateAsk.blocking, UpdateAsk.none]);
      expect(updateBands(latest: '2.1.0').map((b) => b.ask), [UpdateAsk.dismissible, UpdateAsk.none]);
      expect(updateBands(latest: '2.1.0', legacyForce: true).map((b) => b.ask), [UpdateAsk.blocking]);
    });

    test('validation: versions, minimum <= latest, a link on native platforms', () {
      const ok = UpdatePolicyDraft(latest: '2.1.0', minimum: '1.5.0', storeUrl: 'https://x.test/app');
      expect(validateUpdatePolicy('android', ok), isEmpty);
      expect(validateUpdatePolicy('android', const UpdatePolicyDraft(latest: '2.1', minimum: '3.0.0', storeUrl: 'https://x.test')).keys, ['min_supported']);
      expect(validateUpdatePolicy('android', const UpdatePolicyDraft(latest: 'x')).keys, containsAll(['latest_version', 'store_url']));
      expect(validateUpdatePolicy('android', const UpdatePolicyDraft(latest: '2.0.0')).keys, ['store_url']);
      expect(validateUpdatePolicy('android', const UpdatePolicyDraft(latest: '2.0.0'), hasReleaseLink: true), isEmpty);
      expect(validateUpdatePolicy('web', const UpdatePolicyDraft(latest: '2.0.0')), isEmpty, reason: 'the web never needs a link');
      expect(validateUpdatePolicy('ios', const UpdatePolicyDraft(latest: '2.0.0', storeUrl: 'http://x.test')).keys, ['store_url']);
      expect(validateUpdatePolicy('ios', const UpdatePolicyDraft(enabled: false)), isEmpty);
    });

    test('smart default: a newer live build fills an empty / off prompt', () {
      final off = UpdatePolicy.fromJson({
        'platform': 'android',
        'enabled': false,
        'release': {'version': '2.2.0', 'notes_en': 'New home'},
        'suggestion': {'version': '2.2.0', 'message_en': 'New home', 'min_supported': '1.5.0'},
      });
      final d = off.startDraft();
      expect(d.enabled, isTrue);
      expect(d.latest, '2.2.0');
      expect(d.minimum, '1.5.0');
      expect(d.messageEn, 'New home');
      // on: what is saved stays; the message the admin wrote is kept
      final on = _android().startDraft();
      expect(on.latest, '2.1.0');
      expect(on.minimum, '1.5.0');
      expect(on.messageEn, 'Faster live classes');
      expect(_android().buttonSource(on), 'google_play');
    });
  });

  Future<void> open(WidgetTester tester, {String role = 'super-admin'}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = FakeApi(_routes(), latency: const Duration(milliseconds: 20));
    final auth = await cfgSetUp(api, role: role);
    await tester.pumpWidget(cfgProviders(auth, layoutHost(const AdminAppVersionsPage(), scale: 1, scaffold: false)));
    await cfgPump(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('super admin: one card per platform and Build a version', (tester) async {
    await open(tester);
    for (final p in kUpdatePlatforms) {
      expect(find.byKey(ValueKey('update_policy.$p')), findsOneWidget, reason: p);
    }
    expect(find.byKey(const ValueKey('admin_app_versions.build')), findsOneWidget);
    expect(find.byKey(const ValueKey('update_policy.android.use')), findsOneWidget, reason: 'a newer live build');
    expect(find.text('No link: the update button opens nothing.'), findsOneWidget, reason: 'windows has no link');
    expect(find.text('Update prompt history'), findsOneWidget);
    await close(tester);
  });

  testWidgets('plain admin: no Build button', (tester) async {
    await open(tester, role: 'admin');
    expect(find.byKey(const ValueKey('admin_app_versions.build')), findsNothing);
    expect(find.byKey(const ValueKey('update_policy.android')), findsOneWidget);
    await close(tester);
  });

  testWidgets('kill switch: no Build button even for a super admin', (tester) async {
    AppConfig.disableList = [kAppReleasesFeatureKey];
    await open(tester);
    expect(find.byKey(const ValueKey('admin_app_versions.build')), findsNothing);
    await close(tester);
  });

  testWidgets('editor: the live preview draws the real dialog, Save sends the policy', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('update_policy.android.edit')));
    await cfgPump(tester, 6);
    expect(find.byType(UpdateDialog), findsOneWidget);
    expect(tester.widget<UpdateDialog>(find.byType(UpdateDialog)).force, isFalse, reason: 'dismissible first');
    await tester.tap(find.text('Blocking'));
    await cfgPump(tester, 2);
    expect(tester.widget<UpdateDialog>(find.byType(UpdateDialog)).force, isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('update_policy.save')));
    await cfgPump(tester, 2);
    await tester.tap(find.byKey(const ValueKey('update_policy.save')));
    await cfgPump(tester, 6);
    expect(cfgSent['PUT /app/policy/android']?.single, {
      'enabled': true,
      'latest_version': '2.1.0',
      'min_supported': '1.5.0',
      'message_ar': 'تحسينات',
      'message_en': 'Faster live classes',
      'store_url': 'https://play.google.com/store/apps/details?id=com.doubley.alfaheem',
    });
    await close(tester);
  });

  testWidgets('layout: overview and editor', (tester) async {
    final items = [for (final m in _policy()['platforms'] as List) UpdatePolicy.fromJson(Map<String, dynamic>.from(m as Map))];
    await expectNoLayoutErrors(tester, () => UpdatePolicyOverview(items: items, onEdit: (_) {}, onUseSuggestion: (_) {}, onOpenHistory: () {}));
    await expectNoLayoutErrors(tester, () => UpdatePolicyEditor(policy: _android(), onSave: (_) async => null));
  });
}
