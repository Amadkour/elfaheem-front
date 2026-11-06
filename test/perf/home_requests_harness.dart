// Home performance numbers (PROGRESS.md §3 "Dashboard requests on open"): each role's real dashboard screen,
// pumped with the app's real providers over a fake backend (test/support/fake_api.dart, fixture payloads), on a
// 400 px phone. Counted per role: HTTP requests on first open, duplicates, the waterfall depth (how many calls had
// to wait for an earlier answer), and the requests of one pull-to-refresh. Each role runs in its own test file —
// its own isolate — because the app-wide singletons (MeHomeService, AppModeController, AttentionService) would carry
// one role's cache into the next.
//
// The budgets below are today's numbers: a home that makes MORE requests than its budget fails the test. When a
// change makes a home cheaper, lower its budget in the same commit.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/widget/refresh_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

/// Requests on open · duplicates on open · waterfall depth on open · requests of one pull-to-refresh · its depth.
typedef HomeBudget = ({int open, int duplicates, int depth, int refresh, int refreshDepth});

// 2026-10-28, after the student / teacher fixes (PROGRESS.md §3). Before them: student 21 · 4 duplicates · depth 2
// · refresh 4 (depth 2); teacher refresh depth 2. Then lazy shell tabs (AppShell's LazyTabStack, D-077: a tab is
// built on its first visit, so the other tabs load nothing on open): student 17 → 11, teacher 15 → 11, super admin
// 10 → 7, org admin 15 → 4 on open; refresh unchanged. The super admin's refresh is 4 since the home's RAG card
// (monitoring alerts + summary, 4f69dfe) joined the overview and the payouts count.
// 2026-10-31, D-103: org admin open 4 → 5 — the organization dashboard's pages now carry a header with the
// notifications bell on every width (the shell top bar is off), and its unread count is the same ONE
// GET /notifications every other role shell makes (no server field carries it); `/org/mine` gained `?members=1`
// (same call). The membership overview is NOT loaded on open — only when the header's switcher is used.
const homeBudgets = <String, HomeBudget>{
  'student': (open: 11, duplicates: 0, depth: 1, refresh: 3, refreshDepth: 1),
  'teacher': (open: 11, duplicates: 0, depth: 1, refresh: 3, refreshDepth: 1),
  'super-admin': (open: 7, duplicates: 0, depth: 1, refresh: 4, refreshDepth: 1),
  // 2026-11-04, D-287: parent open 3 → 4 — the children's organizations card (GET /org/parent/children), in parallel
  // with the overview (no waterfall), not refreshed with it; nothing at all is drawn when no child is in one.
  'parent': (open: 4, duplicates: 0, depth: 1, refresh: 1, refreshDepth: 1),
  // +1 = the lazy Insights section (D-103): GET …/insights, started in parallel with the dashboard (no waterfall)
  // 2026-11-05, D-287 (f5): open 6 → 7 — the setup checklist (GET /orgs/{id}/setup), started in PARALLEL with the
  // dashboard call (OrgSetupPrefetch, no waterfall: depth stays 2) and NOT asked again on pull-to-refresh (only after
  // a checklist step's page was opened); nothing at all when organizations or `org.setup_checklist` are off.
  'org-admin': (open: 7, duplicates: 0, depth: 2, refresh: 1, refreshDepth: 1),
  // 2026-10-31: open 3 → 4 — GET /me/home carries the mode's side (scope / org_id, the server's default is the
  // personal account). On a first launch the mode is only known from the overview's smart default, so the home asked
  // in parallel is the personal side's: its course block is dropped and the organization's home is asked once more.
  // 2026-11-06: open 4 → 5 — the "My academic advisor" card (academic advising, D-289) asks its organization's
  // member status once, in parallel with the feed (depth unchanged); folding it into /me/overview is a Phase 9 item.
  'org-member': (open: 5, duplicates: 0, depth: 2, refresh: 2, refreshDepth: 1),
};

class HomeMetrics {
  HomeMetrics(this.role);
  final String role;
  var open = <FakeCall>[];
  var duplicates = <String>[];
  var depth = 0;
  var refresh = <FakeCall>[];
  var refreshDepth = 0;
  var unmatched = <String>[];

  @override
  String toString() =>
      '[$role] open ${open.length} · duplicates ${duplicates.length} · depth $depth · refresh ${refresh.length} (depth $refreshDepth)\n'
      '  open:\n${open.map((c) => '    $c').join('\n')}\n'
      '  duplicates: $duplicates\n'
      '  refresh:\n${refresh.map((c) => '    $c').join('\n')}\n'
      '  not in the route table (answered {}): $unmatched';
}

const _org = {'id': 1, 'status': 'approved', 'type': 'faculty', 'name_ar': 'كلية', 'name_en': 'Agg U'};

/// Answers every route a home touches on open: the recorded fixtures for the home aggregates, small real shapes for
/// the rest. Anything else gets `{}` (and is listed in the report).
Map<String, FakeHandler> homeRoutes({bool memberOfOrg = false}) => {
      'GET /api/v1/me/home': (_) => payload(memberOfOrg ? 'me_home_student.json' : 'me_home_student_no_org.json'),
      'GET /api/v1/admin/overview': (_) => payload('admin_overview.json'),
      'GET /api/v1/parent/overview': (_) => payload('parent_overview.json'),
      'GET /api/v1/org/parent/children': (_) => {'children': []},
      // an org admin sees Insights (D-103), so its call is really measured
      'GET /api/v1/org/orgs/1/dashboard': (_) => {...(payload('org_dashboard.json') as Map), 'can_insights': true},
      'GET /api/v1/org/orgs/1/insights': (_) => payload('org_insights.json'),
      'GET /api/v1/org/mine': (_) => {
            'items': [
              {..._org, 'my_role': 'org_admin', 'is_admin': true},
            ],
            'can_create_root': false,
          },
      'GET /api/v1/org/public/me/overview': (_) => memberOfOrg
          ? {
              'items': [
                {
                  'organization': _org,
                  'roles': ['student'],
                  'manage': null,
                  'todo': {'total': 2},
                  'approvals': {'total': 0},
                  'news': 1,
                },
              ],
              'default_org_id': 1,
              'suggested_mode': 'organization',
              'pending_total': 2,
            }
          : {'items': [], 'pending_total': 0},
      'GET /api/v1/org/public/mine': (_) => {'items': []},
      'GET /api/v1/me/attention': (_) => {'counts': {}, 'total': 0, 'items': []},
      'GET /api/v1/me/calendar': (_) => {'events': []},
      'GET /api/v1/me/inbox': (_) => {'items': [], 'counts': {}},
      'GET /api/v1/ads/feed': (_) => {'items': []},
      'GET /api/v1/home/mix': (_) => <String, dynamic>{},
      'GET /api/v1/categories': (_) => [],
      'GET /api/v1/auth/mfa/status': (_) => {'enabled': false, 'allowed': false, 'required': false},
      'GET /api/v1/auth/account-setup': (_) => {'required': false},
      'GET /api/v1/data-lab/me/pending-requests': (_) => {'items': []},
      'GET /api/v1/notifications': (_) => {'items': [], 'total': 0, 'unread_count': 0},
      'GET /api/v1/complaints/unread-count': (_) => {'count': 0},
      'GET /api/v1/my-enrolled-courses': (_) => {'items': [], 'total': 0},
      'GET /api/v1/my-courses': (_) => {'items': [], 'total': 0},
    };

Future<StorageService> _storage() async {
  translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  SharedPreferences.setMockInitialValues({});
  mockRequestPlugins();
  return StorageService.getInstance();
}

/// Opens [screen] as [role] over the fake backend, then pulls to refresh, and returns what was requested.
Future<HomeMetrics> measureHome(WidgetTester tester, String role, Widget screen, {bool memberOfOrg = false}) async {
  final storage = await _storage();
  await storage.saveUser({'id': 7, 'name': 'Test User', 'gmail': 'user@example.com', 'role': role == 'org-member' ? 'student' : role});
  final api = FakeApi(homeRoutes(memberOfOrg: memberOfOrg), fallback: (_) => const <String, dynamic>{});
  api.install();
  addTearDown(api.uninstall);
  AppModeController.applyContext = (_) {};
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final theme = ThemeConfigProvider(api: ApiClient());
  await tester.pumpWidget(MultiProvider(
    providers: appProviders(storage: storage, api: ApiClient()),
    child: ThemeConfigScope(provider: theme, child: MaterialApp(navigatorKey: navigatorKey, home: screen)),
  ));
  // 3 s of app time: every answer takes 100 ms, so a 5-step waterfall still lands inside
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final m = HomeMetrics(role)
    ..open = List.of(api.calls)
    ..duplicates = api.duplicates
    ..depth = api.waterfallDepth
    ..unmatched = api.unmatched.toSet().toList();
  expect(tester.takeException(), isNull);

  // pull to refresh: the home's RefreshIndicator, else the shell's refresh button
  api.reset();
  final indicator = find.byType(RefreshIndicator);
  if (indicator.evaluate().isNotEmpty) {
    tester.state<RefreshIndicatorState>(indicator.first).show();
  } else if (find.byType(RefreshButton).evaluate().isNotEmpty) {
    await tester.tap(find.byType(RefreshButton).first);
  }
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  m
    ..refresh = List.of(api.calls)
    ..refreshDepth = api.waterfallDepth;
  expect(tester.takeException(), isNull);

  // let every timer the home started run out (polls stop once nothing listens)
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 70; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  // ignore: avoid_print
  print(m);
  return m;
}

/// Fails when [m] is over its role's budget.
void expectWithinBudget(HomeMetrics m) {
  final b = homeBudgets[m.role]!;
  expect(
    (open: m.open.length, duplicates: m.duplicates.length, depth: m.depth, refresh: m.refresh.length, refreshDepth: m.refreshDepth),
    predicate<HomeBudget>(
        (x) =>
            x.open <= b.open &&
            x.duplicates <= b.duplicates &&
            x.depth <= b.depth &&
            x.refresh <= b.refresh &&
            x.refreshDepth <= b.refreshDepth,
        'within the budget $b'),
    reason: '$m',
  );
}
