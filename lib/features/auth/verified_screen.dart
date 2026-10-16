import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/login_screen.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../config/theme/app_theme.dart';
import '../../config/theme/theme_config_provider.dart';
import '../shared/profile/change_password_widget.dart';
import 'additional_register_screen.dart';
import 'auth_widgets.dart';
import 'verify_way.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

enum OtpFlowEnum { registration, forget, changePassword }

class OtpVerificationScreen extends StatefulWidget {
  final String? phoneNumber;
  final String email;
  final String role;
  final OtpFlowEnum flow;

  /// Channels still to verify, in order: "email" and/or "phone". Registration/login
  /// pass AuthProvider.pendingChannels; forget-password ignores it.
  final List<String> channels;

  /// The way the student picked on the registration page (null = choose automatically:
  /// Telegram first when it is allowed and installed).
  final VerifyWay? initialWay;

  const OtpVerificationScreen({
    super.key,
    this.channels = const ['email'],
    this.initialWay,
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
  late List<String> _pending;

  // ── Phone verification by Telegram / WhatsApp link (admin: otp_phone_channel) ──
  PhoneLinkSession? _link;
  Timer? _pollTimer;
  bool _linkLoading = false;
  bool _polling = false;
  String? _linkError;
  bool? _telegramInstalled; // null = not checked yet

  // ── Verification ways allowed by the admin (registration flow) ───────────────
  /// Every way of the channels that were pending when this screen opened.
  List<VerifyWay> _allWays = const [];

  /// The way selected right now; the student can switch it with the switcher.
  VerifyWay? _way;

  /// The channel being verified right now (registration flow only).
  String get _channel {
    if (_pending.isEmpty) return 'email';
    final w = _way;
    if (w != null && _pending.contains(w.channel)) return w.channel;
    return _pending.first;
  }

  /// Ways shown in the switcher. Telegram / WhatsApp the server did not configure are hidden.
  List<VerifyWay> get _visibleWays {
    if (widget.flow != OtpFlowEnum.registration) return const [];
    final offered = _link?.methods;
    final linkMode = context.read<MyAuthProvider>().phoneUsesLink;
    return _allWays.where((w) {
      final isLinkWay = w == VerifyWay.telegram || w == VerifyWay.whatsapp;
      if (linkMode && isLinkWay && offered != null) return offered.contains(w.name);
      return true;
    }).toList();
  }

  /// The phone step is done with a Telegram / WhatsApp link instead of typing a code.
  bool get _useLink =>
      widget.flow == OtpFlowEnum.registration &&
          _channel == 'phone' &&
          context.read<MyAuthProvider>().phoneUsesLink;

  @override
  void initState() {
    super.initState();
    _pending = widget.channels.isEmpty ? ['email'] : List.of(widget.channels);
    if (widget.flow == OtpFlowEnum.registration) {
      _allWays = verifyWaysForChannels(context.read<MyAuthProvider>(), _pending);
      final picked = widget.initialWay;
      _way = (picked != null && _allWays.contains(picked))
          ? picked
          : (_allWays.isEmpty ? null : _allWays.first);
    }
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Nothing was picked and both Telegram and WhatsApp are allowed: Telegram has the
      // priority, but only when the student has it (otherwise WhatsApp goes first).
      if (widget.initialWay == null &&
          _way == VerifyWay.telegram &&
          _allWays.contains(VerifyWay.whatsapp)) {
        _telegramInstalled = await _detectTelegram();
        if (!mounted) return;
        if (_telegramInstalled == false) setState(() => _way = VerifyWay.whatsapp);
      }
      _prepareChannel();
    });
  }

  /// Sets up the step for the channel being verified: the link flow for phone
  /// (when the admin chose Telegram / WhatsApp), the code boxes otherwise.
  void _prepareChannel() {
    _pollTimer?.cancel();
    _link = null;
    _linkError = null;
    if (_useLink) {
      _startLink();
    } else {
      _startResendTimer();
      _focusNodes[0].requestFocus();
    }
  }

  Future<bool> _detectTelegram() async {
    if (kIsWeb) return true; // a browser cannot tell; the t.me link handles both cases
    try {
      return await canLaunchUrl(Uri.parse('tg://resolve'));
    } catch (_) {
      return false;
    }
  }

  Future<void> _startLink() async {
    final auth = context.read<MyAuthProvider>();
    setState(() {
      _linkLoading = true;
      _linkError = null;
      _link = null;
    });
    _telegramInstalled ??= await _detectTelegram();
    final session = await auth.startPhoneLink(widget.email);
    if (!mounted) return;
    if (session == null) {
      setState(() {
        _linkLoading = false;
        _linkError = auth.errorMessage ?? 'generic_error'.tr;
      });
      return;
    }
    if (session.verified) {
      setState(() => _linkLoading = false);
      _afterVerified(auth);
      return;
    }
    setState(() {
      _link = session;
      _linkLoading = false;
      // the selected way is not offered by the server: fall back to one that is
      final wanted = _way?.name;
      if (wanted != null &&
          (_way == VerifyWay.telegram || _way == VerifyWay.whatsapp) &&
          !session.methods.contains(wanted)) {
        final fallback = _allWays.where((w) => session.methods.contains(w.name));
        if (fallback.isNotEmpty) _way = fallback.first;
      }
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollLink());
  }

  Future<void> _pollLink() async {
    final link = _link;
    if (link == null || _polling || !mounted) return;
    final auth = context.read<MyAuthProvider>();
    _polling = true;
    final state = await auth.checkPhoneLink(link.token);
    _polling = false;
    if (!mounted) return;
    if (state == 'verified') {
      _pollTimer?.cancel();
      _afterVerified(auth);
    } else if (state == 'expired') {
      _pollTimer?.cancel();
      setState(() {
        _link = null;
        _linkError = 'phone_link_expired'.tr;
      });
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('could_not_open_link'.tr),
          backgroundColor: context.colors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openTelegram(PhoneLinkSession s) async {
    if (!kIsWeb && s.telegramAppUrl != null) {
      try {
        if (await launchUrl(Uri.parse(s.telegramAppUrl!),
            mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {} // app not installed: fall back to the https link
    }
    if (s.telegramUrl != null) await _open(Uri.parse(s.telegramUrl!));
  }

  Future<void> _openWhatsapp(PhoneLinkSession s) async {
    if (s.whatsappUrl != null) await _open(Uri.parse(s.whatsappUrl!));
  }

  String? _urlFor(PhoneLinkSession s, String method) =>
      method == 'telegram' ? s.telegramUrl : s.whatsappUrl;

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('phone_link_copied'.tr),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Flutter web only: a laptop usually has no Telegram / WhatsApp, so let the student
  /// continue on their phone by scanning a QR code (or copying the link). The page keeps
  /// polling, so it moves on by itself once the phone has confirmed the number.
  List<Widget> _buildQrSection(PhoneLinkSession s, VerifyWay way) {
    final url = _urlFor(s, way.name);
    if (url == null) return const [];
    final c = context.colors;
    return [
      const SizedBox(height: 24),
      Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('phone_link_open_on_phone'.tr, style: c.body),
          ),
          const Expanded(child: Divider()),
        ],
      ),
      const SizedBox(height: 16),
      Center(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white, // QR codes need a light background, also in dark mode
            borderRadius: BorderRadius.circular(c.radiusMedium),
            border: Border.all(color: way.brand.withValues(alpha: 0.45), width: 2),
            boxShadow: [
              BoxShadow(
                color: way.brand.withValues(alpha: 0.18),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: QrImageView(
            data: url,
            size: 190,
            padding: const EdgeInsets.all(12),
            backgroundColor: Colors.white,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text('phone_link_scan'.tr, textAlign: TextAlign.center, style: c.body),
      const SizedBox(height: 4),
      Center(
        child: TextButton.icon(
          onPressed: () => _copyLink(url),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text('phone_link_copy'.tr),
        ),
      ),
    ];
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
      final auth = context.read<MyAuthProvider>();
      final success = widget.flow == OtpFlowEnum.registration
          ? await auth.verifyOtp(gmail: widget.email, code: _fullOtp, channel: _channel)
          : await auth.verifyResetOtp(gmail: widget.email, code: _fullOtp);
      if(mounted) if(mounted) setState(() => _isLoading = false);

      if (success && mounted) {
        _afterVerified(auth);
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

  /// A channel was verified (by code or by link). Admin requires BOTH e-mail and
  /// phone: after the first one, move on to the next; otherwise leave the screen.
  void _afterVerified(MyAuthProvider auth) {
    if (widget.flow == OtpFlowEnum.registration && auth.pendingChannels.isNotEmpty) {
      setState(() {
        _pending = List.of(auth.pendingChannels);
        _hasError = false;
        // move the selection to a way of a channel that is still pending
        final left = _allWays.where((w) => _pending.contains(w.channel)).toList();
        _way = left.isEmpty ? null : (left.contains(_way) ? _way : left.first);
      });
      for (final c in _controllers) {
        c.clear();
      }
      _prepareChannel();
      return;
    }
    if (widget.flow == OtpFlowEnum.registration) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          // Only teachers have the extra profile step; students AND parents go straight to login.
          builder: (_) => widget.role == 'teacher'
              ? AdditionalRegisterScreen(email: widget.email)
              : const LoginScreen(),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChangePasswordScreen(email: widget.email, fromProfile: false, code: _fullOtp),
        ),
      );
    }
  }

  /// The student switched the verification way in the switcher.
  void _selectWay(VerifyWay w) {
    if (w == _way) return;
    final channelChanged = w.channel != _channel;
    setState(() {
      _way = w;
      _hasError = false;
    });
    if (channelChanged) {
      for (final c in _controllers) {
        c.clear();
      }
      _prepareChannel(); // e-mail code boxes <-> phone step
    }
    // Telegram <-> WhatsApp stay on the same link session: only the selected way changes.
  }

  Future<void> _onResend() async {
    if (_remainingSeconds > 0) return;
    for (final c in _controllers) {
      c.clear();
    }
    if(mounted) if(mounted) setState(() => _hasError = false);
    _startResendTimer();
    _focusNodes[0].requestFocus();
    final success = await context.read<MyAuthProvider>().resendOtp(
      widget.email,
      reset: widget.flow != OtpFlowEnum.registration,
      channel: widget.flow == OtpFlowEnum.registration ? _channel : null,
    );
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
    _pollTimer?.cancel();
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

            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, context.height / 12, 20, 24),
                  child: form(false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  bool get _isPhoneStep {
    if (widget.flow == OtpFlowEnum.registration) return _channel == 'phone';
    // forget-password by phone number. With link verification the reset code is
    // e-mailed instead (the server says so), so it is not a "phone" step.
    return !widget.email.contains('@') && !context.read<MyAuthProvider>().phoneUsesLink;
  }

  String get _destination {
    if (_isPhoneStep) {
      return widget.phoneNumber ??
          context.read<MyAuthProvider>().pendingPhoneMasked ??
          widget.email;
    }
    if (widget.flow != OtpFlowEnum.registration && !widget.email.contains('@')) {
      return context.read<MyAuthProvider>().resetEmailMasked ?? widget.email;
    }
    return widget.email;
  }

  String get _sentToHint {
    if (!_isPhoneStep) return 'verification_code_sent'.tr;
    return context.read<MyAuthProvider>().otpPhoneChannel == 'whatsapp'
        ? 'verification_code_sent_whatsapp'.tr
        : 'verification_code_sent_sms'.tr;
  }

  Widget form (bool isWeb) {
    Widget main=Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if(isWeb)
          ProgressBar(currentStep: 1, totalSteps:3),
        const SizedBox(height: 28),

        // Every way the admin allows; the student can switch at any time.
        if (_visibleWays.length > 1) ...[
          VerifyWaySwitcher(
            ways: _visibleWays,
            selected: _way,
            verified: {
              for (final w in _allWays)
                if (!_pending.contains(w.channel)) w,
            },
            onChanged: _selectWay,
          ),
          const SizedBox(height: 28),
        ],

        Text(
          _useLink ? 'phone_link_title'.tr : 'enter_verification_code'.tr,
          style: context.colors.h1,
        ),
        const SizedBox(height: 8),
        Text(
          _useLink ? 'phone_link_hint'.tr : _sentToHint,
          style: context.colors.body,
        ),
        const SizedBox(height: 8),
        Text(
          _destination,
          textDirection: TextDirection.ltr,
          style:  TextStyle(
            fontWeight: FontWeight.w700,
            color: context.colors.textDark,
          ),
        ),
        const SizedBox(height: 32),
        if (_useLink)
          ..._buildLinkSection()
        else ...[
          _buildOtpFields(),
          const SizedBox(height: 24),
          _buildResendRow(),
          const SizedBox(height: 32),
          _buildConfirmButton(),
        ],
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
  /// The Telegram / WhatsApp step for the selected way. The other way (when the admin
  /// allows both) is one tap away in the switcher at the top of the screen.
  List<Widget> _buildLinkSection() {
    if (_linkLoading) {
      return const [Center(child: AppLoadingIndicator())];
    }
    final s = _link;
    if (s == null) {
      return [
        if (_linkError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _linkError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.danger, fontWeight: FontWeight.w600),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _startLink,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('phone_link_new'.tr),
        ),
      ];
    }

    var method = _way == VerifyWay.whatsapp ? 'whatsapp' : 'telegram';
    if (!s.methods.contains(method)) {
      if (s.methods.isEmpty) {
        return [
          Text('generic_error'.tr, textAlign: TextAlign.center, style: context.colors.body),
        ];
      }
      method = s.methods.first;
    }
    final way = method == 'telegram' ? VerifyWay.telegram : VerifyWay.whatsapp;
    return [
      VerifyWayButton(
        way: way,
        label: (way == VerifyWay.telegram ? 'phone_link_telegram' : 'phone_link_whatsapp').tr,
        onPressed: () => way == VerifyWay.telegram ? _openTelegram(s) : _openWhatsapp(s),
      ),
      if (kIsWeb) ..._buildQrSection(s, way),
      const SizedBox(height: 20),
      Text(
        (way == VerifyWay.telegram ? 'phone_link_tg_steps' : 'phone_link_wa_steps').tr,
        textAlign: TextAlign.center,
        style: context.colors.body,
      ),
      const SizedBox(height: 4),
      Text(
        'phone_link_same_number'.tr,
        textAlign: TextAlign.center,
        style: context.colors.body,
      ),
      const SizedBox(height: 20),
      VerifyWayStatusPill(way: way, label: 'phone_link_waiting'.tr),
    ];
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