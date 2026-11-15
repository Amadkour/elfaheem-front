// Institutions v2, phase 2 (docs/institutions/V2_PLAN.md, notification routing D-985 – D-988): the phone-push setting
// for organization requests (load · save at once · revert on failure), where an `org_department` notification goes,
// "Message this department" (check, send, the server's 403 text), and the new views lay out at 320×640 and 1400×900
// in Arabic and English with text scale 1.3.
import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/org_inst_notify.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _prefs = '/api/v1/org/public/governance/5/me/notify-prefs';
const _message = '/api/v1/org/public/governance/5/units/3/message';

Widget _host(Widget child) => MultiProvider(
      providers: [ChangeNotifierProvider<OrgSession>(create: (_) => OrgSession())],
      child: ThemeConfigScope(
        provider: ThemeConfigProvider(api: ApiClient()),
        child: MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: child)),
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

Map<String, dynamic> _body(RequestOptions o) {
  final d = o.data;
  if (d is Map) return Map<String, dynamic>.from(d);
  if (d is String && d.isNotEmpty) return Map<String, dynamic>.from(jsonDecode(d) as Map);
  return {};
}

void _bigView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1400);
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('pure', () {
    test('push setting parses; unknown or missing is "all"', () {
      expect(orgPushPrefOf('important'), OrgPushPref.important);
      expect(orgPushPrefOf('off'), OrgPushPref.off);
      expect(orgPushPrefOf(null), OrgPushPref.all);
      expect(orgPushPrefOf('weekly'), OrgPushPref.all);
    });

    test('org_department: dashboard for staff, departments without an id, else notifications', () {
      OrgDeptLink go({int? dept = 3, int? org = 5, bool on = true, List<String> off = const [], bool manages = true}) =>
          orgDeptLinkTarget(deptId: dept, orgId: org, orgsEnabled: on, disabled: off, manages: manages);
      expect(go(), OrgDeptLink.dashboard);
      expect(go(dept: null), OrgDeptLink.departments);
      expect(go(manages: false), OrgDeptLink.notifications, reason: 'a member never opens a staff dashboard');
      expect(go(off: ['org.departments']), OrgDeptLink.notifications, reason: 'kill switch');
      expect(go(on: false), OrgDeptLink.notifications, reason: 'organizations off');
      expect(go(org: null), OrgDeptLink.notifications);
    });

    test('message check and the refused texts', () {
      expect(unitMessageProblem('   '), isNotNull);
      expect(unitMessageProblem('Hello'), isNull);
      final audience = ApiException(statusCode: 403, message: 'x', code: 'audience', body: {'detail': {'code': 'audience'}});
      final forbidden = ApiException(statusCode: 403, message: 'x', code: 'forbidden', body: {'detail': {'code': 'forbidden'}});
      expect(unitMessageErrorText(audience), 'This department does not take messages from you');
      expect(unitMessageErrorText(forbidden), unitMessageErrorText(audience));
      final inactive = ApiException(statusCode: 404, message: 'x', code: 'not_found', body: {'detail': {'code': 'not_found'}});
      expect(unitMessageErrorText(inactive), 'This department is no longer available');
      AppConfig.lang = 'ar';
      expect(unitMessageErrorText(audience), isNot(contains('department')));
    });
  });

  group('flows', () {
    late FakeApi api;

    setUp(() {
      AppConfig.disableList = [];
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
    });
    tearDown(() => api.uninstall());

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    }

    testWidgets('prefs page: loads the setting, saves a pick at once', (tester) async {
      Map<String, dynamic>? put;
      api = FakeApi({
        'GET $_prefs': (_) => {'push': 'important'},
        'PUT $_prefs': (o) {
          put = _body(o);
          return {'push': put!['push']};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      _bigView(tester);
      await tester.pumpWidget(_host(const OrgNotifyPrefsPage(orgId: 5, embedded: true)));
      await _settle(tester, 6);
      expect(find.text('You always see them in the app; this only changes phone alerts.'), findsOneWidget);
      Semantics sem(String k) => tester.widget<Semantics>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Semantics)).first);
      expect(sem('org.notify.important').properties.selected, isTrue);
      await _tap(tester, find.byKey(const ValueKey('org.notify.off')));
      await _settle(tester, 4);
      expect(put, {'push': 'off'});
      expect(sem('org.notify.off').properties.selected, isTrue);
      await close(tester);
    });

    testWidgets('prefs page: a failed save goes back to the old choice', (tester) async {
      api = FakeApi({
        'GET $_prefs': (_) => {'push': 'all'},
        'PUT $_prefs': (_) => const FakeResponse(500, {'detail': 'boom'}),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      _bigView(tester);
      await tester.pumpWidget(_host(const OrgNotifyPrefsPage(orgId: 5, embedded: true)));
      await _settle(tester, 6);
      await _tap(tester, find.byKey(const ValueKey('org.notify.off')));
      await _settle(tester, 8);
      final all = tester.widget<Semantics>(find.descendant(of: find.byKey(const ValueKey('org.notify.all')), matching: find.byType(Semantics)).first);
      expect(all.properties.selected, isTrue);
      await close(tester);
    });

    testWidgets('message sheet: body required, then POST {subject, body} and the item opens', (tester) async {
      Map<String, dynamic>? sent;
      api = FakeApi({
        'POST $_message': (o) {
          sent = _body(o);
          return {'item_id': 77};
        },
        'GET /api/v1/org/public/governance/items/77': (_) => {'id': 77, 'title': 'Hello', 'status': 'open'},
      }, latency: const Duration(milliseconds: 20))
        ..install();
      _bigView(tester);
      int? result;
      await tester.pumpWidget(_host(Builder(
          builder: (ctx) => TextButton(
              onPressed: () async => result = await showUnitMessageSheet(ctx, orgId: 5, dept: {'id': 3, 'name_en': 'Student Affairs'}),
              child: const Text('open')))));
      await _tap(tester, find.text('open'));
      await _tap(tester, find.byKey(const ValueKey('unit.msg.send')));
      expect(find.text('Write your message'), findsOneWidget);
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);

      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('unit.msg.subject')), matching: find.byType(TextField)), 'Card');
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('unit.msg.body')), matching: find.byType(TextField)), 'My card is lost');
      await _tap(tester, find.byKey(const ValueKey('unit.msg.send')));
      await _settle(tester, 6);
      expect(sent, {'subject': 'Card', 'body': 'My card is lost'});
      expect(result, 77);
      expect(api.calls.any((c) => c.path.endsWith('/governance/items/77')), isTrue, reason: 'the new item opens to be tracked');
      await close(tester);
    });

    testWidgets('message sheet: a 403 audience keeps the sheet open with its text', (tester) async {
      api = FakeApi({
        'POST $_message': (_) => const FakeResponse(403, {'detail': {'code': 'audience', 'message': 'no'}}),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      _bigView(tester);
      await tester.pumpWidget(_host(Builder(
          builder: (ctx) => TextButton(onPressed: () => showUnitMessageSheet(ctx, orgId: 5, dept: {'id': 3, 'name_en': 'X'}), child: const Text('open')))));
      await _tap(tester, find.text('open'));
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('unit.msg.body')), matching: find.byType(TextField)), 'Hi');
      await _tap(tester, find.byKey(const ValueKey('unit.msg.send')));
      await _settle(tester, 6);
      expect(find.text('This department does not take messages from you'), findsOneWidget);
      expect(find.byKey(const ValueKey('unit.msg.send')), findsOneWidget);
      await close(tester);
    });
  });

  group('layout', () {
    testWidgets('prefs view and message view', (tester) async {
      final subject = TextEditingController(text: 'A subject long enough to need every pixel of a small phone screen');
      final body = TextEditingController();
      addTearDown(subject.dispose);
      addTearDown(body.dispose);
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            OrgNotifyPrefsView(value: OrgPushPref.important, onPick: (_) {}),
            OrgNotifyPrefsView(value: null, saving: true, onPick: (_) {}),
            UnitMessageView(
              deptName: 'A service department with a long name that wraps on a phone',
              subject: subject,
              body: body,
              onSend: () {},
              error: 'This department does not take messages from you',
            ),
            UnitMessageView(deptName: 'X', subject: subject, body: body, onSend: () {}, busy: true),
          ]),
        ),
      );
    });
  });
}
