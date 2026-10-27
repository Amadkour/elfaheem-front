// lib/design/app_shell.dart — ONE navigation shell for every role dashboard (student · teacher · parent · admin ·
// organization), D-062.
//
//   AppShell(width: constraints.maxWidth, currentIndex:, onTap:, items:, unreadCount:)
//       picks the shell with Breakpoints.shellFor (app_responsive.dart):
//         WideShell    sidebar + top bar            (>= Breakpoints.desktop)
//         RailShell    NavigationRail + top bar     (>= Breakpoints.mobile)
//         MobileShell  bottom bar                   (phones)
//       The three are public too, for a dashboard that picks one by hand. Every shell keeps the tabs in an
//       IndexedStack, so a tab keeps its state.
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
import '../features/auth/auth_provider.dart';
import '../features/shared/guest/guest_state.dart';
import '../features/shared/profile/update_account_widget.dart';
import '../utils/widget/app_network_image.dart';
import '../utils/widget/base_page.dart';
import '../utils/widget/refresh_button.dart';
import 'app_responsive.dart';
import 'calendar_entry.dart';

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

// ─────────────────────────────────────────────────────────────────────────────
// AppShell — picks the shell for a width
// ─────────────────────────────────────────────────────────────────────────────

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.width,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.unreadCount = 0,
  });

  final double width;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<DashboardItem> items;

  /// Unread notifications, for the top bar's bell (phones have none in the shell).
  final int unreadCount;

  @override
  Widget build(BuildContext context) => switch (Breakpoints.shellFor(width)) {
        AppShellKind.wide =>
          WideShell(currentIndex: currentIndex, onTap: onTap, dashboardItems: items, unreadCount: unreadCount),
        AppShellKind.rail =>
          RailShell(currentIndex: currentIndex, onTap: onTap, dashboardItems: items, unreadCount: unreadCount),
        AppShellKind.mobile => MobileShell(currentIndex: currentIndex, onTap: onTap, dashboardItems: items),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDE LAYOUT (>= Breakpoints.desktop) — persistent sidebar + top bar
// ─────────────────────────────────────────────────────────────────────────────

class WideShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<DashboardItem> dashboardItems;
  final int unreadCount;

  const WideShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.dashboardItems,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = context.watch<MyAuthProvider>().currentUser;
    final current = currentIndex.clamp(0, dashboardItems.length - 1);
    return BasePage(
      child: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────────────────────
          Container(
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
                                  AppIdentity.instance.name.isNotEmpty ? AppIdentity.instance.name : 'Al-Faheem',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'bahji',
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
                                  style: TextStyle(fontFamily: 'tajawal', color: c.onHeroFaint, fontSize: 10),
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
                    Divider(height: 1, color: c.heroDivider),
                    const SizedBox(height: 14),
                    if (user != null) UserChipButton(user: user, showLabel: true),
                  ],
                ),
              ],
            ),
          ),

          // ── Main content ──────────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: dashboardItems[current].label.tr,
                  unread: unreadCount,
                  onRefresh: dashboardItems[current].onRefresh,
                ),
                Expanded(
                  child: IndexedStack(
                    index: current,
                    children: dashboardItems.map((e) => e.screen).toList(),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditAccountScreen())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: c.heroGlass, borderRadius: BorderRadius.circular(14)),
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
                          fontWeight: FontWeight.w800,
                          fontFamily: 'bahji',
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
                        style: TextStyle(
                          color: c.primaryLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w100,
                          fontFamily: 'bahji',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        user.role.tr,
                        style: TextStyle(color: c.accent2, fontSize: 10, fontFamily: 'bahji'),
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? c.accent2.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? c.primary.withValues(alpha: 0.3) : Colors.transparent),
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
                  fontFamily: 'bahji',
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
                            fontWeight: FontWeight.w800,
                            fontFamily: 'bahji',
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top bar (wide + rail) ─────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final int unread;
  final Future<void> Function()? onRefresh;

  const _TopBar({required this.title, required this.unread, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: c.isDark ? c.cardBg : c.primary,
        border: Border(bottom: BorderSide(color: c.primary.withValues(alpha: 0.08))),
        boxShadow: c.cardShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: c.h2.copyWith(color: c.isDark ? c.textDark : c.onHero, fontWeight: FontWeight.normal),
            ),
          ),
          // the actions scale down instead of overflowing when the shell is squeezed
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (onRefresh != null) RefreshButton(onTap: onRefresh!),
                const SizedBox(width: 5),
                if (!GuestState.active) const CalendarIcon(),
                NotificationIcon(unreadCount: unread),
              ]),
            ),
          ),
        ],
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

/// The bell with the unread count — opens '/notifications'.
class NotificationIcon extends StatelessWidget {
  const NotificationIcon({super.key, required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed('/notifications'),
      child: Container(
        padding: const EdgeInsets.all(7),
        margin: const EdgeInsets.all(5),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: c.accent2),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.notifications_rounded, color: c.onHero, size: 20),
            if (unreadCount > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle),
                  child: Text(
                    _badgeText(unreadCount),
                    style: TextStyle(fontFamily: 'tajawal', fontSize: 8, fontWeight: FontWeight.w600, color: c.onHero),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RAIL LAYOUT (Breakpoints.mobile … desktop) — NavigationRail + top bar
// ─────────────────────────────────────────────────────────────────────────────

class RailShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<DashboardItem> dashboardItems;
  final int unreadCount;

  const RailShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.dashboardItems,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = context.watch<MyAuthProvider>().currentUser;
    final current = currentIndex.clamp(0, dashboardItems.length - 1);
    final railBg = c.isDark ? c.cardBg : c.primary;
    return BasePage(
      child: Row(
        children: [
          ColoredBox(
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
          ),
          VerticalDivider(width: 1, color: c.divider),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: dashboardItems[current].label.tr,
                  unread: unreadCount,
                  onRefresh: dashboardItems[current].onRefresh,
                ),
                Expanded(
                  child: IndexedStack(
                    index: current,
                    children: dashboardItems.map((e) => e.screen).toList(),
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

  const MobileShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.dashboardItems,
  });

  @override
  Widget build(BuildContext context) {
    final current = currentIndex.clamp(0, dashboardItems.length - 1);
    return BasePage(
      bottomNavigationBar: _BottomNav(onSelect: onTap, index: current, dashboardItems: dashboardItems),
      child: IndexedStack(
        index: current,
        children: dashboardItems.map((e) => e.screen).toList(),
      ),
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
    return GestureDetector(
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
              gradient: active ? c.accentGradient : null,
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
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? c.primary : c.textLight,
              fontFamily: 'bahji',
            ),
          ),
        ],
      ),
    );
  }
}
