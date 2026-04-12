import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/login_screen.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart' as Helpers;
import 'additional_register_screen.dart';
import 'change_password_screen.dart';

enum OtpFlowEnum { registration, forget, changePassword }

class OtpVerificationScreen extends StatefulWidget {
  final String? phoneNumber;
  final String email;
  final String role;
  final OtpFlowEnum flow;

  const OtpVerificationScreen(
      {super.key,
      this.phoneNumber,
      required this.email,
      this.flow = OtpFlowEnum.registration,
      required this.role});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with TickerProviderStateMixin {
  static const int otpLength = 4;
  static const int resendSeconds = 120;

  final List<TextEditingController> _controllers =
      List.generate(otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(otpLength, (_) => FocusNode());

  late AnimationController _shakeController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _shakeAnimation;

  int _remainingSeconds = resendSeconds;
  Timer? _resendTimer;
  bool _isLoading = false;
  bool _hasError = false;

  // Colors
  static const Color _backgroundColor = Color(0xFFE8F0FE);
  static const Color _primaryOrange = Color(0xFFF5A623);
  static const Color _darkText = Color(0xFF1A1A2E);
  static const Color _subtitleText = Color(0xFF6B7280);
  static const Color _activeBoxBorder = Color(0xFFF5A623);
  static const Color _inactiveBoxBorder = Color(0xFFD1D5DB);
  static const Color _filledBoxBg = Color(0xFFFFFFFF);
  static const Color _activeBoxBg = Color(0xFFFFFFFF);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _resendColor = Color(0xFFF5A623);

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    _startResendTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _remainingSeconds = resendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  String get _timerText {
    final minutes = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _fullOtp => _controllers.map((c) => c.text).join();

  bool get _isOtpComplete => _fullOtp.length == otpLength;

  void _onOtpChanged(int index, String value) {
    setState(() => _hasError = false);

    if (value.isNotEmpty) {
      if (index < otpLength - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
    }
  }

  Future<void> _onConfirm() async {
    if (_isOtpComplete) {
      bool success = await context
          .read<AuthProvider>()
          .verifyOtp(gmail: widget.email, code: _fullOtp);
      if (success) {
        if (widget.flow == OtpFlowEnum.registration) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => widget.role == 'student'
                    ? const LoginScreen()
                    : AdditionalRegisterScreen(
                        email: widget.email,
                      )),
          );
        } else if (widget.flow == OtpFlowEnum.forget) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => ChangePasswordScreen(
                      email: widget.email,
                    )),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => ChangePasswordScreen(
                      email: widget.email,
                    )),
          );
        }
      }
    }

    setState(() => _isLoading = true);

    // Simulate API call
    await Future.delayed(const Duration(seconds: 2));

    // Simulate failure for demo (replace with real logic)
    final isValid = _fullOtp != '0000';

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (isValid) {
      _showSuccessSnackbar();
    } else {
      setState(() => _hasError = true);
      _triggerShake();
      _showErrorSnackbar();
    }
  }

  void _triggerShake() {
    _shakeController.forward(from: 0);
  }

  void _showSuccessSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'تم التحقق بنجاح!',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'bahji'),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showErrorSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'رمز التحقق غير صحيح، حاول مرة أخرى',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'bahji'),
        ),
        backgroundColor: _errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _onResend() async {
    if (_remainingSeconds > 0) return;
    for (final c in _controllers) {
      c.clear();
    }
    setState(() => _hasError = false);
    _startResendTimer();
    _focusNodes[0].requestFocus();
    bool success = await context.read<AuthProvider>().resendOtp(widget.email);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'تم إعادة إرسال رمز التحقق',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'bahji'),
          ),
          backgroundColor: _primaryOrange,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _fadeController.dispose();
    _shakeController.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: pageDirection,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: false,
          title: Text(
            'forget_welcome'.tr,
            style: const TextStyle(fontFamily: 'bahji'),
          ),
        ),
        backgroundColor: _backgroundColor,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 48),
                        _buildHeader(),
                        SizedBox(height: context.height / 51),
                        _buildOtpFields(),
                        const SizedBox(height: 32),
                        _buildResendRow(),
                      ],
                    ),
                  ),
                ),
                _buildConfirmButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'enter_verification_code'.tr,
            style: const TextStyle(
              fontSize: 28,
              color: _darkText,
              height: 1.3,
              fontFamily: 'bahji',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'verification_code_sent'.tr,
                  style: const TextStyle(
                      fontSize: 14.5,
                      color: _subtitleText,
                      fontFamily: 'bahji'),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                widget.email.replaceRange(2, widget.email.length - 2,
                    '* ' * (widget.email.length - 4)),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                    color: _darkText,
                    fontFamily: 'bahji',
                    fontWeight: FontWeight.bold),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildOtpFields() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final shake = (_shakeAnimation.value * 4 * 3.14159).abs() < 0.01
            ? 0.0
            : 10 *
                (0.5 - (_shakeAnimation.value - 0.5).abs()) *
                (_shakeAnimation.value > 0.5 ? 1 : -1);
        return Transform.translate(
          offset: Offset(shake, 0),
          child: child,
        );
      },
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(otpLength, (index) {
            // Reverse order for RTL display (right to left entry)
            final displayIndex = otpLength - 1 - index;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: _buildSingleBox(displayIndex),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildSingleBox(int index) {
    return AnimatedBuilder(
      animation: Listenable.merge([_focusNodes[index]]),
      builder: (context, _) {
        final isFocused = _focusNodes[index].hasFocus;
        final isFilled = _controllers[index].text.isNotEmpty;

        Color borderColor;
        Color bgColor;

        if (_hasError) {
          borderColor = _errorColor;
          bgColor = _errorColor.withValues(alpha: 0.06);
        } else if (isFocused) {
          borderColor = _activeBoxBorder;
          bgColor = _activeBoxBg;
        } else if (isFilled) {
          borderColor = _inactiveBoxBorder;
          bgColor = _filledBoxBg;
        } else {
          borderColor = _inactiveBoxBorder;
          bgColor = Colors.white.withValues(alpha: 0.5);
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: context.width / (otpLength + 2),
          height: context.width / (otpLength + 2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor,
              width: isFocused ? 2.2 : 1.5,
            ),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: _primaryOrange.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (event) => _onKeyEvent(index, event),
            child: TextField(
              controller: _controllers[index],
              focusNode: _focusNodes[index],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: _hasError ? _errorColor : _darkText,
                fontFamily: 'bahji',
              ),
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) => _onOtpChanged(index, value),
              cursorColor: _primaryOrange,
              cursorWidth: 2,
              cursorHeight: 28,
            ),
          ),
        );
      },
    );
  }

  Widget _buildResendRow() {
    final canResend = _remainingSeconds == 0;

    return Center(
      child: GestureDetector(
        onTap: canResend ? _onResend : null,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: canResend ? _resendColor : _subtitleText,
            fontFamily: 'bahji',
            decoration:
                canResend ? TextDecoration.underline : TextDecoration.none,
            decorationColor: _resendColor,
          ),
          child: Text(
            canResend ? 'resend'.tr : 'resend_in'.tr + _timerText,
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 32),
      child: AnimatedOpacity(
        opacity: _isOtpComplete ? 1.0 : 0.65,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: _isLoading ? null : _onConfirm,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF5A623), Color(0xFFE8920E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: _primaryOrange.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: _isLoading
                  ? const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      'confirm'.tr,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        fontFamily: 'bahji',
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
