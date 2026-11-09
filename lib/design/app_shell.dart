// lib/design/app_shell.dart — ONE navigation shell for every role dashboard (student · teacher · parent · admin ·
// organization), D-062.
//
//   AppShell(width: constraints.maxWidth, currentIndex:, onTap:, items:, unreadCount:, showTopBar:)
//       picks the shell with Breakpoints.shellFor (app_responsive.dart):
//         WideShell    sidebar + top bar            (>= Breakpoints.desktop)
//         RailShell    NavigationRail + top bar     (>= Breakpoints.mobile)
//         MobileShell  bottom bar                   (phones)
//       The three are public too, for a dashboard that picks one by hand. Every shell keeps the tabs in a
//       [LazyTabStack] (D-077): a tab is built the first time it is shown (the open tab at once, the others on
//       their first visit, so a home's other tabs load nothing until visited) and then kept in an IndexedStack,
//       so it keeps its state. A tab switch from a deep link / onTap just changes currentIndex. Badges never
//       need a tab built: they come from DashboardItem.badge + attentionKeys, drawn by ShellBadge.
//       Each tab has its own navigator (D-081, app_shell_nav.dart): a page opened from inside a tab keeps the bar /
//       rail / sidebar, every tab keeps its own back stack, a tap on the current tab goes back to its root, the
//       system back pops the tab first (then goes to the home tab), and a [ShellFullScreen] page hides the chrome.
//       The tab stack is one GlobalKey'd subtree, so a rotation that changes the shell kind keeps every stack.
//   DashboardItem(icon, selectedIcon, label, onRefresh, screen, {badge, attentionKeys, attentionOrgId})
//       one tab. `label` is a translation key (or an already translated text — a missing key falls back to
//       itself). The count on the tab = `badge` (what the attention feed does not carry, set by the dashboard)
//       + the live count of `attentionKeys` (GET /me/attention, AttentionTabs), drawn by [ShellBadge] at the
//       LEAF: an attention tick repaints the badge, never the shell.
//   UserChipButton · NotificationIcon · CalendarIcon
//       the sidebar's user chip and the top bar's icons (the home headers use them too).
//
// Colours come from context.colors only: onHero / onHeroFaint / heroGlass / heroDivider over the sidebar
// gradient and the primary top bar, cardShadow / bottomNavShadow for the shadows.
// Layout test: test/ui/app_shell_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';
import '../core/app_identity.dart';
import '../core/attention/attention_service.dart';
import '../core/inbox_badge.dart';
import '../core/routing/app_routes.dart' show AppRoutes;
import '../features/auth/auth_provider.dart';
import '../features/shared/help/help_info_button.dart';
import '../features/shared/guest/guest_state.dart';
import '../features/shared/profile/update_account_widget.dart';
import '../utils/widget/app_navigator.dart' show AppNavigator;
import '../utils/widget/app_network_image.dart';
import '../utils/widget/base_page.dart';
import '../utils/widget/refresh_button.dart';
import 'app_focus_mode.dart';
import 'app_tokens.dart';
import 'app_responsive.dart';
import 'app_shell_nav.dart';
import 'calendar_entry.dart';
import '../features/shared/rag/app_assistant.dart' show AppAssistant, appAssistantFeatureKey;
import 'chrome_button.dart';
import 'app_settings.dart' show appRoleLabel;
import 'package:flutter_education_app/core/display/app_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class DashboardItem {
  DashboardItem(
    this.icon,
    this.selectedIcon,
    this.label,
    this.onRefresh,
    this.screen, {
    this.badge = 0,
    this.attentionKeys = const [],
    this.attentionOrgId,
  });

  final IconData icon, selectedIcon;
  final String label;
  final Future<void> Function()? onRefresh;
  final Widget screen;

  /// Count the attention feed does not carry (0 = none). Set by the dashboard from its own provider.
  int badge;

  /// AttentionTabs keys whose live counts are added to [badge] (drawn at the leaf, see [ShellBadge]).
  final List<String> attentionKeys;

  /// Only this organization's attention items (org dashboards).
  final int? attentionOrgId;
}

/// The count on a tab: [DashboardItem.badge] + the live attention counts of its keys. Only this widget
/// rebuilds on an attention tick; an item without keys never listens (guests, tests).
class ShellBadge extends StatelessWidget {
  const ShellBadge({super.key, required this.item, required this.builder});

  final DashboardItem item;
  final Widget Function(BuildContext context, int count) builder;

  /// Test / preview hooks: the feed to listen to and where the counts come from.
  static Listenable Function() source = () => AttentionService.instance;
  static int Function(String tabKey, int? orgId) countOf =
      (key, orgId) => AttentionService.instance.count(key, orgId: orgId);

  int _live() {
    var n = 0;
    for (final k in item.attentionKeys) {
      n += countOf(k, item.attentionOrgId);
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    if (item.attentionKeys.isEmpty) return builder(context, item.badge);
    return ListenableBuilder(
      listenable: source(),
      builder: (context, _) => builder(context, item.badge + _live()),
    );
  }
}

String _badgeText(int n) => n > 99 ? '99+' : '$n';

/// The tab bodies of a shell: an IndexedStack whose children stay placeholders until their tab is first shown
/// (D-077). A visited tab is remembered by its label, so it stays built when tabs before it come or go (an older
/// server, a permission change); its state lives as long as the shell does. Each built tab is a navigator of its
/// own (D-081): [ShellTabs] holds their stacks; without one ([tabs] null) the stack keeps its own.
class LazyTabStack extends StatefulWidget {
  const LazyTabStack({super.key, required this.index, required this.items, this.tabs});

  final int index;
  final List<DashboardItem> items;
  final ShellTabs? tabs;

  @override
  State<LazyTabStack> createState() => _LazyTabStackState();
}

class _LazyTabStackState extends State<LazyTabStack> {
  final Set<String> _visited = {};
  ShellTabs? _own;

  ShellTabs get _tabs => widget.tabs ?? (_own ??= ShellTabs());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final current = widget.index.clamp(0, items.length - 1);
    _visited.add(items[current].label);
    _tabs.homeLabel = items.first.label; // the home's own URL; another tab is `<home>/<tab>` (D-170)
    _tabs.setActive(items[current].label);
    // Each tab's navigator draws its pages over a modal barrier, and a barrier BLOCKS the semantics of everything
    // painted before it in the same semantics container — the sidebar, the rail and the top bar (H12: at 1440 a
    // screen reader found no navigation at all). A container of its own keeps that block inside the tabs.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: IndexedStack(
      index: current,
      children: [
        for (var i = 0; i < items.length; i++)
          _visited.contains(items[i].label)
              ? KeyedSubtree(
                  key: ValueKey('tab:${items[i].label}'),
                  child: _TabNavigatorHost(tab: _tabs.tab(items[i].label), screen: items[i].screen, active: i == current),
                )
              : const SizedBox.shrink(),
      ],
      ),
    );
  }
}

/// One tab: its screen at the bottom of its own navigator. Named routes are built by the app's router (the root
/// navigator's onGenerateRoute), so `pushNamed` works the same inside a tab.
class _TabNavigatorHost extends StatelessWidget {
  const _TabNavigatorHost({required this.tab, required this.screen, required this.active});

  final ShellTab tab;
  final Widget screen;
  final bool active;

  NavigatorState? _root() {
    final ctx = tab.navKey.currentContext;
    return ctx == null ? null : Navigator.maybeOf(ctx, rootNavigator: true);
  }

  @override
  Widget build(BuildContext context) => TickerMode(
        enabled: active,
        child: ShellTabScreen(
          screen: screen,
          child: HeroControllerScope(
            controller: tab.hero,
            child: AppTabNavigator(
              key: tab.navKey,
              tab: tab,
              observers: [tab.observer],
              onGenerateInitialRoutes: (_, _) => [tab.makeRoot()],
              onGenerateRoute: (s) => _root()?.widget.onGenerateRoute?.call(s),
              onUnknownRoute: (s) => _root()?.widget.onUnknownRoute?.call(s),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// AppShell — picks the shell for a width
// ─────────────────────────────────────────────────────────────────────────────

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.width,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.unreadCount = 0,
    this.showTopBar = true,
  });

  final double width;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<DashboardItem> items;

  /// Unread notifications, for the top bar's bell (phones have none in the shell).
  final int unreadCount;

  /// False: the wide / rail shells draw no top bar (title · refresh · calendar · assistant · bell) because every
  /// page draws its own header with those actions — the organization dashboard (OrgPageHeader, D-103), so nothing
  /// appears twice.
  final bool showTopBar;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _tabs = ShellTabs();
  final _stackKey = GlobalKey(debugLabel: 'shell-tabs');

  @override
  void initState() {
    super.initState();
    AppShellNav.register(_tabs);
    _tabs.addListener(_changed);
    AppFocusMode.instance.addListener(_changed);
    AppFocusMode.instance.ensureLoaded();
    AppNavigator.requestedTab.addListener(_onTabRequested);
    // a request made before this shell existed (a `<home>/<tab>` URL, a refresh)
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTabRequested());
  }

  /// A tab asked for by its key (`/admin_dashboard/users`, D-170): every role's home switches to it. The dashboards
  /// that know other keys ('profile', 'last') answer those themselves.
  void _onTabRequested() {
    final id = AppNavigator.requestedTab.value;
    if (id == null || !mounted) return;
    final i = widget.items.indexWhere((e) => e.label == id);
    if (i < 0) return;
    AppNavigator.requestedTab.value = null; // consumed
    if (i != _current) widget.onTap(i);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tabs.hostRoute = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _tabs.removeListener(_changed);
    AppFocusMode.instance.removeListener(_changed);
    AppNavigator.requestedTab.removeListener(_onTabRequested);
    AppShellNav.unregister(_tabs);
    _tabs.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  int get _current => widget.items.isEmpty ? 0 : widget.currentIndex.clamp(0, widget.items.length - 1);

  void _onTap(int i) {
    switch (shellTapAction(tapped: i, current: _current, tabCanPop: _tabs.activeCanPop)) {
      case ShellTap.popToRoot:
        _tabs.popActiveToRoot();
      case ShellTap.switchTab:
      case ShellTap.none:
        widget.onTap(i);
    }
  }

  void _onBack() {
    switch (shellBackAction(tabCanPop: _tabs.activeCanPop, index: _current)) {
      case ShellBack.popTab:
        _tabs.active?.navigator?.maybePop();
      case ShellBack.homeTab:
        widget.onTap(0);
      case ShellBack.leave:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final body = LazyTabStack(key: _stackKey, index: _current, items: items, tabs: _tabs);
    final kind = Breakpoints.shellFor(widget.width);
    final full = _tabs.fullScreen;
    final focus = kind != AppShellKind.mobile && AppFocusMode.instance.value;
    _tabs.bottomBar = full || kind != AppShellKind.mobile ? 0 : BottomNavMetrics.heightFor(context);
    _tabs.sideChrome = full || focus
        ? 0
        : switch (kind) {
            AppShellKind.wide => Breakpoints.sidebarW,
            AppShellKind.rail => 67, // NavigationRail minWidth 66 + its divider
            AppShellKind.mobile => 0,
          };
    final Widget shell = full
        ? ColoredBox(color: context.colors.background, child: body)
        : switch (kind) {
            AppShellKind.wide => WideShell(
                currentIndex: _current, onTap: _onTap, dashboardItems: items, unreadCount: widget.unreadCount, body: body,
                showTopBar: widget.showTopBar, focus: focus),
            AppShellKind.rail => RailShell(
                currentIndex: _current, onTap: _onTap, dashboardItems: items, unreadCount: widget.unreadCount, body: body,
                showTopBar: widget.showTopBar, focus: focus),
            AppShellKind.mobile => MobileShell(currentIndex: _current, onTap: _onTap, dashboardItems: items, body: body),
          };
    final back = shellBackAction(tabCanPop: _tabs.activeCanPop, index: _current);
    return ShellScope(
      tabs: _tabs,
      child: PopScope<Object?>(
        canPop: back == ShellBack.leave,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBack();
        },
        child: shell,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FOCUS MODE (D-360)
// ─────────────────────────────────────────

/// The sidebar / rail: folds to nothing in focus mode and stays in the tree.
class _FocusFold extends StatelessWidget {
  const _FocusFold({required this.focus, required this.child});

  final bool focus;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: AnimatedAlign(
          alignment: AlignmentDirectional.centerEnd,
          widthFactor: focus ? 0 : 1,
          duration: AppMotion.of(context).slow,
          curve: AppMotion.curve,
          child: ExcludeFocus(excluding: focus, child: ExcludeSemantics(excluding: focus, child: child)),
        ),
      );
}

/// The page area, with the way out of focus mode floating over it.
class _FocusExitLayer extends StatelessWidget {
  const _FocusExitLayer({required this.focus, required this.child});

  final bool focus;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        child,
        if (focus)
          const PositionedDirectional(bottom: AppSpace.md, end: AppSpace.md, child: AppFocusExitPill()),
      ]);
}

// ─────────────────────────────────────────
// WIDE LAYOUT (>= Breakpoints.desktop) — persistent sidebar + top bar
// ─────────────────────────────────────────────────────────────────────────────

class WideShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<DashboardItem> dashboardItems;
  final int unreadCount;

  /// The tab bodies ([AppShell] passes its keyed [LazyTabStack]); null = a stack of its own.
  final Widget? body;

  const WideShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.dashboardItems,
    required this.unreadCount,
    this.body,
    this.showTopBar = true,
    this.focus = false,
  });

  /// False: no top bar — the pages draw their own header with these actions (the organization dashboard, D-103).
  final bool showTopBar;

  /// Focus mode: no side chrome and no top bar (the exit pill floats instead).
  final bool focus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = context.watch<MyAuthProvider>().currentUser;
    final current = currentIndex.clamp(0, dashboardItems.length - 1);
    return BasePage(
      child: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────────────────────
          _FocusFold(focus: focus, child: Container(
            width: Breakpoints.sidebarW,
            decoration: BoxDecoration(gradient: c.slideBarGradient),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // decorative glows
                Positioned(top: -80, right: -80, child: _Glow(size: 320, opacity: 0.06)),
                Positioned(bottom: -100, left: -60, child: _Glow(size: 280, opacity: 0.04)),
                Positioned(top: 200, left: -40, child: _Glow(size: 160, opacity: 0.05)),
                Column(
                  children: [
                    const SizedBox(height: 32),
                    // Logo row: ONE app name, the one the super admin sets ("About us").
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: c.primary.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(Icons.school_rounded, color: c.onHero, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppIdentity.instance.name.isNotEmpty ? AppIdentity.instance.name : 'NextBrain',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: AppFonts.display,
                                    color: c.onHero,
                                    fontWeight: FontWeight.normal,
                                    fontSize: 17,
                                  ),
                                ),
                                Text(
                                  AppIdentity.instance.tagline.isNotEmpty
                                      ? AppIdentity.instance.tagline
                                      : 'app_tagline'.tr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontFamily: AppFonts.family, color: c.onHeroFaint, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Divider(height: 1, color: c.heroDivider),
                    const SizedBox(height: 10),
                    // Nav items
                    Expanded(
                      child: Semantics(
                        container: true,
                        explicitChildNodes: true,
                        label: 'shell_navigation'.tr,
                        child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (int i = 0; i < dashboardItems.length; i++)
                            _SidebarTile(
                              item: dashboardItems[i],
                              selected: current == i,
                              onTap: () => onTap(i),
                            ),
                        ],
                      ),
                      ),
                    ),
                    Divider(height: 1, color: c.heroDivider),
                    const SizedBox(height: 14),
                    if (user != null) UserChipButton(user: user, showLabel: true),
                  ],
                ),
              ],
            ),
          )),

          // ── Main content ──────────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                if (showTopBar && !focus)
                  _TopBar(
                    title: dashboardItems[current].label.tr,
                    unread: unreadCount,
                    onRefresh: dashboardItems[current].onRefresh,
                    helpPageId: shellHelpPageId(context, dashboardItems[current].label, current == 0),
                  ),
                // the top bar already sits under the status bar: the pages below must not pad for it again
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: showTopBar && !focus,
                    child: _FocusExitLayer(focus: focus, child: body ?? LazyTabStack(index: current, items: dashboardItems)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: context.colors.onHero.withValues(alpha: opacity)),
      );
}

/// The signed-in user at the bottom of the sidebar / rail — opens the account editor.
class UserChipButton extends StatelessWidget {
  final UserModel user;
  final bool showLabel;

  const UserChipButton({super.key, required this.user, required this.showLabel});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = user.name;
    final initial = name.isNotEmpty ? name[0] : '؟';
    final image = user.imageUrl;
    return Padding(
      padding: showLabel ? const EdgeInsets.fromLTRB(14, 0, 14, 10) : const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: name,
        child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => AppShellNav.navigatorFor(context).push(MaterialPageRoute(builder: (_) => EditAccountScreen())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          // light mode: a solid primary chip — the server's sidebar gradient may fade to near-white at the bottom,
          // where on-hero ink over the glass fell below 4.5:1 (name and role unreadable)
          decoration: BoxDecoration(
            color: c.isDark ? c.heroGlass : c.primary.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: showLabel ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(gradient: c.accentGradient, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: image != null && image.isNotEmpty
                    ? Container(
                        width: 35,
                        height: 35,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.primary.withValues(alpha: 0.1),
                          border: Border.all(color: c.primary, width: 2.5),
                        ),
                        child: ClipOval(
                          child: AppNetworkImage(url: image, enableFullscreen: false, heroTag: 'user_logo-dashboard'),
                        ),
                      )
                    : Text(
                        initial,
                        style: TextStyle(
                          color: c.onHero,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppFonts.display,
                        ),
                      ),
              ),
              if (showLabel) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        // the sidebar is the hero surface in both themes: on-hero ink (primaryLight w100 was
                        // low-contrast blue on it)
                        style: TextStyle(
                          color: c.onHero,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          fontFamily: AppFonts.family,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        appRoleLabel(user.role),
                        maxLines: 1,
                        style: TextStyle(color: c.onHeroMuted, fontSize: 11, fontFamily: AppFonts.family),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ── Sidebar tile ──────────────────────────────────────────────────────────────

class _SidebarTile extends StatelessWidget {
  final DashboardItem item;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarTile({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // a real button for screen readers and the keyboard (H12): focusable, Enter / Space, selected state read out
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            focusColor: c.heroGlass,
            hoverColor: c.heroGlass.withValues(alpha: 0.08),
            child: _tile(c),
          ),
        ),
      ),
    );
  }

  Widget _tile(ThemeConfigProvider c) {
    return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        // selected: a warm accent2 wash on the light (brand) sidebar; the brand gradient pill on the dark one (D-136)
        decoration: BoxDecoration(
          // (no colour under the gradient: a transparent paint colour would fade the shader to nothing)
          color: selected && c.isDark ? null : (selected ? c.accent2.withValues(alpha: 0.2) : Colors.transparent),
          gradient: selected && c.isDark ? c.primaryGradient : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected && !c.isDark ? c.primary.withValues(alpha: 0.3) : Colors.transparent),
          boxShadow: selected && c.isDark ? c.primaryButtonShadow : null,
        ),
        child: Row(
          children: [
            if (selected)
              Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(2)),
                margin: const EdgeInsetsDirectional.only(end: 10),
              ),
            Icon(selected ? item.selectedIcon : item.icon, color: selected ? c.onHero : c.onHeroFaint, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  color: selected ? c.onHero : c.onHeroFaint,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
            ShellBadge(
              item: item,
              builder: (context, n) => n <= 0
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsetsDirectional.only(start: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          _badgeText(n),
                          style: TextStyle(
                            color: c.onHero,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            fontFamily: AppFonts.display,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      );
  }
}

/// The help entry of a role home's tab: `home.student` for the first tab, `home.student/my_courses` for the others
/// (the role from the signed-in person's home route); null for a guest or a tab-less shell.
String? shellHelpPageId(BuildContext context, String tabKey, bool first) {
  try {
    final route = Provider.of<MyAuthProvider>(context, listen: false).homeRoute;
    for (final h in AppRoutes.homes) {
      if (h.path == route) return first ? h.id : '${h.id}/$tabKey';
    }
  } on ProviderNotFoundException {
    return null;
  }
  return null;
}

// ── Top bar (wide + rail) ─────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final int unread;
  final Future<void> Function()? onRefresh;
  final String? helpPageId;

  const _TopBar({required this.title, required this.unread, required this.onRefresh, this.helpPageId});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // A page pushed inside the tab (a course, a setting …) brings its own title: the tab's name would lie (M8).
    final shell = ShellScope.maybeOf(context);
    final pushed = shell?.activeCanPop ?? false;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'shell_top_bar'.tr,
      child: Container(
        height: 64,
        // light: the hero gradient (D-180), so the bar and the brand sidebar read as one header — both start at
        // primary on the reading-start side; dark: the card surface (a brand fill glares on a dark page)
        decoration: BoxDecoration(
          color: c.isDark ? c.cardBg : null,
          gradient: c.isDark ? null : c.heroGradient,
          border: Border(bottom: BorderSide(color: c.primary.withValues(alpha: 0.08))),
          boxShadow: c.cardShadow,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ChromeBar(
          child: Row(
            children: [
              Expanded(
                child: pushed
                    ? const SizedBox.shrink()
                    : Semantics(
                        header: true,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: c.h2.copyWith(color: c.isDark ? c.textDark : c.onHero, fontWeight: FontWeight.w600),
                        ),
                      ),
              ),
              // the actions scale down instead of overflowing when the shell is squeezed
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (onRefresh != null && !pushed) ...[RefreshButton(onTap: onRefresh!), const SizedBox(width: 6)],
                    if (!GuestState.active) const CalendarIcon(),
                    if (!GuestState.active) const ChatEntryIcon(),
                    if (!GuestState.active && !AppConfig.disableList.contains(appAssistantFeatureKey))
                      ChromeIconButton(
                        icon: Icons.auto_awesome_rounded,
                        label: 'assistant_entry_title'.tr,
                        onTap: AppAssistant.openPanel,
                      ),
                    if (helpPageId != null && !pushed) HelpInfoButton(pageId: helpPageId!),
                    NotificationIcon(unreadCount: unread),
                    AppFocusToggle(onHero: !c.isDark),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the personal overall calendar ('/calendar' with no org/dept = every source the user belongs to).
/// The same icon every role uses: [CalendarEntryIcon] (lib/design/calendar_entry.dart, kill switch `calendar.entry`).
class CalendarIcon extends StatelessWidget {
  const CalendarIcon({super.key});

  @override
  Widget build(BuildContext context) => const CalendarEntryIcon();
}

/// The bell — opens the inbox page on its Notifications tab ('/notifications'). Its count is the ACTIONABLE one:
/// [unreadCount] unread notifications plus the inbox's to-dos ([InboxBadge], fed by the answers the app already has;
/// announcements and offers never count). [withTodos] false: the unread count alone (0 = a plain bell, where the
/// screen draws the counts itself).
class NotificationIcon extends StatelessWidget {
  const NotificationIcon({super.key, required this.unreadCount, this.withTodos = true});

  final int unreadCount;
  final bool withTodos;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: InboxBadge.instance,
        builder: (context, _) => ChromeIconButton(
          icon: Icons.notifications_rounded,
          label: 'notifications'.tr,
          badge: withTodos ? inboxActionableCount(todo: InboxBadge.instance.todo, unread: unreadCount) : unreadCount,
          onTap: () => AppShellNav.navigatorFor(context).pushNamed('/notifications'),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// RAIL LAYOUT (Breakpoints.mobile … desktop) — NavigationRail + top bar
// ─────────────────────────────────────────────────────────────────────────────

class RailShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<DashboardItem> dashboardItems;
  final int unreadCount;

  /// The tab bodies ([AppShell] passes its keyed [LazyTabStack]); null = a stack of its own.
  final Widget? body;

  const RailShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.dashboardItems,
    required this.unreadCount,
    this.body,
    this.showTopBar = true,
    this.focus = false,
  });

  /// False: no top bar — the pages draw their own header with these actions (the organization dashboard, D-103).
  final bool showTopBar;

  /// Focus mode: no side chrome and no top bar (the exit pill floats instead).
  final bool focus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = context.watch<MyAuthProvider>().currentUser;
    final current = currentIndex.clamp(0, dashboardItems.length - 1);
    final railBg = c.isDark ? c.cardBg : c.primary;
    return BasePage(
      child: Row(
        children: [
          _FocusFold(focus: focus, child: ColoredBox(
            color: railBg,
            child: Column(
              children: [
                Expanded(
                  child: NavigationRail(
                    backgroundColor: railBg,
                    selectedIndex: current,
                    onDestinationSelected: onTap,
                    minWidth: 66,
                    labelType: NavigationRailLabelType.none,
                    indicatorColor: c.primary.withValues(alpha: 0.35),
                    selectedIconTheme: IconThemeData(color: c.onHero, size: 23),
                    unselectedIconTheme: IconThemeData(color: c.onHeroFaint, size: 22),
                    leading: Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 12),
                      child: Icon(Icons.school_rounded, color: c.accent2, size: 26),
                    ),
                    destinations: [
                      for (final item in dashboardItems)
                        NavigationRailDestination(
                          icon: _RailIcon(item: item, icon: item.icon),
                          selectedIcon: _RailIcon(item: item, icon: item.selectedIcon),
                          label: Text(item.label.tr),
                        ),
                    ],
                  ),
                ),
                if (user != null) UserChipButton(user: user, showLabel: false),
              ],
            ),
          )),
          if (!focus) VerticalDivider(width: 1, color: c.divider),
          Expanded(
            child: Column(
              children: [
                if (showTopBar && !focus)
                  _TopBar(
                    title: dashboardItems[current].label.tr,
                    unread: unreadCount,
                    onRefresh: dashboardItems[current].onRefresh,
                    helpPageId: shellHelpPageId(context, dashboardItems[current].label, current == 0),
                  ),
                // the top bar already sits under the status bar: the pages below must not pad for it again
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: showTopBar && !focus,
                    child: _FocusExitLayer(focus: focus, child: body ?? LazyTabStack(index: current, items: dashboardItems)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  const _RailIcon({required this.item, required this.icon});

  final DashboardItem item;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ShellBadge(
        item: item,
        builder: (context, n) => Badge(
          isLabelVisible: n > 0,
          label: Text(_badgeText(n)),
          child: Icon(icon),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE LAYOUT (< Breakpoints.mobile) — bottom bar
// ─────────────────────────────────────────────────────────────────────────────

class MobileShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<DashboardItem> dashboardItems;

  /// The tab bodies ([AppShell] passes its keyed [LazyTabStack]); null = a stack of its own.
  final Widget? body;

  const MobileShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.dashboardItems,
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    final current = currentIndex.clamp(0, dashboardItems.length - 1);
    return BasePage(
      bottomNavigationBar: _BottomNav(onSelect: onTap, index: current, dashboardItems: dashboardItems),
      child: body ?? LazyTabStack(index: current, items: dashboardItems),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final List<DashboardItem> dashboardItems;

  const _BottomNav({required this.index, required this.onSelect, required this.dashboardItems});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
        boxShadow: c.bottomNavShadow,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (var i = 0; i < dashboardItems.length; i++)
                Expanded(child: _BottomTab(item: dashboardItems[i], active: i == index, onTap: () => onSelect(i))),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomTab extends StatelessWidget {
  const _BottomTab({required this.item, required this.active, required this.onTap});

  final DashboardItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 42,
            height: 30,
            decoration: BoxDecoration(
              // the brand gradient (D-136); the server's accent gradient faded to cream under a white icon
              gradient: active ? c.primaryGradient : null,
              borderRadius: BorderRadius.circular(10),
              boxShadow: active
                  ? [BoxShadow(color: c.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))]
                  : null,
            ),
            child: ShellBadge(
              item: item,
              builder: (context, n) => Badge(
                isLabelVisible: n > 0,
                label: Text(_badgeText(n)),
                child: Center(
                  child: Icon(active ? item.selectedIcon : item.icon, size: 20, color: active ? c.onHero : c.textLight),
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? c.primary : c.textLight,
              fontFamily: AppFonts.display,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// The phone bar's height (its rows + the safe area under it), for what floats above it (the app assistant).
class BottomNavMetrics {
  BottomNavMetrics._();

  /// 8 + 30 (icon well) + 3 + the label line + 8, plus the home-indicator inset.
  static double heightFor(BuildContext context) {
    final label = MediaQuery.textScalerOf(context).scale(10) * 1.5;
    return 8 + 30 + 3 + label + 8 + MediaQuery.paddingOf(context).bottom;
  }
}
