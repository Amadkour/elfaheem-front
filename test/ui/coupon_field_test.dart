// Games v3 CouponField (CONTRACT §7): the controller's states, the device-side refusals, and the bilingual text of
// every coupon_* code the quote and the three checkouts answer.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/features/rewards/coupon_field.dart';
import 'package:flutter_education_app/features/rewards/rewards_models.dart';
import 'package:flutter_test/flutter_test.dart';

CouponQuote _quote(String code, {double discount = 120}) => CouponQuote.fromJson({
      'coupon': {'id': 9, 'code': code, 'status': 'active', 'kind': 'percent', 'value': 30.0},
      'currency': 'EGP',
      'price': 400.0,
      'discount': discount,
      'price_after': 400.0 - discount,
    });

ApiException _err(int status, String code, [Map<String, dynamic> extra = const {}]) => ApiException(
      statusCode: status,
      message: 'server text',
      code: code,
      body: {
        'detail': {'code': code, 'message': 'server text', ...extra}
      },
    );

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('an empty or misshapen code is refused on the device, no request', () async {
    var calls = 0;
    final c = CouponFieldController(quote: (_) async {
      calls++;
      return _quote('K7M2PQ4XTH');
    });
    await c.open();
    expect(c.phase, CouponPhase.open);
    expect(await c.apply('   '), isFalse);
    expect(c.phase, CouponPhase.error);
    expect(c.error, contains('Type a coupon code'));
    expect(await c.apply('ABC'), isFalse);
    expect(c.error, contains('10 English letters'));
    // I and O and 0 / 1 are not in the code alphabet (no look-alikes)
    expect(await c.apply('K7M2PQ4XTI'), isFalse);
    expect(calls, 0);
  });

  test('a good code is normalised, quoted once, applied and handed to the checkout', () async {
    final sent = <String>[];
    final changes = <CouponQuote?>[];
    final c = CouponFieldController(
      quote: (code) async {
        sent.add(code);
        return _quote(code);
      },
      onChanged: changes.add,
    );
    expect(await c.apply(' k7m2 pq4x th '), isTrue);
    expect(sent, ['K7M2PQ4XTH']);
    expect(c.phase, CouponPhase.applied);
    expect(c.appliedCode, 'K7M2PQ4XTH');
    expect(c.quote!.discount, 120);
    expect(changes.single!.coupon.code, 'K7M2PQ4XTH');

    c.remove();
    expect(c.phase, CouponPhase.open);
    expect(c.appliedCode, isNull);
    expect(changes.length, 2);
    expect(changes.last, isNull);
  });

  test('a refusal shows its bilingual text and takes an applied coupon off', () async {
    var fail = false;
    final changes = <CouponQuote?>[];
    final c = CouponFieldController(
      quote: (code) async {
        if (fail) throw _err(409, 'coupon_used');
        return _quote(code);
      },
      onChanged: changes.add,
    );
    await c.apply('K7M2PQ4XTH');
    fail = true;
    // the plan changed: the same code is checked again, and now it was used elsewhere
    await c.retarget((code) async => throw _err(409, 'coupon_used'));
    expect(c.phase, CouponPhase.error);
    expect(c.error, 'This coupon was already used — each coupon works once');
    expect(changes.last, isNull);
    AppConfig.lang = 'ar';
    await c.apply('K7M2PQ4XTH');
    expect(c.error, contains('استُخدمت هذه القسيمة'));
  });

  test('a slower first answer never overwrites a later one', () async {
    final c = CouponFieldController(quote: (code) async {
      if (code == 'AAAAAAAAAA') {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _quote(code, discount: 1);
      }
      return _quote(code, discount: 2);
    });
    final first = c.apply('AAAAAAAAAA');
    await c.apply('BBBBBBBBBB');
    await first;
    expect(c.quote!.discount, 2);
    expect(c.appliedCode, 'BBBBBBBBBB');
  });

  test('my coupons: only usable ones are offered, a failed load is just an empty list', () async {
    final now = DateTime.now().toUtc();
    final c = CouponFieldController(
      quote: (code) async => _quote(code),
      mine: () async => [
        Coupon(id: 1, code: 'AAAAAAAAAA', expiresAt: now.add(const Duration(days: 3))),
        Coupon(id: 2, code: 'BBBBBBBBBB', status: 'redeemed'),
        Coupon(id: 3, code: 'CCCCCCCCCC', expiresAt: now.subtract(const Duration(days: 1))),
      ],
    );
    await c.open();
    expect([for (final m in c.mine) m.id], [1]);
    final broken = CouponFieldController(quote: (code) async => _quote(code), mine: () async => throw _err(500, 'x'));
    await broken.open();
    expect(broken.mine, isEmpty);
    expect(broken.phase, CouponPhase.open);
  });

  test('every coupon code has an Arabic and an English sentence', () {
    const codes = [
      'coupon_not_found',
      'coupon_not_yours',
      'coupon_used',
      'coupon_expired',
      'coupon_revoked',
      'coupon_not_applicable',
      'coupon_min_order',
      'coupon_currency',
    ];
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      final seen = <String>{};
      for (final code in codes) {
        final text = apiErrorText(_err(422, code));
        expect(text, isNot('server text'), reason: '$code ($lang)');
        expect(seen.add(text), isTrue, reason: '$code repeats another code\'s text ($lang)');
        expect(couponErrorText(code), text);
      }
    }
    AppConfig.lang = 'en';
    expect(apiErrorText(_err(422, 'coupon_min_order', {'min_order': 150.0})), contains('150'));
    expect(apiErrorText(_err(422, 'coupon_currency', {'expected': 'SAR'})), contains('SAR'));
    expect(couponErrorText('game_not_found'), isNull);
  });

  test('coupon sections: active, used, expired (revoked joins expired)', () {
    final now = DateTime.utc(2026, 11, 22, 12);
    expect(Coupon(id: 1, code: 'x', expiresAt: now.add(const Duration(hours: 1))).sectionAt(now), 'active');
    expect(Coupon(id: 1, code: 'x', expiresAt: now.subtract(const Duration(hours: 1))).sectionAt(now), 'expired');
    expect(const Coupon(id: 1, code: 'x', status: 'reserved').sectionAt(now), 'used');
    expect(const Coupon(id: 1, code: 'x', status: 'redeemed').sectionAt(now), 'used');
    expect(const Coupon(id: 1, code: 'x', status: 'revoked').sectionAt(now), 'expired');
  });
}
