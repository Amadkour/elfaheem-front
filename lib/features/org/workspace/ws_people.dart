// lib/features/org/workspace/ws_people.dart
//
// One unit's people in the teacher workspace (D-1153 – D-1155, docs/teacher-org/PLAN.md): a search field
// (debounced), a filter sheet (kinds, joined date range, sort) whose choices show as removable chips, saved filters
// (stored on the device, WsPrefs.savedFilters), lazy paging near the end of the list, pull to refresh, and
// multi-select (long press or the Select button) with the bulk bar at the bottom: Select all · Export · Remove (a
// manager only, `can.bulk`) · Close. Remove asks first and offers Undo (`op: restore` with the removed snapshots);
// Export is the Export Studio only, over the selected rows, the current filter or everyone.
//
// The rows and the bulk bar are plain-value widgets ([WsPersonRow], [WsBulkBar]) for the layout harness.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../../admin/admin_table_export.dart' show exportFetched;
import '../org_page_header.dart' show OrgPageRefresh;
import '../org_page_kit.dart' show OrgSegmented;
import '../org_v3.dart' show OrgCall;
import 'ws_models.dart';
import 'ws_person.dart';
import 'ws_shell.dart' show WsController;

/// One page of people per call; the export fetches with the server's largest page.
const _pageSize = 30;
const _exportPageSize = 100;

/// One unit's people: search, filters, paging, multi-select, bulk bar, export (D-1153 – D-1155).
class WsUnitPeople extends StatefulWidget {
  const WsUnitPeople({super.key, required this.unit});
  final WsUnit unit;

  @override
  State<WsUnitPeople> createState() => _WsUnitPeopleState();
}

class _WsUnitPeopleState extends State<WsUnitPeople> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  WsPeopleFilter _filter = const WsPeopleFilter();
  final _items = <WsPerson>[];
  int _page = 0, _pages = 1, _total = 0, _seq = 0;
  WsCan _can = const WsCan();
  bool _loading = true, _loadingMore = false, _selecting = false;
  OrgCall? _error;
  final _selected = <int>{};
  OrgPageRefresh? _refresh;

  WsController get _ws => context.read<WsController>();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    wsPeopleChanged.addListener(_onChanged);
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    wsPeopleChanged.removeListener(_onChanged);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _reload();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 600) _loadMore();
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    final (p, r) = await _ws.api.people(widget.unit.id, _filter, page: 1, size: _pageSize);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (p != null) {
        _items
          ..clear()
          ..addAll(p.items);
        _page = p.page;
        _pages = p.pages;
        _total = p.total;
        _can = p.can;
        final ids = {for (final x in _items) x.userId};
        _selected.removeWhere((id) => !ids.contains(id));
      } else {
        _error = r;
      }
    });
    if (p != null && mounted) OrgPageRefresh.reportUpdated(context);
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _page >= _pages || _error != null) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    final (p, r) = await _ws.api.people(widget.unit.id, _filter, page: _page + 1, size: _pageSize);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loadingMore = false;
      if (p != null) {
        final have = {for (final x in _items) x.userId};
        _items.addAll(p.items.where((x) => !have.contains(x.userId)));
        _page = p.page;
        _pages = p.pages;
        _total = p.total;
      }
    });
    if (p == null) showAppNotice(wsCallText(r), error: true);
  }

  void _setFilter(WsPeopleFilter f) {
    _filter = f;
    if (_search.text != f.q) _search.text = f.q;
    _items.clear();
    _page = 0;
    _reload();
  }

  // ── selection ─────────────────────────────────────────────────────────────

  void _toggle(int id) => setState(() {
        _selecting = true;
        if (!_selected.remove(id)) _selected.add(id);
      });

  bool get _allSelected => _items.isNotEmpty && _items.every((x) => _selected.contains(x.userId));

  void _selectAll() => setState(() {
        if (_allSelected) {
          _selected.clear();
        } else {
          _selected.addAll(_items.map((x) => x.userId));
        }
      });

  void _closeSelection() => setState(() {
        _selected.clear();
        _selecting = false;
      });

  // ── sheets ────────────────────────────────────────────────────────────────

  Future<void> _openFilters() async {
    final f = await showAppSheet<WsPeopleFilter>(context, (_) => _WsFilterSheet(initial: _filter));
    if (f != null && mounted) _setFilter(f.copyWith(q: _filter.q));
  }

  Future<void> _openSaved() async {
    final ws = _ws;
    await showAppSheet<void>(
      context,
      (_) => ChangeNotifierProvider<WsController>.value(
        value: ws,
        child: _WsSavedFiltersSheet(current: _filter, onApply: _setFilter),
      ),
    );
  }

  // ── bulk ──────────────────────────────────────────────────────────────────

  Future<void> _remove() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final ws = _ws;
    final n = ids.length;
    final ok = await appConfirm(
      context,
      danger: true,
      confirmLabel: t('إزالة', 'Remove'),
      message: t('إزالة ', 'Remove ') +
          countText(n, ar1: 'شخص واحد', ar2: 'شخصين', arFew: '$n أشخاص', arMany: '$n شخصًا', en1: 'one person', en: '$n people') +
          t(' من ${widget.unit.name}؟', ' from ${widget.unit.name}?'),
    );
    if (!ok || !mounted) return;
    final r = await ws.api.remove(widget.unit.id, ids);
    if (!mounted || !r.ok) return; // orgCall already showed a refusal
    final m = r.map;
    final failed = [
      for (final f in (m['failed'] is List ? m['failed'] as List : const []))
        if (f is Map) (int.tryParse('${f['user_id']}') ?? 0, '${f['code'] ?? ''}'),
    ];
    final removed = [for (final x in (m['removed'] is List ? m['removed'] as List : const [])) if (x is Map) x.cast<String, dynamic>()];
    final names = {for (final x in _items) x.userId: x.name};
    final unitId = widget.unit.id;
    _closeSelection();
    if (removed.isNotEmpty) {
      final k = removed.length;
      showAppNotice(
        t('أُزيل ', 'Removed ') + countText(k, ar1: 'شخص واحد', ar2: 'شخصان', arFew: '$k أشخاص', arMany: '$k شخصًا', en1: 'one person', en: '$k people'),
        actionLabel: t('تراجع', 'Undo'),
        onAction: () async {
          final u = await ws.api.restore(unitId, removed);
          if (u.ok) {
            wsPeopleChanged.value++;
            showAppNotice(t('أُعيدوا إلى القسم', 'Restored to the department'));
          }
        },
      );
    }
    wsPeopleChanged.value++;
    if (failed.isNotEmpty && mounted) {
      await showAppDialog<void>(
        context,
        title: t('تعذّرت إزالة بعضهم', "Some couldn't be removed"),
        icon: Icons.info_outline_rounded,
        body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (id, code) in failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
              child: Text('${names[id] ?? '#$id'} — ${wsCodeText(code)}', style: AppType.body(context)),
            ),
        ]),
        actions: [Builder(builder: (ctx) => AppButton(label: t('حسنًا', 'OK'), onPressed: () => Navigator.pop(ctx)))],
      );
    }
  }

  Future<void> _export() async {
    final ws = _ws;
    final options = <(String, String, IconData)>[
      if (_selected.isNotEmpty)
        ('selected', t('المحدَّدون (${_selected.length})', 'Selected (${_selected.length})'), Icons.check_box_outlined),
      if (!_filter.isEmpty) ('filtered', t('حسب التصفية الحالية', 'Current filter'), Icons.filter_alt_outlined),
      ('all', t('الجميع', 'Everyone'), Icons.groups_rounded),
    ];
    String? scope = options.length == 1 ? options.first.$1 : null;
    scope ??= await showAppSheet<String>(
      context,
      (ctx) => AppSheetContent(
        title: t('تصدير', 'Export'),
        icon: Icons.ios_share_rounded,
        children: [
          for (final (id, label, icon) in options)
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              minTileHeight: AppTouch.min,
              onTap: () => Navigator.pop(ctx, id),
            ),
        ],
      ),
    );
    if (scope == null || !mounted) return;
    final chosen = [for (final x in _items) if (_selected.contains(x.userId)) x];
    final f = scope == 'all' ? WsPeopleFilter(sort: _filter.sort) : _filter;
    final unit = widget.unit;
    await exportFetched(
      context,
      filters: scope == 'filtered' ? _filterLabels(_filter) : const {},
      fetch: (job) async {
        if (scope == 'selected') return [for (final p in chosen) _row(p)];
        final out = <Map<String, dynamic>>[];
        for (var page = 1; page <= 200; page++) {
          job.throwIfCancelled();
          final (p, r) = await ws.api.people(unit.id, f, page: page, size: _exportPageSize);
          if (p == null) throw r.error!;
          out.addAll([for (final x in p.items) _row(x)]);
          job.step('${t('جلب الصفوف', 'Fetching rows')} ${out.length} / ${p.total}', p.pages <= 0 ? null : page / p.pages);
          if (!p.hasMore) break;
        }
        return out;
      },
      build: (rows) => AppTableExport(
        id: 'org.ws.people',
        title: unit.name,
        orgId: ws.orgId,
        columns: [
          AppExportColumn('name', t('الاسم', 'Name'), locked: true, labels: const {'ar': 'الاسم', 'en': 'Name'}),
          AppExportColumn('username', t('اسم المستخدم', 'Username'), visible: false, labels: const {'ar': 'اسم المستخدم', 'en': 'Username'}),
          AppExportColumn('kind', t('الصفة', 'Role'), labels: const {'ar': 'الصفة', 'en': 'Role'}),
          AppExportColumn('title', t('المسمّى', 'Title'), labels: const {'ar': 'المسمّى', 'en': 'Title'}),
          AppExportColumn('joined', t('تاريخ الانضمام', 'Joined'), type: AppColType.date, labels: const {'ar': 'تاريخ الانضمام', 'en': 'Joined'}),
          if (rows.any((r) => r['email'] != null)) AppExportColumn('email', t('البريد', 'Email'), labels: const {'ar': 'البريد', 'en': 'Email'}),
        ],
        rows: rows,
      ),
    );
  }

  Map<String, dynamic> _row(WsPerson p) => {
        'name': p.name,
        'username': p.username,
        'kind': wsKindLabel(p.kind),
        'title': p.title,
        'joined': p.joinedAt?.toUtc().toIso8601String(),
        'email': p.email,
      };

  Map<String, String> _filterLabels(WsPeopleFilter f) => {
        if (f.q.trim().isNotEmpty) t('بحث', 'Search'): f.q.trim(),
        if (f.kinds.isNotEmpty) t('الصفة', 'Role'): f.kinds.map(wsKindLabel).join('، '),
        if (f.joinedFrom != null || f.joinedTo != null) t('الانضمام', 'Joined'): _rangeLabel(f),
      };

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    final showBar = _selected.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
        child: Row(children: [
          Expanded(
            child: AppSearchField(
              controller: _search,
              hint: t('ابحث بالاسم', 'Search by name'),
              debounce: const Duration(milliseconds: 300),
              onChanged: (q) {
                if (q == _filter.q) return;
                _filter = _filter.copyWith(q: q);
                _reload();
              },
            ),
          ),
          const SizedBox(width: AppSpace.xxs),
          AppIconButton(icon: Icons.tune_rounded, tooltip: t('تصفية', 'Filter'), badge: _filter.chipCount, onPressed: _openFilters),
          AppIconButton(icon: Icons.bookmarks_outlined, tooltip: t('التصفيات المحفوظة', 'Saved filters'), onPressed: _openSaved),
          AppIconButton(
            icon: _selecting ? Icons.checklist_rtl_rounded : Icons.checklist_rounded,
            tooltip: _selecting ? t('إنهاء التحديد', 'Stop selecting') : t('تحديد', 'Select'),
            variant: _selecting ? AppIconButtonVariant.tonal : AppIconButtonVariant.standard,
            onPressed: () => _selecting ? _closeSelection() : setState(() => _selecting = true),
          ),
        ]),
      ),
      if (_filter.chipCount > 0)
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final k in _filter.kinds) _FilterChip(label: wsKindLabel(k), onRemove: () => _setFilter(_filter.without(kind: k))),
            if (_filter.joinedFrom != null || _filter.joinedTo != null)
              _FilterChip(label: _rangeLabel(_filter), onRemove: () => _setFilter(_filter.without())),
          ]),
        ),
      if (!_loading && _error == null)
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
          child: Text(
            countText(_total, ar1: 'شخص واحد', ar2: 'شخصان', arFew: '$_total أشخاص', arMany: '$_total شخصًا', ar0: 'لا أحد', en1: '1 person', en: '$_total people'),
            style: AppType.meta(context).copyWith(color: context.colors.textMedium),
          ),
        ),
      Expanded(child: _body()),
      AnimatedSwitcher(
        duration: motion.base,
        switchInCurve: AppMotion.curve,
        switchOutCurve: AppMotion.curve,
        transitionBuilder: (child, a) => SizeTransition(
          sizeFactor: a,
          child: FadeTransition(opacity: a, child: child),
        ),
        child: showBar
            ? WsBulkBar(
                key: const ValueKey('ws.bulk'),
                count: _selected.length,
                allSelected: _allSelected,
                onSelectAll: _selectAll,
                onExport: _export,
                onRemove: _can.bulk ? _remove : null,
                onClose: _closeSelection,
              )
            : const SizedBox(key: ValueKey('ws.nobulk'), width: double.infinity),
      ),
    ]);
  }

  Widget _body() {
    if (_loading) return const AppListSkeleton(items: 6);
    if (_error != null && _items.isEmpty) {
      return AppRefresh(
        onRefresh: _reload,
        scrollable: false,
        child: AppErrorState(message: wsCallText(_error!), onRetry: _reload),
      );
    }
    if (_items.isEmpty) {
      return AppRefresh(
        onRefresh: _reload,
        scrollable: false,
        child: _filter.isEmpty
            ? AppEmpty(icon: Icons.groups_2_outlined, title: t('لا أحد هنا بعد', 'No one here yet'), message: t('سيظهر أعضاء القسم وفريقه هنا.', "The department's team and members show here."))
            : AppEmpty(
                icon: Icons.search_off_rounded,
                title: t('لا نتائج', 'No matches'),
                message: t('جرّب تصفية أوسع.', 'Try a wider filter.'),
                actionLabel: t('مسح التصفية', 'Clear filter'),
                onAction: () => _setFilter(WsPeopleFilter(sort: _filter.sort)),
              ),
      );
    }
    final ws = _ws;
    return AppRefresh(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl),
        itemCount: _items.length + (_page < _pages ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            // the end of what is loaded: the next page loads here (also when the list is too short to scroll)
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
            return const Padding(
              padding: EdgeInsets.only(top: AppSpace.xs),
              child: AppListSkeleton(items: 1),
            );
          }
          final p = _items[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: WsPersonRow(
              person: p,
              selecting: _selecting,
              selected: _selected.contains(p.userId),
              onTap: _selecting ? () => _toggle(p.userId) : () => openWsPerson(context, ws, unitId: widget.unit.id, userId: p.userId),
              onLongPress: () => _toggle(p.userId),
            ),
          );
        },
      ),
    );
  }
}

String _rangeLabel(WsPeopleFilter f) {
  final a = f.joinedFrom == null ? '…' : AppTime.wall(f.joinedFrom!);
  final b = f.joinedTo == null ? '…' : AppTime.wall(f.joinedTo!);
  return '${t('الانضمام', 'Joined')}: $a – $b';
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => InputChip(
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onDeleted: onRemove,
        deleteButtonTooltipMessage: t('إزالة', 'Remove'),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Plain-value parts
// ═════════════════════════════════════════════════════════════════════════════

/// One person in a unit's list: avatar, name, title, kind, joined date; a checkbox while selecting.
class WsPersonRow extends StatelessWidget {
  const WsPersonRow({
    super.key,
    required this.person,
    this.selecting = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  final WsPerson person;
  final bool selecting, selected;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = person;
    final meta = [
      if (p.title != null) p.title!,
      if (p.joinedAt != null) '${t('انضم', 'Joined')} ${AppTime.date(p.joinedAt!.toUtc())}',
    ].join(' · ');
    return Semantics(
      selected: selecting ? selected : null,
      child: AppCard(
        highlight: selected,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(children: [
          if (selecting)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
              child: ExcludeSemantics(
                child: Checkbox(value: selected, onChanged: onTap == null ? null : (_) => onTap!()),
              ),
            ),
          AppAvatar(name: p.name, url: p.avatarUrl, size: AppTouch.min - AppSpace.xxs),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                AppStatusBadge(label: wsKindLabel(p.kind), tone: wsKindTone(p.kind), dense: true),
                if (meta.isNotEmpty) Text(meta, style: AppType.meta(context).copyWith(color: c.textMedium)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The bulk bar at the bottom of a people list (D-1154): count · Select all · Export · Remove · Close. [onRemove]
/// null hides Remove (a member, or a manager without bulk rights). Labelled buttons from 600 px, icons below.
class WsBulkBar extends StatelessWidget {
  const WsBulkBar({
    super.key,
    required this.count,
    required this.allSelected,
    required this.onSelectAll,
    required this.onExport,
    required this.onClose,
    this.onRemove,
  });

  final int count;
  final bool allSelected;
  final VoidCallback onSelectAll, onExport, onClose;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = countText(count, ar1: 'محدَّد واحد', ar2: 'محدَّدان', arFew: '$count محدَّدين', arMany: '$count محدَّدًا', en1: '1 selected', en: '$count selected');
    final selectAll = allSelected ? t('إلغاء تحديد الكل', 'Clear all') : t('تحديد الكل', 'Select all');
    return Material(
      color: c.cardBg,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth >= AppWidth.phoneMax;
              return Row(children: [
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                  ),
                ),
                if (wide) ...[
                  AppButton(label: selectAll, icon: Icons.select_all_rounded, variant: AppButtonVariant.ghost, size: AppButtonSize.sm, onPressed: onSelectAll),
                  const SizedBox(width: AppSpace.xxs),
                  AppButton(label: t('تصدير', 'Export'), icon: Icons.ios_share_rounded, variant: AppButtonVariant.secondary, size: AppButtonSize.sm, onPressed: onExport),
                  if (onRemove != null) ...[
                    const SizedBox(width: AppSpace.xxs),
                    AppButton(label: t('إزالة', 'Remove'), icon: Icons.person_remove_alt_1_rounded, variant: AppButtonVariant.danger, size: AppButtonSize.sm, onPressed: onRemove),
                  ],
                ] else ...[
                  AppIconButton(icon: Icons.select_all_rounded, tooltip: selectAll, onPressed: onSelectAll),
                  AppIconButton(icon: Icons.ios_share_rounded, tooltip: t('تصدير', 'Export'), onPressed: onExport),
                  if (onRemove != null) AppIconButton(icon: Icons.person_remove_alt_1_rounded, tooltip: t('إزالة', 'Remove'), onPressed: onRemove),
                ],
                AppIconButton(icon: Icons.close_rounded, tooltip: t('إغلاق', 'Close'), onPressed: onClose),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sheets
// ═════════════════════════════════════════════════════════════════════════════

class _WsFilterSheet extends StatefulWidget {
  const _WsFilterSheet({required this.initial});
  final WsPeopleFilter initial;

  @override
  State<_WsFilterSheet> createState() => _WsFilterSheetState();
}

class _WsFilterSheetState extends State<_WsFilterSheet> {
  late WsPeopleFilter _f = widget.initial;

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _f.joinedFrom != null && _f.joinedTo != null ? DateTimeRange(start: _f.joinedFrom!, end: _f.joinedTo!) : null,
    );
    if (r != null && mounted) setState(() => _f = _f.copyWith(joinedFrom: r.start, joinedTo: r.end));
  }

  @override
  Widget build(BuildContext context) {
    final hasDates = _f.joinedFrom != null || _f.joinedTo != null;
    return AppSheetContent(
      title: t('تصفية الأشخاص', 'Filter people'),
      icon: Icons.tune_rounded,
      children: [
        Text(t('الصفة', 'Role'), style: AppType.label(context)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final k in WsPersonKind.values)
            AppChoiceChip(
              label: wsKindLabel(k),
              selected: _f.kinds.contains(k),
              onTap: () => setState(() {
                final s = {..._f.kinds};
                if (!s.remove(k)) s.add(k);
                _f = _f.copyWith(kinds: s);
              }),
            ),
        ]),
        AppSpace.gapMd,
        Text(t('تاريخ الانضمام', 'Joined between'), style: AppType.label(context)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppButton(
            label: hasDates ? _rangeLabel(_f) : t('اختر الفترة', 'Choose dates'),
            icon: Icons.date_range_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: _pickDates,
          ),
          if (hasDates)
            AppIconButton(icon: Icons.close_rounded, tooltip: t('مسح التاريخ', 'Clear dates'), onPressed: () => setState(() => _f = _f.without())),
        ]),
        AppSpace.gapMd,
        Text(t('الترتيب', 'Sort'), style: AppType.label(context)),
        AppSpace.gapXs,
        OrgSegmented<WsSort>(
          value: _f.sort,
          options: [
            (WsSort.name, t('الاسم', 'Name')),
            (WsSort.newest, t('الأحدث', 'Newest')),
            (WsSort.oldest, t('الأقدم', 'Oldest')),
          ],
          onChanged: (s) => setState(() => _f = _f.copyWith(sort: s)),
        ),
        AppSpace.gapLg,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: [
          AppButton(
            label: t('مسح الكل', 'Clear all'),
            variant: AppButtonVariant.ghost,
            onPressed: () => setState(() => _f = WsPeopleFilter(q: _f.q)),
          ),
          AppButton(label: t('تطبيق', 'Apply'), icon: Icons.check_rounded, onPressed: () => Navigator.pop(context, _f)),
        ]),
      ],
    );
  }
}

class _WsSavedFiltersSheet extends StatelessWidget {
  const _WsSavedFiltersSheet({required this.current, required this.onApply});
  final WsPeopleFilter current;
  final ValueChanged<WsPeopleFilter> onApply;

  Future<void> _save(BuildContext context, WsController ws) async {
    final name = TextEditingController();
    final ok = await showAppDialog<bool>(
      context,
      title: t('حفظ التصفية', 'Save filter'),
      icon: Icons.bookmark_add_outlined,
      body: AppField(controller: name, label: t('الاسم', 'Name'), hint: t('مثل: الفريق الجديد', 'e.g. New team')),
      actions: [
        Builder(builder: (ctx) => AppButton(label: t('إلغاء', 'Cancel'), variant: AppButtonVariant.ghost, onPressed: () => Navigator.pop(ctx, false))),
        Builder(builder: (ctx) => AppButton(label: t('حفظ', 'Save'), onPressed: () => Navigator.pop(ctx, true))),
      ],
    );
    final n = name.text.trim();
    name.dispose();
    if (ok != true || n.isEmpty) return;
    await ws.prefs.update((p) => p.copyWith(savedFilters: {...p.savedFilters, n: current}));
    showAppNotice(t('حُفظت التصفية', 'Filter saved'));
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WsController>();
    final saved = ws.prefs.prefs.savedFilters;
    final c = context.colors;
    return AppSheetContent(
      title: t('التصفيات المحفوظة', 'Saved filters'),
      icon: Icons.bookmarks_outlined,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            label: t('حفظ التصفية الحالية', 'Save current filter'),
            icon: Icons.bookmark_add_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: current.isEmpty && current.sort == WsSort.name ? null : () => _save(context, ws),
          ),
        ),
        AppSpace.gapMd,
        if (saved.isEmpty)
          Text(t('لا توجد تصفيات محفوظة. اختر تصفية ثم احفظها هنا.', 'No saved filters. Set a filter, then save it here.'),
              style: AppType.body(context).copyWith(color: c.textMedium)),
        for (final e in saved.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: AppTouch.min,
            leading: const Icon(Icons.bookmark_outline_rounded),
            title: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              Navigator.pop(context);
              onApply(e.value);
            },
            trailing: AppIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: t('حذف', 'Delete'),
              onPressed: () => ws.prefs.update((p) => p.copyWith(savedFilters: {...p.savedFilters}..remove(e.key))),
            ),
          ),
      ],
    );
  }
}
