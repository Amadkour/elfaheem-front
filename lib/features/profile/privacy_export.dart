// "Download my data" (brief §12, data-subject export): ask the server for a copy of everything it holds about the
// signed-in user, follow the build, and save the ZIP (JSON per area + a bilingual README).
//
//   POST /api/v1/me/data-export           start (200 ready at once · 202 queued) · 409 export_in_progress ·
//                                         429 export_rate_limited {next_request_at}
//   GET  /api/v1/me/data-export           status {state, export_id, requested_at, finished_at, expires_at,
//                                         size_bytes, error_code, can_request, next_request_at, keep_days, …}
//   GET  /api/v1/me/data-export/download  the ZIP (only the user's own; refused in super-admin "view as")
//
// [DataExportStatus] and the text helpers are pure; [DataExportView] is the presentational body the layout harness
// tests; [DataExportPage] wires them to [DataExportApi].
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_money_p8.dart' show p8SaveBytes;

/// A server time (naive UTC ISO, or with a zone) as a UTC instant; null when absent or unreadable.
DateTime? exportUtc(dynamic v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(hasZone ? s : '${s}Z')?.toUtc();
}

/// The profile entry's label.
String dataExportEntryLabel() => t('تنزيل بياناتي', 'Download my data');

int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

class DataExportStatus {
  const DataExportStatus({
    required this.state,
    this.exportId,
    this.requestedAt,
    this.finishedAt,
    this.expiresAt,
    this.sizeBytes,
    this.errorCode,
    this.canRequest = false,
    this.nextRequestAt,
    this.keepDays = 3,
    this.cooldownHours = 24,
  });

  /// none | queued | processing | ready | failed | expired
  final String state;
  final String? exportId;
  final DateTime? requestedAt, finishedAt, expiresAt, nextRequestAt;
  final int? sizeBytes;
  final String? errorCode;
  final bool canRequest;
  final int keepDays, cooldownHours;

  static const empty = DataExportStatus(state: 'none', canRequest: true);

  factory DataExportStatus.fromJson(dynamic raw) {
    final j = raw is Map ? raw : const {};
    return DataExportStatus(
      state: '${j['state'] ?? 'none'}',
      exportId: j['export_id']?.toString(),
      requestedAt: exportUtc(j['requested_at']),
      finishedAt: exportUtc(j['finished_at']),
      expiresAt: exportUtc(j['expires_at']),
      sizeBytes: _int(j['size_bytes']),
      errorCode: j['error_code']?.toString(),
      canRequest: j['can_request'] == true,
      nextRequestAt: exportUtc(j['next_request_at']),
      keepDays: _int(j['keep_days']) ?? 3,
      cooldownHours: _int(j['cooldown_hours']) ?? 24,
    );
  }

  bool get busy => state == 'queued' || state == 'processing';
  bool get ready => state == 'ready' && exportId != null;
}

/// Bilingual label of a state.
String dataExportStateText(String state) => switch (state) {
      'queued' => t('في الانتظار', 'Waiting to start'),
      'processing' => t('جارٍ التجهيز', 'Being prepared'),
      'ready' => t('جاهز للتنزيل', 'Ready to download'),
      'failed' => t('تعذّر التجهيز', 'Could not be prepared'),
      'expired' => t('انتهت صلاحيته', 'Expired'),
      _ => t('لم تطلب نسخة بعد', 'No copy requested yet'),
    };

/// `next_request_at` of a 429 `export_rate_limited` (UTC), if the server sent it.
DateTime? exportNextRequestAtOf(ApiException e) {
  final d = ApiException.asMap(e.body)?['detail'];
  return d is Map ? exportUtc(d['next_request_at']) : null;
}

/// Server codes of the export routes as bilingual text; [fallback] (the server's own message) otherwise. The rate
/// limit names the time of the next allowed request when known ([nextRequestAt]), else the server's
/// [cooldownHours] (PRIVACY_EXPORT_COOLDOWN_HOURS, not always 24).
String dataExportCodeText(String? code, String fallback, {int cooldownHours = 24, DateTime? nextRequestAt}) =>
    switch (code) {
      'export_rate_limited' when nextRequestAt != null =>
        '${t('يمكنك طلب نسخة جديدة بعد', 'You can ask for a new copy after')}: ${AppTime.dateTime(nextRequestAt)}',
      'export_rate_limited' => t('يمكنك طلب نسخة من بياناتك مرة واحدة كل $cooldownHours ساعة',
          'You can ask for a copy of your data once every $cooldownHours hours'),
      'export_in_progress' => t('نسخة بياناتك قيد التجهيز بالفعل', 'A copy of your data is already being prepared'),
      'export_not_ready' => t('لا يوجد ملف جاهز للتنزيل', 'There is no file ready to download'),
      'export_expired' => t('انتهت صلاحية الملف، اطلب نسخة جديدة', 'The file has expired — ask for a new copy'),
      'export_replaced' => t('هذا الملف لم يعد متاحاً، حدّث الصفحة', 'This file is no longer available — refresh'),
      'export_failed' || 'export_interrupted' => t('تعذّر تجهيز الملف، حاول مرة أخرى', 'The file could not be prepared — try again'),
      'view_as_not_allowed' => t('لا يمكن تنزيل بيانات مستخدم آخر في وضع العرض', 'Another user\'s data cannot be downloaded in view-as mode'),
      _ => fallback,
    };

/// The calls behind the page (an interface so tests and previews never reach the network).
abstract class DataExportApi {
  Future<DataExportStatus> status();
  Future<DataExportStatus> request();
  Future<Uint8List> download(String exportId);
}

class RemoteDataExportApi implements DataExportApi {
  RemoteDataExportApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _base = '/api/v1/me/data-export';

  @override
  Future<DataExportStatus> status() async => DataExportStatus.fromJson(await _api.get(_base));

  @override
  Future<DataExportStatus> request() async => DataExportStatus.fromJson(await _api.post(_base));

  @override
  Future<Uint8List> download(String exportId) => _api.getBytes('$_base/download', queryParams: {'export_id': exportId});
}

/// The page body from plain values (tested under the layout harness).
class DataExportView extends StatelessWidget {
  const DataExportView({
    super.key,
    required this.status,
    this.loading = false,
    this.requesting = false,
    this.downloading = false,
    this.error,
    this.onRequest,
    this.onDownload,
    this.onRetry,
  });

  final DataExportStatus status;
  final bool loading, requesting, downloading;
  final String? error;
  final VoidCallback? onRequest, onDownload, onRetry;

  Color _stateColor(BuildContext context) {
    final c = context.colors;
    return switch (status.state) {
      'ready' => c.success,
      'failed' => c.danger,
      'queued' || 'processing' => c.warning,
      _ => c.textMedium,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = status;
    return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.lg), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.inventory_2_rounded, color: c.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
                child: Text(t('نسخة من بياناتك', 'A copy of your data'),
                    style: AppType.section(context).copyWith(color: c.textDark))),
          ]),
          const SizedBox(height: AppSpace.xs),
          Text(
              t('ملف مضغوط (ZIP) يضم ملفات JSON لكل جزء من بياناتك (الحساب، الدورات، المدفوعات، الحضور، الاختبارات، '
                      'الأسئلة، الإشعارات، الشكاوى، الأجهزة، المؤسسات، الموافقات) مع ملف يشرح محتوى كل ملف بالعربية والإنجليزية.',
                  'A ZIP file with one JSON file per part of your data (account, courses, payments, attendance, exams, '
                      'questions, notifications, complaints, devices, organizations, consents) and a file that explains each one in Arabic and English.'),
              style: AppType.label(context).copyWith(color: c.textMedium, height: 1.5)),
          const SizedBox(height: AppSpace.xs - 2),
          Text(
              t('يُحتفظ بالملف ${daysText(s.keepDays, lang: 'ar')} ثم يُحذف، ويمكنك طلب نسخة جديدة مرة كل ${hoursText(s.cooldownHours, lang: 'ar')}.',
                  'The file is kept for ${daysText(s.keepDays, lang: 'en')}, then deleted. You can ask for a new copy once every ${hoursText(s.cooldownHours, lang: 'en')}.'),
              style: AppType.meta(context).copyWith(color: c.textMedium, height: 1.5)),
        ]),
      ),
      const SizedBox(height: AppSpace.sm),
      if (loading)
        const SizedBox(height: 120, child: AppListSkeleton(items: 2))
      else ...[
        if (error != null) ...[
          AppBanner(
              icon: Icons.error_outline_rounded,
              color: c.danger,
              text: error!,
              action: onRetry == null
                  ? null
                  : TextButton(onPressed: onRetry, child: Text(t('إعادة المحاولة', 'Retry')))),
          const SizedBox(height: AppSpace.sm),
        ],
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(t('الحالة', 'Status'), style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
              AppBadgePill(dataExportStateText(s.state), color: _stateColor(context)),
            ]),
            const SizedBox(height: AppSpace.sm),
            if (s.requestedAt != null)
              AppInfoRow(Icons.schedule_rounded, '${t('طُلب في', 'Requested')}: ${AppTime.dateTime(s.requestedAt!)}'),
            if (s.ready && s.expiresAt != null)
              AppInfoRow(Icons.timer_outlined, '${t('متاح حتى', 'Available until')}: ${AppTime.dateTime(s.expiresAt!)}'),
            if (s.ready && (s.sizeBytes ?? 0) > 0)
              AppInfoRow(Icons.folder_zip_outlined, '${t('الحجم', 'Size')}: ${fileSizeLabel(s.sizeBytes)}'),
            if (s.state == 'failed')
              AppInfoRow(Icons.info_outline_rounded, dataExportCodeText(s.errorCode, t('تعذّر التجهيز', 'Could not be prepared'))),
            if (s.busy)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs - 2),
                child: Text(t('نجهّز ملفك الآن، ستتحدث هذه الصفحة تلقائياً.', 'We are preparing your file; this page updates by itself.'),
                    style: AppType.meta(context).copyWith(color: c.textMedium, height: 1.5)),
              ),
            if (!s.canRequest && !s.busy && s.nextRequestAt != null)
              AppInfoRow(Icons.hourglass_bottom_rounded,
                  '${t('يمكنك طلب نسخة جديدة بعد', 'You can ask for a new copy after')}: ${AppTime.dateTime(s.nextRequestAt!)}'),
            const SizedBox(height: AppSpace.md),
            if (s.ready)
              AppPrimaryButton(
                  label: t('تنزيل بياناتي', 'Download my data'),
                  icon: Icons.download_rounded,
                  busy: downloading,
                  onPressed: downloading ? null : onDownload),
            if (s.ready && s.canRequest) const SizedBox(height: AppSpace.sm),
            if (!s.ready || s.canRequest)
              AppPrimaryButton(
                  label: s.state == 'none' ? t('طلب نسخة من بياناتي', 'Request a copy of my data') : t('طلب نسخة جديدة', 'Request a new copy'),
                  icon: Icons.inventory_2_outlined,
                  busy: requesting || s.busy,
                  onPressed: (requesting || s.busy || !s.canRequest) ? null : onRequest),
          ]),
        ),
      ],
    ]);
  }
}

class DataExportPage extends StatefulWidget {
  const DataExportPage({super.key, this.api, this.pollEvery = const Duration(seconds: 5)});
  final DataExportApi? api;
  final Duration pollEvery;

  @override
  State<DataExportPage> createState() => _DataExportPageState();
}

class _DataExportPageState extends State<DataExportPage> {
  late final DataExportApi _api = widget.api ?? RemoteDataExportApi();
  DataExportStatus _s = DataExportStatus.empty;
  bool _loading = true, _requesting = false, _downloading = false;
  String? _error;
  EventOrPoll? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.dispose();
    super.dispose();
  }

  /// While the build runs: `job_updated{kind: export}` reloads at once, the poll ([DataExportPage.pollEvery], 4 ×
  /// slower while the live stream is connected) is the fallback.
  void _follow() {
    if (!_s.busy || !mounted) {
      _poll?.stop();
      return;
    }
    (_poll ??= EventOrPoll(kind: 'export', every: widget.pollEvery, poll: () => _load(silent: true))).start();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final s = await _api.status();
      if (!mounted) return;
      setState(() {
        _s = s;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final ex = ApiException.from(e);
      setState(() {
        _error = dataExportCodeText(ex.code, ex.message);
        _loading = false;
      });
    }
    _follow();
  }

  Future<void> _request() async {
    setState(() => _requesting = true);
    try {
      final s = await _api.request();
      if (!mounted) return;
      setState(() {
        _s = s;
        _error = null;
      });
      if (s.ready) appToast(t('ملف بياناتك جاهز', 'Your data file is ready'));
    } catch (e) {
      if (!mounted) return;
      final ex = ApiException.from(e);
      setState(() => _error = dataExportCodeText(ex.code, ex.message,
          cooldownHours: _s.cooldownHours, nextRequestAt: exportNextRequestAtOf(ex)));
      await _load(silent: true);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
    _follow();
  }

  Future<void> _download() async {
    final id = _s.exportId;
    if (id == null) return;
    setState(() => _downloading = true);
    try {
      final bytes = await _api.download(id);
      final stamp = (_s.finishedAt ?? DateTime.now().toUtc()).toIso8601String().substring(0, 10).replaceAll('-', '');
      await p8SaveBytes(bytes, 'my-data-$stamp.zip', mime: 'application/zip');
      appToast(t('تم حفظ ملف بياناتك', 'Your data file was saved'));
    } catch (e) {
      final ex = ApiException.from(e);
      appToast(dataExportCodeText(ex.code, ex.message), error: true);
      if (ex.code == 'export_expired' || ex.code == 'export_replaced') await _load(silent: true);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SdArea(area: AppArea.me, child: BasePage(
      key: const ValueKey('profile.data_export'),
      useWebCard: true,
      width: AppWidth.reading,
      appBar: ScreenAppBar(title: t('تنزيل بياناتي', 'Download my data'), actions: [
        IconButton(tooltip: t('تحديث', 'Refresh'), icon: const Icon(Icons.refresh_rounded), onPressed: _load),
      ]),
      child: SdHeroColumn(title: 'sd_h_data'.tr, subtitle: 'sd_h_data_d'.tr, icon: Icons.inventory_2_outlined, child: DataExportView(
        status: _s,
        loading: _loading,
        requesting: _requesting,
        downloading: _downloading,
        error: _error,
        onRequest: _request,
        onDownload: _download,
        onRetry: _load,
      )),
    ));
  }
}
