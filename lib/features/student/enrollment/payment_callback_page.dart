/// payment_callback_page.dart — FINAL
///
/// Flutter Web only. Moyasar hosted checkout redirects here after payment.
///
/// Moyasar appends these query params to your callback_url:
///   ?id=pay_xxx          ← moyasar payment ID
///   &status=paid         ← paid | failed | initiated
///   &message=...         ← optional human-readable message
///
/// You must also pass course_id yourself inside the callback_url you build:
///   callback_url=https://yourapp.com/payment/callback?course_id=42
/// Moyasar appends its params alongside yours.
///
/// Register in your router:
///   GoRouter:  GoRoute(path: '/payment/callback', builder: (_, __) => const PaymentCallbackPage())
///   Navigator: routes: { '/payment/callback': (_) => const PaymentCallbackPage() }
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../config/app_theme.dart';

class PaymentCallbackPage extends StatefulWidget {
  const PaymentCallbackPage({super.key});

  @override
  State<PaymentCallbackPage> createState() => _PaymentCallbackPageState();
}

class _PaymentCallbackPageState extends State<PaymentCallbackPage>
    with SingleTickerProviderStateMixin {
  _CallbackState _state = _CallbackState.loading;
  String _message = 'جارٍ التحقق من الدفع...';
  bool _isSoftFail = false;

  late AnimationController _iconCtrl;
  late Animation<double> _iconScale;

  @override
  void initState() {
    super.initState();
    _iconCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _iconScale =
        CurvedAnimation(parent: _iconCtrl, curve: Curves.elasticOut);
    _handleCallback();
  }

  @override
  void dispose() {
    _iconCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleCallback() async {
    // Uri.base is only available on Flutter Web
    if (!kIsWeb) {
      _setResult(false, 'هذه الصفحة مخصصة لمتصفح الويب فقط.');
      return;
    }

    final uri = Uri.base;
    final moyasarId = uri.queryParameters['id'];
    final status = uri.queryParameters['status'] ?? '';
    final moyasarMessage = uri.queryParameters['message'];
    final courseIdStr = uri.queryParameters['course_id'];

    // Validate required params
    if (moyasarId == null || moyasarId.isEmpty) {
      _setResult(false, 'بيانات الدفع غير مكتملة. الرجاء المحاولة مرة أخرى.');
      return;
    }
    if (courseIdStr == null) {
      _setResult(false, 'معرّف الكورس مفقود. الرجاء العودة وإعادة المحاولة.');
      return;
    }
    final courseId = int.tryParse(courseIdStr);
    if (courseId == null) {
      _setResult(false, 'معرّف الكورس غير صحيح.');
      return;
    }

    // Check status from Moyasar
    if (status == 'failed') {
      _setResult(
        false,
        moyasarMessage?.isNotEmpty == true
            ? moyasarMessage!
            : 'فشلت عملية الدفع. جرّب مرة أخرى.',
      );
      return;
    }
    if (status != 'paid') {
      // initiated or unknown
      _isSoftFail = true;
      _setResult(
        false,
        'الدفع قيد المعالجة. سيُفعَّل كورسك تلقائياً خلال دقائق.',
      );
      return;
    }

    // status == 'paid' — record on our backend to activate enrollment
    try {
      final api = ApiClient();
      final r = await api.post(
        '/api/v1/payments/record-sdk-payment',
        body: {
          'course_id': courseId,
          'moyasar_payment_id': moyasarId,
        },
      );

      final respStatus =
          (r is Map ? r['status'] as String? : null) ?? '';
      final ok = respStatus == 'completed' || respStatus == 'paid';

      if (ok) {
        _setResult(true, 'تم تفعيل الكورس بنجاح! يمكنك البدء الآن. 🎉');
      } else {
        _isSoftFail = true;
        _setResult(
            false, 'تم الدفع. سيُفعَّل كورسك خلال دقائق تلقائياً.');
      }
    } catch (e) {
      _isSoftFail = true;
      _setResult(
          false, 'تم الدفع لكن حدث خطأ في التحقق. تواصل مع الدعم إذا لم يُفعَّل كورسك.');
    }
  }

  void _setResult(bool success, String msg) {
    if (!mounted) return;
    setState(() {
      _state = success ? _CallbackState.success : _CallbackState.failed;
      _message = msg;
    });
    _iconCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Icon ────────────────────────────────────────────────
                  if (_state == _CallbackState.loading)
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                          color: c.primary, strokeWidth: 3),
                    )
                  else
                    ScaleTransition(
                      scale: _iconScale,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: _state == _CallbackState.success
                                ? [c.success, const Color(0xFF2ECC71)]
                                : _isSoftFail
                                    ? [c.accent, const Color(0xFFF39C12)]
                                    : [c.danger, const Color(0xFFE74C3C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_state == _CallbackState.success
                                      ? c.success
                                      : _isSoftFail
                                          ? c.accent
                                          : c.danger)
                                  .withValues(alpha: .35),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          _state == _CallbackState.success
                              ? Icons.check_rounded
                              : _isSoftFail
                                  ? Icons.hourglass_top_rounded
                                  : Icons.error_outline_rounded,
                          color: Colors.white,
                          size: 54,
                        ),
                      ),
                    ),

                  const SizedBox(height: 28),

                  // ── Title ────────────────────────────────────────────────
                  Text(
                    _state == _CallbackState.loading
                        ? 'جارٍ التحقق...'
                        : _state == _CallbackState.success
                            ? 'تم الدفع بنجاح! 🎉'
                            : _isSoftFail
                                ? 'الدفع قيد المعالجة'
                                : 'فشلت عملية الدفع',
                    style: c.h1.copyWith(fontSize: 24),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  // ── Message ──────────────────────────────────────────────
                  Text(
                    _message,
                    style: c.body.copyWith(height: 1.7),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // ── Action buttons ───────────────────────────────────────
                  if (_state != _CallbackState.loading) ...[
                    SizedBox(
                      width: double.infinity,
                      child: _GradientBtn(
                        label: _state == _CallbackState.success
                            ? 'ابدأ التعلم الآن'
                            : 'العودة للرئيسية',
                        colors: _state == _CallbackState.success
                            ? [c.success, const Color(0xFF2ECC71)]
                            : [c.primary, c.primary],
                        onTap: () =>
                            Navigator.of(context).pushReplacementNamed('/'),
                      ),
                    ),
                    if (_state == _CallbackState.failed && !_isSoftFail) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                            side: BorderSide(color: c.divider),
                          ),
                          child: Text('حاول مرة أخرى',
                              style: c.label
                                  .copyWith(color: c.textMedium)),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _CallbackState { loading, success, failed }

// ── Shared gradient button ────────────────────────────────────────────────────

class _GradientBtn extends StatelessWidget {
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;
  const _GradientBtn(
      {required this.label, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
                color: colors.first.withValues(alpha: .35),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  fontFamily: 'Cairo')),
        ),
      ),
    );
  }
}
