import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../student/profile/component/setting_group.dart';
import '../../student/profile/component/setting_title.dart';
import '../../student/profile/profile_provider.dart';
import '../../student/profile/profile_screen.dart' ;
import 'components/payment_bank_info.dart';
import 'components/profile_header.dart';
import 'components/update_teacher_account_widget.dart';
import '../../../utils/helpers.dart';
class TeacherProfileScreen extends StatefulWidget {
  const TeacherProfileScreen({super.key});

  @override
  State<TeacherProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<TeacherProfileScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final profileProvider = context.watch<ProfileProvider>();

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // ── Avatar ──────────────────────────────────────────────────
                ProfileHeader(
                  provider: profileProvider,
                  onImageTap: () async {
                    // TODO: integrate image_picker, then:
                    // await context.read<TeacherProvider>()
                    //     .uploadProfileImage(pickedFile);
                  },
                ),
                const SizedBox(height: 28),

                // ── Account ─────────────────────────────────────────────────
                SettingsGroup(
                  title: 'account'.tr,
                  children: [
                    SettingsTile(
                      icon: Icons.person_rounded,
                      iconBg: AppTheme.primary.withValues(alpha: 0.12),
                      iconColor: AppTheme.primary,
                      label: 'update_account'.tr,
                      onTap: () => _push(const TeacherEditAccountScreen()),
                    ),
                    SettingsTile(
                      icon: Icons.lock_rounded,
                      iconBg: AppTheme.accent.withValues(alpha: 0.12),
                      iconColor: AppTheme.accent,
                      label: 'change_password'.tr,
                      onTap: () => _push( const ChangePasswordScreen()),
                    ),
                    SettingsTile(
                      icon: Icons.account_balance_wallet_rounded,
                      iconBg: const Color(0xFF8B6FFF).withValues(alpha: 0.12),
                      iconColor: const Color(0xFF8B6FFF),
                      label: 'payment_method'.tr,
                      onTap: () => _push(const PaymentMethodsScreen()),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Settings ────────────────────────────────────────────────
                SettingsGroup(
                  title: 'الضبط',
                  children: [
                    SettingsTile(
                      icon: Icons.notifications_rounded,
                      iconBg: AppTheme.success.withValues(alpha: 0.12),
                      iconColor: AppTheme.success,
                      label: 'الاشعارات',
                      trailing: Switch.adaptive(
                        value: profileProvider.notificationsEnabled,
                        onChanged: profileProvider.toggleNotifications,
                        thumbColor: const WidgetStatePropertyAll( AppTheme.primary),
                      ),
                    ),
                    SettingsTile(
                      icon: Icons.language_rounded,
                      iconBg: const Color(0xFF8B6FFF).withValues(alpha: 0.12),
                      iconColor: const Color(0xFF8B6FFF),
                      label: 'تغيير اللغه',
                      onTap: () => _push(const ChangeLanguageScreen()),
                    ),
                    SettingsTile(
                      icon: Icons.dark_mode_rounded,
                      iconBg: AppTheme.textDark.withValues(alpha: 0.08),
                      iconColor: AppTheme.textDark,
                      label: 'الوضع الليلي',
                      trailing: Switch.adaptive(
                        value: profileProvider.darkMode,
                        onChanged: profileProvider.toggleDarkMode,
                        thumbColor: const WidgetStatePropertyAll( AppTheme.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Help ────────────────────────────────────────────────────
                SettingsGroup(
                  title: 'المساعده',
                  children: [
                    SettingsTile(
                      icon: Icons.headset_mic_rounded,
                      iconBg: AppTheme.primary.withValues(alpha: 0.12),
                      iconColor: AppTheme.primary,
                      label: 'مركز المساعده',
                      onTap: () => _push(const SupportScreen()),
                    ),
                    SettingsTile(
                      icon: Icons.privacy_tip_rounded,
                      iconBg: AppTheme.success.withValues(alpha: 0.12),
                      iconColor: AppTheme.success,
                      label: 'الخصوصيه',
                      onTap: () => _push(const PrivacyScreen()),
                    ),
                    SettingsTile(
                      icon: Icons.info_rounded,
                      iconBg: AppTheme.accent.withValues(alpha: 0.12),
                      iconColor: AppTheme.accent,
                      label: 'عنا',
                      onTap: () => _push(const AboutScreen()),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Logout ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GestureDetector(
                    onTap: () async {
                      final ok = await Helpers.confirmLogout(context);
                      if (ok == true && context.mounted) {
                        await context.read<ProfileProvider>().logout(context);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMedium),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Row(
                        children: [
                          const Text('تسجيل الخروج',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppTheme.danger,
                              )),
                          const Spacer(),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.logout_rounded,
                                size: 18, color: AppTheme.danger),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.chevron_left_rounded,
                              color: AppTheme.textLight, size: 20),
                        ],
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
    );
  }
}
