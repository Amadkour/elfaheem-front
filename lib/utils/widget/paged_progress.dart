// lib/utils/widget/paged_progress.dart
//
// Shared "premium" pagination widgets, used by every infinite-scroll list
// (admin view-as, admin features, courses …) so they all look and behave the same:
//   • PagedCountCard  — pinned above the list: "Showing 40 of 134" + animated progress bar
//   • PagedListFooter — last row of the list: "Loading more…" / "All loaded"
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

/// "Showing {loaded} of {total}" with a progress bar that animates as pages are appended.
class PagedCountCard extends StatelessWidget {
  const PagedCountCard({
    super.key,
    required this.loaded,
    required this.total,
    required this.loadingMore,
    required this.done,
    this.icon = Icons.groups_rounded,
    this.margin = const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
  });

  final int loaded;
  final int total;
  final bool loadingMore;

  /// Everything is loaded (no more pages).
  final bool done;
  final IconData icon;
  final EdgeInsetsGeometry margin;

  /// The progress bar's thickness.
  static const double _bar = 6;

  static String _label(int loaded, int total) => 'admin_showing_count'.tr
      .replaceAll('{loaded}', '$loaded')
      .replaceAll('{total}', '$total');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = total <= 0 ? 1.0 : (loaded / total).clamp(0.0, 1.0);
    return Container(
      margin: margin,
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.md, AppSpace.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
        color: c.cardBg,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpace.xs),
            decoration: BoxDecoration(
              color: c.inputBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: AppIconSize.md, color: c.textMedium),
          ),
          AppSpace.gapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(end: loaded.toDouble()),
                  duration: AppMotion.of(context).slow,
                  builder: (_, v, _) => Text(
                    _label(v.round(), total),
                    style: AppType.bodyStrong(context).copyWith(
                      color: c.textDark,
                    ),
                  ),
                ),
                AppSpace.gapXs,
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: progress),
                    duration: AppMotion.of(context).slow,
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: _bar,
                      backgroundColor: c.inputBg,
                      valueColor: AlwaysStoppedAnimation(
                        done ? c.success : c.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AppSpace.gapSm,
          SizedBox(
            width: AppIconSize.md,
            height: AppIconSize.md,
            child: loadingMore
                ? CircularProgressIndicator(strokeWidth: AppBorder.focus, color: c.primary)
                : done
                ? Icon(Icons.check_circle_rounded, color: c.success, size: AppIconSize.md)
                : Icon(
                    Icons.keyboard_double_arrow_down_rounded,
                    color: c.textLight,
                    size: AppIconSize.md,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Last row of an infinite list.
class PagedListFooter extends StatelessWidget {
  const PagedListFooter({
    super.key,
    required this.loadingMore,
    required this.hasMore,
  });

  final bool loadingMore;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      child: Center(
        child: loadingMore
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: AppIconSize.sm,
                    height: AppIconSize.sm,
                    child: CircularProgressIndicator(
                      strokeWidth: AppBorder.focus,
                      color: c.primary,
                    ),
                  ),
                  AppSpace.gapXs,
                  Flexible(
                    child: Text(
                      'admin_loading_more'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta(context).copyWith(
                        color: c.textMedium,
                      ),
                    ),
                  ),
                ],
              )
            : hasMore
            ? const SizedBox(height: AppSpace.md)
            : Text(
                'admin_all_loaded'.tr,
                style: AppType.meta(context).copyWith(
                  color: c.textLight,
                ),
              ),
      ),
    );
  }
}
