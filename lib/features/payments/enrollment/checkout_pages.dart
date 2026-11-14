/// checkout_pages.dart
///
/// • MobileCheckoutPage        — hosted checkout in a WebView (iOS / Android)
/// • MoyasarCardPaymentScreen  — Moyasar's native card form (mobile, Moyasar only)
///
/// Web uses IFrameCheckoutPage from checkout_web_impl.dart instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_header.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:moyasar/moyasar.dart';

import 'package:flutter_education_app/config/app_config.dart' as helpers;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

// webview_flutter is imported only on mobile; the stub keeps Flutter Web compiling.
import 'package:webview_flutter/webview_flutter.dart'
if (dart.library.html) 'package:flutter_education_app/features/payments/enrollment/webview_stub.dart';
import 'package:flutter_education_app/core/display/lazy_fonts.dart';
import 'package:flutter_education_app/features/payments/enrollment/checkout_callback.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Hosted checkout WebView
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
  bool _resolved = false; // pop once

  // The backend's result page redirects to  FLUTTER_APP_URL/#/payment/callback?status=paid — matched exactly by
  // scheme + host + path (checkout_callback.dart), never by "the URL contains /payment/callback".
  final CheckoutOrigin _origin = CheckoutOrigin.current();

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // the gateways' card forms and 3-D Secure need it
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          if (uri != null && isCheckoutCallback(uri, _origin)) {
            // The page's word only: PaymentFlowProvider asks the server before it shows success.
            _finish(checkoutStatusFrom(uri));
            return NavigationDecision.prevent;
          }
          if (!checkoutNavigationAllowed(uri, _origin, isMainFrame: req.isMainFrame)) {
            debugPrint('Checkout WebView: blocked a non-https navigation');
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        // Only `.description` exists on the web stub's WebResourceError.
        onWebResourceError: (e) {
          debugPrint('Checkout WebView error: ${e.description}');
          _finish('failed');
        },
      ));
    final start = Uri.tryParse(widget.url);
    if (checkoutNavigationAllowed(start, _origin)) {
      _controller.loadRequest(start!);
    } else {
      // the server handed a page we will not open (not https): nothing was paid
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish('failed'));
    }
  }

  void _finish(String status) {
    if (_resolved || !mounted) return;
    _resolved = true;
    Navigator.of(context).pop(status);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        title: 'complete_payment_title'.tr,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: context.colors.onHero),
          tooltip: 'cancel'.tr,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => _finish('cancelled'),
        ),
      ),
      body: Stack(
        children: [
          ParentComponent(
            featureKey: 'payments.card',
            child: WebViewWidget(controller: _controller),
          ),
          if (_loading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLoadingIndicator(),
                  const SizedBox(height: 16),
                  Text('loading_payment_page'.tr),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Moyasar Apple Pay (iOS) — needs the Apple merchant id from GET /config
// ═════════════════════════════════════════════════════════════════════════════

class MoyasarApplePayScreen extends StatelessWidget {
  final PaymentConfig config;
  final void Function(dynamic) onPaymentResult;

  const MoyasarApplePayScreen({super.key, required this.config, required this.onPaymentResult});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Directionality(
      textDirection: helpers.pageDirection,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: const AppHeader(title: 'Apple Pay'),
        body: ParentComponent(
          featureKey: 'payments.card',
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ApplePay(config: config, onPaymentResult: onPaymentResult),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Moyasar native card form
// ═════════════════════════════════════════════════════════════════════════════

class MoyasarCardPaymentScreen extends StatelessWidget {
  final PaymentConfig config;
  final void Function(dynamic) onPaymentResult;

  const MoyasarCardPaymentScreen({
    super.key,
    required this.config,
    required this.onPaymentResult,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Directionality(
      textDirection: helpers.pageDirection,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppHeader(title: 'card_details_title'.tr),
        body: ParentComponent(
          featureKey: 'payments.card',
          // the card form draws with the moyasar package's Readex Pro (a lazy font on the web build)
          child: LazyFontGate(
            families: const ['packages/moyasar/ReadexPro'],
            child: CreditCard(config: config, onPaymentResult: onPaymentResult),
          ),
        ),
      ),
    );
  }
}