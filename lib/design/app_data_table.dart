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
// height, e.g. inside an Expanded); `shrinkWrap: true` lays out every row so it can live in a ListView. The header
// row sits outside the rows' scroll view, so it stays put while the rows scroll.
//
// Opt-in extras (D-290; a table without them looks exactly as before):
//   tableId       this device remembers the column order / hidden columns and the density under this id
//                 (SharedPreferences `app_data_table.v1.<id>`, like the export choice; never the server ui-prefs)
//   columnMenu    a "Columns" toolbar button: show / hide and move up / down; a `primary` column cannot be hidden;
//                 "Reset" restores the defaults. Hidden columns leave the phone card too. Column keys must be unique.
//   density       comfortable (the default look) / compact; the toggle shows when tableId is set or densityToggle
//   selectedRowId the open row (a detail panel): selected fill + a start-side accent bar, on the phone card too
//   onRowHover    the pointer entered a row (mouse / stylus only, never touch): prefetch the detail
//   columnResize  drag a column's edge in the header (double tap: back to its default); remembered with the layout. A
//                 `primary` column takes the room left and has no handle; widths shrink to fit when the table narrows
//   hideBelow     (column) the wide table leaves this column out under that table width, e.g. while a side panel is
//                 open; it stays in the Columns menu and on the phone card
//   maxInlineActions how many row actions sit beside the row; 0 = the row has one menu
//   compactOf     a cell's own density, so a thumbnail or a chip can follow the toggle
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
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
    this.hideBelow,
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
    this.hideBelow,
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

  /// Left out of the wide table when the table is narrower than this (null: always shown).
  final double? hideBelow;
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

enum AppTableDensity { comfortable, compact }

/// What this device remembers of one table: the column order, the hidden columns and the density. Pure: [apply]
/// merges it with the table's current columns (a column added since is put at its default place, a removed one is
/// dropped; a `primary` column is never hidden).
class AppTableLayout {
  const AppTableLayout({this.order = const [], this.hidden = const {}, this.density, this.widths = const {}});

  /// Column keys in the person's order (may miss columns added since).
  final List<String> order;
  final Set<String> hidden;

  /// Null = the table's own default.
  final AppTableDensity? density;

  /// The widths dragged by the person, by column key (the others keep their own width / flex).
  final Map<String, double> widths;

  static String prefKey(String tableId) => 'app_data_table.v1.$tableId';

  bool get isDefault => order.isEmpty && hidden.isEmpty && density == null && widths.isEmpty;

  AppTableLayout copyWith({
    List<String>? order,
    Set<String>? hidden,
    AppTableDensity? density,
    bool clearDensity = false,
    Map<String, double>? widths,
  }) =>
      AppTableLayout(
        order: order ?? this.order,
        hidden: hidden ?? this.hidden,
        density: clearDensity ? null : (density ?? this.density),
        widths: widths ?? this.widths,
      );

  /// Every column of [columns] in the person's order (hidden ones included).
  List<AppTableColumn<T>> ordered<T>(List<AppTableColumn<T>> columns) {
    if (order.isEmpty) return columns;
    final byKey = {for (final c in columns) c.key: c};
    final out = <AppTableColumn<T>>[
      for (final k in order)
        if (byKey.containsKey(k)) byKey[k]!,
    ];
    final placed = out.map((c) => c.key).toSet();
    for (var i = 0; i < columns.length; i++) {
      if (!placed.contains(columns[i].key)) out.insert(math.min(i, out.length), columns[i]);
    }
    return out;
  }

  /// The shown columns of [columns], in the person's order.
  List<AppTableColumn<T>> apply<T>(List<AppTableColumn<T>> columns) =>
      [for (final c in ordered(columns)) if (c.primary || !hidden.contains(c.key)) c];

  Map<String, dynamic> toJson() => {
        'order': order,
        'hidden': hidden.toList(),
        if (density != null) 'density': density!.name,
        if (widths.isNotEmpty) 'widths': widths,
      };

  factory AppTableLayout.fromJson(Map<String, dynamic> j) => AppTableLayout(
        order: [for (final k in (j['order'] as List? ?? const [])) '$k'],
        hidden: {for (final k in (j['hidden'] as List? ?? const [])) '$k'},
        density: AppTableDensity.values.where((d) => d.name == j['density']).firstOrNull,
        widths: {
          if (j['widths'] is Map)
            for (final e in (j['widths'] as Map).entries)
              if (e.value is num) '${e.key}': (e.value as num).toDouble(),
        },
      );
}

/// Remembered layouts already read this run, so a remounted table draws its columns in the first frame.
final Map<String, AppTableLayout> _cache = {};

/// Forgets the layouts read this run (tests: the next table reads SharedPreferences again).
@visibleForTesting
void debugClearAppTableLayouts() => _cache.clear();

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
    this.tableId,
    this.columnMenu = false,
    this.density = AppTableDensity.comfortable,
    this.densityToggle,
    this.selectedRowId,
    this.onRowHover,
    this.columnResize = false,
    this.maxInlineActions,
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

  /// The key under which this device remembers the columns and the density (null = nothing is remembered).
  final String? tableId;

  /// A "Columns" toolbar button: show / hide and reorder the columns.
  final bool columnMenu;

  /// The density until the person picks one.
  final AppTableDensity density;

  /// The comfortable / compact toggle; null = shown when [tableId] is set.
  final bool? densityToggle;

  /// The row drawn as selected / open (compared with [rowId], or the row itself without it).
  final Object? selectedRowId;

  /// Called once each time a mouse (or stylus) pointer enters a row; never on touch.
  final ValueChanged<T>? onRowHover;

  /// A drag handle at each column's edge in the header (the person's widths are remembered with the layout).
  final bool columnResize;

  /// The row actions drawn beside a wide row, the rest in a menu; null = up to 3, or 2 and the menu.
  final int? maxInlineActions;

  /// Whether the table around [context] is in compact density (a cell shrinks its thumbnail or chip).
  static bool compactOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TableDensityScope>()?.compact ?? false;

  /// The key of the row (or phone card) body whose id is [id] (tests, scroll-into-view).
  static Key rowKey(Object id) => ValueKey<(String, Object)>(('app_table_row', id));

  @override
  State<AppDataTable<T>> createState() => _AppDataTableState<T>();
}

class _AppDataTableState<T> extends State<AppDataTable<T>> {
  Set<Object> _internal = {};
  String _query = '';
  bool _loadRequested = false;

  AppTableLayout _layout = const AppTableLayout();

  /// The shown columns of this build, in the person's order.
  List<AppTableColumn<T>> _shown = const [];

  /// [_shown] without the columns this table's width leaves out ([AppTableColumn.hideBelow]).
  List<AppTableColumn<T>> _wide = const [];

  /// The widths drawn when [AppDataTable.columnResize] is on, shrunk to the table's width when they do not fit.
  Map<String, double> _fitted = const {};

  /// A column's width as last laid out (the start of a drag on a flex column).
  final Map<String, double> _measured = {};

  /// The table's own width in this build (a side panel narrows it: the toolbar tightens to stay on one row).
  double _tableWidth = double.infinity;

  static const double _minColumn = 72;
  static const double _maxColumn = 480;

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  @override
  void didUpdateWidget(covariant AppDataTable<T> old) {
    super.didUpdateWidget(old);
    // a new load-more cycle may start once the previous one ended or brought rows
    if ((old.loadingMore && !widget.loadingMore) || old.rows.length != widget.rows.length) _loadRequested = false;
    if (old.tableId != widget.tableId) _loadLayout();
  }

  // ── remembered layout ─────────────────────────────────────────────────────

  void _loadLayout() {
    final id = widget.tableId;
    if (id == null) return;
    final hit = _cache[id];
    if (hit != null) {
      _layout = hit;
      return;
    }
    _layout = const AppTableLayout();
    SharedPreferences.getInstance().then((p) {
      final raw = p.getString(AppTableLayout.prefKey(id));
      if (raw == null || !mounted || widget.tableId != id) return;
      final l = AppTableLayout.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _cache[id] = l;
      setState(() => _layout = l);
    }).catchError((Object e) {
      debugPrint('AppDataTable($id): layout not read: $e');
    });
  }

  void _setLayout(AppTableLayout l) {
    setState(() => _layout = l);
    final id = widget.tableId;
    if (id == null) return;
    _cache[id] = l;
    SharedPreferences.getInstance().then((p) {
      final key = AppTableLayout.prefKey(id);
      return l.isDefault ? p.remove(key) : p.setString(key, jsonEncode(l.toJson()));
    }).catchError((Object e) {
      debugPrint('AppDataTable($id): layout not saved: $e');
      return false;
    });
  }

  AppTableDensity get _density => _layout.density ?? widget.density;
  bool get _compact => _density == AppTableDensity.compact;
  bool get _showDensity => widget.densityToggle ?? widget.tableId != null;

  /// A row's (and the header's) minimum height: 48 comfortable, 36 compact.
  double get _rowMin => _compact ? AppSpace.xl + AppSpace.xxs : AppTouch.min;

  /// Compact rows shrink the checkboxes' and icon buttons' tap padding to the row (pointer devices).
  VisualDensity? get _vd => _compact ? VisualDensity.compact : null;
  MaterialTapTargetSize? get _tap => _compact ? MaterialTapTargetSize.shrinkWrap : null;

  bool _isCurrent(T row) => widget.selectedRowId != null && _id(row) == widget.selectedRowId;

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
      widget.onSearch != null ||
      (widget.filters?.isNotEmpty ?? false) ||
      widget.toolbarTrailing != null ||
      widget.columnMenu ||
      _showDensity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    _shown = (widget.columnMenu || widget.tableId != null) ? _layout.apply(widget.columns) : widget.columns;
    return Material(
      color: c.cardBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardAll,
        side: BorderSide(color: c.divider, width: AppBorder.hairline),
      ),
      child: _TableDensityScope(
        compact: _compact,
        child: LayoutBuilder(builder: (context, box) {
        final phone = box.maxWidth < Breakpoints.mobile;
        _tableWidth = box.maxWidth;
        _wide = [for (final x in _shown) if (x.hideBelow == null || box.maxWidth >= x.hideBelow!) x];
        _fitWidths(box.maxWidth);
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
      ),
    );
  }

  /// Fills [_fitted]: the column widths, scaled down when they leave the flex columns less than their minimum.
  void _fitWidths(double tableWidth) {
    if (!widget.columnResize) {
      _fitted = const {};
      return;
    }
    final sized = <String, double>{
      for (final x in _wide)
        if ((_layout.widths[x.key] ?? x.width) != null) x.key: _layout.widths[x.key] ?? x.width!,
    };
    final flex = _wide.length - sized.length;
    final room = tableWidth - 2 * AppSpace.xs - _actionsWidth - (widget.selectable ? AppTouch.min : 0) - flex * _minColumn;
    final sum = sized.values.fold<double>(0, (a, w) => a + w);
    final k = sum > room && sum > 0 ? math.max(room, 0) / sum : 1.0;
    _fitted = {for (final e in sized.entries) e.key: e.value * k};
  }

  double? _widthOf(AppTableColumn<T> col) => _fitted[col.key] ?? col.width;

  void _dragColumn(AppTableColumn<T> col, double dx) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final from = _layout.widths[col.key] ?? _measured[col.key] ?? col.width ?? _minColumn;
    final next = (from + (rtl ? -dx : dx)).clamp(_minColumn, _maxColumn).toDouble();
    setState(() => _layout = _layout.copyWith(widths: {..._layout.widths, col.key: next}));
  }

  void _resetColumn(AppTableColumn<T> col) {
    if (!_layout.widths.containsKey(col.key)) return;
    _setLayout(_layout.copyWith(widths: {..._layout.widths}..remove(col.key)));
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
          if (widget.onSearch != null || widget.toolbarTrailing != null || widget.columnMenu || _showDensity)
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.onSearch != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(minWidth: phone ? 0 : 240, maxWidth: phone ? double.infinity : 360),
                    child: SizedBox(
                      width: phone ? double.infinity : (_tableWidth * 0.38).clamp(240, 360).toDouble(),
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
                // a card of the page's own design has no columns to arrange
                if (_showDensity && !(phone && widget.mobileCard != null)) _densityButton(context),
                if (widget.columnMenu && !(phone && widget.mobileCard != null)) _columnsButton(context, phone || _tableWidth < 900),
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

  Widget _densityButton(BuildContext context) {
    final c = context.colors;
    final compact = _compact;
    // the icon shows the density a tap switches to
    return IconButton(
      key: const ValueKey('app_table_density'),
      tooltip: compact ? 'ds_density_comfortable'.tr : 'ds_density_compact'.tr,
      isSelected: compact,
      constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
      icon: Icon(compact ? Icons.density_medium_rounded : Icons.density_small_rounded,
          size: AppIconSize.md, color: c.textMedium),
      onPressed: () => _setLayout(_layout.copyWith(
          density: compact ? AppTableDensity.comfortable : AppTableDensity.compact)),
    );
  }

  Widget _columnsButton(BuildContext context, bool phone) {
    final c = context.colors;
    final nHidden = widget.columns.length - _shown.length;
    final hidden = countText(nHidden,
        ar1: 'عمود مخفي',
        ar2: 'عمودان مخفيان',
        arFew: '{n} أعمدة مخفية',
        arMany: '{n} عمودًا مخفيًا',
        en1: '1 hidden',
        en: '{n} hidden');
    final label = nHidden > 0 ? '${'ds_columns'.tr} · $hidden' : 'ds_columns'.tr;
    final icon = Icon(Icons.view_column_outlined, size: AppIconSize.md, color: c.textMedium);
    if (phone) {
      return IconButton(
        key: const ValueKey('app_table_columns'),
        tooltip: label,
        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
        icon: icon,
        onPressed: () => _openColumns(context),
      );
    }
    return TextButton.icon(
      key: const ValueKey('app_table_columns'),
      style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: c.textDark),
      onPressed: () => _openColumns(context),
      icon: icon,
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  void _openColumns(BuildContext context) {
    showAppSheet<void>(
      context,
      (ctx) => _ColumnsSheet<T>(
        columns: widget.columns,
        initial: _layout,
        onChanged: _setLayout,
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
                // the bar's own tint, not the surface: the theme's primary ink is 3.3:1 on it in the dark theme
                style: TextButton.styleFrom(
                    minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: c.textDark),
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

  double get _actionsWidth {
    final inline = widget.maxInlineActions;
    final slots = inline == null ? math.min(_maxActions, 3) : math.min(_maxActions, inline + 1);
    return AppTouch.min * slots;
  }

  Alignment _align(AppTableColumn<T> col) => AlignmentDirectional(
          switch (col.align) {
            AppColAlignment.start => col.numeric ? 1.0 : -1.0,
            AppColAlignment.center => 0.0,
            AppColAlignment.end => 1.0,
          },
          0)
      .resolve(Directionality.of(context));

  Widget _slot(AppTableColumn<T> col, Widget child, {bool header = false}) {
    final padded = Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs), child: child);
    final Widget body = !header || !widget.columnResize || col.primary
        ? padded
        : LayoutBuilder(builder: (context, box) {
            _measured[col.key] = box.maxWidth;
            return Stack(children: [
              padded,
              PositionedDirectional(
                end: 0,
                top: 0,
                bottom: 0,
                child: _ResizeHandle(
                  key: ValueKey('app_table_resize_${col.key}'),
                  onDrag: (dx) => _dragColumn(col, dx),
                  onEnd: () => _setLayout(_layout),
                  onReset: () => _resetColumn(col),
                ),
              ),
            ]);
          });
    final w = _widthOf(col);
    return w != null ? SizedBox(width: w, child: body) : Expanded(flex: col.flex, child: body);
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
                height: _rowMin,
                child: Checkbox(
                  tristate: true,
                  value: nSel == 0 ? false : (nSel == ids.length ? true : null),
                  semanticLabel: 'ds_select_all'.tr,
                  visualDensity: _vd,
                  materialTapTargetSize: _tap,
                  onChanged: (_) => _setSel(nSel == ids.length ? {} : {...ids}),
                ),
              ),
            for (final col in _wide)
              _slot(col, _headerCell(context, col, ar), header: true),
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
    // a long label ends in "…" (one line); an end-aligned (numeric) label ends where its figures end
    final label = Text(col.label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: _textAlign(col),
        style: AppType.label(context));
    if (!col.sortable || widget.onSort == null) {
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: _rowMin),
        child: Align(alignment: _align(col), child: label),
      );
    }
    final state = active ? (asc ? 'ds_sort_asc'.tr : 'ds_sort_desc'.tr) : 'ds_sort'.tr;
    final arrow = Icon(
      active ? (asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded) : Icons.unfold_more_rounded,
      size: AppIconSize.sm,
      color: active ? c.primary : c.textLight,
    );
    // end-aligned: the arrow goes before the label, so the label's end lines up with the column's figures
    final atEnd = _textAlign(col) == TextAlign.end;
    return Semantics(
      button: true,
      selected: active,
      label: '${col.label}, $state',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.chipAll,
        onTap: () => widget.onSort!(col.key, active ? !asc : true),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _rowMin),
          child: Align(
            alignment: _align(col),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: atEnd
                  ? [arrow, const SizedBox(width: AppSpace.xxs), Flexible(child: label)]
                  : [Flexible(child: label), const SizedBox(width: AppSpace.xxs), arrow],
            ),
          ),
        ),
      ),
    );
  }

  TextAlign _textAlign(AppTableColumn<T> col) => switch (col.align) {
        AppColAlignment.start => col.numeric ? TextAlign.end : TextAlign.start,
        AppColAlignment.center => TextAlign.center,
        AppColAlignment.end => TextAlign.end,
      };

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
      // a numbered table starts each page at its top
      key: widget.pagination == null ? null : ValueKey('app_table_page_${widget.pagination!.page}'),
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
      bodyKey: AppDataTable.rowKey(_id(row)),
      selected: selected,
      current: _isCurrent(row),
      minHeight: _rowMin,
      onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
      onHover: widget.onRowHover == null ? null : () => widget.onRowHover!(row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (widget.selectable)
            SizedBox(
              width: AppTouch.min,
              height: _rowMin,
              child: Checkbox(
                value: selected,
                semanticLabel: 'ds_select_row'.tr,
                visualDensity: _vd,
                materialTapTargetSize: _tap,
                onChanged: (_) => _toggle(row),
              ),
            ),
          for (final col in _wide)
            _slot(
              col,
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: _rowMin),
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
        // a value that wraps keeps its column's side (figures end-aligned in Arabic as in English)
        textAlign: _textAlign(col),
        overflow: TextOverflow.ellipsis,
        child: col.cell(context, row),
      );

  ButtonStyle? get _compactButton => _compact
      ? IconButton.styleFrom(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap)
      : null;

  List<Widget> _inlineActions(BuildContext context, List<AppRowAction<T>> actions) {
    final c = context.colors;
    final limit = widget.maxInlineActions;
    final shown = limit ?? (actions.length > 3 ? 2 : actions.length);
    final inline = actions.take(shown).toList();
    final rest = actions.skip(shown).toList();
    return [
      for (final a in inline)
        IconButton(
          tooltip: a.label,
          constraints: BoxConstraints(minWidth: AppTouch.min, minHeight: _rowMin),
          style: _compactButton,
          icon: Icon(a.icon, size: AppIconSize.md, color: a.danger ? c.danger : c.textMedium),
          onPressed: a.onTap,
        ),
      if (rest.isNotEmpty)
        PopupMenuButton<int>(
          tooltip: 'ds_more_actions'.tr,
          style: _compactButton,
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
    final cols = _shown.where((x) => x.showOnPhone).toList();
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
    // compact cards only tighten the vertical padding: a phone keeps 48 px touch targets
    final v = _compact ? AppSpace.xs : AppSpace.sm;
    return _RowShell(
      bodyKey: AppDataTable.rowKey(_id(row)),
      selected: selected,
      current: _isCurrent(row),
      onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
      onHover: widget.onRowHover == null ? null : () => widget.onRowHover!(row),
      onLongPress: widget.selectable
          ? () {
              HapticFeedback.selectionClick();
              _toggle(row);
            }
          : null,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: AppSpace.md, top: v, bottom: v),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.selectable)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
              child: SizedBox(
                width: AppTouch.min,
                height: AppTouch.min,
                child: Checkbox(value: selected, semanticLabel: 'ds_select_row'.tr, onChanged: (_) => _toggle(row)),
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
    final cols = phone ? _shown.where((x) => x.showOnPhone).toList() : _wide;
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
          height: _rowMin + AppSpace.xs,
          child: Row(children: [
            if (widget.selectable) const SizedBox(width: AppTouch.min),
            for (final col in cols)
              _widthOf(col) != null
                  ? SizedBox(width: _widthOf(col), child: const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpace.xs), child: AppSkeletonBox(height: 12)))
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

/// The table's density, for a cell that follows it ([AppDataTable.compactOf]).
class _TableDensityScope extends InheritedWidget {
  const _TableDensityScope({required this.compact, required super.child});

  final bool compact;

  @override
  bool updateShouldNotify(_TableDensityScope oldWidget) => oldWidget.compact != compact;
}

/// The edge of a header cell: drag to resize the column, double tap for its default width; it shows under the pointer
/// (the resize cursor) so a resting header stays calm. Pointer only, so it is kept out of the semantics tree (the
/// Columns sheet's Reset is the other way back).
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({super.key, required this.onDrag, required this.onEnd, required this.onReset});

  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;
  final VoidCallback onReset;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hot = false;

  void _set(bool v) {
    if (v != _hot) setState(() => _hot = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => _set(true),
        onExit: (_) => _set(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _set(true),
          onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
          onHorizontalDragEnd: (_) {
            _set(false);
            widget.onEnd();
          },
          onDoubleTap: widget.onReset,
          child: SizedBox(
            width: AppSpace.sm,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SizedBox(
                width: AppBorder.focus,
                height: AppSpace.md,
                child: ColoredBox(color: _hot ? c.primary : Colors.transparent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row's surface: hover (web / desktop) and selection tint, ink on tap, [minHeight] minimum (48 by default).
/// [current] = the open row: the selected fill plus a start-side accent bar (the hover tint is lighter and has no
/// bar). [onHover] fires once per mouse / stylus enter, never for touch.
class _RowShell extends StatefulWidget {
  const _RowShell({
    required this.child,
    required this.selected,
    this.current = false,
    this.minHeight = AppTouch.min,
    this.bodyKey,
    this.onTap,
    this.onLongPress,
    this.onHover,
  });
  final Widget child;
  final bool selected;
  final bool current;
  final double minHeight;

  /// Keys the row's body (not the shell: two rows with the same id must not collide as siblings).
  final Key? bodyKey;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onHover;

  @override
  State<_RowShell> createState() => _RowShellState();
}

class _RowShellState extends State<_RowShell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = widget.selected || widget.current
        ? c.primaryTint
        : (_hover && widget.onTap != null ? c.primary.withValues(alpha: 0.06) : Colors.transparent);
    Widget shell = MouseRegion(
      onEnter: (e) {
        setState(() => _hover = true);
        if (e.kind != PointerDeviceKind.touch) widget.onHover?.call();
      },
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: Material(
        color: tint,
        animationDuration: AppMotion.of(context).fast,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: ConstrainedBox(
            key: widget.bodyKey,
            constraints: BoxConstraints(minHeight: widget.minHeight),
            child: widget.child,
          ),
        ),
      ),
    );
    if (widget.current) {
      shell = Semantics(
        selected: true,
        child: Stack(children: [
          shell,
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: SizedBox(
                key: const ValueKey('app_table_current_bar'),
                width: AppSpace.xxs,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.isDark ? c.primaryLight : c.primary,
                    borderRadius: const BorderRadiusDirectional.horizontal(end: Radius.circular(AppSpace.xxs))
                        .resolve(Directionality.of(context)),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
    }
    return shell;
  }
}

/// The "Columns" sheet: a checkbox per column (a primary one is locked on), move up / down, and Reset. Every change
/// goes straight to the table through [onChanged] (the table remembers it).
class _ColumnsSheet<T> extends StatefulWidget {
  const _ColumnsSheet({required this.columns, required this.initial, required this.onChanged});
  final List<AppTableColumn<T>> columns;
  final AppTableLayout initial;
  final ValueChanged<AppTableLayout> onChanged;

  @override
  State<_ColumnsSheet<T>> createState() => _ColumnsSheetState<T>();
}

class _ColumnsSheetState<T> extends State<_ColumnsSheet<T>> {
  late AppTableLayout _l = widget.initial;

  void _set(AppTableLayout l) {
    setState(() => _l = l);
    widget.onChanged(l);
  }

  void _move(List<AppTableColumn<T>> cols, int i, int delta) {
    final keys = [for (final c in cols) c.key];
    final k = keys.removeAt(i);
    keys.insert(i + delta, k);
    // the default order again = nothing to remember
    final same = listEquals([for (final c in widget.columns) c.key], keys);
    _set(_l.copyWith(order: same ? const [] : keys));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cols = _l.ordered(widget.columns);
    final changed = _l.order.isNotEmpty || _l.hidden.isNotEmpty || _l.widths.isNotEmpty;
    return AppSheetContent(
      title: 'ds_columns'.tr,
      headerTrailing: TextButton(
        key: const ValueKey('app_table_columns_reset'),
        style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
        onPressed: changed ? () => _set(AppTableLayout(density: _l.density)) : null,
        child: Text('ds_reset'.tr),
      ),
      children: [
        Text('ds_columns_hint'.tr, style: AppType.meta(context)),
        const SizedBox(height: AppSpace.xs),
        for (var i = 0; i < cols.length; i++)
          _ColumnTile(
            key: ValueKey('app_table_col_${cols[i].key}'),
            label: cols[i].label,
            shown: cols[i].primary || !_l.hidden.contains(cols[i].key),
            locked: cols[i].primary,
            onShown: cols[i].primary
                ? null
                : (v) => _set(_l.copyWith(
                    hidden: v ? ({..._l.hidden}..remove(cols[i].key)) : {..._l.hidden, cols[i].key})),
            onUp: i > 0 ? () => _move(cols, i, -1) : null,
            onDown: i < cols.length - 1 ? () => _move(cols, i, 1) : null,
            divider: i > 0 ? c.divider : null,
          ),
      ],
    );
  }
}

class _ColumnTile extends StatelessWidget {
  const _ColumnTile({
    super.key,
    required this.label,
    required this.shown,
    required this.locked,
    required this.onShown,
    required this.onUp,
    required this.onDown,
    this.divider,
  });
  final String label;
  final bool shown;
  final bool locked;
  final ValueChanged<bool>? onShown;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final Color? divider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget arrow(IconData icon, String tip, VoidCallback? onTap, String key) => IconButton(
          key: ValueKey(key),
          tooltip: '$tip: $label',
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(icon, size: AppIconSize.md, color: onTap == null ? c.textLight : c.textMedium),
          onPressed: onTap,
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider == null ? null : Border(top: BorderSide(color: divider!, width: AppBorder.hairline)),
      ),
      child: Row(children: [
        Expanded(
          child: MergeSemantics(
            child: InkWell(
              borderRadius: AppRadius.chipAll,
              onTap: onShown == null ? null : () => onShown!(!shown),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Row(children: [
                  Checkbox(value: shown, onChanged: onShown == null ? null : (v) => onShown!(v ?? false)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                      if (locked) Text('ds_column_locked'.tr, style: AppType.meta(context)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
        arrow(Icons.arrow_upward_rounded, 'ds_move_up'.tr, onUp, 'up'),
        arrow(Icons.arrow_downward_rounded, 'ds_move_down'.tr, onDown, 'down'),
      ]),
    );
  }
}
