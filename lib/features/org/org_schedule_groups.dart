// lib/features/org/org_schedule_groups.dart — the students of each lecture / lab group of a term's course.
//
//   openStudentGroups   course picker · groups with their exact students · distribute (alphabetical / by student
//                       code) · move one student (the server re-checks time clashes and capacity) · roster export ·
//                       tap a student → their group in every course of the term
//   Server: GET|POST /orgs/{o}/registrar/terms/{tid}/groups/{cid}[/distribute] · POST registrations/{rid}/group ·
//           GET terms/{tid}/students/{uid}/groups (services/organization/schedule_groups.py)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart' show RowCard;
import 'org_providers.dart';
import 'org_timetable_parts.dart' show courseName;
import 'org_ui.dart';
import 'org_v3.dart';

String groupLabel(Map<String, dynamic> g) =>
    '${g['kind'] == 'lab' ? t('معمل', 'Lab') : t('نظري', 'Theory')} ${g['group_no']}';

/// Roster rows for the export: one per student, grouped by group.
List<Map<String, Object?>> rosterRows(Map<String, dynamic> data) => [
      for (final g in asMapList(data['groups']))
        for (final s in asMapList(g['students']))
          {'group': groupLabel(g), 'name': '${asMap(s['student'])['name'] ?? ''}', 'code': s['student_code'] ?? ''},
    ];

Future<void> openStudentGroups(BuildContext context, OrgScheduleProvider p) {
  final term = p.schedule?['term_id'];
  if (term == null) {
    toast(t('اربط الجدول بفصل دراسي أولاً (إعدادات الجدول).', 'Link the timetable to a term first (timetable settings).'), error: true);
    return Future.value();
  }
  return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BasePage(
            appBar: ScreenAppBar(title: t('مجموعات الطلاب', 'Student groups')),
            child: _GroupsPage(p: p, termId: asInt(term)),
          )));
}

class _GroupsPage extends StatefulWidget {
  const _GroupsPage({required this.p, required this.termId});
  final OrgScheduleProvider p;
  final int termId;

  @override
  State<_GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<_GroupsPage> {
  int? course;
  Map<String, dynamic>? data;
  bool loading = false;
  String mode = 'alphabetical';

  String get base => '${widget.p.base.replaceFirst(RegExp(r'/$'), '')}/registrar';

  List<Map<String, dynamic>> get courses {
    final scoped = {for (final x in (widget.p.schedule?['course_ids'] as List?) ?? const []) asInt(x)};
    return [for (final l in widget.p.loads) if (scoped.isEmpty || scoped.contains(asInt(l['course_id']))) l];
  }

  Future<void> _load() async {
    if (course == null) return;
    setState(() => loading = true);
    final r = await orgCall(() => widget.p.api.get('$base/terms/${widget.termId}/groups/$course'));
    if (mounted) {
      setState(() {
        loading = false;
        if (r.ok) data = r.map;
      });
    }
  }

  Future<void> _distribute() async {
    setState(() => loading = true);
    final r = await orgCall(() => widget.p.api.post('$base/terms/${widget.termId}/groups/$course/distribute', body: {'mode': mode}));
    if (!mounted) return;
    setState(() {
      loading = false;
      if (r.ok) data = r.map;
    });
    if (r.ok) {
      final kept = asMapList(r.map['kept']).length;
      toast(kept == 0
          ? t('وُزّع ${asInt(r.map['moved'])} طالب', '${asInt(r.map['moved'])} student(s) moved')
          : t('بقي $kept طالب في مجموعته لتعارض أو امتلاء', '$kept student(s) kept their group (clash or full)'));
    }
  }

  Future<void> _move(Map<String, dynamic> student, Map<String, dynamic> from) async {
    final others = [for (final g in asMapList(data?['groups'])) if (g['kind'] == from['kind'] && g['id'] != from['id']) g];
    final to = await showAdminSheet<Map<String, dynamic>>(
        context,
        (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              SheetHeader(t('نقل ${asMap(student['student'])['name']}', 'Move ${asMap(student['student'])['name']}')),
              for (final g in others)
                ListTile(
                  title: Text(groupLabel(g)),
                  trailing: Text('${g['enrolled']}/${g['capacity']}'),
                  onTap: () => Navigator.pop(ctx, g),
                ),
              if (others.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(t('لا توجد مجموعة أخرى', 'No other group'))),
            ]));
    if (to == null || !mounted) return;
    final r = await orgCall(() => widget.p.api.post('$base/registrations/${student['registration_id']}/group', body: {'section_id': to['id']}),
        ok: t('نُقل الطالب', 'Student moved'));
    if (r.ok && mounted) setState(() => data = r.map);
  }

  Future<void> _studentCourses(Map<String, dynamic> student) async {
    final uid = asMap(student['student'])['id'];
    final r = await orgCall(() => widget.p.api.get('$base/terms/${widget.termId}/students/$uid/groups'));
    if (!r.ok || !mounted) return;
    final names = {for (final l in widget.p.loads) asInt(l['course_id']): courseName(l)};
    await showAdminSheet<void>(
        context,
        (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              SheetHeader('${asMap(student['student'])['name']}'),
              for (final x in asMapList(r.map['items']))
                ListTile(
                  dense: true,
                  title: Text(names[asInt(x['course_id'])] ?? '#${x['course_id']}'),
                  subtitle: Text([
                    if (x['lecture_group'] != null) '${t('نظري', 'Theory')} ${x['lecture_group']}',
                    if (x['lab_group'] != null) '${t('معمل', 'Lab')} ${x['lab_group']}',
                  ].join(' · ')),
                ),
            ]));
  }

  void _export() {
    final name = courseName(courses.firstWhere((l) => asInt(l['course_id']) == course, orElse: () => const {}));
    showAppExportSheet(
        context,
        AppTableExport(
          id: 'org.groups.roster',
          title: t('قائمة المجموعات', 'Group roster'),
          subtitle: name,
          groupBy: 'group',
          columns: [
            AppExportColumn('group', t('المجموعة', 'Group')),
            AppExportColumn('name', t('الطالب', 'Student')),
            AppExportColumn('code', t('الرقم الجامعي', 'Student ID')),
          ],
          rows: rosterRows(data ?? const {}),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canEdit = context.read<OrgSession>().can('schedule', 'update');
    final groups = asMapList(data?['groups']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppDropdown<int>(
        value: course,
        hint: Text(t('اختر المقرر', 'Choose a course')),
        items: [for (final l in courses) DropdownMenuItem(value: asInt(l['course_id']), child: Text(courseName(l), overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          setState(() {
            course = v;
            data = null;
          });
          _load();
        },
      ),
      if (course != null && canEdit) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ChoiceChip(label: Text(t('أبجدياً', 'Alphabetical')), selected: mode == 'alphabetical', onSelected: (_) => setState(() => mode = 'alphabetical')),
          ChoiceChip(label: Text(t('بالرقم الجامعي', 'By student ID')), selected: mode == 'student_code', onSelected: (_) => setState(() => mode = 'student_code')),
          FilledButton.tonalIcon(onPressed: loading ? null : _distribute, icon: const Icon(Icons.sort_by_alpha_rounded), label: Text(t('وزّع الطلاب', 'Distribute'))),
          if (data != null) OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.file_download_rounded), label: Text(t('تصدير', 'Export'))),
        ]),
      ],
      const SizedBox(height: 12),
      if (loading) const AppListSkeleton(),
      if (!loading && data != null && groups.isEmpty)
        AppEmpty(
            icon: Icons.groups_rounded,
            title: t('لا مجموعات لهذا المقرر في الفصل', 'No groups for this course this term'),
            message: t('تُنشأ المجموعات من الجدول المنشور للفصل.', 'Groups come from the term\'s published timetable.')),
      if (!loading)
        for (final g in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RowCard(
              accent: asInt(g['enrolled']) > asInt(g['capacity']) ? c.danger : (g['kind'] == 'lab' ? c.purple : c.primary),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(groupLabel(g), style: orgText(context, w: FontWeight.w800))),
                  Text('${g['enrolled']}/${g['capacity']}', style: orgText(context, w: FontWeight.w700, color: c.textMedium)),
                ]),
                for (final s in asMapList(g['students']))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${asMap(s['student'])['name'] ?? ''}', overflow: TextOverflow.ellipsis),
                    subtitle: s['student_code'] == null ? null : Text('${s['student_code']}'),
                    onTap: () => _studentCourses(s),
                    trailing: canEdit
                        ? IconButton(tooltip: t('نقل', 'Move'), icon: const Icon(Icons.swap_horiz_rounded), onPressed: () => _move(s, g))
                        : null,
                  ),
              ]),
            ),
          ),
      if (!loading && asMapList(data?['unassigned']).isNotEmpty)
        AppBanner(
          icon: Icons.warning_amber_rounded,
          color: c.warning,
          text: t('${asMapList(data?['unassigned']).length} طالب بلا مجموعة — اضغط "وزّع الطلاب"', '${asMapList(data?['unassigned']).length} student(s) without a group — tap "Distribute"'),
        ),
    ]);
  }
}
