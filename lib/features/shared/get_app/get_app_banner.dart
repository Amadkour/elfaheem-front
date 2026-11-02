// lib/features/shared/get_app/get_app_banner.dart — "Get the app", on the WEB build only:
//
//   GetAppBanner(child:)   in MaterialApp.builder (main.dart): a calm strip above the role homes with ONE button for
//                          this device (download the APK / desktop package, "How to install" on iPhone, "Copy link"
//                          in an app's own browser, "Install" the web app on a computer), "All platforms" opening the
//                          sheet, and a close button (hidden for 14 days on this browser). Never on sign-in, a pushed
//                          page (player, exam, course), a dialog, the live room, guest or view-as mode; nothing in
//                          the native app, an installed web app or a wrapper. In the installed iPhone web app it
//                          offers "Turn on notifications" instead (iOS asks only after a tap).
//   GetAppBannerView       the strip over plain values (what test/ui/get_app_test.dart lays out).
//   GetAppTile             the settings row that stays after a dismissal (opens the sheet, every platform).
//
// Everything comes from the releases manifest (lib/core/get_app/); the sheet is get_app_sheet.dart. Kill switches:
// get_app.banner, get_app.entry.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import '../../../core/display/app_fonts.dart';
import '../../../core/get_app/get_app_service.dart';
import '../../../core/release/app_downloads.dart' show AppDownloadsService;
import '../../../design/app_notice.dart';
import '../../../design/app_settings.dart';
import '../../../design/app_tokens.dart';
import '../../../main.dart' show navigatorKey;
import '../../../utils/top_route_observer.dart';
import '../../../utils/widget/view_as_state.dart';
import '../guest/guest_state.dart';
import '../live/live_room_host.dart' show LiveRoomHost;
import '../notification/notification_service.dart';
import 'get_app_sheet.dart';

export 'get_app_sheet.dart' show showGetAppSheet, getAppIcon;

void _openSheet(GetAppService s) {
  final ctx = navigatorKey.currentContext;
  if (ctx != null) showGetAppSheet(ctx, service: s);
}

/// The banner's button for [offer].
Future<void> runGetAppOffer(GetAppService s, GetAppOffer offer) async {
  switch (offer.kind) {
    case GetAppOfferKind.download:
      if (!await s.download(offer.os, offer.file!)) showAppNotice('get_app_open_failed'.tr, error: true);
    case GetAppOfferKind.openInSafari:
      await copyGetAppLink(s);
    case GetAppOfferKind.installWeb when s.env.pwaInstallable:
      final r = await s.installWebApp(offer.os);
      if (r == 'accepted') {
        showAppNotice('get_app_installed'.tr);
      } else if (r == 'unavailable') {
        _openSheet(s);
      }
    case GetAppOfferKind.installIos || GetAppOfferKind.installWeb:
      _openSheet(s);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Host
// ─────────────────────────────────────────────────────────────────────────────

class GetAppBanner extends StatefulWidget {
  const GetAppBanner({super.key, required this.child, this.service});

  final Widget child;

  /// Tests pass their own; the app uses [GetAppService.instance].
  final GetAppService? service;

  @override
  State<GetAppBanner> createState() => _GetAppBannerState();
}

class _GetAppBannerState extends State<GetAppBanner> {
  GetAppService get _s => widget.service ?? GetAppService.instance;

  /// The last page decision; a dialog / sheet on top keeps it, so the page below does not jump.
  bool _routeOk = false;

  late final Listenable _deps = Listenable.merge([
    _s,
    topRouteObserver.topRoute,
    LiveRoomHost.listenable,
    GuestState.instance,
    ViewAsState.instance,
    AppConfig.disableListVersion,
    AppDownloadsService.instance,
  ]);

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    _s.init();
    _readRoute();
    _deps.addListener(_changed);
  }

  @override
  void dispose() {
    if (kIsWeb) _deps.removeListener(_changed);
    super.dispose();
  }

  void _readRoute() {
    final r = topRouteObserver.topRoute.value;
    if (r == null) {
      _routeOk = false;
    } else if (r is PageRoute) {
      _routeOk = routeAllowsGetAppBanner(r.settings.name);
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(_readRoute);
  }

  bool get _pageOk => _routeOk && !LiveRoomHost.isOpen && !GuestState.active && !ViewAsState.active;

  /// Straight from the tap: iOS shows its permission prompt only inside the gesture, so nothing is awaited first.
  void _turnOnPush() {
    final asked = _s.requestNotifications();
    asked.then((r) async {
      if (r == 'granted') {
        await NotificationService.instance.registerWithBackend(ApiClient.instance);
        await _s.dismissPush();
      } else if (r == 'denied') {
        showAppNotice('get_app_push_denied'.tr);
        await _s.dismissPush();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    final pageOk = _pageOk;
    // D-144: while the website channel publishes downloads, its strip (AppDownloadBanner) is the one offer
    final offer = pageOk && _s.bannerEligible && !AppDownloadsService.instance.hasDownloads ? _s.offer : null;
    final push = pageOk && offer == null && _s.pushPromptEligible;
    final Widget strip;
    if (offer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _s.trackView(offer.os));
      strip = GetAppBannerView(
        key: ValueKey('get_app_${offer.kind.name}'),
        icon: getAppIcon(offer.os),
        title: getAppOfferTitle(offer),
        meta: getAppOfferMeta(offer),
        actionLabel: getAppOfferAction(offer, canPrompt: _s.env.pwaInstallable),
        onAction: () => runGetAppOffer(_s, offer),
        detailsLabel: 'get_app_all_platforms'.tr,
        onDetails: () => _openSheet(_s),
        onDismiss: _s.dismiss,
      );
    } else if (push) {
      strip = GetAppBannerView(
        key: const ValueKey('get_app_push'),
        icon: Icons.notifications_active_outlined,
        title: 'get_app_push_title'.tr,
        meta: 'get_app_push_body'.tr,
        actionLabel: 'get_app_push_button'.tr,
        onAction: _turnOnPush,
        onDismiss: _s.dismissPush,
      );
    } else {
      strip = const SizedBox(width: double.infinity);
    }
    final visible = offer != null || push;
    final motion = AppMotion.of(context);
    return Column(
      children: [
        AnimatedSize(
          duration: motion.base,
          curve: AppMotion.curve,
          alignment: AlignmentDirectional.topCenter,
          child: strip,
        ),
        // Keyed so the Navigator keeps its state when the strip comes and goes.
        Expanded(
          key: const ValueKey('app_content_get_app'),
          child: MediaQuery.removePadding(context: context, removeTop: visible, child: widget.child),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The strip (plain values)
// ─────────────────────────────────────────────────────────────────────────────

class GetAppBannerView extends StatelessWidget {
  const GetAppBannerView({
    super.key,
    required this.icon,
    required this.title,
    required this.meta,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
    this.detailsLabel,
    this.onDetails,
  });

  final IconData icon;
  final String title;

  /// "Version 1.0.0 · 48.7 MB", or a one-line promise.
  final String meta;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  /// "All platforms" (wide windows show it as a link; on a phone the text block opens the same sheet).
  final String? detailsLabel;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'get_app_banner_label'.tr,
      child: Material(
        color: c.cardBg,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider))),
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(builder: (context, box) {
              // a phone keeps icon (from ~380 px), title + meta, the button and close; a wide window adds the
              // "All platforms" link next to the button
              final tight = box.maxWidth < 380;
              final wide = box.maxWidth >= 600;
              final text = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.row(context).copyWith(fontFamily: AppFonts.family, fontSize: 13.5),
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta(context).copyWith(fontFamily: AppFonts.family, fontSize: 12),
                    ),
                ],
              );
              return Padding(
                padding: EdgeInsetsDirectional.only(
                  start: tight ? AppSpace.sm : AppSpace.md,
                  end: AppSpace.xxs,
                  top: AppSpace.xxs,
                  bottom: AppSpace.xxs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (!tight) ...[
                            ExcludeSemantics(
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
                                child: Icon(icon, size: 20, color: c.primary),
                              ),
                            ),
                            const SizedBox(width: AppSpace.sm),
                          ],
                          Flexible(
                            fit: wide ? FlexFit.loose : FlexFit.tight,
                            // on a phone the text opens the sheet too (no room for a second link)
                            child: onDetails != null && !wide
                                ? Semantics(
                                    button: true,
                                    hint: detailsLabel,
                                    child: InkWell(onTap: onDetails, borderRadius: AppRadius.chipAll, child: text),
                                  )
                                : text,
                          ),
                          SizedBox(width: wide ? AppSpace.md : AppSpace.xs),
                          // a long label (large text, a translation) shortens instead of pushing the title out
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.36),
                            child: FilledButton(
                              onPressed: onAction,
                              style: FilledButton.styleFrom(
                                backgroundColor: c.primary,
                                foregroundColor: c.onHero,
                                minimumSize: const Size(64, 36),
                                tapTargetSize: MaterialTapTargetSize.padded,
                                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                                shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
                              ),
                              child: Text(
                                actionLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ),
                          if (wide && onDetails != null && detailsLabel != null) ...[
                            const SizedBox(width: AppSpace.xxs),
                            TextButton(
                              onPressed: onDetails,
                              style: TextButton.styleFrom(
                                foregroundColor: c.primary,
                                minimumSize: const Size(48, 48),
                                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                              ),
                              child: Text(
                                detailsLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // no Tooltip: the strip sits above the Navigator, where there is no Overlay to draw one
                    Semantics(
                      button: true,
                      label: 'get_app_dismiss'.tr,
                      excludeSemantics: true,
                      child: InkResponse(
                        onTap: onDismiss,
                        radius: 22,
                        child: SizedBox(
                          width: AppTouch.min,
                          height: AppTouch.min,
                          child: Icon(Icons.close_rounded, size: 20, color: c.textMedium),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings row
// ─────────────────────────────────────────────────────────────────────────────

/// "Get the app" in a More / profile list: opens the sheet with every platform. Add it as
/// `if (GetAppTile.available) const GetAppTile()` so a browser with nothing to offer leaves no empty row.
class GetAppTile extends StatelessWidget implements AppSettingsSearchable {
  const GetAppTile({super.key, this.color});

  final Color? color;

  /// Web, a real browser tab, something published (the manifest loads at start-up, with the banner).
  static bool get available => kIsWeb && GetAppService.instance.entryAvailable;

  @override
  String get searchText => '${'get_app_entry'.tr} app download install apk تطبيق تنزيل تثبيت';

  @override
  Widget build(BuildContext context) {
    final s = GetAppService.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (!kIsWeb || !s.entryAvailable) return const SizedBox.shrink();
        final offer = s.offer;
        return AppSettingsTile(
          icon: offer == null ? Icons.install_mobile_rounded : getAppIcon(offer.os),
          color: color ?? context.colors.primary,
          label: 'get_app_entry'.tr,
          subtitle: offer == null ? 'get_app_sheet_sub'.tr : getAppOfferTitle(offer),
          keywords: 'app download install apk تطبيق تنزيل تثبيت',
          onTap: () => showGetAppSheet(context, service: s),
        );
      },
    );
  }
}
