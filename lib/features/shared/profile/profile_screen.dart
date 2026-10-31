/// ─────────────────────────────────────────────────────────────────────────────
/// profile_screen.dart (Teacher)
/// Uses `context.colors` everywhere instead of hardcoded context.colors constants
/// so dark / light mode is automatic — no extra logic needed here.
/// ─────────────────────────────────────────────────────────────────────────────
library;


import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/design/calendar_entry.dart';
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/features/shared/downloads/downloads_screen.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/features/shared/profile/student_favorite_screen.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/offline/offline_strings.dart';
import '../../../utils/widget/count_badge.dart';
import '../../auth/auth_provider.dart';
import '../../auth/mfa_entry.dart' show MfaSettingsEntry;
import '../live/meeting_recording_sheets.dart' show CloudDrivesSettingsEntry;
import '../../parent/student_link_code_screen.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../../utils/widget/parent_component.dart';
import '../../student/certificates/my_certificates_screen.dart';
import '../../teacher/certificates/certificate_requests_screen.dart';
import '../../teacher/profile/payout/teacher_payouts_screen.dart';
import '../../teacher/profile/switch_device_requests/teacher_device_requests_provider.dart';
import '../../teacher/profile/switch_device_requests/teacher_device_requests_screen.dart';
import '../rag/rag_chat_screen.dart' show RagChatScreen;
import '../roadmap/recommendations.dart' show ProfileRecommendations;
import 'about/about_and_terms_screen.dart';
import 'about/about_terms_provider.dart';
import '../../../design/app_language_switch.dart' show AppLanguageTile;
import '../display/display_settings_page.dart' show DisplaySettingsTile;
import '../rag/app_assistant.dart' show AppAssistantOpenTile, AppAssistantBubbleTile;
import 'change_password_widget.dart';
import 'compalints/complaint_provider.dart';
import 'compalints/complaints_hub_page.dart';
import 'course_instractor_profile.dart';
import 'privacy_export.dart' show DataExportPage, dataExportEntryLabel;
import 'profile_provider.dart' show ProfileProvider;
import 'update_account_widget.dart';
import '../../../utils/helpers.dart';
import '../../auth/reauth_sheet.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designs_screen.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import '../../admin/admin_common.dart' show t;
import '../points/points_api.dart' show kPointsFeatureKey;
import '../points/points_wallet_page.dart' show PointsWalletPage;
import '../public_profile/public_profile_page.dart' show ShareMyProfileTile;

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

    return BasePage(
      key: const ValueKey('profile'),
      useWebCard: true,
      enableFooterWidget: false,
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: Breakpoints.contentMax,
              ),
              child: Column(
                children: [
                  // ── Web header ───────────────────────────────────────────
                  if (isWide) _webHeader(c),
                  const SizedBox(height: 24),

                  // ── Avatar / profile header ──────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: AppSettingsHeader(
                      name: p.name,
                      role: p.role,
                      email: p.email,
                      username: p.username,
                      imageUrl: p.imageUrl,
                      heroTag: 'profile-user-${p.id}',
                      onEdit: () async {           // the avatar opens "edit account" (same as the tile)
                        await _push(EditAccountScreen(isTeacher: p.role != 'student'));
                        if (context.mounted) _refresh(context);
                      },
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Recommended for you (students of personal accounts, D-120; nothing otherwise) ──
                  ProfileRecommendations(
                    role: context.read<MyAuthProvider>().currentUser?.role,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  ),

                  // ── Account section ──────────────────────────────────────
                  ParentComponent(
                    featureKey: 'profile.account',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: AppSettingsGroup(
                        title: 'account'.tr,
                        icon: Icons.account_circle_rounded,
                        children: [
                          ParentComponent(
                            featureKey: 'profile.update_account',
                            child: AppSettingsTile(
                              icon: Icons.manage_accounts_rounded,
                              color: c.primary,
                              label: 'update_account'.tr,
                              onTap: () async {
                                await _push(
                                  EditAccountScreen(
                                    isTeacher: p.role != 'student',
                                  ),
                                );
                                if (context.mounted) {
                                  _refresh(context);
                                }
                              },
                            ),
                          ),
                          ParentComponent(
                            featureKey: 'profile.change_password',
                            child: AppSettingsTile(
                              icon: Icons.lock_reset_rounded,
                              color: c.primary, // the theme accent can be a pale tint: the icon read as disabled (L3)
                              label: 'change_password'.tr,
                              onTap: () => _push(const ChangePasswordScreen()),
                            ),
                          ),
                          const CalendarEntryTile(),
                          // Points wallet + the student live-meeting plan (live-rooms-spec §8 – §9)
                          ParentComponent(
                            featureKey: kPointsFeatureKey,
                            child: AppSettingsTile(
                              icon: Icons.stars_rounded,
                              color: c.success,
                              label: t('محفظة النقاط', 'Points wallet'),
                              keywords: 'points wallet نقاط محفظة',
                              onTap: () => _push(const PointsWalletPage()),
                            ),
                          ),
                          // Downloaded (encrypted) videos — native apps only.
                          if (!kIsWeb && !context.read<MyAuthProvider>().isTeacher)
                            ParentComponent(
                              featureKey: 'profile.downloads',
                              child: AppSettingsTile(
                                icon: Icons.download_for_offline_rounded,
                                color: c.primary,
                                label: offlineT('downloads'),
                                onTap: () => _push(const DownloadsScreen()),
                              ),
                            ),
                          if (context.read<MyAuthProvider>().isTeacher) ...[
                            ParentComponent(
                              featureKey: 'profile.my_ads',
                              child: AppSettingsTile(
                                icon: Icons.campaign_rounded,
                                color: c.primary,
                                label: 'my_ads'.tr,
                                onTap: () => _push(const TeacherAdsPage()),
                              ),
                            ),
                            ParentComponent(
                              featureKey: 'profile.certificate_designs',
                              child: AppSettingsTile(
                                icon: Icons.workspace_premium_rounded,
                                color: c.primary,
                                label: 'cert_my_designs'.tr,
                                // personal designs: usable on every course of this teacher (no organization needed)
                                onTap: () => _push(const CertificateDesignsScreen()),
                              ),
                            ),
                            ParentComponent(
                              featureKey: 'profile.teacher_profile',
                              child: AppSettingsTile(
                                icon: Icons.badge_rounded,
                                color: c.danger,
                                label: 'teacher_profile'.tr,
                                onTap: () => _push(
                                  InstructorProfileScreen(
                                    teacher: context
                                        .read<TeacherHomeProvider>()
                                        .stats
                                        .teacher!,
                                    studentView: false,
                                    stats: context
                                        .read<TeacherHomeProvider>()
                                        .stats,
                                  ),
                                ),
                              ),
                            ),
                            // https://nextbrain.site/@name — confirmed usernames only (D-074)
                            const ShareMyProfileTile(),
                            ParentComponent(
                              featureKey: 'profile.certificate_requests',
                              child: AppSettingsTile(
                                icon: Icons.workspace_premium_rounded,
                                color: c.primary,
                                label: 'certificate_requests'.tr,
                                onTap: () => _push(const CertificateRequestsScreen()),
                              ),
                            ),
                            ParentComponent(
                              featureKey: 'profile.payout',
                              child: AppSettingsTile(
                                icon: Icons.payments_rounded,
                                color: c.danger,
                                label: 'admin_earnings_payouts'.tr, // the page it opens (L4)
                                onTap: () => _push(const TeacherPayoutsScreen()),
                              ),
                            ),
                            ParentComponent(
                              featureKey: 'profile.device_requests',
                              child: TileCountOverlay(
                                count: context.select<TeacherDeviceRequestsProvider, int>(
                                      (p) => p.items.length,
                                ),
                                child: AppSettingsTile(
                                  icon: Icons.phonelink_lock_rounded,
                                  color: c.primary,
                                  label: 'device_switch_requests'.tr,
                                  onTap: () => _push(const TeacherDeviceRequestsScreen()),
                                ),
                              ),
                            ),
                          ] else ...[
                            // Student: temporary code to link a parent account
                            if (context.read<MyAuthProvider>().currentUser?.role == 'student')
                              ParentComponent(
                                featureKey: 'profile.parent_link',
                                child: AppSettingsTile(
                                  icon: Icons.family_restroom_rounded,
                                  color: c.success,
                                  label: 'pl_link_code_title'.tr,
                                  onTap: () => _push(const StudentLinkCodeScreen()),
                                ),
                              ),
                            ParentComponent(
                              featureKey: 'profile.my_certificates',
                              child: AppSettingsTile(
                                icon: Icons.workspace_premium_rounded,
                                color: c.primary,
                                label: 'my_certificates'.tr,
                                onTap: () => _push(const MyCertificatesScreen()),
                              ),
                            ),
                            ParentComponent(
                              featureKey: 'profile.my_favorite',
                              child: AppSettingsTile(
                                icon: Icons.favorite_rounded,
                                color: c.danger,
                                label: 'my_favorite'.tr,
                                onTap: () =>
                                    _push(const FavouriteCoursesScreen()),
                              ),
                            ),
                            // ParentComponent(
                            //   key: ValueKey('profile.payment-method'),
                            //   child: AppSettingsTile(
                            //     icon: Icons.account_balance_wallet_rounded,
                            //     iconBg: c.successTint,
                            //     iconColor: c.success,
                            //     label: 'payment-method'.tr,
                            //     onTap: () =>
                            //         _push(const StudentSavedMethodsScreen()),
                            //   ),
                            // ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Security: two-step verification, for the roles the server allows (hidden otherwise) ──
                  const MfaSettingsEntry(padding: EdgeInsets.symmetric(horizontal: 20)),

                  // ── Cloud: connected drives for meeting recordings (feature key profile.cloud_drives) ──
                  const CloudDrivesSettingsEntry(padding: EdgeInsets.symmetric(horizontal: 20)),

                  // ── Settings section ─────────────────────────────────────
                  ParentComponent(
                    featureKey: 'profile.settings',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: AppSettingsGroup(
                        title: 'settings'.tr,
                        icon: Icons.settings_rounded,
                        children: [
                          ParentComponent(
                            featureKey: 'profile.notifications',
                            child: AppSettingsTile(
                              icon: Icons.notifications_active_rounded,
                              color: c.success,
                              label: 'notifications'.tr,
                              trailing: AppSwitch(
                                value: p.notificationsEnabled,
                                onChanged: p.toggleNotifications,
                                semanticLabel: 'notifications'.tr,
                              ),
                            ),
                          ),
                          const AppLanguageTile(),
                          const DisplaySettingsTile(),
                          const AppAssistantOpenTile(),
                          const AppAssistantBubbleTile(),
                          ParentComponent(
                            featureKey: 'profile.dark_mode',
                            child: AppSettingsTile(
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
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Help section ─────────────────────────────────────────
                  ParentComponent(
                    featureKey: 'profile.help_group',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: AppSettingsGroup(
                        title: 'help'.tr,
                        icon: Icons.help_center_rounded,
                        children: [
                          ParentComponent(
                            featureKey: 'profile.help_center',
                            // The teacher dashboard provides a shared ComplaintProvider
                            // (badge). Students don't — nullable lookup returns null there.
                            child: TileCountOverlay(
                              count: context.select<ComplaintProvider?, int>(
                                    (p) => p?.count ?? 0,
                              ),
                              child: AppSettingsTile(
                                // One page for every role here (D-086): New complaint · My complaints ·
                                // To resolve (non-students). The super admin keeps the admin console.
                                onTap: () async {
                                  final shared =
                                  Provider.of<ComplaintProvider?>(
                                    context,
                                    listen: false,
                                  );
                                  await _push(const ComplaintsHubPage());
                                  shared?.refreshCount();
                                },
                                icon: Icons.support_agent_rounded,
                                color: c.primary,
                                // named after the page it opens (L5: "Help center" opened the complaints list)
                                label: 'complaints_and_support'.tr,
                                keywords: 'help center support complaints مساعدة دعم شكاوى',
                              ),
                            ),
                          ),
                          ParentComponent(
                            featureKey: 'profile.app_assistant',
                            child: AppSettingsTile(
                              icon: Icons.question_answer_rounded,
                              color: c.primary,
                              label: 'app_assistant'.tr,
                              onTap: () => _push(const RagChatScreen(app: true)),
                            ),
                          ),
                          ParentComponent(
                            featureKey: 'profile.privacy',
                            child: AppSettingsTile(
                              icon: Icons.verified_user_rounded,
                              color: c.success,
                              label: 'privacy'.tr,
                              onTap: () => _push(const TermsScreen(privacy: true)),
                            ),
                          ),
                          ParentComponent(
                            featureKey: 'profile.data_export',
                            child: AppSettingsTile(
                              icon: Icons.inventory_2_rounded,
                              color: c.primary,
                              label: dataExportEntryLabel(),
                              onTap: () => _push(const DataExportPage()),
                            ),
                          ),
                          ParentComponent(
                            featureKey: 'profile.about',
                            child: AppSettingsTile(
                              icon: Icons.info_rounded,
                              color: c.primary,
                              label: 'about'.tr,
                              onTap: () => _push(
                                ChangeNotifierProvider(
                                  create: (_) => AboutTermsProvider(),
                                  child: AboutScreen(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Logout ───────────────────────────────────────────────
                  ParentComponent(
                    featureKey: 'profile.exit_group',
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: AppSettingsGroup(
                        title: 'exit'.tr,
                        icon: DirIcons.exitToApp,
                        danger: true,
                        children: [
                          ParentComponent(
                            featureKey: 'profile.logout',
                            child: AppSettingsTile(
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
                          ),
                          ParentComponent(
                            featureKey: 'profile.delete_account',
                            child: AppSettingsTile(
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
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _webHeader(ThemeConfigProvider c) => Container(
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Row(
      children: [Text('account'.tr, style: c.h2.copyWith(fontSize: 16))],
    ),
  );
}
