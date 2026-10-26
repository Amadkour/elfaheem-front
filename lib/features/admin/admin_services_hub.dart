// lib/features/admin/admin_services_hub.dart
//
// ONE list of every admin service (icon, colour, label, description, badge,
// target page). It feeds two UIs:
//   • the web / rail sidebar: each group is a sidebar tab → AdminServicesHub
//   • the phone "More" tab:   each group is a SettingsGroup of SettingsTiles
//
// So an icon / label / page is changed in exactly one place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaints_screen.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_title.dart'
    show SettingsTile;
import 'package:flutter_education_app/features/student/courses/details/components/app_responsive.dart'
    show Breakpoints;
import 'package:flutter_education_app/utils/widget/count_badge.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../shared/attendance/admin_data_lab_page.dart';
import 'admin_admins_page.dart';
import 'admin_auth_settings_page.dart';
import 'admin_categories_page.dart';
import 'admin_common.dart';
import 'admin_content_page.dart';
import 'admin_devices_page.dart';
import 'admin_features_page.dart';
import 'admin_platform_settings_page.dart';
import 'admin_finance_page.dart';
import 'admin_mfa_page.dart';
import 'admin_flags_settings_page.dart';
import 'admin_organizations_page.dart';
import 'admin_parent_link_settings_page.dart';
import 'admin_parent_requests_page.dart';
import 'admin_payment_page.dart';
import 'admin_payouts_page.dart';
import 'admin_premium_widgets.dart';
import 'admin_providers.dart' show AdminPendingPayoutsProvider;
import 'admin_required_documents_page.dart';
import 'admin_send_message_page.dart';
import 'admin_subscriptions_page.dart';
import 'admin_theme_page.dart';
import 'admin_users_page.dart';
import 'admin_versions_page.dart';
import 'admin_view_as_page.dart';
import 'enrollment_request/teacher_transfers_provider.dart';
import 'enrollment_request/teacher_transfers_screen.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/admin/admin_datacenter_page.dart';

// ── model ────────────────────────────────────────────────────────────────────
class AdminService {
  const AdminService({
    required this.labelKey,
    required this.descKey,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.badge,
    this.featureKey,
    this.visible = true,
    this.label,
    this.desc,
  });

  final String labelKey;
  final String descKey;

  /// Inline texts (already bilingual, `t(ar, en)`) that replace the translation keys; for services whose strings
  /// are not in translation.json.
  final String? label;
  final String? desc;

  String get labelText => label ?? labelKey.tr;
  String get descText => desc ?? descKey.tr;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  /// null → no badge. A number > 0 shows a red counter.
  final int? badge;

  /// Same keys the app already uses with ParentComponent (admin "Features" page).
  final String? featureKey;

  /// false → hidden (e.g. super-admin only items for a plain admin).
  final bool visible;
}

class AdminServiceGroup {
  const AdminServiceGroup({
    required this.id,
    required this.titleKey,
    required this.subtitleKey,
    required this.icon,
    required this.colors,
    required this.services,
  });

  final String id;
  final String titleKey;
  final String subtitleKey;
  final IconData icon;
  final List<Color> colors;
  final List<AdminService> services;

  List<AdminService> get visibleServices =>
      services.where((s) => s.visible).toList();

  /// Sum of the badges inside the group (used for the sidebar tab badge).
  int get badgeTotal => visibleServices.fold(0, (a, s) => a + (s.badge ?? 0));
}

// ── data ─────────────────────────────────────────────────────────────────────
/// Call from a build method (it uses context.select for the live badge counts).
List<AdminServiceGroup> adminServiceGroups(BuildContext context) {
  Future<void> push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  final isSuper = isSuperNow(context);
  final payouts = context.select<AdminPendingPayoutsProvider, int>(
    (p) => p.count,
  );
  final transfers = context.select<TeacherTransfersProvider, int>(
    (p) => p.total,
  );
  final complaints = context.select<ComplaintProvider, int>((p) => p.count);

  return [
    // ── People ────────────────────────────────────────────────────────────
    AdminServiceGroup(
      id: 'people',
      titleKey: 'admin_group_people',
      subtitleKey: 'svc_group_people_sub',
      icon: Icons.groups_rounded,
      colors: AdminPalette.blue,
      services: [
        AdminService(
          labelKey: 'svc_datacenter',
          descKey: 'svc_datacenter_d',
          icon: Icons.insights_rounded,
          colors: AdminPalette.indigo,
          onTap: () => push(const DataCenterPage()),
        ),
        AdminService(
          labelKey: 'svc_requirements',
          descKey: 'svc_requirements_d',
          icon: Icons.fact_check_rounded,
          colors: AdminPalette.green,
          onTap: () => push(const AdminRequirementsPage()),
        ),
        AdminService(
          labelKey: 'svc_ads',
          descKey: 'svc_ads_d',
          icon: Icons.campaign_rounded,
          colors: AdminPalette.orange,
          onTap: () => push(const AdminAdsPage()),
        ),
        AdminService(
          labelKey: 'svc_organizations',
          descKey: 'svc_organizations_d',
          icon: Icons.account_balance_rounded,
          colors: AdminPalette.teal,
          onTap: () => push(const AdminOrganizationsPage()),
        ),
        AdminService(
          labelKey: 'send_message',
          descKey: 'svc_send_message_d',
          icon: Icons.campaign_rounded,
          colors: AdminPalette.blue,
          onTap: () => push(const AdminSendMessagePage()),
        ),
        AdminService(
          labelKey: 'view_as_user',
          descKey: 'svc_view_as_d',
          icon: Icons.supervised_user_circle_rounded,
          colors: AdminPalette.orange,
          visible: isSuper,
          onTap: () => push(const AdminViewAsPage()),
        ),
        AdminService(
          labelKey: 'teachers',
          descKey: 'svc_teachers_d',
          icon: Icons.cast_for_education_rounded,
          colors: AdminPalette.rose,
          onTap: () => push(const AdminUsersPage(role: 'teacher')),
        ),
        AdminService(
          labelKey: 'admin_admins',
          descKey: 'svc_admins_d',
          icon: Icons.admin_panel_settings_rounded,
          colors: AdminPalette.indigo,
          visible: isSuper,
          onTap: () => push(const AdminAdminsPage()),
        ),
        AdminService(
          labelKey: 'categories',
          descKey: 'svc_categories_d',
          icon: Icons.category_rounded,
          colors: AdminPalette.teal,
          onTap: () => push(const AdminCategoriesPage()),
        ),
        AdminService(
          labelKey: 'pl_requests_title',
          descKey: 'svc_pl_requests_d',
          icon: Icons.family_restroom_rounded,
          colors: AdminPalette.green,
          onTap: () => push(const AdminParentRequestsPage()),
        ),
        AdminService(
          labelKey: 'pl_settings_title',
          descKey: 'svc_pl_settings_d',
          icon: Icons.settings_suggest_rounded,
          colors: AdminPalette.violet,
          visible: isSuper,
          onTap: () => push(const AdminParentLinkSettingsPage()),
        ),
      ],
    ),

    // ── Finance ───────────────────────────────────────────────────────────
    AdminServiceGroup(
      id: 'finance',
      titleKey: 'admin_group_finance',
      subtitleKey: 'svc_group_finance_sub',
      icon: Icons.account_balance_wallet_rounded,
      colors: AdminPalette.green,
      services: [
        AdminService(
          labelKey: 'payout',
          descKey: 'svc_payout_d',
          icon: Icons.account_balance_wallet_rounded,
          colors: AdminPalette.rose,
          badge: payouts,
          onTap: () async {
            final badge = context.read<AdminPendingPayoutsProvider>();
            await push(const AdminPayoutsPage());
            badge
                .refresh(); // approve / reject / paid happened in there → recount
          },
        ),
        AdminService(
          labelKey: 'enrollment_requests',
          descKey: 'svc_enrollment_d',
          icon: Icons.how_to_reg_rounded,
          colors: AdminPalette.green,
          badge: transfers,
          featureKey: 'profile.enrollment_request',
          onTap: () => push(const TeacherTransfersScreen()),
        ),
        AdminService(
          labelKey: 'subscriptions',
          descKey: 'svc_subscriptions_d',
          icon: Icons.workspace_premium_rounded,
          colors: AdminPalette.orange,
          onTap: () => push(const AdminSubscriptionsPage()),
        ),
        AdminService(
          labelKey: 'apm_title',
          descKey: 'svc_payment_methods_d',
          icon: Icons.credit_card_rounded,
          colors: AdminPalette.blue,
          featureKey: 'profile.payment',
          onTap: () => push(const AdminPaymentsPage()),
        ),
        AdminService(
          labelKey: 'admin_payments',
          descKey: 'svc_payments_history_d',
          icon: Icons.receipt_long_rounded,
          colors: AdminPalette.teal,
          featureKey: 'profile.historical_payment',
          onTap: () => push(const AdminFinancePage()),
        ),
      ],
    ),

    // ── Support & security ────────────────────────────────────────────────
    AdminServiceGroup(
      id: 'support',
      titleKey: 'admin_group_support',
      subtitleKey: 'svc_group_support_sub',
      icon: Icons.support_agent_rounded,
      colors: AdminPalette.indigo,
      services: [
        AdminService(
          labelKey: 'help_center',
          descKey: 'svc_help_center_d',
          icon: Icons.support_agent_rounded,
          colors: AdminPalette.blue,
          badge: complaints,
          onTap: () async {
            final provider = context.read<ComplaintProvider>();
            // .value, NOT create: `create` would DISPOSE the shared provider
            // as soon as the complaints screen is popped.
            await push(
              ChangeNotifierProvider<ComplaintProvider>.value(
                value: provider,
                child: const ComplaintsScreen(),
              ),
            );
            provider
                .refreshCount(); // read / replied / status changed → recount
          },
        ),
        AdminService(
          labelKey: 'admin_devices',
          descKey: 'svc_devices_d',
          icon: Icons.devices_other_rounded,
          colors: AdminPalette.slate,
          onTap: () => push(const AdminDevicesPage()),
        ),
        AdminService(
          labelKey: 'auth_settings_title',
          descKey: 'svc_auth_d',
          icon: Icons.verified_user_rounded,
          colors: AdminPalette.indigo,
          onTap: () => push(const AdminAuthSettingsPage()),
        ),
        AdminService(
          labelKey: 'mfa',
          descKey: 'mfa',
          label: mfaEntryLabel(),
          desc: t('تطبيق مصادقة يحمي حسابك مع كلمة المرور', 'An authenticator app protects your account on top of the password'),
          icon: Icons.phonelink_lock_rounded,
          colors: AdminPalette.violet,
          onTap: () => push(const AdminMfaPage()),
        ),
        AdminService(
          labelKey: 'required_documents_title',
          descKey: 'svc_documents_d',
          icon: Icons.folder_shared_rounded,
          colors: AdminPalette.teal,
          onTap: () => push(const AdminRequiredDocumentsPage()),
        ),
      ],
    ),

    // ── App configuration ─────────────────────────────────────────────────
    AdminServiceGroup(
      id: 'config',
      titleKey: 'admin_group_config',
      subtitleKey: 'svc_group_config_sub',
      icon: Icons.tune_rounded,
      colors: AdminPalette.violet,
      services: [
        AdminService(
          labelKey: 'theme',
          descKey: 'svc_theme_d',
          icon: Icons.palette_rounded,
          colors: AdminPalette.violet,
          onTap: () => push(const AdminThemePage()),
        ),
        AdminService(
          labelKey: 'svc_platform_settings',
          descKey: 'svc_platform_settings_d',
          icon: Icons.settings_suggest_rounded,
          colors: AdminPalette.indigo,
          onTap: () => push(const AdminPlatformSettingsPage()),
        ),
        AdminService(
          labelKey: 'features',
          descKey: 'svc_features_d',
          icon: Icons.dashboard_customize_rounded,
          colors: AdminPalette.blue,
          onTap: () => push(const AdminFeaturesPage()),
        ),
        AdminService(
          labelKey: 'dl_admin_title',
          descKey: 'dl_admin_sub',
          icon: Icons.science_rounded,
          colors: AdminPalette.teal,
          featureKey: 'data_lab.admin',
          onTap: () => push(const AdminDataLabPage()),
        ),
        AdminService(
          labelKey: 'admin_flags_title',
          descKey: 'svc_flags_d',
          icon: Icons.flag_rounded,
          colors: AdminPalette.rose,
          onTap: () => push(const AdminFlagsSettingsPage()),
        ),
        AdminService(
          labelKey: 'versions',
          descKey: 'svc_versions_d',
          icon: Icons.system_update_rounded,
          colors: AdminPalette.orange,
          onTap: () => push(const AdminVersionsPage()),
        ),
        AdminService(
          labelKey: 'terms_and_conditions',
          descKey: 'svc_terms_d',
          icon: Icons.gavel_rounded,
          colors: AdminPalette.slate,
          onTap: () => push(const AdminContentPage()),
        ),
      ],
    ),
  ];
}

// ── phone: SettingsTile version of a service ─────────────────────────────────
Widget adminServiceTile(AdminService s) {
  Widget tile = Builder(
    builder: (context) => SettingsTile(
      icon: s.icon,
      iconBg: s.colors.last.withAlpha(38),
      iconColor: s.colors.last,
      label: s.labelText,
      onTap: s.onTap,
    ),
  );
  if (s.badge != null) tile = TileCountOverlay(count: s.badge!, child: tile);
  if (s.featureKey != null)
    tile = ParentComponent(featureKey: s.featureKey!, child: tile);
  return tile;
}

// ── web: hub page (one sidebar tab = one group) ──────────────────────────────
class AdminServicesHub extends StatelessWidget {
  const AdminServicesHub({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    AdminPalette.attach(context);
    context.watch<LangProvider>(); // re-translate when the language changes
    final group = adminServiceGroups(
      context,
    ).firstWhere((g) => g.id == groupId);
    final items = group.visibleServices;

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PremiumHero(
                    icon: group.icon,
                    colors: group.colors,
                    title: group.titleKey.tr,
                    subtitle: group.subtitleKey.tr,
                    footer: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        HeroPill(
                          trp('svc_count', {'n': items.length}),
                          icon: Icons.apps_rounded,
                        ),
                        if (group.badgeTotal > 0)
                          HeroPill(
                            trp('svc_pending', {'n': group.badgeTotal}),
                            icon: Icons.notifications_active_rounded,
                          ),
                      ],
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, bc) {
                      const gap = 12.0;
                      final cols = bc.maxWidth >= 820
                          ? 3
                          : (bc.maxWidth >= 520 ? 2 : 1);
                      final w = (bc.maxWidth - gap * (cols - 1)) / cols;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final s in items)
                            SizedBox(width: w, child: ServiceCard(s)),
                        ],
                      );
                    },
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

class ServiceCard extends StatelessWidget {
  const ServiceCard(this.service, {super.key});

  final AdminService service;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = service.badge ?? 0;

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: c.cardShadow,
      ),
      child: Material(
        color: c.cardBg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.divider),
        ),
        child: InkWell(
          onTap: service.onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ServiceIcon(
                  icon: service.icon,
                  colors: service.colors,
                  size: 46,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.labelText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: adminText(
                          context,
                          size: 14.5,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        service.descText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: adminText(
                          context,
                          size: 12,
                          weight: FontWeight.w500,
                          color: c.textMedium,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (count > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.danger,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: c.textLight,
                    textDirection: Directionality.of(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (service.featureKey != null) {
      card = ParentComponent(featureKey: service.featureKey!, child: card);
    }
    return card;
  }
}
