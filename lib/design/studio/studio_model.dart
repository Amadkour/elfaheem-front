// lib/design/studio/studio_model.dart
//
// The pure values of the studio engine (no widgets): the page, the generic item, the resize handles, the guide
// lines, the border value both studios draw, and the host adapter contract with an in-memory implementation
// (tests, demos and simple hosts). See studio.dart for how a studio plugs in.
library;

import 'dart:ui' show Color, Rect, Size;

import 'package:flutter/foundation.dart' show immutable;

/// The page in its OWN units: 1000 × 707 logical units for a certificate, millimetres of the content box for an
/// export page, … The engine never assumes a unit; [unitPx] is how many screen pixels one unit takes at 100 %.
@immutable
class StudioPage {
  const StudioPage(this.width, this.height, {this.unitPx = 1});

  final double width, height;

  /// Screen pixels per page unit at 100 % zoom (1 for the certificate's logical units, ≈ 3.78 for millimetres).
  final double unitPx;

  Rect get rect => Rect.fromLTWH(0, 0, width, height);
  Size get size => Size(width, height);

  @override
  bool operator ==(Object other) =>
      other is StudioPage && other.width == width && other.height == height && other.unitPx == unitPx;

  @override
  int get hashCode => Object.hash(width, height, unitPx);
}

/// How an item may be resized: freely, keeping its aspect ratio (images), along one axis only (a text field whose
/// height follows its text, a horizontal rule) or not at all.
enum StudioResize { free, aspect, horizontal, vertical, none }

/// One thing on the page. Its z order is its position in [StudioAdapter.readItems] (first = bottom).
/// [payload] belongs to the host (a CertField, an ExportBlock, …): the engine never reads it.
@immutable
class StudioItem<P> {
  const StudioItem({
    required this.id,
    required this.rect,
    required this.payload,
    this.locked = false,
    this.visible = true,
    this.resize = StudioResize.free,
    this.minSize,
    this.rotation = 0,
  });

  final String id;

  /// Position and size in page units, physical (x grows to the right in Arabic too).
  final Rect rect;
  final P payload;

  /// Locked items can be selected (to edit their properties) but never moved, resized, aligned or deleted.
  final bool locked;

  /// Hidden items are not drawn on the canvas and never hit, snapped to or selected by a marquee.
  final bool visible;
  final StudioResize resize;

  /// The smallest size in page units (null = the controller's [StudioController.minSize]).
  final Size? minSize;

  /// Degrees, clockwise, about the centre of [rect]. A turned item is drawn and hit turned; it moves like any item
  /// but shows no resize handles (its size is edited in the host's properties).
  final double rotation;

  StudioItem<P> copyWith({
    String? id,
    Rect? rect,
    P? payload,
    bool? locked,
    bool? visible,
    StudioResize? resize,
    Size? minSize,
    double? rotation,
  }) =>
      StudioItem<P>(
        id: id ?? this.id,
        rect: rect ?? this.rect,
        payload: payload ?? this.payload,
        locked: locked ?? this.locked,
        visible: visible ?? this.visible,
        resize: resize ?? this.resize,
        minSize: minSize ?? this.minSize,
        rotation: rotation ?? this.rotation,
      );
}

/// The 8 resize handles, physical (never mirrored in a right-to-left layout: the page is not mirrored either).
enum StudioHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left;

  bool get movesLeft => this == topLeft || this == left || this == bottomLeft;
  bool get movesRight => this == topRight || this == right || this == bottomRight;
  bool get movesTop => this == topLeft || this == top || this == topRight;
  bool get movesBottom => this == bottomLeft || this == bottom || this == bottomRight;
  bool get isCorner => (movesLeft || movesRight) && (movesTop || movesBottom);
  bool get horizontal => movesLeft || movesRight;
  bool get vertical => movesTop || movesBottom;

  /// Where the handle sits on [r] (page units).
  ({double x, double y}) pointOn(Rect r) => (
        x: movesLeft ? r.left : (movesRight ? r.right : r.center.dx),
        y: movesTop ? r.top : (movesBottom ? r.bottom : r.center.dy),
      );
}

/// A smart guide shown while dragging: a vertical line at x = [position] ([vertical] true) spanning y from
/// [start] to [end], or a horizontal line at y = [position] spanning x. Page units.
@immutable
class StudioGuide {
  const StudioGuide({required this.vertical, required this.position, required this.start, required this.end});

  final bool vertical;
  final double position, start, end;

  @override
  bool operator ==(Object other) =>
      other is StudioGuide &&
      other.vertical == vertical &&
      other.position == position &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(vertical, position, start, end);

  @override
  String toString() => 'StudioGuide(${vertical ? 'x' : 'y'}=$position, $start..$end)';
}

enum StudioAlign { left, centerH, right, top, middle, bottom }

enum StudioAxis { horizontal, vertical }

enum StudioBorderStyle { none, solid, dashed, double }

/// A border as both studios store it: style, width and corner radius in page units, colour.
@immutable
class StudioBorder {
  const StudioBorder({
    this.style = StudioBorderStyle.none,
    this.width = 1,
    this.color = const Color(0xFF1C1C24),
    this.radius = 0,
  });

  static const none = StudioBorder();

  final StudioBorderStyle style;
  final double width;
  final Color color;
  final double radius;

  bool get visible => style != StudioBorderStyle.none && width > 0;

  StudioBorder copyWith({StudioBorderStyle? style, double? width, Color? color, double? radius}) => StudioBorder(
        style: style ?? this.style,
        width: width ?? this.width,
        color: color ?? this.color,
        radius: radius ?? this.radius,
      );

  @override
  bool operator ==(Object other) =>
      other is StudioBorder &&
      other.style == style &&
      other.width == width &&
      other.color == color &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(style, width, color, radius);
}

/// What the engine needs from a studio. The studio keeps its own data model (a CertDesign, an ExportDesign, …);
/// the adapter only translates.
///
///   readItems    every item, bottom first (the list order IS the z order), rects in page units, physical
///   writeRects   store new rects (ids → rect): after a drag / resize / align / nudge / distribute
///   addItems     append items on top (duplicate); their ids come from [cloneItem]
///   removeItems  delete
///   reorder      the full id list, bottom first (bring forward / send back / to front / to back)
///   cloneItem    a copy of an item with a NEW id and a copy of its payload (the rect is moved by the engine)
///   snapshot     the whole design as an opaque value; restore puts it back (undo / redo). An immutable
///   restore      design can return itself; a mutable one returns a deep copy (e.g. its toJson()).
abstract class StudioAdapter<P> {
  List<StudioItem<P>> readItems();
  void writeRects(Map<String, Rect> rects);
  void addItems(List<StudioItem<P>> items);
  void removeItems(Set<String> ids);
  void reorder(List<String> ids);
  StudioItem<P> cloneItem(StudioItem<P> item);
  Object snapshot();
  void restore(Object snapshot);
}

/// An adapter over a plain list of items: for tests, previews and hosts without a model of their own.
/// Payloads are kept as they are: give [copyPayload] when they are mutable.
class StudioMemoryAdapter<P> implements StudioAdapter<P> {
  StudioMemoryAdapter(Iterable<StudioItem<P>> items, {P Function(P payload)? copyPayload, String idPrefix = 'item'})
      : items = List.of(items),
        _copy = copyPayload,
        _prefix = idPrefix;

  /// The items, bottom first. Editable by the host (inside [StudioController.record] to make it undoable).
  final List<StudioItem<P>> items;
  final P Function(P payload)? _copy;
  final String _prefix;
  int _seq = 0;

  int indexOf(String id) => items.indexWhere((i) => i.id == id);

  /// Replaces one item (a property edit from the host).
  void update(String id, StudioItem<P> Function(StudioItem<P> item) change) {
    final i = indexOf(id);
    if (i >= 0) items[i] = change(items[i]);
  }

  @override
  List<StudioItem<P>> readItems() => List.unmodifiable(items);

  @override
  void writeRects(Map<String, Rect> rects) {
    for (var i = 0; i < items.length; i++) {
      final r = rects[items[i].id];
      if (r != null) items[i] = items[i].copyWith(rect: r);
    }
  }

  @override
  void addItems(List<StudioItem<P>> added) => items.addAll(added);

  @override
  void removeItems(Set<String> ids) => items.removeWhere((i) => ids.contains(i.id));

  @override
  void reorder(List<String> ids) {
    final byId = {for (final i in items) i.id: i};
    final next = [for (final id in ids) if (byId[id] != null) byId[id]!];
    for (final i in items) {
      if (!ids.contains(i.id)) next.add(i);
    }
    items
      ..clear()
      ..addAll(next);
  }

  @override
  StudioItem<P> cloneItem(StudioItem<P> item) {
    String id;
    do {
      id = '$_prefix${++_seq}';
    } while (indexOf(id) >= 0);
    final copy = _copy;
    return item.copyWith(id: id, payload: copy == null ? item.payload : copy(item.payload));
  }

  @override
  Object snapshot() => List<StudioItem<P>>.unmodifiable(items);

  @override
  void restore(Object snapshot) {
    items
      ..clear()
      ..addAll(snapshot as List<StudioItem<P>>);
  }
}
