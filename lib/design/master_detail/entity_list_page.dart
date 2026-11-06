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
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';

import '../app_kit.dart';
import 'entity_detail_view.dart' show EntityActionsBuilder, entityErrorText;
import 'entity_panel_controller.dart';
import 'entity_specs.dart' show mdSortLabel;
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
        list: EntityListBody<T>(config: widget.config, panel: _panel),
      );
}

/// The table alone (a page that hosts its own [MasterDetailScaffold]).
class EntityListBody<T> extends StatefulWidget {
  const EntityListBody({super.key, required this.config, required this.panel});

  final EntityListConfig<T> config;
  final EntityPanelController panel;

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
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  int _ticket = 0;

  EntityListConfig<T> get _c => widget.config;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant EntityListBody<T> old) {
    super.didUpdateWidget(old);
    if (old.config.id != _c.id) _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      });
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
          toolbarTrailing: _c.sorts.length < 2
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
                ),
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
