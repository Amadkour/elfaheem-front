// lib/design/studio/studio_canvas.dart
//
// The studio's canvas: the page at the controller's zoom with pan, every item drawn by the host's itemBuilder,
// the selection frame with its 8 handles, smart guides, marquee selection and the keyboard.
//
//   pointer       press an item and drag = move (shift: one axis) · a handle = resize (shift: keep the ratio) ·
//                 tap = select (shift / ctrl / ⌘: add or remove) · tap the empty page = deselect ·
//                 mouse drag on empty space = marquee · touch drag on empty space / wheel = pan ·
//                 ctrl + wheel / pinch = zoom · double click (or long-press on touch) on a text item = edit it in
//                 place (inlineText) · the round knob above the selected item turns it (shift: 15° steps) ·
//                 right click (or long-press on touch, non-text items) = context menu
//   keyboard      arrows nudge (shift ×10) · Delete / Backspace · Ctrl/⌘+Z undo · Shift+Ctrl/⌘+Z or Ctrl+Y redo ·
//                 [ / ] send backward / bring forward (Ctrl: to back / to front) · Ctrl/⌘+L lock · Ctrl/⌘+D duplicate · Ctrl/⌘+A select all · Ctrl/⌘+C / X / V copy, cut, paste · Esc deselect.
//                 Only while the canvas has focus, and never while a text field has it.
//   in-place edit the editor sits exactly over the item (the host's StudioInlineStyle: font, size, alignment,
//                 direction); Enter confirms (Shift+Enter = new line when multiline), a click outside confirms,
//                 Esc cancels; the change is ONE undo step (StudioController.commitText).
//
// Hit-testing is done here, once, on the controller's geometry: item widgets sit under IgnorePointer, so a
// host's content can never steal a drag. Handles keep a 48 px target on touch (AppTouch.min), pushed outward so
// they cover as little of the item as possible. The page is never mirrored: coordinates are physical in Arabic
// too, while the items' own text keeps the app's direction.
//
// 60 fps: a pointer move only fires the controller's [StudioController.live]; the selected items' Positioned
// and the overlay painter react, the item list and every other item stay as they are (the page layer is cached
// per scale and rebuilt on structure changes only).
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_keyboard.dart' show AppKeyboard;
import '../app_tokens.dart';
import 'studio_controller.dart';
import 'studio_model.dart';

/// Draws one item's content in its box (the canvas sizes and positions the box; fill it). Read
/// [StudioCanvas.scaleOf] for screen pixels per page unit (font sizes, stroke widths).
typedef StudioItemBuilder<P> = Widget Function(BuildContext context, StudioItem<P> item, bool selected);

/// White paper: the default page colour (documents print on white).
const Color kStudioPaper = Color(0xFFFFFFFF);

class StudioCanvas<P> extends StatefulWidget {
  const StudioCanvas({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.marquee = true,
    this.pageColor = kStudioPaper,
    this.pageBackground,
    this.padding = AppSpace.lg,
    this.onItemDoubleTap,
    this.focusNode,
    this.autofocus = false,
    this.paperInsets = EdgeInsets.zero,
    this.paperBuilder,
    this.overlayBuilder,
    this.inlineText,
    this.inlineStyle,
    this.onInlineCommit,
    this.contextMenu = true,
    this.buildKey,
  });

  /// A value that changes whenever the host's [itemBuilder] would draw something else for the SAME items (the page
  /// font, the language, sample values …). When the builder is a stable method tear-off, the canvas keeps its
  /// item widgets across host rebuilds and redraws them only when this key or the items change; a closure builder
  /// (a new object every host build) keeps the old behaviour of redrawing every item. Null = compare the builder
  /// only.
  final Object? buildKey;

  final StudioController<P> controller;
  final StudioItemBuilder<P> itemBuilder;

  /// Mouse drag on empty space draws a selection rectangle.
  final bool marquee;
  final Color pageColor;

  /// Drawn under the items, filling the page (a background image, a border artwork).
  final Widget? pageBackground;

  /// Space around the page when it fits (screen pixels).
  final double padding;

  /// Double tap / double click on an item (open its text editor, its image picker, …).
  final ValueChanged<String>? onItemDoubleTap;
  final FocusNode? focusNode;
  final bool autofocus;

  /// The paper around the page, in PAGE units (an export page's margins in mm): the page (where items live, snap
  /// and are clamped) sits inside a larger sheet that is drawn, fitted and panned as one. Zero (the default) = the
  /// page is the paper.
  final EdgeInsets paperInsets;

  /// Draws the whole paper (margins included) under the items: header / footer text, a frame, a watermark.
  /// Receives the screen pixels per page unit.
  final Widget Function(BuildContext context, double scale)? paperBuilder;

  /// Drawn over the page background and under the items (a watermark), at the page's size.
  final Widget Function(BuildContext context, double scale)? overlayBuilder;

  /// The text an item can edit in place, or null when it has none (an image, a line). With [onInlineCommit], a
  /// double click (long-press on touch) on such an item opens the editor; other items keep [onItemDoubleTap].
  final String? Function(StudioItem<P> item)? inlineText;

  /// How the editor looks over [item] at [scale] screen pixels per page unit; null = the theme's body text.
  final StudioInlineStyle? Function(BuildContext context, StudioItem<P> item, double scale)? inlineStyle;

  /// Stores the edited text in the host's model. Runs inside [StudioController.commitText] (one undo step), only
  /// when the text changed.
  final void Function(StudioItem<P> item, String text)? onInlineCommit;

  /// Right click / long-press shows Cut, Copy, Paste, Duplicate, Delete, the z order and Lock (when the adapter
  /// can lock). False for a read-only design.
  final bool contextMenu;

  bool get canEditText => inlineText != null && onInlineCommit != null;

  /// Screen pixels per page unit for the item being built.
  static double scaleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_StudioScale>()?.scale ?? 1;

  @override
  State<StudioCanvas<P>> createState() => _StudioCanvasState<P>();
}

enum _Mode { none, move, resize, rotate, marquee, view }

class _StudioCanvasState<P> extends State<StudioCanvas<P>> {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'studio-canvas'));

  Size _viewport = Size.zero;
  Offset? _origin;
  double? _lastScale;
  double _scale = 1;
  Offset? _anchor;
  bool _viewportQueued = false;

  PointerDeviceKind? _kind;
  Offset _down = Offset.zero;
  _Mode _mode = _Mode.none;
  Offset _startFocal = Offset.zero, _startOrigin = Offset.zero;
  double _startScale = 1;
  Offset _marqueeFrom = Offset.zero;
  bool _marqueeAdd = false;
  String? _lastTapId;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  final _marquee = ValueNotifier<Rect?>(null);
  final _cursor = ValueNotifier<MouseCursor>(SystemMouseCursors.basic);

  // the in-place editor
  final _editingId = ValueNotifier<String?>(null);
  TextEditingController? _editText;
  FocusNode? _editFocus;
  String _editOriginal = '';
  bool Function(KeyDownEvent e)? _prevClaim;
  bool _claimed = false;

  Widget? _layer, _overlay;
  double? _layerScale;

  bool get _touch {
    final k = _kind;
    if (k != null) return k == PointerDeviceKind.touch || k == PointerDeviceKind.stylus;
    return defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _layer = null;
  }

  @override
  void didUpdateWidget(covariant StudioCanvas<P> old) {
    super.didUpdateWidget(old);
    if (old.itemBuilder != widget.itemBuilder ||
        old.buildKey != widget.buildKey ||
        old.pageColor != widget.pageColor ||
        old.pageBackground != widget.pageBackground ||
        old.overlayBuilder != widget.overlayBuilder ||
        old.paperInsets != widget.paperInsets ||
        old.padding != widget.padding) {
      _layer = null;
    }
    if (old.contextMenu != widget.contextMenu) _holdBrowserMenu(widget.contextMenu);
  }

  /// Canvases that own the right click (the browser's menu is off while at least one is mounted). Counted, not
  /// toggled: a new canvas (band switch, next step, other language) mounts BEFORE the old one is disposed, so a plain
  /// disable / enable pair would turn the browser's menu back on under the new canvas.
  static int _menuHolds = 0;
  bool _holdsMenu = false;

  void _holdBrowserMenu(bool hold) {
    if (!kIsWeb || hold == _holdsMenu) return;
    _holdsMenu = hold;
    if (hold) {
      if (_menuHolds++ == 0) unawaited(BrowserContextMenu.disableContextMenu());
    } else {
      if (--_menuHolds == 0) unawaited(BrowserContextMenu.enableContextMenu());
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncEditor);
    _holdBrowserMenu(widget.contextMenu);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncEditor);
    _holdBrowserMenu(false);
    _closeEditor(notify: false);
    _ownFocus?.dispose();
    _marquee.dispose();
    _cursor.dispose();
    _editingId.dispose();
    super.dispose();
  }

  StudioController<P> get _ctl => widget.controller;

  // ── In-place text editor ─────────────────────────────────────────────────────────────────────────────────
  /// Opens / closes the editor when the controller's [StudioController.editingId] changes.
  void _syncEditor() {
    final id = _ctl.editingId;
    if (id == _editingId.value) return;
    if (id == null) {
      _closeEditor();
      return;
    }
    final it = _ctl.itemById(id);
    final text = it == null || !widget.canEditText ? null : widget.inlineText!(it);
    if (text == null) {
      // nothing to edit here: hand the controller back its idle state after this notification
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ctl.editingId == id) _ctl.endTextEdit();
      });
      return;
    }
    _closeEditor(notify: false);
    _editOriginal = text;
    _editText = TextEditingController(text: text)..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    _editFocus = FocusNode(debugLabel: 'studio-inline', onKeyEvent: (node, e) {
      if (e is! KeyDownEvent) return KeyEventResult.ignored;
      return _editorKey(e) ? KeyEventResult.handled : KeyEventResult.ignored;
    });
    // the app-wide keyboard (Enter → next field, Esc → unfocus) runs before the focus tree: claim its keys
    _prevClaim = AppKeyboard.keyClaim;
    _claimed = true;
    AppKeyboard.keyClaim = _editorKey;
    if (mounted) setState(() => _layer = null);
    _editingId.value = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editFocus != null) _editFocus!.requestFocus();
    });
  }

  void _closeEditor({bool notify = true}) {
    if (_claimed) {
      if (AppKeyboard.keyClaim == _editorKey) AppKeyboard.keyClaim = _prevClaim;
      _claimed = false;
      _prevClaim = null;
    }
    final t = _editText, f = _editFocus;
    _editText = null;
    _editFocus = null;
    if (t != null || f != null) {
      // after this frame: the field may still be mounted while it is torn down
      WidgetsBinding.instance.addPostFrameCallback((_) {
        t?.dispose();
        f?.dispose();
      });
    }
    if (!notify) {
      _editingId.value = null;
      return;
    }
    if (_editingId.value != null) {
      _editingId.value = null;
      if (mounted) setState(() => _layer = null);
    }
  }

  /// Enter confirms, Shift+Enter is a new line in a multiline item, Esc cancels.
  bool _editorKey(KeyDownEvent e) {
    final id = _editingId.value;
    if (id == null) return false;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _cancelEdit();
      return true;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        final it = _ctl.itemById(id);
        final st = it == null ? null : widget.inlineStyle?.call(context, it, _scale);
        if (st?.multiline ?? false) {
          final t = _editText!;
          final sel = t.selection.isValid ? t.selection : TextSelection.collapsed(offset: t.text.length);
          t.value = t.value.copyWith(
            text: t.text.replaceRange(sel.start, sel.end, '\n'),
            selection: TextSelection.collapsed(offset: sel.start + 1),
            composing: TextRange.empty,
          );
          return true;
        }
      }
      _commitEdit();
      return true;
    }
    return false;
  }

  void _commitEdit() {
    final id = _editingId.value, t = _editText;
    if (id == null || t == null) return;
    final text = t.text;
    final changed = text != _editOriginal;
    _closeEditor();
    if (changed && widget.onInlineCommit != null) {
      _ctl.commitText(id, text, widget.onInlineCommit!);
    } else {
      _ctl.endTextEdit();
    }
    if (mounted) _focus.requestFocus();
  }

  void _cancelEdit() {
    if (_editingId.value == null) return;
    _closeEditor();
    _ctl.endTextEdit();
    if (mounted) _focus.requestFocus();
  }

  /// Opens the editor on [id] when its item has text to edit; false otherwise.
  bool _tryEdit(String id) {
    if (!widget.canEditText) return false;
    final it = _ctl.itemById(id);
    if (it == null || it.locked || !it.visible || widget.inlineText!(it) == null) return false;
    return _ctl.startTextEdit(id);
  }

  Widget _editor(BuildContext context, Offset origin, double scale) {
    final id = _editingId.value;
    final it = id == null ? null : _ctl.itemById(id);
    final t = _editText, f = _editFocus;
    if (it == null || t == null || f == null) return const SizedBox.shrink();
    final c = context.colors;
    final theme = Theme.of(context);
    final st = widget.inlineStyle?.call(context, it, scale) ??
        StudioInlineStyle(style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(fontSize: 14));
    final r = _ctl.rectOf(it.id) ?? it.rect;
    final w = math.max(r.width * scale, 48.0);
    final h = math.max(r.height * scale, 1.0);
    final style = st.style.copyWith(inherit: true);
    Widget field = TextField(
      key: const ValueKey('studio-inline-editor'),
      controller: t,
      focusNode: f,
      style: style,
      textAlign: st.textAlign,
      textDirection: st.textDirection,
      maxLines: st.multiline ? null : 1,
      minLines: 1,
      keyboardType: st.multiline ? TextInputType.multiline : TextInputType.text,
      textInputAction: st.multiline ? TextInputAction.newline : TextInputAction.done,
      cursorColor: c.primary,
      decoration: const InputDecoration.collapsed(hintText: null).copyWith(isDense: true, contentPadding: EdgeInsets.zero),
      onSubmitted: (_) => _commitEdit(),
      onTapOutside: (_) => _commitEdit(),
    );
    field = Container(
      constraints: BoxConstraints(minHeight: h),
      padding: st.padding,
      decoration: BoxDecoration(
        color: st.background ?? widget.pageColor,
        border: Border.all(color: c.primary, width: 1.5),
        boxShadow: AppShadow.card(context),
      ),
      alignment: switch (st.textAlign) {
        TextAlign.center => Alignment.center,
        _ => AlignmentDirectional.centerStart,
      },
      child: Material(type: MaterialType.transparency, child: field),
    );
    if (it.rotation != 0) field = Transform.rotate(angle: it.rotation * math.pi / 180, child: field);
    return Positioned(
      left: origin.dx + r.left * scale - (w - r.width * scale) / 2,
      top: origin.dy + r.top * scale,
      width: w,
      child: Semantics(textField: true, label: translate('studio_edit_text'), child: field),
    );
  }

  // ── Context menu ─────────────────────────────────────────────────────────────────────────────────────────
  Future<void> _showMenu(Offset global, String? id) async {
    if (!widget.contextMenu) return;
    if (id != null && !_ctl.isSelected(id)) _ctl.select(id);
    if (id == null && !_ctl.canPaste) return;
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final c = context.colors;
    final sel = _ctl.selection.isNotEmpty;
    final locked = _ctl.selectionLocked;
    final editable = _ctl.hasEditableSelection;
    final single = _ctl.single;
    final canText = single != null && !single.locked && widget.canEditText && widget.inlineText!(single) != null;
    final mod = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS ? '⌘' : 'Ctrl+';
    PopupMenuEntry<_Cmd> item(_Cmd cmd, IconData icon, String key, {bool enabled = true, String? keys, bool danger = false}) =>
        PopupMenuItem<_Cmd>(
          value: cmd,
          enabled: enabled,
          height: AppTouch.min,
          child: Row(children: [
            Icon(icon, size: 18, color: !enabled ? c.textLight : (danger ? c.danger : c.textMedium)),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(translate(key), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (keys != null && !_touch) ...[
              const SizedBox(width: AppSpace.md),
              Text(keys, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: c.textLight)),
            ],
          ]),
        );
    final cmd = await showMenu<_Cmd>(
      context: context,
      position: RelativeRect.fromRect(Rect.fromLTWH(global.dx, global.dy, 1, 1), Offset.zero & overlay.size),
      items: [
        if (canText) ...[item(_Cmd.editText, Icons.edit_rounded, 'studio_edit_text'), const PopupMenuDivider()],
        if (sel) ...[
          item(_Cmd.cut, Icons.content_cut_rounded, 'studio_cut', enabled: editable, keys: '${mod}X'),
          item(_Cmd.copy, Icons.copy_rounded, 'studio_copy', keys: '${mod}C'),
        ],
        item(_Cmd.paste, Icons.content_paste_rounded, 'studio_paste', enabled: _ctl.canPaste, keys: '${mod}V'),
        if (sel) ...[
          item(_Cmd.duplicate, Icons.control_point_duplicate_rounded, 'studio_duplicate', keys: '${mod}D'),
          item(_Cmd.delete, Icons.delete_outline_rounded, 'studio_delete', enabled: editable, keys: 'Del', danger: true),
          const PopupMenuDivider(),
          item(_Cmd.forward, Icons.flip_to_front_rounded, 'studio_bring_forward'),
          item(_Cmd.backward, Icons.flip_to_back_rounded, 'studio_send_backward'),
          item(_Cmd.front, Icons.vertical_align_top_rounded, 'studio_bring_front'),
          item(_Cmd.back, Icons.vertical_align_bottom_rounded, 'studio_send_back'),
          if (_ctl.canLock) ...[
            const PopupMenuDivider(),
            locked
                ? item(_Cmd.lock, Icons.lock_open_rounded, 'studio_unlock')
                : item(_Cmd.lock, Icons.lock_outline_rounded, 'studio_lock'),
          ],
        ],
      ],
    );
    if (!mounted || cmd == null) return;
    _run(cmd);
  }

  void _run(_Cmd cmd) {
    switch (cmd) {
      case _Cmd.editText:
        final s = _ctl.single;
        if (s != null) _tryEdit(s.id);
      case _Cmd.cut:
        _ctl.cut();
      case _Cmd.copy:
        _ctl.copy();
      case _Cmd.paste:
        _ctl.paste();
      case _Cmd.duplicate:
        _ctl.duplicate();
      case _Cmd.delete:
        _ctl.deleteSelection();
      case _Cmd.forward:
        _ctl.bringForward();
      case _Cmd.backward:
        _ctl.sendBackward();
      case _Cmd.front:
        _ctl.bringToFront();
      case _Cmd.back:
        _ctl.sendToBack();
      case _Cmd.lock:
        _ctl.toggleLock();
    }
    if (cmd != _Cmd.editText) _focus.requestFocus();
  }

  void _onSecondaryTapUp(TapUpDetails d) {
    if (_editingId.value != null) return;
    final (_, id) = _hit(d.localPosition);
    _showMenu(d.globalPosition, id);
  }

  void _onLongPressStart(LongPressStartDetails d) {
    if (_editingId.value != null) return;
    _ctl.cancelGesture();
    _mode = _Mode.none;
    if (_onRotateKnob(d.localPosition)) return;
    final (h, id) = _hit(d.localPosition);
    if (h != null) return;
    if (id != null && _tryEdit(id)) return;
    _showMenu(d.globalPosition, id);
  }

  Offset _clampOrigin(Offset o, Size page) {
    double axis(double v, double view, double size) {
      final m = widget.padding;
      if (size + 2 * m <= view) return (view - size) / 2;
      return v.clamp(view - size - m, m).toDouble();
    }

    return Offset(axis(o.dx, _viewport.width, page.width), axis(o.dy, _viewport.height, page.height));
  }

  void _queueViewport() {
    if (_viewportQueued) return;
    _viewportQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportQueued = false;
      if (mounted && _viewport.width > 0) _ctl.setViewport(_viewport, padding: widget.padding, extra: _extra);
    });
  }

  Size get _extra => Size(widget.paperInsets.horizontal, widget.paperInsets.vertical);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canvas = ListenableBuilder(
      listenable: _ctl,
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        _viewport = box.biggest;
        final zoom = _ctl.fitted ? _ctl.fitZoomFor(_viewport, padding: widget.padding, extra: _extra) : _ctl.zoom;
        final scale = zoom * _ctl.page.unitPx;
        _queueViewport();
        final pageSize = Size(_ctl.page.width * scale, _ctl.page.height * scale);
        final last = _lastScale, o = _origin;
        if (last != null && o != null && last != scale) {
          final a = _anchor ?? _viewport.center(Offset.zero);
          _origin = a - (a - o) * (scale / last);
        }
        _anchor = null;
        _lastScale = scale;
        _scale = scale;
        // the paper = the page plus its insets; the stored origin is the PAGE's, the clamp works on the paper
        final ins = widget.paperInsets;
        final hasPaper = ins != EdgeInsets.zero;
        final insetOff = Offset(ins.left * scale, ins.top * scale);
        final paperSize = Size(pageSize.width + ins.horizontal * scale, pageSize.height + ins.vertical * scale);
        final paperOrigin = _clampOrigin(
          _origin == null
              ? Offset((_viewport.width - paperSize.width) / 2, (_viewport.height - paperSize.height) / 2)
              : _origin! - insetOff,
          paperSize,
        );
        var origin = _origin = paperOrigin + insetOff;
        final reveal = _ctl.takeReveal();
        final rr = reveal == null ? null : _ctl.rectOf(reveal);
        if (rr != null) {
          final m = widget.padding;
          final r = Rect.fromLTWH(origin.dx + rr.left * scale, origin.dy + rr.top * scale, rr.width * scale, rr.height * scale);
          var dx = 0.0, dy = 0.0;
          if (r.width + 2 * m <= _viewport.width) {
            if (r.left < m) dx = m - r.left;
            if (r.right > _viewport.width - m) dx = _viewport.width - m - r.right;
          }
          if (r.height + 2 * m <= _viewport.height) {
            if (r.top < m) dy = m - r.top;
            if (r.bottom > _viewport.height - m) dy = _viewport.height - m - r.bottom;
          }
          if (dx != 0 || dy != 0) {
            origin = _origin = _clampOrigin(origin + Offset(dx, dy) - insetOff, paperSize) + insetOff;
          }
        }
        if (_layer == null || _layerScale != scale) {
          _layerScale = scale;
          _layer = _StudioPageLayer<P>(
            controller: _ctl,
            scale: scale,
            builder: widget.itemBuilder,
            paper: widget.pageColor,
            background: widget.pageBackground,
            overlay: widget.overlayBuilder,
            decorate: !hasPaper,
            hidden: _editingId,
          );
          final theme = Theme.of(context);
          _overlay = CustomPaint(
            painter: _OverlayPainter(
              ctl: _ctl,
              scale: scale,
              marquee: _marquee,
              touch: _touch,
              primary: c.primary,
              onPrimary: theme.colorScheme.onPrimary,
              guide: c.danger,
              paper: widget.pageColor,
              muted: c.textLight,
              label: TextStyle(
                fontFamily: theme.textTheme.bodySmall?.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          );
        }
        return Stack(clipBehavior: Clip.hardEdge, children: [
          if (hasPaper)
            Positioned(
              left: paperOrigin.dx,
              top: paperOrigin.dy,
              width: paperSize.width,
              height: paperSize.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: widget.pageColor, boxShadow: AppShadow.card(context)),
                  child: widget.paperBuilder == null ? const SizedBox.expand() : widget.paperBuilder!(context, scale),
                ),
              ),
            ),
          Positioned(
            left: origin.dx,
            top: origin.dy,
            width: pageSize.width,
            height: pageSize.height,
            child: _layer!,
          ),
          Positioned(
            left: origin.dx,
            top: origin.dy,
            width: pageSize.width,
            height: pageSize.height,
            child: IgnorePointer(child: _overlay!),
          ),
          if (_ctl.showRulers)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RulerPainter(
                    origin: origin,
                    scale: scale,
                    page: _ctl.page.size,
                    unitPx: _ctl.page.unitPx,
                    band: c.cardBg,
                    ink: c.textMedium,
                    line: c.divider,
                    label: TextStyle(fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily, fontSize: 9, color: c.textMedium),
                    selection: _ctl.selectionBounds,
                    accent: c.primary,
                  ),
                ),
              ),
            ),
          if (_editingId.value != null) _editor(context, origin, scale),
        ]);
      }),
    );

    final gestures = RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        // touch only: a held mouse button must still drag
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus}),
          (r) => r.onLongPressStart = _onLongPressStart,
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
        onSecondaryTapUp: widget.contextMenu ? _onSecondaryTapUp : null,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: ColoredBox(color: c.background, child: SizedBox.expand(child: canvas)),
      ),
    );

    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Semantics(
        container: true,
        label: translate('studio_canvas'),
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerSignal: _onSignal,
          child: ValueListenableBuilder<MouseCursor>(
            valueListenable: _cursor,
            builder: (context, cursor, child) => MouseRegion(cursor: cursor, onHover: _onHover, child: child),
            child: gestures,
          ),
        ),
      ),
    );
  }

  // ── Hit-testing ──────────────────────────────────────────────────────────────────────────────────────────
  Offset _toPage(Offset local) => (local - (_origin ?? Offset.zero)) / _scale;

  (StudioHandle?, String?) _hit(Offset local) {
    final o = _origin ?? Offset.zero;
    final r = _ctl.resizable;
    if (r != null) {
      final rect = _ctl.rectOf(r.id)!;
      final screen = Rect.fromLTWH(o.dx + rect.left * _scale, o.dy + rect.top * _scale, rect.width * _scale, rect.height * _scale);
      // a turned item's handles are turned with it: test the pointer in the item's own frame
      final lp = studioUnrotate(local, screen.center, _ctl.rotationOf(r.id));
      for (final h in studioVisibleHandles(r.resize, screen.size, touch: _touch)) {
        if (_handleHitBox(h, screen, _touch).contains(lp)) return (h, null);
      }
    }
    final p = _toPage(local);
    final tol = 4 / _scale;
    for (final it in _ctl.items.reversed) {
      if (!it.visible) continue;
      final rect = _ctl.rectOf(it.id) ?? it.rect;
      if (rect.inflate(tol).contains(studioUnrotate(p, rect.center, _ctl.rotationOf(it.id)))) return (null, it.id);
    }
    return (null, null);
  }

  /// The screen rect of the rotatable item and the rotate knob's position, or null.
  (Rect, Offset)? _rotateKnob() {
    final it = _ctl.rotatable;
    if (it == null) return null;
    final rect = _ctl.rectOf(it.id)!;
    final o = _origin ?? Offset.zero;
    final screen = Rect.fromLTWH(o.dx + rect.left * _scale, o.dy + rect.top * _scale, rect.width * _scale, rect.height * _scale);
    return (screen, studioRotateHandle(screen, _ctl.rotationOf(it.id), touch: _touch));
  }

  bool _onRotateKnob(Offset local) {
    final k = _rotateKnob();
    if (k == null) return false;
    return (local - k.$2).distance <= (_touch ? AppTouch.min / 2 : 12);
  }

  /// The pointer's angle (degrees) about the centre of the item being turned.
  double _angleAt(Offset local) {
    final k = _rotateKnob();
    final c = k?.$1.center ?? Offset.zero;
    return math.atan2(local.dy - c.dy, local.dx - c.dx) * 180 / math.pi + 90;
  }

  bool get _additive {
    final k = HardwareKeyboard.instance;
    return k.isShiftPressed || k.isControlPressed || k.isMetaPressed;
  }

  // ── Pointer ──────────────────────────────────────────────────────────────────────────────────────────────
  /// Touch and mouse draw different handle sizes: a change of device redraws the overlay.
  void _setKind(PointerDeviceKind k) {
    final was = _touch;
    _kind = k;
    if (was != _touch) setState(() => _layer = null);
  }

  void _onPointerDown(PointerDownEvent e) {
    _setKind(e.kind);
    _down = e.localPosition;
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  void _onHover(PointerHoverEvent e) {
    _setKind(e.kind);
    final (h, id) = _hit(e.localPosition);
    MouseCursor cur = SystemMouseCursors.basic;
    if (_onRotateKnob(e.localPosition)) {
      cur = SystemMouseCursors.grab;
    } else if (h != null) {
      cur = switch (h) {
        StudioHandle.topLeft || StudioHandle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
        StudioHandle.topRight || StudioHandle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
        StudioHandle.left || StudioHandle.right => SystemMouseCursors.resizeLeftRight,
        StudioHandle.top || StudioHandle.bottom => SystemMouseCursors.resizeUpDown,
      };
    } else if (id != null && !(_ctl.itemById(id)?.locked ?? true)) {
      cur = SystemMouseCursors.move;
    }
    if (_cursor.value != cur) _cursor.value = cur;
  }

  void _onTapUp(TapUpDetails d) {
    if (_onRotateKnob(d.localPosition)) return;
    final (h, id) = _hit(d.localPosition);
    if (h != null) return;
    if (id == null) {
      if (!_additive) _ctl.clearSelection();
      return;
    }
    final now = DateTime.now();
    final dbl = id == _lastTapId && now.difference(_lastTapAt) < kDoubleTapTimeout;
    _lastTapId = id;
    _lastTapAt = now;
    if (dbl) {
      _lastTapId = null;
      if (_tryEdit(id)) return;
      if (widget.onItemDoubleTap != null) {
        _ctl.select(id);
        widget.onItemDoubleTap!(id);
        return;
      }
    }
    _ctl.select(id, additive: _additive);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startFocal = d.localFocalPoint;
    _startOrigin = _origin ?? Offset.zero;
    _startScale = _scale;
    if (d.pointerCount >= 2 || d.kind == PointerDeviceKind.trackpad) {
      _ctl.cancelGesture();
      _mode = _Mode.view;
      return;
    }
    if (_onRotateKnob(_down)) {
      _mode = _ctl.beginRotate(_angleAt(_down)) ? _Mode.rotate : _Mode.none;
      return;
    }
    final (h, id) = _hit(_down);
    if (h != null) {
      _mode = _ctl.beginResize(h) ? _Mode.resize : _Mode.none;
      return;
    }
    if (id != null) {
      if (!_ctl.isSelected(id)) _ctl.select(id, additive: _additive);
      _mode = _ctl.beginMove() ? _Mode.move : _Mode.none;
      return;
    }
    if (widget.marquee && !_touch) {
      _mode = _Mode.marquee;
      _marqueeAdd = _additive;
      _marqueeFrom = _toPage(_down);
      _marquee.value = Rect.fromPoints(_marqueeFrom, _marqueeFrom);
      return;
    }
    _mode = _Mode.view;
    _startFocal = _down;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    switch (_mode) {
      case _Mode.move:
        _ctl.updateMove((d.localFocalPoint - _down) / _scale, constrain: shift);
      case _Mode.resize:
        _ctl.updateResize((d.localFocalPoint - _down) / _scale, keepAspect: shift);
      case _Mode.rotate:
        _ctl.updateRotate(_angleAt(d.localFocalPoint), snap: shift);
      case _Mode.marquee:
        _marquee.value = Rect.fromPoints(_marqueeFrom, _toPage(d.localFocalPoint));
      case _Mode.view:
        if ((d.scale - 1).abs() > 1e-3) {
          _ctl.setZoom(_startScale / _ctl.page.unitPx * d.scale);
          final next = _ctl.zoom * _ctl.page.unitPx;
          setState(() {
            _origin = d.localFocalPoint - (_startFocal - _startOrigin) * (next / _startScale);
            _lastScale = next;
          });
        } else {
          setState(() => _origin = _startOrigin + (d.localFocalPoint - _startFocal));
        }
      case _Mode.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    switch (_mode) {
      case _Mode.move || _Mode.resize || _Mode.rotate:
        _ctl.endGesture();
      case _Mode.marquee:
        final r = _marquee.value;
        _marquee.value = null;
        if (r != null && (r.width > 0 || r.height > 0)) _ctl.selectInRect(r, additive: _marqueeAdd);
      case _Mode.view || _Mode.none:
        break;
    }
    _mode = _Mode.none;
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final s = ev as PointerScrollEvent;
      final k = HardwareKeyboard.instance;
      if (k.isControlPressed || k.isMetaPressed) {
        _anchor = s.localPosition;
        _ctl.setZoom(_scale / _ctl.page.unitPx * math.exp(-s.scrollDelta.dy / 400));
      } else {
        final delta = k.isShiftPressed ? Offset(s.scrollDelta.dy, 0) : s.scrollDelta;
        setState(() => _origin = (_origin ?? Offset.zero) - delta);
      }
    });
  }

  // ── Keyboard ─────────────────────────────────────────────────────────────────────────────────────────────
  bool _editingText() {
    final f = FocusManager.instance.primaryFocus;
    if (f == null || f == _focus) return false;
    final ctx = f.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent || _editingText()) return KeyEventResult.ignored;
    final k = HardwareKeyboard.instance;
    final mod = k.isControlPressed || k.isMetaPressed;
    final shift = k.isShiftPressed;
    final key = e.logicalKey, phys = e.physicalKey;
    bool letter(LogicalKeyboardKey l, PhysicalKeyboardKey p) => key == l || phys == p;
    if (mod) {
      if (letter(LogicalKeyboardKey.keyZ, PhysicalKeyboardKey.keyZ)) {
        shift ? _ctl.redo() : _ctl.undo();
      } else if (letter(LogicalKeyboardKey.keyY, PhysicalKeyboardKey.keyY)) {
        _ctl.redo();
      } else if (letter(LogicalKeyboardKey.keyD, PhysicalKeyboardKey.keyD)) {
        _ctl.duplicate();
      } else if (letter(LogicalKeyboardKey.keyA, PhysicalKeyboardKey.keyA)) {
        _ctl.selectAll();
      } else if (letter(LogicalKeyboardKey.keyC, PhysicalKeyboardKey.keyC)) {
        if (_ctl.selection.isEmpty) return KeyEventResult.ignored;
        _ctl.copy();
      } else if (letter(LogicalKeyboardKey.keyX, PhysicalKeyboardKey.keyX)) {
        if (_ctl.selection.isEmpty) return KeyEventResult.ignored;
        _ctl.cut();
      } else if (letter(LogicalKeyboardKey.keyV, PhysicalKeyboardKey.keyV)) {
        if (!_ctl.canPaste) return KeyEventResult.ignored;
        _ctl.paste();
      } else if (letter(LogicalKeyboardKey.keyL, PhysicalKeyboardKey.keyL)) {
        if (!_ctl.canLock) return KeyEventResult.ignored;
        _ctl.toggleLock();
      } else if (key == LogicalKeyboardKey.bracketRight || phys == PhysicalKeyboardKey.bracketRight) {
        if (_ctl.selection.isEmpty) return KeyEventResult.ignored;
        _ctl.bringToFront();
      } else if (key == LogicalKeyboardKey.bracketLeft || phys == PhysicalKeyboardKey.bracketLeft) {
        if (_ctl.selection.isEmpty) return KeyEventResult.ignored;
        _ctl.sendToBack();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    final hasSel = _ctl.selection.isNotEmpty;
    final (dx, dy) = switch (key) {
      LogicalKeyboardKey.arrowLeft => (-1, 0),
      LogicalKeyboardKey.arrowRight => (1, 0),
      LogicalKeyboardKey.arrowUp => (0, -1),
      LogicalKeyboardKey.arrowDown => (0, 1),
      _ => (0, 0),
    };
    if (dx != 0 || dy != 0) {
      if (!hasSel) return KeyEventResult.ignored;
      _ctl.nudge(dx, dy, big: shift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.bracketRight || key == LogicalKeyboardKey.bracketLeft) {
      if (!hasSel) return KeyEventResult.ignored;
      key == LogicalKeyboardKey.bracketRight ? _ctl.bringForward() : _ctl.sendBackward();
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.f2) && _ctl.single != null) {
      return _tryEdit(_ctl.single!.id) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      if (!hasSel) return KeyEventResult.ignored;
      _ctl.deleteSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_ctl.dragging) {
        _ctl.cancelGesture();
        _mode = _Mode.none;
        return KeyEventResult.handled;
      }
      if (!hasSel) return KeyEventResult.ignored;
      _ctl.clearSelection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// The handles drawn for an item of [mode] whose frame measures [screen] pixels: corners only for aspect items,
/// two for one-axis items, and the mid-edge handles only when the side is long enough to tell them apart.
List<StudioHandle> studioVisibleHandles(StudioResize mode, Size screen, {bool touch = false}) {
  final minSide = touch ? AppTouch.min * 1.5 : 36.0;
  switch (mode) {
    case StudioResize.none:
      return const [];
    case StudioResize.horizontal:
      return const [StudioHandle.left, StudioHandle.right];
    case StudioResize.vertical:
      return const [StudioHandle.top, StudioHandle.bottom];
    case StudioResize.aspect:
      return const [StudioHandle.topLeft, StudioHandle.topRight, StudioHandle.bottomRight, StudioHandle.bottomLeft];
    case StudioResize.free:
      return [
        StudioHandle.topLeft,
        StudioHandle.topRight,
        StudioHandle.bottomRight,
        StudioHandle.bottomLeft,
        if (screen.width >= minSide) ...[StudioHandle.top, StudioHandle.bottom],
        if (screen.height >= minSide) ...[StudioHandle.left, StudioHandle.right],
      ];
  }
}

/// The handle's hit box: AppTouch.min square on touch (20 px with a mouse), pushed outward by a quarter so it
/// covers little of the item.
Rect _handleHitBox(StudioHandle h, Rect screen, bool touch) {
  final size = touch ? AppTouch.min : 20.0;
  final p = h.pointOn(screen);
  final push = size / 4;
  final ox = h.movesLeft ? -push : (h.movesRight ? push : 0.0);
  final oy = h.movesTop ? -push : (h.movesBottom ? push : 0.0);
  return Rect.fromCenter(center: Offset(p.x + ox, p.y + oy), width: size, height: size);
}

class _StudioScale extends InheritedWidget {
  const _StudioScale({required this.scale, required super.child});
  final double scale;

  @override
  bool updateShouldNotify(_StudioScale old) => old.scale != scale;
}

/// The page and its items. Rebuilt when the controller's structure changes (or the scale), never per pointer move.
class _StudioPageLayer<P> extends StatefulWidget {
  const _StudioPageLayer({
    required this.controller,
    required this.scale,
    required this.builder,
    required this.paper,
    this.background,
    this.overlay,
    this.decorate = true,
    this.hidden,
  });

  final StudioController<P> controller;
  final double scale;
  final StudioItemBuilder<P> builder;

  /// The item being edited in place: drawn invisible (the editor stands in for it).
  final ValueListenable<String?>? hidden;
  final Color paper;
  final Widget? background;
  final Widget Function(BuildContext context, double scale)? overlay;

  /// false when a larger paper is drawn behind the page (StudioCanvas.paperInsets).
  final bool decorate;

  @override
  State<_StudioPageLayer<P>> createState() => _StudioPageLayerState<P>();
}

class _StudioPageLayerState<P> extends State<_StudioPageLayer<P>> {
  /// The item views of the last build. While the controller's item list is the same object (a selection change,
  /// a zoom-free notification) an unchanged item keeps its widget INSTANCE, so Flutter skips it entirely: 150
  /// items do not rebuild because one was selected.
  final _cache = <String, _ItemView<P>>{};
  List<StudioItem<P>>? _itemsAt;

  @override
  void didUpdateWidget(covariant _StudioPageLayer<P> old) {
    super.didUpdateWidget(old);
    _cache.clear();
    _itemsAt = null;
  }

  _ItemView<P> _view(StudioItem<P> it, bool selected, bool hidden) {
    final w = widget;
    final cached = _cache[it.id];
    if (cached != null && cached.selected == selected && cached.hidden == hidden) return cached;
    return _cache[it.id] = _ItemView<P>(
      key: ValueKey(it.id),
      controller: w.controller,
      item: it,
      selected: selected,
      scale: w.scale,
      builder: w.builder,
      hidden: hidden,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller, hidden = widget.hidden, scale = widget.scale;
    final paper = widget.paper, background = widget.background, overlay = widget.overlay, decorate = widget.decorate;
    final shadow = AppShadow.card(context);
    return _StudioScale(
      scale: scale,
      child: ListenableBuilder(
        listenable: hidden == null ? controller : Listenable.merge([controller, hidden]),
        builder: (context, _) {
          if (!identical(_itemsAt, controller.items)) {
            _cache.clear();
            _itemsAt = controller.items;
          }
          return DecoratedBox(
          decoration: decorate ? BoxDecoration(color: paper, boxShadow: shadow) : const BoxDecoration(),
          child: ClipRect(
            child: Stack(clipBehavior: Clip.none, children: [
              if (background != null) Positioned.fill(child: background),
              if (overlay != null) Positioned.fill(child: IgnorePointer(child: overlay(context, scale))),
              if (controller.showGrid)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GridPainter(
                        grid: controller.grid!,
                        scale: scale,
                        color: paper.computeLuminance() > .5 ? const Color(0x1F1C1C24) : const Color(0x26FFFFFF),
                      ),
                    ),
                  ),
                ),
              for (final it in controller.items)
                if (it.visible) _view(it, controller.isSelected(it.id), hidden?.value == it.id),
            ]),
          ),
        );
        },
      ),
    );
  }
}

class _ItemView<P> extends StatelessWidget {
  const _ItemView({
    super.key,
    required this.controller,
    required this.item,
    required this.selected,
    required this.scale,
    required this.builder,
    this.hidden = false,
  });

  final StudioController<P> controller;
  final StudioItem<P> item;
  final bool selected;
  final double scale;
  final StudioItemBuilder<P> builder;
  final bool hidden;

  Widget _positioned(Rect r, double rotation, Widget child) => Positioned(
        left: r.left * scale,
        top: r.top * scale,
        width: math.max(r.width * scale, 1),
        height: math.max(r.height * scale, 1),
        child: rotation == 0 && !selected ? child : Transform.rotate(angle: rotation * math.pi / 180, child: child),
      );

  @override
  Widget build(BuildContext context) {
    Widget child = IgnorePointer(child: RepaintBoundary(child: builder(context, item, selected)));
    if (hidden) child = Opacity(opacity: 0, child: child);
    // Only a selected item can move: the others never listen to the live signal.
    if (!selected) return _positioned(item.rect, item.rotation, child);
    return ListenableBuilder(
      listenable: controller.live,
      child: child,
      builder: (context, child) {
        final r = controller.rectOf(item.id) ?? item.rect;
        final rot = controller.rotationOf(item.id);
        if (r.size == item.rect.size) return _positioned(r, rot, child!);
        return _positioned(r, rot, IgnorePointer(child: RepaintBoundary(child: builder(context, item.copyWith(rect: r), selected))));
      },
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.ctl,
    required this.scale,
    required this.marquee,
    required this.touch,
    required this.primary,
    required this.onPrimary,
    required this.guide,
    required this.paper,
    required this.muted,
    required this.label,
  }) : super(repaint: Listenable.merge([ctl, ctl.live, marquee]));

  final StudioController<Object?> ctl;
  final double scale;
  final ValueListenable<Rect?> marquee;
  final bool touch;
  final Color primary, onPrimary, guide, paper, muted;
  final TextStyle label;

  Rect _s(Rect r) => Rect.fromLTWH(r.left * scale, r.top * scale, r.width * scale, r.height * scale);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final sel = ctl.selection;
    for (final it in ctl.items) {
      if (!sel.contains(it.id) || !it.visible) continue;
      final r = _s(ctl.rectOf(it.id) ?? it.rect);
      frame.color = it.locked ? muted : primary;
      final rot = ctl.rotationOf(it.id);
      if (rot == 0) {
        canvas.drawRect(r, frame);
      } else {
        canvas
          ..save()
          ..translate(r.center.dx, r.center.dy)
          ..rotate(rot * math.pi / 180)
          ..drawRect(Rect.fromCenter(center: Offset.zero, width: r.width, height: r.height), frame)
          ..restore();
      }
    }
    if (sel.length > 1) {
      final b = ctl.selectionBounds;
      if (b != null) {
        canvas.drawRect(
          _s(b).inflate(3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = primary.withValues(alpha: .45),
        );
      }
    }

    final res = ctl.resizable;
    if (res != null) {
      final r = _s(ctl.rectOf(res.id) ?? res.rect);
      final v = touch ? 12.0 : 9.0;
      final fill = Paint()..color = paper;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = primary;
      final rot = ctl.rotationOf(res.id);
      canvas.save();
      if (rot != 0) {
        canvas
          ..translate(r.center.dx, r.center.dy)
          ..rotate(rot * math.pi / 180)
          ..translate(-r.center.dx, -r.center.dy);
      }
      for (final h in studioVisibleHandles(res.resize, r.size, touch: touch)) {
        final p = h.pointOn(r);
        final box = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(p.x, p.y), width: v, height: v),
          const Radius.circular(2.5),
        );
        canvas
          ..drawRRect(box, fill)
          ..drawRRect(box, ring);
      }
      canvas.restore();
      if (ctl.dragging && !ctl.rotating) _sizeLabel(canvas, r, ctl.rectOf(res.id) ?? res.rect);
    }

    final rotItem = ctl.rotatable;
    if (rotItem != null) {
      final r = _s(ctl.rectOf(rotItem.id) ?? rotItem.rect);
      final rot = ctl.rotationOf(rotItem.id);
      final from = studioRotateHandleBase(r, rot), to = studioRotateHandle(r, rot, touch: touch);
      final stem = Paint()
        ..strokeWidth = 1
        ..color = primary;
      canvas.drawLine(from, to, stem);
      final knob = touch ? 8.0 : 6.0;
      canvas
        ..drawCircle(to, knob, Paint()..color = paper)
        ..drawCircle(
          to,
          knob,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = primary,
        );
      if (ctl.rotating) _angleLabel(canvas, to, rot);
    }

    final g = Paint()
      ..strokeWidth = 1
      ..color = guide;
    for (final l in ctl.guides) {
      final p = l.position * scale;
      if (l.vertical) {
        canvas.drawLine(Offset(p, l.start * scale), Offset(p, l.end * scale), g);
      } else {
        canvas.drawLine(Offset(l.start * scale, p), Offset(l.end * scale, p), g);
      }
    }

    final m = marquee.value;
    if (m != null) {
      final r = _s(m);
      canvas
        ..drawRect(r, Paint()..color = primary.withValues(alpha: .08))
        ..drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = primary.withValues(alpha: .7),
        );
    }
  }

  void _angleLabel(Canvas canvas, Offset at, double degrees) {
    final tp = TextPainter(
      text: TextSpan(text: '${degrees.round()}°', style: label),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final w = tp.width + 12, h = tp.height + 6;
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(at.dx - w / 2, at.dy - 18 - h, w, h), Radius.circular(h / 2));
    canvas.drawRRect(box, Paint()..color = primary);
    tp.paint(canvas, Offset(box.left + 6, box.top + 3));
  }

  void _sizeLabel(Canvas canvas, Rect screen, Rect units) {
    final tp = TextPainter(
      text: TextSpan(text: '${units.width.round()} × ${units.height.round()}', style: label),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final w = tp.width + 12, h = tp.height + 6;
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(screen.center.dx - w / 2, screen.bottom + 10, w, h),
      Radius.circular(h / 2),
    );
    canvas.drawRRect(box, Paint()..color = primary);
    tp.paint(canvas, Offset(box.left + 6, box.top + 3));
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => true;
}

/// Draws a [StudioBorder] and a background around [child] at the canvas scale: what an item builder (and a
/// preview) uses so both studios draw borders the same way. Widths and radius are page units × [scale].
class StudioBorderBox extends StatelessWidget {
  const StudioBorderBox({
    super.key,
    this.border = StudioBorder.none,
    this.background,
    this.scale = 1,
    this.child,
  });

  final StudioBorder border;
  final Color? background;
  final double scale;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _BorderPainter(border, background, scale),
        child: child == null
            ? const SizedBox.expand()
            : ClipRRect(borderRadius: BorderRadius.circular(border.radius * scale), child: child),
      );
}

class _BorderPainter extends CustomPainter {
  const _BorderPainter(this.border, this.background, this.scale);
  final StudioBorder border;
  final Color? background;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(border.radius * scale);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, radius);
    final bg = background;
    if (bg != null) canvas.drawRRect(outer, Paint()..color = bg);
    if (!border.visible) return;
    final w = math.max(border.width * scale, .5);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..color = border.color;
    switch (border.style) {
      case StudioBorderStyle.none:
        return;
      case StudioBorderStyle.solid:
        p.strokeWidth = w;
        canvas.drawRRect(outer.deflate(w / 2), p);
      case StudioBorderStyle.double:
        final line = math.max(w / 3, .5);
        p.strokeWidth = line;
        canvas
          ..drawRRect(outer.deflate(line / 2), p)
          ..drawRRect(outer.deflate(w - line / 2), p);
      case StudioBorderStyle.dashed:
        p.strokeWidth = w;
        final path = Path()..addRRect(outer.deflate(w / 2));
        final dash = math.max(w * 3, 4.0), gap = math.max(w * 2, 3.0);
        for (final metric in path.computeMetrics()) {
          var d = 0.0;
          while (d < metric.length) {
            canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), p);
            d += dash + gap;
          }
        }
    }
  }

  @override
  bool shouldRepaint(covariant _BorderPainter old) =>
      old.border != border || old.background != background || old.scale != scale;
}

/// Where the rotate handle's stem starts: the middle of the item's top edge, on the turned item (screen pixels).
Offset studioRotateHandleBase(Rect screen, double degrees) =>
    screen.center + _turn(Offset(0, -screen.height / 2), degrees);

/// Where the rotate handle's knob sits: [studioRotateStem] pixels beyond the middle of the top edge.
Offset studioRotateHandle(Rect screen, double degrees, {bool touch = false}) =>
    screen.center + _turn(Offset(0, -screen.height / 2 - studioRotateStem(touch)), degrees);

/// The stem's length: longer on touch so the knob clears the finger.
double studioRotateStem(bool touch) => touch ? 34 : 24;

Offset _turn(Offset d, double degrees) {
  final a = degrees * math.pi / 180;
  return Offset(d.dx * math.cos(a) - d.dy * math.sin(a), d.dx * math.sin(a) + d.dy * math.cos(a));
}

/// [p] turned back by [degrees] about [center]: where a point on a turned item lies on the item before the turn.
Offset studioUnrotate(Offset p, Offset center, double degrees) {
  if (degrees == 0) return p;
  final a = -degrees * math.pi / 180;
  final d = p - center;
  return center + Offset(d.dx * math.cos(a) - d.dy * math.sin(a), d.dx * math.sin(a) + d.dy * math.cos(a));
}

/// The snap grid drawn on the page: thin lines every grid step, a stronger one every 5.
class _GridPainter extends CustomPainter {
  const _GridPainter({required this.grid, required this.scale, required this.color});
  final Size grid;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final gx = grid.width * scale, gy = grid.height * scale;
    if (gx < 4 || gy < 4) return;
    final thin = Paint()
      ..color = color
      ..strokeWidth = .5;
    final strong = Paint()
      ..color = color.withValues(alpha: math.min(1, color.a * 2))
      ..strokeWidth = .8;
    var i = 0;
    for (var x = 0.0; x <= size.width + .5; x += gx, i++) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 5 == 0 ? strong : thin);
    }
    i = 0;
    for (var y = 0.0; y <= size.height + .5; y += gy, i++) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), i % 5 == 0 ? strong : thin);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.grid != grid || old.scale != scale || old.color != color;
}

/// Rulers along the canvas's top and left edges, in page units (the page's origin at 0), with the selection's
/// extent marked. Physical: the page is never mirrored, so the vertical ruler is on the left in Arabic too.
class _RulerPainter extends CustomPainter {
  const _RulerPainter({
    required this.origin,
    required this.scale,
    required this.page,
    required this.unitPx,
    required this.band,
    required this.ink,
    required this.line,
    required this.label,
    required this.accent,
    this.selection,
  });

  static const double thickness = 18;

  final Offset origin;
  final double scale, unitPx;
  final Size page;
  final Color band, ink, line, accent;
  final TextStyle label;
  final Rect? selection;

  /// A tick step (page units) that leaves at least ~8 px between ticks.
  double _step() {
    for (final s in const [1.0, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000]) {
      if (s * scale >= 8) return s.toDouble();
    }
    return 1000;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = band;
    final edge = Paint()
      ..color = line
      ..strokeWidth = 1;
    final tick = Paint()
      ..color = ink
      ..strokeWidth = 1;
    canvas
      ..drawRect(Rect.fromLTWH(0, 0, size.width, thickness), bg)
      ..drawRect(Rect.fromLTWH(0, 0, thickness, size.height), bg)
      ..drawLine(const Offset(0, thickness), Offset(size.width, thickness), edge)
      ..drawLine(const Offset(thickness, 0), Offset(thickness, size.height), edge);
    final sel = selection;
    if (sel != null) {
      final hi = Paint()..color = accent.withValues(alpha: .25);
      canvas
        ..drawRect(Rect.fromLTRB(origin.dx + sel.left * scale, 0, origin.dx + sel.right * scale, thickness), hi)
        ..drawRect(Rect.fromLTRB(0, origin.dy + sel.top * scale, thickness, origin.dy + sel.bottom * scale), hi);
    }
    final step = _step();
    final major = step * 5;
    void text(String s, Offset at, {bool vertical = false}) {
      final tp = TextPainter(text: TextSpan(text: s, style: label), textDirection: ui.TextDirection.ltr)..layout();
      if (vertical) {
        canvas
          ..save()
          ..translate(at.dx, at.dy)
          ..rotate(-math.pi / 2);
        tp.paint(canvas, Offset(-tp.width / 2, 0));
        canvas.restore();
      } else {
        tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy));
      }
      tp.dispose();
    }

    for (var u = 0.0; u <= page.width + 1e-6; u += step) {
      final x = origin.dx + u * scale;
      if (x < thickness || x > size.width) continue;
      final isMajor = (u / major - (u / major).round()).abs() < 1e-6;
      canvas.drawLine(Offset(x, thickness - (isMajor ? 8 : 4)), Offset(x, thickness), tick);
      if (isMajor) text(u.round().toString(), Offset(x, 1));
    }
    for (var u = 0.0; u <= page.height + 1e-6; u += step) {
      final y = origin.dy + u * scale;
      if (y < thickness || y > size.height) continue;
      final isMajor = (u / major - (u / major).round()).abs() < 1e-6;
      canvas.drawLine(Offset(thickness - (isMajor ? 8 : 4), y), Offset(thickness, y), tick);
      if (isMajor) text(u.round().toString(), Offset(1, y), vertical: true);
    }
    canvas.drawRect(const Rect.fromLTWH(0, 0, thickness, thickness), bg);
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => true;
}

/// The context menu's commands.
enum _Cmd { editText, cut, copy, paste, duplicate, delete, forward, backward, front, back, lock }
