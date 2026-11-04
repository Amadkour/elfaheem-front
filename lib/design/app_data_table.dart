// lib/design/app_data_table.dart
//
// THE data table of the design system. Presentational and CONTROLLED: the page owns the data, the sort, the search
// text, the filters and the page (so it works for server-side paging); the table draws them.
//
//   toolbar   AppSearchField + filters (chips, or a dropdown above 5 options) + [toolbarTrailing] (an export button)
//   wide      (the table's own width >= Breakpoints.mobile) a real table: header row with sort arrows, rows separated
//             by hairlines, hover highlight, row tap, a checkbox column, row actions (2 inline, the rest in a menu)
//   phone     each row is a card ([mobileCard], or the primary column as the title plus "label: value" lines for the
//             other `showOnPhone` columns); the card's ⋯ opens the actions in a bottom sheet; long-press selects.
//             A wide table is NEVER scrolled sideways on a phone.
//   states    loading = skeleton rows, error = inline block with Retry, empty = [empty] or the default block
//   selection checkbox column / card checkbox + a bulk bar ("N selected" + [bulkActions]) while anything is selected
//
// It sits on cardBg with the card radius and a hairline border: no gradient behind a table (app_gradients.dart).
// Embedding: `shrinkWrap: false` (default) fills the height it is given and scrolls its own rows (give it a bounded
// height, e.g. inside an Expanded); `shrinkWrap: true` lays out every row so it can live in a ListView.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/teacher/data_lab/data_lab_widgets.dart' as dl;

import 'app_kit.dart' show AppChoiceChip, AppDropdown, AppEmpty, AppSheetContent, AppSkeletonBox, showAppSheet;
import 'app_pagination.dart';
import 'app_responsive.dart';
import 'app_search_field.dart';
import 'app_tokens.dart';

enum AppTableState { loading, error, ready }

enum AppColAlignment { start, center, end }

/// One column. [cell] draws the value; [AppTableColumn.text] is the shortcut for plain text.
class AppTableColumn<T> {
  const AppTableColumn({
    required this.key,
    required this.label,
    required this.cell,
    this.sortable = false,
    this.width,
    this.flex = 1,
    this.align = AppColAlignment.start,
    this.numeric = false,
    this.showOnPhone = true,
    this.primary = false,
  });

  AppTableColumn.text({
    required this.key,
    required this.label,
    required String Function(T row) text,
    this.sortable = false,
    this.width,
    this.flex = 1,
    this.align = AppColAlignment.start,
    this.numeric = false,
    this.showOnPhone = true,
    this.primary = false,
  }) : cell = ((context, row) => Text(text(row), maxLines: 2, overflow: TextOverflow.ellipsis));

  /// The sort key handed to `onSort`.
  final String key;
  final String label;
  final Widget Function(BuildContext context, T row) cell;
  final bool sortable;

  /// A fixed width; null = share the rest by [flex].
  final double? width;
  final int flex;
  final AppColAlignment align;

  /// Figures: tabular digits, aligned to the end.
  final bool numeric;
  final bool showOnPhone;

  /// The title line of the phone card.
  final bool primary;
}

/// A filter of the toolbar. [value] null = "All". Up to 5 options draw as chips, more as a dropdown.
class AppTableFilter {
  const AppTableFilter({required this.label, required this.options, this.value, required this.onChanged});
  final String label;
  final List<(String value, String label)> options;
  final String? value;
  final ValueChanged<String?> onChanged;
}

/// A row action: an icon button on wide rows (the first two), the rest in a menu; a sheet entry on phones.
class AppRowAction<T> {
  const AppRowAction({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

class AppDataTable<T> extends StatefulWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.state = AppTableState.ready,
    this.errorText,
    this.onRetry,
    this.searchHint,
    this.onSearch,
    this.searchController,
    this.filters,
    this.onClearFilters,
    this.sortKey,
    this.sortAscending = true,
    this.onSort,
    this.onRowTap,
    this.rowActions,
    this.toolbarTrailing,
    this.empty,
    this.pagination,
    this.mobileCard,
    this.selectable = false,
    this.selected,
    this.rowId,
    this.onSelectionChanged,
    this.bulkActions,
    this.shrinkWrap = false,
    this.onLoadMore,
    this.hasMore = false,
    this.loadingMore = false,
  });

  final List<AppTableColumn<T>> columns;
  final List<T> rows;
  final AppTableState state;
  final String? errorText;
  final VoidCallback? onRetry;
  final String? searchHint;
  final ValueChanged<String>? onSearch;

  /// Lets the page clear the search text (e.g. in [onClearFilters]).
  final TextEditingController? searchController;
  final List<AppTableFilter>? filters;

  /// Shown on the default empty block while a search or a filter is active.
  final VoidCallback? onClearFilters;
  final String? sortKey;
  final bool sortAscending;
  final void Function(String key, bool ascending)? onSort;
  final ValueChanged<T>? onRowTap;
  final List<AppRowAction<T>> Function(T row)? rowActions;
  final Widget? toolbarTrailing;
  final Widget? empty;
  final AppPagination? pagination;
  final Widget Function(BuildContext context, T row)? mobileCard;
  final bool selectable;

  /// The selected row ids. Null = the table keeps the selection itself.
  final Set<Object>? selected;
  final Object Function(T row)? rowId;
  final ValueChanged<Set<Object>>? onSelectionChanged;
  final List<Widget> Function(Set<Object> selected)? bulkActions;
  final bool shrinkWrap;

  /// Infinite scroll (shrinkWrap: false only; a shrinkWrap: true page must use [AppPagination]): when [hasMore] and
  /// the body is scrolled within ~300 px of its end (or the rows do not fill the viewport) this is called once per
  /// cycle — again only after [loadingMore] went false, or the row count changed. While [loadingMore] a slim
  /// skeleton row ends the list.
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool loadingMore;

  @override
  State<AppDataTable<T>> createState() => _AppDataTableState<T>();
}

class _AppDataTableState<T> extends State<AppDataTable<T>> {
  Set<Object> _internal = {};
  String _query = '';
  bool _loadRequested = false;

  @override
  void didUpdateWidget(covariant AppDataTable<T> old) {
    super.didUpdateWidget(old);
    // a new load-more cycle may start once the previous one ended or brought rows
    if ((old.loadingMore && !widget.loadingMore) || old.rows.length != widget.rows.length) _loadRequested = false;
  }

  Set<Object> get _sel => widget.selected ?? _internal;
  Object _id(T r) => widget.rowId != null ? widget.rowId!(r) : (r as Object);

  void _setSel(Set<Object> s) {
    if (widget.selected == null) setState(() => _internal = s);
    widget.onSelectionChanged?.call(s);
  }

  void _toggle(T r) {
    final s = {..._sel};
    final id = _id(r);
    if (!s.remove(id)) s.add(id);
    _setSel(s);
  }

  bool get _filtersActive => (widget.filters ?? const []).any((f) => f.value != null) || _query.isNotEmpty;

  bool get _hasToolbar =>
      widget.onSearch != null || (widget.filters?.isNotEmpty ?? false) || widget.toolbarTrailing != null;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardAll,
        side: BorderSide(color: c.divider, width: AppBorder.hairline),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final phone = box.maxWidth < Breakpoints.mobile;
        final ready = widget.state == AppTableState.ready;
        final empty = ready && widget.rows.isEmpty;
        final fit = widget.shrinkWrap;
        return Column(
          mainAxisSize: fit ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_hasToolbar) _toolbar(context, phone),
            if (ready && widget.selectable && _sel.isNotEmpty) _bulkBar(context),
            if (ready && !empty && !phone) _headerRow(context),
            _fill(
              fit,
              switch (widget.state) {
                AppTableState.loading => _loading(context, phone),
                AppTableState.error => _error(context),
                AppTableState.ready => empty ? _emptyBlock(context) : _rowsList(context, phone, fit),
              },
              scrolls: !(ready && !empty),
            ),
            if (widget.pagination != null && widget.state != AppTableState.error) widget.pagination!,
          ],
        );
      }),
    );
  }

  /// In fit mode the body just takes its height; otherwise it fills the rest and scrolls (rows scroll themselves).
  Widget _fill(bool fit, Widget body, {required bool scrolls}) {
    if (fit) return body;
    return Expanded(child: scrolls ? SingleChildScrollView(child: body) : body);
  }

  // ── toolbar ───────────────────────────────────────────────────────────────

  Widget _toolbar(BuildContext context, bool phone) {
    final c = context.colors;
    final filters = widget.filters ?? const <AppTableFilter>[];
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider, width: AppBorder.hairline))),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (widget.onSearch != null || widget.toolbarTrailing != null)
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.onSearch != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(minWidth: phone ? 0 : 240, maxWidth: phone ? double.infinity : 360),
                    child: SizedBox(
                      width: phone ? double.infinity : 360,
                      child: AppSearchField(
                        hint: widget.searchHint,
                        controller: widget.searchController,
                        onChanged: (v) {
                          if (v.isEmpty != _query.isEmpty) setState(() => _query = v);
                          _query = v;
                          widget.onSearch!(v);
                        },
                      ),
                    ),
                  ),
                if (widget.toolbarTrailing != null) widget.toolbarTrailing!,
              ],
            ),
          for (final f in filters) ...[
            const SizedBox(height: AppSpace.xs),
            _filter(context, f),
          ],
        ]),
      ),
    );
  }

  Widget _filter(BuildContext context, AppTableFilter f) {
    if (f.options.length > 5) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: AppDropdown<String>(
            value: f.value ?? '__all',
            decoration: InputDecoration(labelText: f.label),
            items: [
              DropdownMenuItem(value: '__all', child: Text('${f.label}: ${'ds_all'.tr}')),
              for (final o in f.options) DropdownMenuItem(value: o.$1, child: Text(o.$2)),
            ],
            onChanged: (v) => f.onChanged(v == null || v == '__all' ? null : v),
          ),
        ),
      );
    }
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(f.label, style: AppType.label(context)),
      AppChoiceChip(label: 'ds_all'.tr, selected: f.value == null, onTap: () => f.onChanged(null)),
      for (final o in f.options)
        AppChoiceChip(label: o.$2, selected: f.value == o.$1, onTap: () => f.onChanged(f.value == o.$1 ? null : o.$1)),
    ]);
  }

  // ── bulk bar ──────────────────────────────────────────────────────────────

  Widget _bulkBar(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final n = _sel.length;
    final all = widget.rows.isNotEmpty && widget.rows.every((r) => _sel.contains(_id(r)));
    return ColoredBox(
      color: c.primaryTint,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
        child: Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: ar ? 'إلغاء التحديد' : 'Clear selection',
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textDark),
              onPressed: () => _setSel({}),
            ),
            Semantics(
              liveRegion: true,
              child: Text('$n ${'ds_selected'.tr}', style: AppType.row(context)),
            ),
            if (!all)
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                onPressed: () => _setSel({for (final r in widget.rows) _id(r)}),
                child: Text('ds_select_all'.tr),
              ),
            ...?widget.bulkActions?.call({..._sel}),
          ],
        ),
      ),
    );
  }

  // ── wide table ────────────────────────────────────────────────────────────

  int get _maxActions {
    final f = widget.rowActions;
    if (f == null) return 0;
    var m = 0;
    for (final r in widget.rows) {
      m = math.max(m, f(r).length);
    }
    return m;
  }

  double get _actionsWidth => AppTouch.min * math.min(_maxActions, 3);

  Alignment _align(AppTableColumn<T> col) => AlignmentDirectional(
          switch (col.align) {
            AppColAlignment.start => col.numeric ? 1.0 : -1.0,
            AppColAlignment.center => 0.0,
            AppColAlignment.end => 1.0,
          },
          0)
      .resolve(Directionality.of(context));

  Widget _slot(AppTableColumn<T> col, Widget child) {
    final padded = Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs), child: child);
    return col.width != null ? SizedBox(width: col.width, child: padded) : Expanded(flex: col.flex, child: padded);
  }

  Widget _headerRow(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final ids = widget.rows.map(_id).toList();
    final nSel = ids.where(_sel.contains).length;
    return Material(
      key: const ValueKey('app_table_header'),
      color: c.cardBg2,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider, width: AppBorder.hairline))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          child: Row(children: [
            if (widget.selectable)
              SizedBox(
                width: AppTouch.min,
                height: AppTouch.min,
                child: Checkbox(
                  tristate: true,
                  value: nSel == 0 ? false : (nSel == ids.length ? true : null),
                  semanticLabel: 'ds_select_all'.tr,
                  onChanged: (_) => _setSel(nSel == ids.length ? {} : {...ids}),
                ),
              ),
            for (final col in widget.columns)
              _slot(col, _headerCell(context, col, ar)),
            if (_actionsWidth > 0) SizedBox(width: _actionsWidth),
          ]),
        ),
      ),
    );
  }

  Widget _headerCell(BuildContext context, AppTableColumn<T> col, bool ar) {
    final c = context.colors;
    final active = widget.sortKey == col.key;
    final asc = widget.sortAscending;
    final label = Text(col.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context));
    if (!col.sortable || widget.onSort == null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Align(alignment: _align(col), child: label),
      );
    }
    final state = active ? (asc ? 'ds_sort_asc'.tr : 'ds_sort_desc'.tr) : 'ds_sort'.tr;
    return Semantics(
      button: true,
      selected: active,
      label: '${col.label}, $state',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.chipAll,
        onTap: () => widget.onSort!(col.key, active ? !asc : true),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Align(
            alignment: _align(col),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: label),
              const SizedBox(width: AppSpace.xxs),
              Icon(
                active ? (asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded) : Icons.unfold_more_rounded,
                size: AppIconSize.sm,
                color: active ? c.primary : c.textLight,
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _rowsList(BuildContext context, bool phone, bool fit) {
    final c = context.colors;
    final rows = widget.rows;
    Widget one(int i) => phone ? _card(context, rows[i]) : _wideRow(context, rows[i]);
    if (fit) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
          one(i),
        ],
      ]);
    }
    final footer = widget.loadingMore;
    final list = ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: rows.length + (footer ? 1 : 0),
      separatorBuilder: (_, _) => Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
      itemBuilder: (_, i) => i < rows.length ? one(i) : _loadMoreFooter(),
    );
    if (widget.onLoadMore == null) return list;
    return NotificationListener<Notification>(
      onNotification: (n) {
        if (n is ScrollNotification) {
          _maybeLoadMore(n.metrics);
        } else if (n is ScrollMetricsNotification) {
          _maybeLoadMore(n.metrics);
        }
        return false;
      },
      child: list,
    );
  }

  void _maybeLoadMore(ScrollMetrics m) {
    if (!widget.hasMore || widget.loadingMore || _loadRequested || widget.onLoadMore == null) return;
    if (m.axis != Axis.vertical) return;
    if (m.extentAfter < 300) {
      _loadRequested = true;
      // not inside the scroll / layout callback
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLoadMore!();
      });
    }
  }

  Widget _loadMoreFooter() => Semantics(
        label: 'ds_loading'.tr,
        child: const dl.DlShimmer(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: AppSkeletonBox(height: 14),
          ),
        ),
      );

  Widget _wideRow(BuildContext context, T row) {
    final selected = _sel.contains(_id(row));
    final actions = widget.rowActions?.call(row) ?? const [];
    return _RowShell(
      selected: selected,
      onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (widget.selectable)
            SizedBox(
              width: AppTouch.min,
              height: AppTouch.min,
              child: Checkbox(value: selected, onChanged: (_) => _toggle(row)),
            ),
          for (final col in widget.columns)
            _slot(
              col,
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Align(alignment: _align(col), child: _cell(context, col, row)),
              ),
            ),
          if (_actionsWidth > 0)
            SizedBox(
              width: _actionsWidth,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: _inlineActions(context, actions)),
            ),
        ]),
      ),
    );
  }

  Widget _cell(BuildContext context, AppTableColumn<T> col, T row) => DefaultTextStyle.merge(
        style: AppType.body(context).copyWith(
          color: context.colors.textDark,
          fontFeatures: col.numeric ? const [FontFeature.tabularFigures()] : null,
        ),
        overflow: TextOverflow.ellipsis,
        child: col.cell(context, row),
      );

  List<Widget> _inlineActions(BuildContext context, List<AppRowAction<T>> actions) {
    final c = context.colors;
    final inline = actions.length > 3 ? actions.take(2).toList() : actions;
    final rest = actions.length > 3 ? actions.skip(2).toList() : <AppRowAction<T>>[];
    return [
      for (final a in inline)
        IconButton(
          tooltip: a.label,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(a.icon, size: AppIconSize.md, color: a.danger ? c.danger : c.textMedium),
          onPressed: a.onTap,
        ),
      if (rest.isNotEmpty)
        PopupMenuButton<int>(
          tooltip: 'ds_more_actions'.tr,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(Icons.more_vert_rounded, size: AppIconSize.md, color: c.textMedium),
          onSelected: (i) => rest[i].onTap(),
          itemBuilder: (_) => [
            for (var i = 0; i < rest.length; i++)
              PopupMenuItem<int>(
                value: i,
                child: Row(children: [
                  Icon(rest[i].icon, size: AppIconSize.md, color: rest[i].danger ? c.danger : c.textMedium),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(
                    child: Text(rest[i].label,
                        style: AppType.body(context).copyWith(color: rest[i].danger ? c.danger : c.textDark)),
                  ),
                ]),
              ),
          ],
        ),
    ];
  }

  // ── phone cards ───────────────────────────────────────────────────────────

  Widget _card(BuildContext context, T row) {
    final c = context.colors;
    final selected = _sel.contains(_id(row));
    final actions = widget.rowActions?.call(row) ?? <AppRowAction<T>>[];
    final cols = widget.columns.where((x) => x.showOnPhone).toList();
    final title = cols.where((x) => x.primary).firstOrNull ?? cols.firstOrNull;
    final body = widget.mobileCard != null
        ? widget.mobileCard!(context, row)
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (title != null)
              DefaultTextStyle.merge(
                style: AppType.row(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                child: title.cell(context, row),
              ),
            for (final col in cols)
              if (!identical(col, title))
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  // centred on one line: the label (meta, 1.4) and the value (body, a taller Arabic line) would
                  // otherwise drift apart, the value looking like it belongs to the next label
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Expanded(
                      flex: 2,
                      child: Text(col.label, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: DefaultTextStyle.merge(style: const TextStyle(height: 1.3), child: _cell(context, col, row)),
                      ),
                    ),
                  ]),
                ),
          ]);
    return _RowShell(
      selected: selected,
      onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
      onLongPress: widget.selectable
          ? () {
              HapticFeedback.selectionClick();
              _toggle(row);
            }
          : null,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: AppSpace.md, top: AppSpace.sm, bottom: AppSpace.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.selectable)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
              child: SizedBox(
                width: AppTouch.min,
                height: AppTouch.min,
                child: Checkbox(value: selected, onChanged: (_) => _toggle(row)),
              ),
            ),
          Expanded(child: body),
          if (actions.isNotEmpty)
            IconButton(
              tooltip: 'ds_more_actions'.tr,
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              icon: Icon(Icons.more_vert_rounded, size: AppIconSize.md, color: c.textMedium),
              onPressed: () => _actionsSheet(context, actions),
            )
          else
            const SizedBox(width: AppSpace.md),
        ]),
      ),
    );
  }

  void _actionsSheet(BuildContext context, List<AppRowAction<T>> actions) {
    showAppSheet<void>(
      context,
      (ctx) => AppSheetContent(title: 'ds_more_actions'.tr, children: [
        for (final a in actions)
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              minTileHeight: AppTouch.min,
              contentPadding: EdgeInsets.zero,
              leading: Icon(a.icon, color: a.danger ? ctx.colors.danger : ctx.colors.textMedium),
              title: Text(a.label, style: AppType.row(ctx).copyWith(color: a.danger ? ctx.colors.danger : null)),
              onTap: () {
                Navigator.pop(ctx);
                a.onTap();
              },
            ),
          ),
      ]),
    );
  }

  // ── states ────────────────────────────────────────────────────────────────

  Widget _loading(BuildContext context, bool phone) {
    final c = context.colors;
    final cols = widget.columns.where((x) => phone ? x.showOnPhone : true).toList();
    Widget row(int i) {
      if (phone) {
        return Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AppSkeletonBox(width: 160, height: 14),
            const SizedBox(height: AppSpace.xs),
            const AppSkeletonBox(height: 12),
            const SizedBox(height: AppSpace.xs),
            AppSkeletonBox(width: 120 + (i % 3) * 30.0, height: 12),
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        child: SizedBox(
          height: AppTouch.min + AppSpace.xs,
          child: Row(children: [
            if (widget.selectable) const SizedBox(width: AppTouch.min),
            for (final col in cols)
              col.width != null
                  ? SizedBox(width: col.width, child: const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpace.xs), child: AppSkeletonBox(height: 12)))
                  : Expanded(
                      flex: col.flex,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                        child: AppSkeletonBox(height: 12),
                      ),
                    ),
          ]),
        ),
      );
    }

    return Semantics(
      label: 'ds_loading'.tr,
      child: dl.DlShimmer(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!phone) _headerRow(context),
          for (var i = 0; i < 6; i++) ...[
            if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
            row(i),
          ],
        ]),
      ),
    );
  }

  Widget _error(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Semantics(
        liveRegion: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, size: AppIconSize.hero, color: c.danger),
          const SizedBox(height: AppSpace.sm),
          Text('ds_error_title'.tr, textAlign: TextAlign.center, style: AppType.section(context)),
          const SizedBox(height: AppSpace.xxs),
          Text(widget.errorText ?? 'ds_error_body'.tr, textAlign: TextAlign.center, style: AppType.body(context)),
          if (widget.onRetry != null) ...[
            const SizedBox(height: AppSpace.md),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: OutlinedButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded, size: AppIconSize.md),
                label: Text('retry'.tr),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _emptyBlock(BuildContext context) {
    if (widget.empty != null) return widget.empty!;
    final active = _filtersActive;
    return AppEmpty(
      icon: active ? Icons.search_off_rounded : Icons.inbox_outlined,
      title: active ? 'ds_no_results'.tr : 'ds_no_data'.tr,
      message: active ? 'ds_no_results_hint'.tr : null,
      actionLabel: active && widget.onClearFilters != null ? 'ds_clear_filters'.tr : null,
      onAction: active ? widget.onClearFilters : null,
    );
  }
}

/// One row's surface: hover (web / desktop) and selection tint, ink on tap, 48 px minimum.
class _RowShell extends StatefulWidget {
  const _RowShell({required this.child, required this.selected, this.onTap, this.onLongPress});
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_RowShell> createState() => _RowShellState();
}

class _RowShellState extends State<_RowShell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = widget.selected
        ? c.primaryTint
        : (_hover && widget.onTap != null ? c.primary.withValues(alpha: 0.06) : Colors.transparent);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: Material(
        color: tint,
        animationDuration: AppMotion.of(context).fast,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: AppTouch.min), child: widget.child),
        ),
      ),
    );
  }
}
