// lib/features/admin/admin_dashboard_screen.dart
//
// The admin shell: bottom tabs (Overview · Students · Courses · More).
// "More" opens every other control page (teachers, categories, subscriptions,
// devices & payments, theme, features, versions, terms & about, withdrawals).
//
// Register the route in main.dart:  case '/admin_dashboard': → AdminDashboardScreen()
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_title.dart' show SettingsTile;
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/helpers.dart';
import '../shared/profile/change_language_screen.dart';
import '../shared/profile/components/setting_group.dart';
import 'admin_categories_page.dart';
import 'admin_common.dart';
import 'admin_content_page.dart';
import 'admin_courses_page.dart';
import 'admin_list.dart' show RowCard;
import 'admin_features_page.dart';
import 'admin_overview_page.dart';
import 'admin_send_message_page.dart';
import 'admin_subscriptions_page.dart';
import 'admin_system_page.dart';
import 'admin_theme_page.dart';
import 'admin_users_page.dart';
import 'admin_versions_page.dart';
import 'admin_view_as_page.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final c = context.colors;

    // Defence in depth: the server enforces roles on every call anyway.
    if (!['admin', 'super-admin'].contains(auth.currentUser?.role ?? '')) {
      return BasePage(
        child: EmptyState(
          t('هذه الصفحة للمديرين فقط', 'Admins only'),
          icon: Icons.lock_rounded,
        ),
      );
    }

    final pages = <Widget>[
      AdminOverviewPage(onOpenTab: (i) => setState(() => _tab = i)),
      const AdminUsersPage(role: 'student', embedded: true),
      const AdminCoursesPage(embedded: true),
      const _MorePage(),
    ];
    final titles = [
      t('لوحة التحكم', 'Dashboard'),
      t('الطلاب', 'Students'),
      t('الكورسات', 'Courses'),
      t('المزيد', 'More'),
    ];

    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(
        title: 'dashboard'.tr,
        showBack: false,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_rounded),
            label: t('الرئيسية', 'Overview'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.school_rounded),
            label: t('الطلاب', 'Students'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_rounded),
            label: t('الكورسات', 'Courses'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.apps_rounded),
            label: t('المزيد', 'More'),
          ),
        ],
      ),
      child: IndexedStack(index: _tab, children: pages),
    );
  }
}

Future<bool> _confirmLogout(BuildContext context) => confirm(
  context,
  message: t('هل تريد تسجيل الخروج؟', 'Log out?'),
  danger: true,
);

class _MorePage extends StatelessWidget {
  const _MorePage();
  Future<void> _push(BuildContext context,Widget screen) async => await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => screen));
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.watch<ProfileProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child:SettingsGroup(
        title: 'more'.tr,
        children:  [
        SettingsTile(
          icon: Icons.campaign_rounded,
          iconBg: c.primary.withAlpha(50),
          iconColor: c.primary,
          label: 'send_message'.tr,
          onTap: () => _push( context,const AdminSendMessagePage()),
        ),
        if (context.read<AuthProvider>().isSuper)
          SettingsTile(
            icon: Icons.visibility_rounded,
            iconBg: c.warning.withAlpha(50),
            iconColor:c.warning,
            label: 'view_as_user'.tr,
            onTap: () => _push( context,const AdminViewAsPage()),
          ),
        SettingsTile(
            icon: Icons.person_pin_rounded,
          iconBg: c.danger.withAlpha(50),
          iconColor:c.danger,
            label: 'teachers'.tr,
            onTap: () => _push( context,const AdminUsersPage(role: 'teacher')),
          ),

        SettingsTile(
            icon: Icons.category_rounded,
          iconBg: c.primary.withAlpha(50),
          iconColor: c.primary,
            label: 'categories'.tr,
            onTap: () => _push( context,const AdminCategoriesPage()),
          ),

        SettingsTile(
            icon: Icons.card_membership_rounded,
          iconBg: c.warning.withAlpha(50),
          iconColor:c.warning,
            label: 'subscriptions'.tr,
            onTap: () => _push( context,const AdminSubscriptionsPage()),
          ),

        SettingsTile(
            icon: Icons.devices_rounded,
          iconBg: c.danger.withAlpha(50),
          iconColor:c.danger,
            label: 'devices_and_payments'.tr,
            onTap: () => _push( context,const AdminSystemPage()),
          ),
        SettingsTile(
            icon: Icons.palette_rounded,
          iconBg: c.purpleTint,
          iconColor: const Color(0xFF8B6FFF),
            label: 'theme'.tr,
            onTap: () => _push( context,const AdminThemePage()),
          ),

        SettingsTile(
            icon: Icons.toggle_on_rounded,
          iconBg: c.primary.withAlpha(50),
          iconColor: c.primary,
            label: 'features'.tr,
            onTap: () => _push( context,const AdminFeaturesPage()),
          ),

        SettingsTile(
            icon: Icons.system_update_rounded,
          iconBg: c.warning.withAlpha(50),
          iconColor:c.warning,
            label: 'versions'.tr,
            onTap: () => _push( context,const AdminVersionsPage()),
          ),
        SettingsTile(
            icon: Icons.gavel_rounded,
          iconBg: c.danger.withAlpha(50),
          iconColor:c.danger,
            label: 'terms_and_conditions'.tr,
            onTap: () => _push( context,const AdminContentPage()),
          ),
    SettingsTile(
            icon: Icons.language_rounded,
            iconBg: c.purpleTint,
            iconColor: const Color(0xFF8B6FFF),
            label: 'change_language'.tr,
            onTap: () => _push(context,const ChangeLanguageScreen()),

        ), SettingsTile(
            icon: Icons.dark_mode_rounded,
            iconBg: c.darkIconBg,
            iconColor: c.textDark,
            label: 'dark_mode'.tr,
            trailing: Switch.adaptive(
              value: p.darkMode,
              onChanged: (b) async {
                await p.changeMode(b);
              },
              activeThumbColor: context.colors.primary,
              thumbColor: const WidgetStatePropertyAll(
                Colors.white,
              ),
            ),
          ),
        SettingsTile(
          key: ValueKey('profile.logout'),
          icon: Icons.logout,
          iconBg: c.dangerTint,
          iconColor: c.danger,
          label: 'logout'.tr,
          onTap: () async {
            final ok = await Helpers.confirmDialog(context);
            if (ok == true && context.mounted) {
              await context.read<ProfileProvider>().logout(
                context,
              );
            }
          },
        ),
      ],
      )
    );
  }
}
