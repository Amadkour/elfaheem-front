// Institutions v2, phase 4 (docs/institutions/V2_PLAN.md item 4, D-991 – D-993): the guided setup wizard. The
// payloads parse defensively; the wizard resumes at the server's step, each Next saves the step then PUTs
// {step, done}; the heads step's "Make me head of all empty units" sends "me"; the review groups Block / Warn, jumps
// to a step and only launches with nothing blocking; the Home swaps the old checklist for the wizard card; every
// step lays out at 320×640 and 1400×900 in Arabic and English with text scale 1.3.
import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/home/org_setup_checklist.dart';
import 'package:flutter_education_app/features/org/org_institution_wizard.dart';
import 'package:flutter_education_app/features/org/org_institutions.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/org/org_v3.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _org = '/api/v1/org/orgs/5';
const _inst = '$_org/institution';

Map<String, dynamic> _wizard({
  String step = 'basics',
  List<String> done = const [],
  String? launchedAt,
  bool applicable = true,
  Map<String, dynamic>? readiness,
}) =>
    {
      'step': step,
      'done': done,
      'steps': ['basics', 'departments', 'heads', 'councils', 'optional', 'review'],
      'launched_at': launchedAt,
      'applicable': applicable,
      'readiness': readiness ?? {'ok': true, 'blocking': 0, 'items': []},
    };

Map<String, dynamic> _blocked() => {
      'ok': false,
      'blocking': 1,
      'items': [
        {'key': 'heads_missing', 'severity': 'block', 'count': 2, 'text_ar': 'وحدتان بلا رئيس', 'text_en': '2 units have no head', 'action': 'heads', 'ids': [1, 3]},
        {
          'key': 'core_missing',
          'severity': 'warn',
          'count': 1,
          'text_ar': 'إدارة أساسية ناقصة',
          'text_en': 'A core department is missing',
          'action': 'departments',
          'keys': ['student_affairs'],
          'fix': {
            'templates': [
              {'key': 'student_affairs'},
            ],
          },
        },
        {'key': 'no_members', 'severity': 'warn', 'count': 0, 'text_en': 'Nobody invited yet', 'action': 'optional'},
      ],
    };

Map<String, dynamic> _heads({Map<int, Map<String, dynamic>?> heads = const {}}) => {
      'units': [
        {'id': 1, 'name': 'Computer Science', 'name_ar': 'علوم الحاسب', 'name_en': 'Computer Science', 'kind': 'scientific', 'core': false, 'head': heads[1]},
        {
          'id': 2,
          'name_ar': 'شئون الطلاب',
          'name_en': 'Student Affairs',
          'kind': 'service',
          'core': true,
          'template_key': 'student_affairs',
          'head': heads[2] ?? {'id': 9, 'name': 'Dr. Manager', 'acting': true},
        },
        {
          'id': 3,
          'name': 'A department with a very long name that has to wrap on a small phone screen',
          'kind': 'custom_kind',
          'core': false,
          'head': heads[3],
        },
      ],
    };

Map<String, dynamic> _study() => {
      'study_system': null,
      'effective': 'credit_hours',
      'source': 'default',
      'has_graduate_programs': false,
      'programs': {'credit_hours': 0, 'traditional': 0, 'own_system': 0},
    };

Map<String, dynamic> _tpl(String key, {String group = 'service', bool core = false, bool recommended = false, int? deptId}) => {
      'key': key,
      'group': group,
      'kind': group == 'academic' ? 'scientific' : 'service',
      'name_ar': 'قالب $key',
      'name_en': 'Template $key',
      'description_en': 'What $key does, in one line that is long enough to wrap on a phone.',
      'core': core,
      'recommended': recommended,
      'min_set': core,
      'dept_id': deptId,
      'request_types': [
        {'key': '${key}_r1', 'name_ar': 'طلب', 'name_en': 'A request', 'kind': 'request', 'applied': false},
      ],
    };

Map<String, dynamic> _catalog() => {
      'study_system': 'credit_hours',
      'academic_departments': 0,
      'can_apply': true,
      'items': [
        _tpl('academic_department', group: 'academic'),
        _tpl('student_affairs', core: true),
        _tpl('exam_control', core: true),
        _tpl('library', recommended: true),
        _tpl('it'),
      ],
    };

Map<String, dynamic> _councils() => {
      'mode': 'none',
      'dept_ids': [],
      'auto_new': false,
      'derived': true,
      'faculty': null,
      'departments': [
        {'id': 1, 'name': 'Computer Science', 'head': null, 'has_council': false, 'council_id': null, 'open_agenda_items': 0, 'selected': false},
      ],
    };

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
  await _settle(tester, 6);
}

bool _enabled(WidgetTester tester, Key key) => tester.widget<AppButton>(find.byKey(key)).onPressed != null;

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('pure', () {
    test('wizard state: resume step, done keys, card rule, PUT body order', () {
      final w = InstitutionWizardState.fromJson(_wizard(step: 'heads', done: ['departments', 'basics', 'nonsense']));
      expect(w.stepIndex, 2);
      expect(w.done, {'basics', 'departments'});
      expect(w.doneCount, 2);
      expect(w.showCard, isTrue);
      expect(InstitutionWizardState.fromJson(_wizard(step: 'later')).stepIndex, 0);
      expect(InstitutionWizardState.fromJson(_wizard(launchedAt: '2026-11-15T10:00:00')).showCard, isFalse);
      expect(InstitutionWizardState.fromJson(_wizard(applicable: false)).showCard, isFalse);
      expect(InstitutionWizardState.fromJson(const {}).showCard, isFalse);
      expect(wizardPutBody('councils', {'heads', 'basics', 'departments'}), {
        'step': 'councils',
        'done': ['basics', 'departments', 'heads'],
      });
    });

    test('readiness: Block / Warn groups, launch rule, the 409 items, the quick fix', () {
      final r = InstitutionReadiness.fromJson(_blocked());
      expect(r.blockItems.map((x) => x.key).toList(), ['heads_missing']);
      expect(r.warnItems.map((x) => x.key).toList(), ['core_missing', 'no_members']);
      expect(r.canLaunch, isFalse);
      expect(r.blockItems.first.ids, [1, 3]);
      expect(r.warnItems.first.fix, isNotNull);
      expect(r.warnItems.last.fix, isNull);
      expect(wizardStepOfAction(r.blockItems.first.action), 2);
      expect(wizardStepOfAction('optional'), 4);
      expect(wizardStepOfAction('???'), 0);
      expect(InstitutionReadiness.fromJson(const {'ok': true, 'blocking': 0, 'items': []}).canLaunch, isTrue);
      final from409 = InstitutionReadiness.fromItems([
        {'key': 'x', 'severity': 'block', 'text_en': 'X'},
      ]);
      expect(from409.blocking, 1);
      expect(from409.canLaunch, isFalse);
    });

    test('heads: {units}, scientific = academic, bilingual names, "me" for every empty unit', () {
      final rows = headUnitsOf(_heads());
      expect(rows.length, 3);
      expect(rows[0].academic, isTrue);
      expect(rows[1].academic, isFalse);
      expect(rows[2].academic, isFalse, reason: 'a custom kind is a service unit');
      expect(rows[1].name, 'Student Affairs');
      expect(rows[1].core, isTrue);
      expect(rows[1].acting, isTrue);
      expect(headUnitsOf([_heads()['units'][0]]).length, 1, reason: 'a bare list too');
      var d = const HeadsDraft().set(1, const HeadChoice.person(GovUser(id: 40, name: 'Dr. Mona')));
      expect(d.emptyLeft(rows), 1);
      d = d.meForAllEmpty(rows);
      expect(d.toBody(), {
        'heads': {'1': 40, '3': 'me'},
      });
      expect(d.emptyLeft(rows), 0);
      expect(d.actingLeft(rows), 1);
      expect(d.set(3, null).toBody(), {
        'heads': {'1': 40},
      });
      expect(headInvalidIds(const {'dept_ids': [3, '1']}), {3, 1});
      expect(orgCodeText('head_invalid'), isNot('head_invalid'));
      expect(orgCodeText('not_ready'), isNot('not_ready'));
      expect(orgCodeText('dept_invalid'), isNot('dept_invalid'));
    });

    test('catalog: a core template is pre-ticked and cannot be unticked', () {
      final c = DeptCatalog.fromJson(_catalog());
      final core = c.byKey('student_affairs')!;
      expect(core.coreLocked, isTrue);
      final s = CatalogSelection.initial(c);
      expect(s.isPicked('student_affairs'), isTrue);
      expect(s.isPicked('exam_control'), isTrue);
      expect(s.isPicked('it'), isFalse);
      s.toggle(core);
      expect(s.isPicked('student_affairs'), isTrue);
      s.toggle(c.byKey('library')!);
      expect(s.isPicked('library'), isFalse);
      final made = DeptCatalog.fromJson({
        ..._catalog(),
        'items': [_tpl('student_affairs', core: true, deptId: 4)],
      });
      expect(made.items.first.coreLocked, isFalse, reason: 'created already');
    });

    test('setup payload: the wizard flags decide the card swap', () {
      final base = {
        'dismissed': false,
        'steps': [
          {'key': 'profile', 'done': false},
        ],
      };
      expect(OrgSetupData.fromJson(base).wizardCard, isFalse);
      expect(OrgSetupData.fromJson({...base, 'wizard': {'applicable': true, 'launched': false}}).wizardCard, isTrue);
      expect(OrgSetupData.fromJson({...base, 'dismissed': true, 'wizard': {'applicable': true, 'launched': true}}).wizardCard, isFalse);
      expect(OrgSetupData.fromJson({...base, 'wizard': {'applicable': true, 'launched': false}}).dismissedCopy().wizardCard, isTrue);
    });
  });

  group('page', () {
    late FakeApi api;
    setUp(() async {
      AppConfig.disableList = [];
      AppConfig.orgsEnabled = true;
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      await StorageService.getInstance();
      OrgSetupPrefetch.reset();
    });
    tearDown(() => api.uninstall());

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    Future<void> open(WidgetTester tester, Widget child) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 1300);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(child));
      await _settle(tester, 8);
    }

    testWidgets('basics: Next saves the study system, then PUTs {step, done}; the catalog shows core locked', (tester) async {
      final puts = <String, Map<String, dynamic>>{};
      api = FakeApi({
        'GET $_inst/wizard': (_) => _wizard(),
        'PUT $_inst/wizard': (o) => puts['wizard'] = _body(o),
        'GET $_org/study-system': (_) => _study(),
        'PUT $_org/study-system': (o) {
          puts['study'] = _body(o);
          return {..._study(), 'study_system': 'credit_hours', 'source': 'org'};
        },
        'GET $_org/dept-catalog': (_) => _catalog(),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      await open(tester, const OrgInstitutionWizard());
      expect(find.byKey(const ValueKey('wizard.strip.compact')), findsOneWidget);
      expect(find.text('Step 1 of 6'), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard.back')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('wizard.next')));
      expect(puts['study'], {'study_system': 'credit_hours', 'has_graduate_programs': false});
      expect(puts['wizard'], {
        'step': 'departments',
        'done': ['basics'],
      });
      expect(find.text('Step 2 of 6'), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard.dept.intro')), findsOneWidget);
      expect(find.byKey(const ValueKey('catalog.core.student_affairs')), findsOneWidget);
      expect(find.byKey(const ValueKey('org.page.create_selected')), findsNothing, reason: 'Next creates them');
      expect(find.text('Create 3 and continue'), findsOneWidget);
      await close(tester);
    });

    testWidgets('resumes at the server step; "Make me head of all empty units" → PUT heads "me", then the wizard', (tester) async {
      Map<String, dynamic>? heads, wizard;
      api = FakeApi({
        'GET $_inst/wizard': (_) => _wizard(step: 'heads', done: ['basics', 'departments']),
        'PUT $_inst/wizard': (o) => wizard = _body(o),
        'GET $_inst/heads': (_) => _heads(),
        'PUT $_inst/heads': (o) {
          heads = _body(o);
          return _heads(heads: {
            1: {'id': 77, 'name': 'Me', 'acting': false},
            3: {'id': 77, 'name': 'Me', 'acting': false},
          });
        },
        'GET $_org/governance/councils-setup': (_) => _councils(),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      await open(tester, const OrgInstitutionWizard());
      expect(find.text('Step 3 of 6'), findsOneWidget);
      expect(find.text('Who heads each unit?'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget, reason: 'the acting head is flagged');
      await _tap(tester, find.byKey(const ValueKey('heads.all_me')));
      expect(find.byKey(const ValueKey('heads.choice.1')), findsOneWidget);
      expect(find.byKey(const ValueKey('heads.choice.3')), findsOneWidget);
      expect(find.byKey(const ValueKey('heads.choice.2')), findsNothing, reason: 'an acting head is not "empty"');
      await _tap(tester, find.byKey(const ValueKey('wizard.next')));
      expect(heads, {
        'heads': {'1': 'me', '3': 'me'},
      });
      expect(wizard, {
        'step': 'councils',
        'done': ['basics', 'departments', 'heads'],
      });
      expect(find.text('Do you want councils?'), findsOneWidget);
      // Back returns without saving
      await _tap(tester, find.byKey(const ValueKey('wizard.back')));
      expect(find.text('Who heads each unit?'), findsOneWidget);
      await close(tester);
    });

    testWidgets('422 head_invalid: stays on the step and marks the unit', (tester) async {
      var wizardPuts = 0;
      api = FakeApi({
        'GET $_inst/wizard': (_) => _wizard(step: 'heads'),
        'PUT $_inst/wizard': (_) {
          wizardPuts++;
          return {};
        },
        'GET $_inst/heads': (_) => _heads(),
        'PUT $_inst/heads': (_) => const FakeResponse(422, {
              'detail': {
                'code': 'head_invalid',
                'message': 'bad',
                'dept_ids': [3],
              },
            }),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      await open(tester, const OrgInstitutionWizard());
      await _tap(tester, find.byKey(const ValueKey('heads.all_me')));
      await _tap(tester, find.byKey(const ValueKey('wizard.next')));
      expect(wizardPuts, 0);
      expect(find.text('Who heads each unit?'), findsOneWidget);
      expect(find.text('This head could not be assigned: pick another member'), findsOneWidget);
      expect(find.text(orgCodeText('head_invalid')), findsOneWidget);
      await close(tester);
    });

    testWidgets('review: Block / Warn groups, Launch disabled while blocked, Fix jumps to the step', (tester) async {
      api = FakeApi({
        'GET $_inst/wizard': (_) => _wizard(step: 'review', done: ['basics', 'departments', 'heads', 'councils', 'optional'], readiness: _blocked()),
        'GET $_inst/heads': (_) => _heads(),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      await open(tester, const OrgInstitutionWizard());
      expect(find.text('Needed before launch'), findsOneWidget);
      expect(find.text('Worth a look'), findsOneWidget);
      expect(find.byKey(const ValueKey('review.quick_fix')), findsOneWidget);
      expect(_enabled(tester, const ValueKey('wizard.next')), isFalse);
      await _tap(tester, find.descendant(of: find.byKey(const ValueKey('review.item.heads_missing')), matching: find.byKey(const ValueKey('review.fix'))));
      expect(find.text('Step 3 of 6'), findsOneWidget);
      expect(find.text('Who heads each unit?'), findsOneWidget);
      await close(tester);
    });

    testWidgets('launch: confirm → POST launch → the success state', (tester) async {
      var launches = 0;
      api = FakeApi({
        'GET $_inst/wizard': (_) => _wizard(step: 'review', done: ['basics', 'departments', 'heads', 'councils', 'optional']),
        'POST $_inst/launch': (_) {
          launches++;
          return {'launched_at': '2026-11-15T10:00:00'};
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      await open(tester, const OrgInstitutionWizard());
      expect(find.byKey(const ValueKey('review.ready')), findsOneWidget);
      expect(_enabled(tester, const ValueKey('wizard.next')), isTrue);
      await _tap(tester, find.byKey(const ValueKey('wizard.next')));
      await _tap(tester, find.text('Launch'));
      expect(launches, 1);
      expect(find.byKey(const ValueKey('wizard.launched')), findsOneWidget);
      expect(find.text('Your institution is live'), findsOneWidget);
      await close(tester);
    });

    testWidgets('launch: 409 not_ready shows the items and keeps Launch disabled', (tester) async {
      api = FakeApi({
        'GET $_inst/wizard': (_) => _wizard(step: 'review'),
        'POST $_inst/launch': (_) => FakeResponse(409, {
              'detail': {'code': 'not_ready', 'message': 'not ready', 'items': _blocked()['items']},
            }),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      await open(tester, const OrgInstitutionWizard());
      await _tap(tester, find.byKey(const ValueKey('wizard.next')));
      await _tap(tester, find.text('Launch'));
      expect(find.byKey(const ValueKey('review.item.heads_missing')), findsOneWidget);
      expect(find.text(orgCodeText('not_ready')), findsOneWidget);
      expect(_enabled(tester, const ValueKey('wizard.next')), isFalse);
      await close(tester);
    });

    Map<String, dynamic> setup(Map<String, dynamic>? wizard) => {
          'dismissed': false,
          'steps': [
            {'key': 'profile', 'done': false},
            {'key': 'departments', 'done': true, 'count': 3},
          ],
          'wizard': ?wizard,
        };

    testWidgets('home: an applicable, unlaunched institution gets the wizard card instead of the checklist', (tester) async {
      var opened = 0;
      api = FakeApi({
        'GET $_org/setup': (_) => setup({'applicable': true, 'launched': false}),
        'GET $_inst/wizard': (_) => _wizard(step: 'heads', done: ['basics', 'departments']),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      await open(
          tester,
          SingleChildScrollView(
              child: OrgSetupChecklist(orgId: 5, onOpen: (_) {}, onOpenWizard: () async => opened++)));
      expect(find.byKey(const ValueKey('inst.wizard.card')), findsOneWidget);
      expect(find.text('2 of 6 steps done · Next: Heads'), findsOneWidget);
      expect(find.byKey(const ValueKey('setup.step.profile')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('inst.wizard.continue')));
      expect(opened, 1);
      await close(tester);
    });

    testWidgets('home: a non-applicable organization keeps the old checklist and never asks for the wizard', (tester) async {
      for (final w in [null, {'applicable': false, 'launched': false}]) {
        OrgSetupPrefetch.reset();
        api = FakeApi({
          'GET $_org/setup': (_) => setup(w),
          'GET $_inst/wizard': (_) => _wizard(),
        }, latency: const Duration(milliseconds: 20))
          ..install();
        await open(tester, SingleChildScrollView(child: OrgSetupChecklist(orgId: 5, onOpen: (_) {}, onOpenWizard: () async {})));
        expect(find.byKey(const ValueKey('inst.wizard.card')), findsNothing);
        expect(find.byKey(const ValueKey('setup.step.profile')), findsOneWidget);
        expect(api.calls.where((c) => c.path.contains('/institution/')), isEmpty);
        await close(tester);
        api.uninstall();
      }
      api = FakeApi({})..install(); // for tearDown
    });
  });

  group('layout', () {
    final rows = headUnitsOf(_heads());
    final draft = const HeadsDraft().set(1, const HeadChoice.person(GovUser(id: 40, name: 'Prof. Dr. Samira Abdelrahman El-Sharkawy')));

    Widget framed(Widget body, {int step = 2}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: WizardStepStrip(current: step, done: const {'basics', 'departments'}, reached: step, onTap: (_) {}),
          ),
          Expanded(child: body),
          WizardNavBar(nextLabel: 'Save and continue', onNext: () {}, onBack: step == 0 ? null : () {}),
        ]);

    testWidgets('steps 1 – 2: study system and the catalog (core locked, intro)', (tester) async {
      final info = StudySystemInfo.fromJson(_study());
      await expectNoLayoutErrors(
          tester,
          () => framed(
              StudySystemView(info: info, selected: StudySystem.creditHours, graduate: false, onPick: (_) {}, onGraduate: (_) {}, onSave: () {}),
              step: 0));
      final c = DeptCatalog.fromJson(_catalog());
      final ar = TextEditingController(), en = TextEditingController();
      addTearDown(ar.dispose);
      addTearDown(en.dispose);
      await expectNoLayoutErrors(
          tester,
          () => framed(
              DeptCatalogView(
                catalog: c,
                selection: CatalogSelection.initial(c),
                academic: false,
                embedded: true,
                intro: const DeptKindsIntro(),
                nameAr: ar,
                nameEn: en,
                onGroup: (_) {},
                onToggle: (_) {},
                onToggleType: (_, _) {},
                onCreate: () {},
                onCustom: () {},
              ),
              step: 1));
    });

    testWidgets('step 3: heads (empty, acting, picked, me, error, none)', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => framed(HeadsStepView(
              rows: rows,
              draft: draft.set(2, const HeadChoice.me()),
              onChanged: (_) {},
              onPick: (_) async => null,
              meName: 'Dr. Mohamed Abdelrahman El-Sayed',
              errors: const {3})));
      await expectNoLayoutErrors(tester, () => framed(HeadsStepView(rows: rows, draft: const HeadsDraft(), onChanged: (_) {}, onPick: (_) async => null)));
      await expectNoLayoutErrors(tester, () => framed(HeadsStepView(rows: const [], draft: const HeadsDraft(), onChanged: (_) {})));
    });

    testWidgets('steps 5 – 6: optional, review (blocked, ready), launched', (tester) async {
      await expectNoLayoutErrors(tester, () => framed(OptionalStepView(onOpen: (_) {}), step: 4));
      await expectNoLayoutErrors(
          tester, () => framed(ReviewStepView(readiness: InstitutionReadiness.fromJson(_blocked()), onJump: (_) {}, onQuickFix: (_) {}), step: 5));
      await expectNoLayoutErrors(
          tester,
          () => framed(
              ReviewStepView(
                  readiness: const InstitutionReadiness(ok: true, items: [ReadinessItem(key: 'w', textEn: 'Nobody invited yet', action: 'optional')]),
                  onJump: (_) {}),
              step: 5));
      await expectNoLayoutErrors(tester, () => LaunchedView(onDone: () {}));
    });

    testWidgets('the Home card', (tester) async {
      for (final w in [_wizard(), _wizard(step: 'councils', done: ['basics', 'departments', 'heads'])]) {
        await expectNoLayoutErrors(
            tester,
            () => SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpace.md),
                child: InstitutionSetupCard(state: InstitutionWizardState.fromJson(w), onContinue: () {})));
      }
    });
  });
}
