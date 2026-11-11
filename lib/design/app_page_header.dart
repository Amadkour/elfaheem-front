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
// An editorial masthead on the canvas (D-612): a thin emerald strip on top, the title in the editorial page-title
// face in ink with the asymmetric rhythm (more room above the title than below it), the chrome as paper chips, one
// primary action, a warm hairline under it all. It collapses with the page's scroll (AppHeaderCollapse). The title
// wraps to two lines and ellipsises; nothing overflows at 320 px or text scale 1.3. "Updated 3 min ago" re-draws
// once a minute while shown.
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

  /// A quiet glyph before the title, in the medium ink.
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

  /// Draws the thin emerald strip on top (the one touch of colour).
  final bool accent;

  /// From this width the actions share the title's row.
  static const double wideFrom = 640;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final folded = ShellChrome.ownsHeaderOf(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= wideFrom;
      final gutter = AppSpace.gutter(box.maxWidth);
      final hasCrumbs = breadcrumbs != null && breadcrumbs!.isNotEmpty;
      // underline tabs close the header with their own rule
      final rule = bottom is! AppUnderlineTabs;
      return Material(
        color: c.background,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (folded)
            ?_foldedRow(context, gutter)
          else
            AppHeaderCollapse(
              builder: (context, collapse, _) => RepaintBoundary(
                child: AnimatedBuilder(
                  animation: collapse,
                  builder: (context, _) {
                    final t = collapse.value;
                    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (accent) const AppHeaderStrip(),
                      Padding(
                        // the editorial rhythm: more room above the title than under it; a compact header keeps a hair
                        padding: EdgeInsets.fromLTRB(
                          gutter,
                          lerpDouble(AppSpace.lg, AppSpace.xs, t)!,
                          gutter,
                          lerpDouble(AppSpace.md, AppSpace.xs, t)!,
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (hasCrumbs && t < 1)
                            ClipRect(
                              child: Align(
                                alignment: AlignmentDirectional.topStart,
                                heightFactor: 1 - t,
                                child: Opacity(
                                  opacity: 1 - t,
                                  child: Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: _Crumbs(breadcrumbs!)),
                                ),
                              ),
                            ),
                          _titleRow(context, wide, t),
                          if (!wide && primaryAction != null) ...[
                            AppSpace.gapSm,
                            Align(alignment: AlignmentDirectional.centerEnd, child: primaryAction!),
                          ],
                        ]),
                      ),
                    ]);
                  },
                ),
              ),
            ),
          if (search != null || bottom != null)
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(gutter, 0, gutter, rule ? AppSpace.sm : 0),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ?search,
                if (search != null && bottom != null) AppSpace.gapSm,
                ?bottom,
              ]),
            ),
          if (rule) const AppHeaderRule(),
        ]),
      );
    });
  }

  /// Under the shell's bar the title is already above: what remains is the page's own actions, on the canvas.
  Widget? _foldedRow(BuildContext context, double gutter) {
    final c = context.colors;
    final hasUpdated = updatedAt != null;
    if (primaryAction == null && actions.isEmpty && onRefresh == null && !hasUpdated) return null;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.sm, gutter, AppSpace.xxs),
      child: Row(children: [
        Expanded(child: hasUpdated ? _UpdatedText(at: updatedAt!) : const SizedBox.shrink()),
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
            icon: Icon(Icons.refresh_rounded, size: AppIconSize.lg, color: c.textMedium),
          );
    final global = MediaQuery.sizeOf(context).width >= Breakpoints.desktop ? ShellChrome.toolsOf(context) : null;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (onBack != null) ...[
        AppBackButton(onPressed: onBack),
        const SizedBox(width: AppSpace.xs),
      ],
      if (icon != null) ...[
        Icon(icon, size: AppIconSize.lg, color: c.textMedium),
        AppSpace.gapSm,
      ],
      Expanded(child: _titleBlock(context, collapse)),
      if (wide) ...[
        AppSpace.gapSm,
        ?refresh,
        if (actions.isNotEmpty) AppHeaderTray(child: Row(mainAxisSize: MainAxisSize.min, children: actions)),
        if (primaryAction != null) ...[AppSpace.gapSm, primaryAction!],
        // the app-wide tools (calendar, messages, assistant, bell) on every pushed page, as AppHeader draws them
        if (global != null) ...[AppSpace.gapXs, global(context)],
        AppSpace.gapXs,
        const AppFocusToggle(),
      ] else ...[
        ?refresh,
        if (actions.isNotEmpty) _MoreButton(actions: actions),
      ],
    ]);
  }

  Widget _titleBlock(BuildContext context, double collapse) {
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
          style: TextStyle.lerp(AppType.pageTitle(context), AppType.section(context), collapse),
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
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
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

  /// The widest one crumb grows before it ellipsises.
  static const double _crumbMax = 200;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) Icon(Icons.chevron_right_rounded, size: AppIconSize.sm, color: c.textLight),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _crumbMax),
          child: Text(
            items[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta(context).copyWith(
              color: i == items.length - 1 ? c.textMedium : c.textLight,
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
        style: AppType.meta(context).copyWith(color: context.colors.textLight),
      );
}

/// A section heading with its body, in the editorial rhythm (system.md §4, [AppSpace.sectionHead]): more room above
/// the heading (32) than between it and the [child] (12), so a page reads as paragraphs rather than a stack of equal
/// gaps — put nothing between two sections. Title (+ subtitle) on the start side, an optional trailing widget (a
/// "See all" link, a filter) on the end.
class AppSection extends StatelessWidget {
  const AppSection({super.key, required this.title, this.subtitle, this.trailing, required this.child, this.spaceAbove = true});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  /// The 32 above the heading; false for the first section of a surface that already has its own top padding.
  final bool spaceAbove;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Padding(
      padding: EdgeInsetsDirectional.only(top: spaceAbove ? AppSpace.sectionHead.top : 0),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
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
          // the trailing control never pushes the row past its edge (a pill at a big text scale on a phone): it is
          // capped at 60 % of the row and its own label ellipsizes; a heading without one keeps the plain row
          if (trailing != null) ...[
            AppSpace.gapSm,
            ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.6), child: trailing!),
          ],
        ]),
        SizedBox(height: AppSpace.sectionHead.bottom),
        child,
      ]),
    );
  }
}
