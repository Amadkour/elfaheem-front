// lib/features/shared/study_profile/study_profile_form.dart
//
// THE study-data form (D-790 – D-796): the sign-up's study step, the profile page and nothing else draw these fields.
// Plain values in ([value], [required]), the new value out ([onChanged]); no provider, no call, so the layout harness
// pumps it as it is.
//
//   stage      chips (primary · preparatory · secondary · university · graduate · other), always required
//   grade      chips of that stage (6 / 3 / 3 / 7 · none for graduate / other), always required when it has grades
//   track      chips, secondary 2 – 3 only (science · math · literary)
//   then       school or university · governorate (Egypt's 27 + "outside Egypt", which asks for a city) · date of
//              birth ([showDob]: the sign-up form has its own) · a parent's phone
//
// [compact] (the sign-up) folds the optional fields under "Add more details" unless the super admin made one of them
// required, so the step stays two taps long. [showErrors] marks what is missing under each group.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'study_profile_model.dart';

class StudyProfileForm extends StatefulWidget {
  const StudyProfileForm({
    super.key,
    required this.value,
    required this.onChanged,
    this.required = const [],
    this.showErrors = false,
    this.showDob = true,
    this.compact = false,
  });

  final StudyProfile value;
  final ValueChanged<StudyProfile> onChanged;

  /// The optional fields the super admin made required (StudySettings.required).
  final List<String> required;
  final bool showErrors;
  final bool showDob;
  final bool compact;

  @override
  State<StudyProfileForm> createState() => _StudyProfileFormState();
}

class _StudyProfileFormState extends State<StudyProfileForm> {
  late final _school = TextEditingController(text: widget.value.schoolName ?? '');
  late final _city = TextEditingController(text: widget.value.city ?? '');
  late final _parent = TextEditingController(text: widget.value.parentPhone ?? '');
  late bool _more = !widget.compact || _optionalShown(widget.value);

  /// Something optional is already filled in or required: the optional part starts open.
  bool _optionalShown(StudyProfile v) =>
      widget.required.any((f) => f != 'track') ||
      v.schoolName != null ||
      v.governorate != null ||
      v.parentPhone != null ||
      (widget.showDob && v.dob != null);

  @override
  void initState() {
    super.initState();
    _parent.addListener(_onParent);
  }

  @override
  void didUpdateWidget(covariant StudyProfileForm old) {
    super.didUpdateWidget(old);
    if (!_more && _optionalShown(widget.value)) _more = true;
  }

  @override
  void dispose() {
    _parent.removeListener(_onParent);
    _school.dispose();
    _city.dispose();
    _parent.dispose();
    super.dispose();
  }

  void _onParent() {
    if ((widget.value.parentPhone ?? '') != _parent.text) widget.onChanged(widget.value.withText('parent_phone', _parent.text));
  }

  bool _req(String f) => widget.required.contains(f);

  List<String> get _missing => widget.showErrors ? widget.value.missing(widget.required) : const [];

  Future<void> _pickDob() async {
    final cur = DateTime.tryParse(widget.value.dob ?? '');
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: cur ?? DateTime(now.year - 15, 1, 1),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 3, 12, 31),
    );
    if (picked == null || !mounted) return;
    final iso = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    widget.onChanged(widget.value.withText('dob', iso));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final missing = _missing;
    final grades = studyGradeCount(v.stage);
    final optional = <Widget>[
      AppField(
        controller: _school,
        label: v.stage == 'university' || v.stage == 'graduate'
            ? t('الجامعة أو الكلية', 'University or faculty')
            : t('اسم المدرسة', 'School name'),
        hint: t('مثال: مدرسة السعيدية الثانوية', 'e.g. Saidia Secondary School'),
        icon: Icons.apartment_rounded,
        required: _req('school_name'),
        maxLength: 150,
        errorText: missing.contains('school_name') ? _requiredText : null,
        textCapitalization: TextCapitalization.words,
        onChanged: (s) => widget.onChanged(widget.value.withText('school_name', s)),
      ),
      AppPicker<String>(
        label: t('المحافظة', 'Governorate') + (_req('governorate') ? ' *' : ''),
        value: v.governorate,
        icon: Icons.place_rounded,
        hint: t('اختر المحافظة', 'Pick your governorate'),
        allowNone: !_req('governorate'),
        options: {for (final k in kGovernorates.keys) k: studyGovernorateLabel(k)},
        onChanged: (g) => widget.onChanged(StudyProfile(
          stage: v.stage,
          grade: v.grade,
          track: v.track,
          schoolName: v.schoolName,
          governorate: g,
          city: v.city,
          parentPhone: v.parentPhone,
          dob: v.dob,
        )),
      ),
      if (missing.contains('governorate')) _ErrorLine(_requiredText),
      if (v.governorate == 'other')
        AppField(
          controller: _city,
          label: t('المدينة / البلد', 'City / country'),
          icon: Icons.location_city_rounded,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          onChanged: (s) => widget.onChanged(widget.value.withText('city', s)),
        ),
      if (widget.showDob) ...[
        _DobWell(
          label: studyFieldLabel('dob'),
          value: v.dob,
          required: _req('dob'),
          error: missing.contains('dob') ? _requiredText : null,
          onTap: _pickDob,
          onClear: v.dob == null || _req('dob') ? null : () => widget.onChanged(widget.value.withText('dob', '')),
        ),
        AppSpace.gapSm,
      ],
      PhoneInputField(controller: _parent, label: studyFieldLabel('parent_phone') + (_req('parent_phone') ? ' *' : '')),
      if (missing.contains('parent_phone')) _ErrorLine(_requiredText),
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxs),
        child: Text(
          t('لنتواصل مع ولي الأمر عند الحاجة فقط، ولا يظهر لزملائك.', 'Only to reach a parent when needed; classmates never see it.'),
          style: AppType.meta(context),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChipGroup(
          label: studyFieldLabel('stage'),
          required: true,
          error: missing.contains('stage') ? t('اختر مرحلتك الدراسية', 'Pick your stage') : null,
          children: [
            for (final s in kStudyStages)
              AppChoiceChip(
                key: ValueKey('study.stage.$s'),
                label: studyStageLabel(s),
                selected: v.stage == s,
                onTap: () => widget.onChanged(v.copyWith(stage: s)),
              ),
          ],
        ),
        AnimatedSize(
          duration: AppMotion.of(context).base,
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: grades == 0
              ? const SizedBox(width: double.infinity)
              : _ChipGroup(
                  label: v.stage == 'university' ? t('الفرقة', 'Year') : t('الصف', 'Grade'),
                  required: true,
                  error: missing.contains('grade') ? t('اختر صفك', 'Pick your grade') : null,
                  children: [
                    for (var g = 1; g <= grades; g++)
                      AppChoiceChip(
                        key: ValueKey('study.grade.$g'),
                        label: studyGradeShort(v.stage!, g),
                        selected: v.grade == g,
                        onTap: () => widget.onChanged(v.copyWith(grade: g)),
                      ),
                  ],
                ),
        ),
        AnimatedSize(
          duration: AppMotion.of(context).base,
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: !studyTrackApplies(v.stage, v.grade)
              ? const SizedBox(width: double.infinity)
              : _ChipGroup(
                  label: studyFieldLabel('track'),
                  required: _req('track'),
                  error: missing.contains('track') ? t('اختر شعبتك', 'Pick your track') : null,
                  children: [
                    for (final tr in kStudyTracks)
                      AppChoiceChip(
                        key: ValueKey('study.track.$tr'),
                        label: studyTrackLabel(tr),
                        selected: v.track == tr,
                        onTap: () => widget.onChanged(v.track == tr ? v.copyWith(clearTrack: true) : v.copyWith(track: tr)),
                      ),
                  ],
                ),
        ),
        AppSpace.gapXs,
        if (_more)
          ...optional
        else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.ghost(
              key: const ValueKey('study.more'),
              label: t('أضف المدرسة والمحافظة (اختياري)', 'Add school and governorate (optional)'),
              icon: Icons.add_rounded,
              onPressed: () => setState(() => _more = true),
            ),
          ),
      ],
    );
  }

  String get _requiredText => t('هذا الحقل مطلوب', 'This field is required');
}

/// A label, a wrap of chips and the group's error line, with the form's 12 px rhythm under it.
class _ChipGroup extends StatelessWidget {
  const _ChipGroup({required this.label, required this.children, this.required = false, this.error});

  final String label;
  final List<Widget> children;
  final bool required;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Semantics(
        container: true,
        label: label,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          AppFieldLabel(label, required: required),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: children),
          if (error != null) _ErrorLine(error!),
        ]),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxs, bottom: AppSpace.xs),
        child: Text(text, style: AppType.meta(context).copyWith(color: context.colors.danger)),
      );
}

/// The date of birth: the kit's well, a tap opens the date picker; the date is shown left to right (YYYY-MM-DD).
class _DobWell extends StatelessWidget {
  const _DobWell({required this.label, required this.value, required this.onTap, this.onClear, this.required = false, this.error});

  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool required;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '$label ${value ?? ''}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        AppFieldLabel(label, required: required),
        InkWell(
          key: const ValueKey('study.dob'),
          onTap: onTap,
          borderRadius: AppRadius.controlAll,
          child: InputDecorator(
            isEmpty: value == null,
            decoration: appFieldDecoration(
              context,
              hint: t('اختر التاريخ', 'Pick the date'),
              icon: Icons.cake_rounded,
              errorText: error,
              suffix: onClear == null
                  ? Icon(Icons.calendar_month_rounded, size: AppIconSize.md, color: c.textMedium)
                  : IconButton(
                      tooltip: t('مسح', 'Clear'),
                      icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textMedium),
                      onPressed: onClear,
                    ),
            ),
            child: Text(value ?? '', textDirection: TextDirection.ltr, style: AppType.body(context).copyWith(color: c.textDark)),
          ),
        ),
      ]),
    );
  }
}
