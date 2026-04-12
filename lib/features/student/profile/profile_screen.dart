// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../auth/auth_provider.dart';
// import '../../utils/helpers.dart';
// import '../auth/login_screen.dart';
//
// class ProfileScreen extends StatelessWidget {
//   const ProfileScreen({Key? key}) : super(key: key);
//
//   @override
//   Widget build(BuildContext context) {
//     final authProvider = context.watch<AuthProvider>();
//     final user = authProvider.currentUser;
//
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Profile'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.edit),
//             onPressed: () {
//               // TODO: Navigate to edit profile
//               Helpers.showMessage(context, 'Edit profile coming soon!');
//             },
//           ),
//         ],
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           children: [
//             // Profile Header
//             CircleAvatar(
//               radius: 60,
//               backgroundColor: Theme.of(context).primaryColor,
//               child: Text(
//                 user?.name?.substring(0, 2).toUpperCase() ?? 'U',
//                 style: const TextStyle(
//                   fontSize: 42,
//                   color: Colors.white,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//             ),
//             const SizedBox(height: 16),
//
//             // User Info
//             Text(
//               user?.name ?? user?.gmail ?? 'User',
//               style: Theme.of(context).textTheme.headlineSmall,
//             ),
//             const SizedBox(height: 4),
//             Text(
//               user?.gmail ?? '',
//               style: Theme.of(context).textTheme.bodyMedium?.copyWith(
//                     color: Colors.grey,
//                   ),
//             ),
//             const SizedBox(height: 8),
//
//             // Role Badge
//             Chip(
//               avatar: Icon(
//                 user?.role == 'teacher' ? Icons.school : Icons.person,
//                 size: 16,
//               ),
//               label: Text(
//                 user?.role.toUpperCase() ?? 'USER',
//                 style: const TextStyle(
//                   fontSize: 12,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               backgroundColor: user?.role == 'teacher'
//                   ? Colors.blue.shade100
//                   : Colors.green.shade100,
//             ),
//             const SizedBox(height: 32),
//
//             // Account Section
//             _buildSection(
//               context,
//               title: 'Account',
//               items: [
//                 _buildListTile(
//                   icon: Icons.person_outline,
//                   title: 'Edit Profile',
//                   onTap: () => Helpers.showMessage(context, 'Coming soon!'),
//                 ),
//                 _buildListTile(
//                   icon: Icons.lock_outline,
//                   title: 'Change Password',
//                   onTap: () => Helpers.showMessage(context, 'Coming soon!'),
//                 ),
//                 _buildListTile(
//                   icon: Icons.email_outlined,
//                   title: 'Email Preferences',
//                   onTap: () => Helpers.showMessage(context, 'Coming soon!'),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//
//             // Settings Section
//             _buildSection(
//               context,
//               title: 'Settings',
//               items: [
//                 _buildListTile(
//                   icon: Icons.notifications_outlined,
//                   title: 'Notifications',
//                   trailing: Switch(
//                     value: true,
//                     onChanged: (value) {},
//                   ),
//                 ),
//                 _buildListTile(
//                   icon: Icons.language,
//                   title: 'Language',
//                   subtitle: 'English',
//                   onTap: () => Helpers.showMessage(context, 'Coming soon!'),
//                 ),
//                 _buildListTile(
//                   icon: Icons.dark_mode_outlined,
//                   title: 'Dark Mode',
//                   trailing: Switch(
//                     value: false,
//                     onChanged: (value) {},
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//
//             // Help Section
//             _buildSection(
//               context,
//               title: 'Support',
//               items: [
//                 _buildListTile(
//                   icon: Icons.help_outline,
//                   title: 'Help Center',
//                   onTap: () => Helpers.showMessage(context, 'Coming soon!'),
//                 ),
//                 _buildListTile(
//                   icon: Icons.info_outline,
//                   title: 'About',
//                   onTap: () => _showAboutDialog(context),
//                 ),
//                 _buildListTile(
//                   icon: Icons.privacy_tip_outlined,
//                   title: 'Privacy Policy',
//                   onTap: () => Helpers.showMessage(context, 'Coming soon!'),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//
//             // Logout Section
//             _buildSection(
//               context,
//               title: '',
//               items: [
//                 _buildListTile(
//                   icon: Icons.logout,
//                   title: 'Logout',
//                   titleColor: Colors.red,
//                   iconColor: Colors.red,
//                   onTap: () => _showLogoutDialog(context, authProvider),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 32),
//
//             // Version Info
//             Text(
//               'Version 1.0.0',
//               style: TextStyle(color: Colors.grey[600], fontSize: 12),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildSection(
//     BuildContext context, {
//     required String title,
//     required List<Widget> items,
//   }) {
//     return Card(
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           if (title.isNotEmpty)
//             Padding(
//               padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
//               child: Text(
//                 title,
//                 style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                       fontWeight: FontWeight.bold,
//                     ),
//               ),
//             ),
//           ...items,
//         ],
//       ),
//     );
//   }
//
//   Widget _buildListTile({
//     required IconData icon,
//     required String title,
//     String? subtitle,
//     Widget? trailing,
//     Color? titleColor,
//     Color? iconColor,
//     VoidCallback? onTap,
//   }) {
//     return ListTile(
//       leading: Icon(icon, color: iconColor),
//       title: Text(
//         title,
//         style: TextStyle(color: titleColor),
//       ),
//       subtitle: subtitle != null ? Text(subtitle) : null,
//       trailing: trailing ?? const Icon(Icons.chevron_right),
//       onTap: onTap,
//     );
//   }
//
//   void _showAboutDialog(BuildContext context) {
//     showAboutDialog(
//       context: context,
//       applicationName: 'EduPlatform',
//       applicationVersion: '1.0.0',
//       applicationIcon: const Icon(Icons.school, size: 48),
//       children: [
//         const Text(
//             'Complete educational platform with VOD and live streaming.'),
//         const SizedBox(height: 16),
//         const Text('Built with Flutter and FastAPI.'),
//       ],
//     );
//   }
//
//   void _showLogoutDialog(BuildContext context, AuthProvider authProvider) {
//     showDialog(
//       context: context,
//       builder: (ctx) => AlertDialog(
//         title: const Text('Logout'),
//         content: const Text('Are you sure you want to logout?'),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(ctx),
//             child: const Text('Cancel'),
//           ),
//           TextButton(
//             onPressed: () async {
//               await authProvider.logout();
//               if (context.mounted) {
//                 Navigator.of(ctx).pop();
//                 Navigator.of(context).pushAndRemoveUntil(
//                   MaterialPageRoute(builder: (_) => const LoginScreen()),
//                   (route) => false,
//                 );
//               }
//             },
//             child: const Text('Logout', style: TextStyle(color: Colors.red)),
//           ),
//         ],
//       ),
//     );
//   }
// }

/// ─────────────────────────────────────────────────────────────────────────────
/// profile_screen.dart
/// Main profile screen + all sub-screens:
///   EditAccountScreen, ChangePasswordScreen, ChangeLanguageScreen,
///   FavouriteCoursesScreen, SupportScreen, AboutScreen, PrivacyScreen
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/profile/profile_provider.dart';
import 'package:flutter_education_app/features/teacher/sessions/sessions_provider.dart';
import 'package:flutter_education_app/utils/widget/password_text_field.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart'
    show MyTextField;
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/app_bar.dart';
import '../courses/details/course_detail_provider.dart';
import '../courses/details/course_detail_screen.dart';
import '../models.dart';
import 'component/setting_group.dart';
import 'component/setting_title.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAIN PROFILE SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();

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
                // ── Avatar + name ───────────────────────────────────────────
                _ProfileHeader(provider: provider),
                const SizedBox(height: 28),

                // ── Account group ───────────────────────────────────────────
                SettingsGroup(
                  title: 'الحساب',
                  children: [
                    SettingsTile(
                      icon: Icons.person_rounded,
                      iconBg: AppTheme.primary.withValues(alpha: 0.12),
                      iconColor: AppTheme.primary,
                      label: 'تعديل الحساب',
                      onTap: () => _push(context, const EditAccountScreen()),
                    ),
                    SettingsTile(
                      icon: Icons.lock_rounded,
                      iconBg: AppTheme.accent.withValues(alpha: 0.12),
                      iconColor: AppTheme.accent,
                      label: 'تغيير الباسوورد',
                      onTap: () => _push(context, const ChangePasswordScreen()),
                    ),
                    SettingsTile(
                      icon: Icons.favorite_rounded,
                      iconBg: AppTheme.danger.withValues(alpha: 0.12),
                      iconColor: AppTheme.danger,
                      label: 'الكورسات المفضله',
                      onTap: () =>
                          _push(context, const FavouriteCoursesScreen()),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Settings group ──────────────────────────────────────────
                SettingsGroup(
                  title: 'الضبط',
                  children: [
                    SettingsTile(
                      icon: Icons.notifications_rounded,
                      iconBg: AppTheme.success.withValues(alpha: 0.12),
                      iconColor: AppTheme.success,
                      label: 'الاشعارات',
                      trailing: Switch.adaptive(
                        value: provider.notificationsEnabled,
                        onChanged: provider.toggleNotifications,
                        activeColor: AppTheme.primary,
                      ),
                    ),
                    SettingsTile(
                      icon: Icons.language_rounded,
                      iconBg: const Color(0xFF8B6FFF).withValues(alpha: 0.12),
                      iconColor: const Color(0xFF8B6FFF),
                      label: 'تغيير اللغه',
                      onTap: () => _push(context, const ChangeLanguageScreen()),
                    ),
                    SettingsTile(
                      icon: Icons.dark_mode_rounded,
                      iconBg: AppTheme.textDark.withValues(alpha: 0.08),
                      iconColor: AppTheme.textDark,
                      label: 'الوضع الليلي',
                      trailing: Switch.adaptive(
                        value: provider.darkMode,
                        onChanged: provider.toggleDarkMode,
                        activeColor: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Help group ──────────────────────────────────────────────
                SettingsGroup(
                  title: 'المساعده',
                  children: [
                    SettingsTile(
                      icon: Icons.headset_mic_rounded,
                      iconBg: AppTheme.primary.withValues(alpha: 0.12),
                      iconColor: AppTheme.primary,
                      label: 'مركز المساعده',
                      onTap: () => _push(context, const SupportScreen()),
                    ),
                    SettingsTile(
                      icon: Icons.privacy_tip_rounded,
                      iconBg: AppTheme.success.withValues(alpha: 0.12),
                      iconColor: AppTheme.success,
                      label: 'الخصوصيه',
                      onTap: () => _push(context, const PrivacyScreen()),
                    ),
                    SettingsTile(
                      icon: Icons.info_rounded,
                      iconBg: AppTheme.accent.withValues(alpha: 0.12),
                      iconColor: AppTheme.accent,
                      label: 'عنا',
                      onTap: () => _push(context, const AboutScreen()),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Logout ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GestureDetector(
                    onTap: () async {
                      final confirm = await _confirmLogout(context);
                      if (confirm == true && context.mounted) {
                        await context.read<ProfileProvider>().logout(context);
                        // TODO: navigate to login
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
                          const Text(
                            'تسجيل الخروج',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppTheme.danger,
                            ),
                          ),
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

  Future<bool?> _confirmLogout(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
          title: const Text('تسجيل الخروج',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: const Text('هل أنت متأكد أنك تريد تسجيل الخروج؟',
              style: TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء',
                  style: TextStyle(
                      fontFamily: 'Cairo', color: AppTheme.textMedium)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('خروج',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Profile Header ────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final ProfileProvider provider;

  const _ProfileHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomLeft,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.1),
                border: Border.all(color: AppTheme.primary, width: 2.5),
              ),
              child: provider.avatarUrl != null
                  ? ClipOval(child: AppNetworkImage(url: provider.avatarUrl!))
                  : const Icon(Icons.person_rounded,
                      size: 52, color: AppTheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(provider.name, style: AppTheme.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 4),
        Text(provider.email, style: AppTheme.caption),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDIT ACCOUNT SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class EditAccountScreen extends StatefulWidget {
  const EditAccountScreen({super.key});

  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _dobCtrl;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final p = context.read<ProfileProvider>();
    _nameCtrl = TextEditingController(text: p.name);
    _emailCtrl = TextEditingController(text: p.email);
    _dobCtrl = TextEditingController(text: p.dob);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await context.read<ProfileProvider>().updateProfile(
          name: _nameCtrl.text.trim(),
          phone: context.read<ProfileProvider>().phone,
          dob: _dobCtrl.text.trim(),
        );
    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          _snack('تم حفظ التغييرات بنجاح', AppTheme.success),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'تعديل الحساب'),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Avatar
                        Stack(
                          alignment: Alignment.bottomLeft,
                          children: [
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                border: Border.all(
                                    color: AppTheme.primary, width: 2),
                              ),
                              child: const Icon(Icons.person_rounded,
                                  size: 48, color: AppTheme.primary),
                            ),
                            Container(
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primary,
                              ),
                              child: const Icon(Icons.camera_alt_rounded,
                                  size: 16, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(provider.phone, style: AppTheme.caption),
                        const SizedBox(height: 24),

                        MyTextField(
                          controller: _nameCtrl,
                          label: 'الاسم',
                          validator: (v) =>
                              (v?.isEmpty ?? true) ? 'أدخل الاسم' : null,
                        ),
                        const SizedBox(height: 16),
                        MyTextField(
                          controller: _emailCtrl,
                          label: 'الإيميل',
                          enable: false,
                        ),
                        const SizedBox(height: 16),
                        MyTextField(
                          controller: _dobCtrl,
                          label: 'تاريخ الميلاد',
                        ),
                        const SizedBox(height: 32),
                        MyPrimaryButton(
                          label: 'حفظ التغييرات',
                          isLoading: provider.isLoading,
                          onPressed: _save,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHANGE PASSWORD SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _showOld = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await context.read<ProfileProvider>().changePassword(
          oldPassword: _oldCtrl.text,
          newPassword: _newCtrl.text,
        );
    if (mounted &&
        context.read<ProfileProvider>().passwordStep == PasswordStep.otp) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const _OtpPasswordScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<ProfileProvider>().isLoading;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'change_password'.tr),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        MyPasswordTextField(
                          controller: _oldCtrl,
                          label: 'old_password'.tr,
                          obscurePassword: !_showOld,
                        ),
                        const SizedBox(height: 16),
                        MyPasswordTextField(
                          controller: _newCtrl,
                          label: 'new_password'.tr,
                          obscurePassword: !_showNew,
                        ),
                        const SizedBox(height: 16),
                        MyPasswordTextField(
                          controller: _confirmCtrl,
                          label: 'تأكيد كلمه السر',
                          obscurePassword: !_showConfirm,
                        ),
                        const SizedBox(height: 32),
                        MyPrimaryButton(
                          label: 'حفظ التغييرات',
                          isLoading: isLoading,
                          onPressed: _save,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _visibilityIcon(bool visible, VoidCallback toggle) {
    return IconButton(
      icon: Icon(
          visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          color: AppTheme.textLight,
          size: 20),
      onPressed: toggle,
    );
  }
}

// ── OTP Verification after password change ─────────────────────────────────

class _OtpPasswordScreen extends StatefulWidget {
  const _OtpPasswordScreen();

  @override
  State<_OtpPasswordScreen> createState() => _OtpPasswordScreenState();
}

class _OtpPasswordScreenState extends State<_OtpPasswordScreen> {
  final _controllers = List.generate(4, (_) => TextEditingController());
  final _focusNodes = List.generate(4, (_) => FocusNode());

  String get _code => _controllers.map((c) => c.text).join();

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_code.length < 4) return;
    ScaffoldMessenger.of(context).showSnackBar(
        _snack('تم التحقق وتغيير كلمة المرور بنجاح', AppTheme.success));
    Navigator.of(context)
      ..pop()
      ..pop();
    context.read<ProfileProvider>().resetPasswordStep();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'رمز التحقق'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('ادخل رمز التحقق', style: AppTheme.h2),
                    const SizedBox(height: 6),
                    Text(
                      'لقد تم ارسال رمز التحقق الى +966xxxxxx',
                      style: AppTheme.body,
                    ),
                    const SizedBox(height: 32),
                    // 4 OTP boxes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (i) {
                        return Container(
                          width: 66,
                          height: 66,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _focusNodes[i].hasFocus
                                  ? AppTheme.primary
                                  : AppTheme.divider,
                              width: _focusNodes[i].hasFocus ? 2 : 1.5,
                            ),
                            boxShadow: AppTheme.cardShadow,
                          ),
                          child: TextField(
                            controller: _controllers[i],
                            focusNode: _focusNodes[i],
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 1,
                            style: AppTheme.h2.copyWith(fontSize: 24),
                            decoration: const InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                            ),
                            onChanged: (v) {
                              if (v.isNotEmpty && i < 3) {
                                _focusNodes[i + 1].requestFocus();
                              }
                              if (v.isEmpty && i > 0) {
                                _focusNodes[i - 1].requestFocus();
                              }
                            },
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 28),
                    TextButton(
                      onPressed: () =>
                          context.read<ProfileProvider>().resendOtp(),
                      child: Text('Resend Code in 00:03',
                          style:
                              AppTheme.label.copyWith(color: AppTheme.primary)),
                    ),
                    const SizedBox(height: 20),
                    MyPrimaryButton(
                      label: 'تأكيد',
                      isLoading: provider.isLoading,
                      onPressed: _confirm,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHANGE LANGUAGE SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class ChangeLanguageScreen extends StatelessWidget {
  const ChangeLanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'تغيير اللغه'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Column(
                  children: AppLanguage.values.map((lang) {
                    final isSelected = provider.language == lang;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GestureDetector(
                        onTap: () =>
                            context.read<ProfileProvider>().setLanguage(lang),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primary.withValues(alpha: 0.08)
                                : AppTheme.cardBg,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMedium),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.divider,
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: AppTheme.cardShadow,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                lang.label,
                                style: AppTheme.label.copyWith(
                                  color: isSelected
                                      ? AppTheme.primary
                                      : AppTheme.textDark,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded,
                                    color: AppTheme.primary, size: 22),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: MyPrimaryButton(
                  label: 'تأكيد',
                  isLoading: false,
                  onPressed: () async => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAVOURITE COURSES SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class FavouriteCoursesScreen extends StatelessWidget {
  const FavouriteCoursesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final favourites = context.watch<ProfileProvider>().favourites;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'الكورسات المفضله'),
              const SizedBox(height: 8),
              Expanded(
                child: favourites.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.favorite_border_rounded,
                                size: 64, color: AppTheme.textLight),
                            SizedBox(height: 12),
                            Text('لا توجد كورسات مفضّلة بعد',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: AppTheme.textMedium)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(20),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: favourites.length,
                        itemBuilder: (_, i) =>
                            _FavCourseCard(course: favourites[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavCourseCard extends StatelessWidget {
  final CourseModel course;

  const _FavCourseCard({required this.course});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CourseDetailScreen(
            course: course,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail + remove favourite
            Stack(
              children: [
                AppNetworkImage(
                  url: course.imageUrl,
                  height: 110,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppTheme.radiusMedium),
                    topRight: Radius.circular(AppTheme.radiusMedium),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: GestureDetector(
                    onTap: () => context
                        .read<ProfileProvider>()
                        .removeFavourite(course.id),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.favorite_rounded,
                          color: AppTheme.danger, size: 16),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.title,
                      style: AppTheme.h3.copyWith(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(course.instructorName,
                      style: AppTheme.caption, maxLines: 1),
                  const SizedBox(height: 6),
                  Text(
                    course.price == 0
                        ? 'مجاني'
                        : '\$ ${course.price.toStringAsFixed(2)}',
                    style: AppTheme.label.copyWith(color: AppTheme.accent),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUPPORT SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<ProfileProvider>();
    _nameCtrl.text = p.name;
    _emailCtrl.text = p.email;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(_snack('تم إرسال رسالتك بنجاح', AppTheme.success));
      _messageCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'مركز المساعده'),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MyTextField(
                          controller: _nameCtrl,
                          label: 'الاسم',
                        ),
                        const SizedBox(height: 16),
                        MyTextField(
                          controller: _emailCtrl,
                          label: 'الإيميل',
                          enable: false,
                        ),
                        const SizedBox(height: 16),
                        MyTextField(
                          controller: _messageCtrl,
                          label: 'المساعده',
                          maxLine: 5,
                          validator: (v) =>
                              (v?.isEmpty ?? true) ? 'أدخل رسالتك' : null,
                        ),
                        const SizedBox(height: 32),
                        MyPrimaryButton(
                          label: 'إرسال',
                          isLoading: _sending,
                          onPressed: _send,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ABOUT SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'عنا'),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
                  child: Column(
                    children: [
                      // Logo placeholder
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.primaryShadow,
                        ),
                        child: const Icon(Icons.school_rounded,
                            size: 72, color: Colors.white),
                      ),
                      const SizedBox(height: 24),
                      Text('مركز الفهيم', style: AppTheme.h1),
                      const SizedBox(height: 8),
                      Text('قدرات وتحصيلي والنجليزي',
                          style: AppTheme.caption
                              .copyWith(color: AppTheme.textMedium)),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMedium),
                          boxShadow: AppTheme.cardShadow,
                        ),
                        child: const Text(
                          'مركز الفهيم يحرص على تقديم احسن الكورسات بأحسن المدرسين ليكون عندنا احسن جيل متقدم',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            height: 1.9,
                            color: AppTheme.textDark,
                          ),
                          textAlign: TextAlign.center,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIVACY SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  static const _items = [
    (
      'Lorem Ipsum Dolor',
      'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
    ),
    (
      'Lorem Ipsum Dolor',
      'Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.',
    ),
    (
      'Lorem Ipsum Dolor',
      'Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.',
    ),
  ];

  final Set<int> _expanded = {0}; // first item open by default

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'السياسه و الخصوصيه'),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final (title, body) = _items[i];
                    final isOpen = _expanded.contains(i);

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMedium),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: () => setState(() {
                              if (isOpen) {
                                _expanded.remove(i);
                              } else {
                                _expanded.add(i);
                              }
                            }),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(title, style: AppTheme.h3),
                                  Icon(
                                    isOpen
                                        ? Icons.expand_less_rounded
                                        : Icons.chevron_left_rounded,
                                    color: AppTheme.textLight,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isOpen)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text(body, style: AppTheme.body),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared snackbar helper ────────────────────────────────────────────────────

SnackBar _snack(String msg, Color color) => SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
