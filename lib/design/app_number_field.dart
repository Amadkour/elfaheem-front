// lib/design/app_number_field.dart — THE numeric input (D-360).
//
//   AppNumberField(controller: _seats, label: 'Seats', min: 1, max: 500)
//   AppNumberField(controller: _grade, label: 'Grade', min: 0, max: 100, step: 0.5, decimals: 2, required: true)
//
// Type the number or use the two buttons (hold one to keep counting). The buttons clamp to [min] / [max]; a typed value
// outside them shows an error and fails `Form.validate()`. Arabic-Indic digits are accepted and stored as Latin, so
// `int.tryParse(controller.text)` keeps working in the caller.
//
// Only for real quantities. A phone number, a code or an ID is text and keeps a text field.
//
// The look is the kit's field language (app_inputs.dart): the label above, the well with tabular figures centred
// between two 48 px tonal step buttons (emerald tint, emerald ink; a neutral well when they can go no further), the
// error under the well, the 2 px ring on keyboard focus of the well or of a button.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_buttons.dart' show appFocusRing, appKeyboardFocus;
import 'app_charts.dart' show appInk;
import 'app_contrast.dart' show ensureContrast;
import 'app_inputs.dart' show AppFieldLabel, appFieldDecoration, appFieldTextStyle;
import 'app_motion_kit.dart' show AppEase, AppPressScale;
import 'app_tokens.dart';

/// The text for [v] with at most [decimals] places and no trailing zeros.
String appNumberText(num v, int decimals) {
  if (decimals <= 0) return v.round().toString();
  final s = v.toStringAsFixed(decimals);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// Keeps what can still become a valid number, and turns Arabic-Indic digits into Latin ones.
class AppNumberFormatter extends TextInputFormatter {
  AppNumberFormatter({required this.decimals, required this.negative});

  final int decimals;
  final bool negative;

  static String latin(String s) {
    final out = StringBuffer();
    for (final u in s.runes) {
      if (u >= 0x0660 && u <= 0x0669) {
        out.writeCharCode(u - 0x0660 + 0x30);
      } else if (u >= 0x06F0 && u <= 0x06F9) {
        out.writeCharCode(u - 0x06F0 + 0x30);
      } else if (u == 0x066B) {
        out.write('.');
      } else {
        out.writeCharCode(u);
      }
    }
    return out.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = latin(newValue.text);
    final sign = negative ? '-?' : '';
    final body = decimals > 0 ? '\\d*(\\.\\d{0,$decimals})?' : '\\d*';
    if (!RegExp('^$sign$body\$').hasMatch(text)) return oldValue;
    return newValue.copyWith(text: text, selection: newValue.selection, composing: TextRange.empty);
  }
}

class AppNumberField extends StatefulWidget {
  const AppNumberField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.min,
    this.max,
    this.step = 1,
    this.decimals = 0,
    this.required = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.textInputAction,
    this.focusNode,
    this.autofocus = false,
    this.helper,
  });

  final TextEditingController? controller;
  final num? initialValue;
  final String? label;
  final String? hint;
  final num? min;
  final num? max;
  final num step;

  /// 0 = whole numbers.
  final int decimals;
  final bool required;
  final bool enabled;

  /// The parsed value, null while the field is empty or not yet a number.
  final ValueChanged<num?>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Runs after the built-in empty and range checks pass.
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final bool autofocus;

  /// A short line under the field.
  final String? helper;

  @override
  State<AppNumberField> createState() => _AppNumberFieldState();
}

class _AppNumberFieldState extends State<AppNumberField> {
  late TextEditingController _controller;
  bool _ownsController = false;
  Timer? _repeat;
  String? _error;

  num? get _value => num.tryParse(_controller.text.trim());

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    if (widget.initialValue != null && _controller.text.isEmpty) {
      _controller.text = appNumberText(widget.initialValue!, widget.decimals);
    }
    _controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant AppNumberField old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      _controller.removeListener(_changed);
      if (_ownsController) _controller.dispose();
      _attach();
    }
  }

  @override
  void dispose() {
    _repeat?.cancel();
    _controller.removeListener(_changed);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _changed() {
    final e = _rangeError(_controller.text);
    if (e != _error && mounted) setState(() => _error = e);
    if (mounted) setState(() {}); // the buttons' enabled state
  }

  String? _rangeError(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty || text == '-' || text == '.') return null;
    final v = num.tryParse(text);
    if (v == null) return 'ds_num_invalid'.tr;
    final min = widget.min;
    final max = widget.max;
    if (min != null && v < min) return 'ds_num_min'.tr.replaceAll('{n}', appNumberText(min, widget.decimals));
    if (max != null && v > max) return 'ds_num_max'.tr.replaceAll('{n}', appNumberText(max, widget.decimals));
    return null;
  }

  String? _validate(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return widget.required ? 'ds_num_required'.tr : null;
    if (num.tryParse(text) == null) return 'ds_num_invalid'.tr;
    return _rangeError(text) ?? widget.validator?.call(raw);
  }

  bool get _canDown => widget.enabled && (widget.min == null || _value == null || _value! > widget.min!);
  bool get _canUp => widget.enabled && (widget.max == null || _value == null || _value! < widget.max!);

  void _bump(int direction) {
    final min = widget.min;
    final max = widget.max;
    var next = (_value ?? (min ?? 0)) + widget.step * direction;
    if (_value == null && min != null && direction > 0) next = min;
    if (min != null && next < min) next = min;
    if (max != null && next > max) next = max;
    final text = appNumberText(next, widget.decimals);
    _controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    widget.onChanged?.call(next);
  }

  void _startRepeat(int direction) {
    _repeat?.cancel();
    _repeat = Timer(const Duration(milliseconds: 400), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 90), (_) {
        if (!(direction > 0 ? _canUp : _canDown)) {
          _repeat?.cancel();
          return;
        }
        _bump(direction);
      });
    });
  }

  void _stopRepeat() => _repeat?.cancel();

  @override
  Widget build(BuildContext context) {
    final negative = widget.min == null || widget.min! < 0;
    final label = widget.label;
    final field = TextFormField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      validator: _validate,
      autovalidateMode: AutovalidateMode.disabled,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimals > 0, signed: negative),
      textInputAction: widget.textInputAction,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      style: appFieldTextStyle(context).copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      inputFormatters: [AppNumberFormatter(decimals: widget.decimals, negative: negative)],
      onChanged: (_) => widget.onChanged?.call(_value),
      onFieldSubmitted: widget.onSubmitted,
      decoration: appFieldDecoration(
        context,
        hint: widget.hint,
        helper: widget.helper,
        errorText: _error,
        enabled: widget.enabled,
      ).copyWith(
        // the digits are centred: no side room beyond the well's own
        contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.sm + 1),
      ),
    );
    return Semantics(
      container: true,
      label: label,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (label != null) AppFieldLabel(label, required: widget.required),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _StepButton(
            icon: Icons.remove_rounded,
            semantic: label == null ? 'ds_num_decrease'.tr : '${'ds_num_decrease'.tr} $label',
            enabled: _canDown,
            onStep: () => _bump(-1),
            onHold: () => _startRepeat(-1),
            onRelease: _stopRepeat,
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: field),
          const SizedBox(width: AppSpace.xs),
          _StepButton(
            icon: Icons.add_rounded,
            semantic: label == null ? 'ds_num_increase'.tr : '${'ds_num_increase'.tr} $label',
            enabled: _canUp,
            onStep: () => _bump(1),
            onHold: () => _startRepeat(1),
            onRelease: _stopRepeat,
          ),
        ]),
      ]),
    );
  }
}

class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.icon,
    required this.semantic,
    required this.enabled,
    required this.onStep,
    required this.onHold,
    required this.onRelease,
  });

  final IconData icon;
  final String semantic;
  final bool enabled;
  final VoidCallback onStep;
  final VoidCallback onHold;
  final VoidCallback onRelease;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  bool _focus = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.enabled;
    final ink = ensureContrast(appInk(context, c.primary), [Color.alphaBlend(c.primaryTint, c.cardBg)]);
    final motion = AppMotion.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semantic,
      excludeSemantics: true,
      onTap: enabled ? widget.onStep : null,
      child: Listener(
        onPointerDown: enabled ? (_) => widget.onHold() : null,
        onPointerUp: (_) => widget.onRelease(),
        onPointerCancel: (_) => widget.onRelease(),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? widget.onStep : null,
            onHover: (v) => setState(() => _hover = v),
            onFocusChange: (v) => setState(() => _focus = v),
            borderRadius: AppRadius.controlAll,
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: AppPressScale(
              scale: 0.94,
              enabled: enabled,
              child: AnimatedContainer(
                duration: motion.fast,
                curve: AppEase.out,
                width: AppTouch.min,
                height: AppTouch.min,
                decoration: BoxDecoration(
                  color: !enabled
                      ? c.inputBg
                      : _hover
                          ? Color.lerp(c.primaryTint, c.primary, 0.08)
                          : c.primaryTint,
                  borderRadius: AppRadius.controlAll,
                  border: enabled ? null : Border.all(color: c.divider, width: AppBorder.hairline),
                  boxShadow: _focus && enabled && appKeyboardFocus() ? appFocusRing(context) : null,
                ),
                child: Icon(widget.icon, size: AppIconSize.md, color: enabled ? ink : c.textLight),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
