/// ─────────────────────────────────────────────────────────────────────────────
/// profile_screen.dart — the Account page of every role that has one (student, teacher, org roles).
/// D-713 / D-714: the identity header (a soft primary gradient: avatar, name, chips, the teacher's figures,
/// "Update account" and "Share"), then the rows grouped into titled section cards, each in its own colour:
/// teaching / learning · messages & schedule · money · account & security · preferences · help · sign out.
/// One column on phones; from 900 px two columns balanced by height (profileSectionColumns).
/// Profile E (D-1081): four shortcut tiles under the header (their rows leave the sections), one primary tint for
/// every icon, the exits as quiet red rows at the end and the app's version line under them.
/// Every row keeps its kill switch; the four account sections also answer to `profile.account` together.
/// ─────────────────────────────────────────────────────────────────────────────
library;


import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/design/calendar_entry.dart';
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/exams/hub/hub_entry.dart';
import 'package:flutter_education_app/features/downloads/downloads_screen.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/features/profile/student_favorite_screen.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_home_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/offline_strings.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/mfa_entry.dart' show MfaSettingsEntry;
import 'package:flutter_education_app/features/live/meeting_recording_sheets.dart' show CloudDrivesSettingsEntry;
import 'package:flutter_education_app/features/parent/student_link_code_screen.dart';
import 'package:flutter_education_app/features/courses/student/details/components/app_responsive.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/home/student/record/student_record_pages.dart';
import 'package:flutter_education_app/features/profile/teacher/payout/teacher_payouts_screen.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_screen.dart';
import 'package:flutter_education_app/features/rag/rag_chat_screen.dart' show RagChatScreen;
import 'package:flutter_education_app/features/courses/roadmap/recommendations.dart' show ProfileRecommendations;
import 'package:flutter_education_app/features/profile/about/about_and_terms_screen.dart';
import 'package:flutter_education_app/features/profile/about/about_terms_provider.dart';
import 'package:flutter_education_app/design/app_language_switch.dart' show AppLanguageTile;
import 'package:flutter_education_app/features/profile/display/display_settings_page.dart' show DisplaySettingsTile;
import 'package:flutter_education_app/features/get_app/get_app_banner.dart' show GetAppTile;
import 'package:flutter_education_app/features/rag/app_assistant.dart' show AppAssistantOpenTile, AppAssistantBubbleTile;
import 'package:flutter_education_app/features/profile/change_password_widget.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_hub_page.dart';
import 'package:flutter_education_app/features/profile/privacy_export.dart' show DataExportPage, dataExportEntryLabel;
import 'package:flutter_education_app/features/profile/switch_account_tile.dart' show SwitchAccountTile;
import 'package:flutter_education_app/features/profile/profile_provider.dart' show ProfileProvider;
import 'package:flutter_education_app/features/profile/profile_hero.dart';
import 'package:flutter_education_app/features/profile/update_account_widget.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_pages.dart' show StudyProfilePage, StudyProfileTile;
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/features/auth/reauth_sheet.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/store/manage/store_manage_api.dart' show kStoreManageFeatureKey;
import 'package:flutter_education_app/features/store/manage/store_manage_pages.dart' show StoreManagePage;
import 'package:flutter_education_app/features/quran/quran_api.dart' show kQuranTabKey;
import 'package:flutter_education_app/features/teachers/teacher_onboarding.dart' show TeacherHubPage;
import 'package:flutter_education_app/features/teachers/teachers_api.dart' show kTeacherOnboardingFeature, teacherOnboardingOff;
import 'package:flutter_education_app/features/quran/quran_teacher_hub.dart' show QuranTeacherHubPage;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/payments/points/points_api.dart' show kPointsFeatureKey;
import 'package:flutter_education_app/features/payments/points/points_wallet_page.dart' show PointsWalletPage;
import 'package:flutter_education_app/features/rewards/my_rewards_page.dart' show MyRewardsPage, MyRewardsTile;
import 'package:flutter_education_app/features/records/records_page.dart' show RecordsPage, RecordsSettingsTile;
import 'package:flutter_education_app/features/profile/public_profile/public_profile_page.dart' show MyProfileTile, ShareMyProfileTile, myShareableUsername, shareProfileLink;
import 'package:flutter_education_app/core/personal_access.dart' show PersonalAccess;
import 'package:flutter_education_app/features/profile/personal_account_tile.dart' show PersonalAccountTile;
import 'package:flutter_education_app/features/certificates/issue/cert_verify_page.dart' show CertVerifyEntryTile;
import 'package:flutter_education_app/design/app_header.dart';
import 'package:flutter_education_app/features/profile/teacher/t2b_account.dart';
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart' show TeacherStats;
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
    final isWide = context.showSidebar;
    final auth = context.read<MyAuthProvider>();
    final teacher = auth.isTeacher;
    final student = auth.currentUser?.role == 'student';
    // colour carries meaning (D-610): gold marks what a person earned (points, certificates), the danger tone is kept
    // for leaving. Each section has its own colour (D-714) so the page reads as a few subjects, not a list of 30 rows.
    final accents = ProfileSectionAccents.of(context);

    Future<void> editAccount() async {
      await _push(EditAccountScreen(isTeacher: p.role != 'student'));
      if (context.mounted) _refresh(context);
    }

    // ── The account's exits (D-1190): at the top, in the header, instead of a red group at the end ──
    Future<void> logout() async {
      final ok = await Helpers.confirmDialog(context);
      if (ok == true && context.mounted) {
        // Downloaded videos belong to this login only.
        await OfflineVideoService.instance.deleteAll();
        if (!context.mounted) return;
        await context.read<ProfileProvider>().logout(context);
      }
    }

    Future<void> deleteAccount() async {
      final ok = await Helpers.confirmDialog(
        context,
        title: "are_you_sure_to_delete_account".tr,
        confirm: "delete".tr,
      );
      if (ok != true || !context.mounted) return;
      final re = await askReauth(context); // current password (+ two-step code), S9
      if (re == null || !context.mounted) return;
      final p = context.read<ProfileProvider>();
      final after = await p.deleteAccount(context, password: re.password, mfaCode: re.mfaCode);
      if (after == null) {
        Helpers.showMessage(p.errorMessage ?? 'generic_error'.tr, isError: true);
        return;
      }
      await OfflineVideoService.instance.deleteAll();
      Helpers.showMessage('your_account_will_deleted_successfully_through_14_days'.tr);
    }

    // the old Exit group's switches keep working on the two buttons
    final off = AppConfig.disableList;
    final exitsOn = !off.contains('profile.exit_group');

    // ── The identity header (D-713): the avatar, name, chips, the teacher's figures, the actions and the exits ──
    final shareName = myShareableUsername(context);
    final hero = ProfileHero(
      name: p.name,
      role: p.role,
      email: p.email,
      username: p.username,
      imageUrl: p.imageUrl,
      heroTag: 'profile-user-${p.id}',
      onEdit: editAccount,
      onShare: shareName == null || !PersonalAccess.enabled ? null : () => shareProfileLink(context, username: shareName, name: p.name),
      onLogout: exitsOn && !off.contains('profile.logout') ? logout : null,
      onDeleteAccount: exitsOn && !off.contains('profile.delete_account') ? deleteAccount : null,
      stats: teacher ? profileTeacherFigures(context.select<TeacherHomeProvider, TeacherStats>((h) => h.stats)) : const [],
    );

    // ── My teaching / My learning ──────────────────────────────
    final work = <Widget>[
      // the ONE profile page, owner view (D-850): teachers keep the old `profile.teacher_profile` switch on it too;
      // the teacher's documents moved into its owner panel
      // personal account off (UX v3 phase 3): no public profile to open or share
      if (PersonalAccess.enabled)
        ParentComponent(featureKey: teacher ? 'profile.teacher_profile' : 'profile.my_profile', child: const MyProfileTile()),
      // The Exam Hub (D-350): teachers, and whoever teaches inside an organization; never students or parents
      // teachers open it from the shortcut tiles; a non-teacher who teaches in an organization keeps the row
      if (!teacher && examHubTeachesInAnyOrg(AppModeController.instance.liveEntries))
        AppSettingsTile(
          featureKey: kExamHubFeatureKey,
          icon: Icons.fact_check_rounded,
          label: t('الاختبارات', 'Exams'),
          subtitle: t('أنشئ وصحّح وانشر النتائج من مكان واحد', 'Create, correct and publish results in one place'),
          keywords: 'exams correction results degrees اختبارات امتحانات تصحيح نتائج درجات',
          onTap: () => _push(deferredExamHub()),
        ),
      if (!teacher) ...[
        // Downloaded (encrypted) videos — native apps only.
        if (!kIsWeb)
          AppSettingsTile(
            featureKey: 'profile.downloads',
            icon: Icons.download_for_offline_rounded,
            label: offlineT('downloads'),
            onTap: () => _push(const DownloadsScreen()),
          ),
      ],
      // the teacher's certificate requests (redesign T2b: the Certificates card opens the designs)
      if (teacher)
        AppSettingsTile(
          featureKey: 'profile.certificate_requests',
          icon: Icons.verified_outlined,
          label: 'certificate_requests'.tr,
          onTap: () => _push(deferredCertificateRequests()),
        ),
      // My rewards (Games v3): coupons, wins and the invite link, with the count of new coupons
      MyRewardsTile(onOpen: () => _push(const MyRewardsPage())),
      // Records: my meeting recordings + their edits (D-311, kill switch profile.records)
      RecordsSettingsTile(onOpen: () => _push(const RecordsPage())),
      // where those recordings are saved (feature key profile.cloud_drives)
      const CloudDrivesSettingsEntry(rowOnly: true),
    ];

    // ── Money ────────────────────────────────────────────────
    // ── Money: points, payouts and payments are shortcut tiles now (profile E); the section draws nothing ──
    final money = <Widget>[];

    // ── Messages & schedule ──────────────────────────────────
    final talk = <Widget>[
      const ChatEntryTile(), // NextBrain Messages, every role (D-374)
      const CalendarEntryTile(),
      if (teacher) ...[
        AppSettingsTile(
          featureKey: 'profile.my_ads',
          icon: Icons.campaign_rounded,
          label: 'my_ads'.tr,
          onTap: () => _push(const TeacherAdsPage()),
        ),
        // the teacher's own store items (learning hub phase 5, D-1336; kill switch store.manage)
        AppSettingsTile(
          featureKey: kStoreManageFeatureKey,
          icon: Icons.storefront_rounded,
          label: t('عناصري في المتجر', 'My store items'),
          subtitle: t('كتب وملخصات تبيعها للطلاب', 'Books and summaries you sell to students'),
          keywords: 'store books summaries notes sell متجر كتب ملخصات مذكرات',
          onTap: () => _push(const StoreManagePage()),
        ),
        // the teacher's Quran card + record sheet (learning hub phase 6, D-1347; hidden with the Quran tab). One way in
        // (D-1665): while the teacher profile is on, the record sheet and programs open from its hub instead
        if (teacherOnboardingOff())
        AppSettingsTile(
          featureKey: kQuranTabKey,
          icon: Icons.menu_book_rounded,
          label: t('تعليم القرآن', 'My Quran teaching'),
          subtitle: t('بطاقتك كمعلم وسجل التسميع', 'Your teacher card and the record sheet'),
          keywords: 'quran memorization tajweed teacher قرآن تحفيظ تجويد حلقة',
          onTap: () => _push(const QuranTeacherHubPage()),
        ),
        // every subject's teacher profile + packages (Learning Hub v2, D-1620; kill switch teacher_onboarding) is a
        // shortcut card of the teacher's page now (redesign T2b)
        // https://nextbrain.site/@name — confirmed usernames only (D-074)
        if (PersonalAccess.enabled) const ShareMyProfileTile(),
      ],
    ];

    // ── Account & security ───────────────────────────────────
    final security = <Widget>[
      // "Update account" is the header's main button (D-1190): no second row for it here
      // a student's stage / grade / school (D-790, kill switch profile.study)
      if (student) StudyProfileTile(onOpen: () => _push(const StudyProfilePage())),
      AppSettingsTile(
        featureKey: 'profile.change_password',
        icon: Icons.lock_reset_rounded,
        label: 'change_password'.tr,
        onTap: () => _push(const ChangePasswordScreen()),
      ),
      // two-step verification and fingerprint sign-in, for the roles the server allows (nothing otherwise)
      const MfaSettingsEntry(rowsOnly: true),
      // an organization member's optional personal profile (UX v3 phase 3); nothing without an organization
      const PersonalAccountTile(),
      // D-1158: the personal account and every organization account, one tap apart
      const SwitchAccountTile(),
      if (teacher)
        AppSettingsTile(
          featureKey: 'profile.device_requests',
          icon: Icons.phonelink_lock_rounded,
          label: 'device_switch_requests'.tr,
          badge: context.select<TeacherDeviceRequestsProvider, int>((p) => p.items.length),
          onTap: () => _push(const TeacherDeviceRequestsScreen()),
        ),
      // Student: temporary code to link a parent account
      if (student)
        AppSettingsTile(
          featureKey: 'profile.parent_link',
          icon: Icons.family_restroom_rounded,
          label: 'pl_link_code_title'.tr,
          onTap: () => _push(const StudentLinkCodeScreen()),
        ),
    ];

    // the four account sections answer to the old `profile.account` switch together, as the one Account group did
    Widget accountSection(AppSettingsGroup g) => ParentComponent(featureKey: 'profile.account', child: g);

    final sections = <(int, Widget)>[
      (
        work.length,
        accountSection(AppSettingsGroup(
          title: teacher ? 'profile_sec_teaching'.tr : 'profile_sec_learning'.tr,
          subtitle: teacher ? 'profile_sec_teaching_sub'.tr : 'profile_sec_learning_sub'.tr,
          icon: teacher ? Icons.school_rounded : Icons.auto_stories_rounded,
          accent: accents.work,
          children: work,
        )),
      ),
      (
        talk.length,
        accountSection(AppSettingsGroup(
          title: 'profile_sec_talk'.tr,
          subtitle: 'profile_sec_talk_sub'.tr,
          icon: Icons.forum_rounded,
          accent: accents.talk,
          children: talk,
        )),
      ),
      (
        money.length,
        accountSection(AppSettingsGroup(
          title: 'profile_sec_money'.tr,
          subtitle: teacher ? 'profile_sec_money_sub_teacher'.tr : 'profile_sec_money_sub'.tr,
          icon: Icons.account_balance_wallet_rounded,
          accent: accents.money,
          children: money,
        )),
      ),
      // ── Preferences: the quick switches stay compact ──────
      (
        6,
        ParentComponent(
          featureKey: 'profile.settings',
          child: AppSettingsGroup(
            title: 'settings'.tr,
            subtitle: 'profile_sec_prefs_sub'.tr,
            icon: Icons.tune_rounded,
            accent: accents.prefs,
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
              AppSettingsTile(
                featureKey: 'profile.dark_mode',
                icon: Icons.dark_mode_rounded,
                label: 'dark_mode'.tr,
                trailing: AppSwitch(
                  value: p.darkMode,
                  onChanged: (b) async {
                    await p.changeMode(b);
                  },
                  semanticLabel: 'dark_mode'.tr,
                ),
              ),
              const AppLanguageTile(),
              const DisplaySettingsTile(),
              const AppAssistantOpenTile(),
              const AppAssistantBubbleTile(),
              if (GetAppTile.available) const GetAppTile(), // web: the store / installer for this device
            ],
          ),
        ),
      ),

      (
        security.length,
        accountSection(AppSettingsGroup(
          title: 'profile_sec_security'.tr,
          subtitle: 'profile_sec_security_sub'.tr,
          icon: Icons.shield_rounded,
          accent: accents.security,
          children: security,
        )),
      ),

      // ── Help ───────────────────────────────────────────────
      (
        7,
        ParentComponent(
          featureKey: 'profile.help_group',
          child: AppSettingsGroup(
            title: 'help'.tr,
            subtitle: 'profile_sec_help_sub'.tr,
            icon: Icons.help_center_rounded,
            accent: accents.help,
            children: [
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
              const CertVerifyEntryTile(),
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
      ),

    ].where((s) => s.$1 > 0).toList();

    // ── Profile E (D-1081): the four most used entries as tiles under the header, each keeps its kill switch ──
    final shortcuts = teacher
        ? <AppShortcut>[
            AppShortcut(
              key: 'shortcut.exams',
              featureKey: kExamHubFeatureKey,
              icon: Icons.fact_check_rounded,
              label: t('الاختبارات', 'Exams'),
              hint: t('أنشئ وصحّح وانشر النتائج من مكان واحد', 'Create, correct and publish results in one place'),
              onTap: () => _push(deferredExamHub()),
            ),
            AppShortcut(
              key: 'shortcut.cert_designs',
              featureKey: 'profile.certificate_designs',
              icon: Icons.workspace_premium_rounded,
              label: 'cert_my_designs'.tr,
              hint: 'cert_my_designs'.tr,
              onTap: () => _push(deferredCertificateDesigns()),
            ),
            AppShortcut(
              key: 'shortcut.cert_requests',
              featureKey: 'profile.certificate_requests',
              icon: Icons.verified_rounded,
              label: 'certificate_requests'.tr,
              hint: 'certificate_requests'.tr,
              onTap: () => _push(deferredCertificateRequests()),
            ),
            AppShortcut(
              key: 'shortcut.payouts',
              featureKey: 'profile.payout',
              icon: Icons.payments_rounded,
              label: 'admin_earnings_payouts'.tr,
              hint: 'admin_earnings_payouts'.tr,
              onTap: () => _push(const TeacherPayoutsScreen()),
            ),
          ]
        : <AppShortcut>[
            AppShortcut(
              key: 'shortcut.grades',
              featureKey: 'profile.my_certificates',
              icon: Icons.workspace_premium_rounded,
              label: 'md_p7_grades_certificates'.tr,
              hint: 'md_p7_grades_certificates'.tr,
              onTap: () => _push(const StudentGradesPage()),
            ),
            AppShortcut(
              key: 'shortcut.favourites',
              featureKey: 'profile.my_favorite',
              icon: Icons.favorite_rounded,
              label: 'my_favorite'.tr,
              hint: 'my_favorite'.tr,
              onTap: () => _push(const FavouriteCoursesScreen()),
            ),
            AppShortcut(
              key: 'shortcut.points',
              featureKey: kPointsFeatureKey,
              icon: Icons.stars_rounded,
              label: t('محفظة النقاط', 'Points wallet'),
              hint: t('محفظة النقاط', 'Points wallet'),
              onTap: () => _push(const PointsWalletPage()),
            ),
            AppShortcut(
              key: 'shortcut.payments',
              featureKey: 'profile.my_payments',
              icon: Icons.receipt_long_rounded,
              label: 'md_p7_payments_subscriptions'.tr,
              hint: 'md_p7_payments_subscriptions'.tr,
              onTap: () => _push(const StudentMoneyPage()),
            ),
          ];
    // the tiles answer to the old `profile.account` switch too, as their rows did
    final shortcutRow = ParentComponent(
      featureKey: 'profile.account',
      child: Padding(padding: const EdgeInsets.only(top: AppSpace.md), child: AppShortcutRow(items: shortcuts)),
    );

    // ── The teacher's page (redesign T2b, Tea2Account): the identity hero, four cards, the same sections ──
    if (teacher) {
      final stats = context.select<TeacherHomeProvider, TeacherStats>((h) => h.stats);
      final me = stats.teacher;
      final subject = me?.teacherProfile?.specialization;
      final subjectName = subject == null ? '' : (AppConfig.lang == 'ar' ? subject.nameAr : subject.nameEn);
      final verified = me?.isVerified ?? false;
      return T2bAccountPage(
        title: isWide ? 'account'.tr : null,
        hero: T2bAccountHero(
          name: p.name,
          imageUrl: p.imageUrl,
          verified: verified,
          chips: [
            (Icons.shield_outlined, verified ? 't2_acc_verified'.tr : appRoleLabel(p.role), false),
            if (subjectName.isNotEmpty) (null, subjectName, false),
            if (p.username.isNotEmpty && isWide) (null, '@${p.username}', true),
          ],
          stats: [
            if (stats.teacher != null || stats.totalCourses > 0) ...[
              AppHeroStat(value: '${stats.totalCourses}', label: 'profile_fig_courses'.tr),
              AppHeroStat(value: '${stats.totalStudents}', label: 'profile_fig_students'.tr),
              if (stats.overallRating > 0)
                AppHeroStat(value: stats.overallRating.toStringAsFixed(1), label: 'profile_fig_rating'.tr),
            ],
          ],
          onEdit: editAccount,
          onShare: shareName == null || !PersonalAccess.enabled ? null : () => shareProfileLink(context, username: shareName, name: p.name),
        ),
        shortcuts: [
          T2bShortcut(
            id: 'exams',
            featureKey: kExamHubFeatureKey,
            accent: AppAccent.grape,
            icon: Icons.fact_check_outlined,
            title: t('الاختبارات', 'Exams'),
            meta: 't2_acc_exams_meta'.tr,
            onTap: () => _push(deferredExamHub()),
          ),
          T2bShortcut(
            id: 'certificates',
            featureKey: 'profile.certificate_designs',
            accent: AppAccent.sun,
            icon: Icons.workspace_premium_outlined,
            title: 't2_acc_certs'.tr,
            meta: 't2_acc_certs_meta'.tr,
            onTap: () => _push(deferredCertificateDesigns()),
          ),
          T2bShortcut(
            id: 'teacher_hub',
            featureKey: kTeacherOnboardingFeature,
            accent: AppAccent.sky,
            icon: Icons.inventory_2_outlined,
            title: t('ملفي كمعلم وباقاتي', 'My teacher profile and packages'),
            meta: 't2_acc_hub_meta'.tr,
            onTap: () => _push(const TeacherHubPage()),
          ),
          T2bShortcut(
            id: 'payouts',
            featureKey: 'profile.payout',
            accent: AppAccent.mint,
            icon: Icons.payments_outlined,
            title: 'admin_earnings_payouts'.tr,
            meta: 't2_acc_payouts_meta'.tr,
            onTap: () => _push(const TeacherPayoutsScreen()),
          ),
        ].where((s) => s.featureKey == null || !(off.contains(s.featureKey) || off.contains('profile.account'))).toList(),
        sections: sections,
        exits: T2bAccountExits(
          onLogout: exitsOn && !off.contains('profile.logout') ? logout : null,
          onDelete: exitsOn && !off.contains('profile.delete_account') ? deleteAccount : null,
        ),
        footer: const AppVersionLine(),
      );
    }

    // Recommended for you (students of personal accounts, D-120; draws nothing — not even its padding — otherwise)
    final recs = ProfileRecommendations(
      role: auth.currentUser?.role,
      padding: const EdgeInsets.only(top: AppSpace.xl),
    );

    // ONE orchestrated entrance (system.md §6): the hero leads, the sections follow; each plays once per route,
    // nothing under Reduce motion.
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [enter(0, hero), enter(0, shortcutRow), recs]),
            );
            final columns = profileSectionColumns([for (final s in sections) s.$1], box.maxWidth >= _twoColumnsFrom ? 2 : 1);
            Widget column(List<int> ids) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final i in ids) enter(1 + i, sections[i].$2),
                ]);
            return Padding(
              padding: EdgeInsets.fromLTRB(side, 0, side, AppSpace.xl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                top,
                if (columns.length == 1)
                  column(columns.single)
                else
                  // wide: the header spans the page, the sections fill two balanced columns under it
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: column(columns[0])),
                    const SizedBox(width: AppSpace.lg),
                    Expanded(child: column(columns[1])),
                  ]),
                const SizedBox(height: AppSpace.lg),
                const AppVersionLine(),
              ]),
            );
          }),
        ),
      ),
    );
  }

  static const double _twoColumnsFrom = 900;
}

/// The section colours of the profile page (D-714). Profile E (D-1081): every section wears the primary tint.
@immutable
class ProfileSectionAccents {
  const ProfileSectionAccents({
    required this.work,
    required this.talk,
    required this.money,
    required this.security,
    required this.prefs,
    required this.help,
  });

  final Color work, talk, money, security, prefs, help;

  static ProfileSectionAccents of(BuildContext context) {
    final c = context.colors;
    // profile E (D-1081): one primary tint for every section and icon; colour is left to the exits (danger)
    return ProfileSectionAccents(
      work: c.primary,
      talk: c.primary,
      money: c.primary,
      security: c.primary,
      prefs: c.primary,
      help: c.primary,
    );
  }
}

/// The teacher's figures in the header, from the home's stats the app already holds (no request of its own); none
/// until they have loaded.
List<ProfileHeroStat> profileTeacherFigures(TeacherStats s) {
  if (s.teacher == null && s.totalCourses == 0 && s.totalStudents == 0) return const [];
  return [
    ProfileHeroStat(icon: Icons.menu_book_rounded, value: '${s.totalCourses}', label: 'profile_fig_courses'.tr),
    ProfileHeroStat(icon: Icons.groups_rounded, value: '${s.totalStudents}', label: 'profile_fig_students'.tr),
    if (s.overallRating > 0)
      ProfileHeroStat(icon: Icons.star_rounded, value: s.overallRating.toStringAsFixed(1), label: 'profile_fig_rating'.tr),
  ];
}

/// Splits the sections (their row counts in [weights], in page order) into [count] columns of about the same height:
/// each section goes to the shorter column so far, so the two columns end level and the page has no tall empty side.
List<List<int>> profileSectionColumns(List<int> weights, int count) {
  if (count <= 1) return [List<int>.generate(weights.length, (i) => i)];
  final cols = List.generate(count, (_) => <int>[]);
  final heights = List<double>.filled(count, 0);
  for (var i = 0; i < weights.length; i++) {
    var k = 0;
    for (var j = 1; j < count; j++) {
      if (heights[j] < heights[k]) k = j;
    }
    cols[k].add(i);
    heights[k] += 1.5 + weights[i]; // a section's head is worth about a row and a half
  }
  return cols;
}
