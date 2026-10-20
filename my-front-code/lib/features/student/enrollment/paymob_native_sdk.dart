// /// paymob_native_sdk.dart — thin wrapper over Paymob's official Flutter SDK
// /// (package `flutter_paymob_sdk`, https://github.com/PaymobAccept/flutter_sdk).
// ///
// /// The SDK opens Paymob's native payment sheet (cards + Apple Pay on iOS + Google Pay on Android)
// /// for the intention the backend created. The server never trusts this result: Paymob's webhook is
// /// what completes the payment, the app only decides what to show while it waits.
// library;
//
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_paymob_sdk/flutter_paymob_sdk.dart';
//
// enum PaymobSdkResult { success, pending, rejected, cancelled, unavailable }
//
// class PaymobNativeSdk {
//   PaymobNativeSdk._();
//
//   static final PaymobService _service = PaymobService();
//
//   static Future<PaymobSdkResult> pay({
//     required String publicKey,
//     required String clientSecret,
//     required String appName,
//     Color buttonColor = const Color(0xFF1A73E8),
//   }) async {
//     try {
//       final result = await _service.payWithPaymob(
//         publicKey: publicKey,
//         clientSecret: clientSecret,
//         customization: PaymobCustomization(
//           appName: appName,
//           androidAppLogo: 'ic_launcher', // the app launcher icon every Flutter project ships with
//           buttonBackgroundColor: buttonColor,
//           buttonTextColor: Colors.white,
//           showSaveCard: false,
//           saveCardDefault: false,
//         ),
//       );
//       if (result.isSuccessful) return PaymobSdkResult.success;
//       if (result.isPending) return PaymobSdkResult.pending;
//       if (result.isCancelled) return PaymobSdkResult.cancelled;
//       return PaymobSdkResult.rejected;
//     } on MissingPluginException {
//       return PaymobSdkResult.unavailable; // platform without the plugin (web/desktop) → hosted page
//     } on PlatformException {
//       return PaymobSdkResult.rejected;
//     }
//   }
// }
