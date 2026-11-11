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
//   DashboardItem(icon, selectedIcon, label, onRefresh, screen, {badge, badgeTone, attentionKeys, attentionOrgId})
//       one tab. `label` is a translation key (or an already translated text — a missing key falls back to
//       itself). The count on the tab = `badge` (what the attention feed does not carry, set by the dashboard)
//       + the live count of `attentionKeys` (GET /me/attention, AttentionTabs), drawn by [ShellBadge] at the
//       LEAF: an attention tick repaints the badge, never the shell. `badgeTone` says what the count means
//       ([ShellBadgeTone]: attention = danger, reward = gold).
//   UserChipButton · NotificationIcon · CalendarIcon
//       the sidebar's user chip and the top bar's icons (the home headers use them too).
//
// The look (premium dashboard, D-631, over Warm Editorial Blocks): the page is the warm canvas; the sidebar is a
// PAPER column (`cardBg`) set off by one warm hairline, its tabs in groups — each under a soft tinted header (a
// title and one line) — the open tab a tinted pill in the primary ink with its count, and a button folds it to its
// icons (appSidebarCollapsed); the top bar is a paper band with the search box (when the screen has a Ctrl+K
// palette), ghost icon buttons with small counts and the signed-in person (avatar, name, role); under it the page
// head: the tab's title in the editorial face at the start and its breadcrumb at the end. The phone's bottom bar is
// paper with a hairline, the open tab's icon on a tinted pill over its label in the primary ink.
// Colours come from context.colors only. Layout test: test/ui/app_shell_layout_test.dart.
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
import 'app_dashboard_kit.dart' show AppBreadcrumb;
import 'app_focus_mode.dart' show AppFocusMode, AppFocusToggle;
import 'app_keyboard.dart' show AppCommandPaletteScope;
import 'app_motion_kit.dart';
import 'app_tokens.dart';
import 'app_responsive.dart';
import 'app_shell_nav.dart';
import 'calendar_entry.dart';
import '../features/shared/rag/app_assistant.dart' show AppAssistant, appAssistantFeatureKey;
import 'chrome_button.dart';
import 'app_settings.dart' show appRoleLabel;
import '../core/display/app_fonts.dart' show AppFonts;

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

/// What a tab's count means, and so its colour (system.md §2): [attention] — things waiting on the person — is the
/// danger red; [reward] — what they earned (a new badge, points) — is the gold tint. Gold is never an alarm.
enum ShellBadgeTone { attention, reward }

class DashboardItem {
  DashboardItem(
    this.icon,
    this.selectedIcon,
    this.label,
    this.onRefresh,
    this.screen, {
    this.badge = 0,
    this.badgeTone = ShellBadgeTone.attention,
    this.attentionKeys = const [],
    this.attentionOrgId,
  });

  final IconData icon, selectedIcon;
  final String label;
  final Future<void> Function()? onRefresh;
  final Widget screen;

  /// Count the attention feed does not carry (0 = none). Set by the dashboard from its own provider.
  int badge;

  /// The meaning of the count, which picks its colour.
  final ShellBadgeTone badgeTone;

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
    // a count that changes pops once (D-581)
    if (item.attentionKeys.isEmpty) return AppBump(trigger: item.badge, child: builder(context, item.badge));
    return ListenableBuilder(
      listenable: source(),
      builder: (context, _) {
        final n = item.badge + _live();
        return AppBump(trigger: n, child: builder(context, n));
      },
    );
  }
}

String _badgeText(int n) => n > 99 ? '99+' : '$n';

/// The desktop sidebar folded to its icons (D-631): one switch for the session, flipped by the sidebar's own button.
/// Presentation only: the tabs, their order and their callbacks are the same either way.
final ValueNotifier<bool> appSidebarCollapsed = ValueNotifier(false);

/// The tinted pill of an open tab and the ink on it (sidebar, rail, phone bar).
({Color fill, Color ink}) _openTabColors(BuildContext context) {
  final c = context.colors;
  // an opaque tint of the primary over the paper (a translucent fill would fool the contrast check)
  final fill = Color.lerp(c.cardBg, c.primary, c.isDark ? 0.22 : 0.12)!;
  return (fill: fill, ink: c.blockAccentInk(c.primary, fill));
}

/// The shell's own measures, the few the tokens do not name.
abstract final class _ShellMetrics {
  /// The sidebar's brand mark and the user chip's avatar.
  static const double mark = 36;

  /// The rail (NavigationRail.minWidth); its end hairline makes the 67 px of side chrome the pages are told about.
  static const double railW = 66;

  /// The top bar of the wide / rail shells: a touch target with the bar's own breathing room.
  static const double barH = AppTouch.min + AppSpace.lg;

  /// The slim bar focus mode leaves.
  static const double focusBarH = AppTouch.primary;

  /// The emerald pill under the open tab's icon on the phone bar (the Material 3 indicator measure) and, narrower,
  /// on the rail, where each tab is a [railCellH] tall cell.
  static const double pillW = 56;
  static const double pillH = 32;
  static const double railPillW = 48;
  static const double railCellH = AppTouch.min + AppSpace.xs;
}

/// A tab's count as a small pill in the colour of its meaning (the open tab is a light tint, so the count keeps its
/// colour there too); [ring] (the surface under it) separates a pill that overlaps an icon.
class _CountPill extends StatelessWidget {
  const _CountPill(this.n, {required this.tone, this.ring});

  final int n;
  final ShellBadgeTone tone;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color fill, Color ink) = switch (tone) {
      ShellBadgeTone.attention => (c.danger, c.onHero),
      ShellBadgeTone.reward => (c.blockGold, c.blockAccentInk(c.accent2, c.blockGold)),
    };
    return Container(
      constraints: const BoxConstraints(minWidth: AppIconSize.md, minHeight: AppIconSize.md),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs + 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: ring == null ? null : Border.all(color: ring!, width: AppBorder.focus),
      ),
      child: Text(
        _badgeText(n),
        maxLines: 1,
        style: AppType.overline(context).copyWith(color: ink, height: 1.1, letterSpacing: 0),
      ),
    );
  }
}

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

  /// The labels built in the shell's first frame: they appear with the page; a tab opened later enters (D-580).
  Set<String>? _initial;

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
    _initial ??= {..._visited};
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
                  // the tab coming to the front fades in and rises 8 px (D-580)
                  child: AppTabEntrance(
                    active: i == current,
                    enterNow: !_initial!.contains(items[i].label),
                    child: _TabNavigatorHost(tab: _tabs.tab(items[i].label), screen: items[i].screen, active: i == current),
                  ),
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
    appSidebarCollapsed.addListener(_changed);
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
    appSidebarCollapsed.removeListener(_changed);
    AppNavigator.requestedTab.removeListener(_onTabRequested);
    AppShellNav.unregister(_tabs);
    _tabs.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  int get _current => widget.items.isEmpty ? 0 : widget.currentIndex.clamp(0, widget.items.length - 1);

  Widget _shellTools(BuildContext context) => _GlobalTools(unread: widget.unreadCount);

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
            AppShellKind.wide => appSidebarCollapsed.value ? _ShellMetrics.railW + AppBorder.hairline : Breakpoints.sidebarW,
            AppShellKind.rail => _ShellMetrics.railW + AppBorder.hairline,
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
    final barAvailable = widget.showTopBar && !full && kind != AppShellKind.mobile;
    return ShellScope(
      tabs: _tabs,
      child: ShellChrome(
        barShown: barAvailable && !_tabs.activeCanPop,
        tools: barAvailable ? _shellTools : null,
        child: PopScope<Object?>(
          canPop: back == ShellBack.leave,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _onBack();
          },
          child: shell,
        ),
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

/// The labelled way out of focus mode, on the slim bar it leaves, in the corner where it was entered: a paper
/// pill with a hairline (the canvas bar has no hero colour for a glass button to sit on).
class _FocusExitPill extends StatelessWidget {
  const _FocusExitPill();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      key: const ValueKey('app.focus.exit'),
      color: c.cardBg,
      shape: StadiumBorder(side: BorderSide(color: c.divider, width: AppBorder.hairline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: AppFocusMode.instance.toggle,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.fullscreen_exit_rounded, size: AppIconSize.md, color: c.textDark),
              const SizedBox(width: AppSpace.xs),
              Text('ds_focus_exit'.tr, maxLines: 1, style: AppType.label(context).copyWith(color: c.textDark)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDE LAYOUT (>= Breakpoints.desktop) — paper sidebar + canvas top bar
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
    final user = context.watch<MyAuthProvider>().currentUser;
    final current = currentIndex.clamp(0, dashboardItems.length - 1);
    final barShown = showTopBar && !(ShellScope.maybeOf(context)?.activeCanPop ?? false);
    return BasePage(
      child: Row(
        children: [
          _FocusFold(
            focus: focus,
            child: ValueListenableBuilder<bool>(
              valueListenable: appSidebarCollapsed,
              builder: (context, collapsed, _) => collapsed
                  ? _RailColumn(
                      items: dashboardItems, current: current, onTap: onTap, user: barShown ? null : user, foldable: true)
                  : _Sidebar(items: dashboardItems, current: current, onTap: onTap, user: barShown ? null : user),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                if (barShown)
                  _TopBar(
                    title: dashboardItems[current].label.tr,
                    unread: unreadCount,
                    onRefresh: dashboardItems[current].onRefresh,
                    helpPageId: shellHelpPageId(context, dashboardItems[current].label, current == 0),
                    focus: focus,
                    user: user,
                  ),
                if (barShown && !focus) _PageHead(items: dashboardItems, current: current),
                // the top bar already sits under the status bar: the pages below must not pad for it again
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: barShown,
                    child: body ?? LazyTabStack(index: current, items: dashboardItems),
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

/// The paper column: the wordmark and the fold button, the tabs in groups, the signed-in person (only when no top bar
/// carries them). One warm hairline on its end side.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items, required this.current, required this.onTap, required this.user});

  final List<DashboardItem> items;
  final int current;
  final ValueChanged<int> onTap;
  final UserModel? user;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: Breakpoints.sidebarW,
      decoration: BoxDecoration(
        color: c.cardBg,
        border: BorderDirectional(end: BorderSide(color: c.divider, width: AppBorder.hairline)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: _ShellMetrics.barH,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpace.md, end: AppSpace.xxs),
              child: Row(children: [
                const Expanded(child: _Wordmark()),
                const _FoldButton(),
              ]),
            ),
          ),
          Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
          Expanded(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'shell_navigation'.tr,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.md, AppSpace.sm, AppSpace.md),
                children: [
                  // the home tab under "General", the rest under "Workspace" (the reference's grouped menu, from the
                  // tabs the role already has — no new destination)
                  _GroupHeader(title: 'shell_group_general'.tr, subtitle: 'shell_group_general_sub'.tr),
                  for (int i = 0; i < items.length; i++) ...[
                    if (i == 1) ...[
                      const SizedBox(height: AppSpace.md),
                      _GroupHeader(title: 'shell_group_workspace'.tr, subtitle: 'shell_group_workspace_sub'.tr),
                    ],
                    _SidebarTile(item: items[i], selected: current == i, onTap: () => onTap(i)),
                  ],
                ],
              ),
            ),
          ),
          if (user != null) ...[
            Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
            UserChipButton(user: user!, showLabel: true),
          ],
        ],
      ),
    );
  }
}

/// A group of sidebar tabs: a soft tinted plate with the group's title in the primary ink and one quiet line.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final plate = Color.lerp(c.cardBg, c.primary, c.isDark ? 0.12 : 0.06)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        header: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          decoration: BoxDecoration(color: plate, borderRadius: AppRadius.controlAll),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.row(context).copyWith(color: c.blockAccentInk(c.primary, plate), fontWeight: FontWeight.w600)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.blockMuted(plate))),
          ]),
        ),
      ),
    );
  }
}

/// Folds the desktop sidebar to its icons, or opens it again: a ghost button.
class _FoldButton extends StatelessWidget {
  const _FoldButton();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: appSidebarCollapsed,
        builder: (context, collapsed, _) => ChromeGhost(
          child: ChromeIconButton(
            key: const ValueKey('app.shell.fold'),
            icon: collapsed ? Icons.menu_rounded : Icons.menu_open_rounded,
            label: collapsed ? 'shell_expand'.tr : 'shell_collapse'.tr,
            onTap: () => appSidebarCollapsed.value = !collapsed,
          ),
        ),
      );
}

/// The brand mark: a small emerald tile with the school glyph.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: _ShellMetrics.mark,
      height: _ShellMetrics.mark,
      decoration: BoxDecoration(color: c.primary, borderRadius: AppRadius.chipAll),
      child: Icon(Icons.school_rounded, color: c.onHero, size: AppIconSize.md),
    );
  }
}

/// ONE app name, the one the super admin sets ("About us"), in the editorial face, with its tagline under it.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        const _AppMark(),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppIdentity.instance.name.isNotEmpty ? AppIdentity.instance.name : 'NextBrain',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.section(context),
              ),
              Text(
                AppIdentity.instance.tagline.isNotEmpty ? AppIdentity.instance.tagline : 'app_tagline'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(color: c.textLight),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The signed-in user at the bottom of the sidebar / rail — opens the account editor. A quiet row on paper; on a
/// hero band ([ChromeBar]) the avatar turns to glass like the chrome buttons beside it.
class UserChipButton extends StatelessWidget {
  final UserModel user;
  final bool showLabel;

  /// With [showLabel]: the chip is as wide as its name (up to the width it is given) instead of filling it — the
  /// top bar's person chip (D-631).
  final bool hugLabel;

  const UserChipButton({super.key, required this.user, required this.showLabel, this.hugLabel = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = user.name;
    final initial = name.isNotEmpty ? name[0] : '؟';
    final image = user.imageUrl;
    final onBar = ChromeBar.of(context);
    final avatar = Container(
      width: _ShellMetrics.mark,
      height: _ShellMetrics.mark,
      decoration: BoxDecoration(
        color: onBar ? c.heroGlass : c.primary,
        shape: BoxShape.circle,
        border: onBar ? Border.all(color: c.heroGlassBorder, width: AppBorder.hairline) : null,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: image != null && image.isNotEmpty
          ? AppNetworkImage(url: image, enableFullscreen: false, heroTag: 'user_logo-dashboard')
          // a name is in whichever language the person typed it: the other language's font draws it too
          : Text(initial,
              style: AppType.row(context)
                  .copyWith(color: c.onHero, fontWeight: FontWeight.w600, fontFamilyFallback: AppFonts.fallback)),
    );
    return Padding(
      padding: showLabel
          ? const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.sm)
          : const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Semantics(
        button: true,
        label: name,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.controlAll,
            hoverColor: onBar ? c.heroGlass : c.inputBg,
            focusColor: onBar ? c.heroGlass : c.inputBg,
            onTap: () => AppShellNav.navigatorFor(context).push(MaterialPageRoute(builder: (_) => EditAccountScreen())),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: showLabel ? AppSpace.xs : AppSpace.xxs, vertical: AppSpace.xxs),
                child: Row(
                  mainAxisSize: showLabel && !hugLabel ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    avatar,
                    if (showLabel) ...[
                      const SizedBox(width: AppSpace.sm),
                      Flexible(
                        fit: hugLabel ? FlexFit.loose : FlexFit.tight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.row(context)
                                  .copyWith(color: onBar ? c.onHero : c.textDark, fontFamilyFallback: AppFonts.fallback),
                            ),
                            Text(
                              appRoleLabel(user.role),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.meta(context).copyWith(color: onBar ? c.onHeroMuted : c.textLight),
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
        ),
      ),
    );
  }
}

// ── Sidebar tile ──────────────────────────────────────────────────────────────

/// One tab of the sidebar: a 48 px row; the open one is an emerald pill with on-hero ink.
class _SidebarTile extends StatelessWidget {
  final DashboardItem item;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarTile({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final open = _openTabColors(context);
    final ink = selected ? open.ink : c.textDark;
    // a real button for screen readers and the keyboard (H12): focusable, Enter / Space, selected state read out
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs / 2),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
            hoverColor: c.inputBg,
            focusColor: c.inputBg,
            child: AnimatedContainer(
              duration: AppMotion.of(context).fast,
              curve: AppMotion.curve,
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              decoration: BoxDecoration(
                color: selected ? open.fill : open.fill.withValues(alpha: 0),
                borderRadius: AppRadius.controlAll,
              ),
              child: Row(
                children: [
                  Icon(selected ? item.selectedIcon : item.icon, color: selected ? open.ink : c.textMedium, size: AppIconSize.md),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      item.label.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.row(context).copyWith(color: ink, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                    ),
                  ),
                  ShellBadge(
                    item: item,
                    builder: (context, n) => n <= 0
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsetsDirectional.only(start: AppSpace.xs),
                            child: _CountPill(n, tone: item.badgeTone),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
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

/// The paper band over a tab's first page (D-631): the search box at the start (when the screen has a palette), the
/// chrome buttons as ghosts and the signed-in person at the end; the tab's title moved to [_PageHead] under it.
class _TopBar extends StatelessWidget {
  final String title;
  final int unread;
  final Future<void> Function()? onRefresh;
  final String? helpPageId;

  /// Focus mode: a slim bar with the title and the way out, in the corner where focus mode was entered.
  final bool focus;

  /// The signed-in person drawn at the end (avatar, name, role); null = none (a guest, a test).
  final UserModel? user;

  const _TopBar({
    required this.title,
    required this.unread,
    required this.onRefresh,
    this.helpPageId,
    this.focus = false,
    this.user,
  });

  /// From this bar width the person's name and role show beside the avatar.
  static const double _userLabelFrom = 900;

  /// The person's chip with its name and role.
  static const double _userW = 208;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // focus mode keeps the slim canvas bar it always had: the title and the way out
    if (focus) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'shell_top_bar'.tr,
        child: SizedBox(
          height: _ShellMetrics.focusBarH,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpace.lg, end: AppSpace.md),
            child: Row(children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              const _FocusExitPill(),
            ]),
          ),
        ),
      );
    }
    final palette = AppCommandPaletteScope.openerOf(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'shell_top_bar'.tr,
      child: Container(
        height: _ShellMetrics.barH,
        decoration: BoxDecoration(
          color: c.cardBg,
          border: Border(bottom: BorderSide(color: c.divider, width: AppBorder.hairline)),
        ),
        padding: const EdgeInsetsDirectional.only(start: AppSpace.lg, end: AppSpace.md),
        child: LayoutBuilder(builder: (context, box) {
          final withName = user != null && box.maxWidth >= _userLabelFrom;
          return ChromeGhost(
            // the search at the start, the buttons at the end, whatever room is left between them
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              // the search box opens the screen's own Ctrl+K palette (the same thing the shortcut does)
              if (palette != null)
                Flexible(
                  flex: 3,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: AppWidth.form.max / 2 + AppSpace.xxl),
                    child: _TopSearch(onTap: palette),
                  ),
                )
              else
                const SizedBox.shrink(),
              const SizedBox(width: AppSpace.md),
              // the buttons keep their size and sit at the end; only a squeezed shell scales them down
              Flexible(
                flex: 4,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (onRefresh != null) _ChromeRefresh(onRefresh: onRefresh!),
                    _GlobalTools(unread: unread),
                    if (helpPageId != null) HelpInfoButton(pageId: helpPageId!),
                    const AppFocusToggle(),
                    if (user != null) ...[
                      Container(
                        width: AppBorder.hairline,
                        height: AppTouch.min - AppSpace.md,
                        margin: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                        color: c.divider,
                      ),
                      if (withName)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: _userW),
                          child: UserChipButton(user: user!, showLabel: true, hugLabel: true),
                        )
                      else
                        UserChipButton(user: user!, showLabel: false),
                    ],
                  ]),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }
}

/// The top bar's search box: a quiet field-shaped button with the shortcut hint, opening the screen's palette.
class _TopSearch extends StatelessWidget {
  const _TopSearch({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hint = 'shell_search_hint'.tr;
    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: true,
      child: Material(
        color: c.inputBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.controlAll,
          side: BorderSide(color: c.divider, width: AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('app.shell.search'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xxs),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              child: Row(children: [
                Icon(Icons.search_rounded, size: AppIconSize.md, color: c.textMedium),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textLight)),
                ),
                const SizedBox(width: AppSpace.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
                  decoration: BoxDecoration(
                    color: c.cardBg,
                    borderRadius: AppRadius.chipAll,
                    border: Border.all(color: c.divider, width: AppBorder.hairline),
                  ),
                  child: Text('Ctrl K',
                      maxLines: 1,
                      textDirection: TextDirection.ltr,
                      style: AppType.overline(context).copyWith(color: c.textMedium, letterSpacing: 0)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page head under the top bar: the open tab's title in the editorial face at the start, and on wide screens its
/// breadcrumb at the end (home · the home tab · this tab) — orientation from the tabs the shell already has.
class _PageHead extends StatelessWidget {
  const _PageHead({required this.items, required this.current});

  final List<DashboardItem> items;
  final int current;

  /// From this width the breadcrumb shows beside the title.
  static const double _crumbFrom = 640;

  @override
  Widget build(BuildContext context) {
    final title = items[current].label.tr;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xxs),
      child: LayoutBuilder(builder: (context, box) {
        final crumb = box.maxWidth >= _crumbFrom;
        return Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
            ),
          ),
          if (crumb) ...[
            const SizedBox(width: AppSpace.md),
            Flexible(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: AppBreadcrumb(parts: [
                  if (current != 0) items[0].label.tr,
                  title,
                ]),
              ),
            ),
          ],
        ]);
      }),
    );
  }
}

/// An icon column (the rail, and the desktop sidebar folded): the brand mark, the fold button when [foldable], the
/// tabs as icon cells with the open one's tinted pill, the person at the bottom when no top bar carries them.
class _RailColumn extends StatelessWidget {
  const _RailColumn({required this.items, required this.current, required this.onTap, this.user, this.foldable = false});

  final List<DashboardItem> items;
  final int current;
  final ValueChanged<int> onTap;
  final UserModel? user;
  final bool foldable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: _ShellMetrics.railW + AppBorder.hairline,
      decoration: BoxDecoration(
        color: c.cardBg,
        border: BorderDirectional(end: BorderSide(color: c.divider, width: AppBorder.hairline)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xs),
            child: foldable ? const _FoldButton() : const _AppMark(),
          ),
          Expanded(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'shell_navigation'.tr,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (int i = 0; i < items.length; i++)
                    _RailTile(item: items[i], selected: current == i, onTap: () => onTap(i)),
                ],
              ),
            ),
          ),
          if (user != null) UserChipButton(user: user!, showLabel: false),
        ],
      ),
    );
  }
}

/// The app-wide actions, in one order on every header: calendar, messages, assistant, notifications.
class _GlobalTools extends StatelessWidget {
  const _GlobalTools({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (!GuestState.active) const CalendarIcon(),
        if (!GuestState.active) const ChatEntryIcon(),
        if (!GuestState.active && !AppConfig.disableList.contains(appAssistantFeatureKey))
          ChromeIconButton(
            icon: Icons.auto_awesome_rounded,
            label: 'assistant_entry_title'.tr,
            onTap: AppAssistant.openPanel,
          ),
        NotificationIcon(unreadCount: unread),
      ]);
}

/// Refresh, the same paper square as its neighbours; the icon turns into a spinner while it runs.
class _ChromeRefresh extends StatefulWidget {
  const _ChromeRefresh({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  State<_ChromeRefresh> createState() => _ChromeRefreshState();
}

class _ChromeRefreshState extends State<_ChromeRefresh> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ChromeIconButton(icon: Icons.refresh_rounded, label: 'refresh'.tr, busy: _busy, onTap: _run);
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
// RAIL LAYOUT (Breakpoints.mobile … desktop) — paper rail + canvas top bar
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
    final user = context.watch<MyAuthProvider>().currentUser;
    final current = currentIndex.clamp(0, dashboardItems.length - 1);
    final barShown = showTopBar && !(ShellScope.maybeOf(context)?.activeCanPop ?? false);
    return BasePage(
      child: Row(
        children: [
          _FocusFold(
            focus: focus,
            child: _RailColumn(items: dashboardItems, current: current, onTap: onTap, user: barShown ? null : user),
          ),
          Expanded(
            child: Column(
              children: [
                if (barShown)
                  _TopBar(
                    title: dashboardItems[current].label.tr,
                    unread: unreadCount,
                    onRefresh: dashboardItems[current].onRefresh,
                    helpPageId: shellHelpPageId(context, dashboardItems[current].label, current == 0),
                    focus: focus,
                    user: user,
                  ),
                if (barShown && !focus) _PageHead(items: dashboardItems, current: current),
                // the top bar already sits under the status bar: the pages below must not pad for it again
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: barShown,
                    child: body ?? LazyTabStack(index: current, items: dashboardItems),
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

/// One rail tab: an icon-only cell (the label is its tooltip and its screen-reader name) with the pill of the open
/// tab, a hand-drawn rail so the pill, the count and the 48 px target match the phone bar exactly.
class _RailTile extends StatelessWidget {
  const _RailTile({required this.item, required this.selected, required this.onTap});

  final DashboardItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: item.label.tr,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label.tr,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.controlAll,
            hoverColor: c.inputBg,
            focusColor: c.inputBg,
            child: SizedBox(
              width: _ShellMetrics.railW,
              height: _ShellMetrics.railCellH,
              child: Center(child: _TabIconPill(item: item, active: selected, width: _ShellMetrics.railPillW)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The icon of a rail / phone tab on its pill — emerald with on-hero ink when the tab is open, bare otherwise — and
/// its count on the top-end corner, ringed with the surface under it so it reads over the icon.
class _TabIconPill extends StatelessWidget {
  const _TabIconPill({required this.item, required this.active, required this.width});

  final DashboardItem item;
  final bool active;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final open = _openTabColors(context);
    return ShellBadge(
      item: item,
      builder: (context, n) => Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: AppMotion.of(context).fast,
            curve: AppMotion.curve,
            width: width,
            height: _ShellMetrics.pillH,
            decoration: BoxDecoration(
              color: active ? open.fill : open.fill.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Center(
              child: Icon(
                active ? item.selectedIcon : item.icon,
                size: AppIconSize.lg,
                color: active ? open.ink : c.textMedium,
              ),
            ),
          ),
          // over the icon's top-end quarter, the Material badge offset, so the glyph stays readable under it
          if (n > 0)
            PositionedDirectional(
              top: -(AppSpace.xxs + 2),
              end: -AppSpace.xxs,
              child: _CountPill(n, tone: item.badgeTone, ring: c.cardBg),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE LAYOUT (< Breakpoints.mobile) — paper bottom bar
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

/// Paper with one hairline on top; no shadow — the bar is a surface the page scrolls under, not something afloat. The
/// open tab's icon sits on a tinted pill and its label turns to the primary ink (D-631).
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
        border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xs),
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

/// One phone tab: the icon on an emerald pill when open, its label under it. The label always shows; the open
/// tab's is heavier and in the primary ink. The whole column is the target (≥ 48 px).
class _BottomTab extends StatelessWidget {
  const _BottomTab({required this.item, required this.active, required this.onTap});

  final DashboardItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TabIconPill(item: item, active: active, width: _ShellMetrics.pillW),
              const SizedBox(height: AppSpace.xxs),
              Text(
                item.label.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BottomNavMetrics.labelStyle(context, active: active),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The phone bar's height (its rows + the safe area under it), for what floats above it (the app assistant).
class BottomNavMetrics {
  BottomNavMetrics._();

  /// The size and line of a tab's label (the overline role, tracking off: spaced Arabic loses its joins).
  static const double _labelSize = 11;
  static const double _labelLine = 1.3;

  static TextStyle labelStyle(BuildContext context, {required bool active}) {
    final c = context.colors;
    return AppType.overline(context).copyWith(
      fontSize: _labelSize,
      height: _labelLine,
      letterSpacing: 0,
      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
      color: active ? c.blockAccentInk(c.primary, c.cardBg) : c.textMedium,
    );
  }

  /// 8 + 32 (the icon pill) + 4 + the label line + 8, plus the home-indicator inset.
  static double heightFor(BuildContext context) {
    final label = MediaQuery.textScalerOf(context).scale(_labelSize) * _labelLine;
    return AppSpace.xs + _ShellMetrics.pillH + AppSpace.xxs + label + AppSpace.xs + MediaQuery.paddingOf(context).bottom;
  }
}
