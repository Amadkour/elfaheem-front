import 'package:flutter_education_app/features/exams/exam_authoring.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dart port of back/exam_engine/services/questions.py `validate` (the contract), returning the server code or null.
String? serverValidate(String type, Map<String, dynamic> body, Map<String, dynamic> a) {
  if (!questionTypes.contains(type)) return 'bad_question_type';
  if ('${body['prompt'] ?? ''}'.trim().isEmpty) return 'prompt_required';
  if (type == 'mcq_single' || type == 'mcq_multi') {
    final ids = [for (final o in (body['options'] as List? ?? const [])) '${o is Map ? o['id'] : o}'];
    if (ids.length != ids.toSet().length) return 'duplicate_options';
    if (ids.length < 2) return 'options_required';
    final c = a['correct'];
    if (type == 'mcq_single') {
      if (!ids.contains('$c')) return 'bad_answer_key';
    } else {
      final cs = [for (final x in (c as List? ?? const [])) '$x'];
      if (cs.isEmpty || cs.any((x) => !ids.contains(x))) return 'bad_answer_key';
    }
  } else if (type == 'true_false') {
    if (a['correct'] is! bool) return 'bad_answer_key';
  } else if (type == 'fill_blank') {
    final b = a['blanks'] as List? ?? const [];
    if (b.isEmpty || b.any((x) => x is List ? x.isEmpty : false)) return 'bad_answer_key';
  } else if (type == 'matching') {
    final p = a['pairs'];
    if (p is! Map || p.length < 2) return 'bad_answer_key';
  } else if (type == 'ordering') {
    final o = a['order'] as List? ?? const [];
    if (o.length < 2 || o.map((e) => '$e').toSet().length != o.length) return 'bad_answer_key';
  } else if (type == 'numeric') {
    if (a['value'] == null || double.tryParse('${a['value']}') == null) return 'bad_answer_key';
    if (((a['tolerance'] as num?) ?? 0) < 0) return 'bad_answer_key';
  } else {
    final r = a['rubric'] as List? ?? const [];
    if ('${a['model'] ?? ''}'.trim().isEmpty && r.isEmpty) return 'model_answer_required';
    for (final c in r) {
      if (c is! Map || '${c['criterion'] ?? ''}'.isEmpty || ((c['points'] as num?) ?? 0) <= 0) return 'bad_rubric';
    }
  }
  return null;
}

QuestionDraft mcq([String type = 'mcq_single']) => QuestionDraft(type: type)
  ..prompt = 'Capital of Egypt?'
  ..options = [QOption('a', 'Cairo'), QOption('b', 'Giza'), QOption('c', 'Luxor')];

void expectServerOk(QuestionDraft d) {
  expect(d.validate(), isEmpty, reason: 'client rejects a valid draft');
  expect(serverValidate(d.type, d.body(), d.answer()), isNull);
}

void main() {
  group('objective types: shapes the server validates', () {
    test('mcq_single key {"correct": id} with id among options', () {
      final d = mcq()..correctSingle = 'b';
      expectServerOk(d);
      expect(d.answer()['correct'], 'b');
      final opts = (d.body()['options'] as List).map((o) => (o as Map)['id']).toList();
      expect(opts, ['a', 'b', 'c']);
      expect(d.body()['prompt'], 'Capital of Egypt?');
    });

    test('mcq_multi correct is a list subset of options', () {
      final d = mcq('mcq_multi')..correctMulti = {'a', 'c'};
      expectServerOk(d);
      final c = d.answer()['correct'];
      expect(c, isA<List>());
      expect((c as List).toSet(), {'a', 'c'});
    });

    test('true_false correct is a bool (both values)', () {
      for (final v in [true, false]) {
        final d = QuestionDraft(type: 'true_false')
          ..prompt = 'Nile is a river'
          ..tfCorrect = v;
        expectServerOk(d);
        expect(d.answer()['correct'], v);
      }
    });

    test('fill_blank blanks is a list of non-empty lists', () {
      final d = QuestionDraft(type: 'fill_blank')
        ..prompt = 'The capital is ___ on the ___'
        ..blanks = [TextItem('Cairo, القاهرة'), TextItem('Nile')];
      expectServerOk(d);
      expect(d.answer()['blanks'], [
        ['Cairo', 'القاهرة'],
        ['Nile']
      ]);
    });

    test('fill_blank student body exposes no key', () {
      final d = QuestionDraft(type: 'fill_blank')
        ..prompt = 'x ___'
        ..blanks = [TextItem('a')];
      expect(d.body().containsKey('blanks'), isFalse);
      expect(d.body().containsKey('correct'), isFalse);
    });

    test('matching pairs map left id to right id, both sides in body', () {
      final d = QuestionDraft(type: 'matching')
        ..prompt = 'Match'
        ..pairs = [MatchPair('Egypt', 'Cairo'), MatchPair('France', 'Paris')];
      expectServerOk(d);
      final pairs = d.answer()['pairs'] as Map;
      final body = d.body();
      expect(pairs.length, 2);
      final left = [for (final l in body['left'] as List) l is Map ? '${l['id']}' : '$l'];
      final right = [for (final r in body['right'] as List) r is Map ? '${r['id']}' : '$r'];
      for (final e in pairs.entries) {
        expect(left, contains('${e.key}'));
        expect(right, contains('${e.value}'));
      }
    });

    test('matching distractors extend the right column but not the key', () {
      final d = QuestionDraft(type: 'matching')
        ..prompt = 'Match'
        ..pairs = [MatchPair('Egypt', 'Cairo'), MatchPair('France', 'Paris')]
        ..distractors = 'Rome';
      expectServerOk(d);
      expect((d.body()['right'] as List).length, 3);
      expect((d.answer()['pairs'] as Map).length, 2);
    });

    test('ordering order lists the item ids of the body, unique', () {
      final d = QuestionDraft(type: 'ordering')
        ..prompt = 'Sort'
        ..items = [TextItem('first'), TextItem('second'), TextItem('third')];
      expectServerOk(d);
      final order = (d.answer()['order'] as List).map((e) => '$e').toList();
      expect(order.length, 3);
      final ids = [for (final i in d.body()['items'] as List) i is Map ? '${i['id']}' : '$i'];
      expect(ids.toSet(), order.toSet());
    });

    test('numeric value, tolerance, tolerance_kind and factor-1 unit', () {
      final d = QuestionDraft(type: 'numeric')
        ..prompt = 'g?'
        ..numValue = '9.81'
        ..numTolerance = '0.05'
        ..toleranceKind = 'abs'
        ..units = [NumericUnit('m/s^2', '1'), NumericUnit('cm/s^2', '0.01')];
      expectServerOk(d);
      final a = d.answer();
      expect(a['value'], isA<num>());
      expect(a['value'], 9.81);
      expect(a['tolerance'], 0.05);
      expect(a['tolerance_kind'], 'abs');
      final units = a['units'] as Map;
      expect(units['m/s^2'], 1);
      expect(units['cm/s^2'], 0.01);
      expect(units.values.any((f) => (f as num) == 1), isTrue);
    });

    test('numeric pct tolerance kind is sent as "pct"', () {
      final d = QuestionDraft(type: 'numeric')
        ..prompt = 'g?'
        ..numValue = '100'
        ..numTolerance = '5'
        ..toleranceKind = 'pct';
      expectServerOk(d);
      expect(d.answer()['tolerance_kind'], 'pct');
    });
  });

  group('open types', () {
    for (final t in ['short_answer', 'essay', 'file_upload']) {
      test('$t with a model answer is accepted', () {
        final d = QuestionDraft(type: t)
          ..prompt = 'Explain'
          ..model = 'Because.';
        expectServerOk(d);
        expect(d.answer()['model'], 'Because.');
      });
    }

    test('rubric criteria carry id, criterion, positive points and keywords {term, synonyms, weight}', () {
      final d = QuestionDraft(type: 'essay')
        ..prompt = 'Explain'
        ..points = 5
        ..rubric = [
          RubricCriterion(id: 'c1', criterion: 'Defines it', points: 3, keywords: [RubricKeyword('gravity', ['g'], 2)]),
          RubricCriterion(id: 'c2', criterion: 'Example', points: 2),
        ];
      expectServerOk(d);
      final r = d.answer()['rubric'] as List;
      expect(r.length, 2);
      expect((r[0] as Map)['id'], 'c1');
      expect((r[0] as Map)['points'], 3);
      final kw = ((r[0] as Map)['keywords'] as List).single as Map;
      expect(kw['term'], 'gravity');
      expect(kw['synonyms'], ['g']);
      expect(kw['weight'], 2);
      expect(rubricTotal(d.rubric), 5);
    });

    test('keyword text parsing gives term, synonyms and weight', () {
      final k = parseKeywords('force ×2 = push, pull\nmass');
      expect(k.length, 2);
      expect(k[0].term, 'force');
      expect(k[0].weight, 2);
      expect(k[0].synonyms, ['push', 'pull']);
      expect(k[1].weight, 1);
    });
  });

  group('invalid drafts are rejected client-side like the server', () {
    test('empty prompt', () {
      final d = mcq()
        ..prompt = '  '
        ..correctSingle = 'a';
      expect(d.validate(), isNotEmpty);
      expect(serverValidate(d.type, d.body(), d.answer()), 'prompt_required');
    });

    test('fewer than 2 options', () {
      final d = mcq()
        ..options = [QOption('a', 'only')]
        ..correctSingle = 'a';
      expect(d.validate(), isNotEmpty);
      expect(serverValidate(d.type, d.body(), d.answer()), 'options_required');
    });

    test('mcq_single without a chosen correct option', () {
      expect(mcq().validate(), isNotEmpty);
    });

    test('mcq_single correct not among options', () {
      final d = mcq()..correctSingle = 'zz';
      expect(d.validate(), isNotEmpty);
    });

    test('mcq_multi with no correct or a stray correct id', () {
      expect(mcq('mcq_multi').validate(), isNotEmpty);
      expect((mcq('mcq_multi')..correctMulti = {'a', 'zz'}).validate(), isNotEmpty);
    });

    test('duplicate option ids', () {
      final d = mcq()
        ..options = [QOption('a', 'x'), QOption('a', 'y')]
        ..correctSingle = 'a';
      expect(d.validate(), isNotEmpty);
    });

    test('true_false with no answer chosen', () {
      final d = QuestionDraft(type: 'true_false')..prompt = 'x';
      expect(d.validate(), isNotEmpty);
    });

    test('fill_blank blank without an accepted answer', () {
      final d = QuestionDraft(type: 'fill_blank')
        ..prompt = 'x ___'
        ..blanks = [TextItem('')];
      expect(d.validate(), isNotEmpty);
    });

    test('matching with one pair, ordering with one item', () {
      final m = QuestionDraft(type: 'matching')
        ..prompt = 'm'
        ..pairs = [MatchPair('a', 'b')];
      expect(m.validate(), isNotEmpty);
      final o = QuestionDraft(type: 'ordering')
        ..prompt = 'o'
        ..items = [TextItem('a')];
      expect(o.validate(), isNotEmpty);
    });

    test('numeric: non-number value and negative tolerance', () {
      final d = QuestionDraft(type: 'numeric')
        ..prompt = 'n'
        ..numValue = 'abc';
      expect(d.validate(), isNotEmpty);
      final e = QuestionDraft(type: 'numeric')
        ..prompt = 'n'
        ..numValue = '5'
        ..numTolerance = '-1';
      expect(e.validate(), isNotEmpty);
    });

    test('open type without model or rubric; rubric criterion with zero points', () {
      final d = QuestionDraft(type: 'essay')..prompt = 'e';
      expect(d.validate(), isNotEmpty);
      final r = QuestionDraft(type: 'essay')
        ..prompt = 'e'
        ..rubric = [RubricCriterion(id: 'c1', criterion: 'x', points: 0)];
      expect(r.validate(), isNotEmpty);
    });

    test('create/update bodies carry type, body, answer, points', () {
      final d = mcq()..correctSingle = 'a';
      final c = d.toCreate();
      expect(c['type'], 'mcq_single');
      expect(c['body'], isA<Map>());
      expect(c['answer'], isA<Map>());
      expect(c['points'], 1);
      expect(d.toUpdate().containsKey('type'), isFalse);
    });
  });

  group('exam, section, proctoring payloads', () {
    test('exam body uses server enums and keys', () {
      final e = ExamDraft()
        ..title = 'Midterm'
        ..durationMinutes = 60
        ..platforms = {'web'};
      final b = e.toBody();
      expect(b['title'], 'Midterm');
      expect(b['allowed_platforms'], ['web']);
      expect(resultsPolicies, contains(b['results_policy']));
      expect(b['duration_minutes'], 60);
      expect(b['max_attempts'], greaterThanOrEqualTo(1));
      expect(e.validate(), isEmpty);
    });

    test('exam needs a title, a platform and a positive duration', () {
      expect((ExamDraft()..durationMinutes = 30).validate(), isNotEmpty);
      expect((ExamDraft()
            ..title = 't'
            ..platforms = {}
            ..durationMinutes = 30)
          .validate(), isNotEmpty);
      expect((ExamDraft()
            ..title = 't'
            ..durationMinutes = 0)
          .validate(), isNotEmpty);
    });

    test('exam window must end after it starts', () {
      final e = ExamDraft()
        ..title = 't'
        ..durationMinutes = 30
        ..startsAt = DateTime.utc(2026, 1, 2)
        ..endsAt = DateTime.utc(2026, 1, 1);
      expect(e.validate(), isNotEmpty);
    });

    test('section body uses server mode/navigation values and positive weight', () {
      final s = SectionDraft()
        ..title = 'A'
        ..mode = 'hybrid'
        ..navigation = 'one_way'
        ..weight = 2;
      final b = s.toBody();
      expect(sectionModes, contains(b['mode']));
      expect(sectionNavigations, contains(b['navigation']));
      expect(b['weight'], 2);
      expect(s.validate(), isEmpty);
      expect((SectionDraft()..weight = 0).validate(), isNotEmpty);
      expect((SectionDraft()..timeBoxMinutes = 0).validate(), isNotEmpty);
      expect((SectionDraft()..poolSize = 0).validate(), isNotEmpty);
    });

    test('enums mirror models.py', () {
      expect(sectionModes, ['online', 'paper', 'hybrid']);
      expect(sectionNavigations, ['free', 'one_way']);
      expect(resultsPolicies, ['hidden', 'after_submit', 'when_published']);
      expect(examPlatforms, ['web', 'mobile']);
      expect(proctorConsequences, ['warn', 'flag', 'lock', 'auto_submit', 'reject']);
    });

    test('proctor categories exclude the never-counted kinds', () {
      for (final never in ['proctoring_unavailable', 'network_lost', 'resumed', 'warned', 'locked', 'auto_submitted', 'note']) {
        expect(proctorCategories, isNot(contains(never)));
      }
      expect(proctorCategories.toSet().length, proctorCategories.length);
    });

    test('default proctoring rules equal the server DEFAULT_RULES', () {
      final got = defaultProctorRules().map((r) => r.toJson()).toList();
      expect(got, [
        {'category': 'looking_away', 'max': 3, 'consequence': 'flag'},
        {'category': 'other_app', 'max': 1, 'consequence': 'flag'},
        {'category': 'tab_switch', 'max': 1, 'consequence': 'flag'},
        {'category': 'no_face', 'max': 3, 'consequence': 'warn'},
        {'category': 'multiple_faces', 'max': 1, 'consequence': 'flag'},
      ]);
    });

    test('proctoring body: monitoring flags, rules, auto_reject, calibration', () {
      final p = ProctoringDraft()
        ..camera = true
        ..autoReject = true;
      final b = p.toBody();
      expect(b['monitoring'], {'camera': true, 'mic': false, 'screen': false});
      expect(b['auto_reject'], true);
      expect(b['calibration'], false);
      for (final r in b['rules'] as List) {
        expect(proctorCategories, contains((r as Map)['category']));
        expect(proctorConsequences, contains(r['consequence']));
        expect(r['max'], isA<int>());
        expect(r['max'], greaterThanOrEqualTo(0));
      }
    });

    test('proctoring round trip keeps the server shape', () {
      final j = {
        'monitoring': {'camera': true, 'mic': true, 'screen': false},
        'rules': [
          {'category': 'speech', 'max': 2, 'consequence': 'lock'}
        ],
        'auto_reject': false,
        'calibration': true,
      };
      final b = ProctoringDraft.fromJson(j).toBody();
      expect(b['monitoring'], j['monitoring']);
      expect(b['rules'], j['rules']);
      expect(b['calibration'], true);
    });

    test('proctoring validate flags duplicate categories, negative max, unknown consequence', () {
      expect((ProctoringDraft()..rules = [ProctorRule('tab_switch', 1, 'flag'), ProctorRule('tab_switch', 2, 'warn')]).validate(), isNotEmpty);
      expect((ProctoringDraft()..rules = [ProctorRule('tab_switch', -1, 'flag')]).validate(), isNotEmpty);
      expect((ProctoringDraft()..rules = [ProctorRule('tab_switch', 1, 'explode')]).validate(), isNotEmpty);
    });
  });
}
