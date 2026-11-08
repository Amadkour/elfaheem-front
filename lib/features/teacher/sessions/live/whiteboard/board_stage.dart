// lib/features/teacher/sessions/live/whiteboard/board_stage.dart
//
// The whiteboard on the stage (D-087): the 16:9 page fitted into the space it gets (`contain`), its background,
// ink, shapes, text boxes and laser dots, and — for whoever may draw — the pointer:
//
//   pen / highlighter  a stroke through the annotation ink filter (annotation_ink.dart: One Euro, pressure, palm
//                      rejection as in the annotation layer)
//   line / arrow / rectangle / ellipse   drag from corner to corner (Shift: square / circle / 45°)
//   text               tap on the page: a text box opens there (on the right edge of the tap in Arabic) with the
//                      keyboard; tap a text box: edit it. Type on a phone keyboard or a physical one; the box's
//                      direction follows its first letter (Arabic → right to left). Enter is a new line; Esc,
//                      "Done" or a tap elsewhere ends it.
//   select             tap a shape / text box: selected (frame, Delete, Edit for text, the corner handle sets a text
//                      box's width); drag it: moved. Double-tap a text box: edit it. A drag on empty paper moves the
//                      view (D-096).
//   hand               moves the view only (D-096): one finger, the mouse or the pen drags a continuous page up and
//                      down and a zoomed page around (grab / grabbing cursor). Holding Space does the same with any
//                      tool, the middle mouse button always does, and so does every pointer of whoever is not drawing.
//   eraser             removes what it touches; laser: a fading dot (also on hover with a mouse).
//
// Edge auto-scroll (D-096, board_edge_scroll.dart): a stroke, a shape or a moved selection that comes near an edge of
// the stage scrolls the view that way, faster the closer it gets, while the frame clock runs; the pointer, held
// still, is mapped to the page again every frame (positions are kept in the stage's frame from the pointer's down,
// [_downOrigin]), so the stroke follows without a gap. The presenter's auto-scroll goes out as their view like any
// scroll; a viewer who draws stops following. Tests: test/org/board_edge_scroll_test.dart,
// test/ui/whiteboard_hand_layout_test.dart; renders test/visual/whiteboard_hand_golden_test.dart.
//
// The page is a RepaintBoundary ([pageKey]) without the selection frame or the editor (the board's recording track
// reads it; on a continuous page it is the part on screen). Tests: test/ui/whiteboard_layout_test.dart; renders
// test/visual/whiteboard_golden_test.dart.
//
// Formats (D-093): a landscape / portrait page is fitted (`contain`) and zoomed per device as before; a continuous
// page is a width-filled column ([ContinuousView]) shown down to [boardContinuousExtent] (it grows as people draw
// near its end), scrolled with two fingers, the mouse wheel — or one finger when this person is not drawing or only
// the stylus draws ("Stylus only", draw_input_prefs.dart). Viewers follow the presenter's view (the `vp` packets,
// eased) until they scroll themselves; then "Follow …" snaps back. A rail at the end edge shows where the view is
// (and where the presenter is). Name tags of whoever else draws (presence_tags.dart) sit over the ink; with the host's
// "Show who drew what", the mouse over an item (or a long press when not drawing) shows its author. A finger's stroke
// is held for 70 ms before it goes out, so a pinch never shows anybody a dot.
//
// Growing sideways (D-107): a continuous page also reaches past its column ([boardContinuousSpanX]) — to what is drawn
// there, to where the presenter looks and to where this device's edge auto-scroll took it: a stroke held at the left
// or right edge scrolls that way and the paper grows under it ([ContinuousView.scrolledBy] `grow`), up to
// [kBoardSideMax] widths past each side. The column stays at x 0..1 and the view's sideways position is measured from
// it, so growing (to the left too) never moves a line. The page's layers sit in the shown rect, whose left edge is
// left of the column's once it grew left ([_frame] is that corner; positions inside are `ox + x × width`). A second,
// horizontal rail along the bottom shows where the view is across the page (and where the presenter is); viewers
// follow the presenter sideways too ([boardFollowLeft]).
//
// The rails are scrollbars (D-109, board_scrollbar.dart): a long press on a thumb (a finger or a pen; the mouse just
// presses) grabs it — a tick of haptics, the thumb grows and takes the accent — and dragging it moves the view along
// that axis in proportion to the page; a tap on the track beside the thumb moves a page. Their hit targets are 44 px
// however thin they are drawn. A pointer on a rail is held back from the pen and the view pan until it grabs, taps the
// track, or (a finger or pen that moves first) is handed to them as if it had just come down, so a stroke that starts
// on a rail still draws and a grabbed thumb never does. A viewer who drags a thumb stops following; the presenter's
// view goes out like any scroll. Tests: test/org/board_scrollbar_test.dart, test/ui/whiteboard_scrollbar_layout_test.dart.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart' show EnterSubmits, appText;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import '../annotation/annotation_ink.dart';
import '../annotation/annotation_layer.dart' show kAnnotPalmGuard;
import '../annotation/annotation_toolbar.dart' show AnnotToolButton, annotTypingInField;
import '../annotation/draw_input_prefs.dart';
import '../annotation/presence_tags.dart';
import '../widgets/live_palette.dart';
import 'board_controller.dart';
import 'board_edge_scroll.dart';
import 'board_format.dart';
import 'board_painter.dart';
import 'board_protocol.dart';
import 'board_scrollbar.dart';

/// The page's text style for a box of font size [size] (page-width fraction) on a page [pageWidth] wide.
TextStyle boardTextStyle(BoardText tx, double pageWidth) => TextStyle(
      fontFamily: AppFonts.family,
      fontSize: math.max(1.0, tx.size * pageWidth),
      height: 1.35,
      fontWeight: tx.size >= kBoardFontSizes.last ? FontWeight.w800 : FontWeight.w600,
      color: Color(tx.color),
    );

class WhiteboardStage extends StatefulWidget {
  const WhiteboardStage({
    super.key,
    required this.controller,
    this.pageKey,
    this.railKey,
    this.fallbackRtl = false,
    this.laserColor,
    this.showEmptyHint = true,
    this.presenterName = '',
  });

  final BoardController controller;

  /// "Follow `name`" on a continuous page (empty: "Follow the presenter").
  final String presenterName;

  /// The page's RepaintBoundary (export).
  final GlobalKey? pageKey;

  /// On the vertical rail's drawn strip while it is shown (the room keeps its floating cameras clear of it, D-109).
  final GlobalKey? railKey;

  /// The writer's interface is right to left (Arabic): a text box opens to the left of the tap, an empty box is RTL.
  final bool fallbackRtl;
  final Color? laserColor;

  /// The presenter's empty page says what to do.
  final bool showEmptyHint;

  @override
  State<WhiteboardStage> createState() => _WhiteboardStageState();
}

class _WhiteboardStageState extends State<WhiteboardStage> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) {
    final dt = ((elapsed - _prevTick).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _prevTick = elapsed;
    final lasers = widget.controller.pruneLasers();
    final tags = widget.controller.presence.step();
    final follow = _stepFollow();
    final edge = _stepEdge(dt);
    if (!lasers && !tags && !follow && !edge) _ticker.stop();
  });
  Duration _prevTick = Duration.zero;

  /// Runs the frame clock (lasers, tags, the eased follow, edge auto-scroll).
  void _kick() {
    if (_ticker.isActive) return;
    _prevTick = Duration.zero;
    _ticker.start();
  }

  BoardController get _c => widget.controller;

  /// The page's COORDINATE size on screen (continuous: its whole length) and where its top-left corner is; the drawn
  /// part of it and the stage's size (the last build, or the last auto-scroll step).
  Size _page = Size.zero;
  Offset _origin = Offset.zero;
  Rect _shown = Rect.zero;
  Size _box = Size.zero;

  /// The shown rect's top-left corner on the stage: the frame of the page's layers and its pointer listener (left of
  /// [_origin] once a continuous page grew to the left).
  Offset _frame = Offset.zero;

  /// As far as a continuous page could ever reach sideways (the edge auto-scroll's room to grow, D-107).
  Rect _cap = Rect.zero;

  // pointer
  int? _pointer;
  PointerDeviceKind? _pointerKind;

  /// The page layers' corner ([_frame]) when the drawing pointer went down: its events stay in that frame (the hit
  /// test's), so `localPosition + _downOrigin` is the stage position even after the view moved.
  Offset _downOrigin = Offset.zero;

  // edge auto-scroll (D-096)
  final BoardEdgeScroll _edge = BoardEdgeScroll();
  bool _edgeOn = false;
  Offset? _lastStage;
  double _lastSeconds = 0;
  double _lastPressure = 0.5;
  /// Frame-clock seconds since the pointer last moved: the held point's time. (A wall-clock Stopwatch drifted from
  /// the scroll, which runs on the frame clock: under load the ink filter merged points and the stroke stepped.)
  double _sinceMove = 0;

  // Space held (desktop): any tool pans until it is let go.
  bool _space = false;

  /// The mouse is over an item with the select tool (move cursor; elsewhere: grab).
  bool _hoverItem = false;
  AnnotInkFilter? _ink;
  bool _stylusDown = false;
  DateTime? _stylusUp;
  ({String id, Offset last, Offset start, bool moved})? _drag;
  Offset? _pendingCreate;
  DateTime? _lastTapAt;
  String? _lastTapId;

  // The rails as scrollbars (D-109): the rails at the last build (null: not shown) and the pointer on one.
  BoardRailBox? _vRail, _hRail;
  _RailGrab? _rail;
  Timer? _railTimer;

  /// What the pointer on a rail did down on the board, held back until it is handed over ([_railRelease]).
  ({PointerDownEvent e, Offset frame})? _railDeferredDown;
  PointerDownEvent? _railDeferredView;

  // text editing
  String? _editingId;
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'board.text');

  @override
  void initState() {
    super.initState();
    _listen(_c);
    DrawInputPrefs.stylusOnly.addListener(_onPrefs);
    unawaited(DrawInputPrefs.load());
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// Space held pans with any tool (it only watches the key: a text field still types its space).
  bool _onKey(KeyEvent e) {
    if (e.logicalKey != LogicalKeyboardKey.space) return false;
    final down = e is! KeyUpEvent && !annotTypingInField() && _c.drawMode;
    if (down != _space && mounted) setState(() => _space = down);
    return false;
  }

  /// Space is held now (a key-up lost to another window never leaves it stuck).
  bool get _spaceHeld => _space && HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space);

  void _listen(BoardController c) {
    c.scene.addListener(_onScene);
    c.addListener(_onController);
    c.presence.addListener(_onScene);
    c.presenterViewport.addListener(_onPresenterViewport);
  }

  void _unlisten(BoardController c) {
    c.scene.removeListener(_onScene);
    c.removeListener(_onController);
    c.presence.removeListener(_onScene);
    c.presenterViewport.removeListener(_onPresenterViewport);
  }

  @override
  void didUpdateWidget(WhiteboardStage old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      _unlisten(old.controller);
      _listen(widget.controller);
    }
  }

  @override
  void dispose() {
    _unlisten(_c);
    DrawInputPrefs.stylusOnly.removeListener(_onPrefs);
    HardwareKeyboard.instance.removeHandler(_onKey);
    final id = _editingId;
    if (id != null) _c.endEdit(id);
    _probeTimer?.cancel();
    _offerTimer?.cancel();
    _railTimer?.cancel();
    _ticker.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onScene() {
    if (_c.scene.hasLasers || !_c.presence.isEmpty) _kick();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  // ── Following the presenter (continuous) ───────────────────────────────────
  bool _follow = true;
  double? _followTarget;

  /// Sideways (D-107): the page x (widths) the view's left edge glides to.
  double? _followTargetX;
  double _lastVisible = 0;
  double _lastExtent = 1;

  /// The continuous page's reach sideways at the last build (page widths), and what this device's edge auto-scroll
  /// grew it to (kept while this page is shown).
  double _lastXMin = 0, _lastXMax = 1;
  double _growL = 0, _growR = 1;
  double _lastVisibleW = 1;

  double? _followLeftFor(BoardViewportPos pv) => boardFollowLeft(
      presenter: pv, visibleW: _lastVisibleW, xMin: math.min(_lastXMin, pv.left), xMax: math.max(_lastXMax, pv.right));

  void _onPresenterViewport() {
    if (!mounted || _c.isLocalPresenting || !_c.isContinuous) return;
    final pv = _c.presenterViewport.value;
    if (pv == null) return;
    if (_follow) {
      _followTarget = boardFollowTop(presenter: pv, visible: _lastVisible, extent: math.max(_lastExtent, pv.bottom));
      _followTargetX = _followLeftFor(pv);
      _kick();
    } else {
      setState(() {}); // the rails' presenter marks move
    }
  }

  /// One frame of the eased follow (down and sideways); whether it is still moving.
  bool _stepFollow() {
    if (!_follow || !mounted) return false;
    var moving = false;
    final target = _followTarget;
    if (target != null) {
      final d = target - _scroll;
      if (d.abs() < 1e-5) {
        _followTarget = null;
      } else {
        _scroll += d.abs() < 2e-4 ? d : d * 0.22;
        moving = true;
      }
    }
    final tx = _followTargetX;
    if (tx != null && !_box.isEmpty) {
      final v = _cvNow(_box);
      final d = tx - v.viewLeft;
      final next = v.withViewLeft((d * v.pageWidth).abs() < 0.5 ? tx : v.viewLeft + d * 0.22).panX;
      if ((next - _cpanX).abs() < 0.25) {
        _followTargetX = null; // there (or as near as the page lets it)
        _cpanX = next;
      } else {
        _cpanX = next;
        moving = true;
      }
    }
    if (moving) setState(() {});
    return moving;
  }

  void _followPresenter() {
    final pv = _c.presenterViewport.value;
    setState(() {
      _follow = true;
      if (pv != null) {
        _followTarget = boardFollowTop(presenter: pv, visible: _lastVisible, extent: math.max(_lastExtent, pv.bottom));
        _followTargetX = _followLeftFor(pv);
      }
    });
    _kick();
  }

  /// This viewer moved the view themselves: they stop following until they tap "Follow …".
  void _leaveFollow() {
    if (_c.isLocalPresenting || !_follow) return;
    _follow = false;
    _followTarget = null;
    _followTargetX = null;
  }

  // ── "Drawn by …" ───────────────────────────────────────────────────────────
  ({String author, Offset at, int color})? _probe;
  Timer? _probeTimer;
  Offset? _pressAt;

  bool get _probing => _c.showAuthors() && (!_c.drawMode || _c.tool == BoardTool.select || _c.tool == BoardTool.hand);

  void _probeAt(Offset local, {bool autoHide = false}) {
    final n = _norm(local - _origin);
    final it = !_onPage(n) ? null : _c.itemAt(n.dx, n.dy);
    final color = switch (it) {
      BoardInk() => it.color,
      BoardShape() => it.color,
      BoardText() => it.color,
      null => 0,
    };
    final next = it == null ? null : (author: it.author, at: local, color: color);
    if (next == null && _probe == null) return;
    setState(() => _probe = next);
    _probeTimer?.cancel();
    if (autoHide && next != null) {
      _probeTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _probe = null);
      });
    }
  }

  void _clearProbe() {
    _probeTimer?.cancel();
    _pressAt = null;
    if (_probe != null && mounted) setState(() => _probe = null);
  }

  void _probeDown(PointerDownEvent e) {
    if (_rail != null) return;
    if (!_probing || e.kind == PointerDeviceKind.mouse || (_c.drawMode && _c.tool != BoardTool.hand)) return;
    _pressAt = e.localPosition;
    _probeTimer?.cancel();
    _probeTimer = Timer(const Duration(milliseconds: 450), () {
      final at = _pressAt;
      if (mounted && at != null) _probeAt(at, autoHide: true);
    });
  }

  void _probeMove(PointerMoveEvent e) {
    final at = _pressAt;
    if (at != null && (e.localPosition - at).distance > 10) {
      _pressAt = null;
      if (_probe == null) _probeTimer?.cancel();
    }
  }

  void _probeUp(PointerEvent e) {
    if (_probe == null) _probeTimer?.cancel();
    _pressAt = null;
  }

  // ── "Stylus only?" (once, when a pen first touches the board) ──────────────
  bool _offer = false;
  Timer? _offerTimer;

  void _maybeOfferStylus() {
    if (DrawInputPrefs.offered || DrawInputPrefs.stylusOnly.value || _offer) return;
    DrawInputPrefs.offered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _offer = true);
      _offerTimer = Timer(const Duration(seconds: 9), () {
        if (mounted) setState(() => _offer = false);
      });
    });
  }

  void _answerOffer(bool on) {
    _offerTimer?.cancel();
    setState(() => _offer = false);
    unawaited(DrawInputPrefs.setStylusOnly(on));
  }

  void _onController() {
    // The edit ended elsewhere (a tool change, the item removed, a new page): drop the editor.
    final id = _editingId;
    if (id != null && (!_c.isEditing(id) || _c.scene.item(id) == null)) {
      _editingId = null;
      if (_focus.hasFocus) _focus.unfocus();
    }
    if (!_c.drawMode) _resetPointer();
  }

  void _resetPointer() {
    _pointer = null;
    _pointerKind = null;
    _ink = null;
    _drag = null;
    _pendingCreate = null;
    _edgeOn = false;
    _lastStage = null;
  }

  // ── Geometry ───────────────────────────────────────────────────────────────

  Offset _norm(Offset local) =>
      _page.isEmpty ? Offset.zero : Offset(local.dx / _page.width, local.dy / _page.height);

  /// [n] (page coordinates) is on the drawn paper: the page, or a continuous page's whole reach sideways (D-107).
  bool _onPage(Offset n) {
    final lo = _c.isContinuous ? _lastXMin : 0.0, hi = _c.isContinuous ? _lastXMax : 1.0;
    return n.dx >= lo - 1e-9 && n.dx <= hi + 1e-9 && n.dy >= 0 && n.dy <= 1;
  }

  static bool _isStylus(PointerDeviceKind k) => k == PointerDeviceKind.stylus || k == PointerDeviceKind.invertedStylus;

  /// A stylus is down or just lifted: a touch now is the palm (it neither draws nor scrolls).
  bool get _palmWindow => _stylusDown || (_stylusUp != null && DateTime.now().difference(_stylusUp!) < kAnnotPalmGuard);

  static double _pressure(PointerEvent e) {
    if (!_isStylus(e.kind)) return 0.5;
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0).toDouble();
  }

  static double _seconds(PointerEvent e) => e.timeStamp.inMicroseconds / 1e6;

  /// The drawing pointer's stage position (its events keep the frame of its down, [_downOrigin]).
  Offset _stageOf(PointerEvent e) => e.localPosition + _downOrigin;

  // ── Pointer ────────────────────────────────────────────────────────────────

  /// The hand: the hand tool, or Space held (desktop).
  bool get _handMode => _c.tool == BoardTool.hand || _spaceHeld;

  /// There is something to move: a continuous page, or a zoomed fixed one.
  bool get _pannable => _c.isContinuous || _zoom > 1.01;

  /// A mouse or a pen that moves the view rather than drawing: the middle mouse button always; the primary button /
  /// the pen with the hand, or for whoever is not drawing. (A finger: [_fingerPans].)
  bool _pansWith(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse) {
      if ((e.buttons & kMiddleMouseButton) != 0) return true;
      if ((e.buttons & kPrimaryMouseButton) == 0) return false;
    } else if (!_isStylus(e.kind)) {
      return false;
    }
    return !_c.drawMode || _handMode;
  }

  void _down(PointerDownEvent e, {Offset? frame}) {
    if (!_c.drawMode) return;
    if (e.kind == PointerDeviceKind.mouse && (e.buttons & kPrimaryMouseButton) == 0) return;
    if (_railGrabbed) return; // a thumb is being dragged: nothing draws
    if (_railOwns(e.pointer)) {
      _railDeferredDown = (e: e, frame: _frame);
      return;
    }
    final stylus = _isStylus(e.kind);
    if (stylus) {
      _stylusDown = true;
      DrawInputPrefs.stylusSeen = true;
      if (!_handMode) _maybeOfferStylus();
    }
    // The hand (or Space): the outer listener moves the view; nothing is drawn.
    if (_handMode) return;
    if (!stylus && _palmWindow) return;
    // "Stylus only": a finger scrolls / zooms (the outer listener), it never draws.
    if (e.kind == PointerDeviceKind.touch && DrawInputPrefs.stylusOnly.value) return;
    if (_pointer != null) {
      if (stylus && _pointerKind != null && !_isStylus(_pointerKind!) && _ink != null) {
        _c.cancelInk(); // the touch that was drawing was the palm
        _resetPointer();
      } else {
        return;
      }
    }
    _downOrigin = frame ?? _frame;
    final stage = _stageOf(e);
    final local = stage - _origin; // on the page (x 0 = the column's left edge)
    final n = _norm(local);
    if (!_onPage(n)) return;
    final tool = e.kind == PointerDeviceKind.invertedStylus ? BoardTool.eraser : _c.tool;
    _pointer = e.pointer;
    _pointerKind = e.kind;
    var edge = true; // this gesture scrolls the view at the edges
    switch (tool) {
      case BoardTool.pen:
      case BoardTool.highlighter:
        _endTextEdit();
        final ink = AnnotInkFilter(pressure: stylus);
        final s = ink.start(local.dx, local.dy, _seconds(e), _pressure(e));
        final hold = e.kind == PointerDeviceKind.touch; // a second finger soon after makes it a pinch
        if (_c.beginInk(n.dx, n.dy, p: s.p, stylus: stylus, highlighter: tool == BoardTool.highlighter, hold: hold)) {
          _ink = ink;
        } else {
          _resetPointer();
        }
      case BoardTool.line:
      case BoardTool.arrow:
      case BoardTool.rect:
      case BoardTool.ellipse:
        _endTextEdit();
        _c.select(null);
        if (!_c.beginShape(tool.shape!, n.dx, n.dy)) _resetPointer();
      case BoardTool.eraser:
        _endTextEdit();
        _c.eraseAt(n.dx, n.dy);
      case BoardTool.laser:
        edge = false;
        _c.pointLaser(n.dx, n.dy);
      case BoardTool.hand:
        edge = false;
      case BoardTool.select:
      case BoardTool.text:
        final hit = _c.selectableAt(n.dx, n.dy);
        if (_editingId != null && hit?.id == _editingId) {
          _resetPointer(); // inside the box being edited: the text field places the caret
          return;
        }
        final wasEditing = _editingId != null;
        _endTextEdit();
        if (hit != null) {
          _c.select(hit.id);
          _drag = (id: hit.id, last: n, start: stage, moved: false);
        } else {
          edge = false;
          _c.select(null);
          // A tap beside the box being typed ends it; the next tap opens a new one.
          if (tool == BoardTool.text && !wasEditing) _pendingCreate = n;
          // Select on empty paper: the drag moves the view.
          if (tool == BoardTool.select && _pannable) _beginPan(e.pointer, stage);
        }
    }
    if (_pointer == null) return;
    _lastStage = stage;
    _lastSeconds = _seconds(e);
    _lastPressure = _pressure(e);
    _sinceMove = 0;
    _edgeOn = edge;
    if (edge) _edge.begin(stage, _box);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final stage = _stageOf(e);
    _lastStage = stage;
    _lastSeconds = _seconds(e);
    _lastPressure = _pressure(e);
    _sinceMove = 0;
    _moveAt(stage, _lastSeconds, _lastPressure, e.kind);
    if (_edgeOn && _pointer != null && _edge.track(stage, _box)) _kick();
  }

  /// The drawing pointer is at [stage] (a stage position) — after a move, or held still while the view scrolls.
  void _moveAt(Offset stage, double seconds, double pressure, PointerDeviceKind kind) {
    final local = stage - _origin; // on the page as it is now
    final n = _norm(local);
    final drag = _drag;
    if (drag != null) {
      final moved = drag.moved || (stage - drag.start).distance > 5;
      if (moved) {
        if (!drag.moved) _c.beginEdit(drag.id);
        _c.moveItem(drag.id, n.dx - drag.last.dx, n.dy - drag.last.dy);
        _drag = (id: drag.id, last: n, start: drag.start, moved: true);
      }
      return;
    }
    if (_pendingCreate != null && (n - _pendingCreate!).distance > 0.02) _pendingCreate = null;
    switch (_c.tool) {
      case BoardTool.pen:
      case BoardTool.highlighter:
        final ink = _ink;
        if (ink == null) return;
        final s = ink.add(local.dx, local.dy, seconds, pressure);
        if (s == null) return;
        final q = _norm(Offset(s.x, s.y));
        _c.moveInk(q.dx, q.dy, p: s.p);
      case BoardTool.line:
      case BoardTool.arrow:
      case BoardTool.rect:
      case BoardTool.ellipse:
        _c.moveShape(n.dx, n.dy, square: HardwareKeyboard.instance.isShiftPressed);
      case BoardTool.eraser:
        _c.eraseAt(n.dx, n.dy);
      case BoardTool.laser:
        _c.pointLaser(n.dx, n.dy);
      case BoardTool.select:
      case BoardTool.text:
      case BoardTool.hand:
        break;
    }
    if (kind == PointerDeviceKind.invertedStylus) _c.eraseAt(n.dx, n.dy);
  }

  /// One frame of edge auto-scroll; whether the frame clock must keep running for it.
  bool _stepEdge(double dt) {
    final at = _lastStage;
    if (!_edgeOn || _pointer == null || at == null || !mounted || _box.isEmpty) return false;
    // A continuous page may grow sideways into its cap (D-107); down, it grows under the stroke (D-093).
    final room = _c.isContinuous && !_cap.isEmpty
        ? boardScrollRoom(Rect.fromLTRB(_cap.left, _shown.top, _cap.right, _shown.bottom), _box)
        : boardScrollRoom(_shown, _box);
    final v = _edge.velocity(at, _box, room: room, dt: dt);
    if (v == Offset.zero) return _edge.inZone(at, _box);
    if (dt <= 0) return true;
    _scrollViewBy(v * dt);
    // The pointer is held where it is: it is over another point of the page now.
    _sinceMove += dt;
    _moveAt(at, _lastSeconds + _sinceMove, _lastPressure, _pointerKind ?? PointerDeviceKind.touch);
    return true;
  }

  /// Moves the view by [d] stage pixels (positive: further right / down the page) and puts the page where it now is
  /// at once (the next build lays it out the same), so the next pointer position maps onto the moved page.
  void _scrollViewBy(Offset d) {
    if (_c.isContinuous) {
      _leaveFollow();
      final v = _cvNow(_box).scrolledBy(d.dx, d.dy, grow: true);
      _growL = math.min(_growL, v.xMin);
      _growR = math.max(_growR, v.xMax);
      _lastXMin = v.xMin;
      _lastXMax = v.xMax;
      _scroll = v.scroll;
      _cpanX = v.panX;
      _origin = v.pageRect.topLeft;
      _page = v.pageRect.size;
      _shown = v.shownRect;
      _frame = _shown.topLeft;
      _cap = v.capRect;
    } else {
      _pan -= d;
      final r = _pageRect(_box);
      _origin = r.topLeft;
      _page = r.size;
      _shown = r;
      _frame = r.topLeft;
    }
    setState(() {});
  }

  void _hover(PointerHoverEvent e) {
    if (!_c.drawMode || _pointer != null) return;
    final n = _norm(e.localPosition + _frame - _origin);
    final inside = _onPage(n);
    if (_c.tool == BoardTool.select) {
      final over = inside && _c.selectableAt(n.dx, n.dy) != null;
      if (over != _hoverItem) setState(() => _hoverItem = over);
      return;
    }
    if (_c.tool != BoardTool.laser || !inside) return;
    _c.pointLaser(n.dx, n.dy);
  }

  void _up(PointerEvent e) {
    if (_isStylus(e.kind)) {
      _stylusDown = false;
      _stylusUp = DateTime.now();
    }
    if (e.pointer != _pointer) return;
    final cancelled = e is PointerCancelEvent;
    final drag = _drag;
    final create = _pendingCreate;
    final ink = _ink;
    final local = _stageOf(e) - _origin;
    _resetPointer();
    if (drag != null) {
      if (drag.moved) {
        _c.endEdit(drag.id);
      } else if (!cancelled) {
        final it = _c.scene.item(drag.id);
        final now = DateTime.now();
        final doubleTap = _lastTapId == drag.id && _lastTapAt != null && now.difference(_lastTapAt!) < const Duration(milliseconds: 400);
        _lastTapAt = now;
        _lastTapId = drag.id;
        if (it is BoardText && (_c.tool == BoardTool.text || doubleTap)) _startTextEdit(it.id);
      }
      return;
    }
    if (create != null && !cancelled) {
      final w = kBoardDefaultTextWidth;
      // On the paper there is: the column, or a continuous page's reach (a box never widens the page by itself).
      final lo = _c.isContinuous ? _lastXMin : 0.0, hi = _c.isContinuous ? _lastXMax : 1.0;
      final x = (widget.fallbackRtl ? create.dx - w : create.dx).clamp(lo, math.max(lo, hi - w)).toDouble();
      final lineH = _c.fontSize(_c.fontStep) * 1.35 * _c.aspect;
      final id = _c.createText(x, (create.dy - lineH / 2).clamp(0.0, 1.0).toDouble(), boxWidth: w);
      if (id != null) _startTextEdit(id, fresh: true);
      return;
    }
    switch (_c.tool) {
      case BoardTool.pen:
      case BoardTool.highlighter:
        if (ink != null && e is PointerUpEvent) {
          final last = ink.finish(local.dx, local.dy);
          if (last != null) {
            final q = _norm(Offset(last.x, last.y));
            _c.moveInk(q.dx, q.dy, p: last.p);
          }
        }
        _c.endInk();
      case BoardTool.line:
      case BoardTool.arrow:
      case BoardTool.rect:
      case BoardTool.ellipse:
        _c.endShape();
      case BoardTool.eraser:
        _c.endErase();
      case BoardTool.laser:
      case BoardTool.select:
      case BoardTool.text:
      case BoardTool.hand:
        break;
    }
    if (e.kind == PointerDeviceKind.invertedStylus) _c.endErase();
  }

  // ── Text editing ───────────────────────────────────────────────────────────

  void _startTextEdit(String id, {bool fresh = false}) {
    final it = _c.scene.item(id);
    if (it is! BoardText) return;
    if (!fresh && !_c.beginEdit(id)) return;
    setState(() {
      _editingId = id;
      _text.value = TextEditingValue(text: it.text, selection: TextSelection.collapsed(offset: it.text.length));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingId == id) _focus.requestFocus();
    });
  }

  void _endTextEdit() {
    final id = _editingId;
    if (id == null) return;
    _editingId = null;
    _c.endEdit(id);
    if (_focus.hasFocus) _focus.unfocus();
    if (mounted) setState(() {});
  }

  KeyEventResult _onEditorKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      _endTextEdit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  BoardFormat? _lastFormat;
  String? _lastPage;

  /// A new format or a new page starts the view again (zoom, scroll).
  void _resetViewFor(BoardFormat f, String page) {
    if (_lastFormat == f && _lastPage == page) return;
    final formatChanged = _lastFormat != null && _lastFormat != f;
    final pageChanged = _lastPage != null && _lastPage != page;
    _lastFormat = f;
    _lastPage = page;
    if (formatChanged) {
      _zoom = 1;
      _pan = Offset.zero;
    }
    if (formatChanged || pageChanged) {
      _scroll = 0;
      _cpanX = 0;
      _follow = true;
      _followTarget = null;
      _followTargetX = null;
      _followedOnce = false;
      _growL = _lastXMin = 0;
      _growR = _lastXMax = 1;
    }
  }

  /// The first follow of this page was applied (later ones glide, [_stepFollow]).
  bool _followedOnce = false;

  final Expando<({int n, double bottom})> _inkBottoms = Expando('board.ink.bottom');

  /// The lowest content of the visible page (page fraction), cached per ink by its point count.
  double _contentBottom() {
    final a = _c.aspect;
    var bottom = 0.0;
    for (final it in _c.scene.visibleItems) {
      double b;
      if (it is BoardInk) {
        final hit = _inkBottoms[it];
        if (hit != null && hit.n == it.points.length) {
          b = hit.bottom;
        } else {
          b = boardContentBottom([it], aspect: a);
          _inkBottoms[it] = (n: it.points.length, bottom: b);
        }
      } else {
        b = boardContentBottom([it], aspect: a, textHeight: _c.textHeight);
      }
      if (b > bottom) bottom = b;
    }
    return bottom;
  }

  final Expando<({int n, double lo, double hi})> _inkSpans = Expando('board.ink.span');

  /// The leftmost and rightmost content of the visible page (page widths), cached per ink by its point count.
  (double, double)? _contentSpanX() {
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final it in _c.scene.visibleItems) {
      double a, b;
      if (it is BoardInk) {
        final hit = _inkSpans[it];
        if (hit != null && hit.n == it.points.length) {
          (a, b) = (hit.lo, hit.hi);
        } else {
          final s = boardContentSpanX([it]);
          if (s == null) continue;
          (a, b) = s;
          _inkSpans[it] = (n: it.points.length, lo: a, hi: b);
        }
      } else {
        final s = boardContentSpanX([it]);
        if (s == null) continue;
        (a, b) = s;
      }
      if (a < lo) lo = a;
      if (b > hi) hi = b;
    }
    return lo <= hi ? (lo, hi) : null;
  }

  /// This device's view of the continuous page, kept inside it (the extent follows the content and the presenter,
  /// down and — D-107 — sideways).
  ContinuousView _continuousView(Size size) {
    final base = ContinuousView(box: size, zoom: _zoom, scroll: _scroll, panX: _cpanX, xMin: _lastXMin, xMax: _lastXMax);
    final pv = _c.isLocalPresenting ? null : _c.presenterViewport.value;
    final extent = boardContinuousExtent(contentBottom: _contentBottom(), visible: base.visible, presenterBottom: pv?.bottom ?? 0);
    final (xMin, xMax) = boardContinuousSpanX(content: _contentSpanX(), presenter: pv, grown: (_growL, _growR));
    var start = base.copyWith(extent: extent, xMin: xMin, xMax: xMax);
    if (pv != null && _follow && !_followedOnce) {
      // A viewer who arrives (or a new page) starts where the presenter is.
      _followedOnce = true;
      start = start.copyWith(scroll: boardFollowTop(presenter: pv, visible: base.visible, extent: extent));
      final left = boardFollowLeft(presenter: pv, visibleW: start.visibleW, xMin: xMin, xMax: xMax);
      if (left != null) start = start.withViewLeft(left);
    }
    final v = start.clamped();
    _scroll = v.scroll;
    _cpanX = v.panX;
    _lastVisible = v.visible;
    _lastVisibleW = v.visibleW;
    _lastExtent = extent;
    _lastXMin = xMin;
    _lastXMax = xMax;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);
    final laser = widget.laserColor ?? context.colors.danger;
    return ListenableBuilder(
      listenable: Listenable.merge([_c, _c.scene]),
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        final size = Size(box.maxWidth.isFinite ? box.maxWidth : 0, box.maxHeight.isFinite ? box.maxHeight : 0);
        final scene = _c.scene;
        _resetViewFor(_c.format, scene.page);
        final cont = _c.isContinuous;
        ContinuousView? cv;
        final Rect page; // the page's coordinate rect on screen (continuous: its whole length)
        final Rect shown; // the part that is drawn (continuous: down to the extent)
        if (cont) {
          cv = _continuousView(size);
          page = cv.pageRect;
          shown = cv.shownRect;
        } else {
          page = _pageRect(size);
          shown = page;
        }
        _page = page.size;
        _origin = page.topLeft;
        _shown = shown;
        _frame = shown.topLeft;
        _cap = cv?.capRect ?? Rect.zero;
        _box = size;
        final presenting = _c.isLocalPresenting;
        if (cont && presenting) {
          final vp = cv!.viewport;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _c.reportViewport(vp);
          });
        }
        final texts = scene.visibleItems.whereType<BoardText>().toList();
        final pw = page.width, ph = page.height;
        final draw = _c.drawMode;
        final screen = Offset.zero & size;
        final vis = shown.intersect(screen);
        // The visible part of the page, in the page's own coordinates (the empty hint, the tags, the rail).
        final visLocal = vis.isEmpty ? Rect.zero : vis.shift(-shown.topLeft);
        // Where the column's left edge (x 0) is in the shown rect: right of its left edge once it grew left (D-107).
        final ox = page.left - shown.left;
        final sideRail = cont && cv!.xMax - cv.xMin > cv.visibleW + 1e-3 && !vis.isEmpty;
        // The rails (D-109): where they are drawn and what they show, for the painting and for the pointer.
        final rtl = Directionality.of(context) == TextDirection.rtl;
        BoardRailBox? vRail, hRail;
        if (cont && !vis.isEmpty) {
          final r = Rect.fromLTWH(
              _railLeft(vis, size.width, rtl), vis.top + 10, 6, math.max(0.0, vis.height - (sideRail ? 30 : 20)));
          vRail = BoardRailBox(
            rect: r,
            vertical: true,
            metrics: BoardRailMetrics(
                track: r.height, lo: 0, hi: cv!.extent, start: cv.scroll, length: math.min(cv.visible, cv.extent),
                minThumb: _railLook.minThumb, hit: _railLook.hit),
          );
          if (!vRail.metrics.scrollable) vRail = null;
        }
        // Across the page (D-107): once it reaches past what one screen shows. Page x runs left to right in every
        // language, so this rail is never mirrored.
        if (sideRail) {
          final r = Rect.fromLTWH(vis.left + (rtl ? 26 : 12), vis.bottom - 12, math.max(0.0, vis.width - 38), 6);
          hRail = BoardRailBox(
            rect: r,
            vertical: false,
            metrics: BoardRailMetrics(
                track: r.width, lo: cv.xMin, hi: cv.xMax, start: cv.viewLeft, length: cv.visibleW,
                minThumb: _railLook.minThumb, hit: _railLook.hit),
          );
          if (!hRail.metrics.scrollable) hRail = null;
        }
        _vRail = vRail;
        _hRail = hRail;
        final grab = _rail;
        final pvShown = presenting ? null : _c.presenterViewport.value;

        final content = Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned.fill(
              child: CustomPaint(painter: BoardBackgroundPainter(scene.background, unit: cont ? pw : null, originX: ox))),
          Positioned.fill(
            child: CustomPaint(
              isComplex: true,
              painter: BoardItemsPainter(
                items: () => scene.visibleItems,
                lasers: () => const [],
                laserColor: laser,
                laserOpacity: _c.laserOpacity,
                coordSize: cont ? page.size : null,
                coordOrigin: Offset(ox, 0),
                repaint: scene,
              ),
            ),
          ),
          for (final tx in texts)
            if (tx.id != _editingId)
              Positioned(
                key: ValueKey('board.text.${tx.id}'),
                left: ox + tx.x * pw,
                top: tx.y * ph,
                width: math.max(8, tx.boxWidth * pw),
                child: _textView(tx, pw, ph),
              ),
        ]);

        const radius = 12.0;
        final card = BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [BoxShadow(color: LivePalette.shade(0.45), blurRadius: 30, offset: const Offset(0, 12))],
        );
        final List<Widget> pageLayers;
        if (!cont) {
          pageLayers = [
            if (!page.isEmpty)
              Positioned.fromRect(
                rect: page,
                child: DecoratedBox(
                  decoration: card,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: RepaintBoundary(key: widget.pageKey, child: content),
                  ),
                ),
              ),
          ];
        } else {
          // The page card down to its extent; the boundary (the recording track) is the part on screen.
          pageLayers = [
            if (!shown.isEmpty) Positioned.fromRect(rect: shown, child: DecoratedBox(decoration: card)),
            if (!vis.isEmpty)
              Positioned.fromRect(
                rect: vis,
                child: RepaintBoundary(
                  key: widget.pageKey,
                  child: ClipRect(
                    child: Stack(clipBehavior: Clip.none, children: [
                      Positioned(
                        left: shown.left - vis.left,
                        top: shown.top - vis.top,
                        width: shown.width,
                        height: shown.height,
                        child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: content),
                      ),
                    ]),
                  ),
                ),
              ),
          ];
        }

        final selected = _c.selectedItem;
        final probe = _probe;
        final stage = Stack(fit: StackFit.expand, children: [
          ...pageLayers,
          if (!shown.isEmpty)
            Positioned.fromRect(
              rect: shown,
              child: Semantics(
                container: true,
                label: draw ? t('مساحة الرسم على السبورة', 'Whiteboard drawing area') : t('السبورة البيضاء', 'Whiteboard'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: Stack(clipBehavior: Clip.none, children: [
                    // Laser dots above the text boxes.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: BoardItemsPainter(
                            items: () => const [],
                            lasers: () => scene.lasers,
                            laserColor: laser,
                            laserOpacity: _c.laserOpacity,
                            coordSize: cont ? page.size : null,
                            coordOrigin: Offset(ox, 0),
                            repaint: scene,
                          ),
                        ),
                      ),
                    ),
                    if (widget.showEmptyHint && presenting && scene.pageEmpty && _editingId == null && !visLocal.isEmpty)
                      Positioned.fromRect(
                        rect: cont ? Rect.fromLTWH(visLocal.left, visLocal.top, visLocal.width, math.min(visLocal.height, 260)) : visLocal,
                        child: IgnorePointer(child: _EmptyHint(dark: boardIsDark(scene.background), width: pw)),
                      ),
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !draw,
                        child: GestureDetector(
                          // Taps on the page while drawing stay here (the room would show / hide its controls).
                          behavior: HitTestBehavior.translucent,
                          onTap: draw ? () {} : null,
                          child: Listener(
                            behavior: draw ? HitTestBehavior.opaque : HitTestBehavior.translucent,
                            onPointerDown: _down,
                            onPointerMove: _move,
                            onPointerHover: _hover,
                            onPointerUp: _up,
                            onPointerCancel: _up,
                            child: MouseRegion(cursor: draw ? _drawCursor() : MouseCursor.defer, child: const SizedBox.expand()),
                          ),
                        ),
                      ),
                    ),
                    // Whoever else is drawing: their name follows their pen.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: PresenceTagsPainter(
                            presence: _c.presence,
                            marks: () => _c.presence.on(scene.page),
                            visible: (m) => _c.presenceShownFor(m.identity),
                            toLocal: (x, y) => Offset(ox + x * pw, y * ph),
                            bounds: (_) => visLocal,
                            fallbackRtl: widget.fallbackRtl,
                          ),
                        ),
                      ),
                    ),
                    if (_editingId != null) _editor(pw, ph, ox),
                    if (selected != null && draw) ..._selection(selected, pw, ph, ox, shown.width),
                  ]),
                ),
              ),
            ),
          if (_c.needsUpdate)
            Positioned.fromRect(rect: page.isEmpty || cont ? screen : page, child: const _NeedsUpdate()),
          if (vRail != null)
            _railView(
              vRail,
              key: const ValueKey('board.rail'),
              outer: widget.railKey,
              presenter: pvShown == null ? null : (pvShown.top, pvShown.height),
              grabbed: grab != null && grab.grabbed && grab.vertical,
            ),
          if (hRail != null)
            _railView(
              hRail,
              key: const ValueKey('board.side_rail'),
              presenter: pvShown == null || pvShown.width <= 0 ? null : (pvShown.left, pvShown.width),
              grabbed: grab != null && grab.grabbed && !grab.vertical,
            ),
          if (cont && !presenting && !_follow && _c.presenterViewport.value != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: sideRail ? 26 : 14,
              child: Center(child: BoardFollowButton(name: widget.presenterName, onTap: _followPresenter)),
            ),
          if (_offer)
            Positioned(
              left: 8,
              right: 8,
              top: 10,
              child: Center(child: BoardStylusOffer(onYes: () => _answerOffer(true), onNo: () => _answerOffer(false))),
            ),
          if (probe != null && _probing)
            Positioned(
              left: authorLabelOffset(probe.at, screen).dx,
              top: authorLabelOffset(probe.at, screen).dy,
              child: AuthorLabelChip(
                name: _c.displayName(probe.author),
                mine: probe.author == _c.localIdentity,
                color: Color(probe.color),
              ),
            ),
          if (_zoom > 1.01)
            PositionedDirectional(
              top: 8,
              end: cont ? 16 : 8,
              child: _ZoomChip(percent: (_zoom * 100).round(), onReset: _resetZoom),
            ),
          // The rails' pointer (D-109): hit first, translucent, so whatever is below still gets every event.
          if (vRail != null || hRail != null || grab != null)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _railDown,
                onPointerMove: _railMove,
                onPointerUp: _railUp,
                onPointerCancel: _railUp,
              ),
            ),
        ]);
        // Pinch (two fingers) / Ctrl + wheel zooms this device's view only; two fingers (or the wheel) pan it; a
        // continuous page scrolls with them too — and with one finger, the mouse or the pen with the hand (D-096), when
        // this person is not drawing, or with Space held / the middle mouse button.
        return ClipRect(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) {
              _zoomDown(e, size);
              _probeDown(e);
            },
            onPointerMove: (e) {
              _zoomMove(e, size);
              _probeMove(e);
            },
            onPointerUp: (e) {
              _zoomUp(e);
              _probeUp(e);
            },
            onPointerCancel: (e) {
              _zoomUp(e);
              _probeUp(e);
            },
            onPointerHover: (e) {
              if (_probing && e.kind == PointerDeviceKind.mouse) _probeAt(e.localPosition);
            },
            onPointerSignal: (e) => _zoomSignal(e, size),
            child: MouseRegion(opaque: false, cursor: _viewCursor(), onExit: (_) => _clearProbe(), child: stage),
          ),
        );
      }),
    );
  }

  // ── The rails as scrollbars (D-109) ────────────────────────────────────────

  bool _railOwns(int pointer) => _rail?.pointer == pointer;

  /// D-306: the last pointer's kind (null: none yet) — a finger or a pen gets the big thumb; before any pointer,
  /// a phone / tablet does.
  PointerDeviceKind? _railKind;

  bool get _railTouch {
    final k = _railKind;
    if (k == null) {
      final p = defaultTargetPlatform;
      return p == TargetPlatform.android || p == TargetPlatform.iOS;
    }
    return k != PointerDeviceKind.mouse && k != PointerDeviceKind.trackpad;
  }

  BoardRailLook get _railLook => BoardRailLook.of(touch: _railTouch);
  bool get _railGrabbed => _rail?.grabbed ?? false;

  /// The drawn rail and, over its thumb, the grab cursor (translucent: it takes nothing from the board).
  Widget _railView(BoardRailBox r, {required Key key, GlobalKey? outer, (double, double)? presenter, bool grabbed = false}) {
    final box = _railLook.box;
    final c = r.rect.center;
    final at = r.vertical
        ? Rect.fromLTWH(c.dx - box / 2, r.rect.top, box, r.rect.height)
        : Rect.fromLTWH(r.rect.left, c.dy - box / 2, r.rect.width, box);
    return Positioned.fromRect(
      rect: at,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: IgnorePointer(
            key: outer,
            child: BoardScrollRail(
              key: key,
              vertical: r.vertical,
              lo: r.metrics.lo,
              hi: r.metrics.hi,
              start: r.metrics.start,
              length: r.metrics.length,
              presenter: presenter,
              grabbed: grabbed,
              look: _railLook,
            ),
          ),
        ),
        Positioned.fromRect(
          rect: r.thumbHitRect.shift(-at.topLeft),
          child: MouseRegion(
            opaque: false,
            hitTestBehavior: HitTestBehavior.translucent,
            cursor: grabbed ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
          ),
        ),
      ]),
    );
  }

  /// A pointer came down on the stage: on a rail, the rail holds it — a mouse grabs the thumb (or moves a page from
  /// the track) at once; a finger or a pen grabs the thumb after a long press (on the track beside it, the thumb
  /// first jumps under the finger: the thumb shrinks as the page grows, so a press just off it still takes it),
  /// moves a page with a tap on the track, and is handed back to the board when it moves first.
  void _railDown(PointerDownEvent e) {
    if (_railKind != e.kind) {
      final was = _railTouch;
      _railKind = e.kind;
      if (was != _railTouch && mounted) setState(() {}); // the rail's look follows the hand (D-306)
    }
    if (_rail != null || _pointer != null || _viewPan != null || _pinch != null || !mounted) return;
    final mouse = e.kind == PointerDeviceKind.mouse;
    if (mouse && (e.buttons & kPrimaryMouseButton) == 0) return;
    if (e.kind == PointerDeviceKind.touch && (_touches.isNotEmpty || _palmWindow)) return;
    final hit = boardRailHit([_vRail, _hRail], e.localPosition);
    if (hit == null) return;
    final g = _RailGrab(pointer: e.pointer, kind: e.kind, vertical: hit.rail.vertical, part: hit.part, down: e.localPosition);
    _rail = g;
    if (mouse) {
      if (hit.part == BoardRailPart.thumb) {
        _railGrab();
      } else {
        _railPage(hit.rail, e.localPosition);
      }
      return;
    }
    _railTimer = Timer(kLongPressTimeout, () {
      if (!mounted || !identical(_rail, g) || g.grabbed) return;
      unawaited(HapticFeedback.mediumImpact());
      if (g.part == BoardRailPart.track) {
        final r = g.vertical ? _vRail : _hRail;
        if (r == null) return;
        final m = r.metrics;
        final thumb = (r.along(g.down) - m.thumbLength / 2).clamp(0.0, m.travel).toDouble();
        _railApply(g.vertical, m.startForThumb(thumb));
        _railGrab(thumb0: thumb);
      } else {
        _railGrab();
      }
    });
  }

  /// The pointer on the rail takes the thumb: from now on its moves move the view.
  void _railGrab({double? thumb0}) {
    final g = _rail;
    if (g == null) return;
    final r = g.vertical ? _vRail : _hRail;
    if (r == null) {
      _railEnd();
      return;
    }
    _railTimer?.cancel();
    _probeTimer?.cancel();
    _pressAt = null;
    _railDeferredDown = null;
    _railDeferredView = null;
    setState(() {
      g.grabbed = true;
      g.thumb0 = thumb0 ?? r.metrics.thumbStart;
    });
  }

  void _railMove(PointerMoveEvent e) {
    final g = _rail;
    if (g == null || g.pointer != e.pointer) return;
    if (!g.grabbed) {
      // A finger or a pen that moves before the long press draws / pans as if it had just come down.
      if (g.kind != PointerDeviceKind.mouse && (e.localPosition - g.down).distance > kTouchSlop) _railRelease();
      return;
    }
    final r = g.vertical ? _vRail : _hRail;
    if (r == null || _box.isEmpty) return;
    final d = e.localPosition - g.down;
    _railApply(g.vertical, r.metrics.startForThumb(g.thumb0 + (g.vertical ? d.dy : d.dx)));
  }

  void _railUp(PointerEvent e) {
    final g = _rail;
    if (g == null || g.pointer != e.pointer) return;
    if (!g.grabbed && e is PointerUpEvent && g.kind != PointerDeviceKind.mouse) {
      if (g.part == BoardRailPart.track) {
        // A tap on the track: a page that way (the tap is the rail's).
        final r = g.vertical ? _vRail : _hRail;
        _railEnd();
        if (r != null) _railPage(r, g.down);
      } else {
        _railRelease(); // a tap on the thumb is the board's (a dot, a text box)
      }
      return;
    }
    _railEnd();
  }

  /// The view moved by the rail to [to] (its start on that axis: page fraction down, page widths across).
  void _railApply(bool vertical, double to) {
    if (_box.isEmpty || !_c.isContinuous) return;
    _leaveFollow();
    final v = _cvNow(_box);
    setState(() {
      if (vertical) {
        _scroll = v.copyWith(scroll: to).clamped().scroll;
      } else {
        _cpanX = v.withViewLeft(to).panX;
      }
    });
  }

  /// A tap at [at] (stage) on [r]'s track: a page towards it.
  void _railPage(BoardRailBox r, Offset at) {
    final to = r.metrics.paged(r.along(at));
    if (to != null) _railApply(r.vertical, to);
  }

  /// The rail lets go of its pointer (what it held back is dropped).
  void _railEnd() {
    final g = _rail;
    _railTimer?.cancel();
    _railTimer = null;
    _rail = null;
    _railDeferredDown = null;
    _railDeferredView = null;
    if (g != null && g.grabbed && mounted) setState(() {});
  }

  /// The rail hands its pointer to the board as if it had just come down there.
  void _railRelease() {
    final down = _railDeferredDown, view = _railDeferredView;
    _railEnd();
    if (down != null) _down(down.e, frame: down.frame);
    if (view != null) _zoomDown(view, _box);
  }

  /// The rail beside the visible page's end edge (the left one in Arabic), inside it when there is no room outside.
  static double _railLeft(Rect shown, double width, bool rtl) {
    if (rtl) return shown.left - 14 >= 2 ? shown.left - 14 : math.max(2.0, shown.left + 4);
    return shown.right + 14 <= width - 2 ? shown.right + 8 : math.min(width - 8, shown.right - 10);
  }

  // ── Zoom (this device's view: never sent) ──────────────────────────────────
  double _zoom = 1;
  Offset _pan = Offset.zero;

  /// The continuous page's scroll (page fraction at the top of the stage) and sideways pan of a zoomed column.
  double _scroll = 0;
  double _cpanX = 0;
  final Map<int, Offset> _touches = {};
  ({double zoom, Rect rect, Offset focal, double dist, ContinuousView? view})? _pinch;

  /// One pointer moving the view (a finger, the mouse, the pen): where it went down (stage position) and the view then.
  ({int pointer, Offset start, Offset pan, double scroll, double panX})? _viewPan;

  static const _kMaxZoom = 4.0;

  /// The page on screen: the fitted page, scaled by [_zoom] about its centre and moved by [_pan], never leaving a
  /// gap at an edge it overflows.
  Rect _pageRect(Size size) {
    final base = boardPageRect(size, aspect: _c.aspect);
    if (_zoom <= 1.001 || base.isEmpty) return base;
    final w = base.width * _zoom, h = base.height * _zoom;
    var cx = base.center.dx + _pan.dx, cy = base.center.dy + _pan.dy;
    cx = w <= size.width ? size.width / 2 : cx.clamp(size.width - w / 2, w / 2).toDouble();
    cy = h <= size.height ? size.height / 2 : cy.clamp(size.height - h / 2, h / 2).toDouble();
    _pan = Offset(cx, cy) - base.center;
    return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
  }

  void _resetZoom() => setState(() {
        _zoom = 1;
        _pan = Offset.zero;
        _cpanX = 0;
      });

  /// Zooms to [z] keeping the page point under [focalBefore] under [focalAfter].
  void _zoomTo(double z, Rect before, Offset focalBefore, Offset focalAfter, Size size) {
    final base = boardPageRect(size, aspect: _c.aspect);
    if (base.isEmpty || before.isEmpty) return;
    final nz = z.clamp(1.0, _kMaxZoom).toDouble();
    final p = Offset((focalBefore.dx - before.left) / before.width, (focalBefore.dy - before.top) / before.height);
    final w = base.width * nz, h = base.height * nz;
    final topLeft = focalAfter - Offset(p.dx * w, p.dy * h);
    setState(() {
      _zoom = nz;
      _pan = topLeft + Offset(w / 2, h / 2) - base.center;
    });
  }

  /// The continuous view now (the last build's extent).
  ContinuousView _cvNow(Size size) => ContinuousView(
          box: size, zoom: _zoom, scroll: _scroll, panX: _cpanX, extent: _lastExtent, xMin: _lastXMin, xMax: _lastXMax)
      .clamped();

  void _applyView(ContinuousView v) => setState(() {
        _zoom = v.zoom;
        _scroll = v.scroll;
        _cpanX = v.panX;
      });

  /// A finger moves the view (not a stroke): this person is not drawing, only the stylus draws, or the hand is on.
  bool get _fingerPans => !_c.drawMode || DrawInputPrefs.stylusOnly.value || _handMode;

  /// [pointer] starts moving the view from [stage] (a stage position).
  void _beginPan(int pointer, Offset stage) {
    if (!_pannable) return;
    setState(() => _viewPan = (pointer: pointer, start: stage, pan: _pan, scroll: _scroll, panX: _cpanX));
  }

  void _endPan() {
    if (_viewPan == null) return;
    if (mounted) setState(() => _viewPan = null);
  }

  /// Where the mouse looks over the page while drawing: grabbing while the view moves, grab where a drag moves it.
  MouseCursor _drawCursor() {
    if (_viewPan != null || _railGrabbed) return SystemMouseCursors.grabbing;
    if (_handMode) return SystemMouseCursors.grab;
    if (_c.tool == BoardTool.select) {
      return _hoverItem ? SystemMouseCursors.move : (_pannable ? SystemMouseCursors.grab : SystemMouseCursors.basic);
    }
    return _cursor(_c.tool);
  }

  /// And over the stage (whoever is not drawing).
  MouseCursor _viewCursor() {
    if (_viewPan != null || _railGrabbed) return SystemMouseCursors.grabbing;
    return !_c.drawMode && _pannable ? SystemMouseCursors.grab : MouseCursor.defer;
  }

  void _zoomDown(PointerDownEvent e, Size size) {
    if (_railGrabbed) return;
    if (_railOwns(e.pointer)) {
      _railDeferredView = e;
      return;
    }
    if (_isStylus(e.kind)) {
      // The pen came down: a palm resting on the page must not scroll it (the pen itself may move the view).
      if (_viewPan?.pointer != e.pointer) {
        _touches.clear();
        _pinch = null;
        _viewPan = null;
      }
      if (_pansWith(e)) _beginPan(e.pointer, e.localPosition);
      return;
    }
    if (e.kind == PointerDeviceKind.mouse) {
      if (_pansWith(e)) _beginPan(e.pointer, e.localPosition);
      return;
    }
    if (e.kind != PointerDeviceKind.touch || _palmWindow) return;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2) {
      // A second finger: a pinch, not a stroke — whatever the first finger began is undone (a held stroke never
      // went out).
      _cancelGesture();
      final pts = _touches.values.toList();
      _pinch = (
        zoom: _zoom,
        rect: _c.isContinuous ? _cvNow(size).pageRect : _pageRect(size),
        focal: (pts[0] + pts[1]) / 2,
        dist: math.max(1, (pts[0] - pts[1]).distance),
        view: _c.isContinuous ? _cvNow(size) : null,
      );
      _viewPan = null;
    } else if (_touches.length == 1 && _fingerPans) {
      // One finger moves around a zoomed page / scrolls a continuous one.
      _beginPan(e.pointer, e.localPosition);
    }
  }

  void _zoomMove(PointerMoveEvent e, Size size) {
    if (_touches.containsKey(e.pointer)) {
      _touches[e.pointer] = e.localPosition;
      final pinch = _pinch;
      if (pinch != null && _touches.length >= 2) {
        final pts = _touches.values.take(2).toList();
        final focal = (pts[0] + pts[1]) / 2;
        final dist = math.max(1.0, (pts[0] - pts[1]).distance);
        final view = pinch.view;
        if (view != null) {
          _leaveFollow();
          _applyView(view.zoomedAt(pinch.zoom * dist / pinch.dist, pinch.focal, focal, maxZoom: _kMaxZoom));
        } else {
          _zoomTo(pinch.zoom * dist / pinch.dist, pinch.rect, pinch.focal, focal, size);
        }
        return;
      }
    }
    final vp = _viewPan;
    if (vp == null || vp.pointer != e.pointer) return;
    final d = e.localPosition - vp.start;
    if (_c.isContinuous) {
      if (d.distance > 3) _leaveFollow();
      final v = ContinuousView(
          box: size, zoom: _zoom, scroll: vp.scroll, panX: vp.panX, extent: _lastExtent, xMin: _lastXMin, xMax: _lastXMax);
      _applyView(v.scrolledBy(-d.dx, -d.dy));
    } else {
      setState(() => _pan = vp.pan + d);
    }
  }

  void _zoomUp(PointerEvent e) {
    _touches.remove(e.pointer);
    if (_touches.length < 2) _pinch = null;
    if (_viewPan?.pointer == e.pointer) _endPan();
  }

  void _zoomSignal(PointerSignalEvent e, Size size) {
    if (e is! PointerScrollEvent) return;
    final hk = HardwareKeyboard.instance;
    final zooming = hk.isControlPressed || hk.isMetaPressed;
    if (_c.isContinuous) {
      _leaveFollow();
      final v = _cvNow(size);
      if (zooming) {
        _applyView(v.zoomedAt(_zoom * math.exp(-e.scrollDelta.dy / 400), e.localPosition, e.localPosition, maxZoom: _kMaxZoom));
      } else {
        // Shift + wheel (or a sideways trackpad swipe) moves a zoomed column sideways.
        final dx = hk.isShiftPressed ? e.scrollDelta.dy : e.scrollDelta.dx;
        final dy = hk.isShiftPressed ? 0.0 : e.scrollDelta.dy;
        _applyView(v.scrolledBy(dx, dy));
      }
      return;
    }
    if (zooming) {
      final rect = _pageRect(size);
      _zoomTo(_zoom * math.exp(-e.scrollDelta.dy / 400), rect, e.localPosition, e.localPosition, size);
    } else if (_zoom > 1.01) {
      setState(() => _pan -= e.scrollDelta);
    }
  }

  /// Ends whatever the drawing pointer was doing, without keeping a half-made stroke or shape.
  void _cancelGesture() {
    if (_pointer == null) return;
    switch (_c.tool) {
      case BoardTool.pen:
      case BoardTool.highlighter:
        _c.cancelInk();
      case BoardTool.line:
      case BoardTool.arrow:
      case BoardTool.rect:
      case BoardTool.ellipse:
        _c.cancelShape();
      case BoardTool.eraser:
        _c.endErase();
      case BoardTool.select:
      case BoardTool.text:
        final d = _drag;
        if (d != null && d.moved) _c.endEdit(d.id);
      case BoardTool.laser:
      case BoardTool.hand:
        break;
    }
    _resetPointer();
  }

  Widget _textView(BoardText tx, double pw, double ph) {
    final rtl = boardTextIsRtl(tx.text, fallbackRtl: widget.fallbackRtl);
    final dir = rtl ? TextDirection.rtl : TextDirection.ltr;
    final style = boardTextStyle(tx, pw);
    final tp = TextPainter(text: TextSpan(text: tx.text, style: style), textDirection: dir)
      ..layout(maxWidth: math.max(8, tx.boxWidth * pw));
    if (ph > 0) _c.reportTextHeight(tx.id, tp.height / ph);
    tp.dispose();
    return Text(tx.text, textDirection: dir, textAlign: TextAlign.start, style: style);
  }

  Widget _editor(double pw, double ph, double ox) {
    final tx = _c.scene.item(_editingId!);
    if (tx is! BoardText) return const SizedBox.shrink();
    final rtl = boardTextIsRtl(_text.text, fallbackRtl: widget.fallbackRtl);
    final style = boardTextStyle(tx, pw);
    final accent = LivePalette.accent;
    return Positioned(
      key: const ValueKey('board.editor'),
      left: ox + tx.x * pw - 6,
      top: tx.y * ph - 4,
      width: math.max(40, tx.boxWidth * pw + 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Color(tx.color).computeLuminance() > 0.5 ? const Color(0x22000000) : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent, width: 1.5),
        ),
        child: EnterSubmits(
          onSubmit: _endTextEdit, // Ctrl+Enter on a keyboard ends the box (Enter is a new line)
          child: Focus(
            onKeyEvent: _onEditorKey,
            child: TextField(
              key: const ValueKey('board.editor.field'),
              controller: _text,
              focusNode: _focus,
              maxLines: null,
              minLines: 1,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              textAlign: TextAlign.start,
              style: style,
              cursorColor: accent,
              cursorWidth: 2,
              onTapOutside: (_) {}, // the board decides when the box ends (a toolbar tap keeps it open)
              decoration: InputDecoration.collapsed(
                hintText: t('اكتب هنا…', 'Type here…'),
                hintStyle: style.copyWith(color: Color(tx.color).withValues(alpha: 0.4)),
              ),
              onChanged: (v) {
                _c.updateText(tx.id, text: v);
                setState(() {}); // the direction follows the first letter
              },
            ),
          ),
        ),
      ),
    );
  }

  /// The selection frame, the width handle and the menu, in the page layers' frame ([ox]: the column's left edge in
  /// it; [sw]: its width).
  List<Widget> _selection(BoardItem it, double pw, double ph, double ox, double sw) {
    final Rect r;
    switch (it) {
      case BoardText():
        r = Rect.fromLTWH(ox + it.x * pw, it.y * ph, it.boxWidth * pw, _c.textHeight(it) * ph);
      case BoardShape():
        r = Rect.fromPoints(Offset(ox + it.x1 * pw, it.y1 * ph), Offset(ox + it.x2 * pw, it.y2 * ph));
      case BoardInk():
        return const [];
    }
    final frame = r.inflate(8);
    final editing = _editingId == it.id;
    final accent = LivePalette.accent;
    final chipTop = frame.top - 54 < 0 ? frame.bottom + 6 : frame.top - 54;
    return [
      if (!editing)
        Positioned.fromRect(
          rect: frame,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent, width: 1.5),
              ),
            ),
          ),
        ),
      // The width handle of a text box (bottom end of the frame).
      if (it is BoardText)
        Positioned(
          left: frame.right - 24,
          top: frame.bottom - 24,
          width: 48,
          height: 48,
          child: Semantics(
            label: t('تغيير عرض مربع النص', 'Resize the text box'),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                key: const ValueKey('board.resize'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => _c.beginEdit(it.id),
                onHorizontalDragUpdate: (d) {
                  final cur = _c.scene.item(it.id);
                  if (cur is BoardText && pw > 0) _c.updateText(it.id, boxWidth: cur.boxWidth + d.delta.dx / pw);
                },
                onHorizontalDragEnd: (_) {
                  if (_editingId != it.id) _c.endEdit(it.id);
                },
                child: Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: LivePalette.textHigh,
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: 2.5),
                      boxShadow: [BoxShadow(color: LivePalette.shade(0.3), blurRadius: 4)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      Positioned(
        left: math.max(0, math.min(frame.left, sw - (it is BoardText ? 156 : 60))),
        top: math.max(0, chipTop),
        child: Container(
          key: const ValueKey('board.selection_menu'),
          decoration: BoxDecoration(
            color: LivePalette.surfaceHi.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: LivePalette.glassBorder),
            boxShadow: [BoxShadow(color: LivePalette.shade(0.3), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (it is BoardText)
              AnnotToolButton(
                key: const ValueKey('board.text_edit'),
                label: editing ? t('تم', 'Done') : t('تعديل النص', 'Edit text'),
                onTap: editing ? _endTextEdit : () => _startTextEdit(it.id),
                child: Icon(editing ? Icons.check_rounded : Icons.edit_note_rounded, size: 22, color: LivePalette.textHigh),
              ),
            AnnotToolButton(
              key: const ValueKey('board.delete'),
              label: t('حذف', 'Delete'),
              onTap: () {
                _editingId = null;
                _c.deleteSelected();
              },
              child: Icon(Icons.delete_outline_rounded, size: 22, color: LivePalette.danger),
            ),
          ]),
        ),
      ),
    ];
  }

  static MouseCursor _cursor(BoardTool t) => switch (t) {
        BoardTool.pen || BoardTool.highlighter => SystemMouseCursors.precise,
        BoardTool.line || BoardTool.arrow || BoardTool.rect || BoardTool.ellipse => SystemMouseCursors.precise,
        BoardTool.text => SystemMouseCursors.text,
        BoardTool.select => SystemMouseCursors.move,
        BoardTool.hand => SystemMouseCursors.grab,
        BoardTool.eraser => SystemMouseCursors.cell,
        BoardTool.laser => SystemMouseCursors.none,
      };
}

/// The pointer on a rail (D-109): which rail, on what, where it came down; once [grabbed], the thumb's start (px) then.
class _RailGrab {
  _RailGrab({required this.pointer, required this.kind, required this.vertical, required this.part, required this.down});

  final int pointer;
  final PointerDeviceKind kind;
  final bool vertical;
  final BoardRailPart part;
  final Offset down;
  bool grabbed = false;
  double thumb0 = 0;
}

/// Where this view is on a continuous page (D-093 / D-107, scrollbars D-109): a slim track, the view's thumb and the
/// presenter's view as an accent mark (viewers) — down the end edge ([vertical]) or across the bottom. [lo]..[hi] is
/// the page's range on that axis, [start] / [length] the view's, [presenter] the presenter's (start, length).
/// [grabbed]: the thumb is held — it grows and takes the accent. Drawn centred in a box [thickness] px across;
/// plain values (test/ui/whiteboard_scrollbar_layout_test.dart).
class BoardScrollRail extends StatelessWidget {
  const BoardScrollRail({
    super.key,
    required this.vertical,
    required this.lo,
    required this.hi,
    required this.start,
    required this.length,
    this.presenter,
    this.grabbed = false,
    this.look = BoardRailLook.mouse,
  });

  /// The box a mouse rail is drawn in, across (px): the grabbed rail at its widest ([BoardRailLook.box]).
  static const thickness = 16.0;

  final bool vertical;
  final double lo, hi, start, length;
  final (double, double)? presenter;
  final bool grabbed;

  /// Slim (mouse) or the big touch thumb with its grip (D-306).
  final BoardRailLook look;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: grabbed ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        builder: (context, g, _) => LayoutBuilder(builder: (context, c) {
          final len = vertical ? c.maxHeight : c.maxWidth;
          final across = vertical ? c.maxWidth : c.maxHeight;
          final m = BoardRailMetrics(
              track: len.isFinite ? len : 0, lo: lo, hi: hi, start: start, length: length, minThumb: look.minThumb, hit: look.hit);
          if (!m.scrollable || !across.isFinite) return const SizedBox.shrink();
          final track = ui.lerpDouble(look.track, look.trackGrabbed, g)!;
          final thumbW = math.min(across, ui.lerpDouble(look.thumb, look.thumbGrabbed, g)!);
          final markW = math.min(across, track + 4);
          double at(double v) => ((v - lo) / m.span).clamp(0.0, 1.0) * len;
          Widget bar(Key? key, double a, double l, double w, BoxDecoration d) {
            final off = (across - w) / 2;
            return Positioned(
              left: vertical ? off : a,
              top: vertical ? a : off,
              width: vertical ? w : l,
              height: vertical ? l : w,
              child: DecoratedBox(key: key, decoration: d),
            );
          }

          final p = presenter;
          final accent = LivePalette.accent;
          final thumbColor = Color.lerp(const Color(0xB3475569), accent, g)!;
          return Stack(clipBehavior: Clip.none, children: [
            bar(null, 0, len, track,
                BoxDecoration(color: LivePalette.shade(0.18 + 0.1 * g), borderRadius: BorderRadius.circular(track / 2))),
            if (p != null)
              bar(ValueKey(vertical ? 'board.rail.presenter' : 'board.side_rail.presenter'), at(p.$1),
                  math.max(4.0, at(p.$1 + p.$2) - at(p.$1)), markW,
                  BoxDecoration(color: accent.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(markW / 2))),
            bar(
              ValueKey(vertical ? 'board.rail.thumb' : 'board.side_rail.thumb'),
              m.thumbStart,
              m.thumbLength,
              thumbW,
              BoxDecoration(
                color: thumbColor,
                borderRadius: BorderRadius.circular(thumbW / 2),
                border: Border.all(color: Color.lerp(const Color(0x66FFFFFF), const Color(0xE6FFFFFF), g)!, width: 0.8 + 0.7 * g),
                boxShadow: g <= 0
                    ? null
                    : [BoxShadow(color: accent.withValues(alpha: 0.45 * g), blurRadius: 10 * g, spreadRadius: 1 * g)],
              ),
            ),
            // D-306: the touch thumb's grip — three short lines across it, so it reads as something to hold.
            if (look.grip && m.thumbLength >= 32 && thumbW >= 10)
              Positioned(
                key: ValueKey(vertical ? 'board.rail.grip' : 'board.side_rail.grip'),
                left: vertical ? (across - thumbW) / 2 : m.thumbStart,
                top: vertical ? m.thumbStart : (across - thumbW) / 2,
                width: vertical ? thumbW : m.thumbLength,
                height: vertical ? m.thumbLength : thumbW,
                child: IgnorePointer(
                  child: Center(
                    child: Flex(
                      direction: vertical ? Axis.vertical : Axis.horizontal,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Container(
                            margin: EdgeInsets.symmetric(vertical: vertical ? 1.5 : 0, horizontal: vertical ? 0 : 1.5),
                            width: vertical ? thumbW * 0.5 : 1.6,
                            height: vertical ? 1.6 : thumbW * 0.5,
                            decoration: BoxDecoration(
                              color: const Color(0xE6FFFFFF),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ]);
        }),
      );
}

/// "Follow Dr. Mona" on a continuous page, once a viewer scrolled away from the presenter's view.
class BoardFollowButton extends StatelessWidget {
  const BoardFollowButton({super.key, this.name = '', this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);
    final label = name.isEmpty ? t('تابِع مقدّم العرض', 'Follow the presenter') : t('تابِع $name', 'Follow $name');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('board.follow'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, maxWidth: 300),
            padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 16, 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [LivePalette.accent, LivePalette.accent2]),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: LivePalette.accent.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 6)),
                BoxShadow(color: LivePalette.shade(0.3), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.near_me_rounded, size: 18, color: LivePalette.textHigh),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w800, c: LivePalette.textHigh)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Pen detected: let fingers scroll and zoom?" — offered once, the first time a stylus touches a board.
class BoardStylusOffer extends StatelessWidget {
  const BoardStylusOffer({super.key, this.onYes, this.onNo});

  final VoidCallback? onYes;
  final VoidCallback? onNo;

  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('board.stylus_offer'),
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: LivePalette.surfaceHi.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: LivePalette.glassBorder),
          boxShadow: [BoxShadow(color: LivePalette.shade(0.35), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.draw_rounded, size: 20, color: LivePalette.textHigh),
          const SizedBox(width: 10),
          Flexible(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('اكتشفنا قلماً', 'Pen detected'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w800, c: LivePalette.textHigh)),
              Text(t('القلم يرسم والإصبع يحرّك ويكبّر؟', 'Pen draws, fingers scroll and zoom?'),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: LivePalette.textMid)),
            ]),
          ),
          const SizedBox(width: 6),
          TextButton(
            key: const ValueKey('board.stylus_offer.yes'),
            onPressed: onYes,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: LivePalette.textHigh,
              backgroundColor: LivePalette.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(t('تفعيل', 'Turn on'), style: appText(13, w: FontWeight.w800, c: LivePalette.textHigh)),
          ),
          AnnotToolButton(
            key: const ValueKey('board.stylus_offer.no'),
            label: t('لا، شكراً', 'No thanks'),
            onTap: onNo,
            child: const Icon(Icons.close_rounded, size: 20, color: LivePalette.textMid),
          ),
        ]),
      ),
    );
  }
}

/// "150 %" while this device's view is zoomed; a tap fits the page again.
class _ZoomChip extends StatelessWidget {
  const _ZoomChip({required this.percent, required this.onReset});

  final int percent;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final label = t('عرض الصفحة كاملة', 'Fit the page');
    return Semantics(
      button: true,
      label: '$percent%. $label',
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: const ValueKey('board.zoom_reset'),
          onTap: onReset,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: LivePalette.surfaceHi.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: LivePalette.glassBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.fit_screen_rounded, size: 18, color: LivePalette.textHigh),
              const SizedBox(width: 6),
              Text('$percent%', style: appText(13, w: FontWeight.w700, c: LivePalette.textHigh)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.dark, required this.width});

  final bool dark;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? const Color(0x99FFFFFF) : const Color(0x8A1F2937);
    final small = width < 420;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.gesture_rounded, size: small ? 26 : 40, color: ink),
          SizedBox(height: small ? 4 : 10),
          Text(
            t('اكتب أو ارسم أو أضف أشكالاً', 'Write, draw or add shapes'),
            textAlign: TextAlign.center,
            style: appText(small ? 13 : 18, w: FontWeight.w800, c: ink),
          ),
          if (!small) ...[
            const SizedBox(height: 4),
            Text(
              t('يرى الجميع كل ما تضيفه فوراً', 'Everyone sees what you add, live'),
              textAlign: TextAlign.center,
              style: appText(13, c: ink),
            ),
          ],
        ]),
      ),
    );
  }
}

class _NeedsUpdate extends StatelessWidget {
  const _NeedsUpdate();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: LivePalette.surface, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.system_update_rounded, size: 36, color: LivePalette.textMid),
          const SizedBox(height: 10),
          Text(t('تُعرض سبورة بيضاء', 'A whiteboard is being presented'),
              textAlign: TextAlign.center, style: appText(15, w: FontWeight.w800, c: LivePalette.textHigh)),
          const SizedBox(height: 4),
          Text(t('حدّث التطبيق لرؤيتها كاملة', 'Update the app to see all of it'),
              textAlign: TextAlign.center, style: appText(13, c: LivePalette.textMid)),
        ]),
      );
}

/// The page as a PNG (what everyone sees, without the selection frame), [width] px wide. Null when the page is
/// not on screen.
Future<Uint8List?> boardPagePng(GlobalKey pageKey, {double width = 1920}) async {
  final ro = pageKey.currentContext?.findRenderObject();
  if (ro is! RenderRepaintBoundary || ro.size.isEmpty) return null;
  final ratio = width / ro.size.width;
  final image = await ro.toImage(pixelRatio: ratio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Keeps [run] from piling up (export taps).
Future<void> boardOnce(Future<void> Function() run) async {
  if (_busy) return;
  _busy = true;
  try {
    await run();
  } finally {
    _busy = false;
  }
}

bool _busy = false;

