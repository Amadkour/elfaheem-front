// lib/features/courses/course_profile/course_page_sheets.dart
//
// The course page's editors (D-1090): the teacher's course rules (the three ready-made rules + their own list),
// section groups and who is in which (plus, for a personal course, how students get one), and a student's one-time
// section pick. Each opens with `showAppSheet` and calls [onChanged] after a successful write so the page reloads
// its profile (the Overview reads the `page` block again).
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_page_api.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_page_models.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_screen.dart' show cpErrorMessage;

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Future<bool> _run(Future<void> Function() fn, {String? done}) async {
  try {
    await fn();
    if (done != null) showAppNotice(done);
    return true;
  } catch (e) {
    showAppNotice(cpErrorMessage(e), error: true);
    return false;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Course rules
// ═════════════════════════════════════════════════════════════════════════════

Future<void> showCourseRulesSheet(BuildContext context, {required int courseId, required VoidCallback onChanged}) =>
    showAppSheet<void>(context, (_) => _RulesSheet(api: CoursePageApi(courseId), onChanged: onChanged));

class _RulesSheet extends StatefulWidget {
  const _RulesSheet({required this.api, required this.onChanged});

  final CoursePageApi api;
  final VoidCallback onChanged;

  @override
  State<_RulesSheet> createState() => _RulesSheetState();
}

class _RulesSheetState extends State<_RulesSheet> {
  CourseRules? _r;
  String? _error;
  bool _busy = false;
  final _absence = TextEditingController();
  final _late = TextEditingController();
  final _newRule = TextEditingController();
  final List<(TextEditingController, TextEditingController)> _grades = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_absence, _late, _newRule]) {
      c.dispose();
    }
    for (final g in _grades) {
      g.$1.dispose();
      g.$2.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.rules();
      if (!mounted) return;
      setState(() {
        _r = r;
        _error = null;
        _absence.text = r.absenceLimit?.toString() ?? '';
        _late.text = r.latePolicy ?? '';
        for (final g in _grades) {
          g.$1.dispose();
          g.$2.dispose();
        }
        _grades
          ..clear()
          ..addAll([for (final g in r.grades) (TextEditingController(text: g.label), TextEditingController(text: '${g.weight}'))]);
      });
    } catch (e) {
      if (mounted) setState(() => _error = cpErrorMessage(e));
    }
  }

  int get _gradeTotal => _grades.fold(0, (s, g) => s + (int.tryParse(g.$2.text.trim()) ?? 0));

  Future<void> _savePresets() async {
    final grades = [
      for (final g in _grades)
        if (g.$1.text.trim().isNotEmpty) CourseGradePart(g.$1.text.trim(), int.tryParse(g.$2.text.trim()) ?? 0),
    ];
    if (grades.isNotEmpty && _gradeTotal != 100) {
      showAppNotice(_t('مجموع توزيع الدرجات يجب أن يكون 100', 'The grade breakdown must add up to 100'), error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await _run(
      () => widget.api.savePresets(absenceLimit: int.tryParse(_absence.text.trim()), grades: grades, latePolicy: _late.text),
      done: _t('حُفظت القواعد', 'Rules saved'),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onChanged();
      await _load();
    }
  }

  Future<void> _act(Future<void> Function() fn) async {
    setState(() => _busy = true);
    final ok = await _run(fn);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onChanged();
      await _load();
    }
  }

  Future<void> _edit(CourseRuleItem it) async {
    final ctrl = TextEditingController(text: it.text);
    final saved = await showAppDialog<bool>(
      context,
      title: _t('تعديل القاعدة', 'Edit the rule'),
      body: AppField(controller: ctrl, label: _t('القاعدة', 'Rule'), maxLines: 3, autofocus: true),
      actions: [
        AppButton(label: 'cancel'.tr, variant: AppButtonVariant.ghost, onPressed: () => Navigator.pop(context, false)),
        AppButton(label: _t('حفظ', 'Save'), onPressed: () => Navigator.pop(context, true)),
      ],
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (saved == true && text.isNotEmpty && text != it.text) await _act(() => widget.api.editRule(it.id, text));
  }

  Future<void> _move(int index, int by) async {
    final items = [...?_r?.items];
    final to = index + by;
    if (to < 0 || to >= items.length) return;
    final it = items.removeAt(index);
    items.insert(to, it);
    await _act(() => widget.api.reorderRules([for (final x in items) x.id]));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = _r;
    final children = <Widget>[];
    if (_error != null) {
      children.add(AppEmpty(icon: Icons.error_outline_rounded, title: _error!, actionLabel: _t('إعادة المحاولة', 'Retry'), onAction: _load));
    } else if (r == null) {
      children.add(const AppListSkeleton(items: 3));
    } else {
      final total = _gradeTotal;
      children.addAll([
        Text(_t('القواعد الجاهزة (اختيارية)', 'Ready-made rules (optional)'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.sm),
        AppField(
          controller: _absence,
          label: _t('حد الغياب (عدد المرات)', 'Absence limit (times)'),
          hint: _t('اتركه فارغًا لإيقافه', 'Leave empty to turn it off'),
          keyboard: TextInputType.number,
          ltr: true,
        ),
        const SizedBox(height: AppSpace.sm),
        Row(children: [
          Expanded(child: Text(_t('توزيع الدرجات', 'Grade breakdown'), style: AppType.label(context))),
          if (_grades.isNotEmpty)
            Text('$total / 100', style: AppType.meta(context).copyWith(color: total == 100 ? c.primary : c.danger, fontWeight: FontWeight.w700)),
        ]),
        for (final (i, g) in _grades.indexed)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Row(children: [
              Expanded(flex: 3, child: AppField(controller: g.$1, label: _t('البند', 'Part'), onChanged: (_) => setState(() {}))),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                flex: 2,
                child: AppField(controller: g.$2, label: '%', keyboard: TextInputType.number, ltr: true, onChanged: (_) => setState(() {})),
              ),
              AppIconButton(
                icon: Icons.close_rounded,
                tooltip: _t('حذف البند', 'Remove the part'),
                onPressed: () => setState(() {
                  final x = _grades.removeAt(i);
                  x.$1.dispose();
                  x.$2.dispose();
                }),
              ),
            ]),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            label: _t('إضافة بند', 'Add a part'),
            icon: Icons.add_rounded,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => setState(() => _grades.add((TextEditingController(), TextEditingController()))),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        AppField(controller: _late, label: _t('التسليم المتأخر', 'Late work'), hint: _t('مثال: يُخصم 10% عن كل يوم تأخير', 'e.g. 10% off for each late day'), maxLines: 3),
        const SizedBox(height: AppSpace.sm),
        AppButton(label: _t('حفظ القواعد الجاهزة', 'Save the ready-made rules'), busy: _busy, expand: true, onPressed: _busy ? null : _savePresets),
        const SizedBox(height: AppSpace.lg),
        Text(_t('قواعدك لهذا الكورس', 'Your rules for this course'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        if (r.items.isEmpty)
          Text(_t('لم تضف قواعد بعد.', 'No rules added yet.'), style: AppType.meta(context).copyWith(color: c.textLight)),
        for (final (i, it) in r.items.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
            child: Row(children: [
              Expanded(child: Text('${i + 1}. ${it.text}', style: AppType.body(context))),
              AppIconButton(icon: Icons.arrow_upward_rounded, tooltip: _t('لأعلى', 'Move up'), onPressed: _busy || i == 0 ? null : () => _move(i, -1)),
              AppIconButton(
                icon: Icons.arrow_downward_rounded,
                tooltip: _t('لأسفل', 'Move down'),
                onPressed: _busy || i == r.items.length - 1 ? null : () => _move(i, 1),
              ),
              AppIconButton(icon: Icons.edit_rounded, tooltip: _t('تعديل', 'Edit'), onPressed: _busy ? null : () => _edit(it)),
              AppIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: _t('حذف', 'Delete'),
                onPressed: _busy
                    ? null
                    : () async {
                        if (await appConfirm(context, message: _t('حذف هذه القاعدة؟', 'Delete this rule?'), danger: true)) {
                          await _act(() => widget.api.deleteRule(it.id));
                        }
                      },
              ),
            ]),
          ),
        const SizedBox(height: AppSpace.xs),
        AppField(controller: _newRule, label: _t('قاعدة جديدة', 'New rule'), maxLines: 2),
        const SizedBox(height: AppSpace.xs),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AppButton(
            label: _t('إضافة القاعدة', 'Add the rule'),
            icon: Icons.add_rounded,
            onPressed: _busy
                ? null
                : () async {
                    final text = _newRule.text.trim();
                    if (text.isEmpty) return;
                    await _act(() => widget.api.addRule(text));
                    if (mounted) _newRule.clear();
                  },
          ),
        ),
      ]);
    }
    return AppSheetContent(title: _t('قواعد الكورس', 'Course rules'), icon: Icons.gavel_rounded, children: children);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Sections (staff)
// ═════════════════════════════════════════════════════════════════════════════

Future<void> showCourseSectionsSheet(BuildContext context, {required int courseId, required VoidCallback onChanged}) =>
    showAppSheet<void>(context, (_) => _SectionsSheet(api: CoursePageApi(courseId), onChanged: onChanged));

class _SectionsSheet extends StatefulWidget {
  const _SectionsSheet({required this.api, required this.onChanged});

  final CoursePageApi api;
  final VoidCallback onChanged;

  @override
  State<_SectionsSheet> createState() => _SectionsSheetState();
}

class _SectionsSheetState extends State<_SectionsSheet> {
  CourseSections? _s;
  String? _error;
  bool _busy = false;

  /// The group list being edited: (number or null for a new one, label).
  final List<(int?, TextEditingController)> _groups = [];

  /// Changed assignments: student id → group (null = none).
  final Map<int, int?> _changed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final g in _groups) {
      g.$2.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.sections();
      if (!mounted) return;
      setState(() {
        _s = s;
        _error = null;
        _changed.clear();
        for (final g in _groups) {
          g.$2.dispose();
        }
        _groups
          ..clear()
          ..addAll([for (final g in s.groups) (g.groupNo, TextEditingController(text: g.label))]);
      });
    } catch (e) {
      if (mounted) setState(() => _error = cpErrorMessage(e));
    }
  }

  Future<void> _act(Future<void> Function() fn, String done) async {
    setState(() => _busy = true);
    final ok = await _run(fn, done: done);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onChanged();
      await _load();
    }
  }

  int? _groupOf(CourseSectionStudent st) => _changed.containsKey(st.person.id) ? _changed[st.person.id] : st.groupNo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = _s;
    final ar = AppConfig.lang == 'ar';
    final children = <Widget>[];
    if (_error != null) {
      children.add(AppEmpty(icon: Icons.error_outline_rounded, title: _error!, actionLabel: _t('إعادة المحاولة', 'Retry'), onAction: _load));
    } else if (s == null) {
      children.add(const AppListSkeleton(items: 4));
    } else {
      final editable = s.canEdit && !s.fromRegistrar;
      // how students get a section
      children.add(Text(_t('كيف يحصل الطالب على سكشن', 'How students get a section'), style: AppType.section(context)));
      children.add(const SizedBox(height: AppSpace.xs));
      if (s.modeSource == 'org') {
        children.add(Text(
          s.studentPicks
              ? _t('يختار كل طالب سكشنه مرة واحدة (تحدده إدارة المؤسسة).', "Each student picks once (set by the organization's admin).")
              : _t('يوزّع المحاضر الطلاب (تحدده إدارة المؤسسة).', "The teacher assigns students (set by the organization's admin)."),
          style: AppType.meta(context).copyWith(color: c.textLight),
        ));
      } else {
        children.add(AppTabs(
          index: s.studentPicks ? 1 : 0,
          onChanged: _busy || !editable
              ? (_) {}
              : (i) => _act(() => widget.api.setMode(i == 1 ? 'student_picks_once' : 'teacher_assigns'), _t('حُفظ', 'Saved')),
          items: [AppTabItem(_t('المحاضر يوزّع', 'I assign')), AppTabItem(_t('الطالب يختار مرة', 'Students pick once'))],
        ));
      }
      children.add(const SizedBox(height: AppSpace.lg));
      // the groups
      children.add(Text(_t('السكاشن', 'Sections'), style: AppType.section(context)));
      if (s.fromRegistrar) {
        children.add(Text(
          _t('السكاشن وطلابها من تسجيل المؤسسة، وتُعدَّل هناك.', "Sections and their students come from the organization's registration and are edited there."),
          style: AppType.meta(context).copyWith(color: c.textLight),
        ));
      }
      for (final (i, g) in _groups.indexed) {
        final count = s.group(g.$1)?.students;
        children.add(Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Row(children: [
            Expanded(
              child: AppField(
                controller: g.$2,
                enabled: editable,
                label: g.$1 == null ? _t('سكشن جديد', 'New section') : _t('سكشن ${g.$1}', 'Section ${g.$1}'),
                helper: count == null ? null : _t('$count طالب', '$count students'),
              ),
            ),
            if (editable)
              AppIconButton(
                icon: Icons.close_rounded,
                tooltip: _t('حذف السكشن', 'Remove the section'),
                onPressed: () => setState(() {
                  final x = _groups.removeAt(i);
                  x.$2.dispose();
                }),
              ),
          ]),
        ));
      }
      if (editable) {
        children.add(Row(children: [
          AppButton(
            label: _t('إضافة سكشن', 'Add a section'),
            icon: Icons.add_rounded,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => setState(() => _groups.add((null, TextEditingController()))),
          ),
          const Spacer(),
          AppButton(
            label: _t('حفظ السكاشن', 'Save sections'),
            size: AppButtonSize.sm,
            busy: _busy,
            onPressed: _busy
                ? null
                : () => _act(
                    () => widget.api.saveGroups([
                      for (final g in _groups) (groupNo: g.$1, label: g.$2.text.trim().isEmpty ? null : g.$2.text.trim(), taUserId: s.group(g.$1)?.ta?.id),
                    ]),
                    _t('حُفظت السكاشن', 'Sections saved'),
                  ),
          ),
        ]));
      }
      // who is in which
      if (s.groups.isNotEmpty && s.students.isNotEmpty) {
        children.add(const SizedBox(height: AppSpace.lg));
        final unassigned = s.students.where((st) => _groupOf(st) == null).toList();
        children.add(Row(children: [
          Expanded(child: Text(_t('الطلاب', 'Students'), style: AppType.section(context))),
          if (unassigned.isNotEmpty)
            Text(_t('${unassigned.length} بلا سكشن', '${unassigned.length} without a section'), style: AppType.meta(context).copyWith(color: c.accent2)),
        ]));
        if (editable && unassigned.isNotEmpty) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: AppDropdown<int>(
              hint: Text(_t('ضع كل من بلا سكشن في…', 'Put everyone without a section in…')),
              items: [for (final g in s.groups) DropdownMenuItem(value: g.groupNo, child: Text(g.labelFor(ar)))],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  for (final st in unassigned) {
                    _changed[st.person.id] = v;
                  }
                });
              },
            ),
          ));
        }
        for (final st in s.students) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Row(children: [
              Expanded(child: Text(st.person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: AppDropdown<int>(
                  enabled: editable,
                  value: _groupOf(st) ?? 0,
                  items: [
                    DropdownMenuItem(value: 0, child: Text(_t('بلا سكشن', 'No section'))),
                    for (final g in s.groups) DropdownMenuItem(value: g.groupNo, child: Text(g.labelFor(ar))),
                  ],
                  onChanged: (v) => setState(() => _changed[st.person.id] = (v == null || v == 0) ? null : v),
                ),
              ),
            ]),
          ));
        }
        if (editable) {
          children.add(const SizedBox(height: AppSpace.sm));
          children.add(AppButton(
            label: _t('حفظ التوزيع', 'Save the assignments'),
            expand: true,
            busy: _busy,
            onPressed: _busy || _changed.isEmpty ? null : () => _act(() => widget.api.assign(Map.of(_changed)), _t('حُفظ التوزيع', 'Assignments saved')),
          ));
        }
      }
    }
    return AppSheetContent(title: _t('السكاشن', 'Sections'), icon: Icons.groups_2_rounded, children: children);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// A student's one-time pick
// ═════════════════════════════════════════════════════════════════════════════

Future<void> showPickSectionSheet(
  BuildContext context, {
  required int courseId,
  required List<CourseSectionGroup> groups,
  required VoidCallback onChanged,
}) =>
    showAppSheet<void>(context, (_) => _PickSheet(api: CoursePageApi(courseId), groups: groups, onChanged: onChanged));

class _PickSheet extends StatefulWidget {
  const _PickSheet({required this.api, required this.groups, required this.onChanged});

  final CoursePageApi api;
  final List<CourseSectionGroup> groups;
  final VoidCallback onChanged;

  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  int? _choice;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    return AppSheetContent(
      title: _t('اختر سكشنك', 'Pick your section'),
      icon: Icons.how_to_reg_rounded,
      children: [
        Text(
          _t('تختار مرة واحدة فقط، ويستطيع المحاضر تغييرها لاحقًا.', 'You pick once; the teacher can change it later.'),
          style: AppType.meta(context).copyWith(color: c.textLight),
        ),
        const SizedBox(height: AppSpace.sm),
        for (final g in widget.groups)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: AppCard(
              onTap: () => setState(() => _choice = g.groupNo),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
              child: Row(children: [
                Icon(_choice == g.groupNo ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: c.primary, size: AppIconSize.md),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g.labelFor(ar), style: AppType.row(context)),
                    if (g.ta != null) Text(g.ta!.name, style: AppType.meta(context).copyWith(color: c.textLight)),
                  ]),
                ),
              ]),
            ),
          ),
        const SizedBox(height: AppSpace.sm),
        AppButton(
          label: _t('تأكيد', 'Confirm'),
          expand: true,
          busy: _busy,
          onPressed: _choice == null || _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final ok = await _run(() => widget.api.pick(_choice!), done: _t('تم اختيار سكشنك', 'Your section is set'));
                  if (!context.mounted) return;
                  setState(() => _busy = false);
                  if (ok) {
                    widget.onChanged();
                    Navigator.of(context).maybePop();
                  }
                },
        ),
      ],
    );
  }
}
