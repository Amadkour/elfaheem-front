/// profile_screen.dart — responsive redesign
/// Wide (≥700px): two-column settings grid
/// Mobile: original single-column stack
/// All providers, sub-screens, navigation, logout logic unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/profile/profile_provider.dart';
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
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),

                    // ── Profile header card ─────────────────────────────────
                    _ProfileHeaderCard(provider: provider),
                    const SizedBox(height: 24),

                    // ── Settings groups ─────────────────────────────────────
                    if (isWide)
                      // Wide: two columns side-by-side
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(children: [
                              _buildAccount(context, provider),
                              const SizedBox(height: 20),
                              _buildHelp(context),
                            ]),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(children: [
                              _buildSettings(provider,context),
                            ]),
                          ),
                        ],
                      )
                    else
                      // Mobile: single column
                      Column(children: [
                        _buildAccount(context, provider),
                        const SizedBox(height: 20),
                        _buildSettings(provider,context),
                        const SizedBox(height: 20),
                        _buildHelp(context),
                      ]),

                    const SizedBox(height: 24),

                    // ── Logout ──────────────────────────────────────────────
                    GestureDetector(
                      onTap: () async {
                        final confirm = await _confirmLogout(context);
                        if (confirm == true && context.mounted) {
                          await context.read<ProfileProvider>().logout(context);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: context.colors.cardBg,
                          borderRadius:
                              BorderRadius.circular(context.colors.radiusMedium),
                          boxShadow: context.colors.cardShadow,
                          border: Border.all(
                              color: context.colors.danger.withValues(alpha: 0.15)),
                        ),
                        child: Row(children: [
                           Text('تسجيل الخروج',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: context.colors.danger)),
                          const Spacer(),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: context.colors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child:  Icon(Icons.logout_rounded,
                                size: 18, color: context.colors.danger),
                          ),
                          const SizedBox(width: 10),
                           Icon(Icons.chevron_left_rounded,
                              color: context.colors.textLight, size: 20),
                        ]),
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

  Widget _buildAccount(BuildContext context, ProfileProvider provider) {
    return SettingsGroup(
      title: 'الحساب',
      children: [
        SettingsTile(
          icon: Icons.person_rounded,
          iconBg: context.colors.primary.withValues(alpha: 0.12),
          iconColor: context.colors.primary,
          label: 'تعديل الحساب',
          onTap: () => _push(context, const EditAccountScreen()),
        ),
        SettingsTile(
          icon: Icons.lock_rounded,
          iconBg: context.colors.accent.withValues(alpha: 0.12),
          iconColor: context.colors.accent,
          label: 'تغيير الباسوورد',
          onTap: () => _push(context, const ChangePasswordScreen()),
        ),
        SettingsTile(
          icon: Icons.favorite_rounded,
          iconBg: context.colors.danger.withValues(alpha: 0.12),
          iconColor: context.colors.danger,
          label: 'الكورسات المفضله',
          onTap: () => _push(context, const FavouriteCoursesScreen()),
        ),
      ],
    );
  }

  Widget _buildSettings(ProfileProvider provider,BuildContext context) {
    return SettingsGroup(
      title: 'الضبط',
      children: [
        SettingsTile(
          icon: Icons.notifications_rounded,
          iconBg: context.colors.success.withValues(alpha: 0.12),
          iconColor: context.colors.success,
          label: 'الاشعارات',
          trailing: Switch.adaptive(
            value: provider.notificationsEnabled,
            onChanged: provider.toggleNotifications,
            activeColor: context.colors.primary,
          ),
        ),
        SettingsTile(
          icon: Icons.language_rounded,
          iconBg: const Color(0xFF8B6FFF).withValues(alpha: 0.12),
          iconColor: const Color(0xFF8B6FFF),
          label: 'تغيير اللغه',
          onTap: () {},
        ),
        SettingsTile(
          icon: Icons.dark_mode_rounded,
          iconBg: context.colors.textDark.withValues(alpha: 0.08),
          iconColor: context.colors.textDark,
          label: 'الوضع الليلي',
          trailing: Switch.adaptive(
            value: provider.darkMode,
            onChanged: provider.toggleDarkMode,
            activeColor: context.colors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildHelp(BuildContext context) {
    return SettingsGroup(
      title: 'المساعده',
      children: [
        SettingsTile(
          icon: Icons.headset_mic_rounded,
          iconBg: context.colors.primary.withValues(alpha: 0.12),
          iconColor: context.colors.primary,
          label: 'مركز المساعده',
          onTap: () => _push(context, const SupportScreen()),
        ),
        SettingsTile(
          icon: Icons.privacy_tip_rounded,
          iconBg: context.colors.success.withValues(alpha: 0.12),
          iconColor: context.colors.success,
          label: 'الخصوصيه',
          onTap: () => _push(context, const PrivacyScreen()),
        ),
        SettingsTile(
          icon: Icons.info_rounded,
          iconBg: context.colors.accent.withValues(alpha: 0.12),
          iconColor: context.colors.accent,
          label: 'عنا',
          onTap: () => _push(context, const AboutScreen()),
        ),
      ],
    );
  }

  Future<bool?> _confirmLogout(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.colors.radiusMedium)),
          title: const Text('تسجيل الخروج',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: const Text('هل أنت متأكد أنك تريد تسجيل الخروج؟',
              style: TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:  Text('إلغاء',
                  style: TextStyle(
                      fontFamily: 'Cairo', color: context.colors.textMedium)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.danger,
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

// ── Profile header card — redesigned, same data ───────────────────────────────

class _ProfileHeaderCard extends StatelessWidget {
  final ProfileProvider provider;

  const _ProfileHeaderCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: context.colors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: context.colors.primaryShadow,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5), width: 2.5),
            ),
            child: provider.avatarUrl != null
                ? ClipOval(child: AppNetworkImage(url: provider.avatarUrl!))
                : const Icon(Icons.person_rounded,
                    size: 44, color: Colors.white),
          ),
          const SizedBox(width: 18),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(provider.name,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18)),
                const SizedBox(height: 4),
                Text(provider.email,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.school_rounded, color: Colors.white, size: 13),
                    SizedBox(width: 5),
                    Text('طالب',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// All sub-screens below are identical to the original — zero logic changes.
// ─────────────────────────────────────────────────────────────────────────────

// ── Edit Account ──────────────────────────────────────────────────────────────

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
        ScaffoldMessenger.of(context)
            .showSnackBar(_snack('تم حفظ التغييرات بنجاح', context.colors.success));
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
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'تعديل الحساب'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(children: [
                    Stack(alignment: Alignment.bottomLeft, children: [
                      Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: context.colors.primary.withValues(alpha: 0.1),
                              border: Border.all(
                                  color: context.colors.primary, width: 2)),
                          child:  Icon(Icons.person_rounded,
                              size: 48, color: context.colors.primary)),
                      Container(
                          width: 30,
                          height: 30,
                          decoration:  BoxDecoration(
                              shape: BoxShape.circle, color: context.colors.primary),
                          child: const Icon(Icons.camera_alt_rounded,
                              size: 16, color: Colors.white)),
                    ]),
                    const SizedBox(height: 8),
                    Text(provider.phone, style: context.colors.caption),
                    const SizedBox(height: 24),
                    MyTextField(
                        controller: _nameCtrl,
                        label: 'الاسم',
                        validator: (v) =>
                            (v?.isEmpty ?? true) ? 'أدخل الاسم' : null),
                    const SizedBox(height: 16),
                    MyTextField(
                        controller: _emailCtrl,
                        label: 'الإيميل',
                        enable: false),
                    const SizedBox(height: 16),
                    MyTextField(controller: _dobCtrl, label: 'تاريخ الميلاد'),
                    const SizedBox(height: 32),
                    MyPrimaryButton(
                        label: 'حفظ التغييرات',
                        isLoading: provider.isLoading,
                        onPressed: _save),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Change Password ───────────────────────────────────────────────────────────

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
  final bool _showOld = false;
  final bool _showNew = false;
  final bool _showConfirm = false;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await context
        .read<ProfileProvider>()
        .changePassword(oldPassword: _oldCtrl.text, newPassword: _newCtrl.text);
    if (mounted &&
        context.read<ProfileProvider>().passwordStep == PasswordStep.otp) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const _OtpPasswordScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<ProfileProvider>().isLoading;
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'change_password'.tr),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(children: [
                    MyPasswordTextField(
                        controller: _oldCtrl,
                        label: 'old_password'.tr,
                        obscurePassword: !_showOld),
                    const SizedBox(height: 16),
                    MyPasswordTextField(
                        controller: _newCtrl,
                        label: 'new_password'.tr,
                        obscurePassword: !_showNew),
                    const SizedBox(height: 16),
                    MyPasswordTextField(
                        controller: _confirmCtrl,
                        label: 'تأكيد كلمه السر',
                        obscurePassword: !_showConfirm),
                    const SizedBox(height: 32),
                    MyPrimaryButton(
                        label: 'حفظ التغييرات',
                        isLoading: isLoading,
                        onPressed: _save),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

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
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_code.length < 4) return;
    ScaffoldMessenger.of(context).showSnackBar(
        _snack('تم التحقق وتغيير كلمة المرور بنجاح', context.colors.success));
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
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'رمز التحقق'),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('ادخل رمز التحقق', style: context.colors.h2),
                    const SizedBox(height: 6),
                     Text('لقد تم ارسال رمز التحقق الى +966xxxxxx',
                        style: context.colors.body),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                          4,
                          (i) => Container(
                                width: 66,
                                height: 66,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                decoration: BoxDecoration(
                                  color: context.colors.cardBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: _focusNodes[i].hasFocus
                                          ? context.colors.primary
                                          : context.colors.divider,
                                      width: _focusNodes[i].hasFocus ? 2 : 1.5),
                                  boxShadow: context.colors.cardShadow,
                                ),
                                child: TextField(
                                  controller: _controllers[i],
                                  focusNode: _focusNodes[i],
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  maxLength: 1,
                                  style: context.colors.h2.copyWith(fontSize: 24),
                                  decoration: const InputDecoration(
                                      counterText: '',
                                      border: InputBorder.none),
                                  onChanged: (v) {
                                    if (v.isNotEmpty && i < 3) {
                                      _focusNodes[i + 1].requestFocus();
                                    }
                                    if (v.isEmpty && i > 0) {
                                      _focusNodes[i - 1].requestFocus();
                                    }
                                  },
                                ),
                              )),
                    ),
                    const SizedBox(height: 28),
                    TextButton(
                      onPressed: () =>
                          context.read<ProfileProvider>().resendOtp(),
                      child: Text('Resend Code in 00:03',
                          style:
                              context.colors.label.copyWith(color: context.colors.primary)),
                    ),
                    const SizedBox(height: 20),
                    MyPrimaryButton(
                        label: 'تأكيد',
                        isLoading: provider.isLoading,
                        onPressed: _confirm),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Change Language ───────────────────────────────────────────────────────────

class ChangeLanguageScreen extends StatelessWidget {
  const ChangeLanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(children: [
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
                              ? context.colors.primary.withValues(alpha: 0.08)
                              : context.colors.cardBg,
                          borderRadius:
                              BorderRadius.circular(context.colors.radiusMedium),
                          border: Border.all(
                              color: isSelected
                                  ? context.colors.primary
                                  : context.colors.divider,
                              width: isSelected ? 2 : 1),
                          boxShadow: context.colors.cardShadow,
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(lang.label,
                                  style: context.colors.label.copyWith(
                                      color: isSelected
                                          ? context.colors.primary
                                          : context.colors.textDark,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              if (isSelected)
                                 Icon(Icons.check_circle_rounded,
                                    color: context.colors.primary, size: 22),
                            ]),
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
                  onPressed: () async => Navigator.of(context).pop()),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Favourite Courses ─────────────────────────────────────────────────────────

class FavouriteCoursesScreen extends StatelessWidget {
  const FavouriteCoursesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final favourites = context.watch<ProfileProvider>().favourites;
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'الكورسات المفضله'),
            const SizedBox(height: 8),
            Expanded(
              child: favourites.isEmpty
                  ?  Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.favorite_border_rounded,
                          size: 64, color: context.colors.textLight),
                      SizedBox(height: 12),
                      Text('لا توجد كورسات مفضّلة بعد',
                          style: TextStyle(
                              fontFamily: 'Cairo', color: context.colors.textMedium)),
                    ]))
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
          ]),
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
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CourseDetailScreen(course: course))),
      child: Container(
        decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(context.colors.radiusMedium),
            boxShadow: context.colors.cardShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            AppNetworkImage(
                url: course.imageUrl,
                height: 110,
                borderRadius:  BorderRadius.only(
                    topLeft: Radius.circular(context.colors.radiusMedium),
                    topRight: Radius.circular(context.colors.radiusMedium))),
            Positioned(
              top: 8,
              left: 8,
              child: GestureDetector(
                onTap: () =>
                    context.read<ProfileProvider>().removeFavourite(course.id),
                child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle),
                    child:  Icon(Icons.favorite_rounded,
                        color: context.colors.danger, size: 16)),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.all(10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(course.title,
                  style: context.colors.h3.copyWith(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(course.instructorName, style: context.colors.caption, maxLines: 1),
              const SizedBox(height: 6),
              Text(
                  course.price == 0
                      ? 'مجاني'
                      : '\$ ${course.price.toStringAsFixed(2)}',
                  style: context.colors.label.copyWith(color: context.colors.accent)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Support ───────────────────────────────────────────────────────────────────

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
          .showSnackBar(_snack('تم إرسال رسالتك بنجاح', context.colors.success));
      _messageCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'مركز المساعده'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MyTextField(controller: _nameCtrl, label: 'الاسم'),
                        const SizedBox(height: 16),
                        MyTextField(
                            controller: _emailCtrl,
                            label: 'الإيميل',
                            enable: false),
                        const SizedBox(height: 16),
                        MyTextField(
                            controller: _messageCtrl,
                            label: 'المساعده',
                            maxLine: 5,
                            validator: (v) =>
                                (v?.isEmpty ?? true) ? 'أدخل رسالتك' : null),
                        const SizedBox(height: 32),
                        MyPrimaryButton(
                            label: 'إرسال',
                            isLoading: _sending,
                            onPressed: _send),
                      ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── About ─────────────────────────────────────────────────────────────────────

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'عنا'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
                child: Column(children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                        gradient: context.colors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: context.colors.primaryShadow),
                    child: const Icon(Icons.school_rounded,
                        size: 72, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  Text('مركز الفهيم', style: context.colors.h1),
                  const SizedBox(height: 8),
                  Text('قدرات وتحصيلي والنجليزي',
                      style: context.colors.caption
                          .copyWith(color: context.colors.textMedium)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: context.colors.cardBg,
                        borderRadius:
                            BorderRadius.circular(context.colors.radiusMedium),
                        boxShadow: context.colors.cardShadow),
                    child:  Text(
                      'مركز الفهيم يحرص على تقديم احسن الكورسات بأحسن المدرسين ليكون عندنا احسن جيل متقدم',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          height: 1.9,
                          color: context.colors.textDark),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Privacy ───────────────────────────────────────────────────────────────────

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  static const _items = [
    (
      'Lorem Ipsum Dolor',
      'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.'
    ),
    (
      'Lorem Ipsum Dolor',
      'Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.'
    ),
    (
      'Lorem Ipsum Dolor',
      'Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.'
    ),
  ];

  final Set<int> _expanded = {0};

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(children: [
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
                        color: context.colors.cardBg,
                        borderRadius:
                            BorderRadius.circular(context.colors.radiusMedium),
                        boxShadow: context.colors.cardShadow),
                    child: Column(children: [
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(title, style: context.colors.h3),
                                Icon(
                                    isOpen
                                        ? Icons.expand_less_rounded
                                        : Icons.chevron_left_rounded,
                                    color: context.colors.textLight),
                              ]),
                        ),
                      ),
                      if (isOpen)
                        Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Text(body, style: context.colors.body)),
                    ]),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Shared snackbar ───────────────────────────────────────────────────────────

SnackBar _snack(String msg, Color color) => SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
