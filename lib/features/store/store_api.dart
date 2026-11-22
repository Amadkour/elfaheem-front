// lib/features/store/store_api.dart — the student side of the digital store (Learning Hub Phase 5, D-1333). Every
// path is a literal `/api/v1/store/…` (test/contract/ checks each against the server's routes).
//
//   GET  /api/v1/store/items                         browse (optional auth)
//   GET  /api/v1/store/items/{id}                    the item page (+ a 120 s preview link)
//   POST /api/v1/store/quote                         the cart's lines and sums
//   POST /api/v1/store/orders                        + Idempotency-Key: card → checkout.url, points / free → paid
//   GET  /api/v1/store/orders/{id} · /store/orders   one order (polled after the card page) · purchase history
//   GET  /api/v1/store/library                       what the person owns
//   POST /api/v1/store/library/{id}/download         + X-Device-Id → a short single-use link
//
// Kill switches: `student_tab_store` (the tab, browse, quote, order), `store.buy` (ordering), `store.points`.
// Every server code has a bilingual text in [storeErrorText].
library;

import 'dart:async';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/courses/student/security/device_id_service.dart';
import 'package:flutter_education_app/features/store/store_models.dart';
import 'package:uuid/uuid.dart';

/// The store tab's kill switch (the server answers 403 `feature_disabled` too).
const String kStoreTabKey = 'student_tab_store';

/// Buying (POST /store/orders).
const String kStoreBuyKey = 'store.buy';

/// Paying with points.
const String kStorePointsKey = 'store.points';

bool storeOff() => AppConfig.disableList.contains(kStoreTabKey);

bool storeBuyOff([List<String>? disabled]) {
  final d = disabled ?? AppConfig.disableList;
  return d.contains(kStoreTabKey) || d.contains(kStoreBuyKey);
}

bool storePointsOff() => AppConfig.disableList.contains(kStorePointsKey);

/// One key per checkout attempt (8–64 of `A-Za-z0-9_.:-`, the server's rule): a UUID v4.
String newIdempotencyKey() => const Uuid().v4();

/// The server code of a failed store call.
String? storeErrorCode(Object e) => e is ApiException ? e.code : null;

/// A store code's bilingual text (null = not a store code).
String? storeCodeText(String? code, [Map<String, dynamic> d = const {}]) => switch (code) {
      'store_item_not_found' => t('هذا العنصر غير متاح في المتجر', 'This item is not in the store'),
      'store_mixed_currency' => t('لا يمكن دفع عملات مختلفة في طلب واحد. اشترِ كل عملة في طلب منفصل.',
          'One order cannot mix currencies. Buy the items of each currency in their own order.'),
      'store_already_owned' => t('هذا موجود بالفعل في مكتبتك', 'This is already in your library'),
      'store_bad_currency' => d['allowed'] is List && (d['allowed'] as List).isNotEmpty
          ? t('العملة غير مقبولة. المقبول: ${(d['allowed'] as List).join('، ')}',
              'That currency is not accepted. Accepted: ${(d['allowed'] as List).join(', ')}')
          : t('العملة غير مقبولة', 'That currency is not accepted'),
      'store_empty_cart' => t('السلة فارغة', 'The cart is empty'),
      'store_cart_too_large' => t('السلة كبيرة جداً. قسّمها على أكثر من طلب.', 'The cart is too large. Split it into more than one order.'),
      'idempotency_key_required' || 'idempotency_key_reused' =>
        t('تعذّر بدء الدفع. أعد المحاولة.', 'The payment could not start. Try again.'),
      'card_unavailable' => t('الدفع بالبطاقة غير متاح حالياً', 'Card payment is not available right now'),
      'points_insufficient' => d['needed'] != null && d['balance'] != null
          ? t('رصيد النقاط لا يكفي: تحتاج ${d['needed']} ولديك ${d['balance']}',
              'Not enough points: you need ${d['needed']} and have ${d['balance']}')
          : t('رصيد النقاط لا يكفي', 'Not enough points'),
      'store_points_off' || 'store_points_unavailable' =>
        t('الدفع بالنقاط غير متاح لهذه العناصر', 'Points cannot pay for these items'),
      'store_not_free' => t('هذه العناصر ليست مجانية', 'These items are not free'),
      'bad_provider' || 'store_bad_method' => t('طريقة الدفع غير مدعومة', 'That payment method is not supported'),
      'gateway_error' => t('تعذّر بدء الدفع عند مزوّد الدفع ولم يُنشأ أي طلب. أعد المحاولة.',
          'The payment provider could not start the payment and no order was made. Try again.'),
      'store_order_not_found' => t('الطلب غير موجود', 'The order was not found'),
      'store_not_owned' => t('هذا العنصر ليس في مكتبتك', 'This item is not in your library'),
      'store_download_limit' => d['limit'] != null
          ? t('بلغت حد التنزيل اليومي لهذا العنصر (${d['limit']} مرات). حاول غداً.',
              'You reached today\'s download limit for this item (${d['limit']} times). Try tomorrow.')
          : t('بلغت حد التنزيل اليومي لهذا العنصر. حاول غداً.', 'You reached today\'s download limit for this item. Try tomorrow.'),
      'store_file_missing' || 'store_file_unavailable' =>
        t('الملف غير متاح الآن. أعد المحاولة لاحقاً.', 'The file is not available right now. Try again later.'),
      'store_link_invalid' || 'store_link_expired' =>
        t('انتهت صلاحية رابط التنزيل. نزّله من جديد.', 'The download link expired. Download it again.'),
      'store_link_forbidden' => t('رابط التنزيل لحساب آخر', 'This download link belongs to another account'),
      'DEVICE_ID_MISSING' || 'DEVICE_MISMATCH' => t(
          'حسابك مسجّل على جهاز آخر، فلا يمكن التنزيل هنا. ما اشتريته محفوظ في حسابك: نزّله من جهازك المسجّل، أو اطلب نقل الحساب إلى هذا الجهاز.',
          'Your account is registered on another device, so downloads are not allowed here. Your purchase is safe in your account: download it on your registered device, or request to move the account to this device.'),
      'store_file_corrupt' => t('وصل الملف تالفاً. نزّله من جديد.', 'The file arrived damaged. Download it again.'),
      _ => null,
    };

/// Why a failed order failed, for the buyer (`failure_code`, D-1339): never the provider's raw text.
String storeFailureText(String? code) => switch (code) {
      'amount_mismatch' || 'currency_mismatch' => t('لم يطابق المبلغ المدفوع الطلب، فلم يكتمل الشراء. إن خُصم منك مبلغ فسيُعاد إليك.',
          'The amount paid did not match the order, so the purchase did not complete. If you were charged, it will be refunded.'),
      'transaction_reused' => t('عملية الدفع هذه استُخدمت لطلب آخر. أعد المحاولة بدفع جديد.',
          'This payment was already used for another order. Try again with a new payment.'),
      _ => t('لم يتم الدفع ولم يُخصم شيء. يمكنك المحاولة مرة أخرى.', 'The payment did not go through and nothing was charged. You can try again.'),
    };

/// A store call failed with a definite server answer (a status), so a retry is a new attempt: only then is the
/// Idempotency-Key dropped. A timeout or a lost connection keeps it, so a retry after a lost answer returns the
/// same order instead of opening a second one (D-1339).
bool storeDefiniteAnswer(Object e) => e is ApiException && e.statusCode > 0;

/// What to show for a failed store call: the store's own text, else the app's (feature_disabled, network …).
String storeErrorText(Object e) {
  if (e is TimeoutException) return ApiMessages.timeout;
  final x = ApiException.from(e);
  return storeCodeText(x.code, apiErrorDetail(x)) ?? apiErrorText(x);
}

class StoreApi {
  StoreApi({ApiClient? api, Future<Map<String, String>> Function()? deviceHeaders})
      : _api = api ?? ApiClient(),
        _deviceHeaders = deviceHeaders ?? DeviceIdService.instance.headers;

  final ApiClient _api;
  final Future<Map<String, String>> Function() _deviceHeaders;

  Map<String, dynamic> _m(Object? r) => r is Map ? Map<String, dynamic>.from(r) : const {};

  Future<StoreItemList> items(StoreQuery q, {int skip = 0, int limit = 24}) async =>
      StoreItemList.fromJson(await _api.get('/api/v1/store/items', queryParams: q.toQuery(skip: skip, limit: limit)));

  Future<StoreItem> item(int id, {String? country}) async => StoreItem.fromJson(_m(await _api.get(
      '/api/v1/store/items/$id',
      queryParams: {if (country != null && country.isNotEmpty) 'country': country})));

  /// [couponCode] (Games v3): the sums with that coupon off the net subtotal.
  Future<StoreQuote> quote(List<int> itemIds, {String? couponCode}) async =>
      StoreQuote.fromJson(await _api.post('/api/v1/store/quote', body: {'item_ids': itemIds, 'coupon_code': ?couponCode}));

  /// [method] `card | points | free`; [idempotencyKey] one per checkout attempt; [couponCode] money methods only.
  Future<StoreOrderAnswer> order(List<int> itemIds,
          {required String method, required String idempotencyKey, String? provider, String? couponCode}) async =>
      StoreOrderAnswer.fromJson(await _api.post(
        '/api/v1/store/orders',
        body: {'item_ids': itemIds, 'method': method, 'provider': ?provider, 'coupon_code': ?couponCode},
        headers: {'Idempotency-Key': idempotencyKey},
      ));

  Future<StoreOrderAnswer> orderById(int id) async => StoreOrderAnswer.fromJson(await _api.get('/api/v1/store/orders/$id'));

  Future<StoreOrderPage> orders({int skip = 0, int limit = 20}) async =>
      StoreOrderPage.fromJson(await _api.get('/api/v1/store/orders', queryParams: {'skip': skip, 'limit': limit}));

  Future<List<StoreLibraryItem>> library() async {
    // kept on the device (ReadCache, D-1351): a file already downloaded opens offline from the list
    final m = _m(await readThrough('store.library', () => _api.get('/api/v1/store/library')));
    final items = m['items'];
    return [
      if (items is List)
        for (final e in items)
          if (e is Map) StoreLibraryItem.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<StoreDownload> download(int itemId) async => StoreDownload.fromJson(
      await _api.post('/api/v1/store/library/$itemId/download', headers: await _deviceHeaders()));
}

/// Polls `GET /store/orders/{id}` after the card page closed, until the order is settled or [timeout] passes (the
/// points top-up's wait, pollTopup). A failed read is retried; [sleep] is the test seam.
Future<StoreOrder?> pollStoreOrder(
  Future<StoreOrder> Function() fetch, {
  Duration every = const Duration(seconds: 3),
  Duration timeout = const Duration(minutes: 2),
  Future<void> Function(Duration)? sleep,
  bool Function()? cancelled,
}) async {
  final wait = sleep ?? (d) => Future<void>.delayed(d);
  var waited = Duration.zero;
  StoreOrder? last;
  while (true) {
    if (cancelled?.call() == true) return last;
    try {
      last = await fetch();
      if (last.done) return last;
    } catch (_) {}
    if (waited >= timeout) return last;
    await wait(every);
    waited += every;
  }
}

/// The `store_order` of the payment page's return (`…/#/payment/callback?status=paid&store_order=12`).
int? storeOrderIdFrom(Uri url) {
  final frag = url.fragment;
  if (frag.contains('?')) {
    final v = Uri.splitQueryString(frag.substring(frag.indexOf('?') + 1))['store_order'];
    if (v != null) return int.tryParse(v);
  }
  return int.tryParse(url.queryParameters['store_order'] ?? '');
}
