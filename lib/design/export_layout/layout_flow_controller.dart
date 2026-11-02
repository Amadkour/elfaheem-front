// lib/design/export_layout/layout_flow_controller.dart
//
// The state of the v3 export page (no widgets; driven by test/export/layout_flow_test.dart through FakeApi):
// the document being designed, the step, the language tab, the saved templates, the server preview and the
// background run. Every edit calls [changed], which autosaves a local draft per page key (debounced, try/catch:
// storage may be missing in a private window or a test).
//
//   steps   0 format + language · 1 how to show the items · 2 design the items · 3 fixed parts · 4 preview + export
//   source  the page's server dataset when it has one (`{dataset, params}`), else the table's rows uploaded once
//           (`POST /rows` → `{rows_upload}`)
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/live/event_wait.dart';
import '../export/export_studio_model.dart' show exportFileName;
import '../export/table_export_model.dart' show AppTableExport;
import 'layout_api.dart';
import 'layout_logic.dart';
import 'layout_model.dart';

/// The kill switch of the v3 page (off → the older Export Studio flow).
const kExportLayoutKey = 'export.layout_v3';

bool get exportLayoutEnabled => !AppConfig.disableList.contains(kExportLayoutKey);

enum LayoutRunPhase { idle, preparing, running, downloading, done, failed, cancelled }

class LayoutFlowController extends ChangeNotifier {
  LayoutFlowController({required this.export, LayoutApi? api, this.liveStream, this.saveFile, this.autosaveDelay = const Duration(milliseconds: 600)})
      : api = api ?? LayoutApi.instance,
        fields = layoutFieldsOf(export.columns) {
    final l = AppConfig.lang == 'en' ? 'en' : 'ar';
    lang = l;
    doc = LayoutDocument(format: 'pdf', languages: [l]);
    doc.designs[l] = _starter('table', l);
  }

  final AppTableExport export;
  final LayoutApi api;
  final LiveStreamHandle? liveStream;

  /// Saves the downloaded file (the page passes the platform saver; tests capture it).
  final Future<void> Function(Uint8List bytes, String name, String mime)? saveFile;
  final Duration autosaveDelay;

  /// The fields the designer picks from: the app table's columns, replaced by the server dataset's own columns
  /// (`GET /exports/datasets/{key}/columns`) when the page exports a dataset — the keys the server renders.
  List<LayoutField> fields;

  /// True once [fields] came from the server's dataset columns.
  bool datasetFields = false;

  late LayoutDocument doc;

  /// The language tab being designed.
  late String lang;
  int step = 0, reached = 0;
  bool _disposed = false;

  static const stepCount = 5;

  String get pageKey => export.id;
  LayoutDesign get design => doc.designs[lang] ?? (doc.designs[lang] = _starter('table', lang));
  LayoutField? fieldOf(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }

  LayoutDesign _starter(String mode, String l, {int perLine = 1, LayoutPage? page}) =>
      layoutStarter(mode: mode, lang: l, fields: fields, perLine: perLine, page: page);

  @override
  void dispose() {
    _disposed = true;
    _autosave?.cancel();
    _watch?.stop();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Call after every change of the document: repaints and autosaves the draft.
  void changed() {
    _gen++;
    _dirty = true;
    _notify();
    _autosave?.cancel();
    _autosave = Timer(autosaveDelay, saveDraft);
  }

  /// The document's version ([changed] bumps it) and, per language, the version its preview was rendered from:
  /// a language's preview is stale when they differ (every language's goes stale on any change).
  int _gen = 0;
  final Map<String, int> _previewGen = {};
  bool previewStale(String l) => previews[l] == null || _previewGen[l] != _gen;

  /// True once the person changed something since the page opened / the last template load or export: only then
  /// is a draft worth keeping.
  bool _dirty = false;

  // ── steps ───────────────────────────────────────────────────────────────────────────────────────────────────
  void goTo(int s) {
    step = s.clamp(0, stepCount - 1);
    if (step > reached) reached = step;
    _notify();
    if (step == stepCount - 1 && previewStale(lang)) unawaited(refreshPreview());
  }

  void next() => goTo(step + 1);
  void back() => goTo(step - 1);

  // ── format, languages, tab ──────────────────────────────────────────────────────────────────────────────────
  void setFormat(String f) {
    if (doc.format == f) return;
    doc.format = f;
    changed();
  }

  /// ['ar'] | ['en'] | ['ar', 'en']: a language without a design yet starts from the other one, mirrored.
  void setLanguages(List<String> langs) {
    final next = [for (final l in const ['ar', 'en']) if (langs.contains(l)) l];
    if (next.isEmpty) return;
    for (final l in next) {
      if (doc.designs[l] != null) continue;
      final other = doc.designs.values.firstOrNull;
      doc.designs[l] = other == null ? _starter('table', l) : layoutCopyForLang(other, l, fields);
    }
    doc.languages = next;
    if (!next.contains(lang)) lang = next.first;
    changed();
  }

  void setTab(String l) {
    if (!doc.languages.contains(l) || l == lang) return;
    lang = l;
    _notify();
    if (step == stepCount - 1 && previewStale(l)) unawaited(refreshPreview());
  }

  /// List / Table / Custom ([perLine] cards per line): every language gets the starter's items part; its page,
  /// fixed parts, watermark and frame are kept.
  void pickMode(String mode, {int perLine = 1}) {
    for (final l in doc.languages) {
      final d = doc.designs[l];
      // built on the design's own page, so the items part fills its content width
      final s = _starter(mode, l, perLine: perLine, page: d?.page);
      if (d == null) {
        doc.designs[l] = s;
        continue;
      }
      if (mode == 'table' && d.page.orientation != s.page.orientation) {
        // a wide table turns the page: the fixed parts follow the new width
        layoutSetPage(d, (p) => p.orientation = s.page.orientation);
      }
      d.mode = s.mode;
      d.list = s.list;
      d.table = s.table;
      d.row = s.row;
      // the row's ids must not clash with the bands'
      for (final e in d.row.elements) {
        e.id = '${e.id}r';
      }
    }
    changed();
  }

  /// The design of [lang] restarted from the other language's (mirrored).
  void copyFromOther() {
    final other = doc.languages.firstWhere((l) => l != lang, orElse: () => '');
    if (other.isEmpty || doc.designs[other] == null) return;
    doc.designs[lang] = layoutCopyForLang(doc.designs[other]!, lang, fields);
    changed();
  }

  // ── the items the row preview browses ──────────────────────────────────────────────────────────────────────
  /// The table's rows as the server gets them ([layoutRowValue]: wall-clock dates, status labels in [valueLang]), so
  /// the row preview prints and rules exactly as the file.
  List<Map<String, Object?>> get items {
    final l = valueLang;
    final rows = [
      for (final r in export.rows) {for (final e in r.entries) e.key: layoutRowValue(fieldOf(e.key), e.value, l)},
    ];
    final sort = design.sort;
    if (sort.isEmpty) return rows;
    final s = List.of(rows);
    s.sort((a, b) {
      for (final k in sort) {
        final x = a[k.field], y = b[k.field];
        final c = x is num && y is num ? x.compareTo(y) : '${x ?? ''}'.compareTo('${y ?? ''}');
        if (c != 0) return k.dir == 'desc' ? -c : c;
      }
      return 0;
    });
    return s;
  }

  /// The item the row preview shows (0-based, clamped).
  int itemIndex = 0;
  void browse(int delta) {
    final n = export.rows.length;
    if (n == 0) return;
    itemIndex = (itemIndex + delta).clamp(0, n - 1);
    _notify();
  }

  String titleIn(String l) => export.titles?[l] ?? export.title;

  Map<String, String> varsFor(String l) => {
        'date': _today(),
        'exporter': l == 'ar' ? 'أنت' : 'You',
        'org_name': export.brand ?? '',
        'total': '${export.rows.length}',
        'page': '1',
        'pages': '1',
        'title': titleIn(l),
        'filters': [for (final e in export.filters.entries) '${e.key}: ${e.value}'].join(' · '),
        'group': l == 'ar' ? 'المجموعة' : 'Group',
      };

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  // ── fonts ───────────────────────────────────────────────────────────────────────────────────────────────────
  List<LayoutFont> fonts = const [];

  Future<void> loadFonts() async {
    final r = await api.fonts();
    if (r.ok && r.data!.isNotEmpty) {
      fonts = r.data!;
      _notify();
    }
  }

  // ── the dataset's own columns ─────────────────────────────────────────────────────────────────────────────
  /// For a dataset source, the server's columns become the fields (their keys are what the server renders). A
  /// design made before they arrived (the starter) is rebuilt on them; a restored draft / template keeps its
  /// design when every field it reads is still there. Older servers (no route) / errors keep the table's columns.
  Future<void> loadDatasetFields() async {
    final ds = export.serverDataset;
    if (ds == null || ds.isEmpty) return;
    final r = await api.datasetColumns(ds, {...?export.serverParams});
    if (!r.ok || r.data!.isEmpty || _disposed) return;
    final next = layoutFieldsOfDataset(r.data!, fields);
    if (next.isEmpty) return;
    final keys = {for (final f in next) f.key};
    fields = next;
    datasetFields = true;
    for (final l in doc.languages) {
      final d = doc.designs[l];
      if (d == null) continue;
      if (_starterDoc && !_dirty) {
        // still the untouched starter: rebuild it on the server's fields
        final s = _starter(d.mode, l, perLine: d.row.perLine, page: d.page);
        d.list = s.list;
        d.table = s.table;
        d.row = s.row;
      } else if (!layoutReferencedFields(d).every(keys.contains)) {
        _datasetMismatch = true;
      }
    }
    _gen++;
    _notify();
  }

  /// True while the document is still the page's starter (no draft, template or earlier export applied).
  bool _starterDoc = true;

  /// A restored draft / template reads a field the dataset does not have (the server prints it empty).
  bool _datasetMismatch = false;
  bool get datasetMismatch => _datasetMismatch;

  // ── draft + remembered template ────────────────────────────────────────────────────────────────────────────
  Timer? _autosave;
  String get _draftKey => 'export_layout.v3.draft.$pageKey';
  String get _lastKey => 'export_layout.v3.last_tpl.$pageKey';
  String get _lastDocKey => 'export_layout.v3.last_doc.$pageKey';

  /// True when [init] restored a draft.
  bool restoredDraft = false;

  /// Keeps the draft — only once the person changed something (opening the page and leaving saves nothing).
  Future<void> saveDraft() async {
    if (!_dirty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_draftKey, jsonEncode({'doc': doc.toJson(withSource: false), 'template_id': templateId}));
    } catch (_) {}
  }

  Future<void> discardDraft() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_draftKey);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _read(String key) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return null;
      final j = jsonDecode(raw);
      return j is Map ? j.map((k, v) => MapEntry('$k', v)) : null;
    } catch (_) {
      return null;
    }
  }

  LayoutDocument? _usable(Object? d) {
    if (d is! Map) return null;
    try {
      final x = LayoutDocument.fromJson(d.map((k, v) => MapEntry('$k', v)));
      return x.languages.isNotEmpty && x.languages.every((l) => x.designs[l] != null) ? x : null;
    } catch (_) {
      return null;
    }
  }

  /// Restores the draft of this page (unsaved changes, with a notice), else opens the last template used on it, else
  /// the design of the last export from it; then loads the dataset's columns, templates and fonts.
  Future<void> init() async {
    final draft = await _read(_draftKey);
    final restored = _usable(draft?['doc']);
    if (restored != null) {
      doc = restored;
      lang = doc.languages.contains(lang) ? lang : doc.languages.first;
      templateId = draft?['template_id'] is num ? (draft!['template_id'] as num).toInt() : null;
      restoredDraft = true;
      _starterDoc = false;
      _dirty = true;
    }
    _notify();
    await Future.wait([loadTemplates(applyLast: !restoredDraft), loadFonts()]);
    if (!restoredDraft && templateId == null) {
      final last = _usable((await _read(_lastDocKey))?['doc']);
      if (last != null && !_dirty) {
        doc = last;
        lang = doc.languages.contains(lang) ? lang : doc.languages.first;
        _starterDoc = false;
        _gen++;
        _notify();
      }
    }
    await loadDatasetFields();
  }

  // ── templates ───────────────────────────────────────────────────────────────────────────────────────────────
  List<LayoutTemplate> templates = const [];
  bool templatesLoading = false, templatesMissing = false;
  String? templatesError;
  int? templateId;

  Future<void> loadTemplates({bool applyLast = false}) async {
    templatesLoading = true;
    templatesError = null;
    _notify();
    final r = await api.templates(pageKey: pageKey, orgId: export.orgId);
    templatesLoading = false;
    if (!r.ok) {
      templatesMissing = r.missing;
      templatesError = r.missing ? null : r.error;
      _notify();
      return;
    }
    templates = r.data!.$1;
    _notify();
    if (applyLast) {
      final last = await _read(_lastKey);
      // the page's own memory wins (null after an export made without a template), else the server's last used
      final id = last != null ? (last['id'] is num ? (last['id'] as num).toInt() : null) : r.data!.$2;
      if (id != null && templates.any((t) => t.id == id)) await loadTemplate(id, quiet: true);
    }
  }

  /// Opens a saved template (one click). Returns an error text, or null.
  Future<String?> loadTemplate(int id, {bool quiet = false}) async {
    final r = await api.template(id);
    if (!r.ok) return r.error;
    final d = r.data!.document;
    if (d == null || d.languages.isEmpty || !d.languages.every((l) => d.designs[l] != null)) {
      return AppConfig.lang == 'ar' ? 'هذا القالب لا يحمل تصميمًا صالحًا' : 'This template holds no usable design';
    }
    d.source = {};
    doc = d;
    lang = doc.languages.contains(lang) ? lang : doc.languages.first;
    templateId = id;
    _starterDoc = false;
    api.markUsed(id);
    try {
      await (await SharedPreferences.getInstance()).setString(_lastKey, jsonEncode({'id': id}));
    } catch (_) {}
    if (!quiet) {
      // a template is a finished design: show it
      reached = stepCount - 1;
    }
    // the template IS the saved state: no draft until the next edit (else "your draft is back" on every visit and
    // the last template would never open again)
    _gen++;
    _autosave?.cancel();
    _dirty = false;
    restoredDraft = false;
    await discardDraft();
    if (fields.isNotEmpty && datasetFields && !doc.designs.values.every((x) => layoutReferencedFields(x).every((k) => fieldOf(k) != null))) {
      _datasetMismatch = true;
    }
    _notify();
    return null;
  }

  /// Saves the document as a named template ([scope] user | org). Returns an error text, or null.
  Future<String?> saveTemplate(String name, {String scope = 'user'}) async {
    final r = await api.saveTemplate(pageKey: pageKey, name: name, doc: doc, scope: scope, orgId: export.orgId);
    if (!r.ok) return r.error;
    templateId = r.data!.id;
    templates = [r.data!, ...templates.where((t) => t.id != r.data!.id)];
    try {
      await (await SharedPreferences.getInstance()).setString(_lastKey, jsonEncode({'id': templateId}));
    } catch (_) {}
    _notify();
    unawaited(saveDraft());
    return null;
  }

  // ── source ──────────────────────────────────────────────────────────────────────────────────────────────────
  String? _uploadId, _uploadLang;

  /// The language the uploaded values (status labels) are written in: the document's first language (one upload
  /// serves both files of a two-language export).
  String get valueLang => doc.languages.isEmpty ? lang : doc.languages.first;

  /// The document's source: the page's dataset, else the table's rows uploaded once per page visit.
  Future<String?> ensureSource() async {
    final ds = export.serverDataset;
    if (ds != null && ds.isNotEmpty) {
      doc.source = {'dataset': ds, 'params': {...?export.serverParams}};
      return null;
    }
    final l = valueLang;
    if (_uploadId == null || _uploadLang != l) {
      final r = await api.uploadRows(fields, export.rows, lang: l);
      if (!r.ok) return r.error;
      if (r.data!.isEmpty) return AppConfig.lang == 'ar' ? 'تعذّر رفع الصفوف' : 'Could not upload the rows';
      _uploadId = r.data;
      _uploadLang = l;
    }
    doc.source = {'rows_upload': _uploadId};
    return null;
  }

  // ── preview ─────────────────────────────────────────────────────────────────────────────────────────────────
  final Map<String, LayoutPreview?> previews = {};
  bool previewLoading = false, previewMissing = false;
  String? previewError;
  int previewPage = 0;

  LayoutPreview? get preview => previews[lang];

  void showPreviewPage(int i) {
    previewPage = i;
    _notify();
  }

  /// The notes to show: the server's for this language (Excel / Word notes included) + the app's own, once each.
  List<LayoutIssue> get issues {
    final seen = <String>{};
    return [
      for (final i in [
        ...?preview?.issues,
        ...layoutLocalIssues(design, doc.format),
        if (_datasetMismatch)
          const LayoutIssue(
            code: 'dataset_fields_missing',
            severity: 'warning',
            messageAr: 'يستخدم هذا التصميم حقولًا غير موجودة في بيانات هذه الصفحة: ستظهر فارغة',
            messageEn: "This design uses fields this page's data does not have: they print empty",
          ),
      ])
        if (seen.add(i.key)) i,
    ];
  }

  Future<void> refreshPreview() async {
    previewLoading = true;
    previewError = null;
    _notify();
    final l = lang, gen = _gen;
    final err = await ensureSource();
    if (err != null) {
      previewLoading = false;
      previewError = err;
      _notify();
      return;
    }
    final r = await api.preview(doc, lang: l, title: titleIn(l));
    previewLoading = false;
    if (r.ok) {
      previews[l] = r.data;
      previewPage = 0;
      _previewGen[l] = gen;
    } else {
      previewMissing = r.missing;
      previewError = r.error;
    }
    _notify();
  }

  // ── run ─────────────────────────────────────────────────────────────────────────────────────────────────────
  LayoutRunPhase phase = LayoutRunPhase.idle;
  LayoutRun? run;
  String? runError, savedName;
  LayoutRunWatch? _watch;

  bool get busy => phase == LayoutRunPhase.preparing || phase == LayoutRunPhase.running || phase == LayoutRunPhase.downloading;

  /// The file's name: `<title>_<yyyy-MM-dd>.<ext>` (a zip for two PDF / Word files).
  String get fileName {
    final ext = doc.languages.length > 1 && doc.format != 'xlsx' ? 'zip' : doc.format;
    return exportFileName(export.fileName ?? titleIn(lang), ext);
  }

  String get mime => switch (fileName.split('.').last) {
        'zip' => 'application/zip',
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        _ => 'application/pdf',
      };

  /// Starts the background export, follows it and saves the file. True when the file was saved.
  Future<bool> startRun() async {
    if (busy) return false;
    phase = LayoutRunPhase.preparing;
    run = null;
    runError = null;
    _notify();
    final err = await ensureSource();
    if (err != null) return _fail(err);
    final title = titleIn(valueLang);
    doc.name = title;
    final started = await api.startRun(layoutWithTitles(doc, titleIn), name: title);
    if (!started.ok || started.data!.isEmpty) return _fail(started.error ?? '');
    if (phase == LayoutRunPhase.cancelled) {
      unawaited(api.cancel(started.data!));
      return false;
    }
    phase = LayoutRunPhase.running;
    run = LayoutRun(id: started.data!);
    _notify();
    final w = _watch = LayoutRunWatch(api, started.data!, stream: liveStream);
    final r = await w.wait((x) {
      run = x;
      _notify();
    });
    _watch = null;
    if (phase == LayoutRunPhase.cancelled) return false;
    if (!r.ok) return _fail(r.error ?? '');
    final done = r.data!;
    if (done.cancelled) {
      phase = LayoutRunPhase.cancelled;
      _notify();
      return false;
    }
    if (!done.done) {
      final e = done.error;
      // a run's error is a code (render_timeout, …) or a sentence
      return _fail(e == null || e.isEmpty ? (AppConfig.lang == 'ar' ? 'تعذّر إنشاء الملف' : 'Could not create the file') : (RegExp(r'^[a-z_]+$').hasMatch(e) ? layoutErrorText(e, e) : e));
    }
    return downloadAgain();
  }

  /// Downloads the finished run's file and saves it.
  Future<bool> downloadAgain() async {
    final id = run?.id;
    if (id == null) return false;
    phase = LayoutRunPhase.downloading;
    _notify();
    final b = await api.download(id);
    if (!b.ok) return _fail(b.error ?? '');
    final name = run?.fileName ?? fileName;
    try {
      await saveFile?.call(b.data!, name, mime);
    } catch (e) {
      return _fail(AppConfig.lang == 'ar' ? 'تعذّر حفظ الملف' : 'Could not save the file');
    }
    savedName = name;
    phase = LayoutRunPhase.done;
    _notify();
    if (templateId != null) api.markUsed(templateId!);
    await _exported();
    return true;
  }

  /// After a saved file: the design is remembered as this page's last export (opened next time when no template is)
  /// and the draft goes — nothing is lost, and the "draft is back" notice no longer shows on every visit.
  Future<void> _exported() async {
    _autosave?.cancel();
    _dirty = false;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_lastDocKey, jsonEncode({'doc': doc.toJson(withSource: false)}));
      await p.setString(_lastKey, jsonEncode({'id': templateId}));
    } catch (_) {}
    await discardDraft();
  }

  Future<void> cancelRun() async {
    final id = run?.id;
    phase = LayoutRunPhase.cancelled;
    _watch?.stop();
    _notify();
    if (id != null) await api.cancel(id);
  }

  bool _fail(String error) {
    phase = LayoutRunPhase.failed;
    runError = error.isEmpty ? (AppConfig.lang == 'ar' ? 'تعذّر التصدير' : 'The export failed') : error;
    _notify();
    return false;
  }
}
