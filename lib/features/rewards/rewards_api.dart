// lib/features/rewards/rewards_api.dart — the rewards calls of the app (Games v3, CONTRACT §7). Every path is a
// literal `/api/v1/…` (test/contract/ checks each against the server's routes).
//
//   GET  /api/v1/me/rewards       my coupons (active first), my wins, the invite link and its tiers, the share tiers;
//                                 it also marks my new coupons seen (the `rewards` badge drops)
//   POST /api/v1/coupons/quote    {code, target_type, target_id?, plan?, item_ids?} → the discount on this purchase,
//                                 or a coded refusal (`coupon_*`, texts in core/api_error_text.dart)
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/features/rewards/rewards_models.dart';

String rewardsErrorText(Object e) => apiErrorText(ApiException.from(e));

class RewardsApi {
  RewardsApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<MyRewards> mine() async => MyRewards.fromJson(await _api.get('/api/v1/me/rewards'));

  /// [targetId] for a course / package; [itemIds] for the store; [plan] for a course.
  Future<CouponQuote> quote(String code,
          {required CouponTarget target, int? targetId, String? plan, List<int>? itemIds}) async =>
      CouponQuote.fromJson(await _api.post('/api/v1/coupons/quote', body: {
        'code': normalizeCouponCode(code),
        'target_type': target.name,
        'target_id': ?targetId,
        'plan': ?plan,
        'item_ids': ?itemIds,
      }));
}
