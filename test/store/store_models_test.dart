// The digital store's wire shapes (D-1333): the item, quote and order JSON of ../back/FLUTTER_API_CHANGES.md
// "Learning Hub phase 5", the download link, the payment return and the server codes' texts.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/store/store_api.dart';
import 'package:flutter_education_app/features/store/store_models.dart';
import 'package:flutter_test/flutter_test.dart';

const itemJson = {
  'id': 7,
  'kind': 'ebook',
  'title_ar': 'ملخص الفيزياء',
  'title_en': 'Physics summary',
  'cover_url': 'https://cdn.example/c.png',
  'price': {'net': 100.0, 'vat': 15.0, 'gross': 115.0, 'currency': 'SAR', 'vat_percent': 15.0, 'includes_vat': false},
  'points_price': 300,
  'stage_id': 2,
  'grade_id': 11,
  'subject_id': 4,
  'category_id': 9,
  'pages': 42,
  'country_code': 'SA',
  'owned': false,
  'description_ar': 'وصف',
  'description_en': 'About it',
  'file_name': 'physics.pdf',
  'file_size': 2048000,
  'currency': 'SAR',
  'preview_url': 'https://cdn.example/p.pdf?sig=1',
};

const quoteJson = {
  'lines': [
    {'item_id': 7, 'title': 'Physics summary', 'vat_exempt': false, 'net': 100.0, 'vat': 15.0, 'gross': 115.0},
    {'item_id': 8, 'title': 'Book', 'vat_exempt': true, 'net': 50.0, 'vat': 0.0, 'gross': 50.0},
  ],
  'subtotal': 150.0,
  'vat_amount': 15.0,
  'total': 165.0,
  'currency': 'SAR',
  'vat_percent': 15.0,
  'includes_vat': false,
  'points_total': null,
};

const orderJson = {
  'order': {
    'id': 12,
    'status': 'pending',
    'method': 'card',
    'provider': 'moyasar',
    'currency': 'SAR',
    'country_code': 'SA',
    'subtotal': 100.0,
    'vat_percent': 15.0,
    'vat_amount': 15.0,
    'total': 115.0,
    'points_spent': null,
    'failure_reason': null,
    'created_at': '2026-11-20T10:00:00',
    'paid_at': null,
    'items': [
      {'item_id': 7, 'title': 'Physics summary', 'unit_net': 100.0, 'unit_vat': 15.0, 'unit_gross': 115.0},
    ],
  },
  'checkout': {
    'url': 'https://alfheemacademy.com/api/api/v1/store/checkout/pay?token=abc',
    'token': 'abc',
    'provider': 'moyasar',
    'amount_minor': 11500,
    'is_sandbox': true,
  },
};

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('item: card + page fields', () {
    final i = StoreItem.fromJson(Map<String, dynamic>.from(itemJson));
    expect(i.id, 7);
    expect(i.title, 'Physics summary');
    expect(i.price.net, 100);
    expect(i.price.vat, 15);
    expect(i.price.gross, 115);
    expect(i.price.currency, 'SAR');
    expect(i.price.vatPercentText, '15 %');
    expect(i.pointsPrice, 300);
    expect(i.categoryId, 9);
    expect(i.pages, 42);
    expect(i.owned, isFalse);
    expect(i.fileSize, 2048000);
    expect(i.previewIsImage, isFalse);
    expect(storeMoney(i.price.gross, i.price.currency), '115.00 SAR');
    AppConfig.lang = 'ar';
    expect(i.title, 'ملخص الفيزياء');
  });

  test('browse list', () {
    final l = StoreItemList.fromJson({
      'items': [itemJson],
      'total': 30,
      'has_more': true,
    });
    expect(l.items.single.id, 7);
    expect(l.total, 30);
    expect(l.hasMore, isTrue);
  });

  test('quote: lines and sums; no points total', () {
    final q = StoreQuote.fromJson(quoteJson);
    expect(q.lines, hasLength(2));
    expect(q.lines[1].vatExempt, isTrue);
    expect(q.subtotal, 150);
    expect(q.vatAmount, 15);
    expect(q.total, 165);
    expect(q.pointsTotal, isNull);
    expect(q.isFree, isFalse);
  });

  test('order + checkout; settled only when not pending', () {
    final a = StoreOrderAnswer.fromJson(orderJson);
    expect(a.order.id, 12);
    expect(a.order.status, StoreOrderStatus.pending);
    expect(a.order.done, isFalse);
    expect(a.order.createdAt, DateTime.utc(2026, 11, 20, 10));
    expect(a.order.items.single.unitGross, 115);
    expect(a.checkout!.canOpen, isTrue);
    expect(a.checkout!.amountMinor, 11500);
    final paid = StoreOrderAnswer.fromJson({
      'order': {...orderJson['order']! as Map, 'status': 'paid', 'method': 'points', 'points_spent': 300},
      'checkout': null,
    });
    expect(paid.order.paid, isTrue);
    expect(paid.order.pointsSpent, 300);
    expect(paid.checkout, isNull);
  });

  test('download link under the API base; payment return carries the order', () {
    final d = StoreDownload.fromJson({'url': '/api/v1/store/dl/tok', 'expires_in': 120, 'sha256': 'ab'});
    expect(d.absolute('https://alfheemacademy.com/api').toString(), 'https://alfheemacademy.com/api/api/v1/store/dl/tok');
    expect(StoreDownload.fromJson({'url': 'https://x.example/dl/t'}).absolute().toString(), 'https://x.example/dl/t');
    expect(storeOrderIdFrom(Uri.parse('https://alfheemacademy.com/app/#/payment/callback?status=paid&store_order=12')), 12);
    expect(storeOrderIdFrom(Uri.parse('https://alfheemacademy.com/app/payment/callback?status=paid&store_order=5')), 5);
  });

  test('poll waits until settled', () async {
    var n = 0;
    final o = await pollStoreOrder(() async {
      n++;
      return StoreOrder.fromJson({...orderJson['order']! as Map, 'status': n < 3 ? 'pending' : 'paid'});
    }, sleep: (_) async {});
    expect(o!.paid, isTrue);
    expect(n, 3);
  });

  test('store codes have both languages', () {
    for (final code in ['store_already_owned', 'gateway_error', 'store_download_limit', 'points_insufficient', 'store_mixed_currency']) {
      AppConfig.lang = 'en';
      final en = storeCodeText(code);
      AppConfig.lang = 'ar';
      final ar = storeCodeText(code);
      expect(en, isNotNull, reason: code);
      expect(ar, isNot(en), reason: code);
    }
    AppConfig.lang = 'en';
    expect(storeCodeText('store_bad_currency', {'allowed': ['SAR', 'EGP']}), contains('SAR, EGP'));
    expect(newIdempotencyKey(), matches(RegExp(r'^[A-Za-z0-9_.:-]{8,64}$')));
  });
}
