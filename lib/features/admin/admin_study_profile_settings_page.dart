// lib/features/admin/admin_study_profile_settings_page.dart
//
// SUPER ADMIN: a personal student's study data (D-794). Three settings, one Save:
//   • the sign-up's study step (stage + grade) for new students — on / off
//   • the home's dismissible "Complete your study profile" card — on / off
//   • which optional fields become required (track where it applies · school · governorate · date of birth ·
//     parent phone); stage + grade are always required
// GET / PUT /api/v1/admin/study-profile/settings; the same values reach the sign-up through GET /auth/policy.
//
// StudyProfileSection is the "Study" block of a student in the users page's detail (GET /admin/users/{id}).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_model.dart';

import 'admin_common.dart' show ErrorRetry, KeyValue, Section, t;
import 'admin_page.dart';

class AdminStudyProfileSettingsPage extends StatefulWidget {
  const AdminStudyProfileSettingsPage({super.key, this.api});

  final StudyProfileApi? api;

  @override
  State<AdminStudyProfileSettingsPage> createState() => _AdminStudyProfileSettingsPageState();
}

class _AdminStudyProfileSettingsPageState extends State<AdminStudyProfileSettingsPage> {
  late final StudyProfileApi _api = widget.api ?? StudyProfileApi();
  StudySettings? _saved;
  StudySettings _value = const StudySettings();
  String? _error;
  bool _saving = false;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await _api.loadSettings();
      if (!mounted) return;
      setState(() {
        _saved = s;
        _value = s;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _error = studyErrorText(e));
    }
  }

  bool get _dirty {
    final s = _saved;
    if (s == null) return false;
    return s.signupStep != _value.signupStep ||
        s.homePrompt != _value.homePrompt ||
        s.required.join(',') != _value.required.join(',');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final s = await _api.saveSettings(_value);
      if (!mounted) return;
      setState(() {
        _saved = s;
        _value = s;
      });
      showAppNotice(t('حُفظت الإعدادات', 'Settings saved'));
    } catch (e) {
      if (mounted) showAppNotice(studyErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleRequired(String f) {
    final set = {..._value.required};
    set.contains(f) ? set.remove(f) : set.add(f);
    setState(() => _value = _value.copyWith(required: [for (final k in kStudyOptionalFields) if (set.contains(k)) k]));
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_saved == null) {
      body = _error != null ? ErrorRetry(message: _error!, onRetry: _load) : const AppListSkeleton(items: 3);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppCard(
          padding: AppSpace.card,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSwitchTile(
              key: const ValueKey('study_settings.step'),
              title: t('خطوة الدراسة عند التسجيل', 'Study step at sign-up'),
              subtitle: t('يختار الطالب الجديد مرحلته وصفه قبل إنشاء الحساب',
                  'A new student picks their stage and grade before the account is created'),
              icon: Icons.how_to_reg_rounded,
              value: _value.signupStep,
              onChanged: (v) => setState(() => _value = _value.copyWith(signupStep: v)),
            ),
            AppSwitchTile(
              key: const ValueKey('study_settings.prompt'),
              title: t('بطاقة «أكمل ملفك الدراسي» في الرئيسية', 'The “Complete your study profile” home card'),
              subtitle: t('للطلاب الذين لم يكملوا بياناتهم؛ يمكن إخفاؤها 30 يوماً',
                  'For students whose details are incomplete; they can hide it for 30 days'),
              icon: Icons.dashboard_customize_rounded,
              value: _value.homePrompt,
              onChanged: (v) => setState(() => _value = _value.copyWith(homePrompt: v)),
            ),
          ]),
        ),
        AppSpace.gapMd,
        AppCard(
          padding: AppSpace.card,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('الحقول المطلوبة', 'Required fields'), style: AppType.section(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(
              t('المرحلة والصف مطلوبان دائماً. اختر ما يصبح مطلوباً أيضاً؛ الشعبة تُطلب فقط في الصفين الثاني والثالث الثانوي.',
                  'Stage and grade are always required. Pick what else becomes required; the track is asked only in secondary 2 and 3.'),
              style: AppType.body(context),
            ),
            AppSpace.gapSm,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final f in kStudyOptionalFields)
                AppChoiceChip(
                  key: ValueKey('study_settings.req.$f'),
                  label: studyFieldLabel(f),
                  icon: _value.required.contains(f) ? Icons.check_rounded : null,
                  selected: _value.required.contains(f),
                  onTap: () => _toggleRequired(f),
                ),
            ]),
          ]),
        ),
      ]);
    }
    return AdminPage(
      width: AppWidth.reading,
      title: t('بيانات الدراسة للطلاب', 'Student study details'),
      subtitle: t('ما يُسأل عنه الطالب عند التسجيل وفي ملفه', 'What students are asked at sign-up and in their profile'),
      icon: Icons.school_rounded,
      onRefresh: _saving ? null : _load,
      updatedAt: _loadedAt,
      dirty: _dirty,
      primaryAction: _saved == null
          ? null
          : AppButton.primary(
              key: const ValueKey('study_settings.save'),
              label: t('حفظ', 'Save'),
              busy: _saving,
              onPressed: _dirty && !_saving ? _save : null,
            ),
      body: body,
    );
  }
}

/// A student's study data in the admin user detail (plain values).
class StudyProfileSection extends StatelessWidget {
  const StudyProfileSection({super.key, required this.profile});

  final StudyProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Section(
      title: t('الدراسة', 'Study'),
      child: Column(children: [
        KeyValue(studyFieldLabel('grade'), p.summary.isEmpty ? '—' : p.summary),
        if (p.schoolName != null) KeyValue(studyFieldLabel('school_name'), p.schoolName!),
        if (p.governorate != null)
          KeyValue(studyFieldLabel('governorate'),
              p.governorate == 'other' ? (p.city ?? studyGovernorateLabel('other')) : studyGovernorateLabel(p.governorate!)),
        if (p.parentPhone != null) KeyValue(studyFieldLabel('parent_phone'), p.parentPhone!),
      ]),
    );
  }
}
