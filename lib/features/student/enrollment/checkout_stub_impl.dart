// checkout_stub_impl.dart
//
// THIS FILE IS COMPILED ONLY ON FLUTTER MOBILE (dart.library.io is available).
// It is the "else" branch of the conditional import in enrollment_provider.dart:
//
//   import 'checkout_web_impl.dart'
//       if (dart.library.io) 'checkout_stub_impl.dart';
//
// On mobile the web checkout path (kIsWeb == false) is never taken, so
// _IFrameCheckoutPage is never constructed. This stub just needs to exist
// so the Dart compiler doesn't complain about the missing export.

import 'package:flutter/material.dart';

/// Stub — never instantiated on mobile (kIsWeb is always false there).
// ignore: unused_element
class _IFrameCheckoutPage extends StatelessWidget {
  // ignore: unused_element
  final String url;
  // ignore: unused_element
  const _IFrameCheckoutPage({required this.url});

  @override
  Widget build(BuildContext context) =>
      const SizedBox.shrink(); // unreachable on mobile
}
