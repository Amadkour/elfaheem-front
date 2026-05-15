/// ─────────────────────────────────────────────────────────────────────────────
/// profile_screen.dart (Teacher)
/// Uses `context.colors` everywhere instead of hardcoded context.colors constants
/// so dark / light mode is automatic — no extra logic needed here.
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/profile/setting_group.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/primary_button.dart';
import '../../../utils/widget/text_field.dart';
import '../../auth/auth_provider.dart';
import '../../student/courses/details/course_detail_screen.dart';
import '../../student/models.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../teacher/profile/teacher_earnings_screen.dart';
import '../payment/student_saved_methods_screen.dart';
import '../payment/teacher_payout_screen.dart';
import 'change_password_widget.dart';
import 'course_instractor_profile.dart';
import 'setting_title.dart';
import 'profile_provider.dart' show ProfileProvider, AppLanguage, AppLanguageX;
import 'update_account_widget.dart';
import '../../../utils/helpers.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<ProfileScreen> {
  Future<void> _push(Widget screen) async =>
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh(context);
    });
    super.initState();
  }
  void _refresh(BuildContext context){
     context.read<ProfileProvider>().initData(context.read<AuthProvider>().currentUser);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProfileProvider>();
    final c = context.colors; // ← dynamic palette (light / dark)
    final isWide = context.showSidebar;

    return BasePage(
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: Breakpoints.contentMax),
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
                          onTap: () async {
                          await  _push(const EditAccountScreen());
                          if(context.mounted) {
                            _refresh(context);
                          }
                          },
                        ),
                        SettingsTile(
                          icon: Icons.lock_rounded,
                          iconBg: c.accentTint,
                          iconColor: c.accent,
                          label: 'change_password'.tr,
                          onTap: () => _push(const ChangePasswordScreen()),
                        ),
                        if (context.read<AuthProvider>().isTeacher)
                        SettingsTile(
                          icon: Icons.lock_rounded,
                          iconBg: c.accentTint,
                          iconColor: c.accent,
                          label: 'payments'.tr,
                          onTap: () => _push(const TeacherEarningsScreen()),
                        ),
                        SettingsTile(
                          icon: Icons.account_balance_wallet_rounded,
                          iconBg: c.successTint,
                          iconColor: c.success,
                          label: context.read<AuthProvider>().isTeacher
                              ? 'receiving-account'.tr
                              : 'payment-method'.tr,
                          onTap: () => _push(
                            context.read<AuthProvider>().isTeacher
                                ? const TeacherPayoutScreen()
                                : const StudentSavedMethodsScreen(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Settings section ─────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SettingsGroup(
                      title: 'settings'.tr,
                      children: [
                        SettingsTile(
                          icon: Icons.notifications_rounded,
                          iconBg: c.successTint,
                          iconColor: c.success,
                          label: 'notifications'.tr,
                          trailing: Switch.adaptive(
                            value: p.notificationsEnabled,
                            onChanged: p.toggleNotifications,
                            activeColor: context.colors.primaryBlue,
                            thumbColor:
                                const WidgetStatePropertyAll(Colors.white),
                          ),
                        ),
                        SettingsTile(
                          icon: Icons.language_rounded,
                          iconBg: c.purpleTint,
                          iconColor: const Color(0xFF8B6FFF),
                          label: 'change_language'.tr,
                          onTap: () => _push(const ChangeLanguageScreen()),
                        ),
                        SettingsTile(
                          icon: Icons.dark_mode_rounded,
                          iconBg: c.darkIconBg,
                          iconColor: c.textDark,
                          label: 'dark_mode'.tr,
                          trailing: Switch.adaptive(
                            value: p.darkMode,
                            onChanged: (b) async {
                              await p.changeMode(b);
                            },
                            activeColor: context.colors.primaryBlue,
                            thumbColor:
                                const WidgetStatePropertyAll(Colors.white),
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
                      title: 'help'.tr,
                      children: [
                        SettingsTile(
                          icon: Icons.headset_mic_rounded,
                          iconBg: c.primaryTint,
                          iconColor: c.primary,
                          label: 'help_center'.tr,
                          onTap: () => _push(const SupportScreen()),
                        ),
                        SettingsTile(
                          icon: Icons.privacy_tip_rounded,
                          iconBg: c.successTint,
                          iconColor: c.success,
                          label: 'privacy'.tr,
                          onTap: () => _push(const PrivacyScreen()),
                        ),
                        SettingsTile(
                          icon: Icons.info_rounded,
                          iconBg: c.accentTint,
                          iconColor: c.accent,
                          label: 'about'.tr,
                          onTap: () => _push(const AboutScreen()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Logout ───────────────────────────────────────────────
                  GestureDetector(
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
                                color: context.colors.danger
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(Icons.logout_rounded,
                                  size: 18, color: context.colors.danger),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'log-out'.tr,
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
          color: c.cardBg, // ← was: context.colors.cardBg
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
                                  style:
                                      context.colors.h2.copyWith(fontSize: 24),
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
                    // TextButton(
                    //   onPressed: () =>
                    //       context.read<ProfileProvider>().resendOtp(),
                    //   child: Text('Resend Code in 00:03',
                    //       style:
                    //           context.colors.label.copyWith(color: context.colors.primary)),
                    // ),
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
    final provider = context.watch<LangProvider>();
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'change_language'.tr),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                children: provider.languages.map((l) {
                  final isSelected = AppConfig.lang == l;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GestureDetector(
                      onTap: () async {
                        await provider.changeLang(l);
                        Navigator.pop(context);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : context.colors.cardBg,
                          borderRadius: BorderRadius.circular(
                              context.colors.radiusMedium),
                          border: Border.all(
                              color: isSelected
                                  ? context.colors.primaryBlue
                                  : context.colors.divider,
                              width: isSelected ? 2 : 1),
                          boxShadow: context.colors.cardShadow,
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(l.tr,
                                  style: context.colors.label.copyWith(
                                      color: isSelected
                                          ? context.colors.primaryBlue
                                          : context.colors.textDark,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded,
                                    color: context.colors.primaryBlue, size: 22),
                            ]),
                      ),
                    ),
                  );
                }).toList(),
              ),
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
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.favorite_border_rounded,
                          size: 64, color: context.colors.textLight),
                      SizedBox(height: 12),
                      Text('لا توجد كورسات مفضّلة بعد',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: context.colors.textMedium)),
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

  const _FavCourseCard({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => CourseDetailScreen(course: course)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color:        context.colors.cardBg,
          borderRadius: BorderRadius.circular(context.colors.radiusMedium),
          boxShadow:    context.colors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Stack(
              children: [
                AppNetworkImage(
                  url:    course.imageUrl,
                  height: 110,
                  borderRadius: BorderRadius.only(
                    topLeft:  Radius.circular(context.colors.radiusMedium),
                    topRight: Radius.circular(context.colors.radiusMedium),
                  ),
                ),
              ],
            ),

            // Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.title,
                    style:    context.colors.h3.copyWith(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if(course.teacher!=Null)
                  InstructorAvatar(teacher: course.teacher!, size: 50, canOpen: true,),

                  const SizedBox(height: 6),
                  Text(
                    course.price == 0
                        ? 'مجاني'
                        : '${course.price.toStringAsFixed(2)} ر.س',
                    style: context.colors.label.copyWith(
                        color: course.price == 0
                            ? context.colors.success
                            : context.colors.accent),
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
      ScaffoldMessenger.of(context).showSnackBar(
          _snack('تم إرسال رسالتك بنجاح', context.colors.success));
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
                    child: Text(
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

class ProfileHeader extends StatelessWidget {
  final ProfileProvider provider;

  const ProfileHeader({
    super.key,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomLeft,
          children: [
            Container(
              width: context.height/8,
              height: context.height/8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.primary.withValues(alpha: 0.1),
                border:
                    Border.all(color: context.colors.primaryBlue, width: 2.5),
              ),
              child: provider.imageUrl.isNotEmpty
                  ? ClipOval(child: AppNetworkImage(url: provider.imageUrl))
                  : Icon(Icons.person_rounded,
                      size: 52, color: context.colors.primaryBlue),
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
// ── Shared snackbar ───────────────────────────────────────────────────────────

SnackBar _snack(String msg, Color color) => SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
