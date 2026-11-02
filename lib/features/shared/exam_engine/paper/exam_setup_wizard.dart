// "Paper exam setup" — the teacher's guided wizard for an engine exam of a course (D-150, D-151, D-155, D-156):
//
//   1 Students   how do we identify each student? → the audience check ("34 ready, 6 missing", who shares a value),
//                ask the missing ones (due on exam day for paper) and remind them; the list follows the core's
//                `exam_identifiers` event live (EventOrPoll, a slow poll only as the fallback)
//   2 Type       Online (stored; "Online exams are coming next" — the wizard stops there) or Paper
//   3 Paper      Exam paper only · Bubble sheet only · Both together (paper only skips step 4)
//   4 Sheet      the published bubble-sheet types; "Upload a custom layout" when the caller gives onLearnTemplate
//   5 Models     forms A / B / C … with their own answer keys, how they are told apart (pick two), and what a blank /
//                a double mark means; an unclear mark always goes to review (not a choice)
//
// One primary action per step, a progress line on top, Back on every step (no dead ends). Every step saves its own
// keys through PUT …/setup (the server merges them). Kill switches: `exam.identifiers` drops step 1, `exam.omr` every
// bubble-sheet part. Pure part: exam_setup.dart. Entry points: the quick exam's Offline path and the exam editor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../../admin/admin_common.dart' show asInt, asMapList, t;
import '../exam_authoring.dart' show parseEngineUtc;
import '../exam_authoring_screen.dart' show pickEngineDateTime;
import 'exam_setup.dart';

/// Opens the wizard; true when it was finished (or the choice of Online was saved).
Future<bool?> openExamSetupWizard(BuildContext context,
        {required int examId, String? initialDelivery, SetupStep? initialStep, Future<void> Function()? onLearnTemplate}) =>
    Navigator.of(context).push<bool>(MaterialPageRoute(
      settings: const RouteSettings(name: '/exam-setup'),
      builder: (_) => ExamSetupWizard(examId: examId, initialDelivery: initialDelivery, initialStep: initialStep, onLearnTemplate: onLearnTemplate),
    ));

/// The teacher's `exam_identifiers` notice (a duplicate value, …): the wizard on its identifier step.
Future<void> openExamIdentifiersFromLink(NavigatorState nav, int? examId) async {
  if (examId == null) {
    await nav.pushNamed('/notifications');
    return;
  }
  await nav.push(MaterialPageRoute(
      settings: const RouteSettings(name: '/exam-setup'), builder: (_) => ExamSetupWizard(examId: examId, initialStep: SetupStep.identify)));
}

class ExamSetupWizard extends StatefulWidget {
  const ExamSetupWizard({
    super.key,
    required this.examId,
    this.initialDelivery,
    this.initialStep,
    this.onLearnTemplate,
    this.api,
    this.liveStream,
    this.liveBus,
  });

  final int examId;

  /// `paper` when opened from the quick exam's Offline path (an exam reads `online` until it is set).
  final String? initialDelivery;
  final SetupStep? initialStep;

  /// The template-learning screen (a later wave). The "Upload a custom layout" entry shows only when given.
  /// Opens the template-learning flow; the sheet list reloads when it returns (a type may have been published).
  final Future<void> Function()? onLearnTemplate;
  final ExamSetupApi? api;
  final LiveStreamHandle? liveStream;
  final LiveEvents? liveBus;

  @override
  State<ExamSetupWizard> createState() => _ExamSetupWizardState();
}

class _ExamSetupWizardState extends State<ExamSetupWizard> {
  late final ExamSetupApi _api = widget.api ?? ExamSetupApi();

  bool _loading = true;
  String? _loadError;
  bool _unavailable = false;

  late ExamSetup _setup;
  int? _courseId;
  DateTime? _startsAt;
  List<ObjectiveQuestion> _questions = const [];
  List<IdentifierOption> _options = const [];

  SetupStep _step = SetupStep.delivery;
  bool _busy = false;
  String? _error;

  // 1 · students
  IdentifierChoice? _identifier;
  IdentifierReport? _report;
  bool _reportLoading = false;
  String? _reportError;
  bool _requesting = false;
  bool _reminding = false;
  DateTime? _dueUtc;
  String? _requestNote;
  EventOrPoll? _watch;

  // 2 · type, 3 · paper, 4 · sheet
  String? _delivery;
  bool _onlineSaved = false;
  String? _format;
  List<OmrTemplateItem>? _templates;
  String? _templatesError;
  int? _templateId;

  // 5 · models
  List<ExamFormDraft>? _forms;
  List<ExamFormDraft> _formsLoaded = const [];
  String? _formsError;
  List<String> _markers = const [];
  OmrPolicy _policy = const OmrPolicy();

  bool get _identifiersOn => !AppConfig.disableList.contains(kExamIdentifiersFeatureKey);
  bool get _omrOn => !AppConfig.disableList.contains(kExamOmrFeatureKey);
  bool get _bubble => _omrOn && (_format == 'bubble' || _format == 'both');

  List<SetupStep> get _steps => setupSteps(identifiersOn: _identifiersOn, omrOn: _omrOn, delivery: _delivery, format: _format);

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final res = await Future.wait([_api.setup(widget.examId), _api.exam(widget.examId), if (_identifiersOn) _api.identityFields()]);
    if (!mounted) return;
    final s = res[0], e = res[1];
    if (!s.ok) {
      setState(() {
        _loading = false;
        _unavailable = s.unavailable;
        _loadError = setupErrorText(s);
      });
      return;
    }
    _setup = ExamSetup.fromJson(s.map);
    if (e.ok) {
      _courseId = e.map['course_id'] == null ? null : asInt(e.map['course_id']);
      _startsAt = parseEngineUtc(e.map['starts_at']);
      _questions = [
        for (final sec in asMapList(e.map['sections']))
          for (final q in asMapList(sec['questions'])) ?ObjectiveQuestion.fromPlaced(q),
      ];
    }
    var fields = const <IdentityFieldDef>[];
    if (res.length > 2 && res[2].ok) fields = [for (final f in asMapList(res[2].map['items'])) IdentityFieldDef.fromJson(f)];
    final cols = _identifiersOn && _courseId != null ? await _api.dataLabColumns(_courseId!) : const <(String, String)>[];
    if (!mounted) return;
    _options = identifierOptions(fields, dataLabColumns: cols, dataLab: _courseId != null);
    _identifier = _setup.identifier;
    _delivery = _setup.delivery == 'paper' ? 'paper' : widget.initialDelivery;
    _format = _setup.paperFormat;
    _templateId = _setup.templateId;
    _markers = List.of(_setup.markers);
    _policy = _setup.policy;
    final steps = _steps;
    _step = widget.initialStep != null && steps.contains(widget.initialStep) ? widget.initialStep! : steps.first;
    setState(() => _loading = false);
    _enter(_step);
  }

  // ── step changes ──

  void _enter(SetupStep s) {
    if (s == SetupStep.identify) {
      if (_identifier != null && _report == null) _loadReport();
      _watch?.start();
    } else {
      _watch?.stop();
    }
    if (s == SetupStep.template && _templates == null) _loadTemplates();
    if (s == SetupStep.forms && _forms == null) _loadForms();
  }

  void _go(SetupStep s) {
    setState(() {
      _step = s;
      _error = null;
    });
    _enter(s);
  }

  void _back() {
    if (_onlineSaved && _step == SetupStep.delivery) {
      setState(() => _onlineSaved = false);
      return;
    }
    final steps = _steps;
    final i = steps.indexOf(_step);
    if (i <= 0) {
      Navigator.of(context).maybePop();
      return;
    }
    _go(steps[i - 1]);
  }

  void _next() {
    final steps = _steps;
    final i = steps.indexOf(_step);
    if (i >= 0 && i < steps.length - 1) _go(steps[i + 1]);
  }

  Future<bool> _put(Map<String, dynamic> body) async {
    if (body.isEmpty) return true;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.putSetup(widget.examId, body);
    if (!mounted) return false;
    setState(() {
      _busy = false;
      if (r.ok) {
        _setup = ExamSetup.fromJson(r.map);
      } else {
        _error = setupErrorText(r);
      }
    });
    return r.ok;
  }

  // ── 1 · students ──

  Future<void> _pickIdentifier(IdentifierOption o) async {
    if (_busy) return;
    final prev = _identifier;
    setState(() {
      _identifier = o.choice;
      _report = null;
      _reportError = null;
      _requestNote = null;
    });
    if (!await _put(identifierBody(_setup, o.choice))) {
      if (mounted) setState(() => _identifier = prev);
      return;
    }
    await _loadReport();
  }

  Future<void> _loadReport({bool silent = false}) async {
    if (!silent) setState(() => _reportLoading = true);
    final r = await _api.identifiers(widget.examId);
    if (!mounted) return;
    setState(() {
      _reportLoading = false;
      if (r.ok) {
        _report = IdentifierReport.fromJson(r.map);
        _reportError = null;
      } else if (!silent) {
        _reportError = setupErrorText(r);
      }
    });
    final rep = _report;
    if (rep != null && rep.collectable && _watch == null) {
      _watch = EventOrPoll(
        poll: () => _loadReport(silent: true),
        every: const Duration(seconds: 20),
        fallbackEvery: const Duration(seconds: 90),
        names: const {kExamIdentifiersEvent},
        match: (e) => '${e.data['exam_ref'] ?? ''}' == examRefOf(widget.examId),
        bus: widget.liveBus,
        stream: widget.liveStream,
      );
      if (_step == SetupStep.identify) _watch!.start();
    }
  }

  Future<void> _request() async {
    setState(() {
      _requesting = true;
      _requestNote = null;
    });
    final r = await _api.requestIdentifiers(widget.examId, dueUtc: _dueUtc);
    if (!mounted) return;
    setState(() {
      _requesting = false;
      if (r.ok) {
        final n = asInt(r.map['created']) + asInt(r.map['reopened']);
        _requestNote = n > 0
            ? t('أُرسل الطلب إلى $n طالب', 'Request sent to $n ${n == 1 ? 'student' : 'students'}')
            : t('الطلب مُرسل بالفعل — يمكنك إرسال تذكير', 'Already asked — you can send a reminder');
      } else {
        _requestNote = null;
        _error = setupErrorText(r);
      }
    });
    if (r.ok) await _loadReport(silent: true);
  }

  Future<void> _remind() async {
    setState(() => _reminding = true);
    final r = await _api.remind(widget.examId);
    if (!mounted) return;
    setState(() {
      _reminding = false;
      if (r.ok) {
        final n = asInt(r.map['reminded']);
        _requestNote = t('أُرسل التذكير إلى $n طالب', 'Reminder sent to $n ${n == 1 ? 'student' : 'students'}');
      } else {
        _error = setupErrorText(r);
      }
    });
  }

  Future<void> _changeDue() async {
    final d = await pickEngineDateTime(context, _dueUtc ?? _startsAt);
    if (d != null && mounted) setState(() => _dueUtc = d);
  }

  // ── 2 · type ──

  Future<void> _continueDelivery() async {
    if (_delivery == 'online') {
      if (await _put(onlineBody(_setup)) && mounted) setState(() => _onlineSaved = true);
      return;
    }
    _next();
  }

  // ── 3 · paper, 4 · sheet ──

  Future<void> _continueFormat() async {
    final f = _format;
    if (f == null) return;
    if (f == 'paper' || !_omrOn) {
      if (await _put(formatBody(_setup, 'paper'))) _next();
      return;
    }
    _next();
  }

  Future<void> _loadTemplates() async {
    setState(() => _templatesError = null);
    final r = await _api.templates();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _templates = choosableTemplates([for (final m in asMapList(r.map['items'])) OmrTemplateItem.fromJson(m)]);
        if (_templateId != null && !_templates!.any((x) => x.id == _templateId)) _templateId = null;
      } else {
        _templatesError = setupErrorText(r);
      }
    });
  }

  Future<void> _continueTemplate() async {
    OmrTemplateItem? tpl;
    for (final x in _templates ?? const <OmrTemplateItem>[]) {
      if (x.id == _templateId) tpl = x;
    }
    if (tpl == null) return;
    if (await _put(formatBody(_setup, _format!, template: tpl))) _next();
  }

  // ── 5 · models ──

  Future<void> _loadForms() async {
    setState(() => _formsError = null);
    final r = await _api.forms(widget.examId);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _formsLoaded = [for (final m in asMapList(r.map['items'])) ExamFormDraft.fromJson(m)];
        _forms = _formsLoaded.isEmpty ? [newForm('A', _questions)] : [for (final f in _formsLoaded) f.copy()];
        _markers = [for (final m in (r.map['form_markers'] as List?) ?? const []) '$m'];
      } else {
        _formsError = setupErrorText(r);
      }
    });
  }

  void _addForm() {
    final forms = _forms!;
    final code = nextFormCode(forms);
    if (code == null) return;
    setState(() {
      forms.add(newForm(code, _questions));
      if (forms.length == 2 && _markers.isEmpty) _markers = _bubble ? ['qr', 'bubble'] : ['qr', 'printed']; // recommended: two
    });
  }

  void _removeForm(String code) => setState(() {
        _forms!.removeWhere((f) => f.code == code);
        if (_forms!.length <= 1) _markers = const [];
      });

  void _toggleMarker(String m) => setState(() {
        final cur = List.of(_markers);
        if (cur.contains(m)) {
          cur.remove(m);
        } else if (cur.length < 2) {
          cur.add(m);
        }
        _markers = cur;
      });

  /// The forms to send: nothing when the list is the untouched default single model A.
  List<ExamFormDraft>? get _formsToSend {
    final forms = _forms;
    if (forms == null) return null;
    if (_formsLoaded.isEmpty && forms.length == 1 && sameForms(forms, [newForm('A', _questions)])) return null;
    if (sameForms(forms, _formsLoaded)) return null;
    return forms;
  }

  Future<void> _finish() async {
    final send = _formsToSend;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (send != null) {
      final r = await _api.putForms(widget.examId, send);
      if (!mounted) return;
      if (!r.ok) {
        setState(() {
          _busy = false;
          _error = setupErrorText(r);
        });
        return;
      }
      _formsLoaded = [for (final m in asMapList(r.map['items'])) ExamFormDraft.fromJson(m)];
    }
    setState(() => _busy = false);
    final many = (_forms?.length ?? 0) > 1;
    final body = finishBody(_setup, policy: _bubble ? _policy : null, markers: many ? _markers : null);
    if (!await _put(body) || !mounted) return;
    showAppNotice(t('اكتمل إعداد الاختبار الورقي', 'Paper exam setup saved'));
    Navigator.of(context).pop(true);
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      appBar: AppBar(title: Text(t('إعداد الاختبار الورقي', 'Paper exam setup'))),
      child: _loading
          ? const AppListSkeleton(items: 4, withAvatar: false)
          : _loadError != null
              ? AppEmpty(
                  icon: _unavailable ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
                  title: _unavailable ? t('إعداد الاختبار الورقي غير متاح على هذا الخادم بعد', 'Paper exam setup is not available on this server yet') : _loadError!,
                  actionLabel: _unavailable ? null : t('إعادة المحاولة', 'Try again'),
                  onAction: _unavailable ? null : _load,
                )
              : _frame(c),
    );
  }

  Widget _frame(ThemeConfigProvider c) {
    final steps = _steps;
    final i = steps.indexOf(_step);
    final (title, subtitle) = _titles();
    return SetupFrame(
      index: i < 0 ? 0 : i,
      total: steps.length,
      stepLabel: setupStepLabel(_step),
      title: title,
      subtitle: subtitle,
      error: _error,
      body: _body(),
      primaryLabel: _primaryLabel(),
      onPrimary: _busy ? null : _primaryAction(),
      busy: _busy,
      backLabel: i <= 0 && !_onlineSaved ? t('إغلاق', 'Close') : t('رجوع', 'Back'),
      onBack: _busy ? null : _back,
    );
  }

  (String, String?) _titles() => switch (_step) {
        SetupStep.identify => (t('كيف نتعرف على كل طالب في هذا الاختبار؟', 'How do we identify each student in this exam?'),
            t('نطابق كل ورقة بصاحبها من خلال هذه القيمة', 'Each sheet is matched to its student by this value')),
        SetupStep.delivery => _onlineSaved
            ? (t('الاختبار الإلكتروني', 'Online exam'), null)
            : (t('كيف سيُقدَّم الاختبار؟', 'How will students take this exam?'), null),
        SetupStep.format => (t('ماذا سيُطبع؟', 'What will you print?'), t('يمكنك تغيير هذا لاحقًا', 'You can change this later')),
        SetupStep.template => (t('اختر نوع ورقة التظليل', 'Choose the bubble-sheet type'), t('الأنواع المعتمدة على المنصة', 'The types approved on the platform')),
        SetupStep.forms => (t('نماذج الاختبار', 'Exam models'), t('لكل نموذج مفتاح إجابته', 'Each model has its own answer key')),
      };

  String _primaryLabel() {
    if (_step == SetupStep.delivery && _onlineSaved) return t('تم', 'Done');
    return _step == _steps.last ? t('إنهاء الإعداد', 'Finish setup') : t('متابعة', 'Continue');
  }

  VoidCallback? _primaryAction() => switch (_step) {
        SetupStep.identify => _courseId == null || (_identifier != null && _setup.identifier == _identifier) ? _next : null,
        SetupStep.delivery => _onlineSaved ? () => Navigator.of(context).pop(true) : (_delivery == null ? null : _continueDelivery),
        SetupStep.format => _format == null ? null : _continueFormat,
        SetupStep.template => _templateId == null ? null : _continueTemplate,
        SetupStep.forms => _forms == null ? null : _finish,
      };

  Widget _body() => switch (_step) {
        SetupStep.identify => IdentifierStepBody(
            noCourse: _courseId == null,
            options: _options,
            selected: _identifier,
            onPick: _pickIdentifier,
            busy: _busy,
            report: _report,
            reportLoading: _reportLoading,
            reportError: _reportError,
            onRetry: () => _loadReport(),
            requesting: _requesting,
            reminding: _reminding,
            note: _requestNote,
            dueLabel: _dueLabel(),
            onChangeDue: _setup.delivery == 'paper' || _delivery == 'paper' ? _changeDue : null,
            onRequest: _request,
            onRemind: _remind,
            live: _watch?.connected == true,
          ),
        SetupStep.delivery => _onlineSaved
            ? OnlineComingNext(onPaper: () => setState(() {
                  _onlineSaved = false;
                  _delivery = 'paper';
                }))
            : DeliveryStepBody(value: _delivery, onPick: (v) => setState(() => _delivery = v)),
        SetupStep.format => PaperFormatStepBody(value: _format, omrOn: _omrOn, onPick: (v) => setState(() => _format = v)),
        SetupStep.template => TemplateStepBody(
            templates: _templates,
            error: _templatesError,
            selectedId: _templateId,
            onPick: (x) => setState(() => _templateId = x.id),
            onRetry: _loadTemplates,
            onLearn: widget.onLearnTemplate == null
                ? null
                : () async {
                    await widget.onLearnTemplate!();
                    if (mounted) _loadTemplates();
                  },
            onPaperOnly: () => setState(() {
              _format = 'paper';
              _step = SetupStep.format;
            }),
          ),
        SetupStep.forms => FormsStepBody(
            forms: _forms,
            error: _formsError,
            onRetry: _loadForms,
            questions: _questions,
            markers: _markers,
            policy: _policy,
            bubble: _bubble,
            onAdd: _forms != null && nextFormCode(_forms!) != null ? _addForm : null,
            onRemove: _removeForm,
            onChoose: (f, q, v) => setState(() => q.choose(f, v)),
            onToggleMarker: _toggleMarker,
            onPolicy: (p) => setState(() => _policy = p),
          ),
      };

  String? _dueLabel() {
    final paper = _setup.delivery == 'paper' || _delivery == 'paper';
    final d = _dueUtc ?? (paper ? _startsAt : null);
    if (d == null) return paper ? t('بدون موعد — الاختبار بلا تاريخ بدء', 'No due date — the exam has no start time') : null;
    return _dueUtc == null ? t('موعد الإدخال: يوم الاختبار، ${AppTime.date(d)}', 'Due: exam day, ${AppTime.date(d)}') : t('موعد الإدخال: ${AppTime.date(d)}', 'Due: ${AppTime.date(d)}');
  }
}

// ═══════════════════════════════════════ frame ═════════════════════════════════════════════════════════════════

/// The wizard's page: the progress line, the step's question, its body, and ONE primary action next to Back.
class SetupFrame extends StatelessWidget {
  const SetupFrame({
    super.key,
    required this.index,
    required this.total,
    required this.stepLabel,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    required this.backLabel,
    required this.onBack,
    this.subtitle,
    this.error,
    this.busy = false,
  });

  final int index;
  final int total;
  final String stepLabel;
  final String title;
  final String? subtitle;
  final String? error;
  final Widget body;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool busy;
  final String backLabel;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SetupProgress(index: index, total: total, label: stepLabel),
                const SizedBox(height: AppSpace.lg),
                Text(title, style: appText(21, w: FontWeight.w800, c: c.textDark, h: 1.3)),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(subtitle!, style: appText(13.5, c: c.textMedium, h: 1.45)),
                ],
                const SizedBox(height: AppSpace.lg),
                if (error != null) ...[
                  AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
                  const SizedBox(height: AppSpace.md),
                ],
                body,
              ]),
            ),
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Row(children: [
                  TextButton(
                    key: const ValueKey('setup.back'),
                    onPressed: onBack,
                    style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                    child: Text(backLabel),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: KeyedSubtree(
                      key: const ValueKey('setup.primary'),
                      child: AppPrimaryButton(label: primaryLabel, busy: busy, onPressed: onPrimary),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// "Step 2 of 5 · Type" over a segmented line.
class SetupProgress extends StatelessWidget {
  const SetupProgress({super.key, required this.index, required this.total, required this.label});
  final int index;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = total < 1 ? 1 : total;
    return Semantics(
      label: t('الخطوة ${index + 1} من $n', 'Step ${index + 1} of $n'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExcludeSemantics(
          child: Text(t('الخطوة ${index + 1} من $n · $label', 'Step ${index + 1} of $n · $label'),
              style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
        ),
        const SizedBox(height: AppSpace.xs),
        Row(children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.xxs),
            Expanded(
              child: AnimatedContainer(
                duration: AppMotion.of(context).base,
                height: 5,
                decoration: BoxDecoration(
                  color: i <= index ? c.primary : c.divider,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

/// A selectable card: icon, title, one line, a check when chosen.
class SetupChoiceTile extends StatelessWidget {
  const SetupChoiceTile({super.key, required this.icon, required this.title, this.subtitle, required this.selected, required this.onTap, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(AppRadius.card);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.primary.withValues(alpha: 0.07) : c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: (selected ? c.primary : c.textMedium).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.chip)),
                  child: Icon(icon, color: selected ? c.primary : c.textMedium, size: 22),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: appText(15, w: FontWeight.w800, c: c.textDark)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: appText(12.5, c: c.textMedium, h: 1.4)),
                    ],
                  ]),
                ),
                ?trailing,
                const SizedBox(width: AppSpace.xs),
                Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? c.primary : c.textLight, size: 22),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════ 1 · students ═════════════════════════════════════════════════════════

IconData _kindIcon(String kind, String source) => switch (source) {
      'name' => Icons.person_outline_rounded,
      'email' => Icons.alternate_email_rounded,
      'phone' => Icons.phone_iphone_rounded,
      'datalab' => Icons.table_chart_outlined,
      _ => kind == 'digits' ? Icons.pin_outlined : Icons.badge_outlined,
    };

class IdentifierStepBody extends StatelessWidget {
  const IdentifierStepBody({
    super.key,
    required this.options,
    required this.selected,
    required this.onPick,
    this.busy = false,
    this.report,
    this.reportLoading = false,
    this.reportError,
    this.onRetry,
    this.requesting = false,
    this.reminding = false,
    this.note,
    this.dueLabel,
    this.onChangeDue,
    this.onRequest,
    this.onRemind,
    this.live = false,
    this.noCourse = false,
  });

  /// The exam is not linked to a course: nobody to identify yet (Continue skips the step).
  final bool noCourse;
  final List<IdentifierOption> options;
  final IdentifierChoice? selected;
  final ValueChanged<IdentifierOption> onPick;
  final bool busy;
  final IdentifierReport? report;
  final bool reportLoading;
  final String? reportError;
  final VoidCallback? onRetry;
  final bool requesting;
  final bool reminding;
  final String? note;
  final String? dueLabel;
  final VoidCallback? onChangeDue;
  final VoidCallback? onRequest;
  final VoidCallback? onRemind;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget group(String title, String g) {
      final items = [for (final o in options) if (o.group == g) o];
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final o in items)
              AppChoiceChip(
                key: ValueKey('setup.id.${o.choice.id}'),
                label: o.label,
                icon: _kindIcon(o.kind, o.choice.source),
                selected: selected == o.choice,
                onTap: () {
                  if (!busy) onPick(o);
                },
              ),
          ]),
        ]),
      );
    }

    final rep = report;
    if (noCourse) return AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: setupCodeText('identifiers_need_course'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      group(t('من حساب الطالب', 'From the student\'s account'), 'account'),
      group(t('حقول المنصة', 'Platform fields'), 'field'),
      group(t('من جدول بيانات المقرر', 'From the course\'s Data Lab sheet'), 'datalab'),
      if (selected != null) ...[
        const SizedBox(height: AppSpace.xs),
        if (reportLoading && rep == null)
          const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero)
        else if (reportError != null)
          AppBanner(
            icon: Icons.info_outline_rounded,
            color: c.warning,
            text: reportError!,
            action: onRetry == null ? null : TextButton(onPressed: onRetry, child: Text(t('إعادة', 'Retry'))),
          )
        else if (rep != null) ...[
          AudienceCheckCard(
            report: rep,
            requesting: requesting,
            reminding: reminding,
            note: note,
            dueLabel: dueLabel,
            onChangeDue: onChangeDue,
            onRequest: onRequest,
            onRemind: onRemind,
            live: live,
          ),
          if (rep.duplicates.isNotEmpty) ...[const SizedBox(height: AppSpace.md), DuplicatesCard(report: rep)],
        ],
      ],
    ]);
  }
}

/// "34 ready, 6 missing" with the names of the missing, the request to send and the reminder.
class AudienceCheckCard extends StatefulWidget {
  const AudienceCheckCard({
    super.key,
    required this.report,
    this.requesting = false,
    this.reminding = false,
    this.note,
    this.dueLabel,
    this.onChangeDue,
    this.onRequest,
    this.onRemind,
    this.live = false,
  });

  final IdentifierReport report;
  final bool requesting;
  final bool reminding;
  final String? note;
  final String? dueLabel;
  final VoidCallback? onChangeDue;
  final VoidCallback? onRequest;
  final VoidCallback? onRemind;
  final bool live;

  @override
  State<AudienceCheckCard> createState() => _AudienceCheckCardState();
}

class _AudienceCheckCardState extends State<AudienceCheckCard> {
  bool _all = false;
  static const _preview = 8;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.report;
    final missing = r.missingCount;
    final pending = r.pending ?? 0;
    final names = _all ? r.missing : r.missing.take(_preview).toList();
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(r.label, style: appText(14, w: FontWeight.w800, c: c.textDark), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (r.collectable && widget.live) AppBadgePill(t('مباشر', 'Live'), color: c.success, icon: Icons.circle),
        ]),
        const SizedBox(height: AppSpace.sm),
        if (r.total == 0)
          Text(t('لا يوجد طلاب في هذا المقرر بعد', 'No students in this course yet'), style: appText(13, c: c.textMedium))
        else ...[
          Text(r.summary, key: const ValueKey('setup.audience.summary'), style: appText(20, w: FontWeight.w800, c: missing == 0 ? c.success : c.textDark)),
          const SizedBox(height: AppSpace.xs),
          AppProgressBar(value: r.ready.toDouble(), max: r.total.toDouble(), color: missing == 0 ? c.success : c.primary),
        ],
        if (missing == 0 && r.total > 0) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.task_alt_rounded, color: c.success, text: t('الجميع جاهز — يمكنك المتابعة', 'Everyone is ready — you can continue')),
        ],
        if (missing > 0) ...[
          const SizedBox(height: AppSpace.md),
          Text(t('ينقصهم ${r.label}', 'Missing their ${r.label}'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final s in names) AppBadgePill(s.name, color: c.warning),
            if (r.missing.length > _preview)
              InkWell(
                onTap: () => setState(() => _all = !_all),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(_all ? t('عرض أقل', 'Show less') : t('+${r.missing.length - _preview} آخرين', '+${r.missing.length - _preview} more'),
                      style: appText(12, w: FontWeight.w700, c: c.primary)),
                ),
              ),
          ]),
          const SizedBox(height: AppSpace.md),
          if (!r.collectable)
            AppBanner(
                icon: Icons.table_chart_outlined,
                text: t('لا تُطلب هذه القيمة من الطلاب — أكملها في جدول بيانات المقرر', 'Students cannot be asked for this — fill it in the course\'s Data Lab sheet'))
          else ...[
            if (widget.dueLabel != null)
              Row(children: [
                Icon(Icons.event_rounded, size: 18, color: c.textMedium),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(widget.dueLabel!, style: appText(12.5, c: c.textMedium))),
                if (widget.onChangeDue != null) TextButton(onPressed: widget.onChangeDue, child: Text(t('تغيير', 'Change'))),
              ]),
            const SizedBox(height: AppSpace.xs),
            OutlinedButton.icon(
              key: const ValueKey('setup.request'),
              onPressed: widget.requesting || widget.onRequest == null ? null : widget.onRequest,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
              icon: widget.requesting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(pending > 0
                  ? t('اطلبها من الطلاب الناقصين مرة أخرى', 'Ask the missing students again')
                  : t('اطلبها من $missing طالب', 'Ask the $missing ${missing == 1 ? 'student' : 'students'}')),
            ),
            if (pending > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Row(children: [
                  Expanded(
                    child: Text(t('$pending طلب بانتظار الرد', '$pending ${pending == 1 ? 'request' : 'requests'} waiting for an answer'),
                        style: appText(12.5, c: c.textMedium)),
                  ),
                  TextButton.icon(
                    key: const ValueKey('setup.remind'),
                    onPressed: widget.reminding || widget.onRemind == null ? null : widget.onRemind,
                    icon: const Icon(Icons.notifications_active_outlined, size: 18),
                    label: Text(t('تذكير', 'Remind')),
                  ),
                ]),
              ),
          ],
        ],
        if (widget.note != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(widget.note!, style: appText(12.5, w: FontWeight.w600, c: c.success)),
        ],
      ]),
    );
  }
}

/// Who shares a value with someone else (alert style): sheets cannot be matched while two students share it.
class DuplicatesCard extends StatelessWidget {
  const DuplicatesCard({super.key, required this.report});
  final IdentifierReport report;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = report.duplicateStudents;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.danger.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, color: c.danger, size: 22),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(t('$n طلاب يتشاركون نفس ${report.label}', '$n students share the same ${report.label}'),
                style: appText(14, w: FontWeight.w800, c: c.textDark)),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        for (final g in report.duplicates)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text('• ${g.map((s) => s.name).join(t('، ', ', '))}', style: appText(13, w: FontWeight.w600, c: c.textDark)),
          ),
        const SizedBox(height: AppSpace.xs),
        Text(t('لا يمكن مطابقة الورقة بطالب ما دام اثنان يتشاركان القيمة — اطلب منهم مراجعتها', 'A sheet cannot be matched while two students share a value — ask them to check it'),
            style: appText(12.5, c: c.textMedium, h: 1.45)),
      ]),
    );
  }
}

// ═══════════════════════════════════════ 2 · type ═════════════════════════════════════════════════════════════

class DeliveryStepBody extends StatelessWidget {
  const DeliveryStepBody({super.key, required this.value, required this.onPick});
  final String? value;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SetupChoiceTile(
          key: const ValueKey('setup.delivery.online'),
          icon: Icons.devices_rounded,
          title: t('إلكتروني', 'Online'),
          subtitle: t('يجيب الطلاب على التطبيق', 'Students answer in the app'),
          selected: value == 'online',
          onTap: () => onPick('online'),
        ),
        const SizedBox(height: AppSpace.sm),
        SetupChoiceTile(
          key: const ValueKey('setup.delivery.paper'),
          icon: Icons.description_outlined,
          title: t('ورقي', 'Paper'),
          subtitle: t('في القاعة على الورق، ثم تصحح الأوراق الممسوحة', 'On paper in the room; the scanned sheets are marked after'),
          selected: value == 'paper',
          onTap: () => onPick('paper'),
        ),
      ]);
}

/// Example 2: online is stored, and the wizard stops here.
class OnlineComingNext extends StatelessWidget {
  const OnlineComingNext({super.key, required this.onPaper});
  final VoidCallback onPaper;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary.withValues(alpha: 0.10)),
          child: Icon(Icons.rocket_launch_outlined, size: 34, color: c.primary),
        ),
        const SizedBox(height: AppSpace.md),
        Text(t('الاختبارات الإلكترونية قادمة قريبًا', 'Online exams are coming next'),
            key: const ValueKey('setup.online.next'), textAlign: TextAlign.center, style: appText(17, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        Text(t('حفظنا اختيارك «إلكتروني». إعداد الاختبار الإلكتروني يصل في تحديث قادم، ويمكنك التحويل إلى الورقي في أي وقت.',
                'We saved your choice: online. Setting up online exams arrives in a coming update; you can switch to paper any time.'),
            textAlign: TextAlign.center, style: appText(13, c: c.textMedium, h: 1.5)),
        const SizedBox(height: AppSpace.md),
        TextButton.icon(onPressed: onPaper, icon: const Icon(Icons.description_outlined, size: 18), label: Text(t('استخدم الورقي بدلًا منه', 'Use paper instead'))),
      ]),
    );
  }
}

// ═══════════════════════════════════════ 3 · paper ════════════════════════════════════════════════════════════

class PaperFormatStepBody extends StatelessWidget {
  const PaperFormatStepBody({super.key, required this.value, required this.omrOn, required this.onPick});
  final String? value;
  final bool omrOn;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SetupChoiceTile(
          key: const ValueKey('setup.format.paper'),
          icon: Icons.article_outlined,
          title: t('ورقة الأسئلة فقط', 'Exam paper only'),
          subtitle: t('الأسئلة مطبوعة ويجيب الطالب عليها', 'Questions printed; students answer on the paper'),
          selected: value == 'paper',
          onTap: () => onPick('paper'),
        ),
        if (omrOn)
          ParentComponent(
            featureKey: kExamOmrFeatureKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: AppSpace.sm),
              SetupChoiceTile(
                key: const ValueKey('setup.format.bubble'),
                icon: Icons.grid_on_rounded,
                title: t('ورقة التظليل فقط', 'Bubble sheet only'),
                subtitle: t('يظلل الطالب إجاباته وتُصحح تلقائيًا', 'Students shade their answers; marked automatically'),
                selected: value == 'bubble',
                onTap: () => onPick('bubble'),
              ),
              const SizedBox(height: AppSpace.sm),
              SetupChoiceTile(
                key: const ValueKey('setup.format.both'),
                icon: Icons.library_books_outlined,
                title: t('الاثنان معًا', 'Both together'),
                subtitle: t('ورقة الأسئلة مع ورقة تظليل منفصلة', 'The question paper with a separate bubble sheet'),
                selected: value == 'both',
                onTap: () => onPick('both'),
              ),
            ]),
          ),
      ]);
}

// ═══════════════════════════════════════ 4 · sheet ════════════════════════════════════════════════════════════

class TemplateStepBody extends StatelessWidget {
  const TemplateStepBody({
    super.key,
    required this.templates,
    required this.selectedId,
    required this.onPick,
    required this.onPaperOnly,
    this.error,
    this.onRetry,
    this.onLearn,
  });

  /// null = loading.
  final List<OmrTemplateItem>? templates;
  final String? error;
  final int? selectedId;
  final ValueChanged<OmrTemplateItem> onPick;
  final VoidCallback? onRetry;

  /// "Upload a custom layout" (shown only when given).
  final VoidCallback? onLearn;
  final VoidCallback onPaperOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = templates;
    final learn = onLearn == null
        ? null
        : TextButton.icon(
            key: const ValueKey('setup.template.learn'),
            onPressed: onLearn,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(t('رفع تصميم خاص', 'Upload a custom layout')));
    if (error != null) {
      return AppBanner(
          icon: Icons.error_outline_rounded,
          color: c.danger,
          text: error!,
          action: onRetry == null ? null : TextButton(onPressed: onRetry, child: Text(t('إعادة', 'Retry'))));
    }
    if (list == null) return const AppListSkeleton(items: 3, padding: EdgeInsets.zero);
    if (list.isEmpty) {
      return AppCard(
        child: Column(children: [
          AppEmpty(
            icon: Icons.grid_off_rounded,
            title: t('لا توجد أنواع أوراق تظليل بعد', 'No bubble-sheet types yet'),
            message: t('عندما يعتمد مشرف المنصة نوعًا سيظهر هنا. يمكنك الآن الاكتفاء بورقة الأسئلة.',
                'Once the platform admin approves one it shows here. For now you can use the exam paper only.'),
          ),
          ?learn,
          TextButton(onPressed: onPaperOnly, child: Text(t('استخدم ورقة الأسئلة فقط', 'Use the exam paper only'))),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final x in list) ...[
        SetupChoiceTile(
          key: ValueKey('setup.template.${x.id}'),
          icon: Icons.grid_on_rounded,
          title: x.name,
          subtitle: [x.shape, ?x.description].join(' · '),
          selected: selectedId == x.id,
          onTap: () => onPick(x),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
      if (learn != null) Align(alignment: AlignmentDirectional.centerStart, child: learn),
    ]);
  }
}

// ═══════════════════════════════════════ 5 · models ═══════════════════════════════════════════════════════════

String markerLabel(String m) => switch (m) {
      'qr' => t('رمز QR', 'QR code'),
      'printed' => t('رمز مطبوع', 'Printed code'),
      'bubble' => t('فقاعة مظللة', 'Marked bubble'),
      _ => m,
    };

IconData _markerIcon(String m) => switch (m) {
      'qr' => Icons.qr_code_2_rounded,
      'printed' => Icons.text_fields_rounded,
      _ => Icons.radio_button_checked_rounded,
    };

class FormsStepBody extends StatelessWidget {
  const FormsStepBody({
    super.key,
    required this.forms,
    required this.questions,
    required this.markers,
    required this.policy,
    required this.bubble,
    required this.onRemove,
    required this.onChoose,
    required this.onToggleMarker,
    required this.onPolicy,
    this.onAdd,
    this.error,
    this.onRetry,
  });

  /// null = loading.
  final List<ExamFormDraft>? forms;
  final List<ObjectiveQuestion> questions;
  final List<String> markers;
  final OmrPolicy policy;

  /// A bubble sheet is printed (the marked-bubble marker and the marking rules apply).
  final bool bubble;
  final VoidCallback? onAdd;
  final ValueChanged<String> onRemove;
  final void Function(ExamFormDraft form, ObjectiveQuestion q, Object value) onChoose;
  final ValueChanged<String> onToggleMarker;
  final ValueChanged<OmrPolicy> onPolicy;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (error != null) {
      return AppBanner(
          icon: Icons.error_outline_rounded,
          color: c.danger,
          text: error!,
          action: onRetry == null ? null : TextButton(onPressed: onRetry, child: Text(t('إعادة', 'Retry'))));
    }
    final list = forms;
    if (list == null) return const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero);
    final many = list.length > 1;
    final choices = ['qr', 'printed', if (bubble) 'bubble'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (questions.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppBanner(
              icon: Icons.info_outline_rounded,
              text: t('لا توجد أسئلة اختيار أو صح وخطأ بعد — أضفها من محرر الاختبار لتحديد مفاتيح الإجابة',
                  'No multiple-choice or true/false questions yet — add them in the exam editor to set answer keys')),
        ),
      for (final f in list) ...[
        FormKeyCard(
          key: ValueKey('setup.form.${f.code}'),
          form: f,
          questions: questions,
          onRemove: list.length > 1 ? () => onRemove(f.code) : null,
          onChoose: (q, v) => onChoose(f, q, v),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
      if (onAdd != null)
        OutlinedButton.icon(
          key: const ValueKey('setup.form.add'),
          onPressed: onAdd,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(t('إضافة نموذج ${nextFormCode(list) ?? ''}', 'Add model ${nextFormCode(list) ?? ''}')),
        ),
      if (many) ...[
        const SizedBox(height: AppSpace.lg),
        Text(t('كيف نميّز النماذج؟', 'How do we tell the models apart?'), style: appText(15, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(height: AppSpace.xxs),
        Text(t('ننصح باختيار طريقتين: إن اختلفتا تذهب الورقة للمراجعة ولا تُصحح', 'We recommend two: if they disagree, the sheet goes to review and is not marked'),
            style: appText(12.5, c: c.textMedium, h: 1.45)),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final m in choices)
            m == 'bubble'
                ? ParentComponent(featureKey: kExamOmrFeatureKey, child: _markerChip(m))
                : _markerChip(m),
        ]),
      ],
      if (bubble)
        ParentComponent(
          featureKey: kExamOmrFeatureKey,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.lg),
            child: OmrPolicyCard(policy: policy, onChanged: onPolicy),
          ),
        ),
    ]);
  }

  Widget _markerChip(String m) => AppChoiceChip(
        key: ValueKey('setup.marker.$m'),
        label: markerLabel(m),
        icon: _markerIcon(m),
        selected: markers.contains(m),
        onTap: () => onToggleMarker(m),
      );
}

/// One model: its code, how many answers are set, and (opened) a row of choices per question.
class FormKeyCard extends StatefulWidget {
  const FormKeyCard({super.key, required this.form, required this.questions, required this.onChoose, this.onRemove, this.initiallyExpanded = false});
  final ExamFormDraft form;
  final List<ObjectiveQuestion> questions;
  final void Function(ObjectiveQuestion q, Object value) onChoose;
  final VoidCallback? onRemove;
  final bool initiallyExpanded;

  @override
  State<FormKeyCard> createState() => _FormKeyCardState();
}

class _FormKeyCardState extends State<FormKeyCard> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = widget.form;
    final qs = widget.questions;
    final set = qs.where((q) => q.answeredIn(f)).length;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: qs.isEmpty ? null : () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: c.primaryGradient, borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: Text(f.code, style: appText(16, w: FontWeight.w800, c: c.onHero)),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('النموذج ${f.code}', 'Model ${f.code}'), style: appText(14.5, w: FontWeight.w800, c: c.textDark)),
                  if (qs.isNotEmpty)
                    Text(t('$set من ${qs.length} إجابة محددة', '$set of ${qs.length} answers set'),
                        style: appText(12, c: set == qs.length ? c.success : c.warning)),
                ]),
              ),
              if (widget.onRemove != null)
                IconButton(
                  onPressed: widget.onRemove,
                  tooltip: t('حذف النموذج', 'Remove model'),
                  icon: Icon(Icons.delete_outline_rounded, color: c.textMedium),
                ),
              if (qs.isNotEmpty) Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.textMedium),
            ]),
          ),
        ),
        if (_open && qs.isNotEmpty) ...[
          Divider(height: 1, color: c.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < qs.length; i++) _row(context, i, qs[i]),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _row(BuildContext context, int i, ObjectiveQuestion q) {
    final c = context.colors;
    final f = widget.form;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${i + 1}. ${q.prompt}', maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w600, c: c.textDark)),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
          for (final (v, label) in q.choices)
            Tooltip(
              message: q.type == 'true_false' ? label : q.options.firstWhere((o) => o.$1 == v, orElse: () => ('', label)).$2,
              child: AppChoiceChip(label: label, selected: q.isChosen(f, v), onTap: () => widget.onChoose(q, v)),
            ),
        ]),
      ]),
    );
  }
}

/// What a blank / a double mark means; an unclear mark is always reviewed (said, not asked).
class OmrPolicyCard extends StatelessWidget {
  const OmrPolicyCard({super.key, required this.policy, required this.onChanged});
  final OmrPolicy policy;
  final ValueChanged<OmrPolicy> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(String title, String keyName, List<(String, String)> opts, String value, ValueChanged<String> pick) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: appText(13, w: FontWeight.w700, c: c.textDark)),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final (v, label) in opts)
                AppChoiceChip(key: ValueKey('setup.policy.$keyName.$v'), label: label, selected: value == v, onTap: () => pick(v)),
            ]),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('قواعد التظليل', 'Marking rules'), style: appText(15, w: FontWeight.w800, c: c.textDark)),
      row(t('لا توجد إجابة', 'No answer'), 'blank', [('zero', t('صفر درجة', '0 points')), ('review', t('إرسال للمراجعة', 'Send to review'))], policy.blank,
          (v) => onChanged(policy.copyWith(blank: v))),
      row(t('أكثر من تظليل', 'Multiple marks'), 'multiple', [('wrong', t('خطأ', 'Wrong')), ('review', t('إرسال للمراجعة', 'Send to review'))],
          policy.multiple, (v) => onChanged(policy.copyWith(multiple: v))),
      const SizedBox(height: AppSpace.sm),
      AppBanner(icon: Icons.visibility_outlined, text: t('التظليل غير الواضح يذهب دائمًا للمراجعة — لا نخمّن أبدًا', 'Unclear marks always go to review — we never guess')),
    ]);
  }
}
