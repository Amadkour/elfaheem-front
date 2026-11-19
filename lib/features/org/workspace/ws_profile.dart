// lib/features/org/workspace/ws_profile.dart
//
// The workspace's Profile tab (D-1150 / D-1158 / D-1180, docs/org-profile/PLAN.md): "Profile = me". My card
// (ProfileHero: name, avatar, my role in this organization, units managed · member of · unread alerts), then —
// for an organization admin (D-1160, WsController.admin), personal only:
//   Account       orgAccountRows (switch account · personal account · messages · create another organization),
//                 led for this release by one "Organization settings moved" row that opens the Organization tab
//   My units      one chip per unit: opens it in Management / Membership as the main unit
//   Preferences   orgPreferenceRows + reset the display preferences (confirmed)
//   Security · Help & legal (orgSecurityGroup, orgHelpGroup) and the app version; Log out sits in the card (D-1190)
// The organization's own pages live in the Organization tab and Management, not here. A NON-admin keeps today's
// groups: Account (orgAccountRows), My units, Organization pages (every org-wide sub-page I hold a right to, pushed
// with orgPushPage, D-1150), Workspace preferences and last the D-103 Settings page.
// WsProfileHeader is plain values (tested in test/org/ws_alerts_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/profile/profile_hero.dart' show ProfileHero, ProfileHeroStat;
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart' show Helpers;
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_dashboard_home.dart' show orgPush, orgPushPage;
import '../org_dashboard_screen.dart' show OrgTabs;
import '../org_dashboard_settings.dart' show OrgSettingsPage;
import '../org_providers.dart';
import '../org_settings_groups.dart';
import 'ws_models.dart';
import 'ws_shell.dart' show WsController, WsTabs;
import 'ws_units.dart' show wsOrgSectionName;

/// My role in the selected organization, in the singular ("Teacher", "Teaching assistant", "Staff").
String wsMyRoleLabel(String? memberRole, String access) => switch (memberRole) {
      'teacher' => t('عضو هيئة التدريس', 'Teacher'),
      'teacher_assistant' => t('عضو الهيئة المعاونة', 'Teaching assistant'),
      'admin_assistant' => t('إداري', 'Administrative staff'),
      _ => access == 'member' ? t('عضو', 'Member') : t('فريق العمل', 'Staff'),
    };

/// The org sections' names, for the "Organization pages" rows.
String _sectionName(String key) => wsOrgSectionName(key);

/// My card: ProfileHero with my organization role and three figures.
class WsProfileHeader extends StatelessWidget {
  const WsProfileHeader({
    super.key,
    required this.name,
    required this.role,
    this.email = '',
    this.username = '',
    this.imageUrl = '',
    this.managed = 0,
    this.memberOf = 0,
    this.unread = 0,
    this.onLogout,
  });

  /// Signs out from the card (D-1190); null = no button.
  final VoidCallback? onLogout;

  final String name, role, email, username, imageUrl;
  final int managed, memberOf, unread;

  @override
  Widget build(BuildContext context) => ProfileHero(
        name: name,
        role: role,
        email: email,
        username: username,
        imageUrl: imageUrl,
        onLogout: onLogout,
        stats: [
          ProfileHeroStat(icon: Icons.admin_panel_settings_rounded, value: '$managed', label: t('أديرها', 'I manage')),
          ProfileHeroStat(icon: Icons.groups_2_rounded, value: '$memberOf', label: t('عضو فيها', 'Member of')),
          ProfileHeroStat(icon: Icons.notifications_rounded, value: '$unread', label: t('تنبيهات غير مقروءة', 'Unread alerts')),
        ],
      );
}

class WsProfileTab extends StatefulWidget {
  const WsProfileTab({super.key});

  @override
  State<WsProfileTab> createState() => _WsProfileTabState();
}

class _WsProfileTabState extends State<WsProfileTab> {
  @override
  void initState() {
    super.initState();
    // the preference rows read the profile provider (dark mode …): load it like the old Settings page did
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProfileProvider>().initData(context.read<MyAuthProvider>().currentUser);
    });
  }

  void _openUnit(WsController ws, WsUnit u) {
    final scope = u.manages ? 'management' : 'membership';
    ws.prefs.update((p) => p.setMainUnit(scope, u.id));
    ws.go(u.manages ? WsTabs.management : WsTabs.membership);
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WsController>();
    final s = context.watch<OrgSession>();
    final tabs = context.watch<OrgTabs>();
    final user = context.watch<MyAuthProvider>().currentUser;
    final c = context.colors;
    final h = ws.home;
    final units = h?.all ?? const <WsUnit>[];
    final role = ws.admin ? t('مدير المؤسسة', 'Organization admin') : wsMyRoleLabel(s.memberRole, s.access);
    // an admin's first group: the whole organization's settings (D-1160); everyone else keeps it last
    final settings = AppSettingsGroup(title: t('المؤسسة', 'Organization'), icon: Icons.settings_rounded, children: [
      AppSettingsTile(
        key: const ValueKey('ws.profile.settings'),
        icon: Icons.settings_rounded,
        label: t('إعدادات المؤسسة', 'Organization settings'),
        subtitle: ws.admin
            ? t('بيانات المؤسسة والمؤسسات الفرعية ورمز الانضمام والأدوار وسجل النشاط والأمان',
                'Organization details, sub-organizations, join code, roles, activity log and security')
            : t('الأمان والإشعارات واللغة وتسجيل الخروج', 'Security, notifications, language and sign out'),
        keywords: 'settings organization roles join code activity إعدادات مؤسسة أدوار رمز سجل',
        onTap: () => orgPush(context, t('الإعدادات', 'Settings'), const OrgSettingsPage()),
      ),
    ]);

    final pages = <Widget>[
      for (final e in tabs.sections.entries)
        for (final x in e.value)
          AppSettingsTile(
            key: ValueKey('ws.profile.page.${e.key}.${x.$1}'),
            icon: x.$3,
            label: x.$2,
            subtitle: _sectionName(e.key),
            keywords: '${e.key} ${x.$1}',
            onTap: () => orgPushPage(context,
                session: s, dash: context.read<OrgDashController>(), tabs: tabs, title: x.$2, page: x.$4),
          ),
    ];

    return AppSettingsPage(
      gutter: AppSpace.md,
      searchThreshold: 40,
      columns: true,
      header: WsProfileHeader(
        name: user?.name ?? '',
        role: s.current == null ? role : '$role · ${s.name}',
        email: user?.gmail ?? '',
        username: user?.username ?? '',
        imageUrl: user?.imageUrl ?? '',
        managed: h?.managed.length ?? 0,
        memberOf: h?.memberOf.length ?? 0,
        unread: ws.alertCounts.unread,
        // the exits sit in the card at the top (D-1190), as on the personal Profile
        onLogout: () async {
          final ok = await Helpers.confirmDialog(context);
          if (ok == true && context.mounted) await context.read<ProfileProvider>().logout(context);
        },
      ),
      groups: [
        AppSettingsGroup(title: t('الحساب', 'Account'), icon: Icons.person_rounded, children: [
          if (ws.admin)
            AppSettingsTile(
              key: const ValueKey('ws.profile.moved'),
              icon: Icons.domain_rounded,
              label: t('إعدادات المؤسسة انتقلت', 'Organization settings moved'),
              subtitle: t('تجدها الآن في تبويب «المؤسسة»', 'Find them in the Organization tab now'),
              onTap: () => ws.go(WsTabs.organization),
            ),
          ...orgAccountRows(context, s),
        ]),
        if (units.isNotEmpty)
          AppSettingsGroup(title: t('وحداتي', 'My units'), icon: Icons.account_tree_rounded, children: [
            Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final u in units)
                  ActionChip(
                    key: ValueKey('ws.profile.unit.${u.id}'),
                    avatar: Icon(u.manages ? Icons.admin_panel_settings_rounded : Icons.groups_2_rounded, size: AppIconSize.sm, color: c.primary),
                    label: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    tooltip: u.manages ? t('أديرها', 'I manage it') : t('عضو فيها', 'I am a member'),
                    onPressed: () => _openUnit(ws, u),
                  ),
              ]),
            ),
          ]),
        if (!ws.admin && pages.isNotEmpty)
          AppSettingsGroup(
            title: t('صفحات المؤسسة', 'Organization pages'),
            subtitle: t('الصفحات التي تملك صلاحيتها في المؤسسة', 'The organization pages you have access to'),
            icon: Icons.domain_rounded,
            children: pages,
          ),
        AppSettingsGroup(title: ws.admin ? t('التفضيلات', 'Preferences') : t('تفضيلات مساحة العمل', 'Workspace preferences'), icon: Icons.tune_rounded, children: [
          if (ws.admin) ...orgPreferenceRows(context, s, context.watch<ProfileProvider>()),
          AppSettingsTile(
            key: const ValueKey('ws.profile.reset'),
            icon: Icons.restart_alt_rounded,
            label: t('إعادة ضبط العرض', 'Reset display preferences'),
            subtitle: t('طريقة العرض والوحدة الرئيسية والمثبّتات والفلاتر المحفوظة', 'Display style, main unit, pins and saved filters'),
            onTap: () async {
              final ok = await appConfirm(context,
                  message: t('ستعود طريقة العرض والوحدات الرئيسية والمثبّتات والفلاتر المحفوظة إلى الوضع الافتراضي على هذا الجهاز.',
                      'Display styles, main units, pins and saved filters go back to their defaults on this device.'),
                  confirmLabel: t('إعادة الضبط', 'Reset'));
              if (!ok) return;
              await ws.prefs.update((_) => const WsPrefs());
              showAppNotice(t('أُعيد ضبط التفضيلات', 'Preferences reset'));
            },
          ),
        ]),
        if (!ws.admin) settings,
        if (ws.admin) ...[orgSecurityGroup(), orgHelpGroup(context)],
      ],
      // sign out is in the card at the top now (D-1190): only the version closes the page
      footer: ws.admin ? const AppVersionLine() : null,
    );
  }
}
