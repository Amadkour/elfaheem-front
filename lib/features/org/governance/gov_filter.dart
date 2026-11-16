// lib/features/org/governance/gov_filter.dart — THE shared filter of every governance list.
//
//   ItemFilter       pure query model ⇄ `GET …/items` query string (spec §4), saved-filter JSON, human chips
//   ItemFilterBar    search box · quick chips (All / Waiting for me / Mine / Overdue) · the controls inline on a
//                    wide screen, behind a "Filters (n)" button on a phone · active chips · saved filters menu
//   ItemFilterControls  the controls themselves (types, statuses, dates, entity, assignee, category, outcome, sort)
//
// The bar is presentational: lists (entities, people, categories, saved filters) and callbacks come from the page,
// so the layout harness pumps it with sample values. Tests: test/org/gov_filter_test.dart.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show Debouncer, SheetHeader, asInt, askText, t;
import '../org_v3.dart' show orgDay;
import 'gov_models.dart';
import 'gov_ui.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  ItemFilter (pure)
// ═════════════════════════════════════════════════════════════════════════════

const itemSorts = ['-created_at', 'created_at', 'due_at', 'status', 'priority'];

String itemSortLabel(String s) =>
    {
      '-created_at': t('الأحدث أولاً', 'Newest first'),
      'created_at': t('الأقدم أولاً', 'Oldest first'),
      'due_at': t('الاستحقاق', 'Due date'),
      'status': t('الحالة', 'Status'),
      'priority': t('الأولوية', 'Priority'),
    }[s] ??
    s;

/// One active axis of a filter, for the removable chips row.
class FilterChipInfo {
  const FilterChipInfo(this.key, this.label);
  final String key, label;
  @override
  String toString() => '$key: $label';
}

class ItemFilter {
  const ItemFilter({
    this.q = '',
    this.types = const [],
    this.statuses = const [],
    this.deptId,
    this.sourceDeptId,
    this.sourceUserId,
    this.assigneeId,
    this.categoryId,
    this.outcomes = const [],
    this.dateFrom,
    this.dateTo,
    this.mine = false,
    this.toMe = false,
    this.overdue = false,
    this.escalated = false,
    this.sort = '-created_at',
  });

  final String q;
  final List<String> types, statuses, outcomes;
  final int? deptId, sourceDeptId, sourceUserId, assigneeId, categoryId;
  final DateTime? dateFrom, dateTo;
  final bool mine, toMe, overdue;

  /// Open and escalated at least once (`escalated=true`, the faculty overview's figure, D-979).
  final bool escalated;
  final String sort;

  static const _unset = Object();

  ItemFilter copyWith({
    String? q,
    List<String>? types,
    List<String>? statuses,
    Object? deptId = _unset,
    Object? sourceDeptId = _unset,
    Object? sourceUserId = _unset,
    Object? assigneeId = _unset,
    Object? categoryId = _unset,
    List<String>? outcomes,
    Object? dateFrom = _unset,
    Object? dateTo = _unset,
    bool? mine,
    bool? toMe,
    bool? overdue,
    bool? escalated,
    String? sort,
  }) =>
      ItemFilter(
        q: q ?? this.q,
        types: types ?? this.types,
        statuses: statuses ?? this.statuses,
        deptId: identical(deptId, _unset) ? this.deptId : deptId as int?,
        sourceDeptId: identical(sourceDeptId, _unset) ? this.sourceDeptId : sourceDeptId as int?,
        sourceUserId: identical(sourceUserId, _unset) ? this.sourceUserId : sourceUserId as int?,
        assigneeId: identical(assigneeId, _unset) ? this.assigneeId : assigneeId as int?,
        categoryId: identical(categoryId, _unset) ? this.categoryId : categoryId as int?,
        outcomes: outcomes ?? this.outcomes,
        dateFrom: identical(dateFrom, _unset) ? this.dateFrom : dateFrom as DateTime?,
        dateTo: identical(dateTo, _unset) ? this.dateTo : dateTo as DateTime?,
        mine: mine ?? this.mine,
        toMe: toMe ?? this.toMe,
        overdue: overdue ?? this.overdue,
        escalated: escalated ?? this.escalated,
        sort: sort ?? this.sort,
      );

  /// The quick tab (`all` · `to_me` · `mine` · `overdue`) this filter sits on.
  String get quick => toMe
      ? 'to_me'
      : mine
          ? 'mine'
          : overdue
              ? 'overdue'
              : 'all';

  /// Switches the quick tab (the three flags are exclusive in the bar).
  ItemFilter withQuick(String key) => copyWith(toMe: key == 'to_me', mine: key == 'mine', overdue: key == 'overdue');

  bool get isEmpty => activeCount == 0 && q.isEmpty && sort == '-created_at';

  /// Number of narrowing axes (the search text and the sort order do not count).
  int get activeCount =>
      (types.isNotEmpty ? 1 : 0) +
      (statuses.isNotEmpty ? 1 : 0) +
      (deptId != null ? 1 : 0) +
      (sourceDeptId != null ? 1 : 0) +
      (sourceUserId != null ? 1 : 0) +
      (assigneeId != null ? 1 : 0) +
      (categoryId != null ? 1 : 0) +
      (outcomes.isNotEmpty ? 1 : 0) +
      (dateFrom != null || dateTo != null ? 1 : 0) +
      (mine ? 1 : 0) +
      (toMe ? 1 : 0) +
      (overdue ? 1 : 0) +
      (escalated ? 1 : 0);

  /// The query string of `GET …/items` (only the set axes; csv for lists; days as YYYY-MM-DD).
  Map<String, dynamic> toQuery() => {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        if (types.isNotEmpty) 'type': types.join(','),
        if (statuses.isNotEmpty) 'status': statuses.join(','),
        if (deptId != null) 'dept_id': deptId,
        if (sourceDeptId != null) 'source_dept_id': sourceDeptId,
        if (sourceUserId != null) 'source_user_id': sourceUserId,
        if (assigneeId != null) 'assignee_id': assigneeId,
        if (categoryId != null) 'category_id': categoryId,
        if (outcomes.isNotEmpty) 'outcome': outcomes.join(','),
        if (dateFrom != null) 'date_from': orgDay(dateFrom),
        if (dateTo != null) 'date_to': orgDay(dateTo),
        if (mine) 'mine': true,
        if (toMe) 'to_me': true,
        if (overdue) 'overdue': true,
        if (escalated) 'escalated': true,
        if (sort != '-created_at') 'sort': sort,
      };

  /// The inverse of [toQuery] (also reads a saved filter's `query`, where lists may be JSON arrays).
  static ItemFilter fromQuery(Map<String, dynamic> m) {
    List<String> csv(dynamic v) {
      if (v == null) return const [];
      if (v is List) return [for (final x in v) '$x'].where((s) => s.isNotEmpty).toList();
      return '$v'.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }

    int? id(dynamic v) => v == null || '$v'.isEmpty ? null : asInt(v);
    bool flag(dynamic v) => v == true || v == 1 || '$v' == 'true' || '$v' == '1';
    DateTime? day(dynamic v) {
      final s = '${v ?? ''}';
      if (s.isEmpty) return null;
      final d = DateTime.tryParse(s);
      return d == null ? null : DateTime(d.year, d.month, d.day);
    }

    return ItemFilter(
      q: '${m['q'] ?? ''}',
      types: csv(m['type']),
      statuses: csv(m['status']),
      deptId: id(m['dept_id']),
      sourceDeptId: id(m['source_dept_id']),
      sourceUserId: id(m['source_user_id']),
      assigneeId: id(m['assignee_id']),
      categoryId: id(m['category_id']),
      outcomes: csv(m['outcome']),
      dateFrom: day(m['date_from']),
      dateTo: day(m['date_to']),
      mine: flag(m['mine']),
      toMe: flag(m['to_me']),
      overdue: flag(m['overdue']),
      escalated: flag(m['escalated']),
      sort: itemSorts.contains(m['sort']) ? '${m['sort']}' : '-created_at',
    );
  }

  /// Human descriptions of the set axes; names come from the page's lookups when given.
  List<FilterChipInfo> chips({String Function(int)? deptName, String Function(int)? userName, String Function(int)? categoryName}) {
    String dn(int id) => deptName?.call(id) ?? '#$id';
    String un(int id) => userName?.call(id) ?? '#$id';
    return [
      if (types.isNotEmpty) FilterChipInfo('types', '${t('النوع', 'Type')}: ${types.map(itemTypeLabel).join('، ')}'),
      if (statuses.isNotEmpty) FilterChipInfo('statuses', '${t('الحالة', 'Status')}: ${statuses.map(itemStatusLabel).join('، ')}'),
      if (deptId != null) FilterChipInfo('deptId', '${t('الجهة', 'Entity')}: ${dn(deptId!)}'),
      if (sourceDeptId != null) FilterChipInfo('sourceDeptId', '${t('من جهة', 'From entity')}: ${dn(sourceDeptId!)}'),
      if (sourceUserId != null) FilterChipInfo('sourceUserId', '${t('مقدّمها', 'Submitted by')}: ${un(sourceUserId!)}'),
      if (assigneeId != null) FilterChipInfo('assigneeId', '${t('المسؤول', 'Assignee')}: ${un(assigneeId!)}'),
      if (categoryId != null) FilterChipInfo('categoryId', '${t('التصنيف', 'Category')}: ${categoryName?.call(categoryId!) ?? '#$categoryId'}'),
      if (outcomes.isNotEmpty) FilterChipInfo('outcomes', '${t('نتيجة التصويت', 'Vote outcome')}: ${outcomes.map(voteOutcomeLabel).join('، ')}'),
      if (dateFrom != null || dateTo != null)
        FilterChipInfo('dates', '${t('التاريخ', 'Date')}: ${dateFrom == null ? '…' : govDay(dateFrom)} – ${dateTo == null ? '…' : govDay(dateTo)}'),
      if (toMe) FilterChipInfo('toMe', t('بانتظاري', 'Waiting for me')),
      if (mine) FilterChipInfo('mine', t('ما قدّمته', 'Mine')),
      if (overdue) FilterChipInfo('overdue', t('متأخرة', 'Overdue')),
      if (escalated) FilterChipInfo('escalated', t('مصعَّدة', 'Escalated')),
    ];
  }

  /// This filter without the axis [key] (a chip's key).
  ItemFilter without(String key) => switch (key) {
        'types' => copyWith(types: const []),
        'statuses' => copyWith(statuses: const []),
        'deptId' => copyWith(deptId: null),
        'sourceDeptId' => copyWith(sourceDeptId: null),
        'sourceUserId' => copyWith(sourceUserId: null),
        'assigneeId' => copyWith(assigneeId: null),
        'categoryId' => copyWith(categoryId: null),
        'outcomes' => copyWith(outcomes: const []),
        'dates' => copyWith(dateFrom: null, dateTo: null),
        'toMe' => copyWith(toMe: false),
        'mine' => copyWith(mine: false),
        'overdue' => copyWith(overdue: false),
        'escalated' => copyWith(escalated: false),
        _ => this,
      };

  /// Everything cleared except what the page fixes (its entity and the quick tab).
  ItemFilter cleared({bool keepQuick = true, bool keepDept = false}) => ItemFilter(
        deptId: keepDept ? deptId : null,
        mine: keepQuick && mine,
        toMe: keepQuick && toMe,
        overdue: keepQuick && overdue,
      );

  @override
  bool operator ==(Object other) => other is ItemFilter && _key == other._key;

  @override
  int get hashCode => _key.hashCode;

  String get _key => toQuery().entries.map((e) => '${e.key}=${e.value}').join('&');

  @override
  String toString() => 'ItemFilter($_key)';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Controls (shared by the inline bar and the phone sheet)
// ═════════════════════════════════════════════════════════════════════════════

class ItemFilterControls extends StatelessWidget {
  const ItemFilterControls({
    super.key,
    required this.filter,
    required this.onChanged,
    this.entities = const [],
    this.people = const {},
    this.categories = const [],
    this.showEntity = true,
    this.onPickPerson,
  });

  final ItemFilter filter;
  final ValueChanged<ItemFilter> onChanged;
  final List<Entity> entities;
  final Map<int, String> people;
  final List<Category> categories;
  final bool showEntity;

  /// Search a person (assignee); the controls fall back to the [people] list when absent.
  final Future<GovUser?> Function()? onPickPerson;

  @override
  Widget build(BuildContext context) {
    final f = filter;
    final peopleItems = {...people, if (f.assigneeId != null && !people.containsKey(f.assigneeId)) f.assigneeId!: '#${f.assigneeId}'};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GovChipSelect(
        label: t('النوع', 'Type'),
        icon: Icons.category_outlined,
        options: {for (final x in itemTypes) x: itemTypeLabel(x)},
        selected: f.types,
        onChanged: (v) => onChanged(f.copyWith(types: v)),
      ),
      const SizedBox(height: AppSpace.sm),
      GovChipSelect(
        label: t('الحالة', 'Status'),
        icon: Icons.flag_outlined,
        options: {for (final x in itemStatuses) x: itemStatusLabel(x)},
        selected: f.statuses,
        onChanged: (v) => onChanged(f.copyWith(statuses: v)),
      ),
      const SizedBox(height: AppSpace.sm),
      LayoutBuilder(builder: (context, box) {
        final from = GovDateField(
          label: t('من تاريخ', 'From'),
          value: f.dateFrom,
          onPick: () async {
            final d = await pickGovDate(context, initial: f.dateFrom);
            if (d != null) onChanged(f.copyWith(dateFrom: d));
          },
          onClear: () => onChanged(f.copyWith(dateFrom: null)),
        );
        final to = GovDateField(
          label: t('إلى تاريخ', 'To'),
          value: f.dateTo,
          onPick: () async {
            final d = await pickGovDate(context, initial: f.dateTo ?? f.dateFrom);
            if (d != null) onChanged(f.copyWith(dateTo: d));
          },
          onClear: () => onChanged(f.copyWith(dateTo: null)),
        );
        if (box.maxWidth < 420) return Column(children: [from, const SizedBox(height: AppSpace.sm), to]);
        return Row(children: [Expanded(child: from), const SizedBox(width: AppSpace.sm), Expanded(child: to)]);
      }),
      if (showEntity && entities.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        AppDropdown<int>(
          value: f.deptId ?? 0,
          decoration: InputDecoration(labelText: t('الجهة المالكة', 'Owner entity'), prefixIcon: const Icon(Icons.apartment_rounded)),
          items: [
            DropdownMenuItem(value: 0, child: Text(t('كل الجهات', 'Every entity'))),
            for (final e in entities) DropdownMenuItem(value: e.id, child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => onChanged(f.copyWith(deptId: v == null || v == 0 ? null : v)),
        ),
      ],
      if (showEntity && entities.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        AppDropdown<int>(
          value: f.sourceDeptId ?? 0,
          decoration: InputDecoration(labelText: t('الجهة المصدر', 'Source entity'), prefixIcon: const Icon(Icons.outbox_rounded)),
          items: [
            DropdownMenuItem(value: 0, child: Text(t('أي مصدر', 'Any source'))),
            for (final e in entities) DropdownMenuItem(value: e.id, child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => onChanged(f.copyWith(sourceDeptId: v == null || v == 0 ? null : v)),
        ),
      ],
      const SizedBox(height: AppSpace.sm),
      if (onPickPerson != null)
        GovPersonField(
          label: t('المسؤول (المسند إليه)', 'Assignee'),
          person: f.assigneeId == null ? null : GovUser(id: f.assigneeId!, name: peopleItems[f.assigneeId] ?? '#${f.assigneeId}'),
          onPick: () async {
            final p = await onPickPerson!();
            if (p != null) onChanged(f.copyWith(assigneeId: p.id));
          },
          onClear: () => onChanged(f.copyWith(assigneeId: null)),
        )
      else if (peopleItems.isNotEmpty)
        AppDropdown<int>(
          value: f.assigneeId ?? 0,
          decoration: InputDecoration(labelText: t('المسؤول (المسند إليه)', 'Assignee'), prefixIcon: const Icon(Icons.person_rounded)),
          items: [
            DropdownMenuItem(value: 0, child: Text(t('أي شخص', 'Anyone'))),
            for (final e in peopleItems.entries) DropdownMenuItem(value: e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => onChanged(f.copyWith(assigneeId: v == null || v == 0 ? null : v)),
        ),
      if (categories.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        AppDropdown<int>(
          value: f.categoryId ?? 0,
          decoration: InputDecoration(labelText: t('التصنيف', 'Category'), prefixIcon: const Icon(Icons.label_outline_rounded)),
          items: [
            DropdownMenuItem(value: 0, child: Text(t('كل التصنيفات', 'Every category'))),
            for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => onChanged(f.copyWith(categoryId: v == null || v == 0 ? null : v)),
        ),
      ],
      const SizedBox(height: AppSpace.sm),
      GovChipSelect(
        label: t('نتيجة التصويت', 'Vote outcome'),
        icon: Icons.how_to_vote_outlined,
        options: {for (final x in voteOutcomes) x: voteOutcomeLabel(x)},
        selected: f.outcomes,
        onChanged: (v) => onChanged(f.copyWith(outcomes: v)),
      ),
      const SizedBox(height: AppSpace.sm),
      AppDropdown<String>(
        value: f.sort,
        decoration: InputDecoration(labelText: t('الترتيب', 'Sort'), prefixIcon: const Icon(Icons.sort_rounded)),
        items: [for (final s in itemSorts) DropdownMenuItem(value: s, child: Text(itemSortLabel(s)))],
        onChanged: (v) => onChanged(f.copyWith(sort: v ?? '-created_at')),
      ),
    ]);
  }
}

/// The phone sheet: the same controls on a draft, Apply / Clear at the bottom. Returns the new filter or null.
Future<ItemFilter?> showItemFilterSheet(
  BuildContext context,
  ItemFilter filter, {
  List<Entity> entities = const [],
  Map<int, String> people = const {},
  List<Category> categories = const [],
  bool showEntity = true,
  Future<GovUser?> Function()? onPickPerson,
}) {
  var draft = filter;
  return showAppSheet<ItemFilter>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(tone: AppTone.neutral, icon: Icons.tune_rounded, 
            t('تصفية', 'Filters'),
            trailing: TextButton(
              onPressed: () => set(() => draft = draft.cleared(keepDept: !showEntity)),
              child: Text(t('مسح', 'Clear'), style: AppType.label(ctx).copyWith(fontWeight: FontWeight.w600, color: c.danger)),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
              child: ItemFilterControls(
                filter: draft,
                onChanged: (f) => set(() => draft = f),
                entities: entities,
                people: people,
                categories: categories,
                showEntity: showEntity,
                onPickPerson: onPickPerson,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md),
            child: AppPrimaryButton(label: t('تطبيق', 'Apply'), icon: Icons.check_rounded, onPressed: () => Navigator.pop(ctx, draft)),
          ),
        ]);
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  The bar
// ═════════════════════════════════════════════════════════════════════════════

class ItemFilterBar extends StatefulWidget {
  const ItemFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    this.scope = 'items',
    this.entities = const [],
    this.people = const {},
    this.categories = const [],
    this.savedFilters = const [],
    this.onSaveFilter,
    this.onDeleteFilter,
    this.showQuick = true,
    this.showEntity = true,
    this.onPickPerson,
    this.wideBreakpoint = 820,
  });

  final ItemFilter filter;
  final ValueChanged<ItemFilter> onChanged;
  final String scope;
  final List<Entity> entities;
  final Map<int, String> people;
  final List<Category> categories;
  final List<SavedFilter> savedFilters;
  final Future<void> Function(String name, ItemFilter filter)? onSaveFilter;
  final Future<void> Function(SavedFilter f)? onDeleteFilter;
  final bool showQuick, showEntity;
  final Future<GovUser?> Function()? onPickPerson;
  final double wideBreakpoint;

  @override
  State<ItemFilterBar> createState() => _ItemFilterBarState();
}

class _ItemFilterBarState extends State<ItemFilterBar> {
  bool _open = false; // inline controls expanded (wide screens)

  String _deptName(int id) {
    for (final e in widget.entities) {
      if (e.id == id) return e.name;
    }
    return '#$id';
  }

  String _catName(int id) {
    for (final c in widget.categories) {
      if (c.id == id) return c.name;
    }
    return '#$id';
  }

  Future<void> _openSheet() async {
    final r = await showItemFilterSheet(
      context,
      widget.filter,
      entities: widget.entities,
      people: widget.people,
      categories: widget.categories,
      showEntity: widget.showEntity,
      onPickPerson: widget.onPickPerson,
    );
    if (r != null) widget.onChanged(r);
  }

  Future<void> _saveCurrent() async {
    final name = await askText(context, title: t('اسم الفلتر', 'Filter name'), hint: t('مثلاً: شكاوى متأخرة', 'e.g. Overdue complaints'));
    if (name == null || name.trim().isEmpty) return;
    await widget.onSaveFilter?.call(name.trim(), widget.filter);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = widget.filter;
    final chips = f.chips(deptName: _deptName, userName: (id) => widget.people[id] ?? '#$id', categoryName: _catName)
        .where((ch) => !(widget.showQuick && const ['toMe', 'mine', 'overdue'].contains(ch.key)))
        .where((ch) => !(!widget.showEntity && ch.key == 'deptId'))
        .toList();
    final n = chips.length;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= widget.wideBreakpoint;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: _SearchField(
              value: f.q,
              onChanged: (q) => widget.onChanged(f.copyWith(q: q)),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          _FilterButton(
            count: n,
            open: wide && _open,
            onTap: wide ? () => setState(() => _open = !_open) : _openSheet,
          ),
          if (widget.onSaveFilter != null || widget.savedFilters.isNotEmpty) ...[
            const SizedBox(width: AppSpace.xxs),
            PopupMenuButton<Object>(
              tooltip: t('الفلاتر المحفوظة', 'Saved filters'),
              icon: Icon(Icons.bookmark_border_rounded, color: c.textMedium),
              onSelected: (v) {
                if (v == 'save') {
                  unawaited(_saveCurrent());
                  return;
                }
                if (v is SavedFilter) widget.onChanged(ItemFilter.fromQuery(v.query));
              },
              itemBuilder: (_) => [
                for (final s in widget.savedFilters)
                  PopupMenuItem<Object>(
                    value: s,
                    child: Row(children: [
                      Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (widget.onDeleteFilter != null)
                        IconButton(
                          tooltip: t('حذف', 'Delete'),
                          icon: Icon(Icons.delete_outline_rounded, size: AppIconSize.md, color: c.danger),
                          onPressed: () {
                            Navigator.pop(context);
                            unawaited(widget.onDeleteFilter!(s));
                          },
                        ),
                    ]),
                  ),
                if (widget.savedFilters.isEmpty)
                  PopupMenuItem<Object>(enabled: false, child: Text(t('لا فلاتر محفوظة بعد', 'No saved filters yet'))),
                if (widget.onSaveFilter != null) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem<Object>(
                    value: 'save',
                    child: Row(children: [
                      const Icon(Icons.bookmark_add_outlined, size: AppIconSize.md),
                      const SizedBox(width: AppSpace.xs),
                      Text(t('حفظ الفلتر الحالي…', 'Save current filter…')),
                    ]),
                  ),
                ],
              ],
            ),
          ],
        ]),
        if (widget.showQuick) ...[
          const SizedBox(height: AppSpace.xs),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final e in _quickOptions().entries) ...[
                AppChoiceChip(label: e.value.$1, icon: e.value.$2, selected: f.quick == e.key, onTap: () => widget.onChanged(f.withQuick(e.key))),
                const SizedBox(width: AppSpace.xs),
              ],
            ]),
          ),
        ],
        if (chips.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final ch in chips)
              InputChip(
                label: Text(ch.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
                onDeleted: () => widget.onChanged(f.without(ch.key)),
                deleteIconColor: c.textMedium,
                backgroundColor: c.primaryWash,
                side: BorderSide(color: c.primary.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                visualDensity: VisualDensity.compact,
              ),
            TextButton.icon(
              onPressed: () => widget.onChanged(f.cleared(keepDept: !widget.showEntity)),
              icon: Icon(Icons.filter_alt_off_rounded, size: AppIconSize.sm, color: c.danger),
              label: Text(t('مسح الكل', 'Clear all'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.danger)),
            ),
          ]),
        ],
        if (wide && _open) ...[
          const SizedBox(height: AppSpace.sm),
          AppCard(
            child: ItemFilterControls(
              filter: f,
              onChanged: widget.onChanged,
              entities: widget.entities,
              people: widget.people,
              categories: widget.categories,
              showEntity: widget.showEntity,
              onPickPerson: widget.onPickPerson,
            ),
          ),
        ],
      ]);
    });
  }

  Map<String, (String, IconData)> _quickOptions() => {
        'all': (t('الكل', 'All'), Icons.all_inbox_rounded),
        'to_me': (t('بانتظاري', 'Waiting for me'), Icons.notifications_active_rounded),
        'mine': (t('ما قدّمته', 'Mine'), Icons.person_rounded),
        'overdue': (t('متأخرة', 'Overdue'), Icons.timer_off_rounded),
      };
}



class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.open, required this.onTap});
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = count > 0 || open;
    return Material(
      color: on ? c.primaryWash : c.inputBg,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: on ? c.primary.withValues(alpha: 0.3) : c.divider)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.tune_rounded, size: AppIconSize.md, color: on ? c.primary : c.textMedium),
            if (count > 0) ...[
              const SizedBox(width: AppSpace.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 1),
                decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: Text('$count', style: AppType.overline(context).copyWith(color: c.onHero)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A debounced search box that follows an external value (a saved filter loads its text).
class _SearchField extends StatefulWidget {
  const _SearchField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final _ctrl = TextEditingController(text: widget.value);
  final _debounce = Debouncer(const Duration(milliseconds: 500));
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _SearchField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && widget.value != _ctrl.text && !_focus.hasFocus) _ctrl.text = widget.value;
  }

  @override
  void dispose() {
    _debounce.dispose();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      onChanged: (v) {
        setState(() {});
        _debounce.run(() => widget.onChanged(v.trim()));
      },
      onSubmitted: (v) => _debounce.flush(() => widget.onChanged(v.trim())),
      textInputAction: TextInputAction.search,
      style: AppType.row(context).copyWith(color: c.textDark),
      decoration: InputDecoration(
        hintText: t('ابحث برقم المرجع أو العنوان…', 'Search by reference or title…'),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _ctrl.text.isEmpty
            ? null
            : IconButton(tooltip: t('مسح', 'Clear'), 
                icon: const Icon(Icons.close_rounded, size: AppIconSize.md),
                onPressed: () {
                  _ctrl.clear();
                  _debounce.flush(() => widget.onChanged(''));
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: c.inputBg,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.sm),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.primary, width: 1.6)),
      ),
    );
  }
}
