import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:moyasar/moyasar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../shared/payment/saved_methods_provider.dart';
import '../../shared/payment/saved_payment_models.dart';
import '../../student/models.dart';
import 'enrollment_screen.dart';

import 'checkout_web_impl.dart'
if (dart.library.io) 'checkout_stub_impl.dart';

// webview_flutter is imported only on mobile. On web the stub file above
// provides dummy classes so this import is tree-shaken away.
import 'package:webview_flutter/webview_flutter.dart'
if (dart.library.html) 'webview_stub.dart';

// ─────────────────────────────────────────────────────────────────────────────

enum EnrollStep {
  method,
  stcMobile,
  stcOtp,
  bankDetails,
  verifying,
  success,
  failed,
}

enum _Selection { savedCard, bankTransfer, stcPay, newCard }

// ─────────────────────────────────────────────────────────────────────────────

class EnrollmentProvider extends BaseProvider {
  final ApiClient _api;
  final CourseModel course;

  static const String _publishableKey = String.fromEnvironment(
    'MOYASAR_PUBLISHABLE_KEY',
    defaultValue: 'pk_test_Ut6582RweTo7JgUEuVYBYrQv4v3RAMW7VRW3Umw5',
  );

  EnrollmentProvider(this.course, {ApiClient? api}) : _api = api ?? ApiClient();

  EnrollStep _step = EnrollStep.method;
  _Selection _selection = _Selection.newCard;

  SavedPaymentMethod? _selectedCard;
  Map<String, dynamic>? _bankInfo;
  bool _paidViaBankTransfer = false;
  int? _pendingPaymentId;
  String? _pendingTransactionId;
  String? _failureReason;
  String? _stcOtpError;
  String? _stcTransactionUrl;

  EnrollStep get step => _step;
  Map<String, dynamic>? get bankInfo => _bankInfo;
  bool get paidViaBankTransfer => _paidViaBankTransfer;
  bool get isFree => course.price == 0;
  String? get failureReason => _failureReason;
  String? get stcOtpError => _stcOtpError;

  // ── Selection ─────────────────────────────────────────────────────────────

  void selectSavedCard(SavedPaymentMethod card) {
    _selection = _Selection.savedCard;
    _selectedCard = card;
    notifyListeners();
  }

  void selectBankTransfer() {
    _selection = _Selection.bankTransfer;
    _selectedCard = null;
    notifyListeners();
  }

  void selectStcPay() {
    _selection = _Selection.stcPay;
    _selectedCard = null;
    notifyListeners();
  }

  void selectNewCard() {
    _selection = _Selection.newCard;
    _selectedCard = null;
    notifyListeners();
  }

  FeeBreakdown computedFees(SavedMethodsProvider savedP) =>
      FeeBreakdown.calculate(
        coursePrice: course.price,
        brand: _selection == _Selection.stcPay
            ? CardBrand.stcPay
            : _selectedCard?.cardBrand ?? CardBrand.mada,
      );

  // ── Confirm ───────────────────────────────────────────────────────────────

  Future<void> confirm(SavedMethodsProvider savedP, BuildContext context) async {
    if (isFree) {
      await _enrollFree();
      return;
    }
    switch (_selection) {
      case _Selection.newCard:
        await _openMoyasarCardScreen(context);
      case _Selection.savedCard:
        if (_selectedCard != null) await _chargeWithSavedCard(_selectedCard!);
      case _Selection.bankTransfer:
        await _initBankTransfer();
      case _Selection.stcPay:
        _step = EnrollStep.stcMobile;
        notifyListeners();
    }
  }

  // ── Free enroll ───────────────────────────────────────────────────────────

  Future<void> _enrollFree() async {
    final r = await run(() => _api.post('/api/v1/courses/${course.id}/enroll'));
    if (r != null) {
      _step = EnrollStep.success;
      notifyListeners();
    }
  }

  // ── New card entry point ──────────────────────────────────────────────────

  Future<void> _openMoyasarCardScreen(BuildContext context) async {
    if (kIsWeb) {
      await _openWebCheckout(context);
      return;
    }
    // Mobile: Moyasar SDK handles card form + 3DS internally.
    final fees = FeeBreakdown.calculate(
      coursePrice: course.price,
      brand: CardBrand.mada,
    );
    final config = PaymentConfig(
      publishableApiKey: _publishableKey,
      amount: (fees.total * 100).round(),
      description: 'كورس: ${course.name}',
      metadata: {'course_id': course.id.toString()},
      creditCard: CreditCardConfig(saveCard: false, manual: false),
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MoyasarCardPaymentScreen(
          config: config,
          onPaymentResult: (result) {
            Navigator.of(context).pop();
            _handleSdkResult(result, context);
          },
        ),
      ),
    );
  }

  // ── Web checkout (Flutter Web) ────────────────────────────────────────────

  Future<void> _openWebCheckout(BuildContext context) async {
    makeLoading();
    notifyListeners();

    try {
      final session = await run(() => _api.post(
        '/api/v1/payments/create-web-session',
        body: {'course_id': course.id},
      ));

      if (session is! Map<String, dynamic>) {
        _failureReason = 'فشل إنشاء جلسة الدفع. حاول مرة أخرى.';
        _step = EnrollStep.failed;
        notifyListeners();
        return;
      }

      if (session['already_paid'] == true) {
        _step = EnrollStep.success;
        notifyListeners();
        return;
      }

      final checkoutUrl = session['checkout_url'] as String?;
      final token = session['session_token'] as String?;

      final resolvedUrl = checkoutUrl?.isNotEmpty == true
          ? checkoutUrl!
          : (token != null && token.isNotEmpty)
          ? '${AppConfig.baseUrl}/checkout?token=$token'
          : null;

      if (resolvedUrl == null) {
        _failureReason = 'بيانات الجلسة غير مكتملة. حاول مرة أخرى.';
        _step = EnrollStep.failed;
        notifyListeners();
        return;
      }

      stopLoading();
      notifyListeners();

      if (!context.mounted) return;

      // Push the platform-appropriate checkout page.
      // On web  → _IFrameCheckoutPage (from checkout_web_impl.dart)
      // On mobile → _MobileCheckoutPage (defined below in this file)
      final Widget checkoutPage = kIsWeb
          ? IFrameCheckoutPage(url: resolvedUrl) // web impl via conditional import
          : MobileCheckoutPage(url: resolvedUrl);

      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => checkoutPage,
        ),
      );

      _handleWebCallbackStatus(result ?? 'failed');
    } catch (e) {
      _failureReason = 'تعذّر فتح صفحة الدفع: $e';
      _step = EnrollStep.failed;
      notifyListeners();
    } finally {
      stopLoading();
    }
  }

  void _handleWebCallbackStatus(String status) {
    switch (status) {
      case 'paid':
        _step = EnrollStep.success;
      case 'initiated':
        _failureReason = 'الدفع قيد التأكيد. سيُفعَّل كورسك خلال دقائق.';
        _step = EnrollStep.failed;
      default:
        _failureReason = 'فشلت عملية الدفع. حاول مرة أخرى.';
        _step = EnrollStep.failed;
    }
    notifyListeners();
  }

  // ── Handle Moyasar SDK result (mobile) ────────────────────────────────────

  void _handleSdkResult(dynamic result, BuildContext context) {
    if (result is! PaymentResponse) {
      _failureReason = 'استجابة غير متوقعة من بوابة الدفع';
      _step = EnrollStep.failed;
      notifyListeners();
      return;
    }
    final statusName = result.status.name.toLowerCase();
    if (statusName == 'paid' ||
        statusName == 'authorized' ||
        statusName == 'captured') {
      _recordSdkPayment(result.id);
    } else if (statusName == 'failed') {
      _failureReason =
          (result.source as dynamic)?.message as String? ??
              'فشلت عملية الدفع. حاول مرة أخرى.';
      _step = EnrollStep.failed;
      notifyListeners();
    } else {
      _failureReason = 'الدفع قيد المعالجة. سيُفعَّل كورسك تلقائياً قريباً.';
      _step = EnrollStep.failed;
      notifyListeners();
    }
  }

  Future<void> _recordSdkPayment(String moyasarPaymentId) async {
    _step = EnrollStep.verifying;
    notifyListeners();

    final r = await run(() => _api.post(
      '/api/v1/payments/record-sdk-payment',
      body: {
        'course_id': course.id,
        'moyasar_payment_id': moyasarPaymentId,
      },
    ));

    final status = (r is Map ? r['status'] as String? : null) ?? '';
    if (status == 'completed' || status == 'paid') {
      _step = EnrollStep.success;
    } else {
      _failureReason = 'تم الدفع. سيُفعَّل كورسك خلال دقائق.';
      _step = EnrollStep.failed;
    }
    notifyListeners();
  }

  // ── Saved card ────────────────────────────────────────────────────────────

  Future<void> _chargeWithSavedCard(SavedPaymentMethod card) async {
    final r = await run(() => _api.post('/api/v1/payments', queryParams: {
      'course_id': course.id,
      'payment_method': card.cardBrand?.apiKey ?? 'mada',
      'saved_method_id': card.id,
    }));
    if (r is! Map<String, dynamic>) return;

    _pendingPaymentId = (r['payment_id'] as num?)?.toInt();
    _pendingTransactionId = r['transaction_id'] as String?;

    if (r['status'] == 'completed') {
      _step = EnrollStep.success;
      notifyListeners();
      return;
    }

    final txUrl = r['transaction_url'] as String?;
    if (txUrl != null && txUrl.isNotEmpty) {
      final uri = Uri.parse(txUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }

    await _verifyAfterReturn();
  }

  // ── STC Pay ───────────────────────────────────────────────────────────────

  Future<void> initStcPay(String mobile, BuildContext context) async {
    final fees = FeeBreakdown.calculate(
      coursePrice: course.price,
      brand: CardBrand.stcPay,
    );
    final config = PaymentConfig(
      publishableApiKey: _publishableKey,
      amount: (fees.total * 100).round(),
      description: 'كورس: ${course.name}',
    );

    makeLoading();
    try {
      final result = await Moyasar.pay(
        apiKey: _publishableKey,
        paymentRequest: PaymentRequest(config, StcRequestSource(mobile: mobile)),
      );

      if (result is PaymentResponse) {
        if (result.status == PaymentStatus.initiated) {
          _stcTransactionUrl =
          (result.source as dynamic)?.transactionUrl as String?;
          _step = EnrollStep.stcOtp;
        } else if (result.status == PaymentStatus.paid) {
          await _recordSdkPayment(result.id);
          return;
        } else {
          _failureReason = 'فشل بدء عملية STC Pay';
          _step = EnrollStep.failed;
        }
      } else {
        _failureReason = 'فشل الاتصال ببوابة الدفع';
        _step = EnrollStep.failed;
      }
    } catch (e) {
      _failureReason = 'خطأ: $e';
      _step = EnrollStep.failed;
    } finally {
      stopLoading();
      notifyListeners();
    }
  }

  Future<void> submitStcOtp(String otp) async {
    if (_stcTransactionUrl == null) {
      _stcOtpError = 'انتهت الجلسة. ابدأ من جديد.';
      notifyListeners();
      return;
    }
    _stcOtpError = null;
    makeLoading();
    notifyListeners();

    try {
      final result = await Moyasar.verifyOTP(
        transactionURL: _stcTransactionUrl!,
        otpRequest: OtpRequestSource(otpValue: otp),
      );
      if (result is PaymentResponse && result.status == PaymentStatus.paid) {
        await _recordSdkPayment(result.id);
      } else {
        _stcOtpError = 'رمز التحقق غير صحيح أو انتهت صلاحيته';
        notifyListeners();
      }
    } catch (e) {
      _stcOtpError = 'خطأ: $e';
      notifyListeners();
    } finally {
      stopLoading();
    }
  }

  // ── Bank transfer ─────────────────────────────────────────────────────────

  Future<void> _initBankTransfer() async {
    final r = await run(() => _api.post(
      '/api/v1/payments/bank-transfer',
      queryParams: {'course_id': course.id},
    ));
    if (r is Map<String, dynamic>) {
      _bankInfo = r;
      _step = EnrollStep.bankDetails;
      notifyListeners();
    }
  }

  void confirmBankTransfer() {
    _paidViaBankTransfer = true;
    _step = EnrollStep.success;
    notifyListeners();
  }

  void backToMethod() {
    _step = EnrollStep.method;
    _bankInfo = null;
    notifyListeners();
  }

  // ── Verify after 3DS return ───────────────────────────────────────────────

  Future<void> _verifyAfterReturn() async {
    if (_pendingPaymentId == null) {
      _failureReason = 'لم يتم العثور على بيانات الدفع.';
      _step = EnrollStep.failed;
      notifyListeners();
      return;
    }
    _step = EnrollStep.verifying;
    notifyListeners();

    final r = await run(() => _api.post(
      '/api/v1/payments/$_pendingPaymentId/verify',
      queryParams: _pendingTransactionId != null
          ? {'transaction_id': _pendingTransactionId}
          : {},
    ));

    final status = (r is Map ? r['status'] as String? : null) ?? '';
    if (status == 'completed' || status == 'paid') {
      _step = EnrollStep.success;
    } else if (status == 'failed') {
      _failureReason = 'فشلت عملية الدفع. جرّب طريقة دفع أخرى.';
      _step = EnrollStep.failed;
    } else {
      _failureReason = 'الدفع قيد المعالجة. سيُفعَّل كورسك خلال دقائق.';
      _step = EnrollStep.failed;
    }
    notifyListeners();
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  void retryFromStart() {
    _step = EnrollStep.method;
    _failureReason = null;
    _stcOtpError = null;
    _stcTransactionUrl = null;
    _pendingPaymentId = null;
    _pendingTransactionId = null;
    notifyListeners();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _MobileCheckoutPage  — iOS / Android only
//
// Uses webview_flutter's WebViewController which fully supports
// setJavaScriptMode and onNavigationRequest on native platforms.
// ═════════════════════════════════════════════════════════════════════════════

class MobileCheckoutPage extends StatefulWidget {
  final String url;
  const MobileCheckoutPage({super.key, required this.url});

  @override
  State<MobileCheckoutPage> createState() => _MobileCheckoutPageState();
}

class _MobileCheckoutPageState extends State<MobileCheckoutPage> {
  late final WebViewController _controller;
  bool _loading = true;

  // result.html redirects to APP_URL/#/payment/callback?status=paid
  static const String _callbackMarker = '/payment/callback';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // fine on iOS/Android
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onNavigationRequest: (req) {
          if (req.url.contains(_callbackMarker)) {
            final uri = Uri.parse(req.url);
            // Handle hash-style URL:  /#/payment/callback?status=paid
            final fragment = uri.fragment; // "payment/callback?status=paid"
            String status = 'failed';
            if (fragment.contains('status=')) {
              final q = Uri.parse('?${fragment.split('?').last}');
              status = q.queryParameters['status'] ?? 'failed';
            } else {
              status = uri.queryParameters['status'] ?? 'failed';
            }
            Navigator.of(context).pop(status);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onWebResourceError: (e) =>
            debugPrint('WebView resource error: ${e.description}'),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إتمام الدفع'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'إلغاء',
          onPressed: () => Navigator.of(context).pop('cancelled'),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('جارٍ تحميل صفحة الدفع…'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}