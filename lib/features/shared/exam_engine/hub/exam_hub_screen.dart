// The Exam Hub (D-350): the ONE place for every exam a person manages. Opened from the Profile tab (`deferredExamHub`),
// the organization's and the super admin's menus, and every "All exams" entry. Kill switch `exam.hub`.
//
// Made plain for a teacher who is not technical (D-700 – D-703), top to bottom:
//   the header           "Exams", ONE primary New exam; Grade paper sheets (a labelled button while paper exams exist,
//                        quieter otherwise) and Review grades (without an exam) as labelled header actions
//   Needs you now        a card per thing owed (to grade, grading to finish, results to publish, drafts), only above 0;
//                        a card for one exam opens it straight away, for several it narrows the list to them
//   the list             three stage tabs (Drafts / Running / Finished), search, course, one Filter; every exam with
//                        one sentence, ONE next step and ⋯ for the rest
//   the detail           the selected exam as four steps beside the list on a wide window, its own page on a phone
//
// One list call for all of it; on return from any flow the list is read again. Decisions: `hub_logic.dart`, drawing:
// `hub_widgets.dart`. The flows themselves live under `hub/create`, `hub/deliver`, `hub/correct`, `hub/result`,
// `hub/revision`, `hub/grade`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
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
import 'grade/essay_run_screen.dart' show openEssayRunScreen;
import 'create/exam_create_wizard.dart' show openExamCreateWizard;
import 'deliver/exam_deliver_screen.dart' show openExamDeliver;
import 'grade/grade_papers_sheet.dart' show openGradePapers;
import 'hub_degrees_import_sheet.dart' show openHubDegreesImport;
import 'hub_duplicate.dart';
import 'hub_entry.dart';
import 'hub_logic.dart';
import 'hub_widgets.dart';
import 'result/exam_get_result_screen.dart' show openExamGetResult;
import 'revision/exam_revision_flow.dart' show openExamRevision;

/// "Run this once that page is on top again" (`whenBackOn` bound to the page a flow started from).
typedef HubBackOn = void Function(VoidCallback act);

class ExamHubScreen extends StatefulWidget {
  const ExamHubScreen({super.key, this.orgId, this.orgName, this.initialTab = 0, this.loader, this.now});

  /// Opened from an organization's dashboard: only that organization's exams, and new exams are made there.
  final int? orgId;
  final String? orgName;

  /// 0: the stage that fits (Running, else Drafts, else Finished) · 1: Finished (where the older "Results & Correction"
  /// tab led).
  final int initialTab;

  /// Tests: replaces [loadAllExams].
  final Future<AllExamsData> Function()? loader;

  /// Tests and renders: the instant "now" is (null: the clock).
  final DateTime? now;

  @override
  State<ExamHubScreen> createState() => _ExamHubScreenState();
}

class _ExamHubScreenState extends State<ExamHubScreen> {
  final _api = ExamAuthoringApi();
  final _search = TextEditingController();

  /// Bumped on every change a pushed detail page draws (the list, the busy set).
  final _changes = ValueNotifier<int>(0);
  AllExamsData? _data;
  Object? _error;
  DateTime? _updated;
  HubStage? _stage;
  HubAttentionKind? _focus;
  AllExamsFilter _filter = const AllExamsFilter();
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
    _changes.dispose();
    super.dispose();
  }

  void _changed(VoidCallback fn) {
    setState(fn);
    _changes.value++;
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
      _changed(() {
        _data = hubScoped(d, widget.orgId);
        _error = null;
        _updated = DateTime.now();
        _stage ??= widget.initialTab == 1 ? HubStage.finished : hubInitialStage(_data!, now: widget.now);
        // a card whose exams are all dealt with has nothing left to show
        if (_focus != null && !_data!.exams.any((e) => hubInFocus(e, _focus!))) _focus = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      if (_data != null) showAppNotice(ApiException.from(e).message, error: true); // the list stays, the failure still shows
    }
  }

  /// Runs a pushed flow, then reads the list again once the page it started from ([from]: the exam's own page; else the
  /// hub) is on top: whatever it changed shows at once.
  Future<void> _flow(Future<void> Function() open, {HubBackOn? from}) async {
    await open();
    if (!mounted) return;
    if (from != null) return from(_load);
    whenBackOn(context, _load);
  }

  int? get _courseFilter => _filter.courseId == null || _filter.courseId == AllExamsFilter.noCourse ? null : _filter.courseId;

  Future<void> _newExam() {
    final course = _courseFilter;
    final org = widget.orgId ?? (course == null ? null : _data?.courseOrgs[course]);
    return _flow(() => openExamCreateWizard(context, orgId: org, courseId: course));
  }

  Future<void> _gradePapers() {
    final d = _data;
    return _flow(() => openGradePapers(context, courses: d == null ? const [] : hubGradePlaces(d), orgNames: staffOrgs(), initialCourseId: _courseFilter));
  }

  /// An attention card: one exam opens straight into its step, several narrow the list to them.
  void _attention(HubAttentionKind k) {
    final d = _data;
    if (d == null) return;
    final exams = d.exams.where((e) => hubInFocus(e, k)).toList();
    if (exams.length == 1) {
      final e = exams.single;
      _act(e, switch (k) {
        HubAttentionKind.toCorrect || HubAttentionKind.inCorrection => HubAction.correct,
        HubAttentionKind.unpublished => HubAction.getResult,
        HubAttentionKind.drafts => HubAction.edit,
      });
      return;
    }
    _search.clear();
    setState(() {
      _filter = const AllExamsFilter();
      _focus = k;
      _selected = null;
    });
  }

  Future<void> _publish(AllExam e) async {
    if (e.questionCount == 0) {
      showAppNotice(t('أضف أسئلة قبل النشر، افتح الاختبار في المحرر', 'Add questions before publishing: open the exam in the editor'), error: true);
      return;
    }
    final ok = await appConfirm(context,
        message: e.type == AllExamType.online
            ? t('إرسال «${e.displayTitle}» للطلاب؟ يرونه ويمكنهم أداؤه في موعده.', 'Send "${e.displayTitle}" to students? They will see it and can take it when it opens.')
            : t('نشر «${e.displayTitle}»؟ يصبح جاهزاً للطباعة والتسليم.', 'Publish "${e.displayTitle}"? It becomes ready to print and hand out.'),
        confirmLabel: e.type == AllExamType.online ? t('أرسل', 'Send') : t('نشر', 'Publish'));
    if (!ok || !mounted) return;
    _changed(() => _busy.add(e.id));
    final r = await _api.lifecycle(e.id, ExamAction.publish);
    if (!mounted) return;
    _changed(() => _busy.remove(e.id));
    showAppNotice(r.ok ? (e.type == AllExamType.online ? t('أُرسل الاختبار للطلاب', 'The exam is sent to students') : t('نُشر الاختبار', 'The exam is published')) : authoringError(r),
        error: !r.ok);
    if (r.ok) _load();
  }

  /// Grading, after the question an exam still running deserves.
  Future<void> _correct(AllExam e, HubBackOn? from) async {
    if (hubCorrectionOf(e) == HubCorrection.notEnded) {
      final anyway = await showAppSheet<bool>(
          context,
          (ctx) => AppSheetContent(title: t('لم ينتهِ هذا الاختبار بعد', 'This exam has not ended yet'), children: [
                HubNotEndedBody(text: hubNotEndedText(e), onWait: () => Navigator.pop(ctx, false), onCorrectAnyway: () => Navigator.pop(ctx, true)),
              ]));
      if (anyway != true || !mounted) return;
    }
    // a written-papers run has its own screen (D-662); everything else decides its route in the correction flow
    if (e.grading?.run == 'essay') return _flow(() => openEssayRunScreen(context, examId: e.id), from: from);
    await _flow(() => openExamCorrection(context, examId: e.id, title: e.displayTitle, courseId: e.courseId), from: from);
  }

  /// No degrees yet: from a file, or by grading.
  Future<void> _addDegrees(AllExam e, HubBackOn? from) async {
    final pick = await showAppSheet<HubAction>(
        context,
        (ctx) => AppSheetContent(title: t('لا درجات لهذا الاختبار بعد', 'This exam has no grades yet'), children: [
              HubNoDegreesBody(
                canImport: hubCanImport(e),
                importRecommended: hubImportRecommended(e),
                noCourse: e.courseId == null,
                onImport: () => Navigator.pop(ctx, HubAction.importDegrees),
                onCorrect: () => Navigator.pop(ctx, HubAction.correct),
              ),
            ]));
    if (pick != null && mounted) await _act(e, pick, from: from);
  }

  Future<void> _act(AllExam e, HubAction a, {HubBackOn? from}) async {
    final nav = Navigator.of(context);
    switch (a) {
      case HubAction.edit:
        await _flow(() => nav.push(MaterialPageRoute(builder: (_) => ExamEditorScreen(examId: e.id, courseId: e.courseId, orgId: e.orgId))), from: from);
      case HubAction.results:
        await _flow(() => nav.push(MaterialPageRoute(builder: (_) => ExamResultsScreen(examId: e.id, examTitle: e.displayTitle, courseId: e.courseId))), from: from);
      case HubAction.paper:
        await _flow(() => openExamPaper(context, examId: e.id, course: _data?.courseName(e) ?? ''), from: from);
      case HubAction.publish:
        await _publish(e);
      case HubAction.deliver:
        await _flow(() => openExamDeliver(context, examId: e.id, title: e.displayTitle, courseId: e.courseId, course: _data?.courseName(e) ?? ''), from: from);
      case HubAction.correct:
        await _correct(e, from);
      case HubAction.getResult:
        await _flow(() => openExamGetResult(context, examId: e.id, title: e.displayTitle, courseId: e.courseId), from: from);
      case HubAction.addDegrees:
        await _addDegrees(e, from);
      case HubAction.importDegrees:
        if (await openHubDegreesImport(context, examId: e.id, title: e.displayTitle)) _load();
      case HubAction.revision:
        await _flow(() => openExamRevision(context, examId: e.id, courseId: e.courseId, orgId: e.orgId, title: e.displayTitle), from: from);
      case HubAction.duplicate:
        await _duplicate(e, from);
    }
  }

  /// A new draft with the same questions (D-665), opened in the editor like any draft; the list shows it on return.
  Future<void> _duplicate(AllExam e, HubBackOn? from) async {
    _changed(() => _busy.add(e.id));
    final r = await ExamDuplicateApi().duplicate(e.id);
    if (!mounted) return;
    _changed(() => _busy.remove(e.id));
    final id = duplicatedExamId(r);
    if (id == null) {
      showAppNotice(r.ok ? t('تعذر فتح النسخة', 'The copy could not be opened') : duplicateErrorText(r), error: true);
      if (r.ok) _load();
      return;
    }
    showAppNotice(t('أُنشئت نسخة مسودة من «${e.displayTitle}»', 'A draft copy of "${e.displayTitle}" is ready'));
    await _flow(() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamEditorScreen(examId: id, courseId: e.courseId, orgId: e.orgId))), from: from);
  }

  /// A phone: the exam's steps as their own page, kept current while flows run from it.
  void _openPage(AllExam e) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => HubExamPage(
              examId: e.id,
              changes: _changes,
              exam: () => _data?.exams.where((x) => x.id == e.id).firstOrNull,
              course: () => _data?.courseName(e),
              org: () => _data?.orgName(e),
              busy: () => _busy.contains(e.id),
              now: widget.now,
              onAction: (x, a, from) => _act(x, a, from: from),
            )));
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

  List<Widget> _headerActions() {
    final grade = hubGradeKinds().isEmpty
        ? null
        : AppButton.ghost(key: const ValueKey('exam.hub.quick.grade'), label: t('تصحيح أوراق', 'Grade paper sheets'), icon: Icons.document_scanner_outlined, onPressed: _gradePapers);
    return [
      if (!AppConfig.disableList.contains(kHubRevisionKey))
        AppButton.ghost(
            key: const ValueKey('exam.hub.start_revision'),
            label: t('مراجعة الدرجات', 'Review grades'),
            icon: Icons.compare_arrows_rounded,
            tooltip: t('مراجعة درجات دون اختيار اختبار', 'Review grades without choosing an exam'),
            onPressed: () => _flow(() => openExamRevision(context, orgId: widget.orgId))),
      ?grade,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nav = Navigator.of(context);
    final header = AppPageHeader(
      title: t('الاختبارات', 'Exams'),
      subtitle: _subtitle,
      icon: Icons.fact_check_rounded,
      onBack: nav.canPop() ? () => nav.maybePop() : null,
      onRefresh: _load,
      updatedAt: _updated,
      primaryAction: AppButton.primary(key: const ValueKey('exam.hub.new'), label: t('اختبار جديد', 'New exam'), icon: Icons.add_rounded, onPressed: _newExam),
      actions: _headerActions(),
    );
    return BasePage(
      key: const ValueKey(kExamHubFeatureKey),
      enableFooterWidget: false,
      child: ColoredBox(
        color: c.background,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          Expanded(
            child: ExamHubBody(
              data: _data,
              error: _error == null ? null : ApiException.from(_error!).message,
              stage: _stage ?? HubStage.running,
              focus: _focus,
              filter: _filter,
              busy: _busy,
              selectedId: _selected,
              searchController: _search,
              now: widget.now,
              onSelect: (e) => setState(() => _selected = e.id),
              onOpen: _openPage,
              onStage: (s) => setState(() {
                _stage = s;
                _selected = null;
              }),
              onFilter: (f) => setState(() {
                _filter = f;
                if (f.query.isEmpty && _search.text.isNotEmpty) _search.clear();
              }),
              onClearFocus: () => setState(() {
                _focus = null;
                _selected = null;
              }),
              onAttention: _attention,
              onAction: (e, a) => _act(e, a),
              onRetry: _load,
              onRefresh: _load,
              onNew: _newExam,
            ),
          ),
        ]),
      ),
    );
  }
}

/// One exam on a phone: its steps on a page of its own. It reads the hub's list through [exam] and redraws on
/// [changes], so a flow run from here shows its result here; an exam no longer in the list closes the page.
class HubExamPage extends StatelessWidget {
  const HubExamPage({
    super.key,
    required this.examId,
    required this.changes,
    required this.exam,
    required this.course,
    required this.org,
    required this.busy,
    required this.onAction,
    this.now,
  });

  final int examId;
  final Listenable changes;
  final AllExam? Function() exam;
  final String? Function() course, org;
  final bool Function() busy;
  final void Function(AllExam, HubAction, HubBackOn) onAction;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: changes,
      builder: (context, _) {
        final e = exam();
        final nav = Navigator.of(context);
        return BasePage(
          key: ValueKey('exam.hub.page.$examId'),
          enableFooterWidget: false,
          child: ColoredBox(
            color: c.background,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppPageHeader(title: e?.displayTitle ?? t('الاختبار', 'Exam'), onBack: nav.canPop() ? () => nav.maybePop() : null),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final side = AppSpace.gutter(box.maxWidth);
                  return ListView(padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.xl), children: [
                    if (e == null)
                      AppEmpty(icon: Icons.fact_check_outlined, title: t('هذا الاختبار لم يعد في القائمة', 'This exam is no longer in the list'))
                    else
                      HubExamDetail(exam: e, course: course(), org: org(), busy: busy(), now: now, showTitle: false, onAction: (a) => onAction(e, a, (act) => whenBackOn(context, act))),
                  ]);
                }),
              ),
            ]),
          ),
        );
      },
    );
  }
}
