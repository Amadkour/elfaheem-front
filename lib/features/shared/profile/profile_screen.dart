/// ─────────────────────────────────────────────────────────────────────────────
/// profile_screen.dart (Teacher)
/// Uses `context.colors` everywhere instead of hardcoded context.colors constants
/// so dark / light mode is automatic — no extra logic needed here.
/// ─────────────────────────────────────────────────────────────────────────────
library;


import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/design/calendar_entry.dart';
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/hub_entry.dart';
import 'package:flutter_education_app/features/shared/downloads/downloads_screen.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/features/shared/profile/student_favorite_screen.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/offline/offline_strings.dart';
import '../../auth/auth_provider.dart';
import '../../auth/mfa_entry.dart' show MfaSettingsEntry;
import '../live/meeting_recording_sheets.dart' show CloudDrivesSettingsEntry;
import '../../parent/student_link_code_screen.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../../utils/widget/parent_component.dart';
import '../../student/record/student_record_pages.dart';
import '../../teacher/profile/payout/teacher_payouts_screen.dart';
import '../../teacher/profile/switch_device_requests/teacher_device_requests_provider.dart';
import '../../teacher/profile/switch_device_requests/teacher_device_requests_screen.dart';
import '../rag/rag_chat_screen.dart' show RagChatScreen;
import '../roadmap/recommendations.dart' show ProfileRecommendations;
import 'about/about_and_terms_screen.dart';
import 'about/about_terms_provider.dart';
import '../../../design/app_language_switch.dart' show AppLanguageTile;
import '../display/display_settings_page.dart' show DisplaySettingsTile;
import 'package:flutter_education_app/features/shared/get_app/get_app_banner.dart' show GetAppTile;
import '../rag/app_assistant.dart' show AppAssistantOpenTile, AppAssistantBubbleTile;
import 'change_password_widget.dart';
import 'compalints/complaint_provider.dart';
import 'compalints/complaints_hub_page.dart';
import 'course_instractor_profile.dart';
import 'privacy_export.dart' show DataExportPage, dataExportEntryLabel;
import 'profile_provider.dart' show ProfileProvider;
import 'profile_hero.dart';
import 'update_account_widget.dart';
import '../../../utils/helpers.dart';
import '../../auth/reauth_sheet.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import '../../admin/admin_common.dart' show t;
import '../points/points_api.dart' show kPointsFeatureKey;
import '../points/points_wallet_page.dart' show PointsWalletPage;
import '../records/records_page.dart' show RecordsPage, RecordsSettingsTile;
import '../public_profile/public_profile_page.dart' show ShareMyProfileTile;
import 'package:flutter_education_app/features/shared/certificates_issue/cert_verify_page.dart' show CertVerifyEntryTile;
import 'package:flutter_education_app/design/app_header.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/design/app_tokens.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<ProfileScreen> {
  Future<void> _push(Widget screen) async => await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => screen));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh(context);
    });
    AppModeController.instance.addListener(_onOrgsChanged); // "teaches in an organization" arrives with the overview
  }

  void _onOrgsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppModeController.instance.removeListener(_onOrgsChanged);
    super.dispose();
  }

  void _refresh(BuildContext context) {
    context.read<ProfileProvider>().initData(
      context.read<MyAuthProvider>().currentUser,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProfileProvider>();
    final c = context.colors; // ← dynamic palette (light / dark)
    final isWide = context.showSidebar;
    final auth = context.read<MyAuthProvider>();
    // colour carries meaning only (D-610): the primary well is the row's default, gold marks what a person earned
    // (points, certificates), the danger tone is kept for leaving.
    final earned = c.accent2;

    Future<void> editAccount() async {
      await _push(EditAccountScreen(isTeacher: p.role != 'student'));
      if (context.mounted) _refresh(context);
    }

    // ── The hero block: the page's one tinted surface (the avatar opens "edit account", same as the tile) ──
    final hero = ProfileHero(
      name: p.name,
      role: p.role,
      email: p.email,
      username: p.username,
      imageUrl: p.imageUrl,
      heroTag: 'profile-user-${p.id}',
      onEdit: editAccount,
    );

    // ── Account section ──────────────────────────────────────
    final account = ParentComponent(
      featureKey: 'profile.account',
      child: AppSettingsGroup(
        title: 'account'.tr,
        icon: Icons.account_circle_rounded,
        children: [
          AppSettingsTile(
            featureKey: 'profile.update_account',
            icon: Icons.manage_accounts_rounded,
            label: 'update_account'.tr,
            onTap: editAccount,
          ),
          AppSettingsTile(
            featureKey: 'profile.change_password',
            icon: Icons.lock_reset_rounded,
            label: 'change_password'.tr,
            onTap: () => _push(const ChangePasswordScreen()),
          ),
          const CalendarEntryTile(),
          const ChatEntryTile(), // NextBrain Messages, every role (D-374)
          // The Exam Hub (D-350): teachers, and whoever teaches inside an organization; never students or parents
          if (auth.isTeacher || examHubTeachesInAnyOrg(AppModeController.instance.liveEntries))
            AppSettingsTile(
              featureKey: kExamHubFeatureKey,
              icon: Icons.fact_check_rounded,
              label: t('الاختبارات', 'Exams'),
              subtitle: t('أنشئ وصحّح وانشر النتائج من مكان واحد', 'Create, correct and publish results in one place'),
              keywords: 'exams correction results degrees اختبارات امتحانات تصحيح نتائج درجات',
              onTap: () => _push(deferredExamHub()),
            ),
          // Points wallet + the student live-meeting plan (live-rooms-spec §8 – §9)
          AppSettingsTile(
            featureKey: kPointsFeatureKey,
            icon: Icons.stars_rounded,
            color: earned,
            label: t('محفظة النقاط', 'Points wallet'),
            keywords: 'points wallet نقاط محفظة',
            onTap: () => _push(const PointsWalletPage()),
          ),
          // Records: my meeting recordings + their edits (D-311, kill switch profile.records)
          RecordsSettingsTile(onOpen: () => _push(const RecordsPage())),
          // Downloaded (encrypted) videos — native apps only.
          if (!kIsWeb && !auth.isTeacher)
            AppSettingsTile(
              featureKey: 'profile.downloads',
              icon: Icons.download_for_offline_rounded,
              label: offlineT('downloads'),
              onTap: () => _push(const DownloadsScreen()),
            ),
          if (auth.isTeacher) ...[
            AppSettingsTile(
              featureKey: 'profile.my_ads',
              icon: Icons.campaign_rounded,
              label: 'my_ads'.tr,
              onTap: () => _push(const TeacherAdsPage()),
            ),
            AppSettingsTile(
              featureKey: 'profile.certificate_designs',
              icon: Icons.workspace_premium_rounded,
              color: earned,
              label: 'cert_my_designs'.tr,
              // personal designs: usable on every course of this teacher (no organization needed)
              onTap: () => _push(deferredCertificateDesigns()),
            ),
            AppSettingsTile(
              featureKey: 'profile.teacher_profile',
              icon: Icons.badge_rounded,
              label: 'teacher_profile'.tr,
              onTap: () => _push(
                InstructorProfileScreen(
                  teacher: context.read<TeacherHomeProvider>().stats.teacher!,
                  studentView: false,
                  stats: context.read<TeacherHomeProvider>().stats,
                ),
              ),
            ),
            // https://nextbrain.site/@name — confirmed usernames only (D-074)
            const ShareMyProfileTile(),
            AppSettingsTile(
              featureKey: 'profile.certificate_requests',
              icon: Icons.workspace_premium_rounded,
              color: earned,
              label: 'certificate_requests'.tr,
              onTap: () => _push(deferredCertificateRequests()),
            ),
            AppSettingsTile(
              featureKey: 'profile.payout',
              icon: Icons.payments_rounded,
              label: 'admin_earnings_payouts'.tr, // the page it opens (L4)
              onTap: () => _push(const TeacherPayoutsScreen()),
            ),
            AppSettingsTile(
              featureKey: 'profile.device_requests',
              icon: Icons.phonelink_lock_rounded,
              label: 'device_switch_requests'.tr,
              badge: context.select<TeacherDeviceRequestsProvider, int>((p) => p.items.length),
              onTap: () => _push(const TeacherDeviceRequestsScreen()),
            ),
          ] else ...[
            // Student: temporary code to link a parent account
            if (auth.currentUser?.role == 'student')
              AppSettingsTile(
                featureKey: 'profile.parent_link',
                icon: Icons.family_restroom_rounded,
                label: 'pl_link_code_title'.tr,
                onTap: () => _push(const StudentLinkCodeScreen()),
              ),
            AppSettingsTile(
              featureKey: 'profile.my_certificates',
              icon: Icons.workspace_premium_rounded,
              color: earned,
              label: 'md_p7_grades_certificates'.tr,
              onTap: () => _push(const StudentGradesPage()),
            ),
            AppSettingsTile(
              featureKey: 'profile.my_payments',
              icon: Icons.receipt_long_rounded,
              label: 'md_p7_payments_subscriptions'.tr,
              onTap: () => _push(const StudentMoneyPage()),
            ),
            AppSettingsTile(
              featureKey: 'profile.my_favorite',
              icon: Icons.favorite_rounded,
              label: 'my_favorite'.tr,
              onTap: () => _push(const FavouriteCoursesScreen()),
            ),
          ],
        ],
      ),
    );

    final rest = <Widget>[
      // ── Security: two-step verification, for the roles the server allows (hidden otherwise) ──
      const MfaSettingsEntry(gap: 0),

      // ── Cloud: connected drives for meeting recordings (feature key profile.cloud_drives) ──
      const CloudDrivesSettingsEntry(gap: 0),

      // ── Settings section ─────────────────────────────────────
      ParentComponent(
        featureKey: 'profile.settings',
        child: AppSettingsGroup(
          title: 'settings'.tr,
          icon: Icons.settings_rounded,
          children: [
            AppSettingsTile(
              featureKey: 'profile.notifications',
              icon: Icons.notifications_active_rounded,
              label: 'notifications'.tr,
              trailing: AppSwitch(
                value: p.notificationsEnabled,
                onChanged: p.toggleNotifications,
                semanticLabel: 'notifications'.tr,
              ),
            ),
            const AppLanguageTile(),
            const DisplaySettingsTile(),
            if (GetAppTile.available) const GetAppTile(), // web: the store / installer for this device
            const AppAssistantOpenTile(),
            const AppAssistantBubbleTile(),
            AppSettingsTile(
              featureKey: 'profile.dark_mode',
              icon: Icons.dark_mode_rounded,
              color: c.textDark,
              label: 'dark_mode'.tr,
              trailing: AppSwitch(
                value: p.darkMode,
                onChanged: (b) async {
                  await p.changeMode(b);
                },
                semanticLabel: 'dark_mode'.tr,
              ),
            ),
          ],
        ),
      ),

      // ── Help section ─────────────────────────────────────────
      ParentComponent(
        featureKey: 'profile.help_group',
        child: AppSettingsGroup(
          title: 'help'.tr,
          icon: Icons.help_center_rounded,
          children: [
            const CertVerifyEntryTile(),
            AppSettingsTile(
              featureKey: 'profile.help_center',
              // One page for every role here (D-086): New complaint · My complaints ·
              // To resolve (non-students). The super admin keeps the admin console.
              // The teacher dashboard provides a shared ComplaintProvider
              // (badge). Students don't — nullable lookup returns null there.
              badge: context.select<ComplaintProvider?, int>((p) => p?.count ?? 0),
              onTap: () async {
                final shared = Provider.of<ComplaintProvider?>(context, listen: false);
                await _push(const ComplaintsHubPage());
                shared?.refreshCount();
              },
              icon: Icons.support_agent_rounded,
              // named after the page it opens (L5: "Help center" opened the complaints list)
              label: 'complaints_and_support'.tr,
              keywords: 'help center support complaints مساعدة دعم شكاوى',
            ),
            AppSettingsTile(
              featureKey: 'profile.app_assistant',
              icon: Icons.question_answer_rounded,
              label: 'app_assistant'.tr,
              onTap: () => _push(const RagChatScreen(app: true)),
            ),
            // the privacy policy and the terms of service, each its own page (D-308)
            AppSettingsTile(
              featureKey: 'profile.privacy',
              icon: Icons.privacy_tip_rounded,
              label: 'privacy_policy'.tr,
              keywords: 'privacy data google drive cookies الخصوصية البيانات',
              onTap: () => _push(const TermsScreen(privacy: true)),
            ),
            AppSettingsTile(
              featureKey: 'profile.terms',
              icon: Icons.gavel_rounded,
              label: 'terms_of_service'.tr,
              keywords: 'terms conditions rules refund الشروط الأحكام الاسترداد',
              onTap: () => _push(const TermsScreen()),
            ),
            AppSettingsTile(
              featureKey: 'profile.data_export',
              icon: Icons.inventory_2_rounded,
              label: dataExportEntryLabel(),
              onTap: () => _push(const DataExportPage()),
            ),
            AppSettingsTile(
              featureKey: 'profile.about',
              icon: Icons.info_rounded,
              label: 'about'.tr,
              onTap: () => _push(
                ChangeNotifierProvider(
                  create: (_) => AboutTermsProvider(),
                  child: AboutScreen(),
                ),
              ),
            ),
          ],
        ),
      ),

      // ── Logout ───────────────────────────────────────────────
      ParentComponent(
        featureKey: 'profile.exit_group',
        child: AppSettingsGroup(
          title: 'exit'.tr,
          icon: DirIcons.exitToApp,
          danger: true,
          children: [
            AppSettingsTile(
              featureKey: 'profile.logout',
              icon: DirIcons.logout,
              color: c.danger,
              label: 'logout'.tr,
              onTap: () async {
                final ok = await Helpers.confirmDialog(context);
                if (ok == true && context.mounted) {
                  // Downloaded videos belong to this login only.
                  await OfflineVideoService.instance.deleteAll();
                  if (!context.mounted) return;
                  await context.read<ProfileProvider>().logout(
                    context,
                  );
                }
              },
            ),
            AppSettingsTile(
              featureKey: 'profile.delete_account',
              icon: Icons.delete_forever_rounded,
              color: c.danger,
              label: 'delete_account_title'.tr,
              onTap: () async {
                final ok = await Helpers.confirmDialog(
                  context,
                  title: "are_you_sure_to_delete_account".tr,
                  confirm: "delete".tr,
                );
                if (ok != true || !context.mounted) return;
                final re = await askReauth(context); // current password (+ two-step code), S9
                if (re == null || !context.mounted) return;
                final p = context.read<ProfileProvider>();
                final after = await p.deleteAccount(context,
                    password: re.password, mfaCode: re.mfaCode);
                if (after == null) {
                  Helpers.showMessage(p.errorMessage ?? 'generic_error'.tr, isError: true);
                  return;
                }
                await OfflineVideoService.instance.deleteAll();
                Helpers.showMessage(
                  'your_account_will_deleted_successfully_through_14_days'
                      .tr,
                );
              },
            ),
          ],
        ),
      ),
    ];

    // Recommended for you (students of personal accounts, D-120; draws nothing — not even its padding — otherwise)
    final recs = ProfileRecommendations(
      role: auth.currentUser?.role,
      padding: const EdgeInsets.only(top: AppSpace.xl),
    );

    // ONE orchestrated entrance (system.md §6): the hero leads, the account group follows, the rest arrives with it;
    // each plays once per route, nothing under Reduce motion.
    Widget enter(int i, Widget w) => AppReveal(index: i, group: 'profile', child: w);

    return BasePage(
      key: const ValueKey('profile'),
      useWebCard: true,
      width: AppWidth.content,
      enableFooterWidget: false,
      appBar: isWide ? AppHeader(title: 'account'.tr, showBack: Navigator.of(context).canPop()) : null,
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: LayoutBuilder(builder: (context, box) {
            // a phone page uses the whole width: its gutter is ours; a wide page sits in BasePage's card already
            final side = box.maxWidth < AppWidth.phoneMax ? AppSpace.gutter(box.maxWidth) : 0.0;
            final top = Padding(
              padding: const EdgeInsets.only(top: AppSpace.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [enter(0, hero), recs]),
            );
            if (box.maxWidth < _twoColumnsFrom) {
              return Padding(
                padding: EdgeInsets.fromLTRB(side, 0, side, AppSpace.xl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  top,
                  enter(1, account),
                  enter(2, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rest)),
                ]),
              );
            }
            // wide: the hero spans the page as a masthead, the account on one side, settings and help on the other
            return Padding(
              padding: EdgeInsets.fromLTRB(side, 0, side, AppSpace.xl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                top,
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: enter(1, account)),
                  const SizedBox(width: AppSpace.xl),
                  Expanded(child: enter(2, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rest))),
                ]),
              ]),
            );
          }),
        ),
      ),
    );
  }

  static const double _twoColumnsFrom = 900;
}
