// course_students_logic.dart
//
// The pure half of a course's students page (D-870 – D-874): the filter and sort the server understands, the
// course-wide summary, a student's low-progress reason, the nudge's answer, and every sentence the page draws from
// them ("No activity for 12 days", "Active 3 h ago", "Nudged 3 h ago"). The RULE itself lives on the server
// (services/course_students_service.py `classify`); this file only words the verdict it sends.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

/// A server time (naive UTC, or with an offset) as a UTC instant; null when absent or unreadable.
DateTime? parseServerUtc(Object? raw) {
  final s = '${raw ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  final d = DateTime.tryParse(hasZone ? s : '${s}Z');
  return d?.toUtc();
}

/// The page's ONE filter (D-870).
enum StudentFilter {
  all('all'),
  active('active'),
  low('low'),
  inactive('inactive'),
  completed('completed');

  const StudentFilter(this.wire);
  final String wire;

  String get label => switch (this) {
        StudentFilter.all => t('الكل', 'All'),
        StudentFilter.active => t('نشطون', 'Active'),
        StudentFilter.low => t('تقدّم منخفض', 'Low progress'),
        StudentFilter.inactive => t('غير نشطين', 'Inactive'),
        StudentFilter.completed => t('أكملوا', 'Completed'),
      };
}

/// The page's sort (D-870): by name, by progress, by last activity.
enum StudentSort {
  name('name'),
  progress('progress'),
  progressAsc('progress_asc'),
  active('active'),
  activeAsc('active_asc');

  const StudentSort(this.wire);
  final String wire;

  String get label => switch (this) {
        StudentSort.name => t('الاسم', 'Name'),
        StudentSort.progress => t('الأعلى تقدّمًا', 'Most progress'),
        StudentSort.progressAsc => t('الأقل تقدّمًا', 'Least progress'),
        StudentSort.active => t('الأحدث نشاطًا', 'Recently active'),
        StudentSort.activeAsc => t('الأطول غيابًا', 'Longest inactive'),
      };
}

/// Why the server counts a student as low progress.
class StudentRisk {
  const StudentRisk({required this.code, this.days, this.expected, this.progress});

  /// never_started | no_activity | behind_pace | slow_start
  final String code;
  final int? days;
  final double? expected;
  final double? progress;

  factory StudentRisk.fromJson(Map<String, dynamic> j) => StudentRisk(
        code: '${j['code'] ?? ''}',
        days: (j['days'] as num?)?.toInt(),
        expected: (j['expected'] as num?)?.toDouble(),
        progress: (j['progress'] as num?)?.toDouble(),
      );
}

/// The reason in one short sentence: "No activity for 12 days", "Behind the plan: 20% of 60%", …
String riskText(StudentRisk r) {
  final n = r.days ?? 0;
  String days(int n) => countText(n,
      ar1: 'يوم واحد', ar2: 'يومين', arFew: '{n} أيام', arMany: '{n} يومًا', en1: '1 day', en: '{n} days');
  switch (r.code) {
    case 'no_activity':
      return t('لا نشاط منذ ${days(n)}', 'No activity for ${days(n)}');
    case 'never_started':
      return t('لم يبدأ بعد · مسجّل منذ ${days(n)}', 'Not started · enrolled ${days(n)} ago');
    case 'behind_pace':
      final p = (r.progress ?? 0).round(), e = (r.expected ?? 0).round();
      return t('متأخر عن الخطة: $p٪ من $e٪', 'Behind the plan: $p% of $e%');
    case 'slow_start':
      return t('بداية بطيئة · ${days(n)} منذ التسجيل', 'Slow start · ${days(n)} since enrolling');
  }
  return t('يحتاج متابعة', 'Needs attention');
}

/// "3 min ago" / "5 h ago" / "2 days ago" (the past only; a future instant reads "just now").
String agoText(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return t('الآن', 'just now');
  if (d.inMinutes < 60) {
    return countText(d.inMinutes,
        ar1: 'منذ دقيقة', ar2: 'منذ دقيقتين', arFew: 'منذ {n} دقائق', arMany: 'منذ {n} دقيقة', en1: '1 min ago', en: '{n} min ago');
  }
  if (d.inHours < 24) {
    return countText(d.inHours,
        ar1: 'منذ ساعة', ar2: 'منذ ساعتين', arFew: 'منذ {n} ساعات', arMany: 'منذ {n} ساعة', en1: '1 h ago', en: '{n} h ago');
  }
  return countText(d.inDays,
      ar1: 'منذ يوم', ar2: 'منذ يومين', arFew: 'منذ {n} أيام', arMany: 'منذ {n} يومًا', en1: '1 day ago', en: '{n} days ago');
}

/// "Active 3 h ago" / "Never active".
String lastActiveText(DateTime? at, DateTime now) =>
    at == null ? t('لم ينشط بعد', 'Never active') : t('آخر نشاط ${agoText(at, now)}', 'Active ${agoText(at, now)}');

/// "Nudged 3 h ago".
String nudgedText(DateTime at, DateTime now) => t('تم التذكير ${agoText(at, now)}', 'Nudged ${agoText(at, now)}');

/// "Lessons 12/30" (empty when the course has no lessons yet).
String lessonsText(int done, int total) => total <= 0 ? '' : t('الدروس $done/$total', 'Lessons $done/$total');

/// The friendly default message; the server fills `{name}` (first name) and `{course}` per student.
String nudgeTemplate([String? lang]) => (lang ?? AppConfig.lang) == 'ar'
    ? 'هلا {name}، لاحظت إنك فوّت كم درس في {course}. الدرس الجاي مهم وأبيك معنا، ولو فيه شي معطّلك كلمني.'
    : 'Hi {name}, we miss you in “{course}”! One small step today gets you back on track, and we\'re here to help.';

/// The message as one student reads it (the composer's preview).
String nudgePreview(String template, {required String name, required String course}) {
  final first = name.trim().split(RegExp(r'\s+')).first;
  return template.replaceAll('{name}', first).replaceAll('{course}', course);
}

/// The course-wide figures on top of the page.
class CourseStudentsSummary {
  const CourseStudentsSummary({
    this.enrolled = 0,
    this.activeWeek = 0,
    this.avgProgress = 0,
    this.atRisk = 0,
    this.completed = 0,
    this.lowNudgeable = 0,
    this.lowWithParent = 0,
  });

  final int enrolled;
  final int activeWeek;
  final double avgProgress;
  final int atRisk;
  final int completed;

  /// Low-progress students that may be nudged now (none in the last 24 h), and how many of them have a parent.
  final int lowNudgeable;
  final int lowWithParent;

  factory CourseStudentsSummary.fromJson(Map<String, dynamic> j) => CourseStudentsSummary(
        enrolled: (j['enrolled'] as num?)?.toInt() ?? 0,
        activeWeek: (j['active_week'] as num?)?.toInt() ?? 0,
        avgProgress: (j['avg_progress'] as num?)?.toDouble() ?? 0,
        atRisk: (j['at_risk'] as num?)?.toInt() ?? 0,
        completed: (j['completed'] as num?)?.toInt() ?? 0,
        lowNudgeable: (j['low_nudgeable'] as num?)?.toInt() ?? 0,
        lowWithParent: (j['low_with_parent'] as num?)?.toInt() ?? 0,
      );
}

/// One student the nudge did not reach, and why.
class NudgeSkip {
  const NudgeSkip(this.studentId, this.code, {this.nextAt});

  final int studentId;

  /// nudged_recently | not_enrolled
  final String code;
  final DateTime? nextAt;
}

/// The nudge's answer.
class NudgeResult {
  const NudgeResult({this.sent = 0, this.parents = 0, this.skipped = const [], this.nudgedAt});

  final int sent;
  final int parents;
  final List<NudgeSkip> skipped;
  final DateTime? nudgedAt;

  factory NudgeResult.fromJson(Map<String, dynamic> j) => NudgeResult(
        sent: (j['sent'] as num?)?.toInt() ?? 0,
        parents: (j['parents'] as num?)?.toInt() ?? 0,
        skipped: [
          for (final s in (j['skipped'] as List? ?? const []).whereType<Map>())
            NudgeSkip((s['student_id'] as num?)?.toInt() ?? 0, '${s['code'] ?? ''}', nextAt: parseServerUtc(s['next_at'])),
        ],
        nudgedAt: parseServerUtc(j['nudged_at']),
      );
}

/// "Reminder sent to 3 students · 2 parents told" (+ "1 was nudged in the last 24 h").
String nudgeResultText(NudgeResult r) {
  final students = countText(r.sent,
      ar1: 'طالب واحد', ar2: 'طالبين', arFew: '{n} طلاب', arMany: '{n} طالبًا', en1: '1 student', en: '{n} students');
  final parts = <String>[t('تم إرسال التذكير إلى $students', 'Nudge sent to $students')];
  if (r.parents > 0) {
    parts.add(countText(r.parents,
        ar1: 'وإلى ولي أمر واحد', ar2: 'وإلى وليّي أمر', arFew: 'وإلى {n} أولياء أمور', arMany: 'وإلى {n} ولي أمر',
        en1: '1 parent told', en: '{n} parents told'));
  }
  final recent = r.skipped.where((s) => s.code == 'nudged_recently').length;
  if (recent > 0) {
    parts.add(countText(recent,
        ar1: 'وتم تخطي طالب ذُكِّر خلال 24 ساعة', ar2: 'وتم تخطي طالبين ذُكِّرا خلال 24 ساعة',
        arFew: 'وتم تخطي {n} طلاب ذُكِّروا خلال 24 ساعة', arMany: 'وتم تخطي {n} طالبًا ذُكِّروا خلال 24 ساعة',
        en1: '1 skipped (nudged in the last 24 h)', en: '{n} skipped (nudged in the last 24 h)'));
  }
  return parts.join(AppConfig.lang == 'ar' ? ' ' : ' · ');
}
