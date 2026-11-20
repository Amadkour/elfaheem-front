// lib/features/courses/course_filters.dart — THE course filter bar (Learning Hub F6, D-1325): stage → grade, subject,
// delivery (online / in person) and area over GET /api/v1/courses (CONTRACT §4: `country`, `stage_id`, `grade_id`,
// `subject_id`, `delivery`, `area_id`).
//
//   CourseFilters       the filter model ↔ the query params (the same map the join flow hands the explorer), plus
//                       `matches(CourseSetup)`: the server's rules on a list already loaded (the student home)
//   CourseFilterStore   remembered per user (SharedPreferences `course_filters_<user>`); with nothing remembered the
//                       start is the study profile's country / stage / grade (`course_filters_seed_<user>`, written
//                       whenever StudyProfileApi loads or saves the profile, so the home never asks for it)
//   CourseFilterEdu     the catalog the bar draws names from (EduCatalog); `storedOnly` = no request
//   CourseFilterBar     plain values in, a callback out: chips + a "Filters" sheet on a phone, one row on a desktop,
//                       the result count and "Clear"
//   CourseFilterScope   the student home's host: remembered filters + the stored catalog, no request on load
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/edu_pickers.dart';
import 'package:flutter_education_app/features/courses/course_setup.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String _str(Object? v) => v is String ? v : '';

const Object _keep = Object();

// ═════════════════════════════════════════════════════════════════════════════
//  The model
// ═════════════════════════════════════════════════════════════════════════════

class CourseFilters {
  const CourseFilters({
    this.country,
    this.stageId,
    this.gradeId,
    this.subjectId,
    this.delivery,
    this.areaId,
    this.areaAr = '',
    this.areaEn = '',
  });

  static const empty = CourseFilters();

  /// `delivery` values (null = either).
  static const deliveries = ['online', 'in_person'];

  /// From GET /courses params (or the join flow's `filters` map); unknown keys and bad values are dropped.
  factory CourseFilters.fromQuery(Map<String, dynamic>? q) {
    if (q == null) return empty;
    final c = _str(q['country']).trim().toUpperCase();
    final d = _str(q['delivery']);
    return CourseFilters(
      country: c.length == 2 ? c : null,
      stageId: _int(q['stage_id']),
      gradeId: _int(q['grade_id']),
      subjectId: _int(q['subject_id']),
      delivery: deliveries.contains(d) ? d : null,
      areaId: _int(q['area_id']),
    );
  }

  factory CourseFilters.fromJson(Object? j) {
    if (j is! Map) return empty;
    final m = Map<String, dynamic>.from(j);
    return CourseFilters.fromQuery(m)._copy(areaAr: _str(m['area_ar']), areaEn: _str(m['area_en']));
  }

  final String? country;
  final int? stageId, gradeId, subjectId, areaId;

  /// online | in_person | null.
  final String? delivery;

  /// The area's names, for the chip (the query carries the id only).
  final String areaAr, areaEn;

  /// The GET /courses params (CONTRACT §4).
  Map<String, dynamic> toQuery() => {
        'country': ?country,
        'stage_id': ?stageId,
        'grade_id': ?gradeId,
        'subject_id': ?subjectId,
        'delivery': ?delivery,
        'area_id': ?areaId,
      };

  Map<String, dynamic> toJson() => {
        ...toQuery(),
        if (areaId != null) ...{'area_ar': areaAr, 'area_en': areaEn},
      };

  /// Nothing the person picked (the country alone is where they are, not a filter).
  bool get isEmpty => stageId == null && gradeId == null && subjectId == null && delivery == null && areaId == null;

  /// The picked filters: the level (stage / grade) counts once.
  int get activeCount =>
      ((stageId != null || gradeId != null) ? 1 : 0) +
      (subjectId != null ? 1 : 0) +
      (delivery != null ? 1 : 0) +
      (areaId != null ? 1 : 0);

  String get areaName {
    final first = AppConfig.lang == 'ar' ? areaAr : areaEn;
    return first.isNotEmpty ? first : (AppConfig.lang == 'ar' ? areaEn : areaAr);
  }

  CourseFilters _copy({
    Object? country = _keep,
    Object? stageId = _keep,
    Object? gradeId = _keep,
    Object? subjectId = _keep,
    Object? delivery = _keep,
    Object? areaId = _keep,
    String? areaAr,
    String? areaEn,
  }) =>
      CourseFilters(
        country: identical(country, _keep) ? this.country : country as String?,
        stageId: identical(stageId, _keep) ? this.stageId : stageId as int?,
        gradeId: identical(gradeId, _keep) ? this.gradeId : gradeId as int?,
        subjectId: identical(subjectId, _keep) ? this.subjectId : subjectId as int?,
        delivery: identical(delivery, _keep) ? this.delivery : delivery as String?,
        areaId: identical(areaId, _keep) ? this.areaId : areaId as int?,
        areaAr: areaAr ?? this.areaAr,
        areaEn: areaEn ?? this.areaEn,
      );

  /// Another stage drops the grade; the subject stays (the server answers an empty list rather than an error).
  CourseFilters withLevel(int? stageId, int? gradeId) => _copy(stageId: stageId, gradeId: gradeId);
  CourseFilters withSubject(int? id) => _copy(subjectId: id);
  CourseFilters withDelivery(String? d) => _copy(delivery: deliveries.contains(d) ? d : null);
  CourseFilters withArea(int? id, {String ar = '', String en = ''}) => _copy(areaId: id, areaAr: ar, areaEn: en);

  /// "Clear": every filter off, the country kept.
  CourseFilters cleared() => CourseFilters(country: country);

  /// The server's rules (CONTRACT §4) on a course already loaded: a grade matches a target of that grade or a
  /// whole-stage target of its stage; a stage any target of it; online / in person also match `both`; a level-1
  /// area every course under it. The country is left to the list's own call.
  bool matches(CourseSetup s) {
    if (delivery == 'online' && s.deliveryMode == 'in_person') return false;
    if (delivery == 'in_person' && s.deliveryMode == 'online') return false;
    if (subjectId != null && s.subject?.id != subjectId) return false;
    if (areaId != null && s.area?.id != areaId && s.area?.parent?.id != areaId) return false;
    if (gradeId != null) {
      return s.targets.any((t) => t.gradeId == gradeId || (t.gradeId == null && stageId != null && t.stageId == stageId));
    }
    if (stageId != null) return s.targets.any((t) => t.stageId == stageId);
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is CourseFilters &&
      other.country == country &&
      other.stageId == stageId &&
      other.gradeId == gradeId &&
      other.subjectId == subjectId &&
      other.delivery == delivery &&
      other.areaId == areaId;

  @override
  int get hashCode => Object.hash(country, stageId, gradeId, subjectId, delivery, areaId);

  @override
  String toString() => 'CourseFilters(${toQuery()})';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Remembered per user
// ═════════════════════════════════════════════════════════════════════════════

class CourseFilterStore {
  CourseFilterStore._();

  /// Test hook.
  static Future<SharedPreferences> Function() prefs = SharedPreferences.getInstance;

  static String _key(String user) => 'course_filters_$user';
  static String _seedKey(String user) => 'course_filters_seed_$user';

  /// The signed-in user's id ('guest' in guest mode or signed out) and whether they are a student.
  static Future<({String id, bool student})> user() async {
    if (GuestState.active) return (id: 'guest', student: false);
    try {
      final u = (await StorageService.getInstance()).savedUser;
      final id = u?['id'];
      if (id == null) return (id: 'guest', student: false);
      return (id: '$id', student: (u?['role'] ?? 'student') == 'student');
    } catch (_) {
      return (id: 'guest', student: false);
    }
  }

  static Future<Map<String, dynamic>?> _read(String key) async {
    try {
      final raw = (await prefs()).getString(key);
      return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  /// The remembered filters (an explicit "Clear" is remembered too), else the study profile's level, else empty.
  static Future<CourseFilters> initial(String user) async {
    final saved = await _read(_key(user));
    if (saved != null) return CourseFilters.fromJson(saved);
    final seed = await _read(_seedKey(user));
    return seed == null ? CourseFilters.empty : CourseFilters.fromQuery(seed);
  }

  /// Something to start from is stored (remembered filters or the profile's level).
  static Future<bool> known(String user) async {
    try {
      final p = await prefs();
      return p.containsKey(_key(user)) || p.containsKey(_seedKey(user));
    } catch (_) {
      return false;
    }
  }

  static Future<void> save(String user, CourseFilters f) async {
    try {
      await (await prefs()).setString(_key(user), jsonEncode(f.toJson()));
    } catch (_) {}
  }

  /// The study profile's country / stage / grade, the start when nothing is remembered (StudyProfileApi calls it).
  static Future<void> rememberProfile({String? country, int? stageId, int? gradeId}) async {
    final u = await user();
    if (u.id == 'guest') return;
    try {
      await (await prefs()).setString(_seedKey(u.id),
          jsonEncode(CourseFilters(country: country?.toUpperCase(), stageId: stageId, gradeId: gradeId).toQuery()));
    } catch (_) {}
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The catalog the bar names things from
// ═════════════════════════════════════════════════════════════════════════════

class CourseFilterEdu {
  const CourseFilterEdu({required this.catalog, required this.loadAreas});

  final EduCountryCatalog catalog;
  final EduAreaLoader loadAreas;

  /// [country]'s catalog (EG when none). [storedOnly]: memory or the stored copy, never a request.
  static Future<CourseFilterEdu?> load(String? country, {bool storedOnly = false, EduCatalog? source}) async {
    final s = source ?? EduCatalog.instance;
    final c = (country == null || country.isEmpty) ? 'EG' : country.toUpperCase();
    final cat = storedOnly ? await s.stored(c) : await s.load(c);
    if (cat == null || cat.isEmpty) return null;
    return CourseFilterEdu(catalog: cat, loadAreas: (parent) => s.areas(c, parentId: parent));
  }
}

String _deliveryName(String? d) => switch (d) {
      'online' => _t('أونلاين', 'Online'),
      'in_person' => _t('حضوري', 'In person'),
      _ => _t('الكل', 'Any'),
    };

/// The level chip: the grade's name, else the stage's (generic words while the catalog is not loaded).
String _levelName(CourseFilters f, EduCountryCatalog? cat) {
  final g = cat?.grade(f.gradeId);
  if (g != null) return g.name;
  final s = cat?.stage(f.stageId);
  if (s != null) return s.name;
  return f.gradeId != null ? _t('صفك الدراسي', 'Your grade') : _t('مرحلتك', 'Your stage');
}

String _subjectName(CourseFilters f, EduCountryCatalog? cat) => cat?.subject(f.subjectId)?.name ?? _t('المادة', 'Subject');

String _areaLabel(CourseFilters f) => f.areaName.isNotEmpty ? f.areaName : _t('المنطقة', 'Area');

String courseCountText(int n) => countText(n,
    ar1: 'دورة واحدة',
    ar2: 'دورتان',
    arFew: '$n دورات',
    arMany: '$n دورة',
    en1: '1 course',
    en: '$n courses',
    ar0: 'لا توجد دورات',
    en0: 'No courses');

// ═════════════════════════════════════════════════════════════════════════════
//  The bar
// ═════════════════════════════════════════════════════════════════════════════

/// The filter bar. [edu] names the chips and fills the desktop row (null = not loaded: the phone layout, and the
/// sheet loads it through [loadEdu]). [resultCount] null = hidden (loading).
class CourseFilterBar extends StatelessWidget {
  const CourseFilterBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.edu,
    this.loadEdu,
    this.resultCount,
  });

  final CourseFilters value;
  final ValueChanged<CourseFilters> onChanged;
  final CourseFilterEdu? edu;
  final Future<CourseFilterEdu?> Function()? loadEdu;
  final int? resultCount;

  /// From this width (and with the catalog) the bar is one row of fields.
  static const double rowFrom = 900;

  Future<void> _openSheet(BuildContext context) async {
    final r = await showAppSheet<CourseFilters>(
      context,
      (_) => _CourseFilterSheet(initial: value, edu: edu, loadEdu: loadEdu),
    );
    if (r != null && r != value) onChanged(r);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => box.maxWidth >= rowFrom && edu != null ? _row(context) : _compact(context),
      );

  Widget _summary(BuildContext context) {
    final c = context.colors;
    final n = resultCount;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (n != null)
          Flexible(
            child: Semantics(
              liveRegion: true,
              child: Text(courseCountText(n),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textDark)),
            ),
          ),
        if (!value.isEmpty) ...[
          const SizedBox(width: AppSpace.xs),
          TextButton.icon(
            key: const ValueKey('course_filters.clear'),
            onPressed: () => onChanged(value.cleared()),
            style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            icon: const Icon(Icons.close_rounded, size: AppIconSize.sm),
            label: Text(_t('مسح', 'Clear')),
          ),
        ],
      ],
    );
  }

  // ── phone: "Filters" + the active chips, then the count and Clear ──────────
  Widget _compact(BuildContext context) {
    final cat = edu?.catalog;
    final v = value;
    final chips = <Widget>[
      if (v.stageId != null || v.gradeId != null)
        _ActiveChip(label: _levelName(v, cat), onRemove: () => onChanged(v.withLevel(null, null))),
      if (v.subjectId != null) _ActiveChip(label: _subjectName(v, cat), onRemove: () => onChanged(v.withSubject(null))),
      if (v.delivery != null) _ActiveChip(label: _deliveryName(v.delivery), onRemove: () => onChanged(v.withDelivery(null))),
      if (v.areaId != null) _ActiveChip(label: _areaLabel(v), onRemove: () => onChanged(v.withArea(null))),
    ];
    final n = v.activeCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            AppButton(
              key: const ValueKey('course_filters.open'),
              label: n == 0 ? _t('تصفية', 'Filters') : '${_t('تصفية', 'Filters')} · $n',
              icon: Icons.tune_rounded,
              variant: n == 0 ? AppButtonVariant.secondary : AppButtonVariant.tonal,
              size: AppButtonSize.sm,
              onPressed: () => _openSheet(context),
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (var i = 0; i < chips.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpace.xs),
                      chips[i],
                    ],
                  ]),
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
        if (resultCount != null || !v.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Align(alignment: AlignmentDirectional.centerStart, child: _summary(context)),
          ),
      ],
    );
  }

  // ── desktop: one row of fields ─────────────────────────────────────────────
  Widget _row(BuildContext context) {
    final cat = edu!.catalog;
    final v = value;
    final stage = cat.stage(v.stageId);
    final grades = stage != null && stage.hasGrades ? stage.grades : const <EduGrade>[];
    final subjects = cat.subjectsOf(v.gradeId);
    Widget field(String label, Widget child, {int flex = 3}) => Expanded(
          flex: flex,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            AppFieldLabel(label),
            child,
          ]),
        );
    DropdownMenuItem<int> any() => DropdownMenuItem(value: 0, child: Text(_t('الكل', 'Any'), overflow: TextOverflow.ellipsis));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        field(
          _t('المرحلة', 'Stage'),
          AppDropdown<int>(
            key: const ValueKey('course_filters.stage'),
            value: stage?.id ?? 0,
            items: [
              any(),
              for (final s in cat.stages) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (id) => onChanged(v.withLevel(id == null || id == 0 ? null : id, null)),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        field(
          _t('الصف', 'Grade'),
          AppDropdown<int>(
            key: const ValueKey('course_filters.grade'),
            enabled: grades.isNotEmpty,
            value: grades.any((g) => g.id == v.gradeId) ? v.gradeId : 0,
            items: [
              any(),
              for (final g in grades) DropdownMenuItem(value: g.id, child: Text(g.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (id) => onChanged(v.withLevel(v.stageId, id == null || id == 0 ? null : id)),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        field(
          _t('المادة', 'Subject'),
          AppDropdown<int>(
            key: const ValueKey('course_filters.subject'),
            value: subjects.any((s) => s.id == v.subjectId) ? v.subjectId : 0,
            items: [
              any(),
              for (final s in subjects) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (id) => onChanged(v.withSubject(id == null || id == 0 ? null : id)),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        field(
          _t('طريقة الدراسة', 'How'),
          AppDropdown<String>(
            key: const ValueKey('course_filters.delivery'),
            value: v.delivery ?? '',
            items: [
              for (final d in const ['', ...CourseFilters.deliveries])
                DropdownMenuItem(value: d, child: Text(_deliveryName(d.isEmpty ? null : d), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (d) => onChanged(v.withDelivery(d)),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          flex: 4,
          child: EduAreaPicker(
            key: const ValueKey('course_filters.area'),
            label: _t('المنطقة', 'Area'),
            loadAreas: edu!.loadAreas,
            labels: cat.geoLabels,
            level1: v.areaId == null
                ? null
                : EduArea(id: v.areaId!, key: '', nameAr: v.areaAr.isEmpty ? _areaLabel(v) : v.areaAr, nameEn: v.areaEn.isEmpty ? _areaLabel(v) : v.areaEn),
            onChanged: (l1, l2) {
              final a = l2 ?? l1;
              onChanged(v.withArea(a.id, ar: a.nameAr, en: a.nameEn));
            },
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Flexible(
          flex: 3,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Align(alignment: AlignmentDirectional.centerEnd, widthFactor: 1, child: _summary(context)),
          ),
        ),
      ],
    );
  }
}

/// A picked filter on the phone bar: its name and a remove mark; the whole chip removes it.
class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '${_t('إزالة', 'Remove')} $label',
      child: ExcludeSemantics(
        child: Material(
          color: c.primaryTint,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.chipAll,
            side: BorderSide(color: c.primary, width: AppBorder.hairline),
          ),
          child: InkWell(
            borderRadius: AppRadius.chipAll,
            onTap: onRemove,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpace.md, end: AppSpace.sm),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: AppType.row(context).copyWith(color: c.primary, fontWeight: FontWeight.w600)),
                  const SizedBox(width: AppSpace.xxs),
                  Icon(Icons.close_rounded, size: AppIconSize.sm, color: c.primary),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The sheet (phone, or a desktop without the catalog yet)
// ═════════════════════════════════════════════════════════════════════════════

class _CourseFilterSheet extends StatefulWidget {
  const _CourseFilterSheet({required this.initial, this.edu, this.loadEdu});
  final CourseFilters initial;
  final CourseFilterEdu? edu;
  final Future<CourseFilterEdu?> Function()? loadEdu;

  @override
  State<_CourseFilterSheet> createState() => _CourseFilterSheetState();
}

class _CourseFilterSheetState extends State<_CourseFilterSheet> {
  late CourseFilters _f = widget.initial;
  late CourseFilterEdu? _edu = widget.edu;
  late bool _loading = _edu == null && widget.loadEdu != null;

  @override
  void initState() {
    super.initState();
    if (_loading) _load();
  }

  Future<void> _load() async {
    CourseFilterEdu? r;
    try {
      r = await widget.loadEdu!();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _edu = r;
        _loading = false;
      });
    }
  }

  Widget _group(String label, List<Widget> chips) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFieldLabel(label),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: chips),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final cat = _edu?.catalog;
    final f = _f;
    final subjects = cat?.subjectsOf(f.gradeId) ?? const <EduSubject>[];
    return AppSheetContent(
      title: _t('تصفية الدورات', 'Filter courses'),
      icon: Icons.tune_rounded,
      children: [
        if (_loading)
          const AppListSkeleton(items: 3, withAvatar: false)
        else ...[
          EduStageGradePicker(
            stages: cat?.stages ?? const [],
            stageId: f.stageId,
            gradeId: f.gradeId,
            onChanged: (s, g, _) => setState(() => _f = f.withLevel(s, g)),
          ),
          if (subjects.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            _group(_t('المادة', 'Subject'), [
              EduChoiceChip(label: _t('الكل', 'Any'), selected: f.subjectId == null, onTap: () => setState(() => _f = f.withSubject(null))),
              for (final s in subjects)
                EduChoiceChip(label: s.name, selected: s.id == f.subjectId, onTap: () => setState(() => _f = f.withSubject(s.id))),
            ]),
          ],
          const SizedBox(height: AppSpace.md),
          _group(_t('طريقة الدراسة', 'How'), [
            for (final d in const [null, ...CourseFilters.deliveries])
              EduChoiceChip(
                key: ValueKey('course_filters.sheet.delivery.${d ?? 'any'}'),
                label: _deliveryName(d),
                selected: f.delivery == d,
                onTap: () => setState(() => _f = f.withDelivery(d)),
              ),
          ]),
          if (_edu != null) ...[
            const SizedBox(height: AppSpace.md),
            EduAreaPicker(
              label: _t('المنطقة', 'Area'),
              loadAreas: _edu!.loadAreas,
              labels: cat!.geoLabels,
              level1: f.areaId == null
                  ? null
                  : EduArea(id: f.areaId!, key: '', nameAr: f.areaAr.isEmpty ? _areaLabel(f) : f.areaAr, nameEn: f.areaEn.isEmpty ? _areaLabel(f) : f.areaEn),
              onChanged: (l1, l2) {
                final a = l2 ?? l1;
                setState(() => _f = f.withArea(a.id, ar: a.nameAr, en: a.nameEn));
              },
            ),
            if (f.areaId != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() => _f = f.withArea(null)),
                  child: Text(_t('أي منطقة', 'Any area')),
                ),
              ),
          ],
        ],
        const SizedBox(height: AppSpace.lg),
        Row(children: [
          Expanded(
            child: AppButton(
              key: const ValueKey('course_filters.sheet.clear'),
              label: _t('مسح', 'Clear'),
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: f.isEmpty ? null : () => setState(() => _f = f.cleared()),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: AppButton(
              key: const ValueKey('course_filters.sheet.apply'),
              label: _t('عرض الدورات', 'Show courses'),
              expand: true,
              onPressed: () => Navigator.of(context).pop(_f),
            ),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The student home's host
// ═════════════════════════════════════════════════════════════════════════════

typedef CourseFilterBarBuilder = Widget Function({int? resultCount});

/// Loads the user's remembered filters (else the study profile's level) and the STORED catalog — no request on load
/// (the home's request budget, test/perf/home_requests_*); the catalog comes from the network only when the person
/// opens the filter sheet. [builder] gets the filters and the bar to place.
class CourseFilterScope extends StatefulWidget {
  const CourseFilterScope({super.key, required this.builder});

  final Widget Function(BuildContext context, CourseFilters filters, CourseFilterBarBuilder bar) builder;

  @override
  State<CourseFilterScope> createState() => _CourseFilterScopeState();
}

class _CourseFilterScopeState extends State<CourseFilterScope> {
  CourseFilters _f = CourseFilters.empty;
  CourseFilterEdu? _edu;
  String? _user;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final u = await CourseFilterStore.user();
    final f = await CourseFilterStore.initial(u.id);
    final edu = await CourseFilterEdu.load(f.country, storedOnly: true);
    if (!mounted) return;
    setState(() {
      _user = u.id;
      _f = f;
      _edu = edu;
    });
  }

  Future<CourseFilterEdu?> _loadEdu() async {
    final edu = await CourseFilterEdu.load(_f.country);
    if (mounted && edu != null) setState(() => _edu = edu);
    return edu;
  }

  void _set(CourseFilters f) {
    setState(() => _f = f);
    if (_user != null) CourseFilterStore.save(_user!, f);
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        _f,
        ({int? resultCount}) => CourseFilterBar(value: _f, edu: _edu, loadEdu: _loadEdu, resultCount: resultCount, onChanged: _set),
      );
}
