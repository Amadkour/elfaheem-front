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
import 'org_v3.dart';
import 'org_academic_pages.dart' show CourseArchiveScreen;
import '../admin/admin_table_export.dart' show exportPagedList, orgCoursesExport;
import '../shared/course_profile/course_profile_screen.dart' show openCourseProfile;

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
            avatar: Icon(Icons.ios_share_rounded, size: 18, color: c.success),
            label: Text(t('تصدير الكورسات', 'Export courses'), style: const TextStyle(fontFamily: 'tajawal', fontSize: 12.5)),
            onPressed: () => exportPagedList(context, p, (rows) => orgCoursesExport(rows, orgName: s.name)),
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
            onPressed: () async {
              if (await showOrgCourseForm(context) != null) p.refresh();
            },
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
              Text(teacher == null ? t('بلا مدرس بعد', 'No teacher yet') : '$teacher', style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: teacher == null ? c.warning : c.textMedium)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                InfoChip(Icons.groups_rounded, '${row['students']}', c.primary),
                InfoChip(Icons.payments_rounded, asDouble(row['fees']) == 0 ? t('مجاني', 'Free') : money(asDouble(row['fees'])), c.success),
                if (row['members_only'] == true) InfoChip(Icons.lock_rounded, t('للأعضاء فقط', 'Members only'), context.colors.purple),
                if (row['is_published'] != true) StatusChip(t('غير منشور', 'Draft'), c.warning),
                if ('${row['code'] ?? ''}'.isNotEmpty) InfoChip(Icons.tag_rounded, '${row['code']}', c.textMedium),
                InfoChip(Icons.account_tree_rounded, row['scope'] == 'department' ? t('مقرر قسم', 'Department course') : t('مقرر عام', 'General course'), c.textMedium),
              ]),
            ]),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'profile') {
                await openCourseProfile(context, asInt(row['id']));
                return;
              }
              if (v == 'edit' && await showOrgCourseForm(context, edit: row) != null) p.refresh();
              if (v == 'archive' && context.mounted) {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CourseArchiveScreen(
                    orgId: asInt(context.read<OrgSession>().currentId), courseId: asInt(row['id']), canManage: s.can('academic', 'approve'))));
              }
              if (v == 'code' && context.mounted) {
                final code = await askText(context, title: t('كود المقرر (مثل CS101)', 'Course code (e.g. CS101)'), hint: '${row['code'] ?? ''}');
                if (code != null && context.mounted) {
                  await OrgApi.i.put('${context.read<OrgSession>().base}/academic/courses/${row['id']}/code', {'code': code}, t('تم', 'Saved'));
                  p.refresh();
                }
              }
              if (v == 'enroll') await _enrollSheet(context, p, row);
              if (v == 'unlink' && await confirm(context, message: t('فصل الكورس عن المؤسسة وإلغاء نشره؟ (اشتراكات الطلاب تبقى)', 'Remove this course from the organization and unpublish it? (student enrollments stay)'), danger: true)) {
                await p.unlink(asInt(row['id']));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'profile', child: Text(t('ملف المقرر', 'Course profile'))),
              if (s.can('courses', 'update')) PopupMenuItem(value: 'edit', child: Text(t('تعديل', 'Edit'))),
              if (s.can('courses', 'update')) PopupMenuItem(value: 'code', child: Text(t('كود المقرر', 'Course code'))),
              PopupMenuItem(value: 'archive', child: Text(t('الفصول والأرشيف', 'Terms & archive'))),
              if (s.can('students', 'update')) PopupMenuItem(value: 'enroll', child: Text(t('تسجيل طلاب', 'Enroll students'))),
              if (s.can('courses', 'delete')) PopupMenuItem(value: 'unlink', child: Text(t('فصل عن المؤسسة', 'Remove'), style: TextStyle(color: c.danger))),
            ],
          ),
        ]),
      ),
    );
  }
}


/// Create or edit an organization course. Returns the saved course row (after the server confirmed it), or null.
/// A teacher is optional: a course without one stays unpublished until a teacher is assigned.
Future<Map<String, dynamic>?> showOrgCourseForm(BuildContext context, {Map<String, dynamic>? edit}) async {
  final s = context.read<OrgSession>();
  final rs = await Future.wait([
    orgCall(() => s.api.get('${s.base}/members', queryParams: {'role': 'teacher', 'size': 100}), quiet: true),
    orgCall(() => s.api.get('${s.base}/academic/programs'), quiet: true),
    orgCall(() => s.api.get('${s.base}/academic/terms'), quiet: true),
    orgCall(() => s.api.get('${s.base}/courses', queryParams: {'size': 100, 'scope': 'tree'}), quiet: true),
  ]);
  if (!context.mounted) return null;
  final teachers = asMapList(rs[0].map['items']).map((m) => asMap(m['user'])).toList();
  final programs = asMapList(rs[1].map['items']).where((p) => p['is_active'] != false || p['id'] == edit?['program_id']).toList();
  final terms = asMapList(rs[2].map['items']);
  final options = asMapList(rs[3].map['items']).where((x) => x['id'] != edit?['id']).toList();

  final ar = TextEditingController(text: '${edit?['name_ar'] ?? ''}');
  final en = TextEditingController(text: '${edit?['name_en'] ?? ''}');
  final code = TextEditingController(text: '${edit?['code'] ?? ''}');
  final descAr = TextEditingController(text: '${edit?['description_ar'] ?? ''}');
  final descEn = TextEditingController(text: '${edit?['description_en'] ?? ''}');
  final fees = TextEditingController(text: edit == null ? '0' : '${edit['fees']}');
  final hours = TextEditingController(text: edit == null ? '0' : '${edit['total_hours']}');
  final origTeacher = asMap(edit?['teacher'])['id'] == null ? null : asInt(asMap(edit?['teacher'])['id']);
  int? teacherId = origTeacher;
  int? program = edit?['program_id'] == null ? null : asInt(edit!['program_id']);
  int? term = edit?['term_id'] == null ? null : asInt(edit!['term_id']);
  bool published = edit?['is_published'] ?? false, membersOnly = edit?['members_only'] ?? true, busy = false;
  final prereqs = <int>{...((edit?['prerequisite_ids'] as List?) ?? const []).map((e) => asInt(e))};
  String? err;
  Map<String, dynamic>? saved;

  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final canPublish = teacherId != null;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(edit == null ? t('مقرر جديد', 'New course') : t('تعديل المقرر', 'Edit course')),
            Row(children: [
              SizedBox(width: 130, child: Field(controller: code, label: t('كود المقرر', 'Course code'), ltr: true)),
              const SizedBox(width: 8),
              Expanded(child: Field(controller: ar, label: t('الاسم بالعربية', 'Arabic name'))),
            ]),
            Field(controller: en, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
            Field(controller: descAr, label: t('الوصف بالعربية (اختياري)', 'Arabic description (optional)'), maxLines: 2),
            Field(controller: descEn, label: t('الوصف بالإنجليزية (اختياري)', 'English description (optional)'), maxLines: 2, ltr: true),
            OrgPickField<int>(
              label: t('النطاق', 'Scope'),
              icon: Icons.account_tree_rounded,
              value: program,
              allowNone: true,
              noneLabel: t('مقرر عام (لكل الأقسام)', 'General course (all departments)'),
              options: {for (final p in programs) asInt(p['id']): '${p['code']} · ${orgNameOf(p)}'},
              onChanged: (v) => set(() => program = v),
            ),
            const SizedBox(height: 10),
            OrgPickField<int>(
              label: t('الفصل الدراسي (اختياري)', 'Academic term (optional)'),
              icon: Icons.event_note_rounded,
              value: term,
              allowNone: true,
              options: {for (final x in terms) asInt(x['id']): t('${x['label_ar'] ?? x['year_label']}', '${x['label_en'] ?? x['year_label']}')},
              onChanged: (v) => set(() => term = v),
            ),
            const SizedBox(height: 10),
            OrgPickField<int>(
              label: t('المدرس', 'Teacher'),
              icon: Icons.person_rounded,
              value: teacherId,
              // the server ignores teacher_id: null on update, so an assigned teacher can only be replaced
              allowNone: edit == null || origTeacher == null,
              noneLabel: t('يُعيَّن لاحقاً', 'Assign later'),
              options: {
                for (final u in teachers) asInt(u['id']): '${u['name']}',
                if (origTeacher != null) origTeacher: '${asMap(edit?['teacher'])['name']}',
              },
              onChanged: (v) => set(() {
                teacherId = v;
                if (v == null) published = false;
              }),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                  teacherId == null
                      ? t('بدون مدرس يبقى المقرر غير منشور حتى تعيينه. الخادم يتحقق من أهلية المدرس للقسم.',
                          'Without a teacher the course stays unpublished until one is assigned. The server checks the teacher is eligible for the department.')
                      : t('الخادم يتحقق من أهلية المدرس لنطاق المقرر.', 'The server checks the teacher is eligible for the course scope.'),
                  style: orgText(ctx, size: 11.5, color: c.textLight)),
            ),
            if (options.isNotEmpty) ...[
              Text(t('المتطلبات السابقة (مقررات يجب اجتيازها أولاً)', 'Prerequisites (courses to complete first)'),
                  style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: c.textLight)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final o in options)
                  FilterChip(
                    label: Text(t('${o['name_ar'] ?? o['name_en']}', '${o['name_en'] ?? o['name_ar']}'), style: const TextStyle(fontFamily: 'tajawal')),
                    selected: prereqs.contains(asInt(o['id'])),
                    onSelected: (on) => set(() => on ? prereqs.add(asInt(o['id'])) : prereqs.remove(asInt(o['id']))),
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Expanded(child: Field(controller: fees, label: t('السعر السنوي', 'Yearly fee'), keyboard: TextInputType.number, ltr: true)),
              const SizedBox(width: 10),
              Expanded(child: Field(controller: hours, label: t('عدد الساعات', 'Total hours'), keyboard: TextInputType.number, ltr: true)),
            ]),
            OrgSwitchRow(
                title: t('منشور', 'Published'),
                subtitle: canPublish ? null : t('عيّن مدرساً أولاً', 'Assign a teacher first'),
                value: published && canPublish,
                onChanged: canPublish ? (v) => set(() => published = v) : (_) {}),
            OrgSwitchRow(
                title: t('للأعضاء فقط', 'Members only'),
                subtitle: t('يختفي من الكتالوج العام', 'Hidden from the public catalogue'),
                value: membersOnly,
                onChanged: (v) => set(() => membersOnly = v)),
            if (err != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                child: Text(err!, style: orgText(ctx, size: 12.5, color: c.danger)),
              ),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                if (ar.text.trim().isEmpty && en.text.trim().isEmpty) return set(() => err = t('اكتب اسم المقرر', 'Enter a course name'));
                String? txt(TextEditingController x) => x.text.trim().isEmpty ? null : x.text.trim();
                final body = <String, dynamic>{
                  'name_ar': ar.text.trim(),
                  'name_en': en.text.trim(),
                  'code': txt(code),
                  'description_ar': txt(descAr),
                  'description_en': txt(descEn),
                  'program_id': program,
                  'term_id': term,
                  'teacher_id': ?teacherId,
                  'fees': double.tryParse(fees.text) ?? 0,
                  'total_hours': double.tryParse(hours.text) ?? 0,
                  'is_published': published && canPublish,
                  'members_only': membersOnly,
                  'prerequisite_ids': prereqs.toList(),
                };
                if (edit == null) body.removeWhere((k, v) => v == null);
                set(() {
                  busy = true;
                  err = null;
                });
                final r = await orgCall(
                    () => edit == null ? s.api.post('${s.base}/courses', body: body) : s.api.put('${s.base}/courses/${edit['id']}', body: body),
                    quiet: true);
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (!r.ok) {
                  final why = r.detail['message'];
                  return set(() => err = r.code == 'teacher_not_eligible' && why != null ? '${orgErrorText(r.error!)} — $why' : orgErrorText(r.error!));
                }
                saved = r.map;
                Navigator.pop(ctx);
                toast(t('تم الحفظ', 'Saved'));
              },
            ),
          ]),
        );
      }));
  return saved;
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
