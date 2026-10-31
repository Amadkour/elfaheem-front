// lib/features/shared/certificates_issue/cert_issue_flow.dart
//
// "Issue certificates" from a design — one guided flow (D-132 on the server side, routers/certificate_issue_router.py):
//
//   1 How      Link to a course (pick one of my / the organization's courses; the server issues to its active
//              students — today's behaviour, mode=course) or Standalone (no course).
//   2 Who      standalone only: Search students · Paste a list · Upload a sheet, all landing in ONE review list
//              (matched / several with the name → pick / not on the platform → manual recipient / duplicates /
//              problems highlighted, inline edit or remove, "X ready, Y need attention"). Save the list, or open a
//              saved one. Optional e-mail delivery adds an Email column.
//   3 Preview  languages from the design, an optional title, the first recipient's certificate per language.
//   4 Issue    the batch's progress (EventOrPoll: no live event exists for batches, so a gentle poll), then
//              download the ZIP / merged PDF and open the issued list.
//
// Phones: one column, the step's actions in a bottom bar. Wide: the recipients step is input | review side by side.
// Entry: openCertIssueFlow(context, designId: …, designName: …, orgId: …) — the designs library's card menu.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/live/event_wait.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_notice.dart';
import '../../../design/app_tokens.dart';
import '../../../utils/widget/parent_component.dart';
import 'cert_issue_actions.dart';
import 'cert_issue_api.dart';
import 'cert_issue_history.dart';
import 'cert_issue_lists.dart';
import 'cert_issue_logic.dart';
import 'cert_issue_parts.dart';

Future<void> openCertIssueFlow(BuildContext context, {required int designId, String? designName, int? orgId}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CertIssueFlowPage(designId: designId, designName: designName, orgId: orgId),
    ));

class CertIssueFlowPage extends StatefulWidget {
  const CertIssueFlowPage({super.key, required this.designId, this.designName, this.orgId, this.api});

  final int designId;
  final String? designName;
  final int? orgId;
  final CertIssueApi? api;

  @override
  State<CertIssueFlowPage> createState() => _CertIssueFlowPageState();
}

class _CertIssueFlowPageState extends State<CertIssueFlowPage> {
  late final CertIssueApi _api = widget.api ?? CertIssueApi();

  static const _wide = 980.0;

  int _step = 0;
  IssueMode? _mode;

  // template
  IssueTemplate? _template;
  IssueTemplate? _courseTemplate;
  bool _templateLoading = true;
  String? _templateError;
  bool _withEmail = false;

  // course mode
  List<IssueCourse> _courses = const [];
  bool _coursesLoading = false;
  bool _coursesLoaded = false;
  String? _coursesError;
  int? _courseId;
  final Map<String, TextEditingController> _constants = {};
  bool _courseEmail = false;

  /// The course certificate each picked course's batch is recorded under (null = the course has none to use).
  final Map<int, int?> _courseCerts = {};
  bool _replaceExisting = false;

  // recipients
  final RecipientDraft _draft = RecipientDraft();
  RecipientTab _tab = RecipientTab.paste;
  ReviewFilter _filter = ReviewFilter.all;

  final _pasteCtrl = TextEditingController();
  Timer? _pasteDebounce;
  int _pasteGen = 0;
  bool _pasteChecking = false;
  String? _pasteError;
  int? _pasteCount;

  String? _fileName;
  Uint8List? _fileBytes;
  bool _uploadBusy = false;
  String? _uploadError;
  int? _uploadCount;

  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  int _searchGen = 0;
  bool _searchStarted = false;
  bool _searchLoading = false;
  String? _searchError;
  List<StudentBrief> _results = const [];
  int? _searchTotal;
  int? _searchCourseId;

  // preview / options
  Set<String> _langs = {};
  final _titleCtrl = TextEditingController();
  Map<String, Uint8List> _images = const {};
  bool _previewLoading = false;
  String? _previewError;
  String _previewLang = AppConfig.lang;

  // batch
  IssueBatch? _batch;
  bool _issuing = false;
  EventOrPoll? _watch;
  String? _downloading;

  List<String> get _stepLabels => ['ci_step_how'.tr, 'ci_step_who'.tr, 'ci_step_preview'.tr, 'ci_step_issue'.tr];

  @override
  void initState() {
    super.initState();
    _loadTemplate();
  }

  @override
  void dispose() {
    _pasteDebounce?.cancel();
    _searchDebounce?.cancel();
    _watch?.dispose();
    _pasteCtrl.dispose();
    _searchCtrl.dispose();
    _titleCtrl.dispose();
    for (final c in _constants.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── loading ────────────────────────────────────────────────────────────────

  Future<void> _loadTemplate() async {
    setState(() {
      _templateLoading = true;
      _templateError = null;
    });
    try {
      final t = await _api.columns(widget.designId, withEmail: _withEmail, orgId: widget.orgId);
      if (!mounted) return;
      setState(() {
        _template = t;
        _draft.columns = t.columns;
        for (final c in t.extraColumns) {
          _constants.putIfAbsent(c.key, TextEditingController.new);
        }
        if (_langs.isEmpty || !_langs.every(t.langs.contains)) _langs = t.langs.toSet();
        _templateLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _templateError = certIssueErrorText(e);
        _templateLoading = false;
      });
    }
  }

  Future<void> _loadCourses() async {
    if (_coursesLoading) return;
    setState(() {
      _coursesLoading = true;
      _coursesError = null;
    });
    try {
      final list = await _api.courses(orgId: widget.orgId);
      if (!mounted) return;
      setState(() {
        _courses = list;
        _coursesLoaded = true;
        _coursesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _coursesError = certIssueErrorText(e);
        _coursesLoading = false;
      });
    }
  }

  /// The course certificate a batch for [courseId] is recorded under (loaded once per course; null when the course
  /// has none for this design or the load fails — the batch then goes out without it, as before).
  Future<int?> _courseCertificate(int courseId) async {
    if (_courseCerts.containsKey(courseId)) return _courseCerts[courseId];
    try {
      final certs = await _api.courseCertificates(courseId);
      final id = certCourseCertificateFor(certs, widget.designId);
      if (mounted) setState(() => _courseCerts[courseId] = id);
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCourseTemplate() async {
    if (_courseTemplate != null) return;
    try {
      final t = await _api.columns(widget.designId, mode: IssueMode.course, orgId: widget.orgId);
      if (!mounted) return;
      setState(() {
        _courseTemplate = t;
        for (final c in t.extraColumns) {
          _constants.putIfAbsent(c.key, TextEditingController.new);
        }
      });
    } catch (_) {
      // the constants are optional: without the columns the course is still issued with the server's values
    }
  }

  void _setMode(IssueMode m) {
    setState(() => _mode = m);
    if (m == IssueMode.course) {
      if (!_coursesLoaded) _loadCourses();
      _loadCourseTemplate();
    }
  }

  // ── recipients: paste / upload / search ────────────────────────────────────

  void _onPaste(String text) {
    _pasteDebounce?.cancel();
    _pasteDebounce = Timer(const Duration(milliseconds: 700), () => _checkPaste(text));
  }

  Future<void> _checkPaste(String text) async {
    final gen = ++_pasteGen;
    if (text.trim().isEmpty) {
      setState(() {
        _draft.addChecked(const {'rows': []}, source: RowSource.paste);
        _pasteCount = null;
        _pasteError = null;
        _pasteChecking = false;
      });
      return;
    }
    setState(() {
      _pasteChecking = true;
      _pasteError = null;
    });
    try {
      final r = await _api.checkText(widget.designId, text, orgId: widget.orgId, withEmail: _withEmail);
      if (!mounted || gen != _pasteGen) return;
      setState(() {
        _pasteCount = _draft.addChecked(r, source: RowSource.paste);
        _pasteChecking = false;
      });
    } catch (e) {
      if (!mounted || gen != _pasteGen) return;
      setState(() {
        _pasteError = certIssueErrorText(e);
        _pasteChecking = false;
      });
    }
  }

  Future<void> _pickFile() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx', 'csv']);
    if (f == null || !mounted) return;
    Uint8List bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (_) {
      setState(() => _uploadError = 'ci_file_unreadable'.tr);
      return;
    }
    final max = _template?.maxUploadBytes ?? 5242880;
    if (bytes.length > max) {
      setState(() => _uploadError = 'ci_file_too_big'.tr);
      return;
    }
    _fileName = f.name;
    _fileBytes = bytes;
    await _checkFile();
  }

  Future<void> _checkFile() async {
    final bytes = _fileBytes;
    final name = _fileName;
    if (bytes == null || name == null) return;
    setState(() {
      _uploadBusy = true;
      _uploadError = null;
    });
    try {
      final r = await _api.checkFile(widget.designId, name, bytes, orgId: widget.orgId, withEmail: _withEmail);
      if (!mounted) return;
      setState(() {
        _uploadCount = _draft.addChecked(r, source: RowSource.file);
        _uploadBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadError = certIssueErrorText(e);
        _uploadBusy = false;
      });
    }
  }

  Future<void> _sample(String fmt) async {
    try {
      final bytes = await _api.sample(widget.designId, fmt: fmt, lang: AppConfig.lang, withEmail: _withEmail, orgId: widget.orgId);
      final base = (widget.designName ?? 'certificates').trim();
      await certSaveFile('$base - ${'ci_sample_file'.tr}', bytes, fmt);
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
  }

  void _openTab(RecipientTab t) {
    setState(() => _tab = t);
    if (t == RecipientTab.search && !_searchStarted) {
      _searchStarted = true;
      if (widget.orgId != null) {
        _runSearch();
      } else if (!_coursesLoaded) {
        _loadCourses();
      }
    }
  }

  void _onQuery(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), _runSearch);
  }

  Future<void> _runSearch() async {
    if (widget.orgId == null && _searchCourseId == null) return;
    final gen = ++_searchGen;
    setState(() {
      _searchLoading = true;
      _searchError = null;
    });
    try {
      final r = await _api.students(orgId: widget.orgId, courseId: _searchCourseId, q: _searchCtrl.text);
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _results = r.items;
        _searchTotal = r.total;
        _searchLoading = false;
      });
    } catch (e) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _searchError = certIssueErrorText(e);
        _searchLoading = false;
      });
    }
  }

  void _toggleStudent(StudentBrief s, bool on) => setState(() {
        if (on) {
          _draft.addStudents([s]);
        } else {
          _draft.removeStudent(s.id);
        }
      });

  void _selectAll() => setState(() {
        final allOn = _results.isNotEmpty && _results.every((s) => _draft.hasStudent(s.id));
        if (allOn) {
          for (final s in _results) {
            _draft.removeStudent(s.id);
          }
        } else {
          _draft.addStudents(_results);
        }
      });

  Future<void> _setWithEmail(bool v) async {
    setState(() => _withEmail = v);
    await _loadTemplate();
    if (_pasteCtrl.text.trim().isNotEmpty) await _checkPaste(_pasteCtrl.text);
    if (_fileBytes != null) await _checkFile();
  }

  // ── review actions ─────────────────────────────────────────────────────────

  Future<void> _editRow(RecipientRow row) async {
    final res = await certEditValues(context, title: 'ci_edit_row'.tr, columns: _draft.columns, initial: row.values);
    if (res == null || !mounted) return;
    setState(() {
      for (final e in res.values.entries) {
        if ((row.values[e.key] ?? '') != e.value) _draft.edit(row.uid, e.key, e.value);
      }
    });
    final now = _draft.byUid(row.uid);
    if (now != null && now.student == null && now.name.isNotEmpty && certNormalizeName(now.name) != certNormalizeName(row.name)) {
      _rematch(now.uid, now.name);
    }
  }

  /// A renamed row that matches nobody is looked up again by its new name (the organization's students, or the
  /// course picked in the search tab).
  Future<void> _rematch(String uid, String name) async {
    if (widget.orgId == null && _searchCourseId == null) return;
    try {
      final r = await _api.students(orgId: widget.orgId, courseId: _searchCourseId, q: name);
      if (mounted) setState(() => _draft.rematch(uid, name, r.items));
    } catch (_) {}
  }

  // ── saved lists ────────────────────────────────────────────────────────────

  Future<void> _saveList() async {
    final name = await certAskText(context, title: 'ci_save_list_title'.tr, label: 'ci_list_name'.tr,
        message: 'ci_save_list_sub'.tr);
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await _api.createList(certListBody(
          name: name, orgId: widget.orgId, designId: widget.designId, columns: _draft.columns, rows: _draft.listRows()));
      showAppNotice('ci_list_saved'.tr);
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
  }

  Future<void> _openList() async {
    final picked = await pickCertSavedList(context, api: _api, orgId: widget.orgId);
    if (picked == null || !mounted) return;
    try {
      final full = await _api.list(picked.id);
      if (!mounted) return;
      setState(() => _draft.addListRows(full.rows));
      showAppNotice('ci_list_loaded'.tr.replaceAll('{n}', '${full.rows.length}'));
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
  }

  // ── preview / issue ────────────────────────────────────────────────────────

  Map<String, String> get _constantValues => {for (final e in _constants.entries) e.key: e.value.text};

  List<String> get _langList => [for (final l in (_template?.langs ?? const ['ar'])) if (_langs.contains(l)) l];

  Future<void> _loadPreview() async {
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    final langs = _langList;
    if (!langs.contains(_previewLang) && langs.isNotEmpty) _previewLang = langs.first;
    try {
      final images = await _api.preview(certPreviewBody(
        designId: widget.designId,
        mode: _mode ?? IssueMode.standalone,
        orgId: widget.orgId,
        courseId: _courseId,
        values: _mode == IssueMode.standalone ? _draft.firstReady?.values : null,
        constants: _constantValues,
        langs: langs,
      ));
      if (!mounted) return;
      setState(() {
        _images = images;
        _previewLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewError = certIssueErrorText(e);
        _previewLoading = false;
      });
    }
  }

  Future<void> _issue() async {
    if (_issuing) return;
    setState(() => _issuing = true);
    final course = _mode == IssueMode.course;
    try {
      final certificateId = course && _courseId != null ? await _courseCertificate(_courseId!) : null;
      final b = await _api.createBatch(certBatchBody(
        designId: widget.designId,
        mode: course ? IssueMode.course : IssueMode.standalone,
        orgId: widget.orgId,
        courseId: _courseId,
        certificateId: certificateId,
        replaceExisting: _replaceExisting,
        langs: _langList,
        email: course ? _courseEmail : _withEmail,
        constants: _constantValues,
        title: _titleCtrl.text,
        rows: course ? const [] : _draft.batchRows(),
      ));
      if (!mounted) return;
      setState(() {
        _batch = b;
        _issuing = false;
        _step = 3;
      });
      _follow(b.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _issuing = false);
      showAppNotice(certIssueErrorText(e), error: true);
    }
  }

  void _follow(int id) {
    _watch?.dispose();
    _watch = EventOrPoll(
      kind: 'certificate_batch',
      id: '$id',
      every: const Duration(seconds: 2),
      fallbackEvery: const Duration(seconds: 3),
      poll: () async {
        try {
          final b = await _api.batch(id);
          if (!mounted) return;
          setState(() => _batch = b);
          if (b.finished) {
            _watch?.stop();
            if (b.status == 'done') showAppNotice('ci_batch_done'.tr);
          }
        } catch (_) {
          // a failed poll is retried on the next tick
        }
      },
    )..start();
  }

  Future<void> _download(String kind) async {
    final b = _batch;
    if (b == null) return;
    setState(() => _downloading = kind);
    try {
      await certOpenUrl(await _api.download(b.id, kind));
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
    if (mounted) setState(() => _downloading = null);
  }

  void _restart() {
    _watch?.dispose();
    _watch = null;
    setState(() {
      _batch = null;
      _step = 0;
      _draft.clear();
      _pasteCtrl.clear();
      _pasteCount = null;
      _fileName = null;
      _fileBytes = null;
      _uploadCount = null;
      _images = const {};
    });
  }

  // ── navigation ─────────────────────────────────────────────────────────────

  bool get _canNext => switch (_step) {
        0 => _mode == IssueMode.standalone ? _template != null : (_mode == IssueMode.course && _courseId != null),
        1 => _draft.summary.ready > 0,
        2 => !_issuing && _langs.isNotEmpty,
        _ => false,
      };

  void _next() {
    if (!_canNext) return;
    switch (_step) {
      case 0:
        setState(() => _step = _mode == IssueMode.course ? 2 : 1);
        if (_mode == IssueMode.course) _loadPreview();
      case 1:
        setState(() => _step = 2);
        _loadPreview();
      case 2:
        _issue();
    }
  }

  void _back() {
    if (_step == 0 || _step == 3) return;
    setState(() => _step = _step == 2 && _mode == IssueMode.course ? 0 : _step - 1);
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        centerTitle: false,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('ci_title'.tr, style: AppType.section(context)),
          if ((widget.designName ?? '').isNotEmpty)
            Text(widget.designName!, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          IconButton(
            tooltip: 'ci_saved_lists'.tr,
            icon: const Icon(Icons.groups_2_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => CertSavedListsPage(designId: widget.designId, orgId: widget.orgId, langs: _template?.langs),
            )),
          ),
          IconButton(
            tooltip: 'ci_history'.tr,
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => CertIssueHistoryPage(orgId: widget.orgId),
            )),
          ),
          const SizedBox(width: AppSpace.xxs),
        ],
      ),
      body: ParentComponent(
        featureKey: kCertIssueFeature,
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: IssueStepper(labels: _stepLabels, current: _step, onTap: _step == 3 ? null : _goTo),
                ),
              ),
            ),
            Divider(height: 1, color: c.divider),
            Expanded(child: _body(context)),
            if (_step < 3) _bottomBar(context),
          ]),
        ),
      ),
    );
  }

  void _goTo(int i) {
    if (i == 1 && _mode == IssueMode.course) return;
    setState(() => _step = i);
  }

  Widget _bottomBar(BuildContext context) {
    final s = _draft.summary;
    return IssueStepBar(
      onBack: _step > 0 ? _back : null,
      summary: _step == 1 ? s.label : null,
      nextLabel: switch (_step) {
        2 => _mode == IssueMode.course ? 'ci_issue_course'.tr : 'ci_issue_n'.tr.replaceAll('{n}', '${s.ready}'),
        _ => 'ci_next'.tr,
      },
      nextIcon: _step == 2 ? Icons.workspace_premium_rounded : Icons.arrow_forward_rounded,
      onNext: _canNext ? _next : null,
      busy: _issuing,
    );
  }

  Widget _body(BuildContext context) {
    if (_templateLoading && _template == null) {
      return const AppListSkeleton(items: 4, withAvatar: false);
    }
    if (_template == null) {
      return Padding(
        padding: AppSpace.card,
        child: Align(
          alignment: Alignment.topCenter,
          child: IssueErrorBox(message: _templateError ?? 'ci_load_failed'.tr, onRetry: _loadTemplate),
        ),
      );
    }
    return switch (_step) {
      0 => _centered(_modeStep(context)),
      1 => _recipientsStep(context),
      2 => _centered(_previewStep(context)),
      _ => _centered(_issueStep(context)),
    };
  }

  Widget _centered(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: child)),
      );

  // step 1
  Widget _modeStep(BuildContext context) {
    final courseArea = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('ci_pick_course'.tr, style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      IssueCourseList(
        courses: [for (final co in _courses) (id: co.id, name: co.name(AppConfig.lang), students: co.students)],
        selectedId: _courseId,
        onPick: (id) {
          setState(() => _courseId = id);
          _courseCertificate(id);
        },
        loading: _coursesLoading,
        error: _coursesError,
        onRetry: _loadCourses,
      ),
      if (_courseTemplate != null && _courseTemplate!.extraColumns.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        IssueConstantsForm(columns: _courseTemplate!.extraColumns, controllers: _constants),
      ],
    ]);
    return IssueModeStep(mode: _mode, onMode: _setMode, courseArea: courseArea);
  }

  // step 2
  Widget _inputs(BuildContext context) {
    final cols = _draft.columns;
    final panel = switch (_tab) {
      RecipientTab.paste => IssuePastePanel(
          columns: cols,
          controller: _pasteCtrl,
          onChanged: _onPaste,
          checking: _pasteChecking,
          error: _pasteError,
          parsedCount: _pasteCount,
        ),
      RecipientTab.upload => IssueUploadPanel(
          columns: cols,
          onPick: _pickFile,
          onSample: _sample,
          fileName: _fileName,
          busy: _uploadBusy,
          error: _uploadError,
          parsedCount: _uploadCount,
        ),
      RecipientTab.search => IssueSearchPanel(
          controller: _searchCtrl,
          onQuery: _onQuery,
          results: _results,
          selected: {for (final s in _results) if (_draft.hasStudent(s.id)) s.id},
          onToggle: _toggleStudent,
          onSelectAll: _selectAll,
          loading: _searchLoading || (widget.orgId == null && _coursesLoading),
          error: _searchError ?? (widget.orgId == null ? _coursesError : null),
          onRetry: widget.orgId == null && _coursesError != null ? _loadCourses : _runSearch,
          needsFilter: widget.orgId == null && _searchCourseId == null && _coursesError == null && !_coursesLoading,
          total: _searchTotal,
          filter: widget.orgId == null && _courses.isNotEmpty
              ? AppDropdown<int>(
                  value: _searchCourseId,
                  decoration: InputDecoration(labelText: 'ci_search_course'.tr),
                  items: [
                    for (final co in _courses) DropdownMenuItem(value: co.id, child: Text(co.name(AppConfig.lang))),
                  ],
                  onChanged: (id) {
                    setState(() {
                      _searchCourseId = id;
                      _results = const [];
                    });
                    _runSearch();
                  },
                )
              : null,
        ),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('ci_who_title'.tr, style: AppType.pageTitle(context)),
      const SizedBox(height: AppSpace.xxs),
      Text('ci_who_sub'.tr, style: AppType.meta(context)),
      const SizedBox(height: AppSpace.sm),
      AppSwitchTile(
        value: _withEmail,
        onChanged: _templateLoading ? (_) {} : _setWithEmail,
        title: 'ci_send_email'.tr,
        subtitle: 'ci_send_email_sub'.tr,
        icon: Icons.mail_outline_rounded,
      ),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        OutlinedButton.icon(
          onPressed: _openList,
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          label: Text('ci_open_list'.tr),
        ),
        OutlinedButton.icon(
          onPressed: _draft.isEmpty ? null : _saveList,
          icon: const Icon(Icons.bookmark_add_outlined, size: 18),
          label: Text('ci_save_list'.tr),
        ),
      ]),
      const SizedBox(height: AppSpace.md),
      SizedBox(width: double.infinity, child: IssueRecipientTabs(tab: _tab, onTab: _openTab)),
      const SizedBox(height: AppSpace.md),
      panel,
    ]);
  }

  Widget _reviewHeader(BuildContext context) => IssueReviewHeader(
        summary: _draft.summary,
        filter: _filter,
        onFilter: (f) => setState(() => _filter = f),
        manualDefault: _draft.manualDefault,
        onManualDefault: (v) => setState(() => _draft.manualDefault = v),
        onRemoveDuplicates: () => setState(() {
          final n = _draft.removeDuplicates();
          showAppNotice('ci_duplicates_removed'.tr.replaceAll('{n}', '$n'));
        }),
        onClear: () async {
          final ok = await appConfirm(context, message: 'ci_clear_confirm'.tr, danger: true, confirmLabel: 'ci_clear'.tr);
          if (!ok || !mounted) return;
          setState(() {
            _draft.clear();
            _pasteCtrl.clear();
            _pasteCount = null;
            _fileName = null;
            _fileBytes = null;
            _uploadCount = null;
          });
        },
      );

  List<({RecipientRow row, RowState state, List<RowIssue> issues})> _visibleRows() {
    final all = _draft.review();
    return switch (_filter) {
      ReviewFilter.all => all,
      ReviewFilter.attention => [for (final r in all) if (r.state == RowState.attention) r],
      ReviewFilter.ready => [for (final r in all) if (r.state == RowState.ready) r],
      ReviewFilter.skipped => [for (final r in all) if (r.state == RowState.skipped) r],
    };
  }

  Widget _rowTile(({RecipientRow row, RowState state, List<RowIssue> issues}) e) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: IssueReviewRow(
          key: ValueKey(e.row.uid),
          row: e.row,
          state: e.state,
          issues: e.issues,
          columns: _draft.columns,
          manual: _draft.manualOf(e.row),
          onEdit: () => _editRow(e.row),
          onRemove: () => setState(() => _draft.remove(e.row.uid)),
          onPickCandidate: (s) => setState(() => _draft.pickCandidate(e.row.uid, s)),
          onManual: (v) => setState(() => _draft.setManual(e.row.uid, v)),
        ),
      );

  Widget _emptyReview(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.md),
        child: AppEmpty(icon: Icons.groups_outlined, title: 'ci_review_empty'.tr, message: 'ci_review_empty_sub'.tr),
      );

  Widget _recipientsStep(BuildContext context) {
    final rows = _visibleRows();
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= _wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 460,
            child: SingleChildScrollView(padding: const EdgeInsets.all(AppSpace.md), child: _inputs(context)),
          ),
          VerticalDivider(width: 1, color: context.colors.divider),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpace.md),
              itemCount: 1 + (rows.isEmpty ? 1 : rows.length),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: _reviewHeader(context));
                }
                if (rows.isEmpty) return _emptyReview(context);
                return _rowTile(rows[i - 1]);
              },
            ),
          ),
        ]);
      }
      return ListView.builder(
        padding: const EdgeInsets.all(AppSpace.md),
        itemCount: 2 + (rows.isEmpty ? 1 : rows.length),
        itemBuilder: (context, i) {
          if (i == 0) return _inputs(context);
          if (i == 1) {
            return Padding(
              padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.sm),
              child: _reviewHeader(context),
            );
          }
          if (rows.isEmpty) return _emptyReview(context);
          return _rowTile(rows[i - 2]);
        },
      );
    });
  }

  // step 3
  Widget _previewStep(BuildContext context) {
    final course = _mode == IssueMode.course;
    final s = _draft.summary;
    final langs = _langList;
    final first = course ? null : _draft.firstReady;
    final courseName = _courses.where((co) => co.id == _courseId).map((co) => co.name(AppConfig.lang)).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('ci_preview_step_title'.tr, style: AppType.pageTitle(context)),
      const SizedBox(height: AppSpace.xxs),
      Text(
        course
            ? 'ci_preview_course_sub'.tr.replaceAll('{course}', courseName ?? '')
            : 'ci_preview_sub'.tr.replaceAll('{n}', '${s.ready}'),
        style: AppType.meta(context),
      ),
      const SizedBox(height: AppSpace.md),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if ((_template?.langs.length ?? 0) > 1) ...[
            IssueLangPicker(
              available: _template!.langs,
              selected: _langs,
              onChanged: (v) {
                setState(() => _langs = v);
                _loadPreview();
              },
            ),
            const SizedBox(height: AppSpace.md),
          ],
          TextField(
            controller: _titleCtrl,
            maxLength: 255,
            decoration: InputDecoration(labelText: 'ci_batch_title'.tr, hintText: widget.designName ?? 'ci_optional'.tr),
          ),
          if (course) ...[
            AppSwitchTile(
              value: _courseEmail,
              onChanged: (v) => setState(() => _courseEmail = v),
              title: 'ci_send_email'.tr,
              subtitle: 'ci_send_email_course_sub'.tr,
              icon: Icons.mail_outline_rounded,
            ),
            // students who already hold the course certificate are skipped unless this is on
            if (_courseId != null && _courseCerts[_courseId] != null)
              AppSwitchTile(
                value: _replaceExisting,
                onChanged: (v) => setState(() => _replaceExisting = v),
                title: 'ci_replace_existing'.tr,
                subtitle: 'ci_replace_existing_sub'.tr,
                icon: Icons.published_with_changes_rounded,
              ),
          ] else
            Row(children: [
              Icon(_withEmail ? Icons.mark_email_read_outlined : Icons.mail_lock_outlined, size: 18, color: context.colors.textMedium),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text(_withEmail ? 'ci_email_on'.tr : 'ci_email_off'.tr, style: AppType.meta(context))),
            ]),
        ]),
      ),
      if (!course && (_template?.extraColumns.isNotEmpty ?? false)) ...[
        const SizedBox(height: AppSpace.md),
        AppCard(
          child: IssueConstantsForm(
            columns: _template!.extraColumns,
            controllers: _constants,
            title: 'ci_defaults_title'.tr,
            subtitle: 'ci_defaults_sub'.tr,
          ),
        ),
      ],
      const SizedBox(height: AppSpace.md),
      AppCard(
        child: IssuePreviewPanel(
          langs: langs,
          lang: langs.contains(_previewLang) ? _previewLang : (langs.isEmpty ? AppConfig.lang : langs.first),
          onLang: (l) => setState(() => _previewLang = l),
          images: _images,
          loading: _previewLoading,
          error: _previewError,
          onRetry: _loadPreview,
          recipientName: first?.name,
        ),
      ),
    ]);
  }

  // step 4
  Widget _issueStep(BuildContext context) {
    final b = _batch;
    if (b == null) return const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      IssueBatchProgressCard(
        batch: b,
        downloading: _downloading,
        onZip: () => _download('zip'),
        onPdf: () => _download('pdf'),
        onViewIssued: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CertBatchPage(batchId: b.id, initial: b),
        )),
        onIssueMore: _restart,
      ),
      if (!b.finished) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.info_outline_rounded, text: 'ci_batch_background'.tr),
      ],
    ]);
  }
}
