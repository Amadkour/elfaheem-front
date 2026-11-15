// lib/features/org/governance/gov_entities_page.dart — the entities of the governance module (spec §4 "Entities
// & categories"): service departments · scientific departments (with their councils) · offices · custom units.
//
//   GovEntitiesPage          grouped cards (name · head · members · open / pending decision / overdue), create
//                            (DeptIn + kind + program → POST …/entities), change kind (PATCH …/entities/{id})
//   GovEntityCard            presentational card (layout-tested)
//   GovEntityDetailPage      tabs Items (GovItemsPage) · Categories (CRUD) · Delegations (GovDelegationsPage) ·
//                            Approval chain (GovChainEditorPage, D-141; the org admin edits it) ·
//                            Automatic routing (GovAutoRoutingPage, D-971)
//   showGovCategorySheet     create / edit a category (kind · names · description · form link · order)
library;

import '../org_page_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show SheetHeader, asInt, asMap, asMapList, t;
import '../../admin/admin_list.dart' show AdminAvatar;
import '../org_unit_rules.dart' show ActingChip, CoreUnitBadge, UnitHeadPicker, headProblem, headRequiredText, unitHeadOf, unitIsCore;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_providers.dart' show OrgApi, OrgSession, orgBase;
import '../org_ui.dart' show orgNameOf;
import '../org_v3.dart' show orgCall, orgErrorText;
import 'gov_api.dart';
import 'gov_delegations_page.dart';
import 'gov_items_page.dart';
import 'gov_models.dart';
import 'gov_institutions_s3.dart' show GovAutoRoutingPage;
import 'gov_request_parts.dart' show GovChainEditorPage;
import 'gov_ui.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Card
// ═════════════════════════════════════════════════════════════════════════════

class GovEntityCard extends StatelessWidget {
  const GovEntityCard({super.key, required this.entity, this.council, this.onTap, this.onChangeKind, this.onOpenCouncil});
  final Entity entity;

  /// The council of a scientific department (shown as a sub-row).
  final Entity? council;
  final VoidCallback? onTap, onChangeKind, onOpenCouncil;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entity;
    return AppCard(
      margin: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
      padding: const EdgeInsets.all(AppSpace.sm),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Icon(govKindIcon(e.kind), color: c.primary, size: AppIconSize.lg),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
              const SizedBox(height: AppSpace.xxs / 2),
              Text(
                [
                  entityKindLabel(e.kind),
                  if (e.code.isNotEmpty) e.code,
                  t('${e.members} عضو', '${e.members} members'),
                  if (!e.isActive) t('موقوفة', 'Inactive'),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(color: c.textMedium),
              ),
              const SizedBox(height: AppSpace.xs),
              Row(children: [
                if (e.head != null) ...[
                  AdminAvatar(name: e.head!.name, url: e.head!.avatar, size: 22),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: Text('${t('الرئيس', 'Head')}: ${e.head!.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark))),
                  if (unitHeadOf(e.raw)?.acting ?? false) ...[const SizedBox(width: AppSpace.xs), const ActingChip()],
                ] else
                  Expanded(child: Text(t('بلا رئيس بعد', 'No head yet'), style: AppType.meta(context).copyWith(color: c.warning))),
              ]),
            ]),
          ),
          if (onChangeKind != null)
            IconButton(visualDensity: VisualDensity.compact, tooltip: t('تغيير النوع', 'Change kind'), onPressed: onChangeKind, icon: Icon(Icons.swap_vert_rounded, size: AppIconSize.md, color: c.textLight)),
        ]),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
          AppBadgePill('${t('مفتوحة', 'Open')} ${e.counts.open}', color: c.primary, icon: Icons.inbox_rounded),
          AppBadgePill('${t('بانتظار القرار', 'Pending decision')} ${e.counts.pendingDecision}', color: c.warning, icon: Icons.gavel_rounded),
          if (e.counts.overdue > 0) AppBadgePill('${t('متأخرة', 'Overdue')} ${e.counts.overdue}', color: c.danger, icon: Icons.timer_off_rounded),
          if (!e.acceptsComplaints && !e.isCouncil) AppBadgePill(t('لا تستقبل شكاوى', 'No complaints'), color: c.textLight, icon: Icons.block_rounded),
          if (e.can['decide']) AppBadgePill(t('أقرّر هنا', 'I decide here'), color: c.success, icon: Icons.verified_rounded),
          if (unitIsCore(e.raw)) const CoreUnitBadge(),
        ]),
        if (council != null) ...[
          const SizedBox(height: AppSpace.xs),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: onOpenCouncil,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              decoration: BoxDecoration(color: c.purple.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(AppRadius.control)),
              child: Row(children: [
                Icon(Icons.groups_2_rounded, size: AppIconSize.md, color: c.purple),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(council!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark))),
                Text(t('${council!.members} عضو', '${council!.members} members'), style: AppType.meta(context).copyWith(color: c.textMedium)),
                if (onOpenCouncil != null) Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Create entity · change kind
// ═════════════════════════════════════════════════════════════════════════════

/// Creates an entity (the department fields the existing form sends + `kind` + `program_id`). True when created.
Future<bool> showGovEntitySheet(BuildContext context, GovApi api, {List<Map<String, dynamic>> programs = const []}) async {
  final ar = TextEditingController(), en = TextEditingController(), desc = TextEditingController();
  var kind = 'service';
  int? head, program;
  // Institutions v2 (D-980): a head is required; "Assign me as head" sends head_self
  var headSelf = false;
  String? headErr;
  var acceptsComplaints = true, busy = false;
  final r = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(t('جهة جديدة', 'New entity')),
            Text(t('النوع', 'Kind'), style: AppType.meta(ctx).copyWith(color: c.textLight)),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final k in entityKinds.where((k) => k != 'council'))
                AppChoiceChip(label: entityKindLabel(k), icon: govKindIcon(k), selected: kind == k, onTap: () => set(() => kind = k)),
            ]),
            if (kind == 'scientific') ...[
              const SizedBox(height: AppSpace.xs),
              AppBanner(icon: Icons.groups_2_rounded, color: c.purple, text: t('يُنشأ مجلس القسم تلقائياً مع القسم العلمي، ورئيسه رئيس القسم', 'A department council is created with a scientific department; its head chairs it')),
            ],
            const SizedBox(height: AppSpace.sm),
            AppField(controller: ar, label: t('الاسم بالعربية', 'Arabic name')),
            const SizedBox(height: AppSpace.sm),
            AppField(controller: en, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
            const SizedBox(height: AppSpace.sm),
            AppField(controller: desc, label: t('ماذا تفعل هذه الجهة؟', 'What does it do?'), maxLines: 2),
            const SizedBox(height: AppSpace.sm),
            if (kind == 'scientific' && programs.isNotEmpty) ...[
              AppDropdown<int>(
                value: program ?? 0,
                decoration: InputDecoration(labelText: t('القسم الأكاديمي الذي تمثّله', 'Academic department it stands for'), prefixIcon: const Icon(Icons.school_rounded)),
                items: [
                  DropdownMenuItem(value: 0, child: Text(t('بدون', 'None'))),
                  for (final p in programs) DropdownMenuItem(value: asInt(p['id']), child: Text(orgNameOf(p), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => set(() => program = v == 0 ? null : v),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            UnitHeadPicker(
              label: t('رئيس الجهة', 'Entity head'),
              value: head,
              self: headSelf,
              error: headErr,
              roles: const ['teacher', 'teacher_assistant', 'admin_assistant', 'org_admin'],
              onChanged: (v, me) => set(() {
                head = v;
                headSelf = me;
                headErr = null;
              }),
            ),
            AppSwitchTile(
              icon: Icons.support_agent_rounded,
              title: t('تستقبل شكاوى من الأعضاء', 'Accepts complaints from members'),
              value: acceptsComplaints,
              onChanged: (v) => set(() => acceptsComplaints = v),
            ),
            const SizedBox(height: AppSpace.xs),
            AppPrimaryButton(
              label: t('إنشاء', 'Create'),
              icon: Icons.add_rounded,
              busy: busy,
              onPressed: () async {
                if (ar.text.trim().isEmpty && en.text.trim().isEmpty) {
                  appToast(t('اكتب اسم الجهة', 'Enter a name'), error: true);
                  return;
                }
                final noHead = headProblem(head: head, self: headSelf);
                if (noHead != null) {
                  set(() => headErr = noHead);
                  showAppNotice(noHead, error: true);
                  return;
                }
                set(() => busy = true);
                final res = await orgCall(() => api.createEntity({
                      'kind': kind,
                      'name_ar': ar.text.trim(),
                      'name_en': en.text.trim(),
                      'description': desc.text.trim(),
                      'features': const ['complaints', 'forms', 'announcements', 'materials'],
                      'accepts_complaints': acceptsComplaints,
                      if (headSelf) 'head_self': true else 'head_user_id': ?head,
                      'program_id': ?program,
                    }));
                if (!ctx.mounted) return;
                set(() {
                  busy = false;
                  if (res.code == 'head_required') headErr = headRequiredText();
                });
                if (res.ok) {
                  appToast(t('أُنشئت الجهة 🎉', 'Entity created 🎉'));
                  Navigator.pop(ctx, true);
                }
              },
            ),
          ]),
        );
      }));
  return r == true;
}

Future<bool> showGovKindSheet(BuildContext context, GovApi api, Entity e, {List<Map<String, dynamic>> programs = const []}) async {
  var kind = e.kind;
  int? program = e.programId;
  var busy = false;
  final r = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader('${t('نوع', 'Kind of')} ${e.name}'),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final k in entityKinds.where((k) => k != 'council'))
                AppChoiceChip(label: entityKindLabel(k), icon: govKindIcon(k), selected: kind == k, onTap: () => set(() => kind = k)),
            ]),
            if (kind == 'scientific' && e.kind != 'scientific') ...[
              const SizedBox(height: AppSpace.xs),
              AppBanner(icon: Icons.groups_2_rounded, color: c.purple, text: t('سيُنشأ مجلس القسم مع التغيير', 'The department council is created with the change')),
            ],
            if (kind == 'scientific' && programs.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              AppDropdown<int>(
                value: program ?? 0,
                decoration: InputDecoration(labelText: t('القسم الأكاديمي', 'Academic department'), prefixIcon: const Icon(Icons.school_rounded)),
                items: [
                  DropdownMenuItem(value: 0, child: Text(t('بدون', 'None'))),
                  for (final p in programs) DropdownMenuItem(value: asInt(p['id']), child: Text(orgNameOf(p), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => set(() => program = v == 0 ? null : v),
              ),
            ],
            const SizedBox(height: AppSpace.md),
            AppPrimaryButton(
              label: t('حفظ', 'Save'),
              icon: Icons.save_rounded,
              busy: busy,
              onPressed: () async {
                set(() => busy = true);
                final res = await orgCall(() => api.patchEntity(e.id, {'kind': kind, 'program_id': program}), ok: t('تم الحفظ', 'Saved'));
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (res.ok) Navigator.pop(ctx, true);
              },
            ),
          ]),
        );
      }));
  return r == true;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class GovEntitiesPage extends StatefulWidget {
  const GovEntitiesPage({super.key, this.embedded = false, this.orgId});
  final bool embedded;
  final int? orgId;

  @override
  State<GovEntitiesPage> createState() => _GovEntitiesPageState();
}

class _GovEntitiesPageState extends State<GovEntitiesPage> {
  late GovApi _api;
  List<Entity>? _rows;
  List<Map<String, dynamic>> _programs = const [];
  bool _failed = false, _missing = false;

  int get _orgId => widget.orgId ?? context.read<OrgSession>().currentId ?? 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _api = GovApi(_orgId);
      _load();
      _loadPrograms();
    });
  }

  Future<void> _load() async {
    final r = await orgCall(() => _api.entities(), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _rows = r.data as List<Entity>;
        _failed = false;
      } else {
        _failed = _rows == null;
        _missing = r.endpointMissing;
        if (_rows != null) appToast(orgErrorText(r.error!), error: true);
      }
    });
  }

  Future<void> _loadPrograms() async {
    final r = await OrgApi.i.getMap('$orgBase/orgs/$_orgId/academic/programs');
    if (mounted && r != null) setState(() => _programs = asMapList(r['items']));
  }

  Future<void> _open(Entity e) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GovEntityDetailPage(e, orgId: _orgId)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final canCreate = s.isOrgAdmin || s.can('departments', 'insert');
    final rows = _rows ?? const <Entity>[];
    final councils = {for (final e in rows.where((e) => e.isCouncil)) e.id: e};
    final groups = <String, List<Entity>>{
      'service': rows.where((e) => e.kind == 'service').toList(),
      'scientific': rows.where((e) => e.kind == 'scientific').toList(),
      'office': rows.where((e) => e.kind == 'office').toList(),
      'custom': rows.where((e) => e.kind == 'custom').toList(),
      'council': rows.where((e) => e.isCouncil && !rows.any((p) => p.councilId == e.id)).toList(), // faculty council etc.
    };
    Widget body;
    if (_rows == null && !_failed) {
      body = const AppListSkeleton(items: 5);
    } else if (_missing) {
      body = const GovNeedsServer();
    } else if (_rows == null) {
      body = AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    } else {
      body = AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xxxl + AppSpace.lg), children: [
          if (canCreate)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: AppPill(
                  icon: Icons.add_rounded,
                  label: t('جهة جديدة', 'New entity'),
                  onTap: () async {
                    if (await showGovEntitySheet(context, _api, programs: _programs)) _load();
                  },
                ),
              ),
            ),
          if (rows.isEmpty)
            AppEmpty(
              icon: Icons.account_tree_rounded,
              title: t('لا جهات بعد', 'No entities yet'),
              message: t('الإدارات الخدمية والأقسام العلمية والمكاتب التي تستقبل المعاملات', 'Service departments, scientific departments and offices that receive items'),
            ),
          for (final g in groups.entries)
            if (g.value.isNotEmpty) ...[
              AppSectionTitle(_groupTitle(g.key), subtitle: '${g.value.length}'),
              for (final e in g.value)
                GovEntityCard(
                  entity: e,
                  council: e.councilId == null ? null : councils[e.councilId],
                  onTap: () => _open(e),
                  onOpenCouncil: e.councilId == null || councils[e.councilId] == null ? null : () => _open(councils[e.councilId]!),
                  onChangeKind: canCreate && !e.isCouncil
                      ? () async {
                          if (await showGovKindSheet(context, _api, e, programs: _programs)) _load();
                        }
                      : null,
                ),
            ],
        ]),
      );
    }
    if (widget.embedded) return body;
    // staff only (the dashboard's Services section embeds it): the dashboard's header, Back first
    return OrgPushedPage(helpPageId: 'org.governance', title: t('الجهات', 'Entities'), child: body);
  }

  String _groupTitle(String k) => switch (k) {
        'service' => t('الإدارات الخدمية', 'Service departments'),
        'scientific' => t('الأقسام العلمية', 'Scientific departments'),
        'office' => t('المكاتب', 'Offices'),
        'council' => t('المجالس', 'Councils'),
        _ => t('وحدات أخرى', 'Other units'),
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  Entity detail: Items · Categories · Delegations
// ═════════════════════════════════════════════════════════════════════════════

class GovEntityDetailPage extends StatelessWidget {
  const GovEntityDetailPage(this.entity, {super.key, this.orgId, this.onExport});
  final Entity entity;
  final int? orgId;
  final Future<void> Function(dynamic filter)? onExport;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final oid = orgId ?? context.read<OrgSession>().currentId;
    final chainTab = !entity.isCouncil && oid != null;   // D-141: the approval chain (the org admin edits it)
    // pushed from the staff Entities list only: the dashboard's header (Back · name · kind line), the tabs head the body
    return DefaultTabController(
      length: chainTab ? 5 : 3,
      child: OrgPushedPage(helpPageId: 'org.governance', 
        title: entity.name,
        subtitle: [entityKindLabel(entity.kind), if (entity.code.isNotEmpty) entity.code].join(' · '),
        child: Column(children: [
          Material(
            color: c.cardBg,
            child: TabBar(
              labelColor: c.primary,
              unselectedLabelColor: c.textMedium,
              indicatorColor: c.primary,
              labelStyle: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark),
              tabs: [
                Tab(text: t('المعاملات', 'Items')),
                Tab(text: t('التصنيفات', 'Categories')),
                Tab(text: t('التفويض', 'Delegation')),
                if (chainTab) Tab(text: t('سلسلة الاعتماد', 'Approval chain')),
                if (chainTab) Tab(text: t('الإحالة التلقائية', 'Automatic routing')),
              ],
              isScrollable: chainTab,
              tabAlignment: chainTab ? TabAlignment.start : null,
            ),
          ),
          Expanded(
            child: TabBarView(children: [
              GovItemsPage(deptId: entity.id, orgId: orgId, embedded: true, onExport: onExport),
              _CategoriesTab(entity: entity, orgId: orgId),
              GovDelegationsPage(entity.id, entity: entity, orgId: orgId, embedded: true),
              if (chainTab) GovChainEditorPage(orgId: oid, entity: entity, embedded: true),
              if (chainTab) GovAutoRoutingPage(orgId: oid, entity: entity),
            ]),
          ),
        ]),
      ),
    );
  }
}

String categoryKindLabel(String k) => {'complaint': t('شكوى', 'Complaint'), 'request': t('طلب', 'Request'), 'other': t('أخرى', 'Other')}[k] ?? k;

class GovCategoryTile extends StatelessWidget {
  const GovCategoryTile({super.key, required this.category, this.formTitle, this.onEdit, this.onDeactivate});
  final Category category;
  final String? formTitle;
  final VoidCallback? onEdit, onDeactivate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cat = category;
    return AppCard(
      margin: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
      padding: const EdgeInsets.all(AppSpace.sm),
      onTap: onEdit,
      child: Row(children: [
        Icon(cat.kind == 'complaint' ? Icons.support_agent_rounded : (cat.kind == 'request' ? Icons.inbox_rounded : Icons.label_outline_rounded), color: cat.isActive ? c.primary : c.textLight),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cat.name, style: AppType.bodyStrong(context).copyWith(color: cat.isActive ? c.textDark : c.textLight)),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              AppBadgePill(categoryKindLabel(cat.kind), color: c.textMedium),
              if (cat.formId != null) AppBadgePill(formTitle ?? '${t('نموذج', 'Form')} #${cat.formId}', color: c.primary, icon: Icons.assignment_rounded),
              if (!cat.isActive) AppBadgePill(t('موقوف', 'Inactive'), color: c.danger),
              if (cat.key.isNotEmpty) AppBadgePill(cat.key, color: c.textLight),
            ]),
            if ((cat.description ?? '').isNotEmpty) Text(cat.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
          ]),
        ),
        if (onDeactivate != null && cat.isActive)
          IconButton(tooltip: t('إيقاف', 'Deactivate'), onPressed: onDeactivate, icon: Icon(Icons.visibility_off_outlined, color: c.danger, size: AppIconSize.md)),
      ]),
    );
  }
}

/// Create (edit == null) or edit a category; true when saved.
Future<bool> showGovCategorySheet(BuildContext context, GovApi api, int deptId, {Category? edit, List<GovFormRef> forms = const []}) async {
  final ar = TextEditingController(text: edit?.nameAr ?? ''), en = TextEditingController(text: edit?.nameEn ?? '');
  final desc = TextEditingController(text: edit?.description ?? ''), key = TextEditingController(text: edit?.key ?? ''), order = TextEditingController(text: '${edit?.order ?? 0}');
  final sla = TextEditingController(text: edit?.slaHours == null ? '' : '${edit!.slaHours}');   // D-972
  var kind = edit?.kind ?? 'request';
  int? form = edit?.formId;
  var active = edit?.isActive ?? true, busy = false;
  final r = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(edit == null ? t('تصنيف جديد', 'New category') : t('تعديل التصنيف', 'Edit category')),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final k in const ['complaint', 'request', 'other']) AppChoiceChip(label: categoryKindLabel(k), selected: kind == k, onTap: () => set(() => kind = k)),
            ]),
            const SizedBox(height: AppSpace.sm),
            AppField(controller: ar, label: t('الاسم بالعربية', 'Arabic name')),
            const SizedBox(height: AppSpace.sm),
            AppField(controller: en, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
            const SizedBox(height: AppSpace.sm),
            AppField(controller: desc, label: t('وصف (اختياري)', 'Description (optional)'), maxLines: 2),
            const SizedBox(height: AppSpace.sm),
            if (forms.isNotEmpty) ...[
              AppDropdown<int>(
                value: form ?? 0,
                decoration: InputDecoration(labelText: t('نموذج مرتبط (اختياري)', 'Linked form (optional)'), prefixIcon: const Icon(Icons.assignment_rounded)),
                items: [
                  DropdownMenuItem(value: 0, child: Text(t('بدون نموذج', 'No form'))),
                  for (final f in forms) DropdownMenuItem(value: f.id, child: Text(f.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => set(() => form = v == 0 ? null : v),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            Row(children: [
              Expanded(child: AppField(controller: key, label: t('المفتاح (اختياري)', 'Key (optional)'), ltr: true)),
              const SizedBox(width: AppSpace.sm),
              SizedBox(width: 110, child: OrgNumberField(controller: order, label: t('الترتيب', 'Order'), gap: false)),
            ]),
            if (kind != 'complaint') ...[
              const SizedBox(height: AppSpace.sm),
              OrgNumberField(controller: sla, label: t('مهلة الرد بالساعات (اختياري)', 'SLA hours (optional)'), gap: false),
              Text(t('فارغ = مهلة الأولوية. بعد انتهائها يُنبَّه رئيس الجهة، ثم يُصعَّد للوكيل إن كان التصعيد مفعّلاً.',
                      'Empty = the hours of its priority. When it passes the head is told, then the vice dean if escalation is on.'),
                  style: AppType.meta(ctx).copyWith(color: c.textLight)),
            ],
            if (edit != null) ...[
              const SizedBox(height: AppSpace.xs),
              AppSwitchTile(title: t('مفعّل', 'Active'), value: active, onChanged: (v) => set(() => active = v)),
            ],
            const SizedBox(height: AppSpace.xs),
            if (edit != null) Text(t('يُمكن إيقاف تصنيف لا تعديل مفتاحه', 'A category can be switched off; its key stays'), style: AppType.meta(ctx).copyWith(color: c.textLight)),
            const SizedBox(height: AppSpace.xs),
            AppPrimaryButton(
              label: edit == null ? t('إنشاء', 'Create') : t('حفظ', 'Save'),
              icon: Icons.save_rounded,
              busy: busy,
              onPressed: () async {
                if (ar.text.trim().isEmpty && en.text.trim().isEmpty) {
                  appToast(t('اكتب اسم التصنيف', 'Enter a name'), error: true);
                  return;
                }
                final slaText = sla.text.trim();
                final slaHours = slaText.isEmpty ? null : int.tryParse(slaText);
                if (slaText.isNotEmpty && (slaHours == null || slaHours < 1 || slaHours > 2160)) {
                  appToast(t('مهلة الرد من 1 إلى 2160 ساعة', 'SLA hours go from 1 to 2160'), error: true);
                  return;
                }
                set(() => busy = true);
                final body = {
                  if (key.text.trim().isNotEmpty) 'key': key.text.trim(),
                  'name_ar': ar.text.trim(),
                  'name_en': en.text.trim(),
                  'kind': kind,
                  'description': desc.text.trim(),
                  'form_id': form,
                  'order': int.tryParse(order.text.trim()) ?? 0,
                  if (edit != null) 'is_active': active,
                  'sla_hours': kind == 'complaint' ? edit?.slaHours : slaHours,
                };
                final res = await orgCall(() => edit == null ? api.createCategory(deptId, body) : api.updateCategory(edit.id, body), ok: t('تم الحفظ', 'Saved'));
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (res.ok) Navigator.pop(ctx, true);
              },
            ),
          ]),
        );
      }));
  return r == true;
}

class _CategoriesTab extends StatefulWidget {
  const _CategoriesTab({required this.entity, this.orgId});
  final Entity entity;
  final int? orgId;
  @override
  State<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<_CategoriesTab> {
  late GovApi _api;
  List<Category>? _rows;
  List<GovFormRef> _forms = const [];
  bool _failed = false;

  int get _orgId => widget.orgId ?? context.read<OrgSession>().currentId ?? 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _api = GovApi(_orgId);
      _load();
      _loadForms();
    });
  }

  Future<void> _load() async {
    final r = await orgCall(() => _api.categories(widget.entity.id), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _rows = r.data as List<Category>;
        _failed = false;
      } else {
        _failed = _rows == null;
      }
    });
  }

  Future<void> _loadForms() async {
    final r = await OrgApi.i.getMap('$orgBase/orgs/$_orgId/forms', {'dept_id': widget.entity.id, 'size': 100});
    if (mounted && r != null) setState(() => _forms = [for (final f in asMapList(r['items'])) (id: asInt(f['id']), title: '${f['title'] ?? f['name'] ?? '#${f['id']}'}')]);
  }

  String? _formTitle(int? id) => id == null ? null : _forms.where((f) => f.id == id).map((f) => f.title).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final canEdit = widget.entity.can['manage'] || s.can('workflow', 'update', widget.entity.id);
    final rows = _rows ?? const <Category>[];
    if (_rows == null && !_failed) return const AppListSkeleton(items: 4);
    if (_rows == null) return AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    return AppRefresh(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xxl), children: [
        if (canEdit)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AppPill(
                icon: Icons.add_rounded,
                label: t('تصنيف جديد', 'New category'),
                onTap: () async {
                  if (await showGovCategorySheet(context, _api, widget.entity.id, forms: _forms)) _load();
                },
              ),
            ),
          ),
        if (rows.isEmpty)
          AppEmpty(
            icon: Icons.label_outline_rounded,
            title: t('لا تصنيفات', 'No categories'),
            message: t('يختار مقدّم الطلب تصنيفاً عند الإرسال؛ ويمكن ربط تصنيف بنموذج', 'Submitters pick a category when sending; a category can be backed by a form'),
          ),
        for (final cat in [...rows]..sort((a, b) => a.order.compareTo(b.order)))
          GovCategoryTile(
            category: cat,
            formTitle: _formTitle(cat.formId),
            onEdit: canEdit
                ? () async {
                    if (await showGovCategorySheet(context, _api, widget.entity.id, edit: cat, forms: _forms)) _load();
                  }
                : null,
            onDeactivate: canEdit
                ? () async {
                    if (!await appConfirm(context, message: t('إيقاف التصنيف «${cat.name}»؟', 'Deactivate the category "${cat.name}"?'), danger: true)) return;
                    final r = await orgCall(() => _api.deleteCategory(cat.id), ok: t('أُوقف', 'Deactivated'));
                    if (r.ok) _load();
                  }
                : null,
          ),
      ]),
    );
  }
}

/// Kept for callers that have only the raw entity map (the department hub).
Entity entityFromMap(Map<String, dynamic> m) => Entity.fromJson(asMap(m));
