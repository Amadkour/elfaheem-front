import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_charts.dart' show appInk;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase;
import 'package:flutter_education_app/design/app_tokens.dart';

/// Returns true when [code] is accepted.
///
/// May be async (e.g. a server call). Throwing is treated as a failed attempt;
/// the message shown comes from [PasscodeSheet.errorText] when provided.
typedef PasscodeVerifier = FutureOr<bool> Function(String code);

/// Reusable PIN sheet. It knows nothing about exams or courses: the caller
/// decides what "correct" means ([verify]) and what happens next (the sheet
/// just resolves to true / false).
///
/// Exam:
/// ```dart
/// final ok = await PasscodeSheet.show(
///   context: context,
///   title: tx('exam_passcode_title'),
///   hint: tx('exam_passcode_hint'),
///   wrongText: tx('exam_passcode_wrong'),
///   pinLength: exam.passcode!.length,
///   verify: (code) => code == exam.passcode,
/// );
/// ```
///
/// Private course (server-side check, nothing secret on the client):
/// ```dart
/// final ok = await PasscodeSheet.show(
///   context: context,
///   title: ..., hint: ..., wrongText: ...,
///   verify: (code) async { await api.unlock(courseId, code); return true; },
///   errorText: (e) => e.toString(),
/// );
/// ```
class PasscodeSheet extends StatefulWidget {
  const PasscodeSheet({
    super.key,
    required this.title,
    required this.hint,
    required this.wrongText,
    required this.verify,
    this.errorText,
    this.pinLength = 6,
    this.icon = Icons.lock_outline_rounded,
  });

  final String title;
  final String hint;

  /// Shown when [verify] returns false.
  final String wrongText;

  /// Shown when [verify] throws (wrong code rejected by the server, rate
  /// limit, no network…). Falls back to [wrongText].
  final String Function(Object error)? errorText;

  final PasscodeVerifier verify;
  final int pinLength;
  final IconData icon;

  /// Shows the sheet. Resolves to true only if the code was accepted; false if
  /// the user closed it.
  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String hint,
    required String wrongText,
    required PasscodeVerifier verify,
    String Function(Object error)? errorText,
    int pinLength = 6,
    IconData icon = Icons.lock_outline_rounded,
  }) async {
    final ok = await showAppModalSheet<bool>(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      builder: (_) => PasscodeSheet(
        title: title,
        hint: hint,
        wrongText: wrongText,
        verify: verify,
        errorText: errorText,
        pinLength: pinLength,
        icon: icon,
      ),
    );
    return ok ?? false;
  }

  @override
  State<PasscodeSheet> createState() => _PasscodeSheetState();
}

class _PasscodeSheetState extends State<PasscodeSheet>
    with SingleTickerProviderStateMixin {
  // ── state ─────────────────────────────────────────────────────────────────
  String _entered = '';
  String? _error;
  bool _checking = false;

  late final AnimationController _shakeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  final FocusNode _focus = FocusNode();

  // ── design tokens (the live theme, Warm Editorial) ─────────────────────────
  // The sheet is paper on the kit's warm scrim; the code is ink (a digit is not a success), the error is the
  // danger's readable ink, the mark sits on the emerald block tint.
  ThemeConfigProvider get _c => context.colors;
  Color get _dotFilled => _c.textDark;
  Color get _dotEmpty => Color.lerp(_c.divider, _c.textDark, 0.3)!;
  Color get _errorRed => appInk(context, _c.danger);
  Color get _textSecondary => _c.textMedium;

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── logic ─────────────────────────────────────────────────────────────────
  void _onKey(String digit) {
    if (_checking || _entered.length >= widget.pinLength) return;
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      _entered += digit;
    });
    if (_entered.length == widget.pinLength) _submit();
  }

  void _onDelete() {
    if (_checking || _entered.isEmpty) return;
    setState(() {
      _error = null;
      _entered = _entered.substring(0, _entered.length - 1);
    });
  }

  Future<void> _submit() async {
    setState(() => _checking = true);
    // Let the last dot animate in before reacting.
    await Future.delayed(const Duration(milliseconds: 150));

    String error = widget.wrongText;
    try {
      final ok = await widget.verify(_entered);
      if (ok) {
        HapticFeedback.heavyImpact();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
    } catch (e) {
      error = widget.errorText?.call(e) ?? widget.wrongText;
    }

    if (!mounted) return;
    HapticFeedback.vibrate();
    _shakeCtrl.forward(from: 0);
    setState(() {
      _checking = false;
      _entered = '';
      _error = error;
    });
  }

  /// Physical keyboard (web / desktop / tablets with keyboards).
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = event.character;
    if (ch != null && ch.length == 1 && RegExp(r'^[0-9]$').hasMatch(ch)) {
      _onKey(ch);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _onDelete();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottomPadding = MediaQuery.viewInsetsOf(context).bottom;

    return Focus(
      autofocus: true,
      focusNode: _focus,
      onKeyEvent: _onKeyEvent,
      child: Container(
        constraints: BoxConstraints(maxHeight: size.height * 0.92),
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: SafeArea(
          top: false,
          // Scrolls instead of overflowing on short screens / landscape.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpace.sm),
                _buildHeader(),
                const SizedBox(height: AppSpace.lg),
                // PIN dots and keypad stay left-to-right in RTL locales.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Column(
                    children: [
                      _buildDots(),
                      _buildStatus(),
                      const SizedBox(height: AppSpace.sm),
                      _buildKeypad(),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final tone = AppBlockColors.of(context, AppBlockTone.emerald);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
      child: Column(
        children: [
          Container(
            width: AppTouch.primary,
            height: AppTouch.primary,
            decoration: BoxDecoration(
              color: tone.surface,
              shape: BoxShape.circle,
              border: tone.border == null ? null : Border.all(color: tone.border!, width: AppBorder.hairline),
            ),
            child: Icon(widget.icon, color: tone.accentInk(_c.primary), size: AppIconSize.lg),
          ),
          const SizedBox(height: AppSpace.md),
          Semantics(
            header: true,
            child: Text(widget.title, textAlign: TextAlign.center, style: AppType.headline(context)),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(widget.hint, textAlign: TextAlign.center, style: AppType.body(context).copyWith(height: 1.55)),
        ],
      ),
    );
  }

  Widget _buildDots() {
    final motion = AppMotion.of(context);
    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (context, child) {
        final t = _shakeCtrl.value;
        final dx = math.sin(t * math.pi * 6) * (1 - t) * 10;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Wrap(
        alignment: WrapAlignment.center,
        runSpacing: AppSpace.xs,
        children: List.generate(widget.pinLength, (i) {
          final filled = i < _entered.length;
          final hasError = _error != null;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs - 1),
            child: AnimatedScale(
              scale: filled ? 1.15 : 1,
              duration: motion.fast,
              curve: AppEase.out,
              child: AnimatedContainer(
                duration: motion.fast,
                curve: AppEase.out,
                width: AppSpace.sm + 2,
                height: AppSpace.sm + 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasError ? _errorRed : (filled ? _dotFilled : Colors.transparent),
                  border: Border.all(
                    color: hasError ? _errorRed : (filled ? _dotFilled : _dotEmpty),
                    width: AppBorder.strong,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Fixed-height strip under the dots: spinner while checking, error text
  /// after a failed attempt. Fixed height so the keypad never jumps.
  Widget _buildStatus() {
    return SizedBox(
      height: AppSpace.xxl - AppSpace.xxs,
      child: Center(
        child: _checking
            ? SizedBox(
                width: AppIconSize.sm + 2,
                height: AppIconSize.sm + 2,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: appInk(context, _c.primary),
                ),
              )
            : AnimatedOpacity(
                opacity: _error == null ? 0 : 1,
                duration: AppMotion.of(context).base,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                  child: Text(
                    _error ?? '',
                    textAlign: TextAlign.center,
                    style: AppType.label(context).copyWith(color: _errorRed),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildKeypad() {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['x', '0', 'del'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
      child: Column(
        children: keys.map((row) {
          return Row(
            children: row.map((key) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.xxs + 1),
                  child: key == 'x'
                      ? _buildCloseKey()
                      : key == 'del'
                      ? _buildDeleteKey()
                      : _buildDigitKey(key),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDigitKey(String digit) => _KeyButton(
    onTap: () => _onKey(digit),
    child: Text(digit, style: AppType.figureLarge(context).copyWith(fontWeight: FontWeight.w500, height: 1)),
  );

  Widget _buildDeleteKey() => _KeyButton(
    onTap: _onDelete,
    semanticLabel: AppConfig.lang == 'ar' ? 'حذف' : 'Delete',
    quiet: true,
    child: Icon(Icons.backspace_outlined, color: _textSecondary, size: AppIconSize.lg),
  );

  Widget _buildCloseKey() => _KeyButton(
    onTap: () => Navigator.of(context).pop(false),
    semanticLabel: AppConfig.lang == 'ar' ? 'إغلاق' : 'Close',
    quiet: true,
    child: Icon(Icons.close_rounded, color: _textSecondary, size: AppIconSize.lg),
  );
}

// ── reusable key button ───────────────────────────────────────────────────────
class _KeyButton extends StatefulWidget {
  const _KeyButton({required this.child, required this.onTap, this.quiet = false, this.semanticLabel});

  final Widget child;
  final VoidCallback onTap;

  /// An action key (close, delete): no plate, only the glyph, so the ten digits read as the keypad.
  final bool quiet;

  /// Read by screen readers on icon-only keys (delete, close).
  final String? semanticLabel;

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 160),
    lowerBound: 0.96,
    upperBound: 1.0,
    value: 1.0,
  );

  void _press() {
    _ctrl.reverse().then((_) {
      if (mounted) _ctrl.forward();
    });
    widget.onTap();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: ScaleTransition(
      scale: _ctrl,
      child: GestureDetector(
        onTap: _press,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: AppTouch.primary + AppSpace.xs,
          decoration: widget.quiet
              ? null
              : BoxDecoration(
                  color: c.cardBg,
                  borderRadius: AppRadius.cardAll,
                  border: Border.all(color: c.divider, width: AppBorder.hairline),
                ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
      ),
    );
  }
}
