// lib/features/shared/data_lab/data_lab_provider.dart
// State of the teacher's Data Lab page for ONE course (create it per screen).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

import 'data_lab_api.dart';
import 'data_lab_models.dart';

/// How numbers are drawn in the sheet.
enum DlView { value, bar, both }

class DataLabProvider extends ChangeNotifier {
  DataLabProvider(this.courseId, {DataLabApi? api}) : _api = api ?? DataLabApi();

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
  Timer? _debounce;
  final Set<int> _selected = {};
  final Map<String, double> _widths = {};
  DlView _view = DlView.both;

  static const double minColWidth = 92, maxColWidth = 340, defaultColWidth = 126;

  DlView get view => _view;
  double widthOf(String key) => _widths[key] ?? defaultColWidth;
  int get hiddenCount => columns.where((c) => c.isHidden).length;

  void setView(DlView v) {
    if (v == _view) return;
    _view = v;
    notifyListeners();
  }

  void setWidth(String key, double w) {
    _widths[key] = w.clamp(minColWidth, maxColWidth).toDouble();
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

  String _msg(Object e) => e is ApiException ? e.message : '$e';

  Future<void> load({bool silent = false}) async {
    final gen = ++_gen;
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final g = await _api.grid(courseId, search: _search, sort: _sort, desc: _desc, limit: pageSize, lang: AppConfig.lang);
      if (gen != _gen) return;
      _grid = g;
      _rows = List.of(g.rows);
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

  void setSearch(String v) {
    if (v == _search) return;
    _search = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => load(silent: true));
  }

  /// Tap on a column title: first tap = high→low, second = low→high, third = off.
  void toggleSort(String key) {
    if (_sort != key) {
      _sort = key;
      _desc = true;
    } else if (_desc) {
      _desc = false;
    } else {
      _sort = null;
    }
    load(silent: true);
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

  // ── cells ───────────────────────────────────────────────────────────────
  /// Returns an error message, or null when saved.
  Future<String?> saveCell(DlRow row, DlColumn col, String value) async {
    try {
      final res = await _api.putCell(courseId, row.rowId, col.key, value.trim().isEmpty ? null : value.trim());
      row.values = dlMap(res['values']);
      row.overridden = (res['overridden'] as List?)?.map((e) => '$e').toSet() ?? <String>{};
      notifyListeners();
      load(silent: true); // class averages move with every edit
      return null;
    } catch (e) {
      return _msg(e);
    }
  }

  Future<String?> deleteRow(DlRow row) async {
    try {
      await _api.deleteRow(courseId, row.rowId);
      _rows.removeWhere((r) => r.rowId == row.rowId);
      notifyListeners();
      load(silent: true);
      return null;
    } catch (e) {
      return _msg(e);
    }
  }

  // ── columns ─────────────────────────────────────────────────────────────
  /// Show / hide a column in the table and / or for the students — applied at once, undone if the server refuses.
  Future<String?> setColumnFlags(DlColumn col, {bool? hidden, bool? students}) async {
    final list = _grid?.columns;
    final i = list?.indexWhere((c) => c.key == col.key) ?? -1;
    if (list == null || i < 0) return null;
    final before = list[i];
    list[i] = before.copyWith(isHidden: hidden, visibleToStudents: students);
    notifyListeners();
    try {
      await _api.patchColumn(courseId, col.key, {
        'is_hidden': ?hidden,
        'visible_to_students': ?students,
      });
      return null;
    } catch (e) {
      list[i] = before;
      notifyListeners();
      return _msg(e);
    }
  }

  Future<String?> createColumn(Map<String, dynamic> body) async {
    try {
      await _api.createColumn(courseId, body);
      await load(silent: true);
      return null;
    } catch (e) {
      return _msg(e);
    }
  }

  Future<String?> patchColumn(String key, Map<String, dynamic> body) async {
    try {
      await _api.patchColumn(courseId, key, body);
      await load(silent: true);
      return null;
    } catch (e) {
      return _msg(e);
    }
  }

  Future<String?> deleteColumn(String key) async {
    try {
      await _api.deleteColumn(courseId, key);
      await load(silent: true);
      return null;
    } catch (e) {
      return _msg(e);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
