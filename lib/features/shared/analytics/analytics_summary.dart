// lib/features/shared/analytics/analytics_summary.dart
// The pure half of the Analytics tabs (student and instructor): what the page SAYS, computed from the numbers the
// screens already load (no request of its own).
//
//   AnCourseFacts        one course as plain numbers (yours or the class's), 0–100, null = not known
//   anTotals             the page's three headline figures + the class's, averaged over the courses that have them
//   anRankBy             the courses ordered by one metric (best first, unknown last)
//   studentHeadline /    the ONE sentence under the rings ("You're ahead of the class average in 3 of 5 courses.")
//     teacherHeadline
//   studentInsights /    up to three plain-language nudges, most useful first ("Watch 3 lectures to catch up with
//     teacherInsights    your class in Computer Networks.") — each names the course it is about, so the UI can open it
//   anInsightText /      the sentences in the open language (translation.json, English fallback)
//     anHeadlineText
//
// No dates exist in these payloads (the Data Lab profile and the class overview are snapshots), so the page compares
// with the CLASS, never with a previous period. Tests: test/ui/analytics_summary_test.dart.
library;

import 'package:flutter_education_app/config/app_config.dart';

import 'analytics_ui.dart' show anFmt, anPct;

enum AnMetric { progress, attendance, exams }

/// One course, as numbers. Student page: your numbers + the class averages the teacher shares. Instructor page:
/// the class numbers (no class comparison) + students / at-risk / pass rate.
class AnCourseFacts {
  const AnCourseFacts({
    required this.id,
    required this.title,
    this.subtitle,
    this.progress,
    this.attendance,
    this.exams,
    this.classProgress,
    this.classAttendance,
    this.classExams,
    this.attended = 0,
    this.held = 0,
    this.lectures = 0,
    this.reviewFlags = 0,
    this.students = 0,
    this.atRisk = 0,
    this.passRate,
    this.sharedMarks,
  });

  final int id;
  final String title;
  final String? subtitle;
  final double? progress, attendance, exams;
  final double? classProgress, classAttendance, classExams;
  final int attended, held, lectures, reviewFlags;

  // instructor
  final int students, atRisk;
  final double? passRate;

  /// Marks shared with the students (null = unknown / Data Lab off for the course).
  final int? sharedMarks;

  double? value(AnMetric m) => switch (m) {
        AnMetric.progress => progress,
        AnMetric.attendance => attendance,
        AnMetric.exams => exams,
      };

  double? classValue(AnMetric m) => switch (m) {
        AnMetric.progress => classProgress,
        AnMetric.attendance => classAttendance,
        AnMetric.exams => classExams,
      };

  /// Average of the metrics that exist.
  double? get overall => anMean([progress, attendance, exams]);

  /// Your average and the class's over the metrics where BOTH are known (null when none is).
  (double, double)? get versusClass {
    final mine = <double>[], cls = <double>[];
    for (final m in AnMetric.values) {
      final a = value(m), b = classValue(m);
      if (a != null && b != null) {
        mine.add(a);
        cls.add(b);
      }
    }
    if (mine.isEmpty) return null;
    return (anMean(mine)!, anMean(cls)!);
  }
}

double? anMean(Iterable<double?> xs) {
  final v = xs.whereType<double>().toList();
  return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
}

/// The page's headline figures: each metric averaged over the courses that have it, and the class's over the same
/// courses (so "+6 vs class" compares like with like).
class AnTotals {
  const AnTotals({
    this.progress,
    this.attendance,
    this.exams,
    this.classProgress,
    this.classAttendance,
    this.classExams,
    this.attended = 0,
    this.held = 0,
  });

  final double? progress, attendance, exams;
  final double? classProgress, classAttendance, classExams;
  final int attended, held;

  double? value(AnMetric m) => switch (m) {
        AnMetric.progress => progress,
        AnMetric.attendance => attendance,
        AnMetric.exams => exams,
      };

  /// You minus the class, in points (null when either side is unknown).
  double? delta(AnMetric m) {
    final a = value(m);
    final b = switch (m) {
      AnMetric.progress => classProgress,
      AnMetric.attendance => classAttendance,
      AnMetric.exams => classExams,
    };
    return a == null || b == null ? null : a - b;
  }

  double? get overall => anMean([progress, attendance, exams]);
}

AnTotals anTotals(List<AnCourseFacts> courses) {
  double? mine(AnMetric m) => anMean(courses.map((c) => c.value(m)));
  double? cls(AnMetric m) {
    final pairs = courses.where((c) => c.value(m) != null && c.classValue(m) != null).toList();
    // the class figure counts only when it covers the same courses as yours
    if (pairs.isEmpty || pairs.length != courses.where((c) => c.value(m) != null).length) return null;
    return anMean(pairs.map((c) => c.classValue(m)));
  }

  return AnTotals(
    progress: mine(AnMetric.progress),
    attendance: mine(AnMetric.attendance),
    exams: mine(AnMetric.exams),
    classProgress: cls(AnMetric.progress),
    classAttendance: cls(AnMetric.attendance),
    classExams: cls(AnMetric.exams),
    attended: courses.fold(0, (s, c) => s + c.attended),
    held: courses.fold(0, (s, c) => s + c.held),
  );
}

/// Best first; courses without the metric keep their order at the end.
List<AnCourseFacts> anRankBy(List<AnCourseFacts> courses, AnMetric m) {
  final known = courses.where((c) => c.value(m) != null).toList()..sort((a, b) => b.value(m)!.compareTo(a.value(m)!));
  return [...known, ...courses.where((c) => c.value(m) == null)];
}

/// The metrics at least one course has (the chart's segments).
List<AnMetric> anAvailableMetrics(List<AnCourseFacts> courses) =>
    [for (final m in AnMetric.values) if (courses.any((c) => c.value(m) != null)) m];

// ─────────────────────────────────────────────────────────────────────────────
// Thresholds (the same as the server's "needs attention": attendance < 60 %, exams < 50 %)
// ─────────────────────────────────────────────────────────────────────────────

const double kAnLowAttendance = 60;
const double kAnLowExams = 50;

/// Points behind the class before "catch up" is worth saying.
const double kAnBehindClass = 10;

/// Points ahead of the class before it is worth a "great work".
const double kAnAheadOfClass = 8;

// ─────────────────────────────────────────────────────────────────────────────
// Headline
// ─────────────────────────────────────────────────────────────────────────────

enum AnHeadlineKind { empty, aheadAll, ahead, catchUp, attention, great, steady, teacherRisk, teacherOk, teacherSteady, teacherEmpty }

class AnHeadline {
  const AnHeadline(this.kind, {this.n = 0, this.m = 0, this.course});
  final AnHeadlineKind kind;
  final int n, m;
  final String? course;

  @override
  String toString() => 'AnHeadline($kind, n: $n, m: $m, course: $course)';
}

AnHeadline studentHeadline(List<AnCourseFacts> courses) {
  final withNumbers = courses.where((c) => c.overall != null).toList();
  if (withNumbers.isEmpty) return const AnHeadline(AnHeadlineKind.empty);
  final compared = [for (final c in courses) if (c.versusClass != null) (c, c.versusClass!)];
  if (compared.isNotEmpty) {
    // compared as shown (whole points): level with the class ("±0") is neither ahead nor behind (M5)
    final ahead = compared.where((x) => x.$2.$1.round() > x.$2.$2.round()).length;
    final behind = compared.where((x) => x.$2.$1.round() < x.$2.$2.round()).toList();
    if (ahead == compared.length) return AnHeadline(AnHeadlineKind.aheadAll, n: ahead, m: compared.length);
    if (ahead > 0) return AnHeadline(AnHeadlineKind.ahead, n: ahead, m: compared.length);
    if (behind.isNotEmpty) {
      behind.sort((a, b) => (a.$2.$2 - a.$2.$1).compareTo(b.$2.$2 - b.$2.$1));
      // behind: point at the course that is closest to the class (the quickest win)
      return AnHeadline(AnHeadlineKind.catchUp, course: behind.first.$1.title);
    }
    // level with the class everywhere: say what the numbers themselves say
  }
  final attention = courses.where(anCourseNeedsAttention).length;
  if (attention > 0) return AnHeadline(AnHeadlineKind.attention, n: attention, m: courses.length);
  final overall = anMean(withNumbers.map((c) => c.overall));
  return AnHeadline(overall != null && overall >= 75 ? AnHeadlineKind.great : AnHeadlineKind.steady);
}

/// A figure the students actually made: an attendance or exam number, or progress above zero (0 % progress with
/// nothing else is "nobody started yet", not a result).
bool anHasRealData(AnCourseFacts c) => c.attendance != null || c.exams != null || (c.progress ?? 0) > 0;

/// The overall figure that earns praise for a class.
const double kAnClassGood = 70;

AnHeadline teacherHeadline(List<AnCourseFacts> courses) {
  final risk = courses.fold<int>(0, (s, c) => s + c.atRisk);
  if (risk > 0) return AnHeadline(AnHeadlineKind.teacherRisk, n: risk);
  // N4: no praise over "0 %" and "–": praise only real, good numbers; anything else is a neutral line
  final real = courses.where(anHasRealData).toList();
  if (real.isEmpty) return const AnHeadline(AnHeadlineKind.teacherEmpty);
  final overall = anMean(real.map((c) => c.overall));
  return AnHeadline(overall != null && overall >= kAnClassGood ? AnHeadlineKind.teacherOk : AnHeadlineKind.teacherSteady);
}

bool anCourseNeedsAttention(AnCourseFacts c) =>
    (c.attendance != null && c.attendance! < kAnLowAttendance) || (c.exams != null && c.exams! < kAnLowExams);

// ─────────────────────────────────────────────────────────────────────────────
// Insights
// ─────────────────────────────────────────────────────────────────────────────

enum AnInsightKind {
  // student
  lowAttendance,
  lowExams,
  catchUp,
  lecturesLeft,
  reviewSaved,
  aheadOfClass,
  allGood,
  // instructor
  studentsAtRisk,
  classLowAttendance,
  lowPassRate,
  noSharedMarks,
  strongestClass,
}

enum AnTone { warn, info, good }

/// Where an insight's action goes (the screen decides how).
enum AnTarget { course, attendance, exams, review, dataLab, none }

class AnInsight {
  const AnInsight(this.kind, this.tone, {this.courseId, this.course = '', this.n = 0, this.m = 0, this.value, this.target = AnTarget.course});

  final AnInsightKind kind;
  final AnTone tone;
  final int? courseId;
  final String course;
  final int n, m;
  final double? value;
  final AnTarget target;

  @override
  String toString() => 'AnInsight($kind, $course, n: $n, m: $m, value: $value)';
}

/// The first [max] of [ranked], one of each kind before a second of any (three "low attendance" lines read as a
/// list of failures; three different nudges read as advice), in the ranked order.
List<AnInsight> anPickInsights(List<AnInsight> ranked, int max) {
  final seen = <AnInsightKind>{};
  final first = <AnInsight>[], rest = <AnInsight>[];
  for (final i in ranked) {
    (seen.add(i.kind) ? first : rest).add(i);
  }
  final picked = [...first, ...rest].take(max).toSet();
  return [for (final i in ranked) if (picked.contains(i)) i];
}

/// Up to [max] nudges for a student, warnings first, at most one warning per course (the most useful one), then
/// the encouraging ones. Never empty when there is any number: "Everything is on track" closes the list.
List<AnInsight> studentInsights(List<AnCourseFacts> courses, {int max = 3}) {
  final warn = <AnInsight>[], info = <AnInsight>[], good = <AnInsight>[];
  for (final c in courses) {
    // one warning per course, the strongest first: attendance, exams, then lagging behind the class
    if (c.attendance != null && c.attendance! < kAnLowAttendance && c.held > 0) {
      warn.add(AnInsight(AnInsightKind.lowAttendance, AnTone.warn,
          courseId: c.id, course: c.title, n: c.attended, m: c.held, value: c.attendance, target: AnTarget.attendance));
    } else if (c.exams != null && c.exams! < kAnLowExams) {
      warn.add(AnInsight(AnInsightKind.lowExams, AnTone.warn,
          courseId: c.id,
          course: c.title,
          value: c.exams,
          n: c.reviewFlags,
          target: c.reviewFlags > 0 ? AnTarget.review : AnTarget.exams));
    } else if (c.progress != null && c.classProgress != null && c.lectures > 0 && c.classProgress! - c.progress! >= kAnBehindClass) {
      final n = ((c.classProgress! - c.progress!) / 100 * c.lectures).ceil();
      if (n > 0) warn.add(AnInsight(AnInsightKind.catchUp, AnTone.warn, courseId: c.id, course: c.title, n: n, value: c.progress));
    }
    if (c.reviewFlags > 0 && !(c.exams != null && c.exams! < kAnLowExams)) {
      info.add(AnInsight(AnInsightKind.reviewSaved, AnTone.info,
          courseId: c.id, course: c.title, n: c.reviewFlags, target: AnTarget.review));
    }
    if (c.progress != null && c.progress! < 50 && c.lectures > 0 && c.classProgress == null) {
      final left = c.lectures - (c.progress! / 100 * c.lectures).round();
      if (left > 0) {
        info.add(AnInsight(AnInsightKind.lecturesLeft, AnTone.info, courseId: c.id, course: c.title, n: left, value: c.progress));
      }
    }
    final ex = c.exams, cls = c.classExams;
    if (ex != null && cls != null && ex - cls >= kAnAheadOfClass) {
      good.add(AnInsight(AnInsightKind.aheadOfClass, AnTone.good,
          courseId: c.id, course: c.title, n: (ex - cls).round(), value: ex, target: AnTarget.exams));
    }
  }
  int byValue(AnInsight a, AnInsight b) => (a.value ?? 100).compareTo(b.value ?? 100);
  warn.sort(byValue);
  info.sort((a, b) => b.n.compareTo(a.n));
  good.sort((a, b) => b.n.compareTo(a.n));
  final out = anPickInsights([...warn, ...info, ...good], max);
  if (out.isEmpty && courses.any((c) => c.overall != null)) {
    out.add(const AnInsight(AnInsightKind.allGood, AnTone.good, target: AnTarget.none));
  }
  return out;
}

/// Up to [max] nudges for an instructor: students at risk, weak attendance, a low pass rate, marks not shared yet,
/// then the strongest class.
List<AnInsight> teacherInsights(List<AnCourseFacts> courses, {int max = 3}) {
  final warn = <AnInsight>[], info = <AnInsight>[], good = <AnInsight>[];
  for (final c in courses) {
    if (c.atRisk > 0) {
      warn.add(AnInsight(AnInsightKind.studentsAtRisk, AnTone.warn,
          courseId: c.id, course: c.title, n: c.atRisk, value: c.atRisk.toDouble(), target: AnTarget.course));
    }
    if (c.attendance != null && c.attendance! < 70) {
      warn.add(AnInsight(AnInsightKind.classLowAttendance, AnTone.warn,
          courseId: c.id, course: c.title, value: c.attendance, target: AnTarget.attendance));
    }
    if (c.passRate != null && c.passRate! < 60) {
      warn.add(AnInsight(AnInsightKind.lowPassRate, AnTone.warn,
          courseId: c.id, course: c.title, value: c.passRate, target: AnTarget.exams));
    }
    if (c.sharedMarks == 0 && c.students > 0) {
      info.add(AnInsight(AnInsightKind.noSharedMarks, AnTone.info, courseId: c.id, course: c.title, target: AnTarget.dataLab));
    }
  }
  final ranked = courses.where((c) => c.progress != null && c.progress! >= 75).toList()
    ..sort((a, b) => b.progress!.compareTo(a.progress!));
  if (ranked.isNotEmpty) {
    final b = ranked.first;
    good.add(AnInsight(AnInsightKind.strongestClass, AnTone.good, courseId: b.id, course: b.title, value: b.progress));
  }
  // most students at risk first, then the lowest figure
  warn.sort((a, b) {
    final ra = a.kind == AnInsightKind.studentsAtRisk ? 0 : 1, rb = b.kind == AnInsightKind.studentsAtRisk ? 0 : 1;
    if (ra != rb) return ra.compareTo(rb);
    return ra == 0 ? b.n.compareTo(a.n) : (a.value ?? 100).compareTo(b.value ?? 100);
  });
  final out = anPickInsights([...warn, ...info, ...good], max);
  if (out.isEmpty && courses.any((c) => anHasRealData(c) && (c.overall ?? 0) >= kAnClassGood)) {
    out.add(const AnInsight(AnInsightKind.allGood, AnTone.good, target: AnTarget.none));
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Words
// ─────────────────────────────────────────────────────────────────────────────

bool get _ar => AppConfig.lang == 'ar';

/// "1 lecture" · "3 lectures" / "محاضرة واحدة" · "محاضرتين" · "3 محاضرات" · "11 محاضرة".
String anCountWord(int n, {required String en, required String enPlural, required String arOne, required String arTwo, required String arFew, required String arMany}) {
  if (!_ar) return n == 1 ? '1 $en' : '$n $enPlural';
  if (n == 1) return arOne;
  if (n == 2) return arTwo;
  // L2: zero takes the plural ("0 طلاب"), not the accusative singular ("0 طالبًا")
  if (n == 0 || (n % 100 >= 3 && n % 100 <= 10)) return '$n $arFew';
  return '$n $arMany';
}

String anLecturesWord(int n) =>
    anCountWord(n, en: 'lecture', enPlural: 'lectures', arOne: 'محاضرة واحدة', arTwo: 'محاضرتين', arFew: 'محاضرات', arMany: 'محاضرة');

String anStudentsWord(int n) =>
    anCountWord(n, en: 'student', enPlural: 'students', arOne: 'طالب واحد', arTwo: 'طالبان', arFew: 'طلاب', arMany: 'طالبًا');

String anSessionsWord(int n) =>
    anCountWord(n, en: 'session', enPlural: 'sessions', arOne: 'جلسة واحدة', arTwo: 'جلستان', arFew: 'جلسات', arMany: 'جلسة');

/// "1 course" / "مقرر واحد" · "4 مقررات" (the profile hero's pill read "1 المقررات").
String anCoursesCount(int n) =>
    anCountWord(n, en: 'course', enPlural: 'courses', arOne: 'مقرر واحد', arTwo: 'مقرران', arFew: 'مقررات', arMany: 'مقررًا');

String anExamsWord(int n) =>
    anCountWord(n, en: 'exam', enPlural: 'exams', arOne: 'اختبار واحد', arTwo: 'اختباران', arFew: 'اختبارات', arMany: 'اختبارًا');

String anQuestionsWord(int n) =>
    anCountWord(n, en: 'question', enPlural: 'questions', arOne: 'سؤال واحد', arTwo: 'سؤالان', arFew: 'أسئلة', arMany: 'سؤالًا');

/// A figure inside an Arabic sentence, isolated left-to-right (LRI … PDI) so "47%" never reads "%47".
String anIsolate(String s) => _ar ? '${String.fromCharCode(0x2066)}$s${String.fromCharCode(0x2069)}' : s;

String anInsightText(AnInsight i) {
  final p = <String, Object?>{'course': i.course, 'pct': anIsolate(anPct(i.value)), 'a': i.n, 'h': i.m};
  switch (i.kind) {
    case AnInsightKind.lowAttendance:
      return anFmt('an2_ins_low_att', {...p, 'sessions': anSessionsWord(i.m)},
          'You attended {a} of {sessions} in {course}. Join the next one to get back on track.');
    case AnInsightKind.lowExams:
      return i.n > 0
          ? anFmt('an2_ins_low_exams_review', {...p, 'questions': anQuestionsWord(i.n)},
              'Your exam average in {course} is {pct}. Go over the {questions} you saved before the next exam.')
          : anFmt('an2_ins_low_exams', p, 'Your exam average in {course} is {pct}. A short review before the next exam will help.');
    case AnInsightKind.catchUp:
      return anFmt('an2_ins_catch_up', {...p, 'lectures': anLecturesWord(i.n)}, 'Watch {lectures} to catch up with your class in {course}.');
    case AnInsightKind.lecturesLeft:
      return anFmt('an2_ins_left', {...p, 'lectures': anLecturesWord(i.n)}, '{lectures} left in {course}. A little every day gets you there.');
    case AnInsightKind.reviewSaved:
      return anFmt('an2_ins_review', {...p, 'questions': anQuestionsWord(i.n)}, 'You saved {questions} to review in {course}.');
    case AnInsightKind.aheadOfClass:
      return anFmt('an2_ins_ahead', p, 'Your exams in {course} are {a} points above the class average. Great work!');
    case AnInsightKind.allGood:
      return anFmt('an2_ins_all_good', p, 'Everything is on track. Keep it up!');
    case AnInsightKind.studentsAtRisk:
      return anFmt('an2_tins_at_risk', {...p, 'students': anStudentsWord(i.n)},
          '{students} in {course} are under 60 % attendance or 50 % in exams.');
    case AnInsightKind.classLowAttendance:
      return anFmt('an2_tins_low_att', p, 'Attendance in {course} is {pct}. A reminder before the next session may help.');
    case AnInsightKind.lowPassRate:
      return anFmt('an2_tins_pass', p, 'Only {pct} of students pass the exams in {course}. A review session could help.');
    case AnInsightKind.noSharedMarks:
      return anFmt('an2_tins_no_marks', p, 'No marks are shared with the students of {course} yet.');
    case AnInsightKind.strongestClass:
      return anFmt('an2_tins_best', p, '{course} is your strongest class, at {pct} progress.');
  }
}

String anHeadlineText(AnHeadline h) {
  final p = <String, Object?>{'n': h.n, 'm': h.m, 'course': h.course ?? ''};
  return switch (h.kind) {
    AnHeadlineKind.empty => anFmt('an2_head_empty', p, 'Your progress shows here as you learn.'),
    AnHeadlineKind.aheadAll => h.m == 1
        ? anFmt('an2_head_ahead_one', p, "You're ahead of the class average.")
        : anFmt('an2_head_ahead_all', p, "You're ahead of the class average in all {m} courses."),
    AnHeadlineKind.ahead => anFmt('an2_head_ahead', p, "You're ahead of the class average in {n} of {m} courses."),
    AnHeadlineKind.catchUp => anFmt('an2_head_catch_up', p, "You're catching up. {course} is the best place to start."),
    AnHeadlineKind.attention => anFmt('an_attention', p, '{n} of your courses could use a little extra attention.'),
    AnHeadlineKind.great => anFmt('an2_head_great', p, "You're doing great. Every course is on track."),
    AnHeadlineKind.steady => anFmt('an2_head_steady', p, 'Steady progress. Small steps every day add up.'),
    AnHeadlineKind.teacherRisk => anFmt('an2_thead_risk', {'students': anStudentsWord(h.n)}, '{students} could use your attention this week.'),
    AnHeadlineKind.teacherOk => anFmt('ta_hero_ok', p, 'Every class is on track — nice work!'),
    AnHeadlineKind.teacherSteady => anFmt('an2_thead_steady', p, 'Your classes are under way. The figures below show where they stand.'),
    AnHeadlineKind.teacherEmpty => anFmt('an2_thead_empty', p, 'Class numbers appear once your students start learning.'),
  };
}
