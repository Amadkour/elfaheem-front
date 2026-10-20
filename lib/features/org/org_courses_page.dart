// lib/features/org/org_courses_page.dart — courses of the selected organization.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'org_providers.dart';
import 'org_ui.dart';

/// Active members of one role (up to 200) — used by the pickers.
Future<List<Map<String, dynamic>>> orgPeople(OrgSession s, String role, {String? search}) async {
  final r = await s.run(
      () => s.api.get('${s.base}/members', queryParams: {'role': role, 'size': 100, if (search != null && search.isNotEmpty) 'search': search}),
      makLoading: false);
  return r is Map ? asMapList(r['items']).map((m) => Map<String, dynamic>.from(m['user'] as Map)).toList() : [];
}

class OrgCoursesPage extends StatelessWidget {
  const OrgCoursesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    if (!s.can('courses')) return OrgEmpty(icon: Icons.lock_rounded, title: t('لا تملك صلاحية عرض الكورسات', 'You cannot view courses'));
    return ChangeNotifierProvider(create: (_) => OrgCoursesProvider(s)..refresh(), child: const _CoursesView());
  }
}

class _CoursesView extends StatelessWidget {
  const _CoursesView();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgCoursesProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final header = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: SearchBox(hint: t('بحث باسم الكورس', 'Search courses'), onChanged: p.setSearch),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          if (s.can('courses', 'insert')) ...[
            ActionChip(
              avatar: Icon(Icons.upload_file_rounded, size: 18, color: c.primary),
              label: Text(t('استيراد كورسات', 'Import courses'), style: const TextStyle(fontFamily: 'tajawal', fontSize: 12.5)),
              onPressed: () async {
                if (await importExcelFlow(context, 'courses') && context.mounted) p.refresh();
              },
            ),
            ActionChip(
              avatar: Icon(Icons.description_outlined, size: 18, color: c.textMedium),
              label: Text(t('نموذج الكورسات', 'Courses template'), style: const TextStyle(fontFamily: 'tajawal', fontSize: 12.5)),
              onPressed: () => downloadExcel(context, 'template/courses'),
            ),
          ],
          if (s.can('students', 'insert'))
            ActionChip(
              avatar: Icon(Icons.how_to_reg_rounded, size: 18, color: c.primary),
              label: Text(t('استيراد تسجيلات', 'Import enrollments'), style: const TextStyle(fontFamily: 'tajawal', fontSize: 12.5)),
              onPressed: () => importExcelFlow(context, 'enrollments').then((_) => p.refresh()),
            ),
          ActionChip(
            avatar: Icon(Icons.download_rounded, size: 18, color: c.success),
            label: Text(t('تصدير الكورسات', 'Export courses'), style: const TextStyle(fontFamily: 'tajawal', fontSize: 12.5)),
            onPressed: () => downloadExcel(context, 'export/courses'),
          ),
          ActionChip(
            avatar: Icon(Icons.download_rounded, size: 18, color: c.success),
            label: Text(t('تصدير التسجيلات', 'Export enrollments'), style: const TextStyle(fontFamily: 'tajawal', fontSize: 12.5)),
            onPressed: () => downloadExcel(context, 'export/enrollments'),
          ),
        ]),
      ),
    ]);

    return Stack(children: [
      PagedList<OrgCoursesProvider>(
        header: header,
        emptyText: t('لا توجد كورسات بعد', 'No courses yet'),
        itemBuilder: (ctx, row) => _CourseTile(row: row),
      ),
      if (s.can('courses', 'insert'))
        PositionedDirectional(
          bottom: 16,
          end: 16,
          child: FloatingActionButton.extended(
            heroTag: 'org_add_course',
            backgroundColor: c.primary,
            onPressed: () => _courseForm(context, p, null),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: Text(t('كورس جديد', 'New course'), style: const TextStyle(fontFamily: 'tajawal', color: Colors.white)),
          ),
        ),
    ]);
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final p = context.read<OrgCoursesProvider>();
    final name = t('${row['name_ar'] ?? row['name_en'] ?? ''}', '${row['name_en'] ?? row['name_ar'] ?? ''}');
    final teacher = (row['teacher'] as Map?)?['name'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: RowCard(
        child: Row(children: [
          IconBadge(Icons.menu_book_rounded, c.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
              if (teacher != null) Text('$teacher', style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textMedium)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                InfoChip(Icons.groups_rounded, '${row['students']}', c.primary),
                InfoChip(Icons.payments_rounded, asDouble(row['fees']) == 0 ? t('مجاني', 'Free') : money(asDouble(row['fees'])), c.success),
                if (row['members_only'] == true) InfoChip(Icons.lock_rounded, t('للأعضاء فقط', 'Members only'), context.colors.purple),
                if (row['is_published'] != true) StatusChip(t('غير منشور', 'Draft'), c.warning),
              ]),
            ]),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') await _courseForm(context, p, row);
              if (v == 'enroll') await _enrollSheet(context, p, row);
              if (v == 'unlink' && await confirm(context, message: t('فصل الكورس عن المؤسسة وإلغاء نشره؟ (اشتراكات الطلاب تبقى)', 'Remove this course from the organization and unpublish it? (student enrollments stay)'), danger: true)) {
                await p.unlink(asInt(row['id']));
              }
            },
            itemBuilder: (_) => [
              if (s.can('courses', 'update')) PopupMenuItem(value: 'edit', child: Text(t('تعديل', 'Edit'))),
              if (s.can('students', 'update')) PopupMenuItem(value: 'enroll', child: Text(t('تسجيل طلاب', 'Enroll students'))),
              if (s.can('courses', 'delete')) PopupMenuItem(value: 'unlink', child: Text(t('فصل عن المؤسسة', 'Remove'), style: TextStyle(color: c.danger))),
            ],
          ),
        ]),
      ),
    );
  }
}


Future<void> _courseForm(BuildContext context, OrgCoursesProvider p, Map<String, dynamic>? edit) async {
  final s = context.read<OrgSession>();
  final teachers = await orgPeople(s, 'teacher');
  if (!context.mounted) return;
  if (teachers.isEmpty) {
    toast(t('أضف مدرساً للمؤسسة أولاً', 'Add a teacher to the organization first'), error: true);
    return;
  }
  final ar = TextEditingController(text: '${edit?['name_ar'] ?? ''}');
  final en = TextEditingController(text: '${edit?['name_en'] ?? ''}');
  final fees = TextEditingController(text: edit == null ? '0' : '${edit['fees']}');
  final hours = TextEditingController(text: edit == null ? '0' : '${edit['total_hours']}');
  int teacherId = asInt((edit?['teacher'] as Map?)?['id'], asInt(teachers.first['id']));
  bool published = edit?['is_published'] ?? true, membersOnly = edit?['members_only'] ?? true, busy = false;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(edit == null ? t('كورس جديد', 'New course') : t('تعديل الكورس', 'Edit course')),
            Field(controller: ar, label: t('الاسم بالعربية', 'Arabic name')),
            Field(controller: en, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
            OrgPickField<int>(
              label: t('المدرس', 'Teacher'),
              icon: Icons.person_rounded,
              value: teacherId,
              options: {for (final u in teachers) asInt(u['id']): '${u['name']}'},
              onChanged: (v) => set(() => teacherId = v ?? teacherId),
            ),
            Row(children: [
              Expanded(child: Field(controller: fees, label: t('السعر السنوي', 'Yearly fee'), keyboard: TextInputType.number, ltr: true)),
              const SizedBox(width: 10),
              Expanded(child: Field(controller: hours, label: t('عدد الساعات', 'Total hours'), keyboard: TextInputType.number, ltr: true)),
            ]),
            OrgSwitchRow(title: t('منشور', 'Published'), value: published, onChanged: (v) => set(() => published = v)),
            OrgSwitchRow(
                title: t('للأعضاء فقط', 'Members only'),
                subtitle: t('يختفي من الكتالوج العام', 'Hidden from the public catalogue'),
                value: membersOnly,
                onChanged: (v) => set(() => membersOnly = v)),
            const SizedBox(height: 6),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                if (ar.text.trim().isEmpty && en.text.trim().isEmpty) {
                  toast(t('اكتب اسم الكورس', 'Enter a course name'), error: true);
                  return;
                }
                set(() => busy = true);
                final ok = await p.save(edit == null ? null : asInt(edit['id']), {
                  'name_ar': ar.text.trim(),
                  'name_en': en.text.trim(),
                  'teacher_id': teacherId,
                  'fees': double.tryParse(fees.text) ?? 0,
                  'total_hours': double.tryParse(hours.text) ?? 0,
                  'is_published': published,
                  'members_only': membersOnly,
                });
                if (ctx.mounted) {
                  set(() => busy = false);
                  if (ok) Navigator.pop(ctx);
                }
              },
            ),
          ]),
        );
      }));
}

Future<void> _enrollSheet(BuildContext context, OrgCoursesProvider p, Map<String, dynamic> course) async {
  final s = context.read<OrgSession>();
  var students = await orgPeople(s, 'student');
  if (!context.mounted) return;
  final picked = <int>{};
  final q = TextEditingController();
  bool busy = false;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final shown = students.where((u) => '${u['name']} ${u['email']}'.toLowerCase().contains(q.text.trim().toLowerCase())).toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('تسجيل طلاب في الكورس', 'Enroll students')),
            TextField(controller: q, onChanged: (_) => set(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: t('بحث', 'Search'))),
            const SizedBox(height: 8),
            Flexible(
              child: shown.isEmpty
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(t('لا يوجد طلاب', 'No students')))
                  : ListView(shrinkWrap: true, children: [
                      for (final u in shown)
                        CheckboxListTile(
                          value: picked.contains(asInt(u['id'])),
                          onChanged: (v) => set(() => v == true ? picked.add(asInt(u['id'])) : picked.remove(asInt(u['id']))),
                          title: Text('${u['name']}', style: TextStyle(fontFamily: 'tajawal', color: c.textDark)),
                          subtitle: Text('${u['email']}', textDirection: TextDirection.ltr),
                          dense: true,
                        ),
                    ]),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              isLoading: busy,
              label: t('تسجيل (${picked.length})', 'Enroll (${picked.length})'),
              enable: picked.isNotEmpty,
              onPressed: () async {
                set(() => busy = true);
                final r = await p.enroll(asInt(course['id']), picked.toList());
                if (ctx.mounted) {
                  set(() => busy = false);
                  if (r != null) {
                    toast(t('تم تسجيل ${r['enrolled']} طالب', '${r['enrolled']} students enrolled'));
                    Navigator.pop(ctx);
                  }
                }
              },
            ),
          ]),
        );
      }));
}
