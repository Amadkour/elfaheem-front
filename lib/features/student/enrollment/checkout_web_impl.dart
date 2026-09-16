// checkout_web_impl.dart
//
// THIS FILE IS COMPILED ONLY ON FLUTTER WEB (dart.library.html is available).
// It is imported via the conditional import in enrollment_provider.dart:
//
//   import 'checkout_web_impl.dart'
//       if (dart.library.io) 'checkout_stub_impl.dart';
//
// WHY <iframe> instead of webview_flutter on web:
//   webview_flutter_web does NOT implement setJavaScriptMode or
//   onNavigationRequest — calling them throws UnimplementedError.
//
//   The Flutter-Web-native approach is:
//     1. Register a native <iframe> element via platformViewRegistry.
//     2. Listen on window.onMessage for a postMessage from result.html.
//     3. Pop the route with the payment status string.
//
// IMPORTANT — result.html must send:
//   window.parent.postMessage({ moyasarStatus: '<status>' }, '<APP origin>')
//   (or the newer { paymentStatus: '<status>' } key — both are accepted)
//   BEFORE its redirect timer, for every provider.
//
// PROVIDER-AGNOSTIC BY DESIGN — no Paymob-specific branch needed here:
//   `widget.url` is initially either Moyasar's payment_form.html or
//   Paymob's accept.paymob.com/unifiedcheckout/ page, but in BOTH cases the
//   iframe eventually navigates to redirection_url, which always resolves
//   to *our own* result.html (rendered server-side by checkout.py). Since
//   we own result.html regardless of which gateway was used, this file only
//   ever needs to listen for one message contract — it never needs to know
//   which provider is active. Keep it that way: don't special-case Paymob
//   here, fix it in result.html/checkout.py's _result() if it ever breaks.
//
// SECURITY: postMessage is validated against APP_URL's origin (see
// _expectedOrigin below) so a malicious page embedded some other way can't
// spoof a 'paid' status into this app.

// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

/// Shown on Flutter Web. Embeds the checkout page in a full-screen <iframe>.
/// Works for any hosted-checkout provider (Moyasar, Paymob, ...) because it
/// only ever reacts to a postMessage from our own result.html — see the
/// note above.
class IFrameCheckoutPage extends StatefulWidget {
  final String url;
  const IFrameCheckoutPage({super.key, required this.url});

  @override
  State<IFrameCheckoutPage> createState() => IFrameCheckoutPageState();
}

class IFrameCheckoutPageState extends State<IFrameCheckoutPage> {
  late final String _viewId;
  late final html.IFrameElement _iframe;
  StreamSubscription<html.MessageEvent>? _messageSub;
  bool _loading = true;
  bool _resolved = false; // guard against popping twice

  /// Origin that a legitimate postMessage from result.html must come from.
  /// result.html is always rendered by OUR backend (APP_URL), never by the
  /// gateway (Moyasar/Paymob), regardless of which provider is active — so
  /// this one check covers every provider.
  late final String? _expectedOrigin = Uri.tryParse(AppConfig.baseUrl)?.origin;

  @override
  void initState() {
    super.initState();

    // Unique key per page instance so the platform view registry doesn't
    // collide if the user navigates back and retries (any provider).
    _viewId = 'payment-checkout-${DateTime.now().millisecondsSinceEpoch}';

    _iframe = html.IFrameElement()
      ..src = widget.url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'payment'          // required for payment APIs inside iframe
      ..onLoad.listen((_) {
        if (mounted) setState(() => _loading = false);
      });

    // Register the iframe as a Flutter platform view (web only)
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      _viewId,
          (int viewId) => _iframe,
    );

    // Listen for postMessage from result.html.
    // result.html calls:
    //   window.parent.postMessage({ paymentStatus: 'paid' }, TARGET_ORIGIN)
    // for EVERY provider — it's our own page either way, so there is no
    // Moyasar/Paymob branching to do here.
    _messageSub = html.window.onMessage.listen((html.MessageEvent event) {
      if (_resolved) return;

      if (_expectedOrigin != null && event.origin != _expectedOrigin) {
        // Ignore messages that didn't come from our own backend origin —
        // e.g. Paymob's own hosted checkout page posts its own internal
        // messages (type: redirectionURL) while loaded in this same
        // iframe; that's expected noise, not a bug.
        return;
      }

      final data = event.data;
      if (data is Map) {
        // BUG FIX: this previously checked 'moyasorStatus' (typo — missing
        // the 'a'), which never matched the real key result.html actually
        // sends ('moyasarStatus'), so EVERY message — success or failure —
        // was silently ignored and the user always ended up tapping ✕
        // themselves, which pops 'cancelled'. Accept the new generic key
        // too, for when result.html is updated to send it.
        final status = (data['paymentStatus'] ?? data['moyasarStatus'])
        as String?;
        if (status != null) {
          _resolved = true;
          if (mounted) Navigator.of(context).pop(status);
        }
      }
    });
  }

  @override
  void dispose() {
    // Previously missing: without cancelling this, every checkout attempt
    // (retry after a failure, buying a second course, etc.) left another
    // window.onMessage listener alive for the lifetime of the app, each one
    // racing to pop an already-popped/disposed route.
    _messageSub?.cancel();
    super.dispose();
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
          // The registered iframe fills the entire body
          HtmlElementView(viewType: _viewId),
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