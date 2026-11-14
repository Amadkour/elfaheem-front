// features/teacher/exam/teacher_exam_hub_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart' show deferredBubbleHome, deferredExamsHome;
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/features/exams/legacy/student/exam_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/legacy/exam_model.dart';
import 'package:flutter_education_app/features/exams/legacy/teacher/exam_files.dart';
import 'package:flutter_education_app/features/exams/legacy/teacher/teacher_exam_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/analytics/teacher/teacher_stat_band.dart';
import 'package:flutter_education_app/features/courses/teacher/component/number_pair.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/features/exams/exam_review_screen.dart' show EngineReviewSection;
import 'package:flutter_education_app/features/exams/exam_authoring.dart' show ExamAuthoringApi;
import 'package:flutter_education_app/features/exams/exam_quick_screen.dart' show openQuickExam;
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';

class TeacherExamHubScreen extends StatelessWidget {
  final int courseId;
  final String courseTitle;

  /// When set, the "new exam" sheet pre-selects this session.
  final int? initialSessionId;

  /// When true, the CLASSIC "new exam" sheet (live quiz in the room, legacy Excel) opens automatically as soon as the
  /// hub appears (the session menu's "Classic exam" link, and its fallback when the Exam Engine is unavailable).
  final bool openCreateOnStart;

  const TeacherExamHubScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
    this.initialSessionId,
    this.openCreateOnStart = false,
    this.orgId,
  });

  /// The course's organization when the caller knows it (the engine's exam list is asked under it at once).
  final int? orgId;

  @override
  Widget build(BuildContext context) {
    ExamAuthoringApi.knowScope(courseId, orgId);
    return _build(context);
  }

  Widget _build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => TeacherExamProvider(courseId: courseId)..loadExams(),
    child: _HubView(
      orgId: orgId,
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
  final int? orgId;

  const _HubView({
    required this.courseTitle,
    this.initialSessionId,
    this.openCreateOnStart = false,
    this.orgId,
  });

  @override
  State<_HubView> createState() => _HubViewState();
}

class _HubViewState extends State<_HubView>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _engineExams = const [];      // the Exam Engine section's exams (counted in the header)
  bool? _engineOk;                                          // the engine answered for this course (null = not asked yet)
  // A result's student chip opens the student in the shared panel (D-290); the card itself still opens the answers.
  final _panel = EntityPanelController(rowKind: EntityKind.student);

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
        if (mounted) _showCreateSheet(context);      // the classic sheet: the session menu's "Classic exam" link and its fallback
      });
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _panel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherExamProvider>();
    if (_tab.index != prov.tab) _tab.animateTo(prov.tab);

    return BasePage(
      key: const ValueKey('teacher_exams_hub'),
      useWebCard: true,
      width: AppWidth.wide,
      appBar: AppHeader(
        title: 'exam_hub_title'.tr,
        subtitle: widget.courseTitle,
        actions: [
          // correct bubble sheets, any sheet, a whole class (D-340)
          ParentComponent(
            featureKey: 'exam.bubble',
            child: IconButton(
              key: const ValueKey('exam_hub.bubble'),
              icon: Icon(Icons.grading_rounded, color: context.colors.primary),
              tooltip: AppConfig.lang == 'ar' ? 'تصحيح أوراق التظليل' : 'Correct bubble sheets',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => deferredBubbleHome(courseId: prov.courseId, courseTitle: widget.courseTitle, orgId: widget.orgId))),
            ),
          ),
          // every exam across the courses (D-300)
          ParentComponent(
            featureKey: 'exam.all_exams',
            child: IconButton(
              key: const ValueKey('exam_hub.all_exams'),
              icon: Icon(Icons.fact_check_rounded, color: context.colors.primary),
              tooltip: AppConfig.lang == 'ar' ? 'كل الاختبارات' : 'All exams',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => deferredExamsHome())),
            ),
          ),
        ],
      ),
      floatingActionButton: prov.tab == 0
          ? FloatingActionButton.extended(
              heroTag: "teacher_exam_float",
              key: const ValueKey("teacher_exam_float"),
              onPressed: _newExam,
              backgroundColor: context.colors.primary,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              icon: Icon(Icons.add_rounded, color: context.colors.onHero),
              label: Text(
                'new_exam'.tr,
                style: examT(14, w: FontWeight.w800, c: context.colors.onHero),
              ),
            )
          : null,
      child: MasterDetailScaffold(
      controller: _panel,
      rootLabel: 'tab_student_results'.tr,
      list: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverToBoxAdapter(child: _buildHero(prov)),
          SliverPersistentHeader(
            pinned: true,
            delegate: ExamTabsDelegate(
              controller: _tab,
              tabs: [
                examTab(Icons.quiz_rounded, 'tab_exams'.tr),
                examTab(Icons.bar_chart_rounded, 'tab_student_results'.tr),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tab,
          children: [_buildExamsTab(prov), _buildResultsTab(prov)],
        ),
      ),
      ),
    );
  }

  // ── Hero ────────────────────────────────────────────────────────────────────
  Widget _buildHero(TeacherExamProvider prov) {
    // the Exam Engine's exams of the course count too (the section above the legacy list reports them)
    final published = prov.exams.where((e) => e.isPublished).length + _engineExams.where((e) => e['status'] == 'published').length;
    final third = examHubThirdStat(prov.exams, _engineExams);
    return TeacherStatBand(stats: [
      HeroStat(
        icon: Icons.quiz_rounded,
        color: context.colors.heroTint(context.colors.primaryLight, 0.5),
        value: '${prov.exams.length + _engineExams.length}',
        label: 'tab_exams'.tr,
      ),
      HeroStat(
        icon: Icons.public_rounded,
        color: context.colors.success,
        value: '$published',
        label: 'exam_published_badge'.tr,
      ),
      HeroStat(
        icon: third.icon,
        color: context.colors.accent,
        value: third.value,
        label: third.label,
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Tab 1 — Exams list
  // ══════════════════════════════════════════════════════════════════════════

  // Exam Engine exams (Phase 6 review) sit above the legacy list; the section hides itself when there are none.
  // ONE scroll for the tab: the engine exams at their natural height, then the legacy ones (the engine list used to sit
  // in a box of a quarter of the screen, cut after two and a half rows with the space under it empty).
  Widget _buildExamsTab(TeacherExamProvider prov) => CustomScrollView(
        key: const ValueKey('teacher_exams_tab_scroll'),
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: EngineReviewSection(
              courseId: prov.courseId,
              showCreate: false,                                   // ONE entry: the "New exam" button (D-197)
              onAvailable: (ok) {
                if (ok) _engineOk = true;       // a failure is asked again on the tap (it may have been the network)
              },
              onItems: (items) {
                if (mounted) setState(() => _engineExams = items);
              },
            ),
          ),
          _legacyExamsSliver(prov),
          const SliverToBoxAdapter(child: SizedBox(height: 96)), // clear of the "New exam" button
        ],
      );

  Widget _legacyExamsSliver(TeacherExamProvider prov) {
    Widget box(Widget child, {double top = 0}) => SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: top), child: child));
    if (prov.loadingExams) {
      return box(const AppListSkeleton(withAvatar: false));
    }
    if (prov.examsError != null && prov.exams.isEmpty) {
      return box(_ErrorView(message: prov.examsError, onRetry: prov.loadExams), top: 48);
    }
    if (prov.exams.isEmpty) {
      if (_engineExams.isNotEmpty) return const SliverToBoxAdapter();     // the engine section above lists them
      return box(
        ExamEmpty(
          icon: Icons.quiz_outlined,
          text: '${'no_exams_yet'.tr}\n${'no_exams_empty_hint'.tr}',
        ),
        top: 48,
      );
    }
    final isWide = MediaQuery.of(context).size.width > 720;
    if (!isWide) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        sliver: SliverList.separated(
          itemCount: prov.exams.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (_, i) => _examCard(prov, prov.exams[i]),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: SliverToBoxAdapter(
        child: LayoutBuilder(
          builder: (_, box) {
            const gap = 14.0;
            final w = (box.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final e in prov.exams)
                  SizedBox(width: w, child: _examCard(prov, e)),
              ],
            );
          },
        ),
      ),
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
    final c = context.colors;
    if (prov.selectedExam == null) {
      return ExamEmpty(
        icon: Icons.bar_chart_rounded,
        text: 'select_exam_to_view_results'.tr,
      );
    }
    if (prov.loadingResults) {
      return const AppListSkeleton(withAvatar: false);
    }
    if (prov.resultsError != null) {
      return _ErrorView(
        message: prov.resultsError,
        onRetry: () => prov.loadResults(prov.selectedExam!),
      );
    }

    return Column(
      children: [
        // Summary header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ExamCard(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconTile(Icons.bar_chart_rounded, c.primary, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        prov.selectedExam!.name,
                        style: examT(15, w: FontWeight.w800, c: c.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'menu_export'.tr,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      icon: Icon(
                        Icons.file_download_outlined,
                        color: c.primary,
                      ),
                      onSelected: (kind) =>
                          _exportFlow(context, prov, prov.selectedExam!, kind),
                      itemBuilder: (_) => [
                        _menuItem(
                          'marks',
                          Icons.grading_rounded,
                          'menu_export_marks'.tr,
                        ),
                        _menuItem(
                          'answers',
                          Icons.fact_check_outlined,
                          'menu_export_answers'.tr,
                        ),
                        _menuItem(
                          'all',
                          Icons.table_view_rounded,
                          'menu_export_all'.tr,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Row(
                    children: [
                      _MiniStat(
                        '${prov.results.length}',
                        'stat_enrolled'.tr,
                        c.primary,
                      ),
                      _MiniStat(
                        '${prov.attendedCount}',
                        'stat_attended'.tr,
                        c.success,
                      ),
                      _MiniStat(
                        '${prov.attemptedCount}',
                        'stat_answered'.tr,
                        c.warning,
                      ),
                      _MiniStat(
                        '${prov.passedCount}',
                        'stat_passed'.tr,
                        c.primaryLight,
                      ),
                      _MiniStat(
                        '${prov.avgScore.toStringAsFixed(0)}%',
                        'stat_average'.tr,
                        c.purple,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: prov.results.isEmpty
              ? ExamEmpty(
                  icon: Icons.people_outline_rounded,
                  text: 'no_results_yet'.tr,
                )
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                  itemCount: prov.results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ResultTile(
                    result: prov.results[i],
                    onViewAnswers: () =>
                        _showAnswers(prov.results[i], prov.selectedExam!),
                  ),
                ),
        ),
      ],
    );
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
          ? context.colors.danger
          : (exam.isPublished ? context.colors.success : context.colors.warning),
    );
  }

  Future<void> _confirmDelete(TeacherExamProvider prov, int examId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: Helpers.pageDirection,
        child: AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            'delete_exam_title'.tr,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'delete_exam_confirm_body'.tr,
            style: TextStyle(fontFamily: AppFonts.display),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'cancel'.tr,
                style: TextStyle(fontFamily: AppFonts.display),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.dangerBase,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'btn_delete'.tr,
                style: TextStyle(fontFamily: AppFonts.display),
              ),
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
          deleted ? context.colors.success : context.colors.danger,
        );
      }
    }
  }

  /// ONE "New exam" entry (D-197): the quick builder; the legacy sheet (live quiz in the room, legacy Excel) opens from
  /// its quiet "Classic exam" link, or here when the engine is unavailable for this course.
  Future<void> _newExam() async {
    final courseId = context.read<TeacherExamProvider>().courseId;
    if (_engineOk != true) {
      final r = (await ExamAuthoringApi().resolveScope(courseId)).list;
      if (!mounted) return;
      if (r.ok) {
        _engineOk = true;
      } else if (r.unavailable || r.code != null || r.status == 403) {
        // the engine is not deployed or refuses this course: the legacy sheet, as before D-197
        return _showCreateSheet(context);
      } else {
        // the network or a server error: not a reason to drop the teacher into the old form
        showAppNotice(AppConfig.lang == 'ar' ? 'تعذّر الوصول إلى الخادم، حاول مرة أخرى' : 'Could not reach the server, try again', error: true);
        return;
      }
    }
    await openQuickExam(context,
        courseId: courseId,
        sessionId: widget.initialSessionId,
        course: widget.courseTitle,
        onClassic: () {
          if (mounted) _showCreateSheet(context);
        });
  }

  void _showCreateSheet(BuildContext ctx) => showAppSideSheet(
      ctx,
      withCloseBar: true,
      builder: (_) => _CreateExamSheet(
      provider: ctx.read<TeacherExamProvider>(),
      initialSessionId: widget.initialSessionId,
    ),
  );

  /// Attach the exam to a session (or detach it). Students must PASS a
  /// published, attached exam before the sessions after it unlock.
  Future<void> _showSessionPicker(
    TeacherExamProvider prov,
    ExamModel exam,
  ) async {
    if (!prov.sessionsLoaded) await prov.loadSessions();
    if (!mounted) return;
    // -1 = "no session" (detach); null = dismissed
    final picked = await showAppSideSheet<int>(
      context,
      withCloseBar: true,
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
      err ??
          (newId == null
              ? 'exam_session_detached'.tr
              : 'exam_session_attached'.tr),
      err == null ? context.colors.success : context.colors.danger,
    );
  }

  void _showQuestionsSheet(
    BuildContext ctx,
    TeacherExamProvider prov,
    ExamModel exam,
  ) {
    // Load questions if not already loaded
    prov.loadQuestions(exam.id);
    showAppSideSheet(
      ctx,
      withCloseBar: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: prov,
        child: _ManageQuestionsSheet(exam: exam),
      ),
    );
  }

  void _showAnswers(StudentExamResult r, ExamModel exam) =>
      showAppSideSheet(
      context,
      withCloseBar: true,
      builder: (_) => _AnswersSheet(result: r, exam: exam),
      );

  /// Attempts + random-paper rules of an existing exam.
  void _showRulesSheet(TeacherExamProvider prov, ExamModel exam) =>
      showAppSideSheet(
      context,
      withCloseBar: true,
      builder: (_) => _ExamRulesSheet(provider: prov, exam: exam),
      );

  void _snack(String msg, Color color) =>
      showAppNotice(msg);
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
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = exam.isPublished ? c.success : c.warning;

    return ExamCard(
      borderColor: accent.withValues(alpha: .22),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(Icons.quiz_rounded, accent, size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: examT(
                        16,
                        w: FontWeight.w800,
                        c: c.textDark,
                        h: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ExamBadge(
                      exam.isPublished
                          ? 'exam_published_badge'.tr
                          : 'exam_unpublished_badge'.tr,
                      accent,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 34,
                height: 34,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 22,
                    color: c.textMedium,
                  ),
                  onSelected: (v) => v == 'rules' ? onEditRules() : onExport(v),
                  itemBuilder: (_) => [
                    _menuItem(
                      'rules',
                      Icons.tune_rounded,
                      'menu_exam_settings'.tr,
                    ),
                    const PopupMenuDivider(),
                    _menuItem(
                      'questions',
                      Icons.quiz_outlined,
                      'menu_export_questions'.tr,
                    ),
                    _menuItem(
                      'marks',
                      Icons.grading_rounded,
                      'menu_export_marks'.tr,
                    ),
                    _menuItem(
                      'answers',
                      Icons.fact_check_outlined,
                      'menu_export_answers'.tr,
                    ),
                    _menuItem(
                      'all',
                      Icons.table_view_rounded,
                      'menu_export_all'.tr,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (exam.description != null && exam.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              exam.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: examT(12.5, c: c.textMedium, h: 1.6),
            ),
          ],

          const SizedBox(height: 14),

          // ── Info chips ─────────────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ExamChip(
                Icons.help_outline_rounded,
                '${exam.questionCount} ${'question_count_chip'.tr.split(' ').last}',
                context.colors.primary,
              ),
              ExamChip(
                Icons.timer_outlined,
                '${exam.duration ?? 0} ${'duration_chip'.tr.split(' ').last}',
                context.colors.success,
              ),
              // Which session this exam gates (tap to change / detach).
              GestureDetector(
                onTap: onPickSession,
                child: ExamChip(
                  Icons.play_lesson_rounded,
                  exam.sessionId == null
                      ? 'exam_no_session'.tr
                      : _shorten(sessionName ?? 'session'.tr),
                  exam.sessionId == null ? context.colors.textLight : c.primary,
                ),
              ),
              // Attempts + random-paper rules (tap to edit).
              GestureDetector(
                onTap: onEditRules,
                child: ExamChip(
                  Icons.repeat_rounded,
                  (exam.maxSubmissions ?? 0) > 0
                      ? '${'chip_attempts_label'.tr}: ${exam.maxSubmissions}'
                      : 'chip_attempts_unlimited'.tr,
                  context.colors.primary,
                ),
              ),
              if (exam.questionsPerStudent != null)
                GestureDetector(
                  onTap: onEditRules,
                  child: ExamChip(
                    Icons.filter_list_rounded,
                    '${'chip_random_questions_label'.tr}: ${exam.questionsPerStudent} / ${exam.questionCount}',
                    c.purple,
                  ),
                ),
              if (exam.shuffleQuestions || exam.shuffleOptions)
                GestureDetector(
                  onTap: onEditRules,
                  child: ExamChip(
                    Icons.shuffle_rounded,
                    'chip_shuffled_label'.tr,
                    c.purple,
                  ),
                ),
              if (exam.passcode != null)
                ExamChip(
                  Icons.lock_outline_rounded,
                  exam.passcode!,
                  context.colors.purple,
                ),
              if (exam.startDate != null)
                ExamChip(
                  Icons.schedule_rounded,
                  _fmtDate(exam.startDate!),
                  c.warning,
                ),
            ],
          ),

          const SizedBox(height: 14),
          Divider(height: 1, color: c.divider.withValues(alpha: .7)),
          const SizedBox(height: 12),

          // ── Actions ────────────────────────────────────────────────────
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
                  color: exam.isPublished ? context.colors.primary : c.success,
                  onTap: onToggle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModernActionBtn(
                  title: 'btn_questions'.tr,
                  icon: Icons.edit_note_rounded,
                  color: context.colors.danger,
                  onTap: onManageQuestions,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModernActionBtn(
                  title: 'btn_results'.tr,
                  icon: Icons.bar_chart_rounded,
                  color: c.primary,
                  onTap: onResults,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: c.danger.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        backgroundColor: dctx.colors.cardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                        title: Text(
                          'delete_confirm_title'.tr,
                          style: examT(16, w: FontWeight.w800),
                        ),
                        content: Text(
                          'delete_exam_inline_confirm'.tr,
                          style: examT(13.5, h: 1.6),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dctx),
                            child: Text('cancel'.tr, style: examT(13.5)),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(dctx);
                              onDelete();
                            },
                            child: Text(
                              'btn_delete'.tr,
                              style: examT(
                                13.5,
                                w: FontWeight.w800,
                                c: c.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: c.danger,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // The server sends naive UTC (no "Z"), which DateTime.tryParse reads as a local wall time: shown as-is it was
  // the UTC clock. Read it as UTC and show it in the platform zone + 12h/24h.
  String _fmtDate(DateTime d) => AppTime.dateTime(
      d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second));
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
      textDirection: Helpers.pageDirection,
      child: Column(
          children: [


            // Title row
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 12, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_note_rounded,
                    color: context.colors.danger,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'manage_questions_title'.tr,
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          exam.name,
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 12,
                            color: context.colors.textLight,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Import from Excel / CSV · sample file · export
                  PopupMenuButton<String>(
                    tooltip: 'menu_import_export'.tr,
                    icon: Icon(
                      Icons.upload_file_rounded,
                      color: context.colors.primary,
                    ),
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
                      _menuItem(
                        'import',
                        Icons.upload_file_rounded,
                        'btn_import_questions'.tr,
                      ),
                      _menuItem(
                        'template',
                        Icons.description_outlined,
                        'btn_download_template'.tr,
                      ),
                      _menuItem(
                        'export',
                        Icons.download_rounded,
                        'btn_export_questions'.tr,
                      ),
                    ],
                  ),
                  // Add question button
                  TextButton.icon(
                    onPressed: () => _showQuestionForm(
                      context,
                      prov,
                      examId: exam.id,
                      existing: null,
                    ),
                    icon: Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: context.colors.primary,
                    ),
                    label: Text(
                      'btn_add'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontWeight: FontWeight.w700,
                        color: context.colors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),

            // Body
            Expanded(
              child: loading || prov.saving
                  ? const AppListSkeleton(items: 4, withAvatar: false)
                  : error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_off_rounded,
                            size: 48,
                            color: context.colors.divider,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error,
                            style: TextStyle(
                              fontFamily: AppFonts.display,
                              color: context.colors.textLight,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => prov.loadQuestions(exam.id),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.colors.primary,
                            ),
                            child: Text(
                              'retry'.tr,
                              style: TextStyle(fontFamily: AppFonts.display),
                            ),
                          ),
                        ],
                      ),
                    )
                  : questions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.quiz_outlined,
                            size: 56,
                            color: context.colors.divider,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'no_questions_yet'.tr,
                            style: TextStyle(
                              fontFamily: AppFonts.display,
                              fontSize: 15,
                              color: context.colors.textLight,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'no_questions_hint'.tr,
                            style: TextStyle(
                              fontFamily: AppFonts.display,
                              fontSize: 12,
                              color: context.colors.textLight,
                            ),
                          ),
                        ],
                      ),
                    )
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
                          onEdit: () => _showQuestionForm(
                            context,
                            prov,
                            examId: exam.id,
                            existing: q,
                          ),
                          onDelete: () =>
                              _confirmDeleteQuestion(context, prov, q, exam.id),
                        );
                      },
                    ),
            ),
          ],
        ),
    );
  }

  void _showQuestionForm(
    BuildContext ctx,
    TeacherExamProvider prov, {
    required int examId,
    required Question? existing,
  }) => showAppSideSheet(
      ctx,
      withCloseBar: true,
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
        textDirection: Helpers.pageDirection,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'delete_question_title'.tr,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'delete_question_title'.tr,
            style: TextStyle(fontFamily: AppFonts.display),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'cancel'.tr,
                style: TextStyle(fontFamily: AppFonts.display),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: ctx.colors.dangerBase,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'btn_delete'.tr,
                style: TextStyle(fontFamily: AppFonts.display),
              ),
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
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.colors.inputBg),
      boxShadow: [
        BoxShadow(
          color: context.colors.heroShade.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question header
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: context.colors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  question.title,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
              // Edit / Delete actions
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: context.colors.textLight,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.edit_rounded,
                        color: context.colors.primary,
                      ),
                      title: Text(
                        'btn_edit'.tr,
                        style: TextStyle(fontFamily: AppFonts.display),
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.delete_outline,
                        color: context.colors.danger,
                      ),
                      title: Text(
                        'btn_delete'.tr,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          color: context.colors.danger,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // MCQ options (if any)
        if (question.isMcq)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(50, 0, 14, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: question.options.map((opt) {
                final isCorrect = opt == question.correctAnswer;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isCorrect
                        ? context.colors.success.withValues(alpha: 0.1)
                        : context.colors.inputBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isCorrect
                          ? context.colors.success.withValues(alpha: 0.4)
                          : context.colors.divider,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCorrect) ...[
                        Icon(
                          Icons.check_circle_rounded,
                          size: 12,
                          color: context.colors.success,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        opt,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 12,
                          color: isCorrect
                              ? context.colors.success
                              : context.colors.textMedium,
                          fontWeight: isCorrect
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

        // Marks row
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(50, 2, 14, 10),
          child: Text(
            '${question.marks.toStringAsFixed(question.marks % 1 == 0 ? 0 : 1)} ${'marks_label'.tr}',
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 11,
              color: context.colors.textLight,
            ),
          ),
        ),
      ],
    ),
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
    if (mounted)
      if (mounted) {
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
        _snack('question_add_failed_snack'.tr, context.colors.danger);
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
        _snack('question_update_failed_snack'.tr, context.colors.danger);
      }
    }
  }

  void _snack(String msg, Color color) {
    if (!context.mounted) return;
    showAppNotice(msg);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherExamProvider>();
    final isEditing = widget.existing != null;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [


            // Title bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  Icon(
                    isEditing
                        ? Icons.edit_rounded
                        : Icons.add_circle_outline_rounded,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isEditing
                        ? 'edit_question_title'.tr
                        : 'add_question_title'.tr,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
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
                        width: 260,
                        child: AppNumberField(
                          controller: _marksCtrl,
                          label: 'field_marks_label'.tr,
                          hint: '1',
                          min: 0,
                          step: 0.5,
                          decimals: 2,
                          required: true,
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
                        Text(
                          'options_label'.tr,
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textLight,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Option fields
                        ...List.generate(
                          _optionCtrls.length,
                          (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _optionCtrls[i],
                                    textDirection: Helpers.pageDirection,
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                        ? 'field_required'.tr
                                        : null,
                                    decoration: InputDecoration(
                                      hintText: 'option_hint'.tr.replaceAll(
                                        '{num}',
                                        '${i + 1}',
                                      ),
                                      hintStyle: TextStyle(
                                        fontFamily: AppFonts.display,
                                        color: context.colors.textLight,
                                      ),
                                      filled: true,
                                      fillColor: context.colors.inputBg,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: context.colors.inputBg,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: context.colors.inputBg,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                    ),
                                  ),
                                ),
                                if (_optionCtrls.length > 2) ...[
                                  const SizedBox(width: 6),
                                  IconButton(
                                    tooltip: 'remove'.tr,
                                    onPressed: () => _removeOption(i),
                                    icon: Icon(
                                      Icons.remove_circle_outline,
                                      color: context.colors.danger,
                                      size: 20,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // Add option button
                        TextButton.icon(
                          onPressed: _addOption,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: Text(
                            'btn_add_option'.tr,
                            style: TextStyle(
                              fontFamily: AppFonts.display,
                              fontSize: 13,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: context.colors.primary,
                          ),
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
                            foregroundColor: context.colors.onHero,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: prov.saving
                              ? AppLoadingIndicator()
                              : Text(
                                  isEditing
                                      ? 'btn_save_edits'.tr
                                      : 'btn_add_question'.tr,
                                  style: TextStyle(
                                    fontFamily: AppFonts.display,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !context.mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t == null) return;
    if (mounted)
      if (mounted) {
        setState(
          () => _scheduleDate = DateTime(
            d.year,
            d.month,
            d.day,
            t.hour,
            t.minute,
          ),
        );
      }
  }

  Future<void> _pickDeadline() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !context.mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 23, minute: 59),
    );
    if (t == null) return;
    if (mounted)
      if (mounted) {
        setState(
          () => _deadlineDate = DateTime(
            d.year,
            d.month,
            d.day,
            t.hour,
            t.minute,
          ),
        );
      }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_hasSchedule && _scheduleDate == null) {
      showAppNotice('snack_pick_start_date'.tr);
      return;
    }
    if (_hasDeadline && _deadlineDate == null) {
      showAppNotice('snack_pick_deadline'.tr);
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
      maxSubmissions: _rules.maxSubmissions,
      // 0 = unlimited
      questionsPerStudent: _rules.questionsPerStudent,
      shuffleQuestions: _rules.shuffleQuestions,
      shuffleOptions: _rules.shuffleOptions,
    );
    if (ok && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: Helpers.pageDirection,
    child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Icon(
                  Icons.add_circle_outline_rounded,
                  color: context.colors.primary,
                ),
                SizedBox(width: 8),
                Text(
                  'create_exam_sheet_title'.tr,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Form(
                key: _form,
                child: Column(
                  children: [
                    _Field(
                      ctrl: _nameCtrl,
                      label: 'field_exam_name_label'.tr,
                      hint: 'field_exam_name_hint'.tr,
                      validator: (v) => v!.isEmpty ? 'field_required'.tr : null,
                    ),
                    const SizedBox(height: 12),
                    _Field(
                      ctrl: _descCtrl,
                      label: 'field_desc_optional_label'.tr,
                      hint: 'field_desc_hint_short'.tr,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    NumberPair(
                      first: AppNumberField(
                        controller: _totalMarksCtrl,
                        label: 'field_total_marks_label'.tr,
                        hint: '100',
                        min: 0,
                        step: 5,
                        decimals: 2,
                      ),
                      second: AppNumberField(
                        controller: _passingCtrl,
                        label: 'field_passing_label'.tr,
                        hint: '60',
                        min: 0,
                        step: 5,
                        decimals: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppNumberField(
                      controller: _durationCtrl,
                      label: 'field_duration_label'.tr,
                      hint: '60',
                      min: 1,
                      step: 5,
                    ),
                    const SizedBox(height: 14),
                    // ── Attach to a session (optional) ─────────────────────
                    if (widget.provider.sessions.isNotEmpty) ...[
                      AppDropdown<int?>(
                        initialValue: _sessionId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'field_exam_session_label'.tr,
                          labelStyle: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 13,
                            color: context.colors.textLight,
                          ),
                          prefixIcon: Icon(
                            Icons.play_lesson_rounded,
                            size: 20,
                            color: context.colors.primary,
                          ),
                          filled: true,
                          fillColor: context.colors.inputBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: context.colors.divider),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: context.colors.inputBg),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'exam_no_session'.tr,
                              style: TextStyle(fontFamily: AppFonts.display),
                            ),
                          ),
                          for (final s in widget.provider.sessions)
                            DropdownMenuItem<int?>(
                              value: s.id,
                              child: Text(
                                s.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: AppFonts.display),
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (mounted) setState(() => _sessionId = v);
                        },
                      ),
                      if (_sessionId != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 6,
                            right: 4,
                            left: 4,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 15,
                                color: context.colors.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'exam_session_gate_hint'.tr,
                                  style: TextStyle(
                                    fontFamily: AppFonts.display,
                                    fontSize: 12,
                                    color: context.colors.primary,
                                  ),
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
                        if (mounted)
                          if (mounted) {
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
                                  : null,
                            )
                          : null,
                    ),
                    const SizedBox(height: 10),
                    _Toggle(
                      icon: Icons.schedule_rounded,
                      label: 'toggle_schedule'.tr,
                      value: _hasSchedule,
                      onChanged: (v) {
                        if (mounted)
                          if (mounted) {
                            setState(() => _hasSchedule = v);
                          }
                      },
                      child: _hasSchedule
                          ? GestureDetector(
                              onTap: _pickDate,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: context.colors.divider,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today_outlined,
                                      size: 18,
                                      color: context.colors.textLight,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _scheduleDate != null
                                          ? '${_scheduleDate!.day}/${_scheduleDate!.month}/${_scheduleDate!.year}  '
                                                '${AppTime.clockMinutes(_scheduleDate!.hour * 60 + _scheduleDate!.minute)}'
                                          : 'pick_start_datetime'.tr,
                                      style: TextStyle(
                                        fontFamily: AppFonts.display,
                                        fontSize: 14,
                                        color: _scheduleDate != null
                                            ? context.colors.textDark
                                            : context.colors.textLight,
                                      ),
                                    ),
                                  ],
                                ),
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
                        if (mounted)
                          if (mounted) {
                            setState(() => _hasDeadline = v);
                          }
                      },
                      child: _hasDeadline
                          ? GestureDetector(
                              onTap: _pickDeadline,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: context.colors.warning,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.event_busy_rounded,
                                      size: 18,
                                      color: context.colors.warning,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _deadlineDate != null
                                          ? '${_deadlineDate!.day}/${_deadlineDate!.month}/${_deadlineDate!.year}  '
                                                '${AppTime.clockMinutes(_deadlineDate!.hour * 60 + _deadlineDate!.minute)}'
                                          : 'pick_deadline'.tr,
                                      style: TextStyle(
                                        fontFamily: AppFonts.display,
                                        fontSize: 14,
                                        color: _deadlineDate != null
                                            ? context.colors.textDark
                                            : context.colors.textLight,
                                      ),
                                    ),
                                  ],
                                ),
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
                          foregroundColor: context.colors.onHero,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: widget.provider.saving
                            ? const AppLoadingIndicator()
                            : Text(
                                'btn_create_exam'.tr,
                                style: TextStyle(
                                  fontFamily: AppFonts.display,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
    textDirection: Helpers.pageDirection,
    child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.play_lesson_rounded,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'exam_pick_session_title'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'exam_session_gate_hint'.tr,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 12,
                  color: context.colors.textLight,
                ),
              ),
            ),
            const Divider(height: 12),
            Flexible(
              child: Material(
                type: MaterialType.transparency,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _tile(
                      context,
                      -1,
                      'exam_no_session'.tr,
                      Icons.link_off_rounded,
                      selectedId == null,
                    ),
                    for (final s in sessions)
                      _tile(
                        context,
                        s.id,
                        s.name,
                        Icons.play_circle_outline_rounded,
                        selectedId == s.id,
                      ),
                    if (sessions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'no_sessions_yet'.tr,
                            style: TextStyle(
                              fontFamily: AppFonts.display,
                              color: context.colors.textLight,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
  );

  Widget _tile(
    BuildContext context,
    int value,
    String label,
    IconData icon,
    bool selected,
  ) => ListTile(
    leading: Icon(icon, color: selected ? context.colors.primary : context.colors.textLight),
    title: Text(
      label,
      style: TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        color: selected ? context.colors.primary : null,
      ),
    ),
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
    textDirection: Helpers.pageDirection,
    child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: context.colors.primary.withValues(
                    alpha: 0.1,
                  ),
                  backgroundImage: result.studentImage != null
                      ? NetworkImage(result.studentImage!)
                      : null,
                  child: result.studentImage == null
                      ? Text(
                          result.studentName[0],
                          style: TextStyle(
                            color: context.colors.primary,
                            fontWeight: FontWeight.w700,
                            fontFamily: AppFonts.display,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.studentName,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${result.marksObtained?.toStringAsFixed(0) ?? 0} / '
                        '${result.totalMarks?.toStringAsFixed(0) ?? 0} ${'marks_label'.tr}'
                        '  •  ${result.percentage?.toStringAsFixed(1) ?? 0}%',
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 13,
                          color: context.colors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(
                  result.passed == true
                      ? 'result_passed_badge'.tr
                      : 'result_failed_badge'.tr,
                  result.passed == true
                      ? context.colors.success
                      : context.colors.danger,
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: result.answers.isEmpty
                ? Center(
                    child: Text(
                      'no_answers'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        color: context.colors.textLight,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    itemCount: result.answers.length,
                    itemBuilder: (_, i) {
                      final a = result.answers[i];
                      final correct = a.isCorrect == true;
                      final color = correct
                          ? context.colors.success
                          : context.colors.danger;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: color.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              correct
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              color: color,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${'question_prefix'.tr} ${a.questionId}',
                                    style: TextStyle(
                                      fontFamily: AppFonts.display,
                                      fontSize: 12,
                                      color: context.colors.textLight,
                                    ),
                                  ),
                                  Text(
                                    a.answer ?? 'no_answer_given'.tr,
                                    style: TextStyle(
                                      fontFamily: AppFonts.display,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${a.marksObtained?.toStringAsFixed(1) ?? 0} ${'marks_label'.tr}',
                              style: TextStyle(
                                fontFamily: AppFonts.display,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
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
    final c = context.colors;
    final pct = result.percentage;
    final passed = result.passed;
    final color = passed == true
        ? c.success
        : passed == false
        ? c.danger
        : context.colors.primary;
    final initial = result.studentName.isEmpty ? '?' : result.studentName[0];

    return ExamCard(
      padding: const EdgeInsets.all(14),
      onTap: result.attempted ? onViewAnswers : null,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: .12),
                backgroundImage: result.studentImage != null
                    ? NetworkImage(result.studentImage!)
                    : null,
                child: result.studentImage == null
                    ? Text(
                        initial,
                        style: examT(16, w: FontWeight.w800, c: color),
                      )
                    : null,
              ),
              if (result.isAttended)
                PositionedDirectional(
                  bottom: -1,
                  end: -1,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: c.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.cardBg, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // the student's name opens the student (a link once the server says so); the card opens the answers
                EntityGuardedChip(
                  key: ValueKey('md.exam_result.student.${result.studentId}'),
                  EntityRef(EntityKind.student, result.studentId,
                      label: result.studentName, imageUrl: result.studentImage),
                  showIcon: false,
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _StatusBadge(
                      result.isAttended
                          ? 'attended_badge'.tr
                          : 'absent_badge'.tr,
                      result.isAttended ? c.success : c.danger,
                    ),
                    if (result.attempted)
                      _StatusBadge(
                        passed == true
                            ? 'result_passed_badge'.tr
                            : 'result_failed_badge'.tr,
                        color,
                      )
                    else
                      _StatusBadge('not_attempted_badge'.tr, context.colors.primary),
                  ],
                ),
                if (pct != null) ...[
                  const SizedBox(height: 8),
                  ExamBar(pct: pct, color: color, height: 5),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (pct != null)
            ExamRing(
              value: pct,
              size: 50,
              stroke: 4.5,
              color: color,
              track: color.withValues(alpha: .14),
              center: Text(
                '${pct.toStringAsFixed(0)}%',
                style: examT(11.5, w: FontWeight.w900, c: color),
              ),
            )
          else
            Text(
              '—',
              style: examT(18, w: FontWeight.w800, c: color),
            ),
        ],
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
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: examT(11, w: FontWeight.w700, c: color),
    ),
  );
}

class _MiniStat extends StatelessWidget {
  final String value, label;
  final Color color;

  const _MiniStat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: examT(16, w: FontWeight.w800, c: color),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: examT(9.5, c: context.colors.textMedium),
          ),
        ],
      ),
    ),
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
    textDirection: Helpers.pageDirection,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 13,
        color: context.colors.textLight,
      ),
      hintStyle: TextStyle(fontFamily: AppFonts.display, color: context.colors.textLight),
      filled: true,
      fillColor: context.colors.inputBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.colors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.colors.inputBg),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      border: Border.all(color: context.colors.inputBg),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        ListTile(
          dense: true,
          leading: Icon(icon, color: context.colors.primary, size: 20),
          title: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: AppSwitch(
            value: value,
            onChanged: onChanged,
            semanticLabel: label,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        if (value && child != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: child!,
          ),
      ],
    ),
  );
}

/// The hero's third figure: the course's questions, legacy + engine (`GET /api/v1/exam/exams` items carry
/// `question_count` since round 3 of the paper-exam e2e). An older engine without that figure leaves the tile on the
/// engine exams' attempts — a real number — rather than a false "0 Questions".
({IconData icon, String value, String label}) examHubThirdStat(List<ExamModel> legacy, List<Map<String, dynamic>> engine) {
  final legacyQuestions = legacy.fold<int>(0, (a, e) => a + e.questionCount);
  if (engine.every((e) => e['question_count'] is num)) {
    final engineQuestions = engine.fold<int>(0, (a, e) => a + (e['question_count'] as num).toInt());
    return (icon: Icons.help_outline_rounded, value: '${legacyQuestions + engineQuestions}', label: 'btn_questions'.tr);
  }
  var attempts = 0;
  for (final e in engine) {
    final a = e['attempts'];
    final n = a is Map ? a['total'] : null;
    if (n is num) attempts += n.toInt();
  }
  return (icon: Icons.assignment_turned_in_outlined, value: '$attempts', label: 'exam_hub_attempts'.tr);
}

class _ErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => ExamError(
    message: message ?? 'error_occurred'.tr,
    retryLabel: 'retry'.tr,
    onRetry: onRetry,
  );
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
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: .10),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: examT(10.5, w: FontWeight.w800, c: color),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared helpers — menu item, toast, import / export flows
// ══════════════════════════════════════════════════════════════════════════════

PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
    PopupMenuItem<String>(
      value: value,
      child: Builder(builder: (context) => Row(
        children: [
          Icon(icon, size: 18, color: context.colors.textLight),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontFamily: AppFonts.display, fontSize: 13),
          ),
        ],
      )),
    );

void _toast(BuildContext context, String msg, Color color) {
  if (!context.mounted) return;
  showAppNotice(msg);
}

/// Pick an .xlsx / .csv, upload it, show what was imported / skipped.
Future<void> _importQuestionsFlow(
  BuildContext context,
  TeacherExamProvider prov,
  ExamModel exam,
) async {
  final file = await pickQuestionsFile();
  if (file == null || !context.mounted) return;
  final out = await prov.importQuestions(exam.id, file);
  if (!context.mounted) return;
  if (out.result == null) {
    _toast(context, out.error ?? 'import_failed_snack'.tr, context.colors.danger);
    return;
  }
  await showDialog(
    context: context,
    builder: (_) => _ImportResultDialog(result: out.result!),
  );
}

Future<void> _downloadTemplateFlow(
  BuildContext context,
  TeacherExamProvider prov,
) async {
  final err = await prov.downloadTemplate();
  _toast(
    context,
    err ?? 'template_saved_snack'.tr,
    err == null ? context.colors.success : context.colors.danger,
  );
}

/// kind: questions | marks | answers | all
Future<void> _exportFlow(
  BuildContext context,
  TeacherExamProvider prov,
  ExamModel exam,
  String kind,
) async {
  final err = await prov.exportExam(exam.id, kind);
  _toast(
    context,
    err ?? 'export_saved_snack'.tr,
    err == null ? context.colors.success : context.colors.danger,
  );
}

class _ImportResultDialog extends StatelessWidget {
  final ImportResult result;

  const _ImportResultDialog({required this.result});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: Helpers.pageDirection,
    child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'import_result_title'.tr,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${'import_added_label'.tr}: ${result.created}',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w700,
                color: context.colors.success,
              ),
            ),
            if (result.skipped > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${'import_skipped_label'.tr}: ${result.skipped}',
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontWeight: FontWeight.w700,
                  color: context.colors.danger,
                ),
              ),
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
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 12,
                            color: context.colors.textLight,
                          ),
                        ),
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
          child: Text('btn_ok'.tr, style: TextStyle(fontFamily: AppFonts.display)),
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
    _attemptsCtrl = TextEditingController(
      text: _limitAttempts ? '${r.maxSubmissions}' : '1',
    );
    _perStudentCtrl = TextEditingController(
      text: _limitQuestions ? '${r.questionsPerStudent}' : '10',
    );
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
    widget.onChanged(
      ExamRules(
        maxSubmissions: _limitAttempts
            ? (attempts != null && attempts > 0 ? attempts : 1)
            : 0,
        questionsPerStudent:
            _limitQuestions && perStudent != null && perStudent > 0
            ? perStudent
            : null,
        shuffleQuestions: _shuffleQ,
        shuffleOptions: _shuffleO,
      ),
    );
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
    final hintStyle = TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 12,
      color: context.colors.textLight,
    );

    return Column(
      children: [
        // ── Attempts: unlimited (off) or limited to N (on) ─────────────────────
        _Toggle(
          icon: Icons.repeat_rounded,
          label: 'toggle_max_submissions'.tr,
          value: _limitAttempts,
          onChanged: (v) => _set(() => _limitAttempts = v),
          child: _limitAttempts
              ? AppNumberField(
                  controller: _attemptsCtrl,
                  label: 'field_max_submissions_label'.tr,
                  hint: '1',
                  min: 1,
                  required: true,
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
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppNumberField(
                      controller: _perStudentCtrl,
                      label: 'field_questions_per_student_label'.tr,
                      hint: '10',
                      min: 1,
                      required: true,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tooMany
                          ? 'questions_exceed_pool_warning'.tr
                          : 'questions_per_student_hint'.tr,
                      style: hintStyle.copyWith(
                        color: tooMany ? context.colors.warning : context.colors.textLight,
                      ),
                    ),
                  ],
                )
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
      ],
    );
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
    _toast(
      context,
      err ?? 'exam_rules_saved_snack'.tr,
      err == null ? context.colors.success : context.colors.danger,
    );
    if (err == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: Helpers.pageDirection,
    child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, color: context.colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'exam_rules_title'.tr,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Form(
                key: _form,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'exam_rules_apply_note'.tr,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 12,
                          color: context.colors.textLight,
                        ),
                      ),
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
                          foregroundColor: context.colors.onHero,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _busy
                            ? const AppLoadingIndicator()
                            : Text(
                                'btn_save_changes'.tr,
                                style: TextStyle(
                                  fontFamily: AppFonts.display,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
  );
}
