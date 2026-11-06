// lib/design/master_detail/entity_list_page.dart — ONE paged list for every role (D-290, phase 7). A role never writes a
// list: it writes an EntityListConfig (what to load, the columns, the card, the filter and sorts), and gets the same
// table on the web, the same cards on a phone, the same panel, states and keyboard everywhere.
//
//   EntityListPage<PersonRow>(config: EntityListConfig(
//     id: 'teacher_students',                  // this device remembers the columns and density under it
//     title: 'My students',                    // the panel's first breadcrumb
//     load: (q) => …,                          // one server page: EntityListQuery → EntityPage<T>
//     refOf: (row) => row.person,              // what a row opens (null: nothing)
//     columns: […], card: (context, row) => …,
//     sorts: ['activity_desc', 'name'], filter: EntityListFilter('state', […]),
//     empty: EntityListEmpty(icon, title, message),
//   ))
//
// The server pages, searches, filters and sorts; rows load as the list scrolls. Inside a page that already has its
// own scaffold (a tab of a screen), use the same widget; `deepLinks` writes `?open=` on the list's URL.
//
// Phase 8: `export:` (Excel · Word · PDF · CSV of every row or the selected ones), `bulk:` (actions over the
// selected rows: the table's checkboxes and bulk bar), saved views (`savedViews`, per person on the server), and the
// list's query on its URL (`?list=q%3D…`), so a filtered list is a link that can be shared.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/routing/web_history.dart';

import '../app_kit.dart';
import 'entity_detail_view.dart' show EntityActionsBuilder, entityErrorText;
import 'entity_list_tools.dart';
import 'entity_panel_controller.dart';
import 'entity_specs.dart' show mdSortLabel, mdText;
import 'master_detail_scaffold.dart';

/// The toolbar's one filter. [key] is the query parameter; each option is (value, label).
class EntityListFilter {
  const EntityListFilter(this.key, this.label, this.options);

  final String key;
  final String label;
  final List<(String, String)> options;
}

/// The list's empty state before any search or filter.
class EntityListEmpty {
  const EntityListEmpty(this.icon, this.title, {this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// One role's list over the shared page.
class EntityListConfig<T> {
  const EntityListConfig({
    required this.id,
    required this.title,
    required this.load,
    required this.idOf,
    required this.refOf,
    required this.columns,
    required this.card,
    required this.empty,
    this.rowKind,
    this.sorts = const [],
    this.filter,
    this.searchHint,
    this.pageSize = 20,
    this.fixedFilter = const {},
    this.searchable = true,
    this.export,
    this.bulk = const [],
    this.savedViews = true,
  });

  final String id;
  final String title;
  final Future<EntityPage<T>> Function(EntityListQuery query) load;
  final Object Function(T row) idOf;

  /// What a row opens in the panel (null: nothing; a row without an entity).
  final EntityRef? Function(T row) refOf;
  final List<AppTableColumn<T>> columns;

  /// The phone card of a row: the same information hierarchy as the columns.
  final Widget Function(BuildContext context, T row) card;
  final EntityListEmpty empty;

  /// The kind of the rows the panel steps through (null: they are mixed).
  final EntityKind? rowKind;

  /// The server's sorts, the default first.
  final List<String> sorts;
  final EntityListFilter? filter;
  final String? searchHint;
  final int pageSize;

  /// Sent with every page (a state the list is about).
  final Map<String, String> fixedFilter;

  /// False: the page around the list has its own search, or the list is short by nature.
  final bool searchable;

  /// The list's export (null: none).
  final EntityListExport<T>? export;

  /// Actions over the selected rows; with these or an [export], rows can be selected.
  final List<EntityBulkAction<T>> bulk;

  /// The Views button (saved queries of this list, per person).
  final bool savedViews;
}

/// [config]'s rows in the shared table, with the panel beside them (or as the phone's sheet).
class EntityListPage<T> extends StatefulWidget {
  const EntityListPage({super.key, required this.config, this.actions, this.deepLinks = true, this.controller});

  final EntityListConfig<T> config;
  final EntityActionsBuilder? actions;
  final bool deepLinks;

  /// The page's own controller (else one of its own).
  final EntityPanelController? controller;

  @override
  State<EntityListPage<T>> createState() => _EntityListPageState<T>();
}

class _EntityListPageState<T> extends State<EntityListPage<T>> {
  late final EntityPanelController _own = EntityPanelController(rowKind: widget.config.rowKind);

  EntityPanelController get _panel => widget.controller ?? _own;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MasterDetailScaffold(
        controller: _panel,
        rootLabel: widget.config.title,
        deepLinks: widget.deepLinks,
        actions: widget.actions,
        list: EntityListBody<T>(config: widget.config, panel: _panel, deepLinks: widget.deepLinks),
      );
}

/// The table alone (a page that hosts its own [MasterDetailScaffold]).
class EntityListBody<T> extends StatefulWidget {
  const EntityListBody({super.key, required this.config, required this.panel, this.deepLinks = false});

  final EntityListConfig<T> config;
  final EntityPanelController panel;

  /// The list's query is written on (and read from) its URL.
  final bool deepLinks;

  @override
  State<EntityListBody<T>> createState() => _EntityListBodyState<T>();
}

class _EntityListBodyState<T> extends State<EntityListBody<T>> {
  final _rows = <T>[];
  final _search = TextEditingController();
  late EntityListQuery _query = EntityListQuery(
    sort: widget.config.sorts.isEmpty ? null : widget.config.sorts.first,
    size: widget.config.pageSize,
  );
  final _selected = <Object>{};
  bool _exporting = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  int _ticket = 0;

  EntityListConfig<T> get _c => widget.config;

  EntityListQuery get _base => EntityListQuery(sort: _c.sorts.isEmpty ? null : _c.sorts.first, size: _c.pageSize);

  @override
  void initState() {
    super.initState();
    if (widget.deepLinks) {
      final asked = entityQueryFromParams(entityListParams(EntityLinkRequest.takeList()), _base,
          sorts: _c.sorts, filterKeys: {?_c.filter?.key});
      if (asked != null) {
        _query = asked;
        _search.text = asked.search;
      }
    }
    _reload();
  }

  @override
  void didUpdateWidget(covariant EntityListBody<T> old) {
    super.didUpdateWidget(old);
    if (old.config.id != _c.id) _reload();
  }

  @override
  void dispose() {
    if (widget.deepLinks) WebHistory.instance.setPageQuery(this, 'list', null);
    _search.dispose();
    super.dispose();
  }

  void _writeUrl() {
    if (!widget.deepLinks) return;
    WebHistory.instance.setPageQuery(this, 'list', entityListToken(_query, defaultSort: _base.sort));
  }

  EntityListQuery _send(EntityListQuery q) =>
      _c.fixedFilter.isEmpty ? q : q.copyWith(filter: {...q.filter, ..._c.fixedFilter});

  Future<void> _reload() async {
    final t = ++_ticket;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _query.copyWith(page: 1);
      final p = await _c.load(_send(q));
      if (!mounted || t != _ticket) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(p.items);
        _hasMore = p.hasMore;
        _query = q;
        _loading = false;
        _selected.removeWhere((id) => !_rows.any((r) => _c.idOf(r) == id));
      });
      _writeUrl();
    } catch (e) {
      if (!mounted || t != _ticket) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _more() async {
    if (_loadingMore || _loading || !_hasMore) return;
    final t = _ticket;
    setState(() => _loadingMore = true);
    final next = _query.copyWith(page: _query.page + 1);
    try {
      final p = await _c.load(_send(next));
      if (!mounted || t != _ticket) return;
      setState(() {
        _rows.addAll(p.items);
        _hasMore = p.hasMore;
        _query = next;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || t != _ticket) return;
      setState(() {
        _loadingMore = false;
        _hasMore = false;
      });
      showAppNotice(entityErrorText(e), error: true);
    }
  }

  void _setSearch(String q) {
    if (q.trim() == _query.search) return;
    _query = _query.copyWith(search: q.trim());
    _reload();
  }

  void _setFilter(String? v) {
    final f = _c.filter;
    if (f == null) return;
    _query = _query.copyWith(filter: v == null ? const {} : {f.key: v});
    _reload();
  }

  void _setSort(String? s) {
    if (s == null || s == _query.sort) return;
    _query = _query.copyWith(sort: s);
    _reload();
  }

  void _clear() {
    _search.clear();
    _query = _query.copyWith(search: '', filter: const {});
    _reload();
  }

  /// A saved view (or a link) replaces the whole query.
  void _apply(EntityListQuery q) {
    _search.text = q.search;
    _query = _base.copyWith(search: q.search, sort: _c.sorts.contains(q.sort) ? q.sort : _base.sort, filter: q.filter);
    _reload();
  }

  bool get _isDefault => _query.search.isEmpty && _query.filter.isEmpty && _query.sort == _base.sort;

  List<T> get _selectedRows => [
        for (final r in _rows)
          if (_selected.contains(_c.idOf(r))) r,
      ];

  /// Every row of the query (pages of 100, up to the export's maxRows).
  Future<List<T>> _allRows(EntityListExport<T> e) async {
    if (!_hasMore) return List.of(_rows);
    final out = <T>[];
    var page = 1;
    while (out.length < e.maxRows) {
      final p = await _c.load(_send(_query.copyWith(page: page, size: 100)));
      out.addAll(p.items);
      if (!p.hasMore) break;
      page++;
    }
    return out.length > e.maxRows ? out.sublist(0, e.maxRows) : out;
  }

  /// The filter's label and the chosen option's label, for the export's header.
  Map<String, String> _exportFilters() {
    final f = _c.filter;
    final v = f == null ? null : _query.filter[f.key];
    return {
      if (_query.search.isNotEmpty) 'md_search'.tr: _query.search,
      if (f != null && v != null) f.label: f.options.where((o) => o.$1 == v).firstOrNull?.$2 ?? v,
    };
  }

  Future<void> _export(EntityExportChoice how, {bool onlySelected = false}) async {
    final e = _c.export;
    if (e == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final picked = _selectedRows;
      final rows = onlySelected ? picked : await _allRows(e);
      if (!mounted) return;
      final data = [for (final r in rows) e.row(r)];
      if (how == EntityExportChoice.csv) {
        await entityExportCsv(_c.title, e.columns, data);
      } else {
        await showAppExportSheet(
          context,
          AppTableExport(
            id: 'md.${_c.id}',
            title: _c.title,
            columns: e.columns,
            rows: data,
            filters: _exportFilters(),
            selectedRows: onlySelected || picked.isEmpty ? null : [for (final r in picked) e.row(r)],
          ),
        );
      }
    } catch (err) {
      showAppNotice(entityErrorText(err), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _exportButton(BuildContext context) => PopupMenuButton<EntityExportChoice>(
        key: ValueKey('${_c.id}.export'),
        tooltip: 'md_p8_export'.tr,
        enabled: !_exporting && _rows.isNotEmpty,
        onSelected: _export,
        itemBuilder: (_) => [
          PopupMenuItem(value: EntityExportChoice.studio, child: Text('md_p8_export_studio'.tr)),
          PopupMenuItem(value: EntityExportChoice.csv, child: Text('md_p8_export_csv'.tr)),
        ],
        child: SizedBox.square(
          dimension: AppTouch.min,
          child: Center(
            child: _exporting
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_download_outlined),
          ),
        ),
      );

  Widget _viewsButton(BuildContext context) => AppIconButton(
        key: ValueKey('${_c.id}.views'),
        icon: _isDefault ? Icons.bookmarks_outlined : Icons.bookmarks_rounded,
        tooltip: 'md_p8_views'.tr,
        onPressed: () => showEntityViewsSheet(
          context,
          listId: _c.id,
          current: _query,
          canSave: !_isDefault,
          onApply: _apply,
        ),
      );

  List<Widget> _bulkActions(BuildContext context) {
    final picked = _selectedRows;
    return [
      for (final a in _c.bulk)
        AppButton.tonal(
          label: a.label,
          icon: a.icon,
          size: AppButtonSize.sm,
          tooltip: a.max != null && picked.length > a.max! ? mdText('md_p8_bulk_first', {'n': '${a.max}'}) : null,
          onPressed: () => a.run(context, a.max == null ? picked : picked.take(a.max!).toList()),
        ),
      if (_c.export != null)
        AppButton.tonal(
          label: 'md_p8_export_selected'.tr,
          icon: Icons.file_download_outlined,
          size: AppButtonSize.sm,
          onPressed: () => _export(EntityExportChoice.studio, onlySelected: true),
        ),
    ];
  }

  void _open(T row) {
    final ref = _c.refOf(row);
    if (ref != null) widget.panel.open(ref);
  }

  @override
  Widget build(BuildContext context) {
    final f = _c.filter;
    final filterValue = f == null ? null : _query.filter[f.key];
    final querying = _query.search.isNotEmpty || filterValue != null;
    final empty = _c.empty;
    final selectable = _c.bulk.isNotEmpty || _c.export != null;
    final sort = _c.sorts.length < 2
        ? null
        : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: AppDropdown<String>(
              key: ValueKey('${_c.id}.sort'),
              value: _query.sort,
              decoration: InputDecoration(labelText: 'md_sort'.tr, isDense: true),
              items: [for (final s in _c.sorts) DropdownMenuItem(value: s, child: Text(mdSortLabel(s)))],
              onChanged: _setSort,
            ),
          );
    final tools = <Widget>[
      ?sort,
      if (_c.savedViews) _viewsButton(context),
      if (_c.export != null) _exportButton(context),
    ];
    return ListenableBuilder(
      listenable: widget.panel,
      builder: (context, _) {
        widget.panel.siblings = [for (final r in _rows) ?_c.refOf(r)];
        return AppDataTable<T>(
          tableId: _c.id,
          columnMenu: true,
          columns: _c.columns,
          rows: _rows,
          rowId: _c.idOf,
          state: _loading ? AppTableState.loading : (_error != null ? AppTableState.error : AppTableState.ready),
          errorText: _error == null ? null : entityErrorText(_error),
          onRetry: _reload,
          searchHint: _c.searchHint ?? 'md_search'.tr,
          onSearch: _c.searchable ? _setSearch : null,
          searchController: _c.searchable ? _search : null,
          filters: f == null
              ? null
              : [AppTableFilter(label: f.label, options: f.options, value: filterValue, onChanged: _setFilter)],
          onClearFilters: querying ? _clear : null,
          toolbarTrailing: tools.isEmpty
              ? null
              : Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: tools,
                ),
          selectable: selectable,
          selected: selectable ? _selected : null,
          onSelectionChanged: (s) => setState(() {
            _selected
              ..clear()
              ..addAll(s);
          }),
          bulkActions: selectable ? (_) => _bulkActions(context) : null,
          empty: querying
              ? null
              : AppEmpty(
                  icon: empty.icon,
                  title: empty.title,
                  message: empty.message,
                  actionLabel: empty.actionLabel,
                  onAction: empty.onAction,
                ),
          onRowTap: _open,
          onRowHover: (row) {
            final ref = _c.refOf(row);
            if (ref != null) EntitiesApi.instance.prefetch(ref);
          },
          mobileCard: _c.card,
          selectedRowId: widget.panel.selectedId,
          onLoadMore: _more,
          hasMore: _hasMore,
          loadingMore: _loadingMore,
        );
      },
    );
  }
}
