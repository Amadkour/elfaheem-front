// lib/design/app_share_sheet.dart — THE Share action of the app (D-307): one sheet with the link (always
// left-to-right), Copy, the system share sheet (phones / desktop apps; the web shows the link instead) and a QR code.
//
//   shareAppLink(context, const AppLink.meeting(12), title: 'Staff sync')     a link of the one scheme (app_links.dart)
//   showAppShareSheet(context, url: guestUrl, title: …, kind: …)              any URL (a guest link, a profile link)
//
// Hidden by the kill switch `share.links` (the caller wraps its button in ParentComponent(featureKey: kShareLinksKey);
// [shareAppLink] does nothing while it is off). The body is the plain-values [AppShareSheetBody], laid out by
// test/ui/app_share_sheet_layout_test.dart.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';
import '../core/share/app_links.dart';
import '../features/admin/admin_common.dart' show t;
import 'app_kit.dart';

export '../core/share/app_links.dart';

/// The kill switch of every Share action (feature catalog `share.links`).
const kShareLinksKey = 'share.links';

/// The name and icon of a link's kind, for the sheet's header.
(String, IconData) appLinkKindLabel(AppLinkKind kind) => switch (kind) {
      AppLinkKind.course => (t('كورس', 'Course'), Icons.school_rounded),
      AppLinkKind.teacher => (t('معلم', 'Teacher'), Icons.person_rounded),
      AppLinkKind.material => (t('درس', 'Lesson'), Icons.play_lesson_rounded),
      AppLinkKind.session => (t('حصة مباشرة', 'Live session'), Icons.live_tv_rounded),
      AppLinkKind.meeting => (t('اجتماع', 'Meeting'), Icons.groups_rounded),
      AppLinkKind.roadmap => (t('مسار تعلم', 'Learning path'), Icons.route_rounded),
      AppLinkKind.page => (t('صفحة', 'Page'), Icons.web_rounded),
    };

/// The origin links are built on: the site being browsed on the web (a local stack shares its own address), the
/// public site in the apps.
String appLinkOrigin() => kIsWeb ? Uri.base.origin : AppLink.site;

/// Opens the share sheet of [link]. Nothing while `share.links` is switched off.
Future<void> shareAppLink(BuildContext context, AppLink link, {required String title, String? subtitle, String? hint}) {
  if (AppConfig.disableList.contains(kShareLinksKey)) return Future.value();
  final (kind, icon) = appLinkKindLabel(link.kind);
  return showAppShareSheet(context,
      url: link.url(appLinkOrigin()), title: title, subtitle: subtitle, kind: kind, icon: icon, hint: hint);
}

/// The share sheet of any [url]. [kind] names what is shared ("Meeting"), [hint] says who can open it.
Future<void> showAppShareSheet(BuildContext context,
    {required String url, required String title, String? subtitle, String? kind, IconData? icon, String? hint}) {
  return showAppSheet<void>(
    context,
    (ctx) => _AppShareSheet(url: url, title: title, subtitle: subtitle, kind: kind, icon: icon, hint: hint),
  );
}

class _AppShareSheet extends StatefulWidget {
  const _AppShareSheet({required this.url, required this.title, this.subtitle, this.kind, this.icon, this.hint});
  final String url, title;
  final String? subtitle, kind, hint;
  final IconData? icon;

  @override
  State<_AppShareSheet> createState() => _AppShareSheetState();
}

class _AppShareSheetState extends State<_AppShareSheet> {
  bool _qr = false, _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    setState(() => _copied = true);
    showAppNotice(t('تم نسخ الرابط', 'Link copied'));
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(text: '${widget.title}\n${widget.url}', subject: widget.title));
    } catch (_) {
      await _copy();
    }
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: t('مشاركة', 'Share'),
        children: [
          AppShareSheetBody(
            url: widget.url,
            title: widget.title,
            subtitle: widget.subtitle,
            kind: widget.kind,
            icon: widget.icon ?? Icons.link_rounded,
            hint: widget.hint,
            showQr: _qr,
            copied: _copied,
            onCopy: _copy,
            onShare: kIsWeb ? null : _share,
            onToggleQr: () => setState(() => _qr = !_qr),
          ),
        ],
      );
}

/// The sheet's body from plain values: what is shared, the link, Copy · Share · QR, and the QR code when open.
class AppShareSheetBody extends StatelessWidget {
  const AppShareSheetBody({
    super.key,
    required this.url,
    required this.title,
    required this.icon,
    required this.onCopy,
    required this.onToggleQr,
    this.subtitle,
    this.kind,
    this.hint,
    this.onShare,
    this.showQr = false,
    this.copied = false,
  });

  final String url, title;
  final String? subtitle, kind, hint;
  final IconData icon;
  final VoidCallback onCopy, onToggleQr;

  /// The system share sheet; null hides the button (the web).
  final VoidCallback? onShare;
  final bool showQr, copied;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, c.primary);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.card)),
          child: Icon(icon, color: ink, size: AppIconSize.lg),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (kind != null) Text(kind!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.overline(context).copyWith(color: ink)),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
      ]),
      const SizedBox(height: AppSpace.md),
      // links read left-to-right inside an Arabic page too
      Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: c.inputBg,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            key: const ValueKey('share.url'),
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: onCopy,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                child: Row(children: [
                  Icon(Icons.link_rounded, size: AppIconSize.md, color: ink),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: SelectableText(url, maxLines: 2, style: AppType.row(context).copyWith(color: c.textDark)),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Icon(copied ? Icons.check_rounded : Icons.copy_rounded, size: AppIconSize.md, color: copied ? c.success : c.textMedium),
                ]),
              ),
            ),
          ),
        ),
      ),
      if (hint != null) ...[
        const SizedBox(height: AppSpace.xs),
        Text(hint!, style: AppType.meta(context)),
      ],
      const SizedBox(height: AppSpace.md),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppButton.primary(
          key: const ValueKey('share.copy'),
          label: copied ? t('تم النسخ', 'Copied') : t('نسخ الرابط', 'Copy link'),
          icon: copied ? Icons.check_rounded : Icons.copy_rounded,
          onPressed: onCopy,
        ),
        if (onShare != null)
          AppButton.secondary(
            key: const ValueKey('share.native'),
            label: t('مشاركة…', 'Share…'),
            icon: Icons.ios_share_rounded,
            onPressed: onShare,
          ),
        AppButton.ghost(
          key: const ValueKey('share.qr'),
          label: showQr ? t('إخفاء رمز QR', 'Hide QR code') : t('رمز QR', 'QR code'),
          icon: Icons.qr_code_2_rounded,
          onPressed: onToggleQr,
        ),
      ]),
      if (showQr) ...[
        const SizedBox(height: AppSpace.md),
        Center(
          child: Container(
            key: const ValueKey('share.qr_image'),
            padding: const EdgeInsets.all(AppSpace.sm),
            // the quiet zone stays pure white in both themes: phone scanners need the contrast
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.card)),
            child: QrImageView(data: url, version: QrVersions.auto, size: 200, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(t('امسحه بكاميرا الهاتف لفتح الرابط', 'Scan it with a phone camera to open the link'),
            textAlign: TextAlign.center, style: AppType.meta(context)),
      ],
    ]);
  }
}
