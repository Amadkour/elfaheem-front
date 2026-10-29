// lib/features/teacher/sessions/live/whiteboard/board_controller.dart
//
// The live whiteboard of one room (D-087): the presented board (who presents, background, pages), its items
// (ink, shapes, text boxes), laser dots, the local tool, and undo / redo. Pure logic, no LiveKit import: RoomPage
// injects [send] (publishData on the packet's topic) and feeds every packet of the board topics into [receive]
// with the REAL sender identity. Nothing in a payload decides who sent it.
//
// Who does what:
//   • One presenter at a time (the room's share arbiter decides; a board counts as presenting). The presenter owns
//     the board state (background, pages, the page everyone sees) and answers late joiners' snapshot requests.
//   • The presenter and hosts draw, edit and remove anything; a student draws only when the host allows drawing
//     (the room's annotation permission, [studentMayDraw]) and edits / removes only their own items.
//   • A packet from someone who may not do it is dropped.
//
// Undo / redo are local and per person: add (ink, shape, text), remove (eraser, delete, clear page) and change
// (text edits, moves, resizes, style) can each be undone and redone; a restored item keeps its id and author.
//
// A board the local person stops presenting is kept on this device ([startPresenting] resumes it), so a teacher
// who switches to a screen share and back finds their pages again. Viewers drop a board when it stops.
//
// D-093: the page FORMAT (landscape · portrait · continuous) is the presenter's, on the state packet; a change remaps
// every item (board_format.dart) and goes out as a fresh snapshot, so every device rebuilds the same board. On a
// continuous page the presenter's view travels as `vp` ([reportViewport] → [presenterViewport]). [presence] holds the
// name tags of whoever else is drawing, fed by the packets above (the LiveKit sender, never a payload field). A
// finger's stroke is HELD for [kBoardTouchHold] before it goes out ([beginInk] `hold`): a second finger landing in
// that time (a pinch, a two-finger scroll) cancels it without anybody having seen a dot.
library;

import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../annotation/annotation_controller.dart' show AnnotLaserDot, AnnotSend;
import '../annotation/annotation_protocol.dart';
import '../annotation/live_presence.dart';
import 'board_format.dart';
import 'board_protocol.dart';

/// A finger's stroke waits this long before it goes out (a second finger in that time makes it a pinch).
const kBoardTouchHold = Duration(milliseconds: 70);

/// The presenter's continuous view goes out at most this often while it moves.
const kBoardViewportInterval = Duration(milliseconds: 100);

/// And once more, reliably, this long after it stopped moving.
const kBoardViewportSettle = Duration(milliseconds: 350);

/// What a pointer does on the board. [hand] only moves this device's view (D-096): it never changes the board.
enum BoardTool { select, hand, pen, highlighter, line, arrow, rect, ellipse, text, eraser, laser }

extension BoardToolKind on BoardTool {
  BoardShapeKind? get shape => switch (this) {
        BoardTool.line => BoardShapeKind.line,
        BoardTool.arrow => BoardShapeKind.arrow,
        BoardTool.rect => BoardShapeKind.rect,
        BoardTool.ellipse => BoardShapeKind.ellipse,
        _ => null,
      };

  bool get isShape => shape != null;
}

/// The drawable state: notifies only on visible changes (the painter repaints on it alone).
class BoardScene extends ChangeNotifier {
  final Map<String, BoardItem> _items = {}; // insertion order = drawing order
  final Map<String, AnnotLaserDot> _lasers = {};
  BoardBackground _background = BoardBackground.white;
  String _page = '';
  int _revision = 0;

  Iterable<BoardItem> get items => _items.values;
  Iterable<BoardItem> itemsOn(String page) => _items.values.where((i) => i.page == page);
  Iterable<BoardItem> get visibleItems => itemsOn(_page);
  Iterable<AnnotLaserDot> get lasers => _lasers.values;
  BoardBackground get background => _background;
  String get page => _page;
  int get itemCount => _items.length;
  bool get hasLasers => _lasers.isNotEmpty;
  int get revision => _revision;
  BoardItem? item(String id) => _items[id];

  /// The visible page has nothing on it.
  bool get pageEmpty => !visibleItems.any((_) => true);

  void _changed() {
    _revision++;
    notifyListeners();
  }
}

sealed class _Op {
  const _Op();
}

class _Added extends _Op {
  const _Added(this.items);
  final List<BoardItem> items;
}

class _Removed extends _Op {
  const _Removed(this.items);
  final List<BoardItem> items;
}

class _Changed extends _Op {
  const _Changed(this.before, this.after);
  final BoardItem before;
  final BoardItem after;
}

class BoardController extends ChangeNotifier {
  BoardController({
    required this.localIdentity,
    this.send,
    bool Function(String identity)? isHost,
    bool Function(String identity)? mayPresent,
    bool Function(String identity)? studentMayDraw,
    String Function(String identity)? nameOf,
    bool Function()? othersMayDraw,
    bool Function()? showAuthors,
    DateTime Function()? now,
    this.autoFlush = true,
    this.batchInterval = kAnnotBatchInterval,
    this.putInterval = const Duration(milliseconds: 90),
    this.laserTtl = kAnnotLaserTtl,
    String? idPrefix,
    int? color,
  })  : isHost = isHost ?? ((_) => false),
        mayPresent = mayPresent ?? ((_) => true),
        studentMayDraw = studentMayDraw ?? ((_) => false),
        nameOf = nameOf ?? ((id) => id),
        othersMayDraw = othersMayDraw ?? (() => false),
        showAuthors = showAuthors ?? (() => false),
        now = now ?? DateTime.now,
        _idPrefix = idPrefix ?? _randomPrefix(),
        _color = color ?? 0xFF1F2937;

  /// Read every time: known once connected.
  String localIdentity;
  AnnotSend? send;

  /// A host as the SERVER set them up (the room's own check).
  bool Function(String identity) isHost;

  /// May present a board: a host, or someone the server lets share their screen.
  bool Function(String identity) mayPresent;

  /// A student the host allowed to draw (the annotation permission: everyone, or this person).
  bool Function(String identity) studentMayDraw;

  /// A participant's display name (the room: LiveKit's name; a guest's typed name), made safe for the tags.
  String Function(String identity) nameOf;

  /// Someone besides the presenter may draw (the room's permission is open): every drawer's tag shows. Otherwise only
  /// the tags of people who are not the presenter (a co-host) show.
  bool Function() othersMayDraw;

  /// The host's "Show who drew what" (the annotation permission's `au`): an item's author on hover / long press.
  bool Function() showAuthors;

  final DateTime Function() now;

  /// Who else is drawing now (D-093): the name tags.
  late final LivePresence presence = LivePresence(now: now);

  /// The presenter's view of a continuous page (viewers follow it), null when unknown.
  final ValueNotifier<BoardViewportPos?> presenterViewport = ValueNotifier(null);

  /// [nameOf], cleaned (bidi controls out, 24 characters at most).
  String displayName(String identity) => presenceSafeName(nameOf(identity), fallback: identity.isEmpty ? '' : '…');

  /// Whether [identity]'s name tag is shown on this device.
  bool presenceShownFor(String identity) =>
      identity != localIdentity && (othersMayDraw() || identity != _presenter);

  /// Off in tests: packets then wait for [flush] (or the end of a gesture).
  final bool autoFlush;
  final Duration batchInterval;

  /// How often a shape being dragged or a text being typed goes out.
  final Duration putInterval;
  final Duration laserTtl;

  final BoardScene scene = BoardScene();
  final String _idPrefix;
  int _nextId = 0;
  bool _disposed = false;

  // ── The presented board ────────────────────────────────────────────────────
  String? _presenter;
  List<String> _pages = const [];
  bool _needsUpdate = false;
  BoardFormat _format = BoardFormat.landscape;

  /// Who presents the board now (null: no board).
  String? get presenter => _presenter;
  bool get active => _presenter != null;
  bool get isLocalPresenting => _presenter != null && _presenter == localIdentity;
  List<String> get pages => List.unmodifiable(_pages);
  int get pageCount => _pages.length;
  int get pageIndex => math.max(0, _pages.indexOf(scene.page));
  BoardBackground get background => scene.background;

  /// The page format (D-093).
  BoardFormat get format => _format;

  /// The page's width / height (continuous: of its whole length).
  double get aspect => boardFormatAspect(_format);
  bool get isContinuous => _format == BoardFormat.continuous;

  /// The presenter's board uses features this app does not draw: "update the app".
  bool get needsUpdate => _needsUpdate;

  /// The presenter and hosts lead: draw, edit and remove anything, clear a page.
  bool isLead(String identity) => identity.isNotEmpty && (identity == _presenter || isHost(identity));

  bool canDraw(String identity) {
    if (identity.isEmpty || _presenter == null) return false;
    return isLead(identity) || studentMayDraw(identity);
  }

  bool get canDrawLocal => canDraw(localIdentity);
  bool get isLeadLocal => isLead(localIdentity);

  /// The room: the annotation permission changed (who may draw).
  void permissionsChanged() {
    if (!canDrawLocal) _stopLocal();
    _notify();
  }

  // ── Presenting (local) ─────────────────────────────────────────────────────
  ({Map<String, BoardItem> items, List<String> pages, String page, BoardBackground bg, BoardFormat format})? _saved;

  /// Starts presenting (the room checked the share arbiter first). A board this person presented before in this
  /// room comes back (remapped when [format] differs from the one it had); [background] and [format] are the ones
  /// picked now.
  void startPresenting({BoardBackground background = BoardBackground.white, BoardFormat format = BoardFormat.landscape}) {
    final me = localIdentity;
    if (me.isEmpty) return;
    final saved = _saved;
    _saved = null;
    _resetScene();
    if (saved != null && saved.items.isNotEmpty) {
      final items = boardRemapItems(saved.items.values, saved.format, format);
      scene._items.addAll({for (final i in items) i.id: i});
      _pages = List.of(saved.pages);
      scene._page = saved.page;
    } else {
      final first = _newPageId();
      _pages = [first];
      scene._page = first;
    }
    scene._background = background;
    _format = format;
    _presenter = me;
    _needsUpdate = false;
    _undo.clear();
    _redo.clear();
    scene._changed();
    _emitState();
    _notify();
  }

  /// Stops presenting: everyone drops the board; this device keeps it for a later [startPresenting].
  void stopPresenting() {
    if (!isLocalPresenting) return;
    _stopLocal();
    _flushPuts();
    _emit(const BoardOff());
    _saveAndDrop();
    _notify();
  }

  void _saveAndDrop() {
    _saved = (
      items: Map.of(scene._items)..removeWhere((_, v) => v is BoardInk && v.open),
      pages: List.of(_pages),
      page: scene._page,
      bg: scene._background,
      format: _format,
    );
    _presenter = null;
    _resetScene();
  }

  void _resetScene() {
    _current = null;
    _held = false;
    _shapeDraft = null;
    _format = BoardFormat.landscape;
    _textHeights.clear();
    presence.clear();
    presenterViewport.value = null;
    _localViewport = null;
    _vpTimer?.cancel();
    _vpTimer = null;
    _batch.clear();
    _pendingErase.clear();
    _pendingPuts.clear();
    _editing.clear();
    _selected = null;
    scene._items.clear();
    scene._lasers.clear();
    scene._page = '';
    _pages = const [];
    _undo.clear();
    _redo.clear();
    _awaitingSnapshot = false;
    _tombstones.clear();
    _assembler.clear();
    scene._changed();
  }

  void setBackground(BoardBackground b) {
    if (!isLocalPresenting || b == scene._background) return;
    scene._background = b;
    scene._changed();
    _emitState();
    _notify();
  }

  /// The presenter changes the page format: every item (every page) is remapped (board_format.dart: kept in page
  /// widths, scaled down and centred when it no longer fits) and the board goes out again as a snapshot, so every
  /// device rebuilds it the same. Not an undo step: history starts again.
  void setFormat(BoardFormat f) {
    if (!isLocalPresenting || f == _format) return;
    _stopLocal();
    _flushPuts();
    final moved = boardRemapItems(scene._items.values.toList(), _format, f, textHeight: textHeight);
    scene._items
      ..clear()
      ..addAll({for (final i in moved) i.id: i});
    _format = f;
    _textHeights.clear();
    _undo.clear();
    _redo.clear();
    _selected = null;
    _localViewport = null;
    scene._changed();
    sendSnapshot(); // the state (with the format) first, then every item: receivers start the board again
    _notify();
  }

  /// Adds a page after the current one and shows it.
  void addPage() {
    if (!isLocalPresenting || _pages.length >= kBoardMaxPages) return;
    _stopLocal();
    final id = _newPageId();
    final at = pageIndex + 1;
    _pages = [..._pages]..insert(at, id);
    _showPage(id);
  }

  void goToPage(int index) {
    if (!isLocalPresenting || index < 0 || index >= _pages.length || _pages[index] == scene._page) return;
    _stopLocal();
    _showPage(_pages[index]);
  }

  void nextPage() => goToPage(pageIndex + 1);
  void previousPage() => goToPage(pageIndex - 1);

  /// Removes the current page (never the last one); its items go with it everywhere.
  void deletePage() {
    if (!isLocalPresenting || _pages.length < 2) return;
    _stopLocal();
    final gone = scene._page;
    final i = pageIndex;
    _pages = [..._pages]..remove(gone);
    scene._items.removeWhere((_, v) => v.page == gone);
    _undo.clear();
    _redo.clear();
    _showPage(_pages[math.min(i, _pages.length - 1)]);
  }

  void _showPage(String id) {
    scene._page = id;
    _selected = null;
    _localViewport = null;
    scene._changed();
    _emitState();
    _notify();
  }

  String _newPageId() => '${_idPrefix}p${(_nextId++).toRadixString(36)}';
  String _newId() => '$_idPrefix${(_nextId++).toRadixString(36)}';

  void _emitState({List<String>? to}) {
    if (!isLocalPresenting) return;
    _emit(BoardState(background: scene._background, pages: _pages, page: scene._page, format: _format), to: to);
  }

  // ── The presenter's view of a continuous page ──────────────────────────────
  BoardViewportPos? _localViewport;
  DateTime? _vpSentAt;
  Timer? _vpTimer;

  /// What the presenter's own stage shows of a continuous page (null: not reported yet).
  BoardViewportPos? get localViewport => _localViewport;

  /// The presenter's stage reports what it shows of a continuous page: out lossy at most every
  /// [kBoardViewportInterval], and once reliably [kBoardViewportSettle] after it stops moving ([flushViewport]).
  void reportViewport(BoardViewportPos v) {
    if (!isLocalPresenting || !isContinuous || v == _localViewport) return;
    _localViewport = v;
    final t = now();
    if (_vpSentAt == null || t.difference(_vpSentAt!) >= kBoardViewportInterval) {
      _vpSentAt = t;
      _emit(BoardViewport(top: v.top, height: v.height));
    }
    _vpTimer?.cancel();
    _vpTimer = autoFlush ? Timer(kBoardViewportSettle, flushViewport) : null;
  }

  /// The settled view, reliably (the last lossy one may have been lost).
  void flushViewport({List<String>? to}) {
    _vpTimer?.cancel();
    _vpTimer = null;
    final v = _localViewport;
    if (v == null || !isLocalPresenting || !isContinuous) return;
    _emit(BoardViewport(top: v.top, height: v.height, lossy: false), to: to);
  }

  // ── The local tool ─────────────────────────────────────────────────────────
  BoardTool _tool = BoardTool.pen;
  int _color;
  int _thickness = 1;
  int _fontStep = 1;
  bool _drawMode = true;

  BoardTool get tool => _tool;
  int get colorArgb => _color;

  /// 0, 1, 2: thin, medium, thick.
  int get thickness => _thickness;

  /// 0..3: S, M, L, XL ([kBoardFontSizes]).
  int get fontStep => _fontStep;

  /// Thickness and text steps of this format ([kBoardTallStyleScale] on portrait / continuous pages).
  double get styleScale => boardStyleScale(_format);

  /// The font size (page-width fraction) of text step [step] on this format.
  double fontSize(int step) => annotRound(kBoardFontSizes[step.clamp(0, kBoardFontSizes.length - 1)] * styleScale).toDouble();

  /// The board takes the pointer (otherwise taps go to the room: show / hide its controls).
  bool get drawMode => _drawMode && canDrawLocal;

  void setDrawMode(bool on) {
    if (on == _drawMode) return;
    if (!on) _stopLocal();
    _drawMode = on;
    _notify();
  }

  void setTool(BoardTool t) {
    if (t == _tool) return;
    _stopLocal();
    _tool = t;
    if (t != BoardTool.select && t != BoardTool.text) _selected = null;
    _notify();
  }

  /// The colour of what is drawn next — and of the selected shape / text box.
  void setColor(int argb) {
    _color = argb;
    final s = selectedItem;
    if (s is BoardText && s.color != argb) _restyle(s, s.copyWith(color: argb));
    if (s is BoardShape && s.color != argb) _restyle(s, s.copyWith(color: argb));
    _notify();
  }

  void setThickness(int step) {
    _thickness = step.clamp(0, kAnnotPenWidths.length - 1);
    final s = selectedItem;
    if (s is BoardShape) {
      final w = annotRound(kAnnotPenWidths[_thickness] * 1.25 * styleScale).toDouble();
      if (w != s.width) _restyle(s, s.copyWith(width: w));
    }
    _notify();
  }

  void setFontStep(int step) {
    _fontStep = step.clamp(0, kBoardFontSizes.length - 1);
    final s = selectedItem;
    if (s is BoardText && s.size != fontSize(_fontStep)) _restyle(s, s.copyWith(size: fontSize(_fontStep)));
    _notify();
  }

  /// A style change of one item: applied, sent, one undo step.
  void _restyle(BoardItem before, BoardItem after) {
    if (!_mayEdit(localIdentity, before)) return;
    final next = _withRev(after, before.rev + 1);
    if (before is BoardText && before.text.trim().isEmpty && !_sentIds.contains(before.id)) {
      _apply(next); // a fresh, empty box: nothing went out yet, its edit is the undo step
      return;
    }
    _apply(next);
    _queuePut(next, now: true);
    _push(_Changed(before, next));
  }

  // ── Selection (select tool / text tool) ────────────────────────────────────
  String? _selected;

  String? get selectedId => _selected;
  BoardItem? get selectedItem => _selected == null ? null : scene._items[_selected];

  void select(String? id) {
    final it = id == null ? null : scene._items[id];
    final next = it != null && it is! BoardInk && _mayEdit(localIdentity, it) ? id : null;
    if (next == _selected) return;
    _selected = next;
    if (it is BoardText) _fontStep = _nearestFontStep(it.size);
    if (it is BoardText) _color = it.color;
    if (it is BoardShape) _color = it.color;
    _notify();
  }

  int _nearestFontStep(double size) {
    var best = 0;
    for (var i = 1; i < kBoardFontSizes.length; i++) {
      if ((fontSize(i) - size).abs() < (fontSize(best) - size).abs()) best = i;
    }
    return best;
  }

  /// Removes the selected item (one undo step).
  void deleteSelected() {
    final s = selectedItem;
    if (s == null) return;
    _selected = null;
    removeItems([s.id]);
  }

  // ── Ink (pen / highlighter) ────────────────────────────────────────────────
  BoardInk? _current;
  final AnnotPointBatcher _batch = AnnotPointBatcher();
  Timer? _flushTimer;
  DateTime? _lastLaserSent;

  bool get isDrawing => _current != null || _shapeDraft != null;

  /// The stroke in progress has not gone out yet (a finger's first [kBoardTouchHold]).
  bool _held = false;
  DateTime? _heldSince;

  /// A pen / highlighter stroke starts at ([x], [y]) on the visible page. [stylus]: the width follows the pressure.
  /// [hold] (a finger): nothing goes out for [kBoardTouchHold], so a pinch that starts with one finger never shows
  /// anybody a dot ([cancelInk] then sends nothing).
  bool beginInk(double x, double y, {double p = 0.5, bool stylus = false, bool highlighter = false, bool hold = false}) {
    if (!canDrawLocal || scene._items.length >= kBoardMaxItems) return false;
    if (_current != null) endInk();
    final ink = highlighter ? AnnotInk.highlighter : AnnotInk.pen;
    final widths = highlighter ? kAnnotHighlighterWidths : kAnnotPenWidths;
    final pressured = stylus && !highlighter;
    final s = BoardInk(
      id: _newId(),
      author: localIdentity,
      page: scene._page,
      ink: ink,
      color: _color,
      width: annotRound(widths[_thickness] * styleScale).toDouble(),
      points: [AnnotPoint.wire(x, y, pressured ? p : 0.5)],
      pressured: pressured,
    );
    _current = s;
    scene._items[s.id] = s;
    scene._changed();
    if (hold) {
      _held = true;
      _heldSince = now();
      return true;
    }
    _held = false;
    _emit(BoardInkStart(id: s.id, page: s.page, ink: ink, color: s.color, width: s.width, pressured: pressured));
    _batch.add(s.points.first, now());
    _scheduleFlush();
    return true;
  }

  /// The held stroke goes out: its start, then every point so far.
  void _releaseHeld() {
    final s = _current;
    if (!_held || s == null) return;
    _held = false;
    _emit(BoardInkStart(id: s.id, page: s.page, ink: s.ink, color: s.color, width: s.width, pressured: s.pressured));
    for (final pt in s.points) {
      _batch.add(pt, now());
    }
    flush();
  }

  void moveInk(double x, double y, {double p = 0.5}) {
    final s = _current;
    if (s == null || s.points.length >= kAnnotMaxPointsPerStroke) return;
    final pt = AnnotPoint.wire(x, y, s.pressured == true ? p : 0.5);
    final last = s.points.last;
    if (last == pt) return;
    s.points.add(pt);
    s.version++;
    scene._changed();
    if (_held) {
      if (now().difference(_heldSince ?? now()) >= kBoardTouchHold) _releaseHeld();
      return;
    }
    _batch.add(pt, now());
    if (_batch.due(now())) {
      flush();
    } else {
      _scheduleFlush();
    }
  }

  void endInk() {
    final s = _current;
    if (s == null) return;
    _releaseHeld(); // a tap: a dot
    flush();
    _current = null;
    _emit(BoardInkEnd(s.id));
    s.open = false;
    s.version++;
    scene._changed();
    _push(_Added([s]));
    _notify();
  }

  /// Palm rejection: the stroke a touch started was a palm. Removed everywhere, no undo step.
  void cancelInk() {
    final s = _current;
    final held = _held;
    _current = null;
    _held = false;
    _batch.clear();
    if (s == null) return;
    scene._items.remove(s.id);
    scene._changed();
    if (!held) _emit(BoardDelete([s.id])); // a held stroke never went out
    _notify();
  }

  // ── Shapes ─────────────────────────────────────────────────────────────────
  BoardShape? _shapeDraft;

  bool beginShape(BoardShapeKind kind, double x, double y) {
    if (!canDrawLocal || scene._items.length >= kBoardMaxItems) return false;
    final s = BoardShape(
      id: _newId(),
      author: localIdentity,
      page: scene._page,
      kind: kind,
      x1: _c(x),
      y1: _c(y),
      x2: _c(x),
      y2: _c(y),
      color: _color,
      width: annotRound(kAnnotPenWidths[_thickness] * 1.25 * styleScale).toDouble(),
    );
    _shapeDraft = s;
    scene._items[s.id] = s;
    scene._changed();
    return true;
  }

  /// [square]: Shift held (a circle, a square, a 45° line).
  void moveShape(double x, double y, {bool square = false}) {
    final s = _shapeDraft;
    if (s == null) return;
    var nx = _c(x), ny = _c(y);
    if (square) {
      final dx = nx - s.x1, dy = (ny - s.y1) / aspect;
      final m = math.max(dx.abs(), dy.abs());
      nx = _c(s.x1 + m * dx.sign);
      ny = _c(s.y1 + m * dy.sign * aspect);
    }
    final next = s.copyWith(x2: nx, y2: ny, rev: s.rev + 1);
    _shapeDraft = next;
    scene._items[s.id] = next;
    scene._changed();
    if (!next.isTinyAt(aspect)) _queuePut(next);
  }

  /// The shape being dragged is dropped (a second finger came down: a pinch, not a shape).
  void cancelShape() {
    final s = _shapeDraft;
    if (s == null) return;
    _shapeDraft = s.copyWith(x2: s.x1, y2: s.y1);
    endShape();
  }

  void endShape() {
    final s = _shapeDraft;
    if (s == null) return;
    _shapeDraft = null;
    final sent = _sentIds.contains(s.id);
    if (s.isTinyAt(aspect)) {
      scene._items.remove(s.id);
      scene._changed();
      _pendingPuts.remove(s.id);
      if (sent) _emit(BoardDelete([s.id]));
      _notify();
      return;
    }
    _queuePut(s, now: true);
    _push(_Added([s]));
    _notify();
  }

  // ── Text boxes ─────────────────────────────────────────────────────────────
  /// Items being edited (text typed, a drag): their state before the edit, for one undo step at the end.
  final Map<String, BoardItem?> _editing = {};

  /// Ids this device has sent (a fresh empty text box is never sent).
  final Set<String> _sentIds = {};

  /// Places an empty text box with its top-left corner at ([x], [y]) and selects it. Nothing goes out until
  /// it has text. Returns its id (null when the local person may not draw).
  String? createText(double x, double y, {double? boxWidth}) {
    if (!canDrawLocal || scene._items.length >= kBoardMaxItems) return null;
    final w = boxWidth ?? kBoardDefaultTextWidth;
    final t = BoardText(
      id: _newId(),
      author: localIdentity,
      page: scene._page,
      x: _c(math.min(x, 1 - math.min(w, 1))),
      y: _c(y),
      boxWidth: w,
      size: fontSize(_fontStep),
      color: _color,
      text: '',
    );
    scene._items[t.id] = t;
    _editing[t.id] = null; // new: the undo step is "added"
    _selected = t.id;
    scene._changed();
    _notify();
    return t.id;
  }

  /// Starts editing [id] (typing, a drag, a resize): remembers it for one undo step.
  bool beginEdit(String id) {
    final it = scene._items[id];
    if (it == null || it is BoardInk || !_mayEdit(localIdentity, it)) return false;
    _editing.putIfAbsent(id, () => it);
    _selected = id;
    _notify();
    return true;
  }

  bool isEditing(String id) => _editing.containsKey(id);

  /// Live edit of a text box (each keystroke, the drag, the resize handle).
  void updateText(String id, {String? text, double? x, double? y, double? boxWidth}) {
    final it = scene._items[id];
    if (it is! BoardText || !_mayEdit(localIdentity, it)) return;
    _editing.putIfAbsent(id, () => it);
    final next = it.copyWith(
      rev: it.rev + 1,
      text: text == null ? null : (text.length > kBoardMaxText ? text.substring(0, kBoardMaxText) : text),
      x: x == null ? null : _c(x),
      y: y == null ? null : _c(y),
      boxWidth: boxWidth?.clamp(0.06, 1.0).toDouble(),
    );
    scene._items[id] = next;
    scene._changed();
    if (next.text.trim().isNotEmpty || _sentIds.contains(id)) _queuePut(next);
  }

  /// Moves a shape or a text box by ([dx], [dy]) (a drag with the select tool).
  void moveItem(String id, double dx, double dy) {
    final it = scene._items[id];
    if (it == null || it is BoardInk || !_mayEdit(localIdentity, it)) return;
    _editing.putIfAbsent(id, () => it);
    final next = switch (it) {
      BoardText() => it.moved(dx, dy).copyWith(rev: it.rev + 1),
      BoardShape() => it.moved(dx, dy).copyWith(rev: it.rev + 1),
      BoardInk() => it,
    };
    scene._items[id] = next;
    scene._changed();
    if (next is! BoardText || next.text.trim().isNotEmpty || _sentIds.contains(id)) _queuePut(next);
  }

  /// Ends the edit of [id]: an empty text box is removed; otherwise the last state goes out and the edit is one
  /// undo step.
  void endEdit(String id) {
    if (!_editing.containsKey(id)) return;
    final before = _editing.remove(id);
    final it = scene._items[id];
    if (it == null) return;
    if (it is BoardText && it.text.trim().isEmpty) {
      scene._items.remove(id);
      scene._changed();
      _pendingPuts.remove(id);
      if (_sentIds.contains(id)) _emit(BoardDelete([id]));
      if (before != null) _push(_Removed([before]));
      if (_selected == id) _selected = null;
      _notify();
      return;
    }
    _flushPut(id);
    if (before == null) {
      _push(_Added([it]));
    } else if (!_same(before, it)) {
      _push(_Changed(before, it));
    }
    _notify();
  }

  static bool _same(BoardItem a, BoardItem b) {
    if (a is BoardText && b is BoardText) return a.sameAs(b);
    if (a is BoardShape && b is BoardShape) return a.copyWith(rev: 0) == b.copyWith(rev: 0);
    return false;
  }

  /// Ends every edit in progress (the tool changed, the board stopped, a new page).
  void commitEdits() {
    for (final id in _editing.keys.toList()) {
      endEdit(id);
    }
  }

  // ── Eraser, delete, clear ──────────────────────────────────────────────────
  final List<String> _pendingErase = [];
  final List<BoardItem> _erasing = [];

  /// The eraser at ([x], [y]): removes what it touches (anything for a lead, your own otherwise). One undo step
  /// per gesture ([endErase]).
  List<String> eraseAt(double x, double y, {double tolerance = 0.012}) {
    if (!canDrawLocal) return const [];
    final hits = hitTest(x, y, tolerance: tolerance).where((i) => _mayEdit(localIdentity, i)).toList();
    if (hits.isEmpty) return const [];
    for (final it in hits) {
      scene._items.remove(it.id);
      _pendingPuts.remove(it.id);
      _pendingErase.add(it.id);
      _erasing.add(it);
      if (_selected == it.id) _selected = null;
    }
    scene._changed();
    _scheduleFlush();
    _notify();
    return [for (final i in hits) i.id];
  }

  void endErase() {
    if (_pendingErase.isNotEmpty) flush();
    if (_erasing.isNotEmpty) {
      _push(_Removed(List.of(_erasing)));
      _erasing.clear();
      _notify();
    }
  }

  /// Removes [ids] (that this person may remove) everywhere, as one undo step.
  void removeItems(List<String> ids) {
    final gone = <BoardItem>[];
    for (final id in ids) {
      final it = scene._items[id];
      if (it == null || !_mayEdit(localIdentity, it)) continue;
      scene._items.remove(id);
      _pendingPuts.remove(id);
      _editing.remove(id);
      gone.add(it);
    }
    if (gone.isEmpty) return;
    scene._changed();
    _emit(BoardDelete([for (final i in gone) i.id]));
    _push(_Removed(gone));
    _notify();
  }

  /// A lead clears the visible page for everyone (one undo step).
  void clearPage() {
    if (!isLeadLocal) return;
    _stopLocal();
    final page = scene._page;
    final gone = scene.itemsOn(page).toList();
    scene._items.removeWhere((_, v) => v.page == page);
    _selected = null;
    scene._changed();
    _emit(BoardClearPage(page));
    if (gone.isNotEmpty) _push(_Removed(gone));
    _notify();
  }

  /// Items on the visible page under ([x], [y]) within [tolerance] (page widths), topmost first.
  List<BoardItem> hitTest(double x, double y, {double tolerance = 0.012}) {
    final a = aspect;
    final py = y / a;
    final out = <BoardItem>[];
    for (final it in scene.visibleItems.toList().reversed) {
      if (identical(it, _current) || identical(it, _shapeDraft)) continue;
      var hit = false;
      switch (it) {
        case BoardInk():
          final r = tolerance + it.width / 2;
          final pts = it.points;
          if (pts.length == 1) {
            hit = _dist(x, py, pts[0].x, pts[0].y / a) <= r;
          } else {
            for (var i = 1; i < pts.length && !hit; i++) {
              hit = _segDist(x, py, pts[i - 1].x, pts[i - 1].y / a, pts[i].x, pts[i].y / a) <= r;
            }
          }
        case BoardShape():
          hit = _shapeDist(it, x, py, a) <= tolerance + it.width / 2;
        case BoardText():
          final h = textHeight(it);
          hit = x >= it.x - tolerance &&
              x <= it.x + it.boxWidth + tolerance &&
              py >= it.y / a - tolerance &&
              py <= (it.y + h) / a + tolerance;
      }
      if (hit) out.add(it);
    }
    return out;
  }

  /// The topmost shape / text box under ([x], [y]) this person may select.
  BoardItem? selectableAt(double x, double y) {
    for (final it in hitTest(x, y, tolerance: 0.016)) {
      if (it is! BoardInk && _mayEdit(localIdentity, it)) return it;
    }
    return null;
  }

  final Map<String, double> _textHeights = {};

  /// The stage reports a text box's laid-out height (fraction of the page HEIGHT) for hit tests.
  void reportTextHeight(String id, double h) => _textHeights[id] = h;

  /// A text box's height (page height fraction): the laid-out one, else an estimate from its lines.
  double textHeight(BoardText t) =>
      _textHeights[t.id] ?? (math.max(1, '\n'.allMatches(t.text).length + 1) * t.size * 1.45 * aspect);

  /// Who made the item under ([x], [y]) on the visible page (the topmost one), for "Drawn by …".
  BoardItem? itemAt(double x, double y) {
    final hits = hitTest(x, y, tolerance: 0.01);
    return hits.isEmpty ? null : hits.first;
  }

  static double _shapeDist(BoardShape s, double x, double py, double a) {
    final x1 = s.x1, y1 = s.y1 / a, x2 = s.x2, y2 = s.y2 / a;
    switch (s.kind) {
      case BoardShapeKind.line:
      case BoardShapeKind.arrow:
        return _segDist(x, py, x1, y1, x2, y2);
      case BoardShapeKind.rect:
        final l = math.min(x1, x2), r = math.max(x1, x2), t = math.min(y1, y2), b = math.max(y1, y2);
        return [
          _segDist(x, py, l, t, r, t),
          _segDist(x, py, r, t, r, b),
          _segDist(x, py, r, b, l, b),
          _segDist(x, py, l, b, l, t),
        ].reduce(math.min);
      case BoardShapeKind.ellipse:
        final cx = (x1 + x2) / 2, cy = (y1 + y2) / 2;
        final rx = math.max((x2 - x1).abs() / 2, 1e-6), ry = math.max((y2 - y1).abs() / 2, 1e-6);
        final dx = x - cx, dy = py - cy;
        final k = math.sqrt((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry));
        if (k == 0) return math.min(rx, ry);
        // distance along the ray to the outline, scaled to page widths
        final len = math.sqrt(dx * dx + dy * dy);
        return (len - len / k).abs();
    }
  }

  // ── Laser ──────────────────────────────────────────────────────────────────
  void pointLaser(double x, double y) {
    if (!canDrawLocal) return;
    final t = now();
    scene._lasers[localIdentity] = AnnotLaserDot(author: localIdentity, x: _c(x), y: _c(y), at: t);
    scene._changed();
    if (_lastLaserSent != null && t.difference(_lastLaserSent!) < batchInterval) return;
    _lastLaserSent = t;
    _emit(BoardLaser(x: _c(x), y: _c(y)));
  }

  /// Drops laser dots older than [laserTtl]; whether any are left.
  bool pruneLasers() {
    final t = now();
    final before = scene._lasers.length;
    scene._lasers.removeWhere((_, d) => t.difference(d.at) >= laserTtl);
    if (scene._lasers.length != before) scene._changed();
    return scene._lasers.isNotEmpty;
  }

  double laserOpacity(AnnotLaserDot d) {
    final age = now().difference(d.at).inMicroseconds / laserTtl.inMicroseconds;
    if (age <= 0.6) return 1;
    return (1 - (age - 0.6) / 0.4).clamp(0.0, 1.0).toDouble();
  }

  // ── Undo / redo ────────────────────────────────────────────────────────────
  final List<_Op> _undo = [];
  final List<_Op> _redo = [];

  bool get canUndo => _undo.isNotEmpty && canDrawLocal;
  bool get canRedo => _redo.isNotEmpty && canDrawLocal;

  void _push(_Op op) {
    _undo.add(op);
    if (_undo.length > 300) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() {
    if (!canDrawLocal) return;
    _stopLocal();
    while (_undo.isNotEmpty) {
      final op = _undo.removeLast();
      final inverse = _invert(op);
      if (inverse == null) continue; // nothing of it is left to undo (removed by someone else)
      _redo.add(inverse);
      _notify();
      return;
    }
  }

  void redo() {
    if (!canDrawLocal) return;
    _stopLocal();
    while (_redo.isNotEmpty) {
      final op = _redo.removeLast();
      final inverse = _invert(op);
      if (inverse == null) continue;
      _undo.add(inverse);
      _notify();
      return;
    }
  }

  /// Applies the opposite of [op] here and everywhere; returns the op that undoes THAT (null: nothing applied).
  _Op? _invert(_Op op) {
    switch (op) {
      case _Added(:final items):
        final present = [for (final i in items) if (scene._items.containsKey(i.id)) scene._items[i.id]!];
        if (present.isEmpty) return null;
        for (final i in present) {
          scene._items.remove(i.id);
        }
        if (present.any((i) => i.id == _selected)) _selected = null;
        scene._changed();
        _emit(BoardDelete([for (final i in present) i.id]));
        return _Removed(present);
      case _Removed(:final items):
        final back = <BoardItem>[];
        for (final i in items) {
          if (scene._items.containsKey(i.id) || scene._items.length >= kBoardMaxItems) continue;
          if (!_pages.contains(i.page) && isLocalPresenting) continue; // its page was deleted
          final restored = _restore(i);
          back.add(restored);
        }
        if (back.isEmpty) return null;
        scene._changed();
        return _Added(back);
      case _Changed(:final before, :final after):
        final cur = scene._items[after.id];
        if (cur == null) return null;
        final next = _withRev(before, cur.rev + 1);
        _apply(next);
        _queuePut(next, now: true);
        if (next.page != scene._page && isLocalPresenting) _showPage(next.page);
        return _Changed(cur, next);
    }
  }

  /// Puts a removed item back here and everywhere, with its id and author.
  BoardItem _restore(BoardItem i) {
    switch (i) {
      case BoardInk():
        final s = i.copy()..open = false;
        scene._items[s.id] = s;
        final author = s.author == localIdentity ? '' : s.author;
        _emit(BoardInkStart(
            id: s.id, page: s.page, ink: s.ink, color: s.color, width: s.width, pressured: s.pressured, author: author));
        for (var k = 0; k < s.points.length; k += kAnnotMaxPointsPerPacket) {
          _emit(BoardInkPoints(id: s.id, points: s.points.sublist(k, math.min(s.points.length, k + kAnnotMaxPointsPerPacket))));
        }
        _emit(BoardInkEnd(s.id));
        return s;
      case BoardShape():
      case BoardText():
        final next = _withRev(i, i.rev + 1);
        scene._items[next.id] = next;
        _queuePut(next, now: true);
        return next;
    }
  }

  static BoardItem _withRev(BoardItem i, int rev) => switch (i) {
        BoardShape() => i.copyWith(rev: rev),
        BoardText() => i.copyWith(rev: rev),
        BoardInk() => i,
      };

  void _apply(BoardItem i) {
    scene._items[i.id] = i;
    scene._changed();
  }

  bool _mayEdit(String identity, BoardItem it) => isLead(identity) || (it.author == identity && canDraw(identity));

  /// Ends whatever the local pointer is doing.
  void _stopLocal() {
    if (_current != null) endInk();
    if (_shapeDraft != null) endShape();
    if (_erasing.isNotEmpty || _pendingErase.isNotEmpty) endErase();
    commitEdits();
  }

  // ── Late joiners ───────────────────────────────────────────────────────────
  final BoardSnapshotAssembler _assembler = BoardSnapshotAssembler();
  final Set<String> _tombstones = {};
  bool _awaitingSnapshot = false;

  /// On joining (and on reconnect): asks the presenter for the board.
  void requestSnapshot() {
    _awaitingSnapshot = true;
    _tombstones.clear();
    _emit(const BoardSnapshotRequest());
  }

  /// The room: someone connected. The presenter sends them the board.
  void onParticipantJoined(String identity) {
    if (identity == localIdentity || !isLocalPresenting) return;
    sendSnapshot(to: [identity]);
  }

  /// The room: someone left. A presenter who left takes their board with them.
  void participantLeft(String identity) {
    scene._lasers.remove(identity);
    presence.remove(identity);
    if (identity.isNotEmpty && identity == _presenter && !isLocalPresenting) {
      _presenter = null;
      _needsUpdate = false;
      _resetScene();
      _notify();
    }
  }

  /// The board state, then every item (chunked), to [to] (null: everyone).
  void sendSnapshot({List<String>? to}) {
    if (!isLocalPresenting || send == null) return;
    _emitState(to: to);
    final sid = '${_idPrefix}s${(_nextId++).toRadixString(36)}';
    final items = [
      for (final i in scene.items)
        if (!(i is BoardText && i.text.trim().isEmpty)) i,
    ];
    for (final c in BoardCodec.snapshotChunks(items, sid: sid)) {
      _sendRaw(kBoardTopic, c, true, to: to);
    }
    flushViewport(to: to); // a continuous page: where the presenter is
  }

  void _applySnapshot(List<BoardItem> items) {
    _awaitingSnapshot = false;
    var changed = false;
    for (final d in items) {
      if (_tombstones.contains(d.id)) continue;
      final have = scene._items[d.id];
      if (have != null) {
        if (have is BoardInk && d is BoardInk && have.points.length < d.points.length) {
          have.points = List.of(d.points);
          have.open = d.open;
          have.version++;
          changed = true;
        } else if (have.rev < d.rev) {
          scene._items[d.id] = d;
          changed = true;
        }
        continue;
      }
      if (scene._items.length >= kBoardMaxItems) continue;
      scene._items[d.id] = d;
      changed = true;
    }
    _tombstones.clear();
    if (changed) scene._changed();
  }

  // ── Receiving ──────────────────────────────────────────────────────────────

  /// A packet on [kBoardTopic] / [kBoardLaserTopic] from [sender] (LiveKit's identity). Whether it applied.
  bool receive(String topic, List<int> data, {required String? sender}) {
    if (sender == null || sender.isEmpty || sender == localIdentity) return false;
    final m = BoardCodec.decode(data, topic: topic);
    if (m == null) return false;
    final ok = _onMsg(m, sender);
    if (!ok && kDebugMode) log('whiteboard: dropped ${m.runtimeType} from $sender');
    return ok;
  }

  bool _onMsg(BoardMsg m, String sender) {
    switch (m) {
      case BoardState():
        if (!mayPresent(sender)) return false;
        if (_presenter != sender) {
          if (isLocalPresenting) {
            // Someone else took the stage (a host's takeover): keep mine for later, show theirs.
            _stopLocal();
            _saveAndDrop();
          } else {
            _resetScene();
          }
          _presenter = sender;
          _awaitingSnapshot = true;
        } else if (m.format != _format) {
          // The presenter changed the format: their snapshot of the remapped board follows on this ordered channel.
          _stopLocal();
          scene._items.clear();
          _editing.clear();
          _undo.clear();
          _redo.clear();
          _textHeights.clear();
          _tombstones.clear();
          _assembler.clear();
          presence.clear();
          presenterViewport.value = null;
          _awaitingSnapshot = true;
        }
        _format = m.format;
        _needsUpdate = m.featureVersion > kBoardFeatureVersion;
        final removed = _pages.where((p) => !m.pages.contains(p)).toSet();
        _pages = List.of(m.pages);
        if (removed.isNotEmpty) scene._items.removeWhere((_, v) => removed.contains(v.page));
        scene._page = m.page;
        scene._background = m.background;
        if (_selected != null && scene._items[_selected]?.page != m.page) _selected = null;
        scene._changed();
        _notify();
        return true;
      case BoardOff():
        if (sender != _presenter) return false;
        _presenter = null;
        _needsUpdate = false;
        _resetScene();
        _notify();
        return true;
      case BoardInkStart():
        if (!canDraw(sender)) return false;
        final have = scene._items[m.id];
        if (have != null || scene._items.length >= kBoardMaxItems) return false;
        if (scene._items.values.where((i) => i is BoardInk && i.open && i.author == sender).length >= 4) return false;
        final author = m.author.isNotEmpty && isLead(sender) ? m.author : sender;
        _tombstones.remove(m.id);
        scene._items[m.id] = BoardInk(
            id: m.id, author: author, page: m.page, ink: m.ink, color: m.color, width: m.width, pressured: m.pressured);
        _openBy[m.id] = sender;
        scene._changed();
        return true;
      case BoardInkPoints():
        final s = scene._items[m.id];
        if (s is! BoardInk || !s.open || _openBy[m.id] != sender || !canDraw(sender)) return false;
        final room = kAnnotMaxPointsPerStroke - s.points.length;
        if (room <= 0) return false;
        s.points.addAll(m.points.take(room));
        s.version++;
        scene._changed();
        final tip = s.points.last;
        presence.mark(sender, name: displayName(sender), x: tip.x, y: tip.y, page: s.page, color: s.color, active: true);
        return true;
      case BoardInkEnd():
        final s = scene._items[m.id];
        if (s is! BoardInk || !s.open || _openBy[m.id] != sender) return false;
        _openBy.remove(m.id);
        s.open = false;
        s.version++;
        scene._changed();
        presence.end(sender);
        return true;
      case BoardPut():
        if (!canDraw(sender)) return false;
        final it = m.item;
        final have = scene._items[it.id];
        final BoardItem next;
        if (have != null) {
          if (have.runtimeType != it.runtimeType || !_mayEdit(sender, have)) return false;
          if (it.rev <= have.rev) return true; // older than what we have: nothing to do
          next = _withAuthor(it, have.author);
        } else {
          if (scene._items.length >= kBoardMaxItems) return false;
          if (_awaitingSnapshot && _tombstones.contains(it.id)) _tombstones.remove(it.id);
          next = _withAuthor(it, isLead(sender) ? it.author : sender);
        }
        scene._items[it.id] = next;
        if (_selected == it.id && !_editing.containsKey(it.id)) _selected = null;
        scene._changed();
        switch (next) {
          case BoardShape(): // the corner being dragged
            presence.mark(sender, name: displayName(sender), x: next.x2, y: next.y2, page: next.page, color: next.color, active: false);
          case BoardText(): // just after the caret of the box being typed / moved
            final (x, y) = _caretOf(next);
            presence.mark(sender, name: displayName(sender), x: x, y: y, page: next.page, color: next.color, active: false);
          case BoardInk():
            break;
        }
        return true;
      case BoardDelete():
        var any = false;
        for (final id in m.ids) {
          final it = scene._items[id];
          if (_awaitingSnapshot && _tombstones.length < 20000) _tombstones.add(id);
          if (it == null || !(isLead(sender) || it.author == sender)) continue;
          scene._items.remove(id);
          _editing.remove(id);
          if (_selected == id) _selected = null;
          any = true;
        }
        if (any) {
          scene._changed();
          _notify();
        }
        return any;
      case BoardClearPage():
        if (!isLead(sender)) return false;
        scene._items.removeWhere((_, v) => v.page == m.page);
        _editing.removeWhere((id, _) => !scene._items.containsKey(id));
        if (_selected != null && !scene._items.containsKey(_selected)) _selected = null;
        scene._changed();
        _notify();
        return true;
      case BoardSnapshotRequest():
        if (!isLocalPresenting) return false;
        sendSnapshot(to: [sender]);
        return true;
      case BoardSnapshotChunk():
        if (sender != _presenter) return false;
        final items = _assembler.add(sender, m);
        if (items != null) {
          _applySnapshot(items);
          _notify();
        }
        return true;
      case BoardLaser():
        if (!canDraw(sender)) return false;
        scene._lasers[sender] = AnnotLaserDot(author: sender, x: m.x, y: m.y, at: now());
        scene._changed();
        presence.mark(sender, name: displayName(sender), x: m.x, y: m.y, page: scene._page, active: false);
        return true;
      case BoardViewport():
        if (sender != _presenter || !isContinuous) return false;
        presenterViewport.value = BoardViewportPos(m.top, m.height);
        return true;
    }
  }

  /// About where a text box's caret is (the end of its last line; no layout here: ~0.52 em per character), on the
  /// line's baseline — the writer's tag goes just after it.
  (double, double) _caretOf(BoardText t) {
    final lines = t.text.split('\n');
    final full = lines.last.runes.length * t.size * 0.52;
    final wraps = t.boxWidth <= 0 ? 0 : (full / t.boxWidth).floor();
    final rest = math.min(t.boxWidth, full - wraps * t.boxWidth);
    final lineH = t.size * 1.35 * aspect;
    final rows = lines.length - 1 + wraps;
    final rtl = boardTextIsRtl(t.text, fallbackRtl: false);
    final x = rtl ? t.x + t.boxWidth - rest : t.x + rest;
    final y = t.y + rows * lineH + lineH * 0.8;
    return (x.clamp(0.0, 1.0).toDouble(), y.clamp(0.0, 1.0).toDouble());
  }

  /// Who sent the ink stream that is still open (only they may add to it).
  final Map<String, String> _openBy = {};

  static BoardItem _withAuthor(BoardItem i, String author) => switch (i) {
        BoardShape() => BoardShape(
            id: i.id,
            author: author,
            page: i.page,
            rev: i.rev,
            kind: i.kind,
            x1: i.x1,
            y1: i.y1,
            x2: i.x2,
            y2: i.y2,
            color: i.color,
            width: i.width),
        BoardText() => BoardText(
            id: i.id,
            author: author,
            page: i.page,
            rev: i.rev,
            x: i.x,
            y: i.y,
            boxWidth: i.boxWidth,
            size: i.size,
            color: i.color,
            text: i.text),
        BoardInk() => i,
      };

  // ── Sending ────────────────────────────────────────────────────────────────
  final Map<String, BoardItem> _pendingPuts = {};
  Timer? _putTimer;

  void _queuePut(BoardItem i, {bool now = false}) {
    _pendingPuts[i.id] = i;
    if (now) {
      _flushPut(i.id);
      return;
    }
    if (!autoFlush || _putTimer != null) return;
    _putTimer = Timer(putInterval, _flushPuts);
  }

  void _flushPut(String id) {
    final i = _pendingPuts.remove(id);
    if (i == null) return;
    _sentIds.add(id);
    _emit(BoardPut(i));
  }

  void _flushPuts() {
    _putTimer?.cancel();
    _putTimer = null;
    for (final id in _pendingPuts.keys.toList()) {
      _flushPut(id);
    }
  }

  /// Sends whatever waits: ink points, erases, shape / text updates.
  void flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    final s = _current;
    while (_batch.hasPending) {
      final pts = _batch.take();
      if (s != null) _emit(BoardInkPoints(id: s.id, points: pts));
    }
    if (_pendingErase.isNotEmpty) {
      final ids = List.of(_pendingErase);
      _pendingErase.clear();
      _emit(BoardDelete(ids));
    }
    _flushPuts();
  }

  void _scheduleFlush() {
    if (!autoFlush || _flushTimer != null) return;
    _flushTimer = Timer(batchInterval, flush);
  }

  void _emit(BoardMsg m, {List<String>? to}) => _sendRaw(m.topic, BoardCodec.encode(m), m.reliable, to: to);

  void _sendRaw(String topic, List<int> bytes, bool reliable, {List<String>? to}) {
    final cb = send;
    if (cb == null) return;
    try {
      cb(topic, bytes, reliable, to: to).catchError((Object e) {
        if (kDebugMode) log('whiteboard: send failed: $e');
      });
    } catch (e) {
      if (kDebugMode) log('whiteboard: send failed: $e');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _putTimer?.cancel();
    _vpTimer?.cancel();
    scene.dispose();
    presence.dispose();
    presenterViewport.dispose();
    super.dispose();
  }
}

double _c(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0).toDouble();

double _dist(double ax, double ay, double bx, double by) {
  final dx = ax - bx, dy = ay - by;
  return math.sqrt(dx * dx + dy * dy);
}

double _segDist(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final l2 = dx * dx + dy * dy;
  if (l2 == 0) return _dist(px, py, ax, ay);
  final t = (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0);
  return _dist(px, py, ax + dx * t, ay + dy * t);
}

String _randomPrefix() {
  final r = math.Random();
  const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return String.fromCharCodes([for (var i = 0; i < 4; i++) abc.codeUnitAt(r.nextInt(abc.length))]);
}
