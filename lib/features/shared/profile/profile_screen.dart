/// ─────────────────────────────────────────────────────────────────────────────
/// profile_screen.dart (Teacher)
/// Uses `context.colors` everywhere instead of hardcoded context.colors constants
/// so dark / light mode is automatic — no extra logic needed here.
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/cupertino.dart';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_group.dart';
import 'package:flutter_education_app/features/shared/profile/student_favorite_screen.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../auth/auth_provider.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../../utils/widget/parent_component.dart';
import '../payment/student_saved_methods_screen.dart';
import '../payment/teacher_transfers_screen.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh(context);
    });
    super.initState();
  }

  void _refresh(BuildContext context) {
    context.read<ProfileProvider>().initData(
      context.read<AuthProvider>().currentUser,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProfileProvider>();
    final c = context.colors; // ← dynamic palette (light / dark)
    final isWide = context.showSidebar;

    return BasePage(
      useWebCard: true,
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
                    child: ProfileHeader(provider: p),
                  ),
                  const SizedBox(height: 28),

                  // ── Account section ──────────────────────────────────────
                  ParentComponent(
                    child: Padding(
                      key: ValueKey('profile.account'),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SettingsGroup(
                        title: 'account'.tr,
                        children: [
                          ParentComponent(
                            key: ValueKey('profile.update_account'),
                            child: SettingsTile(
                              icon: Icons.person_rounded,
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
                            key: ValueKey('profile.change_password'),
                            child: SettingsTile(
                              icon: Icons.lock_rounded,
                              iconBg: c.accentTint,
                              iconColor: c.accent,
                              label: 'change_password'.tr,
                              onTap: () => _push(const ChangePasswordScreen()),
                            ),
                          ),
                          if (context.read<AuthProvider>().isTeacher) ...[
                            ParentComponent(
                              key: ValueKey('profile.teacher_profile'),
                              child: SettingsTile(
                                icon: Icons.person_rounded,
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
                              key: ValueKey('profile.payment-method'),
                              child: SettingsTile(
                                icon: Icons.account_balance_wallet_rounded,
                                iconBg: c.successTint,
                                iconColor: c.success,
                                label: 'payment'.tr,
                                onTap: () =>
                                    _push(const TeacherTransfersScreen()),
                              ),
                            ),
                          ] else ...[
                            ParentComponent(
                              key: ValueKey('profile.my_favorite'),
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
                    child: Padding(
                      key: ValueKey('profile.settings'),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SettingsGroup(
                        title: 'settings'.tr,
                        children: [
                          ParentComponent(
                            key: ValueKey('profile.notifications'),
                            child: SettingsTile(
                              icon: Icons.notifications_rounded,
                              iconBg: c.successTint,
                              iconColor: c.success,
                              label: 'notifications'.tr,
                              trailing: Switch.adaptive(
                                value: p.notificationsEnabled,
                                onChanged: p.toggleNotifications,
                                activeThumbColor: context.colors.primaryDark,
                                thumbColor: const WidgetStatePropertyAll(
                                  Colors.white,
                                ),
                              ),
                            ),
                          ),
                          ParentComponent(
                            key: ValueKey('profile.help_center'),
                            child: SettingsTile(
                              icon: Icons.language_rounded,
                              iconBg: c.purpleTint,
                              iconColor: const Color(0xFF8B6FFF),
                              label: 'change_language'.tr,
                              onTap: () => _push(const ChangeLanguageScreen()),
                            ),
                          ),
                          ParentComponent(
                            key: ValueKey('profile.dark_mode'),
                            child: SettingsTile(
                              icon: Icons.dark_mode_rounded,
                              iconBg: c.darkIconBg,
                              iconColor: c.textDark,
                              label: 'dark_mode'.tr,
                              trailing: Switch.adaptive(
                                value: p.darkMode,
                                onChanged: (b) async {
                                  await p.changeMode(b);
                                },
                                activeThumbColor: context.colors.primaryDark,
                                thumbColor: const WidgetStatePropertyAll(
                                  Colors.white,
                                ),
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
                    child: Padding(
                      key: ValueKey('profile.help_group'),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SettingsGroup(
                        title: 'help'.tr,
                        children: [
                          ParentComponent(
                            key: ValueKey('profile.help_center'),
                            child: SettingsTile(
                              onTap: () => _push(
                                ChangeNotifierProvider(
                                  create: (_) => ComplaintProvider(),
                                  child: const ComplaintsScreen(),
                                ),
                              ),
                              icon: Icons.headset_mic_rounded,
                              iconBg: c.primaryTint,
                              iconColor: c.primary,
                              label: 'help_center'.tr,
                            ),
                          ),
                          ParentComponent(
                            key: ValueKey('profile.privacy'),
                            child: SettingsTile(
                              icon: Icons.privacy_tip_rounded,
                              iconBg: c.successTint,
                              iconColor: c.success,
                              label: 'privacy'.tr,
                              onTap: () => _push(TermsScreen()),
                            ),
                          ),
                          ParentComponent(
                            key: ValueKey('profile.about'),
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
                    child: Padding(
                      key: ValueKey('profile.exit_group'),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: SettingsGroup(
                        title: 'exit'.tr,
                        itemBackground: c.danger.withAlpha(30),
                        children: [
                          ParentComponent(
                            child: SettingsTile(
                              key: ValueKey('profile.logout'),
                              icon: Icons.logout,
                              iconBg: c.dangerTint,
                              iconColor: c.danger,
                              label: 'logout'.tr,
                              onTap: () async {
                                final ok = await Helpers.confirmDialog(context);
                                if (ok == true && context.mounted) {
                                  await context.read<ProfileProvider>().logout(
                                    context,
                                  );
                                }
                              },
                            ),
                          ),
                          ParentComponent(
                            child: SettingsTile(
                              key: ValueKey('profile.delete_account'),
                              icon: Icons.delete,
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

  const ProfileHeader({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomLeft,
          children: [
            Container(
              width: context.height / 8,
              height: context.height / 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.primary.withValues(alpha: 0.1),
                border: Border.all(color: context.colors.primary, width: 2.5),
              ),
              child: provider.imageUrl.isNotEmpty
                  ? ClipOval(
                      child: AppNetworkImage(
                        url: provider.imageUrl,
                        heroTag: "profile-user-${provider.id}",
                      ),
                    )
                  : Icon(
                      Icons.person_rounded,
                      size: 70,
                      color: context.colors.primary,
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(provider.name, style: context.colors.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 4),
        Text(provider.email, style: context.colors.caption),
      ],
    );
  }
}
