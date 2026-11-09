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
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

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
    final c = context.colors;
    final negative = widget.min == null || widget.min! < 0;
    final radius = BorderRadius.circular(AppRadius.chip + 4);
    OutlineInputBorder border(Color color, [double w = AppBorder.hairline]) =>
        OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: color, width: w));
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
      style: AppType.bodyStrong(context).copyWith(color: c.textDark),
      inputFormatters: [AppNumberFormatter(decimals: widget.decimals, negative: negative)],
      onChanged: (_) => widget.onChanged?.call(_value),
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hint,
        isDense: true,
        filled: true,
        fillColor: c.inputBg,
        errorText: _error,
        helperText: widget.helper,
        helperMaxLines: 2,
        errorMaxLines: 2,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.sm + 2),
        border: border(c.divider),
        enabledBorder: border(c.divider),
        focusedBorder: border(c.primary, AppBorder.focus),
        errorBorder: border(c.danger),
        focusedErrorBorder: border(c.danger, AppBorder.focus),
      ),
    );
    return Semantics(
      container: true,
      label: label,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (label != null) ...[
          Text(label, style: AppType.label(context).copyWith(color: c.textMedium)),
          const SizedBox(height: AppSpace.xxs + 2),
        ],
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

class _StepButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.chip + 4);
    return Semantics(
      button: true,
      enabled: enabled,
      label: semantic,
      excludeSemantics: true,
      onTap: enabled ? onStep : null,
      child: Listener(
        onPointerDown: enabled ? (_) => onHold() : null,
        onPointerUp: (_) => onRelease(),
        onPointerCancel: (_) => onRelease(),
        child: Material(
          color: enabled ? c.primary.withValues(alpha: 0.12) : c.inputBg,
          shape: RoundedRectangleBorder(borderRadius: radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onStep : null,
            child: SizedBox(
              width: AppTouch.min,
              height: AppTouch.min,
              child: Icon(icon, size: AppIconSize.md, color: enabled ? c.primary : c.textLight),
            ),
          ),
        ),
      ),
    );
  }
}
