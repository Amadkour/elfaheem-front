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
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../utils/helpers.dart';
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
      appBar: ScreenAppBar(title: 'control',showBack: false,actions: [
        IconButton(onPressed: () async {
          final ok = await Helpers.confirmDialog(context);
          if (ok == true && context.mounted) {
            await context.read<ProfileProvider>().logout(
              context,
            );
          }
        }, icon: Icon(Icons.logout)),
      ],),
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
      child: IndexedStack(index: _tab, children: pages)
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget tile(
      IconData icon,
      Color color,
      String title,
      String sub,
      Widget page,
    ) => RowCard(
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    color: c.textDark,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 12,
                    color: c.textLight,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_left_rounded, color: c.textLight),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        tile(
          Icons.campaign_rounded,
          c.primary,
          t('إرسال رسالة', 'Send a message'),
          t('للكل · لطلاب كورس · لطالب محدد', 'All · a course · one student'),
          const AdminSendMessagePage(),
        ),
        if (context.read<AuthProvider>().isSuper)
          tile(
            Icons.visibility_rounded,
            c.warning,
            t('عرض كمستخدم', 'View as user'),
            t(
              'شاهد لوحة طالب أو معلم (قراءة فقط)',
              'See a student / teacher dashboard (read-only)',
            ),
            const AdminViewAsPage(),
          ),
        tile(
          Icons.person_pin_rounded,
          c.purple,
          t('المعلمون', 'Teachers'),
          t('إضافة وتعديل وتحكم', 'Add, edit and control'),
          const AdminUsersPage(role: 'teacher'),
        ),
        tile(
          Icons.category_rounded,
          c.success,
          t('التصنيفات', 'Categories'),
          t('إدارة تصنيفات الكورسات', 'Manage course categories'),
          const AdminCategoriesPage(),
        ),
        tile(
          Icons.card_membership_rounded,
          c.primary,
          t('الاشتراكات', 'Subscriptions'),
          t('مجاني/مدفوع، الأسعار، الطلبات', 'Free/paid, prices, requests'),
          const AdminSubscriptionsPage(),
        ),
        tile(
          Icons.devices_rounded,
          c.warning,
          t('الأجهزة والدفع', 'Devices & payments'),
          t(
            'عدد الأجهزة، مدة التبديل، طرق الدفع',
            'Device limit, switch period, methods',
          ),
          const AdminSystemPage(),
        ),
        tile(
          Icons.palette_rounded,
          c.purple,
          t('المظهر', 'Theme'),
          t('ثيمات جاهزة ومخصصة', 'Built-in and custom themes'),
          const AdminThemePage(),
        ),
        tile(
          Icons.toggle_on_rounded,
          c.success,
          t('الميزات', 'Features'),
          t('إخفاء وإظهار الميزات', 'Hide / unhide features'),
          const AdminFeaturesPage(),
        ),
        tile(
          Icons.system_update_rounded,
          c.danger,
          t('إصدارات التطبيق', 'App versions'),
          t('نشر وتحديث إجباري', 'Publish and force updates'),
          const AdminVersionsPage(),
        ),
        tile(
          Icons.gavel_rounded,
          c.charcoal,
          t('الشروط ومن نحن', 'Terms & About'),
          t('تعديل المحتوى بلغتين', 'Edit bilingual content'),
          const AdminContentPage(),
        ),
      ],
    );
  }
}
