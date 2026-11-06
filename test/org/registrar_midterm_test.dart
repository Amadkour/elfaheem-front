// Midterm marks (docs/advising/PHASE6.md "Midterm marks"): the roster parses (an older / partial answer too), and
// the PUT body carries only the changed, unlocked rows — an emptied field clears the mark, a value outside 0 – 100
// stops the save with `bad_percent`.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_registrar_midterm.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> sampleMidtermJson() => {
      'term': {'id': 7, 'kind': 'term1', 'year': '2026/2027'},
      'course': {'id': 12, 'code': 'CS101', 'name_ar': 'البرمجة 1', 'name_en': 'Programming I'},
      'items': [
        {
          'registration_id': 1,
          'student': {'id': 101, 'name': 'سارة أحمد'},
          'student_code': '2023001',
          'status': 'registered',
          'interim_percent': 45.5,
          'interim_at': '2026-11-01T09:30:00',
          'locked': false,
        },
        {
          'registration_id': 2,
          'student': {'id': 102, 'name': 'Omar Khaled'},
          'student_code': '2023002',
          'status': 'registered',
          'interim_percent': null,
          'interim_at': null,
          'locked': false,
        },
        {
          'registration_id': 3,
          'student': {'id': 103, 'name': 'Lina Hassan'},
          'student_code': null,
          'status': 'completed',
          'interim_percent': 80,
          'interim_at': '2026-10-20T08:00:00',
          'locked': true,
        },
      ],
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('the roster parses', () {
    final r = RegMidtermRoster.fromJson(sampleMidtermJson());
    expect(r.rows.length, 3);
    expect(r.courseTitle, 'CS101 · Programming I');
    final a = r.rows.first;
    expect(a.studentId, 101);
    expect(a.registrationId, 1);
    expect(a.code, '2023001');
    expect(a.percent, 45.5);
    expect(a.text, '45.5');
    expect(a.at, isNotNull);
    expect(r.rows[1].percent, isNull);
    expect(r.rows[1].text, '');
    expect(r.rows[2].locked, isTrue);
    expect(r.rows[2].text, '80');
    expect(r.rows[2].code, isNull);
    AppConfig.lang = 'ar';
    expect(r.courseTitle, 'CS101 · البرمجة 1');
  });

  test('an older or partial answer still parses', () {
    final r = RegMidtermRoster.fromJson({
      'items': [
        {'student': {'id': 5}},
        {'registration_id': 9},
      ],
    });
    expect(r.rows.length, 1);
    expect(r.rows.single.shown, '#5');
    expect(r.rows.single.locked, isFalse);
    expect(r.rows.single.percent, isNull);
    expect(r.courseTitle, '');
    expect(RegMidtermRoster.fromJson(const {}).rows, isEmpty);
  });

  test('only changed, unlocked rows are sent; an empty field clears the mark', () {
    final rows = RegMidtermRoster.fromJson(sampleMidtermJson()).rows;
    var e = regMidtermEdit(rows, {101: '45.5', 102: '', 103: '10'});
    expect(e.error, isNull);
    expect(e.items, isEmpty);

    e = regMidtermEdit(rows, {101: '', 102: '38', 103: '10'});
    expect(e.error, isNull);
    expect(e.items, [
      {'student_id': 101, 'interim_percent': null},
      {'student_id': 102, 'interim_percent': 38.0},
    ]);

    e = regMidtermEdit(rows, {101: ' 50,5 '});
    expect(e.items, [
      {'student_id': 101, 'interim_percent': 50.5},
    ]);
  });

  test('a value outside 0 – 100 or not a number stops the save', () {
    final rows = RegMidtermRoster.fromJson(sampleMidtermJson()).rows;
    expect(regMidtermEdit(rows, {102: '101'}).error, 'bad_percent');
    expect(regMidtermEdit(rows, {102: '-1'}).error, 'bad_percent');
    expect(regMidtermEdit(rows, {102: 'abc'}).error, 'bad_percent');
    expect(regMidtermEdit(rows, {102: '101'}).items, isEmpty);
    // a locked row is never checked nor sent
    expect(regMidtermEdit(rows, {103: '500'}).error, isNull);
  });

  test('mark text', () {
    expect(regMidtermText(null), '');
    expect(regMidtermText(40), '40');
    expect(regMidtermText(40.25), '40.25');
  });
}
