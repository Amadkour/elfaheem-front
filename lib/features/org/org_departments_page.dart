// lib/features/org/org_departments_page.dart
//
//   OrgDepartmentsPage   every department I can see (sub-departments under their parent, plus the academic
//                        departments when I may see them) — tapping one opens its dashboard (org_department_dashboard.dart)
//   showDepartmentWizard ready-made departments (HR, Finance, الإرشاد الأكاديمي, Controls …) or a custom one
//   OrgDepartmentHub     one department: Overview · Team · Ads · Forms · Complaints · Library · Data Lab · Certificates
//                        (a tab exists only when the service is switched on AND I have the right in that department)
library;

import 'package:flutter_education_app/design/app_mesh.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_buttons.dart' show AppButton;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_department_dashboard.dart' show openDepartmentDashboard;
import 'org_providers.dart';
import 'org_page_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'org_services_pages.dart';
import 'org_join_pages.dart' show OrgUnitJoinHub, canConfigureUnit;
import 'org_member_form.dart' show OrgMemberPickField;
import 'org_ui.dart';
import 'package:flutter_education_app/design/app_inputs.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppDropdown, AppRefresh;
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'org_page_header.dart' show OrgHeaderButton, OrgPushedPage;
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
  String _query = '';

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
    final s = context.watch<OrgSession>();
    final items = _items;
    Future<void> create() async {
      if (await showDepartmentWizard(context)) _load();
    }

    final q = _query.trim().toLowerCase();
    bool hit(Map<String, dynamic> d) =>
        q.isEmpty || '${d['name_ar'] ?? ''} ${d['name_en'] ?? ''} ${d['code'] ?? ''}'.toLowerCase().contains(q);
    final shown = items == null ? const <(Map<String, dynamic>, int)>[] : [for (final x in _ordered(items)) if (hit(x.$1)) x];
    final programs = [for (final p in _programs) if (hit(p)) p];
    final any = (items?.length ?? 0) + _programs.length > 0;
    final Widget body;
    if (items == null) {
      body = OrgAsync(loading: !_failed, failed: _failed, onRetry: _load, child: const SizedBox.shrink());
    } else if (!any) {
      body = OrgEmpty(
        icon: Icons.apartment_rounded,
        title: t('نظّم مؤسستك في إدارات', 'Organize your institution into departments'),
        message: t('شؤون الطلاب، الموارد البشرية، الكنترول، الإرشاد الأكاديمي… لكل إدارة فريقها وخدماتها.',
            'Student affairs, HR, controls, academic advising… each with its own team and services.'),
        actionLabel: _canCreate ? t('إضافة أول إدارة', 'Add the first department') : null,
        onAction: create,
      );
    } else if (shown.isEmpty && programs.isEmpty) {
      body = OrgEmpty(
        icon: Icons.search_off_rounded,
        title: t('لا نتائج لـ "$_query"', 'Nothing matches "$_query"'),
        message: t('جرّب اسماً آخر أو امسح البحث.', 'Try another name or clear the search.'),
      );
    } else {
      body = AppRefresh(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: AppSpace.xxs, bottom: AppSpace.xxl + AppTouch.primary),
          children: [
            if (shown.isNotEmpty) ...[
              OrgSectionHeading(
                t('الإدارات الخدمية', 'Service departments'),
                subtitle: t('${items.length} في ${s.name} — اضغط إدارة لفتح لوحتها', '${items.length} in ${s.name} — tap one to open it'),
              ),
              OrgGrid(minTile: 320, padding: const EdgeInsets.symmetric(horizontal: AppSpace.md), children: [
                for (final (d, depth) in shown)
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
            ],
            if (programs.isNotEmpty) ...[
              OrgSectionHeading(
                t('الأقسام العلمية', 'Academic departments'),
                subtitle: t('${_programs.length} قسم — الهيكل والمقررات في "الهيكل الأكاديمي"',
                    '${_programs.length} — structure and courses live in "Academic structure"'),
              ),
              OrgGrid(minTile: 320, padding: const EdgeInsets.symmetric(horizontal: AppSpace.md), children: [
                for (final p in programs)
                  _ProgramCard(
                    p: p,
                    onTap: () async {
                      await openDepartmentDashboard(context, unitType: 'program', unitId: asInt(p['id']), seed: p);
                      _load();
                    },
                  ),
              ]),
            ],
          ],
        ),
      );
    }
    return OrgPageBody(
      primary: _canCreate
          ? OrgPrimaryAction(id: 'new_department', icon: Icons.add_business_rounded, label: t('إدارة جديدة', 'New department'), onTap: create)
          : null,
      // a search only once there is something to look through
      search: any && (items!.length + _programs.length) > 3
          ? OrgSearchField(hint: t('ابحث عن إدارة أو قسم', 'Find a department'), onChanged: (v) => setState(() => _query = v))
          : null,
      child: body,
    );
  }
}

/// The calm card of a department (D-102 language): card surface + hairline, its logo, name (w600), head, and one
/// line of facts; the waiting count is the card's one accent.
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
    return _UnitCard(
      onTap: onTap,
      leading: DeptLogo(d: d, size: 44),
      title: orgNameOf(d),
      meta: head.isEmpty ? t('لم يُعيَّن رئيس بعد', 'No head yet') : '${t('الرئيس', 'Head')}: ${head['name']}',
      badge: attention > 0 ? OrgPill(t('$attention تنتظر', '$attention waiting'), color: c.warning) : null,
      facts: [
        if ((parentName ?? '').isNotEmpty)
          OrgPill(t('تابعة لـ $parentName', 'Part of $parentName'), icon: DirIcons.subArrowLeft, color: c.textMedium),
        if (subCount > 0) OrgPill(t('$subCount فرعية', '$subCount sub'), icon: Icons.account_tree_rounded, color: col),
        OrgPill(t('${asInt(counts['team'])} في الفريق', '${asInt(counts['team'])} team'), icon: Icons.groups_rounded, color: col),
      ],
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
    return _UnitCard(
      onTap: onTap,
      leading: IconBadge(Icons.school_rounded, c.purple, size: 44),
      title: orgNameOf(p),
      meta: mgr.isEmpty ? t('لم يُعيَّن مدير بعد', 'No manager yet') : '${t('المدير', 'Manager')}: ${mgr['name']}',
      facts: [
        if ('${p['code'] ?? ''}'.isNotEmpty) OrgPill('${p['code']}', icon: Icons.tag_rounded, color: c.purple),
        OrgPill(t('${asInt(p['students'])} طالب', '${asInt(p['students'])} students'), icon: Icons.people_alt_rounded, color: c.primary),
      ],
    );
  }
}

/// One unit card: [leading] · title + meta (+ [badge]) · a row of [facts] · chevron.
class _UnitCard extends StatelessWidget {
  const _UnitCard({required this.onTap, required this.leading, required this.title, required this.meta, this.facts = const [], this.badge});
  final VoidCallback onTap;
  final Widget leading;
  final String title, meta;
  final List<Widget> facts;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.divider)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: AppSpace.card,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            leading,
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                const SizedBox(height: AppSpace.xxs),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                if (badge != null || facts.isNotEmpty) ...[
                  AppSpace.gapXs,
                  Wrap(spacing: AppSpace.xs - 2, runSpacing: AppSpace.xs - 2, children: [?badge, ...facts]),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, top: AppSpace.sm),
              child: Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
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
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(edit == null ? t('إدارة خدمية جديدة', 'New service department') : t('تعديل الإدارة', 'Edit department')),
            if (edit == null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Text(
                    t('الإدارات الخدمية: الإرشاد الأكاديمي، شؤون الطلاب، الامتحانات والكنترول، الخريجين، الرعاية الصحية، الشكاوى… أما الأقسام العلمية (نظم المعلومات، علوم الحاسب…) فتُدار من "الهيكل الأكاديمي".',
                        'Service departments: academic advising, student affairs, exams & control, alumni, healthcare, complaints… Academic departments (IS, CS, IT…) are managed in "Academic structure".'),
                    style: AppType.meta(ctx).copyWith(color: c.textLight)),
              ),
            if (presets.isNotEmpty) ...[
              Text(t('ابدأ بإدارة جاهزة — أو اكتب اسماً خاصاً بالأسفل', 'Start from a ready-made one — or type your own below'),
                  style: AppType.label(ctx).copyWith(color: c.textMedium)),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in presets)
                  ChoiceChip(
                    avatar: Icon(deptIcon(p['icon']), size: AppIconSize.sm,
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
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
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
                  padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
                  child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.control),
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
            const SizedBox(height: AppSpace.sm),
            Text(t('أو أيقونة ولون', 'or an icon and colour'), style: AppType.label(ctx).copyWith(color: c.textLight)),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in deptIconChoices.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: () => set(() => icon = e.key),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpace.xs),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      color: icon == e.key ? hexColor(color, c.primary).withValues(alpha: 0.18) : c.inputBg,
                      border: Border.all(color: icon == e.key ? hexColor(color, c.primary) : c.divider),
                    ),
                    child: Icon(e.value, size: AppIconSize.md, color: icon == e.key ? hexColor(color, c.primary) : c.textMedium),
                  ),
                ),
            ]),
            const SizedBox(height: AppSpace.sm),
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
            const SizedBox(height: AppSpace.md),
            Text(t('الخدمات المفعّلة', 'Services switched on'), style: AppType.label(ctx).copyWith(color: c.textLight)),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final e in featureLabels().entries)
                FilterChip(
                  avatar: Icon(_featureIcons[e.key], size: AppIconSize.sm),
                  label: Text(e.value, style: TextStyle(fontFamily: AppFonts.family)),
                  selected: features.contains(e.key),
                  onSelected: (on) => set(() => on ? features.add(e.key) : features.remove(e.key)),
                ),
            ]),
            const SizedBox(height: AppSpace.md),
            Text(t('كيف يصل إليها الطلاب؟ (يظهر في دليل الإدارات)', 'How do people reach it? (shown in the directory)'),
                style: AppType.label(ctx).copyWith(color: c.textLight)),
            const SizedBox(height: AppSpace.xs),
            Field(controller: location, label: t('المكان — مثلاً: مبنى ب، الدور الثاني', 'Where — e.g. Building B, 2nd floor')),
            Field(controller: hours, label: t('مواعيد العمل — مثلاً: الأحد–الخميس 9–2', 'Office hours — e.g. Sun–Thu 9–2')),
            AppEmailField(controller: email, label: t('البريد', 'E-mail')),
            PhoneInputField(controller: phone, label: t('الهاتف', 'Phone')),
            const SizedBox(height: AppSpace.xs),
            AppButton.primary(
              busy: busy,
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
            deferredCertificateDesigns(orgId: asInt(s.currentId))),
      if (f.contains('members') && (can('team') || canConfigureUnit(s, 'dept', _id)))
        (t('الانضمام', 'Joining'), Icons.group_add_rounded,
            OrgUnitJoinHub(unitType: 'dept', unitId: _id, title: orgNameOf(_d), features: f.toList(), embedded: true)),
    ];

    return DefaultTabController(
      length: tabs.length,
      // the dashboard's shared header (Back · name · Edit · Refresh · calendar · bell · switcher)
      child: OrgPushedPage(
        title: orgNameOf(_d),
        primaryAction: s.can('departments', 'update') || can('team', 'update')
            ? OrgHeaderButton(
                icon: Icons.edit_rounded,
                label: t('تعديل', 'Edit'),
                tooltip: t('تعديل الإدارة', 'Edit department'),
                onTap: () async {
                  if (await showDepartmentWizard(context, edit: _d)) _reload();
                },
              )
            : null,
        child: Column(children: [
          Container(margin: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxs), decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.block), boxShadow: [BoxShadow(color: col.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))]), child: AppMeshSurface(color: col, radius: BorderRadius.circular(AppRadius.block), child: Padding(padding: const EdgeInsets.all(AppSpace.md), child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: c.onHero.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(AppRadius.card)),
                child: Icon(deptIcon(_d['icon']), color: c.onHero, size: AppIconSize.xl),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(orgNameOf(_d), style: AppType.section(context).copyWith(color: c.onHero)),
                  if ('${_d['description'] ?? ''}'.isNotEmpty)
                    Text('${_d['description']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
                ]),
              ),
            ])))),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: col,
            indicatorColor: col,
            unselectedLabelColor: c.textMedium,
            labelStyle: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800),
            tabs: [for (final tb in tabs) Tab(icon: Icon(tb.$2, size: AppIconSize.md), text: tb.$1)],
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
    return ListView(padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xxl), children: [
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
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, 0),
        child: Section(
          title: t('بطاقة الإدارة', 'Department card'),
          icon: Icons.contact_mail_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('هكذا يراها الطلاب في دليل الإدارات', 'This is how students see it in the directory'),
                style: AppType.meta(context).copyWith(color: c.textLight)),
            const SizedBox(height: AppSpace.xs),
            OrgInfoRow(Icons.person_rounded, head.isEmpty ? null : '${t('الرئيس', 'Head')}: ${head['name']}'),
            OrgInfoRow(Icons.place_rounded, '${d['location'] ?? ''}'),
            OrgInfoRow(Icons.schedule_rounded, '${d['office_hours'] ?? ''}'),
            OrgInfoRow(Icons.alternate_email_rounded, '${d['email'] ?? ''}', ltr: true),
            OrgInfoRow(Icons.phone_rounded, '${d['phone'] ?? ''}', ltr: true),
            if ('${d['location'] ?? ''}${d['office_hours'] ?? ''}${d['email'] ?? ''}'.isEmpty)
              Text(t('أضف المكان ومواعيد العمل ليعرف الطلاب كيف يصلون إليكم', 'Add the place and office hours so students know how to reach you'),
                  style: AppType.label(context).copyWith(color: c.warning)),
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
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(t('إضافة للفريق', 'Add to the team')),
              if (people.isEmpty)
                Text(t('أضف المدرسين والإداريين أولاً من صفحة الأعضاء', 'Add teachers and staff first from the People page'),
                    style: AppType.row(ctx).copyWith(color: c.textMedium))
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
              const SizedBox(height: AppSpace.xs),
              AppButton.primary(
                busy: busy,
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
                : ListView(padding: const EdgeInsets.fromLTRB(0, AppSpace.xs, 0, AppSpace.xxxl + AppSpace.xl), children: [
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
                        child: RowCard(
                          accent: r['is_head'] == true ? c.warning : null,
                          child: Row(children: [
                            AdminAvatar(name: '${asMap(r['user'])['name']}', url: asMap(r['user'])['image_url'] as String?),
                            const SizedBox(width: AppSpace.sm),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Flexible(child: Text('${asMap(r['user'])['name']}', style: AppType.bodyStrong(context))),
                                  if (r['is_head'] == true) ...[
                                    const SizedBox(width: AppSpace.xs),
                                    OrgPill(t('الرئيس', 'Head'), color: c.warning, icon: Icons.star_rounded),
                                  ],
                                ]),
                                Text('${r['title'] ?? t('عضو الفريق', 'Team member')}', style: AppType.meta(context).copyWith(color: c.textMedium)),
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
              : ListView(padding: const EdgeInsets.fromLTRB(0, AppSpace.xs, 0, AppSpace.xxl), children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
                      child: OrgActionCard(
                        icon: Icons.table_chart_rounded,
                        color: r['enabled'] == true ? c.primary : c.textLight,
                        title: '${r['title']}',
                        subtitle: '${r['teacher'] ?? ''} · ${t('${r['students']} طالب', '${r['students']} students')}'
                            '${r['can_edit'] == true ? '' : ' · ${t('عرض فقط', 'view only')}'}',
                        onTap: r['enabled'] == true
                            ? () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => deferredDataLab(courseId: asInt(r['course_id']), courseTitle: '${r['title']}')))
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
