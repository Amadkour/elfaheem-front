import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';

import 'student_exam_detail_screen.dart';

class ExamPasscodeSheet extends StatefulWidget {
  const ExamPasscodeSheet({
    super.key,
    required this.exam,
    required this.correctPasscode,
  });

  final dynamic exam; // replace with your Exam model type
  final String correctPasscode;

  /// Convenience method – shows the modal bottom sheet.
  static void show({
    required BuildContext context,
    required dynamic exam,
    required String correctPasscode,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => ExamPasscodeSheet(
        exam: exam,
        correctPasscode: correctPasscode,
      ),
    );
  }

  @override
  State<ExamPasscodeSheet> createState() => _ExamPasscodeSheetState();
}

class _ExamPasscodeSheetState extends State<ExamPasscodeSheet>
    with SingleTickerProviderStateMixin {
  // ── state ─────────────────────────────────────────────────────────────────
  final int _pinLength = 6;
  String _entered = '';
  bool _hasError = false;
  bool _isChecking = false;

  // ── shake animation ────────────────────────────────────────────────────────
  late final AnimationController _shakeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  late final Animation<double> _shakeAnim =
      Tween<double>(begin: 0, end: 1).animate(
    CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut),
  );

  // ── colours / design tokens ───────────────────────────────────────────────
  static const _bgColor = Color(0xFF0D0D14);
  static const _surfaceColor = Color(0xFF15151F);
  static const _accentGold = Color(0xFFC9A84C);
  static const _accentGoldLight = Color(0xFFE8C97A);
  static const _dotFilled = Color(0xFFC9A84C);
  static const _dotEmpty = Color(0xFF2A2A3A);
  static const _errorRed = Color(0xFFE05C5C);
  static const _textPrimary = Color(0xFFF4F0E8);
  static const _textSecondary = Color(0xFF8A8498);

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  // ── logic ──────────────────────────────────────────────────────────────────
  void _onKey(String digit) {
    if (_entered.length >= _pinLength || _isChecking) return;
    HapticFeedback.lightImpact();
    setState(() {
      _hasError = false;
      _entered += digit;
    });
    if (_entered.length == _pinLength) _verify();
  }

  void _onDelete() {
    if (_entered.isEmpty || _isChecking) return;
    // HapticFeedback.selectionClick();
    if(mounted) if(mounted) setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _verify() async {
    if(mounted) if(mounted) setState(() => _isChecking = true);
    // Slight delay so the last dot animates in before we react
    await Future.delayed(const Duration(milliseconds: 300));

    if (_entered == widget.correctPasscode) {
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      Navigator.of(context).pop(); // close sheet
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StudentExamDetailScreen(exam: widget.exam),
        ),
      );
    } else {
      HapticFeedback.vibrate();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _hasError = true;
        _isChecking = false;
        _entered = '';
      });
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      width: context.width > 500 ? 500 : context.width,
      height: context.height/1.5,
      decoration: const BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHandle(),
            _buildHeader(),
            const SizedBox(height: 32),
            Expanded(child: _buildDots()),
            _buildErrorLabel(),
            const SizedBox(height: 36),
            _buildKeypad(),
            const SizedBox(height: 24),
          ],
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
            // Icon badge
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
              child: const Icon(
                Icons.lock_outline_rounded,
                color: _bgColor,
                size: 28,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Exam Passcode',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                fontFamily: 'Georgia', // elegant serif fallback
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the 6-digit code provided\nby your instructor to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(
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
      animation: _shakeAnim,
      builder: (context, child) {
        final dx = _hasError
            ? 5 * (0.5 - (_shakeAnim.value % 0.25) / 0.25).abs() * 2 - 1
            : 0.0;
        return Transform.translate(
          offset: Offset(dx * 8, 0),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_pinLength, (i) {
          final filled = i < _entered.length;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 7),
            width: filled ? 16 : 14,
            height: filled ? 16 : 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hasError ? _errorRed : (filled ? _dotFilled : _dotEmpty),
              boxShadow: filled && !_hasError
                  ? [
                      BoxShadow(
                        color: _accentGold.withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildErrorLabel() {
    return AnimatedOpacity(
      opacity: _hasError ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'Incorrect passcode. Please try again.',
          style: TextStyle(
            color: _errorRed,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['x', '0', 'del'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: keys.map((row) {
          return  Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: row.map((key) {
                return Expanded(
                    child:Padding(
                    padding: const EdgeInsets.all(5),
                    child: (key=='x')
                        ? _buildCloseKey()
                        : (key == 'del')
                            ? _buildDeleteKey()
                            : _buildDigitKey(key)));
              }).toList(),

          );
        }).toList(),
      ),
    );
  }

  Widget _buildDigitKey(String digit) {
    return _KeyButton(
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
  }

  Widget _buildDeleteKey() {
    return _KeyButton(
      onTap: _onDelete,
      child: const Icon(
        Icons.backspace_outlined,
        color: _textSecondary,
        size: 22,
      ),
    );
  }
  Widget _buildCloseKey() {
    return _KeyButton(
      onTap: ()=>Navigator.pop(context),
      background: Colors.red.shade400,
      child: const Icon(
      Icons.clear,
      color: Colors.white,
      size: 22,
    ),
    );
  }
}

// ── reusable key button ────────────────────────────────────────────────────────
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
    _ctrl.reverse().then((_) => _ctrl.forward());
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
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: widget.background?? const Color(0xFF1E1E2C),
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
