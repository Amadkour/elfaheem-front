// The Exam Hub (D-350): the ONE place for every exam a person manages. Opened from the Profile tab (`deferredExamHub`),
// the organization's and the super admin's menus, and every "All exams" entry. Kill switch `exam.hub`.
//
//   Creation               every exam (the `loadAllExams` list), status tabs, course and type filters, New exam
//   Results & Correction   Correction: each exam flagged Corrected / In progress / Not corrected / Not ended yet
//                          Results: each exam flagged has degrees or not, with exam revision
//   the smart header       what needs the teacher now, every line a way into the filtered list
//
// One list call for all of it; on return from any flow the list is read again. Decisions: `hub_logic.dart`, drawing:
// `hub_widgets.dart`. The flows themselves live under `hub/create`, `hub/deliver`, `hub/correct`, `hub/result`,
// `hub/revision`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../admin/admin_common.dart' show t;
import '../exam_all.dart';
import '../exam_all_screen.dart' show staffOrgs;
import '../exam_authoring.dart';
import '../exam_authoring_screen.dart' show ExamEditorScreen;
import '../exam_paper_sheet.dart' show openExamPaper;
import '../exam_results_screen.dart';
import 'correct/exam_correct_flow.dart' show openExamCorrection;
import 'create/exam_create_wizard.dart' show openExamCreateWizard;
import 'deliver/exam_deliver_screen.dart' show openExamDeliver;
import 'hub_degrees_import_sheet.dart' show openHubDegreesImport;
import 'hub_entry.dart';
import 'hub_logic.dart';
import 'hub_widgets.dart';
import 'result/exam_get_result_screen.dart' show openExamGetResult;
import 'revision/exam_revision_flow.dart' show openExamRevision;

class ExamHubScreen extends StatefulWidget {
  const ExamHubScreen({super.key, this.orgId, this.orgName, this.initialTab = 0, this.loader});

  /// Opened from an organization's dashboard: only that organization's exams, and new exams are made there.
  final int? orgId;
  final String? orgName;

  /// 0 Creation · 1 Results & Correction.
  final int initialTab;

  /// Tests: replaces [loadAllExams].
  final Future<AllExamsData> Function()? loader;

  @override
  State<ExamHubScreen> createState() => _ExamHubScreenState();
}

class _ExamHubScreenState extends State<ExamHubScreen> {
  final _api = ExamAuthoringApi();
  final _search = TextEditingController();
  AllExamsData? _data;
  Object? _error;
  DateTime? _updated;
  late int _tab = widget.initialTab;
  HubSurface _segment = HubSurface.correction;
  AllExamsFilter _filter = const AllExamsFilter();
  HubCorrection? _correctionFilter;
  HubResultsFilter? _resultsFilter;
  final Set<int> _busy = {};
  int? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (widget.loader == null) {
        final mode = AppModeController.instance;
        if (!mode.loaded) await mode.ready();
      }
      final orgs = {...staffOrgs(), if (widget.orgId != null) widget.orgId!: widget.orgName ?? ''};
      final d = await (widget.loader?.call() ?? loadAllExams(orgs: orgs));
      if (!mounted) return;
      setState(() {
        _data = hubScoped(d, widget.orgId);
        _error = null;
        _updated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      if (_data != null) showAppNotice(ApiException.from(e).message, error: true); // the list stays, the failure still shows
    }
  }

  /// Runs a pushed flow, then reads the list again: whatever it changed shows at once.
  Future<void> _flow(Future<void> Function() open) async {
    await open();
    if (mounted) whenBackOn(context, _load);
  }

  Future<void> _newExam() {
    final course = _filter.courseId == null || _filter.courseId == AllExamsFilter.noCourse ? null : _filter.courseId;
    final org = widget.orgId ?? (course == null ? null : _data?.courseOrgs[course]);
    return _flow(() => openExamCreateWizard(context, orgId: org, courseId: course));
  }

  void _attention(HubAttentionKind k) {
    _search.clear();
    setState(() {
      _filter = _filter.copyWith(query: '');
      _selected = null;
      switch (k) {
        case HubAttentionKind.toCorrect:
          _tab = 1;
          _segment = HubSurface.correction;
          _correctionFilter = HubCorrection.notCorrected;
        case HubAttentionKind.inCorrection:
          _tab = 1;
          _segment = HubSurface.correction;
          _correctionFilter = HubCorrection.inProgress;
        case HubAttentionKind.unpublished:
          _tab = 1;
          _segment = HubSurface.results;
          _resultsFilter = HubResultsFilter.unpublished;
        case HubAttentionKind.drafts:
          _tab = 0;
          _filter = _filter.copyWith(status: 'draft');
      }
    });
  }

  HubSurface get _surface => _tab == 0 ? HubSurface.creation : _segment;

  Future<void> _publish(AllExam e) async {
    if (e.questionCount == 0) {
      showAppNotice(t('أضف أسئلة قبل النشر، افتح الاختبار في المحرر', 'Add questions before publishing: open the exam in the editor'), error: true);
      return;
    }
    final ok = await appConfirm(context,
        message: t('نشر «${e.displayTitle}»؟ يراه الطلاب ويمكنهم أداؤه في موعده.', 'Publish "${e.displayTitle}"? Students will see it and can take it when it opens.'),
        confirmLabel: t('نشر', 'Publish'));
    if (!ok || !mounted) return;
    setState(() => _busy.add(e.id));
    final r = await _api.lifecycle(e.id, ExamAction.publish);
    if (!mounted) return;
    setState(() => _busy.remove(e.id));
    showAppNotice(r.ok ? t('نُشر الاختبار', 'The exam is published') : authoringError(r), error: !r.ok);
    if (r.ok) _load();
  }

  /// Correction, after the question an exam still running deserves.
  Future<void> _correct(AllExam e) async {
    if (hubCorrectionOf(e) == HubCorrection.notEnded) {
      final anyway = await showAppSheet<bool>(
          context,
          (ctx) => AppSheetContent(title: t('لم ينتهِ هذا الاختبار بعد', 'This exam has not ended yet'), children: [
                HubNotEndedBody(text: hubNotEndedText(e), onWait: () => Navigator.pop(ctx, false), onCorrectAnyway: () => Navigator.pop(ctx, true)),
              ]));
      if (anyway != true || !mounted) return;
    }
    await _flow(() => openExamCorrection(context, examId: e.id, title: e.displayTitle, courseId: e.courseId));
  }

  /// No degrees yet: from a file, or by correcting.
  Future<void> _addDegrees(AllExam e) async {
    final pick = await showAppSheet<HubAction>(
        context,
        (ctx) => AppSheetContent(title: t('لا درجات لهذا الاختبار بعد', 'This exam has no degrees yet'), children: [
              HubNoDegreesBody(
                canImport: hubCanImport(e),
                importRecommended: hubImportRecommended(e),
                noCourse: e.courseId == null,
                onImport: () => Navigator.pop(ctx, HubAction.importDegrees),
                onCorrect: () => Navigator.pop(ctx, HubAction.correct),
              ),
            ]));
    if (pick != null && mounted) await _act(e, pick);
  }

  Future<void> _act(AllExam e, HubAction a) async {
    final nav = Navigator.of(context);
    switch (a) {
      case HubAction.edit:
        await _flow(() => nav.push(MaterialPageRoute(builder: (_) => ExamEditorScreen(examId: e.id, courseId: e.courseId, orgId: e.orgId))));
      case HubAction.results:
        await _flow(() => nav.push(MaterialPageRoute(builder: (_) => ExamResultsScreen(examId: e.id, examTitle: e.displayTitle, courseId: e.courseId))));
      case HubAction.paper:
        await _flow(() => openExamPaper(context, examId: e.id, course: _data?.courseName(e) ?? ''));
      case HubAction.publish:
        await _publish(e);
      case HubAction.deliver:
        await _flow(() => openExamDeliver(context, examId: e.id, title: e.displayTitle, courseId: e.courseId, course: _data?.courseName(e) ?? ''));
      case HubAction.correct:
        await _correct(e);
      case HubAction.getResult:
        await _flow(() => openExamGetResult(context, examId: e.id, title: e.displayTitle, courseId: e.courseId));
      case HubAction.addDegrees:
        await _addDegrees(e);
      case HubAction.importDegrees:
        if (await openHubDegreesImport(context, examId: e.id, title: e.displayTitle)) _load();
      case HubAction.revision:
        await _flow(() => openExamRevision(context, examId: e.id, courseId: e.courseId, orgId: e.orgId, title: e.displayTitle));
    }
  }

  String? get _subtitle {
    final d = _data;
    if (d == null) return t('كل اختبار تديره في مكان واحد', 'Every exam you manage, in one place');
    final n = d.exams.where((e) => e.status != 'archived').length;
    final count = countText(n,
        ar1: 'اختبار واحد', ar2: 'اختباران', arFew: '{n} اختبارات', arMany: '{n} اختباراً', en1: '1 exam', en: '{n} exams', ar0: 'لا اختبارات بعد', en0: 'No exams yet');
    final org = widget.orgName ?? '';
    return org.isEmpty ? count : '$org · $count';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = _data;
    final nav = Navigator.of(context);
    final creating = _surface == HubSurface.creation;
    final header = AppPageHeader(
      title: t('الاختبارات', 'Exams'),
      subtitle: _subtitle,
      icon: Icons.fact_check_rounded,
      onBack: nav.canPop() ? () => nav.maybePop() : null,
      onRefresh: _load,
      updatedAt: _updated,
      primaryAction: creating
          ? AppButton.primary(key: const ValueKey('exam.hub.new'), label: t('اختبار جديد', 'New exam'), icon: Icons.add_rounded, onPressed: _newExam)
          : null,
      search: AppSearchField(
        controller: _search,
        hint: t('ابحث باسم الاختبار أو المقرر', 'Search by exam or course name'),
        onChanged: (v) => setState(() => _filter = _filter.copyWith(query: v)),
      ),
      bottom: AppUnderlineTabs(
        expand: true,
        items: [
          AppTabItem(t('الإنشاء', 'Creation'), icon: Icons.edit_note_rounded),
          AppTabItem(t('النتائج والتصحيح', 'Results & Correction'), icon: Icons.task_alt_rounded),
        ],
        index: _tab,
        onChanged: (i) => setState(() {
          _tab = i;
          _selected = null;
        }),
      ),
    );
    return BasePage(
      key: const ValueKey(kExamHubFeatureKey),
      enableFooterWidget: false,
      child: ColoredBox(
        color: c.background,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // the editorial masthead on the canvas (D-614): its own strip on top, the underline tabs close it
          header,
          Expanded(
            child: ExamHubBody(
              data: d,
              error: _error == null ? null : ApiException.from(_error!).message,
              tab: _tab,
              segment: _segment,
              filter: _filter,
              correctionFilter: _correctionFilter,
              resultsFilter: _resultsFilter,
              busy: _busy,
              selectedId: _selected,
              onSelect: (e) => setState(() => _selected = e.id),
              onFilter: (f) => setState(() => _filter = f),
              onSegment: (s) => setState(() {
                _segment = s;
                _selected = null;
              }),
              onCorrectionFilter: (f) => setState(() => _correctionFilter = f),
              onResultsFilter: (f) => setState(() => _resultsFilter = f),
              onAttention: _attention,
              onAction: _act,
              onRetry: _load,
              onRefresh: _load,
              onNew: _newExam,
              onStartRevision: () => _flow(() => openExamRevision(context, orgId: widget.orgId)),
            ),
          ),
        ]),
      ),
    );
  }
}
