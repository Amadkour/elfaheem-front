// lib/utils/widget/paged_progress.dart
//
// Shared "premium" pagination widgets, used by every infinite-scroll list
// (admin view-as, admin features, courses …) so they all look and behave the same:
//   • PagedCountCard  — pinned above the list: "Showing 40 of 134" + animated progress bar
//   • PagedListFooter — last row of the list: "Loading more…" / "All loaded"
library;

import 'package:flutter/material.dart';
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
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 8),
  });

  final int loaded;
  final int total;
  final bool loadingMore;

  /// Everything is loaded (no more pages).
  final bool done;
  final IconData icon;
  final EdgeInsetsGeometry margin;

  static String _label(int loaded, int total) => 'admin_showing_count'.tr
      .replaceAll('{loaded}', '$loaded')
      .replaceAll('{total}', '$total');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = total <= 0 ? 1.0 : (loaded / total).clamp(0.0, 1.0);
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.primary.withValues(alpha: 0.22)),
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [
            c.primary.withValues(alpha: 0.12),
            c.primary.withValues(alpha: 0.03),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: c.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(end: loaded.toDouble()),
                  duration: const Duration(milliseconds: 350),
                  builder: (_, v, _) => Text(
                    _label(v.round(), total),
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: c.textDark,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: progress),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      backgroundColor: c.primary.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(
                        done ? c.success : c.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 22,
            height: 22,
            child: loadingMore
                ? CircularProgressIndicator(strokeWidth: 2.4, color: c.primary)
                : done
                ? Icon(Icons.check_circle_rounded, color: c.success, size: 22)
                : Icon(
                    Icons.keyboard_double_arrow_down_rounded,
                    color: c.textLight,
                    size: 22,
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
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: loadingMore
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'admin_loading_more'.tr,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12.5,
                      color: c.textMedium,
                    ),
                  ),
                ],
              )
            : hasMore
            ? const SizedBox(height: 16)
            : Text(
                'admin_all_loaded'.tr,
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 12,
                  color: c.textLight,
                ),
              ),
      ),
    );
  }
}
