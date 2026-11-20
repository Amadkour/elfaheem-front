// features/auth/verified_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// ONE verification page for every flow:
//   registration · login of an unverified account · Google sign-up · forgot password
//   · change password.
//
// It shows every way the admin allows AND the server can send — Telegram, E-mail,
// WhatsApp, SMS — in this priority order (the admin may put another way first):
//   Telegram > E-mail > WhatsApp > SMS
// The student can switch between them at any time:
//   • code ways   (E-mail, SMS, WhatsApp code)  -> 6 code boxes, paste / auto-fill,
//                                                  auto-submit, a resend timer PER way
//   • link ways   (Telegram, WhatsApp link)     -> brand button, QR code on the web,
//                                                  live status while we wait for the message
// A way that was not used yet is sent automatically the first time it is selected.
// When the admin requires E-mail AND phone, a step tracker shows what is done.
// Forgot / change password offers the ways a reset CODE can reach (E-mail, WhatsApp
// code, SMS); links cannot carry a code, so they never appear there.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_education_app/core/share/external_link.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/login_screen.dart';
import 'package:provider/provider.dart';
import '../../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/profile/change_password_widget.dart';
import 'additional_register_screen.dart';
import 'auth_shell.dart';
import 'auth_widgets.dart';
import '../../design/app_charts.dart' show appInk;
import '../../design/app_tokens.dart';
import 'username.dart' show IdentifierKind, identifierKindOf;
import 'verify_way.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

/// [phoneChange]: a signed-in person verifies the number they just set on the profile (registration-style
/// endpoints, channel "phone" only); on success the screen pops back instead of going to login.
enum OtpFlowEnum { registration, forget, changePassword, phoneChange }

class OtpVerificationScreen extends StatefulWidget {
  final String? phoneNumber;
  final String email;
  final String role;
  final OtpFlowEnum flow;

  /// Channels still to verify, in order: "email" and/or "phone". Registration/login
  /// pass AuthProvider.pendingChannels; forget-password ignores it.
  final List<String> channels;

  /// The way picked on the registration page (null = the first way of the priority list).
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
  /// The server sends 6-digit codes (back/services/auth_security.py OTP_LENGTH).
  static const int otpLength = 6;
  static const int resendSeconds = 120;

  final List<TextEditingController> _controllers = List.generate(
    otpLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    otpLength,
    (_) => FocusNode(),
  );

  late final AnimationController _shakeController;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  // ── state ────────────────────────────────────────────────────────────────
  bool _isLoading = false;
  bool _hasError = false;
  bool _sending = false; // a code is being requested right now
  late List<String> _pending; // channels still to verify
  late final List<String>
  _allChannels; // every channel of this flow (step tracker)

  /// Every way of the channels that were pending when this screen opened.
  List<VerifyWay> _allWays = const [];

  /// The way selected right now.
  VerifyWay? _way;

  /// Ways a code was already requested for (the server sent the first one itself).
  final Set<VerifyWay> _sent = {};

  /// Seconds left before a code can be requested again — one timer per way.
  final Map<VerifyWay, int> _cooldown = {};
  Timer? _ticker;

  // ── Telegram / WhatsApp link ─────────────────────────────────────────────
  PhoneLinkSession? _link;
  Timer? _pollTimer;
  bool _linkLoading = false;
  bool _polling = false;
  String? _linkError;
  bool? _telegramInstalled; // null = not checked yet

  // ── helpers ──────────────────────────────────────────────────────────────
  bool get _isReg =>
      widget.flow == OtpFlowEnum.registration || widget.flow == OtpFlowEnum.phoneChange;

  MyAuthProvider get _auth => context.read<MyAuthProvider>();

  /// The channel being verified right now (registration).
  String get _channel {
    if (_pending.isEmpty) return 'email';
    final w = _way;
    if (w != null && _pending.contains(w.channel)) return w.channel;
    return _pending.first;
  }

  /// Verified with a Telegram / WhatsApp link instead of a typed code.
  bool get _useLink => _isReg && _way != null && _way!.isLink(_auth);

  /// Ways shown in the switcher. A Telegram / WhatsApp link the server did not
  /// configure (not in the link session) is hidden.
  List<VerifyWay> get _visibleWays {
    final offered = _link?.methods;
    final auth = _auth;
    return _allWays.where((w) {
      if (_isReg && w.isLink(auth) && offered != null)
        return offered.contains(w.name);
      return true;
    }).toList();
  }

  String get _fullOtp => _controllers.map((c) => c.text).join();

  bool get _isOtpComplete => _fullOtp.length == otpLength;

  String get _timerText {
    final s = _cooldown[_way] ?? 0;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Lifecycle
  // ═══════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _pending = widget.channels.isEmpty ? ['email'] : List.of(widget.channels);
    _phoneChangeCodePending = widget.flow == OtpFlowEnum.phoneChange;
    _allChannels = List.of(_pending);
    _computeWays();

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

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      var ticked = false;
      _cooldown.updateAll((_, v) {
        if (v > 0) ticked = true;
        return v > 0 ? v - 1 : 0;
      });
      if (ticked) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = _auth;
      if (!auth.policyLoaded) {
        await auth
            .loadPolicy(); // opened straight from a deep link / Google: policy not read yet
        if (!mounted) return;
        setState(_computeWays);
      }
      // Telegram has the priority, but only when the student really has it.
      if (_isReg &&
          widget.initialWay == null &&
          _way == VerifyWay.telegram &&
          _allWays.length > 1) {
        _telegramInstalled = await _detectTelegram();
        if (!mounted) return;
        if (_telegramInstalled == false) {
          setState(
            () => _way = _allWays.firstWhere((w) => w != VerifyWay.telegram),
          );
        }
      }
      _prepare();
    });
  }

  /// Builds the list of ways and picks the first one. Registration: the allowed ways of the
  /// pending channels. Reset: the ways the server said a code can reach.
  void _computeWays() {
    final auth = _auth;
    if (_isReg) {
      _allWays = verifyWaysForChannels(auth, _pending);
      if (_allWays.isEmpty) _allWays = const [VerifyWay.email];
      final picked = widget.initialWay;
      _way = (picked != null && _allWays.contains(picked))
          ? picked
          : _allWays.first;
    } else {
      _allWays = [
        for (final r in auth.resetWays)
          if (VerifyWayX.fromName(r.way) != null) VerifyWayX.fromName(r.way)!,
      ];
      if (_allWays.isEmpty) _allWays = const [VerifyWay.email];
      final sentVia = VerifyWayX.fromName(auth.resetSentVia);
      _way = (sentVia != null && _allWays.contains(sentVia))
          ? sentVia
          : _allWays.first;
    }
    _sent
      ..clear()
      ..addAll(
        _way == null ? const [] : [_way!],
      ); // the server already sent / prepared it
  }

  @override
  void dispose() {
    _ticker?.cancel();
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

  // ═══════════════════════════════════════════════════════════════════════
  //  Step preparation / way switching
  // ═══════════════════════════════════════════════════════════════════════

  /// Sets the page up for the selected way: the link flow, or the code boxes
  /// (requesting a code first when this way has not been sent yet).
  void _prepare() {
    _pollTimer?.cancel();
    _link = null;
    _linkError = null;
    final w = _way;
    if (w == null) return;
    if (_useLink) {
      _startLink();
      return;
    }
    _ensureSent(w);
    _cooldown.putIfAbsent(w, () => resendSeconds);
    if (mounted) setState(() {});
    _focusNodes[0].requestFocus();
  }

  /// A phone change (PUT /auth/me) already sent the first code to the new number: the first phone code way
  /// opens as "sent" (a resend now would only answer 429 otp_cooldown).
  bool _phoneChangeCodePending = false;

  /// First time a code way is selected: ask the server to send it.
  Future<void> _ensureSent(VerifyWay w) async {
    if (_sent.contains(w)) return;
    if (_phoneChangeCodePending && w.channel == 'phone') {
      _phoneChangeCodePending = false;
      _sent.add(w);
      _cooldown[w] = resendSeconds;
      return;
    }
    _sent.add(w);
    _cooldown[w] = resendSeconds;
    setState(() => _sending = true);
    final ok = await _auth.resendOtp(
      widget.email,
      reset: !_isReg,
      channel: _isReg ? w.channel : null,
      way: w.name,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) {
      _sent.remove(w); // allow a manual retry right away
      setState(() => _cooldown[w] = 0);
    }
  }

  void _selectWay(VerifyWay w) {
    if (w == _way) return;
    // Telegram <-> WhatsApp share one link session: only the selected way changes.
    final stayOnLink =
        _link != null && w.isLink(_auth) && (_way?.isLink(_auth) ?? false);
    setState(() {
      _way = w;
      _hasError = false;
    });
    if (stayOnLink) return;
    for (final c in _controllers) {
      c.clear();
    }
    _prepare();
  }

  void _clearBoxes() {
    for (final c in _controllers) {
      c.clear();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Code ways
  // ═══════════════════════════════════════════════════════════════════════

  void _onOtpChanged(int index, String value) {
    setState(() => _hasError = false);
    if (value.length > 2) {
      _distribute(
        value,
      ); // the whole code was pasted / auto-filled into one box
      return;
    }
    if (value.length == 2) {
      // typed over a filled box: keep the new digit
      _controllers[index].text = value.substring(1);
      _controllers[index].selection = const TextSelection.collapsed(offset: 1);
    }
    final v = _controllers[index].text;
    if (v.isNotEmpty && index < otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (v.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    if (_isOtpComplete) _onConfirm();
  }

  void _distribute(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    for (var i = 0; i < otpLength; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }
    final next = math.min(digits.length, otpLength - 1);
    _focusNodes[next].requestFocus();
    setState(() {});
    if (_isOtpComplete) _onConfirm();
  }

  KeyEventResult _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _onConfirm() async {
    if (!_isOtpComplete || _isLoading) return;
    setState(() => _isLoading = true);
    final auth = _auth;
    final success = _isReg
        ? await auth.verifyOtp(
            gmail: widget.email,
            code: _fullOtp,
            channel: _channel,
            way: _way?.name,
          )
        : await auth.verifyResetOtp(gmail: widget.email, code: _fullOtp);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      HapticFeedback.mediumImpact();
      _afterVerified(auth);
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _hasError = true);
      _shakeController.forward(from: 0);
      _clearBoxes();
      _focusNodes[0].requestFocus();
      final why = _auth.errorMessage;
      _snack(why == null || why.isEmpty ? 'invalid_otp'.tr : why, error: true);
    }
  }

  Future<void> _onResend() async {
    final w = _way;
    if (w == null || (_cooldown[w] ?? 0) > 0) return;
    _clearBoxes();
    setState(() {
      _hasError = false;
      _cooldown[w] = resendSeconds;
    });
    _focusNodes[0].requestFocus();
    final ok = await _auth.resendOtp(
      widget.email,
      reset: !_isReg,
      channel: _isReg ? w.channel : null,
      way: w.name,
    );
    if (!mounted) return;
    if (ok) {
      _snack('otp_resent'.tr);
    } else {
      setState(() => _cooldown[w] = 0);
      final why = _auth.errorMessage;
      if (why != null && why.isNotEmpty) _snack(why, error: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Link ways (Telegram / WhatsApp)
  // ═══════════════════════════════════════════════════════════════════════

  Future<bool> _detectTelegram() async {
    if (kIsWeb)
      return true; // a browser cannot tell; the t.me link handles both cases
    try {
      // a fixed probe for the Telegram app (tg:// on purpose, nothing from the server): S5 exception
      return await canLaunchUrl(Uri.parse('tg://resolve'));
    } catch (_) {
      return false;
    }
  }

  Future<void> _startLink() async {
    final auth = _auth;
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
      // the selected link way is not offered by the server: fall back to one that is
      final w = _way;
      if (w != null && w.isLink(auth) && !session.methods.contains(w.name)) {
        final fb = _allWays.where(
          (x) => x.isLink(auth) && session.methods.contains(x.name),
        );
        if (fb.isNotEmpty) _way = fb.first;
      }
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollLink());
  }

  Future<void> _pollLink() async {
    final link = _link;
    if (link == null || _polling || !mounted) return;
    final auth = _auth;
    _polling = true;
    final state = await auth.checkPhoneLink(link.token);
    _polling = false;
    if (!mounted) return;
    if (state == 'verified') {
      _pollTimer?.cancel();
      HapticFeedback.mediumImpact();
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
    if (await openExternalLink(uri.toString(), quiet: true)) return;
    if (mounted) _snack('could_not_open_link'.tr, error: true);
  }

  Future<void> _openTelegram(PhoneLinkSession s) async {
    final tg = Uri.tryParse(s.telegramAppUrl ?? '');
    if (!kIsWeb && tg != null && tg.scheme == 'tg') {
      try {
        // the Telegram app's own tg:// link, and nothing but tg:// (the https t.me link below is the fallback): S5 exception
        if (await launchUrl(
          tg,
          mode: LaunchMode.externalApplication,
        )) {
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
    if (mounted) _snack('phone_link_copied'.tr);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Done
  // ═══════════════════════════════════════════════════════════════════════

  /// A channel was verified (by code or by link). More channels pending (the admin requires
  /// E-mail AND phone) -> move on to the next one; otherwise leave the screen.
  void _afterVerified(MyAuthProvider auth) {
    if (widget.flow == OtpFlowEnum.phoneChange) {
      auth.getMe(); // the profile now says phone_verified
      _snack('phone_verified_done'.tr);
      Navigator.of(context).pop();
      return;
    }
    if (_isReg && auth.pendingChannels.isNotEmpty) {
      setState(() {
        _pending = List.of(auth.pendingChannels);
        _hasError = false;
        final left = _allWays
            .where((w) => _pending.contains(w.channel))
            .toList();
        _way = left.isEmpty ? null : (left.contains(_way) ? _way : left.first);
      });
      _snack('verify_step_done'.tr);
      _clearBoxes();
      _prepare();
      return;
    }
    if (_isReg) {
      if (widget.role == 'teacher') {
        // Only teachers have the extra profile step
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AdditionalRegisterScreen(email: widget.email)),
        );
      } else {
        // students AND parents go straight to login, as the only route named /login: the address bar says /login, so
        // a reload lands on the login page and not on the registration (D-1326)
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(settings: const RouteSettings(name: '/login'), builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChangePasswordScreen(
            email: widget.email,
            fromProfile: false,
            code: _fullOtp,
          ),
        ),
      );
    }
  }

  void _snack(String msg, {bool error = false}) => showAppNotice(msg, error: error);

  // ═══════════════════════════════════════════════════════════════════════
  //  UI
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'verification'.tr,
      subtitle: _isReg ? 'auth_verify_sub'.tr : 'auth_reset_code_sub'.tr,
      maxWidth: 480,
      builder: (context, isWide) => FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isReg) ...[
              const ProgressBar(currentStep: 1, totalSteps: 3),
              const SizedBox(height: AppSpace.lg),
            ],
            _content(),
          ],
        ),
      ),
    );
  }

  /// Where the code goes / was sent to, for the selected way.
  String get _destination {
    final w = _way ?? VerifyWay.email;
    final auth = _auth;
    if (!_isReg) {
      for (final r in auth.resetWays) {
        if (r.way == w.name && r.masked != null) return r.masked!;
      }
      return widget.email;
    }
    if (w.isPhone)
      return widget.phoneNumber ?? auth.pendingPhoneMasked ?? widget.email;
    return widget.email;
  }

  /// A reset asked by @username: the server hides every destination (it must not reveal whether the name
  /// exists), so the screen says so instead of showing the typed name as if it were an address.
  bool get _destinationHidden {
    if (_isReg) return false;
    final w = _way ?? VerifyWay.email;
    if (_auth.resetWays.any((r) => r.way == w.name && r.masked != null)) return false;
    // an e-mail or a phone / ID is shown as typed; only a username is hidden (the server's classify)
    return identifierKindOf(widget.email) == IdentifierKind.username;
  }

  /// "We sent a code to the e-mail or phone on the account @name, if it exists."
  String get _hiddenDestinationText {
    var name = widget.email.trim();
    if (name.startsWith('@')) name = name.substring(1);
    return 'reset_code_sent_neutral'.tr.replaceAll('{name}', '${String.fromCharCode(0x200E)}@$name');
  }

  String get _sentHint => switch (_way) {
    VerifyWay.sms => 'verification_code_sent_sms'.tr,
    VerifyWay.whatsapp => 'verification_code_sent_whatsapp'.tr,
    _ => 'verification_code_sent'.tr,
  };

  Widget _content() {
    final way = _way ?? VerifyWay.email;
    final ways = _visibleWays;
    final link = _useLink;
    final showSteps = _isReg && _allChannels.length > 1 && _auth.requireAll;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSteps) ...[
          VerifyStepTracker(
            channels: _allChannels,
            pending: _pending,
            current: _channel,
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        Center(child: VerifyWayHero(way: way)),
        const SizedBox(height: AppSpace.md),
        AnimatedSwitcher(
          duration: AppMotion.of(context).base,
          child: Column(
            key: ValueKey('head-${way.name}-$link'),
            children: [
              Text(
                link ? 'phone_link_title'.tr : 'enter_verification_code'.tr,
                textAlign: TextAlign.center,
                style: AppType.pageTitle(context),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                link ? 'phone_link_hint'.tr : (_destinationHidden ? _hiddenDestinationText : _sentHint),
                textAlign: TextAlign.center,
                style: AppType.body(context).copyWith(height: 1.5),
              ),
              if (!_destinationHidden) ...[
                const SizedBox(height: AppSpace.sm),
                VerifyDestinationChip(way: way, text: _destination),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        if (ways.length > 1) ...[
          VerifyWaySwitcher(
            ways: ways,
            selected: _way,
            verified: {
              for (final w in _allWays)
                if (_isReg && !_pending.contains(w.channel)) w,
            },
            onChanged: _selectWay,
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        AnimatedSize(
          duration: AppMotion.of(context).slow,
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: AppMotion.of(context).slow,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey('panel-${way.name}-$link'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: link ? _buildLinkSection() : _buildCodeSection(),
            ),
          ),
        ),

        const SizedBox(height: AppSpace.lg),
        Text(
          'verify_try_another_way'.tr,
          textAlign: TextAlign.center,
          style: AppType.meta(context),
        ),
      ],
    );
  }

  // ── code ways ────────────────────────────────────────────────────────────

  List<Widget> _buildCodeSection() => [
    AnimatedSize(
      duration: AppMotion.of(context).base,
      child: _sending
          ? Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: VerifyWayStatusPill(
                way: _way ?? VerifyWay.email,
                label: 'verify_sending'.tr,
              ),
            )
          : const SizedBox(width: double.infinity),
    ),
    _buildOtpFields(),
    const SizedBox(height: AppSpace.md),
    _buildResendRow(),
    const SizedBox(height: AppSpace.lg),
    AuthButton(
      loading: _isLoading,
      label: 'confirm'.tr,
      enabled: _isOtpComplete && !_isLoading,
      icon: Icons.verified_rounded,
      iconBefore: true,
      onPressed: _onConfirm,
    ),
  ];

  Widget _buildOtpFields() {
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final t = _shakeController.value;
        final dx = math.sin(t * math.pi * 6) * 10 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Semantics(
        label: 'enter_verification_code'.tr,
        child: Directionality(
          textDirection: TextDirection.ltr,
          // On a phone the row reaches 4 px into the page gutter and the gaps shrink before the boxes do, so
          // every field keeps a 48 px tap target inside its border (Android guideline; test/ui/a11y_guidelines_test.dart).
          child: LayoutBuilder(
            builder: (context, outer) {
              final width = math.min(380.0, outer.maxWidth + AppSpace.xs);
              final slot = width / otpLength;
              final gap = ((slot - 52) / 2).clamp(1.0, 4.0);
              return SizedBox(
                height: 58,                                // = the boxes' height (AuthOtpBox height: 58 below)
                child: OverflowBox(
                  minWidth: width,
                  maxWidth: width,
                  child: Row(
                    children: List.generate(otpLength, (i) => _buildSingleBox(i, gap)),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSingleBox(int index, double gap) {
    final c = context.colors;
    final digit = AuthOtpBox.digitStyle(context);
    return Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: gap),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            _focusNodes[index],
            _controllers[index],
          ]),
          builder: (context, _) => AuthOtpBox(
            focused: _focusNodes[index].hasFocus,
            filled: _controllers[index].text.isNotEmpty,
            error: _hasError,
            height: 58,
            child: Focus(
              onKeyEvent: (_, e) => _onKeyEvent(index, e),
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                // the field fills the box: text + cursor vertically centered
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.number,
                textInputAction: index == otpLength - 1 ? TextInputAction.done : TextInputAction.next,
                autofillHints: index == 0
                    ? const [AutofillHints.oneTimeCode]
                    : null,
                style: digit,
                // same line box for every font / digit
                strutStyle: const StrutStyle(fontSize: 28, height: 1.0, forceStrutHeight: true),
                cursorColor: c.primary,
                cursorHeight: 32,
                cursorWidth: 2,
                decoration: const InputDecoration(
                  isDense: true,
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  if (value.isNotEmpty) HapticFeedback.selectionClick();
                  _onOtpChanged(index, value);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResendRow() {
    final c = context.colors;
    final w = _way;
    final left = _cooldown[w] ?? 0;
    final canResend = left == 0;
    final ink = appInk(context, c.primary);
    return Center(
      child: AnimatedSwitcher(
        duration: AppMotion.of(context).base,
        child: canResend
            ? TextButton.icon(
                key: const ValueKey('resend'),
                onPressed: _onResend,
                style: TextButton.styleFrom(
                  minimumSize: const Size(AppTouch.min, AppTouch.min),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  backgroundColor: c.primaryTint,
                  foregroundColor: ink,
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
                ),
                icon: Icon(Icons.refresh_rounded, size: AppIconSize.md, color: ink),
                label: Text('resend'.tr, style: AppType.bodyStrong(context).copyWith(color: ink)),
              )
            : Container(
                key: const ValueKey('timer'),
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                decoration: BoxDecoration(
                  color: c.inputBg,
                  borderRadius: AppRadius.controlAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: AppIconSize.md,
                      height: AppIconSize.md,
                      child: CircularProgressIndicator(
                        value: left / resendSeconds,
                        strokeWidth: 2.4,
                        color: (w ?? VerifyWay.email).brand,
                        backgroundColor: c.divider,
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Flexible(
                      child: Text(
                        'resend_in'.tr + _timerText,
                        style: AppType.label(context)
                            .copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ── link ways ────────────────────────────────────────────────────────────

  /// The Telegram / WhatsApp step for the selected way. The other way (when the admin
  /// allows both) is one tap away in the switcher.
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
              style: TextStyle(
                color: context.colors.danger,
                fontWeight: FontWeight.w600,
              ),
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
          Text(
            'generic_error'.tr,
            textAlign: TextAlign.center,
            style: context.colors.body,
          ),
        ];
      }
      method = s.methods.first;
    }
    final way = method == 'telegram' ? VerifyWay.telegram : VerifyWay.whatsapp;
    return [
      VerifyWayButton(
        way: way,
        label:
            (way == VerifyWay.telegram
                    ? 'phone_link_telegram'
                    : 'phone_link_whatsapp')
                .tr,
        onPressed: () =>
            way == VerifyWay.telegram ? _openTelegram(s) : _openWhatsapp(s),
      ),
      if (kIsWeb) ..._buildQrSection(s, way),
      const SizedBox(height: 20),
      Text(
        (way == VerifyWay.telegram
                ? 'phone_link_tg_steps'
                : 'phone_link_wa_steps')
            .tr,
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
            color: context.colors.onHero,
            // QR codes need a light background, also in dark mode
            borderRadius: BorderRadius.circular(c.radiusMedium),
            border: Border.all(
              color: way.brand.withValues(alpha: 0.45),
              width: 2,
            ),
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
            backgroundColor: context.colors.onHero,
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
}
