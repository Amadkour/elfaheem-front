// lib/features/org/org_departments_page.dart
//
//   OrgDepartmentsPage   every department I can see (sub-departments under their parent, plus the academic
//                        departments when I may see them) — tapping one opens its dashboard (org_department_dashboard.dart)
//   showDepartmentWizard ready-made departments (HR, Finance, الإرشاد الأكاديمي, Controls …) or a custom one
//   OrgDepartmentHub     one department: Overview · Team · Ads · Forms · Complaints · Library · Data Lab · Certificates
//                        (a tab exists only when the service is switched on AND I have the right in that department)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designs_screen.dart';
import 'package:flutter_education_app/features/teacher/data_lab/data_lab_screen.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_department_dashboard.dart' show openDepartmentDashboard;
import 'org_providers.dart';
import 'org_services_pages.dart';
import 'org_join_pages.dart' show OrgUnitJoinHub, canConfigureUnit;
import 'org_member_form.dart' show OrgMemberPickField;
import 'org_ui.dart';
import 'package:flutter_education_app/design/app_inputs.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppDropdown, AppRefresh;
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

const _featureIcons = {
  'announcements': Icons.campaign_rounded,
  'forms': Icons.assignment_rounded,
  'complaints': Icons.support_agent_rounded,
  'materials': Icons.folder_copy_rounded,
  'data_lab': Icons.science_rounded,
  'certificates': Icons.workspace_premium_rounded,
  'members': Icons.group_add_rounded,
  'reports': Icons.insights_rounded,
};

Map<String, String> featureLabels() => {
      'announcements': t('الإعلانات', 'Ads & news'),
      'forms': t('النماذج والطلبات', 'Forms'),
      'complaints': t('الشكاوى', 'Complaints'),
      'materials': t('المكتبة', 'Library'),
      'data_lab': t('مختبر البيانات', 'Data Lab'),
      'certificates': t('الشهادات', 'Certificates'),
      'members': t('الأعضاء والانضمام', 'Members & joining'),
      'reports': t('التقارير', 'Reports'),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  List
// ═════════════════════════════════════════════════════════════════════════════

class OrgDepartmentsPage extends StatefulWidget {
  const OrgDepartmentsPage({super.key});

  @override
  State<OrgDepartmentsPage> createState() => _OrgDepartmentsPageState();
}

class _OrgDepartmentsPageState extends State<OrgDepartmentsPage> {
  List<Map<String, dynamic>>? _items;
  List<Map<String, dynamic>> _programs = const [];
  bool _failed = false, _canCreate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    final r = await OrgApi.i.getMap('${s.base}/departments');
    // academic departments are edited in "Academic structure"; listed here for people who may see them
    final p = s.can('academic') ? await OrgApi.i.getMap('${s.base}/academic/programs') : null;
    if (!mounted) return;
    setState(() {
      _items = r == null ? _items : asMapList(r['items']);
      _programs = p == null ? _programs : asMapList(p['items']).where((x) => x['is_active'] != false).toList();
      _canCreate = r?['can_create'] == true;
      _failed = r == null && _items == null;
    });
  }

  /// Parents first, each followed by its own sub-departments (any depth), so the tree reads top-down.
  List<(Map<String, dynamic>, int)> _ordered(List<Map<String, dynamic>> items) {
    final ids = {for (final d in items) asInt(d['id'])};
    final kids = <int, List<Map<String, dynamic>>>{};
    final roots = <Map<String, dynamic>>[];
    for (final d in items) {
      final p = d['parent_id'] == null ? null : asInt(d['parent_id']);
      if (p == null || !ids.contains(p)) {
        roots.add(d);
      } else {
        (kids[p] ??= []).add(d);
      }
    }
    final out = <(Map<String, dynamic>, int)>[];
    final seen = <int>{};
    void walk(Map<String, dynamic> d, int depth) {
      if (!seen.add(asInt(d['id']))) return;
      out.add((d, depth));
      for (final k in kids[asInt(d['id'])] ?? const <Map<String, dynamic>>[]) {
        walk(k, depth + 1);
      }
    }
    for (final r in roots) {
      walk(r, 0);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final items = _items;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              heroTag: 'dept_new',
              backgroundColor: c.primary,
              onPressed: () async {
                if (await showDepartmentWizard(context)) _load();
              },
              icon: Icon(Icons.add_business_rounded, color: c.onHero),
              label: Text(t('إدارة جديدة', 'New department'),
                  style: TextStyle(fontFamily: AppFonts.family, color: c.onHero, fontWeight: FontWeight.w700)),
            )
          : null,
      body: OrgAsync(
        loading: items == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: items == null
            ? const SizedBox.shrink()
            : items.isEmpty
                ? OrgEmpty(
                    icon: Icons.apartment_rounded,
                    title: t('نظّم مؤسستك في إدارات', 'Organize your institution into departments'),
                    message: t('شؤون الطلاب، الموارد البشرية، الكنترول، الإرشاد الأكاديمي… لكل إدارة فريقها وخدماتها.',
                        'Student affairs, HR, controls, academic advising… each with its own team and services.'),
                    actionLabel: _canCreate ? t('إضافة أول إدارة', 'Add the first department') : null,
                    onAction: () async {
                      if (await showDepartmentWizard(context)) _load();
                    },
                  )
                : AppRefresh(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.only(top: 6, bottom: 100), children: [
                      OrgSectionTitle(t('الإدارات الخدمية', 'Service departments'),
                          subtitle: t('${items.length} إدارة في ${s.name} — اضغط أي إدارة لفتح لوحتها',
                              '${items.length} in ${s.name} — tap one to open its dashboard')),
                      OrgGrid(minTile: 300, children: [
                        for (final (d, depth) in _ordered(items))
                          _DeptCard(
                            d: d,
                            parentName: depth == 0
                                ? null
                                : orgNameOf(items.firstWhere((x) => asInt(x['id']) == asInt(d['parent_id']),
                                    orElse: () => const <String, dynamic>{})),
                            subCount: items.where((x) => x['parent_id'] != null && asInt(x['parent_id']) == asInt(d['id'])).length,
                            onTap: () async {
                              await openDepartmentDashboard(context, unitType: 'dept', unitId: asInt(d['id']), seed: d);
                              _load();
                            },
                          ),
                      ]),
                      if (_programs.isNotEmpty) ...[
                        OrgSectionTitle(t('الأقسام العلمية', 'Academic departments'),
                            subtitle: t('${_programs.length} قسم — الهيكل والمقررات في "الهيكل الأكاديمي"',
                                '${_programs.length} — structure and courses live in "Academic structure"')),
                        OrgGrid(minTile: 300, children: [
                          for (final p in _programs)
                            _ProgramCard(
                              p: p,
                              onTap: () async {
                                await openDepartmentDashboard(context, unitType: 'program', unitId: asInt(p['id']), seed: p);
                                _load();
                              },
                            ),
                        ]),
                      ],
                    ]),
                  ),
      ),
    );
  }
}

class _DeptCard extends StatelessWidget {
  const _DeptCard({required this.d, required this.onTap, this.parentName, this.subCount = 0});
  final Map<String, dynamic> d;
  final VoidCallback onTap;
  final String? parentName;
  final int subCount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = hexColor(d['color'], c.primary);
    final counts = asMap(d['counts']);
    final head = asMap(d['head']);
    final attention = asInt(counts['open_complaints']) + asInt(counts['pending_forms']);
    return Material(
      color: c.cardBg,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: col.withValues(alpha: 0.25)),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [col.withValues(alpha: 0.12), c.cardBg, c.cardBg],
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              DeptLogo(d: d, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(orgNameOf(d), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: orgText(context, size: 15.5, w: FontWeight.w800)),
                  Text(head.isEmpty ? t('لم يُعيَّن رئيس بعد', 'No head yet') : '${t('الرئيس', 'Head')}: ${head['name']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, color: c.textMedium)),
                ]),
              ),
              if (attention > 0) OrgPill(t('$attention تنتظر', '$attention waiting'), color: c.warning),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if ((parentName ?? '').isNotEmpty)
                OrgPill(t('تابعة لـ $parentName', 'Part of $parentName'), icon: DirIcons.subArrowLeft, color: c.textMedium),
              if (subCount > 0) OrgPill(t('$subCount فرعية', '$subCount sub'), icon: Icons.account_tree_rounded, color: col),
              OrgPill(t('${asInt(counts['team'])} في الفريق', '${asInt(counts['team'])} team'), icon: Icons.groups_rounded, color: col),
              for (final f in (d['features'] as List? ?? const []))
                Icon(_featureIcons['$f'] ?? Icons.circle, size: 18, color: c.textLight),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// An academic department (OrgProgram): structure is edited in "Academic structure"; the card opens its dashboard.
class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.p, required this.onTap});
  final Map<String, dynamic> p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mgr = asMap(p['manager']);
    return Material(
      color: c.cardBg,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.purple.withValues(alpha: 0.25)),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [c.purple.withValues(alpha: 0.10), c.cardBg, c.cardBg],
            ),
          ),
          child: Row(children: [
            IconBadge(Icons.school_rounded, c.purple, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(orgNameOf(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 15.5, w: FontWeight.w800)),
                Text(mgr.isEmpty ? t('لم يُعيَّن مدير بعد', 'No manager yet') : '${t('المدير', 'Manager')}: ${mgr['name']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, color: c.textMedium)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if ('${p['code'] ?? ''}'.isNotEmpty) OrgPill('${p['code']}', icon: Icons.tag_rounded, color: c.purple),
                  OrgPill(t('${asInt(p['students'])} طالب', '${asInt(p['students'])} students'), icon: Icons.people_alt_rounded, color: c.primary),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Wizard: preset or custom
// ═════════════════════════════════════════════════════════════════════════════

Future<bool> showDepartmentWizard(BuildContext context, {Map<String, dynamic>? edit}) async {
  final s = context.read<OrgSession>();
  List<Map<String, dynamic>> presets = [];
  if (edit == null) {
    final r = await OrgApi.i.getMap('${s.base}/departments/presets');
    presets = asMapList(r?['items']);
  }
  if (!context.mounted) return false;
  String? preset;
  final ar = TextEditingController(text: '${edit?['name_ar'] ?? ''}');
  final en = TextEditingController(text: '${edit?['name_en'] ?? ''}');
  final desc = TextEditingController(text: '${edit?['description'] ?? ''}');
  final email = TextEditingController(text: '${edit?['email'] ?? ''}');
  final phone = TextEditingController(text: '${edit?['phone'] ?? ''}');
  final location = TextEditingController(text: '${edit?['location'] ?? ''}');
  final hours = TextEditingController(text: '${edit?['office_hours'] ?? ''}');
  String icon = '${edit?['icon'] ?? 'apartment'}';
  String? logo = edit?['logo_url'] as String?;
  String color = '${edit?['color'] ?? '#0F7B5F'}';
  // NB: `(x as List?) ?? map.keys` cast the keys (an Iterable) to List on web → the wizard crashed before opening.
  final features = <String>{
    ...(edit == null ? featureLabels().keys : ((edit['features'] as List?) ?? const []).map((e) => '$e')),
  };
  final origHead = asMap(edit?['head'])['id'] == null ? null : asInt(asMap(edit?['head'])['id']);
  int? head = origHead;
  final canHead = s.can('departments', edit == null ? 'insert' : 'update');
  // "part of" another department: a structure change (org-level right); never itself or its own subtree
  int parent = asInt(edit?['parent_id']);
  var parents = <Map<String, dynamic>>[];
  if (canHead) {
    final all = asMapList((await OrgApi.i.getMap('${s.base}/departments'))?['items']);
    final own = edit == null ? null : asInt(edit['id']);
    final blocked = <int>{?own};
    var grew = own != null;
    while (grew) {
      grew = false;
      for (final d in all) {
        if (d['parent_id'] != null && blocked.contains(asInt(d['parent_id'])) && blocked.add(asInt(d['id']))) grew = true;
      }
    }
    parents = all.where((d) => !blocked.contains(asInt(d['id']))).toList();
    if (!context.mounted) return false;
  }
  bool busy = false, saved = false;
  const palette = ['#0F7B5F', '#2563EB', '#7C3AED', '#DB2777', '#EA580C', '#0891B2', '#CA8A04', '#475569'];

  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        void pick(Map<String, dynamic> p) => set(() {
              preset = '${p['key']}';
              ar.text = '${p['name_ar']}';
              en.text = '${p['name_en']}';
              desc.text = t('${p['description_ar']}', '${p['description_en']}');
              icon = '${p['icon']}';
              color = '${p['color']}';
              features
                ..clear()
                ..addAll(((p['features'] as List?) ?? const []).map((e) => '$e'));
            });
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(edit == null ? t('إدارة خدمية جديدة', 'New service department') : t('تعديل الإدارة', 'Edit department')),
            if (edit == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                    t('الإدارات الخدمية: الإرشاد الأكاديمي، شؤون الطلاب، الامتحانات والكنترول، الخريجين، الرعاية الصحية، الشكاوى… أما الأقسام العلمية (نظم المعلومات، علوم الحاسب…) فتُدار من "الهيكل الأكاديمي".',
                        'Service departments: academic advising, student affairs, exams & control, alumni, healthcare, complaints… Academic departments (IS, CS, IT…) are managed in "Academic structure".'),
                    style: orgText(ctx, size: 12, color: c.textLight)),
              ),
            if (presets.isNotEmpty) ...[
              Text(t('ابدأ بإدارة جاهزة — أو اكتب اسماً خاصاً بالأسفل', 'Start from a ready-made one — or type your own below'),
                  style: orgText(ctx, size: 12.5, color: c.textMedium)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in presets)
                  ChoiceChip(
                    avatar: Icon(deptIcon(p['icon']), size: 16,
                        color: preset == p['key'] ? c.onHero : hexColor(p['color'], c.primary)),
                    label: Text(t('${p['name_ar']}', '${p['name_en']}'),
                        style: TextStyle(fontFamily: AppFonts.family, color: preset == p['key'] ? c.onHero : c.textDark)),
                    selected: preset == p['key'],
                    selectedColor: hexColor(p['color'], c.primary),
                    showCheckmark: false,
                    onSelected: (_) => pick(p),
                  ),
              ]),
              const Divider(height: 26),
            ],
            Field(controller: ar, label: t('الاسم بالعربية', 'Arabic name')),
            Field(controller: en, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
            Field(controller: desc, label: t('ماذا تقدم هذه الإدارة؟', 'What does it do?'), maxLines: 2),
            if (canHead && parents.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppDropdown<int>(
                  value: parent,
                  decoration: InputDecoration(labelText: t('تتبع إدارة أخرى؟', 'Part of another department?')),
                  items: [
                    DropdownMenuItem(value: 0, child: Text(t('لا — إدارة رئيسية', 'No — a top-level department'))),
                    for (final p in parents)
                      DropdownMenuItem(value: asInt(p['id']), child: Text(orgNameOf(p), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => set(() => parent = v ?? 0),
                ),
              ),
            if (canHead)
              OrgMemberPickField(
                label: t('رئيس / مدير الإدارة', 'Department head / manager'),
                value: head,
                initialName: asMap(edit?['head'])['name']?.toString(),
                roles: const ['teacher', 'teacher_assistant', 'admin_assistant', 'org_admin'],
                onChanged: (v) => set(() => head = v),
              ),
            // the department's own logo (cropped, resized, public) — replaces the icon everywhere
            Row(children: [
              if ((logo ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: ClipRRect(borderRadius: BorderRadius.circular(14),
                      child: Image.network(logo!, width: 52, height: 52, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(width: 52, height: 52))),
                ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final r = await orgPickAndUpload('/api/v1/org/logo', extensions: const ['png', 'jpg', 'jpeg', 'webp'],
                        context: ctx, cropShape: CropShape.square);
                    if (r != null) set(() => logo = '${r['url']}');
                  },
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: Text((logo ?? '').isEmpty ? t('رفع شعار الإدارة', 'Upload department logo') : t('تغيير الشعار', 'Change logo')),
                ),
              ),
              if ((logo ?? '').isNotEmpty)
                IconButton(tooltip: t('إزالة', 'Remove'), onPressed: () => set(() => logo = null), icon: Icon(Icons.close_rounded, color: c.textLight)),
            ]),
            const SizedBox(height: 12),
            Text(t('أو أيقونة ولون', 'or an icon and colour'), style: orgText(ctx, size: 12.5, color: c.textLight)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in deptIconChoices.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => set(() => icon = e.key),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: icon == e.key ? hexColor(color, c.primary).withValues(alpha: 0.18) : c.inputBg,
                      border: Border.all(color: icon == e.key ? hexColor(color, c.primary) : c.divider),
                    ),
                    child: Icon(e.value, size: 20, color: icon == e.key ? hexColor(color, c.primary) : c.textMedium),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 10, children: [
              for (final h in palette)
                GestureDetector(
                  onTap: () => set(() => color = h),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: hexColor(h, c.primary),
                      shape: BoxShape.circle,
                      border: Border.all(color: color == h ? c.textDark : Colors.transparent, width: 2.5),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            Text(t('الخدمات المفعّلة', 'Services switched on'), style: orgText(ctx, size: 12.5, color: c.textLight)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final e in featureLabels().entries)
                FilterChip(
                  avatar: Icon(_featureIcons[e.key], size: 16),
                  label: Text(e.value, style: TextStyle(fontFamily: AppFonts.family)),
                  selected: features.contains(e.key),
                  onSelected: (on) => set(() => on ? features.add(e.key) : features.remove(e.key)),
                ),
            ]),
            const SizedBox(height: 14),
            Text(t('كيف يصل إليها الطلاب؟ (يظهر في دليل الإدارات)', 'How do people reach it? (shown in the directory)'),
                style: orgText(ctx, size: 12.5, color: c.textLight)),
            const SizedBox(height: 6),
            Field(controller: location, label: t('المكان — مثلاً: مبنى ب، الدور الثاني', 'Where — e.g. Building B, 2nd floor')),
            Field(controller: hours, label: t('مواعيد العمل — مثلاً: الأحد–الخميس 9–2', 'Office hours — e.g. Sun–Thu 9–2')),
            AppEmailField(controller: email, label: t('البريد', 'E-mail')),
            PhoneInputField(controller: phone, label: t('الهاتف', 'Phone')),
            const SizedBox(height: 6),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                if (ar.text.trim().isEmpty && en.text.trim().isEmpty) {
                  toast(t('اكتب اسم الإدارة', 'Enter a name'), error: true);
                  return;
                }
                set(() => busy = true);
                final body = {
                  if (preset != null) 'preset': preset,
                  'name_ar': ar.text.trim(),
                  'name_en': en.text.trim(),
                  'description': desc.text.trim(),
                  'icon': icon,
                  'logo_url': logo,
                  'color': color,
                  'features': features.toList(),
                  'location': location.text.trim(),
                  'office_hours': hours.text.trim(),
                  'email': email.text.trim(),
                  'phone': phone.text.trim(),
                  if (canHead && head != null && head != origHead) 'head_user_id': head,
                  if (canHead && (edit != null || parent != 0)) 'parent_id': parent == 0 ? null : parent,
                };
                final r = edit == null
                    ? await OrgApi.i.post('${s.base}/departments', body, t('أُنشئت الإدارة 🎉', 'Department created 🎉'))
                    : await OrgApi.i.put('${s.base}/departments/${edit['id']}', body, t('تم الحفظ', 'Saved'));
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (r != null) {
                  saved = true;
                  Navigator.pop(ctx);
                }
              },
            ),
          ]),
        );
      }));
  return saved;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Department hub
// ═════════════════════════════════════════════════════════════════════════════

class OrgDepartmentHub extends StatefulWidget {
  const OrgDepartmentHub({super.key, required this.dept});
  final Map<String, dynamic> dept;

  @override
  State<OrgDepartmentHub> createState() => _OrgDepartmentHubState();
}

class _OrgDepartmentHubState extends State<OrgDepartmentHub> {
  late Map<String, dynamic> _d = widget.dept;

  int get _id => asInt(_d['id']);

  @override
  void initState() {
    super.initState();
    // the caller may hand over a light map (e.g. from the department dashboard) — fetch the full record
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final r = await OrgApi.i.getMap('${context.read<OrgSession>().base}/departments/$_id');
    if (r != null && mounted) setState(() => _d = r);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final col = hexColor(_d['color'], c.primary);
    final f = {...((_d['features'] as List?) ?? const []).map((e) => '$e')};
    bool can(String m, [String a = 'view']) => s.can(m, a, _id);

    final tabs = <(String, IconData, Widget)>[
      (t('نظرة عامة', 'Overview'), Icons.space_dashboard_rounded, _DeptOverview(d: _d, onChanged: _reload)),
      if (can('team')) (t('الفريق', 'Team'), Icons.groups_rounded, _DeptTeam(deptId: _id, onChanged: _reload)),
      if (f.contains('announcements') && can('announcements'))
        (t('الإعلانات', 'Ads'), Icons.campaign_rounded, OrgAnnouncementsPage(deptId: _id)),
      if (f.contains('forms') && can('forms')) (t('النماذج', 'Forms'), Icons.assignment_rounded, OrgFormsPage(deptId: _id)),
      if (f.contains('complaints') && can('complaints'))
        (t('الشكاوى', 'Complaints'), Icons.support_agent_rounded, OrgComplaintsPage(deptId: _id)),
      if (f.contains('materials') && can('materials')) (t('المكتبة', 'Library'), Icons.folder_copy_rounded, OrgMaterialsPage(deptId: _id)),
      if (f.contains('data_lab') && can('data_lab')) (t('مختبر البيانات', 'Data Lab'), Icons.science_rounded, _DeptDataLab(deptId: _id)),
      if (f.contains('certificates') && can('certificates'))
        (t('الشهادات', 'Certificates'), Icons.workspace_premium_rounded,
            CertificateDesignsScreen(orgId: asInt(s.currentId))),
      if (f.contains('members') && (can('team') || canConfigureUnit(s, 'dept', _id)))
        (t('الانضمام', 'Joining'), Icons.group_add_rounded,
            OrgUnitJoinHub(unitType: 'dept', unitId: _id, title: orgNameOf(_d), features: f.toList(), embedded: true)),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: BasePage(
        useWebCard: true,
        maxWith: 1100,
        appBar: ScreenAppBar(title: orgNameOf(_d), actions: [
          if (s.can('departments', 'update') || can('team', 'update'))
            IconButton(
              tooltip: t('تعديل', 'Edit'),
              onPressed: () async {
                if (await showDepartmentWizard(context, edit: _d)) _reload();
              },
              icon: const Icon(Icons.edit_rounded),
            ),
         const ContextExitButton()]),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(colors: [col, c.heroEnd(col, 0.25)]),
              boxShadow: [BoxShadow(color: col.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: c.onHero.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
                child: Icon(deptIcon(_d['icon']), color: c.onHero, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(orgNameOf(_d), style: TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w800, color: c.onHero)),
                  if ('${_d['description'] ?? ''}'.isNotEmpty)
                    Text('${_d['description']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5, color: c.onHero.withValues(alpha: 0.88))),
                ]),
              ),
            ]),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: col,
            indicatorColor: col,
            unselectedLabelColor: c.textMedium,
            labelStyle: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800),
            tabs: [for (final tb in tabs) Tab(icon: Icon(tb.$2, size: 20), text: tb.$1)],
          ),
          Expanded(child: TabBarView(children: [for (final tb in tabs) tb.$3])),
        ]),
      ),
    );
  }
}

class _DeptOverview extends StatelessWidget {
  const _DeptOverview({required this.d, required this.onChanged});
  final Map<String, dynamic> d;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = asMap(d['counts']);
    final head = asMap(d['head']);
    return ListView(padding: const EdgeInsets.only(top: 8, bottom: 40), children: [
      OrgGrid(children: [
        OrgStatTile(icon: Icons.groups_rounded, label: t('الفريق', 'Team'), value: k['team']),
        OrgStatTile(icon: Icons.support_agent_rounded, label: t('شكاوى مفتوحة', 'Open complaints'), value: k['open_complaints'],
            color: asInt(k['open_complaints']) > 0 ? c.warning : c.success),
        OrgStatTile(icon: Icons.assignment_late_rounded, label: t('طلبات بانتظار المراجعة', 'Requests to review'),
            value: k['pending_forms'], color: c.purple),
        OrgStatTile(icon: Icons.menu_book_rounded, label: t('المقررات', 'Courses'), value: k['courses'], color: c.accent),
        OrgStatTile(icon: Icons.folder_copy_rounded, label: t('ملفات', 'Files'), value: k['materials'], color: c.accent2),
        OrgStatTile(icon: Icons.campaign_rounded, label: t('إعلانات منشورة', 'Live ads'), value: k['announcements'], color: c.primary),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Section(
          title: t('بطاقة الإدارة', 'Department card'),
          icon: Icons.contact_mail_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('هكذا يراها الطلاب في دليل الإدارات', 'This is how students see it in the directory'),
                style: orgText(context, size: 12, color: c.textLight)),
            const SizedBox(height: 8),
            OrgInfoRow(Icons.person_rounded, head.isEmpty ? null : '${t('الرئيس', 'Head')}: ${head['name']}'),
            OrgInfoRow(Icons.place_rounded, '${d['location'] ?? ''}'),
            OrgInfoRow(Icons.schedule_rounded, '${d['office_hours'] ?? ''}'),
            OrgInfoRow(Icons.alternate_email_rounded, '${d['email'] ?? ''}', ltr: true),
            OrgInfoRow(Icons.phone_rounded, '${d['phone'] ?? ''}', ltr: true),
            if ('${d['location'] ?? ''}${d['office_hours'] ?? ''}${d['email'] ?? ''}'.isEmpty)
              Text(t('أضف المكان ومواعيد العمل ليعرف الطلاب كيف يصلون إليكم', 'Add the place and office hours so students know how to reach you'),
                  style: orgText(context, size: 12.5, color: c.warning)),
          ]),
        ),
      ),
    ]);
  }
}

class _DeptTeam extends StatelessWidget {
  const _DeptTeam({required this.deptId, required this.onChanged});
  final int deptId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => _TeamBody(deptId: deptId, onChanged: onChanged);
}

class _TeamBody extends StatefulWidget {
  const _TeamBody({required this.deptId, required this.onChanged});
  final int deptId;
  final VoidCallback onChanged;

  @override
  State<_TeamBody> createState() => _TeamBodyState();
}

class _TeamBodyState extends State<_TeamBody> {
  List<Map<String, dynamic>>? _rows;
  bool _failed = false;

  String get _url => '${context.read<OrgSession>().base}/departments/${widget.deptId}/team';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap(_url);
    if (!mounted) return;
    setState(() {
      _rows = r == null ? _rows : asMapList(r['items']);
      _failed = r == null && _rows == null;
    });
  }

  Future<void> _add() async {
    final s = context.read<OrgSession>();
    final r = await OrgApi.i.getMap('${s.base}/members',
        {'role': 'teacher,teacher_assistant,admin_assistant', 'size': 100});
    if (r == null || !mounted) return;
    final taken = {for (final x in _rows ?? const <Map<String, dynamic>>[]) asMap(x['user'])['id']};
    final people = asMapList(r['items']).where((m) => !taken.contains(asMap(m['user'])['id'])).toList();
    final title = TextEditingController();
    int? picked;
    bool head = false, busy = false;
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(t('إضافة للفريق', 'Add to the team')),
              if (people.isEmpty)
                Text(t('أضف المدرسين والإداريين أولاً من صفحة الأعضاء', 'Add teachers and staff first from the People page'),
                    style: orgText(ctx, color: c.textMedium))
              else
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final m in people)
                      ListTile(
                        onTap: () => set(() => picked = asInt(asMap(m['user'])['id'])),
                        leading: AdminAvatar(name: '${asMap(m['user'])['name']}', url: asMap(m['user'])['image_url'] as String?, size: 38),
                        title: Text('${asMap(m['user'])['name']}', style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
                        subtitle: Text('${asMap(m['user'])['email']}', textDirection: TextDirection.ltr),
                        trailing: Icon(
                            picked == asInt(asMap(m['user'])['id']) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: picked == asInt(asMap(m['user'])['id']) ? c.primary : c.textLight),
                      ),
                  ]),
                ),
              Field(controller: title, label: t('المسمى الوظيفي — مثلاً: مسؤول القيد', 'Job title — e.g. Registration officer')),
              if (s.can('departments', 'update'))
                OrgSwitchRow(
                    title: t('رئيس الإدارة', 'Head of department'),
                    subtitle: t('يحصل على كل صلاحيات الإدارة (قابلة للتعديل من الأدوار)', 'Gets every right in this department (editable in Roles)'),
                    value: head,
                    onChanged: (v) => set(() => head = v)),
              const SizedBox(height: 8),
              PrimaryButton(
                isLoading: busy,
                label: t('إضافة', 'Add'),
                onPressed: picked == null
                    ? null
                    : () async {
                        set(() => busy = true);
                        final res = await OrgApi.i.post(_url, {'user_id': picked, 'title': title.text.trim(), 'is_head': head},
                            t('انضم للفريق 👋', 'Joined the team 👋'));
                        if (!ctx.mounted) return;
                        set(() => busy = false);
                        if (res != null) Navigator.pop(ctx);
                      },
              ),
            ]),
          );
        }));
    _load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final rows = _rows;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: s.can('team', 'insert', widget.deptId)
          ? FloatingActionButton.extended(
              heroTag: 'team_add',
              backgroundColor: c.primary,
              onPressed: _add,
              icon: Icon(Icons.person_add_alt_1_rounded, color: c.onHero),
              label: Text(t('إضافة', 'Add'), style: TextStyle(fontFamily: AppFonts.family, color: c.onHero)),
            )
          : null,
      body: OrgAsync(
        loading: rows == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: rows == null
            ? const SizedBox.shrink()
            : rows.isEmpty
                ? OrgEmpty(icon: Icons.groups_rounded, title: t('الفريق فارغ', 'No team yet'),
                    message: t('أضف رئيس الإدارة والموظفين — صلاحياتهم تُمنح تلقائياً لهذه الإدارة فقط.',
                        'Add the head and staff — their rights apply to this department only, automatically.'))
                : ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 100), children: [
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: RowCard(
                          accent: r['is_head'] == true ? c.warning : null,
                          child: Row(children: [
                            AdminAvatar(name: '${asMap(r['user'])['name']}', url: asMap(r['user'])['image_url'] as String?),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Flexible(child: Text('${asMap(r['user'])['name']}', style: orgText(context, w: FontWeight.w800))),
                                  if (r['is_head'] == true) ...[
                                    const SizedBox(width: 6),
                                    OrgPill(t('الرئيس', 'Head'), color: c.warning, icon: Icons.star_rounded),
                                  ],
                                ]),
                                Text('${r['title'] ?? t('عضو الفريق', 'Team member')}', style: orgText(context, size: 12, color: c.textMedium)),
                              ]),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (v) async {
                                final url = '$_url/${r['id']}';
                                if (v == 'title') {
                                  final tx = await askText(context, title: t('المسمى الوظيفي', 'Job title'), hint: '${r['title'] ?? ''}');
                                  if (tx != null) await OrgApi.i.put(url, {'title': tx}, t('تم', 'Done'));
                                } else if (v == 'head') {
                                  await OrgApi.i.put(url, {'is_head': r['is_head'] != true}, t('تم', 'Done'));
                                } else if (await confirm(context, message: t('إخراج من الفريق؟ تُسحب صلاحياته في هذه الإدارة.', 'Remove from the team? Their rights here are withdrawn.'), danger: true)) {
                                  await OrgApi.i.del(url, t('تم', 'Done'));
                                }
                                _load();
                                widget.onChanged();
                              },
                              itemBuilder: (_) => [
                                if (s.can('team', 'update', widget.deptId)) PopupMenuItem(value: 'title', child: Text(t('تعديل المسمى', 'Edit title'))),
                                if (s.can('departments', 'update'))
                                  PopupMenuItem(value: 'head', child: Text(r['is_head'] == true ? t('إلغاء الرئاسة', 'Remove as head') : t('تعيين رئيساً', 'Make head'))),
                                if (s.can('team', 'delete', widget.deptId))
                                  PopupMenuItem(value: 'del', child: Text(t('إخراج', 'Remove'), style: TextStyle(color: c.danger))),
                              ],
                            ),
                          ]),
                        ),
                      ),
                  ]),
      ),
    );
  }
}

class _DeptDataLab extends StatefulWidget {
  const _DeptDataLab({required this.deptId});
  final int deptId;

  @override
  State<_DeptDataLab> createState() => _DeptDataLabState();
}

class _DeptDataLabState extends State<_DeptDataLab> {
  List<Map<String, dynamic>>? _rows;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap('${context.read<OrgSession>().base}/departments/${widget.deptId}/data-lab');
    if (!mounted) return;
    setState(() {
      _rows = r == null ? _rows : asMapList(r['items']);
      _failed = r == null && _rows == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _rows;
    return OrgAsync(
      loading: rows == null && !_failed,
      failed: _failed,
      onRetry: _load,
      child: rows == null
          ? const SizedBox.shrink()
          : rows.isEmpty
              ? OrgEmpty(icon: Icons.science_rounded, title: t('لا مقررات مرتبطة بالإدارة', 'No courses linked to this department'),
                  message: t('اربط المقررات بالإدارة من صفحة المقررات لتظهر درجاتها هنا.',
                      'Link courses to this department from the Courses page to see their grades here.'))
              : ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 40), children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: OrgActionCard(
                        icon: Icons.table_chart_rounded,
                        color: r['enabled'] == true ? c.primary : c.textLight,
                        title: '${r['title']}',
                        subtitle: '${r['teacher'] ?? ''} · ${t('${r['students']} طالب', '${r['students']} students')}'
                            '${r['can_edit'] == true ? '' : ' · ${t('عرض فقط', 'view only')}'}',
                        onTap: r['enabled'] == true
                            ? () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => DataLabScreen(courseId: asInt(r['course_id']), courseTitle: '${r['title']}')))
                            : () => toast(t('مختبر البيانات مغلق لهذا المقرر', 'Data Lab is off for this course'), error: true),
                      ),
                    ),
                ]),
    );
  }
}


/// The department's uploaded logo, or its icon badge.
class DeptLogo extends StatelessWidget {
  const DeptLogo({super.key, required this.d, this.size = 44});
  final Map<String, dynamic> d;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = '${d['logo_url'] ?? ''}';
    if (logo.isEmpty) return IconBadge(deptIcon(d['icon']), hexColor(d['color'], context.colors.primary), size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Image.network(logo, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => IconBadge(deptIcon(d['icon']), hexColor(d['color'], context.colors.primary), size: size)),
    );
  }
}
