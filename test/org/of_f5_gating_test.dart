// Org flow overhaul, f5: the setup checklist and the parent's children-organizations card make NO request while
// organizations are off or their kill switch is on; a 403 orgs_disabled hides them quietly; the checklist does not
// refetch on a plain refresh and ignores a Dismiss answer that arrives after the organization changed.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/home/org_setup_checklist.dart';
import 'package:flutter_education_app/features/org/org_v3.dart';
import 'package:flutter_education_app/features/parent/parent_org_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Widget _host(Widget child) => ThemeConfigScope(
      provider: ThemeConfigProvider(api: ApiClient()),
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Map<String, dynamic> _setup() => {
      'dismissed': false,
      'steps': [
        for (final k in orgSetupOrder) {'key': k, 'done': k == 'profile'},
      ],
    };

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.orgsEnabled = true;
    AppConfig.disableList = const [];
    OrgSetupPrefetch.reset();
  });
  tearDown(() {
    api.uninstall();
    AppConfig.orgsEnabled = true;
    AppConfig.disableList = const [];
  });

  group('setup checklist', () {
    testWidgets('organizations off: no request and nothing drawn', (tester) async {
      AppConfig.orgsEnabled = false;
      api = FakeApi({'GET /api/v1/org/orgs/5/setup': (_) => _setup()}, latency: Duration.zero)..install();
      OrgSetupPrefetch.start(5);
      await tester.pumpWidget(_host(OrgSetupChecklist(orgId: 5, onOpen: (_) {})));
      await _frames(tester);
      expect(api.calls, isEmpty);
      expect(find.text('Set up your organization'), findsNothing);
    });

    testWidgets('kill switch org.setup_checklist: no request and nothing drawn', (tester) async {
      AppConfig.disableList = const [orgSetupFeatureKey];
      api = FakeApi({'GET /api/v1/org/orgs/5/setup': (_) => _setup()}, latency: Duration.zero)..install();
      OrgSetupPrefetch.start(5);
      await tester.pumpWidget(_host(OrgSetupChecklist(orgId: 5, onOpen: (_) {})));
      await _frames(tester);
      expect(api.calls, isEmpty);
      expect(find.text('Set up your organization'), findsNothing);
    });

    testWidgets('403 orgs_disabled: hidden quietly, no error strip', (tester) async {
      api = FakeApi({
        'GET /api/v1/org/orgs/5/setup': (_) => const FakeResponse(403, {
              'detail': {'code': 'orgs_disabled', 'message': 'ar', 'message_en': 'off'}
            }),
      }, latency: Duration.zero)
        ..install();
      await tester.pumpWidget(_host(OrgSetupChecklist(orgId: 5, onOpen: (_) {})));
      await _frames(tester);
      expect(find.text('Set up your organization'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a prefetch started with the dashboard call is the only request; a plain refresh asks nothing more; '
        'a refresh after a step was opened asks once', (tester) async {
      api = FakeApi({'GET /api/v1/org/orgs/5/setup': (_) => _setup()}, latency: Duration.zero)..install();
      OrgSetupPrefetch.start(5);
      OrgSetupPrefetch.start(5); // the home may rebuild: still one request
      Object token = 1;
      late StateSetter set;
      var opened = 0;
      await tester.pumpWidget(_host(StatefulBuilder(builder: (context, setState) {
        set = setState;
        return OrgSetupChecklist(orgId: 5, reloadToken: token, onOpen: (_) => opened++);
      })));
      await _frames(tester);
      expect(find.text('Set up your organization'), findsOneWidget);
      expect(api.calls.where((c) => c.path.endsWith('/setup')), hasLength(1));

      set(() => token = 2); // pull-to-refresh of the home
      await _frames(tester);
      expect(api.calls.where((c) => c.path.endsWith('/setup')), hasLength(1), reason: 'no refetch on a plain refresh');

      await tester.ensureVisible(find.text('Open departments'));
      await tester.tap(find.text('Open departments'));
      await _frames(tester, 2);
      expect(opened, 1);
      set(() => token = 3); // back from the step's page: the home reloaded
      await _frames(tester);
      expect(api.calls.where((c) => c.path.endsWith('/setup')), hasLength(2), reason: 'a step was opened: ask once more');
    });

    testWidgets('a Dismiss answer that arrives after the organization changed is ignored', (tester) async {
      api = FakeApi({
        'GET /api/v1/org/orgs/5/setup': (_) => _setup(),
        'GET /api/v1/org/orgs/6/setup': (_) => _setup(),
        'POST /api/v1/org/orgs/5/setup/dismiss': (_) => {'dismissed': true},
      }, latency: const Duration(milliseconds: 300))
        ..install();
      int org = 5;
      late StateSetter set;
      await tester.pumpWidget(_host(StatefulBuilder(builder: (context, setState) {
        set = setState;
        return OrgSetupChecklist(orgId: org, onOpen: (_) {});
      })));
      await _frames(tester, 6);
      await tester.tap(find.byKey(const ValueKey('setup.dismiss')));
      await tester.pump(const Duration(milliseconds: 50));
      set(() => org = 6); // switched while the POST is in flight
      await _frames(tester, 10);
      expect(find.text('Set up your organization'), findsOneWidget, reason: "org 6's card must not be dismissed by org 5's answer");
    });
  });

  group('parent children-organizations card', () {
    testWidgets('organizations off: no request', (tester) async {
      AppConfig.orgsEnabled = false;
      api = FakeApi({'GET /api/v1/org/parent/children': (_) => {'children': []}}, latency: Duration.zero)..install();
      await tester.pumpWidget(_host(const ParentOrgChildrenCard()));
      await _frames(tester);
      expect(api.calls, isEmpty);
    });

    testWidgets('kill switch parent.org_view: no request', (tester) async {
      AppConfig.disableList = const [parentOrgViewKey];
      api = FakeApi({'GET /api/v1/org/parent/children': (_) => {'children': []}}, latency: Duration.zero)..install();
      await tester.pumpWidget(_host(const ParentOrgChildrenCard()));
      await _frames(tester);
      expect(api.calls, isEmpty);
    });

    testWidgets('403 orgs_disabled: nothing drawn and no error strip / Retry', (tester) async {
      api = FakeApi({
        'GET /api/v1/org/parent/children': (_) => const FakeResponse(403, {
              'detail': {'code': 'orgs_disabled', 'message': 'ar', 'message_en': 'off'}
            }),
      }, latency: Duration.zero)
        ..install();
      await tester.pumpWidget(_host(const ParentOrgChildrenCard()));
      await _frames(tester);
      expect(api.calls, hasLength(1));
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining("children's organizations"), findsNothing);
    });

    testWidgets('a real failure (500) still offers Retry', (tester) async {
      api = FakeApi({'GET /api/v1/org/parent/children': (_) => const FakeResponse(500, {'detail': 'boom'})}, latency: Duration.zero)..install();
      await tester.pumpWidget(_host(const ParentOrgChildrenCard()));
      await _frames(tester);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  test('the new error codes have bilingual text', () {
    for (final code in ['admin_only', 'staff_cannot_leave', 'admin_cannot_leave']) {
      AppConfig.lang = 'en';
      final en = orgCodeText(code);
      AppConfig.lang = 'ar';
      final ar = orgCodeText(code);
      expect(en, isNot(code));
      expect(ar, isNot(code));
      expect(ar, isNot(en));
    }
    AppConfig.lang = 'en';
    expect(jsonEncode(orgCodeText('staff_cannot_leave')), contains('admin'));
  });
}
