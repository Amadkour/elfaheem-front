// lib/features/parent/parent_dashboard_screen.dart
//
// The Parent shell — same structure as the admin / teacher dashboards (DashboardItem tabs rendered by
// WideShell / RailShell / MobileShell):
//   Children · Reports · Link (badge = pending requests) · More (account, language, dark mode, logout)
//
// Register the route in main.dart (and send role == 'parent' here after login):
//   case '/parent_dashboard': → const ParentDashboardScreen()
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_title.dart'
    show SettingsTile;
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/features/shared/profile/profile_screen.dart' show ProfileHeader;
import 'package:flutter_education_app/features/student/courses/details/components/app_responsive.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart'
    show WideShell, RailShell, MobileShell;
import 'package:flutter_education_app/features/teacher/dashboard/teacher_dashboard_screen.dart'
    show DashboardItem;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../design/app_switch.dart';
import '../../utils/helpers.dart';
import '../shared/profile/change_language_screen.dart';
import '../shared/profile/change_password_widget.dart';
import '../shared/profile/compalints/complaint_provider.dart';
import '../shared/profile/compalints/complaints_screen.dart';
import '../shared/profile/components/setting_group.dart';
import '../shared/profile/update_account_widget.dart';
import 'parent_alerts_page.dart';
import 'parent_children_page.dart';
import 'parent_link_providers.dart';
import 'parent_link_screen.dart';
import 'parent_reports_page.dart';
import 'parent_widgets.dart';

class ParentTabProvider extends ChangeNotifier {
  int currentTab = 0;

  void onChangeTab(int i) {
    if (i == currentTab) return;
    currentTab = i;
    notifyListeners();
  }
}

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final _tabs = ParentTabProvider();
  final _link = ParentLinkProvider();
  final _alerts = ParentAlertsProvider();
  final _epochs = List.generate(4, (_) => ValueNotifier<int>(0));
  late final List<DashboardItem> _items;

  bool get _isParent => (context.read<MyAuthProvider>().currentUser?.role ?? '') == 'parent';

  Future<void> _refresh(int i) async {
    _epochs[i].value++;
    _link.loadAll(); // fire-and-forget (the refresh button hides itself while the Future is pending)
    _alerts.load(silent: true);
  }

  @override
  void initState() {
    super.initState();
    _items = [
      DashboardItem(
        Icons.family_restroom_outlined,
        Icons.family_restroom_rounded,
        'pl_tab_children',
        () => _refresh(0),
        _ParentTab(
          titleKey: 'pl_tab_children',
          epoch: _epochs[0],
          child: ParentChildrenPage(onOpenLinkTab: () => _tabs.onChangeTab(3)),
        ),
      ),
      DashboardItem(
        Icons.insights_outlined,
        Icons.insights_rounded,
        'pl_tab_reports',
        () => _refresh(1),
        _ParentTab(titleKey: 'pl_tab_reports', epoch: _epochs[1], child: const ParentReportsPage()),
      ),
      DashboardItem(
        Icons.notifications_none_rounded,
        Icons.notifications_rounded,
        'pl_tab_alerts',
        () => _refresh(2),
        _ParentTab(titleKey: 'pl_tab_alerts', epoch: _epochs[2], child: const ParentAlertsPage()),
      ),
      DashboardItem(
        Icons.link_outlined,
        Icons.link_rounded,
        'pl_tab_link',
        () => _refresh(3),
        _ParentTab(titleKey: 'pl_tab_link', epoch: _epochs[3], child: const ParentLinkPage()),
      ),
      DashboardItem(
        Icons.grid_view_outlined,
        Icons.grid_view_rounded,
        'pl_tab_more',
        null,
        const _ParentTab(titleKey: 'pl_tab_more', child: _ParentMorePage()),
      ),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isParent) {
        _link.loadAll();
        _alerts.load(silent: true); // drives the badge on the Alerts tab
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _link.dispose();
    _alerts.dispose();
    for (final e in _epochs) {
      e.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isParent) {
      return BasePage(child: PlEmpty('pl_parents_only'.tr, icon: Icons.lock_rounded));
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ParentTabProvider>.value(value: _tabs),
        ChangeNotifierProvider<ParentLinkProvider>.value(value: _link),
        ChangeNotifierProvider<ParentAlertsProvider>.value(value: _alerts),
      ],
      builder: (context, _) {
        final tabs = context.watch<ParentTabProvider>();
        final pending = context.select<ParentLinkProvider, int>((p) => p.pendingCount);
        final unreadAlerts = context.select<ParentAlertsProvider, int>((p) => p.unread);
        for (final it in _items) {
          it.badge = it.label == 'pl_tab_link'
              ? pending
              : (it.label == 'pl_tab_alerts' ? unreadAlerts : 0);
        }
        return PopScope(
          canPop: tabs.currentTab == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) tabs.onChangeTab(0);
          },
          child: Directionality(
            textDirection: plIsAr ? TextDirection.rtl : TextDirection.ltr,
            child: LayoutBuilder(builder: (context, constraints) {
              final w = constraints.maxWidth;
              void onTap(int i) {
                if (mounted) tabs.onChangeTab(i);
              }

              if (w >= 1000) {
                return WideShell(
                    currentIndex: tabs.currentTab, onTap: onTap, dashboardItems: _items, unreadCount: 0);
              }
              if (kIsWeb && w >= 600) {
                return RailShell(
                    currentIndex: tabs.currentTab, onTap: onTap, dashboardItems: _items, unreadCount: 0);
              }
              return MobileShell(currentIndex: tabs.currentTab, onTap: onTap, dashboardItems: _items);
            }),
          ),
        );
      },
    );
  }
}

class _ParentTab extends StatelessWidget {
  const _ParentTab({required this.titleKey, required this.child, this.epoch});

  final String titleKey;
  final Widget child;
  final ValueNotifier<int>? epoch;

  @override
  Widget build(BuildContext context) => BasePage(
        appBar: ScreenAppBar(title: titleKey.tr, showBack: false),
        child: epoch == null
            ? child
            : ValueListenableBuilder<int>(
                valueListenable: epoch!,
                builder: (_, e, _) => KeyedSubtree(key: ValueKey(e), child: child),
              ),
      );
}

// ── "More" tab ────────────────────────────────────────────────────────────────
class _ParentMorePage extends StatefulWidget {
  const _ParentMorePage();

  @override
  State<_ParentMorePage> createState() => _ParentMorePageState();
}

class _ParentMorePageState extends State<_ParentMorePage> {
  Future<void> _push(Widget s) async =>
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => s));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileProvider>().initData(context.read<MyAuthProvider>().currentUser);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.watch<ProfileProvider>();
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
            child: Column(children: [
              const SizedBox(height: 24),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: ProfileHeader(provider: p)),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SettingsGroup(
                  title: 'account'.tr,
                  icon: Icons.account_circle_rounded,
                  children: [
                    SettingsTile(
                      icon: Icons.manage_accounts_rounded,
                      iconBg: c.primaryTint,
                      iconColor: c.primary,
                      label: 'update_account'.tr,
                      onTap: () async {
                        await _push(const EditAccountScreen(isTeacher: false));
                        if (mounted) {
                          context.read<ProfileProvider>().initData(context.read<MyAuthProvider>().currentUser);
                        }
                      },
                    ),
                    SettingsTile(
                      icon: Icons.lock_reset_rounded,
                      iconBg: c.accentTint,
                      iconColor: c.accent,
                      label: 'change_password'.tr,
                      onTap: () => _push(const ChangePasswordScreen()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SettingsGroup(
                  title: 'settings'.tr,
                  icon: Icons.settings_rounded,
                  children: [
                    SettingsTile(
                      icon: Icons.language_rounded,
                      iconBg: c.purpleTint,
                      iconColor: context.colors.primaryLight,
                      label: 'change_language'.tr,
                      onTap: () => _push(const ChangeLanguageScreen()),
                    ),
                    SettingsTile(
                      icon: Icons.dark_mode_rounded,
                      iconBg: c.darkIconBg,
                      iconColor: c.textDark,
                      label: 'dark_mode'.tr,
                      trailing: AppSwitch(
                        value: p.darkMode,
                        onChanged: (b) async => await p.changeMode(b),
                        semanticLabel: 'dark_mode'.tr,
                      ),
                    ),
                    SettingsTile(
                      icon: Icons.support_agent_rounded,
                      iconBg: c.primaryTint,
                      iconColor: c.primary,
                      label: 'help_center'.tr,
                      onTap: () => _push(ChangeNotifierProvider(
                          create: (_) => ComplaintProvider(), child: const ComplaintsScreen())),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SettingsGroup(
                  title: 'exit'.tr,
                  icon: Icons.exit_to_app_rounded,
                  itemBackground: c.danger.withAlpha(30),
                  children: [
                    SettingsTile(
                      icon: Icons.logout_rounded,
                      iconBg: c.dangerTint,
                      iconColor: c.danger,
                      label: 'logout'.tr,
                      onTap: () async {
                        final ok = await Helpers.confirmDialog(context);
                        if (ok == true && context.mounted) {
                          await context.read<ProfileProvider>().logout(context);
                        }
                      },
                    ),
                    SettingsTile(
                      icon: Icons.delete_forever_rounded,
                      iconBg: c.dangerTint,
                      iconColor: c.danger,
                      label: 'delete_account_title'.tr,
                      onTap: () async {
                        final ok = await Helpers.confirmDialog(context,
                            title: 'are_you_sure_to_delete_account'.tr, confirm: 'delete'.tr);
                        if (ok == true && context.mounted) {
                          Helpers.showMessage('your_account_will_deleted_successfully_through_14_days'.tr);
                          await Future.delayed(const Duration(seconds: 5));
                          if (!context.mounted) return;
                          await context.read<ProfileProvider>().deleteAccount(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
