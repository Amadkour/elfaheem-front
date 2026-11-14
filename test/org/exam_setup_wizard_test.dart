// The teacher's "Paper exam setup" wizard over the fake backend (D-150, D-151):
//   • Example 1: choose National ID → "2 ready, 1 missing", the duplicates card, ask the missing student; the list
//     follows the core's `exam_identifiers` event live (no timer needed) down to "0 missing".
//   • Example 2: Online is stored and the wizard closes (the exam editor holds the online settings).
//   • Exam paper only skips the bubble-sheet step (no template call) and finishing sends nothing it did not change.
// Setup / identifiers / templates replies are the recorded ones (test/org/fixtures/omr_setup_payloads.json); the exam
// itself follows exam_engine/services/exams.py `to_dict(with_sections=True, reveal_answers=True)` with the questions
// the engine test created.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup_wizard.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _p(String name) =>
    ((jsonDecode(File('test/org/fixtures/omr_setup_payloads.json').readAsStringSync()) as Map)['payloads'] as Map)[name] as Map<String, dynamic>;

Map<String, dynamic> _q(int id, String type, Map<String, dynamic> body, Object correct) =>
    {'id': id, 'type': type, 'body': body, 'answer': {'correct': correct}, 'points': 2.0, 'placement_id': id, 'version': 1};

final _exam = {
  'id': 1,
  'org_id': 1,
  'course_id': 100,
  'title': 'Paper midterm',
  'status': 'draft',
  'starts_at': '2026-12-01T08:00:00',
  'ends_at': '2026-12-01T10:00:00',
  'sections': [
    {
      'id': 1,
      'title': 'Paper',
      'mode': 'paper',
      'questions': [
        _q(1, 'mcq_single', {'prompt': 'Q0', 'options': ['a', 'b', 'c', 'd']}, 'b'),
        _q(2, 'mcq_single', {'prompt': 'Q1', 'options': ['a', 'b', 'c', 'd']}, 'b'),
        _q(3, 'true_false', {'prompt': 'The sun is a star'}, true),
      ],
    },
  ],
};

final _connected = ValueNotifier<bool>(true);
final _stream = LiveStreamHandle(connected: _connected, bind: () {}, release: () {});

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Backend {
  _Backend(Map<String, dynamic> setup) : setup = Map.of(setup);
  Map<String, dynamic> setup;
  final puts = <Map<String, dynamic>>[];
  var report = _p('identifiers');
  var orgTemplatesForbidden = false;   // the member has no exams right in the organization: 403 when org_id is sent

  FakeApi fake() => FakeApi({
        'GET /api/v1/exam/exams/1/setup': (_) => setup,
        'GET /api/v1/exam/exams/1': (_) => _exam,
        'GET /api/v1/identity-fields': (_) => _p('fields_all'),
        'GET /api/v1/data-lab/courses/100/grid': (_) => const {'columns': [], 'rows': []},
        'PUT /api/v1/exam/exams/1/setup': (o) {
          final body = Map<String, dynamic>.from(o.data as Map);
          puts.add(body);
          setup = {...setup, ...body};
          if (body['delivery'] == 'online') setup = {...setup, 'paper_format': null, 'omr_template_id': null, 'form_markers': []};
          return setup;
        },
        'GET /api/v1/exam/exams/1/identifiers': (_) => report,
        'POST /api/v1/exam/exams/1/identifiers/request': (_) => _p('request'),
        'GET /api/v1/exam/exams/1/forms': (_) => const {'items': [], 'form_markers': [], 'warnings': []},
        'PUT /api/v1/exam/exams/1/forms': (o) {
          final forms = ((o.data as Map)['forms'] as List).cast<Map>();
          setup = {...setup, 'forms': forms.length};
          return {
            'items': [for (final f in forms) {'id': 1, 'code': f['code'], 'label': f['label'], 'key': f['key'], 'created_at': '2026-11-02T02:07:02'}],
            'form_markers': const [],
            'warnings': const [],
          };
        },
        // the server adds the organization's published answer tables only when asked with `org_id` (D-241)
        'GET /api/v1/exam/omr/templates': (o) {
          final base = _p('templates');
          if ('${o.queryParameters['org_id']}' != '1') return base;
          if (orgTemplatesForbidden) return const FakeResponse(403, {'detail': {'code': 'org_forbidden', 'message': 'x', 'message_en': 'x'}});
          return {
            ...base,
            'items': [
              ...(base['items'] as List),
              {'id': 77, 'family_id': 'f77', 'version': 1, 'name': 'Midterm answer table', 'description': null, 'status': 'published', 'kind': 'answer_table', 'org_id': 1, 'questions': 25, 'options': 4},
            ],
          };
        },
      }, latency: const Duration(milliseconds: 20));
}

bool? result;

Future<FakeApi> _open(WidgetTester tester, _Backend b, {String? initialDelivery}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  final fake = b.fake()..install();
  addTearDown(fake.uninstall);
  await tester.pumpWidget(layoutHost(
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async => result = await Navigator.of(context).push<bool>(MaterialPageRoute(
                builder: (_) => ExamSetupWizard(examId: 1, initialDelivery: initialDelivery, liveStream: _stream, liveBus: LiveEvents.instance))),
            child: const Text('open'),
          ),
        ),
      ),
      scale: 1));
  await tester.tap(find.text('open'));
  await _frames(tester, 10);
  return fake;
}

Future<void> _tapPrimary(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('setup.primary')));
  await _frames(tester);
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUp(() {
    result = null;
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  testWidgets('Example 1: the audience check, the request, and the live count going to 0 missing', (tester) async {
    final b = _Backend(_p('setup_get_new'));
    final fake = await _open(tester, b);
    expect(find.text('How do we identify each student in this exam?'), findsOneWidget);
    expect(find.text('Step 1 of 5 · Students'), findsOneWidget);
    expect(find.byKey(const ValueKey('setup.id.custom:passport_no')), findsOneWidget, reason: 'the platform\'s custom fields are offered');

    await tester.tap(find.byKey(const ValueKey('setup.id.national_id')));
    await _frames(tester);
    expect(b.puts.single, {'identifier': {'source': 'national_id', 'key': null}});
    expect(find.text('2 ready, 1 missing'), findsOneWidget);
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('2 students share the same National ID'), findsOneWidget);
    expect(find.text('Due: exam day, 1 Dec 2026'), findsNothing, reason: 'a new exam reads online: no exam-day due date');

    await tester.ensureVisible(find.byKey(const ValueKey('setup.request')));
    await _frames(tester, 2);
    await tester.tap(find.byKey(const ValueKey('setup.request')));
    await _frames(tester);
    expect(fake.calls.where((c) => c.key == 'POST /api/v1/exam/exams/1/identifiers/request'), hasLength(1));
    expect(find.text('Request sent to 1 student'), findsOneWidget);

    // the student answers: the core's live event, then the report says 0 missing
    b.report = {..._p('identifiers'), 'ready': 3, 'missing': [], 'duplicates': [], 'requests': {'pending': 0, 'done': 1, 'cancelled': 0}};
    final before = fake.calls.where((c) => c.path.endsWith('/identifiers')).length;
    LiveEvents.instance.emit(kExamIdentifiersEvent, {'exam_ref': 'exam:2', 'missing': 0}); // another exam: ignored
    await _frames(tester, 2);
    expect(fake.calls.where((c) => c.path.endsWith('/identifiers')).length, before);
    LiveEvents.instance.emit(kExamIdentifiersEvent, {'exam_ref': 'exam:1', 'missing': 0});
    await _frames(tester);
    expect(fake.calls.where((c) => c.path.endsWith('/identifiers')).length, before + 1);
    expect(find.text('3 ready, 0 missing'), findsOneWidget);
    expect(find.text('Everyone is ready — you can continue'), findsOneWidget);

    await _tapPrimary(tester);
    expect(find.text('How will students take this exam?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _done(tester);
  });

  testWidgets('Example 2: Online is stored and the wizard closes', (tester) async {
    final b = _Backend({..._p('setup_put_bubble'), 'identifier': {'source': 'national_id', 'key': null}});
    AppConfig.disableList = ['exam.identifiers'];
    final fake = await _open(tester, b);
    expect(find.text('How will students take this exam?'), findsOneWidget);
    expect(find.text('Step 1 of 4 · Type'), findsOneWidget, reason: 'paper with a bubble sheet, no identifier step');

    await tester.tap(find.byKey(const ValueKey('setup.delivery.online')));
    await _frames(tester, 2);
    expect(find.text('Step 1 of 1 · Type'), findsOneWidget, reason: 'online has no further steps');
    await _tapPrimary(tester);
    expect(b.puts.single, {'delivery': 'online'});
    await _frames(tester, 6);
    expect(find.text('Online exams are coming next'), findsNothing, reason: 'online is a real path now, not a dead end');
    expect(find.text('How will students take this exam?'), findsNothing, reason: 'the wizard closed');
    expect(result, isTrue);
    expect(fake.calls.where((c) => c.path.contains('/omr/templates') || c.path.endsWith('/forms')), isEmpty);
    expect(tester.takeException(), isNull);
    await _done(tester);
  });

  testWidgets('Exam paper only skips the bubble-sheet step; finishing an untouched single model sends nothing more',
      (tester) async {
    final b = _Backend(_p('setup_get_new'));
    AppConfig.disableList = ['exam.identifiers'];
    final fake = await _open(tester, b, initialDelivery: 'paper');
    expect(find.text('Step 1 of 4 · Type'), findsOneWidget);
    await _tapPrimary(tester); // Paper is preselected from the quick exam's Offline path
    expect(find.text('What will you print?'), findsOneWidget);
    expect(b.puts, isEmpty, reason: 'paper needs its format: nothing sent yet');

    await tester.tap(find.byKey(const ValueKey('setup.format.paper')));
    await _frames(tester, 2);
    expect(find.text('Step 2 of 3 · Paper'), findsOneWidget);
    await _tapPrimary(tester);
    expect(b.puts.single, {'delivery': 'paper', 'paper_format': 'paper'});
    expect(find.text('Exam models'), findsOneWidget);
    expect(find.text('Step 3 of 3 · Models'), findsOneWidget);
    expect(fake.calls.where((c) => c.path.contains('/omr/templates')), isEmpty, reason: 'no template step for paper only');
    expect(find.text('Marking rules'), findsNothing, reason: 'no bubble sheet, no marking rules');
    expect(find.text('3 of 3 answers set'), findsOneWidget);

    await _tapPrimary(tester);
    expect(b.puts, hasLength(1), reason: 'nothing changed on the last step');
    expect(fake.calls.where((c) => c.method == 'PUT' && c.path.endsWith('/forms')), isEmpty);
    expect(result, isTrue, reason: 'Finish closes the wizard');
    expect(tester.takeException(), isNull);
    await _done(tester);
  });

  testWidgets('no exams right in the organization: the global sheets still load (asked again without org_id)', (tester) async {
    final b = _Backend(_p('setup_get_new'))..orgTemplatesForbidden = true;
    AppConfig.disableList = ['exam.identifiers'];
    final fake = await _open(tester, b, initialDelivery: 'paper');
    await _tapPrimary(tester);
    await tester.tap(find.byKey(const ValueKey('setup.format.bubble')));
    await _frames(tester, 2);
    await _tapPrimary(tester);
    final asked = fake.calls.where((c) => c.path.endsWith('/omr/templates')).map((c) => c.query['org_id']).toList();
    expect(asked, ['1', null], reason: 'first with the organization, then the global list');
    expect(find.byKey(const ValueKey('setup.template.1')), findsOneWidget);
    expect(find.byKey(const ValueKey('setup.template.77')), findsNothing);
    await _done(tester);
  });

  testWidgets('bubble sheet + a second model: the template card, two markers recommended, the policy sent', (tester) async {
    final b = _Backend(_p('setup_get_new'));
    AppConfig.disableList = ['exam.identifiers'];
    final fake = await _open(tester, b, initialDelivery: 'paper');
    await _tapPrimary(tester);
    await tester.tap(find.byKey(const ValueKey('setup.format.bubble')));
    await _frames(tester, 2);
    await _tapPrimary(tester);
    expect(find.text('Choose the bubble-sheet type'), findsOneWidget);
    expect(find.text('40 questions'), findsOneWidget);
    expect('${fake.calls.where((c) => c.path.endsWith('/omr/templates')).single.query['org_id']}', '1', reason: 'the exam own organization is sent');
    expect(find.byKey(const ValueKey('setup.template.77')), findsOneWidget, reason: 'the organization\'s answer table is offered');
    expect(find.textContaining('Answer table'), findsOneWidget, reason: 'with its kind');
    expect(find.byKey(const ValueKey('setup.template.learn')), findsNothing, reason: 'no learning screen given');
    await tester.tap(find.byKey(const ValueKey('setup.template.1')));
    await _frames(tester, 2);
    await _tapPrimary(tester);
    expect(b.puts.last, {'delivery': 'paper', 'paper_format': 'bubble', 'omr_template_id': 1, 'omr_template_version': 1});

    await tester.tap(find.byKey(const ValueKey('setup.form.add')));
    await _frames(tester, 2);
    expect(find.text('How do we tell the models apart?'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('setup.policy.blank.zero')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('setup.policy.blank.zero')));
    await _frames(tester, 2);
    expect(find.text('Unclear marks always go to review — we never guess'), findsOneWidget);
    await _tapPrimary(tester);
    final formsPut = fake.calls.where((c) => c.method == 'PUT' && c.path.endsWith('/forms'));
    expect(formsPut, hasLength(1));
    expect(b.puts.last, {
      'omr_policy': {'blank': 'zero', 'multiple': 'review'},
      'form_markers': ['qr', 'bubble'],
    });
    await _done(tester);
  });
}
