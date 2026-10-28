import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'package:provider/provider.dart';

import 'exam_tr.dart';
import 'exam_ui.dart';
import 'student_exam_detail_screen.dart';
import 'student_exam_provider.dart';

class ExamPasscodeSheet extends StatefulWidget {
  const ExamPasscodeSheet({
    super.key,
    required this.exam,
    required this.correctPasscode,
    this.provider,
  });

  final dynamic exam; // replace with your Exam model type
  final String correctPasscode;

  /// Provider handed down to the detail screen that opens after the sheet
  /// closes (the sheet lives on the root navigator, above the course screen).
  final StudentExamProvider? provider;

  /// Convenience method – shows the modal bottom sheet.
  static void show({
    required BuildContext context,
    required dynamic exam,
    required String correctPasscode,
    StudentExamProvider? provider,
  }) {
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.colors.heroShade.withValues(alpha: 0.55),
      builder: (_) => ExamPasscodeSheet(
        exam: exam,
        correctPasscode: correctPasscode,
        provider: provider,
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
  late final Animation<double> _shakeAnim = Tween<double>(begin: 0, end: 1)
      .animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut));

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
    if (mounted) {
      setState(() => _entered = _entered.substring(0, _entered.length - 1));
    }
  }

  Future<void> _verify() async {
    if (mounted) setState(() => _isChecking = true);
    // Slight delay so the last dot animates in before we react
    await Future.delayed(const Duration(milliseconds: 300));

    if (_entered == widget.correctPasscode) {
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      final nav = Navigator.of(context);
      final prov = widget.provider;
      nav.pop(); // close sheet
      nav.push(
        MaterialPageRoute(
          builder: (_) => prov == null
              ? StudentExamDetailScreen(exam: widget.exam)
              : ChangeNotifierProvider.value(
            value: prov,
            child: StudentExamDetailScreen(exam: widget.exam),
          ),
        ),
      );
    } else {
      HapticFeedback.vibrate();
      _shakeCtrl.forward(from: 0);
      if (!mounted) return;
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
    final c = context.colors;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: context.width > 500 ? 500 : context.width,
        height: context.height / 1.45,
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
                color: c.heroShade.withValues(alpha: .12), blurRadius: 24),
          ],
        ),
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHandle(c),
              _buildHeader(c),
              const SizedBox(height: 18),
              Expanded(child: _buildDots(c)),
              _buildErrorLabel(),
              const SizedBox(height: 14),
              _buildKeypad(c),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle(dynamic c) => Container(
    margin: const EdgeInsets.only(top: 12, bottom: 4),
    width: 44,
    height: 4,
    decoration: BoxDecoration(
      color: c.divider,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _buildHeader(dynamic c) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
    child: Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [context.colors.primaryDark, c.primary],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(Icons.lock_outline_rounded,
              color: context.colors.onHero, size: 30),
        ),
        const SizedBox(height: 16),
        Text(tx('exam_passcode_title'),
            style: examT(20, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(height: 6),
        Text(
          tx('exam_passcode_hint'),
          textAlign: TextAlign.center,
          style: examT(13, c: c.textMedium, h: 1.6),
        ),
      ],
    ),
  );

  Widget _buildDots(dynamic c) {
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (context, child) {
        final dx = _hasError
            ? 5 * (0.5 - (_shakeAnim.value % 0.25) / 0.25).abs() * 2 - 1
            : 0.0;
        return Transform.translate(offset: Offset(dx * 8, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_pinLength, (i) {
          final filled = i < _entered.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.symmetric(horizontal: 7),
            width: filled ? 18 : 14,
            height: filled ? 18 : 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hasError
                  ? context.colors.danger
                  : (filled ? c.primary : c.divider),
              boxShadow: filled && !_hasError
                  ? [
                BoxShadow(
                  color: c.primary.withValues(alpha: 0.4),
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

  Widget _buildErrorLabel() => AnimatedOpacity(
    opacity: _hasError ? 1 : 0,
    duration: const Duration(milliseconds: 200),
    child: Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(tx('exam_passcode_wrong'),
          style: examT(13, w: FontWeight.w700, c: context.colors.danger)),
    ),
  );

  Widget _buildKeypad(dynamic c) {
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
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: row.map((key) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: key == 'x'
                      ? _buildCloseKey()
                      : key == 'del'
                      ? _buildDeleteKey(c)
                      : _buildDigitKey(c, key),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDigitKey(dynamic c, String digit) => _KeyButton(
    onTap: () => _onKey(digit),
    child: Text(digit, style: examT(24, w: FontWeight.w600, c: c.textDark)),
  );

  Widget _buildDeleteKey(dynamic c) => _KeyButton(
    onTap: _onDelete,
    child: Icon(Icons.backspace_outlined, color: c.textMedium, size: 22),
  );

  Widget _buildCloseKey() => _KeyButton(
    onTap: () => Navigator.pop(context),
    background: context.colors.danger.withValues(alpha: 0.12),
    borderColor: context.colors.danger.withValues(alpha: 0.3),
    child: Icon(Icons.close_rounded, color: context.colors.danger, size: 24),
  );
}

// ── reusable key button ────────────────────────────────────────────────────────
class _KeyButton extends StatefulWidget {
  const _KeyButton({
    required this.child,
    required this.onTap,
    this.background,
    this.borderColor,
  });

  final Widget child;
  final VoidCallback onTap;
  final Color? background;
  final Color? borderColor;

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
    final c = context.colors;
    return ScaleTransition(
      scale: _ctrl,
      child: GestureDetector(
        onTap: _press,
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: widget.background ?? c.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.borderColor ?? c.divider.withValues(alpha: 0.7),
            ),
          ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}