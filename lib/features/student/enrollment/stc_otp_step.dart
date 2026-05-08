/// stc_otp_step.dart
/// Premium OTP input widget for STC Pay DCB flow.
/// Shows 6 digit boxes, auto-advances focus, handles paste, shake on error.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_theme.dart';
import 'enrollment_provider.dart';

class StcOtpStep extends StatefulWidget {
  const StcOtpStep({super.key});

  @override
  State<StcOtpStep> createState() => _StcOtpStepState();
}

class _StcOtpStepState extends State<StcOtpStep>
    with SingleTickerProviderStateMixin {
  static const _len = 6;

  final _ctrls  = List.generate(_len, (_) => TextEditingController());
  final _fNodes = List.generate(_len, (_) => FocusNode());

  late AnimationController _shake;
  late Animation<double>   _shakeAnim;

  Timer? _resendTimer;
  int    _resendSeconds = 60;
  bool   _canResend     = false;

  String get _otp => _ctrls.map((c) => c.text).join();
  bool   get _full => _otp.length == _len;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -6.0),  weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0),   weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0),    weight: 1),
    ]).animate(_shake);
    _startResendTimer();
  }

  void _startResendTimer() {
    _resendSeconds = 60;
    _canResend     = false;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) {
          _canResend = true;
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    for (final f in _fNodes) f.dispose();
    _shake.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_full) return;
    final p = context.read<EnrollmentProvider>();
    await p.submitStcOtp(_otp);
    if (p.stcOtpError != null) {
      _shake.forward(from: 0); // shake boxes on error
    }
  }

  // ── Handle digit input ────────────────────────────────────────────────────

  void _onChanged(int i, String v) {
    if (v.length > 1) {
      // Pasted full OTP
      _fillFromPaste(v);
      return;
    }
    if (v.isNotEmpty && i < _len - 1) {
      _fNodes[i + 1].requestFocus();
    }
    setState(() {});
  }

  void _onBackspace(int i) {
    if (_ctrls[i].text.isEmpty && i > 0) {
      _ctrls[i - 1].clear();
      _fNodes[i - 1].requestFocus();
      setState(() {});
    }
  }

  void _fillFromPaste(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    for (var i = 0; i < _len && i < digits.length; i++) {
      _ctrls[i].text = digits[i];
    }
    final next = digits.length < _len ? digits.length : _len - 1;
    _fNodes[next].requestFocus();
    setState(() {});
  }

  // ── Resend ────────────────────────────────────────────────────────────────

  Future<void> _resend() async {
    if (!_canResend) return;
    for (final c in _ctrls) c.clear();
    _startResendTimer();
    // Re-initiate the payment from provider — just shows loading briefly
    // In practice the user would go back and re-select STC Pay,
    // but we call retryFromStart for simplicity.
    if (mounted) context.read<EnrollmentProvider>().retryFromStart();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrollmentProvider>();
    final c = context.colors;

    return Column(
      children: [
        // ── App bar ────────────────────────────────────────────────────────
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  color: c.textDark, size: 20),
              onPressed: p.retryFromStart,
            ),
            Expanded(
              child: Text('رمز التحقق',
                  style:     c.h2.copyWith(fontSize: 17),
                  textAlign: TextAlign.center),
            ),
            const SizedBox(width: 44),
          ]),
        ),

        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                // ── STC Pay brand header ──────────────────────────────────
                Center(
                  child: Container(
                    width:  90,
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
                        begin:  Alignment.topLeft,
                        end:    Alignment.bottomRight,
                      ),
                      shape:     BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:      const Color(0xFF4A148C).withValues(alpha: .35),
                          blurRadius: 20,
                          offset:     const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.sim_card_rounded,
                        color: Colors.white, size: 44),
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  'STC Pay — رمز التحقق',
                  style:     c.h2.copyWith(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'تم إرسال رمز مكوّن من 6 أرقام إلى رقم جوالك المسجّل في STC Pay.\nأدخله أدناه لإتمام الدفع.',
                  style:     c.body.copyWith(height: 1.7),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // ── OTP boxes ─────────────────────────────────────────────
                AnimatedBuilder(
                  animation: _shakeAnim,
                  builder:   (_, child) => Transform.translate(
                    offset: Offset(_shakeAnim.value, 0),
                    child:  child,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_len, (i) => _OtpBox(
                      controller: _ctrls[i],
                      focusNode:  _fNodes[i],
                      hasError:   p.stcOtpError != null,
                      onChanged:  (v) => _onChanged(i, v),
                      onBackspace: () => _onBackspace(i),
                    )),
                  ),
                ),

                // ── Error message ─────────────────────────────────────────
                if (p.stcOtpError != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      p.stcOtpError!,
                      style: c.caption.copyWith(color: c.danger),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // ── Submit button ─────────────────────────────────────────
                GestureDetector(
                  onTap: _full && !p.isLoading ? _submit : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: _full
                          ? const LinearGradient(
                              colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
                              begin:  Alignment.topLeft,
                              end:    Alignment.bottomRight,
                            )
                          : LinearGradient(
                              colors: [
                                c.divider,
                                c.divider,
                              ],
                            ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: _full
                          ? [
                              BoxShadow(
                                color:      const Color(0xFF4A148C).withValues(alpha: .35),
                                blurRadius: 16,
                                offset:     const Offset(0, 6),
                              ),
                            ]
                          : [],
                    ),
                    child: Center(
                      child: p.isLoading
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            )
                          : Text(
                              'تأكيد الدفع',
                              style: TextStyle(
                                color:      _full ? Colors.white : c.textLight,
                                fontWeight: FontWeight.w800,
                                fontSize:   16,
                                fontFamily: 'Cairo',
                              ),
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Resend ────────────────────────────────────────────────
                Center(
                  child: GestureDetector(
                    onTap: _canResend ? _resend : null,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity:  _canResend ? 1.0 : 0.5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _canResend
                              ? c.primaryTint
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded,
                                size:  16,
                                color: _canResend ? c.primary : c.textLight),
                            const SizedBox(width: 6),
                            Text(
                              _canResend
                                  ? 'إعادة إرسال الرمز'
                                  : 'إعادة الإرسال خلال $_resendSeconds ثانية',
                              style: c.caption.copyWith(
                                color:      _canResend ? c.primary : c.textLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Security note ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:        c.primaryTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_rounded, color: c.primary, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'لا تشارك هذا الرمز مع أي شخص. لن يطلبه أي موظف من فريقنا.',
                          style: c.caption.copyWith(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Single OTP box ────────────────────────────────────────────────────────────

class _OtpBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode             focusNode;
  final bool                  hasError;
  final ValueChanged<String>  onChanged;
  final VoidCallback          onBackspace;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final c       = context.colors;
    final focused = widget.focusNode.hasFocus;
    final filled  = widget.controller.text.isNotEmpty;

    final borderColor = widget.hasError
        ? c.danger
        : focused
            ? const Color(0xFF4A148C)
            : filled
                ? c.primary
                : c.divider;

    return Container(
      width:  46,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color:        focused
            ? const Color(0xFF4A148C).withValues(alpha: .06)
            : c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: borderColor, width: focused ? 2 : 1.5),
        boxShadow:    focused ? [
          BoxShadow(
            color:      const Color(0xFF4A148C).withValues(alpha: .15),
            blurRadius: 8,
          ),
        ] : [],
      ),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (e) {
          if (e.logicalKey == LogicalKeyboardKey.backspace) {
            widget.onBackspace();
          }
        },
        child: TextField(
          controller:     widget.controller,
          focusNode:      widget.focusNode,
          textAlign:      TextAlign.center,
          keyboardType:   TextInputType.number,
          maxLength:      6,   // allow paste of full OTP
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            fontSize:    22,
            fontWeight:  FontWeight.w800,
            color:       widget.hasError ? c.danger : c.textDark,
            fontFamily:  'Cairo',
          ),
          decoration: const InputDecoration(
            counterText: '',
            border:      InputBorder.none,
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
