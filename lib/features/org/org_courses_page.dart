// lib/features/org/org_courses_page.dart — courses of the selected organization.
library;

import 'package:flutter/material.dart';
import 'org_institutions.dart' show orgCourseDeptOptions;
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_view.dart' show EntityPanelAction;
import 'package:flutter_education_app/design/master_detail/entity_viewer_actions.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_v3.dart';
import 'org_page_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_blocks.dart' show AppBlockColors, AppBlockTone;
import 'package:flutter_education_app/design/app_badges.dart' show AppStatusBadge, AppTone;
import 'org_academic_pages.dart' show CourseArchiveScreen;
import 'org_page_header.dart' show OrgPushedPage;
import 'org_schedule_pages.dart' show OrgSchedulePage;
import '../admin/admin_table_export.dart' show exportPagedList, orgCoursesExport;
import 'package:flutter_education_app/features/courses/course_profile/course_profile_screen.dart' show openCourseProfile;
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_side_sheet.dart' show AppSheetMode;

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
    // a department-scoped right is enough: the server lists those departments' courses plus the ones I teach
    if (!s.canAny('courses')) return OrgEmpty(icon: Icons.lock_rounded, title: t('لا تملك صلاحية عرض الكورسات', 'You cannot view courses'));
    return ChangeNotifierProvider(create: (_) => OrgCoursesProvider(s)..refresh(), child: const _CoursesView());
  }
}

/// The page anatomy (D-103, org_page_kit.dart): search · More (⋯: import / template / enrollments / exports) ·
/// ONE primary action "New course" (FAB on phones, button when wide) · the course cards.
class _CoursesView extends StatefulWidget {
  const _CoursesView();

  @override
  State<_CoursesView> createState() => _CoursesViewState();
}

/// A course opens its connected panel (D-290: statistics and enrolled students, as far as this person's rights go);
/// Open course is the course page, where its teacher finds Exams, attendance and the tools.
class _CoursesViewState extends State<_CoursesView> {
  final _panel = EntityPanelController(rowKind: EntityKind.course);

  @override
  void dispose() {
    _panel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MasterDetailScaffold(
        controller: _panel,
        rootLabel: t('المقررات', 'Courses'),
        actions: (ref, summary) => ref.kind == EntityKind.course
            ? [
                EntityPanelAction(
                  key: const ValueKey('md.open_course'),
                  icon: Icons.open_in_new_rounded,
                  label: t('فتح المقرر', 'Open course'),
                  primary: true,
                  onPressed: () => openCourseProfile(context, ref.id),
                ),
              ]
            : entityViewerActions(context, ref, summary),
        list: Builder(builder: _list),
      );

  Widget _list(BuildContext context) {
    final p = context.watch<OrgCoursesProvider>();
    final s = context.watch<OrgSession>();
    return OrgPageBody(
      primary: s.can('courses', 'insert')
          ? OrgPrimaryAction(
              id: 'new_course',
              icon: Icons.add_rounded,
              label: t('مقرر جديد', 'New course'),
              onTap: () async {
                if (await showOrgCourseForm(context) != null) p.refresh();
              },
            )
          : null,
      search: OrgSearchField(hint: t('ابحث باسم المقرر', 'Search courses'), onChanged: p.setSearch),
      more: [
        if (s.can('courses', 'insert')) ...[
          OrgMenuItem(
            icon: Icons.upload_file_rounded,
            label: t('استيراد مقررات من Excel', 'Import courses from Excel'),
            onTap: () async {
              if (await importExcelFlow(context, 'courses') && context.mounted) p.refresh();
            },
          ),
          OrgMenuItem(
            icon: Icons.description_outlined,
            label: t('تنزيل نموذج المقررات', 'Download the courses template'),
            onTap: () => downloadExcel(context, 'template/courses'),
          ),
        ],
        if (s.can('students', 'insert'))
          OrgMenuItem(
            icon: Icons.how_to_reg_rounded,
            label: t('استيراد تسجيلات الطلاب', 'Import enrollments'),
            onTap: () => importExcelFlow(context, 'enrollments').then((_) => p.refresh()),
          ),
        OrgMenuItem(
          icon: Icons.ios_share_rounded,
          label: t('تصدير المقررات', 'Export courses'),
          onTap: () => exportPagedList(context, p, (rows) => orgCoursesExport(rows, orgName: s.name)),
        ),
        if (s.can('courses'))
        OrgMenuItem(
          icon: Icons.download_rounded,
          label: t('تصدير التسجيلات', 'Export enrollments'),
          onTap: () => downloadExcel(context, 'export/enrollments'),
        ),
      ],
      child: PagedList<OrgCoursesProvider>(
        emptyText: p.search.isNotEmpty
            ? t('لا مقررات بهذا الاسم', 'No course matches this search')
            : s.can('courses', 'insert')
                ? t('لا توجد مقررات بعد — أضف أول مقرر أو استوردها من Excel', 'No courses yet — add the first one or import them from Excel')
                : t('لا توجد مقررات تدرّسها أو في أقسامك بعد', 'No course you teach or in your departments yet'),
        itemBuilder: (ctx, row) => _CourseTile(row: row),
      ),
    );
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
    final name = orgNameOf(row);
    final teacher = (row['teacher'] as Map?)?['name'];
    final code = '${row['code'] ?? ''}';
    final fees = asDouble(row['fees']);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: orgListInset, vertical: AppSpace.xxs),
      child: RowCard(
        onTap: () => EntityNavigator.open(
            context, EntityRef(EntityKind.course, asInt(row['id']), label: '${row['name_ar'] ?? ''}', labelEn: '${row['name_en'] ?? ''}')),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // the course's mark: a block tone that stays with the course everywhere (AppBlockTone.forKey)
          _CourseMark(seed: code.isNotEmpty ? code : '${row['id']}'),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              const SizedBox(height: AppSpace.xxs / 2),
              Text(teacher == null ? t('بلا مدرس بعد', 'No teacher yet') : '$teacher',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(color: teacher == null ? c.warning : c.textMedium)),
              const SizedBox(height: AppSpace.sm),
              // the facts as quiet ink, the states as badges: no row of identical grey pills
              Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _Fact(Icons.groups_rounded, t('${row['students']} طالب', '${row['students']} students')),
                _Fact(Icons.payments_rounded, fees == 0 ? t('مجاني', 'Free') : money(fees)),
                if (code.isNotEmpty) _Fact(Icons.tag_rounded, code),
                _Fact(Icons.account_tree_rounded, row['scope'] == 'department' ? t('مقرر قسم', 'Department course') : t('مقرر عام', 'General course')),
                if (row['members_only'] == true)
                  AppStatusBadge(label: t('للأعضاء فقط', 'Members only'), tone: AppTone.info, icon: Icons.lock_rounded, dense: true),
                if (row['is_published'] != true) AppStatusBadge(label: t('غير منشور', 'Draft'), tone: AppTone.warning, dense: true),
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
              if (v == 'timetable' && context.mounted) {
                // ROUTE: org_schedule (the timetable office, where this course's teaching loads live)
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => OrgPushedPage(title: t('الجدول الدراسي', 'Timetable'), subtitle: name, child: const OrgSchedulePage())));
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
              if (s.can('schedule')) PopupMenuItem(value: 'timetable', child: Text(t('الجدول وتوزيع المدرسين', 'Timetable & teaching loads'))),
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

/// A course's mark: its block tone (stable per course) with the book in the block's ink.
class _CourseMark extends StatelessWidget {
  const _CourseMark({required this.seed});
  final String seed;

  @override
  Widget build(BuildContext context) {
    final k = AppBlockColors.of(context, AppBlockTone.forKey(seed));
    return ExcludeSemantics(
      child: Container(
        width: AppTouch.min,
        height: AppTouch.min,
        decoration: BoxDecoration(
          color: k.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: k.border == null ? null : Border.all(color: k.border!, width: AppBorder.hairline),
        ),
        child: Icon(Icons.menu_book_rounded, size: AppIconSize.lg, color: k.ink),
      ),
    );
  }
}

/// One quiet fact of a course card: a small icon and its text in the meta role.
class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: AppIconSize.xs, color: c.textLight),
      const SizedBox(width: AppSpace.xxs),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
    ]);
  }
}

/// Whether saving [chosen] over the course's [original] teacher takes the teacher away (an edit that ends with none).
bool orgCourseUnassigns({required bool isEdit, required int? original, required int? chosen}) =>
    isEdit && original != null && chosen == null;

/// The `teacher_id` entry of the course body: the chosen teacher; an EXPLICIT null when an edit unassigns (the server
/// keeps the teacher when the key is missing); no key otherwise.
Map<String, dynamic> orgCourseTeacherField({required bool isEdit, required int? original, required int? chosen}) {
  if (chosen != null) return {'teacher_id': chosen};
  return orgCourseUnassigns(isEdit: isEdit, original: original, chosen: chosen) ? {'teacher_id': null} : const {};
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
    orgCall(() => s.api.get('${s.base}/departments'), quiet: true),
  ]);
  if (!context.mounted) return null;
  final teachers = asMapList(rs[0].map['items']).map((m) => asMap(m['user'])).toList();
  final programs = asMapList(rs[1].map['items']).where((p) => p['is_active'] != false || p['id'] == edit?['program_id']).toList();
  final terms = asMapList(rs[2].map['items']);
  final options = asMapList(rs[3].map['items']).where((x) => x['id'] != edit?['id']).toList();
  // the department it sits in (D-963): academic departments first; councils, offices and catalog service
  // departments are left out (the server answers 422 course_dept_not_academic), the current one stays listed
  final origDept = edit?['dept_id'] == null ? null : asInt(edit!['dept_id']);
  final depts = orgCourseDeptOptions(asMapList(rs[4].map['items']), keep: origDept);
  int? dept = origDept;

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

  await showAdminSheet<void>(context, mode: AppSheetMode.side, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final canPublish = teacherId != null;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(edit == null ? t('مقرر جديد', 'New course') : t('تعديل المقرر', 'Edit course')),
            Row(children: [
              SizedBox(width: 130, child: Field(controller: code, label: t('كود المقرر', 'Course code'), ltr: true)),
              const SizedBox(width: AppSpace.xs),
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
            const SizedBox(height: AppSpace.sm),
            if (depts.isNotEmpty) ...[
              OrgPickField<int>(
                label: t('القسم (اختياري)', 'Department (optional)'),
                icon: Icons.apartment_rounded,
                value: dept,
                allowNone: true,
                noneLabel: t('بدون قسم', 'No department'),
                options: {
                  for (final d in depts)
                    asInt(d['id']): d['kind'] == 'scientific' ? orgNameOf(d) : '${orgNameOf(d)} · ${t('غير علمي', 'not academic')}',
                },
                onChanged: (v) => set(() => dept = v),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            OrgPickField<int>(
              label: t('الفصل الدراسي (اختياري)', 'Academic term (optional)'),
              icon: Icons.event_note_rounded,
              value: term,
              allowNone: true,
              options: {for (final x in terms) asInt(x['id']): t('${x['label_ar'] ?? x['year_label']}', '${x['label_en'] ?? x['year_label']}')},
              onChanged: (v) => set(() => term = v),
            ),
            const SizedBox(height: AppSpace.sm),
            OrgPickField<int>(
              label: t('المدرس', 'Teacher'),
              icon: Icons.person_rounded,
              value: teacherId,
              // an explicit teacher_id: null unassigns (C6); the course is unpublished while it has no teacher
              allowNone: true,
              noneLabel: origTeacher == null ? t('يُعيَّن لاحقاً', 'Assign later') : t('إلغاء التعيين (يُلغى النشر)', 'Unassign (the course gets unpublished)'),
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
              padding: const EdgeInsets.only(top: AppSpace.xxs, bottom: AppSpace.xs),
              child: Text(
                  teacherId == null
                      ? t('بدون مدرس يبقى المقرر غير منشور حتى تعيينه. الخادم يتحقق من أهلية المدرس للقسم.',
                          'Without a teacher the course stays unpublished until one is assigned. The server checks the teacher is eligible for the department.')
                      : t('الخادم يتحقق من أهلية المدرس لنطاق المقرر.', 'The server checks the teacher is eligible for the course scope.'),
                  style: AppType.meta(ctx).copyWith(color: c.textLight)),
            ),
            if (options.isNotEmpty) ...[
              Text(t('المتطلبات السابقة (مقررات يجب اجتيازها أولاً)', 'Prerequisites (courses to complete first)'),
                  style: AppType.label(ctx).copyWith(color: c.textLight)),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final o in options)
                  FilterChip(
                    label: Text(t('${o['name_ar'] ?? o['name_en']}', '${o['name_en'] ?? o['name_ar']}'), style: TextStyle(fontFamily: AppFonts.family)),
                    selected: prereqs.contains(asInt(o['id'])),
                    onSelected: (on) => set(() => on ? prereqs.add(asInt(o['id'])) : prereqs.remove(asInt(o['id']))),
                  ),
              ]),
              const SizedBox(height: AppSpace.sm),
            ],
            Row(children: [
              Expanded(child: OrgNumberField(controller: fees, label: t('السعر السنوي', 'Yearly fee'), decimals: 2)),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: OrgNumberField(controller: hours, label: t('عدد الساعات', 'Total hours'))),
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
                margin: const EdgeInsets.only(bottom: AppSpace.sm),
                padding: const EdgeInsets.all(AppSpace.sm),
                decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.control)),
                child: Text(err!, style: AppType.label(ctx).copyWith(color: c.danger)),
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
                  ...orgCourseTeacherField(isEdit: edit != null, original: origTeacher, chosen: teacherId),
                  'fees': double.tryParse(fees.text) ?? 0,
                  'total_hours': double.tryParse(hours.text) ?? 0,
                  'is_published': published && canPublish,
                  'members_only': membersOnly,
                  'prerequisite_ids': prereqs.toList(),
                };
                // dept_id only when it changes: the server re-checks any dept_id it is sent
                if (edit == null ? dept != null : dept != origDept) body['dept_id'] = dept;
                if (edit == null) body.removeWhere((k, v) => v == null);
                if (orgCourseUnassigns(isEdit: edit != null, original: origTeacher, chosen: teacherId) &&
                    !await confirm(ctx,
                        message: t('إلغاء تعيين المدرس؟ سيصبح المقرر غير منشور حتى تعيّن مدرساً آخر.',
                            'Unassign the teacher? The course becomes unpublished until you assign another one.'),
                        danger: true)) {
                  return;
                }
                if (!ctx.mounted) return;
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
  await showAdminSheet<void>(context, mode: AppSheetMode.side, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final shown = students.where((u) => '${u['name']} ${u['email']}'.toLowerCase().contains(q.text.trim().toLowerCase())).toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('تسجيل طلاب في الكورس', 'Enroll students')),
            TextField(controller: q, onChanged: (_) => set(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: t('بحث', 'Search'))),
            const SizedBox(height: AppSpace.xs),
            Flexible(
              child: shown.isEmpty
                  ? Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text(t('لا يوجد طلاب', 'No students')))
                  : ListView(shrinkWrap: true, children: [
                      for (final u in shown)
                        CheckboxListTile(
                          value: picked.contains(asInt(u['id'])),
                          onChanged: (v) => set(() => v == true ? picked.add(asInt(u['id'])) : picked.remove(asInt(u['id']))),
                          title: Text('${u['name']}', style: TextStyle(fontFamily: AppFonts.family, color: c.textDark)),
                          subtitle: Text('${u['email']}', textDirection: TextDirection.ltr),
                          dense: true,
                        ),
                    ]),
            ),
            const SizedBox(height: AppSpace.xs),
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
