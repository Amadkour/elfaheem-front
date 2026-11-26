// lib/features/notebook/notebook_editor.dart
//
// The two ways to write in the دفتر (SubjectProfile `nEdit`): with the keyboard (tool chips عنوان · نقاط · تظليل ·
// معادلة, one line at a time onto the ruled sheet) and with a finger or a stylus (four colours, pen · highlighter ·
// eraser, undo). The page being written is held by the panel; these widgets only report changes.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/notebook/notebook_models.dart';
import 'package:flutter_education_app/features/notebook/notebook_paper.dart';

/// The width / height of a new canvas.
const double kNotebookCanvasAspect = 1.1;

/// The tray the tools sit in (`nb-tools`): a soft well, chips wrapping onto a second row when they do not fit.
class NotebookToolTray extends StatelessWidget {
  const NotebookToolTray({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: context.colors.kit.track, borderRadius: BorderRadius.circular(AppRadius.tile)),
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.xs),
      child: Wrap(
        spacing: AppSpace.xs,
        runSpacing: AppSpace.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    ),
  );
}

class _TraySep extends StatelessWidget {
  const _TraySep();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: AppSpace.lg,
    child: VerticalDivider(width: AppSpace.xs, thickness: AppBorder.hairline, color: context.colors.kit.line),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// With the keyboard
// ═════════════════════════════════════════════════════════════════════════════

/// The chips of the keyboard mode; a chip on = the kind of the line being typed (off = a plain paragraph).
const List<(NoteBlockKind, String)> kNotebookTypeTools = [
  (NoteBlockKind.heading, 'sb_nb_tool_heading'),
  (NoteBlockKind.bullet, 'sb_nb_tool_bullets'),
  (NoteBlockKind.highlight, 'sb_nb_tool_highlight'),
  (NoteBlockKind.equation, 'sb_nb_tool_equation'),
];

class NotebookTypedEditor extends StatefulWidget {
  const NotebookTypedEditor({
    super.key,
    required this.caption,
    required this.blocks,
    required this.onBlocks,
    required this.controller,
    required this.kind,
    required this.onKind,
    this.autofocus = true,
  });

  final String caption;
  final List<NoteBlock> blocks;
  final ValueChanged<List<NoteBlock>> onBlocks;

  /// The line being typed (the panel saves what is still in it).
  final TextEditingController controller;
  final NoteBlockKind kind;
  final ValueChanged<NoteBlockKind> onKind;
  final bool autofocus;

  @override
  State<NotebookTypedEditor> createState() => _NotebookTypedEditorState();
}

class _NotebookTypedEditorState extends State<NotebookTypedEditor> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) {
      widget.onBlocks([...widget.blocks, NoteBlock(widget.kind, text)]);
      widget.controller.clear();
      // a heading is one line: the next line is a paragraph again
      if (widget.kind == NoteBlockKind.heading) widget.onKind(NoteBlockKind.paragraph);
    }
    _focus.requestFocus();
  }

  void _remove(int i) => widget.onBlocks([...widget.blocks]..removeAt(i));

  TextStyle _style(BuildContext context) {
    final c = context.colors;
    return switch (widget.kind) {
      NoteBlockKind.heading => AppType.headline(context).copyWith(color: c.kit.hot),
      NoteBlockKind.equation => AppType.bodyStrong(context).copyWith(color: c.textDark),
      _ => AppType.body(context).copyWith(color: c.textDark),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NotebookToolTray(
          children: [
            for (final (kind, key) in kNotebookTypeTools)
              AppChip(
                label: key.tr,
                selected: widget.kind == kind,
                onTap: () => widget.onKind(widget.kind == kind ? NoteBlockKind.paragraph : kind),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        NotebookPaper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.caption, style: AppType.meta(context).copyWith(color: c.textLight)),
              const SizedBox(height: AppSpace.xs),
              for (final (i, b) in widget.blocks.indexed)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _remove(i),
                  child: NotebookBlockView(block: b),
                ),
              if (widget.kind == NoteBlockKind.bullet)
                Text('•', style: AppType.body(context).copyWith(color: c.kit.hot)),
              TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                minLines: 1,
                maxLines: null,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _commit(),
                onEditingComplete: _commit,
                cursorColor: c.kit.live.color,
                style: _style(context),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                  hintText: 'sb_nb_type_hint'.tr,
                  hintStyle: AppType.body(context).copyWith(color: c.textLight),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// With a finger or a stylus
// ═════════════════════════════════════════════════════════════════════════════

enum NotebookPenTool { pen, highlighter, eraser }

/// The four ink colours, from theme roles (the dark ink, the live red, grape, sun), with their labels.
List<(Color, String)> notebookPenColors(BuildContext context) {
  final k = context.colors.kit;
  return [
    (k.ink, 'sb_nb_color_dark'),
    (k.live.color, 'sb_nb_color_red'),
    (k.accent(AppAccent.grape).color, 'sb_nb_color_purple'),
    (k.accent(AppAccent.sun).color, 'sb_nb_color_orange'),
  ];
}

/// A pan that wins at once, so a stroke never turns into a scroll of the panel.
class _InstantPan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class NotebookPenEditor extends StatefulWidget {
  const NotebookPenEditor({
    super.key,
    required this.caption,
    required this.blocks,
    required this.ink,
    required this.onInk,
  });

  final String caption;

  /// The typed part of the page, drawn above the canvas on the same sheet.
  final List<NoteBlock> blocks;

  /// Null: a new canvas, sized from the first layout.
  final NoteInk? ink;
  final ValueChanged<NoteInk> onInk;

  @override
  State<NotebookPenEditor> createState() => _NotebookPenEditorState();
}

class _NotebookPenEditorState extends State<NotebookPenEditor> {
  NotebookPenTool _tool = NotebookPenTool.pen;
  int _color = 0;
  InkStroke? _live;

  /// Snapshots before each change (undo).
  final _history = <List<InkStroke>>[];

  /// The ink as this editor last changed it (the panel's copy arrives a frame later).
  late NoteInk? _ink = widget.ink;

  @override
  void didUpdateWidget(NotebookPenEditor old) {
    super.didUpdateWidget(old);
    if (widget.ink != old.ink && widget.ink != _ink) _ink = widget.ink;
  }

  void _emit(NoteInk ink) {
    _ink = ink;
    widget.onInk(ink);
  }

  static const double _penWidth = 3;
  static const double _highlighterWidth = 18;
  static const double _eraserReach = 12;

  NoteInk _inkFor(Size box) => _ink ?? NoteInk(width: box.width, height: box.height);

  Offset _toSpace(Offset local, Size box, NoteInk ink) =>
      Offset(local.dx * ink.width / box.width, local.dy * ink.height / box.height);

  void _start(Offset local, Size box) {
    final ink = _inkFor(box);
    final p = _toSpace(local, box, ink);
    if (_tool == NotebookPenTool.eraser) {
      _history.add([...ink.strokes]);
      _erase(p, ink);
      return;
    }
    final colors = notebookPenColors(context);
    setState(
      () => _live = InkStroke(
        tool: _tool == NotebookPenTool.highlighter ? InkTool.highlighter : InkTool.pen,
        color: notebookHex(colors[_color].$1),
        width: _tool == NotebookPenTool.highlighter ? _highlighterWidth : _penWidth,
        points: [p],
      ),
    );
  }

  void _move(Offset local, Size box) {
    final ink = _inkFor(box);
    final p = _toSpace(local, box, ink);
    if (_tool == NotebookPenTool.eraser) {
      _erase(p, ink);
      return;
    }
    final s = _live;
    if (s == null) return;
    // skip points closer than a pixel: smaller paths, the same line
    if ((s.points.last - p).distance < 1) return;
    setState(() => s.points.add(p));
  }

  void _end(Size box) {
    final s = _live;
    if (s == null) return;
    final ink = _inkFor(box);
    _history.add([...ink.strokes]);
    _live = null;
    _emit(NoteInk(width: ink.width, height: ink.height, strokes: [...ink.strokes, s]));
  }

  void _erase(Offset p, NoteInk ink) {
    final keep = [
      for (final s in ink.strokes)
        if (!s.points.any((q) => (q - p).distance <= math.max(_eraserReach, s.width / 2))) s,
    ];
    if (keep.length != ink.strokes.length) {
      _emit(NoteInk(width: ink.width, height: ink.height, strokes: keep));
    }
  }

  void _undo() {
    final ink = _ink;
    if (_history.isEmpty || ink == null) return;
    setState(() => _emit(NoteInk(width: ink.width, height: ink.height, strokes: _history.removeLast())));
  }

  Widget _toolChip(NotebookPenTool t, String key) =>
      AppChip(label: key.tr, selected: _tool == t, onTap: () => setState(() => _tool = t));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colors = notebookPenColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NotebookToolTray(
          children: [
            for (final (i, (color, label)) in colors.indexed)
              _ColorDot(
                color: color,
                label: label.tr,
                selected: _color == i,
                onTap: () => setState(() {
                  _color = i;
                  if (_tool == NotebookPenTool.eraser) _tool = NotebookPenTool.pen;
                }),
              ),
            const _TraySep(),
            _toolChip(NotebookPenTool.pen, 'sb_nb_pen'),
            _toolChip(NotebookPenTool.highlighter, 'sb_nb_highlighter'),
            _toolChip(NotebookPenTool.eraser, 'sb_nb_eraser'),
            const _TraySep(),
            AppIconButton(icon: Icons.undo_rounded, tooltip: 'sb_nb_undo'.tr, onPressed: _history.isEmpty ? null : _undo),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        NotebookPaper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.caption, style: AppType.meta(context).copyWith(color: c.textLight)),
              for (final b in widget.blocks)
                if (b.text.trim().isNotEmpty) NotebookBlockView(block: b),
              const SizedBox(height: AppSpace.xs),
              AspectRatio(
                aspectRatio: _ink == null ? kNotebookCanvasAspect : _ink!.width / _ink!.height,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final size = box.biggest;
                    final ink = _inkFor(size);
                    return Semantics(
                      label: 'sb_nb_canvas'.tr,
                      child: RawGestureDetector(
                        behavior: HitTestBehavior.opaque,
                        gestures: {
                          _InstantPan: GestureRecognizerFactoryWithHandlers<_InstantPan>(
                            _InstantPan.new,
                            (r) => r
                              ..dragStartBehavior = DragStartBehavior.down
                              ..onStart = ((d) => _start(d.localPosition, size))
                              ..onUpdate = ((d) => _move(d.localPosition, size))
                              ..onEnd = ((_) => _end(size))
                              ..onCancel = (() => _end(size)),
                          ),
                        },
                        child: ClipRect(
                          child: CustomPaint(
                          painter: NotebookInkPainter(
                            strokes: ink.strokes,
                            space: Size(ink.width, ink.height),
                            fallback: c.textDark,
                            live: _live,
                          ),
                        ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.label, required this.selected, required this.onTap});

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: AppTouch.min / 2,
        child: SizedBox.square(
          dimension: AppTouch.min,
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.of(context).fast,
              width: AppIconSize.xl,
              height: AppIconSize.xl,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? c.textDark : c.cardBg,
                  width: selected ? AppBorder.focus : AppBorder.strong,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
