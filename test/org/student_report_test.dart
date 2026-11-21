// Student lifecycle phase 7 (D-1400): the Students report's parser (shape of features/org/students/report.py build),
// its derived figures, the period rules (last 30 days, this term, this year, custom) and the export parameters.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/students/student_report_models.dart';
import 'package:flutter_education_app/features/org/students/student_report_page.dart' show studentsExportParams;
import 'package:flutter_education_app/features/org/students/students_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> countsJson({int total = 10, int attention = 2, int movements = 3}) => {
      'total': total,
      'enrolment': {'enrolled': 6, 'suspended': 1, 'postponed': 1, 'withdrawn': 1, 'graduated': 1, 'outside': 0},
      'standing': {'regular': 7, 'warning': 2, 'final_chance': 1, 'carrying': 0, 'repeating': 0},
      'flags': {'struggling': 1, 'conscripted': 2, 'affiliated': 0},
      'attention': attention,
      'movements': movements,
    };

Map<String, dynamic> reportJson() => {
      'from': '2026-10-22T00:00:00',
      'to': '2026-11-22T00:00:00',
      'generated_at': '2026-11-21T09:30:00',
      'at_to': countsJson(),
      'movements': {
        'total': 5,
        'by_dimension': {'enrolment': 3, 'standing': 1, 'flag': 1},
        'by_via': {'auto': 1, 'manual': 2, 'request': 1, 'undo': 1, 'system': 0},
        'by_decision': [
          {'key': 'suspend', 'count': 2, 'label_ar': 'إيقاف القيد', 'label_en': 'Suspend enrolment'},
          {'key': 'standing', 'count': 1, 'label_ar': 'standing', 'label_en': 'standing'},
          {'key': 'resume', 'count': 1},
        ],
      },
      'undone': 1,
      'top_reasons': [
        {'code': 'illness', 'count': 2},
        {'code': 'gpa', 'count': 1},
        {'code': '', 'count': 4},
      ],
      'pending': {
        'total': 2,
        'by_kind': {'student_status': 2},
        'by_decision': [{'key': 'final_chance', 'count': 2, 'label_ar': 'منح فرصة أخيرة', 'label_en': 'Grant a final chance'}],
      },
      'by_programme': [
        {'program': {'id': 3, 'code': 'CS', 'name_ar': 'علوم الحاسب', 'name_en': 'Computer science'}, ...countsJson(total: 7)},
        {'program': null, ...countsJson(total: 3, attention: 0)},
      ],
      'by_level': [
        {'level': '1', 'label_ar': 'المستوى الأول', 'label_en': 'First level', ...countsJson(total: 6)},
        {'level': null, 'label_ar': null, 'label_en': null, ...countsJson(total: 4)},
      ],
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('StudentReport.fromJson', () {
    test('reads every block', () {
      final r = StudentReport.fromJson(reportJson());
      expect(r.from, isNotNull);
      expect(r.to!.isAfter(r.from!), isTrue);
      expect(r.generatedAt, isNotNull);
      expect(r.atTo.total, 10);
      expect(r.atTo.attention, 2);
      expect(r.atTo.studying, 6);
      expect(r.atTo.paused, 2);
      expect(r.atTo.left, 2);
      expect(r.movementsTotal, 5);
      expect(r.byDimension['enrolment'], 3);
      expect(r.undone, 1);
      expect(r.pendingTotal, 2);
      expect(r.pendingByKind['student_status'], 2);
      expect(r.pendingByDecision.single.label, 'Grant a final chance');
      expect(r.isEmpty, isFalse);
    });

    test('vias in order, zero dropped', () {
      final r = StudentReport.fromJson(reportJson());
      expect([for (final v in r.vias) v.via], ['auto', 'manual', 'request', 'undo']);
      expect(reportViaLabel('manual'), 'By staff, by hand');
    });

    test('decision labels: server label, dimension fallback, app fallback', () {
      final d = StudentReport.fromJson(reportJson()).byDecision;
      expect(d[0].label, 'Suspend enrolment');
      expect(d[1].label, 'Standing change');
      expect(d[2].label, 'Resume enrolment');
      AppConfig.lang = 'ar';
      expect(d[0].label, 'إيقاف القيد');
    });

    test('reasons: empty codes skipped, bilingual labels', () {
      final r = StudentReport.fromJson(reportJson());
      expect([for (final x in r.topReasons) x.code], ['illness', 'gpa']);
      expect(reportReasonLabel('illness'), isNot('illness'));
      expect(reportReasonLabel('gpa'), isNot('gpa'));
    });

    test('groups: programme and level labels, the "none" rows', () {
      final r = StudentReport.fromJson(reportJson());
      expect(r.byProgramme.first.label('None'), 'Computer science');
      expect(r.byProgramme.first.code, 'CS');
      expect(r.byProgramme.first.counts.total, 7);
      expect(r.byProgramme.last.isNone, isTrue);
      expect(r.byProgramme.last.label('No programme'), 'No programme');
      expect(r.byLevel.first.label('x'), 'First level');
      expect(r.byLevel.last.label('No level'), 'No level');
    });

    test('lenient: an empty answer is an empty report', () {
      final r = StudentReport.fromJson(const {});
      expect(r.isEmpty, isTrue);
      expect(r.atTo.total, 0);
      expect(r.vias, isEmpty);
      expect(r.byProgramme, isEmpty);
      expect(StudentReport.fromJson(null).isEmpty, isTrue);
    });
  });

  test('reportBars: order, unknown keys last, zero dropped', () {
    final bars = reportBars({'warning': 2, 'regular': 7, 'mystery': 1, 'carrying': 0}, standings, standingLabel);
    expect([for (final b in bars) b.key], ['regular', 'warning', 'mystery']);
    expect(bars.first.label, 'Regular');
    expect(reportBars({'carrying': 0}, standings, standingLabel, keepZero: true).length, standings.length);
  });

  group('periods', () {
    final today = DateTime(2026, 11, 21);
    final terms = ReportTerm.listOf({
      'items': [
        {'id': 3, 'year_label': '2026/2027', 'kind': 'term1', 'label_ar': 'الفصل الأول', 'label_en': 'First term', 'start_date': '2026-09-20', 'end_date': '2027-01-20', 'status': 'current'},
        {'id': 4, 'year_label': '2026/2027', 'kind': 'term2', 'label_ar': 'الفصل الثاني', 'label_en': 'Second term', 'start_date': '2027-02-10', 'end_date': '2027-06-10', 'status': 'upcoming'},
        {'id': 2, 'year_label': '2025/2026', 'kind': 'term2', 'label_ar': 'الفصل الثاني', 'label_en': 'Second term', 'start_date': '2026-02-10', 'end_date': '2026-06-10', 'status': 'finished'},
        {'id': 9, 'year_label': 'bad', 'kind': 'summer', 'start_date': null, 'end_date': '2026-08-01'},
      ],
    });

    test('terms: rows without dates are dropped', () => expect(terms.length, 3));

    test('last 30 days', () {
      final p = last30Days(today);
      expect(p.toQuery(), {'from': '2026-10-22', 'to': '2026-11-21'});
    });

    test('this term: the running one, ending today at the latest', () {
      final p = termPeriod(terms, today)!;
      expect(p.kind, ReportPeriodKind.term);
      expect(p.toQuery(), {'from': '2026-09-20', 'to': '2026-11-21'});
      expect(p.termLabel, 'First term 2026/2027');
    });

    test('this term between terms: the latest that started', () {
      final p = termPeriod(terms, DateTime(2026, 8, 1))!;
      expect(p.toQuery(), {'from': '2026-02-10', 'to': '2026-06-10'});
    });

    test('no terms: no "this term"', () => expect(termPeriod(const [], today), isNull));

    test('this year: every term of the year label, clamped to today', () {
      final p = yearPeriod(terms, today);
      expect(p.toQuery(), {'from': '2026-09-20', 'to': '2026-11-21'});
      expect(p.termLabel, '2026/2027');
    });

    test('this year without terms: from 1 September', () {
      expect(yearPeriod(const [], today).toQuery(), {'from': '2026-09-01', 'to': '2026-11-21'});
      expect(yearPeriod(const [], DateTime(2027, 3, 5)).toQuery(), {'from': '2026-09-01', 'to': '2027-03-05'});
    });

    test('custom: dates put in order, never after today', () {
      final p = customPeriod(DateTime(2026, 12, 30), DateTime(2026, 10, 1), today);
      expect(p.toQuery(), {'from': '2026-10-01', 'to': '2026-11-21'});
      expect(p.kind, ReportPeriodKind.custom);
    });

    test('names in both languages', () {
      expect(reportPeriodName(ReportPeriodKind.term), 'This term');
      AppConfig.lang = 'ar';
      expect(reportPeriodName(ReportPeriodKind.term), 'هذا الفصل');
    });
  });

  test('export params: the list filters without paging, plus org and language', () {
    const q = StudentsQuery(q: ' sara ', enrol: 'suspended', programId: 4, sort: 'recent', page: 3, size: 50);
    final p = studentsExportParams(7, q);
    expect(p, {'org_id': 7, 'q': 'sara', 'enrol': 'suspended', 'program_id': 4, 'lang': 'en'});
  });
}
