// lib/design/app_pagination.dart
//
// Pagination bar for server-paged lists: previous / next, compact numbered pages with ellipses on wide widths,
// "Page x of y" on phones, an optional rows-per-page dropdown and a "1-20 of 345" summary. Controlled: the page owns
// [page] (1-based); every tap calls [onPage]. Chevrons mirror in Arabic by themselves, so they are never picked by
// language. Never overflows: the parts wrap and the controls scale down.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';

import 'app_bidi.dart';
import 'app_gradients.dart';
import 'app_kit.dart' show AppDropdown;
import 'app_responsive.dart';
import 'app_tokens.dart';

class AppPagination extends StatelessWidget {
  const AppPagination({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onPage,
    this.total,
    this.pageSize,
    this.pageSizes,
    this.onPageSize,
  });

  /// The current page, 1-based.
  final int page;
  final int pageCount;
  final ValueChanged<int> onPage;

  /// All rows on the server; with [pageSize] it gives the "1-20 of 345" summary.
  final int? total;
  final int? pageSize;
  final List<int>? pageSizes;
  final ValueChanged<int>? onPageSize;

  /// The page numbers to draw, with null for an ellipsis: 1 … 4 5 [6] 7 8 … 20.
  static List<int?> windowOf(int page, int count, {int siblings = 1}) {
    if (count <= 0) return const [];
    final keep = <int>{1, count, for (var i = page - siblings; i <= page + siblings; i++) i}
        .where((p) => p >= 1 && p <= count)
        .toList()
      ..sort();
    final out = <int?>[];
    for (var i = 0; i < keep.length; i++) {
      if (i > 0) {
        final gap = keep[i] - keep[i - 1];
        if (gap == 2) {
          out.add(keep[i] - 1);
        } else if (gap > 2) {
          out.add(null);
        }
      }
      out.add(keep[i]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final count = pageCount < 1 ? 1 : pageCount;
    final cur = page.clamp(1, count);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= Breakpoints.mobile;
      final summary = _summary(cur);
      final sizes = (pageSizes != null && pageSizes!.isNotEmpty && onPageSize != null) ? pageSizes! : null;
      final maxW = box.maxWidth.isFinite ? box.maxWidth - AppSpace.md : double.infinity;

      final nav = Row(mainAxisSize: MainAxisSize.min, children: [
        _NavButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'ds_prev_page'.tr,
          onTap: cur > 1 ? () => onPage(cur - 1) : null,
        ),
        if (wide)
          for (final p in windowOf(cur, count))
            p == null
                ? SizedBox(
                    width: AppSpace.lg, child: Text('…', textAlign: TextAlign.center, style: AppType.body(context)))
                : _PageButton(number: p, selected: p == cur, onTap: () => onPage(p))
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            child: Text('${'ds_page'.tr} $cur ${'ds_of'.tr} $count', style: AppType.row(context)),
          ),
        _NavButton(
          icon: Icons.chevron_right_rounded,
          tooltip: 'ds_next_page'.tr,
          onTap: cur < count ? () => onPage(cur + 1) : null,
        ),
      ]);

      final info = <Widget>[
        if (summary != null) Text(summary, style: AppType.meta(context)),
        if (sizes != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text('ds_rows_per_page'.tr, style: AppType.meta(context), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: AppSpace.xs),
            SizedBox(
              width: 104,
              child: AppDropdown<int>(
                value: sizes.contains(pageSize) ? pageSize : null,
                items: [for (final s in sizes) DropdownMenuItem(value: s, child: Text('$s'))],
                onChanged: (v) {
                  if (v != null) onPageSize!(v);
                },
              ),
            ),
          ]),
      ];

      return Semantics(
        container: true,
        label: ar ? 'ترقيم الصفحات' : 'Pagination',
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.md,
              runSpacing: AppSpace.xs,
              children: [
                if (info.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW),
                    child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpace.md,
                        runSpacing: AppSpace.xxs,
                        children: info),
                  ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: FittedBox(fit: BoxFit.scaleDown, child: nav),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  String? _summary(int cur) {
    final t = total;
    final s = pageSize;
    if (t == null) return null;
    if (t == 0) return '0';
    if (s == null) {
      return countText(t,
          ar1: 'عنصر واحد', ar2: 'عنصران', arFew: '$t عناصر', arMany: '$t عنصرًا', en1: '1 item', en: '$t items');
    }
    final from = (cur - 1) * s + 1;
    final to = (cur * s) > t ? t : cur * s;
    return '${ltrIsolate('$from–$to')} ${'ds_of'.tr} $t';
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
      onPressed: onTap,
      // chevron_left / right mirror in RTL by themselves
      icon: Icon(icon, size: AppIconSize.lg, color: onTap == null ? c.textLight : c.textDark),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({required this.number, required this.selected, required this.onTap});
  final int number;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: '${'ds_page'.tr} $number',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.chipAll,
        onTap: selected ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          alignment: Alignment.center,
          child: Container(
            constraints: const BoxConstraints(minWidth: AppTouch.min - AppSpace.sm, minHeight: AppTouch.min - AppSpace.sm),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: selected ? AppGradients.brand(context) : null,
              borderRadius: AppRadius.chipAll,
            ),
            child: Text('$number', style: AppType.row(context).copyWith(color: selected ? c.onHero : c.textDark)),
          ),
        ),
      ),
    );
  }
}
