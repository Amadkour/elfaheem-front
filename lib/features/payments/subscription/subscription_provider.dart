// lib/features/subscription/subscription_provider.dart — student side of the paywall.
library;

import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
double _d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
int _i(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

class SubPlan {
  SubPlan(Map<String, dynamic> j)
      : code = '${j['code']}',
        nameAr = '${j['name_ar'] ?? ''}',
        nameEn = '${j['name_en'] ?? ''}',
        price = _d(j['price']),
        currency = '${j['currency'] ?? 'EGP'}',
        durationDays = _i(j['duration_days']);
  final String code, nameAr, nameEn, currency;
  final double price;
  final int durationDays;
  bool get isFree => price <= 0;
}

class SubscriptionProvider extends BaseProvider {
  final ApiClient _api = ApiClient();

  /// This person needs an active subscription (the organization's fee policy or the platform switch).
  bool required = false;
  bool hasAccess = true;

  /// The platform-wide switch (`platform_required`; an older server sends only `required`).
  bool platformRequired = false;

  /// Who asks for the subscription: 'organization' | 'platform' | null (older server: null).
  String? reason;

  /// The organization whose fee policy asks for it: id, name_ar, name_en, contact_email, contact_phone.
  Map<String, dynamic>? organization;
  bool loaded = false;
  String? error;
  Map<String, dynamic>? active;
  Map<String, dynamic>? pending;
  Map<String, dynamic>? last;
  List<SubPlan> plans = [];

  /// The charging organization's name in the current language ('' when none).
  String orgName(bool isAr) {
    final o = organization;
    if (o == null) return '';
    final ar = '${o['name_ar'] ?? ''}'.trim(), en = '${o['name_en'] ?? ''}'.trim();
    return isAr ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  }

  /// The charging organization's e-mail / phone, joined for display ('' when none).
  String orgContact() {
    final o = organization;
    if (o == null) return '';
    return [o['contact_email'], o['contact_phone']]
        .map((e) => '${e ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .join(' · ');
  }

  Map<String, dynamic> transfer = {};

  Future<void> load() async {
    final r = await run(() => _api.get('/api/v1/subscriptions/status'));
    if (r is Map) {
      final j = Map<String, dynamic>.from(r);
      required = j['required'] == true;
      hasAccess = j['has_access'] == true;
      platformRequired = j.containsKey('platform_required') ? j['platform_required'] == true : required;
      reason = j['reason'] is String ? j['reason'] as String : null;
      organization = j['organization'] is Map ? _m(j['organization']) : null;
      active = j['active'] is Map ? _m(j['active']) : null;
      pending = j['pending'] is Map ? _m(j['pending']) : null;
      last = j['last'] is Map ? _m(j['last']) : null;
      plans = (j['plans'] is List ? j['plans'] as List : const []).map((e) => SubPlan(_m(e))).toList();
      error = null;
    } else {
      error = errorMessage;
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> loadTransferDetails(String planCode) async {
    final r = await run(
        () => _api.get('/api/v1/subscriptions/transfer-details', queryParams: {'plan_code': planCode}),
        makLoading: false);
    if (r is Map) {
      transfer = Map<String, dynamic>.from(r);
      notifyListeners();
    }
  }

  /// Returns null on success, otherwise the error message to show.
  Future<String?> subscribe({
    required String planCode,
    String? method,
    String? senderName,
    String? senderPhone,
    String? reference,
    Uint8List? proofBytes,
    String? proofName,
  }) async {
    try {
      await _api.postForm(
        '/api/v1/subscriptions/subscribe',
        fields: {
          'plan_code': planCode,
          'method': method,
          'sender_name': senderName,
          'sender_phone': senderPhone,
          'transfer_reference': reference,
        },
        fileField: 'proof_image',
        fileName: proofName,
        fileBytes: proofBytes,
      );
      await load();
      return null;
    } catch (e) {
      return ApiException.from(e).message;
    }
  }
}
