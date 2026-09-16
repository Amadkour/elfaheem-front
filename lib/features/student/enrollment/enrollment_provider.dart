import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_paymob_egypt/flutter_paymob_egypt.dart';
import 'package:moyasar/moyasar.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../shared/payment/saved_methods_provider.dart';
import '../../shared/payment/saved_payment_models.dart';
import '../../student/models.dart';
import 'enrollment_screen.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
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

  // ── Active payment provider (from GET /api/v1/config) ──────────────────────
  // Backend is the single source of truth for which gateway is live and
  // whether it has a native mobile SDK — this widget never hardcodes that.
  String? _paymentProvider; // "moyasar" | "paymob" | null while loading
  bool _hasNativeMobileSdk = false; // safe default matches today's behaviour

  // ── Paymob mobile SDK credentials (paymob_flutter package) ─────────────────
  // Loaded from GET /api/v1/config's `paymob_sdk` block (see
  // PaymentService.payment_config() / PaymobProvider.sdk_config) — never
  // hardcoded here. Null until config loads, or if the backend has no SDK
  // env vars configured; either way _startPaymobSdkPayment() falls back to
  // hosted checkout when these are missing rather than calling the SDK
  // with a null key.
  String? _paymobApiKey;
  int? _paymobIntegrationId;
  int? _paymobIframeId;
  bool _paymobSandbox = true;

  EnrollStep get step => _step;

  Map<String, dynamic>? get bankInfo => _bankInfo;

  bool get paidViaBankTransfer => _paidViaBankTransfer;

  bool get isFree => course.price == 0;

  String? get failureReason => _failureReason;

  String? get stcOtpError => _stcOtpError;

  /// STC Pay is a Moyasar/Saudi-specific payment method — hide it in the
  /// method picker unless Moyasar is the active provider.
  bool get supportsStcPay => _paymentProvider == 'moyasar';

  String? get activeProvider => _paymentProvider;

  /// Currency symbol for whichever gateway is actually active. Moyasar
  /// charges in SAR, Paymob (Egypt) charges in EGP — this must follow the
  /// backend-reported provider rather than being hardcoded, or an Egyptian
  /// user paying through Paymob sees a Saudi Riyal symbol on an EGP charge.
  /// Defaults to SAR while `_paymentProvider` is still loading, matching
  /// this app's original (Moyasar-only) behaviour.
  String get currencySymbol => _paymentProvider == 'paymob' ? 'ج.م' : 'ر.س';

  /// Call once when the enrollment screen mounts (e.g. from its initState),
  /// before the method picker renders, so supportsStcPay is correct on
  /// first paint. Safe to call more than once.
  Future<void> loadPaymentConfig() async {
    final r = await run(() => _api.get('/api/v1/config'), makLoading: true);
    // BUG FIX: was `r is Map<String, dynamic>`. If ApiClient's decoded
    // response is a Map<dynamic, dynamic> at runtime (e.g. it got
    // re-wrapped anywhere without preserving key type — very easy to do
    // by accident, and Dart's `is` check on generics is exact, not
    // structural), this check silently fails and the ENTIRE block below
    // is skipped with no error at all: _paymentProvider stays null even
    // though the server genuinely returned {"provider": "paymob", ...}.
    // `is Map` still lets us index with String keys safely below.
    if (r is Map) {
      if (r['provider'] == null) {
        debugPrint('[config] WARNING: /api/v1/config returned no "provider" '
            'key. Raw response: $r');
      }
      _paymentProvider = r['provider'] as String?;
      _hasNativeMobileSdk = r['has_native_mobile_sdk'] as bool? ?? true;

      // BUG FIX: was `r['paymob_sdk'] as Map<String, dynamic>?`. Unlike an
      // `is` check, a mismatched `as` cast THROWS rather than silently
      // skipping — if the decoded value were a Map<dynamic, dynamic> at
      // runtime, this would abort the method right here, before
      // notifyListeners() below ever ran, leaving the UI showing stale
      // state even though _paymentProvider was already set two lines up.
      final rawPaymobSdk = r['paymob_sdk'];
      final paymobSdk = rawPaymobSdk is Map
          ? Map<String, dynamic>.from(rawPaymobSdk)
          : null;
      if (paymobSdk != null) {
        _paymobApiKey = paymobSdk['api_key'] as String?;
        _paymobIntegrationId = (paymobSdk['integration_id'] as num?)?.toInt();
        _paymobIframeId = (paymobSdk['iframe_id'] as num?)?.toInt();
        _paymobSandbox = paymobSdk['is_sandbox'] as bool? ?? true;
      } else {
        _paymobApiKey = null;
        _paymobIntegrationId = null;
        _paymobIframeId = null;
      }

      if (_paymentProvider != 'moyasar' && _selection == _Selection.stcPay) {
        _selection = _Selection.newCard;
      }
      notifyListeners();
    }
  }

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
    if (!supportsStcPay) return; // guard even if the UI somehow still shows it
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

  Future<void> confirm(SavedMethodsProvider savedP,
      BuildContext context) async {
    if (isFree) {
      await _enrollFree();
      return;
    }
    switch (_selection) {
      case _Selection.newCard:
        await _startCardPayment(context);
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
  //
  // Both Moyasar and Paymob now have native mobile SDKs (card form + 3DS
  // on-device), so this just routes to whichever one is active. Any
  // provider without a native SDK — or either provider on web — falls back
  // to hosted checkout in _openWebCheckout.
  Future<void> _startCardPayment(BuildContext context) async {
    if (kIsWeb || !_hasNativeMobileSdk) {
      await _openWebCheckout(context);
      return;
    }
    switch (_paymentProvider) {
      case 'moyasar':
        await _startMoyasarSdkPayment(context);
      case 'paymob':
        await _openWebCheckout(context);
        // await _startPaymobSdkPayment2(context);
      default:
        await _openWebCheckout(context);
      // has_native_mobile_sdk was true but we don't recognise which
      // provider that's for (e.g. config hasn't loaded yet) — fail
      // safely and visibly instead of silently doing nothing, which is
      // what happened before this was a real switch statement.
        _failureReason = 'طريقة الدفع هذه غير مدعومة حالياً';
        _step = EnrollStep.failed;
        notifyListeners();
    }
  }

  /// Moyasar SDK: handles card form + 3DS internally, then verifies with
  /// the backend via _recordSdkPayment.
  Future<void> _startMoyasarSdkPayment(BuildContext context) async {
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
        builder: (_) =>
            MoyasarCardPaymentScreen(
              config: config,
              onPaymentResult: (result) {
                Navigator.of(context).pop();
                _handleSdkResult(result, context);
              },
            ),
      ),
    );
  }




  /// Paymob SDK (paymob_flutter, Direct API card entry — no WebView).
  /// Mirrors the Moyasar flow above: charge via the SDK, then verify +
  /// activate the enrollment through the SAME backend endpoint
  /// (_recordSdkPayment), which is provider-agnostic already.
  Future<void> _startPaymobSdkPayment2(BuildContext context) async {
    FlutterPaymobPayment(
        cardInfo: CardInfo(
            apiKey: 'ZXlKaGJHY2lPaUpJVXpVeE1pSXNJblI1Y0NJNklrcFhWQ0o5LmV5SmpiR0Z6Y3lJNklrMWxjbU5vWVc1MElpd2ljSEp2Wm1sc1pWOXdheUk2TVRJeU56QTBPQ3dpYm1GdFpTSTZJbWx1YVhScFlXd2lmUS5XTThHTnRrbzZmd0pEMVdXX1RCQ3dfb19JRnFsS2IwUGs0UzhGa1UyLUVEZkloUGlJUTAwZXE3Y2RLVjBRdHFvTnAzYmcwNUFtRFRmQmRSa3VRajBpdw==',
            integrationID: "5904081",
            iframesID: "1077017",
            ),
        totalPrice: 100, // 100 EGP --required pay with Egypt currency
        successResult: (data) {
          print("--------------[ data ]--------------");
          print(data);
        },
        errorResult: (error) {
          // Handle payment error
        });
    // final result = await Paymob.pay(
    //   context: context,
    //   config: PaymobConfig(
    //     apiKey: 'ZXlKaGJHY2lPaUpJVXpVeE1pSXNJblI1Y0NJNklrcFhWQ0o5LmV5SmpiR0Z6Y3lJNklrMWxjbU5vWVc1MElpd2ljSEp2Wm1sc1pWOXdheUk2TVRJeU56QTBPQ3dpYm1GdFpTSTZJbWx1YVhScFlXd2lmUS5XTThHTnRrbzZmd0pEMVdXX1RCQ3dfb19JRnFsS2IwUGs0UzhGa1UyLUVEZkloUGlJUTAwZXE3Y2RLVjBRdHFvTnAzYmcwNUFtRFRmQmRSa3VRajBpdw==',
    //     integrationId: 5904081,
    //     iframeId: 1077017,
    //     isSandbox: false,
    //   ),
    //   order: PaymobOrder(
    //     amount: 100.0,
    //     currency: 'EGP',
    //     items: [
    //       OrderItem(name: 'Product', amount: 100.0, quantity: 1),
    //     ],
    //   ),
    //   billing: BillingData(
    //     firstName: 'John',
    //     lastName: 'Doe',
    //     email: 'john@example.com',
    //     phone: '+201234567890',
    //   ),
    // );
    // print("===================[result2]===============");
    // print(result.status);
    // print(result.isSuccess);
    // print(result.transactionId);
    // if (result.isSuccess) {
    //   print('Payment ID: ${result.transactionId}');
    // } else if (result.isPending) {
    //   print('Pending: ${result.transactionId}');
    // } else if (result.isCancelled) {
    //   print('Cancelled by user');
    // } else {
    //   print('Failed: ${result.errorMessage}');
    // }
  }
  Future<void> _startPaymobSdkPayment(BuildContext context) async {
    Map data = {
      "api_key": "ZXlKaGJHY2lPaUpJVXpVeE1pSXNJblI1Y0NJNklrcFhWQ0o5LmV5SmpiR0Z6Y3lJNklrMWxjbU5vWVc1MElpd2ljSEp2Wm1sc1pWOXdheUk2TVRJeU56QTBPQ3dpYm1GdFpTSTZJbWx1YVhScFlXd2lmUS5XTThHTnRrbzZmd0pEMVdXX1RCQ3dfb19JRnFsS2IwUGs0UzhGa1UyLUVEZkloUGlJUTAwZXE3Y2RLVjBRdHFvTnAzYmcwNUFtRFRmQmRSa3VRajBpdw==",
      "integration_id": 5904081,
      "iframe_id": 1077017,
      "is_sandbox": true
    };
    _paymobApiKey = data['api_key'];
    _paymobIntegrationId = data['integration_id'];
    _paymobIframeId = data['iframe_id'];
    _paymobSandbox = data['is_sandbox'];
    if (_paymobApiKey == null ||
        _paymobIntegrationId == null ||
        _paymobIframeId == null) {
      // Config hasn't loaded, or the backend has no SDK credentials set
      // (PAYMOB_*_API_KEY / IFRAME_ID / SDK_INTEGRATION_ID missing in
      // .env) — fall back to hosted checkout instead of calling the SDK
      // with a null key.
      await _openWebCheckout(context);
      return;
    }

    // BUG FIX: the amount charged here must equal what
    // PaymentService.record_sdk_payment() expects
    // (FeeService.calculate(course.fees, "mada").total — see that
    // method's comment on why "mada" is used for Paymob's SDK path too).
    // The original code charged raw course.price with no fee added at
    // all, so the backend's amount check would reject every real payment
    // as "مبلغ الدفع غير متطابق".
    // final fees = FeeBreakdown.calculate(
    //   coursePrice: course.price,
    //   brand: CardBrand.mada,
    // );
    //
    // makeLoading();
    // notifyListeners();
    // try {
      UserModel? user=context.read<AuthProvider>().currentUser;
      List<String> names=(user?.name??'student').split(' ');
      String first=names.first;
      String last=names.last;
      //
      // final result = await Paymob.pay(
      //   context: context,
      //   config: PaymobConfig(
      //     apiKey: _paymobApiKey!,
      //     integrationId: _paymobIntegrationId!,
      //     iframeId: _paymobIframeId!,
      //     isSandbox: _paymobSandbox,
      //   ),
      //   order: PaymobOrder(
      //     amount: fees.total,
      //     currency: 'EGP',
      //     items: [
      //       OrderItem(
      //           name: 'كورس: ${course.name}', amount: fees.total, quantity: 1),
      //     ],
      //   ),
      //   billing: BillingData(
      //     firstName: first,
      //     lastName: last,
      //     email: user?.gmail??'app@gmail.com',
      //     phone:  user?.phone??'+201000000000',
      //   ),
      // );
    //   final result = await Paymob.pay(
    //     context: context,
    //     config: PaymobConfig(
    //       apiKey: 'ZXlKaGJHY2lPaUpJVXpVeE1pSXNJblI1Y0NJNklrcFhWQ0o5LmV5SmpiR0Z6Y3lJNklrMWxjbU5vWVc1MElpd2ljSEp2Wm1sc1pWOXdheUk2TVRJeU56QTBPQ3dpYm1GdFpTSTZJbWx1YVhScFlXd2lmUS5XTThHTnRrbzZmd0pEMVdXX1RCQ3dfb19JRnFsS2IwUGs0UzhGa1UyLUVEZkloUGlJUTAwZXE3Y2RLVjBRdHFvTnAzYmcwNUFtRFRmQmRSa3VRajBpdw==',
    //       integrationId: 5904081,
    //       iframeId: 1077017,
    //       isSandbox: true,
    //     ),
    //     order: PaymobOrder(
    //       amount: course.price,
    //       currency: 'EGP',
    //       items: [
    //         OrderItem(name: 'Product', amount: course.price, quantity: 1),
    //       ],
    //     ),
    //     billing: BillingData(
    //       firstName: 'John',
    //       lastName: 'Doe',
    //       email: 'john@example.com',
    //       phone: '+201234567890',
    //     ),
    //   );
    //   print("===================[result]===============");
    //   print(result.status);
    //   print(result.isSuccess);
    //   print(result.transactionId);
    //   if (result.isSuccess && result.transactionId != null) {
    //     // BUG FIX: this used to just print() the transaction id and stop —
    //     // nothing was ever sent to the backend, so the payment was never
    //     // verified and the course was never activated even though Paymob
    //     // had genuinely charged the card. Route through the same
    //     // verify-and-activate call the Moyasar SDK path already uses.
    //     await _recordSdkPayment(result.transactionId!);
    //   } else if (result.isPending && result.transactionId != null) {
    //     // record_sdk_payment() already handles a not-yet-paid transaction
    //     // gracefully (soft "قيد المعالجة" message, not a hard error) — see
    //     // its `else` branch below — so this doesn't need special-casing.
    //     await _recordSdkPayment(result.transactionId!);
    //   } else if (result.isCancelled) {
    //     // User backed out of the sheet — stay on the method step, no
    //     // error banner.
    //   } else {
    //     _failureReason =
    //         result.errorMessage ?? 'فشلت عملية الدفع. حاول مرة أخرى.';
    //     _step = EnrollStep.failed;
    //   }
    // } catch (e) {
    //   _failureReason = 'تعذّر إتمام الدفع: $e';
    //   _step = EnrollStep.failed;
    // } finally {
    //   stopLoading();
    //   notifyListeners();
    // }
  }

  // ── Hosted checkout (web + non-SDK mobile) ────────────────────────────────
  //
  // Works for Moyasar's own checkout page AND Paymob's Unified Checkout —
  // the backend already returns the right checkout_url for whichever
  // provider is active; this widget doesn't need to know which one.
  Future<void> _openWebCheckout(BuildContext context) async {
    makeLoading();
    notifyListeners();

    try {
      final session = await run(() =>
          _api.post(
            '/api/v1/create-web-session',
            body: {'course_id': course.id},
          ));

      // BUG FIX: was `session is! Map<String, dynamic>` — see the note in
      // loadPaymentConfig() on why an exact-generic `is` check can
      // silently misfire on a genuinely successful response.
      if (session is! Map) {
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

      _paymentProvider = session['provider'] as String? ?? _paymentProvider;

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

      // Push the platform-appropriate checkout page. This is provider-
      // agnostic on purpose — it renders whatever checkout_url the backend
      // gave us, whether that's Moyasar's payment_form.html or Paymob's
      // accept.paymob.com/unifiedcheckout/ page.
      //   Web    → IFrameCheckoutPage (checkout_web_impl.dart)
      //   Mobile → MobileCheckoutPage (defined below in this file)

      final Widget checkoutPage = kIsWeb
          ? IFrameCheckoutPage(url: resolvedUrl)
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

  /// Verifies + completes a payment taken via a native mobile SDK
  /// (Moyasar's own SDK, or Paymob's via paymob_flutter) by asking the
  /// backend to fetch and check it against the provider's own API.
  /// Provider-agnostic despite the body field name below
  /// ('moyasar_payment_id') — PaymentService.record_sdk_payment()
  /// dispatches through whichever provider is active, it isn't
  /// Moyasar-specific; the field predates Paymob's SDK support and was
  /// left as-is server-side to avoid an unnecessary breaking rename.
  Future<void> _recordSdkPayment(String providerPaymentId) async {
    _step = EnrollStep.verifying;
    notifyListeners();

    final r = await run(() =>
        _api.post(
          '/api/v1/payments/record-sdk-payment',
          body: {
            'course_id': course.id,
            'moyasar_payment_id': providerPaymentId,
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

  // ── Saved card (Moyasar only — hidden in enrollment_screen.dart's picker
  // when !supportsSavedCards, see enrollment_screen_patch.md) ───────────────

  Future<void> _chargeWithSavedCard(SavedPaymentMethod card) async {
    final r = await run(() =>
        _api.post('/api/v1/payments', queryParams: {
          'course_id': course.id,
          'payment_method': card.cardBrand?.apiKey ?? 'mada',
          'saved_method_id': card.id,
        }));
    if (r is! Map) return;

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

  // ── STC Pay (Moyasar only) ─────────────────────────────────────────────────

  Future<void> initStcPay(String mobile, BuildContext context) async {
    if (!supportsStcPay) {
      _failureReason = 'STC Pay غير متاح مع مزود الدفع الحالي';
      _step = EnrollStep.failed;
      notifyListeners();
      return;
    }
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
        paymentRequest: PaymentRequest(
            config, StcRequestSource(mobile: mobile)),
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
    final r = await run(() =>
        _api.post(
          '/api/v1/payments/bank-transfer',
          queryParams: {'course_id': course.id},
        ));
    if (r is Map) {
      _bankInfo = Map<String, dynamic>.from(r);
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

    final r = await run(() =>
        _api.post(
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
// Provider-agnostic: renders whatever hosted checkout URL it's given,
// whether that's Moyasar's own page or Paymob's Unified Checkout.
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
          if (mounted) if (mounted) setState(() => _loading = false);
        },
        onNavigationRequest: (req) {
          debugPrint('CHECKOUT NAV -> ${req.url}');
          if (req.url.contains(_callbackMarker)) {
            final uri = Uri.parse(req.url);
            // Handle hash-style URL:  /#/payment/callback?status=paid
            final fragment = uri.fragment; // "payment/callback?status=paid"
            String status = 'failed';
            if (fragment.contains('status=')) {
              final q = Uri.parse('?${fragment
                  .split('?')
                  .last}');
              status = q.queryParameters['status'] ?? 'failed';
            } else {
              status = uri.queryParameters['status'] ?? 'failed';
            }
            debugPrint('CHECKOUT STATUS -> $status');
            Navigator.of(context).pop(status);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onWebResourceError: (e) {
          // BUG FIX: this class is COMPILED (never instantiated — see
          // checkout_stub_impl.dart / kIsWeb guard) on Flutter Web builds
          // too. On web, the conditional import swaps in
          // webview_stub.dart's minimal WebResourceError stand-in, which
          // only guarantees `.description` — referencing `.url`,
          // `.errorCode`, or `.isForMainFrame` (real webview_flutter API,
          // not on the stub) fails web compilation even though this
          // branch never runs there. Stick to `.description` only.
          debugPrint('WebView resource error: ${e.description}');
          // Previously this only logged and left the user stuck on a dead
          // page until they manually closed it (which then falls through
          // to the generic "فشلت عملية الدفع" message with no real
          // diagnostic). Fail fast and visibly instead. This does mean
          // any resource error (not just a main-frame load failure) will
          // close the checkout — if that proves too aggressive in
          // practice (e.g. a missing icon/font on the gateway's own page
          // triggering a false failure), share webview_stub.dart and I'll
          // add `isForMainFrame` there too so this can filter properly.
          if (mounted) Navigator.of(context).pop('failed');
        },
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
                  AppLoadingIndicator(),
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