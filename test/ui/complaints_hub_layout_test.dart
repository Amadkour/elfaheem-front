// The profile's Complaints page (D-086): the body on every screen size (layout harness), its callbacks, and the
// data controller over the fake backend (both sources, an older server, an optimistic status change rolled back).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaints_hub_data.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaints_hub_model.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaints_hub_widgets.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/attention/decision_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

final _now = DateTime.utc(2026, 10, 28, 7);
const _long = 'A complaint title that is much longer than anyone would normally write, to stress the card layout';
const _org = HubName('جامعة القاهرة للعلوم والتكنولوجيا والدراسات العليا', 'Cairo University of Science, Technology and Graduate Studies');
const _dept = HubName('إدارة شؤون الطلاب والخريجين والقبول', 'Student, Graduate and Admissions Affairs Office');

List<HubRow> _mine() => [
      HubRow(source: HubSource.platform, id: 1, title: _long, snippet: _long * 2, status: HubStatus.inProgress,
          createdAt: _now.subtract(const Duration(days: 1)), updatedAt: _now.subtract(const Duration(minutes: 3)),
          unread: true, replies: 12, attachments: 3, about: 'Python Fundamentals for Absolute Beginners'),
      HubRow(source: HubSource.org, id: 2, ref: 'C-000002', title: _long, snippet: _long, status: HubStatus.waiting,
          createdAt: _now.subtract(const Duration(days: 30)), updatedAt: _now.subtract(const Duration(days: 20)),
          org: _org, department: _dept, orgId: 3),
      HubRow(source: HubSource.platform, id: 3, title: 'Charged twice', status: HubStatus.closed,
          createdAt: _now.subtract(const Duration(days: 9)), updatedAt: _now.subtract(const Duration(days: 9))),
    ];

List<HubRow> _toResolve() => [
      HubRow(source: HubSource.org, id: 11, ref: 'C-000011', title: _long, snippet: _long, status: HubStatus.open,
          priority: 'urgent', createdAt: _now.subtract(const Duration(days: 2)), updatedAt: _now.subtract(const Duration(days: 2)),
          dueAt: _now.subtract(const Duration(hours: 50)), unread: true, org: _org, department: _dept, orgId: 3,
          sender: 'Mariam Abdelrahman Mohamed Elsayed', canAct: true, mine: false, replies: 4, attachments: 2),
      HubRow(source: HubSource.org, id: 12, ref: 'C-000012', title: 'Late letter', status: HubStatus.inProgress,
          priority: 'high', createdAt: _now.subtract(const Duration(days: 1)), updatedAt: _now,
          dueAt: _now.add(const Duration(hours: 5)), org: _org, department: _dept, orgId: 3, anonymous: true,
          canAct: true, mine: false),
      HubRow(source: HubSource.platform, id: 61, title: 'Too fast', status: HubStatus.open,
          createdAt: _now.subtract(const Duration(hours: 6)), updatedAt: _now.subtract(const Duration(hours: 6)),
          sender: 'Youssef', about: 'Python', canAct: true, mine: false),
      HubRow(source: HubSource.org, id: 9, title: 'Library card', status: HubStatus.resolved,
          createdAt: _now.subtract(const Duration(days: 4)), updatedAt: _now.subtract(const Duration(days: 1)),
          org: _org, orgId: 3, sender: 'Sara', canAct: true, mine: false),
    ];

Widget _view({
  HubSegment segment = HubSegment.mine,
  bool showToResolve = true,
  List<HubRow>? mine,
  List<HubRow>? toResolve,
  HubFilter? filter,
  String query = '',
  bool loading = false,
  bool failed = false,
  TextEditingController? search,
  ValueChanged<HubSegment>? onSegment,
  ValueChanged<HubFilter>? onFilter,
  VoidCallback? onNew,
  ValueChanged<HubRow>? onOpen,
  void Function(HubRow, HubAction)? onAction,
  VoidCallback? onClear,
}) =>
    ComplaintsHubView(
      segment: segment,
      showToResolve: showToResolve,
      mine: mine ?? _mine(),
      toResolve: toResolve ?? _toResolve(),
      filter: filter ?? defaultFilter(segment),
      query: query,
      now: _now,
      loading: loading,
      failed: failed,
      searchController: search ?? TextEditingController(text: query),
      onSegment: onSegment ?? (_) {},
      onFilter: onFilter ?? (_) {},
      onNew: onNew ?? () {},
      onOpen: onOpen ?? (_) {},
      onAction: onAction ?? (_, _) {},
      onRefresh: () async {},
      onClearFilters: onClear ?? () {},
    );

void main() {
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('layout', () {
    testWidgets('my complaints', (t) => expectNoLayoutErrors(t, () => _view()));
    testWidgets('to resolve', (t) => expectNoLayoutErrors(t, () => _view(segment: HubSegment.toResolve)));
    testWidgets('to resolve, a quick action in flight', (t) => expectNoLayoutErrors(t, () {
          final rows = _toResolve();
          return ComplaintsHubView(
            segment: HubSegment.toResolve, showToResolve: true, mine: const [], toResolve: rows,
            filter: HubFilter.active, query: '', now: _now, searchController: TextEditingController(),
            busy: {rows.first.key}, onSegment: (_) {}, onFilter: (_) {}, onNew: () {}, onOpen: (_) {},
            onAction: (_, _) {}, onRefresh: () async {}, onClearFilters: () {},
          );
        }));
    testWidgets('a student: no segments', (t) => expectNoLayoutErrors(t, () => _view(showToResolve: false)));
    testWidgets('nothing yet', (t) => expectNoLayoutErrors(t, () => _view(showToResolve: false, mine: const [], toResolve: const [])));
    testWidgets('all caught up', (t) => expectNoLayoutErrors(t, () => _view(segment: HubSegment.toResolve, toResolve: const [])));
    testWidgets('nothing matches', (t) => expectNoLayoutErrors(t, () => _view(query: 'zzz')));
    testWidgets('loading', (t) => expectNoLayoutErrors(t, () => _view(mine: const [], loading: true)));
    testWidgets('a source failed', (t) => expectNoLayoutErrors(t, () => _view(failed: true)));
    testWidgets('where should it go', (t) => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
              child: HubDestinationSheet(orgs: const [(3, _org, null), (4, _dept, '')], onApp: () {}, onOrg: (_) {}),
            )));
  });

  group('behaviour', () {
    testWidgets('segments, chips, New complaint, open and quick actions call back', (t) async {
      HubSegment? seg;
      HubFilter? f;
      var news = 0;
      HubRow? opened;
      final acted = <(int, HubAction)>[];
      t.view.physicalSize = const Size(500, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(layoutHost(
        _view(
          segment: HubSegment.toResolve,
          onSegment: (s) => seg = s,
          onFilter: (x) => f = x,
          onNew: () => news++,
          onOpen: (r) => opened = r,
          onAction: (r, a) => acted.add((r.id, a)),
        ),
        scale: 1,
      ));
      await t.pump();
      // most urgent first: the overdue org complaint, then the one due in 5 h, then the platform one
      final titles = t.widgetList<HubRowCard>(find.byType(HubRowCard)).map((w) => w.row.id).toList();
      expect(titles, [11, 12, 61]); // "Needs action": the resolved one is not shown
      expect(find.text('Overdue 2 d'), findsOneWidget);
      expect(find.text('Reply within 5 h'), findsOneWidget);
      expect(find.textContaining('Anonymous'), findsOneWidget);

      await t.tap(find.text('My complaints'));
      expect(seg, HubSegment.mine);
      await t.tap(find.text('Overdue'));
      expect(f, HubFilter.overdue);
      await t.tap(find.text('New complaint'));
      expect(news, 1);
      await t.tap(find.text('Resolve').first);
      await t.tap(find.text('Start').first);
      await t.tap(find.text('Reply').last);
      expect(acted, [(11, HubAction.resolve), (11, HubAction.start), (61, HubAction.reply)]);
      await t.tap(find.text('Late letter'));
      expect(opened?.id, 12);
    });

    testWidgets('My complaints: a new reply is marked, nothing to act on', (t) async {
      await t.pumpWidget(layoutHost(_view(showToResolve: false), scale: 1));
      await t.pump();
      expect(find.text('New reply'), findsOneWidget);
      expect(find.text('Waiting for you'), findsOneWidget);
      expect(find.text('Resolve'), findsNothing);
      expect(find.text('To resolve'), findsNothing);
    });
  });

  group('data', () {
    late FakeApi api;
    Map<String, dynamic> platform(int id, int userId, {String status = 'open'}) => {
          'id': id, 'user_id': userId, 'user_name': 'U$userId', 'title': 'P$id', 'description': 'd', 'category': 'general',
          'priority': 'medium', 'status': status, 'is_read_by_admin': true, 'is_read_by_user': true,
          'created_at': '2026-10-27T07:00:00', 'updated_at': '2026-10-27T07:00:00', 'replies_count': 0,
        };

    Future<void> boot(WidgetTester t, Map<String, FakeHandler> routes) async {
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      await StorageService.getInstance();
      AppConfig.orgsEnabled = true;
      api = FakeApi(routes, latency: const Duration(milliseconds: 10));
      api.install();
      addTearDown(api.uninstall);
    }

    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets('both lists from both sources; an older server is split by owner and its missing route is empty', (t) async {
      await boot(t, {
        // an older server ignores `scope`: both of these come back for either scope
        'GET /api/v1/complaints': (_) => {'items': [platform(1, 7), platform(2, 99)], 'total': 2, 'page': 1, 'pages': 1},
        'GET /api/v1/org/public/me/complaints': (_) => {
              'items': [
                {'id': 5, 'org_id': 3, 'subject': 'AC', 'status': 'open', 'created_at': '2026-10-26T07:00:00', 'unread': true},
              ],
            },
        // no /me/complaints/to-resolve route → FastAPI's bare 404 (FakeApi's default)
      });
      final ctl = ComplaintsHubController(myId: 7, listen: false, orgNames: {3: const HubName('', 'Cairo University')});
      addTearDown(ctl.dispose);
      final done = ctl.refresh();
      await settle(t);
      await done;
      expect(ctl.mine.map((r) => r.key).toList(), ['platform:1', 'org:5']);
      expect(ctl.mine.last.org!.text, 'Cairo University');
      expect(ctl.toResolve.map((r) => r.key).toList(), ['platform:2']);
      expect((ctl.mineFailed, ctl.toResolveFailed), (false, false));
      expect((ctl.loadingMine, ctl.loadingToResolve), (false, false));
      final asked = api.calls.map((c) => c.key).toSet();
      expect(asked, containsAll(<String>[
        'GET /api/v1/complaints?per_page=100&scope=mine',
        'GET /api/v1/complaints?per_page=100&scope=to_resolve',
        'GET /api/v1/org/public/me/complaints?size=50',
        'GET /api/v1/org/public/me/complaints/to-resolve?status=all',
      ]));
    });

    testWidgets('a quick action is optimistic and rolled back when refused', (t) async {
      var refuse = true;
      await boot(t, {
        'GET /api/v1/complaints': (o) => {
              'items': o.uri.queryParameters['scope'] == 'to_resolve' ? [platform(2, 99)] : <Object>[],
            },
        'GET /api/v1/org/public/me/complaints': (_) => {'items': []},
        'GET /api/v1/org/public/me/complaints/to-resolve': (_) => {
              'items': [
                {'id': 11, 'org_id': 3, 'subject': 'Grade', 'status': 'open', 'created_at': '2026-10-26T07:00:00',
                  'user': {'id': 4, 'name': 'Sara'}, 'can_act': true},
              ],
              'stats': {'active': 1, 'overdue': 0, 'unread': 0},
            },
        'PUT /api/v1/org/orgs/3/complaints/11': (_) => refuse ? const FakeResponse(403, {'detail': 'Forbidden'}) : {'status': 'resolved'},
        'PUT /api/v1/complaints/2': (_) => platform(2, 99, status: 'in_progress'),
      });
      final ctl = ComplaintsHubController(myId: 7, listen: false);
      addTearDown(ctl.dispose);
      final done = ctl.refresh();
      await settle(t);
      await done;
      final org = ctl.toResolve.firstWhere((r) => r.source == HubSource.org);
      expect(org.canAct, isTrue);

      var ok = ctl.setStatus(org, HubStatus.resolved);
      expect(ctl.toResolve.firstWhere((r) => r.key == org.key).status, HubStatus.resolved); // at once
      await settle(t);
      expect(await ok, isFalse);
      expect(ctl.toResolve.firstWhere((r) => r.key == org.key).status, HubStatus.open); // rolled back

      refuse = false;
      ok = ctl.setStatus(org, HubStatus.resolved);
      await settle(t);
      expect(await ok, isTrue);
      expect(ctl.toResolve.firstWhere((r) => r.key == org.key).status, HubStatus.resolved);

      final p = ctl.toResolve.firstWhere((r) => r.source == HubSource.platform);
      ok = ctl.setStatus(p, HubStatus.inProgress);
      await settle(t);
      expect(await ok, isTrue);
      expect(api.calls.where((c) => c.method == 'PUT').map((c) => c.path),
          ['/api/v1/org/orgs/3/complaints/11', '/api/v1/org/orgs/3/complaints/11', '/api/v1/complaints/2']);
      await t.pump(DecisionRefresh.coalesce); // the badge refresh a successful decision schedules
    });
  });
}
