// lib/design/app_search_field.dart
//
// THE search box of the design system: a search icon at the start, a clear (x) button while it holds text, a debounced
// [onChanged] (clearing fires it at once with ''), Esc clears. It is a plain TextField with `TextInputAction.search`
// and a search icon, which is what AppKeyboardSupport looks for: Ctrl+K and "/" focus it without any wiring.
// It wears the kit's well (appFieldDecoration: warm fill, radius 14, the 2 px ring on focus); the search icon takes
// the focus ink while the person types.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_inputs.dart' show appFieldDecoration, appFieldTextStyle;
import 'app_motion_kit.dart' show AppEase;
import 'app_tokens.dart';

class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.hint,
    required this.onChanged,
    this.onSubmitted,
    this.debounce = const Duration(milliseconds: 350),
    this.controller,
    this.autofocus = false,
    this.dense = false,
  });

  final String? hint;

  /// Called [debounce] after the last keystroke; with '' immediately when the text is cleared.
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final Duration debounce;
  final TextEditingController? controller;
  final bool autofocus;

  /// 40 px high instead of 48 (inside a dense toolbar).
  final bool dense;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  TextEditingController? _own;
  Timer? _timer;
  late bool _hasText;

  TextEditingController get _ctl => widget.controller ?? (_own ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _hasText = _ctl.text.isNotEmpty;
    _ctl.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant AppSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _own)?.removeListener(_sync);
      _ctl.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctl.removeListener(_sync);
    _own?.dispose();
    super.dispose();
  }

  void _sync() {
    final has = _ctl.text.isNotEmpty;
    if (has != _hasText && mounted) setState(() => _hasText = has);
  }

  void _typed(String v) {
    _timer?.cancel();
    if (v.isEmpty) {
      widget.onChanged('');
      return;
    }
    _timer = Timer(widget.debounce, () => widget.onChanged(v));
  }

  void _clear() {
    _timer?.cancel();
    _ctl.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final hint = widget.hint ?? (ar ? 'بحث' : 'Search');
    final clearLabel = ar ? 'مسح' : 'Clear';
    final h = widget.dense ? 40.0 : AppTouch.min;
    final motion = AppMotion.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape && _ctl.text.isNotEmpty) {
          _clear();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: h),
        child: TextField(
          controller: _ctl,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          onChanged: _typed,
          onSubmitted: (v) {
            _timer?.cancel();
            widget.onChanged(v);
            widget.onSubmitted?.call(v);
          },
          style: appFieldTextStyle(context),
          decoration: appFieldDecoration(
            context,
            hint: hint,
            icon: Icons.search_rounded,
            dense: widget.dense,
            // the clear button fades in with the first character (and keeps the well's end from jumping)
            suffix: AnimatedSwitcher(
              duration: motion.fast,
              switchInCurve: AppEase.out,
              switchOutCurve: AppEase.out,
              child: _hasText
                  ? IconButton(
                      key: const ValueKey(1),
                      tooltip: clearLabel,
                      icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textMedium),
                      onPressed: _clear,
                    )
                  : const SizedBox(key: ValueKey(0), width: AppSpace.md),
            ),
          ).copyWith(
            prefixIconConstraints: BoxConstraints(minWidth: h, minHeight: h),
            suffixIconConstraints: BoxConstraints(minWidth: AppSpace.md, minHeight: h),
          ),
        ),
      ),
    );
  }
}
