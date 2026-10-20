/// lib/core/offline/offline_shortcut_overlay.dart
///
/// A small floating pill ("Open downloads") that appears when the app goes
/// OFFLINE while it is being used. The user decides whether to open the
/// Downloads page — nothing navigates by itself any more (except the
/// offline cold start, see main.dart).
///
/// Visibility is decided by [TopRouteObserver.shortcutVisible]:
///   offline + something stored on the phone + not already on Downloads /
///   login / splash + not dismissed.
///
/// Used once in main.dart, inside MaterialApp.builder (keeps the same slot
/// whether the pill is visible or not, so the Navigator is never rebuilt).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/offline_strings.dart';
import 'package:flutter_education_app/utils/top_route_observer.dart';

class OfflineShortcutOverlay extends StatelessWidget {
  const OfflineShortcutOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        ValueListenableBuilder<bool>(
          valueListenable: topRouteObserver.shortcutVisible,
          builder: (context, visible, _) => _ShortcutPill(visible: visible),
        ),
      ],
    );
  }
}

class _ShortcutPill extends StatelessWidget {
  const _ShortcutPill({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return PositionedDirectional(
      end: 14,
      // above the bottom navigation bar
      bottom: bottomInset + 92,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.6),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: Directionality(
              textDirection: pageDirection,
              child: Material(
                color: c.primary,
                elevation: 6,
                shadowColor: c.primary.withValues(alpha: 0.5),
                shape: const StadiumBorder(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: topRouteObserver.openDownloads,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 12,
                          end: 6,
                          top: 8,
                          bottom: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.download_for_offline_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              offlineT('dl_open_downloads'),
                              style: const TextStyle(
                                fontFamily: 'tajawal',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // small "x": hide it until the next connection change
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: topRouteObserver.dismissShortcut,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 2,
                          end: 8,
                          top: 8,
                          bottom: 8,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
