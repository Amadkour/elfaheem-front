// Org flow overhaul, f5: a notification for a STAFF / STUDY organization on a cold start (the overview is not loaded
// yet) waits for the memberships before deciding, and an invitation accepted through /i/<token> reloads the
// memberships and offers "Open the organization" through the one switching rule.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/org_invitations_pages.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Map<String, dynamic> _entry(int id, List<String> roles, {Object? manage}) => {
      'organization': {'id': id, 'status': 'approved', 'name_en': 'Org $id', 'name_ar': 'مؤسسة $id'},
      'roles': roles,
      'manage': manage,
    };

Map<String, dynamic> _mine(int id) => {'id': id, 'name_en': 'Org $id', 'name_ar': 'مؤسسة $id', 'status': 'approved', 'access': 'staff', 'depth': 0};

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.orgsEnabled = true;
    AppConfig.disableList = const [];
    AppConfig.lang = 'en';
    AppModeController.applyContext = (_) {};
  });

  Future<OrgSession> pumpApp(WidgetTester tester, FakeApi fake) async {
    mockRequestPlugins();
    fake.install();
    addTearDown(fake.uninstall);
    final session = OrgSession();
    await tester.pumpWidget(ChangeNotifierProvider<OrgSession>.value(
      value: session,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [topRouteObserver],
        initialRoute: '/home',
        onGenerateRoute: (s) => MaterialPageRoute(settings: s, builder: (_) => Scaffold(body: Text('page ${s.name}'))),
      ),
    ));
    return session;
  }

  FakeApi coldBackend() => FakeApi({
        'GET /api/v1/org/mine': (_) => {'items': [_mine(4)]},
        'GET /api/v1/org/public/me/overview': (_) => {
              'items': [_entry(4, ['teacher'], manage: {'is_admin': false}), _entry(5, ['student'])],
              'default_org_id': 4,
            },
      }, latency: const Duration(milliseconds: 200), fallback: (_) => const <String, dynamic>{});

  testWidgets('cold start, push for a STAFF organization: waits for the overview, then opens the dashboard', (tester) async {
    await pumpApp(tester, coldBackend());
    final ctl = AppModeController.instance;
    await tester.runAsync(() async {
      await ctl.reset();
      unawaited(ctl.bindUser(7)); // the overview is on its way, nothing is loaded yet
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ctl.loaded, isFalse);
      await AppNavigator.openFromPush({'org_id': '4'});
    });
    await _frames(tester);
    expect(ctl.loaded, isTrue);
    expect(ctl.isOrg, isFalse, reason: 'a staff organization is never entered as the student-style member home');
    expect(find.text('page /org_dashboard'), findsOneWidget);
  });

  testWidgets('cold start, push for a STUDY organization: the member home, no dashboard, the dashboard session untouched', (tester) async {
    final session = await pumpApp(tester, coldBackend());
    final ctl = AppModeController.instance;
    await tester.runAsync(() async {
      await ctl.reset();
      unawaited(ctl.bindUser(7));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await AppNavigator.openFromPush({'org_id': '5'});
    });
    await _frames(tester);
    expect(find.text('page /org_dashboard'), findsNothing);
    expect(ctl.isOrg, isTrue);
    expect(ctl.currentOrgId, 5);
    // a study-only organization is never "wanted" by the dashboard's session: a later listing of it selects nothing
    await tester.runAsync(() => session.load());
    expect(session.currentId, isNot(5));
  });

  testWidgets('OrgSession.open for an organization /mine does not list does not stay wanted', (tester) async {
    var items = [_mine(4)];
    final fake = FakeApi({'GET /api/v1/org/mine': (_) => {'items': items}}, latency: Duration.zero, fallback: (_) => const <String, dynamic>{});
    mockRequestPlugins();
    fake.install();
    addTearDown(fake.uninstall);
    final s = OrgSession();
    await tester.runAsync(() => s.load());
    s.open(9);
    await tester.runAsync(() => s.load());
    items = [_mine(4), _mine(9)];
    await tester.runAsync(() => s.load());
    expect(s.currentId, 4);
  });

  group('invitation accepted through /i/<token>', () {
    Map<String, dynamic> lookup(String role) => {
          'org': {'id': 4, 'name_ar': 'جامعة النيل', 'name_en': 'Nile University', 'logo_url': null},
          'role': role,
          'status': 'pending',
          'expires_at': '2099-01-01T10:00:00',
          'contact_masked': 'a***@mail.com',
        };

    Future<(FakeApi, OrgSession)> pumpInvitee(WidgetTester tester, String role) async {
      final fake = FakeApi({
        'GET /api/v1/org/public/invitations/TOK12345': (_) => lookup(role),
        'POST /api/v1/org/public/invitations/TOK12345/accept': (_) => {'joined': true, 'org': {'id': 4}},
        'GET /api/v1/org/mine': (_) => {'items': [_mine(4)]},
        'GET /api/v1/org/public/me/overview': (_) => {
              'items': [_entry(4, [role == 'student' ? 'student' : 'teacher'], manage: role == 'student' ? null : {'is_admin': false})],
              'default_org_id': 4,
            },
      }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{});
      mockRequestPlugins();
      fake.install();
      addTearDown(fake.uninstall);
      final session = OrgSession();
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<OrgSession>.value(
        value: session,
        child: ThemeConfigScope(
          provider: ThemeConfigProvider(api: ApiClient()),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const OrgInviteePage(token: 'TOK12345', signedIn: true),
            onGenerateRoute: (s) => MaterialPageRoute(settings: s, builder: (_) => Scaffold(body: Text('page ${s.name}'))),
          ),
        ),
      ));
      await _frames(tester);
      return (fake, session);
    }

    testWidgets('a staff invitee: memberships and organizations reload, "Open the organization" opens the dashboard', (tester) async {
      AppModeController.instance.debugSet({'items': [], 'default_org_id': null}, mode: AppMode.individual);
      final (fake, session) = await pumpInvitee(tester, 'teacher');
      expect(find.byKey(const ValueKey('org.invitee.open')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('org.invitee.accept')));
      await _frames(tester);
      expect(fake.calls.where((c) => c.path == '/api/v1/org/public/me/overview'), isNotEmpty, reason: 'AppModeController reloaded');
      expect(fake.calls.where((c) => c.path == '/api/v1/org/mine'), isNotEmpty, reason: 'OrgSession reloaded');
      expect(find.byKey(const ValueKey('org.invitee.open')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('org.invitee.open')));
      await _frames(tester);
      expect(find.text('page /org_dashboard'), findsOneWidget);
      expect(session.currentId, 4);
      expect(AppModeController.instance.isOrg, isFalse);
    });

    testWidgets('a student invitee: "Open the organization" enters Organization mode (the member home)', (tester) async {
      AppModeController.instance.debugSet({'items': [], 'default_org_id': null}, mode: AppMode.individual);
      await pumpInvitee(tester, 'student');
      await tester.tap(find.byKey(const ValueKey('org.invitee.accept')));
      await _frames(tester);
      await tester.tap(find.byKey(const ValueKey('org.invitee.open')));
      await _frames(tester);
      expect(find.text('page /org_dashboard'), findsNothing);
      expect(find.text('page ${AppModeController.personalRoute}'), findsOneWidget);
      expect(AppModeController.instance.isOrg, isTrue);
      expect(AppModeController.instance.currentOrgId, 4);
    });
  });
}
