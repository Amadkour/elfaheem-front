// lib/features/admin/admin_labels.dart  (NEW FILE)
//
// Shared helpers for the admin pages:
//  • disposeAfterRoute()  – safe disposal of text controllers created OUTSIDE a bottom sheet / dialog
//  • human-readable (translated) labels for raw server codes (status, plan, payment method)
library;

import 'package:flutter/widgets.dart';

import '../../config/app_config.dart';

/// Dispose controllers only AFTER the sheet / dialog has fully left the screen.
///
/// `showAppModalSheet(...).whenComplete(dispose)` runs the moment the route is POPPED, but the
/// sheet is still on screen for its ~250 ms closing animation (and rebuilds when the keyboard hides).
/// Disposing right away makes the still-mounted TextFields throw "used after being disposed".
void disposeAfterRoute(Iterable<TextEditingController> controllers) {
  final list = controllers.toList();
  Future.delayed(const Duration(milliseconds: 500), () {
    for (final c in list) {
      c.dispose();
    }
  });
}

String subscriptionStatusLabel(String s) => switch (s) {
  'pending' => 'admin_pending_4'.tr,
  'active' => 'admin_active'.tr,
  'expired' => 'admin_expired'.tr,
  'rejected' => 'admin_rejected'.tr,
  'cancelled' => 'admin_cancelled_2'.tr,
  _ => s,
};

String enrollmentStatusLabel(String s) => switch (s) {
  'active' => 'admin_active'.tr,
  'completed' => 'completed'.tr,
  'dropped' => 'admin_dropped'.tr,
  'pending' => 'admin_pending_4'.tr,
  _ => s,
};

String paymentStatusLabel(String s) => switch (s) {
  'completed' => 'completed'.tr,
  'pending' => 'admin_pending_4'.tr,
  'refunded' => 'admin_refunded_status'.tr,
  'failed' => 'admin_failed'.tr,
  _ => s,
};

String planLabel(String code) => switch (code) {
  'monthly' => 'plan_monthly'.tr,
  'six_months' => 'plan_six_months'.tr,
  'yearly' => 'plan_yearly'.tr,
  'custom' => 'admin_custom_days'.tr,
  _ => code,
};

String paymentMethodLabel(String? m) => switch (m) {
  null || '' => '—',
  'instapay' => 'transfer_instapay_title'.tr,
  'bank_transfer' => 'transfer_bank_title'.tr,
  'card' => 'admin_payment_card'.tr,
  _ => m,
};