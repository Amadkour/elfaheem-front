// lib/design/studio/studio_props.dart
//
// Property-panel primitives both studios build their side panels from. Each takes a value and an onChanged and
// keeps no model of its own; wrap a change in `controller.record(label, …)` (with `coalesce: true` for sliders and
// steppers) so it is one undo step.
//
//   StudioPropSection      a titled group (title 14 w600, hairline above)
//   StudioPropField        a label over one control
//   StudioSegmented<T>     the segmented control behind weight / text align / border style
//   StudioFontPicker       fonts from a list of [StudioFontOption]s (each name drawn in its own font)
//   StudioStepper          − value + with typing (size, width, radius, letter spacing, …)
//   StudioWeightPicker     Regular · Medium · Bold
//   StudioTextAlignPicker  left · centre · right (· justify), physical like the page
//   StudioColorField       swatches + #RRGGBB field (optionally "none")
//   StudioBorderEditor     style none / solid / dashed / double · width · colour · corner radius
//   StudioOpacitySlider    0 – 100 %
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_contrast.dart';
import '../app_kit.dart' show AppDropdown, appText;
import '../app_tokens.dart';
import 'studio_model.dart';

/// A titled group of properties.
class StudioPropSection extends StatelessWidget {
  const StudioPropSection({super.key, required this.title, required this.children, this.trailing, this.first = false});

  final String title;
  final List<Widget> children;

  /// A small action at the end of the title row (reset, …).
  final Widget? trailing;

  /// The first section of a panel draws no hairline above.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: c.divider))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
          ),
          ?trailing,
        ]),
        const SizedBox(height: AppSpace.sm),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpace.sm),
          children[i],
        ],
      ]),
    );
  }
}

/// A label over one control.
class StudioPropField extends StatelessWidget {
  const StudioPropField({super.key, required this.label, required this.child, this.value});

  final String label;
  final Widget child;

  /// A short read-out at the end of the label row ("80 %").
  final String? value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w500, c: c.textMedium))),
        if (value != null) Text(value!, style: appText(12, w: FontWeight.w600, c: c.textDark)),
      ]),
      const SizedBox(height: AppSpace.xxs + 2),
      child,
    ]);
  }
}

/// One choice of a [StudioSegmented].
class StudioSegment<T> {
  const StudioSegment({required this.value, required this.label, this.icon});
  final T value;
  final String label;

  /// With an icon the label becomes its tooltip (compact, for align / style choices).
  final IconData? icon;
}

class StudioSegmented<T> extends StatelessWidget {
  const StudioSegmented({super.key, required this.segments, required this.value, required this.onChanged});

  final List<StudioSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final accent = ensureContrast(c.primary, [c.cardBg]);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
      child: Row(children: [
        for (final s in segments)
          Expanded(
            child: Semantics(
              button: true,
              selected: s.value == value,
              label: s.label,
              excludeSemantics: true,
              child: Tooltip(
                message: s.icon != null ? s.label : '',
                child: InkWell(
                  onTap: onChanged == null ? null : () => onChanged!(s.value),
                  borderRadius: BorderRadius.circular(AppRadius.chip - 3),
                  child: AnimatedContainer(
                    duration: motion.fast,
                    curve: AppMotion.curve,
                    constraints: const BoxConstraints(minHeight: AppTouch.min - 6),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                    decoration: BoxDecoration(
                      color: s.value == value ? c.cardBg : null,
                      borderRadius: BorderRadius.circular(AppRadius.chip - 3),
                      boxShadow: s.value == value ? c.cardShadow : null,
                    ),
                    child: s.icon != null
                        ? Icon(s.icon, size: 20, color: s.value == value ? accent : c.textMedium)
                        : Text(
                            s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: appText(12.5,
                                w: s.value == value ? FontWeight.w600 : FontWeight.w500,
                                c: s.value == value ? c.textDark : c.textMedium),
                          ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// A font the picker offers. [family] is the engine family the document uses (the studio's own embedded fonts).
class StudioFontOption {
  const StudioFontOption({required this.id, required this.label, this.family});
  final String id;
  final String label;
  final String? family;
}

class StudioFontPicker extends StatelessWidget {
  const StudioFontPicker({super.key, required this.options, required this.value, required this.onChanged, this.label});

  final List<StudioFontOption> options;
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return StudioPropField(
      label: label ?? translate('studio_font'),
      child: AppDropdown<String>(
        value: options.any((o) => o.id == value) ? value : null,
        decoration: const InputDecoration(isDense: true),
        items: [
          for (final o in options)
            DropdownMenuItem<String>(
              value: o.id,
              child: Text(
                o.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: appText(14, c: c.textDark).copyWith(fontFamily: o.family),
              ),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// − value + : a number with buttons and typing. Values are clamped to [min]..[max] and rounded to [decimals].
class StudioStepper extends StatefulWidget {
  const StudioStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.min = 0,
    this.max = 999,
    this.step = 1,
    this.decimals = 0,
    this.suffix,
    this.enabled = true,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final String? label;
  final double min, max, step;
  final int decimals;
  final String? suffix;

  /// False: the value shows read-only (no typing, no − / +), e.g. the position of a locked layer.
  final bool enabled;

  @override
  State<StudioStepper> createState() => _StudioStepperState();
}

class _StudioStepperState extends State<StudioStepper> {
  late final _text = TextEditingController(text: _fmt(widget.value));
  final _focus = FocusNode();

  String _fmt(double v) => v.toStringAsFixed(widget.decimals);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit(_text.text);
    });
  }

  @override
  void didUpdateWidget(covariant StudioStepper old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _text.text != _fmt(widget.value)) _text.text = _fmt(widget.value);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  double _clamp(double v) {
    final p = double.parse(v.clamp(widget.min, widget.max).toStringAsFixed(widget.decimals));
    return p;
  }

  void _set(double v) {
    if (!widget.enabled) return;
    final n = _clamp(v);
    _text.text = _fmt(n);
    if (n != widget.value) widget.onChanged(n);
  }

  void _submit(String s) {
    final v = double.tryParse(s.trim().replaceAll(',', '.'));
    if (v == null) {
      _text.text = _fmt(widget.value);
      return;
    }
    _set(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.chipAll,
            child: SizedBox(
              width: AppTouch.min,
              height: AppTouch.min,
              child: Icon(icon, size: 18, color: onTap == null ? c.textLight : c.textDark),
            ),
          ),
        );
    final field = Container(
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
      child: Row(children: [
        btn(Icons.remove_rounded, translate('studio_decrease'),
            widget.enabled && widget.value > widget.min ? () => _set(widget.value - widget.step) : null),
        Expanded(
          child: TextField(
            controller: _text,
            focusNode: _focus,
            enabled: widget.enabled,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.numberWithOptions(decimal: widget.decimals > 0),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
            onSubmitted: _submit,
            style: appText(14, w: FontWeight.w600, c: widget.enabled ? c.textDark : c.textMedium)
                .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
              suffixText: widget.suffix,
              suffixStyle: appText(12, c: c.textMedium),
            ),
          ),
        ),
        btn(Icons.add_rounded, translate('studio_increase'),
            widget.enabled && widget.value < widget.max ? () => _set(widget.value + widget.step) : null),
      ]),
    );
    final label = widget.label;
    return label == null ? field : StudioPropField(label: label, child: field);
  }
}

class StudioWeightPicker extends StatelessWidget {
  const StudioWeightPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.options = const [FontWeight.w400, FontWeight.w500, FontWeight.w700],
  });

  final FontWeight value;
  final ValueChanged<FontWeight> onChanged;
  final List<FontWeight> options;

  static String labelOf(FontWeight w) => w.value <= 400
      ? translate('studio_weight_regular')
      : (w.value < 650 ? translate('studio_weight_medium') : translate('studio_weight_bold'));

  @override
  Widget build(BuildContext context) => StudioPropField(
        label: translate('studio_weight'),
        child: StudioSegmented<FontWeight>(
          segments: [for (final w in options) StudioSegment(value: w, label: labelOf(w))],
          value: options.contains(value) ? value : options.first,
          onChanged: onChanged,
        ),
      );
}

/// Text alignment. The page is physical, so left / right are physical too; a [TextAlign.start] / [end] option
/// shows the icon of the side it resolves to in the current language.
class StudioTextAlignPicker extends StatelessWidget {
  const StudioTextAlignPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.options = const [TextAlign.left, TextAlign.center, TextAlign.right],
  });

  final TextAlign value;
  final ValueChanged<TextAlign> onChanged;
  final List<TextAlign> options;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    (IconData, String) face(TextAlign a) {
      final side = switch (a) {
        TextAlign.start => rtl ? TextAlign.right : TextAlign.left,
        TextAlign.end => rtl ? TextAlign.left : TextAlign.right,
        _ => a,
      };
      return switch (side) {
        TextAlign.left => (Icons.format_align_left_rounded, translate('studio_align_text_left')),
        TextAlign.right => (Icons.format_align_right_rounded, translate('studio_align_text_right')),
        TextAlign.justify => (Icons.format_align_justify_rounded, translate('studio_align_text_justify')),
        _ => (Icons.format_align_center_rounded, translate('studio_align_text_center')),
      };
    }

    final control = StudioSegmented<TextAlign>(
      segments: [
        for (final a in options) StudioSegment(value: a, label: face(a).$2, icon: face(a).$1),
      ],
      value: value,
      onChanged: onChanged,
    );
    // Physical choices sit in physical order (left on the left) in Arabic too.
    final physical = !options.contains(TextAlign.start) && !options.contains(TextAlign.end);
    return StudioPropField(
      label: translate('studio_text_align'),
      child: physical ? Directionality(textDirection: TextDirection.ltr, child: control) : control,
    );
  }
}

/// Document colours for the swatch row (ink, greys, the usual certificate / report accents).
const kStudioSwatches = <Color>[
  Color(0xFF1C1C24),
  Color(0xFF4B5563),
  Color(0xFF9CA3AF),
  Color(0xFFFFFFFF),
  Color(0xFF1E3A8A),
  Color(0xFF2563EB),
  Color(0xFF0F766E),
  Color(0xFF15803D),
  Color(0xFFB45309),
  Color(0xFFC9A227),
  Color(0xFFB91C1C),
  Color(0xFF6D28D9),
];

String studioHex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

Color? studioParseHex(String s) {
  final h = s.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) return null;
  return Color(0xFF000000 | int.parse(h, radix: 16));
}

/// Swatches + a #RRGGBB field. With [allowNone], a crossed swatch gives null (no background).
class StudioColorField extends StatefulWidget {
  const StudioColorField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.swatches = kStudioSwatches,
    this.allowNone = false,
  });

  final Color? value;
  final ValueChanged<Color?> onChanged;
  final String? label;
  final List<Color> swatches;
  final bool allowNone;

  @override
  State<StudioColorField> createState() => _StudioColorFieldState();
}

class _StudioColorFieldState extends State<StudioColorField> {
  late final _hex = TextEditingController(text: _text(widget.value));

  String _text(Color? c) => c == null ? '' : studioHex(c);

  @override
  void didUpdateWidget(covariant StudioColorField old) {
    super.didUpdateWidget(old);
    final t = _text(widget.value);
    if (old.value != widget.value && _hex.text.toUpperCase() != t) _hex.text = t;
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  bool _same(Color a, Color? b) => b != null && (a.toARGB32() & 0xFFFFFF) == (b.toARGB32() & 0xFFFFFF);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ring = ensureContrast(c.primary, [c.cardBg, c.background]);
    Widget swatch(Color? color) {
      final on = color == null ? widget.value == null : _same(color, widget.value);
      final name = color == null ? translate('studio_none_color') : '#${studioHex(color)}';
      return Semantics(
        button: true,
        selected: on,
        label: name,
        excludeSemantics: true,
        child: Tooltip(
          message: name,
          child: InkResponse(
            onTap: () {
              _hex.text = _text(color);
              widget.onChanged(color);
            },
            radius: AppTouch.min / 2,
            child: SizedBox(
              width: AppTouch.min - 8,
              height: AppTouch.min - 8,
              child: Center(
                child: AnimatedContainer(
                  duration: AppMotion.of(context).fast,
                  curve: AppMotion.curve,
                  width: 32,
                  height: 32,
                  padding: EdgeInsets.all(on ? 3 : 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: on ? ring : Colors.transparent, width: 2),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color ?? c.cardBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.divider),
                    ),
                    child: color == null ? Icon(Icons.block_rounded, size: 16, color: c.textLight) : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(children: [
        if (widget.allowNone) swatch(null),
        for (final s in widget.swatches) swatch(s),
      ]),
      const SizedBox(height: AppSpace.xs),
      Directionality(
        textDirection: TextDirection.ltr,
        child: Semantics(
          label: translate('studio_hex'),
          child: TextField(
            controller: _hex,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]'))],
            style: appText(14, w: FontWeight.w600, c: c.textDark),
            onChanged: (s) {
              final col = studioParseHex(s);
              if (col != null) widget.onChanged(col);
            },
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: 'RRGGBB',
              prefixText: '#',
              prefixIcon: Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: widget.value ?? c.cardBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.divider),
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ),
        ),
      ),
    ]);
    return StudioPropField(label: widget.label ?? translate('studio_color'), child: body);
  }
}

class StudioBorderEditor extends StatelessWidget {
  const StudioBorderEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.maxWidth = 20,
    this.maxRadius = 100,
    this.swatches = kStudioSwatches,
  });

  final StudioBorder value;
  final ValueChanged<StudioBorder> onChanged;
  final double maxWidth, maxRadius;
  final List<Color> swatches;

  @override
  Widget build(BuildContext context) {
    final b = value;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioPropField(
        label: translate('studio_border'),
        child: StudioSegmented<StudioBorderStyle>(
          segments: [
            StudioSegment(value: StudioBorderStyle.none, label: translate('studio_border_none')),
            StudioSegment(value: StudioBorderStyle.solid, label: translate('studio_border_solid')),
            StudioSegment(value: StudioBorderStyle.dashed, label: translate('studio_border_dashed')),
            StudioSegment(value: StudioBorderStyle.double, label: translate('studio_border_double')),
          ],
          value: b.style,
          onChanged: (s) => onChanged(b.copyWith(style: s)),
        ),
      ),
      if (b.style != StudioBorderStyle.none) ...[
        const SizedBox(height: AppSpace.sm),
        StudioStepper(
          label: translate('studio_border_width'),
          value: b.width,
          min: .5,
          max: maxWidth,
          step: .5,
          decimals: 1,
          onChanged: (w) => onChanged(b.copyWith(width: w)),
        ),
        const SizedBox(height: AppSpace.sm),
        StudioColorField(
          label: translate('studio_border_color'),
          value: b.color,
          swatches: swatches,
          onChanged: (c) => onChanged(b.copyWith(color: c)),
        ),
      ],
      const SizedBox(height: AppSpace.sm),
      StudioStepper(
        label: translate('studio_radius'),
        value: b.radius,
        max: maxRadius,
        onChanged: (r) => onChanged(b.copyWith(radius: r)),
      ),
    ]);
  }
}

/// Opacity 0 – 1 shown as a percentage. [onChangeEnd] is where a host that does not coalesce records the step.
class StudioOpacitySlider extends StatelessWidget {
  const StudioOpacitySlider({super.key, required this.value, required this.onChanged, this.onChangeEnd, this.label});

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0).toDouble();
    return StudioPropField(
      label: label ?? translate('studio_opacity'),
      value: '${(v * 100).round()}%',
      child: Slider(
        value: v,
        divisions: 20,
        label: '${(v * 100).round()}%',
        semanticFormatterCallback: (x) => '${(x * 100).round()}%',
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

/// A text property (a block's text, a link, a caption): keeps the caret while the host rebuilds on every key, takes
/// the host's value again when the field is not focused (undo, another element selected). [ltr] for links.
class StudioTextProp extends StatefulWidget {
  const StudioTextProp({super.key, required this.label, required this.value, required this.onChanged, this.hint, this.maxLines = 1, this.ltr = false, this.maxLength = 1000});
  final String label, value;
  final String? hint;
  final int maxLines, maxLength;
  final bool ltr;
  final ValueChanged<String> onChanged;

  @override
  State<StudioTextProp> createState() => _StudioTextPropState();
}

class _StudioTextPropState extends State<StudioTextProp> {
  late final _c = TextEditingController(text: widget.value);
  final _f = FocusNode();

  @override
  void didUpdateWidget(covariant StudioTextProp old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _c,
      focusNode: _f,
      minLines: 1,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      onChanged: widget.onChanged,
      style: appText(14, c: context.colors.textDark),
      decoration: InputDecoration(isDense: true, labelText: widget.label, hintText: widget.hint, counterText: ''),
    );
    return widget.ltr ? Directionality(textDirection: TextDirection.ltr, child: field) : field;
  }
}

/// One "insert a variable" chip: the inserted [key] and what the person reads.
class StudioPlaceholder {
  const StudioPlaceholder(this.key, this.label);
  final String key, label;
}

/// "Insert a variable" chips under a text property ({{key}} in the export designer, {key} in certificates: the host
/// inserts its own spelling in [onInsert]).
class StudioPlaceholderChips extends StatelessWidget {
  const StudioPlaceholderChips({super.key, required this.items, required this.onInsert, this.label});
  final List<StudioPlaceholder> items;
  final ValueChanged<String> onInsert;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label ?? translate('studio_insert_variable'), style: appText(12, c: c.textMedium)),
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xxs + 2, runSpacing: AppSpace.xxs + 2, children: [
        for (final p in items)
          ActionChip(
            label: Text(p.label, style: appText(12.5, w: FontWeight.w500, c: c.textDark)),
            avatar: Icon(Icons.data_object_rounded, size: 16, color: c.textMedium),
            tooltip: p.key,
            onPressed: () => onInsert(p.key),
          ),
      ]),
    ]);
  }
}
