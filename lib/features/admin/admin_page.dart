// lib/features/admin/admin_page.dart
//
// THE frame of every Super Admin page pushed from a hub (D-181): one AppPageHeader (Back when the page can pop, the
// title once, Refresh, the ONE primary action), a calm background (no doodle pattern behind lists and forms), the
// body centred at a readable width, and an unsaved-changes guard for settings pages.
//
//   AdminPage(
//     title: 'Devices', subtitle: '…', icon: Icons.devices_other_rounded,
//     onRefresh: _load, updatedAt: _loadedAt,
//     primaryAction: AppButton.primary(label: 'save'.tr, busy: _saving, onPressed: _dirty ? _save : null),
//     dirty: _dirty,
//     body: ListView(padding: AdminPage.bodyPadding(context), children: [...]),
//   )
//
// The body fills the rest of the page and scrolls by itself (a ListView, an AppDataTable, a TabBarView …).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show ShellChrome;
import 'package:flutter_education_app/features/shared/help/help_info_button.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// How a shell tab's Refresh reaches the page inside it without re-creating the page (which would drop its
/// filters, search text and scroll position). The tab wraps its page in an [AdminRefreshScope]; the page registers
/// its reload once (`AdminRefreshScope.register(context, provider.refresh)` in initState / didChangeDependencies).
/// A tab whose page registered nothing ([AdminRefreshSlot.reload] stays null) falls back to re-creating it.
/// The tab owns the [slot] (a field of its State), so a rebuild of the tab keeps the registration.
class AdminRefreshScope extends InheritedWidget {
  const AdminRefreshScope({super.key, required this.slot, required super.child});

  final AdminRefreshSlot slot;

  static AdminRefreshScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AdminRefreshScope>();

  /// Called by the page; the latest registration wins. No-op outside a scope (a pushed page).
  static void register(BuildContext context, Future<void> Function() reload) => maybeOf(context)?.slot.reload = reload;

  @override
  bool updateShouldNotify(AdminRefreshScope oldWidget) => false;
}

/// The reload a page registered in its tab's [AdminRefreshScope].
class AdminRefreshSlot {
  Future<void> Function()? reload;
}

class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.icon,
    this.primaryAction,
    this.actions = const [],
    this.search,
    this.onRefresh,
    this.updatedAt,
    this.bottom,
    this.dirty = false,
    this.floatingActionButton,
    this.maxWidth = maxContentWidth,
    this.width,
    this.showBack = true,
    this.helpPageId,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? primaryAction;
  final List<Widget> actions;
  final Widget? search;
  final VoidCallback? onRefresh;
  final DateTime? updatedAt;
  final Widget? bottom;
  final Widget body;

  /// True while a form holds changes that are not saved: Back asks first (AppUnsavedGuard).
  final bool dirty;
  final Widget? floatingActionButton;
  final double maxWidth;

  /// The body's page-width role (D-304) — a settings form takes [AppWidth.reading]; it wins over [maxWidth].
  final AppWidth? width;

  /// False for a page shown as a shell tab (it has nothing to go back to).
  final bool showBack;

  /// The page's id in the route registry (D-170): the header shows its Info (i) button (CONTRACTS section 6); the
  /// button hides itself when the viewer's role has no help for the page.
  final String? helpPageId;

  /// Lists and forms stop growing here; a data table may pass double.infinity.
  static const double maxContentWidth = 1200;

  /// The body's padding: the page gutter on the sides, a section gap at the bottom (above a FAB on phones).
  static EdgeInsets bodyPadding(BuildContext context, {bool fab = false}) {
    final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return EdgeInsets.fromLTRB(g, AppSpace.md, g, fab ? AppSpace.xxl + AppSpace.xl : AppSpace.lg);
  }

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    final header = AppPageHeader(
      title: title,
      subtitle: subtitle,
      icon: icon,
      primaryAction: primaryAction,
      actions: [...actions, if (helpPageId != null) HelpInfoButton(pageId: helpPageId!)],
      search: search,
      // a shell tab: the shell's bar already has Refresh (the tab reaches this page through AdminRefreshScope)
      onRefresh: ShellChrome.ownsHeaderOf(context) ? null : onRefresh,
      updatedAt: updatedAt,
      bottom: bottom,
      onBack: showBack && nav.canPop() ? () => nav.maybePop() : null,
    );
    return AppUnsavedGuard(
      dirty: dirty,
      child: BasePage(
        floatingActionButton: floatingActionButton,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.topCenter,
              child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width?.max ?? maxWidth), child: body),
            ),
          ),
        ]),
      ),
    );
  }
}
