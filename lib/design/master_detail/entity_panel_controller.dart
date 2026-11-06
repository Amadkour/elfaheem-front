// lib/design/master_detail/entity_panel_controller.dart — what the detail panel of a list shows (D-290).
//
// The trail is the panel's history: a row opens a new trail ([open]); a link inside the panel drills in ([push]: the
// trail grows and drops whatever was ahead); [back] / [forward] walk it and keep what is ahead, like a browser;
// [jumpTo] is a breadcrumb tap. [siblings] are the list's rows (the page hands them on every build), so [next] /
// [previous] step through the list without closing the panel. [selectedId] is the row to draw as selected: the open
// root, else the keyboard's cursor. [storage] keeps what the views of this trail held (a scroll offset, a sub-list's
// query and rows), so Back returns to them as they were.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';

class EntityPanelController extends ChangeNotifier {
  EntityPanelController({this.rowKind});

  /// The kind of the list's rows (null: any).
  final EntityKind? rowKind;

  final List<EntityRef> _trail = [];
  int _index = -1;
  int? _cursor;
  int _revision = 0;

  /// The list's rows, in order (set by the page on every build; no notification).
  List<EntityRef> siblings = const [];

  /// What the views of this trail remember; a new trail starts clean.
  PageStorageBucket get storage => _storage;
  PageStorageBucket _storage = PageStorageBucket();

  bool get isOpen => _index >= 0;

  /// The entity shown, or null when closed.
  EntityRef? get current => isOpen ? _trail[_index] : null;

  /// The breadcrumbs: the trail up to the entity shown.
  List<EntityRef> get trail => isOpen ? List.unmodifiable(_trail.sublist(0, _index + 1)) : const [];

  /// The whole trail, the entries ahead included.
  List<EntityRef> get fullTrail => List.unmodifiable(_trail);
  int get index => _index;

  bool get canBack => _index > 0;
  bool get canForward => isOpen && _index < _trail.length - 1;

  /// Bumped by [reload]: the detail view loads again.
  int get revision => _revision;

  /// The entity the trail started from (the list's row).
  EntityRef? get root => isOpen ? _trail.first : null;

  /// The row drawn as selected: the open root when it is one of the list's rows, else the keyboard cursor.
  int? get selectedId {
    final r = root;
    if (r != null) return rowKind == null || r.kind == rowKind ? r.id : null;
    return _cursor;
  }

  /// A student opened from a course: that course (its row is drawn first / scrolled to).
  int? get focusCourseId => _contextOf(EntityKind.student, EntityKind.course);

  /// A course opened from a student: that student (the course's students start at them; their history is one tap
  /// away).
  int? get contextStudentId => _contextOf(EntityKind.course, EntityKind.student);

  int? _contextOf(EntityKind shown, EntityKind from) {
    if (_index < 1 || _trail[_index].kind != shown) return null;
    final prev = _trail[_index - 1];
    return prev.kind == from ? prev.id : null;
  }

  /// A new trail starting at [ref] (a row tap). The same entity already at the root keeps its trail.
  void open(EntityRef ref) {
    if (isOpen && _trail.first == ref && _index == 0) return;
    _trail
      ..clear()
      ..add(ref);
    _index = 0;
    _storage = PageStorageBucket();
    if (rowKind == null || ref.kind == rowKind) _cursor = ref.id;
    notifyListeners();
  }

  /// Drills into [ref] from the entity shown (a link inside the panel); opens when closed. The same entity as the
  /// one shown does nothing.
  void push(EntityRef ref) {
    if (!isOpen) return open(ref);
    if (_trail[_index] == ref) return;
    _trail.removeRange(_index + 1, _trail.length);
    _trail.add(ref);
    _index++;
    notifyListeners();
  }

  bool back() {
    if (!canBack) return false;
    _index--;
    notifyListeners();
    return true;
  }

  bool forward() {
    if (!canForward) return false;
    _index++;
    notifyListeners();
    return true;
  }

  /// A breadcrumb: shows trail[index] (what is ahead stays for [forward]).
  void jumpTo(int index) {
    if (!isOpen || index < 0 || index >= _trail.length || index == _index) return;
    _index = index;
    notifyListeners();
  }

  void close() {
    if (!isOpen) return;
    _trail.clear();
    _index = -1;
    _storage = PageStorageBucket();
    notifyListeners();
  }

  /// The name a summary brought, for the trail's entries that came without one (a deep link): the breadcrumbs read it.
  void learn(EntityRef named) {
    if (named.name.isEmpty) return;
    var changed = false;
    for (var i = 0; i < _trail.length; i++) {
      if (_trail[i] == named && _trail[i].name.isEmpty) {
        _trail[i] = named;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Loads the entity shown again (after a change made elsewhere, e.g. the Manage sheet).
  void reload() {
    _revision++;
    notifyListeners();
  }

  int _siblingIndex(int? id) {
    if (id == null) return -1;
    return siblings.indexWhere((s) => s.id == id && (rowKind == null || s.kind == rowKind));
  }

  /// The position of the open root among the list's rows (-1: not one of them).
  int get siblingIndex => _siblingIndex(isOpen ? (rowKind == null || root!.kind == rowKind ? root!.id : null) : _cursor);

  bool get hasNext {
    final i = siblingIndex;
    return i >= 0 && i < siblings.length - 1;
  }

  bool get hasPrevious => siblingIndex > 0;

  /// The next row of the list: opened when the panel is open, else the cursor moves (the first row when none).
  bool next() => _step(1);

  bool previous() => _step(-1);

  bool _step(int d) {
    if (siblings.isEmpty) return false;
    final i = siblingIndex;
    final j = i < 0 ? (d > 0 ? 0 : siblings.length - 1) : i + d;
    if (j < 0 || j >= siblings.length) return false;
    if (isOpen) {
      _trail
        ..clear()
        ..add(siblings[j]);
      _index = 0;
      _storage = PageStorageBucket();
    }
    _cursor = siblings[j].id;
    notifyListeners();
    return true;
  }

  /// The row under the cursor (Enter opens it).
  EntityRef? get cursorRef {
    final i = _siblingIndex(_cursor);
    return i < 0 ? null : siblings[i];
  }
}
