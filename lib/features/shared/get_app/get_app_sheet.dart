// lib/features/shared/get_app/get_app_sheet.dart — "Get the app" with every platform (web build): this device first
// with its install steps, then the other platforms. Opened from the banner and from the settings row.
//
//   showGetAppSheet(context)   reads GetAppService.instance (manifest + browser)
//   GetAppSheetBody            the sheet over plain values (what test/ui/get_app_test.dart lays out)
library;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/display/app_fonts.dart';
import '../../../core/get_app/get_app_service.dart';
import '../../../design/app_kit.dart' show showAppSheet, AppSheetHeader;
import '../../../design/app_notice.dart';
import '../../../design/app_tokens.dart';

/// "Get the Android app", "Install NextBrain on your iPhone", …
String getAppOfferTitle(GetAppOffer o) => switch (o.kind) {
      GetAppOfferKind.download => 'get_app_title_${o.os.name}'.tr,
      GetAppOfferKind.installIos => 'get_app_install_title_${o.os == GetAppOs.ipados ? 'ipados' : 'ios'}'.tr,
      GetAppOfferKind.openInSafari => 'get_app_open_safari_title'.tr,
      GetAppOfferKind.installWeb => 'get_app_install_title_web'.tr,
    };

/// "Version 1.0.0 · 48.7 MB", or the one-line promise of an install from the browser.
String getAppOfferMeta(GetAppOffer o) => switch (o.kind) {
      GetAppOfferKind.download => _versionSize(o.release, o.file),
      GetAppOfferKind.installIos => 'get_app_meta_ios'.tr,
      GetAppOfferKind.openInSafari => 'get_app_meta_safari'.tr,
      GetAppOfferKind.installWeb => 'get_app_meta_web'.tr,
    };

/// The banner's button.
String getAppOfferAction(GetAppOffer o, {bool canPrompt = false}) => switch (o.kind) {
      GetAppOfferKind.download => 'get_app_download'.tr,
      GetAppOfferKind.installIos => 'get_app_how_to_install'.tr,
      GetAppOfferKind.openInSafari => 'get_app_copy_link'.tr,
      GetAppOfferKind.installWeb => canPrompt ? 'get_app_install'.tr : 'get_app_how_to_install'.tr,
    };

IconData getAppIcon(GetAppOs os) => switch (os) {
      GetAppOs.android => Icons.phone_android_rounded,
      GetAppOs.ios => Icons.phone_iphone_rounded,
      GetAppOs.ipados => Icons.tablet_mac_rounded,
      GetAppOs.windows => Icons.desktop_windows_rounded,
      GetAppOs.macos => Icons.laptop_mac_rounded,
      _ => Icons.computer_rounded,
    };

GetAppOs _osOfKey(String key) => switch (key) {
      'android' => GetAppOs.android,
      'ios' => GetAppOs.ios,
      'windows' => GetAppOs.windows,
      'macos' => GetAppOs.macos,
      _ => GetAppOs.linux,
    };

/// [s] as a left-to-right island ("1.0.0", "48.7 MB", "Android 7.0"), so an Arabic line does not reorder its parts.
String getAppLtr(String s) => s.isEmpty ? s : '${String.fromCharCode(0x2066)}$s${String.fromCharCode(0x2069)}';

String _versionSize(PlatformRelease r, ReleaseFile? f) {
  final parts = [
    if (r.version.isNotEmpty) 'get_app_meta_version'.tr.replaceAll('{v}', getAppLtr(r.version)),
    if (formatReleaseSize(f?.size).isNotEmpty) getAppLtr(formatReleaseSize(f?.size)),
  ];
  return parts.join(' · ');
}

/// "Most phones (64-bit)", "Intel / AMD (64-bit) · .deb"; an arch without a label shows the file type alone. An APK
/// needs no type: the platform says it.
String getAppFileLabel(ReleaseFile f) {
  final key = 'get_app_arch_${f.arch}';
  final arch = key.tr;
  final kind = f.kind.isEmpty || f.kind == 'apk' ? '' : getAppLtr('.${f.kind}');
  if (arch == key) return kind.isEmpty ? f.fileName : kind;
  return kind.isEmpty ? arch : '$arch · $kind';
}

/// What the sheet's buttons do (the app wires them to GetAppService; tests count them).
class GetAppActions {
  const GetAppActions({required this.onDownload, required this.onInstallWeb, required this.onCopyLink});

  final void Function(GetAppOs os, ReleaseFile file) onDownload;
  final VoidCallback onInstallWeb;
  final VoidCallback onCopyLink;
}

/// Opens the sheet over [context] (a context under the Navigator).
Future<void> showGetAppSheet(BuildContext context, {GetAppService? service}) {
  final s = service ?? GetAppService.instance;
  final offer = s.offer;
  if (offer != null && offer.kind != GetAppOfferKind.download) s.track(offer.os, 'install');
  return showAppSheet<void>(
    context,
    (ctx) => ListenableBuilder(
      listenable: s,
      builder: (ctx, _) => GetAppSheetBody(
        env: s.env,
        manifest: s.manifest,
        actions: GetAppActions(
          onDownload: (os, f) async {
            if (!await s.download(os, f)) showAppNotice('get_app_open_failed'.tr, error: true);
          },
          onInstallWeb: () async {
            final os = s.env.os;
            final r = await s.installWebApp(os);
            if (r == 'accepted') {
              showAppNotice('get_app_installed'.tr);
            } else if (r == 'unavailable') {
              showAppNotice('get_app_install_unavailable'.tr);
            }
          },
          onCopyLink: () => copyGetAppLink(s),
        ),
      ),
    ),
  );
}

/// Copies this page's address for "open in Safari".
Future<void> copyGetAppLink(GetAppService s) async {
  s.track(s.env.os, 'install');
  try {
    await Clipboard.setData(ClipboardData(text: s.pageUrl));
    showAppNotice('get_app_link_copied'.tr);
  } catch (_) {
    showAppNotice('get_app_open_failed'.tr, error: true);
  }
}

class GetAppSheetBody extends StatelessWidget {
  const GetAppSheetBody({super.key, required this.env, required this.manifest, required this.actions});

  final GetAppEnv env;
  final ReleasesManifest manifest;
  final GetAppActions actions;

  @override
  Widget build(BuildContext context) {
    final offer = getAppOfferFor(env, manifest);
    final here = releaseKeyFor(env.os);
    final others = [
      for (final k in kReleasePlatforms)
        if (k != (offer == null ? null : here) && manifest[k] != null) k,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetHeader('get_app_entry'.tr),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.md, AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('get_app_sheet_sub'.tr, style: _meta(context)),
                if (offer != null) ...[
                  const SizedBox(height: AppSpace.md),
                  _SectionLabel('get_app_this_device'.tr),
                  _DeviceCard(offer: offer, env: env, actions: actions),
                ],
                if (others.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.lg),
                  _SectionLabel(offer == null ? 'get_app_all_platforms'.tr : 'get_app_other_platforms'.tr),
                  for (final k in others) _PlatformRow(platformKey: k, release: manifest[k]!, actions: actions),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

TextStyle _meta(BuildContext context) => AppType.meta(context).copyWith(fontFamily: AppFonts.family, height: 1.4);

TextStyle _row(BuildContext context) => AppType.row(context).copyWith(fontFamily: AppFonts.family);

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Semantics(
          header: true,
          child: Text(text, style: AppType.bodyStrong(context)),
        ),
      );
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.offer, required this.env, required this.actions});

  final GetAppOffer offer;
  final GetAppEnv env;
  final GetAppActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = offer.release;
    final file = offer.file;
    final notes = r.notes(AppConfig.lang);
    return Container(
      padding: AppSpace.card,
      decoration: BoxDecoration(
        color: c.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            _IconWell(icon: getAppIcon(offer.os)),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(getAppOfferTitle(offer), style: _row(context).copyWith(fontWeight: FontWeight.w700)),
                Text(getAppOfferMeta(offer), style: _meta(context)),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.sm),
          ...switch (offer.kind) {
            GetAppOfferKind.download => [
                if (offer.os == GetAppOs.android) ...[
                  _Step(n: 1, icon: Icons.download_rounded, text: 'get_app_android_step1'.tr),
                  _Step(n: 2, icon: Icons.folder_open_rounded, text: 'get_app_android_step2'.tr),
                  _Step(n: 3, icon: Icons.verified_user_outlined, text: 'get_app_android_step3'.tr),
                ] else
                  _Hint(text: _desktopWarning(offer.os, file)),
                const SizedBox(height: AppSpace.sm),
                _Primary(
                  label: 'get_app_download'.tr,
                  icon: Icons.download_rounded,
                  onTap: () => actions.onDownload(offer.os, file!),
                ),
                if (offer.os == GetAppOs.android && r.files.length > 1)
                  _Hint(text: 'get_app_android_fail'.tr),
                if (r.minOs.isNotEmpty) _Hint(text: 'get_app_min_os'.tr.replaceAll('{os}', getAppLtr(r.minOs))),
                if (notes.isNotEmpty) _Hint(text: '${'get_app_whats_new'.tr}: $notes'),
                if (file?.sha256 != null) _Checksum(sha: file!.sha256!),
              ],
            GetAppOfferKind.installIos => [
                _Step(n: 1, icon: CupertinoIcons.share, text: 'get_app_ios_step1'.tr),
                _Step(n: 2, icon: CupertinoIcons.plus_app, text: 'get_app_ios_step2'.tr),
                _Step(n: 3, icon: Icons.check_circle_outline_rounded, text: 'get_app_ios_step3'.tr),
                _Hint(text: 'get_app_ios_note'.tr),
              ],
            GetAppOfferKind.openInSafari => [
                _Step(n: 1, icon: Icons.link_rounded, text: 'get_app_safari_step'.tr),
                const SizedBox(height: AppSpace.xs),
                _Primary(label: 'get_app_copy_link'.tr, icon: Icons.copy_rounded, onTap: actions.onCopyLink),
              ],
            GetAppOfferKind.installWeb => [
                if (env.pwaInstallable) ...[
                  _Hint(text: 'get_app_web_chromium'.tr),
                  const SizedBox(height: AppSpace.xs),
                  _Primary(label: 'get_app_install'.tr, icon: Icons.install_desktop_rounded, onTap: actions.onInstallWeb),
                ] else
                  _Step(n: 1, icon: Icons.ios_share_rounded, text: 'get_app_web_safari_mac'.tr),
              ],
          },
        ],
      ),
    );
  }
}

String _desktopWarning(GetAppOs os, ReleaseFile? f) => switch (os) {
      GetAppOs.windows => 'get_app_warn_windows'.tr,
      GetAppOs.macos => 'get_app_warn_macos'.tr,
      _ => 'get_app_warn_linux'.tr.replaceAll('{file}', f?.fileName ?? ''),
    };

class _PlatformRow extends StatelessWidget {
  const _PlatformRow({required this.platformKey, required this.release, required this.actions});

  final String platformKey;
  final PlatformRelease release;
  final GetAppActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final os = _osOfKey(platformKey);
    final r = release;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.xs, AppSpace.xs),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _IconWell(icon: getAppIcon(os), small: true),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('get_app_platform_$platformKey'.tr, style: _row(context).copyWith(fontWeight: FontWeight.w700)),
              if (r.hasFiles && r.version.isNotEmpty)
                Text('get_app_meta_version'.tr.replaceAll('{v}', getAppLtr(r.version)), style: _meta(context)),
            ]),
          ),
        ]),
        if (r.pwa && (r.pwaFirst || platformKey == 'ios'))
          _Hint(text: platformKey == 'ios' ? 'get_app_ios_other'.tr : 'get_app_web_other'.tr),
        for (final f in r.files)
          Row(children: [
            Expanded(
              child: Text(
                [getAppFileLabel(f), if (formatReleaseSize(f.size).isNotEmpty) getAppLtr(formatReleaseSize(f.size))].join(' · '),
                style: _meta(context),
              ),
            ),
            // a long label (large text, a translation) shortens instead of squeezing the file name
            Flexible(
              child: TextButton.icon(
                onPressed: () => actions.onDownload(os, f),
                style: TextButton.styleFrom(
                  minimumSize: const Size(AppTouch.min, AppTouch.min),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text('get_app_download'.tr,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppFonts.family)),
              ),
            ),
          ]),
        if (r.hasFiles && os != GetAppOs.android) _Hint(text: _desktopWarning(os, r.primaryFile())),
      ]),
    );
  }
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
        decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.chip)),
        child: Icon(icon, size: small ? 18 : 22, color: c.primary),
      ),
    );
  }
}

/// One numbered step with its icon: the small "illustration" of Share → Add to Home Screen.
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
            decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
            child: Text('$n',
                style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.onHero)),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: _row(context)))),
        const SizedBox(width: AppSpace.xs),
        ExcludeSemantics(child: Icon(icon, size: 22, color: c.primary)),
      ]),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(text, style: _meta(context)));
}

class _Primary extends StatelessWidget {
  const _Primary({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onHero,
        minimumSize: const Size.fromHeight(AppTouch.min),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
    );
  }
}

class _Checksum extends StatelessWidget {
  const _Checksum({required this.sha});

  final String sha;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('get_app_checksum'.tr, style: _meta(context).copyWith(fontWeight: FontWeight.w600)),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(sha, style: _meta(context).copyWith(fontSize: 11, letterSpacing: 0.2)),
          ),
        ]),
      );
}
