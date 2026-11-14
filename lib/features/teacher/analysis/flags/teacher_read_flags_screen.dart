// features/teacher/analysis/flags/teacher_read_flags_screen.dart
//
// Teacher's read-flag bank for one course. The server only returns questions that
// cross the admin's thresholds (students who failed it × wrong tries per student).
//   GET /api/v1/teacher/courses/{courseId}/read-flags
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/features/student/analysis/exam/exam_tr.dart';

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
      error = e.toString();
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
    final c = context.colors;
    final p = context.watch<TeacherReadFlagsProvider>();
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          title: Text(courseTitle,
              style: const TextStyle(
                  fontFamily: 'bahji', fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh_rounded), onPressed: p.load),
          ],
        ),
        body: p.loading
            ? const Center(child: AppLoadingIndicator())
            : p.error != null
            ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(p.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'bahji', color: Colors.grey)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                    onPressed: p.load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('retry'.tr)),
              ]),
            ))
            : RefreshIndicator(
          onRefresh: p.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Icon(Icons.flag_rounded, color: c.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tx('tflag_thresholds', {
                        'students': p.minStudents,
                        'tries': p.minTries,
                      }),
                      style: const TextStyle(
                          fontFamily: 'bahji', fontSize: 12, height: 1.6),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              if (p.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Column(children: [
                    Icon(Icons.task_alt_rounded,
                        size: 72, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('tflag_empty'.tr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: 'bahji',
                            fontSize: 15,
                            color: Colors.grey,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              for (final it in p.items) ...[
                _FlagCard(item: it),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: c.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.examName,
            style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 11,
                color: c.primary,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(item.title,
            textDirection: Helpers.textDirOf(item.title),
            style: c.h3.copyWith(fontSize: 15, height: 1.6)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _Chip(
              icon: Icons.groups_rounded,
              text: tx('tflag_students_failed', {'n': item.studentsFailed}),
              color: c.danger),
          _Chip(
              icon: Icons.repeat_rounded,
              text: tx('tflag_max_tries', {'n': item.maxWrongTries}),
              color: Colors.purple),
          _Chip(
              icon: Icons.functions_rounded,
              text: tx('tflag_avg_tries',
                  {'n': item.avgWrongTries.toStringAsFixed(1)}),
              color: Colors.teal),
          _Chip(
              icon: Icons.star_rounded,
              text: tx('flag_score', {'n': item.score.toStringAsFixed(1)}),
              color: Colors.amber.shade800),
        ]),
        if (item.correctAnswer != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.success.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
                '${'flag_correct_answer'.tr}: ${item.correctAnswer}',
                textDirection: Helpers.textDirOf(item.correctAnswer!),
                style: TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 13,
                    color: c.success,
                    fontWeight: FontWeight.w700)),
          ),
        ],
        if (item.students.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('tflag_students'.tr,
                  style: const TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              children: [
                for (final s in item.students)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.name,
                        style: const TextStyle(
                            fontFamily: 'bahji', fontSize: 13)),
                    trailing: Text(tx('flag_wrong_times', {'n': s.wrongCount}),
                        style: TextStyle(
                            fontFamily: 'bahji',
                            fontSize: 12,
                            color: c.danger,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Chip({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 4),
      Text(text,
          style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color)),
    ]),
  );
}
