import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../student/profile/component/setting_group.dart';
import '../../student/profile/component/setting_title.dart';
import '../../student/profile/profile_provider.dart';
import '../../student/profile/profile_screen.dart';
import 'components/payment_bank_info.dart';
import 'components/profile_header.dart';
import 'components/update_teacher_account_widget.dart';
import '../../../utils/helpers.dart';

class TeacherProfileScreen extends StatefulWidget {
  const TeacherProfileScreen({super.key});

  @override
  State<TeacherProfileScreen> createState() =>
      _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<TeacherProfileScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  void _push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.watch<ProfileProvider>();
    final isWide = context.showSidebar;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    maxWidth: Breakpoints.contentMax),
                child: Column(
                  children: [
                    if (isWide) _webHeader(),
                    const SizedBox(height: 24),

                    // Avatar
                    Padding(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                      child: ProfileHeader(
                        provider: p,
                        onImageTap: () async {},
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Account
                    Padding(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                      child: SettingsGroup(
                        title: 'account'.tr,
                        children: [
                          SettingsTile(
                            icon: Icons.person_rounded,
                            iconBg: AppTheme.primary.withValues(alpha:0.12),
                            iconColor: AppTheme.primary,
                            label: 'update_account'.tr,
                            onTap: () =>
                                _push(const TeacherEditAccountScreen()),
                          ),
                          SettingsTile(
                            icon: Icons.lock_rounded,
                            iconBg: AppTheme.accent.withValues(alpha:0.12),
                            iconColor: AppTheme.accent,
                            label: 'change_password'.tr,
                            onTap: () =>
                                _push(const ChangePasswordScreen()),
                          ),
                          SettingsTile(
                            icon: Icons.account_balance_wallet_rounded,
                            iconBg: AppTheme.success.withValues(alpha:0.12),
                            iconColor: AppTheme.success,
                            label: 'payment_method'.tr,
                            onTap: () =>
                                _push(const PaymentMethodsScreen()),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Settings
                    Padding(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                      child: SettingsGroup(
                        title: 'الضبط',
                        children: [
                          SettingsTile(
                            icon: Icons.notifications_rounded,
                            iconBg: AppTheme.success.withValues(alpha:0.12),
                            iconColor: AppTheme.success,
                            label: 'الاشعارات',
                            trailing: Switch.adaptive(
                              value: p.notificationsEnabled,
                              onChanged: p.toggleNotifications,
                              activeColor: AppTheme.primaryBlue,
                              thumbColor:  WidgetStatePropertyAll(
                                  Colors.white)),
                            ),
                          SettingsTile(
                            icon: Icons.language_rounded,
                            iconBg: const Color(0xFF8B6FFF)
                                .withValues(alpha:0.12),
                            iconColor: const Color(0xFF8B6FFF),
                            label: 'تغيير اللغة',
                            onTap: () =>
                                _push(const ChangeLanguageScreen()),
                          ),
                          SettingsTile(
                            icon: Icons.dark_mode_rounded,
                            iconBg:
                            AppTheme.textDark.withValues(alpha:0.08),
                            iconColor: AppTheme.textDark,
                            label: 'الوضع الليلي',
                            trailing: Switch.adaptive(
                              value: p.darkMode,
                              onChanged: p.toggleDarkMode,
                              activeColor: AppTheme.primaryBlue,
                              thumbColor: const WidgetStatePropertyAll(
                                  Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Help
                    Padding(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                      child: SettingsGroup(
                        title: 'المساعدة',
                        children: [
                          SettingsTile(
                            icon: Icons.headset_mic_rounded,
                            iconBg: AppTheme.primary.withValues(alpha:0.12),
                            iconColor: AppTheme.primary,
                            label: 'مركز المساعدة',
                            onTap: () =>
                                _push(const SupportScreen()),
                          ),
                          SettingsTile(
                            icon: Icons.privacy_tip_rounded,
                            iconBg: AppTheme.success.withValues(alpha:0.12),
                            iconColor: AppTheme.success,
                            label: 'الخصوصية',
                            onTap: () =>
                                _push(const PrivacyScreen()),
                          ),
                          SettingsTile(
                            icon: Icons.info_rounded,
                            iconBg: AppTheme.accent.withValues(alpha:0.12),
                            iconColor: AppTheme.accent,
                            label: 'عنا',
                            onTap: () => _push(const AboutScreen()),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Logout
                    Padding(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                      child: GestureDetector(
                        onTap: () async {
                          final ok =
                          await Helpers.confirmLogout(context);
                          if (ok == true && context.mounted) {
                            await context
                                .read<ProfileProvider>()
                                .logout(context);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha:0.06),
                              borderRadius: BorderRadius.circular(16),

                            ),
                            child: Row(children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withValues(alpha:0.12),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(Icons.logout_rounded,
                                    size: 18, color: AppTheme.danger),
                              ),
                              const SizedBox(width: 12),
                              const Text('تسجيل الخروج',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppTheme.danger,
                                  )),
                              const Spacer(),
                              const Icon(Icons.chevron_right_rounded,
                                  color: AppTheme.danger, size: 20),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _webHeader() => Container(
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    decoration: BoxDecoration(
      color: AppTheme.cardBg,
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 8,
            offset: const Offset(0, 2)),
      ],
    ),
    child: Row(children: [
      Text('ملفي الشخصي',
          style: AppTheme.h2.copyWith(fontSize: 16)),
    ]),
  );
}