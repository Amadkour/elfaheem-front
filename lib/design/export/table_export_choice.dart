// lib/design/export/table_export_choice.dart — the export picker's state (format, column order, selection) and
// how a remembered choice is merged with the table's current columns. Pure, unit-tested.
library;

import 'table_export_model.dart';

/// The picker state: a format, every column id in the user's order, the selected ones.
class AppExportChoice {
  AppExportChoice(this.format, this.order, this.selected);
  AppExportFormat format;
  List<String> order;
  Set<String> selected;

  /// Exported ids in output order.
  List<String> get columns => [for (final id in order) if (selected.contains(id)) id];

  Map<String, Object?> toJson() => {'f': format.name, 'o': order, 's': columns};

  /// Defaults of [e], overlaid with a remembered [json] (unknown ids dropped, new columns at their declared place).
  static AppExportChoice of(AppTableExport e, List<AppExportFormat> formats, [Map<String, Object?>? json]) {
    final ids = [for (final c in e.columns) if (c.id != e.groupBy) c.id];
    final defFormat = formats.contains(AppExportFormat.xlsx) ? AppExportFormat.xlsx : formats.first;
    final choice = AppExportChoice(defFormat, ids, {for (final c in e.columns) if (c.visible || c.locked) c.id});
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
        for (final c in e.columns) if (c.locked || (!known.contains(c.id) && c.visible)) c.id,
      };
    }
    return choice;
  }
}

