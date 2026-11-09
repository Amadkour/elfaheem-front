// "New exam" in the Exam Hub: ONE wizard, Where → Type → Bubble sheet → Questions → Publish → Students, with the choices
// so far always in view and editable (a rail on a wide window, chips on a phone). What is pure is in exam_create_logic,
// the server's one draft in exam_create_sync, the drawn parts in exam_create_parts.
//
// The draft exists from the first moment something needs it (the students step, a Google Forms import, "Full editor",
// "Save as a draft") and is the same draft after that, however often the teacher goes Back. Leaving asks what to do with
// it. Paper exams finish in Deliver (`openExamDeliver`), which owns preview, Studio, print and email.
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
import 'package:flutter_education_app/utils/widget/base_page.dart';
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
import '../../paper/templates/omr_template_learn.dart' show openOmrTemplateLearn;
import '../../paper/templates/own_sheet.dart' show openOwnSheet;
import '../deliver/exam_deliver_screen.dart' show openExamDeliver;
import '../deliver/identifier_plan_step.dart' show IdentifierPlanStep;
import 'exam_create_logic.dart';
import 'exam_create_parts.dart';
import 'exam_create_sync.dart';

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
  CreateStep _step = CreateStep.type;
  CreateStep? _furthest;
  bool _busy = false;
  String? _error;
  bool _tried = false;
  bool _identifierValid = false;
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

  List<CreateStep> get _steps => createSteps(_plan, whereNeeded: _whereNeeded, omrOn: _omrOn, identifiersOn: _identifiersOn);

  @override
  void initState() {
    super.initState();
    if (!_omrOn) _plan.type = CreateType.normal;
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
    final steps = _steps;
    final initial = widget.initialStep;
    setState(() {
      _loading = false;
      _step = initial != null && steps.contains(initial) ? initial : steps.first;
      _furthest = _step;
    });
    _enter(_step);
  }

  void _enter(CreateStep s) {
    if (s == CreateStep.template && _templates == null) _loadTemplates();
    if (s == CreateStep.publish) {
      _loadSessions();
      _plan.publish ??= PublishKind.electronic;
      _plan.normalize();
    }
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

  /// The students step reads the exam on the server: the draft is brought up to date first.
  Future<void> _open(CreateStep s) async {
    if (s == CreateStep.identify && !await _syncDraft()) return;
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
    if (!createStepReady(s, _plan, identifierValid: _identifierValid)) {
      setState(() => _tried = true);
      return;
    }
    final steps = _steps;
    final i = steps.indexOf(s);
    if (i == steps.length - 1) return _finish();
    await _open(steps[i + 1]);
  }

  /// The draft now matches the answers; false = the error is on the page.
  Future<bool> _syncDraft() async {
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
    if (_plan.isPaper) {
      await openExamDeliver(context, examId: _sync.examId!, title: _plan.exam.title.trim(), courseId: _plan.exam.courseId);
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
      _plan.template = made != null && made.published ? made : (keep ?? recommendedTemplate(usable, _plan.questionCount));
      _plan.normalize();
    });
  }

  Future<void> _learnTemplate() async {
    final known = {for (final x in _templates ?? const <OmrTemplateItem>[]) x.id, for (final x in _pending) x.id};
    final saved = await openOmrTemplateLearn(context);
    if (mounted) await _loadTemplates(before: saved == true ? known : null);
  }

  Future<void> _ownSheet() async {
    final made = await openOwnSheet(context, orgId: _plan.exam.orgId);
    if (!mounted || made == null) return;
    setState(() {
      _plan.template = made;
      _plan.normalize();
    });
    await _loadTemplates();
  }

  void _useNormal() {
    setState(() => _plan.setType(CreateType.normal));
    if (_step == CreateStep.template) _go(CreateStep.questions);
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
    if (!await _syncDraft() || !mounted) return;
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

  void _removeNotHeld() => setState(() => _plan.exam.questions.removeWhere((x) => !bubbleCanHold(x.type)));

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
      final ready = createStepReady(s, _plan, identifierValid: _identifierValid);
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
    final ready = createStepReady(_step, _plan, identifierValid: _identifierValid);
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
        CreateStep.type => (t('ما نوع الاختبار؟', 'What kind of exam is it?'), null),
        CreateStep.template => (t('اختر ورقة التظليل', 'Choose the bubble sheet'), t('اخترنا لك الأنسب، ويمكنك تغييرها', 'We picked the closest fit; you can change it')),
        CreateStep.questions => (t('الأسئلة', 'The questions'), null),
        CreateStep.publish => (t('كيف ستنشره؟', 'How will you publish it?'), null),
        CreateStep.identify => (t('كيف نتعرف على كل طالب؟', 'How do we identify each student?'), t('تُطابق كل ورقة بصاحبها من خلال هذه القيمة', 'Each paper is matched to its student by this value')),
      };

  String? _hint() => switch (_step) {
        CreateStep.where => t('اختر المكان للمتابعة', 'Choose a place to continue'),
        CreateStep.type => t('اختر نوع الاختبار للمتابعة', 'Choose a kind to continue'),
        CreateStep.template => t('اختر ورقة معتمدة للمتابعة', 'Choose an approved sheet to continue'),
        CreateStep.questions || CreateStep.publish => null,
        CreateStep.identify => t('أكمل تحديد الطلاب للمتابعة', 'Finish identifying the students to continue'),
      };

  Widget _body() => switch (_step) {
        CreateStep.where => CreateWhereBody(places: _places, selected: _plan.place, orgNames: _orgNames, onPick: (p) => setState(() => _plan.setPlace(p))),
        CreateStep.type => CreateTypeBody(value: _plan.type, onPick: (v) => setState(() => _plan.setType(v))),
        CreateStep.template => _templateBody(),
        CreateStep.questions => _questionsBody(),
        CreateStep.publish => _publishBody(),
        CreateStep.identify => IdentifierPlanStep(
            examId: _sync.examId!,
            courseId: _plan.exam.courseId,
            // may be reported while the step is still building
            onValid: (v) => WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && v != _identifierValid) setState(() => _identifierValid = v);
            }),
          ),
      };

  Widget _templateBody() {
    final check = bubbleCheckOf(_plan);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TemplateStepBody(
        templates: _templates,
        error: _templatesError,
        selectedId: _plan.template?.id,
        onPick: (x) => setState(() {
          _plan.template = x;
          _plan.normalize();
        }),
        onRetry: _loadTemplates,
        onLearn: _learnTemplate,
        onOwnSheet: _ownSheet,
        onPaperOnly: _useNormal,
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
    final bubble = _plan.isBubble;
    if (!_started) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (bubble) ...[const CreateBubbleRules(), const SizedBox(height: AppSpace.md)],
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
      if (check.blocks) ...[
        CreateBubbleProblems(check: check, onRemove: _removeNotHeld, onNormal: _useNormal, onEditor: _openEditor),
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
          for (final ty in bubble ? kBubbleQuestionTypes : quickQuestionTypes)
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
        onKind: (v) => setState(() => _plan.setPublish(v)),
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
