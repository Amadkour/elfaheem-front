// The editor's state, without a widget: the spec being edited, the selected box, undo / redo, and the plain-words
// issues recomputed after every change. One drag (move / resize / draw) is ONE undo step; typing in a field's form
// merges into one step per field.
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';

import '../mark_templates_api.dart';

class MarkEditorModel extends ChangeNotifier {
  MarkEditorModel(MarkSheetSpec spec) : _spec = spec {
    _issues = validateSpec(spec);
  }

  MarkSheetSpec _spec;
  final _undo = <MarkSheetSpec>[];
  final _redo = <MarkSheetSpec>[];
  String? _selected;
  List<SpecIssue> _issues = const [];
  String? _lastKey;
  int _seq = 0;

  /// Raised by undo / redo so a form that holds text controllers can rebuild from the model.
  int epoch = 0;

  /// True once anything changed since the model was made or [markSaved] was called.
  bool dirty = false;

  MarkSheetSpec get spec => _spec;
  List<MarkField> get fields => _spec.fields;
  List<SpecIssue> get issues => _issues;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get selectedId => _selected;
  MarkField? get selected => _spec.field(_selected);
  int get errorCount => _issues.where((i) => i.error).length;
  int get warningCount => _issues.where((i) => !i.error).length;

  /// The issues that mention [id].
  List<SpecIssue> issuesOf(String id) => [for (final i in _issues) if (i.fieldIds.contains(id)) i];

  void markSaved() {
    dirty = false;
    notifyListeners();
  }

  void _set(MarkSheetSpec next, {String? coalesce, bool push = true}) {
    if (push && !(coalesce != null && coalesce == _lastKey)) {
      _undo.add(_spec);
      if (_undo.length > 100) _undo.removeAt(0);
    }
    if (push) _redo.clear();
    _lastKey = coalesce;
    _spec = next;
    _issues = validateSpec(next);
    dirty = true;
    notifyListeners();
  }

  void select(String? id) {
    if (_selected == id) return;
    _selected = id;
    _lastKey = null;
    notifyListeners();
  }

  String _newId() {
    final used = {for (final f in _spec.fields) f.id};
    String id;
    do {
      id = 'f${++_seq}';
    } while (used.contains(id));
    return id;
  }

  /// The question number after the highest one in use (marks and answer rows count apart).
  int nextQuestionNo(FieldType type) {
    var m = 0;
    for (final f in _spec.fields.where((f) => f.type == type)) {
      if ((f.questionNo ?? 0) > m) m = f.questionNo!;
    }
    return m + 1;
  }

  /// A drawn box: an untyped field, selected.
  String addBox(Rect box) {
    final id = _newId();
    _set(_spec.copyWith(fields: [..._spec.fields, MarkField(id: id, type: FieldType.unset, box: _clamp(box))]));
    _selected = id;
    notifyListeners();
    return id;
  }

  void deleteSelected() {
    final id = _selected;
    if (id != null) delete(id);
  }

  void delete(String id) {
    if (_spec.field(id) == null) return;
    final parts = _spec.sumParts;
    _set(_spec.copyWith(
      fields: [for (final f in _spec.fields) if (f.id != id) f],
      clearSumTotal: _spec.sumTotal == id,
      sumParts: parts == null ? null : [for (final p in parts) if (p != id) p],
    ));
    if (_selected == id) _selected = null;
    notifyListeners();
  }

  /// Starts a drag: the state before it becomes ONE undo step, the moves that follow are not pushed.
  void beginDrag() {
    _undo.add(_spec);
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
    _lastKey = null;
  }

  /// A box moved / resized during a drag (after [beginDrag]).
  void dragBox(String id, Rect box) {
    final f = _spec.field(id);
    if (f == null) return;
    final b = _clamp(box);
    var next = f.copyWith(box: b);
    if (f.type == FieldType.answerRow && f.options.isNotEmpty) {
      // the option boxes follow the row: same relative place inside the new box
      final o = f.box;
      Rect map(Rect r) => Rect.fromLTWH(
            b.left + (o.width <= 0 ? 0 : (r.left - o.left) / o.width * b.width),
            b.top + (o.height <= 0 ? 0 : (r.top - o.top) / o.height * b.height),
            o.width <= 0 ? 0 : r.width / o.width * b.width,
            o.height <= 0 ? 0 : r.height / o.height * b.height,
          );
      next = next.copyWith(options: [for (final x in f.options) MarkOption(x.label, map(x.box))]);
    }
    _set(_replace(next), push: false);
  }

  /// A drag that drew or moved nothing (a tap) leaves no undo step behind.
  void endDrag({required bool changed}) {
    if (!changed && _undo.isNotEmpty) _undo.removeLast();
    notifyListeners();
  }

  /// A field edited in the form. [coalesce] merges a run of edits (typing) into one undo step.
  void update(MarkField f, {String? coalesce}) => _set(_replace(f), coalesce: coalesce);

  void setType(String id, FieldType type) {
    final f = _spec.field(id);
    if (f == null || f.type == type) return;
    var next = f.asType(type, nextQuestionNo: type == FieldType.questionMark || type == FieldType.answerRow ? nextQuestionNo(type) : null);
    var spec = _replace(next);
    // the first total is the sum rule's total by default; a field that stops being a total leaves the rule
    if (type == FieldType.total && spec.sumTotal == null) spec = spec.copyWith(sumTotal: id);
    if (f.type == FieldType.total && spec.sumTotal == id) spec = spec.copyWith(clearSumTotal: true);
    _set(spec);
  }

  void setSumTotal(String? id) => _set(id == null ? _spec.copyWith(clearSumTotal: true) : _spec.copyWith(sumTotal: id));

  void setSumParts(List<String>? parts) => _set(parts == null ? _spec.copyWith(clearSumParts: true) : _spec.copyWith(sumParts: parts));

  void togglePart(String id) {
    final cur = _spec.effectiveParts;
    final next = cur.contains(id) ? [for (final p in cur) if (p != id) p] : [...cur, id];
    setSumParts(next);
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_spec);
    _spec = _undo.removeLast();
    _afterHistory();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_spec);
    _spec = _redo.removeLast();
    _afterHistory();
  }

  void _afterHistory() {
    _issues = validateSpec(_spec);
    if (_spec.field(_selected) == null) _selected = null;
    _lastKey = null;
    dirty = true;
    epoch++;
    notifyListeners();
  }

  MarkSheetSpec _replace(MarkField f) => _spec.copyWith(fields: [for (final x in _spec.fields) x.id == f.id ? f : x]);

  /// The field under a point of the page (the smallest box wins, so a small box inside a big one stays reachable).
  String? hit(Offset p) {
    String? best;
    var bestArea = double.infinity;
    for (final f in _spec.fields.reversed) {
      if (f.box.inflate(0.002).contains(p)) {
        final a = f.box.width * f.box.height;
        if (a < bestArea) {
          best = f.id;
          bestArea = a;
        }
      }
    }
    return best;
  }
}

/// Keeps a box on the page (a drawn / dragged box never leaves it) and at least the smallest readable size.
Rect _clamp(Rect r) {
  var w = r.width.clamp(kMinBoxSide, 1.0).toDouble();
  var h = r.height.clamp(kMinBoxSide, 1.0).toDouble();
  final x = r.left.clamp(0.0, 1.0 - w).toDouble();
  final y = r.top.clamp(0.0, 1.0 - h).toDouble();
  return Rect.fromLTWH(x, y, w, h);
}
