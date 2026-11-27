// payer_methods.dart
//
// The payment-method keys the payer's country may use (GET /api/v1/payments/methods, docs/redesign/api/payments.md
// §1): مدى and STC Pay only in Saudi Arabia, InstaPay only in Egypt, cards and wallets elsewhere; all decided by the
// server, never by the app. The course checkout and the points wallet narrow their own lists with it.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

/// The method keys, or null when the server does not answer (an older server, offline) or lists nothing: the
/// caller then keeps its own list. Never throws.
Future<Set<String>?> payerMethodKeys(ApiClient api, {Object? courseId, Duration? timeout}) async {
  try {
    var call = api.get('/api/v1/payments/methods',
        queryParams: {'lang': AppConfig.lang, if (courseId != null) 'course_id': '$courseId'});
    if (timeout != null) call = call.timeout(timeout);
    final raw = await call;
    final list = raw is Map ? raw['methods'] : null;
    if (list is! List || list.isEmpty) return null;
    return {for (final m in list) if (m is Map && m['key'] is String) m['key'] as String};
  } catch (_) {
    return null;
  }
}

/// True when [type] (a /config or wallet method key) is open for the payer: listed, or a card when the country list
/// has `card` or `mada`. Null [keys] allows everything.
bool payerAllows(Set<String>? keys, String type) =>
    keys == null || keys.contains(type) || (type == 'card' && keys.contains('mada'));
