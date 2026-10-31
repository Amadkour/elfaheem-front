// lib/design/export/table_export_choice.dart — the export flow's remembered state (format, column order, selection,
// labels per language, language, numerals, group-by, totals, rows, theme) and how a remembered choice is merged
// with the table's current columns. Pure, unit-tested (test/export/app_table_export_test.dart,
// test/export/export_studio_test.dart).
library;

import 'export_studio_model.dart' show ExportNumerals;
import 'table_export_model.dart';

/// The flow state of one table: a format, every column id in the user's order, the selected ones, and the Export
/// Studio's choices. Remembered per [AppTableExport.id] (SharedPreferences, `app_table_export.v1.<id>`).
class AppExportChoice {
  AppExportChoice(
    this.format,
    this.order,
    this.selected, {
    Map<String, Map<String, String>>? labels,
    this.lang = 'ar',
    Map<String, String>? numerals,
    this.groupBy,
    this.totals = true,
    this.rows = 'all',
    this.theme = 'standard',
  })  : labels = labels ?? {},
        numerals = numerals ?? {};

  AppExportFormat format;
  List<String> order;
  Set<String> selected;

  /// Column id → the person's own header per language (`{'ar': …, 'en': …}`); only renamed ones.
  final Map<String, Map<String, String>> labels;

  /// ar | en | both (two files, each with its own design and labels).
  String lang;

  /// Per language: western | arabic (English is always Western).
  final Map<String, String> numerals;

  /// The group-by column: null = the table's own, '' = no grouping, else a column id.
  String? groupBy;

  /// The totals row (and group subtotals) when a column aggregates.
  bool totals;

  /// all | selected (only when the page passed [AppTableExport.selectedRows]).
  String rows;

  /// The starter theme of a PDF / Word design: standard | clean | formal | colorful.
  String theme;

  /// Exported ids in output order.
  List<String> get columns => [for (final id in order) if (selected.contains(id)) id];

  List<String> get languages => lang == 'both' ? const ['ar', 'en'] : [lang];

  ExportNumerals numeralsFor(String l) => l == 'ar' ? ExportNumerals.parse(numerals['ar']) : ExportNumerals.western;

  /// The header of [c] in [l]: the person's label, else the column's own for that language.
  String labelOf(AppExportColumn c, String l) {
    final v = labels[c.id]?[l];
    return v == null || v.trim().isEmpty ? c.labelIn(l) : v;
  }

  /// Renames [id] in [l]; an empty label (or the column's own) goes back to the default.
  void rename(AppExportColumn c, String l, String label) {
    final v = label.trim();
    final m = labels.putIfAbsent(c.id, () => {});
    if (v.isEmpty || v == c.labelIn(l)) {
      m.remove(l);
    } else {
      m[l] = v;
    }
    if (m.isEmpty) labels.remove(c.id);
  }

  bool renamed(String id) => labels[id]?.isNotEmpty ?? false;

  /// Moves the column at [from] to [to] (ReorderableListView indexes: [to] is the index before removal).
  void move(int from, int to) {
    if (from < 0 || from >= order.length) return;
    final id = order.removeAt(from);
    final at = (to > from ? to - 1 : to).clamp(0, order.length);
    order.insert(at, id);
  }

  /// Ticks every column ([on]) or only the locked ones.
  void setAll(AppTableExport e, bool on) {
    selected = {
      for (final id in order)
        if (on || (e.column(id)?.locked ?? false)) id,
    };
  }

  /// The effective group column for [e].
  String? groupByFor(AppTableExport e) {
    final g = groupBy;
    if (g == null) return e.groupBy;
    if (g.isEmpty || e.column(g) == null) return null;
    return g;
  }

  Map<String, Object?> toJson() => {
        'f': format.name,
        'o': order,
        's': columns,
        if (labels.isNotEmpty) 'l': labels,
        'g': lang,
        if (numerals.isNotEmpty) 'n': numerals,
        'gb': ?groupBy,
        't': totals,
        'r': rows,
        'th': theme,
      };

  /// Defaults of [e], overlaid with a remembered [json] (unknown ids dropped, new columns at their declared place).
  static AppExportChoice of(AppTableExport e, List<AppExportFormat> formats, [Map<String, Object?>? json]) {
    final ids = [for (final c in e.columns) c.id];
    final defFormat = formats.contains(AppExportFormat.xlsx) ? AppExportFormat.xlsx : formats.first;
    final choice = AppExportChoice(
      defFormat,
      ids,
      {for (final c in e.columns) if ((c.visible || c.locked) && c.id != e.groupBy) c.id},
      lang: e.rtl ? 'ar' : 'en',
      totals: e.showTotals,
    );
    if (json == null) return choice;
    final f = AppExportFormat.parse(json['f'] as String?);
    if (f != null && formats.contains(f)) choice.format = f;
    final savedOrder = [for (final x in (json['o'] as List? ?? const [])) if (ids.contains('$x')) '$x'];
    final known = savedOrder.toSet();
    if (savedOrder.isNotEmpty) {
      final order = [...savedOrder];
      for (var i = 0; i < ids.length; i++) {
        if (known.contains(ids[i])) continue;
        // a column added since: after its declared predecessor
        final prev = i == 0 ? -1 : order.indexOf(ids[i - 1]);
        order.insert(prev + 1, ids[i]);
      }
      choice.order = order;
    }
    final saved = json['s'] as List?;
    if (saved != null && e.allowColumnSelection) {
      choice.selected = {
        for (final x in saved) if (ids.contains('$x')) '$x',
        for (final c in e.columns) if (c.locked || (!known.contains(c.id) && c.visible && c.id != e.groupBy)) c.id,
      };
    }
    final l = json['l'];
    if (l is Map) {
      for (final entry in l.entries) {
        if (!ids.contains('${entry.key}') || entry.value is! Map) continue;
        final m = <String, String>{
          for (final x in (entry.value as Map).entries)
            if ((x.key == 'ar' || x.key == 'en') && '${x.value}'.trim().isNotEmpty) '${x.key}': '${x.value}'.trim(),
        };
        if (m.isNotEmpty) choice.labels['${entry.key}'] = m;
      }
    }
    final g = json['g'];
    if (g == 'ar' || g == 'en' || g == 'both') choice.lang = '$g';
    final n = json['n'];
    if (n is Map) {
      for (final x in n.entries) {
        choice.numerals['${x.key}'] = ExportNumerals.parse(x.value).name;
      }
    }
    final gb = json['gb'];
    if (gb is String && (gb.isEmpty || ids.contains(gb))) choice.groupBy = gb;
    if (json['t'] is bool) choice.totals = json['t'] as bool;
    if (json['r'] == 'selected' && (e.selectedRows?.isNotEmpty ?? false)) choice.rows = 'selected';
    final th = json['th'];
    if (const ['standard', 'clean', 'formal', 'colorful'].contains(th)) choice.theme = '$th';
    return choice;
  }
}
