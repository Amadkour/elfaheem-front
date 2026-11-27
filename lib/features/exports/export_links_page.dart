// lib/features/exports/export_links_page.dart
//
// Expiring share links (feature key `export.share_links`, `/api/v1/exports/links`, D-134): a link to a prepared file
// or an uploaded one, for me only or my organization, 1 – 30 days. Never anonymous: whoever opens it signs in, and
// the server checks they may see the data. The token comes back ONCE, when the link is created, so a link can only
// be copied right then; older links can be revoked.
//
//   ExportLinksPage({api})                my links · New link (from a prepared file, or upload xlsx / docx / pdf ≤ 25 MB)
//   showShareExportLinkSheet(...)         audience · expiry · Create → the link with Copy (the export flow's "Share link")
//   ExportLinkCard(info, nowUtc, …)       one link (plain values)
//   ExportShareLinkBody                   the share sheet's body, before and after the link exists (plain values)
//   ExportLinkUrlBox(url)                 the selectable LTR link
//   exportAudienceLabel / exportLinkStateText / exportDaysLabel
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/export/export_studio_api.dart';
import 'package:flutter_education_app/design/export/export_studio_model.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart' show tx;
import 'package:flutter_education_app/features/admin/adm_kit.dart' show admRoleAny;
import 'package:flutter_education_app/features/admin/sup/sup_kit.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/features/org/org_providers.dart' show OrgSession;
import 'package:flutter_education_app/features/exports/export_schedules_page.dart' show exportRunStatusLabel, exportLangLabel;
import 'package:flutter_education_app/features/exports/exports_center_page.dart';

String exportLinksTitle() => tx('exs_links_title', 'Shared links', 'روابط المشاركة');

/// The largest file a link may carry (the server's limit).
const int kExportLinkMaxBytes = 25 * 1024 * 1024;

const kExportLinkDays = [1, 3, 7, 14, 30];

String exportAudienceLabel(String audience) =>
    audience == 'me' ? tx('exs_audience_me', 'Only me', 'أنا فقط') : tx('exs_audience_org', 'My organization', 'مؤسستي');

IconData exportAudienceIcon(String audience) => audience == 'me' ? Icons.person_rounded : Icons.apartment_rounded;

/// "1 day" / "3 days" / "14 days".
String exportDaysLabel(int n) {
  if (n == 1) return tx('exs_days_1', '1 day', 'يوم واحد');
  if (n == 2) return tx('exs_days_2', '2 days', 'يومان');
  return (n <= 10 ? tx('exs_days_few', '{n} days', '{n} أيام') : tx('exs_days_many', '{n} days', '{n} يومًا')).replaceAll('{n}', '$n');
}

/// Revoked · Expired · Expires today · Expires in N days.
String exportLinkStateText(ExportLinkInfo l, DateTime nowUtc) {
  if (l.revoked) return tx('exs_link_revoked', 'Revoked', 'أُلغي');
  if (l.expiredAt(nowUtc)) return tx('exs_link_expired', 'Expired', 'انتهت صلاحيته');
  final at = l.expiresAt;
  if (at == null) return tx('exs_link_active', 'Active', 'نشط');
  final hours = at.difference(nowUtc).inHours;
  if (hours < 24) return tx('exs_link_expires_today', 'Expires within a day', 'ينتهي خلال يوم');
  return tx('exs_link_expires_in', 'Expires in {d}', 'ينتهي بعد {d}').replaceAll('{d}', exportDaysLabel((hours / 24).ceil()));
}

Color exportLinkStateColor(BuildContext context, ExportLinkInfo l, DateTime nowUtc) {
  final c = context.colors;
  if (l.revoked) return c.textMedium;
  if (l.expiredAt(nowUtc)) return c.danger;
  return c.success;
}

Future<void> _copy(String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  showAppNotice(tx('exs_link_copied', 'Link copied', 'نُسخ الرابط'));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class ExportLinksPage extends StatefulWidget {
  const ExportLinksPage({super.key, this.api});

  final ExportStudioApi? api;

  @override
  State<ExportLinksPage> createState() => _ExportLinksPageState();
}

class _ExportLinksPageState extends State<ExportLinksPage> {
  ExportStudioApi get _api => widget.api ?? ExportStudioApi.instance;

  List<ExportLinkInfo>? _items;
  String? _error;
  bool _missing = false;
  int? _busy;

  /// Tokens of the links made while this page is open (the server never sends them again).
  final _tokens = <int, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final r = await _api.links();
    if (!mounted) return;
    setState(() {
      _missing = r.missing;
      if (r.ok) {
        _items = r.data!;
      } else {
        _error = r.error;
      }
    });
  }

  String? _urlOf(ExportLinkInfo l) => l.url ?? (_tokens[l.id] == null ? null : exportLinkUrl(_tokens[l.id]!));

  void _created(ExportLinkInfo? link) {
    if (link == null || !mounted) return;
    if (link.token != null) _tokens[link.id] = link.token!;
    _load();
  }

  Future<void> _revoke(ExportLinkInfo l) async {
    final ok = await appConfirm(
      context,
      danger: true,
      confirmLabel: tx('exs_revoke', 'Revoke', 'إلغاء الرابط'),
      message: tx('exs_link_revoke_q', 'Revoke the link to "{name}"? Nobody can open it after this.',
              'إلغاء رابط «{name}»؟ لن يتمكن أحد من فتحه بعد ذلك.')
          .replaceAll('{name}', l.fileName ?? ''),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = l.id);
    final r = await _api.revokeLink(l.id);
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (r.ok) _items = [for (final x in _items ?? const <ExportLinkInfo>[]) x.id == l.id ? r.data! : x];
    });
    showAppNotice(r.ok ? tx('exs_link_revoked_done', 'Link revoked', 'أُلغي الرابط') : r.error!, error: !r.ok);
  }

  Future<void> _new() async {
    final how = await showAppSheet<String>(context, (_) => const ExportNewLinkChooser());
    if (!mounted || how == null) return;
    if (how == 'run') {
      final run = await showAppSheet<ExportRunInfo>(context, (_) => _PickRunSheet(api: _api));
      if (run == null || !mounted) return;
      ExportLinkInfo? made;
      final link = await showAppSheet<ExportLinkInfo>(
        context,
        (_) => _ShareLinkSheet(
          fileName: run.fileName ?? exportFileName(run.dataset.isEmpty ? 'export' : run.dataset, run.format),
          size: run.size,
          orgAllowed: true,
          initialAudience: exportContextOrg(context) != null ? 'org' : 'me',
          create: (audience, days) => _api.linkFromRun(run.id, audience: audience, expiresDays: days),
          onCreated: (l) => made = l,
        ),
      );
      _created(link ?? made);
    } else {
      final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx', 'docx', 'pdf']);
      if (f == null || !mounted) return;
      Uint8List bytes;
      try {
        bytes = await f.readAsBytes();
      } catch (_) {
        showAppNotice(tx('exs_read_failed', 'The file could not be read', 'تعذّرت قراءة الملف'), error: true);
        return;
      }
      if (!mounted) return;
      if (bytes.length > kExportLinkMaxBytes) {
        showAppNotice(exportStudioErrorText('file_too_big'), error: true);
        return;
      }
      final link = await showShareExportLinkSheet(context, bytes: bytes, fileName: f.name, orgId: exportContextOrg(context), api: _api);
      _created(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final now = DateTime.now().toUtc();
    final untokened = items != null && items.any((l) => l.activeAt(now) && _urlOf(l) == null);
    // redesign A1 (AdmData exports): the signed-in role's hero; the kill switch stays on the page key
    return SupPage(
      pageKey: const ValueKey(kExportLinksKey),
      role: admRoleAny(context),
      title: exportLinksTitle(),
      kicker: exportsCenterTitle(),
      headline: tx('a1_exs_links_head', 'Links to your files that expire on their own', 'روابط لملفاتك تنتهي صلاحيتها تلقائيًا'),
      width: AppWidth.full,
      floatingActionButton: _missing || items == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _new,
              icon: const Icon(Icons.add_link_rounded),
              label: Text(tx('exs_link_new', 'New link', 'رابط جديد')),
            ),
      body: LayoutBuilder(
        builder: (context, box) => AppRefresh(
          onRefresh: _load,
          child: ListView(
            padding: exportsListPadding(box.maxWidth, bottom: 96),
            children: [
              if (_missing)
                ExportsLoadError(message: _error ?? '', missing: true)
              else if (items == null && _error != null)
                ExportsLoadError(message: _error!, onRetry: _load)
              else if (items == null)
                const AppListSkeleton(items: 4, padding: EdgeInsets.zero)
              else if (items.isEmpty)
                AppEmpty(
                  icon: Icons.link_rounded,
                  title: tx('exs_links_empty', 'No shared links yet', 'لا روابط مشاركة بعد'),
                  message: tx('exs_links_empty_sub', 'Share a file with a link that expires on its own. Whoever opens it signs in first.',
                      'شارك ملفًا برابط تنتهي صلاحيته تلقائيًا، ومن يفتحه يسجّل الدخول أولًا.'),
                  actionLabel: tx('exs_link_new', 'New link', 'رابط جديد'),
                  onAction: _new,
                )
              else ...[
                if (untokened) ...[
                  AppBanner(
                    icon: Icons.info_outline_rounded,
                    text: tx('exs_link_once_note', 'A link is shown once, when it is made. To share a file again, make a new link.',
                        'يظهر الرابط مرة واحدة عند إنشائه. لمشاركة الملف مرة أخرى أنشئ رابطًا جديدًا.'),
                  ),
                  AppSpace.gapSm,
                ],
                if (_error != null) ...[
                  AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: context.colors.danger),
                  AppSpace.gapSm,
                ],
                for (final l in items)
                  ExportLinkCard(
                    info: l,
                    nowUtc: now,
                    url: _urlOf(l),
                    busy: _busy == l.id,
                    onCopy: _urlOf(l) == null ? null : () => _copy(_urlOf(l)!),
                    onRevoke: () => _revoke(l),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Card + link box
// ═════════════════════════════════════════════════════════════════════════════

/// One link. [url] (or [ExportLinkInfo.url]) is known only right after the link was made; [onCopy] then copies it.
/// An active link can be revoked.
class ExportLinkCard extends StatelessWidget {
  const ExportLinkCard({super.key, required this.info, required this.nowUtc, this.url, this.busy = false, this.onCopy, this.onRevoke});

  final ExportLinkInfo info;
  final DateTime nowUtc;
  final String? url;
  final bool busy;
  final VoidCallback? onCopy, onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = info;
    final meta = AppType.meta(context);
    final fmt = exportFormatOf(l.fileName);
    final fmtColor = exportFormatColor(context, fmt);
    final active = l.activeAt(nowUtc);
    final link = url ?? l.url;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: fmtColor.withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
              child: Icon(exportFormatIcon(fmt), color: fmtColor, size: AppIconSize.md),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((l.fileName ?? '').isEmpty ? tx('exs_link_file', 'File', 'ملف') : l.fileName!,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                Text(
                  [
                    exportFormatLabel(fmt),
                    if (l.size != null) exportLtr(exportSizeLabel(l.size!)),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meta,
                ),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ExportTintPill(exportAudienceLabel(l.audience), color: c.charcoal, icon: exportAudienceIcon(l.audience)),
            ExportTintPill(
              exportLinkStateText(l, nowUtc),
              color: exportLinkStateColor(context, l, nowUtc),
              icon: l.revoked ? Icons.link_off_rounded : (active ? Icons.timer_outlined : Icons.timer_off_outlined),
            ),
            Text(
              (l.downloadCount == 1 ? tx('exs_link_downloads_1', '1 download', 'تنزيل واحد') : tx('exs_link_downloads_n', '{n} downloads', '{n} تنزيلات'))
                  .replaceAll('{n}', '${l.downloadCount}'),
              style: meta,
            ),
            if (l.createdAt != null)
              Text(tx('exs_link_created', 'Made {t}', 'أُنشئ {t}').replaceAll('{t}', AppTime.dateTime(l.createdAt!)), style: meta),
          ]),
          if (active && link != null) ...[
            AppSpace.gapSm,
            ExportLinkUrlBox(url: link),
          ],
          if (active) ...[
            const SizedBox(height: AppSpace.xs),
            Divider(height: 1, color: c.divider),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xxs, children: [
              if (link != null && onCopy != null)
                ExportActionButton(icon: Icons.copy_rounded, label: tx('exs_link_copy', 'Copy link', 'نسخ الرابط'), onPressed: onCopy),
              ExportActionButton(
                icon: Icons.link_off_rounded,
                label: tx('exs_revoke', 'Revoke', 'إلغاء الرابط'),
                color: c.danger,
                busy: busy,
                onPressed: onRevoke,
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// The link as selectable left-to-right text.
class ExportLinkUrlBox extends StatelessWidget {
  const ExportLinkUrlBox({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SelectableText(url, style: AppType.label(context).copyWith(color: c.textDark)),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  New link: the choice, a prepared file, the share sheet
// ═════════════════════════════════════════════════════════════════════════════

/// "From a prepared file" (pops 'run') or "Upload a file" (pops 'upload').
class ExportNewLinkChooser extends StatelessWidget {
  const ExportNewLinkChooser({super.key});

  @override
  Widget build(BuildContext context) {
    Widget option(IconData icon, String title, String sub, String value) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppCard(
            onTap: () => Navigator.of(context).pop(value),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: context.colors.primaryTint, borderRadius: AppRadius.chipAll),
                child: Icon(icon, color: context.colors.primary),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                  Text(sub, style: AppType.meta(context)),
                ]),
              ),
            ]),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSheetHeader(tx('exs_link_new', 'New link', 'رابط جديد')),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
          child: Column(children: [
            option(Icons.folder_open_rounded, tx('exs_link_from_run', 'From a prepared file', 'من ملف جاهز'),
                tx('exs_link_from_run_sub', 'A file your scheduled exports made', 'ملف أعدّته تصديراتك المجدولة'), 'run'),
            option(Icons.upload_file_rounded, tx('exs_link_upload', 'Upload a file', 'رفع ملف'),
                tx('exs_link_upload_sub', 'Excel, Word or PDF, up to 25 MB', 'Excel أو Word أو PDF حتى 25 ميجابايت'), 'upload'),
          ]),
        ),
      ),
    ]);
  }
}

class _PickRunSheet extends StatefulWidget {
  const _PickRunSheet({required this.api});
  final ExportStudioApi api;

  @override
  State<_PickRunSheet> createState() => _PickRunSheetState();
}

class _PickRunSheetState extends State<_PickRunSheet> {
  List<ExportRunInfo>? _runs;
  String? _error;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final r = await widget.api.runs(size: 50);
    if (!mounted) return;
    setState(() {
      _missing = r.missing;
      if (r.ok) {
        _runs = [for (final x in r.data!.items) if (x.ready) x];
      } else {
        _error = r.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final runs = _runs;
    final meta = AppType.meta(context);
    Widget body;
    if (_missing || (runs == null && _error != null)) {
      body = ExportsLoadError(message: _error ?? '', missing: _missing, onRetry: _load);
    } else if (runs == null) {
      body = const AppListSkeleton(items: 3, padding: EdgeInsets.zero);
    } else if (runs.isEmpty) {
      body = AppEmpty(
        icon: Icons.folder_off_rounded,
        title: tx('exs_link_no_runs', 'No prepared files', 'لا ملفات جاهزة'),
        message: tx('exs_link_no_runs_sub', 'Files made by your scheduled exports show here for a week.', 'تظهر هنا لمدة أسبوع الملفات التي تعدّها تصديراتك المجدولة.'),
      );
    } else {
      body = Column(children: [
        for (final r in runs)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpace.sm),
              onTap: () => Navigator.of(context).pop(r),
              child: Row(children: [
                Icon(exportFormatIcon(r.format), color: exportFormatColor(context, r.format)),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.fileName ?? '${exportFormatLabel(r.format)} · ${exportLangLabel(r.lang)}',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                    Text(
                      [
                        exportRunStatusLabel(r.status),
                        if (r.size != null) exportLtr(exportSizeLabel(r.size!)),
                        if (r.createdAt != null) AppTime.dateTime(r.createdAt!),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: meta,
                    ),
                  ]),
                ),
              ]),
            ),
          ),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSheetHeader(tx('exs_link_pick_run', 'Choose a file', 'اختر ملفًا')),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
          child: body,
        ),
      ),
    ]);
  }
}

/// The organization an export page works in: the organization mode's, else the org dashboard's (an org admin's
/// dashboard keeps it in OrgSession only, so "My organization" was never offered there). The server still checks
/// that the person belongs to it.
int? exportContextOrg(BuildContext context) {
  final mode = AppModeController.instance.currentOrgId;
  if (mode != null) return mode;
  try {
    return Provider.of<OrgSession>(context, listen: false).currentId;
  } catch (_) {
    return null; // no OrgSession above (tests)
  }
}

/// Opens the share sheet for a file the app just generated: audience (my organization only when [orgId] is set),
/// expiry, Create → the link with Copy. The created link (with its one-time token), or null.
Future<ExportLinkInfo?> showShareExportLinkSheet(
  BuildContext context, {
  required Uint8List bytes,
  required String fileName,
  int? orgId,
  String? dataset,
  Map<String, Object?>? params,
  ExportStudioApi? api,
}) async {
  final a = api ?? ExportStudioApi.instance;
  ExportLinkInfo? made;
  final link = await showAppSheet<ExportLinkInfo>(
    context,
    (_) => _ShareLinkSheet(
      fileName: fileName,
      size: bytes.length,
      orgAllowed: orgId != null,
      create: (audience, days) => a.linkFromUpload(bytes, fileName,
          audience: audience, expiresDays: days, orgId: orgId, dataset: dataset, params: params),
      onCreated: (l) => made = l,
    ),
  );
  return link ?? made;
}

class _ShareLinkSheet extends StatefulWidget {
  const _ShareLinkSheet({
    required this.fileName,
    required this.orgAllowed,
    required this.create,
    this.size,
    this.initialAudience,
    this.onCreated,
  });

  final String fileName;
  final int? size;
  final bool orgAllowed;
  final String? initialAudience;
  final Future<ExportResult<ExportLinkInfo>> Function(String audience, int days) create;
  final ValueChanged<ExportLinkInfo>? onCreated;

  @override
  State<_ShareLinkSheet> createState() => _ShareLinkSheetState();
}

class _ShareLinkSheetState extends State<_ShareLinkSheet> {
  late String _audience = widget.orgAllowed ? (widget.initialAudience ?? 'org') : 'me';
  int _days = 7;
  bool _busy = false;
  String? _error;
  ExportLinkInfo? _link;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.create(_audience, _days);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _link = r.data!;
      } else {
        _error = r.error;
      }
    });
    if (r.ok) {
      widget.onCreated?.call(r.data!);
    } else {
      showAppNotice(r.error!, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(_link == null ? tx('exs_link_share_title', 'Share with a link', 'مشاركة برابط') : tx('exs_link_ready', 'Your link is ready', 'الرابط جاهز')),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.lg),
            child: ExportShareLinkBody(
              fileName: widget.fileName,
              size: widget.size,
              orgAllowed: widget.orgAllowed,
              audience: _audience,
              days: _days,
              busy: _busy,
              error: _error,
              link: _link,
              onAudience: (a) => setState(() => _audience = a),
              onDays: (d) => setState(() => _days = d),
              onCreate: _create,
              onCopy: _link?.url == null ? null : () => _copy(_link!.url!),
              onDone: () => Navigator.of(context).pop(_link),
            ),
          ),
        ),
      ]);
}

/// The share sheet's body. Before [link] exists: the file, who can open it, how long, Create. After: the link
/// (selectable, LTR), Copy, and the notes — whoever opens it signs in (D-134) and it is shown only this once.
class ExportShareLinkBody extends StatelessWidget {
  const ExportShareLinkBody({
    super.key,
    required this.fileName,
    required this.orgAllowed,
    required this.audience,
    required this.days,
    this.size,
    this.busy = false,
    this.error,
    this.link,
    this.onAudience,
    this.onDays,
    this.onCreate,
    this.onCopy,
    this.onDone,
  });

  final String fileName;
  final int? size;
  final bool orgAllowed;

  /// me | org
  final String audience;
  final int days;
  final bool busy;
  final String? error;
  final ExportLinkInfo? link;
  final ValueChanged<String>? onAudience;
  final ValueChanged<int>? onDays;
  final VoidCallback? onCreate, onCopy, onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = AppType.meta(context);
    final fmt = exportFormatOf(fileName);
    Widget note(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: AppIconSize.sm, color: c.textLight)),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(text, style: meta)),
          ]),
        );
    final file = Row(children: [
      Icon(exportFormatIcon(fmt), color: exportFormatColor(context, fmt)),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
          Text([exportFormatLabel(fmt), if (size != null) exportLtr(exportSizeLabel(size!))].join(' · '), style: meta),
        ]),
      ),
    ]);
    final signIn = note(Icons.lock_outline_rounded,
        tx('exs_link_signin_note', 'Anyone opening it must sign in, and only people allowed to see this data can download it.',
            'من يفتحه يجب أن يسجّل الدخول، ولا ينزّله إلا من يحق له رؤية هذه البيانات.'));
    final l = link;
    if (l != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        file,
        AppSpace.gapMd,
        if (l.url != null) ExportLinkUrlBox(url: l.url!),
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          ExportTintPill(exportAudienceLabel(l.audience), color: c.charcoal, icon: exportAudienceIcon(l.audience)),
          if (l.expiresAt != null)
            ExportTintPill(tx('exs_link_until', 'Until {t}', 'حتى {t}').replaceAll('{t}', AppTime.dateTime(l.expiresAt!)),
                color: c.success, icon: Icons.timer_outlined),
        ]),
        note(Icons.visibility_outlined,
            tx('exs_link_once', 'This link is shown only once. Copy it now.', 'يظهر هذا الرابط مرة واحدة فقط. انسخه الآن.')),
        signIn,
        AppSpace.gapLg,
        AppPrimaryButton(label: tx('exs_link_copy', 'Copy link', 'نسخ الرابط'), icon: Icons.copy_rounded, onPressed: onCopy),
        AppSpace.gapXs,
        Center(child: ExportActionButton(icon: Icons.check_rounded, label: tx('exs_done', 'Done', 'تم'), onPressed: onDone)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      file,
      AppSpace.gapMd,
      Text(tx('exs_link_who', 'Who can open it', 'من يمكنه فتحه'), style: AppType.bodyStrong(context)),
      AppSpace.gapXs,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(
          label: exportAudienceLabel('me'),
          icon: exportAudienceIcon('me'),
          selected: audience == 'me',
          onTap: () => onAudience?.call('me'),
        ),
        if (orgAllowed)
          AppChoiceChip(
            label: exportAudienceLabel('org'),
            icon: exportAudienceIcon('org'),
            selected: audience == 'org',
            onTap: () => onAudience?.call('org'),
          ),
      ]),
      AppSpace.gapMd,
      AppDropdown<int>(
        value: days,
        decoration: InputDecoration(labelText: tx('exs_link_expires_after', 'Expires after', 'تنتهي صلاحيته بعد')),
        items: [for (final d in kExportLinkDays) DropdownMenuItem(value: d, child: Text(exportDaysLabel(d)))],
        onChanged: (v) => onDays?.call(v ?? 7),
      ),
      signIn,
      if (error != null) ...[
        AppSpace.gapMd,
        AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
      ],
      AppSpace.gapLg,
      AppPrimaryButton(
        label: tx('exs_link_create', 'Create link', 'إنشاء الرابط'),
        icon: Icons.add_link_rounded,
        busy: busy,
        onPressed: onCreate,
      ),
    ]);
  }
}
