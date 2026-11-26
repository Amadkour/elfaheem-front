// lib/features/admin/sup/sup_kit.dart
//
// The redesign frame of every Super Admin page (group A2, the reference's `Sup*` screens): the super-admin role scope,
// a hero band (gold kicker, one editorial headline, one line, at most two hero buttons, up to four glass figures),
// the page's segmented tabs on the hero's lower edge, then the page's own body, which scrolls the hero away.
//
//   SupPage(
//     title: 'a2_fees_title'.tr,                    the top bar (a pushed page) and the screen reader's page name
//     kicker: 'a2_fees_kicker'.tr, headline: …, line: …,
//     actions: [SupHeroButton(label: …, icon: …, onTap: …)],
//     stats: [AppHeroStat(value: '3', label: …)],
//     tabs: [AppTabItem('Rates'), AppTabItem('Policy')], tab: i, onTab: (v) => setState(() => i = v),
//     onRefresh: reload, dirty: _dirty, helpPageId: 'admin.fees',
//     body: ListView(padding: SupPage.bodyPadding(context), children: […]),
//   )
//
// The body is laid out under the hero inside a NestedScrollView: a body that scrolls through the primary scroll
// controller (a plain ListView, a data table's list) carries the hero away with it on every platform; the kept-alive
// tabs of a SupTabStack scroll on their own under the hero.
//
// Motion (DESIGN_SYSTEM §1.3, roles): M9 on the hero buttons, M10 on the figures (AppHeroStat), M13 in the tabs and
// M14 in the sheets; nothing loops (the hero's shapes draw their end state outside a student area).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppJelly;
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/design/chrome_button.dart' show ChromeBar;
import 'package:flutter_education_app/design/app_shell_nav.dart' show ShellChrome;
import 'package:flutter_education_app/features/help/help_info_button.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// The Super Admin page frame (see the file header).
class SupPage extends StatelessWidget {
  const SupPage({
    super.key,
    required this.title,
    required this.headline,
    required this.body,
    this.kicker,
    this.line,
    this.actions = const [],
    this.stats = const [],
    this.tabs,
    this.tab = 0,
    this.onTab,
    this.onRefresh,
    this.dirty = false,
    this.helpPageId,
    this.floatingActionButton,
    this.width = AppWidth.wide,
    this.showBack = true,
    this.heroBottom,
    this.updatedAt,
  });

  /// The page's name: the top bar of a pushed page.
  final String title;

  /// The page's content; it scrolls by itself.
  final Widget body;

  /// The gold line above the headline (the page's group or name).
  final String? kicker;

  /// ONE sentence: what this page is for, or what is waiting.
  final String headline;

  /// At most one line under the headline.
  final String? line;

  /// At most two hero buttons ([SupHeroButton], or one `AppButton.primary` for the page's main action), plus an
  /// optional [SupMoreButton].
  final List<Widget> actions;

  /// Up to four figures on the hero.
  final List<AppHeroStat> stats;

  /// The page's sections as a segmented pill on the hero's lower edge.
  final List<AppTabItem>? tabs;
  final int tab;
  final ValueChanged<int>? onTab;

  final FutureOr<void> Function()? onRefresh;

  /// True while a form holds unsaved changes: Back asks first.
  final bool dirty;
  final String? helpPageId;
  final Widget? floatingActionButton;

  /// The body's width role (D-304).
  final AppWidth width;

  /// False for a page shown as a shell tab.
  final bool showBack;

  /// When the data was loaded: a quiet "Updated …" line under the hero's text.
  final DateTime? updatedAt;

  /// Extra content on the hero under the tabs (a period switch, a search pill).
  final Widget? heroBottom;

  /// The body's padding: the page gutter on the sides, a section gap at the top and bottom.
  static EdgeInsets bodyPadding(BuildContext context, {bool fab = false}) {
    final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return EdgeInsets.fromLTRB(g, AppSpace.md, g, fab ? AppSpace.xxl + AppSpace.xl : AppSpace.xl);
  }

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    final inShell = ShellChrome.ownsHeaderOf(context);
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.mobile;
    final reload = onRefresh;
    final Future<void> Function()? refresh = reload == null ? null : () async => await reload();

    final heroActions = actions.take(3).toList();
    final tabItems = tabs;
    final bottom = <Widget>[
      if (!wide && heroActions.isNotEmpty)
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: heroActions),
      if (tabItems != null && tabItems.length > 1)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppTabs(items: tabItems, index: tab.clamp(0, tabItems.length - 1), onChanged: (i) => onTab?.call(i)),
        ),
      ?heroBottom,
    ];
    final at = updatedAt;
    final lineText = [
      if (line != null && line!.isNotEmpty) line!,
      if (at != null) appUpdatedText(at, DateTime.now()),
    ].join(' · ');

    final hero = AppHero(
      title: headline,
      subtitle: lineText.isEmpty ? null : lineText,
      kicker: kicker,
      stats: stats,
      statsOnPhone: true,
      overlap: false,
      wipe: false,
      trailing: wide && heroActions.isNotEmpty
          ? Align(
              alignment: AlignmentDirectional.bottomEnd,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: heroActions,
              ),
            )
          : null,
      bottom: bottom.isEmpty
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < bottom.length; i++) ...[if (i > 0) const SizedBox(height: AppSpace.sm), bottom[i]],
            ]),
    );

    final scroll = NestedScrollView(
      headerSliverBuilder: (context, _) => [SliverToBoxAdapter(child: hero)],
      body: Builder(
        builder: (context) => PrimaryScrollController(
          controller: PrimaryScrollController.of(context),
          automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
          child: Align(
            alignment: AlignmentDirectional.topCenter,
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width.max), child: body),
          ),
        ),
      ),
    );

    final appBar = inShell
        ? null
        : AppHeader(
            title: title,
            showBack: showBack && nav.canPop(),
            onBack: () => nav.maybePop(),
            actions: [
              if (refresh != null && AppRefreshAction.wanted) AppRefreshAction(onRefresh: refresh),
              if (helpPageId != null) HelpInfoButton(pageId: helpPageId!),
            ],
          );

    Widget page = BasePage(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      child: refresh == null ? scroll : AppRefresh(onRefresh: refresh, child: scroll),
    );
    if (inShell && helpPageId != null) {
      // the shell's bar carries the title; the page's help sits on the hero's top end
      page = Stack(children: [
        page,
        PositionedDirectional(
          top: AppSpace.xs,
          end: AppSpace.xs,
          child: ChromeBar(child: HelpInfoButton(pageId: helpPageId!)),
        ),
      ]);
    }
    return AppUnsavedGuard(
      dirty: dirty,
      child: AppAreaScope.role(role: AppRoleAccent.superAdmin, child: page),
    );
  }
}

/// A button on the hero: glass with the on-hero ink (the reference's `.k-btn.light`), jelly press (M9).
class SupHeroButton extends StatelessWidget {
  const SupHeroButton({super.key, required this.label, required this.onTap, this.icon, this.busy = false});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.pill);
    final enabled = onTap != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AppJelly(
        enabled: enabled,
        child: Opacity(
          opacity: enabled || busy ? 1 : .55,
          child: Material(
            color: c.heroGlass,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: c.heroGlassBorder, width: AppBorder.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                  child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (busy)
                      SizedBox.square(
                        dimension: AppIconSize.sm,
                        child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: c.onHero),
                      )
                    else if (icon != null)
                      Icon(icon, size: AppIconSize.md, color: c.onHero),
                    if (busy || icon != null) const SizedBox(width: AppSpace.xs),
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card of a Super Admin page: the title in the section face, an optional chip or link at the end, the body under.
class SupCard extends StatelessWidget {
  const SupCard({super.key, required this.title, required this.child, this.icon, this.trailing, this.subtitle});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[
            Container(
              width: AppTouch.min,
              height: AppTouch.min,
              decoration: BoxDecoration(color: c.kit.role(AppRoleAccent.superAdmin).tint, borderRadius: AppRadius.cardAll),
              child: Icon(icon, size: AppIconSize.lg, color: c.kit.role(AppRoleAccent.superAdmin).ink),
            ),
            const SizedBox(width: AppSpace.sm),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(subtitle!, style: AppType.meta(context)),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: AppSpace.sm), Flexible(child: trailing!)],
        ]),
        const SizedBox(height: AppSpace.sm),
        child,
      ]),
    );
  }
}

/// A short tab label with an optional count: the design's tabs (`AppTabItem` with a count when it is not zero).
AppTabItem supTab(String label, {int? count, IconData? icon}) =>
    AppTabItem(label, icon: icon, count: count == null || count == 0 ? null : count);

/// The tabs of a [SupPage] kept alive side by side (an IndexedStack, so an edit in one tab survives a visit to
/// another). Each tab scrolls with its own controller: a Scrollable keeps its position when its controller changes,
/// so a kept-alive tab can never be handed the page's nested controller, and sharing it among every tab would scroll
/// them all together. The hero stays in place while a tab scrolls under it.
class SupTabStack extends StatefulWidget {
  const SupTabStack({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<SupTabStack> createState() => _SupTabStackState();
}

class _SupTabStackState extends State<SupTabStack> {
  final _own = <ScrollController>[];

  ScrollController _ownAt(int i) {
    while (_own.length <= i) {
      _own.add(ScrollController());
    }
    return _own[i];
  }

  @override
  void dispose() {
    for (final c in _own) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.index.clamp(0, widget.children.length - 1);
    return IndexedStack(index: index, sizing: StackFit.expand, children: [
      for (var i = 0; i < widget.children.length; i++)
        PrimaryScrollController(
          controller: _ownAt(i),
          automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
          child: widget.children[i],
        ),
    ]);
  }
}

/// One entry of [SupMoreButton].
class SupMenuItem {
  const SupMenuItem({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

/// The hero's "more" button: a glass circle that opens the page's secondary tools.
class SupMoreButton extends StatelessWidget {
  const SupMoreButton({super.key, required this.items});

  final List<SupMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<int>(
      tooltip: 'a2_more'.tr,
      onSelected: (i) => items[i].onTap(),
      itemBuilder: (_) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(children: [
              Icon(items[i].icon, size: AppIconSize.md),
              const SizedBox(width: AppSpace.sm),
              Flexible(child: Text(items[i].label)),
            ]),
          ),
      ],
      child: Container(
        width: AppTouch.min,
        height: AppTouch.min,
        decoration: BoxDecoration(
          color: c.heroGlass,
          shape: BoxShape.circle,
          border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
        ),
        child: Icon(Icons.more_horiz_rounded, color: c.onHero, size: AppIconSize.md),
      ),
    );
  }
}
