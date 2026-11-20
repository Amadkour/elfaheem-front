// lib/features/profile/study_profile/study_profile_form.dart
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

import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/design/edu_pickers.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/auth/register_levels_step.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_model.dart';

/// The catalog behind the form (Learning Hub): the countries, the chosen country's stages and its area loader. With
/// it the stage / grade / area fields come from the catalog and the profile carries ids; without it the form is the
/// older fixed-key one (an older server, or a catalog that did not load).
class StudyEduData {
  const StudyEduData({required this.countries, required this.country, required this.stages, required this.loadAreas, this.labels = const EduGeoLabels()});

  final List<EduCountry> countries;
  final String country;
  final List<EduStage> stages;
  final EduAreaLoader loadAreas;
  final EduGeoLabels labels;
}

class StudyProfileForm extends StatefulWidget {
  const StudyProfileForm({
    super.key,
    required this.value,
    required this.onChanged,
    this.required = const [],
    this.showErrors = false,
    this.showDob = true,
    this.compact = false,
    this.edu,
    this.onCountry,
  });

  /// The catalog (see [StudyEduData]); [onCountry] asks the page to load another country's catalog.
  final StudyEduData? edu;
  final ValueChanged<String>? onCountry;

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
    _resolveArea();
  }

  @override
  void didUpdateWidget(covariant StudyProfileForm old) {
    super.didUpdateWidget(old);
    if (!_more && _optionalShown(widget.value)) _more = true;
    _resolveArea();
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

  EduArea? _area1, _area2;
  String? _pendingTrack;

  int? _resolvedFor;

  /// The saved area's own names (D-1315): `area_id` may be a city (level 2), so it is looked up in the areas list,
  /// level 1 first, then the children of the governorate the server wrote next to it. Until then (or when it is not
  /// found) [_areaFromProfile] shows the governorate's name.
  Future<void> _resolveArea() async {
    final id = widget.value.areaId;
    final edu = widget.edu;
    if (id == null || edu == null || _area1 != null || _resolvedFor == id) return;
    _resolvedFor = id;
    void use(EduArea a1, EduArea? a2) {
      if (!mounted || _area1 != null || widget.value.areaId != id) return;
      setState(() {
        _area1 = a1;
        _area2 = a2;
      });
    }

    try {
      final top = await edu.loadAreas(null);
      final key = (widget.value.governorate ?? '').trim().toLowerCase();
      EduArea? parent;
      for (final a in top) {
        if (a.id == id) return use(a, null);
        if (a.key == key) parent = a;
      }
      if (parent == null) return;
      for (final c in await edu.loadAreas(parent.id)) {
        if (c.id == id) return use(parent, c);
      }
    } catch (_) {}
  }

  /// The saved area before its names are resolved: the old governorate key the server wrote.
  EduArea? _areaFromProfile(StudyProfile v) {
    if (v.areaId == null) return null;
    final name = v.governorate == null ? '' : studyGovernorateLabel(v.governorate!);
    return EduArea(id: v.areaId!, key: v.governorate ?? '', nameAr: name, nameEn: name);
  }

  List<String> get _missing =>
      widget.showErrors ? widget.value.missingIn(widget.edu?.stages, widget.required) : const [];

  void _eduChanged(String? country, int? stageId, int? gradeId, String? track) {
    final v = widget.value;
    final edu = widget.edu!;
    if (country != null && country != edu.country) {
      widget.onCountry?.call(country);
      widget.onChanged(v.withEdu(countryCode: country, gender: v.gender));
      return;
    }
    EduStage? st;
    for (final s in edu.stages) {
      if (s.id == stageId) st = s;
    }
    EduGrade? gr;
    for (final g in st?.grades ?? const <EduGrade>[]) {
      if (g.id == gradeId) gr = g;
    }
    final keepArea = v.countryCode == edu.country;
    widget.onChanged(v.withEdu(
      countryCode: edu.country,
      stageId: stageId,
      gradeId: gradeId,
      track: track,
      areaId: keepArea ? v.areaId : null,
      gender: v.gender,
      stageKey: st?.key,
      gradeNumber: gr?.number,
    ));
  }

  Widget _gender(StudyProfile v) => _ChipGroup(
        label: t('النوع (اختياري)', 'Gender (optional)'),
        children: [
          for (final g in const ['m', 'f'])
            AppChoiceChip(
              key: ValueKey('study.gender.$g'),
              label: g == 'm' ? t('ذكر', 'Male') : t('أنثى', 'Female'),
              selected: v.gender == g,
              onTap: () => widget.onChanged(v.withEdu(
                countryCode: v.countryCode,
                stageId: v.stageId,
                gradeId: v.gradeId,
                track: v.track,
                areaId: v.areaId,
                gender: v.gender == g ? null : g,
                stageKey: v.stage,
                gradeNumber: v.grade,
              )),
            ),
        ],
      );

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
      if (widget.edu != null) ...[
        EduAreaPicker(
          loadAreas: widget.edu!.loadAreas,
          labels: widget.edu!.labels,
          required: _req('governorate'),
          level1: _area1 ?? _areaFromProfile(v),
          level2: _area2,
          onChanged: (a1, a2) {
            _area1 = a1;
            _area2 = a2;
            widget.onChanged(v.withEdu(
              countryCode: v.countryCode,
              stageId: v.stageId,
              gradeId: v.gradeId,
              track: v.track,
              areaId: (a2 ?? a1).id,
              gender: v.gender,
              stageKey: v.stage,
              gradeNumber: v.grade,
            ));
          },
        ),
        if (missing.contains('governorate')) _ErrorLine(_requiredText),
      ] else
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
          gender: v.gender,
        )),
      ),
      if (widget.edu == null && missing.contains('governorate')) _ErrorLine(_requiredText),
      if (widget.edu == null && v.governorate == 'other')
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
        if (widget.edu != null) ...[
          RegisterLevelsStep(
            countries: widget.edu!.countries,
            country: widget.edu!.country,
            stages: widget.edu!.stages,
            stageId: v.stageId,
            gradeId: v.gradeId,
            trackKey: v.track,
            onTrack: (tr) => _pendingTrack = tr,
            errorText: missing.contains('stage')
                ? t('اختر مرحلتك الدراسية', 'Pick your stage')
                : (missing.contains('grade') ? t('اختر صفك', 'Pick your grade') : null),
            onChanged: (c, st, g) => _eduChanged(c, st, g, _pendingTrack),
          ),
          AppSpace.gapMd,
          _gender(v),
        ] else ...[
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
        ],
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
