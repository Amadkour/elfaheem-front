import 'package:flutter_education_app/features/org/org_levels.dart';
import 'package:flutter_test/flutter_test.dart';

LevelDraft lv(String key, {String programs = 'inherit', List<int>? ids}) => LevelDraft(key: key, programs: programs, programIds: ids);

void main() {
  group('resolveLevels — department inheritance', () {
    test('nothing chosen → every level is general, nobody is the source', () {
      final r = resolveLevels([lv('1'), lv('2')]);
      expect(r.every((x) => x.isGeneral && x.inherited && x.sourceIndex == null), isTrue);
    });

    test('a custom level becomes the default of every higher level that inherits', () {
      final r = resolveLevels([lv('1', programs: 'general'), lv('2', programs: 'custom', ids: [5, 6]), lv('3'), lv('4')]);
      expect(r[0].isGeneral, isTrue);
      expect(r[1].programIds, [5, 6]);
      expect(r[1].inherited, isFalse);
      expect(r[2].programIds, [5, 6]);
      expect(r[2].inherited, isTrue);
      expect(r[2].sourceIndex, 1);
      expect(r[3].programIds, [5, 6]);
      expect(r[3].sourceIndex, 1);
    });

    test('editing a lower level reaches inheriting levels; an explicit override stops it', () {
      final levels = [lv('1', programs: 'custom', ids: [1]), lv('2'), lv('3', programs: 'general'), lv('4')];
      levels[0].programIds = [1, 2];
      final r = resolveLevels(levels);
      expect(r[1].programIds, [1, 2]);
      expect(r[2].isGeneral, isTrue);
      expect(r[3].isGeneral, isTrue);
      expect(r[3].sourceIndex, 2);
    });

    test('effective sets are copies (editing one never mutates another)', () {
      final r = resolveLevels([lv('1', programs: 'custom', ids: [1]), lv('2')]);
      r[1].programIds!.add(9);
      expect(r[0].programIds, [1]);
    });
  });

  group('LevelDraft', () {
    test('round trip keeps every field the server needs and drops summer courses when summer is off', () {
      final d = LevelDraft.fromJson({
        'key': '2',
        'label_en': 'Year 2',
        'programs': 'custom',
        'program_ids': [3],
        'prerequisites': [
          {'type': 'level_courses', 'params': {'percent': 100}}
        ],
        'terms': {'term1': [10], 'term2': [11], 'summer': [12]},
        'has_summer': false,
      });
      final j = d.toJson();
      expect(j['program_ids'], [3]);
      expect((j['terms'] as Map)['summer'], isEmpty);
      expect((j['prerequisites'] as List).single['type'], 'level_courses');
      d.programs = 'inherit';
      expect(d.toJson()['program_ids'], isEmpty);
    });

    test('nextKey picks the first free number', () {
      expect(LevelDraft.nextKey(['1', '2', '4']), '3');
      expect(LevelDraft.nextKey(const []), '1');
    });

    test('levelProblems: custom without departments, duplicate course, incomplete rule', () {
      final a = lv('1', programs: 'custom', ids: []);
      final b = lv('2')..terms['term1']!.add(1);
      b.terms['term2']!.add(1);
      final c = lv('3')..prerequisites.add(PrereqRule('min_courses', {'count': 0}));
      expect(levelProblems([a, b, c]).length, 3);
      expect(levelProblems([lv('1', programs: 'general')]), isEmpty);
    });
  });

  group('rules', () {
    test('validation mirrors the server', () {
      expect(PrereqRule('courses_passed', {'course_ids': [1, 2], 'min_count': 2}).isValid, isTrue);
      expect(PrereqRule('courses_passed', {'course_ids': [1], 'min_count': 2}).isValid, isFalse);
      expect(PrereqRule('courses_passed').isValid, isFalse);
      expect(PrereqRule('level_courses', {'percent': 0}).isValid, isFalse);
      expect(PrereqRule('min_hours', {'hours': 12.5}).isValid, isTrue);
      expect(PrereqRule('min_average', {'percent': 101}).isValid, isFalse);
      expect(PrereqRule('nope').isValid, isFalse);
    });

    test('results: progress, percent and text', () {
      final a = RuleResult.fromJson({'type': 'min_courses', 'params': {'count': 4}, 'met': false, 'have': 2, 'need': 4, 'unit': 'courses'});
      final b = RuleResult.fromJson({'type': 'min_average', 'params': {'percent': 70}, 'met': false, 'no_data': true, 'need': 70});
      final c = RuleResult.fromJson({'type': 'min_hours', 'params': {'hours': 10}, 'met': true, 'have': 12.5, 'need': 10});
      expect(a.progress, 0.5);
      expect(b.progress, 0);
      expect(c.progress, 1);
      expect(rulesPercent([a, b, c]), 50);
      expect(rulesPercent(const []), 0);
      expect(a.progressText, '2 / 4');
    });
  });
}
