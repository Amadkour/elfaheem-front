// lib/design/export/export_studio_api.dart
//
// The Export Studio's server side, `/api/v1/exports` (../back/routers/export_router.py, FLUTTER_API_CHANGES.md
// "Export Studio"): templates per user / organization with defaults and "last used", the export log, server
// datasets, scheduled exports and their runs, and expiring sign-in links (D-134).
//
//     final r = await ExportStudioApi.instance.templates(pageKey: 'admin.users', format: 'pdf', lang: 'ar');
//     if (r.ok) …r.data!.items   else if (r.missing) …older server   else showAppNotice(r.error!, error: true)
//
// Every call answers an [ExportResult] (never throws): `missing` = the server has no such route (FastAPI's bare 404
// / a 405) → the screen says it needs a server update; `error` is already a bilingual sentence (codes mapped in
// [exportStudioErrorText]). [ExportStudioApi.log] is fire-and-forget: it never blocks or fails an export.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';

import 'export_studio_model.dart';
import 'table_export_model.dart' show tx;

const exportsBase = '/api/v1/exports';

/// The deep link a share link opens in the app (`/e/<token>`, handled in main.dart → ExportLinkOpenPage).
String exportLinkUrl(String token) => 'https://nextbrain.site/e/$token';

// ═════════════════════════════════════════════════════════════════════════════
//  Result + error text
// ═════════════════════════════════════════════════════════════════════════════

class ExportResult<T> {
  const ExportResult._(this.data, this.error, this.code, this.status, this.missing);
  factory ExportResult.ok(T data) => ExportResult._(data, null, null, 200, false);
  factory ExportResult.fail(String error, {String? code, int status = 0, bool missing = false}) =>
      ExportResult._(null, error, code, status, missing);

  final T? data;
  final String? error, code;
  final int status;

  /// The server lacks the route (an older backend).
  final bool missing;

  bool get ok => error == null;
}

/// Bilingual text for the export routes' error codes (server `detail.code`); [fallback] otherwise.
String exportStudioErrorText(String? code, [String? fallback]) {
  final s = switch (code) {
    'template_forbidden' => tx('exs_err_template_forbidden', 'You may not change this template', 'لا تملك صلاحية تعديل هذا القالب'),
    'template_not_found' => tx('exs_err_template_not_found', 'This template no longer exists', 'هذا القالب لم يعد موجودًا'),
    'org_required' => tx('exs_err_org_required', 'Choose the organization for an organization template', 'اختر المؤسسة لقالب المؤسسة'),
    'org_forbidden' => tx('exs_err_org_forbidden', 'You are not a member of this organization', 'لست عضوًا في هذه المؤسسة'),
    'template_not_org' => tx('exs_err_template_not_org', 'A personal template cannot be the organization default', 'القالب الشخصي لا يكون افتراضيًا للمؤسسة'),
    'page_key_invalid' => tx('exs_err_page_key', 'This page cannot store templates', 'لا يمكن حفظ قوالب لهذه الصفحة'),
    'design_too_big' => tx('exs_err_design_big', 'The design is too large to save (512 KB)', 'التصميم أكبر من المسموح (512 كيلوبايت)'),
    'schema_version_unsupported' => tx('exs_err_schema', 'This template needs a newer app', 'هذا القالب يحتاج إصدارًا أحدث من التطبيق'),
    'rules_invalid' || 'columns_invalid' || 'options_invalid' || 'design_invalid' =>
      tx('exs_err_invalid', 'Something in the design is not valid', 'في التصميم قيمة غير صالحة'),
    'export_log_forbidden' => tx('exs_err_log_forbidden', 'You may not read this export log', 'لا تملك صلاحية على هذا السجل'),
    'feature_disabled' => tx('exs_err_feature_disabled', 'This feature is switched off', 'هذه الميزة متوقفة'),
    'dataset_not_found' => tx('exs_err_dataset', 'This data source is not available', 'مصدر البيانات غير متاح'),
    'dataset_forbidden' => tx('exs_err_dataset_forbidden', 'You may not export this data', 'لا تملك صلاحية تصدير هذه البيانات'),
    'dataset_params_invalid' => tx('exs_err_params', 'The data source settings are not valid', 'إعدادات مصدر البيانات غير صالحة'),
    'schedule_not_found' => tx('exs_err_schedule', 'This schedule no longer exists', 'هذه الجدولة لم تعد موجودة'),
    'run_not_found' => tx('exs_err_run', 'This file no longer exists', 'هذا الملف لم يعد موجودًا'),
    'run_not_ready' => tx('exs_err_run_not_ready', 'The file is not ready yet', 'الملف لم يجهز بعد'),
    'run_expired' => tx('exs_err_run_expired', 'This file has expired', 'انتهت صلاحية هذا الملف'),
    'link_not_found' => tx('exs_err_link_not_found', 'This link is not valid', 'هذا الرابط غير صالح'),
    'link_expired' => tx('exs_err_link_expired', 'This link has expired', 'انتهت صلاحية هذا الرابط'),
    'link_revoked' => tx('exs_err_link_revoked', 'This link was revoked', 'أُلغي هذا الرابط'),
    'link_forbidden' => tx('exs_err_link_forbidden', 'You may not open this file', 'لا تملك صلاحية فتح هذا الملف'),
    'link_other_org' => tx('exs_err_link_other_org', 'This link is for members of another organization', 'هذا الرابط لأعضاء مؤسسة أخرى'),
    'file_too_big' => tx('exs_err_too_large', 'The file is larger than 25 MB', 'الملف أكبر من 25 ميجابايت'),
    'file_type_invalid' => tx('exs_err_type', 'Only Excel, Word and PDF files can be shared', 'يمكن مشاركة ملفات Excel وWord وPDF فقط'),
    'recipients_invalid' => tx('exs_err_recipients', 'Check the e-mail addresses', 'راجع عناوين البريد'),
    'recipient_not_allowed' => tx('exs_err_recipient_not_allowed', 'Files can only be e-mailed to people of the same organization', 'يُرسل الملف بالبريد لأعضاء المؤسسة نفسها فقط'),
    'delivery_invalid' => tx('exs_err_delivery', 'Choose how the file is delivered', 'اختر طريقة التسليم'),
    'cadence_invalid' => tx('exs_err_cadence', 'Check the repeat settings', 'راجع إعدادات التكرار'),
    'timezone_invalid' => tx('exs_err_timezone', 'The timezone is not valid', 'المنطقة الزمنية غير صالحة'),
    'schedule_limit' => tx('exs_err_schedule_limit', 'You reached the number of scheduled exports allowed', 'وصلت إلى الحد المسموح من التصديرات المجدولة'),
    'runs_in_flight' => tx('exs_err_runs_in_flight', 'Several files are being prepared — try again in a minute', 'تُجهَّز ملفات عدة الآن — حاول بعد دقيقة'),
    'owner_inactive' => tx('exs_err_owner_inactive', 'The account that owns this export is no longer active', 'الحساب صاحب هذا التصدير لم يعد نشطًا'),
    'export_forbidden' => tx('exs_err_export_forbidden', 'You may not export this data', 'لا تملك صلاحية تصدير هذه البيانات'),
    'link_expiry_invalid' => tx('exs_err_link_expiry', 'A link lasts 1 to 30 days', 'مدة الرابط من يوم إلى 30 يومًا'),
    'audience_needs_org' => tx('exs_err_audience_org', 'Sharing with the organization needs an organization', 'المشاركة مع المؤسسة تحتاج مؤسسة'),
    'filters_invalid' || 'filters_too_big' => tx('exs_err_filters', 'The filters could not be saved with the export', 'تعذّر حفظ التصفية مع التصدير'),
    'format_invalid' => tx('exs_err_format', 'This format or language is not supported', 'الصيغة أو اللغة غير مدعومة'),
    'not_authenticated' => tx('exs_err_signin', 'Sign in to continue', 'سجّل الدخول للمتابعة'),
    _ => null,
  };
  return s ?? (fallback == null || fallback.trim().isEmpty ? tx('exs_err_generic', 'Something went wrong. Try again.', 'حدث خطأ. حاول مرة أخرى.') : fallback);
}

bool _missing(ApiException e) =>
    e.statusCode == 405 || (e.statusCode == 404 && ApiException.asMap(e.body)?['detail'] == 'Not Found');

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? v) => [if (v is List) for (final x in v) if (x is Map) x.cast<String, dynamic>()];

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

DateTime? _date(Object? v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty) return null;
  final iso = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(s) ? s : '${s}Z'; // naive UTC
  return DateTime.tryParse(iso)?.toUtc();
}

// ═════════════════════════════════════════════════════════════════════════════
//  Models
// ═════════════════════════════════════════════════════════════════════════════

/// One saved template (`GET /templates` items carry no design; `GET /templates/{id}` does).
class StudioTemplate {
  StudioTemplate({
    required this.id,
    required this.name,
    this.scope = 'user',
    this.orgId,
    this.ownerId,
    this.pageKey = '',
    this.format = 'xlsx',
    this.lang = 'ar',
    this.isOrgDefault = false,
    this.canEdit = true,
    this.updatedAt,
    this.design,
    List<Map<String, dynamic>>? columns,
    List<ExportRule>? rules,
    Map<String, dynamic>? options,
  })  : columns = columns ?? [],
        rules = rules ?? [],
        options = options ?? {};

  final int id;
  String name;

  /// user | org
  final String scope;
  final int? orgId, ownerId;
  final String pageKey, format, lang;
  bool isOrgDefault;
  final bool canEdit;
  final DateTime? updatedAt;

  /// The ExportDesign JSON (null on list items).
  final Map<String, dynamic>? design;

  /// [{key, label_ar, label_en, width?, hidden?}] in order.
  final List<Map<String, dynamic>> columns;
  final List<ExportRule> rules;
  final Map<String, dynamic> options;

  bool get isOrg => scope == 'org';
  bool get hasBody => design != null;

  factory StudioTemplate.fromJson(Map<String, dynamic> j) => StudioTemplate(
        id: _int(j['id']) ?? 0,
        name: '${j['name'] ?? ''}',
        scope: '${j['scope'] ?? 'user'}',
        orgId: _int(j['org_id']),
        ownerId: _int(j['owner_id']),
        pageKey: '${j['page_key'] ?? ''}',
        format: '${j['format'] ?? 'xlsx'}',
        lang: '${j['lang'] ?? 'ar'}',
        isOrgDefault: j['is_org_default'] == true,
        canEdit: j['can_edit'] != false,
        updatedAt: _date(j['updated_at']),
        design: j['design'] is Map ? _map(j['design']) : null,
        columns: _maps(j['columns']),
        rules: ExportRule.listFromJson(j['rules']),
        options: _map(j['options']),
      );
}

class StudioTemplateList {
  const StudioTemplateList(this.items, {this.defaultId, this.myDefaultId, this.orgDefaultId, this.lastUsedId});
  final List<StudioTemplate> items;

  /// my default › the organization's; then the last one I used.
  final int? defaultId, myDefaultId, orgDefaultId, lastUsedId;

  /// The template the flow starts with: the default, else the last used.
  int? get preferredId => defaultId ?? lastUsedId;
}

class ExportDatasetInfo {
  const ExportDatasetInfo({required this.key, required this.titleAr, required this.titleEn, this.params = const []});
  final String key, titleAr, titleEn;
  final List<String> params;

  String title(String lang) => (lang == 'ar' ? titleAr : titleEn).isNotEmpty ? (lang == 'ar' ? titleAr : titleEn) : key;

  factory ExportDatasetInfo.fromJson(Map<String, dynamic> j) => ExportDatasetInfo(
        key: '${j['key'] ?? ''}',
        titleAr: '${j['title_ar'] ?? ''}',
        titleEn: '${j['title_en'] ?? ''}',
        params: [
          if (j['params'] is List) for (final p in j['params'] as List) p is Map ? '${p['key'] ?? p['name'] ?? ''}' : '$p',
          if (j['params'] is Map) for (final k in (j['params'] as Map).keys) '$k',
        ]..removeWhere((p) => p.isEmpty),
      );
}

class ExportScheduleInfo {
  ExportScheduleInfo({
    required this.id,
    this.name = '',
    this.orgId,
    this.dataset = '',
    Map<String, dynamic>? params,
    this.templateId,
    this.format = 'xlsx',
    this.lang = 'ar',
    this.cadence = 'weekly',
    this.hour = 7,
    this.minute = 0,
    this.weekday,
    this.monthday,
    this.timezone = 'UTC',
    this.delivery = 'list',
    List<String>? recipients,
    this.status = 'active',
    this.pauseReason,
    this.nextRunAt,
    this.lastRunAt,
    this.lastStatus,
    this.failCount = 0,
  })  : params = params ?? {},
        recipients = recipients ?? [];

  final int id;
  final String name;
  final int? orgId;
  final String dataset;
  final Map<String, dynamic> params;
  final int? templateId;
  final String format, lang, cadence, timezone, delivery, status;
  final int hour, minute;
  final int? weekday, monthday;
  final List<String> recipients;
  final String? pauseReason, lastStatus;
  final DateTime? nextRunAt, lastRunAt;
  final int failCount;

  bool get paused => status != 'active';

  factory ExportScheduleInfo.fromJson(Map<String, dynamic> j) => ExportScheduleInfo(
        id: _int(j['id']) ?? 0,
        name: '${j['name'] ?? ''}',
        orgId: _int(j['org_id']),
        dataset: '${j['dataset'] ?? ''}',
        params: _map(j['params']),
        templateId: _int(j['template_id']),
        format: '${j['format'] ?? 'xlsx'}',
        lang: '${j['lang'] ?? 'ar'}',
        cadence: '${j['cadence'] ?? 'weekly'}',
        hour: _int(j['hour']) ?? 7,
        minute: _int(j['minute']) ?? 0,
        weekday: _int(j['weekday']),
        monthday: _int(j['monthday']),
        timezone: '${j['timezone'] ?? 'UTC'}',
        delivery: '${j['delivery'] ?? 'list'}',
        recipients: [if (j['recipients'] is List) for (final r in j['recipients'] as List) '$r'],
        status: '${j['status'] ?? 'active'}',
        pauseReason: j['pause_reason']?.toString(),
        nextRunAt: _date(j['next_run_at']),
        lastRunAt: _date(j['last_run_at']),
        lastStatus: j['last_status']?.toString(),
        failCount: _int(j['fail_count']) ?? 0,
      );

  /// The body of POST / PUT (the server's ScheduleIn).
  static Map<String, dynamic> body({
    String? name,
    required String dataset,
    Map<String, dynamic> params = const {},
    int? templateId,
    String format = 'xlsx',
    String lang = 'ar',
    String cadence = 'weekly',
    int hour = 7,
    int minute = 0,
    int? weekday,
    int? monthday,
    String timezone = 'UTC',
    String delivery = 'list',
    List<String> recipients = const [],
  }) =>
      {
        if ((name ?? '').trim().isNotEmpty) 'name': name!.trim(),
        'dataset': dataset,
        'params': params,
        'template_id': templateId,
        'format': format,
        'lang': lang,
        'cadence': cadence,
        'hour': hour,
        'minute': minute,
        'weekday': cadence == 'weekly' ? (weekday ?? 0) : null,
        'monthday': cadence == 'monthly' ? (monthday ?? 1) : null,
        'timezone': timezone,
        'delivery': delivery,
        'recipients': delivery == 'email' ? recipients : const <String>[],
      };
}

class ExportRunInfo {
  const ExportRunInfo({
    required this.id,
    this.scheduleId,
    this.dataset = '',
    this.format = 'xlsx',
    this.lang = 'ar',
    this.status = 'queued',
    this.fileName,
    this.size,
    this.rows,
    this.error,
    this.createdAt,
    this.finishedAt,
    this.expiresAt,
  });

  final int id;
  final int? scheduleId;
  final String dataset, format, lang;

  /// queued | running | done | failed | expired
  final String status;
  final String? fileName, error;
  final int? size, rows;
  final DateTime? createdAt, finishedAt, expiresAt;

  bool get ready => status == 'done' || status == 'succeeded' || status == 'ready';
  bool get failed => status == 'failed' || status == 'error';
  bool get pending => status == 'queued' || status == 'running';

  factory ExportRunInfo.fromJson(Map<String, dynamic> j) => ExportRunInfo(
        id: _int(j['id']) ?? 0,
        scheduleId: _int(j['schedule_id']),
        dataset: '${j['dataset'] ?? ''}',
        format: '${j['format'] ?? 'xlsx'}',
        lang: '${j['lang'] ?? 'ar'}',
        status: '${j['status'] ?? 'queued'}',
        fileName: j['file_name']?.toString(),
        size: _int(j['size']),
        rows: _int(j['rows']),
        error: j['error']?.toString(),
        createdAt: _date(j['created_at']),
        finishedAt: _date(j['finished_at']),
        expiresAt: _date(j['expires_at']),
      );
}

class ExportLinkInfo {
  const ExportLinkInfo({
    required this.id,
    this.runId,
    this.fileName,
    this.size,
    this.dataset,
    this.orgId,
    this.audience = 'org',
    this.note,
    this.expiresAt,
    this.revokedAt,
    this.downloadCount = 0,
    this.lastDownloadAt,
    this.createdAt,
    this.token,
  });

  final int id;
  final int? runId, size, orgId;
  final String? fileName, dataset, note;

  /// me | org
  final String audience;
  final DateTime? expiresAt, revokedAt, lastDownloadAt, createdAt;
  final int downloadCount;

  /// Returned ONCE, when the link is created.
  final String? token;

  bool get revoked => revokedAt != null;
  bool expiredAt(DateTime nowUtc) => expiresAt != null && !expiresAt!.isAfter(nowUtc);
  bool activeAt(DateTime nowUtc) => !revoked && !expiredAt(nowUtc);
  String? get url => token == null ? null : exportLinkUrl(token!);

  factory ExportLinkInfo.fromJson(Map<String, dynamic> j) => ExportLinkInfo(
        id: _int(j['id']) ?? 0,
        runId: _int(j['run_id']),
        fileName: j['file_name']?.toString(),
        size: _int(j['size']),
        dataset: j['dataset']?.toString(),
        orgId: _int(j['org_id']),
        audience: '${j['audience'] ?? 'org'}',
        note: j['note']?.toString(),
        expiresAt: _date(j['expires_at']),
        revokedAt: _date(j['revoked_at']),
        downloadCount: _int(j['download_count']) ?? 0,
        lastDownloadAt: _date(j['last_download_at']),
        createdAt: _date(j['created_at']),
        token: (j['token'] ?? '').toString().isEmpty ? null : '${j['token']}',
      );
}

class ExportLogEntry {
  const ExportLogEntry({
    required this.id,
    this.userId,
    this.userName,
    this.orgId,
    this.channel = 'interactive',
    this.pageKey = '',
    this.dataset,
    this.format = 'xlsx',
    this.lang,
    this.rows,
    this.columns = const [],
    this.templateId,
    this.filters = const {},
    this.createdAt,
  });

  final int id;
  final int? userId, orgId, rows, templateId;
  final String? userName, dataset, lang;

  /// interactive | schedule | link
  final String channel;
  final String pageKey, format;
  final List<String> columns;
  final Map<String, dynamic> filters;
  final DateTime? createdAt;

  factory ExportLogEntry.fromJson(Map<String, dynamic> j) {
    final u = _map(j['user']);
    return ExportLogEntry(
      id: _int(j['id']) ?? 0,
      userId: _int(u['id']),
      userName: u['name']?.toString(),
      orgId: _int(j['org_id']),
      channel: '${j['channel'] ?? 'interactive'}',
      pageKey: '${j['page_key'] ?? ''}',
      dataset: j['dataset']?.toString(),
      format: '${j['format'] ?? 'xlsx'}',
      lang: j['lang']?.toString(),
      rows: _int(j['rows']),
      columns: [if (j['columns'] is List) for (final c in j['columns'] as List) '$c'],
      templateId: _int(j['template_id']),
      filters: _map(j['filters']),
      createdAt: _date(j['created_at']),
    );
  }
}

class ExportPage<T> {
  const ExportPage(this.items, {this.total = 0, this.page = 1, this.size = 50, this.pages = 1});
  final List<T> items;
  final int total, page, size, pages;
  bool get hasMore => page < pages;
}

// ═════════════════════════════════════════════════════════════════════════════
//  API
// ═════════════════════════════════════════════════════════════════════════════

class ExportStudioApi {
  ExportStudioApi({ApiClient? api}) : _api = api;
  static final instance = ExportStudioApi();

  final ApiClient? _api;
  ApiClient get api => _api ?? ApiClient();

  Future<ExportResult<T>> _call<T>(Future<dynamic> Function() fn, T Function(dynamic r) parse) async {
    try {
      return ExportResult.ok(parse(await fn()));
    } catch (e) {
      var x = ApiException.from(e);
      // a bytes request (download) carries its JSON error body as bytes: decode it to keep the code
      final raw = x.body;
      if (raw is List<int>) {
        try {
          final decoded = jsonDecode(utf8.decode(raw));
          final (code, msg) = ApiException.codedDetail(decoded);
          x = ApiException(statusCode: x.statusCode, message: msg ?? x.message, type: x.type, body: decoded, code: code ?? x.code);
        } catch (_) {}
      }
      if (_missing(x)) {
        return ExportResult.fail(tx('exs_needs_update', 'This needs a server update', 'هذه الميزة تحتاج تحديث الخادم'),
            status: x.statusCode, missing: true);
      }
      final code = x.code ?? ApiException.codedDetail(x.body).$1;
      return ExportResult.fail(exportStudioErrorText(code, x.message), code: code, status: x.statusCode);
    }
  }

  // ── templates ──────────────────────────────────────────────────────────────
  Future<ExportResult<StudioTemplateList>> templates({String? pageKey, String? format, String? lang, int? orgId}) => _call(
        () => api.get('$exportsBase/templates', queryParams: {'page_key': ?pageKey, 'format': ?format, 'lang': ?lang, 'org_id': ?orgId}),
        (r) {
          final m = _map(r);
          return StudioTemplateList(
            [for (final j in _maps(m['items'])) StudioTemplate.fromJson(j)],
            defaultId: _int(m['default_id']),
            myDefaultId: _int(m['my_default_id']),
            orgDefaultId: _int(m['org_default_id']),
            lastUsedId: _int(m['last_used_id']),
          );
        },
      );

  Future<ExportResult<StudioTemplate>> template(int id) =>
      _call(() => api.get('$exportsBase/templates/$id'), (r) => StudioTemplate.fromJson(_map(r)));

  /// [scope] user | org (org needs [orgId] and the right: 403 template_forbidden otherwise).
  Future<ExportResult<StudioTemplate>> createTemplate({
    required String pageKey,
    required String format,
    required String lang,
    required String name,
    String scope = 'user',
    int? orgId,
    Map<String, dynamic> design = const {},
    List<Map<String, dynamic>> columns = const [],
    List<ExportRule> rules = const [],
    Map<String, dynamic> options = const {},
  }) =>
      _call(
        () => api.post('$exportsBase/templates', body: {
          'scope': scope,
          'org_id': scope == 'org' ? orgId : null,
          'page_key': exportPageKey(pageKey),
          'format': format,
          'lang': lang,
          'name': name.trim(),
          'schema_version': 2,
          'design': design,
          'columns': columns,
          'rules': ExportRule.listToJson(rules),
          'options': options,
        }),
        (r) => StudioTemplate.fromJson(_map(r)),
      );

  Future<ExportResult<StudioTemplate>> updateTemplate(
    int id, {
    required String name,
    required String lang,
    Map<String, dynamic> design = const {},
    List<Map<String, dynamic>> columns = const [],
    List<ExportRule> rules = const [],
    Map<String, dynamic> options = const {},
  }) =>
      _call(
        () => api.put('$exportsBase/templates/$id', body: {
          'name': name.trim(),
          'lang': lang,
          'schema_version': 2,
          'design': design,
          'columns': columns,
          'rules': ExportRule.listToJson(rules),
          'options': options,
        }),
        (r) => StudioTemplate.fromJson(_map(r)),
      );

  Future<ExportResult<bool>> deleteTemplate(int id) => _call(() => api.delete('$exportsBase/templates/$id'), (_) => true);

  /// [scope] me (my default for its page + format) | org (the organization's, org admins).
  Future<ExportResult<bool>> setDefault(int id, {String scope = 'me'}) =>
      _call(() => api.post('$exportsBase/templates/$id/default', body: {'scope': scope}), (_) => true);

  Future<ExportResult<bool>> clearDefault(int id, {String scope = 'me'}) =>
      _call(() => api.delete('$exportsBase/templates/$id/default?scope=$scope'), (_) => true);

  /// Remembers [id] as the last template used for its page + format. Fire-and-forget.
  void markUsed(int id) {
    unawaited(_call(() => api.post('$exportsBase/templates/$id/used', body: const {}), (_) => true));
  }

  // ── export log ─────────────────────────────────────────────────────────────
  /// Reports one interactive export (column KEYS and the row count only). Fire-and-forget: never awaited by the
  /// export, never throws, never shows anything.
  void log({
    required String pageKey,
    required String format,
    String? lang,
    int? rows,
    List<String> columns = const [],
    int? templateId,
    int? orgId,
    Map<String, Object?>? filters,
    String? dataset,
    String channel = 'interactive',
  }) {
    final body = <String, dynamic>{
      'page_key': exportPageKey(pageKey),
      'format': format,
      'lang': ?lang,
      'rows': ?rows,
      'columns': columns.take(200).toList(),
      'template_id': ?templateId,
      'org_id': ?orgId,
      if (filters != null && filters.isNotEmpty) 'filters': filters,
      'dataset': ?dataset,
      'channel': channel,
    };
    unawaited(() async {
      try {
        await api.post('$exportsBase/log', body: body);
      } catch (e) {
        if (kDebugMode) debugPrint('export log skipped: $e');
      }
    }());
  }

  Future<ExportResult<ExportPage<ExportLogEntry>>> readLog({
    int? userId,
    int? orgId,
    String? pageKey,
    String? format,
    String? channel,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int size = 50,
  }) =>
      _call(
        () => api.get('$exportsBase/log', queryParams: {
          'user_id': ?userId,
          'org_id': ?orgId,
          if ((pageKey ?? '').trim().isNotEmpty) 'page_key': pageKey!.trim(),
          'format': ?format,
          'channel': ?channel,
          if (from != null) 'date_from': from.toUtc().toIso8601String(),
          if (to != null) 'date_to': to.toUtc().toIso8601String(),
          'page': page,
          'size': size,
        }),
        (r) {
          final m = _map(r);
          return ExportPage<ExportLogEntry>(
            [for (final j in _maps(m['items'])) ExportLogEntry.fromJson(j)],
            total: _int(m['total']) ?? 0,
            page: _int(m['page']) ?? page,
            size: _int(m['size']) ?? size,
            pages: _int(m['pages']) ?? 1,
          );
        },
      );

  // ── datasets ───────────────────────────────────────────────────────────────
  Future<ExportResult<List<ExportDatasetInfo>>> datasets() =>
      _call(() => api.get('$exportsBase/datasets'), (r) => [for (final j in _maps(_map(r)['items'])) ExportDatasetInfo.fromJson(j)]);

  // ── schedules + runs ───────────────────────────────────────────────────────
  Future<ExportResult<List<ExportScheduleInfo>>> schedules() =>
      _call(() => api.get('$exportsBase/schedules'), (r) => [for (final j in _maps(_map(r)['items'])) ExportScheduleInfo.fromJson(j)]);

  Future<ExportResult<ExportScheduleInfo>> createSchedule(Map<String, dynamic> body) =>
      _call(() => api.post('$exportsBase/schedules', body: body), (r) => ExportScheduleInfo.fromJson(_map(r)));

  Future<ExportResult<ExportScheduleInfo>> updateSchedule(int id, Map<String, dynamic> body) =>
      _call(() => api.put('$exportsBase/schedules/$id', body: body), (r) => ExportScheduleInfo.fromJson(_map(r)));

  Future<ExportResult<bool>> deleteSchedule(int id) => _call(() => api.delete('$exportsBase/schedules/$id'), (_) => true);

  Future<ExportResult<ExportScheduleInfo>> pauseSchedule(int id) =>
      _call(() => api.post('$exportsBase/schedules/$id/pause', body: const {}), (r) => ExportScheduleInfo.fromJson(_map(r)));

  Future<ExportResult<ExportScheduleInfo>> resumeSchedule(int id) =>
      _call(() => api.post('$exportsBase/schedules/$id/resume', body: const {}), (r) => ExportScheduleInfo.fromJson(_map(r)));

  /// Starts a run now (202); the run lands in [runs].
  Future<ExportResult<ExportRunInfo>> runScheduleNow(int id) =>
      _call(() => api.post('$exportsBase/schedules/$id/run', body: const {}), (r) => ExportRunInfo.fromJson(_map(r)));

  Future<ExportResult<ExportPage<ExportRunInfo>>> runs({int? scheduleId, int page = 1, int size = 30}) => _call(
        () => api.get('$exportsBase/runs', queryParams: {'schedule_id': ?scheduleId, 'page': page, 'size': size}),
        (r) {
          final m = _map(r);
          final total = _int(m['total']) ?? 0, sz = _int(m['size']) ?? size;
          return ExportPage<ExportRunInfo>(
            [for (final j in _maps(m['items'])) ExportRunInfo.fromJson(j)],
            total: total,
            page: _int(m['page']) ?? page,
            size: sz,
            pages: sz <= 0 ? 1 : ((total + sz - 1) ~/ sz).clamp(1, 1 << 30),
          );
        },
      );

  Future<ExportResult<ExportRunInfo>> createRun({required String dataset, Map<String, dynamic> params = const {}, int? templateId, String format = 'xlsx', String lang = 'ar'}) =>
      _call(
        () => api.post('$exportsBase/runs', body: {'dataset': dataset, 'params': params, 'template_id': templateId, 'format': format, 'lang': lang}),
        (r) => ExportRunInfo.fromJson(_map(r)),
      );

  Future<ExportResult<ExportRunInfo>> run(int id) => _call(() => api.get('$exportsBase/runs/$id'), (r) => ExportRunInfo.fromJson(_map(r)));

  Future<ExportResult<Uint8List>> downloadRun(int id) => _call(() => api.getBytes('$exportsBase/runs/$id/download'), (r) => r as Uint8List);

  // ── links ──────────────────────────────────────────────────────────────────
  Future<ExportResult<List<ExportLinkInfo>>> links() =>
      _call(() => api.get('$exportsBase/links'), (r) => [for (final j in _maps(_map(r)['items'])) ExportLinkInfo.fromJson(j)]);

  /// A link to a server run's file. [expiresDays] 1 – 30 (null = the server's 7).
  Future<ExportResult<ExportLinkInfo>> linkFromRun(int runId, {String audience = 'org', int? expiresDays}) => _call(
        () => api.post('$exportsBase/links', body: {'run_id': runId, 'audience': audience, 'expires_days': ?expiresDays}),
        (r) => ExportLinkInfo.fromJson(_map(r)),
      );

  /// A link to a file the app just generated (xlsx / docx / pdf ≤ 25 MB).
  Future<ExportResult<ExportLinkInfo>> linkFromUpload(
    Uint8List bytes,
    String fileName, {
    String audience = 'org',
    int? expiresDays,
    int? orgId,
    String? dataset,
    Map<String, Object?>? params,
    String? note,
  }) =>
      _call(
        () => api.postMultipart(
          '$exportsBase/links/upload',
          fields: {
            'audience': audience,
            if (expiresDays != null) 'expires_days': '$expiresDays',
            if (orgId != null) 'org_id': '$orgId',
            'dataset': ?dataset,
            if (params != null) 'params': jsonEncode(params),
            if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
          },
          fileField: 'file',
          fileName: fileName,
          fileBytes: bytes,
        ),
        (r) => ExportLinkInfo.fromJson(_map(r)),
      );

  Future<ExportResult<ExportLinkInfo>> revokeLink(int id) =>
      _call(() => api.delete('$exportsBase/links/$id'), (r) => ExportLinkInfo.fromJson(_map(r)));

  /// The real file name behind a link (`GET …/links/{token}/info`: same checks, nothing counted). Null when the
  /// server is older or refuses — the download itself then reports why.
  Future<String?> linkFileName(String token) async {
    final r = await _call(() => api.get('$exportsBase/links/${Uri.encodeComponent(token)}/info'), (r) => '${_map(r)['file_name'] ?? ''}');
    final name = r.ok ? (r.data ?? '').trim() : '';
    return name.isEmpty ? null : name;
  }

  /// Downloads the file behind a link (signed in; 410 link_expired / link_revoked, 403 link_forbidden …).
  Future<ExportResult<Uint8List>> openLink(String token) =>
      _call(() => api.getBytes('$exportsBase/links/${Uri.encodeComponent(token)}'), (r) => r as Uint8List);
}

/// The token of an in-app share-link route (`/e/<token>`, also with a query string), or null.
String? exportLinkTokenFromRoute(String? name) {
  final m = RegExp(r'^/e/([A-Za-z0-9_\-]{8,200})(?:[?#].*)?$').firstMatch(name ?? '');
  return m?.group(1);
}
