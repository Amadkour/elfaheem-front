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
//                      box's width); drag it: moved. Double-tap a text box: edit it.
//   eraser             removes what it touches; laser: a fading dot (also on hover with a mouse).
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
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
import '../annotation/annotation_toolbar.dart' show AnnotToolButton;
import '../annotation/draw_input_prefs.dart';
import '../annotation/presence_tags.dart';
import '../widgets/live_palette.dart';
import 'board_controller.dart';
import 'board_format.dart';
import 'board_painter.dart';
import 'board_protocol.dart';

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

  /// The writer's interface is right to left (Arabic): a text box opens to the left of the tap, an empty box is RTL.
  final bool fallbackRtl;
  final Color? laserColor;

  /// The presenter's empty page says what to do.
  final bool showEmptyHint;

  @override
  State<WhiteboardStage> createState() => _WhiteboardStageState();
}

class _WhiteboardStageState extends State<WhiteboardStage> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) {
    final lasers = widget.controller.pruneLasers();
    final tags = widget.controller.presence.step();
    final follow = _stepFollow();
    if (!lasers && !tags && !follow) _ticker.stop();
  });

  BoardController get _c => widget.controller;

  /// The page's COORDINATE size on screen (continuous: its whole length) and where its top-left corner is.
  Size _page = Size.zero;
  Offset _origin = Offset.zero;

  // pointer
  int? _pointer;
  PointerDeviceKind? _pointerKind;
  AnnotInkFilter? _ink;
  bool _stylusDown = false;
  DateTime? _stylusUp;
  ({String id, Offset last, Offset start, bool moved})? _drag;
  Offset? _pendingCreate;
  DateTime? _lastTapAt;
  String? _lastTapId;

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
  }

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
    final id = _editingId;
    if (id != null) _c.endEdit(id);
    _probeTimer?.cancel();
    _offerTimer?.cancel();
    _ticker.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onScene() {
    if ((_c.scene.hasLasers || !_c.presence.isEmpty) && !_ticker.isActive) _ticker.start();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  // ── Following the presenter (continuous) ───────────────────────────────────
  bool _follow = true;
  double? _followTarget;
  double _lastVisible = 0;
  double _lastExtent = 1;

  void _onPresenterViewport() {
    if (!mounted || _c.isLocalPresenting || !_c.isContinuous) return;
    final pv = _c.presenterViewport.value;
    if (pv == null) return;
    if (_follow) {
      _followTarget = boardFollowTop(presenter: pv, visible: _lastVisible, extent: math.max(_lastExtent, pv.bottom));
      if (!_ticker.isActive) _ticker.start();
    } else {
      setState(() {}); // the rail's presenter mark moves
    }
  }

  /// One frame of the eased follow; whether it is still moving.
  bool _stepFollow() {
    final target = _followTarget;
    if (target == null || !_follow || !mounted) return false;
    final d = target - _scroll;
    if (d.abs() < 1e-5) {
      _followTarget = null;
      return false;
    }
    setState(() => _scroll += d.abs() < 2e-4 ? d : d * 0.22);
    return true;
  }

  void _followPresenter() {
    final pv = _c.presenterViewport.value;
    setState(() {
      _follow = true;
      if (pv != null) _followTarget = boardFollowTop(presenter: pv, visible: _lastVisible, extent: math.max(_lastExtent, pv.bottom));
    });
    if (!_ticker.isActive) _ticker.start();
  }

  /// This viewer moved the view themselves: they stop following until they tap "Follow …".
  void _leaveFollow() {
    if (_c.isLocalPresenting || !_follow) return;
    _follow = false;
    _followTarget = null;
  }

  // ── "Drawn by …" ───────────────────────────────────────────────────────────
  ({String author, Offset at, int color})? _probe;
  Timer? _probeTimer;
  Offset? _pressAt;

  bool get _probing => _c.showAuthors() && (!_c.drawMode || _c.tool == BoardTool.select);

  void _probeAt(Offset local, {bool autoHide = false}) {
    final n = _norm(local - _origin);
    final it = (n.dx < 0 || n.dx > 1 || n.dy < 0 || n.dy > 1) ? null : _c.itemAt(n.dx, n.dy);
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
    if (!_probing || e.kind == PointerDeviceKind.mouse || _c.drawMode) return;
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
  }

  // ── Geometry ───────────────────────────────────────────────────────────────

  Offset _norm(Offset local) =>
      _page.isEmpty ? Offset.zero : Offset(local.dx / _page.width, local.dy / _page.height);

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

  // ── Pointer ────────────────────────────────────────────────────────────────

  void _down(PointerDownEvent e) {
    if (!_c.drawMode) return;
    if (e.kind == PointerDeviceKind.mouse && (e.buttons & kPrimaryMouseButton) == 0) return;
    final stylus = _isStylus(e.kind);
    if (stylus) {
      _stylusDown = true;
      DrawInputPrefs.stylusSeen = true;
      _maybeOfferStylus();
    }
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
    final n = _norm(e.localPosition);
    if (n.dx < 0 || n.dx > 1 || n.dy < 0 || n.dy > 1) return;
    final tool = e.kind == PointerDeviceKind.invertedStylus ? BoardTool.eraser : _c.tool;
    _pointer = e.pointer;
    _pointerKind = e.kind;
    switch (tool) {
      case BoardTool.pen:
      case BoardTool.highlighter:
        _endTextEdit();
        final ink = AnnotInkFilter(pressure: stylus);
        final s = ink.start(e.localPosition.dx, e.localPosition.dy, _seconds(e), _pressure(e));
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
        _c.pointLaser(n.dx, n.dy);
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
          _drag = (id: hit.id, last: n, start: e.localPosition, moved: false);
        } else {
          _c.select(null);
          // A tap beside the box being typed ends it; the next tap opens a new one.
          if (tool == BoardTool.text && !wasEditing) _pendingCreate = n;
        }
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final n = _norm(e.localPosition);
    final drag = _drag;
    if (drag != null) {
      final moved = drag.moved || (e.localPosition - drag.start).distance > 5;
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
        final s = ink.add(e.localPosition.dx, e.localPosition.dy, _seconds(e), _pressure(e));
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
        break;
    }
    if (e.kind == PointerDeviceKind.invertedStylus) _c.eraseAt(n.dx, n.dy);
  }

  void _hover(PointerHoverEvent e) {
    if (!_c.drawMode || _pointer != null || _c.tool != BoardTool.laser) return;
    final n = _norm(e.localPosition);
    if (n.dx < 0 || n.dx > 1 || n.dy < 0 || n.dy > 1) return;
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
      final x = widget.fallbackRtl ? create.dx - w : create.dx;
      final lineH = _c.fontSize(_c.fontStep) * 1.35 * _c.aspect;
      final id = _c.createText(x, (create.dy - lineH / 2).clamp(0.0, 1.0).toDouble(), boxWidth: w);
      if (id != null) _startTextEdit(id, fresh: true);
      return;
    }
    switch (_c.tool) {
      case BoardTool.pen:
      case BoardTool.highlighter:
        if (ink != null && e is PointerUpEvent) {
          final last = ink.finish(e.localPosition.dx, e.localPosition.dy);
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
      _followedOnce = false;
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

  /// This device's view of the continuous page, kept inside it (the extent follows the content and the presenter).
  ContinuousView _continuousView(Size size) {
    final base = ContinuousView(box: size, zoom: _zoom, scroll: _scroll, panX: _cpanX);
    final pv = _c.isLocalPresenting ? null : _c.presenterViewport.value;
    final extent = boardContinuousExtent(contentBottom: _contentBottom(), visible: base.visible, presenterBottom: pv?.bottom ?? 0);
    var start = base;
    if (pv != null && _follow && !_followedOnce) {
      // A viewer who arrives (or a new page) starts where the presenter is.
      _followedOnce = true;
      start = base.copyWith(scroll: boardFollowTop(presenter: pv, visible: base.visible, extent: extent));
    }
    final v = start.copyWith(extent: extent).clamped();
    _scroll = v.scroll;
    _cpanX = v.panX;
    _lastVisible = v.visible;
    _lastExtent = extent;
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

        final content = Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned.fill(child: CustomPaint(painter: BoardBackgroundPainter(scene.background))),
          Positioned.fill(
            child: CustomPaint(
              isComplex: true,
              painter: BoardItemsPainter(
                items: () => scene.visibleItems,
                lasers: () => const [],
                laserColor: laser,
                laserOpacity: _c.laserOpacity,
                coordSize: cont ? page.size : null,
                repaint: scene,
              ),
            ),
          ),
          for (final tx in texts)
            if (tx.id != _editingId)
              Positioned(
                key: ValueKey('board.text.${tx.id}'),
                left: tx.x * pw,
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
                            child: MouseRegion(cursor: draw ? _cursor(_c.tool) : MouseCursor.defer, child: const SizedBox.expand()),
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
                            toLocal: (x, y) => Offset(x * pw, y * ph),
                            bounds: (_) => visLocal,
                            fallbackRtl: widget.fallbackRtl,
                          ),
                        ),
                      ),
                    ),
                    if (_editingId != null) _editor(pw, ph),
                    if (selected != null && draw) ..._selection(selected, pw, ph),
                  ]),
                ),
              ),
            ),
          if (_c.needsUpdate)
            Positioned.fromRect(rect: page.isEmpty || cont ? screen : page, child: const _NeedsUpdate()),
          if (cont && !vis.isEmpty)
            Positioned(
              top: vis.top + 10,
              height: math.max(0.0, vis.height - 20),
              left: _railLeft(shown, size.width, Directionality.of(context) == TextDirection.rtl),
              width: 6,
              child: IgnorePointer(
                child: _ScrollRail(
                  extent: cv!.extent,
                  view: cv.viewport,
                  presenter: presenting ? null : _c.presenterViewport.value,
                ),
              ),
            ),
          if (cont && !presenting && !_follow && _c.presenterViewport.value != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
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
        ]);
        // Pinch (two fingers) / Ctrl + wheel zooms this device's view only; two fingers (or the wheel) pan it; a
        // continuous page scrolls with them too (and with one finger when this person is not drawing).
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
            child: MouseRegion(opaque: false, onExit: (_) => _clearProbe(), child: stage),
          ),
        );
      }),
    );
  }

  /// The rail beside the column's end edge (the left one in Arabic), inside the page when there is no room outside.
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
  ({Offset start, Offset pan, double scroll, double panX})? _viewPan;

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
  ContinuousView _cvNow(Size size) =>
      ContinuousView(box: size, zoom: _zoom, scroll: _scroll, panX: _cpanX, extent: _lastExtent).clamped();

  void _applyView(ContinuousView v) => setState(() {
        _zoom = v.zoom;
        _scroll = v.scroll;
        _cpanX = v.panX;
      });

  /// A finger moves the view (not a stroke): this person is not drawing, or only the stylus draws.
  bool get _fingerPans => !_c.drawMode || DrawInputPrefs.stylusOnly.value;

  void _zoomDown(PointerDownEvent e, Size size) {
    if (_isStylus(e.kind)) {
      // The pen came down: a palm resting on the page must not scroll it.
      _touches.clear();
      _pinch = null;
      _viewPan = null;
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
    } else if (_touches.length == 1 && _fingerPans && (_c.isContinuous || _zoom > 1.01)) {
      // One finger moves around a zoomed page / scrolls a continuous one.
      _viewPan = (start: e.localPosition, pan: _pan, scroll: _scroll, panX: _cpanX);
    }
  }

  void _zoomMove(PointerMoveEvent e, Size size) {
    if (!_touches.containsKey(e.pointer)) return;
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
    final vp = _viewPan;
    if (vp == null) return;
    final d = e.localPosition - vp.start;
    if (_c.isContinuous) {
      if (d.distance > 3) _leaveFollow();
      final v = ContinuousView(box: size, zoom: _zoom, scroll: vp.scroll, panX: vp.panX, extent: _lastExtent);
      _applyView(v.scrolledBy(-d.dx, -d.dy));
    } else {
      setState(() => _pan = vp.pan + d);
    }
  }

  void _zoomUp(PointerEvent e) {
    _touches.remove(e.pointer);
    if (_touches.length < 2) _pinch = null;
    if (_touches.isEmpty) _viewPan = null;
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

  Widget _editor(double pw, double ph) {
    final tx = _c.scene.item(_editingId!);
    if (tx is! BoardText) return const SizedBox.shrink();
    final rtl = boardTextIsRtl(_text.text, fallbackRtl: widget.fallbackRtl);
    final style = boardTextStyle(tx, pw);
    final accent = LivePalette.accent;
    return Positioned(
      key: const ValueKey('board.editor'),
      left: tx.x * pw - 6,
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

  List<Widget> _selection(BoardItem it, double pw, double ph) {
    final Rect r;
    switch (it) {
      case BoardText():
        r = Rect.fromLTWH(it.x * pw, it.y * ph, it.boxWidth * pw, _c.textHeight(it) * ph);
      case BoardShape():
        r = Rect.fromPoints(Offset(it.x1 * pw, it.y1 * ph), Offset(it.x2 * pw, it.y2 * ph));
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
        left: math.max(0, math.min(frame.left, pw - (it is BoardText ? 156 : 60))),
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
        BoardTool.eraser => SystemMouseCursors.cell,
        BoardTool.laser => SystemMouseCursors.none,
      };
}

/// Where this view is on a continuous page: a slim rail at the end edge, the view's thumb, and the presenter's view
/// as an accent mark (viewers).
class _ScrollRail extends StatelessWidget {
  const _ScrollRail({required this.extent, required this.view, this.presenter});

  final double extent;
  final BoardViewportPos view;
  final BoardViewportPos? presenter;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final h = c.maxHeight;
        if (!h.isFinite || h <= 0 || extent <= 0 || view.height >= extent - 1e-6) return const SizedBox.shrink();
        double y(double v) => (v / extent).clamp(0.0, 1.0) * h;
        final top = y(view.top), bottom = math.max(y(view.bottom), y(view.top) + 18);
        final p = presenter;
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: LivePalette.shade(0.18), borderRadius: BorderRadius.circular(3)),
            ),
          ),
          if (p != null)
            Positioned(
              left: -2,
              right: -2,
              top: y(p.top),
              height: math.max(4.0, y(p.bottom) - y(p.top)),
              child: DecoratedBox(
                key: const ValueKey('board.rail.presenter'),
                decoration: BoxDecoration(
                  color: LivePalette.accent.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: top,
            height: math.min(h, bottom) - top,
            child: DecoratedBox(
              key: const ValueKey('board.rail.thumb'),
              decoration: BoxDecoration(
                color: const Color(0xB3475569),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0x66FFFFFF), width: 0.8),
              ),
            ),
          ),
        ]);
      });
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

