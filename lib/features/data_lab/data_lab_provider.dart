// lib/features/data_lab/data_lab_provider.dart
// State of the teacher's Data Lab page for ONE course (create it per screen).
//
// Formula columns are calculated by the SERVER (services/data_lab_service.py), exactly like weighted columns, so the
// teacher, the students, the exports and the certificates all see the same numbers, and sorting / class averages
// cover every student. The app only evaluates a formula locally for the live "example" line in the column editor.
//
// Every change shows at once (optimistic) and is undone when the server refuses it, with the server's message.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/features/data_lab/data_lab_api.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_formula.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
import 'package:flutter_education_app/core/api_error_text.dart';

/// How numbers are drawn in the sheet.
enum DlView { value, bar, both }

DlView? dlParseView(String? s) => switch (s) {
  'value' => DlView.value,
  'bar' => DlView.bar,
  'both' => DlView.both,
  _ => null,
};

class DataLabProvider extends ChangeNotifier {
  DataLabProvider(this.courseId, {DataLabApi? api}) : _api = api ?? DataLabApi() {
    _restoreLayout();
  }

  final int courseId;
  final DataLabApi _api;

  static const pageSize = 40;

  DlGrid? _grid;
  List<DlRow> _rows = [];
  bool _loading = true, _loadingMore = false;
  String? _error;
  String _search = '';
  String? _sort;
  bool _desc = true;
  int _gen = 0;
  Timer? _debounce, _refresh;
  final Set<int> _selected = {};
  final Map<String, double> _widths = {};

  /// Default way numbers are drawn — plain numbers, calm and easy to read.
  DlView _view = DlView.value;

  /// Columns that were given their own way of drawing (Numbers / Progress / Both). Saved on the server per column.
  final Map<String, DlView> _colView = {};

  Map<String, DlColumn> _byKey = {};

  static const double minColWidth = 64, maxColWidth = 420, defaultColWidth = 126;

  // ── student details that can be pinned like columns ──────────────────────
  static const idName = '__name', idIdentifier = '__identifier', idEmail = '__email', idPhone = '__phone';
  static const identityKeys = [idName, idIdentifier, idEmail, idPhone];
  static const _identityWidth = {idName: 172.0, idIdentifier: 120.0, idEmail: 190.0, idPhone: 132.0};

  static bool isIdentity(String key) => identityKeys.contains(key);

  /// Pinned (frozen) columns on the start side, in order. Student details and/or data columns.
  List<String> _frozen = [idName];

  /// The pinned columns that still exist and are shown (never empty: falls back to the name).
  List<String> get frozenKeys {
    final shown = {for (final c in columns) if (!c.isHidden) c.key};
    final out = _frozen.where((k) => isIdentity(k) || shown.contains(k)).toList();
    return out.isEmpty ? const [idName] : out;
  }

  bool isFrozen(String key) => frozenKeys.contains(key);

  /// Pins / unpins a column. The last pinned column cannot be unpinned (the sheet needs one).
  /// Returns false when nothing changed.
  bool toggleFrozen(String key) {
    final cur = List<String>.of(frozenKeys);
    if (cur.contains(key)) {
      if (cur.length == 1) return false;
      cur.remove(key);
    } else {
      cur.add(key);
    }
    _frozen = cur;
    notifyListeners();
    _saveLayoutSoon();
    return true;
  }

  /// Data columns that scroll (everything shown that is not pinned).
  List<DlColumn> get scrollColumns {
    final f = frozenKeys.toSet();
    return shownColumns.where((c) => !f.contains(c.key)).toList();
  }

  /// Label of a pinned key (student detail or data column).
  String frozenLabel(String key, String Function(String) tr) => switch (key) {
    idName => tr('dl_student'),
    idIdentifier => tr('dl_t_identifier'),
    idEmail => tr('dl_t_email'),
    idPhone => tr('dl_t_phone'),
    _ => _byKey[key]?.label ?? key,
  };

  Timer? _layoutSave;

  String get _layoutKey => 'dl_layout_v1_$courseId';

  /// Pins, widths and the default drawing are remembered per course on this device.
  Future<void> _restoreLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_layoutKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final f = (m['frozen'] as List?)?.map((e) => '$e').toList();
      if (f != null && f.isNotEmpty) _frozen = f;
      (m['widths'] as Map?)?.forEach((k, v) {
        if (v is num) _widths['$k'] = v.toDouble().clamp(minColWidth, maxColWidth).toDouble();
      });
      _view = dlParseView(m['view'] as String?) ?? _view;
      final ap = m['avg_place'];
      if (ap == 'top' || ap == 'header' || ap == 'off') avgPlace = ap as String;
      if (m['avg_highlight'] is bool) avgHighlight = m['avg_highlight'] as bool;
      sheetFont = dlStyleFonts.contains(m['font']) ? m['font'] as String? : null;
      sheetSize = (dlNum(m['size']) ?? 1.0).clamp(0.85, 1.25).toDouble();
      final al = m['align'];
      if (al == 'start' || al == 'center' || al == 'end') sheetAlign = al as String;
      notifyListeners();
    } catch (_) {
      // a broken saved layout is simply ignored
    }
  }

  void _saveLayoutSoon() {
    _layoutSave?.cancel();
    _layoutSave = Timer(const Duration(milliseconds: 600), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            _layoutKey,
            jsonEncode({
              'frozen': _frozen,
              'widths': _widths,
              'view': _view.name,
              'avg_place': avgPlace,
              'avg_highlight': avgHighlight,
              'font': sheetFont,
              'size': sheetSize,
              'align': sheetAlign,
            }));
      } catch (_) {}
    });
  }

  // ── how the sheet reads (this device) ─────────────────────────────────────

  /// Where the class averages are shown: 'top' (a band ABOVE the titles) · 'header' (under the titles) · 'off'.
  String avgPlace = 'top';

  /// The averages band is tinted and its numbers are drawn as pills — impossible to mistake for a student.
  bool avgHighlight = true;

  /// Default font / size / alignment of the values (a column's own style wins).
  String? sheetFont;
  double sheetSize = 1.0;
  String sheetAlign = 'center';

  void setSheetLook({String? avgPlace, bool? avgHighlight, String? font, bool clearFont = false, double? size, String? align}) {
    if (avgPlace != null) this.avgPlace = avgPlace;
    if (avgHighlight != null) this.avgHighlight = avgHighlight;
    if (clearFont) {
      sheetFont = null;
    } else if (font != null) {
      sheetFont = font;
    }
    if (size != null) sheetSize = size;
    if (align != null) sheetAlign = align;
    notifyListeners();
    _saveLayoutSoon();
  }

  // ── column style (shared: saved on the server) ────────────────────────────

  /// The current version of a column (after optimistic edits).
  DlColumn? columnOf(String key) {
    for (final c in columns) {
      if (c.key == key) return c;
    }
    return null;
  }

  /// Colour, font, alignment, rules — shows at once, saved on the server, undone if refused.
  Future<String?> setColumnStyle(DlColumn col, DlColumnStyle style) async {
    final list = _grid?.columns;
    final i = list?.indexWhere((c) => c.key == col.key) ?? -1;
    if (list == null || i < 0) return null;
    final before = list[i];
    list[i] = before.copyWith(style: style);
    _byKey[col.key] = list[i];
    notifyListeners();
    try {
      await _api.patchColumn(courseId, col.key, {'style': style.toJson()});
      return null;
    } catch (e) {
      list[i] = before;
      _byKey[col.key] = before;
      notifyListeners();
      return _msg(e);
    }
  }

  /// Highlights one cell by hand (null removes the highlight).
  Future<String?> setCellColor(DlColumn col, DlRow row, String? color) {
    final cur = columnOf(col.key) ?? col;
    final cells = Map<int, String>.of(cur.style.cells);
    if (color == null) {
      cells.remove(row.rowId);
    } else {
      cells[row.rowId] = color;
    }
    return setColumnStyle(cur, cur.style.copyWith(cells: cells));
  }

  /// True when [r] matches this cell. Numbers are compared as numbers, anything else as text (letter case ignored).
  static bool ruleMatches(DlRule r, DlColumn col, DlRow row) {
    final v = row.values[col.key];
    final empty = v == null || (v is String && v.trim().isEmpty);
    switch (r.type) {
      case 'empty':
        return empty;
      case 'filled':
        return !empty;
      case 'formula':
        final e = r.expr?.trim() ?? '';
        if (e.isEmpty) return false;
        try {
          final res = DlFormula.compile(e).eval((k) {
            final x = k == '__self' ? v : row.values[k];
            return x is num ? x.toDouble() : x;
          });
          if (res is String) return res.trim().isNotEmpty;
          return res is double && res != 0;
        } catch (_) {
          return false;
        }
    }
    if (empty) return false;
    final ta = (r.a ?? '').trim();
    if (r.op == 'contains') return ta.isNotEmpty && '$v'.toLowerCase().contains(ta.toLowerCase());
    final n = dlNum(v), a = dlNum(ta.replaceAll(',', '.')), b = dlNum((r.b ?? '').trim().replaceAll(',', '.'));
    if (n != null && a != null) {
      switch (r.op) {
        case '>':
          return n > a;
        case '>=':
          return n >= a;
        case '<':
          return n < a;
        case '<=':
          return n <= a;
        case '=':
          return (n - a).abs() < 1e-9;
        case '<>':
          return (n - a).abs() >= 1e-9;
        case 'between':
          if (b == null) return false;
          final lo = a < b ? a : b, hi = a < b ? b : a;
          return n >= lo && n <= hi;
      }
      return false;
    }
    final sv = '$v'.trim().toLowerCase(), sa = ta.toLowerCase();
    if (r.op == '=') return sv == sa;
    if (r.op == '<>') return sv != sa;
    return false;
  }

  /// How a cell is coloured: a hand highlight wins, then the first matching rule, then the colour scale.
  /// [scale] is 0–100 (of the full mark) when the colour scale applies.
  ({String? bg, String? fg, bool bold, double? scale}) lookOf(DlRow row, DlColumn col) {
    final st = col.style;
    final manual = st.cells[row.rowId];
    if (manual != null) return (bg: manual, fg: null, bold: st.bold, scale: null);
    for (final r in st.rules) {
      if (ruleMatches(r, col, row)) return (bg: r.bg, fg: r.fg, bold: r.bold || st.bold, scale: null);
    }
    if (st.scale && col.isNumber) {
      final n = dlNum(row.values[col.key]);
      final mx = col.maxValue == 0 ? 100.0 : col.maxValue;
      if (n != null) return (bg: null, fg: null, bold: st.bold, scale: (n / mx * 100).clamp(0, 100).toDouble());
    }
    return (bg: null, fg: null, bold: st.bold, scale: null);
  }

  /// Puts the default widths back (all columns, pinned ones included).
  void resetWidths() {
    _widths.clear();
    notifyListeners();
    _saveLayoutSoon();
  }

  DlView get view => _view;
  double widthOf(String key) => _widths[key] ?? _identityWidth[key] ?? defaultColWidth;
  int get hiddenCount => columns.where((c) => c.isHidden).length;

  /// The way this column is drawn: its own choice, else the sheet's default.
  DlView viewOf(DlColumn col) => _colView[col.key] ?? _view;

  /// Applies one way of drawing to EVERY column (forgets the individual choices, also on the server,
  /// so they do not come back with the next reload).
  void setView(DlView v) {
    if (v == _view && _colView.isEmpty) return;
    _view = v;
    _saveLayoutSoon();
    final saved = columns.where((c) => c.display != null && c.display!.isNotEmpty).map((c) => c.key).toList();
    _colView.clear();
    _replaceColumns((c) => c.display == null ? c : DlColumn.fromJson({..._columnJson(c), 'display': null}));
    notifyListeners();
    for (final k in saved) {
      _api.patchColumn(courseId, k, {'display': ''}).ignore();
    }
  }

  /// Rebuilds the column list in place (the grid's list is shared with the sheets that are open).
  void _replaceColumns(DlColumn Function(DlColumn) f) {
    final list = _grid?.columns;
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      list[i] = f(list[i]);
    }
  }

  Map<String, dynamic> _columnJson(DlColumn c) => {
    'id': c.id,
    'key': c.key,
    'label': c.label,
    'kind': c.kind,
    'data_type': c.dataType,
    'source': c.source,
    'formula': {'inputs': c.inputs, 'missing': c.missing, 'expr': ?c.expr, if (c.isCalculated) 'max': c.maxValue},
    'options': c.options,
    'max_value': c.maxValue,
    'visible_to_students': c.visibleToStudents,
    'is_hidden': c.isHidden,
    'is_locked': c.isLocked,
    'position': c.position,
    'display': c.display,
    'style': c.style.toJson(),
  };

  /// Gives one column its own way of drawing. It shows at once and is saved on the server in the background.
  Future<void> setColumnView(DlColumn col, DlView v) async {
    _colView[col.key] = v;
    _replaceColumns((c) => c.key == col.key ? c.copyWith(display: v.name) : c);
    notifyListeners();
    try {
      await _api.patchColumn(courseId, col.key, {'display': v.name});
    } catch (_) {
      // Not saved (offline / older server): the choice still applies until the screen is closed.
    }
  }

  void setWidth(String key, double w) {
    _widths[key] = w.clamp(minColWidth, maxColWidth).toDouble();
    _saveLayoutSoon();
    notifyListeners();
  }

  DlGrid? get grid => _grid;
  List<DlRow> get rows => _rows;
  List<DlColumn> get columns => _grid?.columns ?? const [];
  List<DlColumn> get shownColumns => columns.where((c) => !c.isHidden).toList();
  DlConfig get config => _grid?.config ?? const DlConfig();
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  String get search => _search;
  String? get sort => _sort;
  bool get desc => _desc;
  int get total => _grid?.total ?? 0;
  bool get hasMore => _rows.length < total;
  Set<int> get selected => _selected;

  DlStat? stat(String key) => _grid?.summary[key];

  /// Sort key of the student-name column.
  static const nameSort = idName;

  /// Columns the teacher locked (approved results).
  int get lockedCount => columns.where((c) => c.isLocked).length;

  String _msg(Object e) => apiErrorText(ApiException.from(e));

  // ── values (all calculated by the server) ───────────────────────────────

  /// What the sheet shows in a cell.
  dynamic cellValue(DlRow row, DlColumn col) => row.values[col.key];

  /// Class average of a column, over the whole class.
  double? avgOf(DlColumn col) => stat(col.key)?.avg;

  /// Live "example" in the column editor: a formula applied to one loaded row, like the server will do it.
  /// Number, text or null — exactly what the server will store.
  Object? evalFormula(DlFormula f, DlRow row, String missing) => f.eval((k) {
    final raw = row.values[k];
    if (raw is String) return raw.trim().isNotEmpty ? raw : (missing != 'skip' ? 0.0 : null);
    final x = dlNum(raw);
    return (x == null && missing != 'skip') ? 0.0 : x;
  });

  /// True when [refs] would make column [selfKey] depend on itself (directly or through other formulas).
  /// A quick check for the editor — the server checks again.
  bool formulaWouldCycle(String selfKey, Set<String> refs) {
    final seen = <String>{};
    bool walk(Set<String> keys) {
      for (final k in keys) {
        if (k == selfKey) return true;
        if (!seen.add(k)) continue;
        final c = _byKey[k];
        if (c != null && c.hasExpr) {
          try {
            if (walk(DlFormula.compile(c.expr!).refs)) return true;
          } catch (_) {}
        }
      }
      return false;
    }

    return walk(refs);
  }

  // ── loading ─────────────────────────────────────────────────────────────

  /// [keep] reloads as many rows as are already on screen (so an edit never throws the teacher back to the top).
  Future<void> load({bool silent = false, bool keep = false}) async {
    final gen = ++_gen;
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final limit = keep ? math.min(math.max(pageSize, _rows.length), 200) : pageSize;
      final g = await _api.grid(courseId, search: _search, sort: _sort, desc: _desc, limit: limit, lang: AppConfig.lang);
      if (gen != _gen) return;
      _grid = g;
      _rows = List.of(g.rows);
      _byKey = {for (final c in g.columns) c.key: c};
      for (final c in g.columns) {
        final v = dlParseView(c.display);
        if (v != null) _colView.putIfAbsent(c.key, () => v);
      }
      _error = null;
    } catch (e) {
      if (gen != _gen) return;
      _error = _msg(e);
    } finally {
      if (gen == _gen) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || _loading || !hasMore) return;
    final gen = _gen;
    _loadingMore = true;
    notifyListeners();
    try {
      final g = await _api.grid(courseId,
          search: _search, sort: _sort, desc: _desc, skip: _rows.length, limit: pageSize, lang: AppConfig.lang);
      if (gen != _gen) return;
      final seen = _rows.map((r) => r.rowId).toSet();
      _rows = [..._rows, ...g.rows.where((r) => seen.add(r.rowId))];
    } catch (_) {
      // keep what we have; the user can scroll again
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// The search waits until the teacher stops typing, so one request is sent instead of one per letter.
  void setSearch(String v) {
    if (v == _search) return;
    _search = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => load(silent: true));
  }

  /// Tap on a column title: first tap = high→low (names: A→Z), second = the other way, third = off.
  void toggleSort(String key) {
    if (_sort != key) {
      _sort = key;
      _desc = !isIdentity(key); // names / IDs: A→Z first; marks: high→low first
    } else if (_desc == !isIdentity(key)) {
      _desc = !_desc;
    } else {
      _sort = null;
    }
    load(silent: true, keep: true);
  }

  // ── selection ───────────────────────────────────────────────────────────
  void toggleSelect(int rowId) {
    _selected.contains(rowId) ? _selected.remove(rowId) : _selected.add(rowId);
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    notifyListeners();
  }

  /// Selects every loaded student (temporary / waiting lines are never selected: they have no account).
  void selectAllLoaded() {
    _selected.addAll(_rows.where((r) => r.studentId != null).map((r) => r.rowId));
    notifyListeners();
  }

  /// Class averages / stats move with every edit; several quick edits cause ONE reload.
  void _refreshSoon() {
    _refresh?.cancel();
    _refresh = Timer(const Duration(milliseconds: 900), () => load(silent: true, keep: true));
  }

  // ── cells ───────────────────────────────────────────────────────────────
  /// The new value shows at once; the server answers with the recalculated line (formulas included) and the
  /// value is undone if the server refuses. Returns an error message, or null when saved.
  Future<String?> saveCell(DlRow row, DlColumn col, String value) async {
    if (col.isLocked) return dlLockedMessage(col);
    final v = value.trim();
    final oldValues = row.values, oldOver = row.overridden;
    final parsed = col.isNumber ? double.tryParse(v.replaceAll(',', '.')) : v;
    if (v.isNotEmpty && parsed != null) {
      row.values = {...row.values, col.key: parsed};
      if (!col.isCustom) row.overridden = {...row.overridden, col.key};
      notifyListeners();
    }
    try {
      final res = await _api.putCell(courseId, row.rowId, col.key, v.isEmpty ? null : v);
      row.values = dlMap(res['values']);
      row.overridden = (res['overridden'] as List?)?.map((e) => '$e').toSet() ?? <String>{};
      notifyListeners();
      _refreshSoon();
      return null;
    } catch (e) {
      row.values = oldValues;
      row.overridden = oldOver;
      notifyListeners();
      return _msg(e);
    }
  }

  Future<String?> deleteRow(DlRow row) async {
    try {
      await _api.deleteRow(courseId, row.rowId);
      _rows.removeWhere((r) => r.rowId == row.rowId);
      notifyListeners();
      load(silent: true, keep: true);
      return null;
    } catch (e) {
      return _msg(e);
    }
  }

  // ── columns ─────────────────────────────────────────────────────────────
  /// Show / hide a column in the table and / or for the students — applied at once, undone if the server refuses.
  Future<String?> setColumnFlags(DlColumn col, {bool? hidden, bool? students, bool? locked}) async {
    final list = _grid?.columns;
    final i = list?.indexWhere((c) => c.key == col.key) ?? -1;
    if (list == null || i < 0) return null;
    final before = list[i];
    list[i] = before.copyWith(isHidden: hidden, visibleToStudents: students, isLocked: locked);
    notifyListeners();
    try {
      await _api.patchColumn(courseId, col.key, {
        'is_hidden': ?hidden,
        'visible_to_students': ?students,
        'is_locked': ?locked,
      });
      return null;
    } catch (e) {
      list[i] = before;
      notifyListeners();
      return _msg(e);
    }
  }

  /// Drag a column title onto another one in the sheet: it takes that place (after it when moving right).
  Future<String?> moveColumn(String key, String targetKey) async {
    final list = _grid?.columns;
    if (list == null || key == targetKey) return null;
    final from = list.indexWhere((c) => c.key == key);
    if (from < 0 || list.indexWhere((c) => c.key == targetKey) < 0) return null;
    final before = List<DlColumn>.of(list);
    final moved = list.removeAt(from);
    final t = list.indexWhere((c) => c.key == targetKey);
    list.insert(from <= t ? t + 1 : t, moved);
    notifyListeners();
    return _saveOrder(before);
  }

  /// Drag & drop in the columns list: moves at once, saved on the server, undone if it fails.
  Future<String?> reorderColumns(int oldIndex, int newIndex) async {
    final list = _grid?.columns;
    if (list == null || oldIndex < 0 || oldIndex >= list.length) return null;
    final before = List<DlColumn>.of(list);
    if (newIndex > oldIndex) newIndex -= 1; // ReorderableListView convention
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), moved);
    notifyListeners();
    return _saveOrder(before);
  }

  Future<String?> _saveOrder(List<DlColumn> before) async {
    final list = _grid!.columns;
    try {
      await _api.reorderColumns(courseId, list.map((c) => c.key).toList());
      return null;
    } catch (e) {
      list
        ..clear()
        ..addAll(before);
      notifyListeners();
      return _msg(e);
    }
  }

  Future<String?> createColumn(Map<String, dynamic> body) async {
    try {
      await _api.createColumn(courseId, body);
      await load(silent: true, keep: true);
      return null;
    } catch (e) {
      return _msg(e);
    }
  }

  Future<String?> patchColumn(String key, Map<String, dynamic> body) async {
    try {
      await _api.patchColumn(courseId, key, body);
      await load(silent: true, keep: true);
      return null;
    } catch (e) {
      return _msg(e);
    }
  }

  Future<String?> deleteColumn(String key) async {
    try {
      await _api.deleteColumn(courseId, key);
      _colView.remove(key);
      await load(silent: true, keep: true);
      return null;
    } catch (e) {
      return _msg(e);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _refresh?.cancel();
    _layoutSave?.cancel();
    super.dispose();
  }
}

/// The message shown when a locked column is tapped (the server says the same in English).
String dlLockedMessage(DlColumn col) {
  final t = 'dl_locked_msg'.tr;
  return (t.isEmpty || t == 'dl_locked_msg') ? '"${col.label}" is locked — unlock it to change values' : '${col.label}: $t';
}
