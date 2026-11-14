// 409 fee_already_paid / fee_under_review on POST /org/creation-fee/checkout and /transfer (A18): for a caller without
// an account the server sends the existing `payment` with `token: null`. A device that holds no fee token itself
// cannot use that payment, so the text must not say "you can send the request".
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/org_creation_fee.dart';
import 'package:flutter_education_app/features/org/org_v3.dart';
import 'package:flutter_test/flutter_test.dart';

OrgCall _fail(String code, Map<String, dynamic> extra) => OrgCall(
    null,
    ApiException(statusCode: 409, message: 'server text', code: code, body: {
      'detail': {'code': code, 'message': 'server text', ...extra}
    }));

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('anonymous payer on another device: say where the payment can be used', () {
    final paid = _fail('fee_already_paid', {'payment': {'id': 3, 'token': null, 'status': 'paid'}});
    final text = feeConflictText(paid, haveToken: false);
    expect(text, contains('another device'));
    expect(text, isNot(orgErrorText(paid.error!)));
    final review = _fail('fee_under_review', {'payment': {'id': 3, 'token': null, 'status': 'review'}});
    expect(feeConflictText(review, haveToken: false), contains('being reviewed'));
    AppConfig.lang = 'ar';
    expect(feeConflictText(paid, haveToken: false), contains('جهاز'));
  });

  test('a device that holds the token, a logged-in owner (token sent) or an older server keep the usual text', () {
    final paid = _fail('fee_already_paid', {'payment': {'id': 3, 'token': null}});
    expect(feeConflictText(paid, haveToken: true), orgErrorText(paid.error!));
    final own = _fail('fee_already_paid', {'payment': {'id': 3, 'token': 'tok'}});
    expect(feeConflictText(own, haveToken: false), orgErrorText(own.error!));
    final old = _fail('fee_already_paid', {});
    expect(feeConflictText(old, haveToken: false), orgErrorText(old.error!));
    final other = _fail('email_required', {});
    expect(feeConflictText(other, haveToken: false), orgErrorText(other.error!));
  });
}
