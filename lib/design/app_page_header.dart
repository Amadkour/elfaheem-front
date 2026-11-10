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
// The organic gradient (D-360), collapsing with the page's scroll; search and tabs sit on the card surface under it. The title wraps to two lines and ellipsises; nothing
// overflows at 320 px or text scale 1.3. "Updated 3 min ago" re-draws once a minute while shown.
library;

import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';

import 'app_kit.dart';
import 'app_responsive.dart' show Breakpoints;
import 'app_shell_nav.dart' show ShellChrome;
import 'app_tokens.dart';
import 'chrome_button.dart' show ChromeBar;

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

  /// Kept for existing callers: the whole header is the gradient now (D-360).
  final bool accent;

  /// From this width the actions share the title's row.
  static const double wideFrom = 640;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final folded = ShellChrome.ownsHeaderOf(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= wideFrom;
      const inset = EdgeInsets.symmetric(horizontal: AppSpace.md);
      final hasCrumbs = breadcrumbs != null && breadcrumbs!.isNotEmpty;
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (folded)
          ?_foldedRow(context)
        else
          AppHeaderCollapse(
          builder: (context, collapse, _) => RepaintBoundary(
            child: AppMeshSurface(
              drift: collapse,
              child: AnimatedBuilder(
                animation: collapse,
                builder: (context, _) {
                  final t = collapse.value;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(AppSpace.md, lerpDouble(AppSpace.md, AppSpace.xxs, t)!, AppSpace.md, lerpDouble(AppSpace.md, AppSpace.xxs, t)!),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (hasCrumbs && t < 1)
                        ClipRect(
                          child: Align(
                            alignment: AlignmentDirectional.topStart,
                            heightFactor: 1 - t,
                            child: Opacity(
                              opacity: 1 - t,
                              child: Padding(padding: const EdgeInsets.only(bottom: AppSpace.xxs), child: _Crumbs(breadcrumbs!)),
                            ),
                          ),
                        ),
                      _titleRow(context, wide, t),
                      if (!wide && primaryAction != null) ...[
                        AppSpace.gapXs,
                        Align(alignment: AlignmentDirectional.centerEnd, child: AppHeaderTray(child: primaryAction!)),
                      ],
                    ]),
                  );
                },
              ),
            ),
          ),
        ),
        if (search != null || bottom != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.cardBg,
              border: Border(bottom: BorderSide(color: c.divider, width: AppBorder.hairline)),
            ),
            child: Padding(
              padding: inset.copyWith(top: AppSpace.sm, bottom: AppSpace.sm),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ?search,
                if (search != null && bottom != null) AppSpace.gapXs,
                ?bottom,
              ]),
            ),
          ),
      ]);
    });
  }

  /// Under the shell's bar the title is already above: what remains is the page's own actions, on the surface.
  Widget? _foldedRow(BuildContext context) {
    final c = context.colors;
    final hasUpdated = updatedAt != null;
    if (primaryAction == null && actions.isEmpty && onRefresh == null && !hasUpdated) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxs),
      child: Row(children: [
        Expanded(
          child: hasUpdated
              ? DefaultTextStyle.merge(style: TextStyle(color: c.textLight), child: _UpdatedText(at: updatedAt!, onSurface: true))
              : const SizedBox.shrink(),
        ),
        if (onRefresh != null)
          IconButton(
            tooltip: 'refresh'.tr,
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            onPressed: onRefresh,
            icon: Icon(Icons.refresh_rounded, size: AppIconSize.lg, color: c.textMedium),
          ),
        ...actions,
        if (primaryAction != null) ...[AppSpace.gapXs, primaryAction!],
      ]),
    );
  }

  Widget _titleRow(BuildContext context, bool wide, double collapse) {
    final c = context.colors;
    final refresh = onRefresh == null
        ? null
        : IconButton(
            tooltip: 'refresh'.tr,
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            onPressed: onRefresh,
            icon: Icon(Icons.refresh_rounded, size: AppIconSize.lg, color: c.onHero),
          );
    final global = MediaQuery.sizeOf(context).width >= Breakpoints.desktop ? ShellChrome.toolsOf(context) : null;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (onBack != null) ...[
        AppBackButton(onHero: true, onPressed: onBack),
        const SizedBox(width: AppSpace.xxs),
      ],
      if (icon != null) ...[
        Container(
          width: AppTouch.min - AppSpace.xs,
          height: AppTouch.min - AppSpace.xs,
          decoration: BoxDecoration(color: c.heroGlass, borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: Icon(icon, size: AppIconSize.lg, color: c.onHero),
        ),
        AppSpace.gapSm,
      ],
      Expanded(child: _titleBlock(context, collapse)),
      if (wide) ...[
        AppSpace.gapSm,
        ?refresh,
        if (actions.isNotEmpty) AppHeaderTray(child: Row(mainAxisSize: MainAxisSize.min, children: actions)),
        if (primaryAction != null) ...[AppSpace.gapXs, AppHeaderTray(child: primaryAction!)],
        // the app-wide tools (calendar, messages, assistant, bell) on every pushed page, as AppHeader draws them
        if (global != null) ...[AppSpace.gapXs, ChromeBar(child: global(context))],
        AppSpace.gapXs,
        const AppFocusToggle(onHero: true),
      ] else ...[
        ?refresh,
        if (actions.isNotEmpty) _MoreButton(actions: actions),
      ],
    ]);
  }

  Widget _titleBlock(BuildContext context, double collapse) {
    final c = context.colors;
    final sub = subtitle;
    final hasExtra = (sub != null && sub.isNotEmpty) || updatedAt != null;
    final extraShare = (1 - collapse * 2).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        header: true,
        child: Text(
          title,
          maxLines: collapse < 0.4 ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle.lerp(AppType.headline(context), AppType.section(context), collapse)!.copyWith(color: c.onHero),
        ),
      ),
      if (hasExtra && extraShare > 0)
        ClipRect(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            heightFactor: extraShare,
            child: Opacity(
              opacity: extraShare,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (sub != null && sub.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
                ],
                if (updatedAt != null) ...[
                  const SizedBox(height: AppSpace.xxs),
                  _UpdatedText(at: updatedAt!),
                ],
              ]),
            ),
          ),
        ),
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
        if (i > 0) Icon(Icons.chevron_right_rounded, size: AppIconSize.sm, color: c.onHeroMuted),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            items[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta(context).copyWith(
              color: i == items.length - 1 ? c.onHero : c.onHeroMuted,
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
        icon: Icon(Icons.more_horiz_rounded, size: AppIconSize.lg, color: context.colors.onHero),
      );
}

/// "Updated 2 min ago", re-drawn once a minute (only this text).
class _UpdatedText extends StatefulWidget {
  const _UpdatedText({required this.at, this.onSurface = false});
  final DateTime at;
  final bool onSurface;

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
        style: AppType.meta(context).copyWith(color: widget.onSurface ? context.colors.textLight : context.colors.onHeroMuted),
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
