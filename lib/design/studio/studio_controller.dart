// lib/design/studio/studio_controller.dart
//
// The studio's brain, pure (no widgets, unit-tested in test/export/studio_controller_test.dart): selection,
// move / resize gestures with smart guides and grid snapping, align / distribute, nudge, duplicate, delete,
// z order, undo / redo and zoom. Every change goes through the host's [StudioAdapter]; the controller only keeps
// the selection, the live rects of a gesture in progress and the history.
//
// Two listenables, so a drag stays at 60 fps:
//   the controller itself   structure: items, selection, history, zoom (the canvas rebuilds its item list)
//   [live]                  every pointer move of a gesture (only the moving items and the overlay repaint)
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';

import 'studio_model.dart';

class StudioController<P> extends ChangeNotifier {
  StudioController({
    required this.adapter,
    required StudioPage page,
    this.clampToPage = true,
    bool snapEnabled = true,
    this.grid,
    this.snapThresholdPx = 6,
    this.minSize = const Size(8, 8),
    this.nudgeStep = 1,
    this.nudgeBigStep = 10,
    this.historyLimit = 60,
    this.coalesceWindow = const Duration(seconds: 1),
    DateTime Function()? clock,
  })  : _page = page,
        _snap = snapEnabled,
        _clock = clock ?? DateTime.now {
    _items = adapter.readItems();
  }

  final StudioAdapter<P> adapter;

  /// Keep items inside the page while moving / resizing / nudging.
  bool clampToPage;

  /// The snap grid in page units (x step, y step); null = no grid. The export page's 2 % grid is
  /// `Size(width * .02, height * .02)`.
  Size? grid;

  /// How close (screen pixels) an edge must come to a guide to snap to it.
  double snapThresholdPx;

  /// The default smallest item size (page units), when an item has no [StudioItem.minSize].
  Size minSize;
  double nudgeStep, nudgeBigStep;
  int historyLimit;

  /// Steps recorded with `coalesce: true` under the same label within this window become one step.
  Duration coalesceWindow;
  final DateTime Function() _clock;

  StudioPage _page;
  bool _snap;
  bool _alignToPage = false;
  List<StudioItem<P>> _items = const [];
  final _selection = <String>{};
  final _live = <String, Rect>{};
  List<StudioGuide> _guides = const [];
  _Gesture? _gesture;
  final _undo = <_Step>[];
  final _redo = <_Step>[];
  final _liveSignal = _Signal();

  /// Fires on every pointer move of a gesture (live rects, guides).
  Listenable get live => _liveSignal;

  // ── Page & items ─────────────────────────────────────────────────────────────────────────────────────────
  StudioPage get page => _page;
  set page(StudioPage p) {
    if (p == _page) return;
    _page = p;
    notifyListeners();
  }

  /// Every item, bottom first, as the adapter last reported them.
  List<StudioItem<P>> get items => _items;

  StudioItem<P>? itemById(String id) {
    for (final i in _items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// The z index of an item (0 = bottom), -1 when unknown.
  int zOf(String id) => _items.indexWhere((i) => i.id == id);

  /// The rect to draw: the live one while a gesture moves the item, else the stored one.
  Rect? rectOf(String id) => _live[id] ?? itemById(id)?.rect;

  /// Re-reads the items from the adapter (after the host changed its model outside [record]) and drops a
  /// selection whose item is gone.
  void refresh() {
    _items = adapter.readItems();
    _selection.removeWhere((id) => itemById(id) == null);
    notifyListeners();
  }

  // ── Selection ────────────────────────────────────────────────────────────────────────────────────────────
  Set<String> get selection => Set.unmodifiable(_selection);
  bool isSelected(String id) => _selection.contains(id);

  /// The one selected item, or null when none or several are selected.
  StudioItem<P>? get single => _selection.length == 1 ? itemById(_selection.first) : null;

  /// Selects [id] alone, or with [additive] (shift / ctrl click) toggles it in the selection. Null clears.
  void select(String? id, {bool additive = false}) {
    if (id == null) return clearSelection();
    if (itemById(id) == null) return;
    if (additive) {
      if (!_selection.remove(id)) _selection.add(id);
    } else {
      if (_selection.length == 1 && _selection.first == id) return;
      _selection
        ..clear()
        ..add(id);
    }
    notifyListeners();
  }

  void selectAll() {
    _selection
      ..clear()
      ..addAll(_items.where((i) => i.visible).map((i) => i.id));
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection.clear();
    notifyListeners();
  }

  /// Marquee: selects the visible, unlocked items the rect touches (page units).
  void selectInRect(Rect r, {bool additive = false}) {
    if (!additive) _selection.clear();
    for (final i in _items) {
      if (i.visible && !i.locked && i.rect.overlaps(r)) _selection.add(i.id);
    }
    notifyListeners();
  }

  /// The bounds of the selection (live rects during a gesture), or null.
  Rect? get selectionBounds => _bounds(_selection.map(rectOf).whereType<Rect>());

  /// The selected items a gesture or a command may change.
  List<StudioItem<P>> get _editable =>
      [for (final i in _items) if (_selection.contains(i.id) && i.visible && !i.locked) i];

  bool get hasEditableSelection => _editable.isNotEmpty;

  /// The single selected item when it can be resized (shows the 8 handles).
  StudioItem<P>? get resizable {
    final s = single;
    return s != null && s.visible && !s.locked && s.rotation == 0 && s.resize != StudioResize.none ? s : null;
  }

  // ── Gestures (one undo step each) ───────────────────────────────────────────────────────────────────────
  bool get dragging => _gesture != null;

  /// The guides of the gesture in progress (page units).
  List<StudioGuide> get guides => _guides;

  /// Starts moving the editable selection. Returns false when nothing can move.
  bool beginMove() {
    final ids = _editable;
    if (ids.isEmpty) return false;
    _gesture = _Gesture(
      start: {for (final i in ids) i.id: i.rect},
      targets: _targetsExcluding(ids.map((i) => i.id).toSet()),
    );
    return true;
  }

  /// [delta] is the TOTAL pointer travel since [beginMove], in page units. [constrain] (shift) keeps the move on
  /// the dominant axis. Returns the active guides.
  List<StudioGuide> updateMove(Offset delta, {bool constrain = false}) {
    final g = _gesture;
    if (g == null || g.handle != null) return const [];
    var d = delta;
    if (constrain) d = d.dx.abs() >= d.dy.abs() ? Offset(d.dx, 0) : Offset(0, d.dy);
    final b0 = _bounds(g.start.values)!;
    var b = b0.shift(d);
    if (_snap) {
      final thr = _threshold;
      final sx = constrain && d.dx == 0 ? 0.0 : _snapAxis([b.left, b.center.dx, b.right], g.targets._xs, thr, grid?.width);
      final sy = constrain && d.dy == 0 ? 0.0 : _snapAxis([b.top, b.center.dy, b.bottom], g.targets._ys, thr, grid?.height);
      d += Offset(sx, sy);
      b = b0.shift(d);
    }
    if (clampToPage) {
      d += Offset(_clampShift(b.left, b.right, _page.width), _clampShift(b.top, b.bottom, _page.height));
      b = b0.shift(d);
    }
    _live
      ..clear()
      ..addAll(g.start.map((id, r) => MapEntry(id, r.shift(d))));
    _guides = _snap ? _guidesFor(b, g.targets) : const [];
    _liveSignal.fire();
    return _guides;
  }

  /// Starts resizing the single resizable item from [handle]. Returns false when it cannot.
  bool beginResize(StudioHandle handle) {
    final it = resizable;
    if (it == null) return false;
    final mode = it.resize;
    if (mode == StudioResize.horizontal && !handle.horizontal) return false;
    if (mode == StudioResize.vertical && !handle.vertical) return false;
    _gesture = _Gesture(start: {it.id: it.rect}, targets: _targetsExcluding({it.id}), handle: handle, item: it);
    return true;
  }

  /// [delta] is the TOTAL pointer travel since [beginResize] (page units). [keepAspect] (shift) keeps the ratio
  /// of any item; [StudioResize.aspect] items always keep it.
  List<StudioGuide> updateResize(Offset delta, {bool keepAspect = false}) {
    final g = _gesture;
    final h = g?.handle;
    if (g == null || h == null) return const [];
    final it = g.item!;
    final r = resizeRect(
      start: g.start[it.id]!,
      handle: h,
      delta: delta,
      mode: it.resize,
      keepAspect: keepAspect,
      min: it.minSize ?? minSize,
      targets: _snap ? g.targets : null,
    );
    _live
      ..clear()
      ..[it.id] = r;
    _guides = _snap ? _guidesFor(r, g.targets) : const [];
    _liveSignal.fire();
    return _guides;
  }

  /// Ends the gesture: the live rects are written as ONE undo step (nothing when nothing moved).
  void endGesture({String label = 'move'}) {
    final g = _gesture;
    if (g == null) return;
    final changed = {
      for (final e in _live.entries)
        if (g.start[e.key] != e.value) e.key: e.value,
    };
    _gesture = null;
    _live.clear();
    _guides = const [];
    if (changed.isEmpty) {
      _liveSignal.fire();
      return;
    }
    record(g.handle == null ? label : 'resize', () => adapter.writeRects(changed));
    _liveSignal.fire();
  }

  /// Drops the gesture without changing anything.
  void cancelGesture() {
    if (_gesture == null) return;
    _gesture = null;
    _live.clear();
    _guides = const [];
    _liveSignal.fire();
  }

  /// The resize maths, exposed for tests and hosts: the new rect of [start] dragged by [delta] from [handle].
  Rect resizeRect({
    required Rect start,
    required StudioHandle handle,
    required Offset delta,
    StudioResize mode = StudioResize.free,
    bool keepAspect = false,
    Size? min,
    StudioSnapTargets? targets,
  }) {
    final mn = min ?? minSize;
    final minW = math.min(mn.width, _page.width), minH = math.min(mn.height, _page.height);
    final dx = mode == StudioResize.vertical ? 0.0 : delta.dx;
    final dy = mode == StudioResize.horizontal ? 0.0 : delta.dy;
    final aspect = mode == StudioResize.aspect ||
        (keepAspect && mode != StudioResize.horizontal && mode != StudioResize.vertical);
    final thr = _threshold;
    final gx = grid?.width, gy = grid?.height;

    if (!aspect) {
      var l = start.left, t = start.top, r = start.right, b = start.bottom;
      if (handle.movesLeft) l += dx;
      if (handle.movesRight) r += dx;
      if (handle.movesTop) t += dy;
      if (handle.movesBottom) b += dy;
      if (targets != null) {
        if (handle.movesLeft) l += _snapAxis([l], targets._xs, thr, gx);
        if (handle.movesRight) r += _snapAxis([r], targets._xs, thr, gx);
        if (handle.movesTop) t += _snapAxis([t], targets._ys, thr, gy);
        if (handle.movesBottom) b += _snapAxis([b], targets._ys, thr, gy);
      }
      if (clampToPage) {
        if (handle.movesLeft) l = math.max(l, 0);
        if (handle.movesRight) r = math.min(r, _page.width);
        if (handle.movesTop) t = math.max(t, 0);
        if (handle.movesBottom) b = math.min(b, _page.height);
      }
      if (r - l < minW) {
        if (handle.movesLeft) {
          l = r - minW;
        } else {
          r = l + minW;
        }
      }
      if (b - t < minH) {
        if (handle.movesTop) {
          t = b - minH;
        } else {
          b = t + minH;
        }
      }
      return Rect.fromLTRB(l, t, r, b);
    }

    // Aspect: one scale factor, anchored on the opposite corner / edge (an edge handle keeps the other axis centred).
    final w0 = start.width <= 0 ? 1.0 : start.width, h0 = start.height <= 0 ? 1.0 : start.height;
    final ax = handle.movesLeft ? start.right : (handle.movesRight ? start.left : start.center.dx);
    final ay = handle.movesTop ? start.bottom : (handle.movesBottom ? start.top : start.center.dy);
    final sx = (w0 + (handle.movesLeft ? -dx : dx)) / w0;
    final sy = (h0 + (handle.movesTop ? -dy : dy)) / h0;
    var s = handle.isCorner ? ((sx - 1).abs() >= (sy - 1).abs() ? sx : sy) : (handle.horizontal ? sx : sy);
    if (targets != null) {
      double? best;
      if (handle.horizontal) {
        final edge = handle.movesLeft ? ax - w0 * s : ax + w0 * s;
        final d = _snapAxis([edge], targets._xs, thr, gx);
        if (d != 0) best = ((edge + d) - ax).abs() / w0;
      }
      if (handle.vertical) {
        final edge = handle.movesTop ? ay - h0 * s : ay + h0 * s;
        final d = _snapAxis([edge], targets._ys, thr, gy);
        if (d != 0) {
          final cand = ((edge + d) - ay).abs() / h0;
          if (best == null || (cand - s).abs() < (best - s).abs()) best = cand;
        }
      }
      if (best != null) s = best;
    }
    final sMin = math.max(minW / w0, minH / h0);
    if (clampToPage) {
      double room(bool start, bool end, double anchor, double size) =>
          start ? anchor : (end ? size - anchor : 2 * math.min(anchor, size - anchor));
      final availW = room(handle.movesLeft, handle.movesRight, ax, _page.width);
      final availH = room(handle.movesTop, handle.movesBottom, ay, _page.height);
      s = math.min(s, math.min(availW / w0, availH / h0));
    }
    s = math.max(s, sMin);
    final w = w0 * s, hh = h0 * s;
    final l = handle.movesLeft ? ax - w : (handle.movesRight ? ax : ax - w / 2);
    final t = handle.movesTop ? ay - hh : (handle.movesBottom ? ay : ay - hh / 2);
    return Rect.fromLTWH(l, t, w, hh);
  }

  // ── Grid, rulers, reveal ─────────────────────────────────────────────────────────────────────────────────
  bool _showGrid = false, _showRulers = false;

  /// Draw [grid] on the page (snapping to it works whenever [grid] is set and snapping is on).
  bool get showGrid => _showGrid && grid != null;
  set showGrid(bool v) {
    if (v == _showGrid) return;
    _showGrid = v;
    notifyListeners();
  }

  /// Rulers in page units along the canvas's top and start edges.
  bool get showRulers => _showRulers;
  set showRulers(bool v) {
    if (v == _showRulers) return;
    _showRulers = v;
    notifyListeners();
  }

  /// Sets the snap grid (null = none) and shows it.
  void setGrid(Size? g) {
    grid = g;
    _showGrid = g != null;
    notifyListeners();
  }

  String? _reveal;

  /// Asks the canvas to pan so item [id] is in view (e.g. above a panel that just opened).
  void reveal(String id) {
    _reveal = id;
    notifyListeners();
  }

  /// The pending reveal (the canvas takes it once).
  String? takeReveal() {
    final r = _reveal;
    _reveal = null;
    return r;
  }

  // ── Snapping ─────────────────────────────────────────────────────────────────────────────────────────────
  bool get snapEnabled => _snap;
  set snapEnabled(bool v) {
    if (v == _snap) return;
    _snap = v;
    notifyListeners();
  }

  void toggleSnap() => snapEnabled = !_snap;

  /// The snap distance in page units at the current zoom.
  double get _threshold => snapThresholdPx / math.max(scale, 1e-6);

  /// What the moving item can snap to: the page's edges and centre, and every other visible item's edges and
  /// centres. Public for tests.
  StudioSnapTargets targetsExcluding(Set<String> ids) => _targetsExcluding(ids);

  StudioSnapTargets _targetsExcluding(Set<String> ids) {
    final xs = <_Target>[
      _Target(0, null),
      _Target(_page.width / 2, null),
      _Target(_page.width, null),
    ];
    final ys = <_Target>[
      _Target(0, null),
      _Target(_page.height / 2, null),
      _Target(_page.height, null),
    ];
    for (final i in _items) {
      if (!i.visible || ids.contains(i.id)) continue;
      final r = i.rect;
      xs.addAll([_Target(r.left, r), _Target(r.center.dx, r), _Target(r.right, r)]);
      ys.addAll([_Target(r.top, r), _Target(r.center.dy, r), _Target(r.bottom, r)]);
    }
    return StudioSnapTargets._(xs, ys);
  }

  /// The shift that brings the nearest of [moving] onto a target within [thr]; else onto the grid (the first
  /// value, i.e. the leading edge); else 0.
  static double _snapAxis(List<double> moving, List<_Target> targets, double thr, double? grid) {
    double? best;
    for (final m in moving) {
      for (final t in targets) {
        final d = t.pos - m;
        if (d.abs() <= thr && (best == null || d.abs() < best.abs())) best = d;
      }
    }
    if (best != null) return best;
    if (grid != null && grid > 0) {
      final m = moving.first;
      return (m / grid).round() * grid - m;
    }
    return 0;
  }

  List<StudioGuide> _guidesFor(Rect b, StudioSnapTargets t) {
    const eps = 1e-6;
    final out = <StudioGuide>[];
    final seenX = <double>{}, seenY = <double>{};
    for (final x in t._xs) {
      if ((x.pos - b.left).abs() > eps && (x.pos - b.center.dx).abs() > eps && (x.pos - b.right).abs() > eps) continue;
      final s = x.source;
      final start = s == null ? 0.0 : math.min(s.top, b.top);
      final end = s == null ? _page.height : math.max(s.bottom, b.bottom);
      if (seenX.add(x.pos)) {
        out.add(StudioGuide(vertical: true, position: x.pos, start: start, end: end));
      } else {
        final i = out.indexWhere((g) => g.vertical && g.position == x.pos);
        final g = out[i];
        out[i] = StudioGuide(vertical: true, position: x.pos, start: math.min(g.start, start), end: math.max(g.end, end));
      }
    }
    for (final y in t._ys) {
      if ((y.pos - b.top).abs() > eps && (y.pos - b.center.dy).abs() > eps && (y.pos - b.bottom).abs() > eps) continue;
      final s = y.source;
      final start = s == null ? 0.0 : math.min(s.left, b.left);
      final end = s == null ? _page.width : math.max(s.right, b.right);
      if (seenY.add(y.pos)) {
        out.add(StudioGuide(vertical: false, position: y.pos, start: start, end: end));
      } else {
        final i = out.indexWhere((g) => !g.vertical && g.position == y.pos);
        final g = out[i];
        out[i] = StudioGuide(vertical: false, position: y.pos, start: math.min(g.start, start), end: math.max(g.end, end));
      }
    }
    return out;
  }

  static double _clampShift(double lo, double hi, double size) {
    if (hi - lo >= size) return -lo;
    if (lo < 0) return -lo;
    if (hi > size) return size - hi;
    return 0;
  }

  // ── Commands (one undo step each) ───────────────────────────────────────────────────────────────────────
  /// Align to the page when [alignToPage] is on or one item is selected, else to the selection's bounds.
  bool get alignToPage => _alignToPage;
  set alignToPage(bool v) {
    if (v == _alignToPage) return;
    _alignToPage = v;
    notifyListeners();
  }

  void align(StudioAlign a) {
    final its = _editable;
    if (its.isEmpty) return;
    final ref = (_alignToPage || its.length == 1) ? _page.rect : _bounds(its.map((i) => i.rect))!;
    _writeRects('align', {
      for (final i in its)
        i.id: switch (a) {
          StudioAlign.left => i.rect.translate(ref.left - i.rect.left, 0),
          StudioAlign.centerH => i.rect.translate(ref.center.dx - i.rect.center.dx, 0),
          StudioAlign.right => i.rect.translate(ref.right - i.rect.right, 0),
          StudioAlign.top => i.rect.translate(0, ref.top - i.rect.top),
          StudioAlign.middle => i.rect.translate(0, ref.center.dy - i.rect.center.dy),
          StudioAlign.bottom => i.rect.translate(0, ref.bottom - i.rect.bottom),
        },
    });
  }

  /// Equal gaps between 3 or more items, the outer two staying where they are.
  bool get canDistribute => _editable.length >= 3;

  void distribute(StudioAxis axis) {
    final its = _editable;
    if (its.length < 3) return;
    final h = axis == StudioAxis.horizontal;
    its.sort((a, b) => h ? a.rect.left.compareTo(b.rect.left) : a.rect.top.compareTo(b.rect.top));
    final lo = h ? its.first.rect.left : its.first.rect.top;
    final hi = its.map((i) => h ? i.rect.right : i.rect.bottom).reduce(math.max);
    final sum = its.fold<double>(0, (s, i) => s + (h ? i.rect.width : i.rect.height));
    final gap = (hi - lo - sum) / (its.length - 1);
    var at = lo;
    final out = <String, Rect>{};
    for (final i in its) {
      out[i.id] = h ? i.rect.translate(at - i.rect.left, 0) : i.rect.translate(0, at - i.rect.top);
      at += (h ? i.rect.width : i.rect.height) + gap;
    }
    _writeRects('distribute', out);
  }

  /// Arrow keys: [dx], [dy] in steps (-1, 0, 1); [big] (shift) uses [nudgeBigStep]. Repeated nudges within
  /// [coalesceWindow] are one undo step.
  void nudge(int dx, int dy, {bool big = false}) {
    final its = _editable;
    if (its.isEmpty) return;
    final step = big ? nudgeBigStep : nudgeStep;
    var d = Offset(dx * step, dy * step);
    if (clampToPage) {
      final b = _bounds(its.map((i) => i.rect))!.shift(d);
      d += Offset(_clampShift(b.left, b.right, _page.width), _clampShift(b.top, b.bottom, _page.height));
    }
    if (d == Offset.zero) return;
    _writeRects('nudge', {for (final i in its) i.id: i.rect.shift(d)}, coalesce: true);
  }

  /// Copies the selection (locked items too), moved by [nudgeBigStep], and selects the copies.
  void duplicate() {
    final its = [for (final i in _items) if (_selection.contains(i.id)) i];
    if (its.isEmpty) return;
    final copies = <StudioItem<P>>[];
    for (final i in its) {
      final c = adapter.cloneItem(i);
      var r = i.rect.shift(Offset(nudgeBigStep, nudgeBigStep));
      if (clampToPage) r = r.shift(Offset(_clampShift(r.left, r.right, _page.width), _clampShift(r.top, r.bottom, _page.height)));
      copies.add(c.copyWith(rect: r, locked: false));
    }
    record('duplicate', () => adapter.addItems(copies));
    // an adapter may add fewer copies than asked (a limit on the number of items): select the ones that exist
    _selection
      ..clear()
      ..addAll([for (final c in copies) if (itemById(c.id) != null) c.id]);
    notifyListeners();
  }

  /// Deletes the selected items that are not locked.
  void deleteSelection() {
    final ids = {for (final i in _items) if (_selection.contains(i.id) && !i.locked) i.id};
    if (ids.isEmpty) return;
    record('delete', () => adapter.removeItems(ids));
    _selection.removeAll(ids);
    notifyListeners();
  }

  void bringForward() => _arrange((ids, sel) {
        for (var i = ids.length - 2; i >= 0; i--) {
          if (sel.contains(ids[i]) && !sel.contains(ids[i + 1])) {
            final t = ids[i];
            ids[i] = ids[i + 1];
            ids[i + 1] = t;
          }
        }
      });

  void sendBackward() => _arrange((ids, sel) {
        for (var i = 1; i < ids.length; i++) {
          if (sel.contains(ids[i]) && !sel.contains(ids[i - 1])) {
            final t = ids[i];
            ids[i] = ids[i - 1];
            ids[i - 1] = t;
          }
        }
      });

  void bringToFront() => _arrange((ids, sel) {
        final picked = ids.where(sel.contains).toList();
        ids
          ..removeWhere(sel.contains)
          ..addAll(picked);
      });

  void sendToBack() => _arrange((ids, sel) {
        final picked = ids.where(sel.contains).toList();
        ids
          ..removeWhere(sel.contains)
          ..insertAll(0, picked);
      });

  void _arrange(void Function(List<String> ids, Set<String> sel) change) {
    if (_selection.isEmpty) return;
    final before = [for (final i in _items) i.id];
    final ids = List.of(before);
    change(ids, _selection);
    if (listEquals(ids, before)) return;
    record('arrange', () => adapter.reorder(ids));
  }

  void _writeRects(String label, Map<String, Rect> rects, {bool coalesce = false}) {
    final changed = {
      for (final e in rects.entries)
        if (itemById(e.key)?.rect != e.value) e.key: e.value,
    };
    if (changed.isEmpty) return;
    record(label, () => adapter.writeRects(changed), coalesce: coalesce);
  }

  // ── History ──────────────────────────────────────────────────────────────────────────────────────────────
  /// Runs a host change of its own model as ONE undo step: `controller.record('font', () => model.font = f)`.
  /// With [coalesce], a step with the same label recorded within [coalesceWindow] (and the same selection)
  /// merges into the previous one: a slider dragged through 40 values is one undo.
  void record(String label, VoidCallback mutate, {bool coalesce = false}) {
    if (_gesture != null) cancelGesture();
    final before = adapter.snapshot();
    final selBefore = Set.of(_selection);
    mutate();
    final after = adapter.snapshot();
    final now = _clock();
    final last = _undo.isEmpty ? null : _undo.last;
    if (coalesce &&
        last != null &&
        _redo.isEmpty &&
        last.coalesce &&
        last.label == label &&
        setEquals(last.selAfter, selBefore) &&
        now.difference(last.at) <= coalesceWindow) {
      _undo[_undo.length - 1] = last.withAfter(after, now);
    } else {
      _undo.add(_Step(label, before, after, selBefore, selBefore, now, coalesce));
      if (_undo.length > historyLimit) _undo.removeAt(0);
    }
    _redo.clear();
    refresh();
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;
  int get historyLength => _undo.length;

  void undo() {
    if (_undo.isEmpty) return;
    cancelGesture();
    final s = _undo.removeLast();
    adapter.restore(s.before);
    _redo.add(s);
    _restoreSelection(s.selBefore);
  }

  void redo() {
    if (_redo.isEmpty) return;
    cancelGesture();
    final s = _redo.removeLast();
    adapter.restore(s.after);
    _undo.add(s.withAt(_clock().subtract(coalesceWindow * 2)));
    _restoreSelection(s.selAfter);
  }

  /// Forgets the history (after loading another design).
  void clearHistory() {
    _undo.clear();
    _redo.clear();
    notifyListeners();
  }

  void _restoreSelection(Set<String> sel) {
    _selection
      ..clear()
      ..addAll(sel);
    refresh();
  }

  // ── Zoom ─────────────────────────────────────────────────────────────────────────────────────────────────
  static const zoomSteps = <double>[.25, .33, .5, .67, .75, 1, 1.25, 1.5, 2, 3, 4];
  static const double minZoom = .25, maxZoom = 4;

  /// "Fit page" may go below [minZoom] on a small window so the page always fits.
  static const double minFitZoom = .05;

  double _zoom = 1;
  bool _fit = true;
  double _fitZoom = 1;

  /// The zoom in effect (1 = 100 %: one page unit = [StudioPage.unitPx] screen pixels).
  double get zoom => _fit ? _fitZoom : _zoom;

  /// Screen pixels per page unit.
  double get scale => zoom * _page.unitPx;
  bool get fitted => _fit;

  /// The zoom that fits the page in [viewport] with [padding] on every side. [extra] (page units) is paper drawn
  /// around the page that must fit too (StudioCanvas.paperInsets: horizontal, vertical sums).
  double fitZoomFor(Size viewport, {double padding = 24, Size extra = Size.zero}) {
    final w = (viewport.width - padding * 2) / ((_page.width + extra.width) * _page.unitPx);
    final h = (viewport.height - padding * 2) / ((_page.height + extra.height) * _page.unitPx);
    final z = math.min(w, h);
    if (!z.isFinite || z <= 0) return minFitZoom;
    return z.clamp(minFitZoom, maxZoom).toDouble();
  }

  /// The canvas reports its size (after layout); notifies only when the fitted zoom changes.
  void setViewport(Size viewport, {double padding = 24, Size extra = Size.zero}) {
    final z = fitZoomFor(viewport, padding: padding, extra: extra);
    if ((z - _fitZoom).abs() < 1e-9) return;
    _fitZoom = z;
    if (_fit) notifyListeners();
  }

  void setZoom(double z) {
    final v = z.clamp(math.min(minZoom, zoom), maxZoom).toDouble();
    if (!_fit && v == _zoom) return;
    _fit = false;
    _zoom = v;
    notifyListeners();
  }

  void zoomIn() {
    final z = zoom;
    setZoom(zoomSteps.firstWhere((s) => s > z + 1e-3, orElse: () => maxZoom));
  }

  void zoomOut() {
    final z = zoom;
    final lower = zoomSteps.where((s) => s < z - 1e-3);
    setZoom(lower.isEmpty ? math.min(z, minZoom) : lower.last);
  }

  void fitPage() {
    if (_fit) return;
    _fit = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _liveSignal.dispose();
    super.dispose();
  }

  static Rect? _bounds(Iterable<Rect> rects) {
    Rect? b;
    for (final r in rects) {
      b = b == null ? r : b.expandToInclude(r);
    }
    return b;
  }
}

/// The snap targets of a gesture (page units); built once when the gesture starts.
class StudioSnapTargets {
  StudioSnapTargets._(this._xs, this._ys);
  final List<_Target> _xs, _ys;

  /// The x positions (for tests).
  List<double> get xPositions => [for (final t in _xs) t.pos];
  List<double> get yPositions => [for (final t in _ys) t.pos];
}

class _Target {
  const _Target(this.pos, this.source);
  final double pos;

  /// The item the line comes from, null for the page.
  final Rect? source;
}

class _Gesture {
  _Gesture({required this.start, required this.targets, this.handle, this.item});
  final Map<String, Rect> start;
  final StudioSnapTargets targets;
  final StudioHandle? handle;
  final StudioItem<Object?>? item;
}

class _Step {
  const _Step(this.label, this.before, this.after, this.selBefore, this.selAfter, this.at, this.coalesce);
  final String label;
  final Object before, after;
  final Set<String> selBefore, selAfter;
  final DateTime at;
  final bool coalesce;

  _Step withAfter(Object a, DateTime now) => _Step(label, before, a, selBefore, selAfter, now, coalesce);
  _Step withAt(DateTime t) => _Step(label, before, after, selBefore, selAfter, t, coalesce);
}

class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}
