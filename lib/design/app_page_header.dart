// lib/design/app_page_header.dart
//
// THE page header of the dashboards (the role-neutral sibling of the organization dashboard's OrgPageHeader), and the
// section heading under it.
//
//   AppPageHeader(
//     title: 'Students', subtitle: 'All departments', icon: Icons.people_alt_rounded,
//     primaryAction: FilledButton(…),            the page's ONE primary action, always visible
//     actions: [IconButton(…), …],               secondary actions: icon buttons; on phones they move into a ⋯ sheet
//     search: AppSearchField(…),                 own row under the title
//     breadcrumbs: ['Org', 'Students'],  onBack: …,  updatedAt: …,  onRefresh: …,
//     bottom: AppTabs(…),                        tabs under everything
//   )
//   AppSection(title: 'Recent activity', trailing: TextButton(…), child: …)
//
// Surface (card colour) with the brand accent strip on top. The title wraps to two lines and ellipsises; nothing
// overflows at 320 px or text scale 1.3. "Updated 3 min ago" re-draws once a minute while shown.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';

import 'app_gradients.dart';
import 'app_kit.dart';
import 'app_tokens.dart';

/// "Updated just now" / "Updated 3 min ago" / "Updated 2 h ago" / "Updated 12 Oct 2026 · 09:30".
String appUpdatedText(DateTime at, DateTime now) {
  final d = now.difference(at);
  final m = d.inMinutes;
  final head = 'ds_updated'.tr;
  final ar = AppConfig.lang == 'ar';
  if (m < 1) return ar ? '$head · الآن' : '$head just now';
  if (m < 60) {
    final n = countText(m, ar1: 'منذ دقيقة', ar2: 'منذ دقيقتين', arFew: 'منذ {n} دقائق', arMany: 'منذ {n} دقيقة', en1: '1 min ago', en: '{n} min ago');
    return ar ? '$head · $n' : '$head $n';
  }
  final h = d.inHours;
  if (h < 24) {
    final n = countText(h, ar1: 'منذ ساعة', ar2: 'منذ ساعتين', arFew: 'منذ {n} ساعات', arMany: 'منذ {n} ساعة', en1: '1 h ago', en: '{n} h ago');
    return ar ? '$head · $n' : '$head $n';
  }
  return '$head · ${AppTime.dateTime(at.toUtc())}';
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.primaryAction,
    this.actions = const [],
    this.search,
    this.breadcrumbs,
    this.onBack,
    this.updatedAt,
    this.onRefresh,
    this.bottom,
    this.accent = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// The page's ONE primary action; stays visible on phones.
  final Widget? primaryAction;

  /// Secondary actions (icon buttons); on phones they open from a ⋯ button.
  final List<Widget> actions;

  /// Own row under the title.
  final Widget? search;
  final List<String>? breadcrumbs;

  /// A Back button leads the header (the arrow mirrors in Arabic by itself).
  final VoidCallback? onBack;

  /// Shows "Updated 3 min ago" under the title.
  final DateTime? updatedAt;

  /// Shows the refresh icon button.
  final VoidCallback? onRefresh;

  /// Tabs / filters under the header's content.
  final Widget? bottom;

  /// The brand strip on top.
  final bool accent;

  /// From this width the actions share the title's row.
  static const double wideFrom = 640;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(bottom: BorderSide(color: c.divider, width: AppBorder.hairline)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (accent) const AppAccentStrip(),
        LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= wideFrom;
          return Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (breadcrumbs != null && breadcrumbs!.isNotEmpty) ...[
                _Crumbs(breadcrumbs!),
                const SizedBox(height: AppSpace.xxs),
              ],
              _titleRow(context, wide),
              if (!wide && primaryAction != null) ...[
                AppSpace.gapXs,
                Align(alignment: AlignmentDirectional.centerEnd, child: primaryAction!),
              ],
              if (search != null) ...[AppSpace.gapSm, search!],
              if (bottom != null) ...[AppSpace.gapXs, bottom!],
            ]),
          );
        }),
      ]),
    );
  }

  Widget _titleRow(BuildContext context, bool wide) {
    final c = context.colors;
    final refresh = onRefresh == null
        ? null
        : IconButton(
            tooltip: 'refresh'.tr,
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            onPressed: onRefresh,
            icon: Icon(Icons.refresh_rounded, size: AppIconSize.lg, color: c.textMedium),
          );
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (onBack != null) ...[
        IconButton(
          tooltip: 'ds_back'.tr,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          onPressed: onBack,
          icon: Icon(Icons.arrow_back_rounded, size: AppIconSize.lg, color: c.textDark),
        ),
        const SizedBox(width: AppSpace.xxs),
      ],
      if (icon != null) ...[
        Container(
          width: AppTouch.min - AppSpace.xs,
          height: AppTouch.min - AppSpace.xs,
          decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: Icon(icon, size: AppIconSize.lg, color: c.primary),
        ),
        AppSpace.gapSm,
      ],
      Expanded(child: _titleBlock(context)),
      if (wide) ...[
        AppSpace.gapSm,
        ?refresh,
        ...actions,
        if (primaryAction != null) ...[AppSpace.gapXs, primaryAction!],
      ] else ...[
        ?refresh,
        if (actions.isNotEmpty) _MoreButton(actions: actions),
      ],
    ]);
  }

  Widget _titleBlock(BuildContext context) {
    final sub = subtitle;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        header: true,
        child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
      ),
      if (sub != null && sub.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
      ],
      if (updatedAt != null) ...[
        const SizedBox(height: AppSpace.xxs),
        _UpdatedText(at: updatedAt!),
      ],
    ]);
  }
}

class _Crumbs extends StatelessWidget {
  const _Crumbs(this.items);
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) Icon(Icons.chevron_right_rounded, size: AppIconSize.sm, color: c.textLight),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            items[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta(context).copyWith(
              color: i == items.length - 1 ? c.textDark : c.textMedium,
              fontWeight: i == items.length - 1 ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ],
    ]);
  }
}

/// The ⋯ button of phones: the secondary actions in a sheet.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.actions});
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'ds_more_actions'.tr,
        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
        onPressed: () => showAppSheet<void>(
          context,
          (ctx) => AppSheetContent(title: 'ds_more_actions'.tr, children: [
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: actions),
          ]),
        ),
        icon: Icon(Icons.more_horiz_rounded, size: AppIconSize.lg, color: context.colors.textMedium),
      );
}

/// "Updated 2 min ago", re-drawn once a minute (only this text).
class _UpdatedText extends StatefulWidget {
  const _UpdatedText({required this.at});
  final DateTime at;

  @override
  State<_UpdatedText> createState() => _UpdatedTextState();
}

class _UpdatedTextState extends State<_UpdatedText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        appUpdatedText(widget.at, DateTime.now()),
        key: const ValueKey('app.header.updated'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.meta(context),
      );
}

/// A section heading with its body: title (+ subtitle) on the start side, an optional trailing widget (a "See all"
/// link, a filter) on the end, the [child] under it with the section rhythm.
class AppSection extends StatelessWidget {
  const AppSection({super.key, required this.title, this.subtitle, this.trailing, required this.child});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Semantics(
              header: true,
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            ),
            if (sub != null && sub.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ],
          ]),
        ),
        if (trailing != null) ...[AppSpace.gapSm, trailing!],
      ]),
      AppSpace.gapSm,
      child,
    ]);
  }
}
