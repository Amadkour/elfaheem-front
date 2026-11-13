// lib/design/export_layout/layout_api.dart
//
// The layout v3 server (`/api/v1/exports/layout`, docs/export_studio/LAYOUT_V3.md "Server API"): the font catalog,
// validate, the preview pages (PNG), rows upload for a table with no server dataset, image assets, background runs
// (start, status, download, cancel), plus the v3 templates on the existing `/api/v1/exports/templates`.
//
//     final r = await LayoutApi.instance.preview(doc, lang: 'ar');
//     if (r.ok) …r.data!.pages   else if (r.missing) …older server   else showAppNotice(r.error!, error: true)
//
// Every call answers an [ExportResult] (never throws; `missing` = the server lacks the route). [LayoutRunWatch]
// waits on a run with JobWatch (the live `job_updated` event, a slow poll only as the fallback) — never a timer.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../core/live/event_wait.dart';
import '../export/export_studio_api.dart';
import '../export/export_studio_model.dart' show exportPageKey;
import '../export/table_export_model.dart' show tx;
import 'layout_logic.dart';
import 'layout_model.dart';

/// One font of the renderer's catalog (the ONLY list: never a second copy in the app).
class LayoutFont {
  const LayoutFont({required this.id, required this.labelAr, required this.labelEn, this.arabic = true});
  final String id, labelAr, labelEn;
  final bool arabic;

  String label(String lang) => lang == 'ar' ? (labelAr.isEmpty ? labelEn : labelAr) : (labelEn.isEmpty ? labelAr : labelEn);

  /// `{id, family, scripts: ["arabic", "latin"] | ["latin"], bold, italic}` (older shapes: label_ar / label_en).
  factory LayoutFont.fromJson(Map<String, dynamic> j) {
    final family = '${j['family'] ?? j['label'] ?? j['name'] ?? j['id'] ?? ''}';
    final scripts = j['scripts'];
    return LayoutFont(
      id: '${j['id'] ?? j['key'] ?? ''}',
      labelAr: '${j['label_ar'] ?? family}',
      labelEn: '${j['label_en'] ?? family}',
      arabic: scripts is List ? scripts.contains('arabic') : j['arabic'] != false,
    );
  }
}

/// One rendered page of the preview.
class LayoutPreviewPage {
  const LayoutPreviewPage({required this.index, required this.total, required this.png});
  final int index, total;
  final Uint8List png;
}

class LayoutPreview {
  const LayoutPreview(this.pages, this.issues);
  final List<LayoutPreviewPage> pages;
  final List<LayoutIssue> issues;
}

class LayoutValidation {
  const LayoutValidation(this.ok, this.issues);
  final bool ok;
  final List<LayoutIssue> issues;
}

/// A background export (ExportRun).
class LayoutRun {
  const LayoutRun({required this.id, this.status = 'queued', this.progress = 0, this.rows, this.error, this.fileName});
  final String id;

  /// queued | running | done | failed | cancelled
  final String status;

  /// 0 – 100
  final int progress;
  final int? rows;
  final String? error, fileName;

  bool get done => status == 'done' || status == 'succeeded' || status == 'ready';
  bool get failed => status == 'failed' || status == 'error' || status == 'expired';
  bool get cancelled => status == 'cancelled' || status == 'canceled';
  bool get finished => done || failed || cancelled;

  factory LayoutRun.fromJson(Map<String, dynamic> j, {String? id}) => LayoutRun(
        id: '${j['run_id'] ?? j['id'] ?? id ?? ''}',
        status: '${j['status'] ?? 'queued'}',
        progress: ((j['progress'] is num ? j['progress'] as num : num.tryParse('${j['progress'] ?? 0}') ?? 0).clamp(0, 100)).round(),
        rows: j['rows'] is num ? (j['rows'] as num).toInt() : null,
        error: j['error']?.toString(),
        fileName: j['file_name']?.toString(),
      );
}

/// A saved v3 template (list item: no design; [document] after [LayoutApi.template]).
class LayoutTemplate {
  const LayoutTemplate({required this.id, required this.name, this.scope = 'user', this.lang = 'ar', this.format = 'pdf', this.canEdit = true, this.document});
  final int id;
  final String name, scope, lang, format;
  final bool canEdit;
  final LayoutDocument? document;

  bool get isOrg => scope == 'org';

  factory LayoutTemplate.fromJson(Map<String, dynamic> j) {
    final d = j['design'];
    return LayoutTemplate(
      id: j['id'] is num ? (j['id'] as num).toInt() : int.tryParse('${j['id']}') ?? 0,
      name: '${j['name'] ?? ''}',
      scope: '${j['scope'] ?? 'user'}',
      lang: '${j['lang'] ?? 'ar'}',
      format: '${j['format'] ?? 'pdf'}',
      canEdit: j['can_edit'] != false,
      document: d is Map && d['designs'] is Map ? LayoutDocument.fromJson(d.map((k, v) => MapEntry('$k', v))) : null,
    );
  }

  static int? versionOf(Map<String, dynamic> j) {
    final v = j['schema_version'] ?? (j['design'] is Map ? (j['design'] as Map)['schema_version'] : null);
    return v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  }
}

/// A server starter design (`GET /exports/layout/starters`): a ready document the gallery offers.
class LayoutStarter {
  const LayoutStarter({required this.key, this.purpose = 'export', required this.nameAr, required this.nameEn, this.descAr = '', this.descEn = '', this.mode = 'table', this.document});
  final String key, purpose, nameAr, nameEn, descAr, descEn, mode;
  final LayoutDocument? document;

  String name(String lang) => lang == 'ar' ? (nameAr.isEmpty ? nameEn : nameAr) : (nameEn.isEmpty ? nameAr : nameEn);
  String description(String lang) => lang == 'ar' ? (descAr.isEmpty ? descEn : descAr) : (descEn.isEmpty ? descAr : descEn);

  factory LayoutStarter.fromJson(Map<String, dynamic> j) {
    final d = j['document'];
    LayoutDocument? doc;
    try {
      doc = d is Map && d['designs'] is Map ? LayoutDocument.fromJson(d.map((k, v) => MapEntry('$k', v))) : null;
    } catch (_) {
      doc = null;
    }
    return LayoutStarter(
      key: '${j['key'] ?? ''}',
      purpose: '${j['purpose'] ?? 'export'}',
      nameAr: '${j['name_ar'] ?? ''}',
      nameEn: '${j['name_en'] ?? ''}',
      descAr: '${j['description_ar'] ?? ''}',
      descEn: '${j['description_en'] ?? ''}',
      mode: '${j['mode'] ?? 'table'}',
      document: doc,
    );
  }
}

/// What `POST /assets` answered: the asset id and whether it came from a PDF (page 1 stored as a PNG).
class LayoutAssetUpload {
  const LayoutAssetUpload(this.id, {this.fromPdf = false, this.pages = 1, this.page = 1, this.width = 0, this.height = 0});
  final String id;
  final bool fromPdf;

  /// A PDF's page count, and which page became the picture (1-based).
  final int pages, page;

  /// The stored picture's size in pixels (0 when an older server did not say).
  final int width, height;
}

/// The server's limits on `POST /rows` (413 above them): rows and bytes.
const kLayoutMaxRows = 50000;
const kLayoutMaxUploadBytes = 20 * 1024 * 1024;

/// A cheap estimate of the JSON size of [rows] sent as [fields] (a sample of rows, scaled): the real encode of
/// 50 000 rows would cost as much as the upload.
int layoutEstimateUploadBytes(List<LayoutField> fields, List<Map<String, Object?>> rows, String lang) {
  if (rows.isEmpty) return 0;
  final n = rows.length < 200 ? rows.length : 200;
  final step = rows.length / n;
  var sample = 0;
  for (var i = 0; i < n; i++) {
    sample += utf8.encode(jsonEncode(layoutJsonRow(rows[(i * step).floor()], fields, lang))).length + 1;
  }
  return (sample / n * rows.length * 1.05).ceil() + 2048;
}

Map<String, dynamic> _map(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final x in v) if (x is Map) _map(x)] : const [];
List<LayoutIssue> _issues(Object? v) => [for (final j in _maps(v)) LayoutIssue.fromJson(j)];

class LayoutApi {
  LayoutApi({ApiClient? api}) : _api = api;
  static final instance = LayoutApi();

  static const _base = '/api/v1/exports/layout';
  static const _templates = '/api/v1/exports/templates';

  final ApiClient? _api;
  ApiClient get api => _api ?? ApiClient();

  Future<ExportResult<T>> _call<T>(Future<dynamic> Function() fn, T Function(dynamic r) parse) async {
    try {
      return ExportResult.ok(parse(await fn()));
    } catch (e) {
      var x = ApiException.from(e);
      final raw = x.body;
      if (raw is List<int>) {
        try {
          final decoded = jsonDecode(utf8.decode(raw));
          final (code, msg) = ApiException.codedDetail(decoded);
          x = ApiException(statusCode: x.statusCode, message: msg ?? x.message, type: x.type, body: decoded, code: code ?? x.code);
        } catch (_) {}
      }
      final missing = x.statusCode == 405 || (x.statusCode == 404 && _bare404(x.body));
      if (missing) {
        return ExportResult.fail(tx('exs_needs_update', 'This needs a server update', 'هذه الميزة تحتاج تحديث الخادم'), status: x.statusCode, missing: true);
      }
      // a 413 refused before the body was read carries no code
      final code = x.code ?? ApiException.codedDetail(x.body).$1 ?? (x.statusCode == 413 ? 'upload_too_big' : null);
      return ExportResult.fail(layoutErrorText(code, x.message), code: code, status: x.statusCode);
    }
  }

  static bool _bare404(Object? body) => body is Map && body['detail'] == 'Not Found';

  /// `GET /fonts` — the renderer's catalog (the ONLY font list: Scheherazade New, Reem Kufi and Aref Ruqaa are not
  /// in it, the renderer cannot join their Arabic).
  Future<ExportResult<List<LayoutFont>>> fonts() => _call(() => api.get('$_base/fonts'), (r) {
        final items = r is List ? _maps(r) : _maps(_map(r)['items'] ?? _map(r)['fonts']);
        return [for (final j in items) LayoutFont.fromJson(j)]..removeWhere((f) => f.id.isEmpty);
      });

  Future<ExportResult<LayoutValidation>> validate(LayoutDocument doc) => _call(
        () => api.post('$_base/validate', body: {'document': doc.toJson()}),
        (r) => LayoutValidation(_map(r)['ok'] != false, _issues(_map(r)['issues'])),
      );

  /// `POST /preview` — the first, middle and last page of [lang]'s file as PNGs, rendered by the file's own renderer.
  Future<ExportResult<LayoutPreview>> preview(LayoutDocument doc, {required String lang, String pages = 'first,middle,last', int sample = 200, String? title}) => _call(
        () => api.post('$_base/preview', body: {'document': doc.toJson(), 'lang': lang, 'pages': pages, 'sample': sample, 'title': ?title}),
        (r) {
          final m = _map(r);
          return LayoutPreview([
            for (final p in _maps(m['pages']))
              if ('${p['png_b64'] ?? ''}'.isNotEmpty)
                LayoutPreviewPage(
                  index: p['index'] is num ? (p['index'] as num).toInt() : 1,
                  total: p['total'] is num ? (p['total'] as num).toInt() : 1,
                  png: base64Decode('${p['png_b64']}'),
                ),
          ], _issues(m['issues']));
        },
      );

  /// `POST /rows` — an app table with no server dataset: its columns (key, labels, type) and rows. → upload id.
  /// The values are what the table shows in [lang] ([layoutJsonRow]: wall-clock dates, status labels).
  Future<ExportResult<String>> uploadRows(List<LayoutField> fields, List<Map<String, Object?>> rows, {String lang = 'ar', void Function(int sent, int total)? onProgress}) {
    // the server refuses more than 50 000 rows / 20 MB: say so before sending anything
    if (rows.length > kLayoutMaxRows) {
      final n = rows.length;
      return Future.value(ExportResult.fail(
          AppConfig.lang == 'ar'
              ? 'عدد الصفوف ($n) أكبر من المسموح ($kLayoutMaxRows صف كحد أقصى): قلّل الصفوف بالتصفية ثم أعد التصدير'
              : 'Too many rows for one export: $n rows, $kLayoutMaxRows at most. Filter the table and export again',
          code: 'rows_too_many'));
    }
    final bytes = layoutEstimateUploadBytes(fields, rows, lang);
    if (bytes > kLayoutMaxUploadBytes) {
      String mb(int b) => (b / 1048576).toStringAsFixed(1);
      return Future.value(ExportResult.fail(
          AppConfig.lang == 'ar'
              ? 'حجم الصفوف ${mb(bytes)} ميجابايت وهو أكبر من المسموح (${mb(kLayoutMaxUploadBytes)} ميجابايت): قلّل الصفوف أو الأعمدة'
              : 'The rows are too large to send: ${mb(bytes)} MB, ${mb(kLayoutMaxUploadBytes)} MB at most. Remove rows or columns',
          code: 'rows_too_big'));
    }
    return _uploadRows(fields, rows, lang, onProgress);
  }

  Future<ExportResult<String>> _uploadRows(List<LayoutField> fields, List<Map<String, Object?>> rows, String lang, void Function(int, int)? onProgress) => _call(
        () => api.post('$_base/rows', body: {
          'columns': [for (final f in fields) f.toJson()],
          'rows': [for (final r in rows) layoutJsonRow(r, fields, lang)],
        }, onSendProgress: onProgress),
        (r) => '${_map(r)['upload_id'] ?? ''}',
      );

  /// `GET /starters?purpose=` — the server's ready designs for the gallery (older servers: `missing`).
  Future<ExportResult<List<LayoutStarter>>> starters({String purpose = 'export'}) => _call(
        () => api.get('$_base/starters', queryParams: {'purpose': purpose}),
        (r) {
          final items = r is List ? _maps(r) : _maps(_map(r)['items'] ?? _map(r)['starters']);
          return [for (final j in items) LayoutStarter.fromJson(j)]..removeWhere((x) => x.key.isEmpty || x.document == null);
        },
      );

  /// `GET /api/v1/exports/datasets/{key}/columns` — the dataset's columns the caller may see with [params]
  /// (`{key, label_ar, label_en, type}`): the field keys the server renders for a dataset source.
  Future<ExportResult<List<Map<String, dynamic>>>> datasetColumns(String key, Map<String, Object?> params) => _call(
        () => api.get('/api/v1/exports/datasets/${Uri.encodeComponent(key)}/columns', queryParams: {
          for (final e in params.entries)
            if (e.value != null) e.key: e.value is List ? (e.value as List).join(',') : '${e.value}',
        }),
        (r) => _maps(_map(r)['columns']),
      );

  /// `POST /assets` — an image (PNG / JPEG ≤ 2 MB) or a PDF (≤ 10 MB: the server keeps page 1 as a PNG). → asset id.
  Future<ExportResult<String>> uploadAsset(Uint8List bytes, String name) async {
    final r = await uploadAssetInfo(bytes, name);
    return r.ok ? ExportResult.ok(r.data!.id) : ExportResult.fail(r.error!, code: r.code, status: r.status, missing: r.missing);
  }

  /// Like [uploadAsset] with the server's extras: `from_pdf` / `pages` when a PDF was rasterised.
  /// [page]: which page of a PDF becomes the picture (an exam cover may be any page, D-730); older servers keep page 1.
  Future<ExportResult<LayoutAssetUpload>> uploadAssetInfo(Uint8List bytes, String name, {int page = 1}) => _call(
        () => api.postFiles(page > 1 ? '$_base/assets?page=$page' : '$_base/assets', files: [(name, bytes)], field: 'file'),
        (r) {
          final m = _map(r);
          int n(Object? v, int d) => v is num ? v.toInt() : d;
          return LayoutAssetUpload('${m['asset_id'] ?? ''}',
              fromPdf: m['from_pdf'] == true, pages: n(m['pages'], 1), page: n(m['page'], 1), width: n(m['width'], 0), height: n(m['height'], 0));
        },
      );


  /// `GET /assets/{id}` — a placed image's bytes (the app's own renderers draw exam papers on the device, D-196).
  Future<ExportResult<Uint8List>> assetBytes(String id) =>
      _call(() => api.getBytes('$_base/assets/${Uri.encodeComponent(id)}'), (r) => r as Uint8List);

  /// `POST /assets/keep` — a design saved outside the export templates (an exam paper) names these images: the
  /// server keeps them instead of expiring them 30 days after upload. → how many it kept.
  Future<ExportResult<int>> keepAssets(Iterable<String> ids) =>
      _call(() => api.post('$_base/assets/keep', body: {'tokens': ids.take(50).toList()}), (r) => (_map(r)['kept'] as num?)?.toInt() ?? 0);

  /// `POST /runs` — 202 {run_id}.
  Future<ExportResult<String>> startRun(LayoutDocument doc, {required String name}) => _call(
        () => api.post('$_base/runs', body: {'document': doc.toJson(), 'name': name}),
        (r) => '${_map(r)['run_id'] ?? _map(r)['id'] ?? ''}',
      );

  Future<ExportResult<LayoutRun>> run(String id) => _call(() => api.get('$_base/runs/$id'), (r) => LayoutRun.fromJson(_map(r), id: id));

  Future<ExportResult<Uint8List>> download(String id) => _call(() => api.getBytes('$_base/runs/$id/download'), (r) => r as Uint8List);

  Future<ExportResult<bool>> cancel(String id) => _call(() => api.post('$_base/runs/$id/cancel', body: const {}), (_) => true);

  // ── templates (schema_version 3 on /api/v1/exports/templates) ─────────────────────────────────────────────────
  /// The v3 templates of [pageKey] (older-schema templates of the page are left out) and the last one used.
  Future<ExportResult<(List<LayoutTemplate>, int?)>> templates({required String pageKey, int? orgId}) => _call(
        () => api.get(_templates, queryParams: {'page_key': exportPageKey(pageKey), 'org_id': ?orgId}),
        (r) {
          final m = _map(r);
          final items = [for (final j in _maps(m['items'])) if (kLayoutSchemaVersions.contains(LayoutTemplate.versionOf(j) ?? 3)) LayoutTemplate.fromJson(j)];
          final last = m['last_used_id'];
          return (items, last is num ? last.toInt() : null);
        },
      );

  Future<ExportResult<LayoutTemplate>> template(int id) => _call(() => api.get('$_templates/$id'), (r) => LayoutTemplate.fromJson(_map(r)));

  /// Saves [doc] (minus its source) as a named template: [scope] user | org (org needs [orgId]).
  Future<ExportResult<LayoutTemplate>> saveTemplate({required String pageKey, required String name, required LayoutDocument doc, String scope = 'user', int? orgId}) => _call(
        () => api.post(_templates, body: {
          'scope': scope,
          'org_id': scope == 'org' ? orgId : null,
          'page_key': exportPageKey(pageKey),
          'format': doc.format,
          'lang': doc.langKey,
          'name': name.trim(),
          'schema_version': kLayoutSchemaVersion,
          'design': doc.toJson(withSource: false),
          'columns': const [],
          'rules': const [],
          'options': const {},
        }),
        (r) => LayoutTemplate.fromJson(_map(r)),
      );

  /// Fire-and-forget "used" mark (the server's last-used template).
  void markUsed(int id) => unawaited(_call(() => api.post('$_templates/$id/used', body: const {}), (_) => true));
}

/// One uploaded row as JSON: [layoutRowValue] per field (dates as the wall clock without an offset, a status as its
/// label in [lang]); a value that is still a DateTime (not a date field) is sent as its wall clock too.
Map<String, Object?> layoutJsonRow(Map<String, Object?> r, List<LayoutField> fields, String lang) => {
      for (final f in fields)
        f.key: switch (layoutRowValue(f, r[f.key], lang)) {
          final DateTime d => layoutRowValue(LayoutField(key: f.key, labelAr: '', labelEn: '', type: 'datetime'), d, lang),
          final num n => n,
          final bool b => b,
          null => null,
          final v => '$v',
        },
    };

/// Bilingual text for the layout routes' error codes.
String layoutErrorText(String? code, [String? fallback]) => switch (code) {
      'rows_too_many' => tx('lay_err_rows_many', 'Too many rows for one export (50,000 at most)', 'عدد الصفوف أكبر من المسموح (50٬000 صف كحد أقصى)'),
      'rows_invalid' => tx('lay_err_rows_invalid', 'The rows could not be read: export again', 'تعذّرت قراءة الصفوف: أعد التصدير'),
      'preview_busy' => tx('lay_err_preview_busy', 'A preview is already being prepared: try again in a moment', 'تُجهَّز معاينة أخرى الآن: حاول بعد لحظات'),
      'preview_timeout' => tx('lay_err_preview_timeout', 'The preview took too long: simplify the design or try again',
          'استغرقت المعاينة وقتًا طويلًا: بسّط التصميم أو حاول مجددًا'),
      'render_timeout' => tx('lay_err_render_timeout', 'Creating the file took too long: try again, or export fewer items',
          'استغرق إنشاء الملف وقتًا طويلًا: حاول مجددًا أو صدّر عناصر أقل'),
      'asset_quota' => tx('lay_err_asset_quota', 'You have reached your image storage limit', 'بلغت الحد المسموح لتخزين الصور'),
      'asset_too_large' || 'image_too_large' || 'asset_pixels' => tx('lay_err_asset_pixels', 'The image is too large (16 megapixels at most)', 'الصورة كبيرة جدًا (16 ميجابكسل كحد أقصى)'),
      'rows_too_big' || 'payload_too_big' || 'upload_too_big' => tx('lay_err_rows_big', 'The rows are too large to send (20 MB at most)', 'حجم الصفوف أكبر من المسموح (20 ميجابايت)'),
      'upload_expired' || 'upload_not_found' => tx('lay_err_upload', 'The uploaded rows expired: export again', 'انتهت صلاحية الصفوف المرفوعة: أعد التصدير'),
      'asset_too_big' => tx('lay_err_asset_big', 'The image is larger than 2 MB', 'الصورة أكبر من 2 ميجابايت'),
      'asset_type' || 'asset_invalid' || 'asset_type_invalid' => tx('lay_err_asset_type', 'Use a PNG or JPEG image, or a PDF', 'استخدم صورة PNG أو JPEG أو ملف PDF'),
      'run_not_found' => tx('lay_err_run', 'This export no longer exists', 'هذا التصدير لم يعد موجودًا'),
      'run_not_ready' => tx('lay_err_not_ready', 'The file is not ready yet', 'الملف لم يجهز بعد'),
      'run_not_cancelable' => tx('lay_err_not_cancelable', 'This export has already finished', 'انتهى هذا التصدير بالفعل'),
      'feature_disabled' => tx('lay_err_disabled', 'This export is switched off on this platform', 'هذا التصدير موقوف على المنصة'),
      'layout_invalid' || 'document_invalid' => tx('lay_err_invalid', 'The design has a problem: check the notes', 'في التصميم مشكلة: راجع الملاحظات'),
      'font_unknown' => tx('lay_err_font', 'A font of the design is not available on the server', 'أحد خطوط التصميم غير متاح على الخادم'),
      'server_busy' => tx('lay_err_busy', 'The server is busy: try again in a moment', 'الخادم مشغول: حاول بعد لحظات'),
      _ => exportStudioErrorText(code, fallback),
    };

/// Waits on a run: the live `job_updated` event for it (SSE / silent push) wakes it at once, a slow poll is only the
/// fallback. [onUpdate] gets every status read; the returned future ends with the finished run (or null when
/// [cancel]led / failed to read).
class LayoutRunWatch {
  LayoutRunWatch(this.api, this.runId, {LiveStreamHandle? stream, this.every = const Duration(seconds: 2), this.fallbackEvery = const Duration(seconds: 8)})
      : _stream = stream;

  final LayoutApi api;
  final String runId;
  final LiveStreamHandle? _stream;
  final Duration every, fallbackEvery;
  bool _stopped = false;
  JobWatch? _watch;

  void stop() {
    _stopped = true;
    _watch?.dispose();
  }

  Future<ExportResult<LayoutRun>> wait(void Function(LayoutRun run) onUpdate) async {
    final w = _watch = JobWatch(id: runId, kind: 'export', stream: _stream);
    var failures = 0;
    try {
      while (!_stopped) {
        final r = await api.run(runId);
        if (_stopped) break;
        if (!r.ok) {
          if (++failures >= 3 || r.missing) return r;
        } else {
          failures = 0;
          onUpdate(r.data!);
          if (r.data!.finished) return r;
        }
        await w.next(every, fallbackEvery: fallbackEvery);
      }
      return ExportResult.fail(tx('lay_cancelled', 'Cancelled', 'أُلغي'), code: 'cancelled');
    } finally {
      w.dispose();
    }
  }
}
