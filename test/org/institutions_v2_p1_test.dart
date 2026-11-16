// Institutions v2, phase 1 (docs/institutions/V2_PLAN.md, data rules D-980 – D-984): department `core` / `head`
// parse null-safe, the head-required check and "Assign me as head" (head_self), the new server codes' texts, the
// archive impact sheet (reassign required, blocked by open agenda items, core units never), the council's
// `secretary_acting` flag, and the new views lay out at 320×640 and 1400×900 in Arabic and English with text scale 1.3.
import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/org/governance/gov_api.dart';
import 'package:flutter_education_app/features/org/governance/gov_council_s2.dart';
import 'package:flutter_education_app/features/org/governance/gov_entities_page.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/org/org_unit_rules.dart';
import 'package:flutter_education_app/features/org/org_v3.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

MyAuthProvider? _auth;

Widget _host(Widget child) => MultiProvider(
      providers: [
        if (_auth != null) ChangeNotifierProvider<MyAuthProvider>.value(value: _auth!),
        ChangeNotifierProvider<OrgSession>(create: (_) => OrgSession()..currentId = 5),
      ],
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

ApiException _err(String code, [int status = 409]) =>
    ApiException(statusCode: status, message: 'server text', code: code, body: {'detail': {'code': code, 'message': 'server text'}});

const _depts = [
  {'id': 3, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student Affairs', 'is_active': true},
  {'id': 4, 'name_ar': 'الكنترول', 'name_en': 'Exams Control', 'is_active': true},
  {'id': 8, 'name_ar': 'إدارة قديمة', 'name_en': 'Old unit', 'is_active': false},
];

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('payloads', () {
    test('head {id, name, acting} parses; an old server without it is "no head"', () {
      final h = unitHeadOf({'head': {'id': 9, 'name': 'Mona', 'acting': true}})!;
      expect((h.id, h.name, h.acting), (9, 'Mona', true));
      expect(unitHeadOf({'head': {'id': 9, 'name': 'Mona'}})!.acting, isFalse);
      expect(unitHeadOf({'head': null}), isNull);
      expect(unitHeadOf({'name_en': 'Old'}), isNull);
      expect(unitHeadOf(null), isNull);
      // an academic department carries `manager`
      expect(unitHeadOf({'manager': {'id': 2, 'name': 'Omar', 'acting': true}})?.acting, isTrue);
    });

    test('core is true only when the server says so', () {
      expect(unitIsCore({'core': true}), isTrue);
      expect(unitIsCore({'core': false}), isFalse);
      expect(unitIsCore({}), isFalse);
      expect(unitIsCore(null), isFalse);
    });

    test('impact parses, missing keys are 0', () {
      final i = DeptImpact.fromJson({'courses': 2, 'open_items': 5, 'councils': 1, 'open_agenda_items': 0, 'members': 12, 'core': false});
      expect([i.courses, i.openItems, i.councils, i.openAgendaItems, i.members], [2, 5, 1, 0, 12]);
      expect(i.core, isFalse);
      final e = DeptImpact.fromJson({});
      expect([e.courses, e.openItems, e.councils, e.openAgendaItems, e.members], [0, 0, 0, 0, 0]);
    });

    test('roster secretary_acting', () {
      expect(CouncilRoster.fromJson({'council_id': 1, 'items': [], 'secretary_acting': true}).secretaryActing, isTrue);
      expect(CouncilRoster.fromJson({'council_id': 1, 'items': []}).secretaryActing, isFalse);
    });
  });

  group('rules', () {
    test('a head is required unless the caller takes it', () {
      expect(headProblem(), 'A head is required. Assign someone, or make yourself the head.');
      expect(headProblem(head: 4), isNull);
      expect(headProblem(self: true), isNull);
      AppConfig.lang = 'ar';
      expect(headProblem(), 'الرئيس مطلوب. عيّن شخصاً، أو اجعل نفسك الرئيس.');
    });

    test('archive: core and open agenda block; open items need a target', () {
      expect(archiveBlock(const DeptImpact(core: true)), orgCodeText('dept_core'));
      expect(archiveBlock(const DeptImpact(openAgendaItems: 2)), orgCodeText('council_has_open_agenda'));
      expect(archiveBlock(const DeptImpact(openItems: 3)), isNull);
      expect(archiveProblem(const DeptImpact(openItems: 3)), isNotNull);
      expect(archiveProblem(const DeptImpact(openItems: 3), reassignTo: 4), isNull);
      expect(archiveProblem(const DeptImpact(courses: 9)), isNull);
    });

    test('reassign targets: never itself, never an inactive one', () {
      final ids = reassignTargets([for (final d in _depts) Map<String, dynamic>.from(d)], 3).map((d) => d['id']).toList();
      expect(ids, [4]);
    });

    test('the new codes have texts in both languages', () {
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        for (final c in ['head_required', 'dept_core', 'council_has_open_agenda', 'dept_has_open_items', 'dept_has_content']) {
          final txt = orgErrorText(_err(c, c == 'head_required' ? 422 : 409));
          expect(txt, isNot('server text'), reason: '$c ($lang)');
          expect(txt, isNot(c), reason: '$c ($lang)');
        }
      }
      AppConfig.lang = 'en';
      expect(orgErrorText(_err('dept_core')), 'Core department: can be renamed, not removed');
    });
  });

  group('views', () {
    testWidgets('archive view: reassign required, then enabled; open agenda disables with the reason', (tester) async {
      int? picked;
      var archived = 0;
      Widget view(DeptImpact i, int? r) => _host(StatefulBuilder(
          builder: (ctx, set) => DeptArchiveView(
                name: 'Student Affairs',
                impact: i,
                targets: [for (final d in _depts.skip(1).take(1)) Map<String, dynamic>.from(d)],
                reassignTo: picked ?? r,
                onReassign: (v) => set(() => picked = v),
                onArchive: () => archived++,
              )));
      await tester.pumpWidget(view(const DeptImpact(openItems: 3, courses: 1), null));
      await _settle(tester, 2);
      VoidCallback? go() => tester.widget<AppPrimaryButton>(find.byKey(const ValueKey('dept.archive.go'))).onPressed;
      expect(find.byKey(const ValueKey('dept.archive.reassign')), findsOneWidget);
      expect(go(), isNull, reason: 'open requests need a department to move to');
      await _tap(tester, find.byKey(const ValueKey('dept.archive.reassign')));
      await _tap(tester, find.text('Exams Control').last);
      expect(picked, 4);
      expect(go(), isNotNull);
      await _tap(tester, find.byKey(const ValueKey('dept.archive.go')));
      expect(archived, 1);

      picked = null;
      await tester.pumpWidget(view(const DeptImpact(openItems: 3, openAgendaItems: 2), null));
      await _settle(tester, 2);
      expect(find.byKey(const ValueKey('dept.archive.blocked')), findsOneWidget);
      expect(find.byKey(const ValueKey('dept.archive.reassign')), findsNothing);
      expect(go(), isNull);

      await tester.pumpWidget(view(const DeptImpact(core: true), null));
      await _settle(tester, 2);
      expect(find.text(orgCodeText('dept_core')), findsOneWidget);
      expect(go(), isNull);
    });

    testWidgets('head line: Acting chip; core badge', (tester) async {
      await tester.pumpWidget(_host(const Column(children: [
        UnitHeadLine(head: UnitHead(id: 1, name: 'Mona', acting: true)),
        UnitHeadLine(head: null),
        CoreUnitBadge(long: true),
      ])));
      await _settle(tester, 2);
      expect(find.text('Head: Mona'), findsOneWidget);
      expect(find.byKey(const ValueKey('unit.head.acting')), findsOneWidget);
      expect(find.text('No head yet'), findsOneWidget);
      expect(find.text('Core department: can be renamed, not removed'), findsOneWidget);
    });

    testWidgets('layout: archive sheet, badges, chip, hints', (tester) async {
      final targets = [for (final d in _depts) Map<String, dynamic>.from(d)];
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DeptArchiveView(
                name: 'A service department with a long name that wraps on a phone',
                impact: const DeptImpact(courses: 12, openItems: 140, councils: 1, members: 2300),
                targets: targets,
                reassignTo: null,
                onReassign: (_) {},
                onArchive: () {},
                error: orgCodeText('dept_has_open_items')),
            DeptArchiveView(
                name: 'Blocked',
                impact: const DeptImpact(openAgendaItems: 3, councils: 1),
                targets: const [],
                reassignTo: null,
                onReassign: (_) {},
                onArchive: () {}),
            const UnitHeadLine(head: UnitHead(id: 1, name: 'Dr. Mohamed Abdelrahman El-Sayed Mahmoud', acting: true)),
            const UnitHeadLine(head: null, manager: true),
            const Wrap(children: [ActingChip(), CoreUnitBadge()]),
            const CoreUnitBadge(long: true),
            AssignMeChip(selected: false, onTap: () {}),
            AssignMeChip(selected: true, meName: 'Dr. Mohamed Abdelrahman El-Sayed', onTap: () {}),
            HeadErrorText(headRequiredText()),
            const CouncilSecretaryActingHint(),
            HeadlessUnitsBanner(count: 3, onFix: () {}),
          ]),
        ),
      );
    });

    testWidgets('council roster: the chair-acts hint only while no secretary is set', (tester) async {
      Map<String, dynamic> roster({bool acting = true, int? secretary}) => {
            'council_id': 1,
            'items': [
              {'user_id': 2, 'user': {'id': 2, 'name': 'Chair'}, 'weight': 1, 'is_chair': true},
            ],
            'secretary_user_id': secretary,
            'secretary_acting': acting,
            'can': {'roster': true},
          };
      await tester.pumpWidget(_host(SingleChildScrollView(child: CouncilRosterCard(roster: CouncilRoster.fromJson(roster()), onSave: (_, _) {}))));
      await _settle(tester, 2);
      expect(find.byKey(const ValueKey('council.secretary.acting')), findsOneWidget);
      await tester.pumpWidget(_host(SingleChildScrollView(
          child: CouncilRosterCard(roster: CouncilRoster.fromJson(roster(acting: false, secretary: 2)), onSave: (_, _) {}))));
      await _settle(tester, 2);
      expect(find.byKey(const ValueKey('council.secretary.acting')), findsNothing);
    });
  });

  group('flows', () {
    late FakeApi api;
    final sent = <String, Map<String, dynamic>>{};

    setUp(() async {
      AppConfig.disableList = [];
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      final storage = await StorageService.getInstance();
      await storage.saveUser({'id': 7, 'name': 'Boss', 'gmail': 'boss@example.test', 'role': 'org-admin'});
      _auth = MyAuthProvider(storage: storage)..loadCachedUser();
      sent.clear();
    });
    tearDown(() {
      api.uninstall();
      _auth = null;
    });

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('entity sheet: no head blocks Create; "Assign me as head" shows my name and sends head_self', (tester) async {
      api = FakeApi({
        'GET /api/v1/org/orgs/5/members': (_) => {'items': []},
        'POST /api/v1/org/orgs/5/governance/entities': (o) {
          sent['POST'] = _body(o);
          return {'id': 11};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(Builder(
          builder: (ctx) => TextButton(onPressed: () => showGovEntitySheet(ctx, GovApi(5)), child: const Text('open')))));
      await _tap(tester, find.text('open'));
      await tester.enterText(find.byType(TextField).first, 'شؤون الطلاب');
      await _tap(tester, find.text('Create'));
      expect(find.text(headRequiredText()), findsWidgets, reason: 'the head is required');
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);

      await _tap(tester, find.byKey(const ValueKey('unit.head.me')));
      expect(find.text('Head: Boss (you)'), findsOneWidget);
      await _tap(tester, find.text('Create'));
      await _settle(tester, 6);
      expect(sent['POST']?['head_self'], isTrue);
      expect(sent['POST']?.containsKey('head_user_id'), isFalse);
      await close(tester);
    });

    testWidgets('archive sheet: impact, required target, confirm, DELETE with reassign_to', (tester) async {
      String? deleted;
      api = FakeApi({
        'GET /api/v1/org/orgs/5/departments/3/impact': (_) =>
            {'courses': 2, 'open_items': 4, 'councils': 1, 'open_agenda_items': 0, 'members': 9, 'core': false},
        'GET /api/v1/org/orgs/5/departments': (_) => {'items': _depts},
        'DELETE /api/v1/org/orgs/5/departments/3': (o) {
          deleted = o.uri.query;
          return {'ok': true};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.reset);
      bool? result;
      await tester.pumpWidget(_host(Builder(
          builder: (ctx) => TextButton(
              onPressed: () async => result = await showArchiveDepartmentSheet(ctx, {'id': 3, 'name_en': 'Student Affairs'}),
              child: const Text('open')))));
      await _tap(tester, find.text('open'));
      await _settle(tester, 6);
      expect(find.text('Move open requests to *'), findsOneWidget);
      expect(tester.widget<AppPrimaryButton>(find.byKey(const ValueKey('dept.archive.go'))).onPressed, isNull);
      await _tap(tester, find.byKey(const ValueKey('dept.archive.reassign')));
      await _tap(tester, find.text('Exams Control').last);
      await _tap(tester, find.byKey(const ValueKey('dept.archive.go')));
      // appConfirm
      await _tap(tester, find.text('Archive').last);
      await _settle(tester, 6);
      expect(deleted, 'reassign_to=4');
      expect(result, isTrue);
      await close(tester);
    });

    testWidgets('archive refused by the server: the code text stays on the sheet', (tester) async {
      api = FakeApi({
        'GET /api/v1/org/orgs/5/departments/3/impact': (_) => {'courses': 0, 'open_items': 0, 'members': 1},
        'DELETE /api/v1/org/orgs/5/departments/3': (_) =>
            const FakeResponse(409, {'detail': {'code': 'dept_has_content', 'message': 'has content'}}),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(Builder(
          builder: (ctx) => TextButton(onPressed: () => showArchiveDepartmentSheet(ctx, {'id': 3, 'name_en': 'X'}), child: const Text('open')))));
      await _tap(tester, find.text('open'));
      await _settle(tester, 6);
      await _tap(tester, find.byKey(const ValueKey('dept.archive.go')));
      await _tap(tester, find.text('Archive').last);
      await _settle(tester, 6);
      expect(find.text(orgCodeText('dept_has_content')), findsOneWidget);
      await close(tester);
    });
  });
}
