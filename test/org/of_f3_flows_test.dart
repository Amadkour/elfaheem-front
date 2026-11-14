// Org flow overhaul, agent f3: the flows over a fake backend (FakeApi): the Super Admin deleting an organization
// (wrong name is blocked, the right one sends reason + confirm_name), transferring the admin seat (platform and org
// admin routes), the creation-fee panel failing closed with Retry, the setup checklist and the organizations list.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show RequestOptions;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_organizations_page.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/org/home/org_setup_checklist.dart';
import 'package:flutter_education_app/features/org/org_creation_fee.dart';
import 'package:flutter_education_app/features/org/org_danger_zone.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

late MyAuthProvider _auth;

Widget _host(Widget child, {bool scroll = true}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<MyAuthProvider>.value(value: _auth),
        ChangeNotifierProvider<OrgSession>(create: (_) => OrgSession()),
      ],
      child: ThemeConfigScope(
        provider: ThemeConfigProvider(api: ApiClient()),
        child: MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: scroll ? SingleChildScrollView(child: child) : child)),
      ),
    );

Future<void> _settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester, 4);
}

Future<void> _until(WidgetTester tester, bool Function() done, {int max = 120}) async {
  for (var i = 0; i < max && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

VoidCallback? _onPressed(WidgetTester tester, Key k) => tester.widget<AppButton>(find.byKey(k)).onPressed;

Map<String, dynamic> _body(RequestOptions o) {
  final d = o.data;
  if (d is Map) return Map<String, dynamic>.from(d);
  if (d is String && d.isNotEmpty) return Map<String, dynamic>.from(jsonDecode(d) as Map);
  return {};
}

const _org = {
  'id': 5,
  'name_ar': 'جامعة النيل',
  'name_en': 'Nile University',
  'status': 'approved',
  'type': 'university',
  'counts': {'members': 3, 'departments': 1, 'sub_organizations': 0},
};

void main() {
  late FakeApi api;
  final sent = <String, Map<String, dynamic>>{};

  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  setUp(() async {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    final storage = await StorageService.getInstance();
    await storage.saveUser({'id': 7, 'name': 'Boss', 'gmail': 'boss@example.test', 'role': 'super-admin'});
    _auth = MyAuthProvider(storage: storage)..loadCachedUser();
    sent.clear();
  });
  tearDown(() => api.uninstall());

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('delete: a wrong name keeps the button off and sends nothing; the right name sends reason + confirm_name', (tester) async {
    api = FakeApi({
      'DELETE /api/v1/admin/orgs/5': (o) {
        sent['DELETE'] = _body(o);
        return {'id': 5, 'status': 'deleted'};
      },
    }, latency: const Duration(milliseconds: 20))
      ..install();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.reset);
    var changed = 0;
    await tester.pumpWidget(_host(OrgReviewPanel(org: _org, onChanged: () async => changed++)));
    await _settle(tester, 2);

    await _tap(tester, find.widgetWithText(AppButton, 'Delete the organization'));
    expect(find.byKey(const ValueKey('danger.confirm')), findsOneWidget);
    expect(_onPressed(tester, const ValueKey('danger.confirm')), isNull);

    await tester.enterText(find.byKey(const ValueKey('danger.name')), 'Nile Univ');
    await tester.enterText(find.byKey(const ValueKey('danger.reason')), 'duplicate organization');
    await tester.pump();
    expect(_onPressed(tester, const ValueKey('danger.confirm')), isNull, reason: 'a wrong name must not enable the button');
    expect(api.calls.where((c) => c.method == 'DELETE'), isEmpty);

    await tester.enterText(find.byKey(const ValueKey('danger.name')), 'nile university');
    await tester.pump();
    expect(_onPressed(tester, const ValueKey('danger.confirm')), isNotNull);
    await tester.enterText(find.byKey(const ValueKey('danger.reason')), 'no');
    await tester.pump();
    expect(_onPressed(tester, const ValueKey('danger.confirm')), isNull, reason: 'a reason under 5 characters is refused');
    await tester.enterText(find.byKey(const ValueKey('danger.reason')), 'duplicate organization');
    await tester.pump();

    await _tap(tester, find.byKey(const ValueKey('danger.confirm')));
    await _settle(tester, 6);
    expect(api.calls.where((c) => c.method == 'DELETE').length, 1);
    expect(sent['DELETE']?['reason'], 'duplicate organization');
    expect(sent['DELETE']?['confirm_name'], isNotEmpty);
    expect(changed, 1);
    await close(tester);
  });

  testWidgets('a deleted organization offers only Restore', (tester) async {
    api = FakeApi({}, latency: const Duration(milliseconds: 20))..install();
    await tester.pumpWidget(_host(OrgReviewPanel(org: {..._org, 'status': 'deleted'}, onChanged: () async {})));
    await _settle(tester, 2);
    expect(find.text('Restore the organization'), findsOneWidget);
    expect(find.text('Delete the organization'), findsNothing);
    expect(find.text('Suspend'), findsNothing);
    await close(tester);
  });

  for (final platform in [true, false]) {
    testWidgets('transfer admin (${platform ? 'platform' : 'org admin'}): pick a member, say what happens to the old admin, send', (tester) async {
      final path = platform ? '/api/v1/admin/orgs/5/transfer-admin' : '/api/v1/org/orgs/5/transfer-admin';
      api = FakeApi({
        'GET /api/v1/org/orgs/5/members': (o) => {
              'items': [
                {'id': 11, 'user': {'id': 21, 'name': 'Sara Ali', 'email': 'sara@x.co'}},
                {'id': 12, 'user': {'id': 22, 'name': 'Omar Nabil', 'email': 'omar@x.co'}},
              ],
            },
        'POST $path': (o) {
          sent['POST'] = _body(o);
          return {'org_id': 5, 'admin': {'id': 22, 'name': 'Omar Nabil'}};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(OrgTransferAdminSheet(orgId: 5, orgName: 'Nile University', platform: platform)));
      await _settle(tester, 5);
      expect(find.text('Sara Ali'), findsOneWidget);
      // nobody picked yet: the button is off
      expect(_onPressed(tester, const ValueKey('transfer.send')), isNull);

      await _tap(tester, find.text('Omar Nabil'));
      await _tap(tester, find.text('Membership ends (removed)'));
      // both routes need a reason of 5+ characters
      expect(_onPressed(tester, const ValueKey('transfer.send')), isNull);
      await tester.enterText(find.byKey(const ValueKey('transfer.reason')), 'owner left');
      await tester.pump();
      expect(_onPressed(tester, const ValueKey('transfer.send')), isNotNull);
      await _tap(tester, find.byKey(const ValueKey('transfer.send')));
      await _settle(tester, 4);
      expect(api.calls.where((c) => c.method == 'POST' && c.path == path).length, 1);
      expect(sent['POST']?['user_id'], 22);
      expect(sent['POST']?['old_admin'], 'remove');
      expect(sent['POST']?['reason'], 'owner left');
      await close(tester);
    });
  }

  testWidgets('transfer admin: a refused transfer shows the server text and keeps the sheet', (tester) async {
    api = FakeApi({
      'GET /api/v1/org/orgs/5/members': (o) => {
            'items': [
              {'id': 11, 'user': {'id': 21, 'name': 'Sara Ali', 'email': 'sara@x.co'}},
            ],
          },
      'POST /api/v1/org/orgs/5/transfer-admin': (o) => const FakeResponse(403, {
            'detail': {'code': 'not_org_admin', 'message': 'ليس مدير المؤسسة', 'message_en': 'Only the organization admin can do this'},
          }),
    }, latency: const Duration(milliseconds: 20))
      ..install();
    await tester.pumpWidget(_host(const OrgTransferAdminSheet(orgId: 5, orgName: 'Nile University', platform: false)));
    await _settle(tester, 5);
    await _tap(tester, find.text('Sara Ali'));
    await tester.enterText(find.byKey(const ValueKey('transfer.reason')), 'owner left');
    await tester.pump();
    await _tap(tester, find.byKey(const ValueKey('transfer.send')));
    await _settle(tester, 4);
    expect(find.byKey(const ValueKey('transfer.send')), findsOneWidget);
    expect(find.textContaining('organization admin'), findsWidgets);
    await close(tester);
  });

  testWidgets('fee panel: a failed status load shows an error with Retry (never "free"), Retry recovers', (tester) async {
    var fail = true;
    final ready = <bool>[];
    api = FakeApi({
      'GET /api/v1/org/creation-fee': (o) => fail ? const FakeResponse(500, {'detail': 'boom'}) : {'required': false, 'can_submit': true},
    }, latency: const Duration(milliseconds: 20))
      ..install();
    await tester.pumpWidget(_host(OrgCreationFeePanel(onReady: (ok, token) => ready.add(ok))));
    await _until(tester, () => ready.isNotEmpty);
    await _settle(tester, 2);
    expect(find.byKey(const ValueKey('fee.error')), findsOneWidget);
    expect(ready, isNotEmpty);
    expect(ready.last, isFalse, reason: 'the form must not be allowed to submit while the fee state is unknown');

    fail = false;
    final before = ready.length;
    await _tap(tester, find.descendant(of: find.byKey(const ValueKey('fee.error')), matching: find.text('Retry')));
    await _until(tester, () => ready.length > before);
    await _settle(tester, 2);
    expect(find.byKey(const ValueKey('fee.error')), findsNothing);
    expect(ready.last, isTrue);
    await close(tester);
  });

  testWidgets('fee panel: an older server without the route is "nothing to pay"', (tester) async {
    final ready = <bool>[];
    api = FakeApi({}, latency: const Duration(milliseconds: 20))..install();
    await tester.pumpWidget(_host(OrgCreationFeePanel(onReady: (ok, token) => ready.add(ok))));
    await _settle(tester, 6);
    expect(find.byKey(const ValueKey('fee.error')), findsNothing);
    expect(ready.last, isTrue);
    await close(tester);
  });

  testWidgets('setup checklist: shows the steps, Dismiss posts and hides it; an older server draws nothing', (tester) async {
    api = FakeApi({
      'GET /api/v1/org/orgs/5/setup': (o) => {
            'dismissed': false,
            'steps': [
              for (final k in orgSetupOrder) {'key': k, 'done': k == 'profile', 'count': k == 'profile' ? 1 : null},
            ],
          },
      'POST /api/v1/org/orgs/5/setup/dismiss': (o) => {'dismissed': true},
    }, latency: const Duration(milliseconds: 20))
      ..install();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(_host(OrgSetupChecklist(orgId: 5, onOpen: (s) => opened.add(s.key))));
    await _settle(tester, 5);
    expect(find.text('1 of 7 steps done'), findsOneWidget);
    expect(find.byKey(const ValueKey('setup.step.timetable')), findsOneWidget);
    await _tap(tester, find.text('Open departments'));
    expect(opened, ['departments']);

    await _tap(tester, find.byKey(const ValueKey('setup.dismiss')));
    await _settle(tester, 3);
    expect(api.calls.where((c) => c.method == 'POST' && c.path.endsWith('/setup/dismiss')).length, 1);
    expect(find.text('Set up your organization'), findsNothing);
    await close(tester);

    // the kill switch hides it, and an older server (no route) draws nothing
    api.uninstall();
    api = FakeApi({}, latency: const Duration(milliseconds: 20))..install();
    await tester.pumpWidget(_host(OrgSetupChecklist(orgId: 5, onOpen: (_) {})));
    await _settle(tester, 5);
    expect(find.text('Set up your organization'), findsNothing);
    await close(tester);
  });

  testWidgets('organizations list: filter chips carry the counts from /stats and "All" asks for status=all', (tester) async {
    api = FakeApi({
      'GET /api/v1/admin/orgs/stats': (o) => {'pending': 3, 'approved': 10, 'rejected': 1, 'suspended': 2, 'total': 16},
      'GET /api/v1/admin/orgs': (o) => {
            'items': [
              {'id': 5, 'name_ar': 'جامعة النيل', 'name_en': 'Nile University', 'status': o.queryParameters['status'] == 'all' ? 'approved' : 'pending', 'type': 'university', 'creator': {'name': 'Sara'}},
            ],
            'total': 1,
            'page': 1,
            'pages': 1,
          },
    }, latency: const Duration(milliseconds: 20))
      ..install();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const AdminOrganizationsPage(), scroll: false));
    await _settle(tester, 8);
    expect(find.text('Waiting · 3'), findsOneWidget);
    expect(find.text('All · 16'), findsOneWidget);
    expect(find.text('Nile University'), findsWidgets);
    expect(api.calls.any((c) => c.path == '/api/v1/admin/orgs' && c.query['status'] == 'pending'), isTrue);

    await _tap(tester, find.byKey(const ValueKey('orgs.filter.all')));
    await _settle(tester, 6);
    expect(api.calls.any((c) => c.path == '/api/v1/admin/orgs' && c.query['status'] == 'all'), isTrue);
    await close(tester);
  });

  testWidgets('organizations list: two ticked rows offer Approve / Reactivate / Export; Approve posts only the waiting one', (tester) async {
    api = FakeApi({
      'GET /api/v1/admin/orgs/stats': (o) => {'pending': 1, 'suspended': 1},
      'GET /api/v1/admin/orgs': (o) => {
            'items': [
              {'id': 5, 'name_ar': 'جامعة النيل', 'name_en': 'Nile University', 'status': 'pending', 'type': 'university', 'creator': {'name': 'Sara'}},
              {'id': 6, 'name_ar': 'مدرسة النور', 'name_en': 'Noor School', 'status': 'suspended', 'type': 'school', 'creator': {'name': 'Ali'}},
            ],
            'total': 2,
            'page': 1,
            'pages': 1,
          },
      'POST /api/v1/admin/orgs/*': (o) => {'ok': true},
    }, latency: const Duration(milliseconds: 20))
      ..install();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const AdminOrganizationsPage(), scroll: false));
    await _settle(tester, 8);
    final boxes = find.byType(Checkbox);
    expect(boxes, findsNWidgets(3)); // select-all + two rows
    await _tap(tester, boxes.at(1));
    await _tap(tester, boxes.at(2));
    expect(find.widgetWithText(AppButton, 'Approve'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Reactivate'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'md_p8_export_selected'.tr), findsOneWidget);

    await _tap(tester, find.widgetWithText(AppButton, 'Approve'));
    await _tap(tester, find.text('Approve').last); // the confirm
    await _settle(tester, 6);
    final posts = api.calls.where((c) => c.method == 'POST').map((c) => c.path).toList();
    expect(posts, ['/api/v1/admin/orgs/5/approve']);
    await close(tester);
  });

  testWidgets('organizations list: a failed load is an error with Retry, not an empty list', (tester) async {
    var fail = true;
    api = FakeApi({
      'GET /api/v1/admin/orgs/stats': (o) => {'pending': 0},
      'GET /api/v1/admin/orgs': (o) => fail
          ? const FakeResponse(500, {'detail': 'boom'})
          : {'items': [], 'total': 0, 'page': 1, 'pages': 1},
    }, latency: const Duration(milliseconds: 20))
      ..install();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const AdminOrganizationsPage(), scroll: false));
    await _until(tester, () => find.text('Retry').evaluate().isNotEmpty);
    await _settle(tester, 2);
    expect(find.text('No applications are waiting'), findsNothing);
    expect(find.text('Retry'), findsWidgets);
    fail = false;
    await _tap(tester, find.text('Retry').first);
    await _settle(tester, 6);
    expect(find.text('No applications are waiting'), findsOneWidget);
    await close(tester);
  });
}
