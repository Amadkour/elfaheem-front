// lib/features/teacher/sessions/live/whiteboard/board_toolbar.dart
//
// The whiteboard's chrome (D-087), presentational (plain values + callbacks; test/ui/whiteboard_layout_test.dart):
//
//   WhiteboardToolbar   the tool dock under the page: select · pen · highlighter · shapes ▸ · text · eraser · laser,
//                       undo / redo, colour, thickness (ink, shapes) or font size (text). Wide (≥ 980 px): one row.
//                       Narrower: two rows of 7 (tools; undo, redo, 4 colours, "style" for the rest). The shapes
//                       (line, arrow, rectangle, ellipse) and the narrow style panel open above the dock.
//   WhiteboardTopBar    over the page: what it is and whose, the page navigator (‹ 2 / 3 › and + for the presenter),
//                       "Board" (options) and Stop presenting.
//   WhiteboardOptionsLayout   the Board sheet: background, the page (clear / delete), students may draw (host),
//                       save as PNG.
//   BoardBackgroundTile a background's preview (the share sheet uses it too).
//
// Every control has a Semantics label and a 48 px target; keyboard shortcuts are in the tooltips on web / desktop.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import '../annotation/annotation_toolbar.dart' show AnnotToolButton, annotThicknessLabels, annotTypingInField;
import '../widgets/live_palette.dart';
import 'board_controller.dart';
import 'board_painter.dart';
import 'board_protocol.dart';

/// At or above this width the dock is one row.
const kBoardDockWideWidth = 980.0;

enum BoardPanel { none, style, shapes }

String boardToolLabel(BoardTool tool) => switch (tool) {
      BoardTool.select => t('تحديد ونقل', 'Select and move'),
      BoardTool.pen => t('قلم', 'Pen'),
      BoardTool.highlighter => t('قلم تظليل', 'Highlighter'),
      BoardTool.line => t('خط', 'Line'),
      BoardTool.arrow => t('سهم', 'Arrow'),
      BoardTool.rect => t('مستطيل', 'Rectangle'),
      BoardTool.ellipse => t('شكل بيضاوي', 'Ellipse'),
      BoardTool.text => t('نص', 'Text'),
      BoardTool.eraser => t('ممحاة', 'Eraser'),
      BoardTool.laser => t('مؤشر ليزر', 'Laser pointer'),
    };

String boardBackgroundLabel(BoardBackground b) => switch (b) {
      BoardBackground.white => t('أبيض', 'White'),
      BoardBackground.blackboard => t('سبورة', 'Blackboard'),
      BoardBackground.grid => t('مربعات', 'Grid'),
      BoardBackground.lined => t('مسطّر', 'Lined'),
    };

List<String> boardColorLabels(BoardBackground b) => boardIsDark(b)
    ? [t('طباشير', 'Chalk'), t('أصفر', 'Yellow'), t('وردي', 'Pink'), t('أزرق', 'Blue'), t('أخضر', 'Green'), t('برتقالي', 'Orange')]
    : [t('حبر', 'Ink'), t('أزرق', 'Blue'), t('أحمر', 'Red'), t('أخضر', 'Green'), t('برتقالي', 'Orange'), t('بنفسجي', 'Purple')];

List<String> boardFontLabels() => [t('نص صغير', 'Small text'), t('نص متوسط', 'Medium text'), t('نص كبير', 'Large text'), t('عنوان', 'Heading')];

String _toolKey(BoardTool tl) => switch (tl) {
      BoardTool.select => 'V',
      BoardTool.pen => 'P',
      BoardTool.highlighter => 'H',
      BoardTool.line => 'I',
      BoardTool.arrow => 'A',
      BoardTool.rect => 'R',
      BoardTool.ellipse => 'O',
      BoardTool.text => 'T',
      BoardTool.eraser => 'E',
      BoardTool.laser => 'L',
    };

bool get _keyboardPlatform =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

String _hint(String key) => _keyboardPlatform ? ' ($key)' : '';

IconData boardToolIcon(BoardTool tl) => switch (tl) {
      BoardTool.select => Icons.pan_tool_alt_rounded,
      BoardTool.pen => Icons.edit_rounded,
      BoardTool.highlighter => Icons.border_color_rounded,
      BoardTool.line => Icons.horizontal_rule_rounded,
      BoardTool.arrow => Icons.arrow_upward_rounded,
      BoardTool.rect => Icons.crop_square_rounded,
      BoardTool.ellipse => Icons.circle_outlined,
      BoardTool.text => Icons.title_rounded,
      BoardTool.eraser => Icons.auto_fix_normal_rounded,
      BoardTool.laser => Icons.ads_click_rounded,
    };

const _shapeTools = [BoardTool.line, BoardTool.arrow, BoardTool.rect, BoardTool.ellipse];
const _dockTools = [BoardTool.select, BoardTool.pen, BoardTool.highlighter, BoardTool.text, BoardTool.eraser, BoardTool.laser];

/// The tool dock.
class WhiteboardToolbar extends StatelessWidget {
  const WhiteboardToolbar({
    super.key,
    required this.tool,
    required this.color,
    required this.colors,
    required this.thickness,
    required this.fontStep,
    this.colorLabels,
    this.textStyle = false,
    this.canUndo = false,
    this.canRedo = false,
    this.wide,
    this.panel = BoardPanel.none,
    this.lastShape = BoardTool.rect,
    this.onTool,
    this.onColor,
    this.onThickness,
    this.onFontStep,
    this.onUndo,
    this.onRedo,
    this.onPanel,
  });

  final BoardTool tool;
  final Color color;
  final List<Color> colors;
  final List<String>? colorLabels;

  /// 0..2.
  final int thickness;

  /// 0..3.
  final int fontStep;

  /// The size control is the font size (the text tool, or a text box is selected).
  final bool textStyle;
  final bool canUndo;
  final bool canRedo;

  /// Null: by the available width ([kBoardDockWideWidth]).
  final bool? wide;
  final BoardPanel panel;

  /// The shape the shapes button shows when no shape tool is active.
  final BoardTool lastShape;

  final ValueChanged<BoardTool>? onTool;
  final ValueChanged<Color>? onColor;
  final ValueChanged<int>? onThickness;
  final ValueChanged<int>? onFontStep;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final ValueChanged<BoardPanel>? onPanel;

  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);
    return LayoutBuilder(builder: (context, c) {
      final oneRow = wide ?? (c.maxWidth.isFinite && c.maxWidth >= kBoardDockWideWidth);
      final shapeShown = tool.isShape ? tool : lastShape;
      Widget toolButton(BoardTool tl) => AnnotToolButton(
            key: ValueKey('board.tool.${tl.name}'),
            label: boardToolLabel(tl) + _hint(_toolKey(tl)),
            selected: tl == tool,
            onTap: onTool == null ? null : () => onTool!(tl),
            child: _ToolGlyph(tl, selected: tl == tool),
          );
      final tools = <Widget>[
        for (final tl in _dockTools.take(3)) toolButton(tl),
        AnnotToolButton(
          key: const ValueKey('board.shapes'),
          label: '${t('الأشكال', 'Shapes')}: ${boardToolLabel(shapeShown)}',
          selected: tool.isShape || panel == BoardPanel.shapes,
          onTap: onPanel == null ? null : () => onPanel!(panel == BoardPanel.shapes ? BoardPanel.none : BoardPanel.shapes),
          child: Stack(clipBehavior: Clip.none, children: [
            _ToolGlyph(shapeShown, selected: tool.isShape),
            PositionedDirectional(
              end: -7,
              bottom: -5,
              child: Icon(Icons.arrow_drop_up_rounded, size: 14, color: tool.isShape ? LivePalette.textHigh : LivePalette.textLow),
            ),
          ]),
        ),
        for (final tl in _dockTools.skip(3)) toolButton(tl),
      ];
      final history = <Widget>[
        AnnotToolButton(
          key: const ValueKey('board.undo'),
          label: t('تراجع', 'Undo') + _hint('Ctrl+Z'),
          onTap: canUndo ? onUndo : null,
          child: Icon(Icons.undo_rounded, size: 22, color: canUndo ? LivePalette.textMid : LivePalette.textLow),
        ),
        AnnotToolButton(
          key: const ValueKey('board.redo'),
          label: t('إعادة', 'Redo') + _hint('Ctrl+Y'),
          onTap: canRedo ? onRedo : null,
          child: Icon(Icons.redo_rounded, size: 22, color: canRedo ? LivePalette.textMid : LivePalette.textLow),
        ),
      ];
      final swatches = _swatches();
      final sizes = textStyle ? _fontButtons() : _thicknessButtons();

      final Widget dock;
      if (oneRow) {
        dock = _scroll(Row(mainAxisSize: MainAxisSize.min, children: [
          ...tools,
          const _Divider(),
          ...history,
          const _Divider(),
          for (final (i, (col, label)) in swatches.indexed) _swatch(i, col, label),
          const _Divider(),
          ...sizes,
        ]));
      } else {
        dock = Column(mainAxisSize: MainAxisSize.min, children: [
          _scroll(Row(mainAxisSize: MainAxisSize.min, children: tools)),
          Container(height: 1, width: 300, color: LivePalette.hairline),
          _scroll(Row(mainAxisSize: MainAxisSize.min, children: [
            ...history,
            const _Divider(),
            for (final (i, (col, label)) in swatches.take(4).indexed) _swatch(i, col, label),
            AnnotToolButton(
              key: const ValueKey('board.style'),
              label: textStyle ? t('اللون وحجم الخط', 'Colour and text size') : t('اللون والسُّمك', 'Colour and thickness'),
              selected: panel == BoardPanel.style,
              onTap: onPanel == null ? null : () => onPanel!(panel == BoardPanel.style ? BoardPanel.none : BoardPanel.style),
              child: Icon(Icons.tune_rounded, size: 22, color: panel == BoardPanel.style ? LivePalette.textHigh : LivePalette.textMid),
            ),
          ])),
        ]);
      }

      Widget? above;
      if (panel == BoardPanel.shapes) {
        above = _scroll(Row(
          key: const ValueKey('board.shapes_panel'),
          mainAxisSize: MainAxisSize.min,
          children: [for (final tl in _shapeTools) toolButton(tl)],
        ));
      } else if (panel == BoardPanel.style && !oneRow) {
        above = Column(key: const ValueKey('board.style_panel'), mainAxisSize: MainAxisSize.min, children: [
          _scroll(Row(mainAxisSize: MainAxisSize.min, children: [
            for (final (i, (col, label)) in swatches.indexed) _swatch(i, col, label),
          ])),
          _scroll(Row(mainAxisSize: MainAxisSize.min, children: sizes)),
        ]);
      }

      return Semantics(
        container: true,
        label: t('أدوات السبورة', 'Whiteboard tools'),
        child: Material(
          color: Colors.transparent,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (above != null) ...[
              _Glass(child: above),
              const SizedBox(height: 8),
            ],
            _Glass(child: dock),
          ]),
        ),
      );
    });
  }

  /// The presets, with the current colour first when it is not one of them.
  List<(Color, String)> _swatches() {
    final labels = colorLabels;
    final out = <(Color, String)>[
      for (var i = 0; i < colors.length; i++)
        (colors[i], labels != null && i < labels.length ? labels[i] : '${t('لون', 'Colour')} ${i + 1}'),
    ];
    if (!colors.any((c) => c.toARGB32() == color.toARGB32())) out.insert(0, (color, t('اللون الحالي', 'Current colour')));
    return out;
  }

  Widget _swatch(int i, Color col, String label) {
    final selected = col.toARGB32() == color.toARGB32();
    return AnnotToolButton(
      key: ValueKey('board.color.$i'),
      label: label,
      selected: selected,
      onTap: onColor == null ? null : () => onColor!(col),
      child: Container(
        width: selected ? 24 : 21,
        height: selected ? 24 : 21,
        decoration: BoxDecoration(
          color: col,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? LivePalette.textHigh : LivePalette.glassBorder, width: 2),
        ),
      ),
    );
  }

  List<Widget> _thicknessButtons() {
    final labels = annotThicknessLabels();
    return [
      for (var i = 0; i < 3; i++)
        AnnotToolButton(
          key: ValueKey('board.thickness.$i'),
          label: labels[i],
          selected: i == thickness,
          onTap: onThickness == null ? null : () => onThickness!(i),
          child: Container(
            width: 18,
            height: 2.0 + i * 2.5,
            decoration: BoxDecoration(
              color: i == thickness ? LivePalette.textHigh : LivePalette.textMid,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
    ];
  }

  List<Widget> _fontButtons() {
    final labels = boardFontLabels();
    const sizes = [12.0, 15.0, 19.0, 23.0];
    return [
      for (var i = 0; i < kBoardFontSizes.length; i++)
        AnnotToolButton(
          key: ValueKey('board.font.$i'),
          label: labels[i],
          selected: i == fontStep,
          onTap: onFontStep == null ? null : () => onFontStep!(i),
          child: Text(
            'A',
            style: appText(sizes[i], w: FontWeight.w800, c: i == fontStep ? LivePalette.textHigh : LivePalette.textMid, h: 1),
          ),
        ),
    ];
  }

  static Widget _scroll(Widget row) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: LivePalette.surfaceHi.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: LivePalette.glassBorder),
          boxShadow: [BoxShadow(color: LivePalette.shade(0.35), blurRadius: 22, offset: const Offset(0, 8))],
        ),
        child: child,
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 4), color: LivePalette.hairline);
}

class _ToolGlyph extends StatelessWidget {
  const _ToolGlyph(this.tool, {required this.selected});

  final BoardTool tool;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final col = selected ? LivePalette.textHigh : LivePalette.textMid;
    if (tool == BoardTool.eraser) {
      return Transform.rotate(
        angle: -0.6,
        child: Container(
          width: 20,
          height: 11,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: col, width: 2),
            gradient: LinearGradient(colors: [col, col, Colors.transparent, Colors.transparent], stops: const [0, 0.42, 0.42, 1]),
          ),
        ),
      );
    }
    final icon = Icon(boardToolIcon(tool), size: 22, color: col);
    // A line and an arrow are drawn on the diagonal (the same on every language: they are drawing tools, not directions).
    if (tool == BoardTool.line) return Transform.rotate(angle: -0.785, child: icon);
    if (tool == BoardTool.arrow) return Transform.rotate(angle: 0.785, child: icon);
    return icon;
  }
}

// ── The bar over the page ─────────────────────────────────────────────────────

class WhiteboardTopBar extends StatelessWidget {
  const WhiteboardTopBar({
    super.key,
    required this.presenting,
    required this.pageIndex,
    required this.pageCount,
    this.presenterName = '',
    this.canDraw = false,
    this.compact,
    this.onPrevious,
    this.onNext,
    this.onAddPage,
    this.onOptions,
    this.onStop,
  });

  /// This device presents the board (the page controls, Board and Stop).
  final bool presenting;
  final int pageIndex;
  final int pageCount;

  /// The viewer's title: "`name`'s whiteboard".
  final String presenterName;

  /// A viewer the host allowed to draw ("You can draw").
  final bool canDraw;
  final bool? compact;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onAddPage;
  final VoidCallback? onOptions;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 1000.0;
      final narrow = compact ?? w < 760;
      // A phone: Stop is the red icon alone, the viewer's "You can draw" a green pen.
      final tiny = w < 330;
      final title = presenting
          ? t('السبورة البيضاء', 'Whiteboard')
          : (presenterName.isEmpty ? t('السبورة البيضاء', 'Whiteboard') : t('سبورة $presenterName', "$presenterName's whiteboard"));
      final badge = Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [LivePalette.accent, LivePalette.accent2]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.draw_rounded, size: 17, color: LivePalette.textHigh),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appText(14, w: FontWeight.w800, c: LivePalette.textHigh)),
        ),
        if (canDraw && !presenting) ...[
          const SizedBox(width: 8),
          _Pill(icon: Icons.edit_rounded, label: t('يمكنك الرسم', 'You can draw'), iconOnly: tiny, color: LivePalette.success),
        ],
      ]);

      final pager = _Pager(
        index: pageIndex,
        count: pageCount,
        presenting: presenting,
        onPrevious: onPrevious,
        onNext: onNext,
        onAdd: onAddPage,
        showAddLabel: !narrow,
      );

      final stop = onStop == null ? null : _StopButton(onTap: onStop, compact: narrow, iconOnly: tiny);
      final actions = presenting
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              AnnotToolButton(
                key: const ValueKey('board.options'),
                label: t('إعدادات السبورة', 'Board options'),
                onTap: onOptions,
                child: const Icon(Icons.tune_rounded, size: 22, color: LivePalette.textHigh),
              ),
              if (stop != null) ...[const SizedBox(width: 4), Flexible(child: stop)],
            ])
          : (stop ?? const SizedBox.shrink()); // a host stops a participant's board

      final row = narrow
          ? Row(children: [
              if (presenting)
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: pager),
                  ),
                )
              else ...[
                Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: badge)),
                const SizedBox(width: 8),
                pager,
              ],
              const SizedBox(width: 8),
              actions,
            ])
          : Row(children: [
              Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: badge)),
              const SizedBox(width: 8),
              pager,
              const SizedBox(width: 8),
              Expanded(child: Align(alignment: AlignmentDirectional.centerEnd, child: actions)),
            ]);
      return Semantics(
        container: true,
        label: title,
        child: Material(color: Colors.transparent, child: row),
      );
    });
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.index,
    required this.count,
    required this.presenting,
    this.onPrevious,
    this.onNext,
    this.onAdd,
    this.showAddLabel = true,
  });

  final int index;
  final int count;
  final bool presenting;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onAdd;
  final bool showAddLabel;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      '${index + 1} / ${count < 1 ? 1 : count}',
      key: const ValueKey('board.page_label'),
      style: appText(13, w: FontWeight.w700, c: LivePalette.textHigh),
    );
    final pageWord = t('الصفحة ${index + 1} من $count', 'Page ${index + 1} of $count');
    if (!presenting) {
      return Semantics(
        label: pageWord,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: LivePalette.glass, borderRadius: BorderRadius.circular(20), border: Border.all(color: LivePalette.glassBorder)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.description_outlined, size: 15, color: LivePalette.textMid),
            const SizedBox(width: 6),
            label,
          ]),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(color: LivePalette.glass, borderRadius: BorderRadius.circular(24), border: Border.all(color: LivePalette.glassBorder)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnnotToolButton(
          key: const ValueKey('board.page_prev'),
          label: t('الصفحة السابقة', 'Previous page'),
          onTap: index > 0 ? onPrevious : null,
          child: Icon(Icons.chevron_left_rounded, size: 24, color: index > 0 ? LivePalette.textHigh : LivePalette.textLow),
        ),
        Semantics(label: pageWord, excludeSemantics: true, child: label),
        AnnotToolButton(
          key: const ValueKey('board.page_next'),
          label: t('الصفحة التالية', 'Next page'),
          onTap: index < count - 1 ? onNext : null,
          child: Icon(Icons.chevron_right_rounded, size: 24, color: index < count - 1 ? LivePalette.textHigh : LivePalette.textLow),
        ),
        Container(width: 1, height: 22, color: LivePalette.hairline),
        Semantics(
          button: true,
          label: t('صفحة جديدة', 'New page'),
          excludeSemantics: true,
          child: InkWell(
            key: const ValueKey('board.page_add'),
            onTap: count >= kBoardMaxPages ? null : onAdd,
            borderRadius: BorderRadius.circular(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 10, end: 14),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_rounded, size: 20, color: LivePalette.textHigh),
                  if (showAddLabel) ...[
                    const SizedBox(width: 4),
                    Text(t('صفحة', 'Page'), style: appText(13, w: FontWeight.w700, c: LivePalette.textHigh)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({this.onTap, this.compact = false, this.iconOnly = false});

  final VoidCallback? onTap;
  final bool compact;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final label = t('إيقاف العرض', 'Stop presenting');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: const ValueKey('board.stop'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : (compact ? 12 : 16)),
            decoration: BoxDecoration(
              color: LivePalette.danger,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: LivePalette.danger.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.stop_rounded, size: 22, color: LivePalette.textHigh),
              if (!iconOnly) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(compact ? t('إيقاف', 'Stop') : label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w800, c: LivePalette.textHigh)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color, this.iconOnly = false});

  final IconData icon;
  final String label;
  final Color color;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        excludeSemantics: true,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: iconOnly ? 6 : 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: LivePalette.textHigh),
            if (!iconOnly) ...[
              const SizedBox(width: 5),
              Text(label, maxLines: 1, style: appText(12, w: FontWeight.w700, c: LivePalette.textHigh)),
            ],
          ]),
        ),
      );
}

// ── Backgrounds ───────────────────────────────────────────────────────────────

/// A background's preview: a little page of it with a few strokes of its default ink, and its name.
class BoardBackgroundTile extends StatelessWidget {
  const BoardBackgroundTile({super.key, required this.background, required this.selected, this.onTap, this.dark = false});

  final BoardBackground background;
  final bool selected;
  final VoidCallback? onTap;

  /// Drawn on the dark room (the Board sheet) instead of a light sheet.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ring = selected ? c.primary : (dark ? LivePalette.glassBorder : c.divider);
    final label = boardBackgroundLabel(background);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('board.bg.${background.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: ring, width: selected ? 2.5 : 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: AspectRatio(
                  aspectRatio: kBoardAspect,
                  child: CustomPaint(
                    painter: _TilePainter(background),
                    child: selected
                        ? Align(
                            alignment: AlignmentDirectional.topEnd,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.check_circle_rounded, size: 18, color: c.primary),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: appText(12.5,
                    w: selected ? FontWeight.w800 : FontWeight.w600,
                    c: dark ? (selected ? LivePalette.textHigh : LivePalette.textMid) : (selected ? c.textDark : c.textMedium))),
          ]),
        ),
      ),
    );
  }
}

class _TilePainter extends CustomPainter {
  const _TilePainter(this.background);

  final BoardBackground background;

  @override
  void paint(Canvas canvas, Size size) {
    BoardBackgroundPainter(background).paint(canvas, size);
    final ink = boardInkColors(background);
    final w = size.width;
    final pen = Paint()
      ..color = ink.first
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.012).clamp(1.2, 3.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // a heading scribble, a shape and an arrow: "this is where you write"
    final h = size.height;
    final title = Path()
      ..moveTo(w * 0.1, h * 0.28)
      ..cubicTo(w * 0.16, h * 0.2, w * 0.2, h * 0.34, w * 0.26, h * 0.26)
      ..cubicTo(w * 0.31, h * 0.2, w * 0.34, h * 0.33, w * 0.4, h * 0.26);
    canvas.drawPath(title, pen);
    canvas.drawLine(Offset(w * 0.1, h * 0.46), Offset(w * 0.46, h * 0.46), pen..color = ink.first.withValues(alpha: 0.55));
    canvas.drawLine(Offset(w * 0.1, h * 0.6), Offset(w * 0.38, h * 0.6), pen);
    final accent = Paint()
      ..color = ink[2]
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.012).clamp(1.2, 3.0)
      ..strokeJoin = StrokeJoin.round;
    canvas.drawOval(Rect.fromLTWH(w * 0.58, h * 0.22, w * 0.3, h * 0.42), accent);
    final blue = Paint()
      ..color = ink[1]
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.012).clamp(1.2, 3.0)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.46, h * 0.78), Offset(w * 0.62, h * 0.66), blue);
  }

  @override
  bool shouldRepaint(_TilePainter old) => old.background != background;
}

// ── The Board sheet ───────────────────────────────────────────────────────────

/// The presenter's board options. [isHost] shows "Students may draw".
class WhiteboardOptionsLayout extends StatelessWidget {
  const WhiteboardOptionsLayout({
    super.key,
    required this.background,
    required this.pageIndex,
    required this.pageCount,
    this.isHost = false,
    this.allowStudents = false,
    this.pageEmpty = false,
    this.onBackground,
    this.onAllowStudents,
    this.onClearPage,
    this.onDeletePage,
    this.onExport,
  });

  final BoardBackground background;
  final int pageIndex;
  final int pageCount;
  final bool isHost;
  final bool allowStudents;
  final bool pageEmpty;
  final ValueChanged<BoardBackground>? onBackground;
  final ValueChanged<bool>? onAllowStudents;
  final VoidCallback? onClearPage;
  final VoidCallback? onDeletePage;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSectionTitle(t('الخلفية', 'Background')),
        const SizedBox(height: 8),
        BoardBackgroundPicker(value: background, onChanged: onBackground),
        const SizedBox(height: 16),
        AppSectionTitle(t('الصفحة ${pageIndex + 1} من $pageCount', 'Page ${pageIndex + 1} of $pageCount')),
        const SizedBox(height: 4),
        _OptionRow(
          key: const ValueKey('board.export'),
          icon: Icons.image_outlined,
          title: t('حفظ الصفحة كصورة PNG', 'Save the page as PNG'),
          subtitle: t('صورة واضحة بحجم 1920×1080 لمشاركتها بعد الحصة', 'A crisp 1920×1080 image to share after class'),
          onTap: onExport,
        ),
        _OptionRow(
          key: const ValueKey('board.clear_page'),
          icon: Icons.cleaning_services_rounded,
          title: t('مسح هذه الصفحة', 'Clear this page'),
          subtitle: t('لدى الجميع. يمكنك التراجع عنه', 'For everyone. You can undo it'),
          color: c.danger,
          onTap: pageEmpty ? null : onClearPage,
        ),
        if (pageCount > 1)
          _OptionRow(
            key: const ValueKey('board.delete_page'),
            icon: Icons.delete_outline_rounded,
            title: t('حذف هذه الصفحة', 'Delete this page'),
            subtitle: t('تُحذف الصفحة وما عليها لدى الجميع', 'The page and everything on it, for everyone'),
            color: c.danger,
            onTap: onDeletePage,
          ),
        if (isHost) ...[
          const SizedBox(height: 12),
          AppSectionTitle(t('الطلاب', 'Students')),
          AppSwitchTile(
            key: const ValueKey('board.allow_students'),
            icon: Icons.group_rounded,
            title: t('السماح للطلاب بالرسم والكتابة', 'Let students draw and write'),
            subtitle: t('يكتب الطلاب على السبورة ويمحون ما كتبوه فقط', 'Students write on the board and erase only their own work'),
            value: allowStudents,
            onChanged: onAllowStudents,
          ),
        ],
      ]),
    );
  }
}

/// The four backgrounds, two per row on a phone sheet, four in a row when there is room.
class BoardBackgroundPicker extends StatelessWidget {
  const BoardBackgroundPicker({super.key, required this.value, this.onChanged, this.dark = false});

  final BoardBackground value;
  final ValueChanged<BoardBackground>? onChanged;
  final bool dark;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final perRow = c.maxWidth >= 520 ? 4 : 2;
        const gap = 8.0;
        final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final b in BoardBackground.values)
            SizedBox(
              width: w,
              child: BoardBackgroundTile(
                background: b,
                selected: b == value,
                dark: dark,
                onTap: onChanged == null ? null : () => onChanged!(b),
              ),
            ),
        ]);
      });
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({super.key, required this.icon, required this.title, required this.subtitle, this.onTap, this.color});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = onTap == null ? c.textLight : (color ?? c.primary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: tint, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: appText(14, w: FontWeight.w700, c: onTap == null ? c.textLight : (color ?? c.textDark))),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Keyboard ──────────────────────────────────────────────────────────────────

/// V select · P pen · H highlighter · I line · A arrow · R rectangle · O ellipse · T text · E eraser · L laser.
BoardTool? boardShortcutTool(LogicalKeyboardKey k) {
  if (k == LogicalKeyboardKey.keyV) return BoardTool.select;
  if (k == LogicalKeyboardKey.keyP) return BoardTool.pen;
  if (k == LogicalKeyboardKey.keyH) return BoardTool.highlighter;
  if (k == LogicalKeyboardKey.keyI) return BoardTool.line;
  if (k == LogicalKeyboardKey.keyA) return BoardTool.arrow;
  if (k == LogicalKeyboardKey.keyR) return BoardTool.rect;
  if (k == LogicalKeyboardKey.keyO) return BoardTool.ellipse;
  if (k == LogicalKeyboardKey.keyT) return BoardTool.text;
  if (k == LogicalKeyboardKey.keyE) return BoardTool.eraser;
  if (k == LogicalKeyboardKey.keyL) return BoardTool.laser;
  return null;
}

/// The board's keys (web / desktop): tools, 1–3 thickness, Ctrl+Z undo, Ctrl+Y / Ctrl+Shift+Z redo, Delete the
/// selection, PageUp / PageDown pages. Never while typing in a field. Returns whether it took the key.
bool boardHandleKey(KeyEvent e, BoardController c) {
  if (e is! KeyDownEvent || annotTypingInField() || !c.canDrawLocal) return false;
  final hk = HardwareKeyboard.instance;
  final k = e.logicalKey;
  final mod = hk.isControlPressed || hk.isMetaPressed;
  if (mod && (k == LogicalKeyboardKey.keyY || (k == LogicalKeyboardKey.keyZ && hk.isShiftPressed))) {
    c.redo();
    return true;
  }
  if (mod && k == LogicalKeyboardKey.keyZ) {
    c.undo();
    return true;
  }
  if (mod || hk.isAltPressed) return false;
  final tool = boardShortcutTool(k);
  if (tool != null) {
    c.setTool(tool);
    return true;
  }
  if (k == LogicalKeyboardKey.digit1 || k == LogicalKeyboardKey.digit2 || k == LogicalKeyboardKey.digit3) {
    c.setThickness(k == LogicalKeyboardKey.digit1 ? 0 : (k == LogicalKeyboardKey.digit2 ? 1 : 2));
    return true;
  }
  if ((k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) && c.selectedItem != null) {
    c.deleteSelected();
    return true;
  }
  if (c.isLocalPresenting && (k == LogicalKeyboardKey.pageDown)) {
    c.nextPage();
    return true;
  }
  if (c.isLocalPresenting && (k == LogicalKeyboardKey.pageUp)) {
    c.previousPage();
    return true;
  }
  if (k == LogicalKeyboardKey.escape && c.selectedItem != null) {
    c.select(null);
    return true;
  }
  return false;
}
