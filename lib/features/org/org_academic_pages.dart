// lib/features/org/org_academic_pages.dart
//
// The academic life of a university / faculty (API: org_academic_router.py)
//   OrgAcademicPage       staff: Calendar · Departments (majors) · Graduation & settings · Students · Archive requests
//   CourseArchiveScreen   a course's archive: years → terms → run (students & results) · open / finish / archive a run
//   MyAcademicPathPage    student: General → Department → Graduated, progress, checklist, "Choose your department"
//   openOrgCourseGated    student taps an org course: open · archived (request the last version) · pending · granted
library;

import 'package:flutter_education_app/design/app_mesh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_join_pages.dart' show OrgUnitJoinHub;
import 'org_levels_pages.dart' show MyLevelCard, OrgLevelsTab, showEnrollBlock;
import 'org_program_form.dart' show orgAllCourses, showProgramForm;
import 'org_v3.dart';
import 'org_page_kit.dart' show OrgPartPicker;
import 'org_page_header.dart' show OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'org_suggestions.dart' show OrgTermSuggestions;
import '../shared/course_profile/course_profile_screen.dart' show openCourseProfile;
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh;
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart' show EntityGuardedChip;

const _pub = '$orgBase/public';
Map<String, String> termKinds() => {'term1': t('الفصل الأول', 'Term 1'), 'term2': t('الفصل الثاني', 'Term 2'), 'summer': t('الصيفي', 'Summer')};
Map<String, String> stageLabels() => {'general': t('طالب عام', 'General'), 'program': t('في قسم', 'In a department'), 'graduated': t('خريج', 'Graduated')};
String _cname(Map c) => '${(c['code'] ?? '').toString().isEmpty ? '' : '${c['code']} · '}${t('${c['name_ar'] ?? c['name_en']}', '${c['name_en'] ?? c['name_ar']}')}';

// ═════════════════════════════════════════════════════════════════════════════
//  Staff
// ═════════════════════════════════════════════════════════════════════════════

class OrgAcademicPage extends StatefulWidget {
  const OrgAcademicPage({super.key});

  @override
  State<OrgAcademicPage> createState() => _OrgAcademicPageState();
}

class _OrgAcademicPageState extends State<OrgAcademicPage> {
  Map<String, dynamic>? _settings;
  List<Map<String, dynamic>> _courses = const [], _terms = const [], _programs = const [], _staff = const [];

  String get _a => '${context.read<OrgSession>().base}/academic';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    final all = orgAllCourses(s);
    final r = await Future.wait([
      OrgApi.i.getMap('$_a/settings'), OrgApi.i.getMap('$_a/terms'), OrgApi.i.getMap('$_a/programs'),
      OrgApi.i.getMap('${s.base}/members', {'role': 'teacher,admin_assistant', 'size': 100}),
    ]);
    final courses = await all;
    if (!mounted) return;
    setState(() {
      _settings = r[0] ?? {};
      _terms = asMapList(r[1]?['items']);
      _programs = asMapList(r[2]?['items']);
      _courses = courses;
      _staff = asMapList(r[3]?['items']);
    });
  }

  int _part = 0;
  final Set<int> _seen = {};

  /// The page anatomy (D-103, org_page_kit.dart): the parts as ONE part picker (chips that fit, else one
  /// "part ▾" button), each part kept alive once opened. The parts themselves are unchanged.
  @override
  Widget build(BuildContext context) {
    if (_settings == null) return const AppListSkeleton();
    final hasDepts = _settings!['has_departments'] == true;
    final tabs = <(String, IconData, Widget)>[
      (t('التقويم', 'Calendar'), Icons.calendar_month_rounded, _Calendar(terms: _terms, base: _a, onChanged: _load)),
      (t('المستويات', 'Levels'), Icons.stairs_rounded, const OrgLevelsTab()),
      if (hasDepts) (t('الأقسام العلمية', 'Departments'), Icons.account_tree_rounded,
          _Programs(programs: _programs, courses: _courses, staff: _staff, base: _a, onChanged: _load)),
      (t('التخرج والإعدادات', 'Graduation & settings'), Icons.school_rounded,
          _SettingsTab(settings: _settings!, courses: _courses, base: _a, onChanged: _load)),
      (t('مسار الطلاب', 'Students'), Icons.route_rounded, _Students(programs: _programs, base: _a)),
      (t('طلبات الأرشيف', 'Archive requests'), Icons.inventory_2_rounded,
          _ArchiveRequests(base: _a, orgId: context.read<OrgSession>().currentId)),
    ];
    final i = _part.clamp(0, tabs.length - 1);
    _seen.add(i);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xs),
        child: OrgPartPicker(
          parts: [for (final x in tabs) (x.$1, x.$2)],
          index: i,
          onChanged: (k) => setState(() => _part = k),
        ),
      ),
      Expanded(
        child: IndexedStack(index: i, children: [
          for (var k = 0; k < tabs.length; k++) _seen.contains(k) ? tabs[k].$3 : const SizedBox.shrink(),
        ]),
      ),
    ]);
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({required this.terms, required this.base, required this.onChanged});
  final List<Map<String, dynamic>> terms;
  final String base;
  final VoidCallback onChanged;

  /// The term form. [draft] = an auto-create suggestion: the form returns the edited values instead of saving.
  Future<Map<String, dynamic>?> _edit(BuildContext context, [Map<String, dynamic>? term, bool draft = false]) async {
    final now = DateTime.now();
    final y = now.month >= 8 ? now.year : now.year - 1;
    final year = TextEditingController(text: '${term?['year_label'] ?? '$y/${y + 1}'}');
    String kind = '${term?['kind'] ?? 'term1'}';
    DateTime? start = DateTime.tryParse('${term?['start_date'] ?? ''}'), end = DateTime.tryParse('${term?['end_date'] ?? ''}');
    Map<String, dynamic>? out;
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          Future<void> pick(bool isStart) async {
            final d = await showDatePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime(2100),
                initialDate: (isStart ? start : end) ?? DateTime.now());
            if (d != null) set(() => isStart ? start = d : end = d);
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(draft ? t('تعديل المسودة', 'Edit the draft') : term == null ? t('فصل دراسي جديد', 'New term') : t('تعديل الفصل', 'Edit term')),
              Field(controller: year, label: t('العام الدراسي (2026/2027)', 'Academic year (2026/2027)'), ltr: true),
              ChoiceRow<String>(label: t('الفصل', 'Term'), options: termKinds(), value: kind, onChanged: (v) => set(() => kind = v)),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => pick(true), icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(start == null ? t('البداية', 'Starts') : shortDate(start!.toIso8601String())))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: () => pick(false), icon: const Icon(Icons.flag_rounded),
                    label: Text(end == null ? t('النهاية', 'Ends') : shortDate(end!.toIso8601String())))),
              ]),
              const SizedBox(height: 14),
              PrimaryButton(isLoading: false, label: draft ? t('اعتماد بعد التعديل', 'Approve with changes') : t('حفظ', 'Save'), onPressed: () async {
                if (start == null || end == null) return toast(t('حدد البداية والنهاية', 'Pick both dates'), error: true);
                final b = <String, dynamic>{'year_label': year.text.trim(), 'kind': kind, 'start_date': start!.toIso8601String().substring(0, 10),
                  'end_date': end!.toIso8601String().substring(0, 10)};
                if (draft) {
                  out = b;
                  if (ctx.mounted) Navigator.pop(ctx);
                  return;
                }
                final r = term == null ? await OrgApi.i.post('$base/terms', b, t('أُضيف الفصل', 'Term added')) : await OrgApi.i.put('$base/terms/${term['id']}', b, t('تم', 'Saved'));
                if (r != null && ctx.mounted) Navigator.pop(ctx);
              }),
            ]),
          );
        }));
    if (!draft) onChanged();
    return out;
  }

  /// "Auto-generate" · "Create manually" + the server's term drafts (Approve / Edit / Reject).
  Widget _suggestions(BuildContext context) => OrgTermSuggestions(
        orgBase: base.substring(0, base.length - '/academic'.length),
        onChanged: onChanged,
        onCreateManually: () => _edit(context),
        editDraft: (d) => _edit(context, d, true),
        kindLabel: (k) => termKinds()[k] ?? k,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final years = <String, List<Map<String, dynamic>>>{};
    for (final x in terms) {
      years.putIfAbsent('${x['year_label']}', () => []).add(x);
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(heroTag: 'term_new', onPressed: () => _edit(context),
          icon: const Icon(Icons.add_rounded), label: Text(t('فصل جديد', 'New term'))),
      body: years.isEmpty
          ? ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 100), children: [
              _suggestions(context),
              OrgEmpty(icon: Icons.calendar_month_rounded, title: t('ابدأ بالتقويم الأكاديمي', 'Start with the academic calendar'),
                  message: t('أضف الأعوام والفصول (الأول، الثاني، الصيفي) بتواريخها، ثم سجّل المقررات في كل فصل.', 'Add years and terms (1, 2, summer) with dates, then offer courses in each term.'),
                  actionLabel: t('فصل جديد', 'New term'), onAction: () => _edit(context)),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 100), children: [
              _suggestions(context),
              for (final e in years.entries) ...[
                OrgSectionTitle('${t('العام', 'Year')} ${e.key}', padding: const EdgeInsets.fromLTRB(4, 14, 4, 6)),
                for (final term in e.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RowCard(
                      accent: term['status'] == 'current' ? c.success : null,
                      onTap: () => _edit(context, term),
                      child: Row(children: [
                        IconBadge(term['kind'] == 'summer' ? Icons.wb_sunny_rounded : Icons.event_note_rounded,
                            term['status'] == 'current' ? c.success : c.primary, size: 40),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(termKinds()['${term['kind']}'] ?? '', style: orgText(context, w: FontWeight.w800)),
                          Text('${shortDate('${term['start_date']}')} → ${shortDate('${term['end_date']}')}', style: orgText(context, size: 12, color: c.textMedium)),
                        ])),
                        OrgPill({'current': t('جارٍ', 'Current'), 'upcoming': t('قادم', 'Upcoming'), 'finished': t('انتهى', 'Finished')}['${term['status']}'] ?? '',
                            color: term['status'] == 'current' ? c.success : c.textMedium),
                      ]),
                    ),
                  ),
              ],
            ]),
    );
  }
}

Widget _courseChips(BuildContext ctx, List<Map<String, dynamic>> courses, Set<int> sel, void Function(void Function()) set, {Set<int> disabled = const {}}) =>
    Wrap(spacing: 6, runSpacing: 6, children: [
      for (final co in courses)
        FilterChip(
          label: Text(_cname(co), style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5)),
          selected: sel.contains(asInt(co['id'])),
          onSelected: disabled.contains(asInt(co['id'])) ? null : (on) => set(() => on ? sel.add(asInt(co['id'])) : sel.remove(asInt(co['id']))),
        ),
    ]);

class _Programs extends StatelessWidget {
  const _Programs({required this.programs, required this.courses, required this.staff, required this.base, required this.onChanged});
  final List<Map<String, dynamic>> programs, courses, staff;
  final String base;
  final VoidCallback onChanged;

  Future<void> _edit(BuildContext context, [Map<String, dynamic>? p]) async {
    // reload even after a cancel: courses may have been created in place
    await showProgramForm(context, edit: p, courses: courses);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(heroTag: 'prog_new', onPressed: () => _edit(context),
          icon: const Icon(Icons.add_rounded), label: Text(t('قسم جديد', 'New department'))),
      body: programs.isEmpty
          ? OrgEmpty(icon: Icons.account_tree_rounded, title: t('أضف الأقسام العلمية', 'Add academic departments'),
              message: t('لكل قسم كود ومدير ومتطلبات التحاق ومقررات إجبارية واختيارية.', 'Each has a code, a manager, entry prerequisites, required and elective courses.'),
              actionLabel: t('قسم جديد', 'New department'), onAction: () => _edit(context))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 100), children: [
              for (final p in programs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RowCard(
                    onTap: () => _edit(context, p),
                    child: Row(children: [
                      IconBadge(Icons.account_tree_rounded, p['is_active'] == false ? c.textLight : c.primary, size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${p['code']} · ${t('${p['name_ar'] ?? p['name_en']}', '${p['name_en'] ?? p['name_ar']}')}', style: orgText(context, w: FontWeight.w800)),
                          Text(
                              t('${p['students']} طالب · ${(p['required_course_ids'] as List).length} إجباري · ${(p['elective_course_ids'] as List).length} اختياري',
                                  '${p['students']} students · ${(p['required_course_ids'] as List).length} required · ${(p['elective_course_ids'] as List).length} electives'),
                              style: orgText(context, size: 12, color: c.textMedium)),
                          Text(asMap(p['manager']).isEmpty ? t('بلا مدير', 'No manager') : '${t('المدير', 'Manager')}: ${asMap(p['manager'])['name']}',
                              style: orgText(context, size: 12, color: c.textLight)),
                          if (p['is_active'] == false) OrgPill(t('موقوف', 'Inactive'), color: c.textMedium),
                        ]),
                      ),
                      IconButton(
                        tooltip: t('الانضمام للقسم', 'Joining'),
                        icon: Icon(Icons.group_add_rounded, color: c.primary),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => OrgUnitJoinHub(unitType: 'program', unitId: asInt(p['id']), title: '${p['code']} · ${orgNameOf(p)}'))),
                      ),
                    ]),
                  ),
                ),
            ]),
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.settings, required this.courses, required this.base, required this.onChanged});
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> courses;
  final String base;
  final VoidCallback onChanged;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late bool hasDepts = widget.settings['has_departments'] == true;
  late final Set<int> grad = {...((widget.settings['graduation_course_ids'] as List?) ?? const []).map((e) => asInt(e))};
  late final Map<String, dynamic> sel = asMap(widget.settings['selection']);
  late bool open = sel['open'] == true, auto = sel['auto_approve'] == true;
  late final msg = TextEditingController(text: '${sel['message'] ?? ''}');
  late DateTime? deadline = orgParseUtc(sel['deadline']);
  bool busy = false;
  late final List<Map<String, dynamic>> levels = [for (final l in asMapList(widget.settings['levels'])) Map<String, dynamic>.from(l)];
  late bool allowGeneral = widget.settings['allow_general_teachers'] == true;
  late bool teacherLab = widget.settings['teacher_may_teach_lab'] != false;
  String? error;

  Future<void> _editLevel([int? i]) async {
    final l = i == null ? <String, dynamic>{} : levels[i];
    final key = TextEditingController(text: '${l['key'] ?? ''}');
    final ar = TextEditingController(text: '${l['label_ar'] ?? ''}');
    final en = TextEditingController(text: '${l['label_en'] ?? ''}');
    await showAdminSheet<void>(context, (ctx) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(i == null ? t('فرقة / مستوى جديد', 'New year / level') : t('تعديل المستوى', 'Edit level')),
            Field(controller: key, label: t('المفتاح (مثلاً 1 أو year4)', 'Key (e.g. 1 or year4)'), ltr: true, enabled: i == null),
            Field(controller: ar, label: t('الاسم بالعربية (مثلاً الفرقة الرابعة)', 'Arabic label (e.g. الفرقة الرابعة)')),
            Field(controller: en, label: t('الاسم بالإنجليزية (مثلاً Fourth year)', 'English label (e.g. Fourth year)'), ltr: true),
            PrimaryButton(isLoading: false, label: t('تم', 'Done'), onPressed: () {
              final k = key.text.trim();
              if (k.isEmpty || k.length > 20) return toast(t('المفتاح مطلوب (حتى 20 حرفاً)', 'A key is required (up to 20 characters)'), error: true);
              if (i == null && levels.any((x) => '${x['key']}' == k)) return toast(t('المفتاح مكرر', 'Duplicate key'), error: true);
              setState(() {
                final v = {'key': k, 'label_ar': ar.text.trim(), 'label_en': en.text.trim()};
                i == null ? levels.add(v) : levels[i] = v;
              });
              Navigator.pop(ctx);
            }),
          ]),
        ));
  }


  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      Section(
        title: t('هيكل المسار', 'Path structure'),
        icon: Icons.route_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          OrgSwitchRow(
            title: t('المؤسسة تعتمد أقساماً علمية', 'This organization has academic departments'),
            subtitle: hasDepts ? t('طالب عام ← قسم علمي ← خريج', 'General → department → graduated') : t('طالب عام ← خريج', 'General → graduated'),
            value: hasDepts, onChanged: (v) => setState(() => hasDepts = v)),
        ]),
      ),
      Section(
        title: t('الحد الأدنى من المقررات للتخرج', 'Minimum courses to graduate'),
        icon: Icons.school_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('مطلوبة من كل الطلاب (ويُضاف إليها مقررات القسم إن وجد).', 'Required from every student (plus the department\'s courses, if any).'),
              style: orgText(context, size: 12, color: c.textMedium)),
          const SizedBox(height: 8),
          _courseChips(context, widget.courses, grad, setState),
        ]),
      ),
      if (hasDepts)
        Section(
          title: t('نافذة اختيار القسم', 'Department selection window'),
          icon: Icons.how_to_vote_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            OrgSwitchRow(title: t('مفتوحة الآن', 'Open now'),
                subtitle: t('يظهر "اختر قسمك" للطلاب المؤهلين على الرئيسية', '"Choose your department" appears to eligible students'),
                value: open, onChanged: (v) => setState(() => open = v)),
            Field(controller: msg, label: t('رسالة للطلاب', 'Message to students'), maxLines: 2),
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.timer_rounded),
                title: Text(deadline == null ? t('بدون موعد نهائي', 'No deadline') : '${t('حتى', 'Until')} ${shortDateTime(deadline!.toIso8601String())}'),
                onTap: () async {
                  final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(2100), initialDate: deadline ?? DateTime.now());
                  if (d != null) setState(() => deadline = DateTime(d.year, d.month, d.day, 23, 59));
                }),
            OrgSwitchRow(title: t('قبول تلقائي', 'Accept automatically'),
                subtitle: t('وإلا يوافق مدير القسم أو الإدارة', 'Otherwise the department manager / admin approves'),
                value: auto, onChanged: (v) => setState(() => auto = v)),
          ]),
        ),
      Section(
        title: t('الفرق / المستويات الدراسية', 'Academic years / levels'),
        icon: Icons.stairs_rounded,
        trailing: IconButton(tooltip: t('إضافة مستوى', 'Add a level'), onPressed: () => _editLevel(), icon: Icon(Icons.add_circle_rounded, color: c.primary)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('تُستخدم في بيانات الطلاب الموثّقة وفي شروط الانضمام للأقسام. الكلية بلا مستويات ترث مستويات جامعتها.',
              'Used in students\' trusted records and in department joining rules. A faculty without levels inherits its university\'s.'),
              style: orgText(context, size: 12, color: c.textMedium)),
          if (levels.isEmpty)
            Padding(padding: const EdgeInsets.all(8), child: Text(t('لا مستويات بعد', 'No levels yet'), style: orgText(context, color: c.textLight))),
          for (var i = 0; i < levels.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 14, child: Text('${levels[i]['key']}', style: const TextStyle(fontSize: 11))),
              title: Text(t('${levels[i]['label_ar'] ?? ''}', '${levels[i]['label_en'] ?? ''}').trim().isEmpty ? '${levels[i]['key']}' : t('${levels[i]['label_ar']}', '${levels[i]['label_en']}')),
              onTap: () => _editLevel(i),
              trailing: IconButton(tooltip: t('حذف', 'Delete'), icon: Icon(Icons.delete_outline_rounded, color: c.danger), onPressed: () => setState(() => levels.removeAt(i))),
            ),
        ]),
      ),
      Section(
        title: t('سياسة التدريس', 'Teaching policy'),
        icon: Icons.co_present_rounded,
        child: Column(children: [
          OrgSwitchRow(
              title: t('المدرس العام يدرّس مقررات الأقسام', 'General teachers may teach department courses'),
              subtitle: t('المدرس بلا قسم علمي — وإلا يدرّس المقررات العامة فقط', 'A teacher with no academic department — otherwise general courses only'),
              value: allowGeneral,
              onChanged: (v) => setState(() => allowGeneral = v)),
          OrgSwitchRow(
              title: t('يمكن للمدرس تدريس السكشن / المعمل', 'Teachers may teach labs'),
              subtitle: t('وإلا يحتاج كل سكشن معيداً', 'Otherwise every lab needs a teaching assistant'),
              value: teacherLab,
              onChanged: (v) => setState(() => teacherLab = v)),
        ]),
      ),
      if (error != null)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: orgText(context, size: 12.5, color: c.danger))),
      PrimaryButton(isLoading: busy, label: t('حفظ', 'Save'), onPressed: () async {
        setState(() {
          busy = true;
          error = null;
        });
        // the PUT resets omitted keys — the whole object is sent
        final r = await orgCall(
            () => OrgApi.i.api.put('${widget.base}/settings', body: {
                  'has_departments': hasDepts, 'graduation_course_ids': grad.toList(),
                  'selection': {'open': open, 'message': msg.text.trim(), 'deadline': orgUtc(deadline), 'auto_approve': auto},
                  'levels': levels, 'allow_general_teachers': allowGeneral, 'teacher_may_teach_lab': teacherLab,
                }),
            ok: t('تم الحفظ', 'Saved'),
            quiet: true);
        if (!mounted) return;
        setState(() {
          busy = false;
          if (!r.ok) {
            final used = (r.detail['levels'] as List?)?.join('، ');
            error = '${orgErrorText(r.error!)}${used == null ? '' : ' ($used)'}';
          }
        });
        if (r.ok) widget.onChanged();
      }),
    ]);
  }
}

class _Students extends StatelessWidget {
  const _Students({required this.programs, required this.base});
  final List<Map<String, dynamic>> programs;
  final String base;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('$base/students')..refresh(),
      child: Builder(builder: (context) {
        final p = context.watch<OrgPaged>();
        final c = context.colors;
        final key = p.filters['pending'] == true ? 'action' : '${p.filters['stage'] ?? ''}';
        return Column(children: [
          const SizedBox(height: 8),
          FilterChips<String>(
            options: {'': t('الكل', 'All'), 'action': t('بانتظار إجراء', 'Needs action'), ...stageLabels()},
            value: key,
            onChanged: (v) async {
              p.filters.remove('pending');
              if (v == 'action') {
                p.filters['pending'] = true;
                await p.setFilter('stage', null);
              } else {
                await p.setFilter('stage', v);
              }
            },
          ),
          Expanded(
            child: PagedList<OrgPaged>(
              emptyText: t('لا طلاب هنا', 'No students here'),
              itemBuilder: (context, row) {
                final u = asMap(row['user']);
                final req = asMap(row['request']);
                final pct = asInt(row['percent']);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: RowCard(
                    accent: row['ready_to_graduate'] == true || req['status'] == 'pending' ? c.warning : null,
                    child: Column(children: [
                      Row(children: [
                        AdminAvatar(name: '${u['name']}', url: u['image_url'] as String?),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (u['id'] != null)
                            EntityGuardedChip(EntityRef(EntityKind.student, asInt(u['id']), label: '${u['name']}'), maxWidth: 320)
                          else
                            Text('${u['name']}', style: orgText(context, w: FontWeight.w800)),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            OrgPill(stageLabels()['${row['stage']}'] ?? '', color: row['stage'] == 'graduated' ? c.success : c.primary),
                            if (row['program'] != null) OrgPill('${asMap(row['program'])['code']}', icon: Icons.account_tree_rounded),
                            if (req['status'] == 'pending')
                              OrgPill('${t('يطلب', 'Asks for')} ${programs.where((x) => x['id'] == req['program_id']).map((x) => x['code']).join()}', color: c.warning),
                          ]),
                        ])),
                        SizedBox(width: 44, height: 44, child: Stack(alignment: Alignment.center, children: [
                          CircularProgressIndicator(value: pct / 100, strokeWidth: 4, backgroundColor: c.divider),
                          Text('$pct%', style: orgText(context, size: 10.5, w: FontWeight.w800)),
                        ])),
                      ]),
                      if (req['status'] == 'pending' || row['ready_to_graduate'] == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(spacing: 8, children: [
                            if (req['status'] == 'pending') ...[
                              FilledButton(onPressed: () async {
                                if (await OrgApi.i.post('$base/students/${u['id']}/request/approve', {'days': 1}, t('تم القبول', 'Approved')) != null) p.refresh();
                              }, child: Text(t('قبول في القسم', 'Accept'))),
                              OutlinedButton(onPressed: () async {
                                final note = await askText(context, title: t('سبب الرفض', 'Reason'), multiline: true);
                                if (note != null && await OrgApi.i.post('$base/students/${u['id']}/request/reject', {'days': 1, 'note': note}, t('تم', 'Done')) != null) p.refresh();
                              }, child: Text(t('رفض', 'Reject'))),
                            ],
                            if (row['ready_to_graduate'] == true)
                              FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: c.success),
                                onPressed: () async {
                                  if (await confirm(context, message: t('اعتماد تخرج ${u['name']}؟', 'Confirm ${u['name']}\'s graduation?')) &&
                                      await OrgApi.i.post('$base/students/${u['id']}/graduate', null, t('مبروك التخرج 🎓', 'Graduated 🎓')) != null) p.refresh();
                                },
                                icon: const Icon(Icons.school_rounded),
                                label: Text(t('اعتماد التخرج', 'Graduate')),
                              ),
                          ]),
                        ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]);
      }),
    );
  }
}

class _ArchiveRequests extends StatelessWidget {
  const _ArchiveRequests({required this.base, this.orgId});
  final String base;
  final int? orgId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('$base/archive-requests', {'status': 'pending'})..refresh(),
      child: Builder(builder: (context) {
        final p = context.watch<OrgPaged>();
        final c = context.colors;
        return Column(children: [
          if (orgId != null) _OrgArchiveOpenSwitch(orgId: orgId!),
          Expanded(child: PagedList<OrgPaged>(
          emptyText: t('لا طلبات لفتح الأرشيف', 'No archive requests'),
          itemBuilder: (context, row) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: RowCard(
              child: Row(children: [
                IconBadge(Icons.inventory_2_rounded, c.warning, size: 42),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // the student and the course open their detail where the server allows it (D-290)
                  if (asMap(row['student'])['id'] != null)
                    EntityGuardedChip(
                        EntityRef(EntityKind.student, asInt(asMap(row['student'])['id']), label: '${asMap(row['student'])['name']}'),
                        maxWidth: 320)
                  else
                    Text('${asMap(row['student'])['name']}', style: orgText(context, w: FontWeight.w800)),
                  Wrap(spacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (asMap(row['course'])['id'] != null)
                      EntityGuardedChip(EntityRef(EntityKind.course, asInt(asMap(row['course'])['id']), label: _cname(asMap(row['course']))))
                    else
                      Text(_cname(asMap(row['course'])), style: orgText(context, size: 12, color: c.textMedium)),
                    Text('${termKinds()[asMap(asMap(row['run'])['term'])['kind']] ?? ''} ${asMap(asMap(row['run'])['term'])['year_label'] ?? ''}',
                        style: orgText(context, size: 12, color: c.textMedium)),
                  ]),
                  if ('${row['reason'] ?? ''}'.isNotEmpty) Text('"${row['reason']}"', style: orgText(context, size: 12)),
                ])),
                IconButton(tooltip: t('موافقة', 'Approve'), icon: Icon(Icons.check_circle_rounded, color: c.success), onPressed: () async {
                  final d = await askText(context, title: t('عدد أيام الفتح', 'Open for how many days?'), hint: '7');
                  if (d != null && await OrgApi.i.post('$base/archive-requests/${row['id']}/approve', {'days': int.tryParse(d) ?? 7}, t('تم الفتح', 'Opened')) != null) p.refresh();
                }),
                IconButton(tooltip: t('رفض', 'Reject'), icon: Icon(Icons.cancel_rounded, color: c.danger), onPressed: () async {
                  final note = await askText(context, title: t('سبب الرفض', 'Reason'), multiline: true);
                  if (note != null && await OrgApi.i.post('$base/archive-requests/${row['id']}/reject', {'days': 1, 'note': note}, t('تم', 'Done')) != null) p.refresh();
                }),
              ]),
            ),
          ),
        )),
        ]);
      }),
    );
  }
}

/// Organization rule for every course archive (was inside each course's profile): open access lets each course's own
/// mode apply (automatic · request · code); off = every pass needs an admin's approval. Hidden for who can't change it.
class _OrgArchiveOpenSwitch extends StatefulWidget {
  const _OrgArchiveOpenSwitch({required this.orgId});
  final int orgId;

  @override
  State<_OrgArchiveOpenSwitch> createState() => _OrgArchiveOpenSwitchState();
}

class _OrgArchiveOpenSwitchState extends State<_OrgArchiveOpenSwitch> {
  bool? _open;
  String get _path => '/api/v1/course-profile/orgs/${widget.orgId}/archive-settings';

  @override
  void initState() {
    super.initState();
    ApiClient().get(_path).then((r) {
      if (mounted && r is Map) setState(() => _open = r['open'] == true);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_open == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: RowCard(
        child: OrgSwitchRow(
          title: t('وصول مفتوح لأرشيف المقررات', 'Open access to course archives'),
          subtitle: t('يطبّق كل مقرر طريقته (تلقائي · طلب · كود) — عند الإيقاف يحتاج كل وصول موافقة المسؤول',
              "Each course's own way applies (automatic · request · code) — when off, every access needs admin approval"),
          value: _open!,
          onChanged: (v) async {
            final r = await orgCall(() => ApiClient().put(_path, body: {'open': v}), ok: t('تم الحفظ', 'Saved'));
            if (r.ok && mounted) setState(() => _open = v);
          },
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  A course's archive (teachers & staff): years → terms → run
// ═════════════════════════════════════════════════════════════════════════════

class CourseArchiveScreen extends StatefulWidget {
  const CourseArchiveScreen({super.key, required this.orgId, required this.courseId, this.canManage = false});
  final int orgId, courseId;
  final bool canManage;

  @override
  State<CourseArchiveScreen> createState() => _CourseArchiveScreenState();
}

class _CourseArchiveScreenState extends State<CourseArchiveScreen> {
  Map<String, dynamic>? _d;
  bool _failed = false; // the archive could not be loaded (getMap already toasted why)
  String get _a => '$orgBase/orgs/${widget.orgId}/academic';

  /// The dashboard header's Refresh reloads the archive in place (D-103).
  final _refresh = OrgPageRefresh();

  @override
  void initState() {
    super.initState();
    _refresh.attach(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_failed) setState(() => _failed = false);
    final r = await OrgApi.i.getMap('$_a/courses/${widget.courseId}/archive');
    if (mounted) setState(() { _failed = r == null && _d == null; _d = r ?? _d; });
    if (mounted && r != null) _refresh.markUpdated();
  }

  Future<void> _openRun() async {
    final terms = asMapList((await OrgApi.i.getMap('$_a/terms'))?['items']).where((x) => x['status'] != 'finished').toList();
    if (!mounted) return;
    if (terms.isEmpty) return toast(t('أضف فصلاً دراسياً من التقويم أولاً', 'Add a term in the calendar first'), error: true);
    final id = await showAdminSheet<int>(context, (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          SheetHeader(t('تسجيل المقرر في فصل', 'Offer the course in a term')),
          for (final x in terms)
            ListTile(leading: const Icon(Icons.event_note_rounded), title: Text('${termKinds()[x['kind']]} ${x['year_label']}'),
                subtitle: Text('${shortDate('${x['start_date']}')} → ${shortDate('${x['end_date']}')}'), onTap: () => Navigator.pop(ctx, asInt(x['id']))),
        ]));
    if (id != null && await OrgApi.i.post('$_a/courses/${widget.courseId}/runs', {'term_id': id}, t('فُتح المقرر للفصل', 'Offered in the term')) != null) _load();
  }

  Future<void> _run(Map<String, dynamic> run) async {
    final d = await OrgApi.i.getMap('$_a/runs/${run['id']}');
    if (d == null || !mounted) return;
    final failed = <int>{};
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          final live = d['status'] != 'archived';
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader('${termKinds()[asMap(d['term'])['kind']]} ${asMap(d['term'])['year_label']}'),
              Wrap(spacing: 6, children: [
                OrgPill(statusLabel('${d['status']}'), color: live ? c.success : c.textMedium),
                if (!live) OrgPill(t('${d['passed']} / ${d['students']} ناجح', '${d['passed']} / ${d['students']} passed'), color: c.success),
              ]),
              const SizedBox(height: 10),
              if (live && widget.canManage)
                Text(t('عند الأرشفة: حدّد غير الناجحين — الباقون يُسجَّلون ناجحين ويُغلق المحتوى للجميع.',
                    'On archive: tick who did NOT pass — everyone else is recorded as passed, and the content closes for all.'),
                    style: orgText(ctx, size: 12, color: c.textMedium)),
              for (final s in asMapList(d['students']))
                live && widget.canManage
                    ? Material(type: MaterialType.transparency, child: CheckboxListTile(
                        dense: true,
                        value: failed.contains(asInt(asMap(s['user'])['id'])),
                        onChanged: (v) => set(() => v == true ? failed.add(asInt(asMap(s['user'])['id'])) : failed.remove(asInt(asMap(s['user'])['id']))),
                        title: Text('${asMap(s['user'])['name']}'),
                        subtitle: Text(failed.contains(asInt(asMap(s['user'])['id'])) ? t('لم ينجح', 'Did not pass') : t('ناجح', 'Passed')),
                      ))
                    : ListTile(dense: true, title: Text('${asMap(s['user'])['name']}'),
                        trailing: s['result'] == null ? null : OrgPill(s['result'] == 'passed' ? t('ناجح', 'Passed') : t('لم ينجح', 'Not passed'),
                            color: s['result'] == 'passed' ? c.success : c.danger)),
              if (live && widget.canManage) ...[
                const SizedBox(height: 10),
                PrimaryButton(isLoading: false, label: t('إنهاء الفصل ونقل المقرر للأرشيف', 'End the term & archive'), icon: Icons.inventory_2_rounded, iconBefore: true,
                    onPressed: () async {
                      if (!await confirm(ctx, message: t('سيُغلق المحتوى لطلاب هذا الفصل ولن يفتحوه إلا بموافقة. متابعة؟', 'The content closes for these students (re-opened only on approval). Continue?'))) return;
                      if (await OrgApi.i.post('$_a/runs/${run['id']}/archive', {'failed_student_ids': failed.toList()}, t('أُرشف المقرر', 'Archived')) != null && ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                    }),
              ],
            ]),
          );
        }));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final course = asMap(d?['course']);
    final title = d == null ? t('أرشيف المقرر', 'Course archive') : _cname(course);
    // staff of this organization: the dashboard's header; a course profile opened elsewhere keeps the older bar
    if (orgUsesDashboardHeader(context, widget.orgId)) {
      return OrgPushedPage(
        title: title,
        subtitle: d == null ? null : t('أرشيف المقرر', 'Course archive'),
        refresh: _refresh,
        maxWidth: 820,
        child: _content(context, d),
      );
    }
    return BasePage(
      useWebCard: true,
      maxWith: 820,
      appBar: ScreenAppBar(title: title, actions: const [ContextExitButton()]),
      child: _content(context, d),
    );
  }

  Widget _content(BuildContext context, Map<String, dynamic>? d) {
    final c = context.colors;
    return d == null
          ? (_failed ? ErrorRetry(message: t('تعذّر تحميل الأرشيف', 'Could not load the archive'), onRetry: _load) : const AppListSkeleton())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
              if (d['current'] != null)
                OrgActionCard(icon: Icons.play_circle_rounded, color: c.success,
                    title: '${t('النسخة الحالية', 'Current version')} · ${termKinds()[asMap(asMap(d['current'])['term'])['kind']]} ${asMap(asMap(d['current'])['term'])['year_label']}',
                    subtitle: t('اضغط لعرض الطلاب أو إنهاء الفصل وأرشفته', 'Tap to see students or end & archive the term'),
                    onTap: () => _run(asMap(d['current'])))
              else if (widget.canManage)
                OrgActionCard(icon: Icons.add_circle_rounded, color: c.primary, title: t('تسجيل المقرر في فصل جديد', 'Offer in a new term'),
                    subtitle: t('افتح نسخة جديدة نظيفة للطلاب الجدد', 'Open a fresh version for new students'), onTap: _openRun),
              const SizedBox(height: 8),
              OrgSectionTitle(t('الأرشيف', 'Archive'), padding: const EdgeInsets.fromLTRB(4, 10, 4, 6)),
              if (asMapList(d['years']).isEmpty) Text(t('لا نسخ سابقة بعد', 'No previous versions yet'), style: orgText(context, color: c.textMedium)),
              for (final y in asMapList(d['years']))
                Card(
                  child: ExpansionTile(
                    leading: Icon(Icons.folder_rounded, color: c.accent2),
                    title: Text('${t('العام', 'Year')} ${y['year_label']}', style: orgText(context, w: FontWeight.w800)),
                    children: [
                      for (final r in asMapList(y['runs']))
                        ListTile(
                          leading: Icon(r['status'] == 'archived' ? Icons.inventory_2_rounded : Icons.play_circle_rounded,
                              color: r['status'] == 'archived' ? c.textMedium : c.success),
                          title: Text(termKinds()[asMap(r['term'])['kind']] ?? ''),
                          subtitle: Text(r['status'] == 'archived' ? t('${r['passed']} / ${r['students']} ناجح', '${r['passed']} / ${r['students']} passed') : statusLabel('${r['status']}')),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _run(r),
                        ),
                    ],
                  ),
                ),
            ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Student
// ═════════════════════════════════════════════════════════════════════════════

class MyAcademicPathPage extends StatefulWidget {
  const MyAcademicPathPage({super.key, required this.orgId});
  final int orgId;

  @override
  State<MyAcademicPathPage> createState() => _MyAcademicPathPageState();
}

class _MyAcademicPathPageState extends State<MyAcademicPathPage> {
  Map<String, dynamic>? _p;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  int _loads = 0;   // pull-to-refresh also reloads the level card

  Future<void> _load() async {
    if (_failed) setState(() => _failed = false);
    final r = await OrgApi.i.getMap('$_pub/${widget.orgId}/my-path');
    if (mounted) {
      setState(() {
        _failed = r == null && _p == null;
        _p = r ?? _p;
        _loads++;
      });
    }
  }

  Future<void> _choose() async {
    final progs = asMapList(_p!['eligible_programs']);
    int? first, second;
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          Widget card(Map<String, dynamic> p, int? sel, ValueChanged<int> on) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: p['full'] == true ? null : () => on(asInt(p['id'])),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: sel == p['id'] ? c.primary.withValues(alpha: 0.08) : c.cardBg,
                      border: Border.all(color: sel == p['id'] ? c.primary : c.divider, width: sel == p['id'] ? 1.6 : 1),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                        child: Text('${p['code']}', style: orgText(ctx, w: FontWeight.w800, color: c.primary)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t('${p['name_ar'] ?? p['name_en']}', '${p['name_en'] ?? p['name_ar']}'), style: orgText(ctx, w: FontWeight.w800)),
                        if ('${p['description'] ?? ''}'.isNotEmpty) Text('${p['description']}', maxLines: 2, style: orgText(ctx, size: 12, color: c.textMedium)),
                        if (p['full'] == true) OrgPill(t('اكتمل العدد', 'Full'), color: c.danger),
                      ])),
                      if (sel == p['id']) Icon(Icons.check_circle_rounded, color: c.primary),
                    ]),
                  ),
                ),
              );
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(t('اختر قسمك العلمي', 'Choose your department')),
              if ('${asMap(_p!['selection'])['message'] ?? ''}'.isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('${asMap(_p!['selection'])['message']}', style: orgText(ctx, color: c.textMedium))),
              Text(t('الاختيار الأول', 'First choice'), style: orgText(ctx, w: FontWeight.w800)),
              const SizedBox(height: 6),
              for (final p in progs) card(p, first, (v) => set(() { first = v; if (second == v) second = null; })),
              if (progs.length > 1) ...[
                const SizedBox(height: 8),
                Text(t('الاختيار الثاني (اختياري)', 'Second choice (optional)'), style: orgText(ctx, w: FontWeight.w800)),
                const SizedBox(height: 6),
                for (final p in progs.where((x) => x['id'] != first)) card(p, second, (v) => set(() => second = second == v ? null : v)),
              ],
              PrimaryButton(isLoading: false, label: t('إرسال اختياري', 'Send my choice'), onPressed: first == null ? null : () async {
                final r = await OrgApi.i.post('$_pub/${widget.orgId}/choose-department', {'program_id': first, 'second_program_id': second},
                    t('وصل اختيارك 🎓', 'Your choice was sent 🎓'));
                if (r != null && ctx.mounted) Navigator.pop(ctx);
              }),
            ]),
          );
        }));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = _p;
    if (p == null) {
      return _failed ? ErrorRetry(message: t('تعذّر تحميل مسارك', 'Could not load your path'), onRetry: _load) : const AppListSkeleton();
    }
    final hasDepts = p['has_departments'] == true;
    final stage = '${p['stage']}';
    final steps = [('general', t('طالب عام', 'General'), Icons.person_rounded),
      if (hasDepts) ('program', t('القسم', 'Department'), Icons.account_tree_rounded),
      ('graduated', t('خريج', 'Graduated'), Icons.school_rounded)];
    final at = steps.indexWhere((s) => s.$1 == stage);
    final pct = asInt(p['percent']);
    final req = asMap(p['request']);
    return AppRefresh(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)), child: AppMeshSurface(radius: BorderRadius.circular(24), child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
            Row(children: [
              for (var i = 0; i < steps.length; i++) ...[
                Expanded(child: Column(children: [
                  CircleAvatar(radius: 20, backgroundColor: i <= at ? c.onHero : c.heroGlassBorder,
                      child: Icon(steps[i].$3, color: i <= at ? c.primary : c.onHeroMuted, size: 20)),
                  const SizedBox(height: 6),
                  Text(steps[i].$2, style: TextStyle(fontFamily: AppFonts.family, color: i <= at ? c.onHero : c.onHeroMuted,
                      fontWeight: i == at ? FontWeight.w800 : FontWeight.w500, fontSize: 12.5)),
                ])),
                if (i < steps.length - 1) Expanded(child: Container(height: 2, color: i < at ? c.onHero : c.heroGlassBorder)),
              ],
            ]),
            const SizedBox(height: 16),
            if (p['program'] != null)
              Text('${asMap(p['program'])['code']} · ${t('${asMap(p['program'])['name_ar'] ?? asMap(p['program'])['name_en']}', '${asMap(p['program'])['name_en'] ?? asMap(p['program'])['name_ar']}')}',
                  style: TextStyle(fontFamily: AppFonts.family, color: c.onHero, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: pct / 100, minHeight: 8, backgroundColor: c.heroGlassBorder, color: c.accent2)),
            const SizedBox(height: 6),
            Text(stage == 'graduated' ? t('مبروك التخرج 🎓', 'Congratulations, graduate 🎓') : t('أنجزت $pct% من متطلبات التخرج', '$pct% of graduation requirements done'),
                style: TextStyle(fontFamily: AppFonts.family, color: c.onHero)),
          ])))),
        const SizedBox(height: 12),
        MyLevelCard(key: ValueKey('lvl_${widget.orgId}_$_loads'), orgId: widget.orgId),
        const SizedBox(height: 12),
        if (p['can_choose'] == true)
          OrgActionCard(icon: Icons.how_to_vote_rounded, color: c.warning, title: t('اختر قسمك العلمي', 'Choose your department'),
              subtitle: t('اجتزت متطلبات الالتحاق — حان وقت الاختيار', 'You passed the entry courses — time to choose'), onTap: _choose),
        if (req['status'] == 'pending')
          OrgActionCard(icon: Icons.hourglass_top_rounded, color: c.warning, title: t('طلب القسم قيد المراجعة', 'Your department request is being reviewed'),
              subtitle: t('سنبلغك فور القرار', 'We\'ll tell you as soon as it\'s decided')),
        if (req['status'] == 'rejected')
          OrgActionCard(icon: Icons.info_rounded, color: c.danger, title: t('لم يُقبل طلب القسم', 'Department request not accepted'),
              subtitle: '${req['note'] ?? ''}'),
        if (p['ready_to_graduate'] == true)
          OrgActionCard(icon: Icons.verified_rounded, color: c.success, title: t('أكملت كل المتطلبات', 'All requirements done'),
              subtitle: t('بانتظار اعتماد التخرج من الإدارة', 'Waiting for the administration to confirm graduation')),
        OrgSectionTitle(t('المقررات المطلوبة', 'Required courses'), padding: const EdgeInsets.fromLTRB(4, 14, 4, 6)),
        for (final x in asMapList(p['required']))
          ListTile(dense: true, leading: Icon(x['passed'] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: x['passed'] == true ? c.success : c.textLight), title: Text(_cname(x))),
        if (asMapList(p['electives']).isNotEmpty) ...[
          OrgSectionTitle(t('اختيارية (${p['electives_done']} من ${p['min_electives']} مطلوبة)', 'Electives (${p['electives_done']} of ${p['min_electives']} needed)'),
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 6)),
          for (final x in asMapList(p['electives']))
            ListTile(dense: true, leading: Icon(x['passed'] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: x['passed'] == true ? c.success : c.textLight), title: Text(_cname(x))),
        ],
      ]),
    );
  }
}

/// A student taps a course of their organization: open normally, or the archive gate.
Future<bool> orgCourseGate(BuildContext context, int courseId) async {
  Map<String, dynamic>? a;
  try {
    final r = await ApiClient().get('$_pub/courses/$courseId/access');
    if (r is Map) a = Map<String, dynamic>.from(r);
  } catch (_) {
    return true;                          // no academic data → open as before
  }
  if (a == null || a['state'] == 'open') {
    // department / course prerequisites: explain kindly instead of a bare refusal at enrollment
    try {
      final e = await ApiClient().get('$_pub/courses/$courseId/eligibility');
      if (e is Map && e['allowed'] == false && context.mounted) {
        await showEnrollBlock(context, asMap(e['reason']));
        return false;
      }
    } catch (_) {}
    return true;
  }
  if (a['state'] == 'archived_granted') {
    toast(t('الأرشيف مفتوح لك حتى ${shortDate('${a['until']}')}', 'The archive is open to you until ${shortDate('${a['until']}')}'));
    return true;
  }
  if (!context.mounted) return false;
  final term = asMap(asMap(a['run'])['term']);
  await showAdminSheet<void>(context, (ctx) {
    final c = ctx.colors;
    final reason = TextEditingController();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader(t('المقرر في الأرشيف', 'This course is archived')),
        IconBadge(Icons.inventory_2_rounded, c.accent2, size: 52),
        const SizedBox(height: 10),
        Text(t('انتهى ${termKinds()[term['kind']] ?? ''} ${term['year_label'] ?? ''} وأُغلقت هذه النسخة.', '${termKinds()[term['kind']] ?? ''} ${term['year_label'] ?? ''} ended and this version is closed.'),
            style: orgText(ctx, w: FontWeight.w700)),
        if (a!['result'] != null)
          Padding(padding: const EdgeInsets.only(top: 6),
              child: OrgPill(a['result'] == 'passed' ? t('نتيجتك: ناجح', 'Your result: passed') : t('نتيجتك: لم تنجح', 'Your result: not passed'),
                  color: a['result'] == 'passed' ? c.success : c.danger)),
        const SizedBox(height: 12),
        if (a['state'] == 'pending')
          Text(t('طلبك لفتح آخر نسخة قيد المراجعة.', 'Your request to open the last version is being reviewed.'), style: orgText(ctx, color: c.warning))
        else if (a['took_it'] == true) ...[
          Field(controller: reason, label: t('لماذا تحتاج فتحها؟ (اختياري)', 'Why do you need it? (optional)'), maxLines: 2),
          PrimaryButton(isLoading: false, label: t('طلب فتح آخر نسخة', 'Request the last version'), onPressed: () async {
            final r = await OrgApi.i.post('$_pub/courses/$courseId/archive-request', {'reason': reason.text.trim()}, t('أُرسل طلبك', 'Request sent'));
            if (r != null && ctx.mounted) Navigator.pop(ctx);
          }),
        ] else
          Text(t('ستُفتح نسخة جديدة عند تسجيل المقرر في فصل قادم.', 'A fresh version opens when the course is offered in an upcoming term.'), style: orgText(ctx, color: c.textMedium)),
        // course profile: read-only archive with this course's access mode (automatic · request · code)
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.dashboard_customize_rounded),
          label: Text(t('ملف المقرر والأرشيف (كود / وصول تلقائي)', 'Course profile & archive (code / automatic access)')),
          onPressed: () {
            Navigator.pop(ctx);
            openCourseProfile(context, courseId, tab: 'archive');
          },
        ),
      ]),
    );
  });
  return false;
}
