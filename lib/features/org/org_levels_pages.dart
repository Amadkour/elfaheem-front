// lib/features/org/org_levels_pages.dart — academic levels (API: /academic/levels, /public/{org}/my-level).
//
// Staff
//   OrgLevelsTab        ordered levels (drag to reorder), per-level department chips ("inherited from Level N" /
//                       "custom" / "all departments"), entry rules, Term 1 · Term 2 · Summer → courses, re-evaluate
//   PrereqRulesEditor   a list of {type, params} rules with a friendly editor — also used by the department form
// Students
//   MyLevelCard         "My academic path": current level, progress toward the next, blocked rules, this level's
//                       terms and courses, the departments open at this level and what each still needs
//   showEnrollBlock     the friendly "why can't I join this course" sheet (department / course prerequisites)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import 'org_levels.dart';
import 'org_program_form.dart' show CourseSetField, orgAllCourses, orgCourseName;
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_v3.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

const _pub = '$orgBase/public';

String _courseLabel(Map<String, dynamic> courses, int id) {
  final c = courses['$id'];
  return c is Map ? orgCourseName(c) : '#$id';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Rules editor (levels + departments)
// ═════════════════════════════════════════════════════════════════════════════

class PrereqRulesEditor extends StatelessWidget {
  const PrereqRulesEditor({
    super.key,
    required this.rules,
    required this.courses,
    required this.onChanged,
    this.levels = const [],
    this.emptyText,
  });

  final List<PrereqRule> rules;                 // mutated in place
  final List<Map<String, dynamic>>? courses;    // null = still loading
  final List<LevelDraft> levels;                // for "finish a level's courses"
  final VoidCallback onChanged;
  final String? emptyText;

  Map<String, dynamic> get _byId => {for (final c in courses ?? const <Map<String, dynamic>>[]) '${c['id']}': c};

  String _levelName(String key) => levels.where((l) => l.key == key).map((l) => l.label).firstOrNull ?? key;

  Future<void> _edit(BuildContext context, [int? index]) async {
    final r = await showAppSheet<PrereqRule>(
        context, (_) => _RuleSheet(rule: index == null ? null : rules[index], courses: courses ?? const [], levels: levels));
    if (r == null) return;
    index == null ? rules.add(r) : rules[index] = r;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final byId = _byId;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (rules.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(emptyText ?? t('لا شروط', 'No rules'), style: orgText(context, size: 12.5, color: c.textLight)),
        ),
      for (var i = 0; i < rules.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 4, 6),
          decoration: BoxDecoration(
            color: (rules[i].isValid ? c.primary : c.danger).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(Icons.rule_rounded, size: 18, color: rules[i].isValid ? c.primary : c.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                rules[i].describe(levelName: _levelName, courseName: (id) => _courseLabel(byId, id)),
                style: orgText(context, size: 12.5, w: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: t('تعديل', 'Edit'),
              visualDensity: VisualDensity.compact,
              onPressed: () => _edit(context, i),
              icon: const Icon(Icons.edit_rounded, size: 18),
            ),
            IconButton(
              tooltip: t('حذف', 'Remove'),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                rules.removeAt(i);
                onChanged();
              },
              icon: Icon(Icons.close_rounded, size: 18, color: c.danger),
            ),
          ]),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: courses == null ? null : () => _edit(context),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(t('إضافة شرط', 'Add a rule')),
        ),
      ),
    ]);
  }
}

class _RuleSheet extends StatefulWidget {
  const _RuleSheet({required this.rule, required this.courses, required this.levels});
  final PrereqRule? rule;
  final List<Map<String, dynamic>> courses;
  final List<LevelDraft> levels;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  late String _type = widget.rule?.type ?? 'courses_passed';
  late final Set<int> _courses = {...?widget.rule?.courseIds};
  late final _num = TextEditingController(text: _initialNumber());
  late final _min = TextEditingController(text: '${widget.rule?.params['min_count'] ?? ''}');
  late String? _levelKey = widget.rule?.params['level_key']?.toString();
  late bool _summer = widget.rule?.params['include_summer'] == true;
  String? _err;

  String _initialNumber() {
    final p = widget.rule?.params ?? const {};
    return '${p['count'] ?? p['hours'] ?? p['percent'] ?? ''}';
  }

  @override
  void dispose() {
    _num.dispose();
    _min.dispose();
    super.dispose();
  }

  PrereqRule _build() {
    final n = num.tryParse(_num.text.trim());
    return switch (_type) {
      'courses_passed' => PrereqRule(_type, {
          'course_ids': _courses.toList(),
          if (int.tryParse(_min.text.trim()) != null) 'min_count': int.parse(_min.text.trim()),
        }),
      'level_courses' => PrereqRule(_type, {'percent': n?.toInt() ?? 100, 'include_summer': _summer, 'level_key': ?_levelKey}),
      'min_courses' => PrereqRule(_type, {'count': n?.toInt()}),
      'min_hours' => PrereqRule(_type, {'hours': n}),
      _ => PrereqRule(_type, {'percent': n}),
    };
  }

  String get _numLabel => switch (_type) {
        'level_courses' => t('النسبة المطلوبة من المقررات (٪)', 'Share of the courses (%)'),
        'min_courses' => t('عدد المقررات المجتازة', 'Courses passed'),
        'min_hours' => t('عدد الساعات', 'Hours'),
        _ => t('أقل متوسط (٪)', 'Minimum average (%)'),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), // the sheet already lifts above the keyboard
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppSheetHeader(widget.rule == null ? t('شرط جديد', 'New rule') : t('تعديل الشرط', 'Edit rule')),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in ruleTypes)
            AppChoiceChip(label: ruleTypeLabel(k), selected: _type == k, onTap: () => setState(() {
                  _type = k;
                  _err = null;
                  if (k == 'level_courses' && _num.text.trim().isEmpty) _num.text = '100';
                })),
        ]),
        const SizedBox(height: 14),
        if (_type == 'courses_passed') ...[
          CourseSetField(
            title: t('المقررات', 'Courses'),
            help: t('يُحسب «اجتياز» من نتائج الفصول والمقررات المكتملة', '"Passed" comes from term results and completed courses'),
            courses: widget.courses,
            selected: _courses,
            onChanged: () => setState(() {}),
          ),
          if (_courses.length > 1)
            Field(controller: _min, label: t('يكفي اجتياز عدد منها (فارغ = كلها)', 'Enough to pass this many (empty = all)'), keyboard: TextInputType.number, ltr: true),
        ] else ...[
          if (_type == 'level_courses') ...[
            Text(t('أي مستوى؟', 'Which level?'), style: orgText(context, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              AppChoiceChip(label: t('المستوى السابق', 'The level below'), selected: _levelKey == null, onTap: () => setState(() => _levelKey = null)),
              for (final l in widget.levels) AppChoiceChip(label: l.label, selected: _levelKey == l.key, onTap: () => setState(() => _levelKey = l.key)),
            ]),
            const SizedBox(height: 8),
            AppSwitchTile(
              title: t('يشمل مقررات الفصل الصيفي', 'Include summer courses'),
              value: _summer,
              onChanged: (v) => setState(() => _summer = v),
            ),
          ],
          Field(controller: _num, label: _numLabel, keyboard: const TextInputType.numberWithOptions(decimal: true), ltr: true),
          if (_type == 'min_average')
            Text(t('يُحسب من أفضل نتيجة للطالب في كل امتحان بمقررات المؤسسة.', 'Computed from the student\'s best result in each exam of the organization\'s courses.'),
                style: orgText(context, size: 11.5, color: c.textLight)),
        ],
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: AppBanner(icon: Icons.error_outline_rounded, text: _err!, color: c.danger)),
        const SizedBox(height: 14),
        AppPrimaryButton(
          label: t('تم', 'Done'),
          icon: Icons.check_rounded,
          onPressed: () {
            final r = _build();
            if (!r.isValid) return setState(() => _err = t('أكمل الشرط بقيمة صحيحة', 'Complete the rule with a valid value'));
            Navigator.pop(context, r);
          },
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Staff: levels tab
// ═════════════════════════════════════════════════════════════════════════════

class OrgLevelsTab extends StatefulWidget {
  const OrgLevelsTab({super.key});

  @override
  State<OrgLevelsTab> createState() => _OrgLevelsTabState();
}

class _OrgLevelsTabState extends State<OrgLevelsTab> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _data;
  List<LevelDraft> _levels = [];
  List<Map<String, dynamic>>? _courses;
  bool _failed = false, _busy = false;

  String get _a => '${context.read<OrgSession>().base}/academic';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    final coursesF = orgAllCourses(s);
    final r = await orgCall(() => s.api.get('$_a/levels'), quiet: true);
    final courses = await coursesF;
    if (!mounted) return;
    setState(() {
      if (r.ok) _apply(r.map);
      _courses = courses;
      _failed = !r.ok && _data == null;
    });
  }

  void _apply(Map<String, dynamic> m) {
    _data = m;
    _levels = [for (final l in asMapList(m['levels'])) LevelDraft.fromJson(l)];
  }

  List<Map<String, dynamic>> get _programs => asMapList(_data?['programs']);

  Map<String, dynamic> get _courseIndex => {
        ...asMap(_data?['courses']),
        for (final c in _courses ?? const <Map<String, dynamic>>[]) '${c['id']}': c,
      };

  String _programName(int id) {
    final p = _programs.where((x) => asInt(x['id']) == id).firstOrNull;
    return p == null ? '#$id' : '${p['code']}';
  }

  /// PUT the whole list (the server replaces every level). Returns true when saved.
  Future<bool> _save(List<LevelDraft> next, {String? ok}) async {
    final problems = levelProblems(next);
    if (problems.isNotEmpty) {
      toast(problems.first, error: true);
      return false;
    }
    setState(() => _busy = true);
    final r = await orgCall(() => context.read<OrgSession>().api.put('$_a/levels', body: {'levels': [for (final l in next) l.toJson()]}),
        ok: ok ?? t('حُفظت المستويات', 'Levels saved'), quiet: true);
    if (!mounted) return false;
    setState(() {
      _busy = false;
      if (r.ok) _apply(r.map);
    });
    if (!r.ok) toast(_levelError(r), error: true);
    return r.ok;
  }

  String _levelError(OrgCall r) => switch (r.code) {
        'level_in_use' => t('لا يمكن حذف مستوى مسجّل عليه طلاب — انقلهم إلى مستوى آخر أولاً', 'A level with students can\'t be removed — move them to another level first'),
        'no_programs' => t('اختر قسماً واحداً على الأقل أو اجعل المستوى عاماً', 'Pick at least one department or make the level general'),
        'course_twice' => t('المقرر مضاف لأكثر من فصل في المستوى نفسه', 'A course is in more than one term of the same level'),
        'bad_course' => t('بعض المقررات لم تعد ضمن المؤسسة — حدّث الصفحة', 'Some courses are no longer in the organization — refresh'),
        'levels_inherited' => t('المستويات موروثة من المؤسسة الأم', 'Levels are inherited from the parent organization'),
        _ => orgErrorText(r.error!),
      };

  Future<void> _reorder(int from, int to) async {
    if (from == to) return;
    final before = [..._levels];
    setState(() => _levels.insert(to, _levels.removeAt(from)));
    final r = await orgCall(() => context.read<OrgSession>().api.put('$_a/levels/order', body: {'keys': [for (final l in _levels) l.key]}),
        ok: t('تم الترتيب — الأقسام الموروثة تتبع الترتيب الجديد', 'Reordered — inherited departments follow the new order'), quiet: true);
    if (!mounted) return;
    if (r.ok) {
      setState(() => _apply(r.map));
    } else {
      setState(() => _levels = before);
      toast(_levelError(r), error: true);
    }
  }

  Future<void> _edit([int? index]) async {
    final isNew = index == null;
    final draft = isNew
        ? LevelDraft(key: LevelDraft.nextKey(_levels.map((l) => l.key)))
        : LevelDraft.fromJson(_levels[index].toJson()..['students'] = _levels[index].students);
    final saved = await showAppSheet<bool>(
      context,
      (_) => _LevelEditor(
        draft: draft,
        index: isNew ? _levels.length : index,
        all: _levels,
        programs: _programs,
        courses: _courses,
        termDates: asMap(_data?['term_dates']),
        onSave: (d) => _save([
          for (var i = 0; i < _levels.length; i++) i == index ? d : _levels[i],
          if (isNew) d,
        ], ok: isNew ? t('أُضيف المستوى', 'Level added') : null),
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _remove(int index) async {
    final l = _levels[index];
    if (!await appConfirm(context,
        danger: true,
        message: l.students > 0
            ? t('على «${l.label}» ${l.students} طالباً — انقلهم أولاً.', '"${l.label}" has ${l.students} students — move them first.')
            : t('حذف «${l.label}»؟ المستويات التي ترث أقسامه ستتبع المستوى الذي قبله.', 'Remove "${l.label}"? Levels inheriting its departments will follow the one below it.'))) {
      return;
    }
    await _save([..._levels]..removeAt(index), ok: t('حُذف المستوى', 'Level removed'));
  }

  Future<void> _advance() async {
    final r = await orgCall(() => context.read<OrgSession>().api.post('$_a/levels/advance'), quiet: true);
    if (!mounted) return;
    if (!r.ok) return toast(orgErrorText(r.error!), error: true);
    final n = asInt(r.map['advanced']);
    toast(n == 0
        ? t('لا أحد مستوفٍ للانتقال الآن — كل شيء محدّث', 'Nobody is ready to move up right now — all up to date')
        : t('انتقل $n طالباً إلى المستوى التالي وتم إشعارهم 🎉', '$n student(s) moved up and were notified 🎉'));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    if (_data == null) {
      return _failed
          ? AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Couldn\'t load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
          : const AppListSkeleton(items: 4);
    }
    final resolved = resolveLevels(_levels);
    final editable = _data!['editable'] != false;
    final parent = asMap(_data!['inherited_from']);
    final students = _levels.fold<int>(0, (a, l) => a + l.students);
    final auto = _levels.skip(1).where((l) => l.prerequisites.isNotEmpty).length;

    final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppHero(
        title: t('المستويات الدراسية', 'Academic levels'),
        subtitle: t('رتّب الفرق، حدّد أقسام كل مستوى وشروط الانتقال — ينتقل الطالب تلقائياً عند استيفائها.',
            'Order the years, set each level\'s departments and entry rules — students move up on their own once they meet them.'),
        icon: Icons.stairs_rounded,
        stats: [
          AppHeroStat(icon: Icons.layers_rounded, value: '${_levels.length}', label: t('مستويات', 'Levels')),
          AppHeroStat(icon: Icons.groups_rounded, value: '$students', label: t('طلاب', 'Students')),
          AppHeroStat(icon: Icons.auto_mode_rounded, value: '$auto', label: t('انتقال تلقائي', 'Auto move-up')),
        ],
      ),
      const SizedBox(height: 12),
      if (!editable)
        AppBanner(
          icon: Icons.account_tree_rounded,
          color: c.warning,
          text: t('هذه المستويات موروثة من «${orgNameOf(parent)}». حفظ أي تعديل هنا ينشئ نسخة خاصة بمؤسستك.',
              'These levels come from "${orgNameOf(parent)}". Saving a change here creates your own copy.'),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          AppPill(icon: Icons.add_rounded, label: t('مستوى جديد', 'New level'), onTap: _busy ? () {} : () => _edit()),
          if (_levels.length > 1)
            AppPill(icon: Icons.auto_mode_rounded, label: t('تحقق من الانتقال الآن', 'Check move-ups now'), onTap: _advance, color: c.success),
        ]),
      ),
      if (_levels.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(t('اسحب ⠿ لتغيير الترتيب. شروط المستوى = ما يلزم لدخوله.', 'Drag ⠿ to reorder. A level\'s rules = what it takes to enter it.'),
              style: orgText(context, size: 12, color: c.textLight)),
        ),
    ]);

    if (_levels.isEmpty) {
      return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        header,
        AppEmpty(
          icon: Icons.stairs_rounded,
          title: t('لا مستويات بعد', 'No levels yet'),
          message: t('أضف «الفرقة الأولى» ثم الثانية… لكل مستوى فصلان وفصل صيفي اختياري.', 'Add "Year 1", then "Year 2"… each level has two terms and an optional summer term.'),
          actionLabel: t('إضافة أول مستوى', 'Add the first level'),
          onAction: () => _edit(),
        ),
      ]);
    }

    return AppRefresh(
      onRefresh: _load,
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        header: header,
        buildDefaultDragHandles: false,
        itemCount: _levels.length,
        onReorderItem: _busy ? (_, _) {} : _reorder,
        itemBuilder: (ctx, i) => _LevelCard(
          key: ValueKey('lvl_${_levels[i].key}'),
          index: i,
          level: _levels[i],
          resolved: resolved[i],
          sourceLabel: resolved[i].sourceIndex == null ? null : _levels[resolved[i].sourceIndex!].label,
          programName: _programName,
          courses: _courseIndex,
          onTap: () => _edit(i),
          onRemove: () => _remove(i),
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    super.key,
    required this.index,
    required this.level,
    required this.resolved,
    required this.sourceLabel,
    required this.programName,
    required this.courses,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final LevelDraft level;
  final ResolvedLevel resolved;
  final String? sourceLabel;
  final String Function(int) programName;
  final Map<String, dynamic> courses;
  final VoidCallback onTap, onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = level;
    final deptNote = !resolved.inherited
        ? (resolved.isGeneral ? t('كل الأقسام', 'All departments') : t('أقسام مخصصة', 'Custom departments'))
        : (sourceLabel == null ? t('كل الأقسام (افتراضي)', 'All departments (default)') : t('موروث من $sourceLabel', 'Inherited from $sourceLabel'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 12, 12, 12),
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Icon(Icons.drag_indicator_rounded, color: c.textLight),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text('${index + 1}', style: orgText(context, size: 16, w: FontWeight.w800, color: c.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(l.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 15, w: FontWeight.w800))),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  onSelected: (v) => v == 'edit' ? onTap() : onRemove(),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text(t('تعديل', 'Edit'))),
                    PopupMenuItem(value: 'remove', child: Text(t('حذف', 'Remove'), style: TextStyle(color: c.danger))),
                  ],
                ),
              ]),
              Text(t('${l.students} طالب', '${l.students} students'), style: orgText(context, size: 12, color: c.textMedium)),
              const SizedBox(height: 8),
              Row(children: [
                Icon(resolved.inherited ? DirIcons.subArrowLeft : Icons.tune_rounded, size: 16,
                    color: resolved.inherited ? c.textLight : c.primary),
                const SizedBox(width: 4),
                Flexible(child: Text(deptNote, style: orgText(context, size: 12, w: FontWeight.w700, color: resolved.inherited ? c.textMedium : c.primary))),
              ]),
              if (!resolved.isGeneral)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final id in resolved.programIds!)
                      AppBadgePill(programName(id), color: resolved.inherited ? c.textMedium : c.primary, icon: Icons.account_tree_rounded),
                  ]),
                ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final k in levelTermKinds)
                  if (k != 'summer' || l.hasSummer)
                    AppBadgePill('${termKindLabel(k)} · ${l.terms[k]!.length}', icon: Icons.menu_book_rounded,
                        color: l.terms[k]!.isEmpty ? c.warning : c.success),
              ]),
              const SizedBox(height: 6),
              if (index == 0)
                Text(t('أول مستوى — يبدأ منه الطلاب', 'First level — students start here'), style: orgText(context, size: 12, color: c.textLight))
              else if (l.prerequisites.isEmpty)
                Text(t('بلا شروط — الانتقال إليه يدوي فقط', 'No rules — students move here only by hand'),
                    style: orgText(context, size: 12, color: c.warning))
              else
                for (final r in l.prerequisites)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.check_circle_outline_rounded, size: 15, color: c.success),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(r.describe(courseName: (id) => _courseLabel(courses, id)),
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12)),
                      ),
                    ]),
                  ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _LevelEditor extends StatefulWidget {
  const _LevelEditor({
    required this.draft,
    required this.index,
    required this.all,
    required this.programs,
    required this.courses,
    required this.termDates,
    required this.onSave,
  });

  final LevelDraft draft;
  final int index;
  final List<LevelDraft> all;
  final List<Map<String, dynamic>> programs;
  final List<Map<String, dynamic>>? courses;
  final Map<String, dynamic> termDates;
  final Future<bool> Function(LevelDraft) onSave;

  @override
  State<_LevelEditor> createState() => _LevelEditorState();
}

class _LevelEditorState extends State<_LevelEditor> {
  LevelDraft get d => widget.draft;
  late final _ar = TextEditingController(text: d.labelAr);
  late final _en = TextEditingController(text: d.labelEn);
  late final Map<String, Set<int>> _terms = {for (final k in levelTermKinds) k: {...d.terms[k]!}};
  late final Set<int> _progs = {...d.programIds};
  bool _busy = false;

  @override
  void dispose() {
    _ar.dispose();
    _en.dispose();
    super.dispose();
  }

  /// What "inherit" would give this level right now (the level below, as currently saved).
  ResolvedLevel? get _below => widget.index == 0 ? null : resolveLevels(widget.all.take(widget.index).toList()).last;

  String _pname(int id) {
    final p = widget.programs.where((x) => asInt(x['id']) == id).firstOrNull;
    return p == null ? '#$id' : '${p['code']} · ${orgNameOf(p)}';
  }

  Future<void> _save() async {
    d
      ..labelAr = _ar.text
      ..labelEn = _en.text
      ..programIds = _progs.toList();
    for (final k in levelTermKinds) {
      d.terms[k]!
        ..clear()
        ..addAll(_terms[k]!);
    }
    final problems = levelProblems([d]);
    if (problems.isNotEmpty) return toast(problems.first, error: true);
    setState(() => _busy = true);
    final ok = await widget.onSave(d);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Widget _section(BuildContext context, IconData icon, String title, List<Widget> children, {String? help}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: c.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: orgText(context, w: FontWeight.w800))),
          ]),
          if (help != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(help, style: orgText(context, size: 11.5, color: c.textLight))),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final below = _below;
    final inheritText = below == null || below.isGeneral
        ? t('كل الأقسام', 'all departments')
        : below.programIds!.map((id) => _pname(id).split(' · ').first).join('، ');
    final levelsBelow = widget.all.take(widget.index).toList();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader(widget.index >= widget.all.length ? t('مستوى جديد', 'New level') : t('تعديل ${d.label}', 'Edit ${d.label}')),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), // the sheet already lifts above the keyboard
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _section(context, Icons.badge_rounded, t('الاسم', 'Name'), [
              Field(controller: _ar, label: t('الاسم بالعربية (مثلاً: الفرقة الأولى)', 'Arabic name (e.g. الفرقة الأولى)')),
              Field(controller: _en, label: t('الاسم بالإنجليزية (مثلاً: Year 1)', 'English name (e.g. Year 1)'), ltr: true),
              Text(t('المفتاح الثابت: ${d.key}', 'Fixed key: ${d.key}'), style: orgText(context, size: 11.5, color: c.textLight)),
            ]),
            _section(
              context,
              Icons.account_tree_rounded,
              t('الأقسام المتاحة في هذا المستوى', 'Departments open at this level'),
              help: t('ما تختاره هنا يصبح الافتراضي لكل المستويات الأعلى التي «ترث».', 'Your choice becomes the default for every higher level that "inherits".'),
              [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  AppChoiceChip(
                    label: widget.index == 0 ? t('افتراضي (كل الأقسام)', 'Default (all)') : t('يرث: $inheritText', 'Inherit: $inheritText'),
                    icon: DirIcons.subArrowLeft,
                    selected: d.programs == 'inherit',
                    onTap: () => setState(() => d.programs = 'inherit'),
                  ),
                  AppChoiceChip(label: t('عام — كل الأقسام', 'General — all'), icon: Icons.public_rounded, selected: d.programs == 'general',
                      onTap: () => setState(() => d.programs = 'general')),
                  AppChoiceChip(label: t('أقسام محددة', 'Specific departments'), icon: Icons.tune_rounded, selected: d.programs == 'custom',
                      onTap: () => setState(() {
                            d.programs = 'custom';
                            if (_progs.isEmpty && below != null && !below.isGeneral) _progs.addAll(below.programIds!);
                          })),
                ]),
                if (d.programs == 'custom') ...[
                  const SizedBox(height: 10),
                  if (widget.programs.isEmpty)
                    Text(t('لا أقسام علمية بعد — أنشئها من تبويب «الأقسام العلمية».', 'No academic departments yet — create them in "Departments".'),
                        style: orgText(context, size: 12, color: c.warning))
                  else
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final p in widget.programs)
                        FilterChip(
                          label: Text(_pname(asInt(p['id'])), style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5)),
                          selected: _progs.contains(asInt(p['id'])),
                          onSelected: (on) => setState(() => on ? _progs.add(asInt(p['id'])) : _progs.remove(asInt(p['id']))),
                        ),
                    ]),
                ],
              ],
            ),
            _section(
              context,
              Icons.rule_rounded,
              t('شروط دخول هذا المستوى', 'Rules to enter this level'),
              help: widget.index == 0
                  ? t('المستوى الأول لا يحتاج شروطاً عادةً.', 'The first level usually needs no rules.')
                  : t('ينتقل الطالب تلقائياً عند استيفاء كل الشروط. بلا شروط = انتقال يدوي فقط.',
                      'Students move up automatically once every rule is met. No rules = moved by hand only.'),
              [
                PrereqRulesEditor(
                  rules: d.prerequisites,
                  courses: widget.courses,
                  levels: levelsBelow,
                  emptyText: t('لا شروط', 'No rules'),
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
            _section(context, Icons.calendar_view_week_rounded, t('الفصول والمقررات', 'Terms & courses'), [
              for (final k in levelTermKinds)
                if (k != 'summer' || d.hasSummer) ...[
                  CourseSetField(
                    title: termKindLabel(k),
                    help: _termHelp(k),
                    courses: widget.courses,
                    selected: _terms[k]!,
                    blocked: {
                      for (final o in levelTermKinds)
                        if (o != k) for (final id in _terms[o]!) id: t('في ${termKindLabel(o)}', 'In ${termKindLabel(o)}')
                    },
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                ],
              AppSwitchTile(
                title: t('فصل صيفي (اختياري)', 'Summer term (optional)'),
                subtitle: t('فصل ثالث قصير بمقرراته الخاصة', 'A short third term with its own courses'),
                icon: Icons.wb_sunny_rounded,
                value: d.hasSummer,
                onChanged: (v) => setState(() => d.hasSummer = v),
              ),
            ]),
            AppPrimaryButton(label: t('حفظ المستوى', 'Save level'), icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _save),
          ]),
        ),
      ),
    ]);
  }

  String? _termHelp(String kind) {
    final d = asMap(widget.termDates[kind]);
    if (d.isEmpty) return t('لا توجد تواريخ لهذا الفصل في التقويم بعد', 'No dates for this term in the calendar yet');
    return '${d['year_label'] ?? ''} · ${shortDate('${d['start_date']}')} → ${shortDate('${d['end_date']}')}';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Student: my level
// ═════════════════════════════════════════════════════════════════════════════

/// "My academic path" — levels part. Hidden when the organization has no levels.
class MyLevelCard extends StatefulWidget {
  const MyLevelCard({super.key, required this.orgId});
  final int orgId;

  @override
  State<MyLevelCard> createState() => _MyLevelCardState();
}

class _MyLevelCardState extends State<MyLevelCard> {
  Map<String, dynamic>? _m;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await orgCall(() => OrgApi.i.api.get('$_pub/${widget.orgId}/my-level'), quiet: true);
    if (!mounted) return;
    setState(() {
      _m = r.ok ? r.map : null;
      _loaded = true;
    });
    final moved = (r.map['just_advanced'] as List?) ?? const [];
    if (r.ok && moved.isNotEmpty) {
      toast(t('مبروك! انتقلت إلى ${asMap(r.map['current'])['label_ar'] ?? ''} 🎉', 'Congratulations! You moved up to ${asMap(r.map['current'])['label_en'] ?? ''} 🎉'));
    }
  }

  String _lname(Map<String, dynamic> l) {
    final ar = '${l['label_ar'] ?? ''}', en = '${l['label_en'] ?? ''}';
    final v = t(ar.isNotEmpty ? ar : en, en.isNotEmpty ? en : ar);
    return v.isEmpty ? t('المستوى ${l['key']}', 'Level ${l['key']}') : v;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!_loaded) return const SizedBox(height: 160, child: AppListSkeleton(items: 2, withAvatar: false));
    final m = _m;
    final levels = asMapList(m?['levels']);
    if (m == null || levels.isEmpty) return const SizedBox.shrink();
    final courses = asMap(m['courses']);
    if (m['placed'] != true) {
      return AppBanner(
        icon: Icons.info_outline_rounded,
        color: c.warning,
        text: t('لم تُسجّل المؤسسة مستواك الدراسي بعد — تواصل مع شؤون الطلاب.', 'Your organization hasn\'t recorded your level yet — contact student affairs.'),
      );
    }
    final cur = asMap(m['current']);
    final next = asMap(m['next']);
    final rules = [for (final r in asMapList(next['rules'])) RuleResult.fromJson(r)];
    final stats = asMap(m['stats']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppSectionTitle(t('مستواك الدراسي', 'Your level'), subtitle: _lname(cur)),
      const SizedBox(height: 8),
      // the ladder
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < levels.length; i++) ...[
            if (i > 0) Container(width: 18, height: 2, color: levels[i]['status'] == 'upcoming' ? c.divider : c.success),
            _LadderStep(label: _lname(levels[i]), status: '${levels[i]['status']}'),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        child: next.isEmpty
            ? Row(children: [
                Icon(Icons.emoji_events_rounded, color: c.success),
                const SizedBox(width: 10),
                Expanded(child: Text(t('أنت في أعلى مستوى 🎓', 'You\'re at the top level 🎓'), style: orgText(context, w: FontWeight.w800))),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  AppRing(value: next['auto'] == true ? asInt(next['percent']).toDouble() : null, label: t('نحو التالي', 'To next'), size: 72),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('المستوى التالي: ${_lname(next)}', 'Next: ${_lname(next)}'), style: orgText(context, w: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        next['auto'] != true
                            ? t('تنقلك المؤسسة إليه — لا شروط تلقائية', 'Your organization moves you there — no automatic rules')
                            : next['met'] == true
                                ? t('استوفيت كل الشروط — سيتم نقلك الآن', 'All rules met — you\'re being moved up')
                                : t('تنتقل تلقائياً عند استيفاء الشروط', 'You move up automatically once these are met'),
                        style: orgText(context, size: 12, color: c.textMedium),
                      ),
                    ]),
                  ),
                ]),
                if (rules.isNotEmpty) const SizedBox(height: 10),
                for (final r in rules) _RuleRow(result: r, courses: courses),
              ]),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppStatChip(icon: Icons.task_alt_rounded, value: '${stats['passed_courses'] ?? 0}', label: t('مقرر مجتاز', 'courses passed')),
        AppStatChip(icon: Icons.schedule_rounded, value: '${stats['hours'] ?? 0}', label: t('ساعة', 'hours')),
        if (stats['average'] != null) AppStatChip(icon: Icons.insights_rounded, value: '${stats['average']}%', label: t('المتوسط', 'average')),
      ]),
      for (final term in asMapList(m['terms'])) ...[
        const SizedBox(height: 12),
        _TermCard(term: term),
      ],
      if (asMapList(m['programs']).isNotEmpty) ...[
        const SizedBox(height: 16),
        AppSectionTitle(t('الأقسام المتاحة في مستواك', 'Departments open at your level'),
            subtitle: t('للتسجيل في مقررات قسم يلزم استيفاء متطلباته', 'A department\'s courses need its prerequisites')),
        const SizedBox(height: 8),
        for (final p in asMapList(m['programs'])) _ProgramReadiness(p: p, courses: courses),
      ],
      if (asMapList(m['history']).isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final h in asMapList(m['history']).take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(h['via'] == 'auto' ? Icons.auto_mode_rounded : Icons.person_rounded, size: 15, color: c.textLight),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${h['via'] == 'auto' ? t('انتقال تلقائي', 'Moved up automatically') : t('نقل من المؤسسة', 'Moved by your organization')} → ${_lname(levels.firstWhere((l) => l['key'] == h['to'], orElse: () => {'key': h['to']}))} · ${orgParseUtc(h['at']) == null ? '—' : AppTime.date(orgParseUtc(h['at'])!)}',
                  style: orgText(context, size: 12, color: c.textMedium),
                ),
              ),
            ]),
          ),
      ],
    ]);
  }
}

class _LadderStep extends StatelessWidget {
  const _LadderStep({required this.label, required this.status});
  final String label, status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = switch (status) { 'done' => c.success, 'current' => c.primary, _ => c.textLight };
    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: col.withValues(alpha: status == 'current' ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: status == 'current' ? col : Colors.transparent, width: 1.4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(status == 'done' ? Icons.check_circle_rounded : (status == 'current' ? Icons.my_location_rounded : Icons.lock_outline_rounded),
            size: 15, color: col),
        const SizedBox(width: 4),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, w: FontWeight.w700, color: col))),
      ]),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.result, required this.courses});
  final RuleResult result;
  final Map<String, dynamic> courses;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = result;
    final col = r.met ? c.success : (r.noData ? c.textLight : c.warning);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(r.met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: col),
          const SizedBox(width: 8),
          Expanded(child: Text(r.rule.describe(courseName: (id) => _courseLabel(courses, id)), maxLines: 3, overflow: TextOverflow.ellipsis,
              style: orgText(context, size: 12.5, w: FontWeight.w600))),
          const SizedBox(width: 8),
          Text(r.progressText, style: orgText(context, size: 12, w: FontWeight.w800, color: col)),
        ]),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 26, top: 4),
          child: AppProgressBar(value: r.progress * 100, color: col, height: 5),
        ),
        if (!r.met && r.missing.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 26, top: 4),
            child: Text(t('متبقٍ: ', 'Still to pass: ') + r.missing.take(4).map((id) => _courseLabel(courses, id)).join('، ') + (r.missing.length > 4 ? ' …' : ''),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 11.5, color: c.textMedium)),
          ),
      ]),
    );
  }
}

class _TermCard extends StatelessWidget {
  const _TermCard({required this.term});
  final Map<String, dynamic> term;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dates = asMap(term['dates']);
    final courses = asMapList(term['courses']);
    final done = courses.where((x) => x['passed'] == true).length;
    final status = '${dates['status'] ?? ''}';
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(term['kind'] == 'summer' ? Icons.wb_sunny_rounded : Icons.menu_book_rounded, color: c.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(t('${term['label_ar']}', '${term['label_en']}'), style: orgText(context, w: FontWeight.w800))),
          if (courses.isNotEmpty) AppBadgePill('$done/${courses.length}', color: done == courses.length ? c.success : c.primary),
        ]),
        if (dates.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${shortDate('${dates['start_date']}')} → ${shortDate('${dates['end_date']}')}'
              '${status == 'current' ? t(' · جارٍ الآن', ' · in progress') : status == 'upcoming' ? t(' · قادم', ' · upcoming') : ''}',
              style: orgText(context, size: 12, color: c.textMedium),
            ),
          ),
        const SizedBox(height: 6),
        if (courses.isEmpty)
          Text(t('لم تُحدَّد مقررات بعد', 'No courses set yet'), style: orgText(context, size: 12, color: c.textLight))
        else
          for (final x in courses)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Icon(x['passed'] == true ? Icons.check_circle_rounded : Icons.circle_outlined, size: 16, color: x['passed'] == true ? c.success : c.textLight),
                const SizedBox(width: 8),
                Expanded(child: Text(orgCourseName(x), maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12.5))),
              ]),
            ),
      ]),
    );
  }
}

class _ProgramReadiness extends StatelessWidget {
  const _ProgramReadiness({required this.p, required this.courses});
  final Map<String, dynamic> p;
  final Map<String, dynamic> courses;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final met = p['met'] == true;
    final rules = [for (final r in asMapList(p['rules'])) RuleResult.fromJson(r)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AppBadgePill('${p['code']}', color: c.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(orgNameOf(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800))),
            Icon(met ? Icons.lock_open_rounded : Icons.lock_rounded, size: 18, color: met ? c.success : c.warning),
          ]),
          Text(
            met
                ? t('مستوفٍ — يمكنك التسجيل في مقرراته', 'Ready — you can join its courses')
                : t('ينقصك ${rules.where((r) => !r.met).length} من الشروط', '${rules.where((r) => !r.met).length} rule(s) still to meet'),
            style: orgText(context, size: 12, color: met ? c.success : c.textMedium),
          ),
          if (!met) for (final r in rules) _RuleRow(result: r, courses: courses),
        ]),
      ),
    );
  }
}

/// Friendly "why can't I join this course" sheet. Returns after the student closes it.
/// Also the roadmap purchase (`roadmap_prerequisites`): one card per blocked course with its own reasons.
Future<void> showEnrollBlock(BuildContext context, Map<String, dynamic> reason) => showAppSheet<void>(context, (ctx) {
      final c = ctx.colors;
      final names = asMap(reason['course_names']);
      final roadmap = reason['code'] == 'roadmap_prerequisites';
      final blocked = asMapList(reason['blocked']);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppSheetHeader(roadmap ? t('خطوة قبل شراء المسار', 'One step before you buy this roadmap') : t('خطوة قبل التسجيل', 'One step before you join')),
          if (!roadmap)
            ..._blockDetails(ctx, reason, names)
          else ...[
            AppBanner(
              icon: Icons.route_rounded,
              color: c.warning,
              text: t('${blocked.length} من مقررات هذا المسار لها متطلبات لم تستوفها بعد — لن يُخصم أي مبلغ قبل استيفائها.',
                  '${blocked.length} course(s) in this roadmap have requirements you haven\'t met yet — nothing is charged until they\'re met.'),
            ),
            const SizedBox(height: 8),
            for (final b in blocked)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      if ((b['code'] ?? '').toString().isNotEmpty) ...[AppBadgePill('${b['code']}', color: c.primary), const SizedBox(width: 8)],
                      Expanded(
                        child: Text(t('${b['name_ar'] ?? b['name_en']}', '${b['name_en'] ?? b['name_ar']}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(ctx, w: FontWeight.w800)),
                      ),
                      Icon(Icons.lock_rounded, size: 18, color: c.warning),
                    ]),
                    const SizedBox(height: 6),
                    ..._blockDetails(ctx, asMap(b['reason']), {...names, ...asMap(asMap(b['reason'])['course_names'])}),
                  ]),
                ),
              ),
          ],
          const SizedBox(height: 16),
          AppPrimaryButton(label: t('حسناً', 'Got it'), onPressed: () => Navigator.pop(ctx)),
        ]),
      );
    });

List<Widget> _blockDetails(BuildContext ctx, Map<String, dynamic> reason, Map<String, dynamic> names) {
  final c = ctx.colors;
  final prog = asMap(reason['program']);
  final rules = [for (final r in asMapList(reason['unmet'])) RuleResult.fromJson(r)];
  final missing = ((reason['missing_course_ids'] as List?) ?? const []).map((e) => asInt(e)).toList();
  return [
    AppBanner(
      icon: Icons.lock_clock_rounded,
      color: c.warning,
      text: reason['code'] == 'department_prerequisites'
          ? t('هذا المقرر تابع لقسم ${prog['code'] ?? ''} — استوفِ متطلبات القسم أولاً، حتى لو انتقلت لمستوى أعلى.',
              'This course belongs to the ${prog['code'] ?? ''} department — meet its prerequisites first, even if your level moved up.')
          : t('أكمل المقررات السابقة المطلوبة لهذا المقرر أولاً.', 'Finish the courses this one requires first.'),
    ),
    const SizedBox(height: 8),
    for (final r in rules) _RuleRow(result: r, courses: names),
    for (final id in missing)
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Icon(Icons.radio_button_unchecked_rounded, size: 18, color: c.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(_courseLabel(names, id), style: orgText(ctx, size: 12.5, w: FontWeight.w600))),
        ]),
      ),
  ];
}
