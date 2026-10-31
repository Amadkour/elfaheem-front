// lib/features/shared/get_app/get_app_banner.dart — "Get the app", on the WEB build only:
//
//   GetAppBanner(child:)   in MaterialApp.builder (main.dart): a calm strip above the role homes with ONE button to
//                          the right store / installer and a close button (hidden for 21 days on this browser).
//                          Never on sign-in, a pushed page (player, exam, course), a dialog, the live room, guest or
//                          view-as mode; nothing at all in the native app, an installed PWA or an in-app browser.
//   GetAppBannerView       the strip over plain values (what test/ui/get_app_test.dart lays out).
//   GetAppTile             the settings row that stays after a dismissal (hidden when this device has no link).
//
// State, links and rules: lib/core/get_app/ (links in web/app_links.json).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/display/app_fonts.dart';
import '../../../core/get_app/get_app_service.dart';
import '../../../design/app_notice.dart';
import '../../../design/app_settings.dart';
import '../../../design/app_tokens.dart';
import '../../../utils/top_route_observer.dart';
import '../../../utils/widget/view_as_state.dart';
import '../guest/guest_state.dart';
import '../live/live_room_host.dart' show LiveRoomHost;

/// "Get the Android app", "Get the iPad app", …
String getAppTitle(GetAppOs os) => 'get_app_title_${os.name}'.tr;

/// The button: the store's name on phones and tablets, "Download" for a desktop installer.
String getAppButtonLabel(GetAppOs os) => switch (os) {
      GetAppOs.android => 'get_app_google_play'.tr,
      GetAppOs.ios || GetAppOs.ipados => 'get_app_app_store'.tr,
      _ => 'get_app_download'.tr,
    };

IconData getAppIcon(GetAppOs os) => switch (os) {
      GetAppOs.android => Icons.phone_android_rounded,
      GetAppOs.ios => Icons.phone_iphone_rounded,
      GetAppOs.ipados => Icons.tablet_mac_rounded,
      GetAppOs.windows => Icons.desktop_windows_rounded,
      GetAppOs.macos => Icons.laptop_mac_rounded,
      _ => Icons.computer_rounded,
    };

Future<void> _openStore(GetAppService s) async {
  if (!await s.open()) showAppNotice('get_app_open_failed'.tr, error: true);
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

  bool get _visible =>
      _routeOk && _s.bannerEligible && !LiveRoomHost.isOpen && !GuestState.active && !ViewAsState.active;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    final visible = _visible;
    final motion = AppMotion.of(context);
    return Column(
      children: [
        AnimatedSize(
          duration: motion.base,
          curve: AppMotion.curve,
          alignment: AlignmentDirectional.topCenter,
          child: visible
              ? GetAppBannerView(
                  os: _s.env.os,
                  onOpen: () => _openStore(_s),
                  onDismiss: _s.dismiss,
                )
              : const SizedBox(width: double.infinity),
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
  const GetAppBannerView({super.key, required this.os, required this.onOpen, required this.onDismiss});

  final GetAppOs os;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

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
              // a phone keeps the title only (icon well from ~380 px); a wide window adds the line below it and keeps
              // the button next to the text, the close button at the far end
              final tight = box.maxWidth < 380;
              final wide = box.maxWidth >= 600;
              return Padding(
                padding: EdgeInsetsDirectional.only(
                  start: tight ? AppSpace.sm : AppSpace.md,
                  end: AppSpace.xxs,
                  top: AppSpace.xxs,
                  bottom: AppSpace.xxs,
                ),
                child: Row(
                  children: [
                    // icon, text and the store button stay together; the close button sits at the far end
                    Expanded(
                      child: Row(
                        children: [
                          if (!tight) ...[
                            ExcludeSemantics(
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
                                child: Icon(getAppIcon(os), size: 20, color: c.primary),
                              ),
                            ),
                            const SizedBox(width: AppSpace.sm),
                          ],
                          Flexible(
                            fit: wide ? FlexFit.loose : FlexFit.tight,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  getAppTitle(os),
                                  maxLines: tight ? 2 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.row(context).copyWith(fontFamily: AppFonts.family, fontSize: 13.5),
                                ),
                                if (wide)
                                  Text(
                                    'get_app_banner_body'.tr,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppType.meta(context).copyWith(fontFamily: AppFonts.family, fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(width: wide ? AppSpace.md : AppSpace.xs),
                          // a long label (large text, a translation) shortens instead of pushing the title out
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.42),
                            child: FilledButton(
                              onPressed: onOpen,
                              style: FilledButton.styleFrom(
                                backgroundColor: c.primary,
                                foregroundColor: c.onHero,
                                minimumSize: const Size(64, 36),
                                tapTargetSize: MaterialTapTargetSize.padded,
                                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                                shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
                              ),
                              child: Text(
                                getAppButtonLabel(os),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ),
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

/// "Get the app" in a More / profile list. Add it as `if (GetAppTile.available) const GetAppTile()` so a device
/// without a link leaves no empty row (and no extra divider) in the group.
class GetAppTile extends StatelessWidget implements AppSettingsSearchable {
  const GetAppTile({super.key, this.color});

  final Color? color;

  /// Web, a real browser tab, and a link for this device (the links load at start-up, with the banner).
  static bool get available => kIsWeb && GetAppService.instance.entryAvailable;

  @override
  String get searchText => '${'get_app_entry'.tr} app download install store تطبيق تنزيل تثبيت متجر';

  @override
  Widget build(BuildContext context) {
    final s = GetAppService.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (!kIsWeb || !s.entryAvailable) return const SizedBox.shrink();
        return AppSettingsTile(
          icon: getAppIcon(s.env.os),
          color: color ?? context.colors.primary,
          label: 'get_app_entry'.tr,
          subtitle: getAppTitle(s.env.os),
          keywords: 'app download install store play تطبيق تنزيل تثبيت متجر',
          onTap: () => _openStore(s),
        );
      },
    );
  }
}
