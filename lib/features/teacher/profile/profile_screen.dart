/// ─────────────────────────────────────────────────────────────────────────────
/// profile_screen.dart (Teacher)
/// Uses `context.colors` everywhere instead of hardcoded context.colors constants
/// so dark / light mode is automatic — no extra logic needed here.
/// ─────────────────────────────────────────────────────────────────────────────
library;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
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

    final p      = context.watch<ProfileProvider>();
    final c      = context.colors;          // ← dynamic palette (light / dark)
    final isWide = context.showSidebar;

    return BasePage(
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
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
                      onImageTap: () async {},
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Account section ──────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SettingsGroup(
                      title: 'account'.tr,
                      children: [
                        SettingsTile(
                          icon: Icons.person_rounded,
                          iconBg: c.primaryTint,
                          iconColor: c.primary,
                          label: 'update_account'.tr,
                          onTap: () => _push(const TeacherEditAccountScreen()),
                        ),
                        SettingsTile(
                          icon: Icons.lock_rounded,
                          iconBg: c.accentTint,
                          iconColor: c.accent,
                          label: 'change_password'.tr,
                          onTap: () => _push(const ChangePasswordScreen()),
                        ),
                        SettingsTile(
                          icon: Icons.account_balance_wallet_rounded,
                          iconBg: c.successTint,
                          iconColor: c.success,
                          label: 'payment_method'.tr,
                          onTap: () => _push(const PaymentMethodsScreen()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Settings section ─────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SettingsGroup(
                      title: 'الضبط',
                      children: [
                        SettingsTile(
                          icon: Icons.notifications_rounded,
                          iconBg: c.successTint,
                          iconColor: c.success,
                          label: 'الاشعارات',
                          trailing: Switch.adaptive(
                            value: p.notificationsEnabled,
                            onChanged: p.toggleNotifications,
                            activeColor: context.colors.primaryBlue,
                            thumbColor: const WidgetStatePropertyAll(Colors.white),
                          ),
                        ),
                        SettingsTile(
                          icon: Icons.language_rounded,
                          iconBg: c.purpleTint,
                          iconColor: const Color(0xFF8B6FFF),
                          label: 'تغيير اللغة',
                          onTap: () => _push(const ChangeLanguageScreen()),
                        ),
                        SettingsTile(
                          icon: Icons.dark_mode_rounded,
                          iconBg: c.darkIconBg,
                          iconColor: c.textDark,
                          label: 'الوضع الليلي',
                          trailing: Switch.adaptive(
                            value: p.darkMode,
                            onChanged: p.toggleDarkMode,
                            activeColor: context.colors.primaryBlue,
                            thumbColor: const WidgetStatePropertyAll(Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Help section ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SettingsGroup(
                      title: 'المساعدة',
                      children: [
                        SettingsTile(
                          icon: Icons.headset_mic_rounded,
                          iconBg: c.primaryTint,
                          iconColor: c.primary,
                          label: 'مركز المساعدة',
                          onTap: () => _push(const SupportScreen()),
                        ),
                        SettingsTile(
                          icon: Icons.privacy_tip_rounded,
                          iconBg: c.successTint,
                          iconColor: c.success,
                          label: 'الخصوصية',
                          onTap: () => _push(const PrivacyScreen()),
                        ),
                        SettingsTile(
                          icon: Icons.info_rounded,
                          iconBg: c.accentTint,
                          iconColor: c.accent,
                          label: 'عنا',
                          onTap: () => _push(const AboutScreen()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Logout ───────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      onTap: () async {
                        final ok = await Helpers.confirmLogout(context);
                        if (ok == true && context.mounted) {
                          await context.read<ProfileProvider>().logout(context);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 16),
                          decoration: BoxDecoration(
                            color: c.dangerTint,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: context.colors.danger.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child:  Icon(Icons.logout_rounded,
                                  size: 18, color: context.colors.danger),
                            ),
                            const SizedBox(width: 12),
                             Text(
                              'تسجيل الخروج',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: context.colors.danger,
                              ),
                            ),
                            const Spacer(),
                             Icon(Icons.chevron_right_rounded,
                                color: context.colors.danger, size: 20),
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
    );
  }

  Widget _webHeader(AppColors c) => Container(
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    decoration: BoxDecoration(
      color: c.cardBg,                          // ← was: context.colors.cardBg
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(children: [
      Text('account'.tr, style: c.h2.copyWith(fontSize: 16)),
    ]),
  );
}