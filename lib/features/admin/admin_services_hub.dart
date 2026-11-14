// lib/features/admin/admin_services_hub.dart
//
// ONE list of every admin service (icon, colour, label, description, badge,
// target page). It feeds two UIs:
//   • the web / rail sidebar: each group is a sidebar tab → AdminServicesHub
//   • the phone "More" tab:   each group is an AppSettingsGroup of AppSettingsTiles (searchable)
//
// So an icon / label / page is changed in exactly one place.
library;

import 'admin_study_profile_settings_page.dart' show AdminStudyProfileSettingsPage;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaints_screen.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../shared/attendance/admin_data_lab_page.dart';
import '../shared/rag/rag_admin_console.dart' show RagAdminConsole;
import 'models/ai_models_page.dart' show AiModelsPage;
import 'package:flutter_education_app/core/routing/deferred_screens.dart' show deferredExamHub;
import 'package:flutter_education_app/features/exams/paper/templates/omr_template_library.dart' show openOmrTemplateLibrary;
import 'admin_admins_page.dart';
import 'admin_auth_settings_page.dart';
import 'admin_username_stats.dart' show AdminUsernameStatsPage, kUsernameStatsFeatureKey;
import 'admin_categories_page.dart';
import 'admin_common.dart';
import 'admin_content_page.dart';
import 'admin_devices_page.dart';
import 'admin_features_page.dart';
import 'admin_feedback_settings.dart' show AdminFeedbackSettingsPage;
import 'admin_platform_settings_page.dart';
import 'admin_finance_page.dart';
import 'admin_mfa_page.dart';
import 'admin_flags_settings_page.dart';
import 'admin_organizations_page.dart';
import 'admin_payment_page.dart';
import 'admin_payouts_page.dart';
import 'admin_premium_widgets.dart';
import 'admin_providers.dart' show AdminPendingPayoutsProvider;
import 'admin_required_documents_page.dart';
import 'admin_send_message_page.dart';
import 'admin_subscriptions_page.dart';
import 'course_students/cs_pages.dart';
import 'course_trash/trash_page.dart';
import 'admin_points_page.dart';
import 'admin_recs_page.dart';
import '../shared/roadmap/roadmap_api.dart' show kRecsAdminKey;
import '../shared/points/points_api.dart' show kAdminPointsFeatureKey;
import 'admin_theme_page.dart';
import 'admin_app_versions_page.dart';
import 'admin_fees_page.dart';
import 'admin_parent_linking_page.dart';
import 'admin_recents.dart';
import 'live_settings/live_settings_page.dart' show LiveSettingsPage, kLiveSettingsFeatureKey, liveSettingsTitle;
import 'enrollment_request/teacher_transfers_provider.dart';
import 'enrollment_request/teacher_transfers_screen.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/admin/admin_datacenter_page.dart';
import 'package:flutter_education_app/features/exams/parent_grade_visibility.dart' show kParentVisibilityKey, openParentGradeVisibility;
import 'landing/admin_landing_page.dart' show AdminLandingPage, landingTitle;
import 'landing/landing_admin_api.dart' show kLandingAdminFeatureKey;

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
///
/// [watch] false: for a call from an event handler (the global search opens the list on Ctrl+K), where
/// `context.select` is not allowed; the counts are then read once.
List<AdminServiceGroup> adminServiceGroups(BuildContext context, {bool watch = true}) {
  Future<void> push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  final isSuper = isSuperNow(context);
  final payouts = watch
      ? context.select<AdminPendingPayoutsProvider, int>((p) => p.count)
      : context.read<AdminPendingPayoutsProvider>().count;
  final transfers =
      watch ? context.select<TeacherTransfersProvider, int>((p) => p.total) : context.read<TeacherTransfersProvider>().total;
  final complaints = watch ? context.select<ComplaintProvider, int>((p) => p.count) : context.read<ComplaintProvider>().count;

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
          label: t('إشعارات تتطلب الإقرار', 'Notices to acknowledge'),
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
          icon: Icons.send_rounded,
          colors: AdminPalette.blue,
          onTap: () => push(const AdminSendMessagePage()),
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
          labelKey: 'admin_parent_linking',
          descKey: 'svc_pl_requests_d',
          label: t('ربط أولياء الأمور', 'Parent linking'),
          icon: Icons.family_restroom_rounded,
          colors: AdminPalette.green,
          onTap: () => push(const AdminParentLinkingPage()),
        ),
        // the sign-up's study step, the home card, the required fields (D-794, super admin)
        AdminService(
          labelKey: 'svc_study_profile',
          descKey: 'svc_study_profile_d',
          label: t('بيانات الدراسة للطلاب', 'Student study details'),
          desc: t('خطوة المرحلة والصف عند التسجيل، بطاقة «أكمل ملفك الدراسي»، والحقول المطلوبة',
              'The stage and grade step at sign-up, the “Complete your study profile” card, and the required fields'),
          icon: Icons.school_rounded,
          colors: AdminPalette.indigo,
          // never behind profile.study itself (D-801): switching the feature off must not hide its own settings
          visible: isSuper,
          onTap: () => push(const AdminStudyProfileSettingsPage()),
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
          labelKey: 'admin_course_students',
          descKey: 'admin_course_students_d',
          label: t('الدورات والطلاب', 'Courses & students'),
          desc: t('اشتراك كل طالب في كل دورة، سبب الوصول بالضبط، والتمديد أو المنح أو الإلغاء مع السجل',
              'Every student in every course, the exact reason behind their access, and extend / grant / cancel with a history'),
          icon: Icons.groups_2_rounded,
          colors: AdminPalette.green,
          featureKey: 'admin.course_students',
          visible: isSuper,
          onTap: () => push(const CourseStudentsPage()),
        ),
        AdminService(
          labelKey: 'admin_course_trash',
          descKey: 'admin_course_trash_d',
          label: t('الكورسات المحذوفة', 'Deleted courses'),
          desc: t('سلة الكورسات المحذوفة: استرجاع الكورس بطلابه أو حذفه نهائياً مع السجل',
              'The trash of deleted courses: restore a course with its students, or delete it permanently, with the history'),
          icon: Icons.delete_sweep_outlined,
          colors: AdminPalette.rose,
          featureKey: 'admin.course_trash',
          visible: isSuper,
          onTap: () => push(const CourseTrashPage()),
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
          labelKey: 'admin_fees',
          descKey: 'admin_fees_d',
          label: t('الرسوم', 'Fees'),
          desc: t('نسب الرسوم لكل وسيلة دفع والمنصة والضريبة، وسياسة من يتحمل الرسوم',
              'Fee rates per payment method, the platform and VAT, and the policy of who pays them'),
          icon: Icons.percent_rounded,
          colors: AdminPalette.blue,
          onTap: () => push(const AdminFeesPage()),
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
          labelKey: 'admin_landing',
          descKey: 'admin_landing_d',
          label: landingTitle(),
          desc: t('حد الطلبات على أرقام الصفحة الرئيسية، واختيار آراء الطلاب الحقيقية التي تظهر للزوار',
              'The request limit on the landing page numbers, and which real student reviews visitors see'),
          icon: Icons.web_rounded,
          colors: AdminPalette.blue,
          visible: isSuper,
          featureKey: kLandingAdminFeatureKey,
          onTap: () => push(const AdminLandingPage()),
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
          desc: t('سجل التصدير، التصدير المجدول، والروابط المشتركة', 'The export log, scheduled exports and shared links'),
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
        // The Exam Hub (D-350): every exam, its correction and its results in one place
        AdminService(
          labelKey: 'svc_exam_hub',
          descKey: 'svc_exam_hub_d',
          label: t('الاختبارات', 'Exams'),
          desc: t('إنشاء الاختبارات وتصحيحها ونتائجها من مكان واحد', 'Create exams, correct them and publish results in one place'),
          icon: Icons.fact_check_rounded,
          colors: AdminPalette.indigo,
          featureKey: 'exam.hub',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredExamHub())),
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
        // the grading-corrections store (it was reachable only from inside Platform settings)
        AdminService(
          labelKey: 'admin_feedback_settings',
          descKey: 'admin_feedback_settings_d',
          label: t('بيانات تصحيح الامتحانات', 'Grading feedback store'),
          desc: t('جمع تصحيحات المعلمين لتحسين التصحيح الآلي: التفعيل، الافتراضي للمؤسسات، مدة الاحتفاظ، والتصدير',
              'Collect teachers’ corrections to improve automatic grading: on/off, organization default, retention and export'),
          icon: Icons.rate_review_rounded,
          colors: AdminPalette.rose,
          visible: isSuper,
          onTap: () => push(const AdminFeedbackSettingsPage()),
        ),
        AdminService(
          labelKey: 'admin_flags_title',
          descKey: 'svc_flags_d',
          label: t('علامات المراجعة والقراءة للطلاب', 'Student review & read flags'),
          icon: Icons.flag_rounded,
          colors: AdminPalette.rose,
          onTap: () => push(const AdminFlagsSettingsPage()),
        ),
        // app versions (D-144, ONE screen since D-309): per platform the latest / minimum version, the update message
        // with a live preview and the link; "Build a version" (Codemagic / runner) is its primary action
        AdminService(
          labelKey: 'svc_app_releases',
          descKey: 'svc_app_releases_d',
          label: t('إصدارات التطبيق', 'App versions'),
          desc: t('أحدث إصدار وأقل إصدار مسموح لكل منصة، ورسالة التحديث مع معاينتها، وبناء إصدار جديد',
              'Each platform’s latest and minimum version, the update message with its preview, and new builds'),
          icon: Icons.rocket_launch_rounded,
          colors: AdminPalette.indigo,
          onTap: () => push(const AdminAppVersionsPage()),
        ),
        AdminService(
          labelKey: 'terms_and_conditions',
          descKey: 'svc_terms_d',
          label: t('من نحن والشروط', 'About & terms'),
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
      onTap: () => _openService(s),
    );

/// Opens a service and remembers it for the Overview's "Recently opened" (and the search palette's Recent).
void _openService(AdminService s) {
  AdminRecents.instance.record(s.labelKey);
  s.onTap();
}


// ── wide shells: hub page (one sidebar tab = one group) ──────────────────────
/// No hero (the shell's top bar already names the tab): a search field that filters the group's services by label
/// and description, then a grid of tiles that fills the width up to [maxWidth].
class AdminServicesHub extends StatefulWidget {
  const AdminServicesHub({super.key, required this.groupId, this.onRefresh});

  final String groupId;

  /// Reloads the counts on the cards (the dashboard's badge refresh); null = no pull-to-refresh.
  final Future<void> Function()? onRefresh;

  static const double maxWidth = 1440;

  /// 1 column on a narrow window, then 2 → 3 → 4 → 5.
  static int columnsFor(double width) => width >= 1320 ? 5 : (width >= 960 ? 4 : (width >= 700 ? 3 : (width >= 440 ? 2 : 1)));

  /// The services of [items] whose label or description contains every word of [q].
  static List<AdminService> filter(List<AdminService> items, String q) {
    final words = q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return items;
    return [
      for (final s in items)
        if (words.every('${s.labelText} ${s.descText}'.toLowerCase().contains)) s,
    ];
  }

  @override
  State<AdminServicesHub> createState() => _AdminServicesHubState();
}

class _AdminServicesHubState extends State<AdminServicesHub> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    AdminPalette.attach(context);
    context.watch<LangProvider>(); // re-translate when the language changes
    final group = adminServiceGroups(context).firstWhere((g) => g.id == widget.groupId);
    final all = group.visibleServices;
    final items = AdminServicesHub.filter(all, _q);
    final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);

    final body = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(g, AppSpace.md, g, AppSpace.xl),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AdminServicesHub.maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSearchField(
                hint: t('ابحث في ${group.titleKey.tr}', 'Search ${group.titleKey.tr}'),
                onChanged: (v) => setState(() => _q = v),
              ),
              AppSpace.gapMd,
              if (items.isEmpty)
                AppEmpty(
                  icon: Icons.search_off_rounded,
                  title: t('لا توجد خدمة بهذا الاسم', 'No service matches'),
                  message: t('جرّب كلمة أخرى', 'Try another word'),
                )
              else
                _grid(items),
            ]),
          ),
        ),
      ],
    );
    return SafeArea(
      child: widget.onRefresh == null ? body : AppRefresh(onRefresh: widget.onRefresh!, child: body),
    );
  }

  Widget _grid(List<AdminService> items) => LayoutBuilder(builder: (context, box) {
        final cols = AdminServicesHub.columnsFor(box.maxWidth);
        final rows = (items.length / cols).ceil();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) AppSpace.gapSm,
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < cols; i++) ...[
                  if (i > 0) AppSpace.gapSm,
                  Expanded(child: r * cols + i < items.length ? ServiceCard(items[r * cols + i]) : const SizedBox.shrink()),
                ],
              ]),
            ),
          ],
        ]);
      });
}

/// One service tile: a brand-tint icon square, the name, up to two lines of description, and the count (or a
/// chevron). The whole tile is the target (≥ 48 px, focusable, Enter / Space).
class ServiceCard extends StatelessWidget {
  const ServiceCard(this.service, {super.key});

  final AdminService service;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = service.badge ?? 0;

    Widget card = Semantics(
      button: true,
      container: true,
      label: '${service.labelText}. ${service.descText}',
      excludeSemantics: true,
      onTap: () => _openService(service),
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: c.divider, width: AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openService(service),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary + AppSpace.md),
            child: Padding(
              padding: AppSpace.card,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: AppTouch.min - AppSpace.xs,
                  height: AppTouch.min - AppSpace.xs,
                  decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
                  child: Icon(service.icon, size: AppIconSize.lg, color: c.primary),
                ),
                AppSpace.gapSm,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(service.labelText, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                    const SizedBox(height: AppSpace.xxs),
                    Text(service.descText, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  ]),
                ),
                AppSpace.gapSm,
                if (count > 0)
                  AppCountBadge(count: count)
                else
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Icon(Icons.arrow_forward_ios_rounded, size: AppIconSize.xs, color: c.textLight),
                  ),
              ]),
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
