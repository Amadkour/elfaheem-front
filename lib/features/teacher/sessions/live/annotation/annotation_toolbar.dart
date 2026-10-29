// lib/features/teacher/sessions/live/annotation/annotation_toolbar.dart
//
// The annotation toolbar (D-079). [AnnotationToolbar] is presentational (plain values + callbacks, tested by
// test/ui/annotation_toolbar_layout_test.dart): pen, highlighter, eraser, laser · undo, clear all (host) ·
// colour (the theme palette's presets + the current one) and thickness (3 steps) · "Allow students to draw"
// (host, AppSwitch) and "Show who drew what" (host, D-093) · close. On a phone (compact) colour and thickness fold into one "Style" button that opens a
// row under the bar, and the bar scrolls sideways instead of overflowing. Every control has a Semantics label
// and a 48 px target.
//
// [AnnotationControllerToolbar] binds it to an AnnotationController (and asks before clearing).
//
// Keyboard (web / desktop, [AnnotationShortcuts]; ignored while a text field has the focus):
//   P pen · H highlighter · E eraser · L laser · 1 / 2 / 3 thickness · Ctrl+Z (⌘Z) undo · Esc close.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import '../widgets/live_palette.dart';
import 'annotation_controller.dart';

/// Below this width the toolbar is compact.
const kAnnotToolbarCompactWidth = 600.0;

/// The preset colours, from the theme palette: red, amber, green, accent, light primary, purple, light, dark.
List<Color> annotPresetColors(ThemeConfigProvider c) =>
    [c.danger, c.warning, c.success, c.accent, c.primaryLight, c.purple, c.onHero, c.charcoalDark];

List<String> annotPresetColorLabels() => [
      t('أحمر', 'Red'),
      t('برتقالي', 'Amber'),
      t('أخضر', 'Green'),
      t('لون مميز', 'Accent'),
      t('أزرق فاتح', 'Light blue'),
      t('بنفسجي', 'Purple'),
      t('أبيض', 'White'),
      t('داكن', 'Dark'),
    ];

String annotToolLabel(AnnotTool tool) => switch (tool) {
      AnnotTool.pen => t('قلم', 'Pen'),
      AnnotTool.highlighter => t('قلم تظليل', 'Highlighter'),
      AnnotTool.eraser => t('ممحاة', 'Eraser'),
      AnnotTool.laser => t('مؤشر ليزر', 'Laser pointer'),
    };

List<String> annotThicknessLabels() => [t('رفيع', 'Thin'), t('متوسط', 'Medium'), t('سميك', 'Thick')];

class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({
    super.key,
    required this.tool,
    required this.color,
    required this.colors,
    required this.thickness,
    this.colorLabels,
    this.canUndo = false,
    this.isHost = false,
    this.allowStudents = false,
    this.showAuthors = false,
    this.burnedIn = false,
    this.compact,
    this.styleOpen = false,
    this.onTool,
    this.onColor,
    this.onThickness,
    this.onUndo,
    this.onClear,
    this.onAllowStudents,
    this.onShowAuthors,
    this.onToggleStyle,
    this.onClose,
  });

  final AnnotTool tool;
  final Color color;
  final List<Color> colors;

  /// Same length as [colors] (spoken labels); default "Colour n".
  final List<String>? colorLabels;

  /// 0, 1, 2.
  final int thickness;
  final bool canUndo;

  /// Shows clear all and the students switch.
  final bool isHost;
  final bool allowStudents;

  /// The host's "Show who drew what" (D-093): a toggle next to the students switch.
  final bool showAuthors;

  /// Android whole-screen share: students cannot draw (the switch is off and says why).
  final bool burnedIn;

  /// Null: by the available width ([kAnnotToolbarCompactWidth]).
  final bool? compact;

  /// Compact only: the colour / thickness row under the bar is open.
  final bool styleOpen;

  final ValueChanged<AnnotTool>? onTool;
  final ValueChanged<Color>? onColor;
  final ValueChanged<int>? onThickness;
  final VoidCallback? onUndo;
  final VoidCallback? onClear;
  final ValueChanged<bool>? onAllowStudents;
  final ValueChanged<bool>? onShowAuthors;
  final VoidCallback? onToggleStyle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);
    return LayoutBuilder(builder: (context, c) {
      final narrow = compact ?? (c.maxWidth.isFinite && c.maxWidth < kAnnotToolbarCompactWidth);
      final shown = _swatches();
      final bar = _scroll(Row(mainAxisSize: MainAxisSize.min, children: [
        for (final tl in AnnotTool.values)
          AnnotToolButton(
            key: ValueKey('annot.tool.${tl.name}'),
            label: annotToolLabel(tl) + _hint(_toolKey(tl)),
            selected: tl == tool,
            onTap: onTool == null ? null : () => onTool!(tl),
            child: tl == AnnotTool.eraser
                ? const _EraserGlyph()
                : Icon(_toolIcon(tl), size: 22, color: tl == tool ? LivePalette.textHigh : LivePalette.textMid),
          ),
        const _Divider(),
        AnnotToolButton(
          key: const ValueKey('annot.undo'),
          label: t('تراجع', 'Undo') + _hint('Ctrl+Z'),
          onTap: canUndo ? onUndo : null,
          child: Icon(Icons.undo_rounded, size: 22, color: canUndo ? LivePalette.textMid : LivePalette.textLow),
        ),
        if (isHost)
          AnnotToolButton(
            key: const ValueKey('annot.clear'),
            label: t('مسح الكل', 'Clear all'),
            onTap: onClear,
            child: Icon(Icons.delete_sweep_rounded, size: 22, color: LivePalette.danger),
          ),
        const _Divider(),
        if (narrow)
          AnnotToolButton(
            key: const ValueKey('annot.style'),
            label: t('اللون والسُّمك', 'Colour and thickness'),
            selected: styleOpen,
            onTap: onToggleStyle,
            child: _ColorDot(color: color, size: 22, ring: LivePalette.textHigh),
          )
        else ...[
          for (final (i, (col, label)) in shown.indexed)
            _swatch(i, col, label),
          const _Divider(),
          ..._thicknessButtons(),
        ],
        if (isHost) ...[
          const _Divider(),
          _studentsSwitch(narrow),
          if (onShowAuthors != null)
            AnnotToolButton(
              key: const ValueKey('annot.show_authors'),
              label: t('إظهار من رسم كل شيء', 'Show who drew what'),
              selected: showAuthors,
              onTap: () => onShowAuthors!(!showAuthors),
              child: Icon(Icons.badge_outlined, size: 22, color: showAuthors ? LivePalette.textHigh : LivePalette.textMid),
            ),
        ],
        const _Divider(),
        AnnotToolButton(
          key: const ValueKey('annot.close'),
          label: t('إغلاق التعليق التوضيحي', 'Close annotation') + _hint('Esc'),
          onTap: onClose,
          child: const Icon(Icons.close_rounded, size: 22, color: LivePalette.textMid),
        ),
      ]));

      return Semantics(
        container: true,
        label: t('أدوات التعليق التوضيحي', 'Annotation tools'),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: LivePalette.surfaceHi.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: LivePalette.glassBorder),
              boxShadow: [BoxShadow(color: LivePalette.shade(0.4), blurRadius: 18)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              bar,
              if (narrow && styleOpen) ...[
                Container(height: 1, color: LivePalette.hairline),
                _scroll(Row(
                  key: const ValueKey('annot.style_panel'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, (col, label)) in shown.indexed) _swatch(i, col, label),
                    const _Divider(),
                    ..._thicknessButtons(),
                  ],
                )),
              ],
            ]),
          ),
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
      key: ValueKey('annot.color.$i'),
      label: label,
      selected: selected,
      onTap: onColor == null ? null : () => onColor!(col),
      child: _ColorDot(color: col, size: selected ? 24 : 20, ring: selected ? LivePalette.textHigh : LivePalette.glassBorder),
    );
  }

  List<Widget> _thicknessButtons() {
    final labels = annotThicknessLabels();
    return [
      for (var i = 0; i < 3; i++)
        AnnotToolButton(
          key: ValueKey('annot.thickness.$i'),
          label: labels[i] + _hint('${i + 1}'),
          selected: i == thickness,
          onTap: onThickness == null ? null : () => onThickness!(i),
          child: Container(
            width: 4.0 + i * 4,
            height: 4.0 + i * 4,
            decoration: BoxDecoration(
              color: i == thickness ? LivePalette.textHigh : LivePalette.textMid,
              shape: BoxShape.circle,
            ),
          ),
        ),
    ];
  }

  Widget _studentsSwitch(bool narrow) {
    final label = t('السماح للطلاب بالرسم', 'Allow students to draw');
    final note = burnedIn ? t('غير متاح أثناء مشاركة الشاشة كاملة من أندرويد', 'Not available while sharing the whole Android screen') : null;
    final enabled = onAllowStudents != null && !burnedIn;
    return Tooltip(
      message: note ?? label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.group_rounded, size: 20, color: enabled ? LivePalette.textMid : LivePalette.textLow),
            if (!narrow) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: enabled ? LivePalette.textHigh : LivePalette.textLow),
                ),
              ),
            ],
            const SizedBox(width: 6),
            SizedBox(
              height: 48,
              child: Center(
                child: AppSwitch(
                  key: const ValueKey('annot.allow_students'),
                  value: allowStudents && !burnedIn,
                  onChanged: enabled ? onAllowStudents : null,
                  activeColor: LivePalette.success,
                  semanticLabel: note == null ? label : '$label. $note',
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  static Widget _scroll(Widget row) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);

  static IconData _toolIcon(AnnotTool tl) => switch (tl) {
        AnnotTool.pen => Icons.edit_rounded,
        AnnotTool.highlighter => Icons.border_color_rounded,
        AnnotTool.eraser => Icons.auto_fix_normal_rounded,
        AnnotTool.laser => Icons.ads_click_rounded,
      };

  static String _toolKey(AnnotTool tl) => switch (tl) {
        AnnotTool.pen => 'P',
        AnnotTool.highlighter => 'H',
        AnnotTool.eraser => 'E',
        AnnotTool.laser => 'L',
      };

  /// The shortcut, shown in tooltips on web / desktop only.
  static String _hint(String key) => _keyboardPlatform ? ' ($key)' : '';
}

bool get _keyboardPlatform =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

/// One 48 × 48 control of the toolbar: Semantics (button, selected, label), tooltip, ink.
class AnnotToolButton extends StatelessWidget {
  const AnnotToolButton({super.key, required this.label, required this.child, this.selected = false, this.onTap});

  final String label;
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected ? LivePalette.accent.withValues(alpha: 0.28) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: selected ? Border.all(color: LivePalette.accent.withValues(alpha: 0.7)) : null,
                ),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.size, required this.ring});

  final Color color;
  final double size;
  final Color ring;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 4), color: LivePalette.hairline);
}

/// An eraser block (Material has no eraser icon).
class _EraserGlyph extends StatelessWidget {
  const _EraserGlyph();

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: -0.6,
        child: Container(
          width: 20,
          height: 11,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: LivePalette.textMid, width: 2),
            gradient: LinearGradient(
              colors: [LivePalette.textMid, LivePalette.textMid, Colors.transparent, Colors.transparent],
              stops: const [0, 0.42, 0.42, 1],
            ),
          ),
        ),
      );
}

// ── Keyboard ──────────────────────────────────────────────────────────────────

/// Annotation keys while [enabled] (web / desktop): P / H / E / L tools, 1–3 thickness, Ctrl+Z / ⌘Z undo, Esc
/// close. A key typed into a text field (chat, Q&A) is left alone.
class AnnotationShortcuts extends StatefulWidget {
  const AnnotationShortcuts({
    super.key,
    required this.child,
    this.enabled = true,
    this.onTool,
    this.onThickness,
    this.onUndo,
    this.onClose,
  });

  final Widget child;
  final bool enabled;
  final ValueChanged<AnnotTool>? onTool;
  final ValueChanged<int>? onThickness;
  final VoidCallback? onUndo;
  final VoidCallback? onClose;

  @override
  State<AnnotationShortcuts> createState() => _AnnotationShortcutsState();
}

class _AnnotationShortcutsState extends State<AnnotationShortcuts> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AnnotationShortcuts old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.enabled && !_on) {
      HardwareKeyboard.instance.addHandler(_handle);
      _on = true;
    } else if (!widget.enabled && _on) {
      HardwareKeyboard.instance.removeHandler(_handle);
      _on = false;
    }
  }

  @override
  void dispose() {
    if (_on) HardwareKeyboard.instance.removeHandler(_handle);
    super.dispose();
  }

  bool _handle(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (annotTypingInField()) return false;
    final hk = HardwareKeyboard.instance;
    final k = e.logicalKey;
    if ((hk.isControlPressed || hk.isMetaPressed) && k == LogicalKeyboardKey.keyZ && !hk.isShiftPressed) {
      if (widget.onUndo == null) return false;
      widget.onUndo!();
      return true;
    }
    if (hk.isControlPressed || hk.isMetaPressed || hk.isAltPressed) return false;
    final tool = annotShortcutTool(k);
    if (tool != null && widget.onTool != null) {
      widget.onTool!(tool);
      return true;
    }
    final th = annotShortcutThickness(k);
    if (th != null && widget.onThickness != null) {
      widget.onThickness!(th);
      return true;
    }
    if (k == LogicalKeyboardKey.escape && widget.onClose != null) {
      widget.onClose!();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

AnnotTool? annotShortcutTool(LogicalKeyboardKey k) {
  if (k == LogicalKeyboardKey.keyP) return AnnotTool.pen;
  if (k == LogicalKeyboardKey.keyH) return AnnotTool.highlighter;
  if (k == LogicalKeyboardKey.keyE) return AnnotTool.eraser;
  if (k == LogicalKeyboardKey.keyL) return AnnotTool.laser;
  return null;
}

int? annotShortcutThickness(LogicalKeyboardKey k) {
  if (k == LogicalKeyboardKey.digit1 || k == LogicalKeyboardKey.numpad1) return 0;
  if (k == LogicalKeyboardKey.digit2 || k == LogicalKeyboardKey.numpad2) return 1;
  if (k == LogicalKeyboardKey.digit3 || k == LogicalKeyboardKey.numpad3) return 2;
  return null;
}

/// A text field has the keyboard focus.
bool annotTypingInField() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget is EditableText) return true;
  return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

// ── Bound to a controller ─────────────────────────────────────────────────────

/// The toolbar wired to [controller]: picks the tool and turns draw mode on, asks before clear all, and
/// handles the keyboard on web / desktop. [onClose] leaves annotation (RoomPage hides the toolbar).
class AnnotationControllerToolbar extends StatefulWidget {
  const AnnotationControllerToolbar({super.key, required this.controller, this.onClose, this.compact});

  final AnnotationController controller;
  final VoidCallback? onClose;
  final bool? compact;

  @override
  State<AnnotationControllerToolbar> createState() => _AnnotationControllerToolbarState();
}

class _AnnotationControllerToolbarState extends State<AnnotationControllerToolbar> {
  bool _styleOpen = false;

  AnnotationController get _c => widget.controller;

  void _close() {
    _c.setDrawMode(false);
    widget.onClose?.call();
  }

  Future<void> _clear() async {
    final ok = await appConfirm(
      context,
      message: t('مسح كل الرسومات لدى الجميع؟', 'Clear every drawing for everyone?'),
      danger: true,
      confirmLabel: t('مسح الكل', 'Clear all'),
    );
    if (ok && mounted) _c.clearAll();
  }

  void _tool(AnnotTool tl) {
    _c.setTool(tl);
    _c.setDrawMode(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = annotPresetColors(context.colors);
    return ListenableBuilder(
      listenable: Listenable.merge([_c, _c.board]),
      builder: (context, _) => AnnotationShortcuts(
        enabled: _keyboardPlatform && _c.canDrawLocal,
        onTool: _tool,
        onThickness: _c.setThickness,
        onUndo: _c.undo,
        onClose: _close,
        child: AnnotationToolbar(
          tool: _c.tool,
          color: Color(_c.colorArgb),
          colors: colors,
          colorLabels: annotPresetColorLabels(),
          thickness: _c.thickness,
          canUndo: _c.canUndo,
          isHost: _c.isHost,
          allowStudents: _c.allowStudents,
          showAuthors: _c.showAuthors,
          burnedIn: _c.burnedIn,
          compact: widget.compact,
          styleOpen: _styleOpen,
          onTool: _tool,
          onColor: (col) => _c.setColor(col.toARGB32()),
          onThickness: _c.setThickness,
          onUndo: _c.undo,
          onClear: _clear,
          onAllowStudents: _c.setAllowStudents,
          onShowAuthors: _c.setShowAuthors,
          onToggleStyle: () => setState(() => _styleOpen = !_styleOpen),
          onClose: _close,
        ),
      ),
    );
  }
}
