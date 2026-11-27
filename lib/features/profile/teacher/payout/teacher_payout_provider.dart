// lib/features/teacher/payout/teacher_payout_provider.dart
//
//   GET    /api/v1/teacher/payout/status        allowed? methods · min amount · accounts · earnings summary
//   GET    /api/v1/teacher/payout/methods       the fields each method asks for in the teacher's country (WP8)
//   POST   /api/v1/teacher/payout/accounts      PUT/DELETE /accounts/{id} · POST /accounts/{id}/default
//   POST   /api/v1/payments/iban/check          {iban} → {valid, code, iban}: checked before an account is saved
//   GET    /api/v1/teacher/withdrawals          history
//   POST   /api/v1/teacher/withdrawals          {amount, payout_account_id, note}
//   DELETE /api/v1/teacher/withdrawals/{id}     cancel while pending
library;

import 'package:flutter_education_app/features/admin/admin_common.dart';
import 'package:flutter_education_app/features/admin/admin_models.dart';
import 'package:flutter_education_app/features/admin/admin_providers.dart' show AdminBase;

class PayoutMethodInfo {
  PayoutMethodInfo(this.j);
  final Map<String, dynamic> j;
  String get id => asStr(j['id']);
  String get label => t(asStr(j['label_ar']), asStr(j['label_en']));
  bool get automatic => asBool(j['automatic']);
  String? get currency => asStrOrNull(j['currency']);

  /// The fields this method asks for in the teacher's residence country (GET /payout/methods, WP8): an IBAN country
  /// asks for the IBAN, a country without one for the account number and SWIFT. Empty = the app's own field list.
  List<({String key, bool required})> get fields => [
        for (final f in asMapList(j['fields'])) (key: asStr(f['key']), required: asBool(f['required'])),
      ];
}

class PayoutAccount {
  PayoutAccount(this.j);
  final Map<String, dynamic> j;
  int get id => asInt(j['id']);
  String get method => asStr(j['method']);
  String? get label => asStrOrNull(j['label']);
  Map<String, dynamic> get details => asMap(j['details']);
  bool get isDefault => asBool(j['is_default']);
  bool get automatic => asBool(j['automatic']);
  String? get currency => asStrOrNull(j['currency']);
  String get summary => payoutDestinationSummary({'method': method, ...details});
}

class TeacherPayoutProvider extends AdminBase {
  bool loaded = false;
  String? error;
  bool allowed = false;
  double minAmount = 0;
  List<PayoutMethodInfo> methods = [];
  List<PayoutAccount> accounts = [];
  Map<String, dynamic> summary = {};
  List<Withdrawal> withdrawals = [];

  double get available => asDouble(summary['pending_balance']);
  double get withdrawn => asDouble(summary['withdrawn_total']);
  double get inFlight => asDouble(summary['pending_withdrawal']);
  double get totalNet => asDouble(summary['total_net']);
  bool get hasOpenRequest => withdrawals.any((w) => w.status == 'pending' || w.status == 'approved');

  Future<void> load() async {
    final st = await run(() => api.get('/api/v1/teacher/payout/status'));
    final hist = await run(() => api.get('/api/v1/teacher/withdrawals', queryParams: {'limit': 50}),
        makLoading: false);
    if (st is Map) {
      allowed = asBool(st['allowed']);
      minAmount = asDouble(st['min_amount']);
      methods = asMapList(st['methods']).map(PayoutMethodInfo.new).toList();
      accounts = asMapList(st['accounts']).map(PayoutAccount.new).toList();
      summary = asMap(st['summary']);
      error = null;
    } else {
      error = errorMessage ?? t('تعذر تحميل البيانات', 'Could not load data');
    }
    if (hist is Map) withdrawals = asMapList(hist['items']).map(Withdrawal.new).toList();
    // the per-country fields (WP8); an older server without the route keeps the app's own field lists
    final per = await run(() => api.get('/api/v1/teacher/payout/methods'), makLoading: false);
    if (per is Map && per['methods'] is List) {
      final byId = {for (final m in asMapList(per['methods'])) asStr(m['id']): m};
      methods = [for (final m in methods) PayoutMethodInfo({...m.j, ...?byId[m.id]})];
    }
    loaded = true;
    notifyListeners();
  }

  Future<bool> saveAccount({
    int? id,
    required String method,
    String? label,
    required Map<String, dynamic> details,
    bool makeDefault = false,
  }) async {
    final r = await call(
        () => id == null
            ? api.post('/api/v1/teacher/payout/accounts',
                body: {'method': method, 'label': label, 'details': details, 'make_default': makeDefault})
            : api.put('/api/v1/teacher/payout/accounts/$id', body: {'label': label, 'details': details}),
        ok: t('تم حفظ الحساب', 'Account saved'));
    if (r != null) await load();
    return r != null;
  }

  /// The server's IBAN check (any IBAN country, mod-97): `(iban: the cleaned IBAN, code: null)` when valid,
  /// `(iban: null, code: iban_format | iban_country | iban_length | iban_checksum)` when not, null when the check
  /// could not run (offline, an older server): the save goes on and the server checks again.
  Future<({String? iban, String? code})?> checkIban(String iban) async {
    try {
      final r = await api.post('/api/v1/payments/iban/check', body: {'iban': iban});
      if (r is! Map) return null;
      return r['valid'] == true ? (iban: asStr(r['iban'], iban), code: null) : (iban: null, code: asStr(r['code'], 'iban_format'));
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteAccount(int id) async {
    final r = await call(() => api.delete('/api/v1/teacher/payout/accounts/$id'),
        ok: t('تم حذف الحساب', 'Account removed'));
    if (r != null) await load();
    return r != null;
  }

  Future<bool> makeDefault(int id) async {
    final r = await call(() => api.post('/api/v1/teacher/payout/accounts/$id/default'));
    if (r != null) await load();
    return r != null;
  }

  Future<bool> requestWithdrawal(double amount, int accountId, String? note) async {
    final r = await call(
        () => api.post('/api/v1/teacher/withdrawals',
            body: {'amount': amount, 'payout_account_id': accountId, 'note': note}),
        ok: t('تم إرسال طلب السحب للمراجعة', 'Withdrawal request sent for review'));
    if (r != null) await load();
    return r != null;
  }

  /// Fresh signed link to the receipt the admin attached (the stored URL is private / expires).
  Future<Map<String, dynamic>?> receiptLink(int id) async {
    final r = await call(() => api.get('/api/v1/teacher/payout/withdrawals/$id/receipt-url'));
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<bool> cancelWithdrawal(int id) async {
    final r = await call(() => api.delete('/api/v1/teacher/withdrawals/$id'),
        ok: t('تم إلغاء الطلب', 'Request cancelled'));
    if (r != null) await load();
    return r != null;
  }
}
