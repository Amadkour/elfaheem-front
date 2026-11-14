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
import 'package:flutter_education_app/features/exams/legacy/student/exam_ui.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_profile_screen.dart';

import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppHeader, AppListSkeleton, AppWidth;
import 'package:flutter_education_app/features/analytics/teacher/teacher_stat_band.dart';

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

  Widget _hero(BuildContext context, TeacherReadFlagsProvider p) {
    final failed = p.items.fold<int>(0, (s, i) => s + i.studentsFailed);
    final wrong = p.items.fold<int>(0, (s, i) => s + i.totalWrong);
    return TeacherStatBand(
      color: context.colors.danger,
      stats: [
        HeroStat(
          icon: Icons.flag_rounded,
          color: context.colors.accent,
          value: '${p.items.length}',
          label: 'tflag_btn'.tr,
        ),
        HeroStat(
          icon: Icons.groups_rounded,
          color: context.colors.heroTint(context.colors.primaryLight, 0.5),
          value: '$failed',
          label: 'tflag_students'.tr,
        ),
        HeroStat(
          icon: Icons.close_rounded,
          color: context.colors.danger,
          value: '$wrong',
          label: 'flag_total_wrong'.tr,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.watch<TeacherReadFlagsProvider>();

    final Widget body;
    if (p.loading) {
      body = Column(children: [
        _hero(context, p),
        const Expanded(child: AppListSkeleton()),
      ]);
    } else if (p.error != null) {
      body = Column(children: [
        _hero(context, p),
        Expanded(
          child: ExamError(
              message: p.error!, retryLabel: 'retry'.tr, onRetry: p.load),
        ),
      ]);
    } else {
      body = AppRefresh(
        onRefresh: p.load,
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          children: [
            _hero(context, p),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(children: [
                ExamBanner(
                  icon: Icons.flag_rounded,
                  color: c.primary,
                  text: tx('tflag_thresholds', {
                    'students': p.minStudents,
                    'tries': p.minTries,
                  }),
                ),
                const SizedBox(height: 16),
                if (p.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: ExamEmpty(
                        icon: Icons.task_alt_rounded, text: 'tflag_empty'.tr),
                  ),
                for (final it in p.items) ...[
                  _FlagCard(item: it),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
          ],
        ),
      );
    }

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(
        useWebCard: true,
        width: AppWidth.wide,
        appBar: AppHeader(
          title: courseTitle,
          subtitle: 'tflag_btn_sub'.tr,
          color: context.colors.danger,
          actions: [
            IconButton(
              tooltip: 'refresh'.tr,
              onPressed: p.load,
              icon: Icon(Icons.refresh_rounded, color: context.colors.primary),
            ),
          ],
        ),
        child: body,
      ),
    );
  }
}

class _FlagCard extends StatelessWidget {
  final TeacherFlagItem item;
  const _FlagCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExamCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.quiz_rounded, size: 12, color: c.primary),
              const SizedBox(width: 5),
              Text(item.examName,
                  style: examT(11, w: FontWeight.w700, c: c.primary)),
            ]),
          ),
          const Spacer(),
          ExamBadge(tx('flag_score', {'n': item.score.toStringAsFixed(1)}), c.warning),
        ]),
        const SizedBox(height: 12),
        Text(item.title,
            textDirection: Helpers.textDirOf(item.title),
            style: examT(15, w: FontWeight.w700, c: c.textDark, h: 1.7)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ExamChip(Icons.groups_rounded,
              tx('tflag_students_failed', {'n': item.studentsFailed}), c.danger),
          ExamChip(Icons.repeat_rounded,
              tx('tflag_max_tries', {'n': item.maxWrongTries}), c.purple),
          ExamChip(Icons.functions_rounded,
              tx('tflag_avg_tries', {'n': item.avgWrongTries.toStringAsFixed(1)}),
              context.colors.success),
        ]),
        if (item.correctAnswer != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.success.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.success.withValues(alpha: .25)),
            ),
            child: Row(children: [
              Icon(Icons.check_circle_rounded, size: 18, color: c.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    '${'flag_correct_answer'.tr}: ${item.correctAnswer}',
                    textDirection: Helpers.textDirOf(item.correctAnswer!),
                    style: examT(13, w: FontWeight.w700, c: c.success, h: 1.5)),
              ),
            ]),
          ),
        ],
        if (item.students.isNotEmpty)
          Material(
            type: MaterialType.transparency,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                iconColor: c.primary,
                collapsedIconColor: c.textMedium,
                title: Row(children: [
                  Icon(Icons.groups_rounded, size: 18, color: c.primary),
                  const SizedBox(width: 8),
                  Text('tflag_students'.tr,
                      style: examT(13, w: FontWeight.w800, c: c.textDark)),
                ]),
                children: [
                  for (final s in item.students)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
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
                      child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: c.danger.withValues(alpha: .10),
                          child: Text(s.name.isEmpty ? '?' : s.name[0],
                              style: examT(12, w: FontWeight.w800, c: c.danger)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(s.name,
                              style: examT(13, c: c.textDark)),
                        ),
                        ExamBadge(
                            tx('flag_wrong_times', {'n': s.wrongCount}), c.danger),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, size: 18, color: c.textLight),
                      ]),
                    ),
                    ),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}