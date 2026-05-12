// checkout_stub_impl.dart
//
// THIS FILE IS COMPILED ONLY ON FLUTTER MOBILE (dart.library.io is available).
// It is the "else" branch of the conditional import in enrollment_provider.dart:
//
//   import 'checkout_web_impl.dart'
//       if (dart.library.io) 'checkout_stub_impl.dart';
//
// On mobile the kIsWeb branch in _openWebCheckout is never taken, so
// IFrameCheckoutPage is never constructed. This stub exists only so the
// Dart compiler finds the public symbol used in that dead-code branch.

import 'package:flutter/material.dart';

/// Stub — never instantiated on mobile (kIsWeb is always false there).
class IFrameCheckoutPage extends StatelessWidget {
  final String url;
  const IFrameCheckoutPage({super.key, required this.url});

  @override
  Widget build(BuildContext context) =>
      const SizedBox.shrink(); // unreachable on mobile
}