/// ─────────────────────────────────────────────────────────────────────────────
/// profile_screen.dart — the Account page of every role that has one (student, teacher, org roles).
/// D-713 / D-714: the identity header (a soft primary gradient: avatar, name, chips, the teacher's figures,
/// "Update account" and "Share"), then the rows grouped into titled section cards, each in its own colour:
/// teaching / learning · messages & schedule · money · account & security · preferences · help · sign out.
/// One column on phones; from 900 px two columns balanced by height (profileSectionColumns).
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
import 'package:flutter_education_app/features/shared/downloads/downloads_screen.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/features/shared/profile/student_favorite_screen.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/offline/offline_strings.dart';
import '../../auth/auth_provider.dart';
import '../../auth/mfa_entry.dart' show MfaSettingsEntry;
import 'package:flutter_education_app/features/live/meeting_recording_sheets.dart' show CloudDrivesSettingsEntry;
import '../../parent/student_link_code_screen.dart';
import 'package:flutter_education_app/features/courses/student/details/components/app_responsive.dart';
import '../../../utils/widget/parent_component.dart';
import '../../student/record/student_record_pages.dart';
import '../../teacher/profile/payout/teacher_payouts_screen.dart';
import '../../teacher/profile/switch_device_requests/teacher_device_requests_provider.dart';
import '../../teacher/profile/switch_device_requests/teacher_device_requests_screen.dart';
import '../rag/rag_chat_screen.dart' show RagChatScreen;
import 'package:flutter_education_app/features/courses/roadmap/recommendations.dart' show ProfileRecommendations;
import 'about/about_and_terms_screen.dart';
import 'about/about_terms_provider.dart';
import '../../../design/app_language_switch.dart' show AppLanguageTile;
import '../display/display_settings_page.dart' show DisplaySettingsTile;
import 'package:flutter_education_app/features/shared/get_app/get_app_banner.dart' show GetAppTile;
import '../rag/app_assistant.dart' show AppAssistantOpenTile, AppAssistantBubbleTile;
import 'change_password_widget.dart';
import 'compalints/complaint_provider.dart';
import 'compalints/complaints_hub_page.dart';
import 'privacy_export.dart' show DataExportPage, dataExportEntryLabel;
import 'profile_provider.dart' show ProfileProvider;
import 'profile_hero.dart';
import 'update_account_widget.dart';
import '../study_profile/study_profile_pages.dart' show StudyProfilePage, StudyProfileTile;
import '../../../utils/helpers.dart';
import '../../auth/reauth_sheet.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import '../../admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/payments/points/points_api.dart' show kPointsFeatureKey;
import 'package:flutter_education_app/features/payments/points/points_wallet_page.dart' show PointsWalletPage;
import '../records/records_page.dart' show RecordsPage, RecordsSettingsTile;
import '../public_profile/public_profile_page.dart' show MyProfileTile, ShareMyProfileTile, myShareableUsername, shareProfileLink;
import 'package:flutter_education_app/features/certificates/issue/cert_verify_page.dart' show CertVerifyEntryTile;
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
    final teacher = auth.isTeacher;
    final student = auth.currentUser?.role == 'student';
    // colour carries meaning (D-610): gold marks what a person earned (points, certificates), the danger tone is kept
    // for leaving. Each section has its own colour (D-714) so the page reads as a few subjects, not a list of 30 rows.
    final earned = c.accent2;
    final accents = ProfileSectionAccents.of(context);

    Future<void> editAccount() async {
      await _push(EditAccountScreen(isTeacher: p.role != 'student'));
      if (context.mounted) _refresh(context);
    }

    // ── The identity header (D-713): the avatar, name, chips, the teacher's figures and the two actions ──
    final shareName = myShareableUsername(context);
    final hero = ProfileHero(
      name: p.name,
      role: p.role,
      email: p.email,
      username: p.username,
      imageUrl: p.imageUrl,
      heroTag: 'profile-user-${p.id}',
      onEdit: editAccount,
      onShare: shareName == null ? null : () => shareProfileLink(context, username: shareName, name: p.name),
      stats: teacher ? profileTeacherFigures(context.select<TeacherHomeProvider, TeacherStats>((h) => h.stats)) : const [],
    );

    // ── My teaching / My learning ──────────────────────────────
    final work = <Widget>[
      // the ONE profile page, owner view (D-850): teachers keep the old `profile.teacher_profile` switch on it too;
      // the teacher's documents moved into its owner panel
      ParentComponent(featureKey: teacher ? 'profile.teacher_profile' : 'profile.my_profile', child: const MyProfileTile()),
      // The Exam Hub (D-350): teachers, and whoever teaches inside an organization; never students or parents
      if (teacher || examHubTeachesInAnyOrg(AppModeController.instance.liveEntries))
        AppSettingsTile(
          featureKey: kExamHubFeatureKey,
          icon: Icons.fact_check_rounded,
          label: t('الاختبارات', 'Exams'),
          subtitle: t('أنشئ وصحّح وانشر النتائج من مكان واحد', 'Create, correct and publish results in one place'),
          keywords: 'exams correction results degrees اختبارات امتحانات تصحيح نتائج درجات',
          onTap: () => _push(deferredExamHub()),
        ),
      if (teacher) ...[
        AppSettingsTile(
          featureKey: 'profile.certificate_designs',
          icon: Icons.workspace_premium_rounded,
          color: earned,
          label: 'cert_my_designs'.tr,
          // personal designs: usable on every course of this teacher (no organization needed)
          onTap: () => _push(deferredCertificateDesigns()),
        ),
        AppSettingsTile(
          featureKey: 'profile.certificate_requests',
          icon: Icons.verified_rounded,
          color: earned,
          label: 'certificate_requests'.tr,
          onTap: () => _push(deferredCertificateRequests()),
        ),
      ] else ...[
        AppSettingsTile(
          featureKey: 'profile.my_certificates',
          icon: Icons.workspace_premium_rounded,
          color: earned,
          label: 'md_p7_grades_certificates'.tr,
          onTap: () => _push(const StudentGradesPage()),
        ),
        AppSettingsTile(
          featureKey: 'profile.my_favorite',
          icon: Icons.favorite_rounded,
          label: 'my_favorite'.tr,
          onTap: () => _push(const FavouriteCoursesScreen()),
        ),
        // Downloaded (encrypted) videos — native apps only.
        if (!kIsWeb)
          AppSettingsTile(
            featureKey: 'profile.downloads',
            icon: Icons.download_for_offline_rounded,
            label: offlineT('downloads'),
            onTap: () => _push(const DownloadsScreen()),
          ),
      ],
      // Records: my meeting recordings + their edits (D-311, kill switch profile.records)
      RecordsSettingsTile(onOpen: () => _push(const RecordsPage())),
      // where those recordings are saved (feature key profile.cloud_drives)
      const CloudDrivesSettingsEntry(rowOnly: true),
    ];

    // ── Money ────────────────────────────────────────────────
    final money = <Widget>[
      // Points wallet + the student live-meeting plan (live-rooms-spec §8 – §9)
      AppSettingsTile(
        featureKey: kPointsFeatureKey,
        icon: Icons.stars_rounded,
        color: earned,
        label: t('محفظة النقاط', 'Points wallet'),
        keywords: 'points wallet نقاط محفظة',
        onTap: () => _push(const PointsWalletPage()),
      ),
      if (teacher)
        AppSettingsTile(
          featureKey: 'profile.payout',
          icon: Icons.payments_rounded,
          label: 'admin_earnings_payouts'.tr, // the page it opens (L4)
          onTap: () => _push(const TeacherPayoutsScreen()),
        )
      else
        AppSettingsTile(
          featureKey: 'profile.my_payments',
          icon: Icons.receipt_long_rounded,
          label: 'md_p7_payments_subscriptions'.tr,
          onTap: () => _push(const StudentMoneyPage()),
        ),
    ];

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
        // https://nextbrain.site/@name — confirmed usernames only (D-074)
        const ShareMyProfileTile(),
      ],
    ];

    // ── Account & security ───────────────────────────────────
    final security = <Widget>[
      AppSettingsTile(
        featureKey: 'profile.update_account',
        icon: Icons.manage_accounts_rounded,
        label: 'update_account'.tr,
        onTap: editAccount,
      ),
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

      // ── Logout ─────────────────────────────────────────────
      (
        2,
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
      ),
    ].where((s) => s.$1 > 0).toList();

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
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [enter(0, hero), recs]),
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
              ]),
            );
          }),
        ),
      ),
    );
  }

  static const double _twoColumnsFrom = 900;
}

/// The section colours of the profile page (D-714), all from the theme's roles: teaching / learning in the
/// purple, messages in a terracotta drawn from the peach accent, money in gold, account & security in the primary,
/// preferences in the quiet ink and help in the sage.
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
    final peach = HSLColor.fromColor(c.accent);
    final sage = HSLColor.fromColor(c.accent3);
    return ProfileSectionAccents(
      work: c.purple,
      talk: peach.withSaturation(peach.saturation.clamp(0.45, 0.7)).withLightness(0.5).toColor(),
      money: c.accent2,
      security: c.primary,
      prefs: c.textMedium,
      help: sage.withSaturation(sage.saturation.clamp(0.2, 0.35)).withLightness(0.4).toColor(),
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
