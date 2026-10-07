// features/teacher/exam/teacher_exam_hub_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import '../../../../config/app_config.dart';
import '../../../shared/models/exam_model.dart';
import 'exam_files.dart';
import 'teacher_exam_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
class TeacherExamHubScreen extends StatelessWidget {
  final int courseId;
  final String courseTitle;

  /// When set, the "new exam" sheet pre-selects this session.
  final int? initialSessionId;

  /// When true, the "new exam" sheet opens automatically as soon as the hub
  /// appears (used by the "Add exam" button on a session card).
  final bool openCreateOnStart;

  const TeacherExamHubScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
    this.initialSessionId,
    this.openCreateOnStart = false,
  });

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => TeacherExamProvider(courseId: courseId)..loadExams(),
    child: _HubView(
      courseTitle: courseTitle,
      initialSessionId: initialSessionId,
      openCreateOnStart: openCreateOnStart,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Hub view
// ══════════════════════════════════════════════════════════════════════════════

class _HubView extends StatefulWidget {
  final String courseTitle;
  final int? initialSessionId;
  final bool openCreateOnStart;

  const _HubView({
    required this.courseTitle,
    this.initialSessionId,
    this.openCreateOnStart = false,
  });

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
    if (widget.openCreateOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCreateSheet(context);
      });
    }
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

    return BasePage(
      key: const ValueKey('teacher_exams_hub'),
      useWebCard: true,
      floatingActionButton: prov.tab == 0
          ? FloatingActionButton.extended(
        onPressed: () => _showCreateSheet(context),
        backgroundColor: context.colors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('new_exam'.tr,
            style: TextStyle(
                fontFamily: 'bahji',
                color: Colors.white,
                fontWeight: FontWeight.w700)),
      )
          : null,
      child: NestedScrollView(
        headerSliverBuilder: (ctx, _) =>
        [SliverToBoxAdapter(child: _buildAppBar(ctx))],
        body: TabBarView(
          controller: _tab,
          children: [_buildExamsTab(prov), _buildResultsTab(prov)],
        ),
      ),
    );
  }

  // ── App bar ─────────────────────────────────────────────────────────────────
  Widget _buildAppBar(BuildContext ctx) => Column(
    children: [
      Container(
        height: 250,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/test_background.png'),
            fit: BoxFit.cover,
          ),
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(34),
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios,
                      color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  'exam_hub_title'.tr,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  'exam_hub_subtitle'.tr,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: TabBar(
                  controller: _tab,
                  indicatorSize: TabBarIndicatorSize.label,
                  indicatorWeight: 4,
                  indicatorColor: Color(0xff2E67F8),
                  labelColor: Color(0xff2E67F8),
                  unselectedLabelColor: Color(0xff8B94B0),
                  labelStyle: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: [
                    Tab(text: 'tab_exams'.tr),
                    Tab(text: 'tab_student_results'.tr),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  // ══════════════════════════════════════════════════════════════════════════
  // Tab 1 — Exams list
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildExamsTab(TeacherExamProvider prov) {
    if (prov.loadingExams) {
      return const Center(child: AppLoadingIndicator());
    }
    if (prov.examsError != null && prov.exams.isEmpty) {
      return _ErrorView(message: prov.examsError, onRetry: prov.loadExams);
    }
    if (prov.exams.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.quiz_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('no_exams_yet'.tr,
              style: const TextStyle(
                  fontFamily: 'bahji', fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('no_exams_empty_hint'.tr,
              style: const TextStyle(
                  fontFamily: 'bahji', fontSize: 13, color: Colors.grey)),
        ]),
      );
    }
    final isWide = MediaQuery.of(context).size.width > 720;
    return isWide
        ? GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.15, // taller: session + rule chips may wrap lines
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
    sessionName: prov.sessionNameFor(exam),
    onPickSession: () => _showSessionPicker(prov, exam),
    onToggle: () => _toggle(prov, exam),
    onResults: () => prov.loadResults(exam),
    onDelete: () => _confirmDelete(prov, exam.id),
    onManageQuestions: () => _showQuestionsSheet(context, prov, exam),
    onEditRules: () => _showRulesSheet(prov, exam),
    onExport: (kind) => _exportFlow(context, prov, exam, kind),
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
          Text('select_exam_to_view_results'.tr,
              style: const TextStyle(
                  fontFamily: 'bahji', fontSize: 15, color: Colors.grey)),
        ]),
      );
    }
    if (prov.loadingResults) {
      return const Center(child: AppLoadingIndicator());
    }
    if (prov.resultsError != null) {
      return _ErrorView(
          message: prov.resultsError,
          onRetry: () => prov.loadResults(prov.selectedExam!));
    }

    return Column(children: [
      // Summary header
      Container(
        color: context.colors.cardBg,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(prov.selectedExam!.name,
                  style: const TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
            PopupMenuButton<String>(
              tooltip: 'menu_export'.tr,
              icon: Icon(Icons.file_download_outlined,
                  color: context.colors.primary),
              onSelected: (kind) =>
                  _exportFlow(context, prov, prov.selectedExam!, kind),
              itemBuilder: (_) => [
                _menuItem('marks', Icons.grading_rounded,
                    'menu_export_marks'.tr),
                _menuItem('answers', Icons.fact_check_outlined,
                    'menu_export_answers'.tr),
                _menuItem('all', Icons.table_view_rounded,
                    'menu_export_all'.tr),
              ],
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _MiniStat('${prov.results.length}', 'stat_enrolled'.tr,
                context.colors.primary),
            _MiniStat('${prov.attendedCount}', 'stat_attended'.tr,
                context.colors.success),
            _MiniStat(
                '${prov.attemptedCount}', 'stat_answered'.tr, Colors.orange),
            _MiniStat('${prov.passedCount}', 'stat_passed'.tr, Colors.teal),
            _MiniStat('${prov.avgScore.toStringAsFixed(0)}%', 'stat_average'.tr,
                Colors.purple),
          ]),
        ]),
      ),
      Expanded(
        child: prov.results.isEmpty
            ? Center(
            child: Text('no_results_yet'.tr,
                style: const TextStyle(
                    fontFamily: 'bahji', color: Colors.grey)))
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
              ? 'exam_published_snack'.tr
              : 'exam_unpublished_snack'.tr),
      err != null
          ? Colors.redAccent
          : (exam.isPublished ? context.colors.success : Colors.orange),
    );
  }

  Future<void> _confirmDelete(TeacherExamProvider prov, int examId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('delete_exam_title'.tr,
              style: const TextStyle(
                  fontFamily: 'bahji', fontWeight: FontWeight.w700)),
          content: Text('delete_exam_confirm_body'.tr,
              style: const TextStyle(fontFamily: 'bahji')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('cancel'.tr,
                    style: const TextStyle(fontFamily: 'bahji'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text('btn_delete'.tr,
                  style: const TextStyle(fontFamily: 'bahji')),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      final deleted = await prov.deleteExam(examId);
      if (context.mounted) {
        _snack(
            deleted ? 'exam_deleted_snack'.tr : 'exam_delete_failed_snack'.tr,
            deleted ? context.colors.success : Colors.redAccent);
      }
    }
  }

  void _showCreateSheet(BuildContext ctx) => showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CreateExamSheet(
      provider: ctx.read<TeacherExamProvider>(),
      initialSessionId: widget.initialSessionId,
    ),
  );

  /// Attach the exam to a session (or detach it). Students must PASS a
  /// published, attached exam before the sessions after it unlock.
  Future<void> _showSessionPicker(TeacherExamProvider prov, ExamModel exam) async {
    if (!prov.sessionsLoaded) await prov.loadSessions();
    if (!mounted) return;
    // -1 = "no session" (detach); null = dismissed
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SessionPickerSheet(
        sessions: prov.sessions,
        selectedId: exam.sessionId,
      ),
    );
    if (picked == null || !mounted) return;
    final newId = picked == -1 ? null : picked;
    if (newId == exam.sessionId) return;
    final err = await prov.assignSession(exam, newId);
    if (!mounted) return;
    _snack(
      err ?? (newId == null ? 'exam_session_detached'.tr : 'exam_session_attached'.tr),
      err == null ? context.colors.success : Colors.redAccent,
    );
  }

  void _showQuestionsSheet(
      BuildContext ctx, TeacherExamProvider prov, ExamModel exam) {
    // Load questions if not already loaded
    prov.loadQuestions(exam.id);
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
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

  /// Attempts + random-paper rules of an existing exam.
  void _showRulesSheet(TeacherExamProvider prov, ExamModel exam) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ExamRulesSheet(provider: prov, exam: exam),
      );

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'bahji')),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
}

// ══════════════════════════════════════════════════════════════════════════════
// _ExamCard
// ══════════════════════════════════════════════════════════════════════════════

/// Keeps a long session name from overflowing its chip.
String _shorten(String s, [int max = 22]) =>
    s.length <= max ? s : '${s.substring(0, max - 1)}…';

class _ExamCard extends StatelessWidget {
  final ExamModel exam;
  final String? sessionName;
  final VoidCallback onPickSession;
  final VoidCallback onToggle, onResults, onDelete, onManageQuestions;
  final VoidCallback onEditRules;
  final ValueChanged<String> onExport; // questions | marks | answers | all

  const _ExamCard({
    super.key,
    required this.exam,
    required this.sessionName,
    required this.onPickSession,
    required this.onToggle,
    required this.onResults,
    required this.onDelete,
    required this.onManageQuestions,
    required this.onEditRules,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(22),
      border: Border(),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withValues(alpha: 0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// HEADER
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// Left Icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.quiz_rounded,
                  color: context.colors.primary,
                  size: 28,
                ),
              ),

              const SizedBox(width: 14),

              /// Title + Desc
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            exam.name,
                            style: const TextStyle(
                              fontFamily: 'bahji',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: exam.isPublished
                                ? Colors.green.withValues(alpha: .1)
                                : Colors.orange.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            exam.isPublished
                                ? 'exam_published_badge'.tr
                                : 'exam_unpublished_badge'.tr,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'bahji',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: !exam.isPublished
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.more_vert_rounded,
                                size: 22, color: Colors.grey.shade600),
                            onSelected: (v) =>
                            v == 'rules' ? onEditRules() : onExport(v),
                            itemBuilder: (_) => [
                              _menuItem('rules', Icons.tune_rounded,
                                  'menu_exam_settings'.tr),
                              const PopupMenuDivider(),
                              _menuItem('questions', Icons.quiz_outlined,
                                  'menu_export_questions'.tr),
                              _menuItem('marks', Icons.grading_rounded,
                                  'menu_export_marks'.tr),
                              _menuItem('answers', Icons.fact_check_outlined,
                                  'menu_export_answers'.tr),
                              _menuItem('all', Icons.table_view_rounded,
                                  'menu_export_all'.tr),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (exam.description != null)
                      Text(
                        exam.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'bahji',
                          fontSize: 13,
                          height: 1.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const Spacer(),

          /// INFO CHIPS
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoChip(
                icon: Icons.help_outline_rounded,
                label:
                '${exam.questionCount} ${'question_count_chip'.tr.split(' ').last}',
                color: Colors.blueGrey,
              ),
              _InfoChip(
                icon: Icons.timer_outlined,
                label:
                '${exam.duration ?? 0} ${'duration_chip'.tr.split(' ').last}',
                color: Colors.teal,
              ),
              // Which session this exam gates (tap to change / detach).
              GestureDetector(
                onTap: onPickSession,
                child: _InfoChip(
                  icon: Icons.play_lesson_rounded,
                  label: exam.sessionId == null
                      ? 'exam_no_session'.tr
                      : _shorten(sessionName ?? 'session'.tr),
                  color: exam.sessionId == null
                      ? Colors.grey
                      : context.colors.primary,
                ),
              ),
              // Attempts + random-paper rules (tap to edit).
              GestureDetector(
                onTap: onEditRules,
                child: _InfoChip(
                  icon: Icons.repeat_rounded,
                  label: (exam.maxSubmissions ?? 0) > 0
                      ? '${'chip_attempts_label'.tr}: ${exam.maxSubmissions}'
                      : 'chip_attempts_unlimited'.tr,
                  color: Colors.indigo,
                ),
              ),
              if (exam.questionsPerStudent != null)
                GestureDetector(
                  onTap: onEditRules,
                  child: _InfoChip(
                    icon: Icons.filter_list_rounded,
                    label:
                    '${'chip_random_questions_label'.tr}: ${exam.questionsPerStudent} / ${exam.questionCount}',
                    color: Colors.deepPurple,
                  ),
                ),
              if (exam.shuffleQuestions || exam.shuffleOptions)
                GestureDetector(
                  onTap: onEditRules,
                  child: _InfoChip(
                    icon: Icons.shuffle_rounded,
                    label: 'chip_shuffled_label'.tr,
                    color: Colors.deepPurple,
                  ),
                ),
              if (exam.passcode != null)
                _InfoChip(
                  icon: Icons.lock_outline_rounded,
                  label: exam.passcode!,
                  color: Colors.purple,
                ),
              if (exam.startDate != null)
                _InfoChip(
                  icon: Icons.schedule_rounded,
                  label: _fmtDate(exam.startDate!),
                  color: Colors.orange,
                ),
            ],
          ),

          Spacer(),
          Divider(color: AppTheme.textLight.withAlpha(100)),

          /// ACTION BUTTONS
          Row(
            children: [
              Expanded(
                child: _ModernActionBtn(
                  title: exam.isPublished
                      ? 'exam_toggle_hide'.tr
                      : 'exam_toggle_publish'.tr,
                  icon: exam.isPublished
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: exam.isPublished
                      ? Colors.grey
                      : context.colors.success,
                  onTap: onToggle,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(5),
                child: Text(
                  "|",
                  style: TextStyle(
                      fontSize: 18,
                      color: AppTheme.textLight.withAlpha(100)),
                ),
              ),
              Expanded(
                child: _ModernActionBtn(
                  title: 'btn_questions'.tr,
                  icon: Icons.edit_note_rounded,
                  color: Colors.deepOrange,
                  onTap: onManageQuestions,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(5),
                child: Text(
                  "|",
                  style: TextStyle(
                      fontSize: 18,
                      color: AppTheme.textLight.withAlpha(100)),
                ),
              ),
              Expanded(
                child: _ModernActionBtn(
                  title: 'btn_results'.tr,
                  icon: Icons.bar_chart_rounded,
                  color: context.colors.primary,
                  onTap: onResults,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(5),
                child: Text(
                  "|",
                  style: TextStyle(
                      fontSize: 18,
                      color: AppTheme.textLight.withAlpha(100)),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 22,
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text('delete_confirm_title'.tr),
                      content: Text('delete_exam_inline_confirm'.tr),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('cancel'.tr),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onDelete();
                          },
                          child: Text(
                            'btn_delete'.tr,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )
            ],
          ),
        ],
      ),
    ),
  );

  //////

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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
        decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
                      Text('manage_questions_title'.tr,
                          style: const TextStyle(
                              fontFamily: 'bahji',
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      Text(exam.name,
                          style: const TextStyle(
                              fontFamily: 'bahji',
                              fontSize: 12,
                              color: Colors.grey),
                          overflow: TextOverflow.ellipsis),
                    ]),
              ),
              // Import from Excel / CSV · sample file · export
              PopupMenuButton<String>(
                tooltip: 'menu_import_export'.tr,
                icon: Icon(Icons.upload_file_rounded,
                    color: context.colors.primary),
                onSelected: (v) {
                  switch (v) {
                    case 'import':
                      _importQuestionsFlow(context, prov, exam);
                    case 'template':
                      _downloadTemplateFlow(context, prov);
                    case 'export':
                      _exportFlow(context, prov, exam, 'questions');
                  }
                },
                itemBuilder: (_) => [
                  _menuItem('import', Icons.upload_file_rounded,
                      'btn_import_questions'.tr),
                  _menuItem('template', Icons.description_outlined,
                      'btn_download_template'.tr),
                  _menuItem('export', Icons.download_rounded,
                      'btn_export_questions'.tr),
                ],
              ),
              // Add question button
              TextButton.icon(
                onPressed: () => _showQuestionForm(context, prov,
                    examId: exam.id, existing: null),
                icon: Icon(Icons.add_rounded,
                    size: 18, color: context.colors.primary),
                label: Text('btn_add'.tr,
                    style: TextStyle(
                        fontFamily: 'bahji',
                        fontWeight: FontWeight.w700,
                        color: context.colors.primary)),
              ),
            ]),
          ),
          const Divider(height: 16),

          // Body
          Expanded(
            child: loading ||prov.saving
                ? const Center(child: AppLoadingIndicator())
                : error != null
                ? Center(
                child:
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.wifi_off_rounded,
                      size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text(error,
                      style: const TextStyle(
                          fontFamily: 'bahji', color: Colors.grey)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => prov.loadQuestions(exam.id),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.primary),
                    child: Text('retry'.tr,
                        style: const TextStyle(fontFamily: 'bahji')),
                  ),
                ]))
                : questions.isEmpty
                ? Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.quiz_outlined,
                          size: 56, color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                      Text('no_questions_yet'.tr,
                          style: const TextStyle(
                              fontFamily: 'bahji',
                              fontSize: 15,
                              color: Colors.grey)),
                      const SizedBox(height: 6),
                      Text('no_questions_hint'.tr,
                          style: const TextStyle(
                              fontFamily: 'bahji',
                              fontSize: 12,
                              color: Colors.grey)),
                    ]))
                : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: questions.length,
              // drag-to-reorder hint (order save via API not implemented)
              itemBuilder: (_, i) {
                final q = questions[i];
                return _QuestionTile(
                  key: ValueKey(q.id),
                  question: q,
                  index: i,
                  onEdit: () => _showQuestionForm(context, prov,
                      examId: exam.id, existing: q),
                  onDelete: () => _confirmDeleteQuestion(
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
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('delete_question_title'.tr,
              style: const TextStyle(
                  fontFamily: 'bahji', fontWeight: FontWeight.w700)),
          content: Text('delete_question_title'.tr,
              style: const TextStyle(fontFamily: 'bahji')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('cancel'.tr,
                    style: const TextStyle(fontFamily: 'bahji'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text('btn_delete'.tr,
                  style: const TextStyle(fontFamily: 'bahji')),
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
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('${index + 1}',
                  style: TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: context.colors.primary)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(question.title,
                style: const TextStyle(
                    fontFamily: 'bahji',
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
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.edit_rounded,
                      color: context.colors.primary),
                  title: Text('btn_edit'.tr,
                      style: const TextStyle(fontFamily: 'bahji')),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.delete_outline,
                      color: Colors.redAccent),
                  title: Text('btn_delete'.tr,
                      style: const TextStyle(
                          fontFamily: 'bahji', color: Colors.redAccent)),
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
              final isCorrect = opt == question.correctAnswer;
              return Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isCorrect
                      ? context.colors.success.withValues(alpha: 0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isCorrect
                          ? context.colors.success.withValues(alpha: 0.4)
                          : Colors.grey.shade300),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isCorrect) ...[
                    Icon(Icons.check_circle_rounded,
                        size: 12, color: context.colors.success),
                    const SizedBox(width: 4),
                  ],
                  Text(opt,
                      style: TextStyle(
                          fontFamily: 'bahji',
                          fontSize: 12,
                          color: isCorrect
                              ? context.colors.success
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
            '${question.marks.toStringAsFixed(question.marks % 1 == 0 ? 0 : 1)} ${'marks_label'.tr}',
            style: TextStyle(
                fontFamily: 'bahji',
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
    _titleCtrl = TextEditingController(text: q?.title ?? '');
    _marksCtrl = TextEditingController(text: q?.marks.toString() ?? '1');
    _correctCtrl = TextEditingController(text: q?.correctAnswer ?? '');

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
    if (mounted) if (mounted) {
      setState(() => _optionCtrls.add(TextEditingController()));
    }
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
    final correct = _isMcq && _correctCtrl.text.trim().isNotEmpty
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
        _snack('question_added_snack'.tr, context.colors.success);
      } else {
        _snack('question_add_failed_snack'.tr, Colors.redAccent);
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
        _snack('question_updated_snack'.tr, context.colors.success);
      } else {
        _snack('question_update_failed_snack'.tr, Colors.redAccent);
      }
    }
  }

  void _snack(String msg, Color color) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'bahji')),
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
                  color: context.colors.primary),
              const SizedBox(width: 8),
              Text(
                  isEditing
                      ? 'edit_question_title'.tr
                      : 'add_question_title'.tr,
                  style: const TextStyle(
                      fontFamily: 'bahji',
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
                        label: 'field_question_text_label'.tr,
                        hint: 'field_question_text_hint'.tr,
                        maxLines: 3,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'field_required'.tr
                            : null,
                      ),
                      const SizedBox(height: 14),

                      // Marks field
                      SizedBox(
                        width: 130,
                        child: _Field(
                          ctrl: _marksCtrl,
                          label: 'field_marks_label'.tr,
                          hint: '1',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'field_required'.tr;
                            }
                            if (double.tryParse(v.trim()) == null) {
                              return 'field_invalid_number'.tr;
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 14),

                      // MCQ toggle
                      _Toggle(
                        icon: Icons.format_list_bulleted_rounded,
                        label: 'toggle_mcq'.tr,
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
                        Text('options_label'.tr,
                            style: const TextStyle(
                                fontFamily: 'bahji',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey)),
                        const SizedBox(height: 8),

                        // Option fields
                        ...List.generate(
                            _optionCtrls.length,
                                (i) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _optionCtrls[i],
                                    textDirection: TextDirection.rtl,
                                    validator: (v) =>
                                    v == null || v.trim().isEmpty
                                        ? 'field_required'.tr
                                        : null,
                                    decoration: InputDecoration(
                                      hintText: 'option_hint'
                                          .tr
                                          .replaceAll('{num}', '${i + 1}'),
                                      hintStyle: const TextStyle(
                                          fontFamily: 'bahji',
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
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ]),
                            )),

                        // Add option button
                        TextButton.icon(
                          onPressed: _addOption,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: Text('btn_add_option'.tr,
                              style: const TextStyle(
                                  fontFamily: 'bahji', fontSize: 13)),
                          style: TextButton.styleFrom(
                              foregroundColor: context.colors.primary),
                        ),

                        const SizedBox(height: 12),
                      ],
// Correct answer
                      _Field(
                        ctrl: _correctCtrl,
                        label: 'correct_answer_label'.tr,
                        hint: 'correct_answer_hint'.tr,
                      ),
                      const SizedBox(height: 20),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: prov.saving ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: prov.saving
                              ? AppLoadingIndicator(): Text(
                              isEditing
                                  ? 'btn_save_edits'.tr
                                  : 'btn_add_question'.tr,
                              style: const TextStyle(
                                  fontFamily: 'bahji',
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
  final int? initialSessionId;

  const _CreateExamSheet({required this.provider, this.initialSessionId});

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
  bool _hasDeadline = false;
  ExamRules _rules = const ExamRules(); // attempts + random-paper rules
  DateTime? _scheduleDate;
  DateTime? _deadlineDate;
  int? _sessionId; // optional: the session this exam belongs to

  @override
  void initState() {
    super.initState();
    _sessionId = widget.initialSessionId;
    if (!widget.provider.sessionsLoaded) {
      widget.provider.loadSessions().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

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
    if (mounted) if (mounted) {
      setState(() =>
      _scheduleDate = DateTime(d.year, d.month, d.day, t.hour, t.minute));
    }
  }

  Future<void> _pickDeadline() async {
    final d = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 7)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !context.mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 23, minute: 59));
    if (t == null) return;
    if (mounted) if (mounted) {
      setState(() =>
      _deadlineDate = DateTime(d.year, d.month, d.day, t.hour, t.minute));
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_hasSchedule && _scheduleDate == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('snack_pick_start_date'.tr)));
      return;
    }
    if (_hasDeadline && _deadlineDate == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('snack_pick_deadline'.tr)));
      return;
    }
    final ok = await widget.provider.createExam(
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      sessionId: _sessionId,
      startDate: _hasSchedule ? _scheduleDate : null,
      endDate: _hasDeadline ? _deadlineDate : null,
      duration: int.tryParse(_durationCtrl.text),
      totalMarks: double.tryParse(_totalMarksCtrl.text),
      passingScore: double.tryParse(_passingCtrl.text),
      passcode: _hasPasscode && _passcodeCtrl.text.trim().isNotEmpty
          ? _passcodeCtrl.text.trim()
          : null,
      maxSubmissions: _rules.maxSubmissions, // 0 = unlimited
      questionsPerStudent: _rules.questionsPerStudent,
      shuffleQuestions: _rules.shuffleQuestions,
      shuffleOptions: _rules.shuffleOptions,
    );
    if (ok && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Container(
      decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding:
      EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            Icon(Icons.add_circle_outline_rounded,
                color: context.colors.primary),
            SizedBox(width: 8),
            Text('create_exam_sheet_title'.tr,
                style: const TextStyle(
                    fontFamily: 'bahji',
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
                    label: 'field_exam_name_label'.tr,
                    hint: 'field_exam_name_hint'.tr,
                    validator: (v) =>
                    v!.isEmpty ? 'field_required'.tr : null),
                const SizedBox(height: 12),
                _Field(
                    ctrl: _descCtrl,
                    label: 'field_desc_optional_label'.tr,
                    hint: 'field_desc_hint_short'.tr,
                    maxLines: 2),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _Field(
                          ctrl: _totalMarksCtrl,
                          label: 'field_total_marks_label'.tr,
                          hint: '100',
                          keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _Field(
                          ctrl: _passingCtrl,
                          label: 'field_passing_label'.tr,
                          hint: '60',
                          keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _Field(
                          ctrl: _durationCtrl,
                          label: 'field_duration_label'.tr,
                          hint: '60',
                          keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 14),
                // ── Attach to a session (optional) ─────────────────────
                if (widget.provider.sessions.isNotEmpty) ...[
                  DropdownButtonFormField<int?>(
                    initialValue: _sessionId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'field_exam_session_label'.tr,
                      labelStyle: const TextStyle(
                          fontFamily: 'bahji', fontSize: 13, color: Colors.grey),
                      prefixIcon: Icon(Icons.play_lesson_rounded,
                          size: 20, color: context.colors.primary),
                      filled: true,
                      fillColor: context.colors.inputBg,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade200)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text('exam_no_session'.tr,
                            style: const TextStyle(fontFamily: 'bahji')),
                      ),
                      for (final s in widget.provider.sessions)
                        DropdownMenuItem<int?>(
                          value: s.id,
                          child: Text(s.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'bahji')),
                        ),
                    ],
                    onChanged: (v) {
                      if (mounted) setState(() => _sessionId = v);
                    },
                  ),
                  if (_sessionId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 4, left: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 15, color: context.colors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'exam_session_gate_hint'.tr,
                              style: TextStyle(
                                  fontFamily: 'bahji',
                                  fontSize: 12,
                                  color: context.colors.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                ],
                _Toggle(
                  icon: Icons.lock_outline_rounded,
                  label: 'toggle_passcode'.tr,
                  value: _hasPasscode,
                  onChanged: (v) {
                    if (mounted) if (mounted) {
                      setState(() => _hasPasscode = v);
                    }
                  },
                  child: _hasPasscode
                      ? _Field(
                      ctrl: _passcodeCtrl,
                      label: 'field_passcode_label'.tr,
                      hint: '123456',
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      validator: _hasPasscode
                          ? (v) => v!.isEmpty
                          ? 'field_required'.tr
                          : !RegExp(r'^\d+$').hasMatch(v)
                          ? 'passcode_digits_only'.tr
                          : null
                          : null)
                      : null,
                ),
                const SizedBox(height: 10),
                _Toggle(
                  icon: Icons.schedule_rounded,
                  label: 'toggle_schedule'.tr,
                  value: _hasSchedule,
                  onChanged: (v) {
                    if (mounted) if (mounted) {
                      setState(() => _hasSchedule = v);
                    }
                  },
                  child: _hasSchedule
                      ? GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                          border:
                          Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 18, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          _scheduleDate != null
                              ? '${_scheduleDate!.day}/${_scheduleDate!.month}/${_scheduleDate!.year}  '
                              '${_scheduleDate!.hour.toString().padLeft(2, '0')}:${_scheduleDate!.minute.toString().padLeft(2, '0')}'
                              : 'pick_start_datetime'.tr,
                          style: TextStyle(
                              fontFamily: 'bahji',
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
                const SizedBox(height: 10),
                // ── Deadline (end_date) ────────────────────────────────────
                _Toggle(
                  icon: Icons.hourglass_bottom_rounded,
                  label: 'toggle_deadline'.tr,
                  value: _hasDeadline,
                  onChanged: (v) {
                    if (mounted) if (mounted) {
                      setState(() => _hasDeadline = v);
                    }
                  },
                  child: _hasDeadline
                      ? GestureDetector(
                    onTap: _pickDeadline,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors.orange.shade300),
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        Icon(Icons.event_busy_rounded,
                            size: 18, color: Colors.orange.shade600),
                        const SizedBox(width: 8),
                        Text(
                          _deadlineDate != null
                              ? '${_deadlineDate!.day}/${_deadlineDate!.month}/${_deadlineDate!.year}  '
                              '${_deadlineDate!.hour.toString().padLeft(2, '0')}:${_deadlineDate!.minute.toString().padLeft(2, '0')}'
                              : 'pick_deadline'.tr,
                          style: TextStyle(
                              fontFamily: 'bahji',
                              fontSize: 14,
                              color: _deadlineDate != null
                                  ? context.colors.textDark
                                  : Colors.grey),
                        ),
                      ]),
                    ),
                  )
                      : null,
                ),
                const SizedBox(height: 10),
                // ── Attempts + per-student random papers ──────────────────
                _ExamRulesFields(
                  initial: _rules,
                  onChanged: (r) => _rules = r,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.provider.saving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: widget.provider.saving
                        ? const  AppLoadingIndicator(): Text('btn_create_exam'.tr,
                        style: const TextStyle(
                            fontFamily: 'bahji',
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
// _SessionPickerSheet — attach an exam to a session / detach it
// ══════════════════════════════════════════════════════════════════════════════

class _SessionPickerSheet extends StatelessWidget {
  final List<SessionOption> sessions;
  final int? selectedId;

  const _SessionPickerSheet({required this.sessions, required this.selectedId});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius:
          const BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(children: [
              Icon(Icons.play_lesson_rounded, color: context.colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('exam_pick_session_title'.tr,
                    style: const TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('exam_session_gate_hint'.tr,
                style: const TextStyle(
                    fontFamily: 'bahji', fontSize: 12, color: Colors.grey)),
          ),
          const Divider(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                _tile(context, -1, 'exam_no_session'.tr,
                    Icons.link_off_rounded, selectedId == null),
                for (final s in sessions)
                  _tile(context, s.id, s.name, Icons.play_circle_outline_rounded,
                      selectedId == s.id),
                if (sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('no_sessions_yet'.tr,
                          style: const TextStyle(
                              fontFamily: 'bahji', color: Colors.grey)),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    ),
  );

  Widget _tile(BuildContext context, int value, String label, IconData icon,
      bool selected) =>
      ListTile(
        leading: Icon(icon,
            color: selected ? context.colors.primary : Colors.grey),
        title: Text(label,
            style: TextStyle(
                fontFamily: 'bahji',
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? context.colors.primary : null)),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: context.colors.primary)
            : null,
        onTap: () => Navigator.pop(context, value),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
              context.colors.primary.withValues(alpha: 0.1),
              backgroundImage: result.studentImage != null
                  ? NetworkImage(result.studentImage!)
                  : null,
              child: result.studentImage == null
                  ? Text(result.studentName[0],
                  style: TextStyle(
                      color: context.colors.primary,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'bahji'))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.studentName,
                        style: const TextStyle(
                            fontFamily: 'bahji',
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    Text(
                        '${result.marksObtained?.toStringAsFixed(0) ?? 0} / '
                            '${result.totalMarks?.toStringAsFixed(0) ?? 0} ${'marks_label'.tr}'
                            '  •  ${result.percentage?.toStringAsFixed(1) ?? 0}%',
                        style: const TextStyle(
                            fontFamily: 'bahji',
                            fontSize: 13,
                            color: Colors.grey)),
                  ]),
            ),
            _StatusBadge(
                result.passed == true
                    ? 'result_passed_badge'.tr
                    : 'result_failed_badge'.tr,
                result.passed == true
                    ? context.colors.success
                    : Colors.redAccent),
          ]),
        ),
        const Divider(height: 20),
        Expanded(
          child: result.answers.isEmpty
              ? Center(
              child: Text('no_answers'.tr,
                  style: const TextStyle(
                      fontFamily: 'bahji', color: Colors.grey)))
              : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              itemCount: result.answers.length,
              itemBuilder: (_, i) {
                final a = result.answers[i];
                final correct = a.isCorrect == true;
                final color =
                correct ? context.colors.success : Colors.redAccent;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border:
                    Border.all(color: color.withValues(alpha: 0.3)),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${'question_prefix'.tr} ${a.questionId}',
                                style: const TextStyle(
                                    fontFamily: 'bahji',
                                    fontSize: 12,
                                    color: Colors.grey)),
                            Text(a.answer ?? 'no_answer_given'.tr,
                                style: const TextStyle(
                                    fontFamily: 'bahji',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                          ]),
                    ),
                    Text(
                        '${a.marksObtained?.toStringAsFixed(1) ?? 0} ${'marks_label'.tr}',
                        style: TextStyle(
                            fontFamily: 'bahji',
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
        ? context.colors.success
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
                    fontFamily: 'bahji',
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
                    color: context.colors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5)),
              ),
            ),
        ]),
        title: Text(result.studentName,
            style: const TextStyle(
                fontFamily: 'bahji',
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        subtitle:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          Row(children: [
            _StatusBadge(
                result.isAttended ? 'attended_badge'.tr : 'absent_badge'.tr,
                result.isAttended ? context.colors.success : Colors.redAccent),
            const SizedBox(width: 6),
            if (result.attempted)
              _StatusBadge(
                  passed == true
                      ? 'result_passed_badge'.tr
                      : 'result_failed_badge'.tr,
                  color)
            else
              _StatusBadge('not_attempted_badge'.tr, Colors.grey),
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
        trailing:
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(pct != null ? '${pct.toStringAsFixed(0)}%' : '—',
              style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color)),
          if (result.attempted)
            GestureDetector(
              onTap: onViewAnswers,
              child: Text('view_answers_btn'.tr,
                  style: TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 11,
                      color: context.colors.primary,
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
            fontFamily: 'bahji',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color)),
  );
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
              fontFamily: 'bahji',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color)),
      Text(label,
          style: const TextStyle(
              fontFamily: 'bahji', fontSize: 10, color: Colors.grey)),
    ]),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.ctrl,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: ctrl,
    maxLines: maxLines,
    maxLength: maxLength,
    keyboardType: keyboardType,
    textDirection: TextDirection.rtl,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
          fontFamily: 'bahji', fontSize: 13, color: Colors.grey),
      hintStyle: const TextStyle(fontFamily: 'bahji', color: Colors.grey),
      filled: true,
      fillColor: context.colors.inputBg,
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
        leading: Icon(icon, color: context.colors.primary, size: 20),
        title: Text(label,
            style: const TextStyle(
                fontFamily: 'bahji',
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        trailing: Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: context.colors.primary),
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
      Text(message ?? 'error_occurred'.tr,
          style: const TextStyle(
              fontFamily: 'bahji', fontSize: 14, color: Colors.grey)),
      const SizedBox(height: 12),
      ElevatedButton(
          onPressed: onRetry,
          style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          child: Text('retry'.tr,
              style: const TextStyle(
                  fontFamily: 'bahji', color: Colors.white))),
    ]),
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'bahji',
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModernActionBtn extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ModernActionBtn({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        height: 52,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'bahji',
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
// Shared helpers — menu item, toast, import / export flows
// ══════════════════════════════════════════════════════════════════════════════

PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
    PopupMenuItem<String>(
      value: value,
      child: Row(children: [
        Icon(icon, size: 18, color: Colors.grey.shade700),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(fontFamily: 'bahji', fontSize: 13)),
      ]),
    );

void _toast(BuildContext context, String msg, Color color) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontFamily: 'bahji')),
    backgroundColor: color,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

/// Pick an .xlsx / .csv, upload it, show what was imported / skipped.
Future<void> _importQuestionsFlow(
    BuildContext context, TeacherExamProvider prov, ExamModel exam) async {
  final file = await pickQuestionsFile();
  if (file == null || !context.mounted) return;
  final out = await prov.importQuestions(exam.id, file);
  if (!context.mounted) return;
  if (out.result == null) {
    _toast(context, out.error ?? 'import_failed_snack'.tr, Colors.redAccent);
    return;
  }
  await showDialog(
    context: context,
    builder: (_) => _ImportResultDialog(result: out.result!),
  );
}

Future<void> _downloadTemplateFlow(
    BuildContext context, TeacherExamProvider prov) async {
  final err = await prov.downloadTemplate();
  _toast(context, err ?? 'template_saved_snack'.tr,
      err == null ? context.colors.success : Colors.redAccent);
}

/// kind: questions | marks | answers | all
Future<void> _exportFlow(BuildContext context, TeacherExamProvider prov,
    ExamModel exam, String kind) async {
  final err = await prov.exportExam(exam.id, kind);
  _toast(context, err ?? 'export_saved_snack'.tr,
      err == null ? context.colors.success : Colors.redAccent);
}

class _ImportResultDialog extends StatelessWidget {
  final ImportResult result;
  const _ImportResultDialog({required this.result});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('import_result_title'.tr,
          style: const TextStyle(
              fontFamily: 'bahji', fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${'import_added_label'.tr}: ${result.created}',
                style: TextStyle(
                    fontFamily: 'bahji',
                    fontWeight: FontWeight.w700,
                    color: context.colors.success)),
            if (result.skipped > 0) ...[
              const SizedBox(height: 6),
              Text('${'import_skipped_label'.tr}: ${result.skipped}',
                  style: const TextStyle(
                      fontFamily: 'bahji',
                      fontWeight: FontWeight.w700,
                      color: Colors.redAccent)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in result.errors)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                            '${'import_row_label'.tr} ${e.row}: ${e.message}',
                            style: const TextStyle(
                                fontFamily: 'bahji',
                                fontSize: 12,
                                color: Colors.grey)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('btn_ok'.tr,
              style: const TextStyle(fontFamily: 'bahji')),
        ),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Exam rules — attempts (unlimited / limited) + per-student random papers
// ══════════════════════════════════════════════════════════════════════════════

/// Attempts and random-paper switches. Reports every change through
/// [onChanged] (no setState needed in the parent). Put it inside a [Form]:
/// the number fields validate themselves.
class _ExamRulesFields extends StatefulWidget {
  final ExamRules initial;
  final ValueChanged<ExamRules> onChanged;

  /// Number of questions in the pool, when known (only used for a warning).
  final int? poolSize;

  const _ExamRulesFields({
    required this.initial,
    required this.onChanged,
    this.poolSize,
  });

  @override
  State<_ExamRulesFields> createState() => _ExamRulesFieldsState();
}

class _ExamRulesFieldsState extends State<_ExamRulesFields> {
  late bool _limitAttempts;
  late bool _limitQuestions;
  late bool _shuffleQ;
  late bool _shuffleO;
  late final TextEditingController _attemptsCtrl;
  late final TextEditingController _perStudentCtrl;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _limitAttempts = !r.unlimitedAttempts;
    _limitQuestions = r.questionsPerStudent != null;
    _shuffleQ = r.shuffleQuestions;
    _shuffleO = r.shuffleOptions;
    _attemptsCtrl =
        TextEditingController(text: _limitAttempts ? '${r.maxSubmissions}' : '1');
    _perStudentCtrl = TextEditingController(
        text: _limitQuestions ? '${r.questionsPerStudent}' : '10');
    _attemptsCtrl.addListener(_emit);
    _perStudentCtrl.addListener(() {
      _emit();
      if (mounted) setState(() {}); // refresh the "more than the pool" warning
    });
  }

  @override
  void dispose() {
    _attemptsCtrl.dispose();
    _perStudentCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final attempts = int.tryParse(_attemptsCtrl.text.trim());
    final perStudent = int.tryParse(_perStudentCtrl.text.trim());
    widget.onChanged(ExamRules(
      maxSubmissions:
      _limitAttempts ? (attempts != null && attempts > 0 ? attempts : 1) : 0,
      questionsPerStudent: _limitQuestions && perStudent != null && perStudent > 0
          ? perStudent
          : null,
      shuffleQuestions: _shuffleQ,
      shuffleOptions: _shuffleO,
    ));
  }

  void _set(VoidCallback change) {
    setState(change);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(_perStudentCtrl.text.trim());
    final pool = widget.poolSize;
    final tooMany =
        _limitQuestions && n != null && pool != null && pool > 0 && n > pool;
    const hintStyle =
    TextStyle(fontFamily: 'bahji', fontSize: 12, color: Colors.grey);

    return Column(children: [
      // ── Attempts: unlimited (off) or limited to N (on) ─────────────────────
      _Toggle(
        icon: Icons.repeat_rounded,
        label: 'toggle_max_submissions'.tr,
        value: _limitAttempts,
        onChanged: (v) => _set(() => _limitAttempts = v),
        child: _limitAttempts
            ? _Field(
          ctrl: _attemptsCtrl,
          label: 'field_max_submissions_label'.tr,
          hint: '1',
          keyboardType: TextInputType.number,
          validator: (v) {
            final x = int.tryParse(v ?? '');
            return (x == null || x < 1)
                ? 'field_max_submissions_error'.tr
                : null;
          },
        )
            : null,
      ),
      if (!_limitAttempts)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('attempts_unlimited_hint'.tr, style: hintStyle),
          ),
        ),
      const SizedBox(height: 10),

      // ── How many questions each student gets ───────────────────────────────
      _Toggle(
        icon: Icons.filter_list_rounded,
        label: 'toggle_limit_questions'.tr,
        value: _limitQuestions,
        onChanged: (v) => _set(() => _limitQuestions = v),
        child: _limitQuestions
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Field(
            ctrl: _perStudentCtrl,
            label: 'field_questions_per_student_label'.tr,
            hint: '10',
            keyboardType: TextInputType.number,
            validator: (v) {
              final x = int.tryParse(v ?? '');
              return (x == null || x < 1)
                  ? 'field_questions_per_student_error'.tr
                  : null;
            },
          ),
          const SizedBox(height: 8),
          Text(
            tooMany
                ? 'questions_exceed_pool_warning'.tr
                : 'questions_per_student_hint'.tr,
            style: hintStyle.copyWith(
                color: tooMany ? Colors.orange.shade800 : Colors.grey),
          ),
        ])
            : null,
      ),
      const SizedBox(height: 10),

      // ── Random order ────────────────────────────────────────────────────────
      _Toggle(
        icon: Icons.shuffle_rounded,
        label: 'toggle_shuffle_questions'.tr,
        value: _shuffleQ,
        onChanged: (v) => _set(() => _shuffleQ = v),
      ),
      const SizedBox(height: 10),
      _Toggle(
        icon: Icons.sort_rounded,
        label: 'toggle_shuffle_options'.tr,
        value: _shuffleO,
        onChanged: (v) => _set(() => _shuffleO = v),
      ),
    ]);
  }
}

/// Edit the rules of an existing exam (opened from the card's chips / ⋮ menu).
class _ExamRulesSheet extends StatefulWidget {
  final TeacherExamProvider provider;
  final ExamModel exam;

  const _ExamRulesSheet({required this.provider, required this.exam});

  @override
  State<_ExamRulesSheet> createState() => _ExamRulesSheetState();
}

class _ExamRulesSheetState extends State<_ExamRulesSheet> {
  final _form = GlobalKey<FormState>();
  late ExamRules _rules;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.exam;
    _rules = ExamRules(
      maxSubmissions: e.maxSubmissions ?? 0,
      questionsPerStudent: e.questionsPerStudent,
      shuffleQuestions: e.shuffleQuestions,
      shuffleOptions: e.shuffleOptions,
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final err = await widget.provider.updateExamRules(widget.exam, _rules);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(context, err ?? 'exam_rules_saved_snack'.tr,
        err == null ? context.colors.success : Colors.redAccent);
    if (err == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Container(
      decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius:
          const BorderRadius.vertical(top: Radius.circular(24))),
      padding:
      EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            Icon(Icons.tune_rounded, color: context.colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('exam_rules_title'.tr,
                  style: const TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        const Divider(height: 20),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Form(
              key: _form,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('exam_rules_apply_note'.tr,
                      style: const TextStyle(
                          fontFamily: 'bahji',
                          fontSize: 12,
                          color: Colors.grey)),
                ),
                _ExamRulesFields(
                  initial: _rules,
                  poolSize: widget.exam.questionCount,
                  onChanged: (r) => _rules = r,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _busy
                        ? const AppLoadingIndicator()
                        : Text('btn_save_changes'.tr,
                        style: const TextStyle(
                            fontFamily: 'bahji',
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