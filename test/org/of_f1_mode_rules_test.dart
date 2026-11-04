// Organization flow overhaul, f1: the switching rules (pure), the fallback when the remembered organization is gone,
// the last-known list kept when a refresh fails, and org A -> org B through a notification tap.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Map<String, dynamic> _entry(int id, List<String> roles, {String status = 'approved', Object? manage, String? name}) => {
      'organization': {'id': id, 'status': status, 'name_en': name ?? 'Org $id', 'name_ar': name ?? 'مؤسسة $id'},
      'roles': roles,
      'manage': manage,
    };

Map<String, dynamic> _mine(int id) => {'id': id, 'name_en': 'Org $id', 'name_ar': 'مؤسسة $id', 'status': 'approved', 'access': 'staff', 'depth': 0};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.orgsEnabled = true;
    AppConfig.disableList = const [];
    AppConfig.lang = 'en';
    AppModeController.applyContext = (_) {};
  });

  group('pure rules', () {
    test('resolveOrgId: remembered while listed, else the default, else the first - and says when it fell back', () {
      OrgChoice r(int? rem, List<int> live, [int? def]) => AppModeController.resolveOrgId(remembered: rem, liveIds: live, defaultId: def);
      expect(r(4, [3, 4]).orgId, 4);
      expect(r(4, [3, 4]).fellBack, isFalse);
      expect(r(null, [3, 4], 4).orgId, 4);
      expect(r(null, [3, 4]).fellBack, isFalse);
      expect(r(9, [3, 4], 4).orgId, 4);
      expect(r(9, [3, 4], 4).fellBack, isTrue);
      expect(r(9, [3, 4]).orgId, 3);
      expect(r(9, const []).orgId, isNull);
      expect(r(9, const []).fellBack, isTrue);
    });

    test('orgGoneText names the lost and the new organization, in both languages', () {
      AppConfig.lang = 'en';
      expect(AppModeController.orgGoneText(lostName: 'Alpha', nowName: 'Beta'), allOf(contains('Alpha'), contains('Beta')));
      expect(AppModeController.orgGoneText(nowName: null), contains('personal'));
      AppConfig.lang = 'ar';
      expect(AppModeController.orgGoneText(lostName: 'ألفا', nowName: 'بيتا'), allOf(contains('ألفا'), contains('بيتا')));
    });

    test('one rule: staff of any kind opens the dashboard, only a student gets the member home', () {
      expect(AppModeController.opensDashboard(_entry(1, ['teacher'])), isTrue);
      expect(AppModeController.opensDashboard(_entry(1, ['student'])), isFalse);
      expect(AppModeController.opensDashboard(_entry(1, ['student', 'teacher'])), isFalse);
    });
  });

  group('AppModeController', () {
    test('openOrg: a staff organization is remembered (dashboard), a study organization enters Organization mode', () async {
      final ctl = AppModeController.instance;
      ctl.debugSet({
        'items': [_entry(1, ['teacher'], manage: {'is_admin': false}), _entry(2, ['student'])],
      }, mode: AppMode.individual);
      await ctl.openOrg(1);
      expect(ctl.isOrg, isFalse);
      expect(ctl.currentOrgId, 1);
      await ctl.openOrg(2);
      expect(ctl.isOrg, isTrue);
      expect(ctl.currentOrgId, 2);
      await ctl.openOrg(1); // from Organization mode to a staff organization: the member home is left
      expect(ctl.isOrg, isFalse);
      await ctl.openOrg(77); // not one of mine: nothing changes
      expect(ctl.currentOrgId, 1);
    });

    test('the overview no longer lists the remembered organization: fallback WITH a notice; Retry state on failure', () async {
      SharedPreferences.setMockInitialValues({});
      final notices = <String>[];
      AppModeController.showGoneNotice = notices.add;
      addTearDown(() => AppModeController.showGoneNotice = (_) {});
      var phase = 0;
      final fake = FakeApi({
        'GET /api/v1/org/public/me/overview': (_) {
          if (phase == 0) return {'items': [_entry(5, ['student'], name: 'Alpha'), _entry(6, ['student'], name: 'Beta')], 'default_org_id': 5};
          if (phase == 1) return const FakeResponse(500, {'detail': 'boom'});
          return {'items': [_entry(6, ['student'], name: 'Beta')], 'default_org_id': 6};
        },
      }, latency: Duration.zero);
      mockRequestPlugins();
      fake.install();
      addTearDown(fake.uninstall);

      final ctl = AppModeController.instance;
      await ctl.reset();
      SharedPreferences.setMockInitialValues({'app_mode.7': 'organization', 'app_mode_org.7': 5});
      await ctl.bindUser(7);
      expect(ctl.isOrg, isTrue);
      expect(ctl.currentOrgId, 5);
      expect(notices, isEmpty);

      phase = 1; // offline / server error: the last known list stays, the failure is flagged
      await ctl.refresh();
      expect(ctl.refreshFailed, isTrue);
      expect(ctl.liveEntries.length, 2);
      expect(notices, isEmpty);

      phase = 2; // Alpha was removed: Beta opens, and the person is told
      await ctl.refresh();
      expect(ctl.refreshFailed, isFalse);
      expect(ctl.currentOrgId, 6);
      expect(notices, hasLength(1));
      expect(notices.single, allOf(contains('Alpha'), contains('Beta')));
      await ctl.reset();
    });

    test('a staff organization is never entered as Organization mode (remembered mode is normalised)', () async {
      final fake = FakeApi({
        'GET /api/v1/org/public/me/overview': (_) => {'items': [_entry(1, ['teacher'], manage: {'is_admin': false})], 'default_org_id': 1},
      }, latency: Duration.zero);
      mockRequestPlugins();
      fake.install();
      addTearDown(fake.uninstall);
      final ctl = AppModeController.instance;
      await ctl.reset();
      SharedPreferences.setMockInitialValues({'app_mode.8': 'organization', 'app_mode_org.8': 1});
      await ctl.bindUser(8);
      expect(ctl.isOrg, isFalse);
      expect(ctl.currentOrgId, 1);
      await ctl.reset();
    });
  });

  group('OrgSession', () {
    test('a failed /org/mine keeps the last known list and flags loadFailed (never "no organizations")', () async {
      var fail = false;
      final fake = FakeApi({
        'GET /api/v1/org/mine': (_) => fail ? const FakeResponse(503, {'detail': 'down'}) : {'items': [_mine(3), _mine(4)]},
      }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{});
      mockRequestPlugins();
      fake.install();
      addTearDown(fake.uninstall);
      final s = OrgSession();
      await s.load();
      expect(s.loadFailed, isFalse);
      fail = true;
      await s.load();
      expect(s.loadFailed, isTrue);
      expect(s.items.length, 2);
      expect(s.currentId, 3);
      fail = false;
      await s.load();
      expect(s.loadFailed, isFalse);
    });

    test('the organization I was in disappears: the fallback is announced', () async {
      final notices = <String>[];
      AppModeController.showGoneNotice = notices.add;
      addTearDown(() => AppModeController.showGoneNotice = (_) {});
      var items = [_mine(3), _mine(4)];
      final fake = FakeApi({'GET /api/v1/org/mine': (_) => {'items': items}}, latency: Duration.zero, fallback: (_) => const <String, dynamic>{});
      mockRequestPlugins();
      fake.install();
      addTearDown(fake.uninstall);
      final s = OrgSession();
      await s.load();
      s.select(4);
      items = [_mine(3)];
      await s.load();
      expect(s.currentId, 3);
      expect(notices, hasLength(1));
      expect(notices.single, allOf(contains('Org 4'), contains('Org 3')));
      await s.load(); // nothing changed any more: silent
      expect(notices, hasLength(1));
    });
  });

  testWidgets('a notification for org B while org A is open: OrgSession ends on B and no page of A stays open', (tester) async {
    final fake = FakeApi({
      'GET /api/v1/org/mine': (_) => {'items': [_mine(3), _mine(4)]},
      'GET /api/v1/org/public/me/overview': (_) => {
            'items': [_entry(3, ['teacher'], manage: {'is_admin': false}), _entry(4, ['teacher'], manage: {'is_admin': false})],
            'default_org_id': 3,
          },
    }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{});
    mockRequestPlugins();
    fake.install();
    addTearDown(fake.uninstall);

    final session = OrgSession();
    await tester.runAsync(() => session.load());
    session.select(3);
    final ctl = AppModeController.instance;
    ctl.debugSet({
      'items': [_entry(3, ['teacher'], manage: {'is_admin': false}), _entry(4, ['teacher'], manage: {'is_admin': false})],
      'default_org_id': 3,
    }, mode: AppMode.individual, orgId: 3);

    await tester.pumpWidget(ChangeNotifierProvider<OrgSession>.value(
      value: session,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [topRouteObserver],
        initialRoute: '/home',
        onGenerateRoute: (s) => MaterialPageRoute(settings: s, builder: (_) => Scaffold(body: Text('page ${s.name}'))),
      ),
    ));
    final nav = navigatorKey.currentState!;
    nav.pushNamed('/org_dashboard');
    await tester.pumpAndSettle();
    nav.pushNamed('/org_a_page'); // a page of organization A on top of the dashboard
    await tester.pumpAndSettle();
    expect(find.text('page /org_a_page'), findsOneWidget);

    await tester.runAsync(() => AppNavigator.openFromPush({'org_id': '4'}));
    await tester.pumpAndSettle();

    expect(session.currentId, 4);
    expect(ctl.currentOrgId, 4);
    expect(find.text('page /org_a_page'), findsNothing);
    expect(find.text('page /org_dashboard'), findsOneWidget);
  });
}
