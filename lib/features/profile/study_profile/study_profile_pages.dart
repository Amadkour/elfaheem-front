// lib/features/profile/study_profile/study_profile_pages.dart
//
// Where a student meets their study data (D-790 – D-796), every surface behind the kill switch `profile.study`:
//
//   StudyProfileStepPage   the sign-up's ONE extra step (students, when the super admin keeps it on): stage + grade,
//                          the rest folded under "Add school and governorate"; its button creates the account
//   StudyProfilePage       Profile › Study details: the same form, loaded from and saved to /me/study-profile;
//                          offline the edit waits in the outbox, and a `sync_stale` answer puts the server's copy
//                          back in the form (StudyProfileSync, D-1352)
//   StudyProfileTile       the Account page's row into it
//   StudyPromptCard        the student home's dismissible "Complete your profile" card (plain values; the home shows it
//                          while /me/home says `study_prompt`, never a blocking wall)
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry, t;
import 'package:flutter_education_app/features/auth/auth_shell.dart';
import 'package:flutter_education_app/features/auth/auth_widgets.dart' show AuthButton;
import 'package:flutter_education_app/features/auth/register_levels_step.dart' show offerContactWhatsapp;
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_form.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_model.dart';

/// The catalog for the form: the countries and [country]'s stages (the profile's country, else the first one). Null
/// when nothing loaded, and the form falls back to its fixed keys.
Future<StudyEduData?> loadStudyEdu(String? country, {EduCatalog? catalog}) async {
  final countries = await EduCountries.load();
  final c = pickEduCountry(countries, country)?.code ?? (country ?? 'EG').toUpperCase();
  final cat = await (catalog ?? EduCatalog.instance).load(c);
  if (cat == null || cat.isEmpty) return null;
  return StudyEduData(
    countries: countries,
    country: c,
    stages: cat.stages,
    labels: cat.geoLabels,
    loadAreas: (parent) => (catalog ?? EduCatalog.instance).areas(c, parentId: parent),
  );
}

EduStage? _stageOf(StudyEduData? edu, StudyProfile v) {
  for (final s in edu?.stages ?? const <EduStage>[]) {
    if (s.id == v.stageId) return s;
  }
  return null;
}

EduCountry? _countryOf(StudyEduData? edu) => pickEduCountry(edu?.countries ?? const [], edu?.country);

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
  StudyEduData? _edu;
  List<(int, String)> _interests = const [];

  @override
  void initState() {
    super.initState();
    _loadEdu(widget.initial.countryCode);
    _loadInterests();
  }

  Future<void> _loadInterests() async {
    final v = await loadStudyInterestChoices();
    if (mounted) setState(() => _interests = v);
  }

  Future<void> _loadEdu(String? country) async {
    final e = await loadStudyEdu(country);
    if (mounted && e != null) setState(() => _edu = e);
  }

  /// The sign-up form asks the date of birth itself.
  List<String> get _required => [for (final f in widget.settings.required) if (f != 'dob') f];

  Future<void> _submit() async {
    if (_value.missingIn(_edu?.stages, _required).isNotEmpty) {
      setState(() => _showErrors = true);
      showAppNotice(t('أكمل الحقول المطلوبة', 'Fill in the required fields'), error: true);
      return;
    }
    final stage = _stageOf(_edu, _value), country = _countryOf(_edu);
    await widget.onSubmit(_value);
    // the account is made and this page is gone: a contact-only stage (university) is handed to WhatsApp
    if (!mounted) await offerContactWhatsapp(country, stage);
  }

  @override
  Widget build(BuildContext context) {
    // redesign (Stu1Auth?screen=study, S-A row 16): the auth hero, the card's one question
    return AuthScaffold(
      kicker: t('خطوة صغيرة', 'One small step'),
      heroTitle: t('خلّنا نعرفك أكثر', 'Let us get to know you'),
      squiggle: t('نعرفك', 'know'),
      title: t('سؤالين ونرتّب لك', "Two questions and you're set"),
      subtitle: null,
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
            edu: _edu,
            onCountry: _loadEdu,
            interestChoices: _interests,
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
  StudyEduData? _edu;
  List<(int, String)> _interests = const [];

  @override
  void initState() {
    super.initState();
    StudyProfileSync.wireSync();
    StudyProfileSync.latest.addListener(_onSync);
    _load();
    _loadInterests();
  }

  Future<void> _loadInterests() async {
    final v = await loadStudyInterestChoices();
    if (mounted) setState(() => _interests = v);
  }

  @override
  void dispose() {
    StudyProfileSync.latest.removeListener(_onSync);
    super.dispose();
  }

  /// The server's copy arrived through the outbox: an applied edit, or a stale one refused (the engine said so).
  void _onSync() {
    final x = StudyProfileSync.latest.value;
    if (x == null || !mounted) return;
    setState(() {
      _loaded = x.view;
      _value = x.view.profile;
      _showErrors = false;
    });
  }

  /// Keeps the edit on the device; false when there is no outbox here.
  Future<bool> _queue() async {
    if (!await _api.queue(_value, baseUpdatedAt: _loaded?.updatedAt)) return false;
    if (!mounted) return true;
    final l = _loaded!;
    setState(() {
      _loaded = StudyProfileView(profile: _value, settings: l.settings, updatedAt: l.updatedAt);
      _showErrors = false;
    });
    showAppNotice(t('حُفظت بيانات الدراسة على هذا الجهاز وتُرسل عند الاتصال.',
        'Study details saved on this device. They are sent once you are online.'));
    return true;
  }

  Future<void> _loadEdu(String? country) async {
    final e = await loadStudyEdu(country);
    if (mounted && e != null) setState(() => _edu = e);
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
      _loadEdu(v.profile.countryCode);
    } catch (e) {
      if (mounted) setState(() => _error = studyErrorText(e));
    }
  }

  Future<void> _save() async {
    final required = _loaded?.settings.required ?? const <String>[];
    if (_value.missingIn(_edu?.stages, required).isNotEmpty) {
      setState(() => _showErrors = true);
      showAppNotice(t('أكمل الحقول المطلوبة', 'Fill in the required fields'), error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      if (!offlineReadsOnline().value && await _queue()) return;
      final v = await _api.save(_value);
      if (!mounted) return;
      setState(() {
        _loaded = v;
        _value = v.profile;
        _showErrors = false;
      });
      showAppNotice(t('حُفظت بيانات الدراسة', 'Study details saved'));
      await offerContactWhatsapp(_countryOf(_edu), _stageOf(_edu, _value));
    } catch (e) {
      if (isTransportFailure(e) && await _queue()) return;
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
          edu: _edu,
          onCountry: _loadEdu,
          interestChoices: _interests,
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
    return SdArea(area: AppArea.me, child: BasePage(
      key: const ValueKey(kStudyProfileFeatureKey),
      useWebCard: true, // the form width role on a wide screen (D-805), not a 1400 px wide form
      width: AppWidth.form,
      appBar: ScreenAppBar(title: t('بيانات الدراسة', 'Study details')),
      child: SdHeroColumn(title: 'sd_h_study'.tr, subtitle: 'sd_h_study_d'.tr, icon: Icons.school_outlined, child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.md),
          child: AppUnsavedGuard(dirty: dirty, child: body),
        ),
      )),
    ));
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
