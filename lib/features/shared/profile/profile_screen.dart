/// ─────────────────────────────────────────────────────────────────────────────
/// profile_screen.dart (Teacher)
/// Uses `context.colors` everywhere instead of hardcoded context.colors constants
/// so dark / light mode is automatic — no extra logic needed here.
/// ─────────────────────────────────────────────────────────────────────────────
library;


import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/features/shared/downloads/downloads_screen.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_group.dart';
import 'package:flutter_education_app/features/shared/profile/student_favorite_screen.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/offline/offline_strings.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/count_badge.dart';
import '../../auth/auth_provider.dart';
import '../../parent/student_link_code_screen.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../../utils/widget/parent_component.dart';
import '../../student/certificates/my_certificates_screen.dart';
import '../../teacher/certificates/certificate_requests_screen.dart';
import '../../teacher/profile/payout/teacher_payouts_screen.dart';
import '../../teacher/profile/switch_device_requests/teacher_device_requests_provider.dart';
import '../../teacher/profile/switch_device_requests/teacher_device_requests_screen.dart';
import 'about/about_and_terms_screen.dart';
import 'about/about_terms_provider.dart';
import 'change_language_screen.dart';
import 'change_password_widget.dart';
import 'compalints/complaint_provider.dart';
import 'compalints/complaints_screen.dart';
import 'course_instractor_profile.dart';
import 'components/setting_title.dart';
import 'profile_provider.dart' show ProfileProvider;
import 'update_account_widget.dart';
import '../../../utils/helpers.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designs_screen.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';

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
                    child: ProfileHeader(
                      provider: p,
                      onEdit: () async {           // the avatar opens "edit account" (same as the tile)
                        await _push(EditAccountScreen(isTeacher: p.role != 'student'));
                        if (context.mounted) _refresh(context);
                      },
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Account section ──────────────────────────────────────
                  ParentComponent(
                    featureKey: 'profile.account',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SettingsGroup(
                        title: 'account'.tr,
                        icon: Icons.account_circle_rounded,
                        children: [
                          ParentComponent(
                            featureKey: 'profile.update_account',
                            child: SettingsTile(
                              icon: Icons.manage_accounts_rounded,
                              iconBg: c.primaryTint,
                              iconColor: c.primary,
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
                            child: SettingsTile(
                              icon: Icons.lock_reset_rounded,
                              iconBg: c.accentTint,
                              iconColor: c.accent,
                              label: 'change_password'.tr,
                              onTap: () => _push(const ChangePasswordScreen()),
                            ),
                          ),
                          // Downloaded (encrypted) videos — native apps only.
                          if (!kIsWeb && !context.read<MyAuthProvider>().isTeacher)
                            ParentComponent(
                              featureKey: 'profile.downloads',
                              child: SettingsTile(
                                icon: Icons.download_for_offline_rounded,
                                iconBg: c.accentTint,
                                iconColor: c.accent,
                                label: offlineT('downloads'),
                                onTap: () => _push(const DownloadsScreen()),
                              ),
                            ),
                          if (context.read<MyAuthProvider>().isTeacher) ...[
                            ParentComponent(
                              featureKey: 'profile.my_ads',
                              child: SettingsTile(
                                icon: Icons.campaign_rounded,
                                iconBg: c.accentTint,
                                iconColor: c.accent,
                                label: 'my_ads'.tr,
                                onTap: () => _push(const TeacherAdsPage()),
                              ),
                            ),
                            ParentComponent(
                              featureKey: 'profile.certificate_designs',
                              child: SettingsTile(
                                icon: Icons.workspace_premium_rounded,
                                iconBg: c.accentTint,
                                iconColor: c.accent,
                                label: 'cert_my_designs'.tr,
                                // personal designs: usable on every course of this teacher (no organization needed)
                                onTap: () => _push(const CertificateDesignsScreen()),
                              ),
                            ),
                            ParentComponent(
                              featureKey: 'profile.teacher_profile',
                              child: SettingsTile(
                                icon: Icons.badge_rounded,
                                iconBg: c.dangerTint,
                                iconColor: c.danger,
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
                            ParentComponent(
                              featureKey: 'profile.certificate_requests',
                              child: SettingsTile(
                                icon: Icons.workspace_premium_rounded,
                                iconBg: c.primaryTint,
                                iconColor: c.primary,
                                label: 'certificate_requests'.tr,
                                onTap: () => _push(const CertificateRequestsScreen()),
                              ),
                            ),
                            ParentComponent(
                              featureKey: 'profile.payout',
                              child: SettingsTile(
                                icon: Icons.payments_rounded,
                                iconBg: c.dangerTint,
                                iconColor: c.danger,
                                label: 'payout'.tr,
                                onTap: () => _push(const TeacherPayoutsScreen()),
                              ),
                            ),
                            ParentComponent(
                              featureKey: 'profile.device_requests',
                              child: TileCountOverlay(
                                count: context.select<TeacherDeviceRequestsProvider, int>(
                                      (p) => p.items.length,
                                ),
                                child: SettingsTile(
                                  icon: Icons.phonelink_lock_rounded,
                                  iconBg: c.primaryLight.withValues(alpha: 0.3),
                                  iconColor: c.primary,
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
                                child: SettingsTile(
                                  icon: Icons.family_restroom_rounded,
                                  iconBg: c.successTint,
                                  iconColor: c.success,
                                  label: 'pl_link_code_title'.tr,
                                  onTap: () => _push(const StudentLinkCodeScreen()),
                                ),
                              ),
                            ParentComponent(
                              featureKey: 'profile.my_certificates',
                              child: SettingsTile(
                                icon: Icons.workspace_premium_rounded,
                                iconBg: c.primaryTint,
                                iconColor: c.primary,
                                label: 'my_certificates'.tr,
                                onTap: () => _push(const MyCertificatesScreen()),
                              ),
                            ),
                            ParentComponent(
                              featureKey: 'profile.my_favorite',
                              child: SettingsTile(
                                icon: Icons.favorite_rounded,
                                iconBg: c.dangerTint,
                                iconColor: c.danger,
                                label: 'my_favorite'.tr,
                                onTap: () =>
                                    _push(const FavouriteCoursesScreen()),
                              ),
                            ),
                            // ParentComponent(
                            //   key: ValueKey('profile.payment-method'),
                            //   child: SettingsTile(
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

                  // ── Settings section ─────────────────────────────────────
                  ParentComponent(
                    featureKey: 'profile.settings',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SettingsGroup(
                        title: 'settings'.tr,
                        icon: Icons.settings_rounded,
                        children: [
                          ParentComponent(
                            featureKey: 'profile.notifications',
                            child: SettingsTile(
                              icon: Icons.notifications_active_rounded,
                              iconBg: c.successTint,
                              iconColor: c.success,
                              label: 'notifications'.tr,
                              trailing: AppSwitch(
                                value: p.notificationsEnabled,
                                onChanged: p.toggleNotifications,
                                semanticLabel: 'notifications'.tr,
                              ),
                            ),
                          ),
                          ParentComponent(
                            featureKey: 'profile.change_language',
                            child: SettingsTile(
                              icon: Icons.language_rounded,
                              iconBg: c.purpleTint,
                              iconColor: context.colors.primaryLight,
                              label: 'change_language'.tr,
                              onTap: () => _push(const ChangeLanguageScreen()),
                            ),
                          ),
                          ParentComponent(
                            featureKey: 'profile.dark_mode',
                            child: SettingsTile(
                              icon: Icons.dark_mode_rounded,
                              iconBg: c.darkIconBg,
                              iconColor: c.textDark,
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
                      child: SettingsGroup(
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
                              child: SettingsTile(
                                onTap: () async {
                                  final shared =
                                  Provider.of<ComplaintProvider?>(
                                    context,
                                    listen: false,
                                  );
                                  await _push(
                                    shared != null
                                        ? ChangeNotifierProvider<
                                        ComplaintProvider
                                    >.value(
                                      value: shared,
                                      child: const ComplaintsScreen(),
                                    )
                                        : ChangeNotifierProvider(
                                      create: (_) => ComplaintProvider(),
                                      child: const ComplaintsScreen(),
                                    ),
                                  );
                                  shared?.refreshCount();
                                },
                                icon: Icons.support_agent_rounded,
                                iconBg: c.primaryTint,
                                iconColor: c.primary,
                                label: 'help_center'.tr,
                              ),
                            ),
                          ),
                          ParentComponent(
                            featureKey: 'profile.privacy',
                            child: SettingsTile(
                              icon: Icons.verified_user_rounded,
                              iconBg: c.successTint,
                              iconColor: c.success,
                              label: 'privacy'.tr,
                              onTap: () => _push(TermsScreen()),
                            ),
                          ),
                          ParentComponent(
                            featureKey: 'profile.about',
                            child: SettingsTile(
                              icon: Icons.info_rounded,
                              iconBg: c.accentTint,
                              iconColor: c.accent,
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
                      child: SettingsGroup(
                        title: 'exit'.tr,
                        icon: Icons.exit_to_app_rounded,
                        itemBackground: c.danger.withAlpha(30),
                        children: [
                          ParentComponent(
                            featureKey: 'profile.logout',
                            child: SettingsTile(
                              icon: Icons.logout_rounded,
                              iconBg: c.dangerTint,
                              iconColor: c.danger,
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
                            child: SettingsTile(
                              icon: Icons.delete_forever_rounded,
                              iconBg: c.dangerTint,
                              iconColor: c.danger,
                              label: 'delete_account_title'.tr,
                              onTap: () async {
                                final ok = await Helpers.confirmDialog(
                                  context,
                                  title: "are_you_sure_to_delete_account".tr,
                                  confirm: "delete".tr,
                                );
                                if (ok == true && context.mounted) {
                                  Helpers.showMessage(
                                    'your_account_will_deleted_successfully_through_14_days'
                                        .tr,
                                  );
                                  await Future.delayed(Duration(seconds: 5));
                                  await OfflineVideoService.instance.deleteAll();
                                  await context
                                      .read<ProfileProvider>()
                                      .deleteAccount(context);
                                }
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

class ProfileHeader extends StatelessWidget {
  final ProfileProvider provider;
  final VoidCallback? onEdit;

  const ProfileHeader({super.key, required this.provider, this.onEdit});

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'profile.header',
    child: _featureContent(context),
  );

  static String _roleLabel(String r) => {
        'student': 'role_student', 'teacher': 'role_teacher', 'parent': 'role_parent', 'admin': 'role_admin',
        'super_admin': 'role_super_admin', 'org-admin': 'role_org_admin', 'org_admin': 'role_org_admin',
        'org-staff': 'role_org_staff', 'org_staff': 'role_org_staff', 'developer': 'role_developer',
      }[r]?.tr ?? r;

  /// Premium hero: gradient card, glowing avatar ring with a camera badge (edit), name, role badge, e-mail.
  Widget _featureContent(BuildContext context) {
    final c = context.colors;
    final avatar = Container(
      width: 104,
      height: 104,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [Colors.white, c.accent2.withValues(alpha: 0.9)]),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: ClipOval(
        child: provider.imageUrl.isNotEmpty
            ? AppNetworkImage(url: provider.imageUrl, heroTag: "profile-user-${provider.id}")
            : Container(
                color: Colors.white,
                alignment: Alignment.center,
                child: Text(provider.name.isNotEmpty ? provider.name.characters.first.toUpperCase() : '?',
                    style: TextStyle(fontFamily: 'tajawal', fontSize: 40, fontWeight: FontWeight.w800, color: c.primary)),
              ),
      ),
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(c.radiusLarge + 4),
        gradient: LinearGradient(begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd, colors: [c.primary, c.primaryDark]),
        boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        PositionedDirectional(top: -40, end: -30, child: _bubble(150, 0.08)),
        PositionedDirectional(bottom: -50, start: -20, child: _bubble(130, 0.06)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
          child: Column(children: [
            GestureDetector(
              onTap: onEdit,
              child: Stack(clipBehavior: Clip.none, children: [
                avatar,
                if (onEdit != null)
                  PositionedDirectional(
                    bottom: 2,
                    end: 2,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(color: c.accent2, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
                      child: const Icon(Icons.photo_camera_rounded, size: 15, color: Colors.white),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            Text(provider.name, textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'tajawal', fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
              if (provider.role.isNotEmpty)
                _glass(Icons.verified_user_rounded, _roleLabel(provider.role)),
              if (provider.email.isNotEmpty) _glass(Icons.alternate_email_rounded, provider.email, ltr: true),
            ]),
          ]),
        ),
      ]),
    );
  }

  static Widget _bubble(double size, double a) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: a)),
      );

  static Widget _glass(IconData icon, String text, {bool ltr = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis, textDirection: ltr ? TextDirection.ltr : null,
              style: const TextStyle(fontFamily: 'tajawal', fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white))),
        ]),
      );
}
