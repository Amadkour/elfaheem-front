import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _placed(int pid, int qid, {String type = 'mcq_single', double points = 2, bool outdated = false, List<String> tags = const []}) => {
      'id': qid, 'org_id': 2, 'type': type, 'tags': tags, 'difficulty': 3, 'status': 'active', 'current_version': outdated ? 2 : 1, 'version': 1,
      'body': {'prompt': 'Which of these statements about photosynthesis and cellular respiration is correct in green plants? ' * 2,
        'options': [{'id': 'a', 'text': 'A'}, {'id': 'b', 'text': 'B'}]},
      'answer': {'correct': 'a'}, 'points': points, 'placement_id': pid, 'position': pid, 'required': pid == 1, 'pinned_version': 1, 'outdated': outdated,
    };

Map<String, dynamic> _exam({String status = 'draft', bool withQuestions = true, int? duration = 60, String? results}) => {
      'id': 5, 'org_id': 2, 'course_id': 9, 'title': 'Midterm exam of the first term — biology and chemistry', 'description': 'd', 'status': status,
      'allowed_platforms': ['web'], 'starts_at': '2026-11-01T08:00:00', 'ends_at': '2026-11-01T10:00:00', 'duration_minutes': duration,
      'max_attempts': 1, 'has_passcode': true, 'results_policy': 'when_published', 'high_stakes': true, 'anonymous_grading': false,
      'settings': {'passing_percent': 60, 'grading': {'auto_accept': false, 'scan_mode': 'printed'}, 'extra_attempts': {'7': 1}, 'appeals': {'days': 7}},
      'version': 4, 'results_published_at': results,
      'sections': [
        {'id': 1, 'position': 0, 'title': 'Part A — multiple choice', 'instructions': 'Answer every question. ' * 6, 'mode': 'online', 'weight': 1.5,
          'time_box_minutes': 20, 'navigation': 'one_way', 'shuffle_questions': true, 'shuffle_options': false, 'pool_size': 2, 'pool_tags': [],
          'questions': withQuestions ? [_placed(1, 11), _placed(2, 12, outdated: true, tags: ['bio'])] : []},
        {'id': 2, 'position': 1, 'title': '', 'instructions': null, 'mode': 'paper', 'weight': 1, 'time_box_minutes': null, 'navigation': 'free',
          'shuffle_questions': false, 'shuffle_options': false, 'pool_size': null, 'pool_tags': [], 'questions': []},
      ],
      'max_score': 6,
      'proctoring': {'exam_id': 5, 'monitoring': {'camera': true, 'mic': false, 'screen': false},
        'rules': [{'category': 'looking_away', 'max': 3, 'consequence': 'flag'}, {'category': 'speech', 'max': 1, 'consequence': 'reject'}],
        'auto_reject': false, 'calibration': false},
    };

Future<String?> _ok(dynamic _) async => null;

void main() {
  setUp(() => AppConfig.lang = 'ar');

  group('question drafts: JSON per type', () {
    test('mcq_single: body options + key; validation codes', () {
      final d = QuestionDraft(type: 'mcq_single')..prompt = ' Capital? ';
      expect(d.validate(), containsAll(['option_text_required', 'bad_answer_key']));
      d.options[0].text = 'Cairo';
      d.options[1].text = 'Giza';
      d.correctSingle = 'a';
      expect(d.validate(), isEmpty);
      expect(d.body(), {'prompt': 'Capital?', 'options': [{'id': 'a', 'text': 'Cairo'}, {'id': 'b', 'text': 'Giza'}]});
      expect(d.answer(), {'correct': 'a'});
      d.options.removeLast();
      expect(d.validate(), contains('options_required'));
      d.prompt = '';
      expect(d.validate(), contains('prompt_required'));
    });

    test('mcq_multi: correct ids follow the options order; partial mode', () {
      final d = QuestionDraft(type: 'mcq_multi')..prompt = 'p';
      d.options.add(QOption(nextOptionId(d.options.map((o) => o.id)), 'C'));
      expect(d.options.last.id, 'c');
      for (final o in d.options) {
        o.text = o.id.toUpperCase();
      }
      expect(d.validate(), ['bad_answer_key']);
      d.correctMulti = {'c', 'a'};
      d.multiPartial = 'none';
      expect(d.validate(), isEmpty);
      expect(d.answer(), {'correct': ['a', 'c'], 'partial': 'none'});
    });

    test('true_false needs a choice', () {
      final d = QuestionDraft(type: 'true_false')..prompt = 'p';
      expect(d.validate(), ['bad_answer_key']);
      d.tfCorrect = false;
      expect(d.validate(), isEmpty);
      expect(d.answer(), {'correct': false});
      expect(d.body(), {'prompt': 'p'});
    });

    test('fill_blank: accepted answers split on commas (Arabic too); markers counted', () {
      final d = QuestionDraft(type: 'fill_blank')..prompt = 'The capital of Egypt is ___ on the ____';
      expect(blankMarkers(d.prompt), 2);
      expect(d.validate(), ['blank_answer_required']);
      d.blanks[0].text = 'Cairo، القاهرة , cairo city';
      d.blanks.add(TextItem('Nile'));
      expect(d.validate(), isEmpty);
      expect(d.answer()['blanks'], [['Cairo', 'القاهرة', 'cairo city'], ['Nile']]);
      expect(d.answer()['partial'], 'per_blank');
    });

    test('matching: left / right columns with distractors, key pairs, round trip', () {
      final d = QuestionDraft(type: 'matching')..prompt = 'match';
      d.pairs[0]
        ..left = 'H2O'
        ..right = 'water';
      d.pairs[1]
        ..left = 'NaCl'
        ..right = 'salt';
      d.distractors = 'sugar, water';
      expect(d.validate(), isEmpty);
      expect(d.body()['left'], ['H2O', 'NaCl']);
      expect(d.body()['right'], ['water', 'salt', 'sugar']);
      expect(d.answer()['pairs'], {'H2O': 'water', 'NaCl': 'salt'});
      final back = QuestionDraft.fromJson({'type': 'matching', 'body': d.body(), 'answer': d.answer(), 'points': 2});
      expect(back.pairs.map((p) => '${p.left}>${p.right}').toList(), ['H2O>water', 'NaCl>salt']);
      expect(back.distractors, 'sugar');
      d.pairs[1].left = 'H2O';
      expect(d.validate(), contains('duplicate_items'));
      d.pairs[1].right = '';
      expect(d.validate(), contains('pair_incomplete'));
    });

    test('ordering: the authored order is the key and the body', () {
      final d = QuestionDraft(type: 'ordering')..prompt = 'order';
      expect(d.validate(), contains('item_text_required'));
      d.items[0].text = 's1';
      d.items[1].text = 's2';
      d.items[2].text = 's3';
      d.orderPartial = 'adjacent';
      expect(d.validate(), isEmpty);
      expect(d.body()['items'], ['s1', 's2', 's3']);
      expect(d.answer(), {'order': ['s1', 's2', 's3'], 'partial': 'adjacent'});
      d.items[2].text = 's1';
      expect(d.validate(), ['duplicate_items']);
    });

    test('numeric: value, tolerance kinds, units with a base unit', () {
      final d = QuestionDraft(type: 'numeric')..prompt = 'g?';
      expect(d.validate(), ['bad_numeric_value']);
      d.numValue = '٩٫٨١';
      d.numTolerance = '2';
      d.toleranceKind = 'pct';
      expect(d.validate(), isEmpty);
      expect(d.answer(), {'value': 9.81, 'tolerance': 2.0, 'tolerance_kind': 'pct'});
      d.units = [NumericUnit('cm/s^2', '0.01')];
      expect(d.validate(), ['unit_base_required']);
      d.units.add(NumericUnit('m/s^2', '1'));
      expect(d.validate(), isEmpty);
      expect(d.answer()['units'], {'cm/s^2': 0.01, 'm/s^2': 1.0});
      expect(d.body()['units'], ['cm/s^2', 'm/s^2']);
      d.numTolerance = '-1';
      d.units.add(NumericUnit('m/s^2', 'x'));
      expect(d.validate(), containsAll(['bad_tolerance', 'bad_unit', 'bad_unit_factor']));
    });

    test('open types: model or rubric; keywords with synonyms; rubric total', () {
      final d = QuestionDraft(type: 'essay')..prompt = 'Explain gravity';
      expect(d.validate(), ['model_answer_required']);
      d.rubric.add(RubricCriterion(id: nextCriterionId(d.rubric), criterion: 'mentions mass', points: 2,
          keywords: parseKeywords('mass = weight, كتلة\n\nattraction ×2 = pull')));
      d.rubric.add(RubricCriterion(id: nextCriterionId(d.rubric), criterion: 'mentions distance', points: 3));
      expect(d.rubric.map((c) => c.id).toList(), ['c1', 'c2']);
      expect(rubricTotal(d.rubric), 5);
      expect(d.validate(), isEmpty);
      final a = d.answer();
      expect(a['model'], '');
      expect((a['rubric'] as List).first, {
        'id': 'c1', 'criterion': 'mentions mass', 'points': 2.0,
        'keywords': [{'term': 'mass', 'synonyms': ['weight', 'كتلة']}, {'term': 'attraction', 'synonyms': ['pull'], 'weight': 2.0}],
      });
      expect(keywordsText(d.rubric.first.keywords), 'mass = weight, كتلة\nattraction ×2 = pull');
      d.alternatives = 'mass attracts mass\n\n bodies pull each other ';
      expect(d.answer()['alternatives'], ['mass attracts mass', 'bodies pull each other']);
      d.rubric.last.points = 0;
      expect(d.validate(), ['bad_rubric']);
      final s = QuestionDraft(type: 'short_answer')
        ..prompt = 'p'
        ..model = 'answer';
      expect(s.validate(), isEmpty);
      expect(s.answer(), {'model': 'answer'});
      expect(QuestionDraft(type: 'file_upload').isOpen, isTrue);
    });

    test('fromJson → body/answer round trip keeps unknown keys; create / update bodies', () {
      final src = {
        'id': 31, 'type': 'mcq_single', 'version': 3, 'points': 2, 'tags': ['algebra'], 'difficulty': 4,
        'body': {'prompt': 'p', 'options': [{'id': 'x', 'text': 'X'}, {'id': 'y', 'text': 'Y'}], 'image_key': 'k1', 'explanation': 'because'},
        'answer': {'correct': 'y', 'teacher_notes': 'n'},
      };
      final d = QuestionDraft.fromJson(src);
      expect(d.isNew, isFalse);
      expect(d.body(), src['body']);
      expect(d.answer(), src['answer']);
      expect(d.toUpdate(), {'body': src['body'], 'answer': src['answer'], 'points': 2.0, 'tags': ['algebra'], 'difficulty': 4});
      final n = QuestionDraft(type: 'true_false')
        ..prompt = 'p'
        ..tfCorrect = true;
      expect(n.toCreate().containsKey('org_id'), isFalse);
      expect(n.toCreate(orgId: 2)['org_id'], 2);
      final open = QuestionDraft.fromJson({'type': 'essay', 'body': {'prompt': 'p'}, 'answer': {'model': 'm', 'keywords': [{'term': 'k'}],
        'rubric': [{'id': 'c1', 'criterion': 'c', 'points': 1, 'keywords': [{'term': 'a', 'synonyms': ['b']}]}]}});
      expect(open.answer()['keywords'], [{'term': 'k'}]);
      expect(open.rubric.single.keywords.single.synonyms, ['b']);
      final num = QuestionDraft.fromJson({'type': 'numeric', 'body': {'prompt': 'p', 'units': ['m']}, 'answer': {'value': 9.81, 'tolerance': 0.05, 'units': {'m': 1}}});
      expect(num.answer(), {'value': 9.81, 'tolerance': 0.05, 'tolerance_kind': 'abs', 'units': {'m': 1.0}});
      final ord = QuestionDraft.fromJson({'type': 'ordering', 'body': {'prompt': 'p', 'items': ['s2', 's1']}, 'answer': {'order': ['s1', 's2']}});
      expect(ord.items.map((i) => i.text).toList(), ['s1', 's2']);
    });

    test('switching the type of a new question keeps the shared parts', () {
      final d = QuestionDraft()
        ..prompt = 'p'
        ..points = 4
        ..tags = ['t'];
      final e = d.withType('essay');
      expect((e.type, e.prompt, e.points, e.tags.single), ('essay', 'p', 4.0, 't'));
      expect(QuestionDraft(type: 'ordering').items.length, 3);
      expect((QuestionDraft()..prompt = 'p'..points = 0).validate(), contains('points_positive'));
    });
  });

  group('exam settings', () {
    test('fromJson defaults and parsed instants (naive UTC)', () {
      final e = ExamDraft.fromJson(_exam());
      expect(e.startsAt, DateTime.utc(2026, 11, 1, 8));
      expect(e.platforms, {'web'});
      expect(e.passingPercent, 60);
      expect(e.appealDays, 7);
      expect(e.appealsPerAttempt, 5);
      expect(e.hasPasscode, isTrue);
      expect(parseEngineUtc('2026-01-01T10:00:00+02:00'), DateTime.utc(2026, 1, 1, 8));
      expect(parseEngineUtc(null), isNull);
      expect(engineIso(DateTime.utc(2026, 1, 1, 8)), '2026-01-01T08:00:00.000Z');
      final fresh = ExamDraft();
      expect((fresh.highStakes, fresh.resultsPolicy, fresh.maxAttempts), (true, 'when_published', 1));
    });

    test('create body carries the space and the passcode', () {
      final d = ExamDraft()
        ..title = ' Quiz '
        ..courseId = 9
        ..durationMinutes = 30
        ..passcode = '1234';
      final b = d.toBody();
      expect(b['title'], 'Quiz');
      expect(b['course_id'], 9);
      expect(b.containsKey('org_id'), isFalse);
      expect(b['passcode'], '1234');
      expect(b['duration_minutes'], 30);
      expect(b['allowed_platforms'], ['web', 'mobile']);
      expect(b.containsKey('expected_version'), isFalse);
    });

    test('update body: unchanged duration / attempts are not sent; settings keep grading and retries', () {
      final original = ExamDraft.fromJson(_exam(status: 'published'));
      final w = original.copy()..title = 'New title';
      var b = w.toBody(original: original);
      expect(b['expected_version'], 4);
      expect(b.containsKey('duration_minutes'), isFalse);
      expect(b.containsKey('max_attempts'), isFalse);
      expect(b.containsKey('passcode'), isFalse);
      expect(b.containsKey('course_id'), isFalse);
      final s = b['settings'] as Map<String, dynamic>;
      expect(s['grading'], {'auto_accept': false, 'scan_mode': 'printed'});
      expect(s['extra_attempts'], {'7': 1});
      expect(s['appeals'], {'days': 7, 'enabled': true, 'per_attempt': 5, 'independent_reviewer': false});
      w
        ..durationMinutes = 90
        ..passcode = '';
      b = w.toBody(original: original);
      expect(b['duration_minutes'], 90);
      expect(b['passcode'], '');
    });

    test('validation codes', () {
      final d = ExamDraft()
        ..startsAt = DateTime.utc(2026, 1, 2)
        ..endsAt = DateTime.utc(2026, 1, 1)
        ..platforms = {}
        ..maxAttempts = -1
        ..passingPercent = 120;
      expect(d.validate(), ['title_required', 'bad_window', 'bad_attempts', 'platform_required', 'bad_passing']);
      final p = ExamDraft.fromJson(_exam(status: 'published', duration: null))..endsAt = null;
      expect(p.validate(), contains('duration_required'));
      expect(platformAdvice({'web', 'mobile'}, highStakes: true), isNot(platformAdvice({'web', 'mobile'}, highStakes: false)));
      expect(platformAdvice({}, highStakes: true), isNotEmpty);
    });
  });

  group('sections, publish gate, lifecycle', () {
    test('section bodies and validation', () {
      final s = SectionDraft.fromJson(_exam()['sections'][0] as Map<String, dynamic>);
      expect((s.navigation, s.poolSize, s.weight), ('one_way', 2, 1.5));
      expect(s.toBody()['pool_tags'], isEmpty);
      expect(s.toPublishedBody().keys.toSet(), {'title', 'instructions', 'time_box_minutes'});
      final bad = SectionDraft()
        ..weight = 0
        ..timeBoxMinutes = -1
        ..poolSize = 0;
      expect(bad.validate(), ['bad_weight', 'bad_time_box_minutes', 'bad_pool_size']);
      expect((SectionDraft()..instructions = '  ').toBody()['instructions'], isNull);
      expect(s.copy().title, s.title);
    });

    test('exam view: counts, pool points, eligible questions', () {
      final v = ExamView.fromJson(_exam());
      expect(v.questionCount, 2);
      expect(v.placedIds, {11, 12});
      expect(v.sections.first.questions.last.outdated, isTrue);
      expect(v.sections.first.points, 6.0);
      expect(publishBlockers(v), isEmpty);
      v.sections.first.section.poolTags = ['bio'];
      expect(v.sections.first.eligible, 1);
      expect(publishBlockers(v), [const PublishBlocker('pool_too_small', 'Part A — multiple choice')]);
    });

    test('publish blockers mirror the server gate', () {
      expect(publishBlockers(ExamView.fromJson({..._exam(), 'sections': []})).map((b) => b.code), ['no_sections']);
      expect(publishBlockers(ExamView.fromJson(_exam(withQuestions: false))).map((b) => b.code), ['no_questions']);
      final empty = _exam();
      (empty['sections'] as List).add({'id': 3, 'position': 2, 'title': 'C', 'mode': 'online', 'questions': []});
      final b = publishBlockers(ExamView.fromJson(empty));
      expect(b.map((e) => e.code), ['empty_section']);
      expect(b.single.text, contains('«C»'));
      final noTime = _exam(duration: null)..['ends_at'] = null;
      expect(publishBlockers(ExamView.fromJson(noTime)).map((e) => e.code), ['duration_required']);
    });

    test('lifecycle actions and section moves', () {
      expect(lifecycleActions('draft', resultsPublished: false), [ExamAction.publish]);
      expect(lifecycleActions('published', resultsPublished: false), [ExamAction.unpublish, ExamAction.close, ExamAction.publishResults]);
      expect(lifecycleActions('closed', resultsPublished: true), isEmpty);
      expect(lifecycleActions('closed', resultsPublished: false), [ExamAction.publishResults]);
      expect(moveInOrder([1, 2, 3], 3, -1), [1, 3, 2]);
      expect(moveInOrder([1, 2, 3], 1, -1), [1, 2, 3]);
      expect(moveInOrder([1, 2, 3], 9, 1), [1, 2, 3]);
    });
  });

  group('proctoring and accommodations', () {
    test('defaults per the brief; body; validation; idle rules; consent coverage', () {
      final d = ProctoringDraft();
      final byCat = {for (final r in d.rules) r.category: (r.max, r.consequence)};
      expect(byCat['looking_away'], (3, 'flag'));
      expect(byCat['tab_switch'], (1, 'flag'));
      expect(byCat['other_app'], (1, 'flag'));
      expect(d.idleRules.map((r) => r.category), containsAll(['looking_away', 'no_face', 'multiple_faces']));
      final p = ProctoringDraft.fromJson(_exam()['proctoring'] as Map<String, dynamic>);
      expect(p.camera, isTrue);
      expect(p.idleRules.map((r) => r.category), ['speech']);
      expect(p.toBody(), {
        'monitoring': {'camera': true, 'mic': false, 'screen': false},
        'rules': [{'category': 'looking_away', 'max': 3, 'consequence': 'flag'}, {'category': 'speech', 'max': 1, 'consequence': 'reject'}],
        'auto_reject': false, 'calibration': false,
      });
      expect(p.unusedCategories, isNot(contains('speech')));
      p.rules.add(ProctorRule('speech', -1, 'explode'));
      expect(p.validate(), ['duplicate_rule', 'bad_rule']);
      expect(undeclaredSensors(p, []), ['camera']);
      expect(undeclaredSensors(p, [{'active': true, 'requires': {'camera': true}}, {'active': false, 'requires': {}}]), isEmpty);
      expect(undeclaredSensors(p, [{'active': true, 'requires': {'camera': true}}, {'active': true, 'lang': 'en', 'requires': {}}]), ['camera']);
    });

    test('accommodation draft', () {
      final a = AccommodationDraft();
      expect(a.validate(), ['student_required', 'accommodation_empty']);
      a
        ..studentId = '42'
        ..extraPercent = '25'
        ..note = ' dyslexia ';
      expect(a.validate(), isEmpty);
      expect(a.toBody(), {'student_id': 42, 'extra_minutes': 0, 'extra_percent': 25, 'large_text': false, 'screen_reader': false,
        'relaxed_thresholds': false, 'note': 'dyslexia', 'exam_only': true});
      a.extraMinutes = '-3';
      expect(a.validate(), ['bad_extra_time']);
      AppConfig.lang = 'en';
      expect(accommodationSummary({'extra_minutes': 10, 'large_text': true, 'exam_id': null}), '+10 min · large text · all exams');
    });
  });

  test('codes → bilingual text; errors; the organization named by the server', () {
    expect(authoringCodeText('pool_too_small'), contains('السحب'));
    AppConfig.lang = 'en';
    expect(authoringCodeText('attempts_exist'), startsWith('Students have started'));
    expect(authoringCodeText('consent_required'), 'Read and accept the consent text before starting');
    expect(authoringCodeText('something_new'), 'something_new');
    expect(authoringError(EngineResult.fail(422, 'no_sections', 'أضف قسماً')), 'Add at least one section');
    expect(authoringError(EngineResult.fail(422, 'brand_new_code', 'server words')), 'server words');
    expect(authoringError(EngineResult.fail(404, null, 'Not Found')), authoringCodeText('engine_unavailable'));
    expect(orgFromScopeError(EngineResult.fail(409, 'course_not_in_org', 'm', {'code': 'course_not_in_org', 'course_org_id': 7})), 7);
    expect(orgFromScopeError(EngineResult.fail(409, 'course_not_in_org', 'm', {'code': 'course_not_in_org', 'course_org_id': null})), isNull);
    expect(orgFromScopeError(EngineResult.fail(403, 'forbidden', 'm')), isNull);
    expect(splitList(' a, b ;c\n'), ['a', 'b', 'c']);
    expect(nextOptionId(['a', 'b', 'd']), 'c');
    expect(fmtPoints(2), '2');
    expect(fmtPoints(2.5), '2.5');
    expect(parseIntField('١٢'), 12);
    expect(parseIntField('1.5'), isNull);
  });

  group('layout', () {
    testWidgets('exam settings form: create and published', (tester) async {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: ExamSettingsForm(draft: ExamDraft()..courseId = 9, creating: true, onSave: _ok)));
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: ExamSettingsForm(draft: ExamDraft.fromJson(_exam(status: 'published')), onSave: _ok)),
          act: (tester) async {
        final save = find.text(AppConfig.lang == 'ar' ? 'حفظ الإعدادات' : 'Save settings');
        await tester.ensureVisible(save);
        await tester.tap(save);
      });
    });

    testWidgets('sections panel: draft, published, empty', (tester) async {
      Widget panel(Map<String, dynamic> j) => SingleChildScrollView(
          child: ExamSectionsPanel(view: ExamView.fromJson(j), onAddSection: () {}, onEditSection: (_) {}, onDeleteSection: (_) {},
              onMoveSection: (_, _) {}, onAddQuestions: (_) {}, onRemoveQuestion: (_) {}, onEditQuestion: (_, _) {}));
      await expectNoLayoutErrors(tester, () => panel(_exam()));
      await expectNoLayoutErrors(tester, () => panel(_exam(status: 'published')));
      await expectNoLayoutErrors(tester, () => panel({..._exam(), 'sections': []}));
    });

    testWidgets('question editor: every type, new and existing', (tester) async {
      for (final type in questionTypes) {
        await expectNoLayoutErrors(tester, () => QuestionEditorForm(draft: QuestionDraft(type: type)..prompt = 'A long prompt ' * 12, onSave: _ok));
      }
      final essay = QuestionDraft.fromJson({'id': 3, 'version': 2, 'type': 'essay', 'points': 4, 'tags': ['a', 'b'], 'body': {'prompt': 'Explain'},
        'answer': {'model': 'm', 'rubric': [{'id': 'c1', 'criterion': 'light energy is used to make glucose', 'points': 1,
          'keywords': [{'term': 'light', 'synonyms': ['sunlight', 'ضوء']}]}]}});
      await expectNoLayoutErrors(tester, () => QuestionEditorForm(draft: essay, onSave: _ok));
      final numeric = QuestionDraft(type: 'numeric')
        ..prompt = 'g'
        ..units = [NumericUnit('m/s^2', '1'), NumericUnit('cm/s^2', '0.01')];
      await expectNoLayoutErrors(tester, () => QuestionEditorForm(draft: numeric, onSave: _ok));
    });

    testWidgets('question editor: validation errors show', (tester) async {
      await expectNoLayoutErrors(tester, () => QuestionEditorForm(draft: QuestionDraft(type: 'matching'), onSave: _ok), act: (tester) async {
        final save = find.text(AppConfig.lang == 'ar' ? 'حفظ في البنك' : 'Save to the bank');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pump();
        expect(find.textContaining(authoringCodeText('prompt_required')), findsOneWidget);
      });
    });

    testWidgets('section form, proctoring, accommodations', (tester) async {
      await expectNoLayoutErrors(tester, () => SectionForm(section: SectionDraft(), onSave: _ok));
      await expectNoLayoutErrors(tester, () => SectionForm(section: SectionDraft.fromJson(_exam()['sections'][0] as Map<String, dynamic>), published: true, onSave: _ok));
      final policy = ProctoringDraft.fromJson(_exam()['proctoring'] as Map<String, dynamic>)..mic = false;
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: ProctoringPolicyForm(draft: policy, consents: const [], onSave: _ok)));
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          child: AccommodationsPanel(items: [
            {'id': 1, 'student_id': 42, 'extra_minutes': 15, 'extra_percent': 25, 'large_text': true, 'screen_reader': true, 'relaxed_thresholds': true,
              'note': 'Needs a quiet room and a reader for the long passages ' * 3, 'exam_id': null},
          ], onAdd: () {}, onRevoke: (_) {})));
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: AccommodationsPanel(items: null, onAdd: () {}, onRevoke: (_) {})));
      await expectNoLayoutErrors(tester, () => AccommodationForm(onSave: _ok));
    });

    testWidgets('publish panel: blockers, published, closed with an error', (tester) async {
      Widget panel(Map<String, dynamic> j, {String? error}) => SingleChildScrollView(child: ExamPublishPanel(view: ExamView.fromJson(j), onAction: (_) {}, error: error));
      await expectNoLayoutErrors(tester, () => panel({..._exam(duration: null), 'ends_at': null, 'sections': []}));
      await expectNoLayoutErrors(tester, () => panel(_exam()));
      await expectNoLayoutErrors(tester, () => panel(_exam(status: 'published')));
      await expectNoLayoutErrors(tester, () => panel(_exam(status: 'closed'), error: authoringCodeText('review_pending')));
    });

    testWidgets('bank tile', (tester) async {
      final q = BankQuestion.fromJson({..._placed(1, 11, tags: ['algebra', 'equations', 'grade-10', 'hidden']), 'status': 'archived'});
      await expectNoLayoutErrors(tester, () => ListView(children: [
            BankQuestionTile(question: q, trailing: IconButton(onPressed: () {}, icon: const Icon(Icons.add))),
            BankQuestionTile(question: q),
          ]));
    });
  });
}
