// Exam notices (D-177): the core turns the engine's `exam.notify` into an in-app notification, an FCM push and the live
// event `exam_notice` (LiveEvents.examNotice). A tap lands here through AppNavigator (module `exam_notice`, or a push
// whose data has `type: exam_notice`). Kinds: appeal_created (→ the exam's managers: the appeals queue),
// appeal_decided and results_published (→ the student: their result), batch_done (scan batch finished) and
// mark_session_done (a grade-review session finished) — those two are hooks the agents who own those screens fill.
import 'package:flutter/material.dart';

import '../../admin/admin_common.dart' show asInt, asMap, t;
import 'exam_engine_api.dart';
import 'exam_insights_screen.dart' show ExamAppealsScreen;
import 'exam_result_screen.dart' show ExamResultScreen;
import 'exam_results_screen.dart' show ExamResultsScreen;
import 'marks/review/grade_review_entry.dart' show openMarkSessionFromNotice;
import 'paper/scan/omr_batch_notice.dart' as batch_notice;

/// What an `exam_notice` (push data, live event fields or a notification target) points at.
class ExamNotice {
  ExamNotice({required this.kind, this.examId, this.attemptId, this.sessionId, this.batchId, this.courseId, this.orgId, this.title = ''});
  final String kind;
  final int? examId;
  final int? attemptId;
  final int? sessionId;
  final int? batchId;
  final int? courseId;
  final int? orgId;
  final String title;

  /// Reads the fields flat or under `data` (the contract nests the ids in `data: {module, …ids}`).
  factory ExamNotice.parse(Map<String, dynamic> raw, {String? module}) {
    final inner = raw['data'] is Map ? asMap(raw['data']) : const <String, dynamic>{};
    dynamic pick(String k) => raw[k] ?? inner[k];
    int? n(String k) {
      final v = pick(k);
      return v == null ? null : int.tryParse('$v');
    }

    final mod = '${module ?? pick('module') ?? ''}';
    final kind = '${pick('kind') ?? ''}'.isNotEmpty
        ? '${pick('kind')}'
        : switch (mod) {
            'exam_appeal' || 'exam_appeals' => 'appeal',
            'exam_result' || 'exam_results' => 'results_published',
            'exam_batch' || 'omr_batch' => 'batch_done',
            'exam_mark_session' || 'mark_session' => 'mark_session_done',
            _ => '',
          };
    return ExamNotice(
      kind: kind,
      examId: n('exam_id') ?? n('target_id'),
      attemptId: n('attempt_id'),
      sessionId: n('session_id'),
      batchId: n('batch_id'),
      courseId: n('course_id'),
      orgId: n('org_id'),
      title: '${pick('exam_title') ?? pick('title') ?? ''}',
    );
  }
}

/// Where a notice leads, as a name the tests can check.
enum ExamNoticeTarget { appeals, studentResult, batchDone, markSession, none }

/// [teacher]: the legacy kind `appeal` (no created / decided) goes to the queue for a manager, the result for a student.
ExamNoticeTarget examNoticeTarget(ExamNotice n, {bool teacher = false}) {
  if (n.examId == null && n.kind != 'mark_session_done') return ExamNoticeTarget.none;
  return switch (n.kind) {
    'appeal_created' => ExamNoticeTarget.appeals,
    'appeal' => teacher ? ExamNoticeTarget.appeals : ExamNoticeTarget.studentResult,
    'appeal_decided' || 'results_published' => ExamNoticeTarget.studentResult,
    'batch_done' => ExamNoticeTarget.batchDone,
    'mark_session_done' => ExamNoticeTarget.markSession,
    _ => ExamNoticeTarget.none,
  };
}

/// The scan batch finished → the exam's scanned pages, where the batch and its issues list are.
Future<void> examNoticeBatchDone(NavigatorState nav, ExamNotice n) async =>
    batch_notice.examNoticeBatchDone(nav.context, {'exam_id': n.examId, 'title': n.title, if (n.batchId != null) 'batch_id': n.batchId});

/// A grade-review session finished → that session's three lists.
Future<void> examNoticeMarkSession(NavigatorState nav, ExamNotice n) async {
  if (n.sessionId != null) return openMarkSessionFromNotice(n.sessionId!);
  if (n.examId != null) return _openResults(nav, n);
  await nav.pushNamed('/notifications');
}

Future<void> _openResults(NavigatorState nav, ExamNotice n) async {
  await nav.push(MaterialPageRoute(
      settings: const RouteSettings(name: '/exam-results'),
      builder: (_) => ExamResultsScreen(examId: n.examId!, examTitle: n.title.isEmpty ? t('الاختبار', 'Exam') : n.title, courseId: n.courseId)));
}

/// The student's own result: by attempt when the notice names it, else the exam in their list (its latest result).
Future<void> _openStudentResult(NavigatorState nav, ExamNotice n, ExamEngineApi api) async {
  Map<String, dynamic>? result;
  var title = n.title;
  if (n.attemptId != null) {
    final r = await api.result(n.attemptId!);
    if (r.ok) result = r.map;
  }
  if (result == null) {
    final r = await api.studentExams(courseId: n.courseId, orgId: n.orgId);
    final list = r.ok ? (r.map['items'] ?? r.map['value'] ?? r.map['exams']) : null;
    for (final e in list is List ? list : const []) {
      if (e is Map && asInt(e['id']) == n.examId && e['results'] is List && (e['results'] as List).isNotEmpty) {
        result = asMap((e['results'] as List).last);
        if (title.isEmpty) title = '${e['title'] ?? ''}';
        break;
      }
    }
  }
  if (result == null) return; // nothing visible (held or unpublished): stay where the tap came from
  await nav.push(MaterialPageRoute(
      settings: const RouteSettings(name: '/exam-result'), builder: (_) => ExamResultScreen(result: result!, examTitle: title.isEmpty ? t('نتيجة الاختبار', 'Exam result') : title)));
}

/// Opens the screen a notice points at. Returns false when it names nothing this app can open (the caller falls back).
Future<bool> openExamNotice(NavigatorState nav, ExamNotice n, {bool teacher = false, ExamEngineApi? api}) async {
  switch (examNoticeTarget(n, teacher: teacher)) {
    case ExamNoticeTarget.appeals:
      await nav.push(MaterialPageRoute(
          settings: const RouteSettings(name: '/exam-appeals'),
          builder: (_) => ExamAppealsScreen(examId: n.examId!, examTitle: n.title.isEmpty ? t('الاختبار', 'Exam') : n.title)));
    case ExamNoticeTarget.studentResult:
      await _openStudentResult(nav, n, api ?? ExamEngineApi());
    case ExamNoticeTarget.batchDone:
      await examNoticeBatchDone(nav, n);
    case ExamNoticeTarget.markSession:
      await examNoticeMarkSession(nav, n);
    case ExamNoticeTarget.none:
      return false;
  }
  return true;
}
