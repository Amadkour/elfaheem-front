// lib/features/org/governance/gov_items_page.dart — the unified list of requests · complaints · forms · memos
// (spec §4 `GET …/items`), one widget for the organization (deptId null) and for one entity (deptId set):
//
//   GovItemsPage          tabs All · Waiting for me · Mine · Overdue (the filter's quick flags), the shared
//                         ItemFilterBar with saved filters, paging ("load more"), multi-select → bulk bar (route ·
//                         close · assign through POST …/items/bulk), "New item" (staff memo / request on behalf),
//                         an optional export button (the coordinator passes `onExport` → the Export Hub)
//   GovItemCard           one row (presentational, layout-tested)
//   showGovNewItemSheet   the creation sheet (type · entity · category · title · body · priority · due · route now)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show SheetHeader, asInt, asMap, asMapList, t;
import '../../admin/admin_list.dart' show IconBadge;
import '../org_providers.dart' show OrgSession;
import '../org_v3.dart' show orgCall, orgUtc;
import 'gov_api.dart';
import 'gov_delegations_page.dart' show GovActingBanner;
import 'gov_filter.dart';
import 'gov_item_screen.dart';
import 'gov_models.dart';
import 'gov_route_sheet.dart';
import 'gov_ui.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Card
// ═════════════════════════════════════════════════════════════════════════════

class GovItemCard extends StatelessWidget {
  const GovItemCard({super.key, required this.item, this.selected = false, this.selectMode = false, this.onTap, this.onLongPress, this.member = false});
  final WorkItem item;
  final bool selected, selectMode, member;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final it = item;
    final pr = it.pendingRoute;
    final accent = it.overdue ? c.danger : (selected ? c.primary : null);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      decoration: BoxDecoration(
        color: selected ? c.primary.withValues(alpha: 0.06) : c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusLarge - 4),
        border: Border.all(color: accent?.withValues(alpha: 0.5) ?? c.divider),
        boxShadow: c.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(c.radiusLarge - 4),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (selectMode)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10, top: 8),
                  child: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? c.primary : c.textLight),
                )
              else ...[
                IconBadge(govTypeIcon(it.type), govPriorityColor(context, it.priority), size: 42),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(it.ref, style: appText(11.5, w: FontWeight.w800, c: c.textLight)),
                    GovTypePill(it.type),
                    GovStatusPill(it.status),
                  ]),
                  const SizedBox(height: 4),
                  Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w800, c: c.textDark)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (it.sourceName.isNotEmpty) '${t('من', 'From')}: ${it.sourceName}',
                      if (it.ownerDept != null) '${t('لدى', 'At')}: ${it.ownerDept!.name}',
                      if (it.createdAt != null) relTime(it.createdAt!.toUtc().toIso8601String()),
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: appText(12, c: c.textMedium),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    GovPriorityPill(it.priority),
                    GovDuePill(dueAt: it.dueAt, overdue: it.overdue),
                    if (pr != null)
                      AppBadgePill('${routeActionLabel(pr.action)} → ${pr.targetName}', color: c.warning, icon: Icons.alt_route_rounded),
                    if (it.voteOutcome != null) GovOutcomePill(it.voteOutcome!),
                    if (it.assignee != null && !member) AppBadgePill(it.assignee!.name, color: c.textMedium, icon: Icons.person_rounded),
                    if (it.category != null) AppBadgePill(it.category!.name, color: c.textMedium, icon: Icons.label_outline_rounded),
                    if (it.anonymous) AppBadgePill(t('هوية محجوبة', 'Anonymous'), color: c.textMedium, icon: Icons.visibility_off_rounded),
                    if (it.attachments.isNotEmpty) AppBadgePill('${it.attachments.length}', color: c.textMedium, icon: Icons.attach_file_rounded),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  New item (staff memo / request on behalf)
// ═════════════════════════════════════════════════════════════════════════════

/// Returns the created item (already routed when the person asked for it), or null.
Future<WorkItem?> showGovNewItemSheet(BuildContext context, GovApi api, {required List<Entity> entities, int? deptId}) async {
  final title = TextEditingController(), body = TextEditingController();
  var type = 'memo';
  GovDept? owner = entities.where((e) => e.id == deptId).map((e) => e.dept).firstOrNull;
  List<Category> cats = entities.where((e) => e.id == owner?.id).map((e) => e.categories).firstOrNull ?? const [];
  int? category;
  var priority = 'medium';
  DateTime? due;
  var routeNow = false, busy = false;
  final created = await showAppSheet<WorkItem>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Future<void> loadCats(int id) async {
          final r = await orgCall(() => api.categories(id), quiet: true);
          if (!ctx.mounted) return;
          set(() {
            cats = r.ok ? (r.data as List<Category>) : const [];
            if (!cats.any((x) => x.id == category)) category = null;
          });
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(t('معاملة جديدة', 'New item')),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final x in const ['memo', 'request', 'complaint', 'custom'])
                AppChoiceChip(label: itemTypeLabel(x), icon: govTypeIcon(x), selected: type == x, onTap: () => set(() => type = x)),
            ]),
            const SizedBox(height: 12),
            GovEntityPickField(
              label: t('الجهة المالكة', 'Owner entity'),
              entities: entities,
              value: owner,
              onChanged: (d) {
                set(() => owner = d);
                if (d != null) loadCats(d.id);
              },
            ),
            if (cats.isNotEmpty) ...[
              const SizedBox(height: 12),
              AppDropdown<int>(
                value: category ?? 0,
                decoration: InputDecoration(labelText: t('التصنيف', 'Category'), prefixIcon: const Icon(Icons.label_outline_rounded)),
                items: [
                  DropdownMenuItem(value: 0, child: Text(t('بدون تصنيف', 'No category'))),
                  for (final x in cats.where((x) => x.isActive)) DropdownMenuItem(value: x.id, child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => set(() => category = v == 0 ? null : v),
              ),
            ],
            const SizedBox(height: 12),
            AppField(controller: title, label: t('العنوان', 'Title')),
            const SizedBox(height: 12),
            AppField(controller: body, label: t('التفاصيل', 'Details'), maxLines: 4),
            const SizedBox(height: 12),
            Text(t('الأولوية', 'Priority'), style: appText(12, c: c.textLight)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in priorities) AppChoiceChip(label: priorityLabelOf(p), selected: priority == p, onTap: () => set(() => priority = p)),
            ]),
            const SizedBox(height: 12),
            GovDateField(
              label: t('الاستحقاق (اختياري — يُحسب من الأولوية)', 'Due (optional — defaults from the priority)'),
              value: due,
              withTime: true,
              icon: Icons.timer_rounded,
              onPick: () async {
                final d = await pickGovDateTime(ctx, initial: due);
                if (d != null) set(() => due = d);
              },
              onClear: () => set(() => due = null),
            ),
            const SizedBox(height: 6),
            AppSwitchTile(
              title: t('إحالتها فور الإنشاء', 'Route it right after creating'),
              subtitle: t('تفتح شاشة الإحالة بعد الحفظ', 'The route sheet opens after saving'),
              value: routeNow,
              onChanged: (v) => set(() => routeNow = v),
            ),
            const SizedBox(height: 8),
            AppPrimaryButton(
              label: t('إنشاء', 'Create'),
              icon: Icons.add_rounded,
              busy: busy,
              onPressed: owner == null
                  ? null
                  : () async {
                      if (title.text.trim().isEmpty) {
                        appToast(t('اكتب العنوان', 'Enter a title'), error: true);
                        return;
                      }
                      set(() => busy = true);
                      final r = await orgCall(() => api.createItem({
                            'type': type,
                            'dept_id': owner!.id,
                            'category_id': ?category,
                            'title': title.text.trim(),
                            'body': body.text.trim(),
                            'priority': priority,
                            'due_at': orgUtc(due),
                          }));
                      if (!ctx.mounted) return;
                      set(() => busy = false);
                      if (r.ok) {
                        appToast(t('أُنشئت المعاملة', 'Item created'));
                        Navigator.pop(ctx, WorkItem.fromJson(asMap(r.data)));
                      }
                    },
            ),
          ]),
        );
      }));
  if (created == null || !routeNow || !context.mounted) return created;
  final routed = await showGovRouteSheet(context, api, created, entities: entities);
  return routed ?? created;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class GovItemsPage extends StatefulWidget {
  const GovItemsPage({
    super.key,
    this.deptId,
    this.scope = 'items',
    this.title,
    this.embedded = false,
    this.initial,
    this.onExport,
    this.orgId,
    this.showQuick = true,
  });

  /// One entity's items (also hides the entity picker); null = every entity I may see.
  final int? deptId;

  /// Saved-filter scope (`items` · `council` · `my` …).
  final String scope;
  final String? title;

  /// Inside another page (a dashboard section, an entity tab): no scaffold, bounded height expected.
  final bool embedded;

  /// The starting filter (a dashboard tile opens the list on its numbers).
  final ItemFilter? initial;

  /// When given, an Export button opens the Export Hub with the current filter (wired by the coordinator).
  final Future<void> Function(ItemFilter filter)? onExport;

  /// Defaults to the selected organization of `OrgSession`.
  final int? orgId;
  final bool showQuick;

  @override
  State<GovItemsPage> createState() => _GovItemsPageState();
}

class _GovItemsPageState extends State<GovItemsPage> {
  late GovApi _api;
  late ItemFilter _filter;
  final _items = <WorkItem>[];
  final _selected = <int>{};
  List<Entity> _entities = const [];
  List<Category> _categories = const [];
  Map<int, String> _people = const {};
  List<SavedFilter> _saved = const [];
  Map<String, dynamic> _facets = const {};
  int _page = 1, _pages = 1, _total = 0, _req = 0;
  bool _loading = true, _more = false, _failed = false, _missing = false, _selectMode = false;

  int get _orgId => widget.orgId ?? context.read<OrgSession>().currentId ?? 0;

  @override
  void initState() {
    super.initState();
    _filter = (widget.initial ?? const ItemFilter()).copyWith(deptId: widget.deptId ?? widget.initial?.deptId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _api = GovApi(_orgId);
      _load(reset: true);
      _loadSetup();
    });
  }

  Future<void> _loadSetup() async {
    final ent = await orgCall(() => _api.entities(), quiet: true);
    if (!mounted) return;
    if (ent.ok) setState(() => _entities = ent.data as List<Entity>);
    if (widget.deptId != null) {
      final cats = await orgCall(() => _api.categories(widget.deptId!), quiet: true);
      if (mounted && cats.ok) setState(() => _categories = cats.data as List<Category>);
    }
    final ppl = await searchGovPeople(_orgId, '', roles: const ['teacher', 'teacher_assistant', 'admin_assistant', 'org_admin'], size: 100);
    if (mounted) setState(() => _people = {for (final p in ppl) p.id: p.name});
    final sf = await orgCall(() => _api.savedFilters(widget.scope), quiet: true);
    if (mounted && sf.ok) setState(() => _saved = sf.data as List<SavedFilter>);
  }

  Future<void> _load({bool reset = false}) async {
    final req = ++_req;
    if (reset) {
      _page = 1;
      setState(() {
        _loading = true;
        _failed = false;
      });
    } else {
      setState(() => _more = true);
    }
    final r = await orgCall(() => _api.items({..._filter.toQuery(), 'page': _page, 'size': 30}), quiet: true);
    if (!mounted || req != _req) return;
    setState(() {
      _loading = false;
      _more = false;
      if (!r.ok) {
        _failed = true;
        _missing = r.endpointMissing;
        return;
      }
      final page = r.data as GovPage<WorkItem>;
      if (reset) _items.clear();
      _items.addAll(page.items);
      _pages = page.pages;
      _total = page.total;
      _facets = page.facets;
      _selected.removeWhere((id) => !_items.any((i) => i.id == id));
    });
  }

  void _loadMore() {
    if (_more || _loading || _page >= _pages) return;
    _page++;
    _load();
  }

  void _setFilter(ItemFilter f) {
    setState(() => _filter = f);
    _load(reset: true);
  }

  Future<void> _saveFilter(String name, ItemFilter f) async {
    final r = await orgCall(() => _api.saveFilter(name, widget.scope, f.toQuery()), ok: t('حُفظ الفلتر', 'Filter saved'));
    if (!r.ok) return;
    final sf = await orgCall(() => _api.savedFilters(widget.scope), quiet: true);
    if (mounted && sf.ok) setState(() => _saved = sf.data as List<SavedFilter>);
  }

  Future<void> _deleteFilter(SavedFilter f) async {
    if (!await appConfirm(context, message: t('حذف الفلتر «${f.name}»؟', 'Delete the filter "${f.name}"?'), danger: true)) return;
    final r = await orgCall(() => _api.deleteSavedFilter(f.id), ok: t('حُذف', 'Deleted'));
    if (r.ok && mounted) setState(() => _saved = _saved.where((x) => x.id != f.id).toList());
  }

  Future<void> _open(WorkItem it) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GovItemScreen(it.id, orgId: _orgId)));
    if (mounted) _load(reset: true);
  }

  Future<void> _newItem() async {
    final it = await showGovNewItemSheet(context, _api, entities: _entities, deptId: widget.deptId);
    if (it != null && mounted) _load(reset: true);
  }

  Future<void> _bulk(String op) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    Map<String, dynamic>? route;
    int? userId;
    switch (op) {
      case 'route':
        route = await showGovRouteBodySheet(context, orgId: _orgId, entities: _entities, excludeDeptId: widget.deptId, title: t('إحالة ${ids.length} معاملة', 'Route ${ids.length} items'));
        if (route == null) return;
      case 'assign':
        final p = await pickGovPerson(context, _orgId, title: t('إسناد إلى', 'Assign to'));
        if (p == null) return;
        userId = p.id;
      case 'close':
        if (!await appConfirm(context, message: t('إغلاق ${ids.length} معاملة؟', 'Close ${ids.length} items?'))) return;
    }
    if (!mounted) return;
    final r = await orgCall(() => _api.bulk(ids, op, route: route, userId: userId));
    if (!r.ok || !mounted) return;
    final done = asInt(r.map['done']), failed = asMapList(r.map['failed']);
    appToast(
      failed.isEmpty
          ? t('تم تنفيذ $done', 'Done: $done')
          : t('تم $done · تعذّر ${failed.length} (${failed.map((f) => govCodeTexts()['${f['code']}'] ?? f['code']).toSet().join('، ')})',
              'Done $done · failed ${failed.length} (${failed.map((f) => govCodeTexts()['${f['code']}'] ?? f['code']).toSet().join(', ')})'),
      error: failed.isNotEmpty,
    );
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
    _load(reset: true);
  }

  String _deptName(int id) => _entities.where((e) => e.id == id).map((e) => e.name).firstOrNull ?? '#$id';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final canInsert = widget.deptId == null ? s.canAny('workflow', 'insert') : s.can('workflow', 'insert', widget.deptId);
    final canExport = widget.onExport != null && (widget.deptId == null ? s.canAny('workflow', 'export') : s.can('workflow', 'export', widget.deptId));
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GovActingBanner(orgId: _orgId),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: ItemFilterBar(
          filter: _filter,
          onChanged: _setFilter,
          scope: widget.scope,
          entities: _entities,
          people: _people,
          categories: _categories,
          savedFilters: _saved,
          onSaveFilter: _saveFilter,
          onDeleteFilter: _deleteFilter,
          showQuick: widget.showQuick,
          showEntity: widget.deptId == null,
          onPickPerson: () => pickGovPerson(context, _orgId, title: t('المسؤول', 'Assignee')),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (!_loading) Text(t('$_total معاملة', '$_total items'), style: appText(12, w: FontWeight.w700, c: c.textMedium)),
          for (final st in const ['open', 'in_review', 'pending_approval', 'in_council'])
            if (asInt(asMap(_facets['status'])[st]) > 0)
              AppBadgePill('${itemStatusLabel(st)} ${asInt(asMap(_facets['status'])[st])}', color: govStatusColor(context, st)),
          const SizedBox(width: 4),
          if (canInsert) AppPill(icon: Icons.add_rounded, label: t('معاملة جديدة', 'New item'), onTap: _entities.isEmpty ? null : _newItem),
          if (canExport) AppPill(icon: Icons.file_download_rounded, label: t('تصدير', 'Export'), color: c.textMedium, onTap: () => widget.onExport!(_filter)),
          if (_items.isNotEmpty)
            AppPill(
              icon: _selectMode ? Icons.close_rounded : Icons.checklist_rounded,
              label: _selectMode ? t('إلغاء التحديد', 'Cancel') : t('تحديد', 'Select'),
              color: c.textMedium,
              onTap: () => setState(() {
                _selectMode = !_selectMode;
                if (!_selectMode) _selected.clear();
              }),
            ),
        ]),
      ),
      Expanded(child: _list(context)),
      if (_selectMode && _selected.isNotEmpty) _BulkBar(count: _selected.length, onRoute: () => _bulk('route'), onClose: () => _bulk('close'), onAssign: () => _bulk('assign')),
    ]);
    if (widget.embedded) return body;
    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: widget.title ?? (widget.deptId == null ? t('الطلبات والمعاملات', 'Requests & workflow') : _deptName(widget.deptId!)), actions: const [ContextExitButton()]),
      child: body,
    );
  }

  Widget _list(BuildContext context) {
    if (_loading && _items.isEmpty) return const AppListSkeleton(items: 6);
    if (_missing) return const GovNeedsServer();
    if (_failed && _items.isEmpty) {
      return AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: () => _load(reset: true));
    }
    if (_items.isEmpty) {
      return AppEmpty(
        icon: Icons.inbox_rounded,
        title: _filter.activeCount > 0 || _filter.q.isNotEmpty ? t('لا نتائج لهذا الفلتر', 'Nothing matches this filter') : t('لا معاملات بعد', 'No items yet'),
        message: _filter.quick == 'to_me' ? t('لا شيء بانتظار قرارك الآن 🌿', 'Nothing is waiting for you right now 🌿') : null,
      );
    }
    return AppRefresh(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 90),
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i == _items.length) {
            if (_page >= _pages) return const SizedBox(height: 8);
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: _more
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton.icon(onPressed: _loadMore, icon: const Icon(Icons.expand_more_rounded), label: Text(t('تحميل المزيد', 'Load more'))),
              ),
            );
          }
          final it = _items[i];
          return GovItemCard(
            item: it,
            selectMode: _selectMode,
            selected: _selected.contains(it.id),
            onTap: _selectMode ? () => setState(() => _selected.contains(it.id) ? _selected.remove(it.id) : _selected.add(it.id)) : () => _open(it),
            onLongPress: () => setState(() {
              _selectMode = true;
              _selected.add(it.id);
            }),
          );
        },
      ),
    );
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({required this.count, required this.onRoute, required this.onClose, required this.onAssign});
  final int count;
  final VoidCallback onRoute, onClose, onAssign;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider)), boxShadow: c.cardShadow),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(t('$count محددة', '$count selected'), style: appText(13, w: FontWeight.w800, c: c.textDark)),
        AppPill(icon: Icons.alt_route_rounded, label: t('إحالة', 'Route'), onTap: onRoute),
        AppPill(icon: Icons.person_add_alt_1_rounded, label: t('إسناد', 'Assign'), onTap: onAssign, color: c.textMedium),
        AppPill(icon: Icons.check_circle_outline_rounded, label: t('إغلاق', 'Close'), onTap: onClose, color: c.danger),
      ]),
    );
  }
}
