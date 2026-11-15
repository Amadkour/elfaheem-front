// lib/features/org/org_institutions.dart
//
// Institutions S1 (plan docs/institutions/PLAN.md items 1 – 4, contract docs/institutions/CONTRACT_S1.md, back
// D-960 – D-964). Two Settings pages behind the kill switch `org.institution`, plus the pure helpers other org
// screens share:
//   StudySystemInfo · studySystemBody      GET|PUT …/study-system
//   DeptCatalog · CatalogTemplate · CatalogSelection   GET …/dept-catalog, POST …/dept-catalog/apply
//   orgAudienceOf · orgAudienceBody · orgAudienceLabel  the department's audience (students · staff · departments)
//   orgRoleTitle · orgPortfolioLabel        dean, the three vice deans (portfolio), council secretary
//   orgCourseDeptOptions                    the course form's department picker: academic departments first
//   OrgStudySystemPage → StudySystemView     two big choice cards + the graduate-programs switch
//   OrgDeptCatalogPage → DeptCatalogView     Academic / Service, tick cards, request types, "Create selected"
// The views take plain values (test/org/institutions_s1_test.dart pumps them through expectNoLayoutErrors).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppCard, AppField, AppStatusBadge, AppSwitchTile, AppTone, showAppNotice;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asInt, asMap, asMapList, asStr, t;
import 'org_departments_page.dart' show showDepartmentWizard;
import 'org_page_kit.dart';
import 'org_providers.dart';
import 'org_ui.dart' show OrgAsync, OrgEmpty, OrgGrid, deptIcon, hexColor;
import 'org_v3.dart' show orgCall, orgErrorText;

/// The kill switch that hides both Settings entries (back `feature_catalog.py`).
const orgInstitutionFeatureKey = 'org.institution';

// ═════════════════════════════════════════════════════════════════════════════
//  Study system
// ═════════════════════════════════════════════════════════════════════════════

enum StudySystem { traditional, creditHours }

StudySystem? studySystemOf(Object? v) => switch ('$v') {
      'traditional' => StudySystem.traditional,
      'credit_hours' => StudySystem.creditHours,
      _ => null,
    };

String? studySystemWire(StudySystem? s) => switch (s) {
      StudySystem.traditional => 'traditional',
      StudySystem.creditHours => 'credit_hours',
      null => null,
    };

String studySystemLabel(StudySystem s) =>
    s == StudySystem.traditional ? t('النظام التقليدي (العام الدراسي)', 'Traditional (academic year)') : t('نظام الساعات المعتمدة', 'Credit hours');

/// One plain sentence on what changes with each system.
String studySystemSentence(StudySystem s) => s == StudySystem.traditional
    ? t('سنة دراسية كاملة، تقديرات (ممتاز، جيد جداً…) ودور ثانٍ للامتحانات.',
        'A full academic year, grade labels (Excellent, Very good…) and second-round exams.')
    : t('معدل تراكمي، تسجيل وحذف وإضافة للمقررات بالساعات، وموافقة المرشد الأكاديمي.',
        'A GPA, course add / drop by hours, and the academic advisor\'s sign-off.');

class StudySystemInfo {
  const StudySystemInfo({
    this.stored,
    required this.effective,
    this.source = 'default',
    this.hasGraduatePrograms = false,
    this.creditPrograms = 0,
    this.traditionalPrograms = 0,
    this.ownSystem = 0,
    this.programsChanged,
  });

  /// The stored setting; null = derived from the programs.
  final StudySystem? stored;
  final StudySystem effective;

  /// `org` (stored) · `programs` (derived) · `default` (no programs).
  final String source;
  final bool hasGraduatePrograms;
  final int creditPrograms, traditionalPrograms, ownSystem;

  /// Only on a PUT answer: how many programs were rewritten.
  final int? programsChanged;

  factory StudySystemInfo.fromJson(Map<String, dynamic> j) {
    final p = asMap(j['programs']);
    return StudySystemInfo(
      stored: studySystemOf(j['study_system']),
      effective: studySystemOf(j['effective']) ?? StudySystem.creditHours,
      source: asStr(j['source'], 'default'),
      hasGraduatePrograms: j['has_graduate_programs'] == true,
      creditPrograms: asInt(p['credit_hours']),
      traditionalPrograms: asInt(p['traditional']),
      ownSystem: asInt(p['own_system']),
      programsChanged: j['programs_changed'] == null ? null : asInt(j['programs_changed']),
    );
  }

  /// The plain line under the cards: where the current value comes from.
  String get sourceText => switch (source) {
        'org' => t('محفوظ لمؤسستك.', 'Saved for your institution.'),
        'programs' => t('غير محدد بعد — مأخوذ من أغلب برامجك الحالية.', 'Not set yet — taken from most of your current programs.'),
        _ => t('غير محدد بعد — الساعات المعتمدة هي الافتراضي.', 'Not set yet — credit hours is the default.'),
      };
}

/// The PUT body: `study_system` is always sent (null = derive it), the graduate flag only when known.
Map<String, dynamic> studySystemBody(StudySystem? s, {bool? graduate}) =>
    {'study_system': studySystemWire(s), 'has_graduate_programs': ?graduate};

// ═════════════════════════════════════════════════════════════════════════════
//  Department catalog
// ═════════════════════════════════════════════════════════════════════════════

class CatalogRequestType {
  const CatalogRequestType({required this.key, required this.nameAr, required this.nameEn, this.kind = 'request', this.applied = false});
  final String key, nameAr, nameEn, kind;
  final bool applied;

  factory CatalogRequestType.fromJson(Map<String, dynamic> j) => CatalogRequestType(
      key: asStr(j['key']),
      nameAr: asStr(j['name_ar']),
      nameEn: asStr(j['name_en']),
      kind: asStr(j['kind'], 'request'),
      applied: j['applied'] == true);

  String get name => t(nameAr.isEmpty ? nameEn : nameAr, nameEn.isEmpty ? nameAr : nameEn);
}

class CatalogTemplate {
  const CatalogTemplate({
    required this.key,
    this.group = 'service',
    this.kind = 'service',
    this.preset,
    required this.nameAr,
    required this.nameEn,
    this.descAr = '',
    this.descEn = '',
    this.icon,
    this.color,
    this.audience,
    this.minSet = false,
    this.condition,
    this.recommended = false,
    this.needsName = false,
    this.deptId,
    this.requestTypes = const [],
  });

  final String key, group, kind, nameAr, nameEn, descAr, descEn;
  final String? preset, icon, color, condition;
  final List<String>? audience;
  final bool minSet, recommended, needsName;
  final int? deptId;
  final List<CatalogRequestType> requestTypes;

  factory CatalogTemplate.fromJson(Map<String, dynamic> j) => CatalogTemplate(
        key: asStr(j['key']),
        group: asStr(j['group'], 'service'),
        kind: asStr(j['kind'], 'service'),
        preset: j['preset']?.toString(),
        nameAr: asStr(j['name_ar']),
        nameEn: asStr(j['name_en']),
        descAr: asStr(j['description_ar']),
        descEn: asStr(j['description_en']),
        icon: j['icon']?.toString(),
        color: j['color']?.toString(),
        audience: j['audience'] is List ? [for (final a in j['audience'] as List) '$a'] : null,
        minSet: j['min_set'] == true,
        condition: j['condition']?.toString(),
        recommended: j['recommended'] == true,
        needsName: j['needs_name'] == true,
        deptId: j['dept_id'] == null ? null : asInt(j['dept_id']),
        requestTypes: [for (final r in asMapList(j['request_types'])) CatalogRequestType.fromJson(r)],
      );

  bool get isAcademic => group == 'academic';
  String get name => t(nameAr.isEmpty ? nameEn : nameAr, nameEn.isEmpty ? nameAr : nameEn);
  String get description => t(descAr.isEmpty ? descEn : descAr, descEn.isEmpty ? descAr : descEn);

  /// Request types not on the department yet (every one while it has not been created).
  List<CatalogRequestType> get missingTypes => [for (final r in requestTypes) if (deptId == null || !r.applied) r];

  /// Created already, with every request type in place: shown as done, nothing to tick.
  bool get done => deptId != null && missingTypes.isEmpty;

  /// The academic template is never "done": each tick makes another department.
  bool get tickable => needsName || !done;

  /// The plain reason it is in the minimum set.
  String? get conditionText => switch (condition) {
        'credit_hours' => t('لنظام الساعات المعتمدة', 'For credit hours'),
        'graduate_programs' => t('عند وجود دراسات عليا', 'When you run graduate programs'),
        _ => null,
      };
}

class DeptCatalog {
  const DeptCatalog({this.studySystem, this.hasGraduatePrograms = false, this.academicDepartments = 0, this.canApply = false, this.items = const []});
  final StudySystem? studySystem;
  final bool hasGraduatePrograms, canApply;
  final int academicDepartments;
  final List<CatalogTemplate> items;

  factory DeptCatalog.fromJson(Map<String, dynamic> j) => DeptCatalog(
        studySystem: studySystemOf(j['study_system']),
        hasGraduatePrograms: j['has_graduate_programs'] == true,
        academicDepartments: asInt(j['academic_departments']),
        canApply: j['can_apply'] == true,
        items: [for (final x in asMapList(j['items'])) CatalogTemplate.fromJson(x)],
      );

  List<CatalogTemplate> get academic => [for (final x in items) if (x.isAcademic) x];
  List<CatalogTemplate> get service => [for (final x in items) if (!x.isAcademic) x];
  CatalogTemplate? byKey(String key) {
    for (final x in items) {
      if (x.key == key) return x;
    }
    return null;
  }

  /// Nothing made from the catalog yet (the guiding empty state).
  bool get untouched => academicDepartments == 0 && items.every((x) => x.deptId == null);
}

/// What the admin has ticked: template key → the ticked request-type keys. The academic template carries its names.
class CatalogSelection {
  CatalogSelection([Map<String, Set<String>>? picked]) : picked = picked ?? {};

  final Map<String, Set<String>> picked;
  String academicNameAr = '', academicNameEn = '';

  /// The minimum set the server recommends for this organization, pre-ticked when it is not created yet.
  factory CatalogSelection.initial(DeptCatalog c) => CatalogSelection({
        for (final x in c.items)
          if (x.recommended && !x.needsName && x.tickable) x.key: {for (final r in x.missingTypes) r.key},
      });

  bool isPicked(String key) => picked.containsKey(key);
  int get count => picked.length;
  bool get isEmpty => picked.isEmpty;

  /// Ticking a template ticks every request type it still lacks.
  void toggle(CatalogTemplate x) {
    if (!x.tickable) return;
    if (picked.remove(x.key) == null) picked[x.key] = {for (final r in x.missingTypes) r.key};
  }

  void toggleType(CatalogTemplate x, String typeKey) {
    final s = picked[x.key];
    if (s == null) return;
    if (!s.remove(typeKey)) s.add(typeKey);
  }

  bool typePicked(String templateKey, String typeKey) => picked[templateKey]?.contains(typeKey) ?? false;

  /// A local check before the call (the server's `template_name_required` in the user's words).
  String? problem() {
    if (picked.containsKey(_academicKey) && academicNameAr.trim().isEmpty && academicNameEn.trim().isEmpty) {
      return t('اكتب اسم القسم العلمي', 'Name the academic department');
    }
    return null;
  }

  /// `{templates: [...]}`: `request_types` is null (every default) when all the missing ones are ticked.
  Map<String, dynamic> toApplyBody(DeptCatalog c) => {
        'templates': [
          for (final e in picked.entries)
            if (c.byKey(e.key) case final x?)
              {
                'key': x.key,
                if (!_allTicked(x, e.value)) 'request_types': [for (final r in x.requestTypes) if (e.value.contains(r.key)) r.key],
                if (x.needsName && academicNameAr.trim().isNotEmpty) 'name_ar': academicNameAr.trim(),
                if (x.needsName && academicNameEn.trim().isNotEmpty) 'name_en': academicNameEn.trim(),
              },
        ],
      };

  static bool _allTicked(CatalogTemplate x, Set<String> s) => x.missingTypes.every((r) => s.contains(r.key));
}

const _academicKey = 'academic_department';

// ═════════════════════════════════════════════════════════════════════════════
//  Audience · roles · the course form's departments
// ═════════════════════════════════════════════════════════════════════════════

const orgAudienceKeys = ['students', 'staff', 'departments'];

/// The stored audience as a set; null / empty / unknown = everyone.
Set<String> orgAudienceOf(Object? v) {
  final s = v is List ? {for (final a in v) if (orgAudienceKeys.contains('$a')) '$a'} : <String>{};
  return s.isEmpty ? {...orgAudienceKeys} : s;
}

/// The value to send: null when everyone is picked (the server's "everyone"), else the keys in the server's order.
List<String>? orgAudienceBody(Set<String> s) =>
    s.isEmpty || orgAudienceKeys.every(s.contains) ? null : [for (final k in orgAudienceKeys) if (s.contains(k)) k];

String orgAudienceLabel(String key) => switch (key) {
      'students' => t('الطلاب', 'Students'),
      'staff' => t('الموظفون', 'Staff'),
      _ => t('الإدارات الأخرى', 'Other departments'),
    };

/// The faculty roles (D-964): the app's own title for each, so they read the same wherever roles are listed.
String? orgFacultyRoleLabel(String? key) => switch (key) {
      'dean' => t('عميد', 'Dean'),
      'vice_dean_education_students' => t('وكيل الكلية لشئون التعليم والطلاب', 'Vice dean for education & students'),
      'vice_dean_postgraduate_research' => t('وكيل الكلية لشئون الدراسات العليا والبحوث', 'Vice dean for postgraduate studies & research'),
      'vice_dean_community_service' => t('وكيل الكلية لشئون خدمة المجتمع وتنمية البيئة', 'Vice dean for community service & environment'),
      'council_secretary' => t('أمين المجلس', 'Council secretary'),
      _ => null,
    };

/// A vice dean's portfolio as a short label (null for every other role).
String? orgPortfolioLabel(Object? portfolio) => switch ('$portfolio') {
      'education_students' => t('التعليم والطلاب', 'Education & students'),
      'postgraduate_research' => t('الدراسات العليا والبحوث', 'Postgraduate & research'),
      'community_service' => t('خدمة المجتمع والبيئة', 'Community service'),
      _ => null,
    };

/// A role's display name: a role row (`key`, `name_ar`, `name_en`) or an assignment (`role_key`, `role_name_*`).
String orgRoleTitle(Map<String, dynamic> r) {
  final key = r['key'] ?? r['role_key'];
  // a system role keeps the app's title; an own role (or a renamed copy) keeps the name the admin gave it
  final known = (r['is_system'] == false) ? null : orgFacultyRoleLabel(key?.toString());
  if (known != null) return known;
  final ar = asStr(r['name_ar'] ?? r['role_name_ar']), en = asStr(r['name_en'] ?? r['role_name_en']);
  return t(ar.isEmpty ? en : ar, en.isEmpty ? ar : en);
}

/// May a course sit in this department (the server's D-963 rule)? Councils, offices and catalog-made service
/// departments are refused; an older plain service department may be an academic one stored that way.
bool orgCourseDeptAllowed(Map<String, dynamic> d) {
  final kind = asStr(d['kind'], 'service');
  if (kind == 'council' || kind == 'office') return false;
  return !(kind == 'service' && asStr(d['template_key']).isNotEmpty);
}

/// The course form's department options, academic (scientific) departments first, then the others a course may
/// still sit in, each group by name. [keep] (the course's current department) stays listed even when refused, so an
/// edit that leaves it alone shows it.
List<Map<String, dynamic>> orgCourseDeptOptions(List<Map<String, dynamic>> depts, {int? keep}) {
  String name(Map<String, dynamic> d) => t(asStr(d['name_ar'] ?? d['name_en']), asStr(d['name_en'] ?? d['name_ar']));
  final shown = [
    for (final d in depts)
      if (d['is_active'] != false && (orgCourseDeptAllowed(d) || (keep != null && asInt(d['id']) == keep))) d,
  ];
  int rank(Map<String, dynamic> d) => d['kind'] == 'scientific' ? 0 : 1;
  shown.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : name(a).compareTo(name(b));
  });
  return shown;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Study system page
// ═════════════════════════════════════════════════════════════════════════════

class OrgStudySystemPage extends StatefulWidget {
  const OrgStudySystemPage({super.key});

  @override
  State<OrgStudySystemPage> createState() => _OrgStudySystemPageState();
}

class _OrgStudySystemPageState extends State<OrgStudySystemPage> {
  StudySystemInfo? _info;
  StudySystem? _pick;
  bool _graduate = false, _failed = false, _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _take(StudySystemInfo i) {
    _info = i;
    _pick = i.stored ?? i.effective;
    _graduate = i.hasGraduatePrograms;
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    setState(() => _failed = false);
    final r = await orgCall(() => s.api.get('${s.base}/study-system'), quiet: true);
    if (!mounted) return;
    setState(() => r.ok ? _take(StudySystemInfo.fromJson(r.map)) : _failed = true);
  }

  bool get _dirty {
    final i = _info;
    return i != null && (_pick != i.stored || _graduate != i.hasGraduatePrograms);
  }

  Future<void> _save() async {
    final s = context.read<OrgSession>();
    setState(() => _busy = true);
    final r = await orgCall(() => s.api.put('${s.base}/study-system', body: studySystemBody(_pick, graduate: _graduate)), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    final i = StudySystemInfo.fromJson(r.map);
    setState(() => _take(i));
    final n = i.programsChanged ?? 0;
    showAppNotice(n > 0 ? t('تم الحفظ — تحدّث $n من البرامج', 'Saved — $n programs updated') : t('تم الحفظ', 'Saved'));
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    if (i == null) return OrgAsync(loading: !_failed, failed: _failed, onRetry: _load, child: const SizedBox.shrink());
    return StudySystemView(
      info: i,
      selected: _pick,
      graduate: _graduate,
      busy: _busy,
      dirty: _dirty,
      onPick: (v) => setState(() => _pick = v),
      onGraduate: (v) => setState(() => _graduate = v),
      onSave: _save,
    );
  }
}

/// Two big choice cards (one plain sentence each), the graduate-programs switch, the programs line and Save.
class StudySystemView extends StatelessWidget {
  const StudySystemView({
    super.key,
    required this.info,
    required this.selected,
    required this.graduate,
    required this.onPick,
    required this.onGraduate,
    required this.onSave,
    this.busy = false,
    this.dirty = false,
  });

  final StudySystemInfo info;
  final StudySystem? selected;
  final bool graduate, busy, dirty;
  final ValueChanged<StudySystem> onPick;
  final ValueChanged<bool> onGraduate;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final programs = info.creditPrograms + info.traditionalPrograms;
    return OrgPageBody(
      primary: dirty ? OrgPrimaryAction(id: 'save_study_system', icon: Icons.check_rounded, label: t('حفظ', 'Save'), onTap: busy ? () {} : onSave) : null,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.xxl + AppTouch.primary),
        children: [
          OrgSectionHeading(t('نظام الدراسة', 'Study system'),
              subtitle: t('يحدد المصطلحات والقواعد في التسجيل والدرجات. يمكن لأي برنامج أن يختار نظاماً مختلفاً.',
                  'It sets the terms and rules of registration and grades. Any program may still choose another one.')),
          OrgGrid(minTile: 300, children: [
            for (final s in StudySystem.values)
              _SystemCard(system: s, selected: selected == s, onTap: () => onPick(s)),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
            child: Text(
              [
                info.sourceText,
                if (programs > 0)
                  t('برامجك: ${info.creditPrograms} بالساعات و${info.traditionalPrograms} تقليدي'
                      '${info.ownSystem > 0 ? ' (${info.ownSystem} اختار نظامه بنفسه ولن يتغير)' : ''}.',
                      'Your programs: ${info.creditPrograms} credit hours, ${info.traditionalPrograms} traditional'
                      '${info.ownSystem > 0 ? ' (${info.ownSystem} set their own and stay as they are)' : ''}.'),
              ].join(' '),
              style: AppType.meta(context).copyWith(color: c.textMedium),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, 0),
            child: AppCard(
              child: AppSwitchTile(
                icon: Icons.school_rounded,
                title: t('لدينا برامج دراسات عليا', 'We run graduate programs'),
                subtitle: t('يضيف إدارة الدراسات العليا إلى الحد الأدنى من الإدارات.', 'Adds Postgraduate Studies to the minimum set of departments.'),
                value: graduate,
                onChanged: onGraduate,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({required this.system, required this.selected, required this.onTap});
  final StudySystem system;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = system == StudySystem.traditional ? Icons.calendar_month_rounded : Icons.timer_outlined;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.primaryWash : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? AppBorder.focus : AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: AppTouch.min,
                height: AppTouch.min,
                decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.control)),
                child: Icon(icon, color: c.primary, size: AppIconSize.lg),
              ),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(studySystemLabel(system), style: AppType.section(context)),
                  const SizedBox(height: AppSpace.xxs),
                  Text(studySystemSentence(system), style: AppType.body(context).copyWith(color: c.textMedium)),
                ]),
              ),
              AppSpace.gapXs,
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? c.primary : c.textLight, size: AppIconSize.lg),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Department catalog page
// ═════════════════════════════════════════════════════════════════════════════

class OrgDeptCatalogPage extends StatefulWidget {
  const OrgDeptCatalogPage({super.key});

  @override
  State<OrgDeptCatalogPage> createState() => _OrgDeptCatalogPageState();
}

class _OrgDeptCatalogPageState extends State<OrgDeptCatalogPage> {
  DeptCatalog? _catalog;
  CatalogSelection _sel = CatalogSelection();
  bool _failed = false, _missing = false, _busy = false;
  bool _academic = false;
  final _nameAr = TextEditingController(), _nameEn = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    super.dispose();
  }

  void _take(DeptCatalog c) {
    _catalog = c;
    _sel = CatalogSelection.initial(c);
    _nameAr.clear();
    _nameEn.clear();
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    setState(() => _failed = false);
    final r = await orgCall(() => s.api.get('${s.base}/dept-catalog'), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _take(DeptCatalog.fromJson(r.map));
      } else {
        _failed = true;
        _missing = r.endpointMissing;
      }
    });
  }

  Future<void> _apply() async {
    final c = _catalog;
    if (c == null || _sel.isEmpty) return;
    _sel
      ..academicNameAr = _nameAr.text
      ..academicNameEn = _nameEn.text;
    final why = _sel.problem();
    if (why != null) {
      showAppNotice(why, error: true);
      return;
    }
    final s = context.read<OrgSession>();
    setState(() => _busy = true);
    final r = await orgCall(() => s.api.post('${s.base}/dept-catalog/apply', body: _sel.toApplyBody(c)), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    final made = asMapList(r.map['created']).length, types = asInt(r.map['request_types_created']);
    setState(() => _take(DeptCatalog.fromJson(asMap(r.map['catalog']))));
    showAppNotice(made > 0
        ? t('أُنشئت $made من الإدارات و$types من أنواع الطلبات', '$made departments and $types request types created')
        : t('أُضيفت $types من أنواع الطلبات', '$types request types added'));
  }

  Future<void> _custom() async {
    if (await showDepartmentWizard(context)) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = _catalog;
    if (c == null) {
      if (_failed && _missing) {
        return OrgEmpty(
            icon: Icons.cloud_off_rounded,
            title: t('يحتاج تحديثاً للخادم', 'Needs a server update'),
            message: t('دليل الإدارات غير متاح على هذا الخادم بعد.', 'The department catalog is not on this server yet.'));
      }
      return OrgAsync(loading: !_failed, failed: _failed, onRetry: _load, child: const SizedBox.shrink());
    }
    return DeptCatalogView(
      catalog: c,
      selection: _sel,
      academic: _academic,
      busy: _busy,
      nameAr: _nameAr,
      nameEn: _nameEn,
      onGroup: (v) => setState(() => _academic = v),
      onToggle: (x) => setState(() => _sel.toggle(x)),
      onToggleType: (x, k) => setState(() => _sel.toggleType(x, k)),
      onCreate: _apply,
      onCustom: _custom,
    );
  }
}

/// The catalog: Academic / Service, tick cards, each ticked card's request types, ONE "Create selected".
class DeptCatalogView extends StatelessWidget {
  const DeptCatalogView({
    super.key,
    required this.catalog,
    required this.selection,
    required this.academic,
    required this.nameAr,
    required this.nameEn,
    required this.onGroup,
    required this.onToggle,
    required this.onToggleType,
    required this.onCreate,
    required this.onCustom,
    this.busy = false,
  });

  final DeptCatalog catalog;
  final CatalogSelection selection;
  final bool academic, busy;
  final TextEditingController nameAr, nameEn;
  final ValueChanged<bool> onGroup;
  final ValueChanged<CatalogTemplate> onToggle;
  final void Function(CatalogTemplate x, String typeKey) onToggleType;
  final VoidCallback onCreate, onCustom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = academic ? catalog.academic : catalog.service;
    final n = selection.count;
    final canApply = catalog.canApply;
    return OrgPageBody(
      top: OrgSegmented<bool>(
        value: academic,
        options: [(false, t('خدمية', 'Service')), (true, t('علمية', 'Academic'))],
        onChanged: onGroup,
      ),
      primary: canApply && n > 0
          ? OrgPrimaryAction(
              id: 'create_selected',
              icon: Icons.add_task_rounded,
              label: t('إنشاء المحدد ($n)', 'Create selected ($n)'),
              onTap: busy ? () {} : onCreate)
          : null,
      more: [
        if (canApply) OrgMenuItem(icon: Icons.add_business_rounded, label: t('إضافة إدارة مخصصة', 'Add custom department'), onTap: onCustom),
      ],
      child: list.isEmpty
          ? OrgEmpty(
              icon: Icons.apartment_rounded,
              title: t('لا قوالب هنا بعد', 'No templates here yet'),
              message: t('أضف إدارة مخصصة بالاسم والخدمات التي تريدها.', 'Add a custom department with the name and services you want.'),
              actionLabel: canApply ? t('إضافة إدارة مخصصة', 'Add custom department') : null,
              onAction: onCustom)
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpace.xxl + AppTouch.primary),
              children: [
                if (catalog.untouched && !academic)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
                    child: AppCard(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.tips_and_updates_rounded, color: c.primary, size: AppIconSize.lg),
                        AppSpace.gapSm,
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t('ابدأ بالحد الأدنى', 'Start with the minimum set'), style: AppType.section(context)),
                            const SizedBox(height: AppSpace.xxs),
                            Text(
                                t('حددنا لك الإدارات التي تحتاجها كل كلية. راجع أنواع الطلبات تحت كل إدارة ثم اضغط «إنشاء المحدد».',
                                    'We ticked the departments every faculty needs. Check the request types under each, then press "Create selected".'),
                                style: AppType.body(context).copyWith(color: c.textMedium)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                OrgSectionHeading(
                  academic ? t('الأقسام العلمية', 'Academic departments') : t('الإدارات الخدمية', 'Service departments'),
                  subtitle: academic
                      ? t('لكل قسم علمي مجلس قسم ومقرراته. لديك ${catalog.academicDepartments} قسم.',
                          'Each academic department has its own council and courses. You have ${catalog.academicDepartments}.')
                      : t('اختر ما تحتاجه — يمكنك الإضافة لاحقاً.', 'Pick what you need — you can add more later.'),
                ),
                OrgGrid(minTile: 360, children: [
                  for (final x in list)
                    CatalogTemplateCard(
                      template: x,
                      picked: selection.isPicked(x.key),
                      enabled: canApply,
                      typePicked: (k) => selection.typePicked(x.key, k),
                      onToggle: () => onToggle(x),
                      onToggleType: (k) => onToggleType(x, k),
                      names: x.needsName ? (nameAr, nameEn) : null,
                    ),
                ]),
              ],
            ),
    );
  }
}

/// One template: a tick, its mark, name, one line, the "minimum set" / "created" badges; ticked, its request types.
class CatalogTemplateCard extends StatelessWidget {
  const CatalogTemplateCard({
    super.key,
    required this.template,
    required this.picked,
    required this.typePicked,
    required this.onToggle,
    required this.onToggleType,
    this.enabled = true,
    this.names,
  });

  final CatalogTemplate template;
  final bool picked, enabled;
  final bool Function(String key) typePicked;
  final VoidCallback onToggle;
  final ValueChanged<String> onToggleType;
  final (TextEditingController, TextEditingController)? names;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = template;
    final tint = hexColor(x.color, c.primary);
    final canTick = enabled && x.tickable;
    final created = x.deptId != null;
    final head = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: AppTouch.min,
        height: AppTouch.min,
        decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.control)),
        child: Icon(deptIcon(x.icon), color: tint, size: AppIconSize.md),
      ),
      AppSpace.gapSm,
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(x.name, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (x.description.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(x.description, style: AppType.meta(context), maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          if (x.minSet || created) ...[
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              if (x.minSet) AppStatusBadge(label: t('الحد الأدنى', 'Minimum set'), tone: AppTone.brand, dense: true),
              if (x.minSet && x.conditionText != null) AppStatusBadge(label: x.conditionText!, dense: true),
              if (created)
                AppStatusBadge(
                    icon: Icons.check_rounded,
                    label: x.done ? t('مُنشأة', 'Created') : t('مُنشأة — ينقصها أنواع طلبات', 'Created — request types missing'),
                    tone: AppTone.success,
                    dense: true),
            ]),
          ],
        ]),
      ),
      AppSpace.gapXs,
      Icon(
        x.done ? Icons.check_circle_rounded : (picked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
        color: x.done ? c.success : (picked ? c.primary : c.textLight),
        size: AppIconSize.lg,
      ),
    ]);
    final shownTypes = x.missingTypes;
    return Semantics(
      checked: x.done || picked,
      child: Material(
        color: picked ? c.primaryWash : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: picked ? c.primary : c.divider, width: picked ? AppBorder.strong : AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: canTick ? onToggle : null,
            child: Padding(padding: const EdgeInsets.all(AppSpace.md), child: head),
          ),
          if (picked) ...[
            Divider(height: 1, color: c.divider),
            if (names case (final ar, final en))
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
                child: Column(children: [
                  AppField(controller: ar, label: t('اسم القسم بالعربية', 'Arabic name')),
                  AppSpace.gapXs,
                  AppField(controller: en, label: t('اسم القسم بالإنجليزية', 'English name')),
                ]),
              ),
            if (shownTypes.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxs),
                child: Text(t('أنواع الطلبات المقترحة', 'Suggested request types'), style: AppType.label(context).copyWith(color: c.textMedium)),
              ),
              for (final r in shownTypes)
                InkWell(
                  onTap: () => onToggleType(r.key),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppTouch.min),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                      child: Row(children: [
                        Icon(typePicked(r.key) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            color: typePicked(r.key) ? c.primary : c.textLight, size: AppIconSize.md),
                        AppSpace.gapSm,
                        Expanded(child: Text(r.name, style: AppType.row(context))),
                        if (r.kind == 'complaint') AppStatusBadge(label: t('شكوى', 'Complaint'), dense: true),
                      ]),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: AppSpace.xs),
          ],
        ]),
      ),
    );
  }
}
