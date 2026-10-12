import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/login_screen.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../config/theme/theme_config_provider.dart';
import '../shared/profile/change_password_widget.dart';
import 'additional_register_screen.dart';
import 'auth_widgets.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

enum OtpFlowEnum { registration, forget, changePassword }

class OtpVerificationScreen extends StatefulWidget {
  final String? phoneNumber;
  final String email;
  final String role;
  final OtpFlowEnum flow;

  const OtpVerificationScreen({
    super.key,
    this.phoneNumber,
    required this.email,
    this.flow = OtpFlowEnum.registration,
    required this.role,
  });

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
    if(mounted) if(mounted) setState(() => _remainingSeconds = resendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
      } else {
        if(mounted) if(mounted) setState(() => _remainingSeconds--);
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
    if(mounted) if(mounted) setState(() => _hasError = false);
    if (value.isNotEmpty && index < otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
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
      if(mounted) if(mounted) setState(() => _isLoading = true);
      final auth = context.read<AuthProvider>();
      final success = widget.flow == OtpFlowEnum.registration
          ? await auth.verifyOtp(gmail: widget.email, code: _fullOtp)
          : await auth.verifyResetOtp(gmail: widget.email, code: _fullOtp);
      if(mounted) if(mounted) setState(() => _isLoading = false);

      if (success && mounted) {
        if (widget.flow == OtpFlowEnum.registration) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => widget.role == 'student'
                  ? const LoginScreen()
                  : AdditionalRegisterScreen(email: widget.email),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ChangePasswordScreen(email: widget.email,fromProfile: false,code: _fullOtp,),
            ),
          );
        }
      } else if (mounted) {
        if(mounted) if(mounted) setState(() => _hasError = true);
        _shakeController.forward(from: 0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('invalid_otp'.tr),
            backgroundColor: context.colors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _onResend() async {
    if (_remainingSeconds > 0) return;
    for (final c in _controllers) {
      c.clear();
    }
    if(mounted) if(mounted) setState(() => _hasError = false);
    _startResendTimer();
    _focusNodes[0].requestFocus();
    final success = await context.read<AuthProvider>().resendOtp(widget.email, reset: widget.flow != OtpFlowEnum.registration);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('otp_resent'.tr),
          backgroundColor: context.colors.success,
          behavior: SnackBarBehavior.floating,
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
    bool isWeb=MediaQuery.of(context).size.width > 800;
    return BasePage(
      appBar:isWeb?null: ScreenAppBar(title: 'verification'.tr),
      child:  SafeArea(
        child: (isWeb)?
        Row(
          children: [
            AuthSidebar(),
            form(true)
          ],
        ):Column(
          children: [
            ProgressBar(currentStep: 1, totalSteps:3),

            Padding(
              padding:  EdgeInsets.fromLTRB(20,context.height/7,20,0),
              child: form(false),
            ),
          ],
        ),
      ),
    );
  }
  Widget form (bool isWeb) {
    Widget main=Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if(isWeb)
          ProgressBar(currentStep: 1, totalSteps:3),
        const SizedBox(height: 28),

        Text(
          'enter_verification_code'.tr,
          style: context.colors.h1,
        ),
        const SizedBox(height: 8),
        Text(
          'verification_code_sent'.tr,
          style: context.colors.body,
        ),
        const SizedBox(height: 8),
        Text(
          widget.email,
          style:  TextStyle(
            fontWeight: FontWeight.w700,
            color: context.colors.textDark,
          ),
        ),
        const SizedBox(height: 32),
        _buildOtpFields(),
        const SizedBox(height: 24),
        _buildResendRow(),
        const SizedBox(height: 32),
        _buildConfirmButton(),
      ],
    );
    if(isWeb) {
      return Expanded(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(context.colors.radiusXL),
                  ),
                  color: context.colors.cardBg,
                  child: ColoredBox(
                    color:context.colors.isDark?context.colors.primaryDark: context.colors.primary.withAlpha(30),
                    child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: main
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return main;
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
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(otpLength, (index) {
            return _buildSingleBox(index);
          }),
        ),
      ),
    );
  }

  Widget _buildSingleBox(int index) {
    final isFocused = _focusNodes[index].hasFocus;
    final isFilled = _controllers[index].text.isNotEmpty;
    Color borderColor;
    Color bgColor;

    if (_hasError) {
      borderColor = context.colors.danger;
      bgColor = context.colors.danger.withValues(alpha: 0.05);
    } else if (isFocused) {
      borderColor = context.colors.primary;
      bgColor = context.colors.background;
    } else if (isFilled) {
      borderColor = context.colors.primary.withValues(alpha: 0.5);
      bgColor = context.colors.background;
    } else {
      borderColor = context.colors.divider;
      bgColor = context.colors.inputBg;
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(context.colors.radiusMedium),
            border: Border.all(color: borderColor, width: isFocused ? 2 : 1),
            boxShadow: isFocused
                ? [
              BoxShadow(
                color: context.colors.primary.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ]
                : null,
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
              style:  TextStyle(
                fontSize: 28,
                height: 2.7,
                fontWeight: FontWeight.w800,
                color: context.colors.textDark,
              ),
              decoration:  InputDecoration(
                constraints: BoxConstraints(minHeight: 70),
                focusColor:  context.colors.cardBg,
                counterText: '',
                border: InputBorder.none,
                fillColor: context.colors.cardBg,
                contentPadding: EdgeInsets.zero,
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(context.colors.radiusMedium)
                ),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(context.colors.radiusMedium)
                ),
                disabledBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(context.colors.radiusMedium)
                ),
              ),

              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) => _onOtpChanged(index, value),
              cursorColor: context.colors.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResendRow() {
    final canResend = _remainingSeconds == 0;
    return Center(
      child: GestureDetector(
        onTap: canResend ? _onResend : null,
        child: Text(
          canResend ? 'resend'.tr : 'resend_in'.tr + _timerText,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: canResend ? context.colors.primary : context.colors.textLight,
            decoration:
            canResend ? TextDecoration.underline : TextDecoration.none,
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmButton() {
    return ElevatedButton(
      onPressed: _isOtpComplete && !_isLoading ? _onConfirm : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: context.colors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        ),
      ),
      child: _isLoading
          ? const SizedBox(
          width: 24,
          height: 24,
          child: AppLoadingIndicator())
          : Text('confirm'.tr,
          style:
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}