/// checkout_callback.dart — the rules of the hosted-checkout WebView (S6), pure so they can be tested.
///
/// The server's result page sends the browser to `FLUTTER_APP_URL/#/payment/callback?status=…` (the course checkout,
/// `../back/features/billing/api/checkout.py` `_result`, and the points top-up, `points_router.py`). The WebView
///   • treats a URL as that callback only on an exact scheme + host + path match ([isCheckoutCallback]),
///   • follows only https pages ([checkoutNavigationAllowed]), and
///   • never shows "paid" on the page's word alone: the flow asks `GET /api/v1/payments/{id}` first
///     ([paymentStatusStep], PaymentFlowProvider).
library;

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'package:flutter_education_app/config/app_config.dart';

/// The app's callback route, after the `#` (hash routing) or as the path (a path-strategy build).
const String kCheckoutCallbackRoute = '/payment/callback';

/// Paths of the web app the callback may sit under: the site root (the landing forwards a hash route to `/app/`)
/// and the app itself (D-270).
const List<String> kCheckoutAppPaths = ['', '/', '/app', '/app/'];

/// Where the callback may come from: the API's own host (and its `www.` twin), plus the local stack's hosts in a
/// debug build (`FLUTTER_APP_URL` is `http://localhost:8000` there).
class CheckoutOrigin {
  const CheckoutOrigin({required this.schemes, required this.hosts});

  final Set<String> schemes;
  final Set<String> hosts;

  /// From [AppConfig.baseUrl].
  factory CheckoutOrigin.current({bool release = kReleaseMode}) {
    final api = Uri.tryParse(AppConfig.baseUrl);
    final host = (api?.host ?? '').toLowerCase();
    final hosts = <String>{
      if (host.isNotEmpty) host,
      if (host.isNotEmpty && !host.startsWith('www.')) 'www.$host',
      if (!release) ...kDevCheckoutHosts,
    };
    final schemes = <String>{'https', if (!release) 'http'};
    return CheckoutOrigin(schemes: schemes, hosts: hosts);
  }

  bool matches(Uri u) => schemes.contains(u.scheme.toLowerCase()) && hosts.contains(u.host.toLowerCase());
}

/// The local stack's hosts (CLAUDE.md: emulator `10.0.2.2`, web / simulator `localhost`).
const Set<String> kDevCheckoutHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

/// True when [url] is the app's payment callback: an allowed scheme + host, the web app's path, and the
/// `/payment/callback` route (in the fragment, or as the path). A URL that merely *contains* the words — a gateway
/// page, `evil.example/payment/callback`, `?next=/payment/callback` — is not.
bool isCheckoutCallback(Uri url, CheckoutOrigin origin) {
  if (!origin.matches(url)) return false;
  final path = url.path;
  if (kCheckoutAppPaths.contains(path)) {
    final frag = url.fragment;
    final route = frag.split('?').first;
    return route == kCheckoutCallbackRoute || route == '$kCheckoutCallbackRoute/';
  }
  return path == kCheckoutCallbackRoute || path == '/app$kCheckoutCallbackRoute';
}

/// The callback's `status` (`paid` · `initiated` · `failed` …), read from the hash route's query first, then from the
/// URL's own query. `failed` when there is none.
String checkoutStatusFrom(Uri url) {
  final frag = url.fragment;
  if (frag.contains('?')) {
    final q = Uri.splitQueryString(frag.substring(frag.indexOf('?') + 1));
    final s = q['status'];
    if (s != null && s.isNotEmpty) return s;
  }
  final s = url.queryParameters['status'];
  return (s == null || s.isEmpty) ? 'failed' : s;
}

/// May the checkout WebView follow [url]? https only — the gateway pages, 3-D Secure and our result page are all
/// https. A sub-frame may also load `about:blank` / `about:srcdoc` (3-D Secure iframes start there). A debug build
/// also follows the local stack's own http pages ([origin]). Everything else (`http:`, `javascript:`, `data:`,
/// `file:`, `intent:`, custom schemes) is blocked.
bool checkoutNavigationAllowed(Uri? url, CheckoutOrigin origin, {bool isMainFrame = true}) {
  if (url == null) return false;
  final scheme = url.scheme.toLowerCase();
  if (scheme == 'https') return url.host.isNotEmpty;
  if (scheme == 'about') return !isMainFrame && (url.path == 'blank' || url.path == 'srcdoc');
  if (scheme == 'http') return origin.schemes.contains('http') && origin.hosts.contains(url.host.toLowerCase());
  return false;
}

/// What the server says about a payment the result page called paid (`GET /api/v1/payments/{id}` → `status`:
/// `pending` · `completed` · `failed` · `refunded`).
enum PaidCheck { confirmed, pending, failed }

/// Folds the statuses of every payment of one checkout (a roadmap checkout makes one per course): confirmed only when
/// every one is `completed`; failed as soon as one failed or was refunded; pending otherwise (unknown, unreadable, or
/// no ids at all — never success).
PaidCheck paymentStatusStep(List<String?> statuses) {
  if (statuses.isEmpty) return PaidCheck.pending;
  final s = statuses.map((e) => (e ?? '').toLowerCase()).toList();
  if (s.any((e) => e == 'failed' || e == 'refunded')) return PaidCheck.failed;
  if (s.every((e) => e == 'completed')) return PaidCheck.confirmed;
  return PaidCheck.pending;
}

/// The payment ids of a checkout session (`payment_ids`, else `payment_id`).
List<int> checkoutPaymentIds(Map<String, dynamic> session) {
  final ids = <int>[];
  final list = session['payment_ids'];
  if (list is List) {
    for (final e in list) {
      final v = e is int ? e : int.tryParse('$e');
      if (v != null && !ids.contains(v)) ids.add(v);
    }
  }
  if (ids.isEmpty) {
    final one = session['payment_id'];
    final v = one is int ? one : int.tryParse('${one ?? ''}');
    if (v != null) ids.add(v);
  }
  return ids;
}
