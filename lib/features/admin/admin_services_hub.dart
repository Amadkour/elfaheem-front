// lib/features/admin/admin_services_hub.dart
//
// ONE list of every admin service (icon, colour, label, description, badge,
// target page). It feeds two UIs:
//   • the web / rail sidebar: each group is a sidebar tab → AdminServicesHub
//   • the phone "More" tab:   each group is an AppSettingsGroup of AppSettingsTiles (searchable)
//
// So an icon / label / page is changed in exactly one place.
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaints_screen.dart';
import 'package:flutter_education_app/features/student/courses/details/components/app_responsive.dart'
    show Breakpoints;
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../shared/attendance/admin_data_lab_page.dart';
import '../shared/rag/rag_admin_console.dart' show RagAdminConsole;
import 'models/ai_models_page.dart' show AiModelsPage;
import '../shared/exam_engine/paper/templates/omr_template_library.dart' show openOmrTemplateLibrary;
import 'admin_admins_page.dart';
import 'admin_auth_settings_page.dart';
import 'admin_username_stats.dart' show AdminUsernameStatsPage, kUsernameStatsFeatureKey;
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
import 'admin_points_page.dart';
import 'admin_recs_page.dart';
import '../shared/roadmap/roadmap_api.dart' show kRecsAdminKey;
import '../shared/points/points_api.dart' show kAdminPointsFeatureKey;
import 'admin_theme_page.dart';
import 'admin_users_page.dart';
import 'admin_versions_page.dart';
import 'admin_view_as_page.dart';
import 'live_settings/live_settings_page.dart' show LiveSettingsPage, kLiveSettingsFeatureKey, liveSettingsTitle;
import 'enrollment_request/teacher_transfers_provider.dart';
import 'enrollment_request/teacher_transfers_screen.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/admin/admin_datacenter_page.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'app_releases/app_releases_page.dart';
import '../shared/exam_engine/parent_grade_visibility.dart' show kParentVisibilityKey, openParentGradeVisibility;

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
          labelKey: 'admin_points',
          descKey: 'admin_points_d',
          label: t('النقاط والمحافظ', 'Points & wallets'),
          desc: t('طلبات شحن النقاط، أرصدة المستخدمين، وإعدادات باقة الاجتماعات المباشرة',
              'Points top-ups, user balances and the live-meeting plan settings'),
          icon: Icons.stars_rounded,
          colors: AdminPalette.indigo,
          featureKey: kAdminPointsFeatureKey,
          onTap: () => push(const AdminPointsPage()),
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
          labelKey: 'admin_username_stats',
          descKey: 'admin_username_stats_d',
          label: t('أسماء المستخدمين', 'Usernames'),
          desc: t('هل يستخدم الناس اسم المستخدم: من أكّده أو غيّره، وطرق تسجيل الدخول',
              'Is the @username used: who kept or changed it, and how people sign in'),
          icon: Icons.alternate_email_rounded,
          colors: AdminPalette.teal,
          featureKey: kUsernameStatsFeatureKey,
          onTap: () => push(const AdminUsernameStatsPage()),
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
          labelKey: 'admin_live_settings',
          descKey: 'admin_live_settings_d',
          label: liveSettingsTitle(),
          desc: t('الترميز، ضعف الشبكة، جودة الكاميرات والشاشة، ومكان التسجيل — لكل الأجهزة دون تحديث',
              'Codec, weak networks, camera and screen quality, and where classes are recorded — no app update'),
          icon: Icons.speed_rounded,
          colors: AdminPalette.rose,
          visible: isSuper,
          featureKey: kLiveSettingsFeatureKey,
          onTap: () => push(const LiveSettingsPage()),
        ),
        AdminService(
          labelKey: 'admin_recommendations',
          descKey: 'admin_recommendations_d',
          label: t('التوصيات', 'Recommendations'),
          desc: t('ما يُقترح على الطلاب: الأرقام حسب السبب، وأوزان المحرّك', 'What students are suggested: numbers per reason and the engine’s weights'),
          icon: Icons.auto_awesome_rounded,
          colors: AdminPalette.violet,
          visible: isSuper,
          featureKey: kRecsAdminKey,
          onTap: () => push(const AdminRecommendationsPage()),
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
        // Export Studio (D-130): the export log, scheduled exports and shared links; each section has its own key
        AdminService(
          labelKey: 'exs_center_title',
          descKey: 'exs_center_admin',
          icon: Icons.ios_share_rounded,
          colors: AdminPalette.teal,
          onTap: () => Navigator.pushNamed(context, '/exports', arguments: true),
        ),
        AdminService(
          labelKey: 'svc_app_assistant',
          descKey: 'svc_app_assistant_d',
          label: t('لوحة المساعد الذكي', 'AI assistant console'),
          desc: t('إعدادات النموذج والوكلاء، التحليلات، تجربة الأسئلة مع مسارها، ومستندات التطبيق',
              'Model and agent settings, analytics, a playground with every step traced, and the app documents'),
          icon: Icons.auto_awesome_rounded,
          colors: AdminPalette.indigo,
          featureKey: 'rag.admin',
          onTap: () => push(const RagAdminConsole()),
        ),
        // the model hub (D-152): the models behind the assistant, the exam grader and the paper scanner
        AdminService(
          labelKey: 'svc_ai_models',
          descKey: 'svc_ai_models_d',
          label: t('نماذج الذكاء الاصطناعي', 'AI Models'),
          desc: t('تنزيل النماذج واختبارها وتفعيلها والرجوع عنها، النموذج الاحتياطي، حدود الموارد، وسجل التغييرات',
              'Download, test, activate and roll back models; fallbacks, resource limits and the change log'),
          icon: Icons.memory_rounded,
          colors: AdminPalette.violet,
          featureKey: 'models.admin',
          visible: isSuper,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              settings: const RouteSettings(name: AiModelsPage.routeName), builder: (_) => const AiModelsPage())),
        ),
        // paper exams (D-155): the global library of bubble-sheet types, learned sheets, approvals
        AdminService(
          labelKey: 'svc_omr_templates',
          descKey: 'svc_omr_templates_d',
          label: t('أنواع أوراق التظليل', 'Bubble sheet types'),
          desc: t('مكتبة أوراق التظليل وإصداراتها، تعليم المنصة ورقة جديدة، واعتماد أوراق المعلمين',
              'The bubble sheet library and its versions, teaching the platform a new sheet, approving the sheets teachers send'),
          icon: Icons.grid_on_rounded,
          colors: AdminPalette.teal,
          featureKey: 'exam.omr',
          visible: isSuper,
          onTap: () => openOmrTemplateLibrary(context),
        ),
        // grades (D-244): whether parents see their child's grades — always / when published / never
        AdminService(
          labelKey: 'svc_parent_grades',
          descKey: 'svc_parent_grades_d',
          label: t('رؤية أولياء الأمور للدرجات', 'What parents see of grades'),
          desc: t('القاعدة الافتراضية للمنصة: دائماً، عند النشر، أو أبداً', 'The platform default: always, when published, or never'),
          icon: Icons.family_restroom_rounded,
          colors: AdminPalette.teal,
          featureKey: kParentVisibilityKey,
          visible: isSuper,
          onTap: () => openParentGradeVisibility(context),
        ),
        AdminService(
          labelKey: 'admin_flags_title',
          descKey: 'svc_flags_d',
          icon: Icons.flag_rounded,
          colors: AdminPalette.rose,
          onTap: () => push(const AdminFlagsSettingsPage()),
        ),
        // app versions from the dashboard (D-144): Codemagic builds them, then the store or our website's download
        // banner; going live also fills the update prompt below, which stays for a manual override
        AdminService(
          labelKey: 'svc_app_releases',
          descKey: 'svc_app_releases_d',
          label: t('إصدارات التطبيق (بناء ونشر)', 'App versions (build & publish)'),
          desc: t('بناء إصدار جديد لأندرويد أو الويب أو لينكس أو ويندوز على Codemagic ونشره على المتجر أو في شريط التحميل بالموقع',
              'Build a new Android, web, Linux or Windows version on Codemagic and publish it to the store or the website download banner'),
          icon: Icons.rocket_launch_rounded,
          colors: AdminPalette.indigo,
          featureKey: kAppReleasesFeatureKey,
          visible: isSuper,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              settings: const RouteSettings(name: AppReleasesPage.routeName), builder: (_) => deferredAppReleases())),
        ),
        AdminService(
          labelKey: 'versions',
          descKey: 'svc_versions_d',
          label: t('رسالة التحديث', 'Update prompt'),
          desc: t('الإصدار الذي يطلب التطبيق من المستخدمين التحديث إليه (إجباري أو مُوصى به)، دون بناء',
              'The version the app asks users to update to (forced or recommended), without building'),
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

// ── phone: settings-row version of a service (the description doubles as search text) ──
Widget adminServiceTile(AdminService s) => AppSettingsTile(
      icon: s.icon,
      color: s.colors.last,
      label: s.labelText,
      subtitle: s.descText,
      badge: s.badge,
      featureKey: s.featureKey,
      onTap: s.onTap,
    );

// ── web: hub page (one sidebar tab = one group) ──────────────────────────────
class AdminServicesHub extends StatelessWidget {
  const AdminServicesHub({super.key, required this.groupId, this.onRefresh});

  final String groupId;

  /// Reloads the counts on the cards (the dashboard's badge refresh); null = no pull-to-refresh.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    AdminPalette.attach(context);
    context.watch<LangProvider>(); // re-translate when the language changes
    final group = adminServiceGroups(
      context,
    ).firstWhere((g) => g.id == groupId);
    final items = group.visibleServices;

    final body = SingleChildScrollView(
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
      );
    return SafeArea(
      child: onRefresh == null ? body : AppRefresh(onRefresh: onRefresh!, child: body),
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
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: c.onHero,
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
