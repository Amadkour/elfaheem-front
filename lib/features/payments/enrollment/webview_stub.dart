// webview_stub.dart
//
// Stub for `package:webview_flutter` on Flutter Web.
// Imported via the conditional import in enrollment_provider.dart:
//
//   import 'package:webview_flutter/webview_flutter.dart'
//       if (dart.library.html) 'webview_stub.dart';
//
// On Flutter Web, webview_flutter_web throws UnimplementedError for
// setJavaScriptMode and onNavigationRequest, so we never use it.
// This stub satisfies the Dart type-checker while the kIsWeb guard
// ensures _MobileCheckoutPage is never constructed on web.

import 'package:flutter/material.dart';

// Minimal stubs — only the symbols referenced in _MobileCheckoutPage.

enum JavaScriptMode { unrestricted, disabled }

class NavigationDecision {
  static const NavigationDecision navigate = NavigationDecision._();
  static const NavigationDecision prevent  = NavigationDecision._();
  const NavigationDecision._();
}

class NavigationRequest {
  final String url;
  final bool isMainFrame;
  const NavigationRequest(this.url, {this.isMainFrame = true});
}

class WebResourceError {
  final String description;
  const WebResourceError({required this.description});
}

class NavigationDelegate {
  final void Function(String)? onPageFinished;
  final NavigationDecision Function(NavigationRequest)? onNavigationRequest;
  final void Function(WebResourceError)? onWebResourceError;
  const NavigationDelegate({
    this.onPageFinished,
    this.onNavigationRequest,
    this.onWebResourceError,
  });
}

class WebViewController {
  WebViewController setJavaScriptMode(JavaScriptMode _) => this;
  WebViewController setNavigationDelegate(NavigationDelegate _) => this;
  Future<void> loadRequest(Uri _) async {}
}

class WebViewWidget extends StatelessWidget {
  // ignore: unused_element
  final WebViewController controller;
  const WebViewWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
