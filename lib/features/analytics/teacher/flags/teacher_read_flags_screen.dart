// features/analytics/teacher/flags/teacher_read_flags_screen.dart
//
// Teacher's read-flag bank for one course. The server only returns questions that
// cross the admin's thresholds (students who failed it × wrong tries per student).
//   GET /api/v1/teacher/courses/{courseId}/read-flags
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/features/exams/legacy/student/exam_tr.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_profile_screen.dart';

import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart';

// ── models ────────────────────────────────────────────────────────────────────

class TeacherFlagStudent {
  final int studentId;
  final String name;
  final int wrongCount;
  const TeacherFlagStudent(this.studentId, this.name, this.wrongCount);
}

class TeacherFlagItem {
  final int questionId;
  final int examId;
  final String examName;
  final String title;
  final List<String> options;
  final String? correctAnswer;
  final double marks;
  final int studentsFailed;
  final int studentsFlagged;
  final int maxWrongTries;
  final double avgWrongTries;
  final int totalWrong;
  final double score;
  final List<TeacherFlagStudent> students;

  const TeacherFlagItem({
    required this.questionId,
    required this.examId,
    required this.examName,
    required this.title,
    required this.options,
    this.correctAnswer,
    required this.marks,
    required this.studentsFailed,
    required this.studentsFlagged,
    required this.maxWrongTries,
    required this.avgWrongTries,
    required this.totalWrong,
    required this.score,
    required this.students,
  });

  factory TeacherFlagItem.fromJson(Map<String, dynamic> j) => TeacherFlagItem(
    questionId: (j['question_id'] as num).toInt(),
    examId: (j['exam_id'] as num?)?.toInt() ?? 0,
    examName: j['exam_name'] as String? ?? '',
    title: j['title'] as String? ?? '',
    options: (j['options'] as List? ?? []).map((o) => o.toString()).toList(),
    correctAnswer: j['correct_answer'] as String?,
    marks: (j['marks'] as num?)?.toDouble() ?? 0,
    studentsFailed: (j['students_failed'] as num?)?.toInt() ?? 0,
    studentsFlagged: (j['students_flagged'] as num?)?.toInt() ?? 0,
    maxWrongTries: (j['max_wrong_tries'] as num?)?.toInt() ?? 0,
    avgWrongTries: (j['avg_wrong_tries'] as num?)?.toDouble() ?? 0,
    totalWrong: (j['total_wrong'] as num?)?.toInt() ?? 0,
    score: (j['score'] as num?)?.toDouble() ?? 0,
    students: (j['students'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map((s) => TeacherFlagStudent(
      (s['student_id'] as num).toInt(),
      s['name'] as String? ?? '',
      (s['wrong_count'] as num?)?.toInt() ?? 0,
    ))
        .toList(),
  );
}

class TeacherFlagsApi {
  final ApiClient _api;
  TeacherFlagsApi({ApiClient? api}) : _api = api ?? ApiClient();

  Future<({int minStudents, int minTries, List<TeacherFlagItem> items})>
  fetch(int courseId) async {
    final d = await _api.get('/api/v1/teacher/courses/$courseId/read-flags')
    as Map<String, dynamic>;
    final th = (d['thresholds'] as Map?)?.cast<String, dynamic>() ?? {};
    return (
    minStudents: (th['min_students'] as num?)?.toInt() ?? 1,
    minTries: (th['min_wrong_tries'] as num?)?.toInt() ?? 1,
    items: (d['items'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(TeacherFlagItem.fromJson)
        .toList(),
    );
  }
}

// ── provider ──────────────────────────────────────────────────────────────────

class TeacherReadFlagsProvider extends ChangeNotifier {
  final TeacherFlagsApi _api;
  final int courseId;
  TeacherReadFlagsProvider({required this.courseId, TeacherFlagsApi? api})
      : _api = api ?? TeacherFlagsApi();

  bool loading = false;
  String? error;
  int minStudents = 1;
  int minTries = 1;
  List<TeacherFlagItem> items = [];

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final r = await _api.fetch(courseId);
      minStudents = r.minStudents;
      minTries = r.minTries;
      items = r.items;
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = apiErrorText(ApiException.from(e));
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

// ── screen ────────────────────────────────────────────────────────────────────

class TeacherReadFlagsScreen extends StatelessWidget {
  final int courseId;
  final String courseTitle;
  const TeacherReadFlagsScreen(
      {super.key, required this.courseId, required this.courseTitle});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => TeacherReadFlagsProvider(courseId: courseId)..load(),
    child: _View(courseTitle: courseTitle),
  );
}

class _View extends StatelessWidget {
  final String courseTitle;
  const _View({required this.courseTitle});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherReadFlagsProvider>();
    final failed = p.items.fold<int>(0, (s, i) => s + i.studentsFailed);
    final wrong = p.items.fold<int>(0, (s, i) => s + i.totalWrong);

    final List<Widget> body;
    if (p.loading) {
      body = [const AppListSkeleton()];
    } else if (p.error != null) {
      body = [AppCard(child: AppErrorState(message: p.error!, onRetry: p.load))];
    } else {
      body = [
        _ThresholdNote(text: tx('tflag_thresholds', {'students': p.minStudents, 'tries': p.minTries})),
        if (p.items.isEmpty) AppCard(child: AppEmpty(icon: Icons.task_alt_rounded, title: 'tflag_empty'.tr)),
        for (final it in p.items) _FlagCard(item: it),
      ];
    }

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: T2HeroPage(
        title: 't2_flags_title'.tr,
        width: AppWidth.reading,
        onRefresh: p.load,
        actions: [AppRefreshAction(onRefresh: p.load)],
        hero: AppHero(
          kicker: courseTitle,
          title: 't2_flags_hero'.tr,
          stats: p.loading || p.error != null
              ? const []
              : [
                  AppHeroStat(value: '${p.items.length}', label: 'tflag_btn'.tr),
                  AppHeroStat(value: '$failed', label: 'tflag_students'.tr),
                  AppHeroStat(value: '$wrong', label: 'flag_total_wrong'.tr),
                ],
        ),
        children: body,
      ),
    );
  }
}

/// When a question counts as hard (the server's thresholds), in one line.
class _ThresholdNote extends StatelessWidget {
  const _ThresholdNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppAreaScope.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: t.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.flag_outlined, size: AppIconSize.md, color: t.ink),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(text, style: AppType.label(context).copyWith(color: t.ink))),
      ]),
    );
  }
}

/// One hard question: the exam, the score (how many got it wrong), the question, the figures, the right answer and
/// the students who stumbled (each opens their analytics profile).
class _FlagCard extends StatelessWidget {
  final TeacherFlagItem item;
  const _FlagCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppStatusBadge(label: item.examName, tone: AppTone.brand, icon: Icons.quiz_outlined),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Flexible(
            flex: 2,
            child: Text(tx('flag_score', {'n': item.score.toStringAsFixed(1)}),
                textAlign: TextAlign.end, style: AppType.figure(context).copyWith(color: kit.error.ink)),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Text(item.title, textDirection: Helpers.textDirOf(item.title), style: AppType.tileTitle(context)),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppStatusBadge(label: tx('tflag_students_failed', {'n': item.studentsFailed}), tone: AppTone.danger, icon: Icons.groups_outlined),
          AppStatusBadge(label: tx('tflag_max_tries', {'n': item.maxWrongTries}), tone: AppTone.warning, icon: Icons.repeat_rounded),
          AppStatusBadge(
              label: tx('tflag_avg_tries', {'n': item.avgWrongTries.toStringAsFixed(1)}), tone: AppTone.neutral, icon: Icons.functions_rounded),
        ]),
        if (item.correctAnswer != null) ...[
          const SizedBox(height: AppSpace.sm),
          Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(color: kit.ok.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
            child: Row(children: [
              Icon(Icons.check_circle_outline_rounded, size: AppIconSize.md, color: kit.ok.ink),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text('${'flag_correct_answer'.tr}: ${item.correctAnswer}',
                    textDirection: Helpers.textDirOf(item.correctAnswer!),
                    style: AppType.label(context).copyWith(color: kit.ok.ink, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ],
        if (item.students.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          AppExpandCard(
            header: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                child: Row(children: [
                  Icon(Icons.groups_outlined, size: AppIconSize.md, color: AppAreaScope.of(context).ink),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: Text('t2_flags_show_students'.tr, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600))),
                ]),
              ),
            ),
            child: Column(children: [
              for (final s in item.students)
                InkWell(
                  borderRadius: AppRadius.controlAll,
                  // tap → the student's analytics profile
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudentAnalyticsProfileScreen.forTeacher(
                        studentId: s.studentId,
                        studentName: s.name,
                        courseId: context.read<TeacherReadFlagsProvider>().courseId,
                      ),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppTouch.min),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
                      child: Row(children: [
                        AppAvatar(name: s.name.isEmpty ? '?' : s.name, size: AppDashSize.ringSm - AppSpace.xs),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
                        Flexible(child: AppStatusBadge(label: tx('flag_wrong_times', {'n': s.wrongCount}), tone: AppTone.danger, dense: true)),
                        const SizedBox(width: AppSpace.xxs),
                        Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}
