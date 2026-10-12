/// payment_callback_page.dart — FIXED
///
/// Loaded when Flutter Web's router matches /#/payment/callback
/// after the backend 302-redirects from /api/v1/payments/web-callback.
///
/// URL format produced by backend:
///   ✅  https://yourapp.com/#/payment/callback?status=paid&course_id=42
///   ❌  https://yourapp.com/#/payment/callback?status=failed&message=amount_mismatch
///   ⏳  https://yourapp.com/#/payment/callback?status=initiated&course_id=42
///
/// FIXES vs original:
/// ──────────────────
/// FIX 1 (CRITICAL): Uri.base.fragment on Flutter Web is the hash AFTER '#',
///   e.g. fragment = '/payment/callback?status=paid&course_id=42'
///   The '?' query string is INSIDE the fragment, not in Uri.base.query.
///   The original code tried Uri.base.queryParameters which is always empty
///   for hash-routed Flutter Web apps. Fixed: parse fragment manually.
///
/// FIX 2: _readParams was called in initState before the widget tree was
///   mounted, so ModalRoute.of(context) returned null.
///   Fixed: wrapped in addPostFrameCallback.
///
/// FIX 3: "Try Again" used Navigator.pop() which has no enrollment screen
///   in the stack (this page is reached via full browser redirect, not push).
///   Fixed: navigates to home.
///
/// Register in GoRouter:
///   GoRoute(
///     path: '/payment/callback',
///     builder: (_, __) => const PaymentCallbackPage(),
///   )
///
/// Register in Navigator routes:
///   '/payment/callback': (_) => const PaymentCallbackPage()
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

import '../../../utils/widget/base_page.dart';

class PaymentCallbackPage extends StatefulWidget {
  const PaymentCallbackPage({super.key});

  @override
  State<PaymentCallbackPage> createState() => _PaymentCallbackPageState();
}

class _PaymentCallbackPageState extends State<PaymentCallbackPage>
    with SingleTickerProviderStateMixin {
  _CbState _cbState = _CbState.failed;
  String _title = '';
  String _message = '';
  int? _courseId;

  late AnimationController _ctrl;
  late Animation<double> _scale;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);

    // FIX 2: use addPostFrameCallback so widget tree (and ModalRoute) is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readParams();
      _ctrl.forward();
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _readParams() {
    // FIX 1: On Flutter Web with hash routing, Uri.base looks like:
    //   https://yourapp.com/#/payment/callback?status=paid&course_id=42
    //
    // Uri.base.queryParameters → always {} (query is inside the fragment)
    // Uri.base.fragment        → '/payment/callback?status=paid&course_id=42'
    //
    // We must parse the fragment to get the query string.
    Map<String, String> params = {};

    // Try fragment-based params first (Flutter Web hash routing)
    final fragment =
        Uri.base.fragment; // e.g. '/payment/callback?status=paid&...'
    final qIdx = fragment.indexOf('?');
    if (qIdx != -1) {
      params = Uri.splitQueryString(fragment.substring(qIdx + 1));
    }

    // Fallback: GoRouter may pass params as route arguments
    if (params.isEmpty) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        params = args.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    }

    // Fallback: try Uri.base.queryParameters (non-hash routing)
    if (params.isEmpty && Uri.base.queryParameters.isNotEmpty) {
      params = Uri.base.queryParameters;
    }

    final status = params['status'] ?? 'failed';
    final message = params['message'];
    _courseId = int.tryParse(params['course_id'] ?? '');

    switch (status) {
      case 'paid':
        _cbState = _CbState.success;
        _title = 'payment_success_title'.tr;
        _message = 'payment_success_message'.tr;
      case 'initiated':
        _cbState = _CbState.pending;
        _title = 'payment_pending_title'.tr;
        _message = 'payment_pending_message'.tr;
      default:
        _cbState = _CbState.failed;
        _title = 'payment_failed_title'.tr;
        _message =
            _humanMessage(message) ?? 'payment_failed_message_generic'.tr;
    }
  }

  String? _humanMessage(String? raw) => switch (raw) {
    'session_not_found' => 'payment_error_session_expired'.tr,
    'amount_mismatch' => 'payment_error_amount_mismatch'.tr,
    'no_payment_id' => 'payment_error_no_payment_id'.tr,
    null => null,
    _ => raw,
  };

  void _goHome() {
    Navigator.of(context).pushReplacementNamed('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _title.isEmpty) {
      return const BasePage(
          useWebCard: true,
          child:Center(child: AppLoadingIndicator()));
    }

    final c = context.colors;
    final (Color c1, Color c2, IconData icon) = switch (_cbState) {
      _CbState.success => (
      c.success,
      const Color(0xFF2ECC71),
      Icons.check_rounded,
      ),
      _CbState.pending => (
      c.accent,
      const Color(0xFFF39C12),
      Icons.hourglass_top_rounded,
      ),
      _CbState.failed => (
      c.danger,
      const Color(0xFFE74C3C),
      Icons.error_outline_rounded,
      ),
    };

    return BasePage(
      key: const ValueKey('payment_callback'),
      useWebCard: true,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ScaleTransition(
                    scale: _scale,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [c1, c2],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: c1.withValues(alpha: .4),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 60),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  _title,
                  style: c.h1.copyWith(fontSize: 24),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _message,
                  style: c.body.copyWith(height: 1.8),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 44),

                _GradBtn(
                  label: _cbState == _CbState.success
                      ? 'start_learning_now'.tr
                      : 'back_to_home'.tr,
                  c1: c1,
                  c2: c2,
                  onTap: _goHome,
                ),

                // FIX 3: "Try Again" goes home (not pop) — no enrollment
                // screen in the stack after a full browser redirect.
                if (_cbState == _CbState.failed) ...[
                  const SizedBox(height: 14),
                  ParentComponent(
                      featureKey: 'payment_callback.try_again',
                      child: OutlinedButton(
                        onPressed: _goHome,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          side: BorderSide(color: c.divider),
                        ),
                        child: Text(
                          'try_again_payment'.tr,
                          style: c.label.copyWith(color: c.textMedium),
                        ),
                      )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _CbState { success, pending, failed }

class _GradBtn extends StatelessWidget {
  final String label;
  final Color c1, c2;
  final VoidCallback onTap;

  const _GradBtn({
    required this.label,
    required this.c1,
    required this.c2,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c1, c2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: c1.withValues(alpha: .4),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
            fontFamily: 'bahji',
          ),
        ),
      ),
    ),
  );
}