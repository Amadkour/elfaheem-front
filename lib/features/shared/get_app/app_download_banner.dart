// lib/features/shared/get_app/app_download_banner.dart — the website channel's download strip (D-144,
// docs/release/APP_RELEASES_CODEMAGIC.md "Front repo"), on the WEB build only:
//
//   AppDownloadBanner(child:)   in MaterialApp.builder (main.dart), under the "A new version is live" strip of D-143
//                               (both can show; the reload strip keeps the top spot) and above every page, the sign-in
//                               page included. One button for this device (the universal APK on Android, the Windows
//                               zip, the Linux .deb; "How to install" → Add to Home Screen on iPhone / iPad; "See
//                               downloads" elsewhere), "Other downloads" opening the sheet, and a close button
//                               remembered on this browser for this version. Hidden while the live room is open, in the
//                               native app, an installed web app or a wrapper, when nothing is published, when the
//                               request fails, and by the kill switch `app.download_banner`.
//   AppDownloadsSheetBody       every download (this device first), over plain values (test/ui/app_releases_layout_test).
//
// Data and rules: lib/core/release/app_downloads.dart. The strip itself is the D-137 GetAppBannerView, so the two
// "get the app" strips look the same; while anything is published here the D-137 strip steps aside.
library;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/display/app_fonts.dart';
import '../../../core/get_app/releases_manifest.dart' show formatReleaseSize;
import '../../../core/release/app_downloads.dart';
import '../../../design/app_kit.dart' show showAppSheet, AppSheetHeader;
import '../../../design/app_notice.dart';
import '../../../design/app_tokens.dart';
import '../../../main.dart' show navigatorKey;
import '../../../utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/live/live_room_host.dart' show LiveRoomHost;
import 'get_app_banner.dart' show GetAppBannerView;
import 'get_app_sheet.dart' show getAppIcon, getAppLtr;

export '../../../core/release/app_downloads.dart';

/// The platform's name ("Android", "Windows", …).
String appDownloadPlatformName(String platform) {
  final key = 'get_app_platform_$platform';
  final v = key.tr;
  return v == key ? platform : v;
}

GetAppOs appDownloadOsOf(String platform) => switch (platform) {
      'android' => GetAppOs.android,
      'ios' => GetAppOs.ios,
      'windows' => GetAppOs.windows,
      'macos' => GetAppOs.macos,
      _ => GetAppOs.linux,
    };

/// "Most phones (64-bit)", "All devices (larger file)", ".deb", ".tar.gz", ".zip".
String appDownloadFileLabel(AppDownloadFile f) {
  final key = 'get_app_arch_${f.abi}';
  final arch = f.abi == null ? key : key.tr;
  final kind = switch (f.kind) {
    'apk' || '' => '',
    'tar' || 'gz' => getAppLtr('.tar.gz'),
    _ => getAppLtr('.${f.kind}'),
  };
  if (arch == key || f.kind != 'apk') return kind.isEmpty ? getAppLtr(f.name) : kind;
  return arch;
}

String _versionSize(AppDownloadRelease? r, AppDownloadFile? f) => [
      if (r != null && r.version.isNotEmpty) 'get_app_meta_version'.tr.replaceAll('{v}', getAppLtr(r.version)),
      if (formatReleaseSize(f?.size).isNotEmpty) getAppLtr(formatReleaseSize(f?.size)),
    ].join(' · ');

/// The strip's words for [o] (plain strings; [releases] names the platforms of "See downloads").
({String title, String meta, String action, IconData icon}) appDownloadStripText(AppDownloadOffer o, List<AppDownloadRelease> releases) =>
    switch (o.kind) {
      AppDownloadOfferKind.file => (
          title: 'get_app_title_${o.release!.platform}'.tr,
          meta: _versionSize(o.release, o.file),
          action: 'get_app_download'.tr,
          icon: getAppIcon(o.os),
        ),
      AppDownloadOfferKind.iosWebApp => (
          title: 'get_app_install_title_${o.os == GetAppOs.ipados ? 'ipados' : 'ios'}'.tr,
          meta: 'get_app_meta_ios'.tr,
          action: 'get_app_how_to_install'.tr,
          icon: getAppIcon(o.os),
        ),
      AppDownloadOfferKind.browse => (
          title: 'app_dl_browse_title'.tr,
          meta: [for (final r in releases) appDownloadPlatformName(r.platform)].join(' · '),
          action: 'app_dl_see_downloads'.tr,
          icon: Icons.install_desktop_rounded,
        ),
    };

// ─────────────────────────────────────────────────────────────────────────────
// Host
// ─────────────────────────────────────────────────────────────────────────────

class AppDownloadBanner extends StatefulWidget {
  const AppDownloadBanner({super.key, required this.child, this.service, this.enabled = kIsWeb, this.openSheet});

  final Widget child;

  /// Tests pass their own; the app uses [AppDownloadsService.instance].
  final AppDownloadsService? service;

  /// Tests turn it on off the web.
  final bool enabled;

  /// Opens the downloads sheet (the app: over the root Navigator, because the strip sits above it).
  final void Function(AppDownloadsService s)? openSheet;

  @override
  State<AppDownloadBanner> createState() => _AppDownloadBannerState();
}

class _AppDownloadBannerState extends State<AppDownloadBanner> {
  AppDownloadsService get _s => widget.service ?? AppDownloadsService.instance;

  late final Listenable _deps = Listenable.merge([_s, LiveRoomHost.listenable, AppConfig.disableListVersion]);

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    _s.init();
    _deps.addListener(_changed);
  }

  @override
  void dispose() {
    if (widget.enabled) _deps.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _sheet() {
    final open = widget.openSheet;
    if (open != null) return open(_s);
    final ctx = navigatorKey.currentContext;
    if (ctx != null) showAppDownloadsSheet(ctx, service: _s);
  }

  Future<void> _primary(AppDownloadOffer o) async {
    if (o.kind == AppDownloadOfferKind.file && o.file != null) {
      if (!await _s.download(o.file!)) showAppNotice('get_app_open_failed'.tr, error: true);
    } else {
      _sheet();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final o = _s.visible && !LiveRoomHost.isOpen ? _s.offer : null;
    final Widget strip;
    if (o != null) {
      final w = appDownloadStripText(o, _s.releases);
      strip = ParentComponent(
        featureKey: kDownloadBannerKey,
        child: GetAppBannerView(
          key: ValueKey('app_download_${o.kind.name}'),
          icon: w.icon,
          title: w.title,
          meta: w.meta,
          actionLabel: w.action,
          onAction: () => _primary(o),
          detailsLabel: o.kind == AppDownloadOfferKind.browse ? null : 'app_dl_other_downloads'.tr,
          onDetails: o.kind == AppDownloadOfferKind.browse ? null : _sheet,
          onDismiss: _s.dismiss,
        ),
      );
    } else {
      strip = const SizedBox(width: double.infinity);
    }
    final motion = AppMotion.of(context);
    return Column(children: [
      AnimatedSize(duration: motion.base, curve: AppMotion.curve, alignment: AlignmentDirectional.topCenter, child: strip),
      // Keyed so the Navigator keeps its state when the strip comes and goes.
      Expanded(
        key: const ValueKey('app_content_app_download'),
        child: MediaQuery.removePadding(context: context, removeTop: o != null, child: widget.child),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet
// ─────────────────────────────────────────────────────────────────────────────

/// Every download, this device first ([context] under the Navigator).
Future<void> showAppDownloadsSheet(BuildContext context, {AppDownloadsService? service}) {
  final s = service ?? AppDownloadsService.instance;
  return showAppSheet<void>(
    context,
    (ctx) => ListenableBuilder(
      listenable: s,
      builder: (ctx, _) => AppDownloadsSheetBody(
        releases: s.releases,
        offer: s.offer,
        iosSafari: s.env.iosSafari,
        onDownload: (f) async {
          if (!await s.download(f)) showAppNotice('get_app_open_failed'.tr, error: true);
        },
      ),
    ),
  );
}

TextStyle _meta(BuildContext context) => AppType.meta(context).copyWith(fontFamily: AppFonts.family, height: 1.4);

TextStyle _row(BuildContext context) => AppType.row(context).copyWith(fontFamily: AppFonts.family);

class AppDownloadsSheetBody extends StatelessWidget {
  const AppDownloadsSheetBody({super.key, required this.releases, required this.offer, required this.onDownload, this.iosSafari = true});

  final List<AppDownloadRelease> releases;
  final AppDownloadOffer? offer;
  final ValueChanged<AppDownloadFile> onDownload;

  /// The iPhone / iPad steps assume Safari; another browser is told to open the page in Safari first.
  final bool iosSafari;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final mine = o?.kind == AppDownloadOfferKind.file ? o!.release : null;
    final others = [for (final r in releases) if (!identical(r, mine)) r];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetHeader('get_app_entry'.tr),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.md, AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('get_app_sheet_sub'.tr, style: _meta(context)),
              if (o != null && o.kind != AppDownloadOfferKind.browse) ...[
                const SizedBox(height: AppSpace.md),
                _Label('get_app_this_device'.tr),
                o.kind == AppDownloadOfferKind.file
                    ? _DeviceCard(offer: o, onDownload: onDownload)
                    : _IosCard(os: o.os, iosSafari: iosSafari),
              ],
              if (mine != null && mine.others.isNotEmpty || others.isNotEmpty) ...[
                const SizedBox(height: AppSpace.lg),
                _Label('app_dl_other_downloads'.tr),
                if (mine != null && mine.others.isNotEmpty) _PlatformCard(release: mine, files: mine.others, onDownload: onDownload),
                for (final r in others) _PlatformCard(release: r, files: r.files, onDownload: onDownload),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Semantics(header: true, child: Text(text, style: AppType.bodyStrong(context))),
      );
}

class _IconWell extends StatelessWidget {
  const _IconWell({required this.icon, this.small = false});

  final IconData icon;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = small ? 32.0 : 40.0;
    return ExcludeSemantics(
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(color: small ? c.primaryTint : c.cardBg, borderRadius: BorderRadius.circular(AppRadius.chip)),
        child: Icon(icon, size: small ? 18 : 22, color: c.isDark ? c.primaryLight : c.primary),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.offer, required this.onDownload});

  final AppDownloadOffer offer;
  final ValueChanged<AppDownloadFile> onDownload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = offer.release!;
    final f = offer.file!;
    final notes = r.notes(AppConfig.lang);
    return Container(
      key: const ValueKey('app_dl.device'),
      padding: AppSpace.card,
      decoration: BoxDecoration(
        color: c.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.primary.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _IconWell(icon: getAppIcon(offer.os)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('get_app_title_${r.platform}'.tr, style: _row(context).copyWith(fontWeight: FontWeight.w700)),
              Text([appDownloadFileLabel(f), _versionSize(r, f)].where((s) => s.isNotEmpty).join(' · '), style: _meta(context)),
            ]),
          ),
        ]),
        if (r.platform == 'android') ...[
          const SizedBox(height: AppSpace.xs),
          Text('get_app_update_hint'.tr, style: _meta(context)),
        ],
        const SizedBox(height: AppSpace.sm),
        FilledButton.icon(
          key: ValueKey('app_dl.file.${f.name}'),
          onPressed: () => onDownload(f),
          icon: const Icon(Icons.download_rounded, size: 20),
          label: Text('get_app_download'.tr, style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(
            backgroundColor: c.primary,
            foregroundColor: c.onHero,
            minimumSize: const Size.fromHeight(AppTouch.min),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          ),
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text('${'get_app_whats_new'.tr}: $notes', style: _meta(context)),
        ],
      ]),
    );
  }
}

/// iPhone / iPad: the installable web app (Share → Add to Home Screen); Apple allows no other install.
class _IosCard extends StatelessWidget {
  const _IosCard({required this.os, required this.iosSafari});

  final GetAppOs os;
  final bool iosSafari;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('app_dl.ios'),
      padding: AppSpace.card,
      decoration: BoxDecoration(
        color: c.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.primary.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _IconWell(icon: getAppIcon(os)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('get_app_install_title_${os == GetAppOs.ipados ? 'ipados' : 'ios'}'.tr, style: _row(context).copyWith(fontWeight: FontWeight.w700)),
              Text('get_app_meta_ios'.tr, style: _meta(context)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        if (!iosSafari) _Step(n: 0, icon: Icons.link_rounded, text: 'get_app_safari_step'.tr),
        _Step(n: 1, icon: CupertinoIcons.share, text: 'get_app_ios_step1'.tr),
        _Step(n: 2, icon: CupertinoIcons.plus_app, text: 'get_app_ios_step2'.tr),
        _Step(n: 3, icon: Icons.check_circle_outline_rounded, text: 'get_app_ios_step3'.tr),
        Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text('get_app_ios_note'.tr, style: _meta(context))),
      ]),
    );
  }
}

/// One numbered step ([n] 0 = an unnumbered first step, e.g. "open this page in Safari").
class _Step extends StatelessWidget {
  const _Step({required this.n, required this.icon, required this.text});

  final int n;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExcludeSemantics(
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: n == 0 ? c.warning : c.primary, shape: BoxShape.circle),
            child: n == 0
                ? Icon(Icons.priority_high_rounded, size: 16, color: c.onHero)
                : Text('$n', style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.onHero)),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: _row(context)))),
        const SizedBox(width: AppSpace.xs),
        ExcludeSemantics(child: Icon(icon, size: 22, color: c.isDark ? c.primaryLight : c.primary)),
      ]),
    );
  }
}

class _PlatformCard extends StatelessWidget {
  const _PlatformCard({required this.release, required this.files, required this.onDownload});

  final AppDownloadRelease release;
  final List<AppDownloadFile> files;
  final ValueChanged<AppDownloadFile> onDownload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = release;
    return Container(
      key: ValueKey('app_dl.platform.${r.platform}'),
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.xs, AppSpace.xs),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _IconWell(icon: getAppIcon(appDownloadOsOf(r.platform)), small: true),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(appDownloadPlatformName(r.platform), style: _row(context).copyWith(fontWeight: FontWeight.w700)),
              if (r.version.isNotEmpty) Text('get_app_meta_version'.tr.replaceAll('{v}', getAppLtr(r.version)), style: _meta(context)),
            ]),
          ),
        ]),
        for (final f in files)
          Row(children: [
            Expanded(
              child: Padding(
                // under the platform's name on a wide sheet; from the edge on a phone, so "Most phones (64-bit)" keeps one line
                padding: EdgeInsetsDirectional.only(start: MediaQuery.sizeOf(context).width < 480 ? 0 : 40),
                // the label, then the size under it (one line joined with "·" broke in the middle on a phone)
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(appDownloadFileLabel(f), style: _row(context).copyWith(fontSize: 13.5)),
                  if (formatReleaseSize(f.size).isNotEmpty) Text(getAppLtr(formatReleaseSize(f.size)), style: _meta(context)),
                ]),
              ),
            ),
            // a long label (large text, a translation) shortens instead of squeezing the file name
            Flexible(
              child: TextButton.icon(
                key: ValueKey('app_dl.file.${f.name}'),
                onPressed: () => onDownload(f),
                style: TextButton.styleFrom(
                  foregroundColor: c.isDark ? c.primaryLight : c.primary,
                  minimumSize: const Size(AppTouch.min, AppTouch.min),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text('get_app_download'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppFonts.family)),
              ),
            ),
          ]),
      ]),
    );
  }
}
