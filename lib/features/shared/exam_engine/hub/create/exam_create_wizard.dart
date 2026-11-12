// "New exam" in the Exam Hub: ONE wizard. Online (D-661): Where → How → Questions → Settings. On paper (D-697, the
// owner's flow): Where → How → Questions → Answer sheet (four layouts, the best fit for the questions preselected) →
// Bubble form (layouts 2 / 3) → Copies → Students (per student, no course) → Attributes → Paper design → Review. A step
// that does not apply is not shown; the choices so far are always in view and editable (a rail on a wide window, chips on
// a phone), Back and forward keep them, and the device remembers the last ones (`exam_create_prefs.dart`). What is pure
// is in exam_create_logic / offline_flow, the server's one draft in exam_create_sync, the drawn parts in
// exam_create_parts / offline_steps.
//
// The draft exists from the first moment something needs it (the students, the attributes, the paper design, a Google
// Forms import, "Full editor", "Save as a draft") and is the same draft after that, however often the teacher goes Back.
// Leaving asks what to do with it. Paper exams finish in Deliver (`openExamDeliver`), which owns preview, print and email.
library;

import 'dart:async' show unawaited;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../../../admin/admin_common.dart' show asMapList, t;
import '../../../rag/rag_learning.dart' show LearningApi, kRagLearningFeatureKey;
import '../../exam_all.dart';
import '../../exam_all_screen.dart' show staffOrgs;
import '../../exam_authoring.dart';
import '../../exam_authoring_screen.dart' show ExamEditorScreen;
import '../../exam_forms_import.dart' show GoogleFormsImportSheet, formExamTitle;
import '../../exam_gen_api.dart' show genMetaOf, kExamAutoCreateKey;
import '../../exam_generate.dart' show ExamGenReview, GenMark, deleteGenItem, regenerateGenItem, sendGenFeedback;
import '../../exam_generate_sheet.dart' show GenRejectSheet, GenReviewBar, QuickGenerateCard, openExamGenerator;
import '../../exam_quick.dart';
import '../../exam_quick_screen.dart' show QuickAdvancedPanel, QuickFilePanel, QuickQuestionCard, paperFileExtensions, quickFormsAvailable, quickTypeIcon;
import '../../exam_results_screen.dart';
import '../../paper/exam_setup.dart';
import '../../paper/exam_setup_wizard.dart' show TemplateStepBody;
import '../../paper/omr_counts.dart' show omrMinutesText;
import '../../paper/bubble/bubble_import_screen.dart' show openBubbleSheetFinder;
import '../../paper/templates/omr_template_learn.dart' show openOmrTemplateLearn;
import '../../../../../design/engine/design_engine.dart' show DesignPurpose;
import '../../../../../design/export_layout/layout_api.dart' show LayoutApi;
import '../../exam_paper_design_api.dart';
import '../../exam_paper_designer.dart' show PaperConflictChoice, blankPaperDoc, openPaperDesigner, paperDocFrom, paperSampleRow, paperStartChoices, showPaperConflictDialog;
import '../../exam_paper_bands.dart' show PaperPrintedId;
import '../deliver/exam_deliver_screen.dart' show openExamDeliver;
import 'answer_sheet_widgets.dart';
import 'attributes_step.dart';
import 'exam_create_logic.dart';
import 'exam_create_parts.dart';
import 'exam_create_prefs.dart';
import 'exam_create_sync.dart';
import 'offline_steps.dart';

/// Opens the wizard. [courseId] / [orgId] fix or narrow where the exam goes.
Future<void> openExamCreateWizard(BuildContext context, {int? orgId, int? courseId}) => Navigator.of(context).push<void>(MaterialPageRoute(
      // the name the paper setup already uses: the browser's Back belongs to this page, not to a deep link
      settings: const RouteSettings(name: '/exam-setup'),
      builder: (_) => ExamCreateWizard(orgId: orgId, courseId: courseId),
    ));

/// Every place an exam can go: the courses, then each organization the person works in, then personal.
List<NewExamPlace> createPlaces(AllExamsData data, Map<int, String> orgs, {int? orgId}) {
  final courses = newExamPlaces(data);
  final personal = courses.removeLast();
  final out = <NewExamPlace>[
    ...courses,
    for (final e in (orgs.entries.toList()..sort((a, b) => a.value.compareTo(b.value)))) (courseId: null, orgId: e.key, name: e.value),
    personal,
  ];
  if (orgId == null) return out;
  final here = [for (final p in out) if (p.orgId == orgId) p];
  return here.isEmpty ? [(courseId: null, orgId: orgId, name: orgs[orgId] ?? t('المؤسسة', 'The organization'))] : here;
}

/// The sheet types as the wizard needs them, so a render can hand them over without a server.
typedef CreateTemplates = ({List<OmrTemplateItem>? items, String? error});

class ExamCreateWizard extends StatefulWidget {
  const ExamCreateWizard({super.key, this.orgId, this.courseId, this.sync, this.placesLoader, this.templatesLoader, this.initialPlan, this.initialStep, this.startedQuestions});
  final int? orgId;
  final int? courseId;

  /// Tests and renders.
  final ExamCreateSync? sync;
  final Future<(List<NewExamPlace>, Map<int, String>)> Function()? placesLoader;
  final Future<CreateTemplates> Function()? templatesLoader;
  final ExamCreatePlan? initialPlan;
  final CreateStep? initialStep;
  final bool? startedQuestions;

  @override
  State<ExamCreateWizard> createState() => _ExamCreateWizardState();
}

class _ExamCreateWizardState extends State<ExamCreateWizard> {
  late final ExamCreateSync _sync = widget.sync ?? ExamCreateSync();
  late final ExamAuthoringApi _api = _sync.api;
  final _setupApi = ExamSetupApi();
  late final ExamCreatePlan _plan = widget.initialPlan ?? ExamCreatePlan(title: quickKindTitle(QuickKind.quiz));
  final _review = ExamGenReview();
  late final _learning = LearningApi();
  late final _title = TextEditingController(text: _plan.exam.title);

  bool _loading = true;
  String? _loadError;
  List<NewExamPlace>? _places;
  Map<int, String> _orgNames = const {};
  bool _whereNeeded = true;
  CreateStep _step = CreateStep.answer;

  // remembered from this teacher's previous exam (D-661)
  ExamCreatePrefs? _prefs;
  AnswerFormat? _lastAnswer;
  int? _lastTemplate;
  SheetCopies? _lastCopies;
  PaperLayout? _lastLayout;
  List<String> _lastAttributes = const [];
  CreateStep? _furthest;
  bool _busy = false;
  String? _error;
  bool _tried = false;
  final bool _identifierValid = true;   // nothing in the paper flow waits on the identifier plan any more (D-697)
  final _designApi = ExamPaperDesignApi();
  bool _designing = false;

  /// The teacher picked the layout: kept while it fits. Until then it follows the questions (the best fit).
  late bool _layoutPicked = _plan.layout != null;
  List<LockSession> _sessions = const [];
  int? _sessionsFor;

  // template
  List<OmrTemplateItem>? _templates;
  List<OmrTemplateItem> _pending = const [];
  String? _templatesError;
  bool _justSent = false;

  // questions
  late bool _started = widget.startedQuestions ?? _plan.hasContent;
  String _genNotice = '';
  bool _feedbackSent = false;

  // the end
  bool _published = false;

  bool get _omrOn => !AppConfig.disableList.contains(kExamOmrFeatureKey);
  bool get _identifiersOn => !AppConfig.disableList.contains(kExamIdentifiersFeatureKey);
  bool get _canGenerate => !AppConfig.disableList.contains(kExamAutoCreateKey);
  bool get _answerSheetOn => !AppConfig.disableList.contains(kExamAnswerSheetFeatureKey);

  List<CreateStep> get _steps => createSteps(_plan, whereNeeded: _whereNeeded, omrOn: _omrOn, identifiersOn: _identifiersOn);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<(List<NewExamPlace>, Map<int, String>)> _loadPlaces() async {
    final mode = AppModeController.instance;
    if (!mode.loaded) await mode.ready();
    final orgs = staffOrgs();
    final data = await loadAllExams(orgs: orgs);
    return (createPlaces(data, orgs, orgId: widget.orgId), orgs);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final fixedCourse = widget.courseId;
    _plan.answerSheetOn = _answerSheetOn;
    try {
      if (widget.initialPlan != null && widget.placesLoader == null) {
        _places = const [];
        _whereNeeded = false;
      } else {
        final (places, orgs) = await (widget.placesLoader?.call() ?? _loadPlaces());
        if (!mounted) return;
        _places = places;
        _orgNames = orgs;
      }
      final places = _places ?? const <NewExamPlace>[];
      if (fixedCourse != null) {
        final known = places.where((p) => p.courseId == fixedCourse).firstOrNull;
        _plan.setPlace(known ?? (courseId: fixedCourse, orgId: widget.orgId, name: ''));
        _whereNeeded = false;
      } else if (places.length == 1) {
        _plan.setPlace(places.first);
        _whereNeeded = false;
      }
    } catch (e) {
      if (!mounted) return;
      if (fixedCourse == null) {
        setState(() {
          _loading = false;
          _loadError = ApiException.from(e).message;
        });
        return;
      }
      // only the course's name was missing: the wizard works without it
      _plan.setPlace((courseId: fixedCourse, orgId: widget.orgId, name: ''));
      _whereNeeded = false;
    }
    if (!mounted) return;
    unawaited(_remember());   // never holds the first step back: a slow store only means nothing is preselected
    final steps = _steps;
    final initial = widget.initialStep;
    setState(() {
      _loading = false;
      _step = initial != null && steps.contains(initial) ? initial : steps.first;
      _furthest = _step;
    });
    _enter(_step);
  }

  /// This teacher's last choices on this device: the way of taking the exam is preselected while nothing is chosen; the
  /// layout, the copies and the attributes become the defaults of their steps.
  Future<void> _remember() async {
    int uid = 0;
    try {
      uid = context.read<MyAuthProvider>().currentUser?.id ?? 0;
    } catch (_) {
      // no auth in scope (tests, renders): remembered on the device alone
    }
    final prefs = _prefs = ExamCreatePrefs(uid);
    final got = await prefs.load();
    if (!mounted) return;
    final last = got.answer;
    setState(() {
      _lastAnswer = last;
      _lastTemplate = got.templateId;
      _lastCopies = got.copies;
      _lastLayout = got.layout;
      _lastAttributes = got.attributes;
      // the answer sheets as last time, while nothing was chosen here (D-687)
      if (got.bubble != null) _plan.bubbleSource = got.bubble!;
      if (got.idSource != null) _plan.idSource = got.idSource!;
      if (_plan.copies == null && got.copies != null) _plan.copies = got.copies;
      // only while the teacher has not answered yet
      if (_plan.answer == null && last != null) _pickMode(createModeOf(last));
    });
  }

  void _enter(CreateStep s) {
    if (s == CreateStep.layout) _ensureLayout();
    if (s == CreateStep.template && _templates == null) _loadTemplates();
    if (s == CreateStep.publish) _loadSessions();
  }

  /// Online or on paper: every other answer is kept, so a sheet chosen earlier stays chosen on the way back.
  void _pickMode(AnswerFormat v) => _plan.setOffline(v != AnswerFormat.online);

  /// The layout once the questions are known: kept while it still fits them, else the best fit (D-697). Without the
  /// answer-sheet step (`exam.answer_sheet` off) the best fit is taken as it is.
  void _ensureLayout() {
    if (!_plan.isPaper) return;
    final mix = _plan.mix;
    final l = _plan.layout;
    if (l != null && _layoutPicked && paperLayoutAvailable(l, mix, omrOn: _omrOn)) return;
    final best = recommendedPaperLayout(mix, omrOn: _omrOn);
    if (l == best) return;
    setState(() => _plan.setLayout(best));
  }

  Future<void> _loadSessions() async {
    final id = _plan.exam.courseId;
    if (id == null || id == _sessionsFor) return;
    _sessionsFor = id;
    final s = await _api.courseSessions(id);
    if (mounted) setState(() => _sessions = s);
  }

  void _go(CreateStep s) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _step = s;
      _error = null;
      _tried = false;
      final steps = _steps;
      if (_furthest == null || steps.indexOf(s) > steps.indexOf(_furthest!)) _furthest = s;
    });
    _enter(s);
  }

  /// The steps that read the exam on the server (the student list, the attributes, the paper design): the draft is
  /// brought up to date first.
  Future<void> _open(CreateStep s) async {
    if (const {CreateStep.identify, CreateStep.attributes, CreateStep.design}.contains(s) && !await _syncDraft()) return;
    if (mounted) _go(s);
  }

  // ── moving ──

  void _back() {
    final steps = _steps;
    final i = steps.indexOf(_step);
    if (i <= 0) {
      _askLeave();
      return;
    }
    _go(steps[i - 1]);
  }

  Future<void> _next() async {
    if (_busy) return;
    final s = _step;
    if (!createStepReady(s, _plan, identifierValid: _identifierValid, omrOn: _omrOn)) {
      setState(() => _tried = true);
      return;
    }
    // the steps after the questions follow the layout
    if (s == CreateStep.questions) _ensureLayout();
    final steps = _steps;
    final i = steps.indexOf(s);
    if (i == steps.length - 1) return _finish();
    await _open(steps[i + 1]);
  }

  /// The draft now matches the answers; false = the error is on the page.
  Future<bool> _syncDraft() async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    final e = await _sync.ensure(_plan);
    if (!mounted) return false;
    setState(() {
      _busy = false;
      _error = e;
    });
    return e == null;
  }

  Future<void> _finish() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    _plan.exam.title = _title.text;
    final e = await _sync.finish(_plan);
    if (!mounted) return;
    if (_sync.examId != null && !_feedbackSent) {
      _feedbackSent = true;
      unawaited(sendGenFeedback(_learning, _review, _review.onSave(_plan.exam.questions)));
    }
    if (e != null) {
      setState(() {
        _busy = false;
        _error = e;
      });
      return;
    }
    setState(() {
      _busy = false;
      _published = true;
    });
    unawaited(_prefs?.save(
      answer: _plan.answer,
      templateId: _plan.isBubble ? _plan.template?.id : null,
      bubble: _plan.isBubble ? _plan.bubbleSource : null,
      copies: _plan.asksCopies ? _plan.effectiveCopies : null,
      idSource: _plan.isPaper && _plan.hasCourse ? _plan.idSource : null,
      layout: _layoutPicked ? _plan.layout : null,
      attributes: [for (final a in _plan.attributes) a.key],
    ));
    if (_plan.isPaper) {
      final course = _plan.exam.courseId == null ? '' : (_plan.place?.name ?? '');   // a place without a course is named for the organization
      await openExamDeliver(context, examId: _sync.examId!, title: _plan.exam.title.trim(), courseId: _plan.exam.courseId, course: course);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _askLeave() async {
    if (_busy) return;
    final hasDraft = _sync.examId != null;
    if (!hasDraft && !_plan.hasContent) {
      Navigator.of(context).pop();
      return;
    }
    final (errors, perQ) = questionStepErrors(_plan);
    final canSave = errors.isEmpty && perQ.isEmpty;
    final pick = await showAppSheet<CreateLeave>(
        context,
        (ctx) => AppSheetContent(title: t('الخروج من إنشاء الاختبار؟', 'Leave this exam?'), children: [
              CreateLeaveBody(hasDraft: hasDraft, canSave: canSave, onPick: (v) => Navigator.pop(ctx, v), onStay: () => Navigator.pop(ctx)),
            ]));
    if (pick == null || !mounted) return;
    final nav = Navigator.of(context);
    switch (pick) {
      case CreateLeave.keep:
        if (canSave) await _sync.ensure(_plan);   // best effort: the draft keeps the latest answers
        if (mounted) nav.pop();
      case CreateLeave.save:
        if (await _syncDraft() && mounted) {
          showAppNotice(t('حُفظ كمسودة في صفحة الاختبارات', 'Saved as a draft on the Exams page'));
          nav.pop();
        }
      case CreateLeave.delete:
        setState(() => _busy = true);
        final e = await _sync.discard();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = e;
        });
        if (e == null) nav.pop();
      case CreateLeave.discard:
        nav.pop();
    }
  }

  // ── template ──

  /// [before]: the ids known before the teacher taught a sheet, to find the one just made.
  Future<void> _loadTemplates({Set<int>? before}) async {
    setState(() => _templatesError = null);
    List<OmrTemplateItem>? got;
    String? error;
    if (widget.templatesLoader != null) {
      final r = await widget.templatesLoader!();
      got = r.items;
      error = r.error;
    } else {
      final org = _plan.exam.orgId;
      var r = await _setupApi.templates(orgId: org);
      // no exams right in the organization, or a suspended one: the global sheets still
      if (!r.ok && org != null && (r.status == 403 || r.status == 423)) r = await _setupApi.templates();
      if (r.ok) {
        got = [for (final m in asMapList(r.map['items'])) OmrTemplateItem.fromJson(m)];
      } else {
        error = setupErrorText(r);
      }
    }
    if (!mounted) return;
    final all = got;
    setState(() {
      _templatesError = error;
      if (all == null) return;
      final usable = choosableTemplates(all);
      _templates = usable;
      _pending = pendingTemplates(all);
      final made = before == null ? null : [for (final x in all) if (!before.contains(x.id)) x].lastOrNull;
      _justSent = made?.status == 'pending_approval';
      final tid = _plan.template?.id;
      final keep = usable.where((x) => x.id == tid).firstOrNull;
      // then the sheet of the previous bubble exam, if it still holds these questions
      final last = usable.where((x) => x.id == _lastTemplate && (x.questions <= 0 || x.questions >= _plan.questionCount)).firstOrNull;
      _plan.template = made != null && made.published ? made : (keep ?? last ?? recommendedTemplate(usable, _plan.questionCount));
      _plan.normalize();
    });
  }

  /// "Import an example sheet": one photo of a sheet the teacher has (D-340 / D-500).
  Future<void> _ownSheet() async {
    final made = await openBubbleSheetFinder(context, orgId: _plan.exam.orgId);
    if (!mounted || made == null) return;
    setState(() {
      _plan.template = made;
      _plan.bubbleForm = BubbleFormSource.imported;
      _plan.normalize();
    });
    await _loadTemplates();
  }

  /// "Design a new sheet": a layout learned from an upload (published, or waiting for approval).
  Future<void> _designSheet() async {
    final before = {for (final x in [...?_templates, ..._pending]) x.id};
    final saved = await openOmrTemplateLearn(context);
    if (!mounted || saved != true) return;
    await _loadTemplates(before: before);
    if (mounted && _plan.template != null && !before.contains(_plan.template!.id)) setState(() => _plan.bubbleForm = BubbleFormSource.designed);
  }

  /// Out of the bubble sheet: everything is answered in the question paper (layout 1).
  void _usePaper() {
    setState(() {
      _layoutPicked = true;
      _plan.setLayout(PaperLayout.allInPaper);
    });
    if (_step == CreateStep.template) _go(CreateStep.sheets);
  }

  // ── questions ──

  Future<void> _generate() async {
    final q = _plan.exam;
    final got = await openExamGenerator(context, courseId: q.courseId!, orgId: q.orgId, avoidPrompts: [for (final x in q.questions) x.prompt]);
    if (got == null || got.items.isEmpty || !mounted) return;
    _review.track(got);
    setState(() {
      q.questions.addAll(got.questions);
      _genNotice = got.notice;
      _started = true;
    });
    final cant = got.questions.where((x) => !bubbleCanHold(x.type)).length;
    showAppNotice(_plan.isBubble && cant > 0
        ? t('أُضيف ${questionsCountText(got.items.length)}، منها ${questionsCountText(cant)} لا تناسب ورقة التظليل', '${questionsCountText(got.items.length)} added; ${questionsCountText(cant)} do not fit a bubble sheet')
        : t('أُضيف ${questionsCountText(got.items.length)}. راجعها قبل النشر', '${questionsCountText(got.items.length)} added. Review them before publishing'));
  }

  Future<void> _pickFile() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: paperFileExtensions);
    if (f == null) return;
    final bytes = kIsWeb || f.path == null ? await f.readAsBytes() : null;
    if (!mounted) return;
    setState(() {
      final q = _plan.exam;
      q.fileName = f.name;
      q.fileBytes = bytes;
      q.filePath = kIsWeb ? null : f.path;
      _plan.normalize();
    });
  }

  Future<void> _importForms() async {
    var done = false;
    await showAppSheet<bool>(
        context,
        (_) => GoogleFormsImportSheet(
              api: _api,
              createExam: (form) async {
                final q = _plan.exam;
                q.title = formExamTitle(form, q.title);
                _title.text = q.title;
                final e = await _sync.ensure(_plan);
                done = e == null;
                return QuickResult(examId: _sync.examId, error: e);
              },
            ));
    if (done && mounted) {
      setState(() => _started = true);
      await _refreshImported();
    }
  }

  Future<void> _refreshImported() async {
    final r = await _sync.imported();
    if (r == null || !mounted) return;
    setState(() {
      _plan.importedQuestions = r.questions;
      _plan.importedPoints = r.points;
      _plan.importedNotBubble = r.notBubble;
    });
  }

  Future<void> _openEditor() async {
    if (_busy || !await _syncDraft() || !mounted) return;
    final q = _plan.exam;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamEditorScreen(examId: _sync.examId, courseId: q.courseId, orgId: q.orgId)));
    if (mounted) await _refreshImported();
  }

  void _way(CreateQuestionWay w) {
    void source(QuickSource s) => setState(() {
          _started = true;
          _plan.exam.source = s;
          _plan.normalize();
        });
    switch (w) {
      case CreateQuestionWay.automatic:
        _generate();
      case CreateQuestionWay.manual:
        source(QuickSource.questions);
      case CreateQuestionWay.file:
        source(QuickSource.file);
      case CreateQuestionWay.forms:
        _importForms();
    }
  }

  void _removeNotHeld() => setState(() {
        final out = bubbleCheckOf(_plan).notHeld.toSet();
        _plan.exam.questions.removeWhere(out.contains);
      });

  bool _reviewing(QuickQuestion x) => _review.supported && _review.isGenerated(x) && !AppConfig.disableList.contains(kRagLearningFeatureKey);

  Future<void> _reject(QuickQuestion x) async {
    final reason = await showAppSheet<String>(context, (_) => const GenRejectSheet());
    if (reason == null || !mounted) return;
    final ref = _review.of(x);
    final v2 = genMetaOf(x) != null;
    final call = _review.reject(x, reason.isEmpty ? null : reason);
    setState(() => _plan.exam.questions.remove(x));
    if (call != null) unawaited(sendGenFeedback(_learning, _review, [call]));
    if (ref != null && v2 && ref.serverN != null) unawaited(deleteGenItem(ref.draftId, ref.serverN!));
  }

  Future<QuickQuestion?> _regenerate(QuickQuestion old) async {
    final ref = _review.of(old);
    if (ref == null || ref.serverN == null) return null;
    final fresh = await regenerateGenItem(ref.draftId, ref.serverN!);
    if (fresh == null || !mounted) return null;
    setState(() {
      final list = _plan.exam.questions;
      final at = list.indexOf(old);
      if (at >= 0) list[at] = fresh;
      _review.replace(old, fresh);
    });
    return fresh;
  }

  // ── the page ──

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget page;
    if (_loading) {
      page = const SafeArea(child: AppListSkeleton(items: 5, withAvatar: false));
    } else if (_loadError != null) {
      page = AppEmpty(icon: Icons.error_outline_rounded, title: _loadError!, actionLabel: t('إعادة المحاولة', 'Try again'), onAction: _load);
    } else if (_published && _plan.isElectronic) {
      page = _done();
    } else if (_published) {
      page = const SafeArea(child: AppListSkeleton(items: 3, withAvatar: false));   // behind Deliver, for the moment it opens
    } else {
      page = _shell();
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_published) {
          Navigator.of(context).pop();
        } else {
          _back();   // the system / browser Back walks the steps, then asks before leaving
        }
      },
      child: BasePage(key: const ValueKey('exam.create'), enableFooterWidget: false, child: ColoredBox(color: c.background, child: page)),
    );
  }

  Widget _done() {
    final q = _plan.exam;
    final id = _sync.examId!;
    final nav = Navigator.of(context);
    final where = _plan.place?.name ?? '';
    return CreateDoneBody(
      title: q.title.trim(),
      place: where.isEmpty ? null : where,
      lines: [
        ...createEstimate(_plan),
        (t('يبدأ', 'Opens'), q.startsAt == null ? t('الآن', 'Now') : AppTime.dateTime(q.startsAt!)),
      ],
      onDone: () => nav.pop(),
      onOpen: () => nav.pushReplacement(MaterialPageRoute(builder: (_) => ExamEditorScreen(examId: id, courseId: q.courseId, orgId: q.orgId))),
      onFollow: () => nav.pushReplacement(MaterialPageRoute(builder: (_) => ExamResultsScreen(examId: id, examTitle: q.title.trim(), courseId: q.courseId))),
      onShare: () async {
        await Clipboard.setData(ClipboardData(
            text: t('الاختبار «${q.title.trim()}» متاح الآن في $where على NextBrain.', 'The exam "${q.title.trim()}" is now open in $where on NextBrain.')));
        showAppNotice(t('نسخنا الرسالة. الصقها حيث تكلّم طلابك.', 'Message copied. Paste it wherever you talk to your students.'));
      },
    );
  }

  Widget _shell() {
    final steps = _steps;
    final i = steps.indexOf(_step).clamp(0, steps.length - 1);
    final furthestAt = _furthest == null ? i : steps.indexOf(_furthest!);
    final items = <CreateSummaryItem>[];
    var allBeforeReady = true;
    for (var k = 0; k < steps.length; k++) {
      final s = steps[k];
      final ready = createStepReady(s, _plan, identifierValid: _identifierValid, omrOn: _omrOn);
      final locked = s == CreateStep.where && _sync.examId != null;
      final reachable = !locked && !_busy && k != i && allBeforeReady && k <= furthestAt + 1;
      items.add(CreateSummaryItem(
        label: createStepLabel(s),
        value: createStepValue(s, _plan),
        state: k == i ? CreateItemState.current : (ready && k <= furthestAt ? CreateItemState.done : CreateItemState.todo),
        locked: locked,
        onTap: reachable ? () => _open(s) : (locked ? _lockedNotice : null),
      ));
      if (!ready) allBeforeReady = false;
    }
    final last = i == steps.length - 1;
    final ready = createStepReady(_step, _plan, identifierValid: _identifierValid, omrOn: _omrOn);
    final (title, subtitle) = _texts();
    return ExamCreateShell(
      stepKey: _step,
      items: items,
      index: i,
      stepLabel: createStepLabel(_step),
      title: title,
      subtitle: subtitle,
      error: _error,
      hint: ready ? null : _hint(),
      body: _body(),
      primaryLabel: last ? (_plan.isElectronic ? t('انشر الاختبار', 'Publish the exam') : t('أنشئ وجهّز الطباعة', 'Create and prepare printing')) : t('متابعة', 'Continue'),
      primaryIcon: last && _plan.isElectronic ? Icons.send_rounded : null,
      // the questions step takes the press even when not ready: it is what shows which question needs what
      onPrimary: _busy || !(ready || _step == CreateStep.questions) ? null : _next,
      busy: _busy,
      backLabel: i == 0 ? t('إغلاق', 'Close') : t('رجوع', 'Back'),
      onBack: _busy ? null : _back,
      onClose: _askLeave,
      estimate: createEstimate(_plan),
    );
  }

  void _lockedNotice() => showAppNotice(t('المسودة أُنشئت بالفعل في هذا المكان. لتغييره ابدأ اختبارًا جديدًا.', 'The draft already exists here. To change this, start a new exam.'));

  (String, String?) _texts() => switch (_step) {
        CreateStep.where => (t('لأي مقرر هذا الاختبار؟', 'Where does this exam belong?'), t('يحدد المكان طلاب الاختبار', 'The place decides who the students are')),
        CreateStep.answer => (t('كيف يُؤدّى الاختبار؟', 'How is the exam taken?'), t('على التطبيق أو ورقيًا', 'In the app, or on paper')),
        CreateStep.questions => (t('الأسئلة', 'The questions'), null),
        CreateStep.layout => (t('أين يجيب الطلاب؟', 'Where do students answer?'), t('اخترنا الأنسب لأسئلتك، ويمكنك تغييره', 'We picked the best fit for your questions; you can change it')),
        CreateStep.template => (t('نموذج ورقة التظليل', 'The bubble form'), t('ورقة جاهزة، أو استورد ورقة لديك، أو صمّم ورقة جديدة', 'A ready sheet, one you already have, or a new design')),
        CreateStep.publish => (t('متى وكيف يفتح؟', 'When and how does it open?'), null),
        CreateStep.sheets => (t('كم نسخة تُطبع؟', 'Which copies are printed?'), t('نسخة عامة واحدة، أو نسخة باسم كل طالب', 'One generic copy, or one named for each student')),
        CreateStep.identify => (t('من هم الطلاب؟', 'Who are the students?'), t('تُطبع النسخ من القائمة التي ترفعها', 'The copies are printed from the list you upload')),
        CreateStep.attributes => (t('ماذا يُطبع عن كل طالب؟', 'What is printed about each student?'), null),
        CreateStep.design => (t('تصميم الورقة', 'The paper design'), t('الرأس والشعار وبيانات الطالب', 'The header, the logo and the student details')),
        CreateStep.review => (t('راجع وأنشئ', 'Review and create'), t('اضغط على أي سطر لتغييره', 'Tap any line to change it')),
      };

  String? _hint() => switch (_step) {
        CreateStep.where => t('اختر المكان للمتابعة', 'Choose a place to continue'),
        CreateStep.answer => t('اختر طريقة الاختبار للمتابعة', 'Choose how the exam is taken to continue'),
        CreateStep.layout => t('اختر ورقة الإجابة للمتابعة', 'Choose the answer sheet to continue'),
        CreateStep.template => t('اختر ورقة معتمدة للمتابعة', 'Choose an approved sheet to continue'),
        CreateStep.identify => t('ارفع قائمة الطلاب للمتابعة', 'Upload the student list to continue'),
        _ => null,
      };

  Widget _body() => switch (_step) {
        CreateStep.where => CreateWhereBody(places: _places, selected: _plan.place, orgNames: _orgNames, onPick: (p) => setState(() => _plan.setPlace(p))),
        CreateStep.answer => CreateAnswerBody(
            formats: kCreateModes,
            value: _plan.answer == null ? null : createModeOf(_plan.answer!),
            lastUsed: _lastAnswer == null ? null : createModeOf(_lastAnswer!),
            onPick: (v) => setState(() => _pickMode(v)),
          ),
        CreateStep.questions => _questionsBody(),
        CreateStep.layout => CreateLayoutBody(
            options: paperLayoutOptions(_plan.mix, omrOn: _omrOn),
            value: _plan.layout,
            recommended: recommendedPaperLayout(_plan.mix, omrOn: _omrOn),
            lastUsed: _lastLayout,
            mix: _plan.mix,
            onPick: (l) => setState(() {
              _layoutPicked = true;
              _plan.setLayout(l);
            }),
          ),
        CreateStep.template => _templateBody(),
        CreateStep.publish => _publishBody(),
        CreateStep.sheets => CreateCopiesBody(
            copies: _plan.effectiveCopies,
            hasCourse: _plan.hasCourse,
            personalAllowed: _plan.personalAllowed,
            whyNotPersonal: _plan.exam.isFile
                ? t('الملف المرفوع يُطبع كما هو، فلا يحمل اسم الطالب', 'An uploaded file prints as it is, so it cannot carry a name')
                : t('ورقتك الخاصة لا تطبعها NextBrain', 'NextBrain does not print your own sheet'),
            lastUsed: _lastCopies,
            onCopies: (v) => setState(() => _plan.setCopies(v)),
            versions: CreateVersionsPanel(
              plan: _plan,
              onVersions: (n) => setState(() => _plan.versions = n),
              onShuffleQuestions: (v) => setState(() => _plan.shuffleQuestions = v),
              onShuffleOptions: (v) => setState(() => _plan.shuffleOptions = v),
            ),
          ),
        CreateStep.identify => PeopleFileStep(
            examId: _sync.examId!,
            onCount: (n) {
              if (mounted && n != _plan.peopleCount) setState(() => _plan.peopleCount = n);
            },
          ),
        CreateStep.attributes => AttributesStep(
            key: ValueKey('create.attributes.${_sync.examId}.${_plan.effectiveCopies.name}.${_plan.peopleCount}'),
            examId: _sync.examId!,
            courseId: _plan.exam.courseId,
            initial: [for (final a in _plan.attributes) a.key],
            remembered: _lastAttributes,
            idSource: asksIdSource(_plan) ? _plan.idSource : null,
            onIdSource: (v) => setState(() => _plan.idSource = v),
            onChanged: (list) {
              if (mounted) setState(() => _plan.attributes = list);
            },
          ),
        CreateStep.design => CreatePaperDesignBody(
            designed: _plan.designed,
            attributes: [for (final a in _plan.attributes) a.label],
            busy: _designing,
            onDesign: _designing ? null : _designPaper,
          ),
        CreateStep.review => CreateReviewBody(lines: _reviewLines(), onEdit: _busy ? null : _open),
      };

  /// Each step taken, in a line: tapping one goes back to it with every answer kept.
  List<ReviewLine> _reviewLines() => [
        for (final s in _steps)
          if (s != CreateStep.review && createStepValue(s, _plan) != null) (step: s, label: createStepLabel(s), value: createStepValue(s, _plan)!),
      ];

  /// The paper's design (D-196) in the design engine, with this exam's attributes in the sample header; saved on the
  /// draft, so Deliver prints with it.
  Future<void> _designPaper() async {
    final id = _sync.examId;
    if (id == null) return;
    setState(() => _designing = true);
    try {
      final held = await _designApi.load(id);
      var doc = held?.document;
      if (doc == null) {
        final r = await LayoutApi.instance.starters(purpose: DesignPurpose.examPaper);
        final choices = r.ok ? paperStartChoices(r.data!, const []) : const [];
        doc = choices.isEmpty ? blankPaperDoc(purpose: DesignPurpose.examPaper) : paperDocFrom(choices.first.document, purpose: DesignPurpose.examPaper);
      }
      if (!mounted) return;
      final q = _plan.exam;
      final sample = paperSampleRow(
        institution: _orgNames[q.orgId] ?? '',
        course: q.courseId == null ? '' : (_plan.place?.name ?? ''),
        title: q.title.trim(),
        date: '',
        duration: omrMinutesText(q.durationMinutes),
        total: fmtPoints(_plan.totalPoints),
        instructions: '',
        identifiers: [
          for (final a in _plan.attributes)
            if (a.key != 'name') PaperPrintedId(labelAr: a.label, labelEn: a.label),
        ],
      );
      final out = await openPaperDesigner(context, purpose: DesignPurpose.examPaper, title: q.title.trim(), initial: doc, sample: sample, orgId: q.orgId);
      if (out == null || !mounted) return;
      var r = await _designApi.save(id, document: out, cover: held?.cover, version: held?.version ?? 0);
      if (!mounted) return;
      if (r.conflict) {
        final pick = await showPaperConflictDialog(context);
        if (!mounted || pick == null || pick == PaperConflictChoice.reload) return;
        final cur = await _designApi.load(id);
        if (!mounted || cur == null) return;
        r = await _designApi.save(id, document: out, cover: cur.cover, version: cur.version);
        if (!mounted) return;
      }
      if (!r.ok) {
        showAppNotice(r.error ?? t('تعذّر حفظ التصميم', 'Could not save the design'), error: true);
        return;
      }
      setState(() => _plan.designed = true);
    } finally {
      if (mounted) setState(() => _designing = false);
    }
  }

  Widget _templateBody() {
    final check = bubbleCheckOf(_plan);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CreateBubbleSourceBody(value: _plan.bubbleSource, onPick: (v) => setState(() => _plan.bubbleSource = v)),
      const SizedBox(height: AppSpace.sm),
      CreateBubbleWays(onImport: _ownSheet, onDesign: _designSheet),
      const SizedBox(height: AppSpace.md),
      TemplateStepBody(
        templates: _templates,
        error: _templatesError,
        selectedId: _plan.template?.id,
        onPick: (x) => setState(() {
          _plan.template = x;
          _plan.bubbleForm = BubbleFormSource.template;
          _plan.normalize();
        }),
        onRetry: _loadTemplates,
        onLearn: null,
        onOwnSheet: null,   // "Import an example sheet" above
        onPaperOnly: _usePaper,
      ),
      // what is waiting comes after what can be used now
      if (_pending.isNotEmpty || _justSent) ...[
        const SizedBox(height: AppSpace.sm),
        CreatePendingTemplates(items: _pending, justSent: _justSent),
      ],
      if (_plan.ownSheet) ...[const SizedBox(height: AppSpace.sm), const CreateOwnSheetNote()],
      if (_plan.template != null && check.blocks) ...[const SizedBox(height: AppSpace.sm), CreateBubbleProblems(check: check)],
    ]);
  }

  Widget _questionsBody() {
    final c = context.colors;
    final q = _plan.exam;
    // the layout follows the questions (D-697): only an exam made the D-661 way, its bubble sheet chosen first, is held to it
    final bubble = _plan.isBubble && _plan.layout == null;
    if (!_started) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (bubble) ...[const CreateBubbleRules(), const SizedBox(height: AppSpace.md)],
        if (_plan.answerBooklet) ...[const CreateTableRules(), const SizedBox(height: AppSpace.md)],
        CreateQuestionWayBody(onPick: _way, hasCourse: _plan.hasCourse, canGenerate: _canGenerate, canImportForms: quickFormsAvailable, bubble: bubble),
      ]);
    }
    final (rawErrors, perQ) = _tried ? questionStepErrors(_plan) : (const <String>[], const <int, List<String>>{});
    final check = bubbleCheckOf(_plan);
    void source(QuickSource s) => setState(() {
          q.source = s;
          _plan.normalize();
        });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(key: const ValueKey('create.title'), controller: _title, label: t('اسم الاختبار', 'Exam name'), onChanged: (v) => setState(() => q.title = v)),
      const SizedBox(height: AppSpace.sm),
      if (bubble) ...[const CreateBubbleRules(), const SizedBox(height: AppSpace.sm)],
      if (bubble && _plan.answerSheetOn) ...[
        AppBanner(
          key: const ValueKey('create.bubble.written'),
          icon: Icons.edit_note_rounded,
          text: t('الأسئلة الكتابية (رقم، كلمة، إجابة قصيرة أو طويلة) تُطبع في ورقة إجابة منفصلة يقرؤها الماسح.',
              'Written questions (a number, a word, a short or long answer) go on a separate answer sheet the scanner reads.'),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
      if (_plan.answerBooklet) ...[const CreateTableRules(), const SizedBox(height: AppSpace.sm)],
      if (check.blocks) ...[
        CreateBubbleProblems(check: check, onRemove: _removeNotHeld, onNormal: _usePaper, onEditor: _openEditor),
        const SizedBox(height: AppSpace.xs),
      ],
      if (!bubble) ...[
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppChoiceChip(label: t('أسئلة في التطبيق', 'Questions in the app'), icon: Icons.quiz_outlined, selected: !q.isFile, onTap: () => source(QuickSource.questions)),
          AppChoiceChip(label: t('رفع ملف الامتحان', 'Upload the exam file'), icon: Icons.upload_file_rounded, selected: q.isFile, onTap: () => source(QuickSource.file)),
        ]),
        const SizedBox(height: AppSpace.sm),
      ],
      if (q.isFile)
        QuickFilePanel(fileName: q.fileName, points: q.filePoints, offline: _plan.isPaper, onPick: _busy ? null : _pickFile, onPoints: (v) => setState(() => q.filePoints = v))
      else ...[
        if (_plan.importedQuestions > 0) ...[
          CreateImportedCard(count: _plan.importedQuestions, points: _plan.importedPoints, onEditor: _openEditor),
          const SizedBox(height: AppSpace.sm),
        ],
        if (_plan.hasCourse)
          ParentComponent(
            featureKey: kExamAutoCreateKey,
            child: Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: QuickGenerateCard(onTap: _busy ? null : _generate)),
          ),
        if (_genNotice.isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: _genNotice)),
        for (var i = 0; i < q.questions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_reviewing(q.questions[i]))
                GenReviewBar(
                  key: ObjectKey(_review.of(q.questions[i])),
                  mark: _review.of(q.questions[i])!.mark,
                  onAccept: () => setState(() => _review.mark(q.questions[i], GenMark.accepted)),
                  onEdit: () => setState(() => _review.mark(q.questions[i], GenMark.edited)),
                  onReject: () => _reject(q.questions[i]),
                  meta: genMetaOf(q.questions[i]),
                  onRegenerate: genMetaOf(q.questions[i]) == null ? null : () => _regenerate(q.questions[i]),
                ),
              QuickQuestionCard(
                key: ObjectKey(q.questions[i]),
                index: i,
                question: q.questions[i],
                orgId: q.orgId,
                courseId: q.courseId,
                errors: perQ[i] ?? const [],
                onChanged: () => setState(() {}),
                onRemove: _reviewing(q.questions[i]) ? () => _reject(q.questions[i]) : () => setState(() => q.questions.removeAt(i)),
              ),
            ]),
          ),
        if (q.questions.isEmpty && _plan.importedQuestions == 0)
          AppEmpty(icon: Icons.post_add_rounded, title: t('أضف أول سؤال', 'Add the first question'), message: t('اختر نوع السؤال من الأسفل', 'Pick a question type below')),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final ty in bubble ? [...kBubbleQuestionTypes, if (_plan.answerSheetOn) ...kWrittenQuestionTypes] : quickQuestionTypes)
            AppPill(key: ValueKey('create.add.$ty'), icon: quickTypeIcon(ty), label: quickTypeLabel(ty), onTap: () => setState(() => q.questions.add(QuickQuestion.ofType(ty)))),
        ]),
      ],
      if (_tried && rawErrors.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: rawErrors.map(quickCodeText).join('\n')),
      ],
      if (_tried && rawErrors.isEmpty && perQ.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: t('أكمل الأسئلة المعلّمة', 'Complete the marked questions')),
      ],
    ]);
  }

  Widget _publishBody() {
    final c = context.colors;
    final errors = publishStepErrors(_plan);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CreatePublishBody(
        plan: _plan,
        onPaperPlan: (v) => setState(() {
          _plan.paperPlan = v;
          _plan.normalize();
        }),
        onVersions: (n) => setState(() => _plan.versions = n),
        onShuffleQuestions: (v) => setState(() => _plan.shuffleQuestions = v),
        onShuffleOptions: (v) => setState(() => _plan.shuffleOptions = v),
        electronicDetail: QuickAdvancedPanel(exam: _plan.exam, sessions: _sessions, onChanged: () => setState(() {}), onFullEditor: _busy ? null : _openEditor),
      ),
      if (errors.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: errors.map(quickCodeText).join('\n')),
      ],
    ]);
  }
}
