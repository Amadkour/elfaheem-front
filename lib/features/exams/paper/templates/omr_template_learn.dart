// "New bubble sheet type" — learning a sheet layout from a BLANK and a FILLED sample (D-155, the brief's Example 3),
// for the super admin (the library's "New bubble sheet type") and the teacher (the exam wizard's "Upload a custom
// layout"):
//
//   upload   the blank sheet + the filled sample (image or PDF; a camera photo on phones) + the shading description in
//            plain numbers → POST /omr/templates/learn (202, a draft)
//   learning the worker job reads it; the screen follows `job_updated {kind: omr_template, id}` (EventOrPoll, a slow
//            poll only as the fallback)
//   result   "Detected 4 corner marks, 2 answer columns" + the warnings, each with its fix
//   check    the step-through on the sheet: "Question 1: detected 4 bubbles, filled: B. Correct?" — Next / Back /
//            jump, the question's bubbles highlighted; Fix → DRAG a bubble (or the whole question) / its handle to
//            resize, Save → PUT …/boxes (the box is re-measured by a job: `recalibrating`); then the student ID zone
//            ("Detected 10 columns × 10 digits. Student ID read from the filled sheet: 2024001234. Correct?") and the
//            model row
//   save     POST …/validate (errors / warnings with the fix) → POST …/submit: the super admin's is published, a
//            teacher's is "Sent for approval" when the server says pending_approval
//
// A published version is never edited in place: "Edit" makes version n + 1 (POST …/versions) and says so. Keyboard:
// ← / → walk the steps (mirrored in Arabic), Enter confirms; while fixing, the arrows nudge the box (Shift: 1 mm),
// Enter saves, Esc cancels. Presentational bodies take plain values (layout harness); the state wires them.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asMap, t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/exams/paper/exam_setup_wizard.dart' show SetupChoiceTile, SetupProgress;
import 'package:flutter_education_app/features/exams/paper/templates/omr_sheet_overlay.dart';
import 'package:flutter_education_app/features/exams/paper/templates/omr_templates.dart';
import 'package:flutter_education_app/features/exams/paper/omr_counts.dart';

/// Picks one file: (name, bytes), or null when the person cancelled. [camera]: a photo (phones only).
typedef LearnFilePicker = Future<(String, Uint8List)?> Function({required bool camera});

Future<(String, Uint8List)?> defaultLearnFilePicker({required bool camera}) async {
  try {
    if (camera) {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 3000, imageQuality: 92);
      if (x == null) return null;
      return (x.name.isEmpty ? 'sheet.jpg' : x.name, await x.readAsBytes());
    }
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf']);
    if (f == null) return null;
    return (f.name, await f.readAsBytes());
  } catch (_) {
    return null;
  }
}

/// Opens the learning flow; true when a sheet type was saved (published or sent for approval).
Future<bool?> openOmrTemplateLearn(BuildContext context, {bool isSuperAdmin = false, int? templateId, bool readOnly = false}) =>
    Navigator.of(context).push<bool>(MaterialPageRoute(
      settings: const RouteSettings(name: OmrTemplateLearnPage.routeName),
      builder: (_) => OmrTemplateLearnPage(isSuperAdmin: isSuperAdmin, templateId: templateId, readOnly: readOnly),
    ));

enum LearnStage { start, upload, learning, result, check, save, done }

class OmrTemplateLearnPage extends StatefulWidget {
  const OmrTemplateLearnPage({
    super.key,
    this.isSuperAdmin = false,
    this.templateId,
    this.readOnly = false,
    this.api,
    this.pickFile,
    this.liveStream,
    this.liveBus,
  });

  static const routeName = '/omr-template-learn';

  /// Wording only (Publish vs. Submit); the server decides what a submission becomes.
  final bool isSuperAdmin;

  /// Opens an existing version (a draft to finish, a pending one to review) instead of a new upload.
  final int? templateId;

  /// The super admin reviewing a teacher's pending version: walk it, approve or reject it, change nothing.
  final bool readOnly;
  final OmrTemplatesApi? api;
  final LearnFilePicker? pickFile;
  final LiveStreamHandle? liveStream;
  final LiveEvents? liveBus;

  @override
  State<OmrTemplateLearnPage> createState() => _OmrTemplateLearnPageState();
}

class _OmrTemplateLearnPageState extends State<OmrTemplateLearnPage> {
  late final OmrTemplatesApi _api = widget.api ?? OmrTemplatesApi();
  LearnFilePicker get _pick => widget.pickFile ?? defaultLearnFilePicker;

  LearnStage _stage = LearnStage.upload;
  bool _busy = false;
  String? _error;

  // start (a teacher's unfinished sheet types)
  List<OmrTemplateRow>? _mine;

  // upload
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _questions = TextEditingController();
  final _options = TextEditingController();
  final _perColumn = TextEditingController();
  final _idColumns = TextEditingController();
  final _forms = TextEditingController();
  String _layout = 'columns';
  bool _oneChoice = true;
  String _idKind = 'shaded';
  (String, Uint8List)? _blank;
  (String, Uint8List)? _filled;

  // the template
  int? _tid;
  OmrTemplateRow? _row;
  TemplateSteps? _steps;
  Uint8List? _blankImage;
  Uint8List? _filledImage;
  int? _imagesFor;
  bool _showFilled = true;
  EventOrPoll? _watch;

  // check
  int _index = 0;
  bool _editing = false;
  bool _moveAll = false;
  int? _selected;
  List<OmrBubble>? _draft;
  int _idColumn = 0;
  bool _identifierChecked = false;
  bool _formChecked = false;

  // save / done
  TemplateValidation? _validation;
  OmrTemplateRow? _final;

  final _overlayKey = GlobalKey<SheetOverlayState>();
  final _focus = FocusNode(debugLabel: 'omr-step-through');

  @override
  void initState() {
    super.initState();
    final id = widget.templateId;
    if (id != null) {
      _openTemplate(id);
    } else if (!widget.isSuperAdmin) {
      _stage = LearnStage.start;
      _loadMine();
    }
  }

  @override
  void dispose() {
    _watch?.dispose();
    for (final c in [_name, _description, _questions, _options, _perColumn, _idColumns, _forms]) {
      c.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  void _fail(EngineResult r) => setState(() {
        _busy = false;
        _error = omrTemplateErrorText(r);
      });

  // ── start ──

  Future<void> _loadMine() async {
    final r = await _api.list();
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _stage = LearnStage.upload); // nothing to resume is never a dead end: go on with a new upload
      return;
    }
    final rows = [
      for (final m in (r.map['items'] is List ? r.map['items'] as List : const []))
        if (m is Map) OmrTemplateRow.fromJson(asMap(m)),
    ].where((x) => !x.isBuiltin && (x.editable || x.pending)).toList();
    setState(() {
      _mine = rows;
      if (rows.isEmpty) _stage = LearnStage.upload;
    });
  }

  // ── upload ──

  LearnHints get _hints => LearnHints(
        questions: int.tryParse(_questions.text.trim()),
        options: int.tryParse(_options.text.trim()),
        perColumn: int.tryParse(_perColumn.text.trim()),
        layout: _layout,
        oneChoice: _oneChoice,
        idKind: _idKind,
        idColumns: int.tryParse(_idColumns.text.trim()),
        forms: _forms.text,
      );

  String? get _uploadProblem {
    if (_name.text.trim().isEmpty) return t('اكتب اسمًا لنوع الورقة', 'Give the sheet type a name');
    if (_blank == null) return t('ارفع صورة الورقة الفارغة', 'Upload the blank sheet');
    return _hints.problem();
  }

  Future<void> _pickInto(bool blank, {required bool camera}) async {
    final f = await _pick(camera: camera);
    if (f == null || !mounted) return;
    if (!learnFileAccepted(f.$1) && !camera) {
      showAppNotice(t('ارفع صورة PNG أو JPEG أو WebP أو ملف PDF', 'Upload a PNG, JPEG or WebP image or a PDF'), error: true);
      return;
    }
    if (f.$2.length > 20 * 1024 * 1024) {
      showAppNotice(t('الملف أكبر من 20 ميجابايت', 'The file is larger than 20 MB'), error: true);
      return;
    }
    setState(() {
      if (blank) {
        _blank = f;
      } else {
        _filled = f;
      }
      _error = null;
    });
  }

  Future<void> _learn() async {
    final p = _uploadProblem;
    if (p != null) {
      setState(() => _error = p);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.learn(name: _name.text, hints: _hints, blank: _blank!, filled: _filled, description: _description.text);
    if (!mounted) return;
    if (!r.ok) return _fail(r);
    final row = OmrTemplateRow.fromJson(r.map);
    setState(() {
      _busy = false;
      _tid = row.id;
      _row = row;
      _steps = null;
      _stage = LearnStage.learning;
      _resetCheck();
    });
    _watchJob();
  }

  // ── a template: load, watch ──

  Future<void> _openTemplate(int id) async {
    setState(() {
      _tid = id;
      _stage = LearnStage.learning;
      _busy = true;
    });
    final d = await _api.detail(id);
    if (!mounted) return;
    if (!d.ok) {
      setState(() {
        _busy = false;
        _stage = LearnStage.result;
        _error = omrTemplateErrorText(d);
      });
      return;
    }
    setState(() => _row = OmrTemplateRow.fromJson(d.map));
    await _loadSteps(initial: true);
  }

  Future<void> _loadSteps({bool initial = false}) async {
    final id = _tid;
    if (id == null) return;
    final r = await _api.steps(id);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = omrTemplateErrorText(r);
      });
      return;
    }
    final s = TemplateSteps.fromJson(r.map);
    final was = _steps;
    setState(() {
      _busy = false;
      _steps = s;
      if (_row != null && _row!.status != s.status) _row = _copyStatus(_row!, s.status);
      if (s.learning) {
        _stage = LearnStage.learning;
      } else if (_stage == LearnStage.learning) {
        _stage = (initial && widget.readOnly) ? LearnStage.check : LearnStage.result;
      }
      if (_index >= stepItems(s).length) _index = 0;
    });
    if (s.busy) {
      _watchJob();
    } else {
      _watch?.stop();
      if (was != null && was.recalibrating) showAppNotice(t('تم قياس المربعات المعدّلة', 'The corrected boxes are measured'));
      if (_stage == LearnStage.save) _validate();
    }
    _loadImages(s);
  }

  OmrTemplateRow _copyStatus(OmrTemplateRow r, String status) => OmrTemplateRow(
        id: r.id,
        familyId: r.familyId,
        version: r.version,
        name: r.name,
        nameAr: r.nameAr,
        nameEn: r.nameEn,
        description: r.description,
        status: status,
        ownerId: r.ownerId,
        ownerRole: r.ownerRole,
        questions: r.questions,
        options: r.options,
        optionLabels: r.optionLabels,
        idKind: r.idKind,
        idDigits: r.idDigits,
        formsOnSheet: r.formsOnSheet,
        builtin: r.builtin,
        printable: r.printable,
        learningState: r.learningState,
        previewUrl: r.previewUrl,
        validationOk: r.validationOk,
        reviewNote: r.reviewNote,
        approvedAt: r.approvedAt,
        createdAt: r.createdAt,
      );

  Future<void> _loadImages(TemplateSteps s) async {
    final id = _tid;
    if (id == null || _imagesFor == id || !s.preview.available) return;
    _imagesFor = id;
    final blank = await _api.image(id, 'blank_preview');
    final filled = s.preview.filledUrl == null ? null : await _api.image(id, 'filled_preview');
    if (!mounted || _tid != id) return;
    setState(() {
      _blankImage = blank;
      _filledImage = filled;
    });
  }

  void _watchJob() {
    final id = _tid;
    if (id == null) return;
    final w = _watch;
    if (w != null && w.id == '$id') {
      if (!w.running) w.start();
      return;
    }
    w?.dispose();
    _watch = EventOrPoll(
      kind: 'omr_template',
      id: '$id',
      every: const Duration(seconds: 3),
      fallbackEvery: const Duration(seconds: 12),
      poll: () => _loadSteps(),
      bus: widget.liveBus,
      stream: widget.liveStream,
    )..start();
  }

  // ── check (the step-through) ──

  List<StepItem> get _items => _steps == null ? const [] : stepItems(_steps!);

  void _resetCheck() {
    _index = 0;
    _editing = false;
    _draft = null;
    _selected = null;
    _identifierChecked = false;
    _formChecked = false;
    _idColumn = 0;
  }

  List<OmrBubble> _bubblesOf(StepItem item) {
    final s = _steps!;
    return switch (item) {
      QuestionItem(:final n) => s.question(n)?.bubbles ?? const [],
      IdentifierItem() => s.identifier.columns.isEmpty ? const [] : s.identifier.columns[_idColumn.clamp(0, s.identifier.columns.length - 1)],
      FormRowItem() => s.form.bubbles,
    };
  }

  void _toCheck() {
    setState(() {
      _stage = LearnStage.check;
      _error = null;
      final s = _steps;
      if (s != null) {
        // start at the first question still to confirm
        final first = s.questions.indexWhere((q) => !q.confirmed);
        _index = first < 0 ? 0 : first;
      }
    });
    _focus.requestFocus();
  }

  void _go(int i) {
    final items = _items;
    if (items.isEmpty) return;
    setState(() {
      _index = i.clamp(0, items.length - 1);
      _editing = false;
      _draft = null;
      _selected = null;
      _error = null;
    });
  }

  void _next() {
    if (_index >= _items.length - 1) {
      _toSave();
    } else {
      _go(_index + 1);
    }
  }

  void _back() {
    if (_index == 0) {
      setState(() => _stage = LearnStage.result);
    } else {
      _go(_index - 1);
    }
  }

  Future<void> _confirmCurrent() async {
    final items = _items;
    if (items.isEmpty || _busy) return;
    final item = items[_index];
    if (widget.readOnly || !(_steps?.editable ?? false)) return _next();
    switch (item) {
      case QuestionItem(:final n):
        if (_steps!.question(n)?.confirmed ?? false) return _next();
        setState(() => _busy = true);
        final r = await _api.confirm(_tid!, [n]);
        if (!mounted) return;
        if (!r.ok) return _fail(r);
        setState(() {
          _busy = false;
          _steps = TemplateSteps.fromJson(r.map);
        });
        _next();
      case IdentifierItem():
        setState(() => _identifierChecked = true);
        _next();
      case FormRowItem():
        setState(() => _formChecked = true);
        _next();
    }
  }

  Future<void> _confirmClear() async {
    final s = _steps;
    if (s == null) return;
    final ns = s.clearUnconfirmed;
    if (ns.isEmpty) return;
    final ok = await appConfirm(context,
        message: t('تأكيد ${omrQuestionsText(ns.length)} قُرئ في كل منها تظليل واحد واضح دون مشكلات؟ تبقى الأسئلة الأخرى لمراجعتك.',
            'Confirm the ${ns.length} questions that each read as one clear mark with no problem? The others stay for you to check.'),
        confirmLabel: t('تأكيد', 'Confirm'));
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await _api.confirm(_tid!, ns);
    if (!mounted) return;
    if (!r.ok) return _fail(r);
    setState(() {
      _busy = false;
      _steps = TemplateSteps.fromJson(r.map);
    });
    showAppNotice(t('تم تأكيد ${omrQuestionsText(ns.length)}', '${ns.length} questions confirmed'));
  }

  void _startEdit() {
    final items = _items;
    if (items.isEmpty) return;
    final cur = _bubblesOf(items[_index]);
    if (cur.isEmpty) return;
    var sel = 0;
    final item = items[_index];
    if (item is QuestionItem) {
      final f = _steps!.question(item.n)?.filled ?? const [];
      final i = cur.indexWhere((b) => f.contains(b.label));
      if (i >= 0) sel = i;
    }
    setState(() {
      _editing = true;
      _moveAll = false;
      _draft = List.of(cur);
      _selected = sel;
    });
    _focus.requestFocus();
  }

  void _cancelEdit() => setState(() {
        _editing = false;
        _draft = null;
        _selected = null;
      });

  Future<void> _saveEdit() async {
    final draft = _draft;
    final items = _items;
    if (draft == null || items.isEmpty) return;
    final item = items[_index];
    if (sameBubbles(draft, _bubblesOf(item))) return _cancelEdit();
    setState(() => _busy = true);
    final r = switch (item) {
      QuestionItem(:final n) => await _api.putAnswerBoxes(_tid!, n, draft),
      IdentifierItem() => await _api.putIdentifierColumn(_tid!, _idColumn, draft),
      FormRowItem() => await _api.putFormRow(_tid!, draft),
    };
    if (!mounted) return;
    if (!r.ok) return _fail(r);
    setState(() {
      _busy = false;
      _steps = TemplateSteps.fromJson(r.map);
      _editing = false;
      _draft = null;
      _selected = null;
      if (item is IdentifierItem) _identifierChecked = false;
      if (item is FormRowItem) _formChecked = false;
    });
    showAppNotice(t('حُفظ التعديل — نعيد قياس الورقة الآن، ثم أكّد الخطوة.', 'Fix saved — the sheet is being re-measured; confirm this step next.'));
    _watchJob();
  }

  void _nudge(double dx, double dy) {
    final d = _draft, g = _steps?.preview.geometry;
    if (d == null || g == null) return;
    setState(() {
      if (_moveAll || _selected == null) {
        _draft = [for (final b in d) nudged(b, dx, dy, g)];
      } else {
        _draft = [for (var i = 0; i < d.length; i++) i == _selected ? nudged(d[i], dx, dy, g) : d[i]];
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (_stage != LearnStage.check || (e is! KeyDownEvent && e is! KeyRepeatEvent)) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    if (_editing) {
      final step = HardwareKeyboard.instance.isShiftPressed ? 1.0 : 0.1;
      if (k == LogicalKeyboardKey.arrowLeft) return _handled(() => _nudge(-step, 0));
      if (k == LogicalKeyboardKey.arrowRight) return _handled(() => _nudge(step, 0));
      if (k == LogicalKeyboardKey.arrowUp) return _handled(() => _nudge(0, -step));
      if (k == LogicalKeyboardKey.arrowDown) return _handled(() => _nudge(0, step));
      if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) return _handled(_saveEdit);
      if (k == LogicalKeyboardKey.escape) return _handled(_cancelEdit);
      return KeyEventResult.ignored;
    }
    if (e is KeyRepeatEvent) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowRight) return _handled(rtl ? _back : _next);
    if (k == LogicalKeyboardKey.arrowLeft) return _handled(rtl ? _next : _back);
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) return _handled(_confirmCurrent);
    return KeyEventResult.ignored;
  }

  KeyEventResult _handled(void Function() f) {
    f();
    return KeyEventResult.handled;
  }

  // ── save ──

  void _toSave() {
    setState(() {
      _stage = LearnStage.save;
      _error = null;
      _validation = null;
    });
    if (!(_steps?.busy ?? false)) _validate();
  }

  Future<void> _validate() async {
    final id = _tid;
    if (id == null || widget.readOnly || !(_steps?.editable ?? false)) return;
    final r = await _api.validate(id);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _validation = TemplateValidation.fromJson(r.map);
      } else {
        _error = omrTemplateErrorText(r);
      }
    });
  }

  Future<void> _submit() async {
    final id = _tid;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.submit(id);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = omrTemplateErrorText(r);
        if (r.code == 'template_invalid') _validation = TemplateValidation.fromJson(r.detail['validation']);
      });
      return;
    }
    setState(() {
      _busy = false;
      _final = OmrTemplateRow.fromJson(r.map);
      _stage = LearnStage.done;
    });
  }

  Future<void> _approve() async {
    final id = _tid;
    if (id == null) return;
    setState(() => _busy = true);
    final r = await _api.approve(id);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = omrTemplateErrorText(r);
      });
      return;
    }
    setState(() {
      _busy = false;
      _final = OmrTemplateRow.fromJson(r.map);
      _stage = LearnStage.done;
    });
  }

  Future<void> _reject() async {
    final id = _tid;
    if (id == null) return;
    final reason = await askRejectReason(context);
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final r = await _api.reject(id, reason);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = omrTemplateErrorText(r);
      });
      return;
    }
    setState(() {
      _busy = false;
      _final = OmrTemplateRow.fromJson(r.map);
      _stage = LearnStage.done;
    });
  }

  /// A published version: make version n + 1 and carry on there.
  Future<void> _newVersion() async {
    final id = _tid;
    if (id == null) return;
    setState(() => _busy = true);
    final r = await _api.newVersion(id);
    if (!mounted) return;
    if (!r.ok) return _fail(r);
    final row = OmrTemplateRow.fromJson(r.map);
    showAppNotice(t('أُنشئ الإصدار ${row.version} — الاختبارات التي تستخدم الإصدار ${_row?.version ?? ''} تبقى عليه.',
        'Version ${row.version} created — exams that use version ${_row?.version ?? ''} keep it.'));
    _imagesFor = null;
    setState(() {
      _resetCheck();
      _row = row;
      _tid = row.id;
    });
    await _loadSteps();
    if (mounted) _toCheck();
  }

  void _reupload() {
    _watch?.dispose();
    _watch = null;
    setState(() {
      _stage = LearnStage.upload;
      _tid = null;
      _row = null;
      _steps = null;
      _blankImage = null;
      _filledImage = null;
      _imagesFor = null;
      _error = null;
      _resetCheck();
    });
  }

  // ── build ──

  String get _title {
    final r = _row;
    if (r == null) return t('نوع ورقة تظليل جديد', 'New bubble sheet type');
    return t('${r.displayName} · الإصدار ${r.version}', '${r.displayName} · v${r.version}');
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey(kOmrFeatureKey),
      appBar: ScreenAppBar(title: _title),
      child: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final s = _steps;
    switch (_stage) {
      case LearnStage.start:
        return LearnStartBody(
          mine: _mine,
          onOpen: (r) {
            _watch?.dispose();
            _watch = null;
            _imagesFor = null;
            _openTemplate(r.id);
          },
          onNew: () => setState(() => _stage = LearnStage.upload),
        );
      case LearnStage.upload:
        return LearnUploadBody(
          name: _name,
          description: _description,
          questions: _questions,
          options: _options,
          perColumn: _perColumn,
          idColumns: _idColumns,
          forms: _forms,
          layout: _layout,
          oneChoice: _oneChoice,
          idKind: _idKind,
          blankName: _blank?.$1,
          blankBytes: _blank?.$2.length,
          filledName: _filled?.$1,
          filledBytes: _filled?.$2.length,
          cameraAvailable: !kIsWeb,
          busy: _busy,
          error: _error,
          onLayout: (v) => setState(() => _layout = v),
          onOneChoice: (v) => setState(() => _oneChoice = v),
          onIdKind: (v) => setState(() => _idKind = v),
          onPickBlank: ({required bool camera}) => _pickInto(true, camera: camera),
          onPickFilled: ({required bool camera}) => _pickInto(false, camera: camera),
          onClearFilled: () => setState(() => _filled = null),
          onLearn: _learn,
          onBack: () => Navigator.of(context).maybePop(),
        );
      case LearnStage.learning:
        return LearnWaitingBody(name: _row?.displayName ?? _name.text.trim(), error: _error, onBack: () => Navigator.of(context).maybePop());
      case LearnStage.result:
        return LearnResultBody(
          steps: s,
          image: _blankImage,
          error: _error,
          readOnly: widget.readOnly,
          published: _row?.versionable ?? false,
          version: _row?.version ?? 1,
          busy: _busy,
          onCheck: s == null || s.questions.isEmpty ? null : _toCheck,
          onReupload: widget.templateId == null ? _reupload : null,
          onNewVersion: _newVersion,
          onBack: () => Navigator.of(context).maybePop(),
        );
      case LearnStage.check:
        if (s == null || s.preview.geometry == null) {
          return LearnResultBody(
              steps: s,
              image: null,
              error: _error,
              readOnly: widget.readOnly,
              version: _row?.version ?? 1,
              onReupload: widget.templateId == null ? _reupload : null,
              onBack: () => Navigator.of(context).maybePop());
        }
        final items = stepItems(s);
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: StepThroughView(
            steps: s,
            items: items,
            index: _index.clamp(0, items.isEmpty ? 0 : items.length - 1),
            blankImage: _blankImage,
            filledImage: _filledImage,
            showFilled: _showFilled && _filledImage != null,
            editing: _editing,
            moveAll: _moveAll,
            draft: _draft,
            selected: _selected,
            idColumn: _idColumn,
            identifierChecked: _identifierChecked,
            formChecked: _formChecked,
            canEdit: !widget.readOnly && s.editable,
            published: _row?.versionable ?? false,
            version: _row?.version ?? 1,
            busy: _busy,
            error: _error,
            overlayKey: _overlayKey,
            onShowFilled: (v) => setState(() => _showFilled = v),
            onBack: _back,
            onNext: _next,
            onConfirm: _confirmCurrent,
            onConfirmClear: s.clearUnconfirmed.isEmpty || widget.readOnly || !s.editable ? null : _confirmClear,
            onJump: _go,
            onEdit: _startEdit,
            onCancelEdit: _cancelEdit,
            onSaveEdit: _saveEdit,
            onMoveAll: (v) => setState(() => _moveAll = v),
            onSelect: (i) => setState(() => _selected = i),
            onDraft: (d) => setState(() => _draft = d),
            onIdColumn: (i) => setState(() {
              _idColumn = i;
              if (_editing) _draft = List.of(s.identifier.columns[i]);
            }),
            onNewVersion: _newVersion,
            onFinish: _toSave,
          ),
        );
      case LearnStage.save:
        return LearnSaveBody(
          steps: s,
          validation: _validation ?? s?.validation,
          checking: (s?.busy ?? false) || (_validation == null && _error == null && !widget.readOnly && (s?.editable ?? false)),
          isSuperAdmin: widget.isSuperAdmin,
          readOnly: widget.readOnly,
          status: _row?.status ?? s?.status ?? 'draft',
          version: _row?.version ?? 1,
          busy: _busy,
          error: _error,
          onBack: () => setState(() {
            _stage = LearnStage.check;
            _error = null;
          }),
          onOpenQuestion: (n) {
            final i = _items.indexWhere((x) => x is QuestionItem && x.n == n);
            _toCheck();
            if (i >= 0) _go(i);
          },
          onSubmit: _submit,
          onApprove: _approve,
          onReject: _reject,
          onNewVersion: _newVersion,
        );
      case LearnStage.done:
        return LearnDoneBody(row: _final!, onDone: () => Navigator.of(context).maybePop(true));
    }
  }
}

/// The super admin's reason for rejecting a version (required, ≤ 500 characters); null when cancelled.
Future<String?> askRejectReason(BuildContext context) => showAppSheet<String>(context, (_) => const RejectReasonSheet());

class RejectReasonSheet extends StatefulWidget {
  const RejectReasonSheet({super.key});

  @override
  State<RejectReasonSheet> createState() => _RejectReasonSheetState();
}

class _RejectReasonSheetState extends State<RejectReasonSheet> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final empty = _ctl.text.trim().isEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('سبب الرفض', 'Why is it rejected?'), style: appText(18, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(height: AppSpace.xxs),
        Text(t('يقرأ المعلم هذا السبب ويصحح الورقة ثم يرسلها مرة أخرى.', 'The teacher reads this, fixes the sheet and sends it again.'),
            style: appText(13, c: c.textMedium, h: 1.4)),
        const SizedBox(height: AppSpace.md),
        TextField(
          key: const ValueKey('omr.reject.reason'),
          controller: _ctl,
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          minLines: 2,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: t('السبب', 'Reason'), hintText: t('مثل: علامات الأركان قريبة جدًا من الحافة', 'e.g. The corner marks are too close to the edge')),
        ),
        const SizedBox(height: AppSpace.sm),
        KeyedSubtree(
          key: const ValueKey('omr.reject.send'),
          child: AppPrimaryButton(label: t('رفض الإصدار', 'Reject this version'), icon: Icons.block_rounded, onPressed: empty ? null : () => Navigator.of(context).pop(_ctl.text.trim())),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════ presentational bodies ═════════════════════════════════════════════════

/// The frame of the upload / result / save / done stages: progress, title, body, one primary action, Back.
class LearnFrame extends StatelessWidget {
  const LearnFrame({
    super.key,
    required this.step,
    required this.title,
    this.subtitle,
    this.error,
    required this.body,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.primaryKey = 'omr.primary',
    this.busy = false,
    this.backLabel,
    this.onBack,
    this.secondary,
    this.maxWidth = 720,
  });

  /// 0 upload · 1 check · 2 save
  final int step;
  final String title;
  final String? subtitle;
  final String? error;
  final Widget body;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final String primaryKey;
  final bool busy;
  final String? backLabel;
  final VoidCallback? onBack;
  final Widget? secondary;
  final double maxWidth;

  static String stepName(int i) => switch (i) {
        0 => t('الرفع والوصف', 'Upload and describe'),
        1 => t('المراجعة', 'Check'),
        _ => t('الحفظ', 'Save'),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SetupProgress(index: step, total: 3, label: stepName(step)),
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
      _ActionBar(
        maxWidth: maxWidth,
        children: [
          if (backLabel != null)
            Flexible(
              child: TextButton(
                key: const ValueKey('omr.back'),
                onPressed: onBack,
                style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                child: Text(backLabel!, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          if (secondary != null) Flexible(child: secondary!),
          const SizedBox(width: AppSpace.sm),
          if (primaryLabel != null)
            Expanded(
              flex: 2,
              child: KeyedSubtree(
                key: ValueKey(primaryKey),
                child: AppPrimaryButton(label: primaryLabel!, icon: primaryIcon, busy: busy, onPressed: onPrimary),
              ),
            )
          else
            const Spacer(),
        ],
      ),
    ]);
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.children, this.maxWidth = 720});
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        child: Center(
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: Row(children: children)),
        ),
      ),
    );
  }
}

/// A teacher's unfinished sheet types (drafts, pending, rejected) above "Upload a new layout".
class LearnStartBody extends StatelessWidget {
  const LearnStartBody({super.key, required this.mine, required this.onOpen, required this.onNew});

  /// null = loading.
  final List<OmrTemplateRow>? mine;
  final ValueChanged<OmrTemplateRow> onOpen;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = mine;
    return LearnFrame(
      step: 0,
      title: t('أوراق التظليل الخاصة بك', 'Your bubble sheet types'),
      subtitle: t('أكمل نوعًا بدأته، أو ارفع تصميمًا جديدًا.', 'Finish one you started, or upload a new layout.'),
      backLabel: t('رجوع', 'Back'),
      onBack: () => Navigator.of(context).maybePop(),
      primaryLabel: t('رفع تصميم جديد', 'Upload a new layout'),
      primaryIcon: Icons.upload_file_rounded,
      primaryKey: 'omr.start.new',
      onPrimary: onNew,
      body: rows == null
          ? const AppListSkeleton(items: 2, padding: EdgeInsets.zero)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final r in rows) ...[
                SetupChoiceTile(
                  key: ValueKey('omr.mine.${r.id}'),
                  icon: Icons.grid_on_rounded,
                  title: t('${r.displayName} · الإصدار ${r.version}', '${r.displayName} · v${r.version}'),
                  subtitle: [omrStatusLabel(r.status), r.shape, if (r.reviewNote != null) t('السبب: ${r.reviewNote}', 'Reason: ${r.reviewNote}')].join(' · '),
                  selected: false,
                  onTap: () => onOpen(r),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              if (rows.isEmpty) Text(t('لا توجد أنواع غير مكتملة.', 'Nothing unfinished.'), style: appText(13, c: c.textMedium)),
            ]),
    );
  }
}

Color omrStatusColor(BuildContext context, String status) {
  final c = context.colors;
  return switch (status) {
    'published' => c.success,
    'pending_approval' => c.warning,
    'rejected' => c.danger,
    'retired' => c.textMedium,
    _ => c.primary,
  };
}

typedef PickInto = Future<void> Function({required bool camera});

class LearnUploadBody extends StatelessWidget {
  const LearnUploadBody({
    super.key,
    required this.name,
    required this.description,
    required this.questions,
    required this.options,
    required this.perColumn,
    required this.idColumns,
    required this.forms,
    required this.layout,
    required this.oneChoice,
    required this.idKind,
    this.blankName,
    this.blankBytes,
    this.filledName,
    this.filledBytes,
    this.cameraAvailable = false,
    this.busy = false,
    this.error,
    required this.onLayout,
    required this.onOneChoice,
    required this.onIdKind,
    required this.onPickBlank,
    required this.onPickFilled,
    required this.onClearFilled,
    required this.onLearn,
    required this.onBack,
  });

  final TextEditingController name;
  final TextEditingController description;
  final TextEditingController questions;
  final TextEditingController options;
  final TextEditingController perColumn;
  final TextEditingController idColumns;
  final TextEditingController forms;
  final String layout;
  final bool oneChoice;
  final String idKind;
  final String? blankName;
  final int? blankBytes;
  final String? filledName;
  final int? filledBytes;
  final bool cameraAvailable;
  final bool busy;
  final String? error;
  final ValueChanged<String> onLayout;
  final ValueChanged<bool> onOneChoice;
  final ValueChanged<String> onIdKind;
  final PickInto onPickBlank;
  final PickInto onPickFilled;
  final VoidCallback onClearFilled;
  final VoidCallback onLearn;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final needsColumns = idKind == 'shaded' || idKind == 'handwritten';
    Widget numField(TextEditingController ctl, String label, String key, {String? hint}) => KeyedSubtree(
          key: ValueKey(key),
          child: Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppNumberField(controller: ctl, label: label, hint: hint, min: 1, textInputAction: TextInputAction.next)),
        );
    return LearnFrame(
      step: 0,
      title: t('علّم المنصة شكل ورقتك', 'Teach the platform your sheet'),
      subtitle: t('ارفع الورقة فارغة ونموذجًا مظلّلًا منها، وصِف التظليل بالأرقام. نتعرّف على العلامات والفقاعات، ثم تراجع كل سؤال بنفسك.',
          'Upload the sheet blank and one filled copy, and describe the shading in numbers. We find the marks and bubbles, then you check each question yourself.'),
      error: error,
      backLabel: t('رجوع', 'Back'),
      onBack: onBack,
      primaryLabel: t('تعلّم هذه الورقة', 'Learn this sheet'),
      primaryIcon: Icons.auto_awesome_rounded,
      primaryKey: 'omr.learn',
      busy: busy,
      onPrimary: busy ? null : onLearn,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KeyedSubtree(key: const ValueKey('omr.name'), child: AppField(controller: name, label: t('اسم نوع الورقة', 'Sheet type name'), hint: t('مثل: ورقة المدرسة 50 سؤالًا', 'e.g. School sheet, 50 questions'))),
        AppSectionTitle(t('الصور', 'The scans')),
        const SizedBox(height: AppSpace.xs),
        _FileSlot(
          slotKey: 'omr.blank',
          icon: Icons.description_outlined,
          title: t('الورقة الفارغة', 'Blank sheet'),
          help: t('مطلوبة · صورة مستقيمة تظهر فيها علامات الأركان الأربع', 'Required · a straight scan showing all four corner marks'),
          fileName: blankName,
          bytes: blankBytes,
          cameraAvailable: cameraAvailable,
          onPick: onPickBlank,
        ),
        const SizedBox(height: AppSpace.sm),
        _FileSlot(
          slotKey: 'omr.filled',
          icon: Icons.task_alt_rounded,
          title: t('نموذج مظلّل', 'Filled sample'),
          help: t('يُنصح به · نفس الورقة وقد ظُلّلت إجابة لكل سؤال ورقم طالب', 'Recommended · the same sheet with one answer per question and a student ID shaded'),
          fileName: filledName,
          bytes: filledBytes,
          cameraAvailable: cameraAvailable,
          onPick: onPickFilled,
          onClear: filledName == null ? null : onClearFilled,
        ),
        const SizedBox(height: AppSpace.lg),
        AppSectionTitle(t('وصف التظليل', 'How it is shaded'), subtitle: t('أرقام فقط — لا نخمّن شيئًا', 'Numbers only — nothing is guessed')),
        const SizedBox(height: AppSpace.xs),
        _TwoUp(children: [
          numField(questions, t('عدد الأسئلة', 'Questions'), 'omr.questions', hint: '1–300'),
          numField(options, t('اختيارات لكل سؤال', 'Options per question'), 'omr.options', hint: '2–8'),
        ]),
        _TwoUp(children: [
          numField(perColumn, t('أسئلة في كل عمود', 'Questions per column'), 'omr.per_column', hint: t('اختياري', 'Optional')),
          _ChoiceRow(
            label: t('ترقيم الأسئلة', 'Numbering'),
            value: layout,
            options: {'columns': t('نزولًا في كل عمود', 'Down each column'), 'rows': t('عبر الصفوف', 'Across the rows')},
            onChanged: onLayout,
            keyPrefix: 'omr.layout',
          ),
        ]),
        AppSwitchTile(
          key: const ValueKey('omr.one_choice'),
          title: t('اختيار واحد لكل سؤال', 'One choice per question'),
          subtitle: t('أوقفه إن كانت بعض الأسئلة متعددة الإجابات', 'Turn it off when some questions take several answers'),
          value: oneChoice,
          onChanged: onOneChoice,
        ),
        const SizedBox(height: AppSpace.md),
        AppSectionTitle(t('رقم الطالب على الورقة', 'Student ID on the sheet')),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final k in LearnHints.idKinds)
            KeyedSubtree(
              key: ValueKey('omr.id_kind.$k'),
              child: AppChoiceChip(label: omrIdKindLabel(k), selected: idKind == k, onTap: () => onIdKind(k)),
            ),
        ]),
        if (needsColumns) ...[
          const SizedBox(height: AppSpace.sm),
          numField(idColumns, t('عدد خانات رقم الطالب (الأعمدة)', 'Student ID digits (columns)'), 'omr.id_columns', hint: t('مثل 10', 'e.g. 10')),
        ],
        const SizedBox(height: AppSpace.sm),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('omr.more'),
            tilePadding: EdgeInsets.zero,
            title: Text(t('تفاصيل أخرى (اختيارية)', 'More details (optional)'), style: appText(14, w: FontWeight.w700, c: c.textDark)),
            children: [
              KeyedSubtree(
                key: const ValueKey('omr.forms'),
                child: AppField(controller: forms, label: t('حروف النماذج المطبوعة على الورقة', 'Model letters printed on the sheet'), hint: t('مثل ABCD — اتركه فارغًا إن لم توجد', 'e.g. ABCD — leave empty when there are none'), ltr: true),
              ),
              AppField(controller: description, label: t('ملاحظة', 'Note'), maxLines: 2),
            ],
          ),
        ),
      ]),
    );
  }
}

class _TwoUp extends StatelessWidget {
  const _TwoUp({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 520) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.sm),
            Expanded(child: children[i]),
          ],
        ]);
      });
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.label, required this.value, required this.options, required this.onChanged, required this.keyPrefix});
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final e in options.entries)
            KeyedSubtree(key: ValueKey('$keyPrefix.${e.key}'), child: AppChoiceChip(label: e.value, selected: value == e.key, onTap: () => onChanged(e.key))),
        ]),
      ]),
    );
  }
}

class _FileSlot extends StatelessWidget {
  const _FileSlot({
    required this.slotKey,
    required this.icon,
    required this.title,
    required this.help,
    required this.fileName,
    required this.bytes,
    required this.cameraAvailable,
    required this.onPick,
    this.onClear,
  });
  final String slotKey;
  final IconData icon;
  final String title;
  final String help;
  final String? fileName;
  final int? bytes;
  final bool cameraAvailable;
  final PickInto onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final picked = fileName != null;
    final r = BorderRadius.circular(AppRadius.card);
    return Container(
      key: ValueKey(slotKey),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: picked ? c.success.withValues(alpha: 0.06) : c.cardBg,
        borderRadius: r,
        border: Border.all(color: picked ? c.success.withValues(alpha: 0.6) : c.divider, width: picked ? 1.4 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: (picked ? c.success : c.primary).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.chip)),
            child: Icon(picked ? Icons.check_rounded : icon, color: picked ? c.success : c.primary),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: appText(15, w: FontWeight.w800, c: c.textDark)),
              const SizedBox(height: 2),
              Text(picked ? '$fileName · ${fileSizeLabel(bytes ?? 0)}' : help, style: appText(12.5, c: c.textMedium, h: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          OutlinedButton.icon(
            key: ValueKey('$slotKey.pick'),
            onPressed: () => onPick(camera: false),
            style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(picked ? t('تغيير الملف', 'Change file') : t('اختيار ملف (صورة أو PDF)', 'Choose a file (image or PDF)')),
          ),
          if (cameraAvailable)
            OutlinedButton.icon(
              key: ValueKey('$slotKey.camera'),
              onPressed: () => onPick(camera: true),
              style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: Text(t('التقاط صورة', 'Take a photo')),
            ),
          if (onClear != null)
            TextButton(
              key: ValueKey('$slotKey.clear'),
              onPressed: onClear,
              style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              child: Text(t('إزالة', 'Remove')),
            ),
        ]),
      ]),
    );
  }
}

/// While the worker job reads the scans: a calm sheet-shaped skeleton, never a spinner.
class LearnWaitingBody extends StatelessWidget {
  const LearnWaitingBody({super.key, required this.name, this.error, required this.onBack});
  final String name;
  final String? error;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LearnFrame(
      step: 0,
      title: t('نقرأ ورقتك…', 'Reading your sheet…'),
      subtitle: t('نبحث عن علامات الأركان، ثم أعمدة الإجابات والفقاعات ومنطقة رقم الطالب. يستغرق ذلك ثوانيَ عادةً — يمكنك البقاء هنا.',
          'We look for the corner marks, then the answer columns, the bubbles and the student ID zone. It usually takes a few seconds — you can stay here.'),
      error: error,
      backLabel: t('رجوع', 'Back'),
      onBack: onBack,
      body: AppCard(
        child: AppShimmer(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const AppSkeletonBox(width: 28, height: 28, radius: 6),
              const Spacer(),
              const AppSkeletonBox(width: 28, height: 28, radius: 6),
            ]),
            const SizedBox(height: AppSpace.md),
            for (var i = 0; i < 6; i++) ...[
              Row(children: [
                const AppSkeletonBox(width: 22, height: 12),
                const SizedBox(width: AppSpace.sm),
                for (var k = 0; k < 4; k++) ...[const AppSkeletonBox(width: 18, height: 18, radius: 9), const SizedBox(width: AppSpace.xs)],
              ]),
              const SizedBox(height: AppSpace.sm),
            ],
            const SizedBox(height: AppSpace.xs),
            Text(name, style: appText(13, w: FontWeight.w700, c: c.textMedium), textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

class LearnResultBody extends StatelessWidget {
  const LearnResultBody({
    super.key,
    required this.steps,
    required this.image,
    this.error,
    this.readOnly = false,
    this.published = false,
    this.version = 1,
    this.busy = false,
    this.onCheck,
    this.onReupload,
    this.onNewVersion,
    required this.onBack,
  });

  final TemplateSteps? steps;
  final Uint8List? image;
  final String? error;
  final bool readOnly;
  final bool published;
  final int version;
  final bool busy;
  final VoidCallback? onCheck;
  final VoidCallback? onReupload;
  final VoidCallback? onNewVersion;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = steps;
    final noPreview = s != null && !s.preview.available;
    final noQuestions = s != null && s.questions.isEmpty;
    final failed = s != null && s.failed;
    final blocked = failed || noPreview || noQuestions;
    return LearnFrame(
      step: 1,
      title: failed
          ? t('تعذّر تعلّم الورقة', 'The sheet could not be learned')
          : (s?.summary ?? t('اكتمل التعلّم', 'Learning finished')),
      subtitle: blocked
          ? t('لم نستطع رسم الفقاعات على الورقة. اتبع الإرشاد ثم ارفعها مرة أخرى.', 'We could not place the bubbles on the sheet. Follow the advice below, then upload it again.')
          : t('${omrQuestionsText(s?.questions.length ?? 0)}. ستراجع الآن كل سؤال على الورقة: ما اكتشفناه، وما ظُلّل في النموذج.',
              '${s?.questions.length ?? 0} questions. Now check each one on the sheet: what we found, and what the sample shows.'),
      error: error,
      backLabel: t('رجوع', 'Back'),
      onBack: onBack,
      primaryLabel: blocked ? (onReupload == null ? null : t('رفع الصور مرة أخرى', 'Upload again')) : (readOnly ? t('مراجعة الأسئلة', 'Walk the questions') : t('راجع كل سؤال', 'Check each question')),
      primaryIcon: blocked ? Icons.upload_file_rounded : Icons.fact_check_rounded,
      primaryKey: blocked ? 'omr.reupload' : 'omr.check',
      onPrimary: blocked ? onReupload : onCheck,
      body: s == null
          ? const AppListSkeleton(items: 3, padding: EdgeInsets.zero)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (published) ...[
                AppBanner(
                  icon: Icons.history_edu_rounded,
                  color: c.primary,
                  text: t('هذا الإصدار $version منشور ولا يُعدَّل. التعديل يُنشئ الإصدار ${version + 1}، وتبقى الاختبارات التي تستخدم الإصدار $version عليه.',
                      'Version $version is published and is not edited. Editing creates version ${version + 1}; exams that use version $version keep it.'),
                  action: onNewVersion == null ? null : TextButton(key: const ValueKey('omr.new_version'), onPressed: busy ? null : onNewVersion, child: Text(t('تعديل', 'Edit'))),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              if (!blocked)
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                  FactChip(icon: Icons.format_list_numbered_rounded, label: omrQuestionsText(s.questions.length)),
                  if (s.identifier.present) FactChip(icon: Icons.badge_outlined, label: omrIdKindLabel(s.identifier.kind)),
                  if (s.form.forms.isNotEmpty) FactChip(icon: Icons.layers_outlined, label: t('النماذج ${s.form.forms.join('، ')}', 'Models ${s.form.forms.join(', ')}')),
                ]),
              if (image != null) ...[
                const SizedBox(height: AppSpace.md),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      child: DecoratedBox(
                        decoration: BoxDecoration(border: Border.all(color: c.divider)),
                        child: Image.memory(image!, fit: BoxFit.contain, semanticLabel: t('الورقة الفارغة', 'The blank sheet')),
                      ),
                    ),
                  ),
                ),
              ],
              if (s.warnings.isNotEmpty) ...[
                const SizedBox(height: AppSpace.lg),
                AppSectionTitle(t('ملاحظات', 'Notes'), subtitle: t('كل ملاحظة ومعها ما تفعله', 'Each with what to do')),
                const SizedBox(height: AppSpace.xs),
                for (final w in s.warnings) IssueTile(issue: w, warning: true),
              ],
            ]),
    );
  }
}

/// A warning / an error with its fix underneath.
class IssueTile extends StatelessWidget {
  const IssueTile({super.key, required this.issue, this.warning = false, this.onOpen});
  final OmrIssue issue;
  final bool warning;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = warning ? c.warning : c.danger;
    final fix = issue.fix;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(warning ? Icons.info_outline_rounded : Icons.error_outline_rounded, color: col, size: 20),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(issue.text, style: appText(13.5, w: FontWeight.w700, c: c.textDark, h: 1.4)),
              if (fix != null) ...[
                const SizedBox(height: 2),
                Text(fix, style: appText(12.5, c: c.textMedium, h: 1.4)),
              ],
            ]),
          ),
          if (onOpen != null)
            TextButton(onPressed: onOpen, style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)), child: Text(t('فتح', 'Open'))),
        ]),
      ),
    );
  }
}

// ── the step-through ──

class StepThroughView extends StatelessWidget {
  const StepThroughView({
    super.key,
    required this.steps,
    required this.items,
    required this.index,
    required this.blankImage,
    required this.filledImage,
    required this.showFilled,
    required this.editing,
    required this.moveAll,
    required this.draft,
    required this.selected,
    required this.idColumn,
    required this.identifierChecked,
    required this.formChecked,
    required this.canEdit,
    this.published = false,
    this.version = 1,
    required this.busy,
    this.error,
    this.overlayKey,
    required this.onShowFilled,
    required this.onBack,
    required this.onNext,
    required this.onConfirm,
    this.onConfirmClear,
    required this.onJump,
    required this.onEdit,
    required this.onCancelEdit,
    required this.onSaveEdit,
    required this.onMoveAll,
    required this.onSelect,
    required this.onDraft,
    required this.onIdColumn,
    this.onNewVersion,
    required this.onFinish,
  });

  final TemplateSteps steps;
  final List<StepItem> items;
  final int index;
  final Uint8List? blankImage;
  final Uint8List? filledImage;
  final bool showFilled;
  final bool editing;
  final bool moveAll;
  final List<OmrBubble>? draft;
  final int? selected;
  final int idColumn;
  final bool identifierChecked;
  final bool formChecked;
  final bool canEdit;
  final bool published;
  final int version;
  final bool busy;
  final String? error;
  final GlobalKey<SheetOverlayState>? overlayKey;
  final ValueChanged<bool> onShowFilled;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onConfirm;
  final VoidCallback? onConfirmClear;
  final ValueChanged<int> onJump;
  final VoidCallback onEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onSaveEdit;
  final ValueChanged<bool> onMoveAll;
  final ValueChanged<int> onSelect;
  final ValueChanged<List<OmrBubble>> onDraft;
  final ValueChanged<int> onIdColumn;
  final VoidCallback? onNewVersion;
  final VoidCallback onFinish;

  StepItem? get _item => items.isEmpty ? null : items[index];

  List<OmrBubble> _all() => [
        for (final q in steps.questions) ...q.bubbles,
        for (final col in steps.identifier.columns) ...col,
        ...steps.form.bubbles,
      ];

  /// (current boxes, filled labels, zone, others)
  (List<OmrBubble>, Set<String>, Rect?, List<OmrBubble>) _layers() {
    final item = _item;
    final s = steps;
    switch (item) {
      case QuestionItem(:final n):
        final q = s.question(n);
        final cur = draft ?? q?.bubbles ?? const <OmrBubble>[];
        final others = [
          for (final o in s.questions)
            if (o.n != n) ...o.bubbles,
          for (final col in s.identifier.columns) ...col,
          ...s.form.bubbles,
        ];
        return (cur, {...?q?.filled}, null, others);
      case IdentifierItem():
        final id = s.identifier;
        if (editing && id.columns.isNotEmpty) {
          final col = draft ?? id.columns[idColumn.clamp(0, id.columns.length - 1)];
          final others = [for (final b in _all()) if (!col.any((x) => x.label == b.label && (x.cx - b.cx).abs() < 1e-6 && (x.cy - b.cy).abs() < 1e-6)) b];
          return (col, const <String>{}, null, others);
        }
        // the digits read from the filled sample, one bubble per column, drawn as marks over the whole grid
        final read = id.read ?? '';
        final cur = <OmrBubble>[];
        for (var i = 0; i < id.columns.length && i < read.length; i++) {
          final d = read[i];
          for (final b in id.columns[i]) {
            if (b.label == d) cur.add(b);
          }
        }
        final others = [for (final b in _all()) if (!cur.contains(b)) b];
        return (cur, {for (final b in cur) b.label}, id.zoneMm, others);
      case FormRowItem():
        final cur = draft ?? s.form.bubbles;
        final others = [for (final q in s.questions) ...q.bubbles, for (final col in s.identifier.columns) ...col];
        Rect? z;
        for (final b in cur) {
          final r = Rect.fromCircle(center: Offset(b.cx, b.cy), radius: b.r);
          z = z == null ? r : z.expandToInclude(r);
        }
        return (cur, {?s.form.readValue}, editing ? null : z?.inflate(1.5), others);
      case null:
        return (const [], const {}, null, const []);
    }
  }

  /// The current step's boxes as the server has them (not the draft).
  List<OmrBubble> _baseBubbles() => switch (_item) {
        QuestionItem(:final n) => steps.question(n)?.bubbles ?? const [],
        IdentifierItem() => steps.identifier.columns.isEmpty ? const [] : steps.identifier.columns[idColumn.clamp(0, steps.identifier.columns.length - 1)],
        FormRowItem() => steps.form.bubbles,
        null => const [],
      };

  Rect? _focusMm(List<OmrBubble> cur, Rect? zone) {
    if (zone != null) return zone;
    Rect? u;
    for (final b in cur) {
      final r = Rect.fromCircle(center: Offset(b.cx, b.cy), radius: b.r);
      u = u == null ? r : u.expandToInclude(r);
    }
    return u?.inflate(3);
  }

  @override
  Widget build(BuildContext context) {
    final g = steps.preview.geometry!;
    final (cur, filled, zone, others) = _layers();
    // while fixing, the view stays where the boxes were (a drag never moves the page under the pointer)
    final focusMm = editing ? _focusMm(_baseBubbles(), null) : _focusMm(cur, zone);
    final overlay = SheetOverlay(
      key: overlayKey,
      image: showFilled ? (filledImage ?? blankImage) : blankImage,
      geometry: g,
      others: others,
      current: cur,
      filled: filled,
      zoneMm: zone,
      focusMm: focusMm,
      editing: editing,
      moveAll: moveAll,
      selected: selected,
      onSelect: onSelect,
      onChanged: onDraft,
      semanticLabel: _title(),
    );
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final panel = _Panel(view: this, wide: wide);
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(AppSpace.md), child: overlay)),
          SizedBox(width: 400, child: panel),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _TopLine(view: this),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm), child: overlay)),
        panel,
      ]);
    });
  }

  String _title() => switch (_item) {
        QuestionItem(:final n) => t('السؤال $n من ${steps.questions.length}', 'Question $n of ${steps.questions.length}'),
        IdentifierItem() => t('منطقة رقم الطالب', 'Student ID zone'),
        FormRowItem() => t('صف النموذج', 'Model row'),
        null => '',
      };

  String _prompt() => switch (_item) {
        QuestionItem(:final n) => steps.question(n)?.prompt ?? '',
        IdentifierItem() => steps.identifier.prompt,
        FormRowItem() => steps.form.prompt,
        null => '',
      };

  bool get _confirmed => switch (_item) {
        QuestionItem(:final n) => steps.question(n)?.confirmed ?? false,
        IdentifierItem() => identifierChecked,
        FormRowItem() => formChecked,
        null => false,
      };

  bool get _editable => canEdit && switch (_item) {
        QuestionItem() => true,
        IdentifierItem() => steps.identifier.columns.isNotEmpty,
        FormRowItem() => steps.form.hasRow,
        null => false,
      };

  bool get _last => index >= items.length - 1;
}

class _TopLine extends StatelessWidget {
  const _TopLine({required this.view});
  final StepThroughView view;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = view.steps;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.xs, AppSpace.xs),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(view._title(), style: appText(15, w: FontWeight.w800, c: c.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(t('أُكّد ${s.confirmedCount} من ${s.questions.length}', '${s.confirmedCount} of ${s.questions.length} confirmed'),
                style: appText(12, c: c.textMedium), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (view.filledImage != null) _ImageToggle(view: view),
        IconButton(
          key: const ValueKey('omr.jump'),
          tooltip: t('الانتقال إلى سؤال', 'Jump to a question'),
          constraints: const BoxConstraints.tightFor(width: AppTouch.min, height: AppTouch.min),
          onPressed: view.editing ? null : () => _openJump(context, view),
          icon: const Icon(Icons.grid_view_rounded),
        ),
      ]),
    );
  }
}

Future<void> _openJump(BuildContext context, StepThroughView view) async {
  final i = await showAppSheet<int>(
    context,
    (ctx) => Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(t('الانتقال إلى', 'Jump to'), style: appText(18, w: FontWeight.w800, c: ctx.colors.textDark)),
          const SizedBox(height: AppSpace.sm),
          JumpGrid(view: view, onPick: (i) => Navigator.of(ctx).pop(i)),
        ]),
      ),
    ),
  );
  if (i != null) view.onJump(i);
}

/// Every stop as a numbered chip: green = confirmed, red = a problem names it, outlined = where you are.
class JumpGrid extends StatelessWidget {
  const JumpGrid({super.key, required this.view, required this.onPick});
  final StepThroughView view;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = view.steps;
    Widget chip(int i, String label, {required bool done, required bool problem, required String semantics}) {
      final current = i == view.index;
      final col = problem ? c.danger : (done ? c.success : c.textMedium);
      return Semantics(
        button: true,
        selected: current,
        label: semantics,
        child: Material(
          color: done ? c.success.withValues(alpha: 0.12) : (problem ? c.danger.withValues(alpha: 0.08) : c.cardBg),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.chip), side: BorderSide(color: current ? c.primary : col.withValues(alpha: 0.4), width: current ? 2 : 1)),
          child: InkWell(
            key: ValueKey('omr.jump.$i'),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            onTap: () => onPick(i),
            child: SizedBox(
              width: AppTouch.min,
              height: AppTouch.min,
              child: Center(child: ExcludeSemantics(child: Text(label, style: appText(13, w: FontWeight.w800, c: current ? c.primary : col)))),
            ),
          ),
        ),
      );
    }

    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      for (var i = 0; i < view.items.length; i++)
        switch (view.items[i]) {
          QuestionItem(:final n) => chip(i, '$n',
              done: s.question(n)?.confirmed ?? false,
              problem: (s.question(n)?.problems.isNotEmpty ?? false) || (s.question(n)?.stateNote != null),
              semantics: t('السؤال $n', 'Question $n')),
          IdentifierItem() => chip(i, 'ID', done: view.identifierChecked, problem: false, semantics: t('منطقة رقم الطالب', 'Student ID zone')),
          FormRowItem() => chip(i, t('ن', 'M'), done: view.formChecked, problem: false, semantics: t('صف النموذج', 'Model row')),
        },
    ]);
  }
}

class _ImageToggle extends StatelessWidget {
  const _ImageToggle({required this.view});
  final StepThroughView view;

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpace.xxs, children: [
        KeyedSubtree(
          key: const ValueKey('omr.image.filled'),
          child: AppChoiceChip(label: t('المظلّل', 'Filled'), selected: view.showFilled, onTap: () => view.onShowFilled(true)),
        ),
        KeyedSubtree(
          key: const ValueKey('omr.image.blank'),
          child: AppChoiceChip(label: t('الفارغ', 'Blank'), selected: !view.showFilled, onTap: () => view.onShowFilled(false)),
        ),
      ]);
}

class _Panel extends StatelessWidget {
  const _Panel({required this.view, required this.wide});
  final StepThroughView view;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = view;
    final s = v.steps;
    final item = v._item;
    final q = item is QuestionItem ? s.question(item.n) : null;
    final note = q?.stateNote;
    final text = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (wide) ...[
        Text(v._title(), style: appText(13, w: FontWeight.w800, c: c.textMedium)),
        const SizedBox(height: AppSpace.xs),
        AppProgressBar(value: s.questions.isEmpty ? 0 : s.confirmedCount / s.questions.length),
        const SizedBox(height: AppSpace.xxs),
        Text(t('أُكّد ${s.confirmedCount} من ${s.questions.length}', '${s.confirmedCount} of ${s.questions.length} confirmed'), style: appText(12, c: c.textMedium)),
        const SizedBox(height: AppSpace.md),
      ],
      if (v.published && v.onNewVersion != null) ...[
        AppBanner(
          icon: Icons.history_edu_rounded,
          color: c.primary,
          text: t('الإصدار ${v.version} منشور ولا يُعدَّل. التعديل يُنشئ الإصدار ${v.version + 1}.', 'Version ${v.version} is published and is not edited. Editing creates version ${v.version + 1}.'),
          action: TextButton(key: const ValueKey('omr.new_version'), onPressed: v.busy ? null : v.onNewVersion, child: Text(t('تعديل', 'Edit'))),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
      if (s.recalibrating) ...[
        AppBanner(icon: Icons.straighten_rounded, color: c.primary, text: t('نعيد قياس المربعات المعدّلة…', 'Re-measuring the corrected boxes…')),
        const SizedBox(height: AppSpace.sm),
      ],
      if (v.error != null) ...[
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: v.error!),
        const SizedBox(height: AppSpace.sm),
      ],
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Text(v.editing ? _editTitle() : v._prompt(), key: const ValueKey('omr.prompt'), style: appText(wide ? 18 : 16, w: FontWeight.w800, c: c.textDark, h: 1.4)),
        ),
        if (v._confirmed && !v.editing) ...[
          const SizedBox(width: AppSpace.xs),
          AppBadgePill(t('مؤكَّد', 'Confirmed'), color: c.success, icon: Icons.check_rounded),
        ],
      ]),
      if (v.editing) ...[
        const SizedBox(height: AppSpace.xs),
        Text(
            t('اسحب الفقاعة لتحريكها، واسحب مقبضها لتغيير حجمها. على لوحة المفاتيح: الأسهم تحرّك 0.1 مم (مع Shift ‏1 مم)، Enter للحفظ، Esc للإلغاء.',
                'Drag a bubble to move it, drag its handle to resize it. On a keyboard: arrows move 0.1 mm (Shift: 1 mm), Enter saves, Esc cancels.'),
            style: appText(12.5, c: c.textMedium, h: 1.45)),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          KeyedSubtree(key: const ValueKey('omr.edit.one'), child: AppChoiceChip(label: t('فقاعة واحدة', 'One bubble'), selected: !v.moveAll, onTap: () => v.onMoveAll(false))),
          KeyedSubtree(key: const ValueKey('omr.edit.all'), child: AppChoiceChip(label: t('السؤال كله', 'Whole question'), selected: v.moveAll, onTap: () => v.onMoveAll(true))),
        ]),
        if (!v.moveAll && v.draft != null) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (var i = 0; i < v.draft!.length; i++)
              KeyedSubtree(key: ValueKey('omr.edit.bubble.$i'), child: AppChoiceChip(label: v.draft![i].label, selected: v.selected == i, onTap: () => v.onSelect(i))),
          ]),
        ],
      ],
      if (item is IdentifierItem && s.identifier.columns.isNotEmpty && v.editing) ...[
        const SizedBox(height: AppSpace.sm),
        Text(t('عمود الرقم الذي تعدّله', 'The ID column to fix'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (var i = 0; i < s.identifier.columns.length; i++)
            KeyedSubtree(key: ValueKey('omr.id_column.$i'), child: AppChoiceChip(label: '${i + 1}', selected: v.idColumn == i, onTap: () => v.onIdColumn(i))),
        ]),
      ],
      if (note != null && !v.editing) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: note),
      ],
      if (q != null && !v.editing)
        for (final p in q.problems) ...[const SizedBox(height: AppSpace.xs), IssueTile(issue: p)],
      if (wide && !v.editing) ...[
        const SizedBox(height: AppSpace.lg),
        Row(children: [
          Expanded(child: Text(t('الانتقال إلى', 'Jump to'), style: appText(13, w: FontWeight.w800, c: c.textMedium))),
          if (v.filledImage != null) _ImageToggle(view: v),
        ]),
        const SizedBox(height: AppSpace.xs),
        JumpGrid(view: v, onPick: v.onJump),
      ],
      if (v.onConfirmClear != null && !v.editing) ...[
        const SizedBox(height: AppSpace.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('omr.confirm_clear'),
            onPressed: v.busy ? null : v.onConfirmClear,
            style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: Text(t('تأكيد الأسئلة الواضحة (${s.clearUnconfirmed.length})', 'Confirm the clear ones (${s.clearUnconfirmed.length})')),
          ),
        ),
      ],
    ]);

    final actions = _actions(context);
    final body = wide
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(AppSpace.md), child: text)),
            actions,
          ])
        : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
              child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xs), child: text),
            ),
            actions,
          ]);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.cardBg,
        border: wide ? BorderDirectional(start: BorderSide(color: c.divider)) : Border(top: BorderSide(color: c.divider)),
      ),
      child: body,
    );
  }

  String _editTitle() => switch (view._item) {
        QuestionItem(:final n) => t('تصحيح مربعات السؤال $n', 'Fix the boxes of question $n'),
        IdentifierItem() => t('تصحيح العمود ${view.idColumn + 1} من رقم الطالب', 'Fix column ${view.idColumn + 1} of the student ID'),
        FormRowItem() => t('تصحيح صف النموذج', 'Fix the model row'),
        null => '',
      };

  Widget _actions(BuildContext context) {
    final c = context.colors;
    final v = view;
    final pad = const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.sm);
    if (v.editing) {
      return Padding(
        padding: pad,
        child: Row(children: [
          TextButton(
            key: const ValueKey('omr.edit.cancel'),
            onPressed: v.busy ? null : v.onCancelEdit,
            style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: KeyedSubtree(
              key: const ValueKey('omr.edit.save'),
              child: AppPrimaryButton(label: t('حفظ التصحيح', 'Save the fix'), icon: Icons.save_rounded, busy: v.busy, onPressed: v.busy ? null : v.onSaveEdit),
            ),
          ),
        ]),
      );
    }
    final canConfirm = v.canEdit && !v._confirmed;
    final primaryLabel = canConfirm ? t('نعم، صحيح', 'Yes, correct') : (v._last ? t('إلى الحفظ', 'To saving') : t('التالي', 'Next'));
    // a narrow phone: Fix is an icon (with its tooltip) and the primary has no icon, so the label always fits
    final compact = MediaQuery.sizeOf(context).width < 420;
    return Padding(
      padding: pad,
      child: Row(children: [
        IconButton(
          key: const ValueKey('omr.step.back'),
          tooltip: t('السابق', 'Back'),
          onPressed: v.busy ? null : v.onBack,
          constraints: const BoxConstraints.tightFor(width: AppTouch.min, height: AppTouch.min),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        if (v._editable && compact)
          IconButton(
            key: const ValueKey('omr.fix'),
            tooltip: t('تصحيح المربعات', 'Fix the boxes'),
            onPressed: v.busy ? null : v.onEdit,
            constraints: const BoxConstraints.tightFor(width: AppTouch.min, height: AppTouch.min),
            icon: Icon(Icons.open_with_rounded, color: c.primary),
          )
        else if (v._editable)
          TextButton.icon(
            key: const ValueKey('omr.fix'),
            onPressed: v.busy ? null : v.onEdit,
            style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            icon: Icon(Icons.open_with_rounded, size: 18, color: c.primary),
            label: Text(t('تصحيح', 'Fix')),
          ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: KeyedSubtree(
            key: const ValueKey('omr.step.primary'),
            child: AppPrimaryButton(label: primaryLabel, icon: canConfirm && !compact ? Icons.check_rounded : null, busy: v.busy, onPressed: v.busy ? null : v.onConfirm),
          ),
        ),
        IconButton(
          key: const ValueKey('omr.step.next'),
          tooltip: v._last ? t('إلى الحفظ', 'To saving') : t('التالي دون تأكيد', 'Next without confirming'),
          onPressed: v.busy ? null : (v._last ? v.onFinish : v.onNext),
          constraints: const BoxConstraints.tightFor(width: AppTouch.min, height: AppTouch.min),
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ]),
    );
  }
}

// ── save, done ──

class LearnSaveBody extends StatelessWidget {
  const LearnSaveBody({
    super.key,
    required this.steps,
    required this.validation,
    required this.checking,
    required this.isSuperAdmin,
    this.readOnly = false,
    required this.status,
    required this.version,
    this.busy = false,
    this.error,
    required this.onBack,
    required this.onOpenQuestion,
    required this.onSubmit,
    required this.onApprove,
    required this.onReject,
    this.onNewVersion,
  });

  final TemplateSteps? steps;
  final TemplateValidation? validation;
  final bool checking;
  final bool isSuperAdmin;
  final bool readOnly;
  final String status;
  final int version;
  final bool busy;
  final String? error;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenQuestion;
  final VoidCallback onSubmit;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback? onNewVersion;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = validation;
    final review = readOnly && status == 'pending_approval';
    final editable = status == 'draft' || status == 'rejected';
    final ok = v?.ok ?? false;
    String? primary;
    VoidCallback? onPrimary;
    IconData? icon;
    if (review) {
      primary = t('اعتماد ونشر', 'Approve and publish');
      onPrimary = busy ? null : onApprove;
      icon = Icons.verified_rounded;
    } else if (editable && !readOnly) {
      primary = isSuperAdmin ? t('حفظ ونشر الإصدار $version', 'Save and publish version $version') : t('حفظ وإرسال', 'Save and submit');
      onPrimary = busy || checking || !ok ? null : onSubmit;
      icon = isSuperAdmin ? Icons.publish_rounded : Icons.send_rounded;
    }
    return LearnFrame(
      step: 2,
      title: review
          ? t('اعتماد هذا النوع؟', 'Approve this sheet type?')
          : (checking ? t('نفحص الورقة…', 'Checking the sheet…') : (ok ? t('الورقة جاهزة', 'The sheet is ready') : t('بقيت أشياء قبل الحفظ', 'A few things before saving'))),
      subtitle: review
          ? t('بعد الاعتماد يختاره كل المعلمين لاختبارات أوراق التظليل.', 'Once approved, every teacher can choose it for bubble-sheet exams.')
          : (isSuperAdmin
              ? t('يُنشر الإصدار $version فور الحفظ ويظهر لكل المعلمين.', 'Version $version is published as soon as you save it, for every teacher.')
              : t('يُرسل لمشرف المنصة ليعتمده، أو يُنشر مباشرة إن لم يكن الاعتماد مطلوبًا.', 'It goes to a platform admin for approval, or straight to the list when approval is not required.')),
      error: error,
      backLabel: t('رجوع للمراجعة', 'Back to checking'),
      onBack: onBack,
      primaryLabel: primary,
      primaryIcon: icon,
      primaryKey: review ? 'omr.approve' : 'omr.submit',
      busy: busy,
      onPrimary: onPrimary,
      secondary: review
          ? TextButton(
              key: const ValueKey('omr.reject'),
              onPressed: busy ? null : onReject,
              style: TextButton.styleFrom(foregroundColor: c.danger, minimumSize: const Size(AppTouch.min, AppTouch.min)),
              child: Text(t('رفض', 'Reject')))
          : null,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (steps != null)
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            FactChip(icon: Icons.task_alt_rounded, label: t('أُكّد ${steps!.confirmedCount} من ${steps!.questions.length}', '${steps!.confirmedCount} of ${steps!.questions.length} confirmed')),
            if (steps!.summary != null) FactChip(icon: Icons.crop_free_rounded, label: steps!.summary!),
          ]),
        const SizedBox(height: AppSpace.md),
        if (!editable && !review && !readOnly) ...[
          AppBanner(
            icon: Icons.history_edu_rounded,
            color: c.primary,
            text: t('هذا الإصدار ${omrStatusLabel(status)}. التعديل يُنشئ الإصدار ${version + 1}.', 'This version is ${omrStatusLabel(status).toLowerCase()}. Editing creates version ${version + 1}.'),
            action: onNewVersion == null ? null : TextButton(onPressed: busy ? null : onNewVersion, child: Text(t('تعديل', 'Edit'))),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (checking)
          const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero)
        else if (v != null) ...[
          if (v.ok)
            AppBanner(icon: Icons.verified_rounded, color: c.success, text: t('اجتازت الورقة كل الفحوص: العلامات والأعداد والتداخل والمناطق.', 'The sheet passed every check: marks, counts, overlaps and zones.')),
          for (final e in v.errors)
            IssueTile(issue: e, onOpen: e.question != null ? () => onOpenQuestion(e.question!) : (e.code == 'questions_unconfirmed' && e.numbers.isNotEmpty ? () => onOpenQuestion(e.numbers.first) : null)),
          if (v.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            AppSectionTitle(t('ملاحظات', 'Notes')),
            const SizedBox(height: AppSpace.xs),
            for (final w in v.warnings) IssueTile(issue: w, warning: true),
          ],
        ],
      ]),
    );
  }
}

class LearnDoneBody extends StatelessWidget {
  const LearnDoneBody({super.key, required this.row, required this.onDone});
  final OmrTemplateRow row;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, color, title, body) = switch (row.status) {
      'published' => (
          Icons.verified_rounded,
          c.success,
          t('نُشر الإصدار ${row.version}', 'Version ${row.version} is published'),
          t('يختاره المعلمون الآن لاختبارات أوراق التظليل.', 'Teachers can choose it for bubble-sheet exams now.'),
        ),
      'pending_approval' => (
          Icons.hourglass_top_rounded,
          c.warning,
          t('أُرسل للاعتماد', 'Sent for approval'),
          t('يراجعه مشرف المنصة، ويظهر في قائمة الأوراق عند اعتماده.', 'A platform admin reviews it; it shows in the sheet list once approved.'),
        ),
      'rejected' => (
          Icons.block_rounded,
          c.danger,
          t('رُفض الإصدار ${row.version}', 'Version ${row.version} was rejected'),
          row.reviewNote == null ? t('يرى صاحبه السبب ويعدّله.', 'Its owner sees the reason and fixes it.') : t('السبب: ${row.reviewNote}', 'Reason: ${row.reviewNote}'),
        ),
      _ => (Icons.check_circle_rounded, c.primary, omrStatusLabel(row.status), ''),
    };
    return LearnFrame(
      step: 2,
      title: title,
      subtitle: body.isEmpty ? null : body,
      primaryLabel: t('تم', 'Done'),
      primaryKey: 'omr.done',
      onPrimary: onDone,
      body: Center(
        child: Container(
          key: ValueKey('omr.done.${row.status}'),
          width: 96,
          height: 96,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 48),
        ),
      ),
    );
  }
}

/// A small fact (icon + text) that wraps instead of overflowing on a narrow phone.
class FactChip extends StatelessWidget {
  const FactChip({super.key, required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, 6, AppSpace.sm, 6),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: col.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: col),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: appText(12.5, w: FontWeight.w700, c: c.textDark))),
      ]),
    );
  }
}
