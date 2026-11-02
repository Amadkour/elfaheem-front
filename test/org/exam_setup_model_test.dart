// Paper exam setup (D-150, D-151, D-155, D-156): the pure part of the wizard — the real reply shapes (recorded from
// the backend's own e2e tests, test/org/fixtures/omr_setup_payloads.json), the steps, the request bodies (only the
// keys that change) and the codes in plain words.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _p(String name) =>
    ((jsonDecode(File('test/org/fixtures/omr_setup_payloads.json').readAsStringSync()) as Map)['payloads'] as Map)[name] as Map<String, dynamic>;

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('real replies', () {
    test('GET setup of a new exam: online, nothing chosen, the safe policy', () {
      final s = ExamSetup.fromJson(_p('setup_get_new'));
      expect(s.examId, 1);
      expect(s.delivery, 'online');
      expect(s.onlineAvailable, isFalse);
      expect(s.paperFormat, isNull);
      expect(s.identifier, isNull);
      expect(s.template, isNull);
      expect(s.policy, const OmrPolicy(blank: 'review', multiple: 'review'));
      expect(s.markers, isEmpty);
      expect(s.paperSections, 1);
    });

    test('PUT setup reply: bubble sheet pinned to a published version, markers, warnings', () {
      final s = ExamSetup.fromJson(_p('setup_put_bubble'));
      expect(s.delivery, 'paper');
      expect(s.paperFormat, 'bubble');
      expect(s.isBubble, isTrue);
      expect((s.templateId, s.templateVersion), (1, 1));
      expect(s.template!.name, 'Bubble 40');
      expect(s.template!.status, 'published');
      expect(s.policy, const OmrPolicy(blank: 'zero', multiple: 'wrong'));
      expect(s.markers, ['qr', 'bubble']);
      expect(s.forms, 2);
      expect(s.warnings, ['identifier_not_set']);
    });

    test('identifiers: 3 total / 2 ready / 1 missing by name, one duplicate group, no values', () {
      final r = IdentifierReport.fromJson(_p('identifiers'));
      expect(r.source, 'national_id');
      expect(r.label, 'National ID');
      expect(r.kind, 'digits');
      expect(r.collectable, isTrue);
      expect((r.total, r.ready, r.missingCount), (3, 2, 1));
      expect(r.missing.single.name, 'Sara');
      expect(r.missing.single.userId, 15);
      expect(r.duplicates, hasLength(1));
      expect(r.duplicates.single.map((s) => s.name).toList(), ['Ali', 'Mona']);
      expect(r.duplicateStudents, 2);
      expect(r.pending, 0);
      expect(r.summary, '2 ready, 1 missing');
      AppConfig.lang = 'ar';
      expect(r.label, 'الرقم القومي');
      expect(r.summary, '2 جاهز، 1 ناقص');
      expect(IdentifierReport.fromJson(_p('identifiers_after_request')).pending, 1);
    });

    test('templates: the published version with its question count; options only when the server sends them', () {
      final items = [for (final m in (_p('templates')['items'] as List).cast<Map<String, dynamic>>()) OmrTemplateItem.fromJson(m)];
      expect(items.single.name, 'Bubble 40');
      expect(items.single.questions, 40);
      expect(items.single.options, isNull, reason: 'the list does not send options today');
      expect(items.single.shape, '40 questions');
      expect(OmrTemplateItem.fromJson({'id': 3, 'name': 'X', 'status': 'published', 'questions': 50, 'options': 4}).shape, '50 questions, 4 options (A–D)');
      expect(choosableTemplates([...items, OmrTemplateItem.fromJson({'id': 2, 'name': 'Mine', 'status': 'pending_approval'})]).map((x) => x.id), [1]);
    });

    test('forms: codes, labels and keys as the server stores them', () {
      final forms = [for (final m in (_p('forms_put')['items'] as List).cast<Map<String, dynamic>>()) ExamFormDraft.fromJson(m)];
      expect(forms.map((f) => f.code), ['A', 'B']);
      expect(forms.first.label, 'Model A');
      expect(forms.first.key, {'1': 'b', '2': 'b', '3': true});
      expect(forms.first.toJson(), {'code': 'A', 'label': 'Model A', 'key': {'1': 'b', '2': 'b', '3': true}});
      final g = [for (final m in (_p('forms_get')['items'] as List).cast<Map<String, dynamic>>()) ExamFormDraft.fromJson(m)];
      expect(g.last.key, isEmpty);
      expect(g.first.toJson().containsKey('label'), isFalse, reason: 'a null label is not sent');
    });

    test('identity fields: the seeded national / academic ids plus a custom field', () {
      final fields = [for (final m in (_p('fields_all')['items'] as List).cast<Map<String, dynamic>>()) IdentityFieldDef.fromJson(m)];
      expect(fields.map((f) => f.key), ['national_id', 'academic_id', 'passport_no']);
      expect((fields.first.kind, fields.first.minLen, fields.first.maxLen), ('digits', 14, 14));
      final opts = identifierOptions(fields, dataLab: true, dataLabColumns: const [('seat_no', 'Seat number')]);
      expect(opts.map((o) => o.choice.id), [
        'name', 'email', 'phone', 'academic_id', 'national_id', 'custom:passport_no', 'datalab:__identifier', 'datalab:seat_no',
      ]);
      expect(opts.where((o) => !o.collectable).map((o) => o.choice.id), ['name', 'datalab:__identifier', 'datalab:seat_no']);
      expect(opts.firstWhere((o) => o.choice.source == 'national_id').label, 'National ID');
      // a switched-off national id is not offered; no course → no Data Lab
      expect(identifierOptions(fields.skip(1).toList()).map((o) => o.choice.id), ['name', 'email', 'phone', 'academic_id', 'custom:passport_no']);
    });

    test('the server\'s errors keep their code and detail', () {
      expect(setupCodeText('template_not_published', const {}), 'This sheet type is not approved yet — choose a published one');
      expect(setupCodeText('form_in_use', {'codes': ['A']}), 'Models with read sheets cannot be removed: A');
      expect(setupCodeText('reminder_too_soon', {'retry_after': 1700}), 'A reminder went out recently — you can remind again in 29 min');
      expect(setupCodeText('nope'), '');
      AppConfig.lang = 'ar';
      expect(setupCodeText('identifiers_need_course'), contains('اربط الاختبار بمقرر'));
    });
  });

  group('steps', () {
    test('the full paper path with a bubble sheet: 5 steps', () {
      expect(setupSteps(identifiersOn: true, omrOn: true, delivery: 'paper', format: 'bubble'),
          [SetupStep.identify, SetupStep.delivery, SetupStep.format, SetupStep.template, SetupStep.forms]);
      expect(setupSteps(identifiersOn: true, omrOn: true, delivery: 'paper', format: 'both'), contains(SetupStep.template));
    });

    test('Example 2: online stops after the type', () {
      expect(setupSteps(identifiersOn: true, omrOn: true, delivery: 'online'), [SetupStep.identify, SetupStep.delivery]);
    });

    test('exam paper only skips the template step', () {
      expect(setupSteps(identifiersOn: true, omrOn: true, delivery: 'paper', format: 'paper'),
          [SetupStep.identify, SetupStep.delivery, SetupStep.format, SetupStep.forms]);
    });

    test('kill switches: no identifier step; no bubble-sheet step', () {
      expect(setupSteps(identifiersOn: false, omrOn: true, delivery: 'paper', format: 'bubble').first, SetupStep.delivery);
      expect(setupSteps(identifiersOn: true, omrOn: false, delivery: 'paper', format: 'bubble'), isNot(contains(SetupStep.template)));
    });
  });

  group('bodies: only the keys that change', () {
    final fresh = ExamSetup.fromJson(_p('setup_get_new'));
    final bubble = ExamSetup.fromJson(_p('setup_put_bubble'));
    const tpl = OmrTemplateItem(id: 1, version: 1, name: 'Bubble 40', questions: 40);

    test('identifier', () {
      expect(identifierBody(fresh, const IdentifierChoice('national_id')), {
        'identifier': {'source': 'national_id', 'key': null},
      });
      expect(identifierBody(fresh, const IdentifierChoice('custom', 'passport_no'))['identifier'], {'source': 'custom', 'key': 'passport_no'});
      final set = ExamSetup.fromJson({..._p('setup_get_new'), 'identifier': {'source': 'national_id', 'key': null}});
      expect(identifierBody(set, const IdentifierChoice('national_id')), isEmpty);
    });

    test('online: sent only when the exam is not online already', () {
      expect(onlineBody(fresh), isEmpty);
      expect(onlineBody(bubble), {'delivery': 'online'});
    });

    test('paper only from a new exam; leaving the bubble sheet drops the bubble marker', () {
      expect(formatBody(fresh, 'paper'), {'delivery': 'paper', 'paper_format': 'paper'});
      expect(formatBody(bubble, 'paper'), {'paper_format': 'paper', 'form_markers': ['qr']});
    });

    test('bubble sheet: the template with its version in the same call', () {
      expect(formatBody(fresh, 'bubble', template: tpl), {'delivery': 'paper', 'paper_format': 'bubble', 'omr_template_id': 1, 'omr_template_version': 1});
      expect(formatBody(bubble, 'bubble', template: tpl), isEmpty, reason: 'nothing changed');
      expect(formatBody(bubble, 'both', template: tpl), {'paper_format': 'both', 'omr_template_id': 1, 'omr_template_version': 1});
    });

    test('finish: policy and markers only when changed; never `uncertain`', () {
      expect(finishBody(fresh, policy: const OmrPolicy(blank: 'zero')), {
        'omr_policy': {'blank': 'zero', 'multiple': 'review'},
      });
      expect(finishBody(bubble, policy: const OmrPolicy(blank: 'zero', multiple: 'wrong'), markers: const ['bubble', 'qr']), isEmpty);
      expect(finishBody(bubble, markers: const ['qr', 'printed']), {'form_markers': ['qr', 'printed']});
      expect(const OmrPolicy().toJson().containsKey('uncertain'), isFalse);
    });
  });

  group('forms', () {
    final qs = [
      ObjectiveQuestion.fromPlaced({'id': 1, 'type': 'mcq_single', 'body': {'prompt': 'Q0', 'options': ['a', 'b', 'c', 'd']}, 'answer': {'correct': 'b'}})!,
      ObjectiveQuestion.fromPlaced({
        'id': 2,
        'type': 'mcq_multi',
        'body': {'prompt': 'Pick two', 'options': [{'id': 'x', 'text': 'X'}, {'id': 'y', 'text': 'Y'}, {'id': 'z', 'text': 'Z'}]},
        'answer': {'correct': ['x', 'z']},
      })!,
      ObjectiveQuestion.fromPlaced({'id': 3, 'type': 'true_false', 'body': {'prompt': 'The sun is a star'}, 'answer': {'correct': true}})!,
    ];

    test('objective questions only, with their own keys and letters', () {
      expect(ObjectiveQuestion.fromPlaced({'id': 9, 'type': 'essay', 'body': {}}), isNull);
      expect(qs[0].choices.map((c) => c.$2), ['A', 'B', 'C', 'D']);
      expect(qs[0].choices.map((c) => c.$1), ['a', 'b', 'c', 'd']);
      expect(qs[2].choices.map((c) => c.$1), [true, false]);
    });

    test('a new form starts from the questions\' keys; choosing replaces / toggles', () {
      final b = newForm('B', qs);
      expect(b.key, {'1': 'b', '2': ['x', 'z'], '3': true});
      qs[0].choose(b, 'c');
      qs[1].choose(b, 'x');
      qs[1].choose(b, 'y');
      qs[2].choose(b, false);
      expect(b.key, {'1': 'c', '2': ['z', 'y'], '3': false});
      expect(qs[1].isChosen(b, 'y'), isTrue);
      expect(qs[1].isChosen(b, 'x'), isFalse);
      expect(qs[0].answeredIn(ExamFormDraft(code: 'C')), isFalse);
    });

    test('codes A, B, C … and at most ten; the same list sends nothing', () {
      final list = [ExamFormDraft(code: 'A'), ExamFormDraft(code: 'C')];
      expect(nextFormCode(list), 'B');
      expect(nextFormCode([for (var i = 0; i < 10; i++) ExamFormDraft(code: String.fromCharCode(65 + i))]), isNull);
      final a = newForm('A', qs);
      expect(sameForms([a], [newForm('A', qs)]), isTrue);
      expect(sameForms([a], [a.copy()..key['1'] = 'd']), isFalse);
      expect(sameForms([a], const []), isFalse);
    });

    test('exam refs', () {
      expect(examIdFromRef('exam:12'), 12);
      expect(examIdFromRef('quiz:12'), isNull);
      expect(examIdFromRef(null), isNull);
      expect(examRefOf(7), 'exam:7');
    });
  });
}
