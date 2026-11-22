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
//   Pins and colour boxes (D-1170, shell_pins.dart): any page opened inside a tab can be pinned from its header; on
//       the sidebar / rail each pin is an entry under "Pinned" after the role's tabs (AppShell selects it itself, the
//       dashboard's index never sees it), on phones a strip at the top of Home. A long press on a tab (or Customize
//       tabs) gives each tab a colour box. `AppShell(pinScope:)` names the dashboard the pins belong to.
//
// The look (floating chrome, D-648, after the Spike admin reference): the page is the canvas; the sidebar is a white
// rounded card ([ChromeCard]) inset from the window by the page gutter — the wordmark on top, the tabs in groups under
// small muted labels (a one-tab group named like its tab draws none), the open tab a tinted pill in the primary ink
// with its count, the signed-in person in a tinted box at the foot, and a button folds it to its icons
// (appSidebarCollapsed); the top bar is a second floating card of one height on every shell page: the tab's title
// (the home it belongs to as one small line above it), the search pill (when the screen has a Ctrl+K palette), ghost
// icon buttons with small counts and the avatar. The phone's bottom bar is paper with a hairline, the open tab's icon
// on a tinted pill over its label in the primary ink.
// D-649 (the brand gradient layer): the sidebar (and the rail) is no longer white — it is a floating rounded card in
// the deep green gradient (primary_dark → a deeper forest, AppBrandLayer.sidebar) with a faint lattice, its text and
// icons in the on-hero roles, the open tab a soft glass pill with a 3 px gold bar on its start edge and cream ink, the
// person in a glass box; counts stay red. The top bar stays a white card (the intended contrast), its avatar ringed
// in the brand gradient; the phone bar stays light, its open tab on a brand-gradient pill.
// D-1340 (the phone bar's slots): the bar draws at most BottomNavMetrics.maxSlots (5) slots. More items than that:
// items sharing a DashboardItem.mobileGroup fold into ONE slot at the first member's place (a group with one visible
// member draws that tab itself); still too many, slots 5… fold into the built-in "More" group. A group slot is active
// while a member is open, its count is the members' sum, and a tap opens a sheet of its members ([ShellGroupSheet]).
// The items, their indexes, LazyTabStack and the wide shells do not change: only the phone bar draws slots.
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
import 'package:flutter_education_app/features/help/help_info_button.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/profile/update_account_widget.dart';
import '../utils/widget/app_navigator.dart' show AppNavigator;
import '../utils/widget/app_network_image.dart';
import '../utils/widget/base_page.dart';
import 'app_focus_mode.dart' show AppFocusMode, AppFocusToggle;
import 'app_gradients.dart' show AppBrandInk, AppBrandLayer, AppBrandPanel, AppGradientIcon, BrandInk;
import 'app_keyboard.dart' show AppCommandPaletteScope;
import 'app_motion_kit.dart';
import 'listenable_selector.dart';
import 'app_tokens.dart';
import 'app_responsive.dart';
import 'app_shell_nav.dart';
import 'shell_pins.dart';
import 'calendar_entry.dart';
import 'package:flutter_education_app/features/rag/app_assistant.dart' show AppAssistant, appAssistantFeatureKey;
import 'chrome_button.dart';
import 'sync_status_chip.dart' show SyncStatusChip;
import 'app_settings.dart' show appRoleLabel;
import 'app_kit.dart' show showAppSheet;
import 'app_sheet_header.dart' show AppSheetHeader;
import '../core/display/app_fonts.dart' show AppFonts;

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

/// What a tab's count means, and so its colour (system.md §2): [attention] — things waiting on the person — is the
/// danger red; [reward] — what they earned (a new badge, points) — is the gold tint. Gold is never an alarm.
enum ShellBadgeTone { attention, reward }

/// A group of tabs that share ONE slot on the phone bar when the bar would hold more than
/// [BottomNavMetrics.maxSlots] (D-1340). [label] is a translation key. Groups are equal by [id].
@immutable
class ShellMobileGroup {
  const ShellMobileGroup(this.id, this.icon, this.selectedIcon, this.label);

  final String id;
  final IconData icon, selectedIcon;
  final String label;

  /// The fallback every role gets (rule 3): the slots past the fourth.
  static const more = ShellMobileGroup('more', Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'more');

  @override
  bool operator ==(Object other) => other is ShellMobileGroup && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

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
    this.id,
    this.mobileGroup,
    this.hint,
  });

  final IconData icon, selectedIcon;
  final String label;

  /// The phone bar's group this tab folds into when the bar is full (D-1340); null = a slot of its own.
  final ShellMobileGroup? mobileGroup;

  /// One line under the label in a group's sheet (a translation key); null = none.
  final String? hint;

  /// The tab's identity in the shell (its back stack, its URL `<home>/<tab>`): [label] unless set (a pinned page's
  /// `pin_…`, D-1170).
  final String? id;
  String get tabId => id ?? label;

  /// A stable key for what the person chooses about this tab (its colour, D-1170) when [label] is a translated text
  /// that changes with the language (the organization dashboards set their section keys here).
  String? prefKey;
  String get colorKey => prefKey ?? tabId;
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
    // rebuilds when this item's count moves, not on every answer of the feed (UX v3 phase 5)
    return ListenableSelector<int>(
      listenable: source(),
      select: () => item.badge + _live(),
      builder: (context, n) => AppBump(trigger: n, child: builder(context, n)),
    );
  }
}

String _badgeText(int n) => n > 99 ? '99+' : '$n';

/// How far the floating sidebar and top bar sit in from the window's edges (D-648): the page gutter of [width].
double shellInset(double width) => AppSpace.gutter(width);

/// The desktop sidebar folded to its icons (D-631): one switch for the session, flipped by the sidebar's own button.
/// Presentation only: the tabs, their order and their callbacks are the same either way.
final ValueNotifier<bool> appSidebarCollapsed = ValueNotifier(false);


/// The shell's own measures, the few the tokens do not name.
abstract final class _ShellMetrics {
  /// The sidebar's brand mark and the user chip's avatar.
  static const double mark = 36;

  /// The rail (NavigationRail.minWidth); its end hairline makes the 67 px of side chrome the pages are told about.
  static const double railW = 66;

  /// The top bar of the wide / rail shells, the sidebar's head and every pushed page's bar: one height.
  static const double barH = ChromeCard.barHeight;

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
      ShellBadgeTone.attention => (c.dangerBase, c.onHero),
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
    _visited.add(items[current].tabId);
    _initial ??= {..._visited};
    _tabs.homeLabel = items.first.tabId; // the home's own URL; another tab is `<home>/<tab>` (D-170)
    _tabs.setActive(items[current].tabId);
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
          _visited.contains(items[i].tabId)
              ? KeyedSubtree(
                  key: ValueKey('tab:${items[i].tabId}'),
                  // the tab coming to the front fades in and rises 8 px (D-580)
                  child: AppTabEntrance(
                    active: i == current,
                    enterNow: !_initial!.contains(items[i].tabId),
                    child: _TabNavigatorHost(tab: _tabs.tab(items[i].tabId), screen: items[i].screen, active: i == current),
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
    this.pinScope,
  });

  final double width;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<DashboardItem> items;

  /// Which dashboard the pins and tab colours belong to (D-1170): `org<id>` for an organization's; null = the
  /// shell's own route ('/dashboard', '/teacher_dashboard', …).
  final String? pinScope;

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

  /// This dashboard's pins and tab colours (D-1170); null for a guest.
  ShellPinScope? _pins;

  /// The pinned page on screen instead of the dashboard's own tab (its tab id); null = [AppShell.currentIndex].
  /// Only the sidebar / rail have pin entries; the dashboard's index never sees them.
  String? _pinTab;

  /// What the last build drew: its tabs (the role's, then the pins) and the open one.
  List<DashboardItem> _shown = const [];
  int _cur = 0;

  @override
  void initState() {
    super.initState();
    AppShellNav.register(_tabs);
    _tabs.addListener(_changed);
    _tabs.onPinnedRootPop = _goHome;
    AppFocusMode.instance.addListener(_changed);
    appSidebarCollapsed.addListener(_changed);
    AppFocusMode.instance.ensureLoaded();
    AppNavigator.requestedTab.addListener(_onTabRequested);
    // a request made before this shell existed (a `<home>/<tab>` URL, a refresh)
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTabRequested());
  }

  /// A tab asked for by its key (`/admin_dashboard/users`, D-170): every role's home switches to it. The dashboards
  /// that know other keys ('profile', 'last') answer those themselves. A pinned page's key (`pin_…`, a refreshed
  /// URL) is answered once the pins are read.
  void _onTabRequested() {
    final id = AppNavigator.requestedTab.value;
    if (id == null || !mounted) return;
    if (isShellPinTab(id)) {
      final pins = _pins;
      if (pins == null || !pins.loaded) return;
      AppNavigator.requestedTab.value = null; // consumed
      if (pins.pins.any((p) => p.tabId == id)) setState(() => _pinTab = id);
      return;
    }
    final i = widget.items.indexWhere((e) => e.tabId == id);
    if (i < 0) return;
    AppNavigator.requestedTab.value = null; // consumed
    if (_pinTab != null) setState(() => _pinTab = null);
    if (i != widget.currentIndex) widget.onTap(i);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tabs.hostRoute = ModalRoute.of(context);
    _bindPins();
  }

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    // the dashboard moved to one of its tabs (a deep link, its own code): that tab shows, not a pin
    if (old.currentIndex != widget.currentIndex) _pinTab = null;
    if (old.pinScope != widget.pinScope) _bindPins();
  }

  /// The scope of this person on this dashboard (`<user>|<dashboard>`); none for a guest.
  void _bindPins() {
    if (GuestState.active) {
      _pins?.removeListener(_pinsChanged);
      _pins = _tabs.pins = null;
      return;
    }
    int? uid;
    try {
      uid = Provider.of<MyAuthProvider>(context, listen: false).currentUser?.id;
    } on ProviderNotFoundException {
      uid = null;
    }
    final key = '${uid ?? 0}|${widget.pinScope ?? _tabs.hostRoute?.settings.name ?? 'home'}';
    if (_pins?.key == key) return;
    _pins?.removeListener(_pinsChanged);
    _pins = ShellPins.scope(key)..addListener(_pinsChanged);
    _tabs.pins = _pins;
  }

  void _pinsChanged() {
    if (!mounted) return;
    final pins = _pins;
    if (_pinTab != null && !(pins?.pins.any((p) => p.tabId == _pinTab) ?? false)) _pinTab = null;
    setState(() {});
    _onTabRequested();
  }

  @override
  void dispose() {
    _pins?.removeListener(_pinsChanged);
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

  /// The pinned pages' entries, kept per pin so their tab keeps its page between builds.
  final Map<ShellPin, DashboardItem> _pinItems = {};

  /// The role's tabs, then (sidebar / rail only) one entry per pin.
  List<DashboardItem> _itemsFor(AppShellKind kind) {
    final pins = _pins;
    if (kind == AppShellKind.mobile || pins == null || pins.pins.isEmpty) return widget.items;
    _pinItems.removeWhere((p, _) => !pins.pins.contains(p));
    return [
      ...widget.items,
      for (final p in pins.pins)
        _pinItems.putIfAbsent(
          p,
          () => DashboardItem(Icons.push_pin_outlined, Icons.push_pin_rounded, p.title, null,
              ShellPinnedPage(scope: pins, pin: p), id: p.tabId),
        ),
    ];
  }

  int _currentIn(List<DashboardItem> items) {
    final pin = _pinTab;
    if (pin != null) {
      final i = items.indexWhere((e) => e.tabId == pin);
      if (i >= 0) return i;
    }
    return widget.items.isEmpty ? 0 : widget.currentIndex.clamp(0, widget.items.length - 1);
  }

  Widget _shellTools(BuildContext context) => _GlobalTools(unread: widget.unreadCount);

  void _onTap(int i) {
    if (i < 0 || i >= _shown.length) return;
    switch (shellTapAction(tapped: i, current: _cur, tabCanPop: _tabs.activeCanPop)) {
      case ShellTap.popToRoot:
        _tabs.popActiveToRoot();
      case ShellTap.switchTab:
      case ShellTap.none:
        final id = _shown[i].tabId;
        if (isShellPinTab(id)) {
          setState(() => _pinTab = id);
          return;
        }
        if (_pinTab != null) setState(() => _pinTab = null);
        widget.onTap(i);
    }
  }

  /// To the home tab (Back from a tab's first page, a pinned page that closed itself).
  void _goHome() {
    if (!mounted) return;
    if (_pinTab != null) setState(() => _pinTab = null);
    widget.onTap(0);
  }

  void _onBack() {
    switch (shellBackAction(tabCanPop: _tabs.activeCanPop, index: _cur)) {
      case ShellBack.popTab:
        _tabs.active?.navigator?.maybePop();
      case ShellBack.homeTab:
        _goHome();
      case ShellBack.leave:
        break;
    }
  }

  /// Customize tabs: a colour for each of the role's tabs and the pins.
  void _customize() {
    final pins = _pins;
    if (pins == null) return;
    showShellTabsSheet(context, scope: pins, tabs: [
      for (final it in widget.items) ShellTabEntry(tabId: it.colorKey, label: it.label.tr, icon: it.selectedIcon),
    ]);
  }

  /// Phones: a pin opens inside Home, over its first page (the bar keeps the role's tabs, D-1160).
  void _openPinHere(ShellPin pin) {
    final pins = _pins;
    final nav = _tabs.active?.navigator;
    if (pins == null || nav == null) return;
    nav.push(MaterialPageRoute<void>(builder: (_) => ShellPinnedPage(scope: pins, pin: pin)));
  }

  /// The pins' strip on a phone's Home, at its first page.
  Widget? _strip(AppShellKind kind, bool full) {
    final pins = _pins;
    if (kind != AppShellKind.mobile || full || pins == null || pins.pins.isEmpty) return null;
    if (_cur != 0 || _tabs.activeCanPop) return null;
    return ShellPinStrip(pins: pins.pins, colors: pins.state.colors, onOpen: _openPinHere, onCustomize: _customize);
  }

  @override
  Widget build(BuildContext context) {
    final kind = Breakpoints.shellFor(widget.width);
    final items = _shown = _itemsFor(kind);
    final current = _cur = _currentIn(items);
    final pinnedFrom = items.length > widget.items.length ? widget.items.length : null;
    final customize = _pins == null ? null : _customize;
    final body = LazyTabStack(key: _stackKey, index: current, items: items, tabs: _tabs);
    final full = _tabs.fullScreen;
    final focus = kind != AppShellKind.mobile && AppFocusMode.instance.value;
    _tabs.bottomBar = full || kind != AppShellKind.mobile ? 0 : BottomNavMetrics.heightFor(context);
    // the floating side card and its inset from the window edge (D-648)
    final inset = shellInset(widget.width);
    _tabs.sideChrome = full || focus
        ? 0
        : switch (kind) {
            AppShellKind.wide => (appSidebarCollapsed.value ? _ShellMetrics.railW : Breakpoints.sidebarW) + inset,
            AppShellKind.rail => _ShellMetrics.railW + inset,
            AppShellKind.mobile => 0,
          };
    final Widget shell = full
        ? ColoredBox(color: context.colors.background, child: body)
        : switch (kind) {
            AppShellKind.wide => WideShell(
                currentIndex: current, onTap: _onTap, dashboardItems: items, unreadCount: widget.unreadCount, body: body,
                showTopBar: widget.showTopBar, focus: focus, pinnedFrom: pinnedFrom, onCustomize: customize),
            AppShellKind.rail => RailShell(
                currentIndex: current, onTap: _onTap, dashboardItems: items, unreadCount: widget.unreadCount, body: body,
                showTopBar: widget.showTopBar, focus: focus, pinnedFrom: pinnedFrom, onCustomize: customize),
            AppShellKind.mobile => MobileShell(
                currentIndex: current, onTap: _onTap, dashboardItems: items, body: body,
                top: _strip(kind, full), onCustomize: customize),
          };
    final back = shellBackAction(tabCanPop: _tabs.activeCanPop, index: current);
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

  /// The first pinned page's index in [dashboardItems] (null: none), D-1170.
  final int? pinnedFrom;

  /// Customize tabs (a long press on a tab, the button under them); null = none.
  final VoidCallback? onCustomize;

  const WideShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.dashboardItems,
    required this.unreadCount,
    this.body,
    this.showTopBar = true,
    this.focus = false,
    this.pinnedFrom,
    this.onCustomize,
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
    final inset = shellInset(MediaQuery.sizeOf(context).width);
    return BasePage(
      child: Row(
        children: [
          _FocusFold(
            focus: focus,
            child: _SideInset(
              inset: inset,
              child: ValueListenableBuilder<bool>(
                valueListenable: appSidebarCollapsed,
                builder: (context, collapsed, _) => collapsed
                    ? _RailColumn(
                        items: dashboardItems, current: current, onTap: onTap, user: barShown ? null : user, foldable: true,
                        pinnedFrom: pinnedFrom, onCustomize: onCustomize)
                    : _Sidebar(
                        items: dashboardItems, current: current, onTap: onTap, user: user,
                        pinnedFrom: pinnedFrom ?? dashboardItems.length, onCustomize: onCustomize),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                if (barShown)
                  _TopBar(
                    title: dashboardItems[current].label.tr,
                    crumb: current == 0 ? null : dashboardItems[0].label.tr,
                    unread: unreadCount,
                    onRefresh: dashboardItems[current].onRefresh,
                    helpPageId: isShellPinTab(dashboardItems[current].tabId)
                        ? null
                        : shellHelpPageId(context, dashboardItems[current].label, current == 0),
                    focus: focus,
                    user: user,
                    inset: inset,
                  ),
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

/// The side card's place: inset from the window's start, top and bottom edges by the page gutter (D-648).
class _SideInset extends StatelessWidget {
  const _SideInset({required this.inset, required this.child});

  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsetsDirectional.only(start: inset, top: inset, bottom: inset),
        child: child,
      );
}

/// The floating sidebar card (D-648): the wordmark and the fold button, the tabs in groups under small muted labels,
/// and the signed-in person in a tinted box at the bottom. No rules inside: space and the labels group it.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.current,
    required this.onTap,
    required this.user,
    required this.pinnedFrom,
    this.onCustomize,
  });

  final List<DashboardItem> items;
  final int current;
  final ValueChanged<int> onTap;
  final UserModel? user;
  final int pinnedFrom;
  final VoidCallback? onCustomize;

  @override
  Widget build(BuildContext context) {
    // the home tab under "General", the rest under "Workspace" (from the tabs the role already has — no new
    // destination); a group of one tab named like its label draws no label (it would read the same word twice)
    final general = 'shell_group_general'.tr;
    final generalLabel = items.isNotEmpty && items.first.label.tr == general ? null : general;
    return SizedBox(
      width: Breakpoints.sidebarW,
      child: _BrandSideCard(
        child: Column(
          children: [
            SizedBox(
              height: _ShellMetrics.barH,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpace.md, end: AppSpace.xxs),
                child: Row(children: const [Expanded(child: _Wordmark()), _FoldButton()]),
              ),
            ),
            Expanded(
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                label: 'shell_navigation'.tr,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.md),
                  children: [
                    if (generalLabel != null) _GroupLabel(generalLabel, first: true),
                    for (int i = 0; i < items.length; i++) ...[
                      if (i == 1 && pinnedFrom > 1) _GroupLabel('shell_group_workspace'.tr),
                      if (i == pinnedFrom) _GroupLabel('shell_group_pinned'.tr),
                      _SidebarTile(
                          item: items[i], selected: current == i, onTap: () => onTap(i), onLongPress: onCustomize),
                    ],
                    if (onCustomize != null) _CustomizeTile(onTap: onCustomize!),
                  ],
                ),
              ),
            ),
            if (user != null) _SidebarUser(user: user!),
          ],
        ),
      ),
    );
  }
}

/// The sidebar / rail card (D-649): floating and rounded like the top bar (D-648), but filled with the deep green
/// brand gradient (primary_dark → a deeper forest) under a faint lattice. Its subtree is a [ChromeBar], so the fold
/// button and the person's avatar draw as glass and their text in the on-hero ink.
class _BrandSideCard extends StatelessWidget {
  const _BrandSideCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppBrandLayer.of(context);
    final radius = BorderRadius.circular(AppRadius.card);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: AppElevation.of(context, 2)),
      child: ClipRRect(
        borderRadius: radius,
        // D-650 r3: the 60 / 40 panel, top → bottom; each tab, label and the person box picks its ink from the
        // colour under it (AppBrandInk)
        child: AppBrandPanel(
          borderRadius: radius,
          // dark mode: a hairline of the ink so the deep card still has an edge on the dark canvas
          border: c.isDark ? Border.all(color: c.heroDivider, width: AppBorder.hairline) : null,
          child: Material(
            type: MaterialType.transparency,
            child: ChromeBar(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: l.sideInk),
                child: IconTheme.merge(data: IconThemeData(color: l.sideItem), child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A group's label: small muted text over its tabs (HOME / APPS in the reference) — a heading, never a plate that
/// reads as a button. English draws it in capitals; Arabic has none and keeps its letters joined (no tracking).
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.title, {this.first = false});

  final String title;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final latin = AppConfig.lang != 'ar';
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(AppSpace.md, first ? AppSpace.xxs : AppSpace.md, AppSpace.md, AppSpace.xs),
      child: AppBrandInk(
        builder: (context, k) => Semantics(
          header: true,
          child: Text(
            latin ? title.toUpperCase() : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.overline(context).copyWith(
              color: k.muted,
              fontWeight: FontWeight.w700,
              letterSpacing: latin ? 0.8 : 0,
            ),
          ),
        ),
      ),
    );
  }
}

/// The signed-in person at the foot of the sidebar: avatar, name and role in a softly tinted box (the account editor
/// on tap, as before).
class _SidebarUser extends StatelessWidget {
  const _SidebarUser({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    // a glass box on the brand gradient (D-649); at the foot it usually sits on the cream part (D-650 r3), so its
    // glass and its name / role inks are the ones for the colour under it
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, 0, AppSpace.sm, AppSpace.sm),
      child: AppBrandInk(
        builder: (context, k) => DecoratedBox(
          decoration: BoxDecoration(
            color: k.glass,
            borderRadius: AppRadius.controlAll,
            border: Border.all(color: k.glassBorder, width: AppBorder.hairline),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: UserChipButton(
                user: user, showLabel: true, surface: Color.alphaBlend(k.glass, k.surfaces.last), brandInk: k),
          ),
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

/// The brand mark: a small glass tile with the school glyph in cream, on the green sidebar / rail (D-649).
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final l = AppBrandLayer.of(context);
    return Container(
      width: _ShellMetrics.mark,
      height: _ShellMetrics.mark,
      decoration: BoxDecoration(
        color: l.sideActiveFill,
        borderRadius: AppRadius.chipAll,
        border: Border.all(color: l.sideGlassBorder, width: AppBorder.hairline),
      ),
      child: Icon(Icons.school_rounded, color: l.sideActiveInk, size: AppIconSize.md),
    );
  }
}

/// ONE app name, the one the super admin sets ("About us"), in the editorial face, with its tagline under it.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final l = AppBrandLayer.of(context);
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
                AppIdentity.instance.name.isNotEmpty ? AppIdentity.instance.name : 'Alfaheem',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.section(context).copyWith(color: l.sideInk),
              ),
              Text(
                AppIdentity.instance.tagline.isNotEmpty ? AppIdentity.instance.tagline : 'app_tagline'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(color: l.sideMuted),
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

  /// The tinted box the chip sits in (the sidebar's person card): the role line is inked to read on it; null = paper.
  final Color? surface;

  /// On the brand panel (D-650 r3): the inks of the spot the chip sits on (the cream part's dark set at the foot).
  final BrandInk? brandInk;

  const UserChipButton(
      {super.key, required this.user, required this.showLabel, this.hugLabel = false, this.surface, this.brandInk});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = user.name;
    final initial = name.isNotEmpty ? name[0] : '؟';
    final image = user.imageUrl;
    final onBar = ChromeBar.of(context);
    // on paper (the top bar, D-649): the brand gradient fills the initials and rings the avatar, a paper gap between
    final ringed = !onBar && surface == null;
    final k = brandInk;
    const ringW = AppBorder.focus + AppBorder.strong;
    final inner = ringed ? _ShellMetrics.mark + AppSpace.xxs - 2 * ringW : _ShellMetrics.mark;
    Widget avatar = Container(
      width: inner,
      height: inner,
      // on paper the initial sits on the brand fill, its cream end past the letter (D-650 r2)
      decoration: ringed ? AppBrandLayer.buttonFill(context, content: AppIconSize.md, shape: BoxShape.circle) : BoxDecoration(
        color: k != null ? k.activeFill : onBar ? c.heroGlass : (ringed ? null : c.primary),
        shape: BoxShape.circle,
        border: k != null
            ? Border.all(color: k.glassBorder, width: AppBorder.hairline)
            : onBar ? Border.all(color: c.heroGlassBorder, width: AppBorder.hairline) : null,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: image != null && image.isNotEmpty
          ? AppNetworkImage(url: image, enableFullscreen: false, heroTag: 'user_logo-dashboard')
          // a name is in whichever language the person typed it: the other language's font draws it too
          : Text(initial,
              style: AppType.row(context)
                  .copyWith(color: k?.ink ?? c.onHero, fontWeight: FontWeight.w600, fontFamilyFallback: AppFonts.fallback)),
    );
    if (ringed) {
      avatar = Container(
        padding: const EdgeInsets.all(AppBorder.focus),
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: AppBrandLayer.button(context)),
        child: Container(
          padding: const EdgeInsets.all(AppBorder.strong),
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.cardBg),
          child: avatar,
        ),
      );
    }
    return Padding(
      padding: showLabel
          ? (surface != null ? const EdgeInsets.all(AppSpace.xs) : const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.sm))
          : const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Semantics(
        button: true,
        label: name,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.controlAll,
            hoverColor: k?.hover ?? (onBar ? c.heroGlass : c.primary.withValues(alpha: 0.06)),
            focusColor: k?.hover ?? (onBar ? c.heroGlass : c.primary.withValues(alpha: 0.06)),
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
                                  .copyWith(color: k?.ink ?? (onBar ? c.onHero : c.textDark), fontFamilyFallback: AppFonts.fallback),
                            ),
                            Text(
                              appRoleLabel(user.role),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.meta(context).copyWith(
                                  color: k?.muted ?? (onBar ? c.onHeroMuted : (surface != null ? c.blockMuted(surface!) : c.textLight))),
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

/// One tab of the sidebar on the green gradient (D-649): a 48 px row, the idle one in the muted on-hero ink; the open
/// one a soft glass pill in cream ink with a 3 px gold bar on its start edge (it mirrors in Arabic). Counts stay red.
class _SidebarTile extends StatelessWidget {
  final DashboardItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SidebarTile({required this.item, required this.selected, required this.onTap, this.onLongPress});

  /// The gold bar's width and its inset from the pill's top and bottom.
  static const double _bar = 3, _barInset = AppSpace.sm + 2;

  @override
  Widget build(BuildContext context) {
    // D-650 r3: the inks of the spot the tab sits on (the green part's on-hero set, the cream part's dark set)
    return AppBrandInk(builder: _tile);
  }

  Widget _tile(BuildContext context, BrandInk l) {
    final ink = selected ? l.activeInk : l.item;
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
            onLongPress: onLongPress,
            customBorder: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
            hoverColor: l.hover,
            focusColor: l.hover,
            highlightColor: l.hover,
            splashColor: l.hover,
            child: AnimatedContainer(
              duration: AppMotion.of(context).fast,
              curve: AppMotion.curve,
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              decoration: BoxDecoration(
                color: selected ? l.activeFill : l.activeFill.withValues(alpha: 0),
                borderRadius: AppRadius.controlAll,
              ),
              child: Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  if (selected)
                    PositionedDirectional(
                      start: 0,
                      top: _barInset,
                      bottom: _barInset,
                      width: _bar,
                      child: ExcludeSemantics(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: l.indicator,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: AppTouch.min),
                      child: Row(
                        children: [
                          // D-650 r3: every tab's glyph wears the brand family, matched to what is under it; a tab the
                          // person coloured sits on its colour box instead (D-1170)
                          _ColorOr(
                            item: item,
                            selected: selected,
                            box: 28,
                            fallback: AppGradientIcon(selected ? item.selectedIcon : item.icon,
                                size: AppIconSize.md, on: selected ? l.activeSurfaces : l.surfaces),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: Text(
                              item.label.tr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.row(context)
                                  .copyWith(color: ink, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
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

/// The floating top bar over a tab's first page (D-648): a white rounded card inset like the sidebar, the same height
/// on every shell page. At the start the page's title (with the home it belongs to as one small line above it — the
/// breadcrumb, never the title twice), then the search pill (the screen's Ctrl+K palette), then the ghost buttons
/// with their small counts and the signed-in person's avatar at the end.
class _TopBar extends StatelessWidget {
  final String title;

  /// The home tab's name when this is another tab (the breadcrumb's one parent); null on the home tab.
  final String? crumb;
  final int unread;
  final Future<void> Function()? onRefresh;
  final String? helpPageId;

  /// Focus mode: a slim bar with the title and the way out, in the corner where focus mode was entered.
  final bool focus;

  /// The signed-in person's avatar at the end; null = none (a guest, a test).
  final UserModel? user;

  /// The card's inset from the window and the sidebar (the page gutter).
  final double inset;

  const _TopBar({
    required this.title,
    this.crumb,
    required this.unread,
    required this.onRefresh,
    this.helpPageId,
    this.focus = false,
    this.user,
    this.inset = AppSpace.lg,
  });

  /// The widest the search pill grows.
  static const double _searchMax = 360;

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
    final heading = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (crumb != null)
        Semantics(
          label: '${'breadcrumb_path'.tr}: $crumb / $title',
          excludeSemantics: true,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.home_outlined, size: AppIconSize.xs, color: c.textMedium),
            const SizedBox(width: AppSpace.xxs),
            Flexible(
              child: Text(crumb!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
            ),
          ]),
        ),
      Semantics(
        header: true,
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.section(context).copyWith(color: c.textDark, height: 1.25),
        ),
      ),
    ]);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'shell_top_bar'.tr,
      child: ChromeCard(
        margin: EdgeInsetsDirectional.fromSTEB(inset, inset, inset, AppSpace.xs),
        height: _ShellMetrics.barH,
        padding: const EdgeInsetsDirectional.only(start: AppSpace.lg, end: AppSpace.sm),
        child: Row(children: [
          // the title and the search share the start; the buttons keep their size at the end
          Expanded(
            flex: 5,
            child: Row(children: [
              Flexible(flex: 2, child: heading),
              if (palette != null) ...[
                const SizedBox(width: AppSpace.lg),
                Flexible(
                  flex: 3,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _searchMax),
                    child: _TopSearch(onTap: palette),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(width: AppSpace.md),
          // only a squeezed shell scales the buttons down
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
                  const SizedBox(width: AppSpace.xxs),
                  UserChipButton(user: user!, showLabel: false),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The top bar's search: a pill on the card with the shortcut hint, opening the screen's palette.
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
        color: c.cardBg,
        shape: StadiumBorder(side: BorderSide(color: c.divider, width: AppBorder.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('app.shell.search'),
          onTap: onTap,
          hoverColor: c.primary.withValues(alpha: 0.04),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xxs),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpace.md, end: AppSpace.xs),
              child: Row(children: [
                Icon(Icons.search_rounded, size: AppIconSize.md, color: c.textMedium),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
                ),
                const SizedBox(width: AppSpace.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
                  decoration: BoxDecoration(
                    color: c.inputBg,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text('Ctrl K',
                      maxLines: 1,
                      textDirection: TextDirection.ltr,
                      style: AppType.overline(context).copyWith(color: c.blockMuted(c.inputBg), letterSpacing: 0)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon column (the rail, and the desktop sidebar folded): the brand mark, the fold button when [foldable], the
/// tabs as icon cells with the open one's tinted pill, the person at the bottom when no top bar carries them.
class _RailColumn extends StatelessWidget {
  const _RailColumn({
    required this.items,
    required this.current,
    required this.onTap,
    this.user,
    this.foldable = false,
    this.pinnedFrom,
    this.onCustomize,
  });

  final List<DashboardItem> items;
  final int current;
  final ValueChanged<int> onTap;
  final UserModel? user;
  final bool foldable;
  final int? pinnedFrom;
  final VoidCallback? onCustomize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _ShellMetrics.railW,
      child: _BrandSideCard(
        child: Column(
          children: [
            SizedBox(
              height: _ShellMetrics.barH,
              child: Center(child: foldable ? const _FoldButton() : const _AppMark()),
            ),
          Expanded(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'shell_navigation'.tr,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    if (i == pinnedFrom && i > 0) const _RailRule(),
                    _RailTile(item: items[i], selected: current == i, onTap: () => onTap(i), onLongPress: onCustomize),
                  ],
                  if (onCustomize != null) _RailCustomize(onTap: onCustomize!),
                ],
              ),
            ),
          ),
            if (user != null) AppBrandInk(builder: (context, k) => UserChipButton(user: user!, showLabel: false, brandInk: k)),
          ],
        ),
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
        // offline / syncing / waiting writes (D-1351); draws nothing while online with nothing waiting
        if (!GuestState.active) const SyncStatusChip(),
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

  /// The first pinned page's index in [dashboardItems] (null: none), D-1170.
  final int? pinnedFrom;

  /// Customize tabs (a long press on a tab, the button under them); null = none.
  final VoidCallback? onCustomize;

  const RailShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.dashboardItems,
    required this.unreadCount,
    this.body,
    this.showTopBar = true,
    this.focus = false,
    this.pinnedFrom,
    this.onCustomize,
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
    final inset = shellInset(MediaQuery.sizeOf(context).width);
    return BasePage(
      child: Row(
        children: [
          _FocusFold(
            focus: focus,
            child: _SideInset(
              inset: inset,
              child: _RailColumn(
                  items: dashboardItems, current: current, onTap: onTap, user: barShown ? null : user,
                  pinnedFrom: pinnedFrom, onCustomize: onCustomize),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                if (barShown)
                  _TopBar(
                    title: dashboardItems[current].label.tr,
                    crumb: current == 0 ? null : dashboardItems[0].label.tr,
                    unread: unreadCount,
                    onRefresh: dashboardItems[current].onRefresh,
                    helpPageId: isShellPinTab(dashboardItems[current].tabId)
                        ? null
                        : shellHelpPageId(context, dashboardItems[current].label, current == 0),
                    focus: focus,
                    user: user,
                    inset: inset,
                  ),
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
  const _RailTile({required this.item, required this.selected, required this.onTap, this.onLongPress});

  final DashboardItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    // the rail sits on the brand panel (D-649 / D-650 r3): its hover and inks are the ones for the spot under it
    return AppBrandInk(builder: (context, k) => _cell(context, k));
  }

  Widget _cell(BuildContext context, BrandInk k) {
    final hover = k.hover;
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
            onLongPress: onLongPress,
            borderRadius: AppRadius.controlAll,
            hoverColor: hover,
            focusColor: hover,
            child: SizedBox(
              width: _ShellMetrics.railW,
              height: _ShellMetrics.railCellH,
              child: Center(
                child: _TabIconPill(item: item, active: selected, width: _ShellMetrics.railPillW, brand: k),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The icon of a rail / phone tab on its pill, and its count on the top-end corner, ringed with the surface under it
/// so it reads over the icon (D-649): on the phone's light bar the open tab's pill is the brand gradient with the
/// on-hero ink; on the green rail ([onBrand]) it is the sidebar's glass pill in cream ink, the idle icons muted on-hero.
class _TabIconPill extends StatelessWidget {
  const _TabIconPill({required this.item, required this.active, required this.width, this.brand});

  final DashboardItem item;
  final bool active;
  final double width;

  /// On the rail: the inks of the spot under the cell (D-650 r3); null = the phone's paper bar.
  final BrandInk? brand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppBrandLayer.of(context);
    final k = brand;
    final onBrand = k != null;
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
            // the phone's open tab: the brand fill, its cream end past the centred glyph (D-650 r2)
            decoration: !onBrand && active
                ? AppBrandLayer.buttonFill(context, content: AppIconSize.lg, borderRadius: BorderRadius.circular(AppRadius.pill))
                : BoxDecoration(
              color: onBrand ? (active ? k.activeFill : k.activeFill.withValues(alpha: 0)) : null,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            // D-650 r3: every tab glyph wears the brand family, matched to what is under it (the rail's spot, the
            // phone's green pill, the paper bar)
            child: Center(
              // the person's colour box for this tab, when they chose one (D-1170)
              child: _ColorOr(
                item: item,
                selected: active,
                box: _ShellMetrics.pillH - AppSpace.xxs,
                fallback: AppGradientIcon(
                  active ? item.selectedIcon : item.icon,
                  size: AppIconSize.lg,
                  on: onBrand
                      ? (active ? k.activeSurfaces : k.surfaces)
                      : (active ? [l.button.first] : [c.cardBg]),
                ),
              ),
            ),
          ),
          // over the icon's top-end quarter, the Material badge offset, so the glyph stays readable under it
          if (n > 0)
            PositionedDirectional(
              top: -(AppSpace.xxs + 2),
              end: -AppSpace.xxs,
              child: _CountPill(n, tone: item.badgeTone, ring: onBrand ? k.surfaces.first : c.cardBg),
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

  /// Over the tabs: the pinned pages' strip on Home (D-1170); null = nothing.
  final Widget? top;

  /// Customize tabs (a long press on a tab); null = none.
  final VoidCallback? onCustomize;

  const MobileShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.dashboardItems,
    this.body,
    this.top,
    this.onCustomize,
  });

  @override
  Widget build(BuildContext context) {
    final current = currentIndex.clamp(0, dashboardItems.length - 1);
    final tabs = body ?? LazyTabStack(index: current, items: dashboardItems);
    return BasePage(
      bottomNavigationBar:
          _BottomNav(onSelect: onTap, index: current, dashboardItems: dashboardItems, onLongPress: onCustomize),
      // one Column always, so the keyed tab stack keeps its place when the strip comes and goes
      child: Column(children: [
        if (top != null) SafeArea(bottom: false, child: top!),
        Expanded(child: MediaQuery.removePadding(context: context, removeTop: top != null, child: tabs)),
      ]),
    );
  }
}

/// One slot of the phone bar (D-1340): one tab ([group] null, [members] = its index) or a group of tabs.
@immutable
class ShellNavSlot {
  const ShellNavSlot(this.members, [this.group]);

  /// Indexes into the items, in their order.
  final List<int> members;

  /// Null: the slot is the tab `members.single` itself.
  final ShellMobileGroup? group;

  bool get isGroup => group != null;
}

/// The phone bar's slots for [items] (D-1340): rule 1 (at most [max] items: one slot each), rule 2 (items of one
/// [DashboardItem.mobileGroup] fold into one slot at the first member's place; one member draws the tab itself),
/// rule 3 (still more than [max]: slots [max]… and on fold into [ShellMobileGroup.more]).
List<ShellNavSlot> shellNavSlots(List<DashboardItem> items, {int max = BottomNavMetrics.maxSlots}) {
  if (items.length <= max) return [for (var i = 0; i < items.length; i++) ShellNavSlot([i])];
  final slots = <ShellNavSlot>[];
  final byGroup = <ShellMobileGroup, List<int>>{};
  for (var i = 0; i < items.length; i++) {
    final g = items[i].mobileGroup;
    if (g == null) {
      slots.add(ShellNavSlot([i]));
      continue;
    }
    final members = byGroup[g];
    if (members != null) {
      members.add(i);
      continue;
    }
    final list = byGroup[g] = [i];
    slots.add(ShellNavSlot(list, g));
  }
  final folded = [for (final sl in slots) sl.isGroup && sl.members.length == 1 ? ShellNavSlot(sl.members) : sl];
  if (folded.length <= max) return folded;
  return [
    ...folded.take(max - 1),
    ShellNavSlot([for (final sl in folded.skip(max - 1)) ...sl.members], ShellMobileGroup.more),
  ];
}

/// Paper with one hairline on top; no shadow — the bar is a surface the page scrolls under, not something afloat. The
/// open tab's icon sits on a tinted pill and its label turns to the primary ink (D-631). At most five slots (D-1340).
class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final List<DashboardItem> dashboardItems;
  final VoidCallback? onLongPress;

  const _BottomNav({required this.index, required this.onSelect, required this.dashboardItems, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final slots = shellNavSlots(dashboardItems);
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
              for (final sl in slots)
                Expanded(
                  child: sl.isGroup
                      ? _GroupSlot(
                          group: sl.group!,
                          items: dashboardItems,
                          members: sl.members,
                          index: index,
                          onSelect: onSelect,
                          onLongPress: onLongPress)
                      : _BottomTab(
                          item: dashboardItems[sl.members.single],
                          active: sl.members.single == index,
                          onTap: () => onSelect(sl.members.single),
                          onLongPress: onLongPress),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group's slot on the phone bar (D-1340): the group's icon and label, active while one of its members is the open
/// tab, the members' counts summed. A tap ALWAYS opens the group's sheet; a long press is Customize tabs.
class _GroupSlot extends StatelessWidget {
  const _GroupSlot({
    required this.group,
    required this.items,
    required this.members,
    required this.index,
    required this.onSelect,
    this.onLongPress,
  });

  final ShellMobileGroup group;
  final List<DashboardItem> items;
  final List<int> members;
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback? onLongPress;

  /// The slot drawn as a tab of its own: the group's glyphs, the members' summed count.
  DashboardItem _asItem() {
    final ms = [for (final i in members) items[i]];
    final orgs = {for (final m in ms) m.attentionOrgId};
    return DashboardItem(group.icon, group.selectedIcon, group.label, null, const SizedBox.shrink(),
        id: 'group:${group.id}',
        badge: ms.fold<int>(0, (n, m) => n + m.badge),
        badgeTone: ms.every((m) => m.badgeTone == ShellBadgeTone.reward) ? ShellBadgeTone.reward : ShellBadgeTone.attention,
        attentionKeys: [for (final m in ms) ...m.attentionKeys],
        attentionOrgId: orgs.length == 1 ? orgs.first : null);
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showAppSheet<int>(
      context,
      (ctx) => ShellGroupSheet(
        title: group.label.tr,
        items: items,
        members: members,
        current: index,
        onPick: (i) => Navigator.of(ctx).pop(i),
      ),
    );
    if (picked != null) onSelect(picked);
  }

  @override
  Widget build(BuildContext context) => _BottomTab(
        key: ValueKey('shell.group.${group.id}'),
        item: _asItem(),
        active: members.contains(index),
        onTap: () => _open(context),
        onLongPress: onLongPress,
      );
}

/// A phone-bar group's members as a sheet (D-1340), from plain values: the title, then one row per member in the
/// items' order (its icon pill or colour box, the label, a one-line hint, its count, a mirrored chevron); the open
/// tab's row is marked selected. Each row is at least [AppTouch.min] high; a tap calls [onPick] with the item's index.
class ShellGroupSheet extends StatelessWidget {
  const ShellGroupSheet({
    super.key,
    required this.title,
    required this.items,
    required this.members,
    required this.current,
    required this.onPick,
  });

  final String title;
  final List<DashboardItem> items;
  final List<int> members;
  final int current;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSheetHeader(title),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.sm, 0, AppSpace.sm, AppSpace.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final i in members)
                      _GroupRow(
                          key: ValueKey('shell.group.row.${items[i].tabId}'),
                          item: items[i],
                          selected: i == current,
                          onTap: () => onPick(i)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({super.key, required this.item, required this.selected, required this.onTap});

  final DashboardItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hint = item.hint;
    final ink = selected ? c.blockAccentInk(c.primary, c.primaryTint) : c.textDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xxs),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? c.primaryTint : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                child: Row(
                  children: [
                    _ColorOr(
                      item: item,
                      selected: selected,
                      box: _ShellMetrics.pillH + AppSpace.xxs,
                      fallback: Container(
                        width: _ShellMetrics.pillH + AppSpace.xxs,
                        height: _ShellMetrics.pillH + AppSpace.xxs,
                        decoration: BoxDecoration(
                          color: selected ? c.cardBg : c.primaryTint,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        alignment: Alignment.center,
                        child: Icon(selected ? item.selectedIcon : item.icon,
                            size: AppIconSize.md, color: c.blockAccentInk(c.primary, selected ? c.cardBg : c.primaryTint)),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.label.tr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.row(context)
                                  .copyWith(color: ink, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                          if (hint != null)
                            Text(hint.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.meta(context)
                                    .copyWith(color: selected ? c.blockAccentInk(c.textMedium, c.primaryTint) : c.textMedium)),
                        ],
                      ),
                    ),
                    ShellBadge(
                      item: item,
                      builder: (context, n) => n > 0
                          ? Padding(
                              padding: const EdgeInsetsDirectional.only(start: AppSpace.xs),
                              child: _CountPill(n, tone: item.badgeTone),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: AppSpace.xxs),
                    Icon(Icons.chevron_right_rounded, size: AppIconSize.lg, color: c.textLight),
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

/// One phone tab: the icon on an emerald pill when open, its label under it. The label always shows; the open
/// tab's is heavier and in the primary ink. The whole column is the target (≥ 48 px).
class _BottomTab extends StatelessWidget {
  const _BottomTab({super.key, required this.item, required this.active, required this.onTap, this.onLongPress});

  final DashboardItem item;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
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

  /// The most slots the phone bar draws (D-1340); more tabs fold into groups.
  static const int maxSlots = 5;

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

// ─────────────────────────────────────────────────────────────────────────────
// Colour boxes and Customize tabs (D-1170)
// ─────────────────────────────────────────────────────────────────────────────

/// The colour the person gave [item]'s tab, if any.
ShellTabColor? _tabColor(BuildContext context, DashboardItem item) =>
    ShellScope.maybeOf(context)?.pins?.state.colorOf(item.colorKey);

/// [item]'s colour box when the person gave its tab a colour, else [fallback] (the shell's own glyph).
class _ColorOr extends StatelessWidget {
  const _ColorOr({required this.item, required this.selected, required this.box, required this.fallback});

  final DashboardItem item;
  final bool selected;
  final double box;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final col = _tabColor(context, item);
    // the same width either way, so the labels of coloured and plain tabs line up
    if (col == null) return SizedBox(width: box, height: box, child: Center(child: fallback));
    return ShellColorBox(icon: selected ? item.selectedIcon : item.icon, color: col, size: box);
  }
}

/// The sidebar's last row: Customize tabs (colours, the pins' order), quiet under the tabs.
class _CustomizeTile extends StatelessWidget {
  const _CustomizeTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm),
        child: AppBrandInk(
          builder: (context, l) => Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const ValueKey('app.shell.customize'),
              onTap: onTap,
              customBorder: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
              hoverColor: l.hover,
              focusColor: l.hover,
              highlightColor: l.hover,
              splashColor: l.hover,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  child: Row(children: [
                    SizedBox(
                      width: 28,
                      child: Center(child: Icon(Icons.palette_outlined, size: AppIconSize.md, color: l.muted)),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        'shell_customize'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.row(context).copyWith(color: l.muted),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

/// The rail's line between the role's tabs and the pins.
class _RailRule extends StatelessWidget {
  const _RailRule();

  @override
  Widget build(BuildContext context) => AppBrandInk(
        builder: (context, l) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
          child: Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: l.glassBorder),
        ),
      );
}

/// The rail's Customize tabs cell (an icon; its name is the tooltip and the screen reader's).
class _RailCustomize extends StatelessWidget {
  const _RailCustomize({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppBrandInk(
        builder: (context, l) => Tooltip(
          message: 'shell_customize'.tr,
          excludeFromSemantics: true,
          child: Semantics(
            button: true,
            label: 'shell_customize'.tr,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: const ValueKey('app.shell.customize'),
                onTap: onTap,
                borderRadius: AppRadius.controlAll,
                hoverColor: l.hover,
                focusColor: l.hover,
                child: SizedBox(
                  width: _ShellMetrics.railW,
                  height: _ShellMetrics.railCellH,
                  child: Center(child: Icon(Icons.palette_outlined, size: AppIconSize.md, color: l.muted)),
                ),
              ),
            ),
          ),
        ),
      );
}
