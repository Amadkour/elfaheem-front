// The ONE organization dashboard (D-103, docs/backend/org-dashboard-spec.md stage 1): my access per organization
// (`/org/mine?members=1`, an older server without `access`), what '/org_dashboard' shows when nothing is listed
// (students never see "Create organization"), the switcher's routing from a personal home, the access reload on
// `org_access_changed` / 403 org_forbidden · student_forbidden, and the header's refresh state.
// Home cases live in test/org/org_home_v3_test.dart.
import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/org_page_header.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Map<String, dynamic> _org(int id, {String? access, String? role, Object? perms, Object? dept, String? member}) => {
      'id': id,
      'name_ar': 'مؤسسة $id',
      'name_en': 'Org $id',
      'type': 'faculty',
      'status': 'approved',
      'my_role': ?role,
      'access': ?access,
      'member_role': ?member,
      'permissions': perms ?? const <String, dynamic>{},
      'dept_permissions': dept ?? const <String, dynamic>{},
    };

Map<String, dynamic> _entry(int id, List<String> roles, {Object? manage}) => {
      'organization': {'id': id, 'status': 'approved', 'name_en': 'Org $id'},
      'roles': roles,
      'manage': manage,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('access', () {
    test('the server\'s access wins; an older server: admin role → admin, any right → staff, else member', () {
      expect(orgAccessOf(_org(1, access: 'member', role: 'org_admin')), 'member');
      expect(orgAccessOf(_org(1, access: 'staff')), 'staff');
      expect(orgAccessOf(_org(1, role: 'org_admin')), 'admin');
      expect(orgAccessOf(_org(1, role: 'platform_admin')), 'admin');
      expect(orgAccessOf({..._org(1), 'is_admin': true}), 'admin');
      expect(orgAccessOf(_org(1, perms: {'students': ['view']})), 'staff');
      expect(orgAccessOf(_org(1, dept: {'4': {'courses': ['view']}})), 'staff');
      expect(orgAccessOf(_org(1, perms: {'students': <String>[]}, dept: {'4': <String, dynamic>{}})), 'member');
      expect(orgAccessOf(_org(1)), 'member');
      expect(orgAccessOf({..._org(1), 'access': 'owner'}), 'member'); // an unknown value is not trusted
      expect(orgAccessOf(null), 'member');
    });

    test('403 codes that mean "my access changed", and the organization of an org route', () {
      expect(orgAccessDeniedCode({'detail': {'code': 'student_forbidden', 'message': 'x'}}), 'student_forbidden');
      expect(orgAccessDeniedCode({'detail': 'org_forbidden'}), 'org_forbidden');
      expect(orgAccessDeniedCode({'code': 'student_forbidden'}), 'student_forbidden');
      expect(orgAccessDeniedCode('{"detail": {"code": "org_forbidden"}}'), 'org_forbidden');
      expect(orgAccessDeniedCode({'detail': {'code': 'mfa_enrollment_required'}}), isNull);
      expect(orgAccessDeniedCode({'detail': 'Forbidden'}), isNull);
      expect(orgAccessDeniedCode(null), isNull);
      expect(orgIdOfPath('/api/v1/org/orgs/12/dashboard'), 12);
      expect(orgIdOfPath('/api/v1/org/orgs/7'), 7);
      expect(orgIdOfPath('/api/v1/org/public/me/overview'), isNull);
    });
  });

  group('routing', () {
    test('the switcher of a personal home: the dashboard wherever I am not a student', () {
      expect(AppModeController.opensDashboard(_entry(1, ['teacher'])), isTrue);
      expect(AppModeController.opensDashboard(_entry(1, ['admin_assistant'])), isTrue);
      expect(AppModeController.opensDashboard(_entry(1, const [], manage: {'is_admin': true})), isTrue);
      expect(AppModeController.opensDashboard(_entry(1, ['student'])), isFalse);
      // a student with grants is still blocked from the dashboard ("dashboard only", spec §2)
      expect(AppModeController.opensDashboard(_entry(1, ['student', 'teacher'], manage: {'is_admin': false})), isFalse);
      expect(AppModeController.studentOnly([_entry(1, ['student']), _entry(2, ['student'])]), isTrue);
      expect(AppModeController.studentOnly([_entry(1, ['student']), _entry(2, ['teacher'])]), isFalse);
      expect(AppModeController.studentOnly([_entry(1, ['student'], manage: {'departments': []})]), isFalse);
      expect(AppModeController.studentOnly(const []), isFalse);
    });

    test('what /org_dashboard shows: never "Create organization" for a student', () {
      OrgGate gate({
        bool loaded = true,
        bool items = false,
        bool blocked = false,
        String? role,
        bool overviewLoaded = true,
        List<Map<String, dynamic>> overview = const [],
      }) =>
          orgDashboardGate(
            loaded: loaded,
            hasItems: items,
            studentBlocked: blocked,
            userRole: role,
            overviewLoaded: overviewLoaded,
            overview: overview,
          );

      expect(gate(loaded: false), OrgGate.loading);
      expect(gate(items: true, role: 'student'), OrgGate.dashboard); // a teacher-member whose account role is student
      expect(gate(blocked: true, role: 'org-admin'), OrgGate.staffOnly); // the server said 403 student_forbidden
      expect(gate(role: 'org-admin', overviewLoaded: false), OrgGate.createFirst); // no wait for the overview
      expect(gate(role: 'org-staff', overviewLoaded: false), OrgGate.loading);
      expect(gate(role: 'org-staff', overview: [_entry(1, ['student'])]), OrgGate.staffOnly);
      expect(gate(role: 'student', overview: [_entry(1, ['student'])]), OrgGate.staffOnly);
      expect(gate(role: 'student'), OrgGate.staffOnly); // no membership at all
      expect(gate(role: 'teacher'), OrgGate.createFirst);
      // an older server lists no member without rights in /mine: their member page, as before
      expect(gate(role: 'org-staff', overview: [_entry(1, ['admin_assistant'])]), OrgGate.memberPage);
    });
  });

  group('OrgSession', () {
    late FakeApi fake;
    var mine = <Map<String, dynamic>>[];

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      fake = FakeApi({
        'GET /api/v1/org/mine': (_) => {'items': mine, 'can_create_root': false},
        'GET /api/v1/org/orgs/5/dashboard': (_) => const FakeResponse(403, {'detail': {'code': 'student_forbidden'}}),
        'GET /api/v1/org/orgs/3/members': (_) => const FakeResponse(403, {'detail': {'code': 'org_forbidden'}}),
      }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{});
      fake.install();
      addTearDown(fake.uninstall);
    });

    test('load asks members=1, exposes access + member role, picks asked → current → remembered → first', () async {
      mine = [
        _org(3, role: 'org_admin'),
        _org(4, access: 'member', member: 'teacher'),
        _org(6, access: 'staff', perms: {'courses': ['view']}),
      ];
      final s = OrgSession();
      await s.load(prefer: 4);
      expect(fake.calls.first.query, {'members': '1'});
      expect(s.currentId, 4); // the remembered one
      expect(s.access, 'member');
      expect(s.memberRole, 'teacher');
      expect(s.isOrgAdmin, isFalse);
      expect(s.can('courses'), isFalse);

      s.select(6);
      expect(s.access, 'staff');
      expect(s.memberRole, isNull);
      await s.load(prefer: 4);
      expect(s.currentId, 6); // the current one is kept over the remembered one

      s.open(3); // loaded and listed → selected at once
      expect(s.currentId, 3);
      expect(s.access, 'admin');

      final fresh = OrgSession()..open(6);
      await fresh.load(prefer: 4);
      expect(fresh.currentId, 6); // asked by the switcher of a personal home
      await fresh.load(keepSelection: false, prefer: 99);
      expect(fresh.currentId, 3); // nothing asked / kept / remembered → the first
    });

    test('an older server (no access, no member_role) keeps working', () async {
      mine = [_org(3, role: 'org_admin'), _org(4, role: 'admin_assistant', perms: {'students': ['view']})];
      final s = OrgSession();
      await s.load();
      expect(s.access, 'admin');
      s.select(4);
      expect(s.access, 'staff');
      expect(s.memberRole, isNull);
    });

    test('org_access_changed reloads my access and every section (epoch)', () async {
      mine = [_org(3, access: 'staff', perms: {'courses': ['view']}), _org(4, access: 'member')];
      final s = OrgSession();
      await s.load();
      s.watchAccess();
      addTearDown(s.unwatchAccess);
      final epoch = s.epoch.value;

      mine = [_org(4, access: 'member')]; // my rights in organization 3 were revoked
      fake.reset();
      LiveEvents.instance.emit(LiveEvents.orgAccessChanged, {'org_id': 3});
      await pumpEventQueue();
      expect(fake.calls.map((c) => c.path), contains('/api/v1/org/mine'));
      expect(s.currentId, 4); // the next organization
      expect(s.epoch.value, greaterThan(epoch));
    });

    test('403 student_forbidden on an org call: that organization leaves the list; nothing left → staff only', () async {
      mine = [_org(5, access: 'member', member: 'teacher')]; // the server still lists it (a race)
      final s = OrgSession();
      await s.load();
      s.watchAccess();
      addTearDown(s.unwatchAccess);

      await expectLater(s.api.get('/api/v1/org/orgs/5/dashboard'), throwsA(anything));
      await pumpEventQueue();
      expect(s.items, isEmpty);
      expect(s.currentId, isNull);
      expect(s.studentBlocked, isTrue);
      expect(orgDashboardGate(loaded: s.loaded, hasItems: s.items.isNotEmpty, studentBlocked: s.studentBlocked),
          OrgGate.staffOnly);

      // my membership role changed: the event lifts the block
      LiveEvents.instance.emit(LiveEvents.orgAccessChanged, {'org_id': 5});
      await pumpEventQueue();
      expect(s.items.map((o) => o['id']), [5]);
      expect(s.studentBlocked, isFalse);
    });

    test('403 org_forbidden reloads once, keeps the organization when still listed, no epoch bump if unchanged',
        () async {
      mine = [_org(3, access: 'staff', perms: {'students': ['view']})];
      final s = OrgSession();
      await s.load();
      s.watchAccess();
      addTearDown(s.unwatchAccess);
      final epoch = s.epoch.value;
      fake.reset();

      await expectLater(s.api.get('/api/v1/org/orgs/3/members'), throwsA(anything));
      await pumpEventQueue();
      await expectLater(s.api.get('/api/v1/org/orgs/3/members'), throwsA(anything));
      await pumpEventQueue();
      expect(fake.calls.where((c) => c.path == '/api/v1/org/mine').length, 1); // at most once per accessReloadGap
      expect(s.currentId, 3);
      expect(s.epoch.value, epoch);
    });

    test('nobody watches (the dashboard is closed): a 403 changes nothing', () async {
      mine = [_org(5, access: 'member')];
      final s = OrgSession();
      await s.load();
      fake.reset();
      await expectLater(s.api.get('/api/v1/org/orgs/5/dashboard'), throwsA(anything));
      await pumpEventQueue();
      expect(fake.calls.where((c) => c.path == '/api/v1/org/mine'), isEmpty);
      expect(s.items, hasLength(1));
    });
  });

  group('page refresh', () {
    setUp(() => TestWidgetsFlutterBinding.ensureInitialized());
    tearDown(() => OrgClock.now = DateTime.now);

    test('"Updated …": just now · minutes · hours · a date', () {
      final now = DateTime(2026, 10, 31, 12);
      expect(orgUpdatedText(now, now), 'Updated just now');
      expect(orgUpdatedText(now.subtract(const Duration(seconds: 59)), now), 'Updated just now');
      expect(orgUpdatedText(now.subtract(const Duration(minutes: 2)), now), 'Updated 2 min ago');
      expect(orgUpdatedText(now.subtract(const Duration(hours: 3)), now), 'Updated 3 h ago');
      expect(orgUpdatedText(now.subtract(const Duration(days: 2)), now), startsWith('Updated '));
      AppConfig.lang = 'ar';
      expect(orgUpdatedText(now.subtract(const Duration(minutes: 2)), now), 'تم التحديث منذ دقيقتين');
      expect(orgUpdatedText(now.subtract(const Duration(minutes: 5)), now), 'تم التحديث منذ 5 دقائق');
      expect(orgUpdatedText(now.subtract(const Duration(minutes: 25)), now), 'تم التحديث منذ 25 دقيقة');
      expect(orgUpdatedText(now.subtract(const Duration(hours: 1)), now), 'تم التحديث منذ ساعة');
    });

    test('nothing registered → Refresh re-keys the page; a registered refresher runs instead and may report', () async {
      var clock = DateTime(2026, 10, 31, 9);
      OrgClock.now = () => clock;
      final r = OrgPageRefresh();
      addTearDown(r.dispose);
      expect(r.updatedAt, clock);

      clock = clock.add(const Duration(minutes: 5));
      await r.refresh();
      expect(r.generation.value, 1);
      expect(r.updatedAt, clock);

      var runs = 0;
      Future<void> reload() async {
        runs++;
        r.markUpdated(DateTime(2026, 10, 31, 8, 58)); // the server's generated_at
      }

      r.attach(reload);
      await r.refresh();
      expect(runs, 1);
      expect(r.generation.value, 1); // not re-keyed
      expect(r.updatedAt, DateTime(2026, 10, 31, 8, 58));
      expect(r.busy, isFalse);

      r.unregister(() async {}); // another function: still registered
      expect(r.hasRefresher, isTrue);
      r.unregister(reload);
      expect(r.hasRefresher, isFalse);

      clock = clock.add(const Duration(minutes: 1));
      r.restarted();
      expect(r.updatedAt, clock);
    });

    testWidgets('register / reportUpdated find the page\'s scope from its context', (tester) async {
      final r = OrgPageRefresh();
      addTearDown(r.dispose);
      var ran = false;
      await tester.pumpWidget(OrgPageRefreshScope(
        controller: r,
        child: Builder(builder: (context) {
          OrgPageRefresh.register(context, () async => ran = true);
          OrgPageRefresh.reportUpdated(context, DateTime(2026, 1, 1)); // from a build: deferred, no exception
          return const SizedBox();
        }),
      ));
      await tester.pump();
      expect(r.updatedAt, DateTime(2026, 1, 1));
      await r.refresh();
      expect(ran, isTrue);
    });
  });
}
