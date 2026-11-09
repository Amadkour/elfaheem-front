// The revision setup: what to compare with · the paper template · how to match · one sample read · how the paper is
// written, then the run. One screen per step, one primary action each; nothing is asked twice, and the first sample
// is read again with every change of style so the teacher sees what the choice did.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../../../../teacher/data_lab/data_lab_api.dart';
import '../../exam_authoring.dart' show ExamAuthoringApi;
import '../../marks/mark_sessions_api.dart' show MarkMode;
import '../../marks/mark_templates_api.dart';
import '../../marks/marks_links.dart' show openLegacyGradeReview;
import '../../marks/review/grade_review_screen.dart' show GradeReviewScreen;
import '../../marks/review/grade_review_start.dart' show GradeColumn;
import '../../marks/templates/mark_template_common.dart' show MarkImagePicker, canUseCamera, defaultMarkImagePicker;
import '../../marks/templates/mark_template_editor.dart';
import '../../marks/templates/mark_template_new.dart';
import '../../paper/scan/omr_camera.dart' show OmrCamera;
import 'revision_api.dart';
import 'revision_models.dart';
import 'revision_run_screen.dart';
import 'revision_wizard_steps.dart';

/// The degree columns and the columns that can identify a student, of one course's Data Lab.
typedef RevisionColumns = ({List<GradeColumn> degree, List<({String key, String label})> match});

Future<RevisionColumns> loadRevisionColumns(int courseId) async {
  final g = await DataLabApi().grid(courseId, limit: 1, lang: AppConfig.lang);
  return (
    degree: [for (final c in g.columns) if (c.isNumber && !c.isCalculated && !c.isLocked) GradeColumn(c.key, c.label, c.maxValue)],
    match: [for (final c in g.columns) if (!c.isCalculated && !c.isBuiltin) (key: c.key, label: c.label)],
  );
}

enum _Step { source, template, match, sample, style }

class RevisionWizardScreen extends StatefulWidget {
  const RevisionWizardScreen({super.key, this.examId, this.courseId, this.orgId, this.title, this.api, this.templatesApi, this.picker, this.camera, this.columnsLoader, this.onOlderServer});

  final int? examId, courseId, orgId;
  final String? title;
  final RevisionApi? api;
  final MarkTemplatesApi? templatesApi;
  final MarkImagePicker? picker;
  final OmrCamera Function()? camera;
  final Future<RevisionColumns> Function(int courseId)? columnsLoader;

  /// The server has no revision routes: the caller opens the short form instead.
  final VoidCallback? onOlderServer;

  @override
  State<RevisionWizardScreen> createState() => _RevisionWizardScreenState();
}

class _RevisionWizardScreenState extends State<RevisionWizardScreen> {
  late final RevisionApi _api = widget.api ?? RevisionApi();
  late final MarkTemplatesApi _templates = widget.templatesApi ?? MarkTemplatesApi();
  final _s = RevisionSetup();

  _Step _step = _Step.source;
  bool _booting = true;
  List<RevisionCourse> _courses = const [];
  bool _courseLocked = false;
  String? _courseName;
  List<GradeColumn> _degreeColumns = const [];
  List<({String key, String label})> _matchColumns = const [];
  bool _loadingColumns = false, _uploading = false;
  List<RevisionSession> _earlier = const [];
  int? _orgId;

  List<MarkTemplate> _tpls = const [];
  bool _loadingTpls = false;
  int? _loadingTplId;

  Uint8List? _photo;
  String _photoName = 'sheet.jpg';
  RevisionSample? _sample, _previous;
  bool _sampling = false, _force = false, _starting = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() => _booting = true);
    if (!await _api.supported()) {
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onOlderServer?.call();
      return;
    }
    var cid = widget.courseId;
    var oid = widget.orgId ?? AppModeController.instance.currentOrgId;
    if (widget.examId != null && cid == null) {
      final r = await ExamAuthoringApi().exam(widget.examId!);
      final exam = asMap(r.map['exam']).isNotEmpty ? asMap(r.map['exam']) : r.map;
      if (r.ok) {
        final c = asInt(exam['course_id']);
        if (c > 0) cid = c;
        if (exam['org_id'] != null) oid = asInt(exam['org_id']);
      } else if (mounted) {
        showAppNotice(r.message, error: true);
      }
    }
    final courses = cid != null ? const <RevisionCourse>[] : await _api.courses(orgId: oid);
    final earlier = await _api.openSessions(courseId: cid, orgId: oid);
    if (!mounted) return;
    setState(() {
      _booting = false;
      _orgId = oid;
      _courses = courses;
      _earlier = earlier.take(3).toList();
      _courseLocked = cid != null;
      _courseName = widget.title;
      if (cid != null) {
        _s.source = RevisionSource.gradebook;
        _s.courseId = cid;
      } else if (courses.isEmpty) {
        _s.source = RevisionSource.excel;
      }
    });
    if (cid != null) unawaited(_loadColumns(cid));
  }

  Future<void> _loadColumns(int courseId) async {
    setState(() => _loadingColumns = true);
    RevisionColumns? got;
    try {
      got = await (widget.columnsLoader ?? loadRevisionColumns)(courseId);
    } catch (_) {
      showAppNotice(t('تعذّر فتح دفتر درجات المقرر', 'The course gradebook could not be opened'), error: true);
    }
    if (!mounted) return;
    setState(() {
      _loadingColumns = false;
      _degreeColumns = got?.degree ?? const [];
      _matchColumns = got?.match ?? const [];
      if (_degreeColumns.length == 1) _s.column = _degreeColumns.first;
    });
  }

  Future<void> _upload() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx']);
    if (f == null || !mounted) return;
    setState(() => _uploading = true);
    final r = await _api.sheetPreview(f.name, await f.readAsBytes());
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (r.ok) _s.adoptSheet(RevisionSheetPreview.fromJson(r.map, fileName: f.name));
    });
    if (!r.ok) showAppNotice(revisionErrorText(r), error: true);
  }

  Future<void> _loadTemplates({int? selectNewerThan}) async {
    setState(() => _loadingTpls = _tpls.isEmpty);
    final org = _s.courseId == null ? _orgId : (_courses.where((c) => c.id == _s.courseId).firstOrNull?.orgId ?? _orgId);
    final r = await _templates.list(orgId: org);
    if (!mounted) return;
    final items = r.ok ? [for (final m in asMapList(r.map['items'])) MarkTemplate.fromJson(m)].where((x) => !x.retired && (x.kind == MarkKind.markSheet || x.kind == MarkKind.cover)).toList() : <MarkTemplate>[];
    setState(() {
      _loadingTpls = false;
      _tpls = items;
    });
    if (!r.ok) showAppNotice(markErrorText(r), error: true);
    if (selectNewerThan != null) {
      final fresh = items.where((x) => x.id > selectNewerThan).toList()..sort((a, b) => b.id.compareTo(a.id));
      if (fresh.isNotEmpty) await _pickTemplate(fresh.first);
    } else if (_s.template == null && items.length == 1) {
      await _pickTemplate(items.first);
    }
  }

  Future<void> _pickTemplate(MarkTemplate x) async {
    setState(() => _loadingTplId = x.id);
    final r = await _templates.detail(x.id);
    if (!mounted) return;
    setState(() => _loadingTplId = null);
    if (!r.ok) {
      showAppNotice(markErrorText(r), error: true);
      return;
    }
    final spec = MarkSheetSpec.fromJson(asMap(r.map['spec']), kind: x.kind ?? MarkKind.parse(r.map['kind']));
    final id = spec.fields.where((f) => f.type == FieldType.identifier).firstOrNull;
    setState(() {
      _s.template = RevisionTemplateChoice(id: x.id, name: x.name, totalMax: x.totalMax ?? 0, identifierSource: id?.source ?? '', aspect: spec.aspect, identifierBox: id?.box);
      _s.match = null;
      _clearSample();
    });
  }

  Future<void> _newTemplate() async {
    final before = _tpls.isEmpty ? 0 : _tpls.map((e) => e.id).reduce((a, b) => a > b ? a : b);
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => MarkTemplateNewPage(orgId: _orgId, api: _templates, picker: widget.picker)));
    if (mounted) await _loadTemplates(selectNewerThan: before);
  }

  Future<void> _editTemplate() async {
    final id = _s.template?.id;
    final x = _tpls.where((e) => e.id == id).firstOrNull;
    if (x == null) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => MarkTemplateEditorPage(api: _templates, picker: widget.picker, orgId: _orgId, template: x)));
    if (mounted) {
      // an edit saves a new version: the newest of this family becomes the choice
      final before = _tpls.isEmpty ? 0 : _tpls.map((e) => e.id).reduce((a, b) => a > b ? a : b);
      await _loadTemplates(selectNewerThan: before);
      if (mounted) setState(_clearSample);
    }
  }

  void _clearSample() {
    _sample = null;
    _previous = null;
    _photo = null;
    _force = false;
  }

  Future<void> _takeSample({required bool camera}) async {
    final img = await (widget.picker ?? defaultMarkImagePicker)(camera: camera);
    if (img == null || !mounted) return;
    setState(() {
      _photoName = img.$1;
      _photo = img.$2;
      _sample = null;
      _previous = null;
      _force = false;
    });
    await _runSample();
  }

  Future<void> _runSample({bool keepPrevious = false}) async {
    final photo = _photo, tpl = _s.template;
    if (photo == null || tpl == null) return;
    final gen = ++_gen;
    setState(() {
      if (keepPrevious && (_sample?.ok ?? false)) _previous = _sample;
      _sampling = true;
    });
    final excel = _s.source == RevisionSource.excel;
    final r = await _api.sample(
      (_photoName, photo),
      templateId: tpl.id,
      match: excel ? null : _s.match,
      styles: _s.styles,
      courseId: excel ? null : _s.courseId,
      sheetKey: excel ? _s.sheet?.sheetKey : null,
      sheetMatchColumn: excel ? _s.matchColumn : null,
    );
    if (!mounted || gen != _gen) return;
    setState(() {
      _sampling = false;
      if (r.ok) _sample = RevisionSample.fromJson(r.map, lang: AppConfig.lang, styles: _s.styles);
    });
    if (!r.ok) showAppNotice(revisionErrorText(r, fallback: t('تعذّرت قراءة الورقة', 'The paper could not be read')), error: true);
  }

  void _changeStyles(RevisionStyles v) {
    if (v == _s.styles) return;
    setState(() {
      _s.styles = v;
      _force = false;
    });
    unawaited(_runSample(keepPrevious: true));
  }

  void _restoreStyles() {
    final p = _previous;
    if (p == null) return;
    setState(() {
      _s.styles = p.styles;
      _sample = p;
      _previous = null;
      _gen++; // a read still out for the other setting is no longer wanted
      _sampling = false;
    });
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    final r = await _api.create(_s.createBody(examId: widget.examId));
    if (!mounted) return;
    setState(() => _starting = false);
    if (!r.ok) {
      showAppNotice(revisionErrorText(r, fallback: t('تعذّر بدء الجلسة', 'The session could not be started')), error: true);
      return;
    }
    final info = RevisionSession.fromJson(r.map);
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => RevisionRunScreen(info: info, api: _api, camera: widget.camera)));
  }

  void _continueEarlier(RevisionSession s) {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => GradeReviewScreen(sessionId: s.id, camera: widget.camera)));
  }

  void _importInstead() {
    final cid = _s.courseId;
    if (cid != null) unawaited(openLegacyGradeReview(context, cid, mode: MarkMode.import));
  }

  Future<void> _go(_Step to) async {
    setState(() => _step = to);
    if (to == _Step.template) await _loadTemplates();
  }

  Map<RevisionMatch?, String> get _matchOptions {
    final tpl = _s.template;
    if (tpl == null) return const {};
    String label(String s) => s == 'phone' ? t('رقم الهاتف', 'Phone number') : revisionTemplateMatchLabel(s);
    return {
      null: label(tpl.identifierSource),
      for (final s in const ['national_id', 'academic_id', 'phone'])
        if (s != tpl.identifierSource) RevisionMatch(s): label(s),
      for (final c in _matchColumns) RevisionMatch('datalab', c.key): c.label,
    };
  }

  (String, String) _head() => switch (_step) {
        _Step.source => (t('ماذا نقارن به؟', 'What should we compare with?'), t('اختر مصدر الدرجات المسجّلة.', 'Choose where the recorded degrees are.')),
        _Step.template => (t('شكل الورقة', 'The paper'), t('نستخدم القالب لنعرف أين تُكتب الدرجات ورقم الطالب.', "A template tells us where the degrees and the student's number are.")),
        _Step.match => (t('كيف نربط الورقة بالطالب؟', 'How do we link a paper to a student?'), t('لا تُربط أي ورقة بالاسم وحده تلقائيًا.', 'A name alone never links a paper.')),
        _Step.sample => (t('جرّب ورقة واحدة', 'Try one paper'), t('صوّر أو ارفع ورقة معبأة واحدة لترى ما سنقرأه. لن يُحفظ شيء.', 'Scan or upload ONE filled paper to see what we read. Nothing is saved.')),
        _Step.style => (t('كيف كُتبت الورقة؟', 'How is the paper written?'), t('اختر ما يناسب أوراقك، ونعيد قراءة ورقتك فورًا لتقارن.', 'Choose what fits your papers; we read your paper again at once so you can compare.')),
      };

  bool get _sampleGood => _sample != null && _sample!.verdict(nameOnly: _s.template?.nameOnly ?? false) == SampleVerdict.good;

  Widget _body() {
    return switch (_step) {
      _Step.source => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final e in _earlier)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: RevisionChoiceCard(key: ValueKey('rv.earlier.${e.id}'), icon: Icons.play_circle_outline_rounded, title: t('متابعة جلسة مفتوحة', 'Continue an open session'), subtitle: '${e.columnLabel} · ${countText(e.counts.pages, ar1: 'ورقة واحدة', ar2: 'ورقتان', arFew: '${e.counts.pages} أوراق', arMany: '${e.counts.pages} ورقة', en1: '1 paper', en: '${e.counts.pages} papers', ar0: 'لا أوراق', en0: 'no papers')}', selected: false, onTap: () => _continueEarlier(e)),
            ),
          if (_earlier.isNotEmpty) const SizedBox(height: AppSpace.sm),
          RevisionSourceStep(
            key: const ValueKey('rv.step.source'),
            setup: _s,
            courses: _courses,
            columns: _degreeColumns,
            courseLocked: _courseLocked,
            courseName: _courseName,
            loadingColumns: _loadingColumns,
            uploading: _uploading,
            onSource: (v) => setState(() {
              _s.source = v;
              _clearSample();
            }),
            onCourse: (id) {
              setState(() {
                _s.courseId = id;
                _s.column = null;
                _degreeColumns = const [];
                _clearSample();
              });
              unawaited(_loadColumns(id));
            },
            onColumn: (col) => setState(() => _s.column = col),
            onUpload: _upload,
            onMatchColumn: (x) => setState(() {
              _s.matchColumn = x;
              _clearSample();
              if (_s.degreeColumn == x) _s.degreeColumn = null;
            }),
            onDegreeColumn: (x) => setState(() {
              _s.degreeColumn = x;
              if (_s.matchColumn == x) _s.matchColumn = null;
            }),
            onSheetMax: (x) => setState(() => _s.sheetMax = x),
            onImportInstead: _courseLocked ? _importInstead : null,
          ),
        ]),
      _Step.template => RevisionTemplateStep(
          key: const ValueKey('rv.step.template'),
          setup: _s,
          templates: _tpls,
          loading: _loadingTpls,
          loadingId: _loadingTplId,
          onPick: _pickTemplate,
          onCreate: _newTemplate,
          onEdit: _editTemplate,
          onStep: (v) => setState(() => _s.step = v),
        ),
      _Step.match => RevisionMatchStep(
          key: const ValueKey('rv.step.match'),
          setup: _s,
          options: _matchOptions,
          onPick: (v) => setState(() {
            _s.match = v;
            _clearSample();
          }),
        ),
      _Step.sample => _sampleStep(),
      _Step.style => RevisionStyleStep(
          key: const ValueKey('rv.step.style'),
          styles: _s.styles,
          hasPhoto: _photo != null,
          sample: _sample,
          previous: _previous,
          loading: _sampling,
          onChanged: _changeStyles,
          onRestore: _previous == null ? null : _restoreStyles,
        ),
    };
  }

  Widget _sampleStep() {
    final tpl = _s.template;
    final s = _sample;
    if (_sampling) return const AppListSkeleton(items: 4);
    if (s == null || tpl == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(Icons.document_scanner_outlined, size: AppIconSize.hero, color: context.colors.primary),
        AppSpace.gapSm,
        Text(t('اختر ورقة معبأة تمثل بقية الأوراق.', 'Pick one filled paper that looks like the rest.'), textAlign: TextAlign.center, style: AppType.section(context)),
        AppSpace.gapMd,
        if (canUseCamera) ...[
          AppPrimaryButton(key: const ValueKey('rv.sample.camera'), label: t('تصوير ورقة', 'Scan a paper'), icon: Icons.photo_camera_outlined, onPressed: () => _takeSample(camera: true)),
          AppSpace.gapSm,
        ],
        canUseCamera
            ? OutlinedButton.icon(key: const ValueKey('rv.sample.file'), onPressed: () => _takeSample(camera: false), icon: const Icon(Icons.upload_file_rounded), label: Text(t('رفع صورة', 'Upload a picture')))
            : AppPrimaryButton(key: const ValueKey('rv.sample.file'), label: t('رفع صورة الورقة', 'Upload the paper'), icon: Icons.upload_file_rounded, onPressed: () => _takeSample(camera: false)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RevisionSampleView(key: const ValueKey('rv.step.sample'), sample: s, aspect: tpl.aspect, identifierBox: tpl.identifierBox, nameOnly: tpl.nameOnly),
      AppSpace.gapSm,
      Center(child: TextButton.icon(key: const ValueKey('rv.sample.again'), onPressed: () => _takeSample(camera: canUseCamera), icon: const Icon(Icons.replay_rounded), label: Text(t('تجربة ورقة أخرى', 'Try another paper')))),
    ]);
  }

  Widget _footer() {
    final (label, icon, on) = switch (_step) {
      _Step.source => (t('التالي', 'Next'), Icons.arrow_forward_rounded, _s.sourceReady ? () => _go(_Step.template) : null),
      _Step.template => (t('التالي', 'Next'), Icons.arrow_forward_rounded, _s.templateReady ? () => _go(_Step.match) : null),
      _Step.match => (t('التالي', 'Next'), Icons.arrow_forward_rounded, () => _go(_Step.sample)),
      _Step.sample => (t('التالي: طريقة الكتابة', 'Next: how it is written'), Icons.arrow_forward_rounded, (_sample?.ok ?? false) && !_sampling ? () => _go(_Step.style) : null),
      _Step.style => (t('ابدأ المراجعة', 'Start the revision'), Icons.play_arrow_rounded, (_sampleGood || _force) && !_sampling && !_starting ? _start : null),
    };
    final badSample = _step == _Step.sample && _sample != null && !_sample!.ok;
    final canForce = (_step == _Step.style && !_sampleGood && !_force && !_sampling) || badSample;
    return Container(
      decoration: BoxDecoration(color: context.colors.surface, border: Border(top: BorderSide(color: context.colors.divider))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.form.max),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (canForce)
                  TextButton(
                    key: const ValueKey('rv.force'),
                    onPressed: () async {
                      setState(() => _force = true);
                      if (_step == _Step.sample) await _go(_Step.style);
                    },
                    child: Text(t('المتابعة رغم ذلك (ستُراجع الأوراق غير المقروءة بنفسك)', 'Continue anyway (you will correct what cannot be read)')),
                  ),
                Row(children: [
                  if (_step != _Step.source) ...[
                    OutlinedButton(
                      key: const ValueKey('rv.back'),
                      style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(AppTouch.min, AppTouch.primary))),
                      onPressed: () => setState(() => _step = _Step.values[_step.index - 1]),
                      child: Text(t('رجوع', 'Back')),
                    ),
                    AppSpace.gapSm,
                  ],
                  Expanded(child: AppPrimaryButton(key: const ValueKey('rv.primary'), label: label, icon: icon, busy: _starting, onPressed: on)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (head, sub) = _head();
    final wideStep = _step == _Step.sample || _step == _Step.style;
    return BasePage(
      appBar: ScreenAppBar(title: t('مراجعة الدرجات', 'Grade revision')),
      child: _booting
          ? const AppListSkeleton(items: 4)
          : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: wideStep ? AppWidth.content.max : AppWidth.form.max),
                        child: RevisionStepHeader(index: _step.index, total: _Step.values.length, title: head, subtitle: sub),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: wideStep ? AppWidth.content.max : AppWidth.form.max),
                          child: AnimatedSwitcher(duration: AppMotion.of(context).base, child: KeyedSubtree(key: ValueKey(_step), child: _body())),
                        ),
                      ),
                    ),
                  ),
                  _footer(),
                ]),
    );
  }
}

class RevisionStepHeader extends StatelessWidget {
  const RevisionStepHeader({super.key, required this.index, required this.total, required this.title, required this.subtitle});
  final int index, total;
  final String title, subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.xxs),
          Expanded(child: Container(height: 4, decoration: BoxDecoration(color: i <= index ? c.primary : c.divider, borderRadius: BorderRadius.circular(2)))),
        ],
      ]),
      AppSpace.gapSm,
      Text(t('الخطوة ${index + 1} من $total', 'Step ${index + 1} of $total'), style: AppType.meta(context)),
      Text(title, style: AppType.pageTitle(context)),
      Text(subtitle, style: AppType.meta(context)),
    ]);
  }
}
