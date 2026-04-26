// features/teacher/exam/teacher_exam_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/analytics/teacher/analytics_models.dart' hide StudentExamResult;
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'exam_model.dart';
import 'teacher_exam_provider.dart';

class TeacherExamHubScreen extends StatelessWidget {
  final int courseId;
  final String courseTitle;

  const TeacherExamHubScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
  });

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) =>
    TeacherExamProvider(courseId: courseId)..loadExams(),
    child: _HubView(courseTitle: courseTitle),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Hub view
// ══════════════════════════════════════════════════════════════════════════════

class _HubView extends StatefulWidget {
  final String courseTitle;
  const _HubView({required this.courseTitle});

  @override
  State<_HubView> createState() => _HubViewState();
}

class _HubViewState extends State<_HubView>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) {
        context.read<TeacherExamProvider>().setTab(_tab.index);
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherExamProvider>();
    if (_tab.index != prov.tab) _tab.animateTo(prov.tab);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: NestedScrollView(
          headerSliverBuilder: (ctx, _) => [_buildAppBar(ctx)],
          body: TabBarView(
            controller: _tab,
            children: [_buildExamsTab(prov), _buildResultsTab(prov)],
          ),
        ),
        floatingActionButton: prov.tab == 0
            ? FloatingActionButton.extended(
          onPressed: () => _showCreateSheet(context),
          backgroundColor: AppTheme.primary,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('اختبار جديد',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.white,
                  fontWeight: FontWeight.w700)),
        )
            : null,
      ),
    );
  }

  // ── App bar ─────────────────────────────────────────────────────────────────
  Widget _buildAppBar(BuildContext ctx) => SliverAppBar(
    expandedHeight: 148,
    pinned: true,
    backgroundColor: AppTheme.primary,
    leading: IconButton(
      icon: const Icon(Icons.arrow_forward_ios,
          color: Colors.white, size: 20),
      onPressed: () => Navigator.pop(ctx),
    ),
    flexibleSpace: FlexibleSpaceBar(
      background: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [AppTheme.primary, Colors.deepPurple],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('إدارة الاختبارات',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo')),
                  Text(widget.courseTitle,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontFamily: 'Cairo')),
                ]),
          ),
        ),
      ),
    ),
    bottom: TabBar(
      controller: _tab,
      labelStyle: const TextStyle(
          fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 14),
      unselectedLabelStyle:
      const TextStyle(fontFamily: 'Cairo', fontSize: 13),
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white60,
      indicatorColor: Colors.white,
      indicatorWeight: 3,
      tabs: const [
        Tab(text: 'الاختبارات'),
        Tab(text: 'نتائج الطلاب'),
      ],
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // Tab 1 — Exams list
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildExamsTab(TeacherExamProvider prov) {
    if (prov.loadingExams) {
      return const Center(child: CircularProgressIndicator());
    }
    if (prov.examsError != null && prov.exams.isEmpty) {
      return _ErrorView(message: prov.examsError, onRetry: prov.loadExams);
    }
    if (prov.exams.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.quiz_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text('لا توجد اختبارات بعد',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          const Text('اضغط على "اختبار جديد" لإنشاء أول اختبار',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 13, color: Colors.grey)),
        ]),
      );
    }
    final isWide = MediaQuery.of(context).size.width > 720;
    return isWide
        ? GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.5,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14),
      itemCount: prov.exams.length,
      itemBuilder: (_, i) => _examCard(prov, prov.exams[i]),
    )
        : ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: prov.exams.length,
      itemBuilder: (_, i) => _examCard(prov, prov.exams[i]),
    );
  }

  Widget _examCard(TeacherExamProvider prov, ExamModel exam) => _ExamCard(
    key: ValueKey(exam.id),
    exam: exam,
    onToggle: () => _toggle(prov, exam),
    onResults: () => prov.loadResults(exam),
    onDelete: () => _confirmDelete(prov, exam.id),
    onManageQuestions: () => _showQuestionsSheet(context, prov, exam),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // Tab 2 — Results
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildResultsTab(TeacherExamProvider prov) {
    if (prov.selectedExam == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bar_chart_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text('اختر اختباراً لعرض نتائج الطلاب',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 15, color: Colors.grey)),
        ]),
      );
    }
    if (prov.loadingResults) {
      return const Center(child: CircularProgressIndicator());
    }
    if (prov.resultsError != null) {
      return _ErrorView(
          message: prov.resultsError,
          onRetry: () => prov.loadResults(prov.selectedExam!));
    }

    return Column(children: [
      // Summary header
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.quiz_rounded, color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(prov.selectedExam!.name,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _MiniStat('${prov.results.length}', 'مسجّل', AppTheme.primary),
            _MiniStat('${prov.attendedCount}', 'حضر', AppTheme.success),
            _MiniStat('${prov.attemptedCount}', 'أجاب', Colors.orange),
            _MiniStat('${prov.passedCount}', 'نجح', Colors.teal),
            _MiniStat(
                '${prov.avgScore.toStringAsFixed(0)}%', 'متوسط', Colors.purple),
          ]),
        ]),
      ),
      Expanded(
        child: prov.results.isEmpty
            ? const Center(
            child: Text('لا توجد نتائج بعد',
                style:
                TextStyle(fontFamily: 'Cairo', color: Colors.grey)))
            : ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: prov.results.length,
          itemBuilder: (_, i) => _ResultTile(
            result: prov.results[i],
            onViewAnswers: () =>
                _showAnswers(prov.results[i], prov.selectedExam!),
          ),
        ),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Actions
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _toggle(TeacherExamProvider prov, ExamModel exam) async {
    final err = await prov.togglePublish(exam);
    if (!context.mounted) return;
    _snack(
      err ??
          (exam.isPublished
              ? 'تم نشر الاختبار'
              : 'تم إيقاف نشر الاختبار'),
      err != null
          ? Colors.redAccent
          : (exam.isPublished ? AppTheme.success : Colors.orange),
    );
  }

  Future<void> _confirmDelete(
      TeacherExamProvider prov, int examId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('حذف الاختبار',
              style: TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: const Text('هل أنت متأكد؟ سيتم حذف جميع الأسئلة والإجابات.',
              style: TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء',
                    style: TextStyle(fontFamily: 'Cairo'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child:
              const Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      final deleted = await prov.deleteExam(examId);
      if (context.mounted) {
        _snack(deleted ? 'تم حذف الاختبار' : 'فشل الحذف',
            deleted ? AppTheme.success : Colors.redAccent);
      }
    }
  }

  void _showCreateSheet(BuildContext ctx) => showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _CreateExamSheet(provider: ctx.read<TeacherExamProvider>()),
  );

  void _showQuestionsSheet(
      BuildContext ctx, TeacherExamProvider prov, ExamModel exam) {
    // Load questions if not already loaded
    prov.loadQuestions(exam.id);
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: prov,
        child: _ManageQuestionsSheet(exam: exam),
      ),
    );
  }

  void _showAnswers(StudentExamResult r, ExamModel exam) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AnswersSheet(result: r, exam: exam),
      );

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
}

// ══════════════════════════════════════════════════════════════════════════════
// _ExamCard
// ══════════════════════════════════════════════════════════════════════════════

class _ExamCard extends StatelessWidget {
  final ExamModel exam;
  final VoidCallback onToggle, onResults, onDelete, onManageQuestions;

  const _ExamCard({
    super.key,
    required this.exam,
    required this.onToggle,
    required this.onResults,
    required this.onDelete,
    required this.onManageQuestions,
  });

  Color get _statusColor => switch (exam.status) {
    ExamStatus.active    => AppTheme.success,
    ExamStatus.scheduled => Colors.orange,
    ExamStatus.ended     => Colors.grey,
    ExamStatus.draft     => Colors.blueGrey,
  };

  String get _statusLabel => switch (exam.status) {
    ExamStatus.active    => 'نشط',
    ExamStatus.scheduled => 'مجدول',
    ExamStatus.ended     => 'انتهى',
    ExamStatus.draft     => 'مسودة',
  };

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
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
          borderRadius:
          const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exam.name,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  if (exam.description != null) ...[
                    const SizedBox(height: 2),
                    Text(exam.description!,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ]),
          ),
          const SizedBox(width: 10),
          _StatusBadge(_statusLabel, _statusColor),
        ]),
      ),

      // ── Info chips ──────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          _Chip(Icons.help_outline_rounded,
              '${exam.questionCount} سؤال', Colors.blueGrey),
          const SizedBox(width: 12),
          _Chip(Icons.timer_outlined,
              '${exam.duration ?? 0} دقيقة', Colors.teal),
          if (exam.passcode != null) ...[
            const SizedBox(width: 12),
            _Chip(Icons.lock_outline_rounded, exam.passcode!,
                Colors.purple),
          ],
        ]),
      ),
      if (exam.startDate != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            _Chip(Icons.schedule_rounded, _fmtDate(exam.startDate!),
                Colors.orange),
          ]),
        ),

      // ── Action row ──────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(children: [
          // Publish / Unpublish
          Expanded(
            child: _ActionBtn(
              onTap: onToggle,
              color: exam.isPublished ? AppTheme.success : Colors.grey,
              filled: exam.isPublished,
              icon: exam.isPublished
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              label: exam.isPublished ? 'منشور' : 'نشر',
            ),
          ),
          const SizedBox(width: 8),
          // Manage questions
          Expanded(
            child: _ActionBtn(
              onTap: onManageQuestions,
              color: Colors.deepOrange,
              filled: false,
              icon: Icons.edit_note_rounded,
              label: 'الأسئلة',
            ),
          ),
          const SizedBox(width: 8),
          // Results
          Expanded(
            child: _ActionBtn(
              onTap: onResults,
              color: AppTheme.primary,
              filled: false,
              icon: Icons.bar_chart_rounded,
              label: 'النتائج',
            ),
          ),
          const SizedBox(width: 8),
          // More (delete)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded,
                color: Colors.grey, size: 20),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline,
                      color: Colors.red),
                  title: Text('حذف الاختبار',
                      style: TextStyle(
                          fontFamily: 'Cairo', color: Colors.red)),
                ),
              ),
            ],
          ),
        ]),
      ),
    ]),
  );

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ── Small action button ───────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;
  final bool filled;
  final IconData icon;
  final String label;
  const _ActionBtn({
    required this.onTap,
    required this.color,
    required this.filled,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: filled
            ? color.withValues(alpha: 0.1)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: filled
                ? color.withValues(alpha: 0.4)
                : Colors.grey.shade200),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon,
            size: 15,
            color: filled ? color : Colors.grey.shade600),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: filled ? color : Colors.grey.shade600)),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// _ManageQuestionsSheet  — lists questions + add / edit / delete
// ══════════════════════════════════════════════════════════════════════════════

class _ManageQuestionsSheet extends StatelessWidget {
  final ExamModel exam;
  const _ManageQuestionsSheet({required this.exam});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherExamProvider>();
    final questions = prov.questionsFor(exam.id);
    final loading = prov.loadingQuestionsFor(exam.id);
    final error = prov.questionErrorFor(exam.id);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          // Handle
          Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),

          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
            child: Row(children: [
              const Icon(Icons.edit_note_rounded,
                  color: Colors.deepOrange, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('إدارة الأسئلة',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      Text(exam.name,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.grey),
                          overflow: TextOverflow.ellipsis),
                    ]),
              ),
              // Add question button
              TextButton.icon(
                onPressed: () => _showQuestionForm(context, prov,
                    examId: exam.id, existing: null),
                icon: const Icon(Icons.add_rounded,
                    size: 18, color: AppTheme.primary),
                label: const Text('إضافة',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary)),
              ),
            ]),
          ),
          const Divider(height: 16),

          // Body
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          size: 48,
                          color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text(error,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.grey)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () =>
                            prov.loadQuestions(exam.id),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary),
                        child: const Text('إعادة المحاولة',
                            style:
                            TextStyle(fontFamily: 'Cairo')),
                      ),
                    ]))
                : questions.isEmpty
                ? Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.quiz_outlined,
                          size: 56,
                          color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                      const Text('لا توجد أسئلة بعد',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 15,
                              color: Colors.grey)),
                      const SizedBox(height: 6),
                      const Text(
                          'اضغط "إضافة" لإنشاء أول سؤال',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.grey)),
                    ]))
                : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  16, 4, 16, 32),
              itemCount: questions.length,
              onReorder: (_, __) {},
              // drag-to-reorder hint (order save via API not implemented)
              itemBuilder: (_, i) {
                final q = questions[i];
                return _QuestionTile(
                  key: ValueKey(q.id),
                  question: q,
                  index: i,
                  onEdit: () => _showQuestionForm(
                      context, prov,
                      examId: exam.id, existing: q),
                  onDelete: () =>
                      _confirmDeleteQuestion(
                          context, prov, q, exam.id),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _showQuestionForm(
      BuildContext ctx,
      TeacherExamProvider prov, {
        required int examId,
        required Question? existing,
      }) =>
      showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ChangeNotifierProvider.value(
          value: prov,
          child: _QuestionFormSheet(examId: examId, existing: existing),
        ),
      );

  Future<void> _confirmDeleteQuestion(
      BuildContext ctx,
      TeacherExamProvider prov,
      Question q,
      int examId,
      ) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('حذف السؤال',
              style: TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: Text(
              'هل تريد حذف: "${q.title.length > 60 ? '${q.title.substring(0, 60)}...' : q.title}"?',
              style: const TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء',
                    style: TextStyle(fontFamily: 'Cairo'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('حذف',
                  style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await prov.deleteQuestion(questionId: q.id, examId: examId);
    }
  }
}

// ── Question tile inside the manage sheet ─────────────────────────────────────
class _QuestionTile extends StatelessWidget {
  final Question question;
  final int index;
  final VoidCallback onEdit, onDelete;

  const _QuestionTile({
    super.key,
    required this.question,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2))
      ],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Question header
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('${index + 1}',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(question.title,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.4)),
              ),
              // Edit / Delete actions
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    size: 18, color: Colors.grey),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      leading:
                      Icon(Icons.edit_rounded, color: AppTheme.primary),
                      title: Text('تعديل',
                          style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.delete_outline,
                          color: Colors.redAccent),
                      title: Text('حذف',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.redAccent)),
                    ),
                  ),
                ],
              ),
            ]),
      ),

      // MCQ options (if any)
      if (question.isMcq)
        Padding(
          padding: const EdgeInsets.fromLTRB(50, 0, 14, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: question.options.map((opt) {
              final isCorrect =
                  opt == question.correctAnswer;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isCorrect
                      ? AppTheme.success.withValues(alpha: 0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isCorrect
                          ? AppTheme.success.withValues(alpha: 0.4)
                          : Colors.grey.shade300),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isCorrect) ...[
                    Icon(Icons.check_circle_rounded,
                        size: 12, color: AppTheme.success),
                    const SizedBox(width: 4),
                  ],
                  Text(opt,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: isCorrect
                              ? AppTheme.success
                              : Colors.grey.shade700,
                          fontWeight: isCorrect
                              ? FontWeight.w700
                              : FontWeight.w400)),
                ]),
              );
            }).toList(),
          ),
        ),

      // Marks row
      Padding(
        padding: const EdgeInsets.fromLTRB(50, 2, 14, 10),
        child: Text(
            '${question.marks.toStringAsFixed(question.marks % 1 == 0 ? 0 : 1)} درجة',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                color: Colors.grey.shade500)),
      ),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// _QuestionFormSheet — add OR edit a question
// ══════════════════════════════════════════════════════════════════════════════

class _QuestionFormSheet extends StatefulWidget {
  final int examId;
  final Question? existing; // null → adding new

  const _QuestionFormSheet({required this.examId, required this.existing});

  @override
  State<_QuestionFormSheet> createState() => _QuestionFormSheetState();
}

class _QuestionFormSheetState extends State<_QuestionFormSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _marksCtrl;
  late final TextEditingController _correctCtrl;
  final List<TextEditingController> _optionCtrls = [];
  bool _isMcq = true;

  @override
  void initState() {
    super.initState();
    final q = widget.existing;
    _titleCtrl =
        TextEditingController(text: q?.title ?? '');
    _marksCtrl =
        TextEditingController(text: q?.marks.toString() ?? '1');
    _correctCtrl =
        TextEditingController(text: q?.correctAnswer ?? '');

    if (q != null && q.options.isNotEmpty) {
      _isMcq = true;
      for (final o in q.options) {
        _optionCtrls.add(TextEditingController(text: o));
      }
    } else if (q != null && q.options.isEmpty) {
      _isMcq = false;
    }

    // Ensure at least 2 option fields when MCQ
    while (_isMcq && _optionCtrls.length < 2) {
      _optionCtrls.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _marksCtrl.dispose();
    _correctCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_optionCtrls.length <= 2) return;
    setState(() {
      _optionCtrls[i].dispose();
      _optionCtrls.removeAt(i);
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    final prov = context.read<TeacherExamProvider>();
    final title = _titleCtrl.text.trim();
    final marks = double.tryParse(_marksCtrl.text.trim()) ?? 1.0;
    final options = _isMcq
        ? _optionCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList()
        : <String>[];
    final correct =
    _isMcq && _correctCtrl.text.trim().isNotEmpty
        ? _correctCtrl.text.trim()
        : null;

    if (widget.existing == null) {
      // ADD
      final q = await prov.addQuestion(
        examId: widget.examId,
        title: title,
        options: options,
        correctAnswer: correct,
        marks: marks,
      );
      if (!context.mounted) return;
      if (q != null) {
        Navigator.pop(context);
        _snack('تمت إضافة السؤال بنجاح', AppTheme.success);
      } else {
        _snack('فشلت الإضافة، حاول مرة أخرى', Colors.redAccent);
      }
    } else {
      // EDIT
      final q = await prov.updateQuestion(
        questionId: widget.existing!.id,
        examId: widget.examId,
        title: title,
        options: options,
        correctAnswer: correct,
        marks: marks,
      );
      if (!context.mounted) return;
      if (q != null) {
        Navigator.pop(context);
        _snack('تم تعديل السؤال بنجاح', AppTheme.success);
      } else {
        _snack('فشل التعديل، حاول مرة أخرى', Colors.redAccent);
      }
    }
  }

  void _snack(String msg, Color color) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherExamProvider>();
    final isEditing = widget.existing != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding:
        EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),

          // Title bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(children: [
              Icon(
                  isEditing
                      ? Icons.edit_rounded
                      : Icons.add_circle_outline_rounded,
                  color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(isEditing ? 'تعديل السؤال' : 'إضافة سؤال',
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
          const Divider(height: 20),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Question title
                      _Field(
                        ctrl: _titleCtrl,
                        label: 'نص السؤال *',
                        hint: 'اكتب السؤال هنا...',
                        maxLines: 3,
                        validator: (v) =>
                        v == null || v.trim().isEmpty ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 14),

                      // Marks field
                      SizedBox(
                        width: 130,
                        child: _Field(
                          ctrl: _marksCtrl,
                          label: 'الدرجة',
                          hint: '1',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'مطلوب';
                            if (double.tryParse(v.trim()) == null)
                              return 'رقم صحيح';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 14),

                      // MCQ toggle
                      _Toggle(
                        icon: Icons.format_list_bulleted_rounded,
                        label: 'سؤال اختيار من متعدد (MCQ)',
                        value: _isMcq,
                        onChanged: (v) {
                          setState(() {
                            _isMcq = v;
                            if (v && _optionCtrls.length < 2) {
                              while (_optionCtrls.length < 2) {
                                _optionCtrls.add(TextEditingController());
                              }
                            }
                          });
                        },
                      ),

                      if (_isMcq) ...[
                        const SizedBox(height: 14),
                        const Text('الخيارات',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey)),
                        const SizedBox(height: 8),

                        // Option fields
                        ...List.generate(_optionCtrls.length, (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Expanded(
                              child: TextFormField(
                                controller: _optionCtrls[i],
                                textDirection: TextDirection.rtl,
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'أدخل الخيار'
                                    : null,
                                decoration: InputDecoration(
                                  hintText: 'الخيار ${i + 1}',
                                  hintStyle: const TextStyle(
                                      fontFamily: 'Cairo',
                                      color: Colors.grey),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  border: OutlineInputBorder(
                                      borderRadius:
                                      BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade200)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius:
                                      BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade200)),
                                  contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                              ),
                            ),
                            if (_optionCtrls.length > 2) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                onPressed: () => _removeOption(i),
                                icon: Icon(Icons.remove_circle_outline,
                                    color: Colors.redAccent.shade200,
                                    size: 20),
                                padding: EdgeInsets.zero,
                                constraints:
                                const BoxConstraints(),
                              ),
                            ],
                          ]),
                        )),

                        // Add option button
                        TextButton.icon(
                          onPressed: _addOption,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('إضافة خيار',
                              style: TextStyle(
                                  fontFamily: 'Cairo', fontSize: 13)),
                          style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primary),
                        ),

                        const SizedBox(height: 12),


                      ],
// Correct answer
                      _Field(
                        ctrl: _correctCtrl,
                        label: 'الإجابة الصحيحة (اختياري)',
                        hint: 'انسخ الخيار الصحيح بالضبط',
                      ),
                      const SizedBox(height: 20),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: prov.saving ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding:
                            const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: prov.saving
                              ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                              : Text(
                              isEditing
                                  ? 'حفظ التعديلات'
                                  : 'إضافة السؤال',
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _CreateExamSheet  (unchanged from before)
// ══════════════════════════════════════════════════════════════════════════════

class _CreateExamSheet extends StatefulWidget {
  final TeacherExamProvider provider;
  const _CreateExamSheet({required this.provider});

  @override
  State<_CreateExamSheet> createState() => _CreateExamSheetState();
}

class _CreateExamSheetState extends State<_CreateExamSheet> {
  final _form = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _passcodeCtrl = TextEditingController();
  final _totalMarksCtrl = TextEditingController(text: '100');
  final _passingCtrl = TextEditingController(text: '60');
  final _durationCtrl = TextEditingController(text: '60');
  bool _hasPasscode = false;
  bool _hasSchedule = false;
  DateTime? _scheduleDate;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _passcodeCtrl.dispose();
    _totalMarksCtrl.dispose();
    _passingCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 1)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !context.mounted) return;
    final t =
    await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    setState(() =>
    _scheduleDate = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await widget.provider.createExam(
      name: _nameCtrl.text.trim(),
      description:
      _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      startDate: _hasSchedule ? _scheduleDate : null,
      duration: int.tryParse(_durationCtrl.text),
      totalMarks: double.tryParse(_totalMarksCtrl.text),
      passingScore: double.tryParse(_passingCtrl.text),
      passcode:
      _hasPasscode && _passcodeCtrl.text.trim().isNotEmpty
          ? _passcodeCtrl.text.trim()
          : null,
    );
    if (ok && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
          BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            Icon(Icons.add_circle_outline_rounded,
                color: AppTheme.primary),
            SizedBox(width: 8),
            Text('إنشاء اختبار جديد',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
        const Divider(height: 20),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Form(
              key: _form,
              child: Column(children: [
                _Field(
                    ctrl: _nameCtrl,
                    label: 'اسم الاختبار *',
                    hint: 'مثال: اختبار الوحدة الأولى',
                    validator: (v) => v!.isEmpty ? 'مطلوب' : null),
                const SizedBox(height: 12),
                _Field(
                    ctrl: _descCtrl,
                    label: 'الوصف (اختياري)',
                    hint: 'وصف مختصر',
                    maxLines: 2),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _Field(
                          ctrl: _totalMarksCtrl,
                          label: 'الدرجة الكلية',
                          hint: '100',
                          keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _Field(
                          ctrl: _passingCtrl,
                          label: 'النجاح %',
                          hint: '60',
                          keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _Field(
                          ctrl: _durationCtrl,
                          label: 'المدة (د)',
                          hint: '60',
                          keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 14),
                _Toggle(
                  icon: Icons.lock_outline_rounded,
                  label: 'كلمة مرور للاختبار',
                  value: _hasPasscode,
                  onChanged: (v) =>
                      setState(() => _hasPasscode = v),
                  child: _hasPasscode
                      ? _Field(
                      ctrl: _passcodeCtrl,
                      label: 'كلمة المرور',
                      hint: 'EXAM2025',
                      validator: _hasPasscode
                          ? (v) =>
                      v!.isEmpty ? 'مطلوب' : null
                          : null)
                      : null,
                ),
                const SizedBox(height: 10),
                _Toggle(
                  icon: Icons.schedule_rounded,
                  label: 'جدولة وقت محدد',
                  value: _hasSchedule,
                  onChanged: (v) =>
                      setState(() => _hasSchedule = v),
                  child: _hasSchedule
                      ? GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors.grey.shade300),
                          borderRadius:
                          BorderRadius.circular(10)),
                      child: Row(children: [
                        const Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                            color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          _scheduleDate != null
                              ? '${_scheduleDate!.day}/${_scheduleDate!.month}/${_scheduleDate!.year}  '
                              '${_scheduleDate!.hour.toString().padLeft(2, '0')}:${_scheduleDate!.minute.toString().padLeft(2, '0')}'
                              : 'اختر التاريخ والوقت',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                              color: _scheduleDate != null
                                  ? Colors.black87
                                  : Colors.grey),
                        ),
                      ]),
                    ),
                  )
                      : null,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                    widget.provider.saving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding:
                      const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: widget.provider.saving
                        ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                        : const Text('إنشاء الاختبار',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// _AnswersSheet — view a student's answers
// ══════════════════════════════════════════════════════════════════════════════

class _AnswersSheet extends StatelessWidget {
  final StudentExamResult result;
  final ExamModel exam;
  const _AnswersSheet({required this.result, required this.exam});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
          BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            CircleAvatar(
              backgroundColor:
              AppTheme.primary.withValues(alpha: 0.1),
              backgroundImage: result.studentImage != null
                  ? NetworkImage(result.studentImage!)
                  : null,
              child: result.studentImage == null
                  ? Text(result.studentName[0],
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo'))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.studentName,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    Text(
                        '${result.marksObtained?.toStringAsFixed(0) ?? 0} / '
                            '${result.totalMarks?.toStringAsFixed(0) ?? 0} درجة'
                            '  •  ${result.percentage?.toStringAsFixed(1) ?? 0}%',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: Colors.grey)),
                  ]),
            ),
            _StatusBadge(
                result.passed == true ? 'نجح' : 'راسب',
                result.passed == true
                    ? AppTheme.success
                    : Colors.redAccent),
          ]),
        ),
        const Divider(height: 20),
        Expanded(
          child: result.answers.isEmpty
              ? const Center(
              child: Text('لا توجد إجابات مسجّلة',
                  style: TextStyle(
                      fontFamily: 'Cairo', color: Colors.grey)))
              : ListView.builder(
              padding:
              const EdgeInsets.fromLTRB(20, 0, 20, 32),
              itemCount: result.answers.length,
              itemBuilder: (_, i) {
                final a = result.answers[i];
                final correct = a.isCorrect == true;
                final color =
                correct ? AppTheme.success : Colors.redAccent;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Icon(
                        correct
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: color,
                        size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text('السؤال ${a.questionId}',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    color: Colors.grey)),
                            Text(a.answer ?? 'لم يجب',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 14,
                                    fontWeight:
                                    FontWeight.w600)),
                          ]),
                    ),
                    Text(
                        '${a.marksObtained?.toStringAsFixed(1) ?? 0} درجة',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ]),
                );
              }),
        ),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Result tile
// ══════════════════════════════════════════════════════════════════════════════

class _ResultTile extends StatelessWidget {
  final StudentExamResult result;
  final VoidCallback onViewAnswers;
  const _ResultTile({required this.result, required this.onViewAnswers});

  @override
  Widget build(BuildContext context) {
    final pct = result.percentage;
    final passed = result.passed;
    final color = passed == true
        ? AppTheme.success
        : passed == false
        ? Colors.redAccent
        : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        leading: Stack(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withValues(alpha: 0.12),
            backgroundImage: result.studentImage != null
                ? NetworkImage(result.studentImage!)
                : null,
            child: result.studentImage == null
                ? Text(result.studentName[0],
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    color: color))
                : null,
          ),
          if (result.isAttended)
            Positioned(
              bottom: 0,
              left: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    color: AppTheme.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5)),
              ),
            ),
        ]),
        title: Text(result.studentName,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(children: [
                _StatusBadge(result.isAttended ? 'حضر' : 'غاب',
                    result.isAttended ? AppTheme.success : Colors.redAccent),
                const SizedBox(width: 6),
                if (result.attempted)
                  _StatusBadge(passed == true ? 'نجح' : 'راسب', color)
                else
                  const _StatusBadge('لم يؤدِّ', Colors.grey),
              ]),
              if (pct != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                      value: pct / 100,
                      backgroundColor: Colors.grey.shade100,
                      color: color,
                      minHeight: 5),
                ),
              ],
            ]),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(
              pct != null ? '${pct.toStringAsFixed(0)}%' : '—',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color)),
          if (result.attempted)
            GestureDetector(
              onTap: onViewAnswers,
              child: Text('الإجابات',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared micro-widgets
// ══════════════════════════════════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

class _MiniStat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _MiniStat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(value,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color)),
      Text(label,
          style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 10, color: Colors.grey)),
    ]),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.ctrl,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: ctrl,
    maxLines: maxLines,
    keyboardType: keyboardType,
    textDirection: TextDirection.rtl,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
          fontFamily: 'Cairo', fontSize: 13, color: Colors.grey),
      hintStyle:
      const TextStyle(fontFamily: 'Cairo', color: Colors.grey),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
  );
}

class _Toggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? child;

  const _Toggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      ListTile(
        dense: true,
        leading: Icon(icon, color: AppTheme.primary, size: 20),
        title: Text(label,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        trailing: Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      if (value && child != null)
        Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: child!),
    ]),
  );
}

class _ErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.wifi_off_rounded, size: 52, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text(message ?? 'حدث خطأ',
          style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 14, color: Colors.grey)),
      const SizedBox(height: 12),
      ElevatedButton(
          onPressed: onRetry,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          child: const Text('إعادة المحاولة',
              style: TextStyle(
                  fontFamily: 'Cairo', color: Colors.white))),
    ]),
  );
}