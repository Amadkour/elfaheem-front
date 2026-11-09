// "Get result" (Exam Hub, F5; back docs/exam_hub/CONTRACT.md 1.3 - 1.6): one screen for the results of ANY exam, online, on
// paper, on bubble sheets or totals imported from Excel. The summary first, then what is still open and where the results have
// gone, then the three things to do with them: publish to students and parents, write to a Data Lab column, export.
//
// It reuses the engine's flows instead of forking them: the attempt sheet and the grade log of the results screen, the review
// pages for what is open, `PublishBlockedSheet` for the 409, the shared export page. A server without the Hub routes
// (`GET /degrees` answers FastAPI's bare 404) simply loses the tiles that need them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart' show loadDeferred;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/design/export_hub/export_flow.dart' deferred as export_flow;
import 'package:flutter_education_app/design/export_layout/layout_page.dart' deferred as export_layout;
import 'package:flutter_education_app/features/teacher/data_lab/data_lab_api.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../../admin/admin_common.dart' show asInt, asMapList, t;
import '../../exam_authoring.dart' show ExamAuthoringApi;
import '../../exam_engine_api.dart';
import '../../exam_grade_log_screen.dart' show ExamGradeLogScreen;
import '../../exam_grading.dart' show PublishOutcome, ReviewPending;
import '../../exam_grading_widgets.dart' show PublishBlockedSheet, PublishChoice;
import '../../exam_results_screen.dart' show AttemptAnswersSheet, ExamResultsScreen;
import '../../exam_review_screen.dart' show ExamReviewScreen;
import '../../paper/review/omr_results_parts.dart' show OmrQuestionStatsView;
import '../../paper/review/omr_review_page.dart' show OmrReviewPage, omrScanWatch;
import '../correct/exam_correct_flow.dart' show openExamCorrection;
import '../hub_degrees_import_sheet.dart' show openHubDegreesImport;
import 'exam_result_data.dart';
import 'exam_result_sheets.dart';
import 'exam_result_widgets.dart';

Future<void> openExamGetResult(BuildContext context, {required int examId, required String title, int? courseId}) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamGetResultScreen(examId: examId, title: title, courseId: courseId)));
}

class ExamGetResultScreen extends StatefulWidget {
  const ExamGetResultScreen({super.key, required this.examId, required this.title, this.courseId, this.api});
  final int examId;
  final String title;
  final int? courseId;
  final ResultsHubApi? api;

  @override
  State<ExamGetResultScreen> createState() => _ExamGetResultScreenState();
}

class _ExamGetResultScreenState extends State<ExamGetResultScreen> {
  late final ResultsHubApi _api = widget.api ?? ResultsHubApi();
  final _authoring = ExamAuthoringApi();
  EventOrPoll? _watch;
  ResultsBoard? _board;
  List<LabColumnChoice> _columns = const [];
  Map<int, String> _names = const {};
  String? _error;
  bool _busy = false, _students = true, _parents = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final id = widget.examId;
    final results = await Future.wait<EngineResult>([_api.exam(id), _api.attempts(id), _api.omrResults(id), _api.degrees(id), _api.analytics(id)]);
    if (!mounted) return;
    final ex = results[0];
    if (!ex.ok) {
      if (!silent) setState(() => _error = resultErrorText(ex));
      return;
    }
    final courseId = ex.map['course_id'] == null ? widget.courseId : asInt(ex.map['course_id']);
    if (_names.isEmpty && courseId != null && ex.map['anonymous_grading'] != true) {
      final r = await _api.courseStudents(courseId);
      final list = r.map['value'] is List ? asMapList(r.map['value']) : asMapList(r.map['items']);
      _names = {for (final s in list) asInt(s['id']): '${s['name'] ?? ''}'};
    }
    final attempts = results[1], omr = results[2], degrees = results[3], analytics = results[4];
    final board = ResultsBoard.fromSources(
      exam: ex.map,
      attempts: attempts.ok ? attempts.map : null,
      omr: omr.ok ? omr.map : null,
      degrees: degrees.ok ? degrees.map : null,
      analytics: analytics.ok ? analytics.map : null,
      names: _names,
      hubServer: !degrees.unavailable,
    );
    if (_columns.isEmpty && labAccessOf(hubServer: board.hubServer, disabled: AppConfig.disableList, courseId: board.courseId, anonymous: board.anonymous) == LabAccess.ready) {
      await _loadColumns(board.courseId!);
    }
    if (!mounted) return;
    if (board.isPaper) _watch ??= (omrScanWatch(id, () => _load(silent: true))..start());
    setState(() {
      _board = board;
      _error = attempts.ok || silent ? null : resultErrorText(attempts);
    });
  }

  Future<void> _loadColumns(int courseId) async {
    try {
      final g = await DataLabApi().grid(courseId, limit: 1, lang: AppConfig.lang);
      _columns = [for (final c in g.columns) if (c.isNumber && !c.isCalculated && !c.isLocked) LabColumnChoice(c.key, c.label, c.maxValue)];
    } catch (_) {
      _columns = const []; // the sheet still offers a new column
    }
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _load(silent: true);
  }

  void _openScans() => _push(OmrReviewPage(examId: widget.examId));
  void _openAnswers() => _push(ExamReviewScreen(examId: widget.examId, examTitle: widget.title));

  Future<void> _publish({bool gradedOnly = false}) async {
    final b = _board;
    if (b == null) return;
    final telling = _parents && !b.parentsTold;
    setState(() => _busy = true);
    final r = await _api.publish(widget.examId, gradedOnly: gradedOnly, notifyParents: telling);
    if (!mounted) return;
    setState(() => _busy = false);
    final pending = ReviewPending.from(r);
    if (pending != null) {
      final pick = await showAppSheet<PublishChoice>(context, (_) => PublishBlockedSheet(pending: pending));
      if (!mounted || pick == null) return;
      if (pick == PublishChoice.publishReviewed) return _publish(gradedOnly: true);
      return pending.openItems > 0 ? _openScans() : _openAnswers();
    }
    if (!r.ok) {
      showAppNotice(resultErrorText(r), error: true);
      return;
    }
    showAppNotice(b.published ? t('سيصل الإشعار إلى أولياء الأمور', 'The parents will be told') : PublishOutcome.fromJson(r.map).text);
    await _load(silent: true);
  }

  Future<void> _setStudents(bool on) async {
    final b = _board;
    if (b == null) return;
    if (!b.published) {
      setState(() {
        _students = on;
        if (!on) _parents = false;
      });
      return;
    }
    if (on) return;
    final ok = await appConfirm(context,
        danger: true,
        message: t('تختفي النتائج عن الطلاب وأولياء الأمور فورًا إلى أن تنشرها مرة أخرى. متابعة؟', 'Students and parents stop seeing these results at once, until you publish them again. Continue?'),
        confirmLabel: t('إلغاء النشر', 'Unpublish'));
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await _api.unpublish(widget.examId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(resultErrorText(r), error: true);
      return;
    }
    showAppNotice(t('أُلغي نشر النتائج', 'Results unpublished'));
    await _load(silent: true);
  }

  Future<void> _openDataLab() async {
    final b = _board;
    if (b == null) return;
    final wrote = await showResultDataLabSheet(context, board: b, columns: _columns, api: _api);
    if (wrote && mounted) {
      _columns = const [];
      await _load(silent: true);
    }
  }

  Future<void> _import() async {
    if (await openHubDegreesImport(context, examId: widget.examId, title: widget.title) && mounted) {
      await _load(silent: true);
    }
  }

  void _openAttempt(ResultEntry e) {
    showAppSheet<void>(context, (_) => AttemptAnswersSheet(attemptId: e.attemptId!, title: e.name, api: _authoring, examId: widget.examId, examTitle: widget.title)).then((_) {
      if (mounted) _load(silent: true);
    });
  }

  void _showAllQuestions() {
    final o = _board?.omr;
    if (o == null) return;
    showAppSheet<void>(context, (_) => AppSheetContent(title: t('إحصاءات الأسئلة', 'Question statistics'), children: [OmrQuestionStatsView(questions: o.questions, wide: false)]));
  }

  void _export() {
    final b = _board;
    if (b != null) showAppExportSheet(context, bilingualExport(() => examHubResultsExport(b)));
  }

  /// Export's Design step, before any file is written: the shared export page, or the older flow when `export.layout_v3` is off.
  Future<void> _openStudio() async {
    final b = _board;
    if (b == null) return;
    final export = bilingualExport(() => examHubResultsExport(b));
    export.brandColor ??= (context.colors.primary.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    await loadDeferred('export_flow', export_flow.loadLibrary);
    await loadDeferred('export_layout', export_layout.loadLibrary);
    if (!mounted) return;
    if (export_layout.exportLayoutEnabled) {
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => export_layout.ExportLayoutPage(export: export, initialStep: 2)));
    } else {
      await showAppSheet<bool>(context, (_) => export_flow.ExportFlowSheet(export: export, initialStep: 3));
    }
  }

  String? _columnLabel(ResultsBoard b) {
    final key = b.dataLabColumn;
    if (key == null) return null;
    for (final c in _columns) {
      if (c.key == key) return c.label;
    }
    return key;
  }

  ResultBoardCallbacks _callbacks(ResultsBoard b) => ResultBoardCallbacks(
        onScans: _openScans,
        onAnswers: _openAnswers,
        onStudents: _setStudents,
        onParents: (v) => setState(() => _parents = v),
        onPublish: () => _publish(),
        onDataLab: _openDataLab,
        onExport: _export,
        onStudio: AppConfig.disableList.contains(kResultsStudioKey) ? null : _openStudio,
        onCorrect: () async {
          await openExamCorrection(context, examId: widget.examId, title: widget.title, courseId: b.courseId);
          if (mounted) _load(silent: true);
        },
        onImport: !b.hubServer || AppConfig.disableList.contains(kResultsImportKey) ? null : _import,
        onOpenAttempt: _openAttempt,
        onAllQuestions: b.omr == null || b.omr!.questions.isEmpty ? null : _showAllQuestions,
        onAttempts: () => _push(ExamResultsScreen(examId: widget.examId, examTitle: widget.title, courseId: b.courseId)),
        onGradeLog: () => _push(ExamGradeLogScreen(examId: widget.examId, examTitle: widget.title)),
      );

  Widget _waiting() {
    final c = context.colors;
    if (_error != null) {
      return AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!, action: TextButton(onPressed: () => _load(), child: Text(t('إعادة المحاولة', 'Try again'))));
    }
    return const AppListSkeleton(key: ValueKey('result.waiting'), items: 5, withAvatar: false);
  }

  @override
  Widget build(BuildContext context) {
    final b = _board;
    return BasePage(
      key: const ValueKey('exam.hub.result'),
      appBar: AppHeader(
        title: widget.title,
        actions: [AppRefreshAction(onRefresh: () => _load())],
      ),
      child: LayoutBuilder(builder: (context, box) {
        final pad = AppSpace.gutter(box.maxWidth);
        final wide = box.maxWidth >= Breakpoints.desktop;
        return AppRefresh(
          onRefresh: () => _load(),
          child: ListView(padding: EdgeInsets.fromLTRB(pad, AppSpace.md, pad, AppSpace.xl), children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.wide.max),
                child: AnimatedSwitcher(
                  duration: AppMotion.of(context).base,
                  child: b == null
                      ? _waiting()
                      : ResultBoardView(key: const ValueKey('result.board'), board: b, wide: wide, callbacks: _callbacks(b), students: _students, parents: _parents, busy: _busy, columnLabel: _columnLabel(b), error: _error),
                ),
              ),
            ),
          ]),
        );
      }),
    );
  }
}

class ResultBoardCallbacks {
  const ResultBoardCallbacks({
    this.onScans,
    this.onAnswers,
    this.onStudents,
    this.onParents,
    this.onPublish,
    this.onDataLab,
    this.onExport,
    this.onStudio,
    this.onCorrect,
    this.onImport,
    this.onOpenAttempt,
    this.onAllQuestions,
    this.onAttempts,
    this.onGradeLog,
  });
  final VoidCallback? onScans, onAnswers, onPublish, onDataLab, onExport, onStudio, onCorrect, onImport, onAllQuestions, onAttempts, onGradeLog;
  final ValueChanged<bool>? onStudents, onParents;
  final ValueChanged<ResultEntry>? onOpenAttempt;
}

/// The whole page in plain values: one column on a phone; on a desktop the results on the left and the actions in a rail.
class ResultBoardView extends StatelessWidget {
  const ResultBoardView({
    super.key,
    required this.board,
    required this.wide,
    this.callbacks = const ResultBoardCallbacks(),
    this.students = true,
    this.parents = false,
    this.busy = false,
    this.columnLabel,
    this.error,
  });

  final ResultsBoard board;
  final bool wide, students, parents, busy;
  final ResultBoardCallbacks callbacks;
  final String? columnLabel, error;

  LabAccess get _lab => labAccessOf(hubServer: board.hubServer, disabled: AppConfig.disableList, courseId: board.courseId, anonymous: board.anonymous);

  @override
  Widget build(BuildContext context) {
    final b = board;
    final s = b.stats;
    final cb = callbacks;
    final banner = error == null ? null : AppBanner(icon: Icons.error_outline_rounded, color: context.colors.danger, text: error!);
    if (s.empty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ?banner,
        ResultNothingYet(isPaper: b.isPaper, inProgress: s.inProgress, onCorrect: cb.onCorrect, onImport: cb.onImport),
      ]);
    }
    const gap = SizedBox(height: AppSpace.md);
    final results = <Widget>[
      ?banner,
      ResultSummaryHero(stats: s, sourceLabel: b.sourceLabel),
      gap,
      if (s.partial) ...[
        ResultOpenCard(students: s.openStudents, scanItems: s.openScanItems, onScans: cb.onScans, onAnswers: cb.onAnswers),
        gap,
      ],
      ResultStatusStrip(
        published: b.published ? b.publishedAt : null,
        parentsTold: b.parentsTold,
        autoStudents: b.onlyImported ? t('لا تظهر في نتائج الاختبار', 'Not in exam results') : (b.publishable ? null : _policyShort(b.resultsPolicy)),
        dataLab: columnLabel,
        showParents: b.hubServer && b.publishable && !b.onlyImported,
        showDataLab: _lab == LabAccess.ready,
      ),
      gap,
      if (s.graded > 0) ...[
        ResultDistributionCard(stats: s),
        gap,
      ],
      if (b.hardest.isNotEmpty) ...[
        ResultHardestCard(questions: b.hardest, onAll: cb.onAllQuestions),
        gap,
      ],
    ];
    final actions = <Widget>[
      ResultPublishCard(board: b, students: b.published || students, parents: parents, onStudents: cb.onStudents, onParents: cb.onParents, onPublish: cb.onPublish, busy: busy, primary: !s.partial),
      if (_lab != LabAccess.hidden) ...[gap, ResultDataLabCard(access: _lab, column: columnLabel, onOpen: cb.onDataLab)],
      gap,
      ResultExportCard(enabled: !s.empty, onExport: cb.onExport ?? () {}, onStudio: cb.onStudio, perQuestion: s.entries.any((e) => e.questions.isNotEmpty)),
    ];
    final links = Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      if (cb.onImport != null) AppPill(icon: Icons.upload_file_rounded, label: t('استيراد درجات من Excel', 'Import totals from Excel'), onTap: cb.onImport),
      AppPill(icon: Icons.assignment_outlined, label: t('المحاولات وتعديل الدرجات', 'Attempts and mark changes'), onTap: cb.onAttempts),
      AppPill(icon: Icons.history_rounded, label: t('سجل الدرجات', 'Grade log'), onTap: cb.onGradeLog),
    ]);
    final list = ResultStudentsCard(entries: s.entries, anonymous: b.anonymous, wide: wide, onOpen: cb.onOpenAttempt);
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...results, list])),
        const SizedBox(width: AppSpace.lg),
        SizedBox(width: 360, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...actions, gap, links])),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...results, ...actions, gap, list, gap, links]);
  }
}

String _policyShort(String p) => switch (p) {
      'after_submit' => t('تظهر بعد التسليم', 'Shown after submitting'),
      'hidden' => t('مخفية', 'Hidden'),
      _ => t('غير منشورة', 'Not published'),
    };
