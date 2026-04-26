// features/student/exam/student_exam_list_screen.dart
//
// Tab shown inside the student dashboard — lists all published exams across
// every course the student is enrolled in, with score chips for submitted ones.
// Tapping an exam navigates to StudentExamDetailScreen (entry gate + quiz).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import '../../teacher/exam/exam_model.dart';
import 'student_exam_api.dart';
import 'student_exam_provider.dart';
import 'student_exam_detail_screen.dart';

class StudentExamListScreen extends StatefulWidget {
  const StudentExamListScreen({super.key});

  @override
  State<StudentExamListScreen> createState() => _StudentExamListScreenState();
}

class _StudentExamListScreenState extends State<StudentExamListScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudentExamProvider>().loadMyExams();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final prov = context.watch<StudentExamProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(children: [
            _buildHeader(),
            _buildFilterRow(prov),
            Expanded(child: _buildBody(prov)),
          ]),
        ),
      ),
    );
  }

  // ── Filter state ───────────────────────────────────────────────────────────
  _Filter _filter = _Filter.all;

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('اختباراتي', style: AppTheme.h1),
              const SizedBox(height: 2),
              Consumer<StudentExamProvider>(builder: (_, p, __) {
                final total = p.myExams.length;
                final done = p.myExams.where((e) => e.isSubmitted).length;
                return Text(
                  '$done / $total مكتمل',
                  style: AppTheme.body,
                );
              }),
            ]),
          ),
          Consumer<StudentExamProvider>(builder: (_, p, __) => IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.grey),
            onPressed: p.loadingList ? null : p.loadMyExams,
          )),
        ]),
      );

  Widget _buildFilterRow(StudentExamProvider prov) => SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: _Filter.values.map((f) {
            final selected = _filter == f;
            return GestureDetector(
              onTap: () => setState(() => _filter = f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.primary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: selected ? AppTheme.primary : Colors.grey.shade200),
                ),
                child: Text(
                  f.label,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );

  Widget _buildBody(StudentExamProvider prov) {
    if (prov.loadingList && prov.myExams.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (prov.listError != null && prov.myExams.isEmpty) {
      return _ErrorRetry(
        message: prov.listError!,
        onRetry: prov.loadMyExams,
      );
    }

    final items = _filtered(prov.myExams);

    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.quiz_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            prov.myExams.isEmpty ? 'لا توجد اختبارات حتى الآن' : 'لا توجد نتائج',
            style: const TextStyle(
                fontFamily: 'Cairo', fontSize: 16, color: Colors.grey),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: prov.loadMyExams,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _ExamCard(
          item: items[i],
          onTap: () => _openExam(context, items[i]),
        ),
      ),
    );
  }

  List<StudentExamListItem> _filtered(List<StudentExamListItem> all) {
    return switch (_filter) {
      _Filter.all => all,
      _Filter.pending => all.where((e) => !e.isSubmitted).toList(),
      _Filter.submitted => all.where((e) => e.isSubmitted).toList(),
      _Filter.passed =>
        all.where((e) => e.isSubmitted && e.passed == true).toList(),
    };
  }

  void _openExam(BuildContext context, StudentExamListItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<StudentExamProvider>(),
          child: StudentExamDetailScreen(exam: item),
        ),
      ),
    );
  }
}

enum _Filter { all, pending, submitted, passed }

extension _FilterLabel on _Filter {
  String get label => switch (this) {
        _Filter.all => 'الكل',
        _Filter.pending => 'لم يُؤدَّ',
        _Filter.submitted => 'مكتمل',
        _Filter.passed => 'ناجح',
      };
}

// ── Exam card ─────────────────────────────────────────────────────────────────

class _ExamCard extends StatelessWidget {
  final StudentExamListItem item;
  final VoidCallback onTap;

  const _ExamCard({required this.item, required this.onTap});

  Color get _statusColor => item.isSubmitted
      ? (item.passed == true ? AppTheme.success : Colors.redAccent)
      : (item.status == ExamStatusExt.scheduled
          ? Colors.orange
          : AppTheme.primary);

  @override
  Widget build(BuildContext context) {
    final pct = item.percentage;
    final isDone = item.isSubmitted;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(children: [
          // ── Header ─────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isDone ? Icons.check_circle_rounded : Icons.quiz_rounded,
                  color: _statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (item.courseName != null) ...[
                      const SizedBox(height: 2),
                      Text(item.courseName!,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(_statusLabel, _statusColor),
            ]),
          ),

          // ── Body ───────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(children: [
              // Info chips
              Row(children: [
                _Chip(Icons.timer_outlined,
                    '${item.duration ?? 0} دقيقة', Colors.teal),
                const SizedBox(width: 12),
                _Chip(Icons.help_outline_rounded,
                    '${item.questionCount} سؤال', AppTheme.primary),
                if (item.passingScore != null) ...[
                  const SizedBox(width: 12),
                  _Chip(Icons.star_outline_rounded,
                      '${item.passingScore!.toInt()}% للنجاح',
                      Colors.amber.shade700),
                ],
              ]),

              // Score bar (only when submitted)
              if (isDone && pct != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'الدرجة: ${item.marksObtained?.toStringAsFixed(0)} / '
                              '${item.totalMarks?.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: Colors.grey),
                            ),
                            Text(
                              '${pct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _statusColor),
                            ),
                          ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: pct / 100,
                          backgroundColor: Colors.grey.shade100,
                          color: _statusColor,
                          minHeight: 7,
                        ),
                      ),
                    ]),
                  ),
                ]),
              ],

              // Pending CTA
              if (!isDone) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(Icons.play_arrow_rounded,
                        color: AppTheme.primary, size: 18),
                    const SizedBox(width: 6),
                    Text('ابدأ الاختبار',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary)),
                  ]),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  String get _statusLabel {
    if (item.isSubmitted) return item.passed == true ? 'ناجح ✓' : 'راسب ✗';
    if (item.startDate != null && item.startDate!.isAfter(DateTime.now())) {
      return 'مجدول';
    }
    return 'متاح';
  }
}

// ── Shared micro-widgets ──────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color)),
      );
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: Colors.grey.shade700)),
      ]);
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.wifi_off_rounded,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة',
                  style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
          ]),
        ),
      );
}

// Small extension so ExamStatus can be used in the card without importing
// the teacher model directly in the switch expression.
extension ExamStatusExt on ExamStatus {
  static const scheduled = 'scheduled';
}
