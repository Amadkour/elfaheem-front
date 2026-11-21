// lib/features/org/students/student_rules_pages.dart — "Study rules" in plain language (student lifecycle contract
// §8, PLAN §1 rows 4.2b – 4.2e and §3.8 groups 2 – 3, RESEARCH "Configurable options implied"): the study system
// (credit hours or years, summer term, preparatory year, second round), how a course is passed, the grade scale,
// moving up a year, academic warnings, dismissal and the longest study time, the final chance, repeats and
// improvement, the honours list — every option with its usual Egyptian value next to it. "Start from a bylaw preset"
// fills everything at once (with a "review it with your bylaw" note and the sources), and each programme can keep its
// own progression rules.
//
// Routes (back features/org/students/api/rules_router.py, registrar router):
//   GET | PUT …/registrar/rules                    the institution's whole rule set ({rules} on PUT, one Save)
//   GET …/students/rules/presets                   [{key, label_*, system, institution, review_with_bylaw, note_*,
//                                                    sources, rules (full), overrides (what the preset sets)}]
//   GET …/students/rules/scales                    [{key, label_*, points_max, pass_letter, grade_scale}]
//   GET | PUT …/students/rules/programs/{pid}      {program_id, system_type, overrides, rules, blocks} · PUT {overrides}
//   GET …/study-system · GET …/academic/settings   the system card (credit hours / years) and the number of years
//
//   openStudentRules(context, orgId, {canEdit})          THE opener
//   showStudentSettingsChooser(context, orgId, {canEdit}) the Students page's "Settings": study rules · statuses and
//                                                         reminders · who decides what
//   StudyRulesView / RulePresetsView / ProgrammeListView / StudentSettingsChooserView   plain values (the layout test)
library;

import 'dart:convert' show jsonEncode;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t, asBool, asDouble, asInt, asMap, asMapList, asStr;
import '../org_institutions.dart' show OrgStudySystemPage, StudySystem, StudySystemInfo;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_providers.dart' show OrgSession, orgBase;
import '../org_v3.dart' show OrgCall, orgCall, orgErrorText;
import 'student_file_page.dart' show pushStudentPage;
import 'student_matrix_page.dart' show openStudentMatrix;
import 'student_scale_editor.dart';
import 'student_settings_page.dart' show kStudentSettingsHelpId, openStudentSettings;

String studentRulesTitle() => t('قواعد الدراسة', 'Study rules');

/// The blocks a programme may override (server `policy.PROGRAM_BLOCKS`).
const programmeRuleBlocks = ['traditional', 'standing', 'dismissal', 'final_chance', 'study'];

/// The blocks a bylaw preset may set (a preset never touches the calendar, the load bands or staff caps).
const presetRuleKeys = [
  'scale_preset', 'grade_scale', 'pass_letter', 'pass', 'traditional', 'standing', 'dismissal', 'final_chance', 'retake',
  'suspension', 'postponement', 'reenrolment', 'withdrawal', 'excuses', 'study', 'graduation',
];

// ═════════════════════════════════════════════════════════════════════════════
//  Models and pure helpers
// ═════════════════════════════════════════════════════════════════════════════

/// One bylaw preset (`data/lifecycle_presets/*.json`).
class RulePreset {
  const RulePreset({
    required this.key,
    this.labelAr = '',
    this.labelEn = '',
    this.system = 'credit_hour',
    this.institution = 'public',
    this.reviewWithBylaw = false,
    this.noteAr = '',
    this.noteEn = '',
    this.sources = const [],
    this.rules = const {},
    this.overrides = const {},
  });

  final String key, labelAr, labelEn, system, institution, noteAr, noteEn;
  final bool reviewWithBylaw;
  final List<String> sources;

  /// The full rule set (defaults + the preset, validated); [overrides] is only what the preset sets.
  final Map<String, dynamic> rules, overrides;

  factory RulePreset.fromJson(dynamic j) {
    final m = asMap(j);
    return RulePreset(
      key: asStr(m['key']),
      labelAr: asStr(m['label_ar']),
      labelEn: asStr(m['label_en']),
      system: asStr(m['system'], 'credit_hour'),
      institution: asStr(m['institution'], 'public'),
      reviewWithBylaw: asBool(m['review_with_bylaw']),
      noteAr: asStr(m['note_ar']),
      noteEn: asStr(m['note_en']),
      sources: [for (final s in (m['sources'] is List ? m['sources'] as List : const [])) '$s'],
      rules: asMap(m['rules']),
      overrides: asMap(m['overrides']),
    );
  }

  String get label => t(labelAr.isEmpty ? labelEn : labelAr, labelEn.isEmpty ? labelAr : labelEn);
  String get note => t(noteAr.isEmpty ? noteEn : noteAr, noteEn.isEmpty ? noteAr : noteEn);
}

/// A programme of the picker.
class ProgrammeRef {
  const ProgrammeRef({required this.id, this.nameAr = '', this.nameEn = '', this.code = ''});
  final int id;
  final String nameAr, nameEn, code;

  factory ProgrammeRef.fromJson(dynamic j) {
    final m = asMap(j);
    return ProgrammeRef(id: asInt(m['id']), nameAr: asStr(m['name_ar']), nameEn: asStr(m['name_en']), code: asStr(m['code']));
  }

  String get name {
    final n = t(nameAr.isEmpty ? nameEn : nameAr, nameEn.isEmpty ? nameAr : nameEn);
    return n.isEmpty ? code : n;
  }
}

/// [rules] with [patch] merged into [block] (a copy).
Map<String, dynamic> rulesSet(Map<String, dynamic> rules, String block, Map<String, dynamic> patch) =>
    {...rules, block: {...asMap(rules[block]), ...patch}};

/// [rules] filled from preset [p], two levels deep (only what the preset sets; the rest of the institution's rules
/// stays). A preset naming a scale brings the scale, its pass letter and (unless it sets one) its pass mark.
Map<String, dynamic> rulesWithPreset(Map<String, dynamic> rules, RulePreset p) {
  final src = p.overrides.isNotEmpty ? p.overrides : {for (final k in presetRuleKeys) if (p.rules.containsKey(k)) k: p.rules[k]};
  final out = Map<String, dynamic>.from(rules);
  src.forEach((k, v) {
    if (!presetRuleKeys.contains(k)) return;
    out[k] = v is Map && out[k] is Map ? {...asMap(out[k]), ...asMap(v)} : v;
  });
  if (src.containsKey('scale_preset') && !src.containsKey('grade_scale') && p.rules['grade_scale'] is List) {
    out['grade_scale'] = p.rules['grade_scale'];
    out['pass_letter'] = p.rules['pass_letter'];
    if (!asMap(src['pass']).containsKey('course_min_pct')) {
      out['pass'] = {...asMap(out['pass']), 'course_min_pct': asMap(p.rules['pass'])['course_min_pct']};
    }
  }
  return out;
}

/// [rules] with the scale of [e]; a ready scale also brings its pass mark (the passing letter's lowest percent).
Map<String, dynamic> rulesWithScale(Map<String, dynamic> rules, ScaleEdit e) {
  final out = {...rules, 'grade_scale': e.rows, 'pass_letter': e.passLetter, 'scale_preset': e.presetKey};
  final pm = e.passMin;
  if (e.presetKey != 'custom' && pm != null) return rulesSet(out, 'pass', {'course_min_pct': pm});
  return out;
}

/// The programme's own values: every key of [programmeRuleBlocks] whose value differs from the institution's.
Map<String, dynamic> programmeOverrides(Map<String, dynamic> institution, Map<String, dynamic> programme) {
  final out = <String, dynamic>{};
  for (final b in programmeRuleBlocks) {
    final mine = asMap(programme[b]), theirs = asMap(institution[b]);
    final diff = <String, dynamic>{
      for (final k in mine.keys)
        if (jsonEncode(mine[k]) != jsonEncode(theirs[k])) k: mine[k],
    };
    if (diff.isNotEmpty) out[b] = diff;
  }
  return out;
}

int overrideCount(Map<String, dynamic> overrides) => overrides.values.fold(0, (n, v) => n + asMap(v).length);

/// 'credit_hour' · 'traditional' · 'mixed' (both kinds of programme).
String studyRulesSystem(StudySystemInfo? i) {
  if (i == null || (i.creditPrograms > 0 && i.traditionalPrograms > 0)) return 'mixed';
  return i.effective == StudySystem.traditional ? 'traditional' : 'credit_hour';
}

String systemLabel(String s) => switch (s) {
      'traditional' => t('نظام الفرق (السنوات الدراسية)', 'Years (the traditional system)'),
      'mixed' => t('ساعات معتمدة وفرق معاً', 'Credit hours and years together'),
      _ => t('الساعات المعتمدة', 'Credit hours'),
    };

/// The short names of the research sources the presets cite (RESEARCH §0).
String ruleSourceLabel(String code) => switch (code) {
      'S1' => t('قانون تنظيم الجامعات 49 لسنة 1972', 'Universities Law 49/1972'),
      'S2' => t('اللائحة التنفيذية، المادة 74 (2015)', 'Executive Regulations, art. 74 (2015)'),
      'S3' => t('اللائحة التنفيذية، المادة 80 (2015)', 'Executive Regulations, art. 80 (2015)'),
      'S5' => t('جامعة دمياط: وقف القيد والأعذار', 'Damietta University: suspension and excuses'),
      'S6' => t('جامعة أسيوط: القيد والتحويل', 'Assiut University: enrolment and transfer'),
      'S7' => t('جامعة أسيوط: نظام الامتحانات', 'Assiut University: examinations'),
      'S9' => t('حقوق القاهرة: دليل الطالب', 'Cairo University Law: student guide'),
      'S10' => t('هندسة عين شمس: لائحة الساعات المعتمدة', 'Ain Shams Engineering: credit-hour bylaw'),
      'S11' => t('هندسة سوهاج: دليل الطالب', 'Sohag Engineering: student guide'),
      'S12' => t('آداب بني سويف: اللائحة الداخلية', 'Beni-Suef Arts: internal bylaw'),
      'S21' => t('قانون الأزهر 103 لسنة 1961', 'Al-Azhar Law 103/1961'),
      'S22' => t('قانون الجامعات الخاصة والأهلية 12 لسنة 2009', 'Private and Ahlia Universities Law 12/2009'),
      'S23' => t('قواعد جامعة خاصة منشورة', 'A private university\'s published rules'),
      _ => code,
    };

String _usual(String ar, String en) => t('المعتاد: $ar', 'Usual: $en');

String _num(num v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

String studentRulesErrorText(OrgCall r) {
  if (r.code == 'bad_registrar_rules') {
    final f = asStr(r.detail['field']);
    if (f.startsWith('grade_scale') || f == 'pass_letter') {
      return t('سلم التقديرات غير مكتمل: راجعه ثم احفظ.', 'The grade scale is not complete: check it, then save.');
    }
    return t('قيمة غير مقبولة ($f): راجعها ثم احفظ.', 'A value is not accepted ($f): check it, then save.');
  }
  return orgErrorText(r.error!);
}

// ═════════════════════════════════════════════════════════════════════════════
//  API
// ═════════════════════════════════════════════════════════════════════════════

class StudyRulesApi {
  StudyRulesApi(this.orgId, [ApiClient? api]) : _api = api ?? ApiClient();
  final int orgId;
  final ApiClient _api;

  String get _org => '$orgBase/orgs/$orgId';

  Future<OrgCall> rules() => orgCall(() => _api.get('$_org/registrar/rules'), quiet: true);
  Future<OrgCall> saveRules(Map<String, dynamic> rules) => orgCall(() => _api.put('$_org/registrar/rules', body: {'rules': rules}), quiet: true);
  Future<OrgCall> presets() => orgCall(() => _api.get('$_org/students/rules/presets'), quiet: true);
  Future<OrgCall> scales() => orgCall(() => _api.get('$_org/students/rules/scales'), quiet: true);
  Future<OrgCall> studySystem() => orgCall(() => _api.get('$_org/study-system'), quiet: true);
  Future<OrgCall> academic() => orgCall(() => _api.get('$_org/academic/settings'), quiet: true);
  Future<OrgCall> programmes() => orgCall(() => _api.get('$_org/academic/programs'), quiet: true);
  Future<OrgCall> programme(int pid) => orgCall(() => _api.get('$_org/students/rules/programs/$pid'), quiet: true);
  Future<OrgCall> saveProgramme(int pid, Map<String, dynamic> overrides) =>
      orgCall(() => _api.put('$_org/students/rules/programs/$pid', body: {'overrides': overrides}), quiet: true);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Openers
// ═════════════════════════════════════════════════════════════════════════════

/// Opens the study rules of organization [orgId]. [canEdit] false shows them read only.
Future<void> openStudentRules(BuildContext context, int orgId, {bool canEdit = true, StudyRulesApi? api}) => pushStudentPage<void>(
      context,
      OrgPushedPage(
        title: studentRulesTitle(),
        subtitle: t('النجاح والانتقال والتقديرات', 'Passing, moving up, grades'),
        helpPageId: kStudentSettingsHelpId,
        width: AppWidth.form,
        child: OrgStudentRulesPage(orgId: orgId, canEdit: canEdit, api: api),
      ),
    );

/// The Students page's "Settings": three plain doors.
Future<void> showStudentSettingsChooser(BuildContext context, int orgId, {bool canEdit = true}) async {
  final pick = await showAppSheet<String>(
    context,
    (ctx) => AppSheetContent(
      title: t('إعدادات الطلاب', 'Student settings'),
      icon: Icons.tune_rounded,
      children: [StudentSettingsChooserView(onPick: (k) => Navigator.of(ctx).pop(k))],
    ),
  );
  if (pick == null || !context.mounted) return;
  switch (pick) {
    case 'rules':
      await openStudentRules(context, orgId, canEdit: canEdit);
    case 'statuses':
      await openStudentSettings(context, orgId, canEdit: canEdit);
    case 'matrix':
      await openStudentMatrix(context, orgId, canEdit: canEdit);
  }
}

class StudentSettingsChooserView extends StatelessWidget {
  const StudentSettingsChooserView({super.key, required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppActionCard(
          key: const ValueKey('student-settings-door-rules'),
          icon: Icons.menu_book_rounded,
          title: studentRulesTitle(),
          subtitle: t('نظام الدراسة، النجاح، سلم التقديرات، الإنذار والفصل، الإعادة والتحسين',
              'Study system, passing, the grade scale, warnings and dismissal, repeats and improvement'),
          onTap: () => onPick('rules'),
        ),
        AppSpace.gapXs,
        AppActionCard(
          key: const ValueKey('student-settings-door-statuses'),
          icon: Icons.notifications_active_outlined,
          title: t('الحالات والتذكيرات', 'Statuses and reminders'),
          subtitle: t('ما يحدث عند توقف الطالب، التذكيرات، ما يراه الطالب', 'When a student stops, reminders, what the student sees'),
          onTap: () => onPick('statuses'),
        ),
        AppSpace.gapXs,
        AppActionCard(
          key: const ValueKey('student-settings-door-matrix'),
          icon: Icons.gavel_rounded,
          title: t('من يقرر ماذا', 'Who decides what'),
          subtitle: t('من يقترح ومن يعتمد كل تغيير في حالة الطالب', 'Who proposes and who approves each change to a student\'s status'),
          onTap: () => onPick('matrix'),
        ),
      ]);
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class OrgStudentRulesPage extends StatefulWidget {
  const OrgStudentRulesPage({super.key, required this.orgId, this.canEdit = true, this.api});
  final int orgId;
  final bool canEdit;
  final StudyRulesApi? api;

  @override
  State<OrgStudentRulesPage> createState() => _OrgStudentRulesPageState();
}

class _OrgStudentRulesPageState extends State<OrgStudentRulesPage> {
  late final StudyRulesApi _api = widget.api ?? StudyRulesApi(widget.orgId);
  Map<String, dynamic>? _saved, _draft;
  bool _inherited = false, _busy = false;
  List<RulePreset> _presets = const [];
  List<ScalePreset> _scales = const [];
  StudySystemInfo? _system;
  int? _years;
  String? _error;
  int _gen = 0;

  bool get _dirty => _saved != null && _draft != null && jsonEncode(_saved) != jsonEncode(_draft);

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _hasSession {
    try {
      context.read<OrgSession>();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final r = await Future.wait([_api.rules(), _api.presets(), _api.scales(), _api.studySystem(), _api.academic()]);
    if (!mounted) return;
    setState(() {
      if (!r[0].ok) {
        _error = orgErrorText(r[0].error!);
        return;
      }
      _takeRules(r[0].map);
      if (r[1].ok && r[1].data is List) {
        _presets = [for (final p in r[1].data as List) RulePreset.fromJson(p)];
      }
      if (r[2].ok && r[2].data is List) {
        _scales = [for (final s in r[2].data as List) ScalePreset.fromJson(s)];
      }
      if (r[3].ok) _system = StudySystemInfo.fromJson(r[3].map);
      if (r[4].ok) {
        final n = asMapList(r[4].map['levels']).length;
        _years = n == 0 ? null : n;
      }
    });
  }

  void _takeRules(Map<String, dynamic> m) {
    _saved = Map<String, dynamic>.from(asMap(m['rules']));
    _draft = _saved;
    _inherited = m['inherited_from'] != null;
    _gen++;
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    setState(() => _busy = true);
    final r = await _api.saveRules(d);
    if (!mounted) return;
    if (r.ok) {
      final again = await _api.rules();
      if (!mounted) return;
      setState(() {
        if (again.ok) {
          _takeRules(again.map);
        } else {
          _saved = Map<String, dynamic>.from(d);      // the PUT went through: what was sent is what is saved
        }
      });
    }
    setState(() => _busy = false);
    showAppNotice(r.ok ? t('حُفظت قواعد الدراسة', 'Study rules saved') : studentRulesErrorText(r), error: !r.ok);
  }

  Future<void> _pickPreset() async {
    final d = _draft;
    if (d == null || _presets.isEmpty) return;
    final p = await showAppSheet<RulePreset>(
      context,
      (ctx) => AppSheetContent(
        title: t('ابدأ من لائحة جاهزة', 'Start from a bylaw preset'),
        icon: Icons.auto_stories_rounded,
        children: [RulePresetsView(presets: _presets, system: studyRulesSystem(_system), onPick: (p) => Navigator.of(ctx).pop(p))],
      ),
    );
    if (p == null || !mounted) return;
    final ok = await appConfirm(context,
        message: t('املأ القواعد من «${p.label}»؟ تتغير القيم التي تحددها هذه اللائحة فقط، ولا يُحفظ شيء قبل أن تضغط «حفظ».',
            'Fill the rules from "${p.label}"? Only the values this preset sets change, and nothing is saved until you press Save.'),
        confirmLabel: t('املأ', 'Fill'));
    if (!ok || !mounted) return;
    setState(() {
      _draft = rulesWithPreset(_draft!, p);
      _gen++;
    });
    showAppNotice(t('راجع القيم مع لائحتك ثم اضغط «حفظ».', 'Check the values with your bylaw, then press Save.'));
  }

  Future<void> _editScale() async {
    final d = _draft;
    if (d == null) return;
    final e = await openScaleEditor(context, initial: ScaleEdit.ofRules(d), scales: _scales, canEdit: widget.canEdit);
    if (e == null || !mounted) return;
    setState(() {
      _draft = rulesWithScale(_draft!, e);
      _gen++;
    });
  }

  Future<void> _openSystem() async {
    await pushStudentPage<void>(
      context,
      OrgPushedPage(title: t('نظام الدراسة', 'Study system'), helpPageId: kStudentSettingsHelpId, width: AppWidth.form, child: const OrgStudySystemPage()),
    );
    if (!mounted) return;
    final r = await _api.studySystem();
    if (mounted && r.ok) setState(() => _system = StudySystemInfo.fromJson(r.map));
  }

  Future<void> _openProgrammes() async {
    final saved = _saved;
    if (saved == null) return;
    final r = await _api.programmes();
    if (!mounted) return;
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    final items = [for (final p in asMapList(r.map['items'])) ProgrammeRef.fromJson(p)];
    final pick = await showAppSheet<ProgrammeRef>(
      context,
      (ctx) => AppSheetContent(
        title: t('قواعد خاصة بقسم', 'A programme\'s own rules'),
        icon: Icons.account_tree_outlined,
        children: [ProgrammeListView(items: items, onPick: (p) => Navigator.of(ctx).pop(p))],
      ),
    );
    if (pick == null || !mounted) return;
    await pushStudentPage<void>(
      context,
      OrgPushedPage(
        title: pick.name,
        subtitle: t('قواعد هذا القسم', 'This programme\'s rules'),
        helpPageId: kStudentSettingsHelpId,
        width: AppWidth.form,
        child: _ProgrammeRulesPage(api: _api, programme: pick, institution: saved, canEdit: widget.canEdit),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    if (d == null) {
      if (_error == null) return const AppListSkeleton(items: 6);
      return AppErrorState(message: _error, onRetry: _load);
    }
    final problem = scaleProblem(ScaleEdit.ofRules(d));
    return AppUnsavedGuard(
      dirty: _dirty,
      child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        StudyRulesView(
          key: ValueKey('study-rules-$_gen'),
          rules: d,
          system: studyRulesSystem(_system),
          yearsCount: _years,
          scales: _scales,
          inherited: _inherited,
          onChanged: widget.canEdit ? (r) => setState(() => _draft = r) : null,
          onPresets: widget.canEdit && _presets.isNotEmpty ? _pickPreset : null,
          onEditScale: _editScale,
          onStudySystem: widget.canEdit && _hasSession ? _openSystem : null,
          onProgrammes: _openProgrammes,
        ),
        if (widget.canEdit) ...[
          if (problem != null) ...[AppSpace.gapMd, AppBanner(icon: Icons.error_outline_rounded, text: problem, color: context.colors.danger)],
          AppSpace.gapLg,
          AppButtonRow(
            primary: AppButton.primary(
              key: const ValueKey('study-rules-save'),
              label: t('حفظ', 'Save'),
              icon: Icons.check_rounded,
              busy: _busy,
              onPressed: _dirty && !_busy && problem == null ? _save : null,
            ),
            secondary: [
              if (_dirty)
                AppButton.ghost(
                  label: t('تجاهل التغييرات', 'Discard changes'),
                  icon: Icons.undo_rounded,
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _draft = _saved;
                            _gen++;
                          }),
                ),
            ],
          ),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  A programme's own rules
// ═════════════════════════════════════════════════════════════════════════════

class _ProgrammeRulesPage extends StatefulWidget {
  const _ProgrammeRulesPage({required this.api, required this.programme, required this.institution, required this.canEdit});
  final StudyRulesApi api;
  final ProgrammeRef programme;
  final Map<String, dynamic> institution;
  final bool canEdit;

  @override
  State<_ProgrammeRulesPage> createState() => _ProgrammeRulesPageState();
}

class _ProgrammeRulesPageState extends State<_ProgrammeRulesPage> {
  Map<String, dynamic>? _saved, _draft;
  String _system = 'credit_hour';
  String? _error;
  bool _busy = false;
  int _gen = 0;

  bool get _dirty => _saved != null && _draft != null && jsonEncode(_saved) != jsonEncode(_draft);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _take(Map<String, dynamic> m) {
    _saved = Map<String, dynamic>.from(asMap(m['rules']));
    _draft = _saved;
    _system = asStr(m['system_type'], 'credit_hour') == 'traditional' ? 'traditional' : 'credit_hour';
    _gen++;
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final r = await widget.api.programme(widget.programme.id);
    if (!mounted) return;
    setState(() => r.ok ? _take(r.map) : _error = orgErrorText(r.error!));
  }

  Future<void> _put(Map<String, dynamic> overrides) async {
    setState(() => _busy = true);
    final r = await widget.api.saveProgramme(widget.programme.id, overrides);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _take(r.map);
    });
    showAppNotice(r.ok ? t('حُفظت قواعد القسم', 'Programme rules saved') : studentRulesErrorText(r), error: !r.ok);
  }

  Future<void> _reset() async {
    final ok = await appConfirm(context,
        message: t('إرجاع هذا القسم إلى قواعد المؤسسة؟', 'Put this programme back on the institution\'s rules?'), confirmLabel: t('إرجاع', 'Put back'));
    if (ok && mounted) await _put(const {});
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    if (d == null) {
      if (_error == null) return const AppListSkeleton(items: 5);
      return AppErrorState(message: _error, onRetry: _load);
    }
    final own = programmeOverrides(widget.institution, d);
    return AppUnsavedGuard(
      dirty: _dirty,
      child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        StudyRulesView(
          key: ValueKey('programme-rules-$_gen'),
          rules: d,
          system: _system,
          programme: true,
          institution: widget.institution,
          onChanged: widget.canEdit ? (r) => setState(() => _draft = r) : null,
        ),
        if (widget.canEdit) ...[
          AppSpace.gapLg,
          AppButtonRow(
            primary: AppButton.primary(
              key: const ValueKey('programme-rules-save'),
              label: t('حفظ', 'Save'),
              icon: Icons.check_rounded,
              busy: _busy,
              onPressed: _dirty && !_busy ? () => _put(own) : null,
            ),
            secondary: [
              AppButton.ghost(
                label: t('استخدم قواعد المؤسسة', 'Use the institution\'s rules'),
                icon: Icons.restart_alt_rounded,
                onPressed: _busy || (own.isEmpty && !_dirty) ? null : _reset,
              ),
            ],
          ),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Plain views
// ═════════════════════════════════════════════════════════════════════════════

/// The bylaw presets, each with its note, its sources and (when the server says so) "review it with your bylaw".
class RulePresetsView extends StatelessWidget {
  const RulePresetsView({super.key, required this.presets, this.system = 'mixed', required this.onPick});
  final List<RulePreset> presets;
  final String system;
  final ValueChanged<RulePreset> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(
        icon: Icons.fact_check_outlined,
        color: c.warning,
        text: t('اللائحة الجاهزة نقطة بداية فقط: راجع كل قيمة مع لائحة كليتك الداخلية قبل أن تحفظ.',
            'A preset is only a starting point: check every value against your faculty\'s own bylaw before you save.'),
      ),
      for (final p in presets) ...[
        AppSpace.gapSm,
        AppCard(
          key: ValueKey('rule-preset-${p.key}'),
          onTap: () => onPick(p),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(p.label, style: AppType.bodyStrong(context)),
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppStatusBadge(label: systemLabel(p.system), tone: AppTone.info, dense: true),
              if (system != 'mixed' && p.system != system)
                AppStatusBadge(label: t('نظام غير نظامك الحالي', 'Not your current system'), tone: AppTone.neutral, dense: true),
              if (p.reviewWithBylaw)
                AppStatusBadge(
                    label: t('راجعها مع لائحتك', 'Review with your bylaw'), icon: Icons.warning_amber_rounded, tone: AppTone.warning, dense: true),
            ]),
            if (p.note.isNotEmpty) ...[
              AppSpace.gapXs,
              Text(p.note, style: AppType.body(context).copyWith(color: c.textMedium)),
            ],
            if (p.sources.isNotEmpty) ...[
              AppSpace.gapXs,
              Text('${t('المصادر', 'Sources')}: ${p.sources.map(ruleSourceLabel).join(t('، ', ', '))}',
                  style: AppType.meta(context).copyWith(color: c.textMedium)),
            ],
          ]),
        ),
      ],
    ]);
  }
}

/// The programmes to pick from (or an empty note).
class ProgrammeListView extends StatelessWidget {
  const ProgrammeListView({super.key, required this.items, required this.onPick});
  final List<ProgrammeRef> items;
  final ValueChanged<ProgrammeRef> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (items.isEmpty) {
      return Text(t('لا توجد أقسام بعد. أضف الأقسام من الإعدادات الأكاديمية أولاً.', 'No programmes yet. Add them from the academic settings first.'),
          style: AppType.body(context).copyWith(color: c.textMedium));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        t('القسم يتبع قواعد المؤسسة إلا فيما تغيّره له: الانتقال بين الفرق، الإنذار، الفصل، الفرصة الأخيرة، والفصل الصيفي.',
            'A programme follows the institution\'s rules except what you change for it: moving up, warnings, dismissal, the final chance and the summer term.'),
        style: AppType.body(context).copyWith(color: c.textMedium),
      ),
      for (final p in items) ...[
        AppSpace.gapXs,
        AppActionCard(
          key: ValueKey('rules-programme-${p.id}'),
          icon: Icons.account_tree_outlined,
          title: p.name,
          subtitle: p.code.isEmpty || p.code == p.name ? null : p.code,
          onTap: () => onPick(p),
        ),
      ],
    ]);
  }
}

/// Every rule group over plain values. [onChanged] null = read only. [programme] true shows only the blocks a
/// programme may change, each marked when it differs from [institution]. Re-key it when [rules] is replaced from
/// outside (the number fields keep what was typed).
class StudyRulesView extends StatelessWidget {
  const StudyRulesView({
    super.key,
    required this.rules,
    this.system = 'credit_hour',
    this.yearsCount,
    this.scales = const [],
    this.inherited = false,
    this.programme = false,
    this.institution,
    this.onChanged,
    this.onPresets,
    this.onEditScale,
    this.onStudySystem,
    this.onProgrammes,
  });

  final Map<String, dynamic> rules;

  /// 'credit_hour' · 'traditional' · 'mixed'.
  final String system;
  final int? yearsCount;
  final List<ScalePreset> scales;
  final bool inherited, programme;
  final Map<String, dynamic>? institution;
  final ValueChanged<Map<String, dynamic>>? onChanged;
  final VoidCallback? onPresets, onEditScale, onStudySystem, onProgrammes;

  bool get _edit => onChanged != null;
  bool get _credit => system != 'traditional';
  bool get _years => system != 'credit_hour';

  Map<String, dynamic> _b(String block) => asMap(rules[block]);
  dynamic _v(String block, String key) => _b(block)[key];

  void _set(String block, Map<String, dynamic> patch) => onChanged?.call(rulesSet(rules, block, patch));

  /// The "differs from the institution" badge of a programme's section.
  Widget? _differs(List<String> blocks) {
    final inst = institution;
    if (!programme || inst == null) return null;
    final own = programmeOverrides(inst, rules);
    if (!blocks.any(own.containsKey)) return null;
    return AppStatusBadge(label: t('خاص بالقسم', 'Own value'), tone: AppTone.brand, dense: true);
  }

  // ── field helpers ────────────────────────────────────────────────────────

  Widget _number(BuildContext context, String block, String key, String label,
      {required num max, num min = 0, int decimals = 0, String? helper}) {
    final raw = _v(block, key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: AppNumberField(
        key: ValueKey('rules-$block.$key'),
        label: label,
        helper: helper,
        initialValue: decimals == 0 ? asInt(raw) : asDouble(raw),
        min: min,
        max: max,
        decimals: decimals,
        step: decimals == 0 ? 1 : 0.1,
        enabled: _edit,
        onChanged: (v) {
          if (v == null || v < min || v > max) return;
          _set(block, {key: decimals == 0 ? v.toInt() : v.toDouble()});
        },
      ),
    );
  }

  /// A rule that is off (null, or 0 with [zeroIsOff]) or a number.
  Widget _optional(BuildContext context, String block, String key,
      {required IconData icon,
      required String title,
      required String subtitle,
      required String fieldLabel,
      required num onValue,
      required num max,
      num min = 0,
      int decimals = 0,
      bool zeroIsOff = false,
      String? helper}) {
    final raw = _v(block, key);
    final on = zeroIsOff ? asDouble(raw) > 0 : raw != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSwitchTile(
        key: ValueKey('rules-switch-$block.$key'),
        icon: icon,
        title: title,
        subtitle: subtitle,
        value: on,
        onChanged: _edit ? (v) => _set(block, {key: v ? onValue : (zeroIsOff ? 0 : null)}) : null,
      ),
      if (on) _number(context, block, key, fieldLabel, max: max, min: zeroIsOff ? 1 : min, decimals: decimals, helper: helper),
    ]);
  }

  /// A rule that is off (null) or two numbers ({below, terms} …).
  Widget _pair(BuildContext context, String key,
      {required IconData icon,
      required String title,
      required String subtitle,
      required Map<String, num> onValue,
      required Map<String, String> labels,
      required Map<String, num> maxes,
      Map<String, int> decimals = const {}}) {
    final raw = _v('dismissal', key);
    final m = asMap(raw);
    final on = raw != null;
    final keys = onValue.keys.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSwitchTile(
        key: ValueKey('rules-switch-dismissal.$key'),
        icon: icon,
        title: title,
        subtitle: subtitle,
        value: on,
        onChanged: _edit ? (v) => _set('dismissal', {key: v ? Map<String, dynamic>.from(onValue) : null}) : null,
      ),
      if (on)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: RuleFieldsRow(children: [
            for (var i = 0; i < keys.length; i++) ...[
              if (i > 0) AppSpace.gapXs,
              Expanded(
                child: AppNumberField(
                  key: ValueKey('rules-dismissal.$key.${keys[i]}'),
                  label: labels[keys[i]],
                  initialValue: (decimals[keys[i]] ?? 0) == 0 ? asInt(m[keys[i]]) : asDouble(m[keys[i]]),
                  min: 0,
                  max: maxes[keys[i]],
                  decimals: decimals[keys[i]] ?? 0,
                  step: (decimals[keys[i]] ?? 0) == 0 ? 1 : 0.1,
                  enabled: _edit,
                  onChanged: (v) {
                    final mx = maxes[keys[i]] ?? 20;
                    if (v == null || v < 0 || v > mx) return;
                    _set('dismissal', {key: {...m, keys[i]: (decimals[keys[i]] ?? 0) == 0 ? v.toInt() : v.toDouble()}});
                  },
                ),
              ),
            ],
          ]),
        ),
    ]);
  }

  Widget _switch(String block, String key, {required IconData icon, required String title, required String subtitle}) => AppSwitchTile(
        key: ValueKey('rules-switch-$block.$key'),
        icon: icon,
        title: title,
        subtitle: subtitle,
        value: asBool(_v(block, key)),
        onChanged: _edit ? (v) => _set(block, {key: v}) : null,
      );

  Widget _drop(String id, String label, String value, Map<String, String> options, ValueChanged<String> onPick, {String? helper}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: AppDropdown<String>(
          key: ValueKey('rules-$id-$value'),
          decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 3),
          value: options.containsKey(value) ? value : options.keys.first,
          enabled: _edit,
          items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
          onChanged: _edit ? (v) => v == null ? null : onPick(v) : null,
        ),
      );

  Map<String, String> _letterOptions(String none) {
    final out = <String, String>{'': none};
    for (final g in asMapList(rules['grade_scale'])) {
      final l = asStr(g['letter']);
      if (l.isEmpty) continue;
      final n = scaleRowName(g);
      out[l] = n.isEmpty || n == l ? l : '$l · $n';
    }
    return out;
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scale = ScaleEdit.ofRules(rules);
    final passMin = asMap(rules['pass'])['course_min_pct'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        programme
            ? t('غيّر هنا ما يختلف فيه هذا القسم فقط؛ الباقي يتبع قواعد المؤسسة. سلم التقديرات والنجاح في المقرر واحد للمؤسسة كلها.',
                'Change here only what this programme does differently; the rest follows the institution. The grade scale and the course pass mark are the same for the whole institution.')
            : t('هذه قواعد مؤسستك كما تنص عليها لائحتها. القيمة المعتادة مكتوبة تحت كل خيار، وكل نتيجة تنتج عنها توصية يراجعها المسؤول ما لم تجعلها «تلقائية» في «من يقرر ماذا».',
                'These are your institution\'s rules as its bylaw states them. The usual value is written under each option, and every result is a recommendation someone reviews unless "Who decides what" makes it automatic.'),
        style: AppType.body(context).copyWith(color: c.textMedium),
      ),
      if (!_edit) ...[
        AppSpace.gapSm,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppStatusBadge(label: t('للعرض فقط', 'View only'), icon: Icons.visibility_outlined, tone: AppTone.neutral),
        ),
      ],
      if (inherited && !programme) ...[
        AppSpace.gapSm,
        AppBanner(
          icon: Icons.account_balance_outlined,
          text: t('هذه القواعد مأخوذة من جامعتك. عند الحفظ تصبح لهذه الكلية نسختها الخاصة.',
              'These rules come from your university. Saving gives this faculty its own copy.'),
        ),
      ],
      if (!programme && onPresets != null) ...[
        AppSpace.gapMd,
        AppActionCard(
          key: const ValueKey('study-rules-presets'),
          icon: Icons.auto_stories_rounded,
          title: t('ابدأ من لائحة جاهزة', 'Start from a bylaw preset'),
          subtitle: t('قانون 49، هندسة، حقوق، نظام المستويات، الخاصة والأهلية والأزهر — ثم راجعها مع لائحتك',
              'Law 49, engineering, law, levels, private, ahlia and Azhar — then review it with your bylaw'),
          onTap: onPresets,
        ),
      ],

      // ── study system ──
      AppSection(
        title: t('نظام الدراسة', 'Study system'),
        trailing: _differs(const ['study']),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!programme) ...[
            AppActionCard(
              key: const ValueKey('study-rules-system'),
              icon: Icons.school_outlined,
              title: systemLabel(system),
              subtitle: [
                if (yearsCount != null) t('عدد السنوات: $yearsCount', 'Years of study: $yearsCount'),
                t('فصلان رئيسيان في السنة', 'Two main terms a year'),
                _usual('حسب البرنامج', 'per programme'),
              ].join(' · '),
              onTap: onStudySystem,
            ),
            AppSpace.gapXs,
          ],
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _switch('study', 'summer',
                  icon: Icons.wb_sunny_outlined,
                  title: t('فصل صيفي', 'Summer term'),
                  subtitle: t('فصل قصير اختياري بعد الفصلين الرئيسيين. ${_usual('موجود في الساعات المعتمدة', 'on for credit hours')}',
                      'A short optional term after the two main terms. ${_usual('موجود في الساعات المعتمدة', 'on for credit hours')}')),
              _switch('study', 'preparatory_year',
                  icon: Icons.foundation_rounded,
                  title: t('سنة إعدادية', 'Preparatory year'),
                  subtitle: t('سنة قبل الفرقة الأولى، تُعامل معاملة الفرقة الأولى في فرص الامتحان. ${_usual('لا', 'no')}',
                      'A year before the first year, treated as the first year for exam chances. ${_usual('لا', 'no')}')),
              AppSwitchTile(
                key: const ValueKey('rules-switch-study.makeup_term'),
                icon: Icons.replay_rounded,
                title: t('دور ثانٍ (امتحانات تكميلية)', 'Second round (make-up exams)'),
                subtitle: t('امتحان آخر للراسبين بعد النتيجة، يُضاف له فصل «تكميلي» في التقويم. ${_usual('لا', 'no')}',
                    'Another exam for those who failed, after the results; adds a "make-up" term to the calendar. ${_usual('لا', 'no')}'),
                value: asBool(_v('study', 'makeup_term')) || asBool(_v('traditional', 'second_round')),
                onChanged: _edit
                    ? (v) => onChanged!(rulesSet(rulesSet(rules, 'study', {'makeup_term': v}), 'traditional', {'second_round': v}))
                    : null,
              ),
            ]),
          ),
        ]),
      ),

      // ── passing and the grade scale ──
      if (!programme)
        AppSection(
          title: t('النجاح وسلم التقديرات', 'Passing and the grade scale'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppActionCard(
              key: const ValueKey('study-rules-scale'),
              icon: Icons.grading_rounded,
              title: scalePresetLabel(scale.presetKey, scales),
              subtitle: [
                for (final g in scale.rows.take(4)) '${asStr(g['letter'])} ${_num(asDouble(g['min']))}${t('٪', '%')}',
                if (scale.rows.length > 4) '…',
                '${t('أدنى نجاح', 'lowest pass')}: ${scale.passLetter}',
              ].join(' · '),
              onTap: onEditScale,
            ),
            AppSpace.gapXs,
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _optional(context, 'pass', 'course_min_pct',
                    icon: Icons.percent_rounded,
                    title: t('درجة النجاح في المقرر', 'Course pass mark'),
                    subtitle: t('أقل نسبة ينجح بها الطالب في المقرر. عند الإيقاف تُؤخذ من سلم التقديرات. ${_usual('50 ٪ (60 ٪ في كليات الهندسة)', '50 % (60 % in engineering)')}',
                        'The lowest percent that passes a course. Off = taken from the grade scale. ${_usual('50 ٪ (60 ٪ في كليات الهندسة)', '50 % (60 % in engineering)')}'),
                    fieldLabel: t('ينجح من (٪)', 'Passes from (%)'),
                    onValue: scale.passMin ?? 50,
                    max: 100,
                    decimals: 1),
                _optional(context, 'pass', 'final_min_pct',
                    icon: Icons.edit_note_rounded,
                    title: t('حد أدنى في الامتحان النهائي', 'A minimum in the final exam'),
                    subtitle: t('لا ينجح الطالب في المقرر إن قلّت درجته في التحريري النهائي عن هذه النسبة، مهما كان مجموعه. ${_usual('لا يوجد (40 ٪ في بعض الهندسة)', 'none (40 % in some engineering)')}',
                        'A student fails the course below this percent in the written final, whatever his total. ${_usual('لا يوجد (40 ٪ في بعض الهندسة)', 'none (40 % in some engineering)')}'),
                    fieldLabel: t('أقل نسبة في النهائي (٪)', 'Lowest final percent (%)'),
                    onValue: 40,
                    max: 100,
                    decimals: 1),
                if (passMin == null && scale.passMin != null)
                  Text(t('الآن: من ${_num(scale.passMin!)} ٪ حسب السلم', 'Now: from ${_num(scale.passMin!)} % by the scale'),
                      style: AppType.meta(context).copyWith(color: c.textMedium)),
                if (_credit)
                  _number(context, 'graduation', 'min_cgpa', t('أقل معدل تراكمي للتخرج', 'Lowest CGPA to graduate'),
                      max: 5, decimals: 2, helper: _usual('2.0', '2.0')),
              ]),
            ),
          ]),
        ),

      // ── traditional: moving up a year ──
      if (_years)
        AppSection(
          title: t('الانتقال بين الفرق', 'Moving up a year'),
          subtitle: t('نظام الفرق: ينتقل الطالب إلى الفرقة التالية أو يبقى للإعادة', 'Years: the student moves to the next year or repeats this one'),
          trailing: _differs(const ['traditional']),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _number(context, 'traditional', 'max_carry', t('أقصى عدد مقررات يُنقل بها (مواد التخلف)', 'Most failed courses he can carry and still move up'),
                  max: 20, helper: _usual('مقرران', '2 courses')),
              _optional(context, 'traditional', 'max_carry_specialised',
                  icon: Icons.science_outlined,
                  title: t('حد مستقل للمقررات التخصصية', 'A separate limit for specialised courses'),
                  subtitle: t('عدد أقل من المقررات التخصصية يُسمح بحملها. ${_usual('لا يوجد', 'none')}',
                      'Fewer specialised courses may be carried. ${_usual('لا يوجد', 'none')}'),
                  fieldLabel: t('أقصى عدد تخصصي', 'Most specialised courses'),
                  onValue: 1,
                  max: 20),
              if (!programme)
                _drop(
                  'promotion_basis',
                  t('شرط الانتقال', 'What moving up needs'),
                  asStr(_v('traditional', 'promotion_basis'), 'carry_limit'),
                  {
                    'carry_limit': t('ألا يزيد الرسوب عن الحد أعلاه', 'No more failed courses than the limit above'),
                    'min_percent': t('الحد أعلاه ومجموع سنوي لا يقل عن نسبة', 'The limit above and a year total of at least a percent'),
                    'min_gpa': t('الحد أعلاه ومعدل سنوي لا يقل عن رقم', 'The limit above and a year GPA of at least a number'),
                  },
                  (v) => _set('traditional', {'promotion_basis': v, if (v == 'carry_limit') 'promotion_min': null, if (v == 'min_percent') 'promotion_min': 50, if (v == 'min_gpa') 'promotion_min': 2.0}),
                  helper: _usual('حد مواد التخلف فقط', 'the carry limit only'),
                ),
              if (!programme && asStr(_v('traditional', 'promotion_basis')) == 'min_percent')
                _number(context, 'traditional', 'promotion_min', t('أقل مجموع سنوي (٪)', 'Lowest year total (%)'), max: 100, decimals: 1),
              if (!programme && asStr(_v('traditional', 'promotion_basis')) == 'min_gpa')
                _number(context, 'traditional', 'promotion_min', t('أقل معدل سنوي', 'Lowest year GPA'), max: 5, decimals: 2),
              _number(context, 'traditional', 'years_inside', t('سنوات البقاء في الفرقة الواحدة', 'Years allowed inside one year of study'),
                  min: 1, max: 10, helper: t('بعدها يمتحن «من الخارج». ${_usual('سنتان (المادة 80)', '2 (art. 80)')}', 'After that he sits the exams "from outside". ${_usual('سنتان (المادة 80)', '2 (art. 80)')}')),
              AppSpace.gapXs,
              Text(t('فرص الامتحان من الخارج', 'Exam chances from outside'), style: AppType.label(context)),
              Text(_usual('لا شيء للأولى، فرصة للمتوسطة، ثلاث للنهائية (المادة 80 بعد 2015)', 'none for the first, 1 for middle years, 3 for the final ones (art. 80, 2015)'),
                  style: AppType.meta(context).copyWith(color: c.textMedium)),
              _chances(context),
              _switch('traditional', 'five_year_rule',
                  icon: Icons.looks_5_outlined,
                  title: t('كليات الخمس سنوات', 'Five-year faculties'),
                  subtitle: t('تُعامل الفرقة قبل النهائية معاملة النهائية في الفرص. ${_usual('نعم', 'yes')}',
                      'The year before the final one gets the final years\' chances. ${_usual('نعم', 'yes')}')),
              if (!programme)
                _drop('repeat_cap', t('أعلى تقدير لمقرر يُعاد بعد الرسوب', 'Highest grade for a course passed after failing'),
                    asStr(_v('traditional', 'repeat_cap_letter')), _letterOptions(t('بلا حد', 'No cap')),
                    (v) => _set('traditional', {'repeat_cap_letter': v.isEmpty ? null : v}), helper: _usual('مقبول (D)', 'Pass (D)')),
            ]),
          ),
        ),

      // ── credit hours: warnings ──
      if (_credit)
        AppSection(
          title: t('الإنذار الأكاديمي', 'Academic warning'),
          subtitle: t('تنبيه رسمي للطالب حين ينخفض معدله', 'A formal notice when a student\'s GPA drops'),
          trailing: _differs(const ['standing']),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _drop(
                'warning_basis',
                t('يُحسب الإنذار من', 'The warning looks at'),
                asStr(_v('standing', 'warning_basis'), 'cgpa'),
                {
                  'cgpa': t('المعدل التراكمي (كل الفصول)', 'The cumulative GPA (every term)'),
                  'term_gpa': t('معدل الفصل الأخير فقط', 'The last term\'s GPA only'),
                },
                (v) => _set('standing', {'warning_basis': v}),
                helper: _usual('المعدل التراكمي', 'the cumulative GPA'),
              ),
              _number(context, 'standing', 'probation_below', t('إنذار عندما يقل المعدل عن', 'Warn when the GPA is below'),
                  max: 5, decimals: 2, helper: _usual('2.0', '2.0')),
              _switch('standing', 'skip_first_term',
                  icon: Icons.first_page_rounded,
                  title: t('لا إنذار في الفصل الأول', 'No warning in the first term'),
                  subtitle: t('يُعطى الطالب الجديد فصلاً ليتأقلم. ${_usual('لا', 'no')}', 'A new student gets one term to settle in. ${_usual('لا', 'no')}')),
              _switch('standing', 'reset_on_recover',
                  icon: Icons.restart_alt_rounded,
                  title: t('يُلغى العدّ عند التحسن', 'The count restarts on recovery'),
                  subtitle: t('عندما يرتفع المعدل فوق الحد تُمحى الإنذارات السابقة من العدّ. ${_usual('نعم', 'yes')}',
                      'When the GPA rises above the bar, earlier warnings stop counting. ${_usual('نعم', 'yes')}')),
              _number(context, 'standing', 'warning_load_max', t('أقصى ساعات يسجلها الطالب المنذر', 'Most credit hours a warned student may take'),
                  max: 40, helper: _usual('12 ساعة', '12 hours')),
            ]),
          ),
        ),

      // ── dismissal ──
      if (_credit)
        AppSection(
          title: t('الفصل من الكلية', 'Dismissal'),
          subtitle: t('كل قاعدة تعمل وحدها؛ الناتج توصية لمجلس الكلية', 'Each rule works on its own; the result is a recommendation to the faculty council'),
          trailing: _differs(const ['dismissal']),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _optional(context, 'dismissal', 'consecutive_warnings',
                  icon: Icons.repeat_rounded,
                  title: t('بعد إنذارات متتالية', 'After warnings in a row'),
                  subtitle: _usual('6 إنذارات (4 في بعض الكليات)', '6 warnings (4 in some faculties)'),
                  fieldLabel: t('عدد الإنذارات المتتالية', 'Warnings in a row'),
                  onValue: 6,
                  max: 20,
                  zeroIsOff: true),
              _pair(context, 'early_gpa',
                  icon: Icons.trending_down_rounded,
                  title: t('معدل منخفض جداً في البداية', 'A very low GPA at the start'),
                  subtitle: _usual('لا يُستخدم (أقل من 1.0 في أول 3 فصول)', 'off (below 1.0 in the first 3 terms)'),
                  onValue: {'below': 1.0, 'terms': 3},
                  labels: {'below': t('أقل من', 'Below'), 'terms': t('في أول (فصول)', 'In the first (terms)')},
                  maxes: {'below': 5, 'terms': 20},
                  decimals: {'below': 2}),
              _pair(context, 'cgpa_after',
                  icon: Icons.south_rounded,
                  title: t('معدل تراكمي منخفض بعد فصل معيّن', 'A low CGPA after a given term'),
                  subtitle: _usual('لا يُستخدم (أقل من 1.5 بعد الفصل الرابع)', 'off (below 1.5 after the 4th term)'),
                  onValue: {'below': 1.5, 'term': 4},
                  labels: {'below': t('أقل من', 'Below'), 'term': t('بعد الفصل رقم', 'After term no.')},
                  maxes: {'below': 5, 'term': 30},
                  decimals: {'below': 2}),
              _pair(context, 'unregistered_terms',
                  icon: Icons.event_busy_outlined,
                  title: t('الانقطاع بلا عذر', 'Not registering without an excuse'),
                  subtitle: _usual('لا يُستخدم (فصلان متتاليان أو 3 متفرقة)', 'off (2 terms in a row or 3 in all)'),
                  onValue: {'consecutive': 2, 'total': 3},
                  labels: {'consecutive': t('متتالية', 'In a row'), 'total': t('إجمالاً', 'In all')},
                  maxes: {'consecutive': 20, 'total': 20}),
              _optional(context, 'dismissal', 'max_years',
                  icon: Icons.hourglass_bottom_rounded,
                  title: t('أطول مدة للدراسة', 'Longest time to finish'),
                  subtitle: t('يُفصل من تجاوز هذه المدة دون أن يتخرج. ${_usual('8 سنوات (10 في بعض الهندسة)', '8 years (10 in some engineering)')}',
                      'A student past this time without graduating is dismissed. ${_usual('8 سنوات (10 في بعض الهندسة)', '8 years (10 in some engineering)')}'),
                  fieldLabel: t('عدد السنوات', 'Years'),
                  onValue: 8,
                  min: 1,
                  max: 20),
            ]),
          ),
        ),

      // ── final chance ──
      if (_credit)
        AppSection(
          title: t('الفرصة الأخيرة', 'The final chance'),
          subtitle: t('قبل الفصل بسبب المعدل، لمن أنجز أغلب ساعاته', 'Before a GPA dismissal, for a student who passed most of his hours'),
          trailing: _differs(const ['final_chance']),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _number(context, 'final_chance', 'terms', t('عدد الفصول الإضافية', 'Extra terms'),
                  max: 6, helper: t('صفر = لا فرصة أخيرة. ${_usual('فصلان', '2 terms')}', '0 = no final chance. ${_usual('فصلان', '2 terms')}')),
              _switch('final_chance', 'summer',
                  icon: Icons.wb_sunny_outlined,
                  title: t('ومعها فصل صيفي', 'Plus a summer term'),
                  subtitle: _usual('نعم', 'yes')),
              _number(context, 'final_chance', 'min_credits_pct', t('لمن أنجز على الأقل (٪ من الساعات)', 'For a student who passed at least (% of the hours)'),
                  max: 100, decimals: 1, helper: _usual('75 ٪', '75 %')),
            ]),
          ),
        ),

      // ── repeats and improvement ──
      if (_credit && !programme)
        AppSection(
          title: t('الإعادة والتحسين', 'Repeats and improvement'),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _optional(context, 'retake', 'improvement_max',
                  icon: Icons.trending_up_rounded,
                  title: t('حد لمرات التحسين', 'A limit on improvement repeats'),
                  subtitle: t('إعادة مقرر ناجح لرفع التقدير، طوال مدة الدراسة. عند الإيقاف: بلا حد. ${_usual('5 مرات', '5 times')}',
                      'Retaking a passed course to raise its grade, over the whole study. Off = no limit. ${_usual('5 مرات', '5 times')}'),
                  fieldLabel: t('أقصى عدد', 'At most'),
                  onValue: 5,
                  max: 50,
                  helper: t('صفر = التحسين غير مسموح', '0 = improvement is not allowed')),
              _drop(
                'improvement_count',
                t('أي تقدير يُحسب بعد التحسين', 'Which grade counts after improving'),
                asStr(_v('retake', 'improvement_count'), 'best'),
                {'best': t('الأعلى من المحاولتين', 'The better of the two'), 'latest': t('الأخير دائماً', 'Always the latest')},
                (v) => _set('retake', {'improvement_count': v}),
                helper: _usual('الأعلى', 'the better one'),
              ),
              _drop('failed_cap', t('أعلى تقدير لمقرر يُنجح فيه بعد رسوب', 'Highest grade for a course passed after failing it'),
                  asStr(_v('retake', 'failed_cap_letter')), _letterOptions(t('بلا حد', 'No cap')),
                  (v) => _set('retake', {'failed_cap_letter': v.isEmpty ? null : v}), helper: _usual('بلا حد (B+ في بعض الهندسة)', 'no cap (B+ in some engineering)')),
            ]),
          ),
        ),

      // ── honours ──
      if (_credit && !programme)
        AppSection(
          title: t('لوحة الشرف', 'Honours list'),
          subtitle: t('الطلاب المتفوقون في الفصل', 'The term\'s top students'),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _number(context, 'standing', 'honours_term_gpa', t('معدل الفصل لا يقل عن', 'Term GPA of at least'),
                  max: 5, decimals: 2, helper: _usual('3.5', '3.5')),
              _number(context, 'standing', 'honours_min_credits', t('مع ساعات مسجلة لا تقل عن', 'With at least this many credit hours'),
                  max: 40, helper: _usual('12 ساعة', '12 hours')),
            ]),
          ),
        ),

      // ── programmes ──
      if (!programme && onProgrammes != null)
        AppSection(
          title: t('قواعد خاصة بالأقسام', 'Programmes with their own rules'),
          child: AppActionCard(
            key: const ValueKey('study-rules-programmes'),
            icon: Icons.account_tree_outlined,
            title: t('اختر قسماً لتغيير قواعده', 'Pick a programme to change its rules'),
            subtitle: t('الانتقال، الإنذار، الفصل، الفرصة الأخيرة، الفصل الصيفي', 'Moving up, warnings, dismissal, the final chance, the summer term'),
            onTap: onProgrammes,
          ),
        ),
    ]);
  }

  Widget _chances(BuildContext context) {
    final oc = asMap(_v('traditional', 'outside_chances'));
    const keys = ['first', 'middle', 'final'];
    final labels = {'first': t('الأولى', 'First year'), 'middle': t('المتوسطة', 'Middle years'), 'final': t('النهائية', 'Final years')};
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: RuleFieldsRow(children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) AppSpace.gapXs,
          Expanded(
            child: AppNumberField(
              key: ValueKey('rules-traditional.outside_chances.${keys[i]}'),
              label: labels[keys[i]],
              initialValue: asInt(oc[keys[i]]),
              min: 0,
              max: 10,
              enabled: _edit,
              onChanged: (v) {
                if (v == null || v < 0 || v > 10) return;
                _set('traditional', {'outside_chances': {...oc, keys[i]: v.toInt()}});
              },
            ),
          ),
        ],
      ]),
    );
  }
}
