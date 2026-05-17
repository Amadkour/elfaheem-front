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
// IMPORTANT — result.html must send postMessage BEFORE its redirect timer.
//   See the updated result.html delivered alongside this file.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

/// Shown on Flutter Web. Embeds the checkout page in a full-screen <iframe>.
/// Receives the payment status via window.postMessage from result.html.
class IFrameCheckoutPage extends StatefulWidget {
  final String url;
  const IFrameCheckoutPage({super.key, required this.url});

  @override
  State<IFrameCheckoutPage> createState() => IFrameCheckoutPageState();
}

class IFrameCheckoutPageState extends State<IFrameCheckoutPage> {
  late final String _viewId;
  late final html.IFrameElement _iframe;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    // Unique key per page instance so the platform view registry
    // doesn't collide if the user navigates back and retries.
    _viewId = 'moyasar-checkout-${DateTime.now().millisecondsSinceEpoch}';

    _iframe = html.IFrameElement()
      ..src = widget.url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'payment'          // required for payment APIs inside iframe
      ..onLoad.listen((_) {
        if (mounted) if(mounted) setState(() => _loading = false);
      });

    // Register the iframe as a Flutter platform view (web only)
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) => _iframe,
    );

    // Listen for postMessage from result.html.
    // result.html calls: window.parent.postMessage({ moyasarStatus: 'paid' }, '*')
    html.window.onMessage.listen((html.MessageEvent event) {
      final data = event.data;
      if (data is Map && data.containsKey('moyasarStatus')) {
        final status = data['moyasarStatus'] as String? ?? 'failed';
        if (mounted) Navigator.of(context).pop(status);
      }
    });
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
