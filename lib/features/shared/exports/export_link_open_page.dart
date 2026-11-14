// lib/features/shared/exports/export_link_open_page.dart
//
// What a share link opens (`https://nextbrain.site/e/<token>` → route `/e/<token>`, D-134): the file is downloaded
// through `GET /api/v1/exports/links/{token}` (signed in — the route guard handles sign-in) and saved on the device
// at once; then "Download again". Expired / revoked / not allowed / another organization's links get a calm page
// with Back.
//
//   ExportLinkOpenPage({token, api})
//   ExportLinkOpenView(phase, …)     the plain-values body (loading · saved · failed)
//   exportSniffExtension(bytes)      pdf / docx / xlsx from the file's first bytes ('' when unknown)
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/export/export_studio_api.dart';
import 'package:flutter_education_app/design/export/export_studio_model.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart' show tx;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/features/data_lab/data_lab_saver_io.dart' if (dart.library.html) 'package:flutter_education_app/features/data_lab/data_lab_saver_web.dart' as saver;
import 'exports_center_page.dart';

enum ExportLinkOpenPhase { loading, saved, failed }

/// The extension of a downloaded file from its first bytes: `%PDF` → pdf; a zip holding `word/` → docx, `xl/` →
/// xlsx; '' otherwise.
String exportSniffExtension(Uint8List bytes) {
  if (bytes.length >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) return 'pdf';
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    final head = latin1.decode(bytes.sublist(0, bytes.length.clamp(0, 64 * 1024)), allowInvalid: true);
    if (head.contains('word/')) return 'docx';
    if (head.contains('xl/')) return 'xlsx';
  }
  return '';
}

/// A share link opened while signed out (`/e/<token>` → login): kept until the first signed-in screen
/// (`_Guard` in main.dart) opens it, as `DeepLinkService` does for course and profile links.
class ExportLinkPending {
  ExportLinkPending._();

  static String? _token;

  /// The remembered token (null = none).
  static String? get token => _token;

  static void set(String token) => _token = token;

  /// Opens the remembered link on [nav], once. True when there was one.
  static bool consume(NavigatorState nav) {
    final t = _token;
    if (t == null) return false;
    _token = null;
    nav.pushNamed('/e/$t');
    return true;
  }
}

class ExportLinkOpenPage extends StatefulWidget {
  const ExportLinkOpenPage({super.key, required this.token, this.api});

  final String token;
  final ExportStudioApi? api;

  @override
  State<ExportLinkOpenPage> createState() => _ExportLinkOpenPageState();
}

class _ExportLinkOpenPageState extends State<ExportLinkOpenPage> {
  ExportStudioApi get _api => widget.api ?? ExportStudioApi.instance;

  ExportLinkOpenPhase _phase = ExportLinkOpenPhase.loading;
  Uint8List? _bytes;
  String? _name, _error, _code;
  bool _missing = false, _saving = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _phase = ExportLinkOpenPhase.loading;
      _error = null;
      _code = null;
    });
    final r = await _api.openLink(widget.token);
    if (!mounted) return;
    if (!r.ok) {
      // A bytes download loses the error body's code; ask once more as JSON to learn it (refusals count nothing).
      final code = r.code ?? (const {403, 404, 410}.contains(r.status) ? await _probeCode() : null);
      if (!mounted) return;
      setState(() {
        _phase = ExportLinkOpenPhase.failed;
        _error = code == null ? r.error : exportStudioErrorText(code, r.error);
        _code = code ?? (r.status == 401 ? 'not_authenticated' : null);
        _missing = r.missing;
      });
      return;
    }
    final bytes = r.data!;
    final ext = exportSniffExtension(bytes);
    _bytes = bytes;
    // the shared file's own name (a bytes download cannot read Content-Disposition across origins)
    final real = await _api.linkFileName(widget.token);
    if (!mounted) return;
    _name = real ?? (ext.isEmpty ? 'export' : exportFileName('export', ext));
    await _save();
    if (mounted) setState(() => _phase = ExportLinkOpenPhase.saved);
  }

  Future<String?> _probeCode() async {
    try {
      await _api.api.get('$exportsBase/links/${Uri.encodeComponent(widget.token)}');
    } catch (e) {
      final x = ApiException.from(e);
      return x.code ?? ApiException.codedDetail(x.body).$1;
    }
    return null;
  }

  Future<void> _save() async {
    final b = _bytes, n = _name;
    if (b == null || n == null) return;
    setState(() => _saving = true);
    try {
      await saver.dlSaveBytes(b, n, exportMimeOf(n));
      showAppNotice('${exportLtr(n)} · ${exportLtr(exportSizeLabel(b.length))}');
    } catch (_) {
      showAppNotice(tx('exs_save_failed', 'The file could not be saved', 'تعذّر حفظ الملف'), error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _back() async {
    final nav = Navigator.of(context);
    if (await nav.maybePop() || !mounted) return;
    // Opened from a link with nothing beneath: go to the person's home.
    String? home;
    try {
      home = Provider.of<MyAuthProvider>(context, listen: false).homeRoute;
    } catch (_) {
      home = null;
    }
    if (home != null) nav.pushNamedAndRemoveUntil(home, (_) => false);
  }

  @override
  Widget build(BuildContext context) => BasePage(
        key: const ValueKey(kExportLinksKey),
        appBar: ScreenAppBar(title: tx('exs_open_title', 'Shared file', 'ملف مشارَك')),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: exportsListPadding(box.maxWidth, top: AppSpace.xl),
            child: ExportLinkOpenView(
              phase: _phase,
              fileName: _name,
              size: _bytes?.length,
              error: _error,
              code: _code,
              missing: _missing,
              saving: _saving,
              onDownloadAgain: _save,
              onRetry: _open,
              onBack: _back,
            ),
          ),
        ),
      );
}

/// The open page's body with plain values. [code] picks the failure text (link_expired · link_revoked ·
/// link_forbidden · link_other_org · link_not_found · not_authenticated); anything else shows [error] with Try again.
class ExportLinkOpenView extends StatelessWidget {
  const ExportLinkOpenView({
    super.key,
    required this.phase,
    this.fileName,
    this.size,
    this.error,
    this.code,
    this.missing = false,
    this.saving = false,
    this.onDownloadAgain,
    this.onRetry,
    this.onBack,
  });

  final ExportLinkOpenPhase phase;
  final String? fileName, error, code;
  final int? size;
  final bool missing, saving;
  final VoidCallback? onDownloadAgain, onRetry, onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final back = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min * 2, AppTouch.min)),
      onPressed: onBack,
      icon: const Icon(Icons.arrow_back_rounded),
      label: Text(tx('exs_back', 'Back', 'رجوع')),
    );
    switch (phase) {
      case ExportLinkOpenPhase.loading:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.primaryTint),
            child: Icon(Icons.cloud_download_rounded, size: AppIconSize.hero, color: c.primary),
          ),
          AppSpace.gapMd,
          Text(tx('exs_open_loading', 'Opening the file…', 'جارٍ فتح الملف…'), textAlign: TextAlign.center, style: AppType.section(context)),
          AppSpace.gapXs,
          Text(tx('exs_open_loading_sub', 'It will be saved on this device.', 'سيُحفظ على هذا الجهاز.'),
              textAlign: TextAlign.center, style: AppType.meta(context)),
          AppSpace.gapMd,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: ClipRRect(borderRadius: AppRadius.chipAll, child: LinearProgressIndicator(color: c.primary, backgroundColor: c.primaryTint)),
          ),
        ]);
      case ExportLinkOpenPhase.saved:
        final name = fileName ?? 'export';
        return Column(mainAxisSize: MainAxisSize.min, children: [
          AppEmpty(
            icon: Icons.download_done_rounded,
            title: tx('exs_open_saved', 'File saved', 'حُفظ الملف'),
            message: size == null ? name : '${exportLtr(name)} · ${exportLtr(exportSizeLabel(size!))}',
          ),
          Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: c.primary, minimumSize: const Size(AppTouch.min * 2, AppTouch.min)),
              onPressed: saving ? null : onDownloadAgain,
              icon: const Icon(Icons.file_download_rounded),
              label: Text(tx('exs_open_again', 'Download again', 'تنزيل مرة أخرى'), style: AppType.bodyStrong(context).copyWith(color: c.onHero)),
            ),
            back,
          ]),
        ]);
      case ExportLinkOpenPhase.failed:
        if (missing) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            ExportsLoadError(message: error ?? '', missing: true),
            AppSpace.gapMd,
            back,
          ]);
        }
        final (icon, title, message, retry) = switch (code) {
          'link_expired' => (
              Icons.timer_off_rounded,
              tx('exs_err_link_expired', 'This link has expired', 'انتهت صلاحية هذا الرابط'),
              tx('exs_open_ask_new', 'Ask the person who shared it for a new link.', 'اطلب من صاحب المشاركة رابطًا جديدًا.'),
              false,
            ),
          'link_revoked' => (
              Icons.link_off_rounded,
              tx('exs_err_link_revoked', 'This link was revoked', 'أُلغي هذا الرابط'),
              tx('exs_open_ask_new', 'Ask the person who shared it for a new link.', 'اطلب من صاحب المشاركة رابطًا جديدًا.'),
              false,
            ),
          'link_forbidden' => (
              Icons.lock_outline_rounded,
              tx('exs_err_link_forbidden', 'You may not open this file', 'لا تملك صلاحية فتح هذا الملف'),
              tx('exs_open_forbidden_sub', 'This file is shared only with people who may see its data.', 'هذا الملف مشارَك فقط مع من يحق له رؤية بياناته.'),
              false,
            ),
          'link_other_org' => (
              Icons.apartment_rounded,
              tx('exs_err_link_other_org', 'This link is for members of another organization', 'هذا الرابط لأعضاء مؤسسة أخرى'),
              tx('exs_open_other_org_sub', 'Sign in with the account you use in that organization.', 'سجّل الدخول بالحساب الذي تستخدمه في تلك المؤسسة.'),
              false,
            ),
          'link_not_found' => (
              Icons.link_off_rounded,
              tx('exs_err_link_not_found', 'This link is not valid', 'هذا الرابط غير صالح'),
              tx('exs_open_check_link', 'Check that the whole link was copied.', 'تأكد من نسخ الرابط كاملًا.'),
              false,
            ),
          'not_authenticated' => (
              Icons.account_circle_outlined,
              tx('exs_open_signin', 'Sign in to open this file', 'سجّل الدخول لفتح هذا الملف'),
              tx('exs_open_signin_sub', 'Shared files open only for signed-in people.', 'الملفات المشارَكة تُفتح للمستخدمين المسجّلين فقط.'),
              false,
            ),
          _ => (
              Icons.cloud_off_rounded,
              tx('exs_open_failed', 'The file could not be opened', 'تعذّر فتح الملف'),
              error ?? exportStudioErrorText(null),
              true,
            ),
        };
        return Column(mainAxisSize: MainAxisSize.min, children: [
          AppEmpty(icon: icon, title: title, message: message),
          Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (retry && onRetry != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: c.primary, minimumSize: const Size(AppTouch.min * 2, AppTouch.min)),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(tx('exs_retry', 'Try again', 'أعد المحاولة'), style: AppType.bodyStrong(context).copyWith(color: c.onHero)),
              ),
            back,
          ]),
        ]);
    }
  }
}
