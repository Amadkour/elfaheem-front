/// app_shell.dart — responsive navigation wrapper
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../config/app_config.dart' as Helpers;
import '../../../../../config/theme/theme_config_provider.dart';
import '../../../../../utils/widget/app_navigator.dart';
import '../../../../auth/auth_provider.dart';
import 'app_responsive.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

/// Wrap all pages inside AppShell to get sidebar on web,
/// bottom-nav on mobile automatically.
class AppShell extends StatefulWidget {
  final List<ShellPage> pages;

  const AppShell({super.key, required this.pages});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _idx = 0;

  // _AppShellState
  @override
  void initState() {
    super.initState();
    AppNavigator.requestedTab.addListener(_onTabRequest);
  }

  @override
  void dispose() {
    AppNavigator.requestedTab.removeListener(_onTabRequest);
    super.dispose();
  }

  void _onTabRequest() {
    final i = widget.pages.indexWhere(
      (p) => p.id != null && p.id == AppNavigator.requestedTab.value,
    );
    if (i != -1 && mounted) setState(() => _idx = i);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: context.showSidebar
          ? _WebLayout(
              pages: widget.pages,
              idx: _idx,
              onSelect: (i) {
                if (mounted) setState(() => _idx = i);
              },
            )
          : _MobileLayout(
              pages: widget.pages,
              idx: _idx,
              onSelect: (i) {
                if (mounted) setState(() => _idx = i);
              },
            ),
    );
  }
}

// ── Shell page definition ─────────────────────────────────────────────────────

class ShellPage {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget child;
  final String? id;

  const ShellPage({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.child,
    this.id,
  });
}

// ── Web layout: fixed sidebar + content ───────────────────────────────────────

class _WebLayout extends StatelessWidget {
  final List<ShellPage> pages;
  final int idx;
  final ValueChanged<int> onSelect;

  const _WebLayout({
    required this.pages,
    required this.idx,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────────────────
          _Sidebar(pages: pages, idx: idx, onSelect: onSelect),

          // ── Content ──────────────────────────────────────────────────
          Expanded(child: pages[idx].child),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<ShellPage> pages;
  final int idx;
  final ValueChanged<int> onSelect;

  const _Sidebar({
    required this.pages,
    required this.idx,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final user = context.watch<MyAuthProvider>().currentUser;
    final name = user?.name ?? 'student'.tr;
    final initial = name.isNotEmpty ? name[0] : '؟';

    return Container(
      width: Breakpoints.sidebarW,
      decoration: BoxDecoration(
        color: context.colors.heroShade,
        border: BorderDirectional(end: BorderSide(color: context.colors.heroDivider, width: 0.5)),
      ),
      child: Column(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: context.colors.primaryGradient,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: context.colors.primary.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    color: context.colors.onHero,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'EduApp',
                  style: TextStyle(
                    color: context.colors.onHero,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFamily: AppFonts.display,
                  ),
                ),
              ],
            ),
          ),

          Container(height: 0.5, color: context.colors.onHero.withValues(alpha: 0.08)),
          const SizedBox(height: 12),

          // Nav items
          ...pages.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            final active = i == idx;
            return _SideNavItem(
              label: p.label,
              icon: active ? p.activeIcon : p.icon,
              active: active,
              onTap: () => onSelect(i),
            );
          }),

          const Spacer(),
          Container(height: 0.5, color: context.colors.onHero.withValues(alpha: 0.08)),

          // User footer
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: context.colors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: context.colors.onHero,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      fontFamily: AppFonts.display,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: context.colors.onHero,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: AppFonts.display,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'طالب',
                        style: TextStyle(
                          color: context.colors.onHero.withValues(alpha: 0.5),
                          fontSize: 10,
                          fontFamily: AppFonts.display,
                        ),
                      ),
                    ],
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

class _SideNavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _SideNavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: active
                ? context.colors.primary.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: active ? context.colors.primaryGradient : null,
                  color: active ? null : context.colors.onHero.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: context.colors.primary.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: active
                      ? context.colors.onHero
                      : context.colors.onHero.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: active
                      ? context.colors.onHero
                      : context.colors.onHero.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  fontFamily: AppFonts.display,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mobile layout: scaffold + bottom nav ──────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final List<ShellPage> pages;
  final int idx;
  final ValueChanged<int> onSelect;

  const _MobileLayout({
    required this.pages,
    required this.idx,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: pages[idx].child,
      bottomNavigationBar: _BottomNav(
        pages: pages,
        idx: idx,
        onSelect: onSelect,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final List<ShellPage> pages;
  final int idx;
  final ValueChanged<int> onSelect;

  const _BottomNav({
    required this.pages,
    required this.idx,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        border: Border(
          top: BorderSide(
            color: context.colors.heroShade.withValues(alpha: 0.07),
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: context.colors.heroShade.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: pages.asMap().entries.map((e) {
              final i = e.key;
              final p = e.value;
              final active = i == idx;

              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 42,
                        height: 30,
                        decoration: BoxDecoration(
                          gradient: active
                              ? context.colors.primaryGradient
                              : null,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          active ? p.activeIcon : p.icon,
                          size: 20,
                          color: active
                              ? context.colors.onHero
                              : context.colors.textLight,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        p.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: active
                              ? context.colors.primary
                              : context.colors.textLight,
                          fontFamily: AppFonts.display,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
