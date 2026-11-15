// Institutions v2, phase 3 (docs/institutions/V2_PLAN.md item 3, D-989 – D-990): the councils question. The
// payload parses, the draft builds the none / faculty / departments / both bodies, select all, the open-agenda
// lock, the faculty chair check; the page saves over FakeApi (incl. 409 council_has_open_agenda and 422
// head_required); the view lays out at 320×640 and 1400×900 in Arabic and English with text scale 1.3.
import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/governance/gov_councils_setup.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/org/org_v3.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _base = '/api/v1/org/orgs/5/governance/councils-setup';

Map<String, dynamic> _payload({
  String mode = 'none',
  bool derived = true,
  List<int> deptIds = const [],
  bool autoNew = false,
  Map<String, dynamic>? faculty,
  int openAgenda = 3,
}) =>
    {
      'mode': mode,
      'dept_ids': deptIds,
      'auto_new': autoNew,
      'derived': derived,
      'faculty': faculty,
      'departments': [
        {'id': 1, 'name': 'Computer Science', 'head': {'id': 21, 'name': 'Dr. Mona', 'acting': false}, 'has_council': true, 'council_id': 11, 'open_agenda_items': openAgenda, 'selected': deptIds.contains(1)},
        {'id': 2, 'name': 'Information Systems', 'head': {'id': 22, 'name': 'Dr. Ali', 'acting': true}, 'has_council': false, 'council_id': null, 'open_agenda_items': 0, 'selected': deptIds.contains(2)},
        {'id': 3, 'name': 'A scientific department with a very long name that wraps on a phone', 'head': null, 'has_council': false, 'council_id': null, 'open_agenda_items': 0, 'selected': deptIds.contains(3)},
      ],
    };

CouncilsSetup _setup([Map<String, dynamic>? p]) => CouncilsSetup.fromJson(p ?? _payload());

Map<String, dynamic> _body(RequestOptions o) {
  final d = o.data;
  if (d is Map) return Map<String, dynamic>.from(d);
  if (d is String && d.isNotEmpty) return Map<String, dynamic>.from(jsonDecode(d) as Map);
  return {};
}

Widget _host(Widget child) => ChangeNotifierProvider<OrgSession>(
      create: (_) => OrgSession()..currentId = 5,
      child: ThemeConfigScope(
        provider: ThemeConfigProvider(api: ApiClient()),
        child: MaterialApp(navigatorKey: navigatorKey, debugShowCheckedModeBanner: false, home: Scaffold(body: child)),
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

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('draft', () {
    test('payload parses; a derived setup with no council asks Q1, a saved "none" is answered No', () {
      final s = _setup(_payload(faculty: {
        'id': 9,
        'chair': {'id': 30, 'name': 'Dean'},
        'secretary': null,
        'members': [
          {'id': 30, 'name': 'Dean'},
          {'id': 31, 'name': 'Prof'},
        ],
      }));
      expect(s.departments.length, 3);
      expect(s.departments.first.locked, isTrue);
      expect(s.departments[1].head!.acting, isTrue);
      expect(s.departments[2].head, isNull);
      expect(s.faculty!.chair!.id, 30);
      expect(CouncilsDraft.from(s).want, isNull);
      expect(CouncilsDraft.from(s).members.map((u) => u.id).toList(), [31], reason: 'the chair is not a plain member');
      expect(CouncilsDraft.from(_setup(_payload(derived: false))).want, isFalse);
      expect(CouncilsDraft.from(_setup(_payload(mode: 'both', deptIds: [1]))).mode, CouncilsMode.both);
    });

    test('none: mode none, no departments, no faculty', () {
      final rows = _setup(_payload(openAgenda: 0)).departments;
      final d = const CouncilsDraft().answer(false);
      expect(d.problem(rows), isNull);
      final b = d.toBody();
      expect(b['mode'], 'none');
      expect(b['dept_ids'], isEmpty);
      expect(b['auto_new'], isFalse);
      expect(b.containsKey('faculty'), isFalse);
    });

    test('faculty: the chair is required; head_self or chair_user_id, secretary and members', () {
      final rows = _setup(_payload(openAgenda: 0)).departments;
      var d = const CouncilsDraft().answer(true);
      expect(d.problem(rows), 'Choose which councils');
      d = d.pick(CouncilsMode.faculty, rows);
      expect(d.problem(rows), chairRequiredText());
      expect(d.chairProblem, chairRequiredText());
      final self = d.copyWith(chairSelf: true);
      expect(self.problem(rows), isNull);
      expect(self.toBody()['faculty'], {'head_self': true, 'member_ids': <int>[]});
      expect(self.toBody()['dept_ids'], isEmpty);
      final picked = d.copyWith(
          chair: const GovUser(id: 30, name: 'Dean'), secretary: const GovUser(id: 32, name: 'Sec'), members: const [GovUser(id: 31, name: 'Prof')]);
      expect(picked.toBody()['faculty'], {'chair_user_id': 30, 'secretary_user_id': 32, 'member_ids': [31]});
      expect(picked.toBody()['mode'], 'faculty');
    });

    test('departments: first pick ticks all, select all / clear, auto_new', () {
      final rows = _setup(_payload(openAgenda: 0)).departments;
      var d = const CouncilsDraft().pick(CouncilsMode.departments, rows);
      expect(d.allSelected(rows), isTrue);
      d = d.selectAll(rows, false);
      expect(d.deptIds, isEmpty);
      expect(d.problem(rows), 'Pick at least one department');
      d = d.toggle(rows[2]).copyWith(autoNew: true);
      final b = d.toBody();
      expect(b['mode'], 'departments');
      expect(b['dept_ids'], [3]);
      expect(b['auto_new'], isTrue);
      expect(b.containsKey('faculty'), isFalse);
      expect(d.selectAll(rows, true).toBody()['dept_ids'], [1, 2, 3]);
    });

    test('both: faculty block and departments', () {
      final rows = _setup(_payload(openAgenda: 0)).departments;
      final d = const CouncilsDraft().pick(CouncilsMode.both, rows).copyWith(chairSelf: true);
      final b = d.toBody();
      expect(b['mode'], 'both');
      expect(b['dept_ids'], [1, 2, 3]);
      expect((b['faculty'] as Map)['head_self'], isTrue);
    });

    test('open agenda lock: a ticked department with open items cannot be unticked; leaving department councils is refused', () {
      final rows = _setup(_payload(mode: 'departments', derived: false, deptIds: [1, 2])).departments;
      var d = CouncilsDraft.from(_setup(_payload(mode: 'departments', derived: false, deptIds: [1, 2])));
      expect(d.toggle(rows[0]).deptIds, {1, 2}, reason: 'locked');
      expect(d.toggle(rows[1]).deptIds, {1});
      expect(d.selectAll(rows, false).deptIds, {1}, reason: 'clear keeps the locked one');
      d = d.answer(false);
      expect(d.lockedOut(rows).map((r) => r.id).toList(), [1]);
      expect(d.problem(rows), contains(orgCodeText('council_has_open_agenda')));
      expect(d.problem(rows), contains('Computer Science'));
      d = d.answer(true).pick(CouncilsMode.faculty, rows).copyWith(chairSelf: true);
      expect(d.lockedOut(rows), isNotEmpty, reason: 'faculty only drops the department councils too');
    });

    test('409 text names each council with its open items', () {
      final txt = councilsOpenAgendaText({
        'councils': [
          {'id': 11, 'name': 'CS council', 'open_agenda_items': 2},
          {'id': 12, 'name': 'IS council', 'open_agenda_items': 1},
        ],
      });
      expect(txt, contains('CS council (2 open items)'));
      expect(txt, contains('IS council (1 open item)'));
      expect(orgCodeText('head_required'), isNot('head_required'));
    });
  });

  group('view', () {
    Widget view(CouncilsDraft d, {CouncilsSetup? s, String? chairError}) => CouncilsChoiceView(
          setup: s ?? _setup(),
          draft: d,
          onChanged: (_) {},
          pickPerson: (_, _) async => null,
          meName: 'Dr. Mohamed Abdelrahman El-Sayed',
          chairError: chairError,
          onSave: () {},
          dirty: true,
        );

    testWidgets('layout: Q1 unanswered, No, faculty, departments with locks, both', (tester) async {
      final rows = _setup().departments;
      final faculty = const CouncilsDraft()
          .pick(CouncilsMode.faculty, rows)
          .copyWith(chair: const GovUser(id: 30, name: 'Prof. Dr. Ahmed Mahmoud Abdelaziz El-Sharkawy'), members: const [
        GovUser(id: 31, name: 'Prof. Dr. Samira Abdelrahman'),
        GovUser(id: 32, name: 'Dr. Karim'),
      ]);
      for (final d in [
        const CouncilsDraft(),
        const CouncilsDraft().answer(false),
        const CouncilsDraft().answer(true),
        faculty,
        const CouncilsDraft().pick(CouncilsMode.faculty, rows),
        const CouncilsDraft().pick(CouncilsMode.departments, rows),
        const CouncilsDraft().pick(CouncilsMode.both, rows).copyWith(chairSelf: true),
      ]) {
        await expectNoLayoutErrors(tester, () => view(d, chairError: d.chairProblem));
      }
      // no academic departments yet; a mode that drops a council with open items
      await expectNoLayoutErrors(tester,
          () => view(const CouncilsDraft().pick(CouncilsMode.departments, const []), s: CouncilsSetup.fromJson({..._payload(), 'departments': []})));
      await expectNoLayoutErrors(
          tester, () => view(CouncilsDraft.from(_setup(_payload(mode: 'departments', derived: false, deptIds: [1]))).answer(false)));
    });

    testWidgets('a locked department shows the reason and ignores taps', (tester) async {
      final s = _setup(_payload(mode: 'departments', derived: false, deptIds: [1, 2]));
      CouncilsDraft? changed;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(CouncilsChoiceView(setup: s, draft: CouncilsDraft.from(s), onChanged: (d) => changed = d)));
      await _settle(tester, 2);
      expect(find.byKey(const ValueKey('councils.dept.1.locked')), findsOneWidget);
      expect(find.text('3 open items'), findsOneWidget);
      expect(find.text('No head yet'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('councils.dept.1')));
      expect(changed, isNull);
      await _tap(tester, find.byKey(const ValueKey('councils.dept.2')));
      expect(changed!.deptIds, {1});
    });
  });

  group('page', () {
    late FakeApi api;
    setUp(() async {
      AppConfig.disableList = [];
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      await StorageService.getInstance();
    });
    tearDown(() => api.uninstall());

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    Future<void> open(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(const OrgCouncilsSetupPage()));
      await _settle(tester, 6);
    }

    testWidgets('No → PUT mode none; success notice', (tester) async {
      Map<String, dynamic>? sent;
      api = FakeApi({
        'GET $_base': (_) => _payload(openAgenda: 0),
        'PUT $_base': (o) {
          sent = _body(o);
          return _payload(derived: false, openAgenda: 0);
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      await open(tester);
      await _tap(tester, find.byKey(const ValueKey('councils.want.no')));
      expect(find.byKey(const ValueKey('councils.later')), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('org.page.save_councils_setup')));
      await _settle(tester, 4);
      expect(sent, {'mode': 'none', 'dept_ids': <int>[], 'auto_new': false});
      expect(find.text('Councils setup saved'), findsOneWidget);
      await close(tester);
    });

    testWidgets('faculty without a chair is stopped locally; 422 head_required marks the chair', (tester) async {
      var puts = 0;
      api = FakeApi({
        'GET $_base': (_) => _payload(openAgenda: 0),
        'PUT $_base': (o) {
          puts++;
          return const FakeResponse(422, {'detail': {'code': 'head_required', 'message': 'head required'}});
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      await open(tester);
      await _tap(tester, find.byKey(const ValueKey('councils.want.yes')));
      await _tap(tester, find.byKey(const ValueKey('councils.mode.faculty')));
      await _tap(tester, find.byKey(const ValueKey('org.page.save_councils_setup')));
      expect(puts, 0);
      expect(find.text(chairRequiredText()), findsWidgets);
      await _tap(tester, find.byKey(const ValueKey('unit.head.me')));
      await _tap(tester, find.byKey(const ValueKey('org.page.save_councils_setup')));
      await _settle(tester, 4);
      expect(puts, 1);
      expect(find.text(chairRequiredText()), findsWidgets);
      await close(tester);
    });

    testWidgets('409 council_has_open_agenda: the notice lists the councils, nothing reloads', (tester) async {
      var gets = 0;
      Map<String, dynamic>? sent;
      api = FakeApi({
        'GET $_base': (_) {
          gets++;
          return _payload(openAgenda: 0);
        },
        'PUT $_base': (o) {
          sent = _body(o);
          return const FakeResponse(409, {
            'detail': {
              'code': 'council_has_open_agenda',
              'message': 'open agenda',
              'councils': [
                {'id': 11, 'name': 'CS council', 'open_agenda_items': 2},
              ],
            },
          });
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      await open(tester);
      await _tap(tester, find.byKey(const ValueKey('councils.want.yes')));
      await _tap(tester, find.byKey(const ValueKey('councils.mode.departments')));
      await _tap(tester, find.byKey(const ValueKey('councils.select_all'))); // all ticked → Clear
      await _tap(tester, find.byKey(const ValueKey('councils.dept.2')));
      await _tap(tester, find.byKey(const ValueKey('org.page.save_councils_setup')));
      await _settle(tester, 4);
      expect(sent?['dept_ids'], [2]);
      expect(find.textContaining('CS council (2 open items)'), findsOneWidget);
      expect(gets, 1);
      await close(tester);
    });
  });
}
