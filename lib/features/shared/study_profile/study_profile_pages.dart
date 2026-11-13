// lib/features/shared/study_profile/study_profile_pages.dart
//
// Where a student meets their study data (D-790 – D-796), every surface behind the kill switch `profile.study`:
//
//   StudyProfileStepPage   the sign-up's ONE extra step (students, when the super admin keeps it on): stage + grade,
//                          the rest folded under "Add school and governorate"; its button creates the account
//   StudyProfilePage       Profile › Study details: the same form, loaded from and saved to /me/study-profile
//   StudyProfileTile       the Account page's row into it
//   StudyPromptCard        the student home's dismissible "Complete your profile" card (plain values; the home shows it
//                          while /me/home says `study_prompt`, never a blocking wall)
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show ErrorRetry, t;
import '../../auth/auth_shell.dart';
import '../../auth/auth_widgets.dart' show AuthButton;
import 'study_profile_form.dart';
import 'study_profile_model.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  The sign-up step
// ═════════════════════════════════════════════════════════════════════════════

/// The sign-up's study step. [onSubmit] creates the account with the profile (the register screen's own submit, which
/// opens the verification page on success); [busy] is its loading state. Going back keeps the values ([onChanged]).
class StudyProfileStepPage extends StatefulWidget {
  const StudyProfileStepPage({
    super.key,
    required this.initial,
    required this.settings,
    required this.onSubmit,
    required this.busy,
    this.onChanged,
  });

  final StudyProfile initial;
  final StudySettings settings;
  final Future<void> Function(StudyProfile profile) onSubmit;
  final ValueListenable<bool> busy;
  final ValueChanged<StudyProfile>? onChanged;

  @override
  State<StudyProfileStepPage> createState() => _StudyProfileStepPageState();
}

class _StudyProfileStepPageState extends State<StudyProfileStepPage> {
  late StudyProfile _value = widget.initial;
  bool _showErrors = false;

  /// The sign-up form asks the date of birth itself.
  List<String> get _required => [for (final f in widget.settings.required) if (f != 'dob') f];

  Future<void> _submit() async {
    if (_value.missing(_required).isNotEmpty) {
      setState(() => _showErrors = true);
      showAppNotice(t('أكمل الحقول المطلوبة', 'Fill in the required fields'), error: true);
      return;
    }
    await widget.onSubmit(_value);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: t('دراستك', 'Your studies'),
      subtitle: t('خطوة أخيرة قصيرة: مرحلتك وصفك لنعرض عليك ما يناسبك.',
          'One short last step: your stage and grade, so we can show you what fits.'),
      pageKey: const ValueKey('register.study'),
      maxWidth: 640,
      builder: (context, isWide) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudyProfileForm(
            value: _value,
            required: _required,
            showErrors: _showErrors,
            showDob: false,
            compact: true,
            onChanged: (v) {
              setState(() => _value = v);
              widget.onChanged?.call(v);
            },
          ),
          AppSpace.gapLg,
          ValueListenableBuilder<bool>(
            valueListenable: widget.busy,
            builder: (context, busy, _) => AuthButton(
              key: const ValueKey('study.submit'),
              loading: busy,
              label: 'auth_create_my_account'.tr,
              onPressed: _submit,
            ),
          ),
          AppSpace.gapSm,
          Text(
            t('يمكنك تعديلها لاحقاً من صفحة الحساب.', 'You can change it later from your Account page.'),
            textAlign: TextAlign.center,
            style: AppType.meta(context),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Profile › Study details
// ═════════════════════════════════════════════════════════════════════════════

class StudyProfilePage extends StatefulWidget {
  const StudyProfilePage({super.key, this.api});

  final StudyProfileApi? api;

  @override
  State<StudyProfilePage> createState() => _StudyProfilePageState();
}

class _StudyProfilePageState extends State<StudyProfilePage> {
  late final StudyProfileApi _api = widget.api ?? StudyProfileApi();
  StudyProfileView? _loaded;
  StudyProfile _value = StudyProfile.empty;
  String? _error;
  bool _saving = false, _showErrors = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final v = await _api.load();
      if (!mounted) return;
      setState(() {
        _loaded = v;
        _value = v.profile;
      });
    } catch (e) {
      if (mounted) setState(() => _error = studyErrorText(e));
    }
  }

  Future<void> _save() async {
    final required = _loaded?.settings.required ?? const <String>[];
    if (_value.missing(required).isNotEmpty) {
      setState(() => _showErrors = true);
      showAppNotice(t('أكمل الحقول المطلوبة', 'Fill in the required fields'), error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final v = await _api.save(_value);
      if (!mounted) return;
      setState(() {
        _loaded = v;
        _value = v.profile;
        _showErrors = false;
      });
      showAppNotice(t('حُفظت بيانات الدراسة', 'Study details saved'));
    } catch (e) {
      if (mounted) {
        if (studyErrorFields(e).isNotEmpty) setState(() => _showErrors = true);
        showAppNotice(studyErrorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _loaded;
    final dirty = loaded != null && _value != loaded.profile;
    final Widget body;
    if (loaded == null) {
      body = _error != null
          ? ErrorRetry(message: _error!, onRetry: _load)
          : const AppListSkeleton(items: 4);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          t('مرحلتك وصفك ومدرستك تساعد معلميك على معرفة من يدرّسون، وتظهر لهم وللإدارة فقط.',
              'Your stage, grade and school help your teachers know who they teach; only they and the admins see it.'),
          style: AppType.body(context),
        ),
        AppSpace.gapMd,
        StudyProfileForm(
          key: const ValueKey('study.page.form'),
          value: _value,
          required: loaded.settings.required,
          showErrors: _showErrors,
          onChanged: (v) => setState(() => _value = v),
        ),
        AppSpace.gapMd,
        AppButton.primary(
          key: const ValueKey('study.save'),
          label: t('حفظ', 'Save'),
          icon: Icons.check_rounded,
          busy: _saving,
          onPressed: dirty && !_saving ? _save : null,
        ),
      ]);
    }
    return BasePage(
      key: const ValueKey(kStudyProfileFeatureKey),
      width: AppWidth.form,
      appBar: ScreenAppBar(title: t('بيانات الدراسة', 'Study details')),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.md),
          child: AppUnsavedGuard(dirty: dirty, child: body),
        ),
      ),
    );
  }
}

/// The Account page's row into [StudyProfilePage] (students; kill switch `profile.study`).
class StudyProfileTile extends StatelessWidget {
  const StudyProfileTile({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => AppSettingsTile(
        featureKey: kStudyProfileFeatureKey,
        icon: Icons.school_rounded,
        label: t('بيانات الدراسة', 'Study details'),
        subtitle: t('المرحلة والصف والمدرسة', 'Stage, grade and school'),
        keywords: 'study school grade stage track governorate دراسة مدرسة صف مرحلة شعبة محافظة',
        onTap: onOpen,
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  The home card
// ═════════════════════════════════════════════════════════════════════════════

/// "Complete your profile": one calm card with one action and a close button (30 days, server side).
class StudyPromptCard extends StatelessWidget {
  const StudyPromptCard({super.key, required this.onOpen, required this.onDismiss});

  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: AppSpace.card,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppTouch.min,
            height: AppTouch.min,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: AppRadius.controlAll),
            child: Icon(Icons.school_rounded, color: c.primary, size: AppIconSize.md),
          ),
          AppSpace.gapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('أكمل ملفك الدراسي', 'Complete your study profile'), style: AppType.section(context)),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  t('أخبرنا بمرحلتك وصفك ليعرف معلموك من يدرّسون. دقيقة واحدة.',
                      'Tell us your stage and grade so your teachers know who they teach. One minute.'),
                  style: AppType.body(context),
                ),
                AppSpace.gapSm,
                AppButton.tonal(
                  key: const ValueKey('home_study.open'),
                  label: t('أكمل الآن', 'Complete now'),
                  icon: Icons.edit_rounded,
                  size: AppButtonSize.sm,
                  onPressed: onOpen,
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('home_study.dismiss'),
            tooltip: t('ليس الآن', 'Not now'),
            icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textMedium),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
