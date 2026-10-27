// lib/features/parent/parent_dashboard_screen.dart
//
// The Parent shell — same structure as the admin / teacher dashboards (DashboardItem tabs rendered by
// AppShell, lib/design/app_shell.dart):
//   Children · Reports · Link (badge = pending requests) · More (account, language, dark mode, logout)
//
// Register the route in main.dart (and send role == 'parent' here after login):
//   case '/parent_dashboard': → const ParentDashboardScreen()
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart' show AttentionTabs;
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../design/app_switch.dart';
import '../../design/calendar_entry.dart';
import '../../utils/helpers.dart';
import '../auth/reauth_sheet.dart';
import '../shared/profile/change_language_screen.dart';
import '../shared/profile/change_password_widget.dart';
import '../shared/profile/compalints/complaint_provider.dart';
import '../shared/profile/compalints/complaints_screen.dart';
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

  /// Deep links (attention items): 'parent_alerts' → Alerts tab, 'parent_link' → Link tab.
  void _onTabRequested() {
    final i = switch (AppNavigator.requestedTab.value) {
      'parent_alerts' => 2,
      'parent_link' => 3,
      _ => -1,
    };
    if (i < 0) return;
    AppNavigator.requestedTab.value = null;
    _tabs.onChangeTab(i);
  }

  @override
  void initState() {
    super.initState();
    AppNavigator.requestedTab.addListener(_onTabRequested);
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
        attentionKeys: const [AttentionTabs.home],   // badges: GET /me/attention, drawn at the leaf
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
        attentionKeys: const [AttentionTabs.parentAlerts],
      ),
      DashboardItem(
        Icons.link_outlined,
        Icons.link_rounded,
        'pl_tab_link',
        () => _refresh(3),
        _ParentTab(titleKey: 'pl_tab_link', epoch: _epochs[3], child: const ParentLinkPage()),
        attentionKeys: const [AttentionTabs.parentLink],
      ),
      DashboardItem(
        Icons.grid_view_outlined,
        Icons.grid_view_rounded,
        'pl_tab_more',
        null,
        const _ParentTab(titleKey: 'pl_tab_more', child: _ParentMorePage()),
        attentionKeys: const [AttentionTabs.profile],
      ),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isParent) {
        _link.loadAll();
        _alerts.load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    AppNavigator.requestedTab.removeListener(_onTabRequested);
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
        return PopScope(
          canPop: tabs.currentTab == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) tabs.onChangeTab(0);
          },
          child: Directionality(
            textDirection: plIsAr ? TextDirection.rtl : TextDirection.ltr,
            child: LayoutBuilder(builder: (context, constraints) {
              void onTap(int i) {
                if (mounted) tabs.onChangeTab(i);
              }

              return AppShell(width: constraints.maxWidth, currentIndex: tabs.currentTab, onTap: onTap, items: _items);
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
        appBar: ScreenAppBar(title: titleKey.tr, showBack: false, actions: const [CalendarEntryIcon()]),
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
    return AppSettingsPage(
      header: AppSettingsHeader(
        name: p.name,
        role: p.role,
        email: p.email,
        imageUrl: p.imageUrl,
        heroTag: 'profile-user-${p.id}',
      ),
      groups: [
        AppSettingsGroup(
          title: 'account'.tr,
          icon: Icons.account_circle_rounded,
          children: [
            AppSettingsTile(
              icon: Icons.manage_accounts_rounded,
              color: c.primary,
              label: 'update_account'.tr,
              onTap: () async {
                await _push(const EditAccountScreen(isTeacher: false));
                if (mounted) {
                  context.read<ProfileProvider>().initData(context.read<MyAuthProvider>().currentUser);
                }
              },
            ),
            AppSettingsTile(
              icon: Icons.lock_reset_rounded,
              color: c.accent2,
              label: 'change_password'.tr,
              onTap: () => _push(const ChangePasswordScreen()),
            ),
            const CalendarEntryTile(),
          ],
        ),
        AppSettingsGroup(
          title: 'settings'.tr,
          icon: Icons.settings_rounded,
          children: [
            AppSettingsTile(
              icon: Icons.language_rounded,
              color: c.primaryLight,
              label: 'change_language'.tr,
              onTap: () => _push(const ChangeLanguageScreen()),
            ),
            AppSettingsTile(
              icon: Icons.dark_mode_rounded,
              color: c.textDark,
              label: 'dark_mode'.tr,
              trailing: AppSwitch(
                value: p.darkMode,
                onChanged: (b) async => await p.changeMode(b),
                semanticLabel: 'dark_mode'.tr,
              ),
            ),
            AppSettingsTile(
              icon: Icons.support_agent_rounded,
              color: c.primary,
              label: 'help_center'.tr,
              onTap: () => _push(ChangeNotifierProvider(
                  create: (_) => ComplaintProvider(), child: const ComplaintsScreen())),
            ),
          ],
        ),
        AppSettingsGroup(
          title: 'exit'.tr,
          icon: Icons.exit_to_app_rounded,
          danger: true,
          children: [
            AppSettingsTile(
              icon: Icons.logout_rounded,
              color: c.danger,
              label: 'logout'.tr,
              onTap: () async {
                final ok = await Helpers.confirmDialog(context);
                if (ok == true && context.mounted) {
                  await context.read<ProfileProvider>().logout(context);
                }
              },
            ),
            AppSettingsTile(
              icon: Icons.delete_forever_rounded,
              color: c.danger,
              label: 'delete_account_title'.tr,
              onTap: () async {
                        final ok = await Helpers.confirmDialog(context,
                            title: 'are_you_sure_to_delete_account'.tr, confirm: 'delete'.tr);
                        if (ok != true || !context.mounted) return;
                        final re = await askReauth(context); // current password (+ two-step code), S9
                        if (re == null || !context.mounted) return;
                        final p = context.read<ProfileProvider>();
                        final after = await p.deleteAccount(context, password: re.password, mfaCode: re.mfaCode);
                        if (after == null) {
                          Helpers.showMessage(p.errorMessage ?? 'generic_error'.tr, isError: true);
                          return;
                        }
                        Helpers.showMessage('your_account_will_deleted_successfully_through_14_days'.tr);
              },
            ),
          ],
        ),
      ],
    );
  }
}
