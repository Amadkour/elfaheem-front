// lib/features/sessions/material/material_guest_links_sheet.dart — "Share with guests" for a course video
// (D-841): the session's staff make a link that plays THIS video for anyone who opens it, no account, view only.
//
//   showMaterialGuestLinksSheet(context, sessionId:, materialId:, title:)   the sheet (list · create · copy · share ·
//                                                                          revoke), over material_guest_links_api
//   MaterialGuestLinksBody                                                  its plain-values body
//                                                                          (test/ui/guest_share_layout_test.dart)
//
// Kill switch `materials.guest_link` (the caller hides the option; the server refuses a create too).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_share_sheet.dart' show showAppShareSheet;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/sessions/material/material_guest_links_api.dart';

Future<void> showMaterialGuestLinksSheet(BuildContext context,
        {required int sessionId, required int materialId, required String title, MaterialGuestLinksApi? api}) =>
    showAppSheet<void>(
        context,
        (_) => _MaterialGuestLinksSheet(
            sessionId: sessionId, materialId: materialId, title: title, api: api ?? RemoteMaterialGuestLinksApi()));

class _MaterialGuestLinksSheet extends StatefulWidget {
  const _MaterialGuestLinksSheet({required this.sessionId, required this.materialId, required this.title, required this.api, this.captions, this.subtitle});
  final int sessionId, materialId;
  final String title;
  final String? subtitle;

  /// Captions on top of the sharing (the video's CC button); null: the sharing alone.
  final Widget? captions;
  final MaterialGuestLinksApi api;

  @override
  State<_MaterialGuestLinksSheet> createState() => _MaterialGuestLinksSheetState();
}

class _MaterialGuestLinksSheetState extends State<_MaterialGuestLinksSheet> {
  List<MaterialGuestLink> _links = const [];
  bool _loading = true, _busy = false;
  String? _error;
  int? _expiry = 7;

  @override
  void initState() {
    super.initState();
    _run(() => widget.api.list(widget.sessionId, widget.materialId), first: true);
  }

  Future<MaterialGuestLinks?> _run(Future<MaterialGuestLinks> Function() call, {bool first = false}) async {
    setState(() => first ? _loading = true : _busy = true);
    try {
      final r = await call();
      if (!mounted) return null;
      setState(() {
        _links = r.links;
        _loading = _busy = false;
        _error = null;
      });
      return r;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _loading = _busy = false;
        if (first) _error = materialGuestErrorText(e);
      });
      if (!first) showAppNotice(materialGuestErrorText(e), error: true);
      return null;
    }
  }

  Future<void> _create() async {
    final r = await _run(() => widget.api.create(widget.sessionId, widget.materialId, expiresDays: _expiry));
    final made = r?.created;
    if (made == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: made.link));
    showAppNotice(t('الرابط جاهز ونُسخ — من يفتحه يشاهد الفيديو دون حساب', 'Link ready and copied — whoever opens it watches the video without an account'));
  }

  Future<void> _copy(MaterialGuestLink l) async {
    await Clipboard.setData(ClipboardData(text: l.link));
    showAppNotice(t('تم نسخ الرابط', 'Link copied'));
  }

  void _share(MaterialGuestLink l) => showAppShareSheet(context,
      url: l.link,
      title: widget.title,
      kind: t('فيديو للضيوف', 'Video for guests'),
      icon: Icons.smart_display_rounded,
      hint: t('يفتحه أي شخص دون حساب، للمشاهدة فقط.', 'Anyone can open it without an account, view only.'));

  Future<void> _revoke(MaterialGuestLink l) async {
    if (!await appConfirm(context,
        message: t('سيتوقف هذا الرابط فوراً، حتى لمن يشاهد الآن. متابعة؟', 'This link stops at once, even for someone watching now. Continue?'),
        danger: true,
        confirmLabel: t('إلغاء الرابط', 'Revoke'))) {
      return;
    }
    if (!mounted) return;
    await _run(() => widget.api.revoke(widget.sessionId, widget.materialId, l.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final share = !AppConfig.disableList.contains('materials.guest_link');
    final body = _loading
        ? const AppListSkeleton(items: 2)
        : MaterialGuestLinksBody(
            links: _links,
            error: _error,
            expiresDays: _expiry,
            busy: _busy,
            onExpiry: (d) => setState(() => _expiry = d),
            onCreate: _create,
            onCopy: _copy,
            onShare: kIsWeb ? null : _share,
            onRevoke: _revoke,
          );
    return AppSheetContent(
      tone: AppTone.brand,
      icon: widget.captions == null ? Icons.public_rounded : Icons.smart_display_rounded,
      title: widget.captions == null ? t('مشاركة مع ضيوف', 'Share with guests') : widget.title,
      subtitle: widget.captions == null ? widget.title : widget.subtitle,
      children: [
        ?widget.captions,
        if (widget.captions != null && share) ...[
          const SizedBox(height: AppSpace.md),
          Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
          const SizedBox(height: AppSpace.md),
          Row(children: [
            Icon(Icons.link_rounded, size: AppIconSize.md, color: c.textDark),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(t('مشاركة مع ضيوف', 'Share with guests'), style: AppType.section(context))),
          ]),
          const SizedBox(height: AppSpace.sm),
        ],
        if (widget.captions == null || share) body,
      ],
    );
  }
}

/// Where a video's captions stand.
enum MaterialCaptionsState { none, pending, failed, ready }

/// The captions part of the video's sheet (Tea1Course "captions and sharing"): a state chip, the actions (upload a
/// .vtt, generate automatically, delete) and one note about the automatic job. Plain values.
class MaterialCaptionsPanel extends StatelessWidget {
  const MaterialCaptionsPanel({super.key, required this.state, this.onUpload, this.onGenerate, this.onRemove});

  final MaterialCaptionsState state;
  final VoidCallback? onUpload, onGenerate, onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, tone) = switch (state) {
      MaterialCaptionsState.ready => (t('جاهزة', 'Ready'), AppTone.success),
      MaterialCaptionsState.pending => (t('قيد الإنشاء', 'Being made'), AppTone.info),
      MaterialCaptionsState.failed => (t('فشلت', 'Failed'), AppTone.danger),
      MaterialCaptionsState.none => (t('لا توجد', 'None yet'), AppTone.neutral),
    };
    Widget action(String key, String text, IconData icon, VoidCallback? on, {bool danger = false}) => AppButton(
          key: ValueKey(key),
          label: text,
          icon: icon,
          variant: danger ? AppButtonVariant.danger : AppButtonVariant.secondary,
          dangerOutline: danger,
          onPressed: on,
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Icon(Icons.closed_caption_rounded, size: AppIconSize.md, color: c.textDark),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(t('الترجمة النصية', 'Captions'), style: AppType.section(context))),
        AppStatusBadge(label: label, tone: tone),
      ]),
      const SizedBox(height: AppSpace.sm),
      Text(
        state == MaterialCaptionsState.failed ? 'captions_status_failed'.tr : 'captions_none'.tr,
        style: AppType.body(context).copyWith(color: c.textMedium),
      ),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        action('captions.upload', t('رفع ملف .vtt', 'Upload .vtt file'), Icons.upload_rounded, onUpload),
        if (state != MaterialCaptionsState.pending)
          action('captions.generate', state == MaterialCaptionsState.failed ? 'captions_retry'.tr : t('إنشاء تلقائي', 'Generate automatically'),
              Icons.auto_awesome_rounded, onGenerate),
        if (state == MaterialCaptionsState.ready && onRemove != null)
          action('captions.remove', t('حذف', 'Delete'), Icons.delete_outline_rounded, onRemove, danger: true),
      ]),
      const SizedBox(height: AppSpace.sm),
      AppBanner(
        icon: Icons.info_outline_rounded,
        text: t('الإنشاء التلقائي يدخل قائمة انتظار ويوصلك إشعار لما يجهز. لو تعطّل تقدر تعيده من هنا.',
            'Automatic captions join a queue and you get a notice when they are ready. If it stalls you can run it again from here.'),
        color: c.primary,
      ),
    ]);
  }
}

/// A video's sheet: its captions on top, then "Share with guests" (unless the kill switch `materials.guest_link` is
/// off). Each captions action closes the sheet and runs its callback.
Future<void> showMaterialCaptionsSheet(BuildContext context,
        {required int sessionId,
        required int materialId,
        required String title,
        String? subtitle,
        required MaterialCaptionsState state,
        VoidCallback? onUpload,
        VoidCallback? onGenerate,
        VoidCallback? onRemove,
        MaterialGuestLinksApi? api}) =>
    showAppSheet<void>(context, (sheet) {
      VoidCallback? run(VoidCallback? f) => f == null
          ? null
          : () {
              Navigator.of(sheet).pop();
              f();
            };
      return _MaterialGuestLinksSheet(
        sessionId: sessionId,
        materialId: materialId,
        title: title,
        subtitle: subtitle,
        api: api ?? RemoteMaterialGuestLinksApi(),
        captions: MaterialCaptionsPanel(
          state: state,
          onUpload: run(onUpload),
          onGenerate: run(onGenerate),
          onRemove: run(onRemove),
        ),
      );
    });

/// The sheet's body from plain values: what a guest link is, how long a new one works, Create link, the live links
/// (views, expiry) with Copy · Share · Revoke.
class MaterialGuestLinksBody extends StatelessWidget {
  const MaterialGuestLinksBody({
    super.key,
    this.links = const [],
    this.error,
    this.expiresDays = 7,
    this.busy = false,
    this.onExpiry,
    this.onCreate,
    this.onCopy,
    this.onShare,
    this.onRevoke,
  });

  final List<MaterialGuestLink> links;
  final String? error;
  final int? expiresDays;
  final bool busy;
  final ValueChanged<int?>? onExpiry;
  final VoidCallback? onCreate;
  final ValueChanged<MaterialGuestLink>? onCopy, onShare, onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final live = [for (final l in links) if (!l.expired) l];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(
        t('من يفتح الرابط يشاهد هذا الفيديو فقط مباشرة دون حساب: للمشاهدة فقط، بلا تنزيل، مع حماية الشاشة. لا يفتح أي محتوى آخر من الكورس، ويمكنك إلغاؤه في أي وقت.',
            'Whoever opens the link watches only this video, straight away, no account: view only, no download, screen protected. It opens nothing else of the course, and you can revoke it at any time.'),
        style: AppType.body(context).copyWith(color: c.textMedium),
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
      ],
      const SizedBox(height: AppSpace.md),
      Text(t('صلاحية الرابط الجديد', 'A new link works for'),
          style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final d in materialGuestExpiries)
          AppChoiceChip(
            key: ValueKey('material_guest.expiry.${d ?? 'never'}'),
            label: materialGuestExpiryLabel(d),
            selected: d == expiresDays,
            onTap: () => busy ? null : onExpiry?.call(d),
          ),
      ]),
      const SizedBox(height: AppSpace.sm),
      AppButton(
        key: const ValueKey('material_guest.create'),
        label: t('إنشاء رابط', 'Create link'),
        icon: Icons.add_link_rounded,
        variant: AppButtonVariant.tonal,
        busy: busy,
        expand: true,
        onPressed: busy || error != null ? null : onCreate,
      ),
      if (live.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        Text(t('الروابط النشطة', 'Active links'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xxs),
        for (final l in live) _LinkRow(link: l, busy: busy, onCopy: onCopy, onShare: onShare, onRevoke: onRevoke),
      ],
    ]);
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.link, this.busy = false, this.onCopy, this.onShare, this.onRevoke});
  final MaterialGuestLink link;
  final bool busy;
  final ValueChanged<MaterialGuestLink>? onCopy, onShare, onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = link;
    final meta = [
      l.expiresAt == null ? t('بلا انتهاء', 'Never expires') : t('حتى ${AppTime.date(l.expiresAt!)}', 'Until ${AppTime.date(l.expiresAt!)}'),
      if (l.openedAt == null) t('لم يُفتح بعد', 'Not opened yet') else t('${l.views} مشاهدة', '${l.views} views'),
    ].join(' · ');
    IconButton action(String key, String tip, IconData icon, ValueChanged<MaterialGuestLink>? on, {Color? color}) => IconButton(
          key: ValueKey('material_guest.$key.${l.id}'),
          tooltip: tip,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(icon, color: color ?? c.textMedium, size: AppIconSize.md),
          onPressed: busy || on == null ? null : () => on(l),
        );
    return ConstrainedBox(
      key: ValueKey('material_guest.link.${l.id}'),
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(Icons.link_rounded, size: AppIconSize.md, color: appInk(context, c.primary)),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(l.link,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: AppType.row(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
              Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
            ]),
          ),
          action('copy', t('نسخ الرابط', 'Copy link'), Icons.copy_rounded, onCopy),
          if (onShare != null) action('share', t('مشاركة', 'Share'), Icons.ios_share_rounded, onShare),
          action('revoke', t('إلغاء الرابط', 'Revoke'), Icons.link_off_rounded, onRevoke, color: c.danger),
        ]),
      ),
    );
  }
}
