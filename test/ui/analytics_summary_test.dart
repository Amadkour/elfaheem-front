// The pure half of the Analytics tabs (lib/features/shared/analytics/analytics_summary.dart): the headline figures and
// their class comparison, the ranking, the ONE sentence and the "For you" nudges (student and instructor), and the
// words they are written in (English fallback here: the tests do not load translation.json).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/analytics/analytics_summary.dart';
import 'package:flutter_test/flutter_test.dart';

AnCourseFacts course(
  int id, {
  double? p,
  double? a,
  double? e,
  double? cp,
  double? ca,
  double? ce,
  int attended = 0,
  int held = 0,
  int lectures = 0,
  int review = 0,
  int students = 0,
  int atRisk = 0,
  double? pass,
  int? shared,
}) =>
    AnCourseFacts(
      id: id,
      title: 'C$id',
      progress: p,
      attendance: a,
      exams: e,
      classProgress: cp,
      classAttendance: ca,
      classExams: ce,
      attended: attended,
      held: held,
      lectures: lectures,
      reviewFlags: review,
      students: students,
      atRisk: atRisk,
      passRate: pass,
      sharedMarks: shared,
    );

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('totals', () {
    test('each metric is averaged over the courses that have it', () {
      final t = anTotals([course(1, p: 40, a: 50, attended: 5, held: 10), course(2, p: 80, e: 70, attended: 3, held: 4)]);
      expect(t.progress, 60);
      expect(t.attendance, 50);
      expect(t.exams, 70);
      expect(t.overall, 60);
      expect((t.attended, t.held), (8, 14));
    });

    test('the class figure only counts when it covers the same courses as yours', () {
      final full = anTotals([course(1, p: 40, cp: 50), course(2, p: 80, cp: 60)]);
      expect(full.classProgress, 55);
      expect(full.delta(AnMetric.progress), 5);
      final partial = anTotals([course(1, p: 40, cp: 50), course(2, p: 80)]);
      expect(partial.classProgress, isNull);
      expect(partial.delta(AnMetric.progress), isNull);
    });

    test('no numbers → nulls, not zeros', () {
      final t = anTotals([course(1)]);
      expect(t.overall, isNull);
      expect(t.delta(AnMetric.exams), isNull);
    });
  });

  test('ranking: best first, unknown last in their order', () {
    final r = anRankBy([course(1, a: 50), course(2), course(3, a: 90), course(4)], AnMetric.attendance);
    expect([for (final c in r) c.id], [3, 1, 2, 4]);
    expect(anAvailableMetrics([course(1, p: 10), course(2, e: 30)]), [AnMetric.progress, AnMetric.exams]);
  });

  group('student headline', () {
    test('empty without any number', () {
      expect(studentHeadline([course(1)]).kind, AnHeadlineKind.empty);
      expect(anHeadlineText(studentHeadline([])), 'Your progress shows here as you learn.');
    });

    test('ahead of the class in n of m courses', () {
      final h = studentHeadline([
        course(1, p: 80, cp: 70),
        course(2, p: 40, cp: 60),
        course(3, p: 90, e: 50, cp: 80, ce: 55), // 70 vs 67.5 → ahead
      ]);
      expect((h.kind, h.n, h.m), (AnHeadlineKind.ahead, 2, 3));
      expect(anHeadlineText(h), "You're ahead of the class average in 2 of 3 courses.");
    });

    test('ahead everywhere, and the one-course wording', () {
      expect(studentHeadline([course(1, p: 80, cp: 70), course(2, e: 70, ce: 70)]).kind, AnHeadlineKind.aheadAll);
      expect(anHeadlineText(studentHeadline([course(1, p: 80, cp: 70)])), "You're ahead of the class average.");
    });

    test('behind everywhere → start with the course closest to the class', () {
      final h = studentHeadline([course(1, p: 20, cp: 70), course(2, p: 55, cp: 60)]);
      expect((h.kind, h.course), (AnHeadlineKind.catchUp, 'C2'));
    });

    test('without class figures: attention, great or steady', () {
      expect(studentHeadline([course(1, p: 90, a: 40)]).kind, AnHeadlineKind.attention);
      expect(studentHeadline([course(1, p: 90, a: 80)]).kind, AnHeadlineKind.great);
      expect(studentHeadline([course(1, p: 40)]).kind, AnHeadlineKind.steady);
    });
  });

  group('student insights', () {
    test('low attendance comes first, with the sessions in words', () {
      final i = studentInsights([course(1, a: 58, attended: 7, held: 12, p: 70)]);
      expect(i.first.kind, AnInsightKind.lowAttendance);
      expect(i.first.target, AnTarget.attendance);
      expect(anInsightText(i.first), 'You attended 7 of 12 sessions in C1. Join the next one to get back on track.');
    });

    test('low exams point at the saved questions when there are some', () {
      final withFlags = studentInsights([course(1, e: 41, review: 6)]).first;
      expect((withFlags.kind, withFlags.target), (AnInsightKind.lowExams, AnTarget.review));
      expect(anInsightText(withFlags), 'Your exam average in C1 is 41%. Go over the 6 questions you saved before the next exam.');
      final without = studentInsights([course(1, e: 41)]).first;
      expect(without.target, AnTarget.exams);
    });

    test('behind the class → how many lectures to catch up', () {
      final i = studentInsights([course(1, p: 40, cp: 61, lectures: 18)]).first;
      expect(i.kind, AnInsightKind.catchUp);
      expect(i.n, 4); // 21 points of 18 lectures = 3.78 → 4
      expect(anInsightText(i), 'Watch 4 lectures to catch up with your class in C1.');
      expect(anInsightText(const AnInsight(AnInsightKind.catchUp, AnTone.warn, course: 'X', n: 1)),
          'Watch 1 lecture to catch up with your class in X.');
    });

    test('at most three, one warning per course, one of each kind before a second', () {
      final i = studentInsights([
        course(1, a: 40, attended: 4, held: 10, e: 30),
        course(2, a: 50, attended: 5, held: 10),
        course(3, e: 35),
        course(4, p: 80, review: 9),
      ]);
      expect(i.length, 3);
      expect(i.where((x) => x.courseId == 1).length, 1);
      expect(i.map((x) => x.kind).toSet(), {AnInsightKind.lowAttendance, AnInsightKind.lowExams, AnInsightKind.reviewSaved});
    });

    test('the same kind fills the list when nothing else is to say', () {
      final i = studentInsights([course(1, a: 40, attended: 4, held: 10), course(2, a: 50, attended: 5, held: 10)]);
      expect([for (final x in i) x.courseId], [1, 2]); // the lowest first
    });

    test('praise when well above the class; "on track" when nothing else', () {
      final good = studentInsights([course(1, e: 92, ce: 76, p: 90, cp: 80)]);
      expect(good.single.kind, AnInsightKind.aheadOfClass);
      expect(anInsightText(good.single), 'Your exams in C1 are 16 points above the class average. Great work!');
      expect(studentInsights([course(1, p: 90, a: 90)]).single.kind, AnInsightKind.allGood);
      expect(studentInsights([course(1)]), isEmpty);
    });

    test('lectures left only when there is no class figure to compare with', () {
      expect(studentInsights([course(1, p: 30, lectures: 14)]).single.kind, AnInsightKind.lecturesLeft);
      expect(studentInsights([course(1, p: 30, lectures: 14)]).single.n, 10);
    });
  });

  group('instructor', () {
    test('headline: students at risk, on track, or nothing yet', () {
      final h = teacherHeadline([course(1, p: 60, atRisk: 5), course(2, p: 80, atRisk: 1)]);
      expect((h.kind, h.n), (AnHeadlineKind.teacherRisk, 6));
      expect(anHeadlineText(h), '6 students could use your attention this week.');
      expect(teacherHeadline([course(1, p: 80)]).kind, AnHeadlineKind.teacherOk);
      expect(teacherHeadline([course(1)]).kind, AnHeadlineKind.teacherEmpty);
    });

    test('insights: the most students at risk first, then one of each other kind (lowest figure first)', () {
      final i = teacherInsights([
        course(1, p: 58, a: 66, students: 64, atRisk: 5, pass: 72, shared: 2),
        course(2, p: 81, a: 89, students: 48, pass: 94, shared: 3),
        course(3, p: 64, a: 78, students: 37, atRisk: 3, pass: 46, shared: 0),
      ]);
      expect([for (final x in i) (x.kind, x.courseId)], [
        (AnInsightKind.studentsAtRisk, 1),
        (AnInsightKind.lowPassRate, 3),
        (AnInsightKind.classLowAttendance, 1),
      ]);
      expect(anInsightText(i.first), '5 students in C1 are under 60 % attendance or 50 % in exams.');
    });

    test('a calm term: marks not shared, then the strongest class', () {
      final i = teacherInsights([course(1, p: 88, a: 90, students: 30, pass: 95, shared: 0)]);
      expect([for (final x in i) x.kind], [AnInsightKind.noSharedMarks, AnInsightKind.strongestClass]);
      expect(anInsightText(i.last), 'C1 is your strongest class, at 88% progress.');
    });
  });

  group('Arabic words', () {
    setUp(() => AppConfig.lang = 'ar');

    test('dual and plural forms', () {
      expect(anLecturesWord(1), 'محاضرة واحدة');
      expect(anLecturesWord(2), 'محاضرتين');
      expect(anLecturesWord(5), '5 محاضرات');
      expect(anLecturesWord(12), '12 محاضرة');
      expect(anStudentsWord(9), '9 طلاب');
    });

    test('a figure in an Arabic sentence is isolated left-to-right', () {
      final s = anIsolate('47%');
      expect(s.codeUnits.first, 0x2066);
      expect(s.codeUnits.last, 0x2069);
      AppConfig.lang = 'en';
      expect(anIsolate('47%'), '47%');
    });
  });
}
