// The pure half of "Get result" (Exam Hub, F5; back docs/exam_hub/CONTRACT.md 1.3 - 1.6): one board of any exam's results,
// merged from what the server already has, the words that say what publishing will do, the Data Lab and Excel previews,
// the export table and the calls. No widgets here (test/org/exam_hub_f5_test.dart).
//
// One student = one line, by the same rule the server writes to the Data Lab with (services/results_datalab.py): the LAST
// settled attempt when it is graded, else the imported total. So the numbers on the screen are the numbers that get written.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_table_export.dart' show AppColType, AppExportColumn, AppStatusTone, AppTableExport, AppTotal;

import '../../../../admin/admin_common.dart' show asDouble, asInt, asMap, asMapList, t;
import '../../exam_authoring.dart';
import '../../exam_engine_api.dart';
import '../../exam_insights.dart';
import '../../exam_quick.dart' show ResultRow;
import '../../paper/review/omr_review.dart';

const kResultsDataLabKey = 'exam.results.datalab';
const kResultsImportKey = 'exam.results.import';
const kResultsStudioKey = 'export.studio';

enum ResultState { graded, open }

/// One student's mark of one question (a paper exam's `?include=questions`).
class ResultQuestionMark {
  const ResultQuestionMark(this.n, this.score, this.max);
  final int n;
  final double? score;
  final double max;
}

class ResultEntry {
  const ResultEntry({
    required this.key,
    required this.name,
    required this.state,
    this.attemptId,
    this.studentId,
    this.score,
    this.maxScore,
    this.percent,
    this.passed,
    this.imported = false,
    this.form = '',
    this.questions = const [],
  });

  final String key;
  final String name;
  final ResultState state;
  final int? attemptId, studentId;
  final double? score, maxScore, percent;
  final bool? passed;

  /// The total came from an Excel sheet (no attempt behind it).
  final bool imported;
  final String form;
  final List<ResultQuestionMark> questions;

  bool get graded => state == ResultState.graded && percent != null;
  bool get open => state == ResultState.open;
}

/// A question most students missed.
class HardQuestion {
  const HardQuestion({required this.n, required this.share, this.prompt = '', this.wrong, this.wrongCount = 0, this.isMeanMark = false});
  final int n;

  /// 0-100: the share who got it right, or the mean mark ([isMeanMark], the analysis snapshot of an online exam).
  final double share;
  final bool isMeanMark;
  final String prompt;
  final String? wrong;
  final int wrongCount;
}

class ResultStats {
  ResultStats(this.entries, {this.openScanItems = 0, this.inProgress = 0});
  final List<ResultEntry> entries;
  final int openScanItems, inProgress;

  late final List<ResultEntry> gradedEntries = [for (final e in entries) if (e.graded) e];
  int get students => entries.length;
  int get graded => gradedEntries.length;
  int get openStudents => entries.where((e) => e.open).length;
  bool get empty => entries.isEmpty;
  bool get partial => openStudents > 0 || openScanItems > 0;

  Iterable<double> get _p => gradedEntries.map((e) => e.percent!);
  double? get average => graded == 0 ? null : _p.reduce((a, b) => a + b) / graded;
  double? get highest => graded == 0 ? null : _p.reduce((a, b) => a > b ? a : b);
  double? get lowest => graded == 0 ? null : _p.reduce((a, b) => a < b ? a : b);

  int get passed => gradedEntries.where((e) => e.passed == true).length;
  int get failed => gradedEntries.where((e) => e.passed == false).length;

  /// null when no result says passed or failed.
  double? get passRate => passed + failed == 0 ? null : passed * 100 / (passed + failed);

  /// Ten bins, 0-9 ... 90-100.
  List<({int from, int to, int count})> get bins {
    final c = List<int>.filled(10, 0);
    for (final p in _p) {
      c[(p.clamp(0, 100) ~/ 10).clamp(0, 9)]++;
    }
    return [for (var i = 0; i < 10; i++) (from: i * 10, to: i == 9 ? 100 : i * 10 + 9, count: c[i])];
  }
}

/// What the Data Lab tile can be.
enum LabAccess { hidden, ready, noCourse, anonymous }

LabAccess labAccessOf({required bool hubServer, required Iterable<String> disabled, required int? courseId, required bool anonymous}) {
  if (!hubServer || disabled.contains(kResultsDataLabKey)) return LabAccess.hidden;
  if (courseId == null || courseId <= 0) return LabAccess.noCourse;
  return anonymous ? LabAccess.anonymous : LabAccess.ready;
}

class ResultsBoard {
  ResultsBoard({
    required this.examId,
    required this.title,
    required this.stats,
    this.courseId,
    this.anonymous = false,
    this.status = '',
    this.resultsPolicy = 'when_published',
    this.publishedAt,
    this.parentsTold = false,
    this.dataLabColumn,
    this.isPaper = false,
    this.hubServer = true,
    this.hardest = const [],
    this.omr,
    this.questionCount = 0,
    this.passingPercent = 50,
  });

  final int examId;
  final String title;
  final int? courseId;
  final bool anonymous;
  final String status;
  final String resultsPolicy;
  final DateTime? publishedAt;
  final bool parentsTold;

  /// The key of the column last written (`settings.data_lab_column`).
  final String? dataLabColumn;

  /// A paper exam (sections on paper, or a paper format): correction means scanning.
  final bool isPaper;

  /// false: a server without the Exam Hub routes; those tiles hide.
  final bool hubServer;
  final ResultStats stats;
  final List<HardQuestion> hardest;

  /// The per-question detail of a scanned exam, when there is one.
  final OmrResults? omr;
  final int questionCount;
  final double passingPercent;

  bool get published => publishedAt != null;
  bool get publishable => resultsPolicy == 'when_published' && status != 'draft';
  bool get hasAttempts => stats.entries.any((e) => !e.imported);
  bool get onlyImported => stats.entries.isNotEmpty && !hasAttempts;
  int get visibleOnPublish => stats.gradedEntries.where((e) => !e.imported).length;
  int get heldOnPublish => stats.entries.where((e) => e.open).length;

  /// A short word for where the marks came from.
  String get sourceLabel {
    if (onlyImported) return t('درجات مستوردة من Excel', 'Totals from Excel');
    if (isPaper) return t('اختبار ورقي', 'Paper exam');
    return t('اختبار عبر الإنترنت', 'Online exam');
  }

  factory ResultsBoard.fromSources({
    required Map<String, dynamic> exam,
    Map<String, dynamic>? attempts,
    Map<String, dynamic>? omr,
    Map<String, dynamic>? degrees,
    Map<String, dynamic>? analytics,
    Map<int, String> names = const {},
    bool hubServer = true,
  }) {
    final view = ExamView.fromJson(exam);
    final d = view.exam;
    final settings = asMap(exam['settings']);
    final o = omr == null || asMapList(omr['students']).isEmpty && asMapList(omr['questions']).isEmpty ? null : OmrResults.fromJson(omr);
    final omrBy = {for (final s in o?.students ?? const <OmrStudentResult>[]) s.attemptId: s};
    final perQuestion = <int, List<ResultQuestionMark>>{
      for (final x in asMapList(omr?['students']))
        if (x['questions'] is List)
          asInt(x['attempt_id']): [
            for (final q in asMapList(x['questions'])) ResultQuestionMark(asInt(q['n']), q['score'] == null ? null : asDouble(q['score']), asDouble(q['max'])),
          ],
    };

    final rows = attempts == null ? const <ResultRow>[] : ResultRow.fromAttempts(attempts, names);
    final latest = <Object, ResultRow>{};
    for (final r in rows) {
      if (!r.finished) continue;
      final k = r.studentId ?? 'a${r.attemptId}';
      final cur = latest[k];
      if (cur == null || r.attemptId > cur.attemptId) latest[k] = r;
    }

    final byKey = <Object, ResultEntry>{};
    final heldKeys = <Object>{};
    latest.forEach((k, r) {
      final s = omrBy[r.attemptId];
      final held = r.needsReview || (s?.openReview ?? 0) > 0;
      if (held) heldKeys.add(k);
      final pct = r.percentage ?? _pct(r.score, r.maxScore);
      byKey[k] = ResultEntry(
        key: 'a${r.attemptId}',
        attemptId: r.attemptId,
        studentId: r.studentId,
        name: (s?.name ?? '').trim().isNotEmpty || (s?.studentCode ?? '').isNotEmpty ? s!.who : r.name,
        state: r.state == 'graded' && !held && r.score != null ? ResultState.graded : ResultState.open,
        score: r.score,
        maxScore: r.maxScore,
        percent: pct,
        passed: r.passed,
        form: s?.formText == '—' ? '' : (s?.formText ?? ''),
        questions: perQuestion[r.attemptId] ?? const [],
      );
    });

    for (final x in asMapList(degrees?['items'])) {
      final sid = asInt(x['student_id']);
      final cur = byKey[sid];
      if (cur != null && (cur.state == ResultState.graded || heldKeys.contains(sid))) continue; // an attempt still being marked is not replaced
      final score = x['score'] == null ? null : asDouble(x['score']);
      final max = x['max_score'] == null ? null : asDouble(x['max_score']);
      final pct = _pct(score, max);
      final given = '${x['name'] ?? ''}'.trim();
      byKey[sid] = ResultEntry(
        key: 's$sid',
        studentId: sid,
        name: given.isNotEmpty ? given : (names[sid] ?? t('طالب #$sid', 'Student #$sid')),
        state: score == null ? ResultState.open : ResultState.graded,
        score: score,
        maxScore: max,
        percent: pct,
        passed: pct == null ? null : pct >= d.passingPercent,
        imported: true,
      );
    }

    final entries = byKey.values.toList()
      ..sort((a, b) => a.open != b.open ? (a.open ? -1 : 1) : a.name.compareTo(b.name));

    return ResultsBoard(
      examId: asInt(exam['id']),
      title: d.title,
      courseId: d.courseId,
      anonymous: d.anonymousGrading,
      status: d.status,
      resultsPolicy: d.resultsPolicy,
      publishedAt: d.resultsPublishedAt,
      parentsTold: settings['notify_parents'] == true,
      dataLabColumn: settings['data_lab_column']?.toString(),
      isPaper: view.sections.any((s) => s.section.mode == 'paper') || settings['paper_format'] != null,
      hubServer: hubServer,
      stats: ResultStats(entries, openScanItems: o?.openReviewItems ?? 0, inProgress: rows.where((r) => r.state == 'in_progress').length),
      hardest: hardestQuestions(view, o, analytics == null ? null : ExamAnalytics.fromJson(analytics)),
      omr: o,
      questionCount: view.questionCount,
      passingPercent: d.passingPercent,
    );
  }
}

double? _pct(double? score, double? max) => score == null || max == null || max <= 0 ? null : score * 100 / max;

/// Up to three questions with the lowest share right; the scanned exam's live numbers first, else the analysis snapshot.
List<HardQuestion> hardestQuestions(ExamView view, OmrResults? omr, ExamAnalytics? analytics) {
  final placed = [for (final s in view.sections) ...s.questions];
  String prompt(int id) => placed.firstWhereOrNull((q) => q.questionId == id)?.prompt ?? '';
  final out = <HardQuestion>[
    for (final q in omr?.questions ?? const <OmrQuestionStat>[])
      if (q.scored > 0 && q.difficulty != null)
        HardQuestion(n: q.n, share: q.difficulty! * 100, prompt: prompt(q.questionId), wrong: q.mostChosenWrong, wrongCount: q.mostChosenWrongCount),
  ];
  if (out.isEmpty) {
    for (final it in analytics?.items ?? const <ItemStat>[]) {
      if (it.answered <= 0 || it.difficulty == null || it.voided) continue;
      final i = placed.indexWhere((q) => q.questionId == it.questionId);
      if (i >= 0) out.add(HardQuestion(n: i + 1, share: it.difficulty! * 100, prompt: placed[i].prompt, isMeanMark: true));
    }
  }
  out.sort((a, b) => a.share.compareTo(b.share));
  return out.where((q) => q.share < 100).take(3).toList();
}

extension _FirstWhere<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final x in this) {
      if (test(x)) return x;
    }
    return null;
  }
}

// ── what publishing will do ─────────────────────────────────────────────────────────────────────────────────────────

String resultStudentsText(int n) => countText(n, ar1: 'طالب واحد', ar2: 'طالبان', arFew: '{n} طلاب', arMany: '{n} طالبًا', en1: '1 student', en: '{n} students');

/// "3 students are still being marked".
String resultStillOpenText(int students, int scanItems) {
  final parts = <String>[
    if (students > 0)
      countText(students,
          ar1: 'طالب واحد لم يكتمل تصحيحه',
          ar2: 'طالبان لم يكتمل تصحيحهما',
          arFew: '{n} طلاب لم يكتمل تصحيحهم',
          arMany: '{n} طالبًا لم يكتمل تصحيحهم',
          en1: '1 student is not fully marked yet',
          en: '{n} students are not fully marked yet'),
    if (scanItems > 0)
      countText(scanItems,
          ar1: 'عنصر واحد من الأوراق ينتظر قرارك',
          ar2: 'عنصران من الأوراق ينتظران قرارك',
          arFew: '{n} عناصر من الأوراق تنتظر قرارك',
          arMany: '{n} عنصرًا من الأوراق ينتظر قرارك',
          en1: '1 scanned item waits for your decision',
          en: '{n} scanned items wait for your decision'),
  ];
  return parts.join(t(' · ', ' · '));
}

class PublishPlan {
  const PublishPlan({required this.text, this.button, this.note});

  /// In one or two sentences: what happens when the button is pressed, or how things stand.
  final String text;

  /// null = there is nothing to press.
  final String? button;

  /// A plain limit worth saying (imported totals, a policy that is not "when published").
  final String? note;
}

PublishPlan publishPlanOf(ResultsBoard b, {required bool students, required bool parents}) {
  final canParents = b.hubServer;
  if (b.onlyImported) {
    return PublishPlan(
      text: t('الدرجات المستوردة لا تظهر في نتائج الاختبار عند الطلاب.', 'Imported totals do not appear in the students\' exam results.'),
      note: t('لتصل إلى الطلاب وأولياء الأمور، اكتبها في عمود من Data Lab واجعل العمود ظاهرًا لهم.', 'To reach students and parents, write them to a Data Lab column and make that column visible to them.'),
    );
  }
  if (!b.publishable) {
    return PublishPlan(
      text: switch (b.resultsPolicy) {
        'after_submit' => t('يرى كل طالب نتيجته تلقائيًا بعد التسليم، فلا حاجة إلى نشر.', 'Each student sees their result right after submitting, so there is nothing to publish.'),
        'hidden' => t('النتائج مخفية عن الطلاب في إعدادات هذا الاختبار.', 'This exam\'s settings hide the results from students.'),
        _ => b.status == 'draft' ? t('انشر الاختبار أولًا.', 'Publish the exam first.') : resultsPolicyLabel(b.resultsPolicy),
      },
    );
  }
  final held = b.heldOnPublish;
  final heldText = held == 0
      ? ''
      : ' ${countText(held, ar1: 'والطالب الذي لم يكتمل تصحيحه تبقى نتيجته مخفية حتى تُصحَّح.', ar2: 'والطالبان اللذان لم يكتمل تصحيحهما تبقى نتيجتاهما مخفيتين حتى تُصحَّحا.', arFew: 'والـ {n} طلاب الذين لم يكتمل تصحيحهم تبقى نتائجهم مخفية حتى تُصحَّح.', arMany: 'والـ {n} طالبًا الذين لم يكتمل تصحيحهم تبقى نتائجهم مخفية حتى تُصحَّح.', en1: 'The 1 student not fully marked stays hidden until marked.', en: 'The {n} students not fully marked stay hidden until marked.')}';
  if (b.published) {
    if (parents && !b.parentsTold && canParents) {
      return PublishPlan(
          text: t('يصل إشعار واحد إلى أولياء أمور الطلاب الذين تظهر لهم النتيجة الآن، ثم إلى من تظهر نتيجته لاحقًا.', 'The parents of every student who can see a result now get one notice, and the rest as their results appear.'),
          button: t('إبلاغ أولياء الأمور', 'Tell the parents'));
    }
    return PublishPlan(text: t('تظهر النتائج للطلاب. أي تصحيح يكتمل لاحقًا يظهر من تلقاء نفسه.', 'Students can see the results. Anything marked later appears by itself.'));
  }
  if (!students) {
    return PublishPlan(text: t('شغّل «الطلاب» لتنشر النتائج. يُبلَّغ أولياء الأمور فقط عندما تظهر النتيجة لأبنائهم.', 'Turn on Students to publish. Parents are told only once their child can see the result.'));
  }
  final seen = countText(b.visibleOnPublish,
      ar1: 'سيرى طالب واحد نتيجته، ولا يرى نتائج غيره.',
      ar2: 'سيرى طالبان نتيجتيهما، ولا يرى أحد نتائج غيره.',
      arFew: 'سيرى {n} طلاب نتائجهم، ولا يرى أحد نتائج غيره.',
      arMany: 'سيرى {n} طالبًا نتائجهم، ولا يرى أحد نتائج غيره.',
      en1: '1 student will see their own result, and nobody else\'s.',
      en: '{n} students will each see their own result, and nobody else\'s.');
  final parentText = !canParents
      ? ''
      : (parents ? ' ${t('ويصل إشعار إلى أولياء أمورهم.', 'Their parents get a notice.')}' : ' ${t('لن يصل إشعار إلى أولياء الأمور.', 'Parents get no notice.')}');
  return PublishPlan(text: '$seen$heldText$parentText', button: held > 0 ? t('نشر المصحّح…', 'Publish what is graded…') : t('نشر النتائج', 'Publish results'));
}

// ── Data Lab ────────────────────────────────────────────────────────────────────────────────────────────────────────

class LabColumnChoice {
  const LabColumnChoice(this.key, this.label, this.max);
  final String key, label;
  final double max;
}

class LabChange {
  const LabChange(this.name, this.oldValue, this.newValue);
  final String name;
  final double? oldValue, newValue;
}

class LabPreviewData {
  const LabPreviewData({
    required this.label,
    required this.max,
    this.key,
    this.scale = 1,
    this.matched = 0,
    this.changes = const [],
    this.unchanged = 0,
    this.held = 0,
    this.unmatched = const [],
  });

  /// null: a column still to create.
  final String? key;
  final String label;
  final double? max;
  final double scale;
  final int matched, unchanged, held;
  final List<LabChange> changes;
  final List<String> unmatched;

  int get overwrites => changes.where((c) => c.oldValue != null).length;
  bool get scaled => (scale - 1).abs() > 1e-4;

  /// The exam's own full mark, worked back from the column's and the scale.
  double? get examMax => max == null || scale <= 0 ? null : max! / scale;

  factory LabPreviewData.fromJson(Map<String, dynamic> j) {
    final c = asMap(j['column']);
    final ar = '${c['label_ar'] ?? ''}'.trim(), en = '${c['label_en'] ?? ''}'.trim();
    return LabPreviewData(
      key: c['key']?.toString(),
      label: t(ar.isNotEmpty ? ar : en, en.isNotEmpty ? en : ar),
      max: c['max'] == null ? null : asDouble(c['max']),
      scale: j['scale'] == null ? 1 : asDouble(j['scale']),
      matched: asInt(j['matched']),
      unchanged: asInt(j['unchanged']),
      held: asInt(j['held']),
      changes: [
        for (final x in asMapList(j['changes']))
          LabChange(_who(x), x['old'] == null ? null : asDouble(x['old']), x['new'] == null ? null : asDouble(x['new'])),
      ],
      unmatched: [for (final x in asMapList(j['unmatched'])) _who(x)],
    );
  }
}

String _who(Map<String, dynamic> x) {
  final n = '${x['name'] ?? ''}'.trim();
  return n.isNotEmpty ? n : t('طالب #${asInt(x['student_id'])}', 'Student #${asInt(x['student_id'])}');
}

/// The body of preview and apply: exactly one of [columnKey] and a new column.
Map<String, dynamic> labBody({String? columnKey, String? newLabel, double? newMax, double? roundingStep}) => {
      if (columnKey != null) 'column_key': columnKey else 'new_column': {'label_ar': newLabel, 'label_en': newLabel, 'max': newMax},
      'rounding_step': ?roundingStep,
    };

/// The column offered first: the one last written, else one named like the exam, else null (a new column is best).
String? labDefaultColumn(List<LabColumnChoice> columns, {String? lastWritten, String title = ''}) {
  if (columns.any((c) => c.key == lastWritten)) return lastWritten;
  final want = title.trim().toLowerCase();
  if (want.isEmpty) return null;
  for (final c in columns) {
    if (c.label.trim().toLowerCase() == want) return c.key;
  }
  return null;
}

// ── totals from Excel ───────────────────────────────────────────────────────────────────────────────────────────────

// ── server errors in plain words ────────────────────────────────────────────────────────────────────────────────────

String resultErrorText(EngineResult r) {
  final mapped = switch (r.code) {
    'no_course' => t('هذا الاختبار غير مرتبط بمقرر، فلا يوجد Data Lab يُكتب فيه', 'This exam is not linked to a course, so there is no Data Lab to write to'),
    'anonymous_exam' => t('هذا الاختبار مصحَّح بلا أسماء، فلا يمكن كتابة نتائجه باسم كل طالب', 'This exam is marked anonymously, so its results cannot be written by name'),
    'column_locked' => t('هذا العمود مقفل. افتحه من Data Lab أو اختر عمودًا آخر', 'This column is locked. Unlock it in Data Lab or choose another one'),
    'column_not_found' => t('لم يعد هذا العمود موجودًا', 'This column no longer exists'),
    'column_required' => t('اختر عمودًا أو أنشئ عمودًا جديدًا', 'Choose a column or create a new one'),
    'column_label_required' => t('اكتب اسم العمود', 'Enter the column\'s name'),
    'rounding_step_invalid' => t('خطوة التقريب غير صالحة', 'The rounding step is not valid'),
    'feature_disabled' => t('هذه الميزة غير مفعّلة حاليًا', 'This feature is switched off right now'),
    _ => '',
  };
  if (mapped.isNotEmpty) return mapped;
  final en = r.detail['message_en'];
  if (AppConfig.lang == 'en' && en != null && '$en'.isNotEmpty) return '$en';
  return authoringError(r);
}

// ── export ──────────────────────────────────────────────────────────────────────────────────────────────────────────

/// Beyond this many questions the per-question columns start unticked: a page cannot hold them all.
const kExportQuestionsVisible = 20;

/// The results table, with a column per question when the server gave them. Call inside `bilingualExport(() => …)`.
AppTableExport examHubResultsExport(ResultsBoard b) {
  final s = b.stats;
  final numbers = <int>{for (final e in s.entries) for (final q in e.questions) q.n}.toList()..sort();
  final maxOf = <int, double>{for (final e in s.entries) for (final q in e.questions) q.n: q.max};
  final hasForms = s.entries.any((e) => e.form.isNotEmpty);
  String status(ResultEntry e) => e.open ? 'open' : (e.passed == true ? 'passed' : (e.passed == false ? 'failed' : 'graded'));
  return AppTableExport(
    id: 'exam.hub.results',
    title: b.title.isEmpty ? t('نتائج الاختبار', 'Exam results') : b.title,
    fileName: b.title.isEmpty ? t('نتائج الاختبار', 'Exam results') : b.title,
    subtitle: b.sourceLabel,
    meta: [
      t('الطلاب: ${s.students} · مصحّح: ${s.graded}', 'Students: ${s.students} · graded: ${s.graded}'),
      if (s.average != null) t('المتوسط: ${omrNum(s.average)}%', 'Average: ${omrNum(s.average)}%'),
      if (s.passRate != null) t('نسبة النجاح: ${omrNum(s.passRate)}%', 'Pass rate: ${omrNum(s.passRate)}%'),
    ],
    columns: [
      AppExportColumn('student', b.anonymous ? t('الرمز', 'Code') : t('الطالب', 'Student'), locked: true),
      if (hasForms) AppExportColumn('form', t('النموذج', 'Form')),
      AppExportColumn('score', t('الدرجة', 'Score'), type: AppColType.number, decimals: 2),
      AppExportColumn('max', t('من', 'Out of'), type: AppColType.number, decimals: 2),
      AppExportColumn('percentage', t('النسبة', 'Percent'), type: AppColType.percent, total: AppTotal.average),
      AppExportColumn('status', t('الحالة', 'Status'), type: AppColType.status, statusLabels: {
        'passed': t('ناجح', 'Passed'),
        'failed': t('لم ينجح', 'Not passed'),
        'open': t('قيد التصحيح', 'Being marked'),
        'graded': t('مصحّح', 'Graded'),
      }, statusTones: const {
        'passed': AppStatusTone.good,
        'failed': AppStatusTone.bad,
        'open': AppStatusTone.warn,
        'graded': AppStatusTone.neutral,
      }),
      for (final n in numbers)
        AppExportColumn('q$n', t('س$n (${omrNum(maxOf[n])})', 'Q$n (${omrNum(maxOf[n])})'), type: AppColType.number, decimals: 2, visible: numbers.length <= kExportQuestionsVisible),
    ],
    rows: [
      for (final e in s.entries)
        {
          'student': e.name,
          if (hasForms) 'form': e.form,
          'score': e.score,
          'max': e.maxScore,
          'percentage': e.percent,
          'status': status(e),
          for (final q in e.questions) 'q${q.n}': q.score,
        },
    ],
  );
}

// ── calls ───────────────────────────────────────────────────────────────────────────────────────────────────────────

class ResultsHubApi {
  ResultsHubApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = ExamEngineApi.base;

  Future<EngineResult> exam(int id) => engineCall(() => _api.get('$base/exams/$id'));
  Future<EngineResult> attempts(int id) => engineCall(() => _api.get('$base/exams/$id/attempts'));
  Future<EngineResult> omrResults(int id) => engineCall(() => _api.get('$base/exams/$id/omr/results', queryParams: {'include': 'questions'}));
  Future<EngineResult> degrees(int id) => engineCall(() => _api.get('$base/exams/$id/degrees'));
  Future<EngineResult> analytics(int id) => engineCall(() => _api.get('$base/exams/$id/analytics'));
  Future<EngineResult> courseStudents(int courseId) => engineCall(() => _api.get('/api/v1/courses/$courseId/students'));

  /// [notifyParents]: also on an exam already published (the server tells only the parents nobody told yet).
  Future<EngineResult> publish(int id, {bool gradedOnly = false, bool notifyParents = false}) => engineCall(
      () => _api.post('$base/exams/$id/results/publish', body: {if (gradedOnly) 'graded_only': true, if (notifyParents) 'notify_parents': true}));
  Future<EngineResult> unpublish(int id) => engineCall(() => _api.post('$base/exams/$id/results/unpublish'));

  Future<EngineResult> labPreview(int id, Map<String, dynamic> body) => engineCall(() => _api.post('$base/exams/$id/results/data-lab/preview', body: body));
  Future<EngineResult> labApply(int id, Map<String, dynamic> body) => engineCall(() => _api.post('$base/exams/$id/results/data-lab/apply', body: body));
}
