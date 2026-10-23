import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final ok = await showModalBottomSheet<bool>(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
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

  // ── design tokens ─────────────────────────────────────────────────────────
  static const _bgColor = Color(0xFF0D0D14);
  static const _surfaceColor = Color(0xFF15151F);
  static const _accentGold = Color(0xFFC9A84C);
  static const _dotFilled = Color(0xFFC9A84C);
  static const _dotEmpty = Color(0xFF2A2A3A);
  static const _errorRed = Color(0xFFE05C5C);
  static const _textPrimary = Color(0xFFF4F0E8);
  static const _textSecondary = Color(0xFF8A8498);

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
        width: math.min(size.width, 500.0),
        constraints: BoxConstraints(maxHeight: size.height * 0.92),
        decoration: const BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: SafeArea(
          top: false,
          // Scrolls instead of overflowing on short screens / landscape.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHandle(),
                _buildHeader(),
                const SizedBox(height: 28),
                // PIN dots and keypad stay left-to-right in RTL locales.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Column(
                    children: [
                      _buildDots(),
                      _buildStatus(),
                      const SizedBox(height: 12),
                      _buildKeypad(),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() => Container(
    margin: const EdgeInsets.only(top: 14, bottom: 4),
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: const Color(0xFF3A3A4A),
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
    child: Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_accentGold, Color(0xFF8B6914)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _accentGold.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(widget.icon, color: _bgColor, size: 28),
        ),
        const SizedBox(height: 18),
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            fontFamily: 'Georgia',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.hint,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 14,
            height: 1.55,
            letterSpacing: 0.1,
          ),
        ),
      ],
    ),
  );

  Widget _buildDots() {
    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (context, child) {
        final t = _shakeCtrl.value;
        final dx = math.sin(t * math.pi * 6) * (1 - t) * 10;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Wrap(
        alignment: WrapAlignment.center,
        runSpacing: 8,
        children: List.generate(widget.pinLength, (i) {
          final filled = i < _entered.length;
          final hasError = _error != null;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 7),
            width: filled ? 16 : 14,
            height: filled ? 16 : 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasError ? _errorRed : (filled ? _dotFilled : _dotEmpty),
              boxShadow: filled && !hasError
                  ? [
                      BoxShadow(
                        color: _accentGold.withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
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
      height: 44,
      child: Center(
        child: _checking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _accentGold,
                ),
              )
            : AnimatedOpacity(
                opacity: _error == null ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _error ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _errorRed,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
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
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: keys.map((row) {
          return Row(
            children: row.map((key) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(5),
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
    child: Text(
      digit,
      style: const TextStyle(
        color: _textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w300,
        letterSpacing: 1,
      ),
    ),
  );

  Widget _buildDeleteKey() => _KeyButton(
    onTap: _onDelete,
    child: const Icon(Icons.backspace_outlined, color: _textSecondary, size: 22),
  );

  Widget _buildCloseKey() => _KeyButton(
    onTap: () => Navigator.of(context).pop(false),
    background: Colors.red.shade400,
    child: const Icon(Icons.clear, color: Colors.white, size: 22),
  );
}

// ── reusable key button ───────────────────────────────────────────────────────
class _KeyButton extends StatefulWidget {
  const _KeyButton({required this.child, required this.onTap, this.background});

  final Widget child;
  final VoidCallback onTap;
  final Color? background;

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 160),
    lowerBound: 0.88,
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
    return ScaleTransition(
      scale: _ctrl,
      child: GestureDetector(
        onTap: _press,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: widget.background ?? const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2E2E40), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
