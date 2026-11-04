// lib/design/export_layout/layout_flow_controller.dart
//
// The state of the export / design page (no widgets; driven by test/export/layout_flow_test.dart through FakeApi):
// the document being designed, the step, the language tab, the gallery (server starters + presets + saved
// templates), the server preview and the background run. Every edit calls [changed], which autosaves a local draft
// per page key (debounced, try/catch: storage may be missing in a private window or a test) and, while a live
// preview is shown, schedules a new server preview (debounced, coalesced: never two in flight).
//
//   steps   0 start (format, language, gallery, Export now) · 1 layout (mode + large-list presets, sort / group /
//           totals, computed columns) · 2 design (items + fixed parts on one canvas) · 3 preview + export
//   source  the page's server dataset when it has one (`{dataset, params}`), else the table's rows uploaded once
//           (`POST /rows` → `{rows_upload}`), uploaded again when the rows or the field set change
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
import 'layout_computed.dart' show applyComputed;
import 'layout_logic.dart';
import 'layout_model.dart';

/// The kill switch of the v3 page (off → the older Export Studio flow).
const kExportLayoutKey = 'export.layout_v3';

bool get exportLayoutEnabled => !AppConfig.disableList.contains(kExportLayoutKey);

enum LayoutRunPhase { idle, preparing, running, downloading, done, failed, cancelled }

/// What a design looks like at a glance: the thumbnails on the gallery and mode cards are drawn from this, never
/// from the server.
class LayoutThumbSpec {
  const LayoutThumbSpec({this.mode = 'table', this.columns = 1, this.perLine = 1, this.perPage = 0, this.fill = false, this.tableColumns = 4, this.landscape = false});
  final String mode;

  /// list columns (1 – 4) · cards per line (1 – 4) · cards per page (0 = as many as fit) · the table's column count
  final int columns, perLine, perPage, tableColumns;
  final bool fill, landscape;

  factory LayoutThumbSpec.fromDesign(LayoutDesign d) => LayoutThumbSpec(
        mode: d.mode,
        columns: d.list.columns,
        perLine: d.row.perLine,
        perPage: d.row.perPage,
        fill: d.row.fillPage,
        tableColumns: d.table.columns.isEmpty ? 4 : d.table.columns.length.clamp(2, 7),
        landscape: d.page.orientation == 'landscape',
      );
}

/// A ready layout: the gallery offers these when the server has no starters, the layout step's cards use them.
class LayoutPreset {
  const LayoutPreset(this.key, this.nameAr, this.nameEn, this.hintAr, this.hintEn, this.mode, {this.columns = 1, this.perLine = 1, this.perPage = 0, this.fill = false});
  final String key, nameAr, nameEn, hintAr, hintEn;

  /// table | list | custom | page
  final String mode;
  final int columns, perLine, perPage;
  final bool fill;

  String name(String lang) => lang == 'ar' ? nameAr : nameEn;
  String hint(String lang) => lang == 'ar' ? hintAr : hintEn;
  LayoutThumbSpec get thumb => LayoutThumbSpec(mode: mode, columns: columns, perLine: perLine, perPage: perPage, fill: fill);
}

const kLayoutPresets = <LayoutPreset>[
  LayoutPreset('table', 'جدول', 'Table', 'أعمدة بعناوين، مناسب للأرقام', 'Columns with headings, good for figures', 'table'),
  LayoutPreset('list', 'قائمة', 'List', 'سطر لكل عنصر', 'One line per item', 'list'),
  LayoutPreset('list2', 'قائمة بعمودين', 'List, 2 columns', 'قائمة طويلة في عمودين متجاورين', 'A long list in two columns side by side', 'list', columns: 2),
  LayoutPreset('list3', 'قائمة بثلاثة أعمدة', 'List, 3 columns', 'أكثر عناصر في الصفحة', 'The most items on a page', 'list', columns: 3),
  LayoutPreset('cards', 'بطاقات', 'Cards', 'بطاقة لكل عنصر', 'A card per item', 'custom'),
  LayoutPreset('cards2', 'بطاقتان في السطر', 'Two cards per line', 'بطاقات متجاورة', 'Cards side by side', 'custom', perLine: 2),
  LayoutPreset('cards4', 'أربع بطاقات في السطر', 'Four cards per line', 'بطاقات صغيرة للقوائم الكبيرة', 'Small cards for large lists', 'custom', perLine: 4),
  LayoutPreset('grid2', 'شبكة 2×2', 'Grid 2×2', 'أربع بطاقات تملأ الصفحة', 'Four cards fill the page', 'custom', perLine: 2, perPage: 4, fill: true),
  LayoutPreset('grid3', 'شبكة 3×3', 'Grid 3×3', 'تسع بطاقات تملأ الصفحة', 'Nine cards fill the page', 'custom', perLine: 3, perPage: 9, fill: true),
  LayoutPreset('page', 'صفحة لكل عنصر', 'One page per item', 'شهادات وبطاقات تعريف', 'Certificates and profile sheets', 'page'),
];

/// One card of the start screen's gallery.
class LayoutGalleryItem {
  const LayoutGalleryItem({required this.id, required this.nameAr, required this.nameEn, this.hintAr = '', this.hintEn = '', this.thumb, this.kind = 'preset', this.badgeAr, this.badgeEn});
  final String id, nameAr, nameEn, hintAr, hintEn;

  /// preset | starter | template | last
  final String kind;
  final String? badgeAr, badgeEn;
  final LayoutThumbSpec? thumb;

  String name(String lang) => lang == 'ar' ? (nameAr.isEmpty ? nameEn : nameAr) : (nameEn.isEmpty ? nameAr : nameEn);
  String hint(String lang) => lang == 'ar' ? (hintAr.isEmpty ? hintEn : hintAr) : (hintEn.isEmpty ? hintAr : hintEn);
  String? badge(String lang) => lang == 'ar' ? badgeAr : badgeEn;
}

/// Changes the cards per line: the card's elements stretch / shrink with the card's new width.
void layoutSetPerLine(LayoutDesign d, int n) {
  final row = d.row;
  final w = d.page.contentWidth;
  final before = row.cardWidth(w);
  row.perLine = n.clamp(1, 4);
  final k = row.cardWidth(w) / before;
  for (final e in row.elements) {
    e.x = mm(e.x * k);
    e.w = mm(e.w * k);
  }
}

class LayoutFlowController extends ChangeNotifier {
  LayoutFlowController({
    required this.export,
    LayoutApi? api,
    this.liveStream,
    this.saveFile,
    this.autosaveDelay = const Duration(milliseconds: 600),
    this.previewDelay = const Duration(milliseconds: 900),
    this.purpose = 'export',
    this.designOnly = false,
    List<LayoutField>? fieldsOverride,
    LayoutDocument? initialDocument,
  })  : api = api ?? LayoutApi.instance,
        fields = fieldsOverride ?? layoutFieldsOf(export.columns) {
    final l = AppConfig.lang == 'en' ? 'en' : 'ar';
    lang = l;
    doc = LayoutDocument(format: 'pdf', languages: [l], purpose: purpose);
    doc.designs[l] = _starter('table', l);
    final init = initialDocument;
    if (init != null && init.languages.isNotEmpty && init.languages.every((x) => init.designs[x] != null)) {
      doc = LayoutDocument.fromJson(init.toJson())..purpose = purpose;
      lang = doc.languages.contains(l) ? l : doc.languages.first;
      _starterDoc = false;
      _explicitInitial = true;
    }
  }

  /// A document handed in by the host (a design to edit): no draft, template or last design replaces it.
  bool _explicitInitial = false;

  final AppTableExport export;
  final LayoutApi api;
  final LiveStreamHandle? liveStream;

  /// The document's purpose (`export`, `certificate`, `exam_paper`, …).
  final String purpose;

  /// No export run: the page ends with "Save the design" and returns the document.
  final bool designOnly;

  /// Saves the downloaded file (the page passes the platform saver; tests capture it).
  final Future<void> Function(Uint8List bytes, String name, String mime)? saveFile;
  final Duration autosaveDelay;

  /// How long after the last edit the live preview is asked for.
  final Duration previewDelay;

  /// The fields the designer picks from: the app table's columns, replaced by the server dataset's own columns
  /// (`GET /exports/datasets/{key}/columns`) when the page exports a dataset — the keys the server renders.
  List<LayoutField> fields;

  /// [fields] + the document's computed fields: every picker (columns, list fields, card fields, sort, group,
  /// totals, rules) offers these.
  List<LayoutField> get allFields => [...fields, ...doc.computedFields];

  /// True once [fields] came from the server's dataset columns.
  bool datasetFields = false;

  late LayoutDocument doc;

  /// The language tab being designed.
  late String lang;
  int step = 0, reached = 0;
  bool _disposed = false;

  static const stepCount = 4;

  /// Bumps whenever a design's lists are REPLACED (a layout pick, a copy, a template, a starter): canvases keyed on
  /// it are rebuilt, the others keep their undo history.
  int designEpoch = 0;

  bool get isXlsx => doc.format == 'xlsx';

  String get pageKey => export.id;
  LayoutDesign get design => doc.designs[lang] ?? (doc.designs[lang] = _starter('table', lang));
  LayoutField? fieldOf(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    for (final f in doc.computedFields) {
      if (f.key == key) return f;
    }
    return null;
  }

  LayoutDesign _starter(String mode, String l, {int perLine = 1, LayoutPage? page}) =>
      layoutStarter(mode: mode, lang: l, fields: fields, perLine: perLine, page: page);

  bool _deferred = false;

  @override
  void dispose() {
    // a run the person chose to leave running is finished first (its file still has to be downloaded and saved)
    if (detached && busy && !_disposed) {
      _deferred = true;
      return;
    }
    if (_disposed) return;
    _disposed = true;
    _autosave?.cancel();
    _previewTimer?.cancel();
    _watch?.stop();
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
    if (_deferred && !busy) dispose();
  }

  /// Call after every change of the document: repaints, autosaves the draft and (live preview on) schedules a preview.
  void changed() {
    _gen++;
    _dirty = true;
    _notify();
    _autosave?.cancel();
    _autosave = Timer(autosaveDelay, saveDraft);
    if (livePreview) _schedulePreview();
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
    // one page per item has no Excel form: those designs fall back to cards
    if (f == 'xlsx' && doc.languages.any((l) => doc.designs[l]?.mode == 'page')) {
      setLayout('custom');
      return;
    }
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
    designEpoch++;
    changed();
  }

  void setTab(String l) {
    if (!doc.languages.contains(l) || l == lang) return;
    lang = l;
    _notify();
    if (step == stepCount - 1 && previewStale(l)) unawaited(refreshPreview());
    if (livePreview && previewStale(l)) _schedulePreview(after: const Duration(milliseconds: 150));
  }

  /// List / Table / Custom ([perLine] cards per line): every language gets the starter's items part; its page,
  /// fixed parts, watermark and frame are kept.
  void pickMode(String mode, {int perLine = 1}) {
    _pick(mode, perLine);
    designEpoch++;
    changed();
  }

  void _pick(String mode, int perLine) {
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
  }

  /// The layout step's one entry: [mode] table | list | custom | page, with the large-list settings ([columns] of a
  /// list, [perLine] cards per line, [perPage] items on a page, [fill] = the cards fill the page).
  void setLayout(String mode, {int columns = 1, int perLine = 1, int perPage = 0, bool fill = false}) {
    final m = mode == 'page' && isXlsx ? 'custom' : mode;
    _pick(m == 'page' ? 'custom' : m, perLine.clamp(1, 3));
    for (final l in doc.languages) {
      final d = doc.designs[l]!;
      if (m == 'list') d.list.columns = columns.clamp(1, 4);
      if (m == 'custom') {
        if (perLine > 3) layoutSetPerLine(d, perLine);
        d.row.perPage = perPage;
        d.row.fillPage = fill;
      }
      if (m == 'page') {
        d.mode = 'page';
        d.row.perLine = 1;
        d.row.height = mm(d.page.contentHeight);
      }
    }
    galleryId = null;
    designEpoch++;
    changed();
  }

  /// A preset of [kLayoutPresets].
  void applyPreset(LayoutPreset p) {
    setLayout(p.mode, columns: p.columns, perLine: p.perLine, perPage: p.perPage, fill: p.fill);
    galleryId = 'preset:${p.key}';
    _notify();
  }

  /// The layout of the design now, as the layout step's cards read it: table | list | cards | grid | page.
  String get layoutKind {
    final d = design;
    return d.mode == 'custom' ? (d.row.fillPage ? 'grid' : 'cards') : d.mode;
  }

  /// Items per page of the current mode (0 = as many as fit).
  int get itemsPerPage => switch (design.mode) {
        'list' => design.list.itemsPerPage,
        'table' => design.table.itemsPerPage,
        'custom' => design.row.perPage,
        _ => 0,
      };

  void setItemsPerPage(int n) {
    for (final l in doc.languages) {
      final d = doc.designs[l];
      if (d == null) continue;
      switch (d.mode) {
        case 'list':
          d.list.itemsPerPage = n;
        case 'table':
          d.table.itemsPerPage = n;
        case 'custom':
          d.row.perPage = n;
      }
    }
    changed();
  }

  /// The design of [lang] restarted from the other language's (mirrored).
  void copyFromOther() {
    final other = doc.languages.firstWhere((l) => l != lang, orElse: () => '');
    if (other.isEmpty || doc.designs[other] == null) return;
    doc.designs[lang] = layoutCopyForLang(doc.designs[other]!, lang, fields);
    designEpoch++;
    changed();
  }

  /// After the computed-fields editor returned true: the document changed (new keys in every picker).
  void computedChanged() {
    designEpoch++;
    changed();
  }

  // ── gallery: server starters (or the local presets) + the saved templates ───────────────────────────────────
  /// The server's starters (null = not loaded / unavailable: the local presets are offered instead).
  List<LayoutStarter>? starters;
  bool startersLoading = false;

  /// The card the person picked (null = none yet).
  String? galleryId;
  bool _lastDesign = false;

  /// The id of the card that is selected: the one picked, else the saved template / last design in use, else the
  /// table (the untouched starter).
  String? get selectedGalleryId {
    if (galleryId != null) return galleryId;
    if (templateId != null) return 'tpl:$templateId';
    if (_lastDesign) return 'last';
    if (!_starterDoc) return null;
    for (final g in gallery) {
      if (g.thumb?.mode == 'table') return g.id;
    }
    return null;
  }

  Future<void> loadStarters() async {
    startersLoading = true;
    _notify();
    final r = await api.starters(purpose: purpose);
    startersLoading = false;
    starters = r.ok && r.data!.isNotEmpty ? r.data : null;
    _notify();
  }

  List<LayoutGalleryItem> get gallery => [
        if (_lastDesign)
          const LayoutGalleryItem(id: 'last', nameAr: 'آخر تصميم استخدمته', nameEn: 'Your last design', hintAr: 'كما صدّرت المرة السابقة', hintEn: 'As you exported last time', kind: 'last'),
        if (starters != null) ...[
          for (final s in starters!)
            if (!(isXlsx && s.mode == 'page'))
              LayoutGalleryItem(
                id: 'starter:${s.key}',
                nameAr: s.nameAr,
                nameEn: s.nameEn,
                hintAr: s.descAr,
                hintEn: s.descEn,
                kind: 'starter',
                thumb: s.document!.designs.values.isEmpty ? null : LayoutThumbSpec.fromDesign(s.document!.designs.values.first),
              ),
        ] else ...[
          for (final p in kLayoutPresets)
            if (!(p.mode == 'page' && isXlsx))
              LayoutGalleryItem(id: 'preset:${p.key}', nameAr: p.nameAr, nameEn: p.nameEn, hintAr: p.hintAr, hintEn: p.hintEn, thumb: p.thumb),
        ],
        for (final tp in templates)
          LayoutGalleryItem(
            id: 'tpl:${tp.id}',
            nameAr: tp.name,
            nameEn: tp.name,
            hintAr: '${tp.format.toUpperCase()} · ${tp.lang == 'both' ? 'لغتان' : (tp.lang == 'ar' ? 'العربية' : 'الإنجليزية')}',
            hintEn: '${tp.format.toUpperCase()} · ${tp.lang == 'both' ? 'Both' : (tp.lang == 'ar' ? 'Arabic' : 'English')}',
            kind: 'template',
            badgeAr: tp.isOrg ? 'المؤسسة' : 'قالبي',
            badgeEn: tp.isOrg ? 'Organization' : 'Mine',
          ),
      ];

  /// Applies a gallery card. Returns an error text for a template that did not open, else null.
  Future<String?> pickGallery(LayoutGalleryItem g) async {
    switch (g.kind) {
      case 'template':
        final id = int.tryParse(g.id.substring(4));
        if (id == null) return null;
        final err = await loadTemplate(id, quiet: true);
        if (err == null) {
          galleryId = g.id;
          _lastDesign = false;
          _notify();
        }
        return err;
      case 'starter':
        final s = starters?.where((x) => 'starter:${x.key}' == g.id).firstOrNull;
        if (s?.document != null) applyStarter(s!);
        galleryId = g.id;
        _notify();
      case 'last':
        final last = _usable((await _read(_lastDocKey))?['doc']);
        if (last != null) {
          doc = last..purpose = purpose;
          lang = doc.languages.contains(lang) ? lang : doc.languages.first;
          templateId = null;
          designEpoch++;
          changed();
          galleryId = 'last';
          _notify();
        }
      default:
        final p = kLayoutPresets.where((x) => 'preset:${x.key}' == g.id).firstOrNull;
        if (p != null) applyPreset(p);
    }
    return null;
  }

  /// Puts the starter's designs on the document (per language; a missing language is the other one, mirrored). A
  /// design that reads fields this table does not have keeps its page, parts and v4 settings but gets the items
  /// part rebuilt on the real fields, so "Export now" never prints an empty file.
  void applyStarter(LayoutStarter s) {
    final src = s.document!;
    for (final l in doc.languages) {
      final raw = src.designs[l] ?? (src.designs.values.isEmpty ? null : layoutCopyForLang(src.designs.values.first, l, fields));
      if (raw == null) continue;
      final d = LayoutDesign.fromJson(raw.toJson());
      if (!layoutReferencedFields(d).every((k) => fieldOf(k) != null)) {
        final cols = d.list.columns, lPer = d.list.itemsPerPage, tPer = d.table.itemsPerPage;
        final perLine = d.row.perLine, perPage = d.row.perPage, fill = d.row.fillPage;
        final fresh = _starter(d.mode == 'page' ? 'custom' : d.mode, l, perLine: perLine.clamp(1, 3), page: d.page);
        d.list = fresh.list
          ..columns = cols
          ..itemsPerPage = lPer;
        d.table = fresh.table..itemsPerPage = tPer;
        d.row = fresh.row
          ..perPage = perPage
          ..fillPage = fill;
        for (final e in d.row.elements) {
          e.id = '${e.id}r';
        }
        if (perLine > 3) layoutSetPerLine(d, perLine);
      }
      if (isXlsx && d.mode == 'page') d.mode = 'custom';
      doc.designs[l] = d;
    }
    templateId = null;
    designEpoch++;
    changed();
  }

  // ── the items the row preview browses ──────────────────────────────────────────────────────────────────────
  /// The table's rows as the server gets them ([layoutRowValue]: wall-clock dates, status labels in [valueLang]), so
  /// the row preview prints and rules exactly as the file; the document's computed columns are worked out first, as
  /// the server does before sort / group / totals.
  List<Map<String, Object?>> get items {
    final l = valueLang;
    final specs = doc.computed;
    Map<String, Object?> row(Map<String, Object?> r) {
      final v = <String, Object?>{for (final e in r.entries) e.key: layoutRowValue(fieldOf(e.key), e.value, l)};
      return specs.isEmpty ? v : applyComputed(v, specs);
    }
    final rows = [for (final r in export.rows) row(r)];
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
    fields = next;
    datasetFields = true;
    designEpoch++;
    for (final l in doc.languages) {
      final d = doc.designs[l];
      if (d == null) continue;
      if (_starterDoc && !_dirty) {
        // still the untouched starter: rebuild it on the server's fields
        final s = _starter(d.mode, l, perLine: d.row.perLine, page: d.page);
        d.list = s.list;
        d.table = s.table;
        d.row = s.row;
      }
    }
    _gen++;
    _notify();
  }

  /// True while the document is still the page's starter (no draft, template or earlier export applied).
  bool _starterDoc = true;

  /// The design being shown reads a field the dataset does not have (the server prints it empty) — checked on the
  /// current design, so picking another starter or field clears it.
  bool get datasetMismatch => datasetFields && !layoutReferencedFields(design).every((k) => fieldOf(k) != null);

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

  /// A design-only page ended with "Save the design": nothing is left to restore.
  Future<void> finishDesign() {
    _autosave?.cancel();
    _dirty = false;
    return discardDraft();
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
    final draft = _explicitInitial ? null : await _read(_draftKey);
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
    await Future.wait([loadTemplates(applyLast: !restoredDraft && !_explicitInitial), loadFonts(), loadStarters()]);
    if (!restoredDraft && templateId == null && !_explicitInitial) {
      final last = _usable((await _read(_lastDocKey))?['doc']);
      if (last != null && !_dirty) {
        doc = last..purpose = purpose;
        lang = doc.languages.contains(lang) ? lang : doc.languages.first;
        _starterDoc = false;
        _lastDesign = true;
        designEpoch++;
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
    d.purpose = purpose;
    templateId = id;
    galleryId = 'tpl:$id';
    _starterDoc = false;
    designEpoch++;
    api.markUsed(id);
    try {
      await (await SharedPreferences.getInstance()).setString(_lastKey, jsonEncode({'id': id}));
    } catch (_) {}
    if (!quiet) reached = stepCount - 1;
    // the template IS the saved state: no draft until the next edit (else "your draft is back" on every visit and
    // the last template would never open again)
    _gen++;
    _autosave?.cancel();
    _dirty = false;
    restoredDraft = false;
    await discardDraft();
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
  String? _uploadId, _uploadSig;
  Future<String?>? _uploadFlight;

  /// True while the table's rows are being sent (rows = [uploadCount]): the page shows it as "Sending N rows".
  bool uploading = false;
  int uploadCount = 0;

  /// The share of the rows upload already sent (0 – 1); null = indeterminate (no size yet, or no upload running).
  /// Listeners are told at most every ~100 ms.
  double? uploadProgress;
  DateTime? _progressAt;

  void _onUploadProgress(int sent, int total) {
    uploadProgress = total > 0 ? (sent / total).clamp(0.0, 1.0) : null;
    final now = DateTime.now();
    final last = _progressAt;
    if (last != null && now.difference(last) < const Duration(milliseconds: 100) && (uploadProgress ?? 0) < 1) return;
    _progressAt = now;
    _notify();
  }

  /// What the uploaded rows were made of: language, field keys and the rows themselves (count + a few samples). A
  /// different signature means the server's copy is out of date.
  String _sourceSig(String l) {
    final rows = export.rows;
    final sample = rows.isEmpty ? 0 : Object.hash(rows.first.toString(), rows[rows.length ~/ 2].toString(), rows.last.toString());
    return '$l|${[for (final f in fields) '${f.key}:${f.type}'].join(',')}|${rows.length}|$sample';
  }

  /// Forgets the uploaded rows (the next preview / run sends them again): call after the rows were changed in place.
  void invalidateSource() {
    _uploadId = null;
    _uploadSig = null;
  }

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
    final sig = _sourceSig(l);
    if (_uploadId == null || _uploadSig != sig) {
      // a preview and a run asking at once share one upload
      final flight = _uploadFlight ??= _upload(l, sig).whenComplete(() => _uploadFlight = null);
      final err = await flight;
      if (err != null) return err;
    }
    doc.source = {'rows_upload': _uploadId};
    return null;
  }

  Future<String?> _upload(String l, String sig) async {
    uploading = true;
    uploadCount = export.rows.length;
    uploadProgress = null;
    _progressAt = null;
    _notify();
    final r = await api.uploadRows(fields, export.rows, lang: l, onProgress: _onUploadProgress);
    uploading = false;
    uploadProgress = null;
    _notify();
    if (!r.ok) return r.error;
    if (r.data!.isEmpty) return AppConfig.lang == 'ar' ? 'تعذّر رفع الصفوف' : 'Could not upload the rows';
    _uploadId = r.data;
    _uploadSig = sig;
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
        if (datasetMismatch)
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

  // ── live preview: debounced after the last edit, one request at a time ──────────────────────────────────────
  /// True while a side pane / the phone's preview sheet shows the preview: edits then ask for a new one.
  bool livePreview = false;
  Timer? _previewTimer;
  bool _previewInFlight = false, _previewQueued = false;

  /// Turns the live preview on / off (the page calls it from its layout). Turning it on with a stale preview
  /// schedules one.
  void wantLivePreview(bool on) {
    if (livePreview == on) return;
    livePreview = on;
    if (on && previewStale(lang)) {
      _schedulePreview(after: const Duration(milliseconds: 150));
    } else if (!on) {
      _previewTimer?.cancel();
    }
  }

  void _schedulePreview({Duration? after}) {
    _previewTimer?.cancel();
    _previewTimer = Timer(after ?? previewDelay, () {
      if (!_disposed) unawaited(refreshPreview());
    });
  }

  /// Renders the first page(s) on the server. A request while one is in flight is remembered and runs right after
  /// it (several edits = one more request); the page the person is on is kept.
  Future<void> refreshPreview() async {
    if (_previewInFlight) {
      _previewQueued = true;
      return;
    }
    _previewInFlight = true;
    try {
      do {
        _previewQueued = false;
        await _renderPreview();
      } while (_previewQueued && !_disposed);
    } finally {
      _previewInFlight = false;
    }
  }

  Future<void> _renderPreview() async {
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
      _previewGen[l] = gen;
      previewMissing = false;
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

  /// The person left the page while the file was being made and chose to let it finish: the controller outlives the
  /// page until the file is saved (or the run fails), then [onBackgroundDone] tells them.
  bool detached = false;
  void Function(String message, bool error)? onBackgroundDone;

  void detach() {
    if (busy) detached = true;
  }

  /// Rows made so far / in all (the server reports the total and a percentage).
  int? get rowsTotal => run?.rows ?? (export.rows.isEmpty ? null : export.rows.length);
  int get rowsDone => rowsTotal == null ? 0 : (rowsTotal! * (run?.progress ?? 0) / 100).round();

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
    if (busy || designOnly) return false;
    detached = false;
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
    if (detached) onBackgroundDone?.call(runError!, true);
    _notify();
    return false;
  }
}
