/// saved_methods_provider.dart
library;


import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import 'saved_payment_models.dart';

class SavedMethodsProvider extends BaseProvider {
  final ApiClient _api;

  SavedMethodsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<SavedPaymentMethod> _methods = [];
  bool _fetched = false;

  List<SavedPaymentMethod> get methods  => List.unmodifiable(_methods);
  bool                     get fetched  => _fetched;

  List<SavedPaymentMethod> get cards =>
      _methods.where((m) => m.isCard).toList();

  List<SavedPaymentMethod> get bankAccounts =>
      _methods.where((m) => m.isBankAccount).toList();

  SavedPaymentMethod? get defaultCard =>
      cards.firstWhere((m) => m.isDefault, orElse: () => cards.isNotEmpty ? cards.first : throw StateError(''));

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> fetch({bool refresh = false}) async {
    if (_fetched && !refresh) return;
    final r = await run(() => _api.get('/api/v1/payment-methods'));
    if (r is List) {
      _methods = r
          .map((e) => SavedPaymentMethod.fromJson(e as Map<String, dynamic>))
          .toList();
      _fetched = true;
      notifyListeners();
    }
  }

  // ── Save card (from Moyasar callback) ─────────────────────────────────────

  Future<SavedPaymentMethod?> saveCard({
    required String token,
    required String customerId,
    required CardBrand brand,
    required String last4,
    required String expiryMonth,
    required String expiryYear,
    String?  holderName,
    bool     setAsDefault = false,
  }) async {
    final r = await run(() => _api.post('/api/v1/payment-methods/cards', body: {
      'moyasar_token':       token,
      'moyasar_customer_id': customerId,
      'card_brand':          brand.apiKey,
      'card_last4':          last4,
      'card_expiry_month':   expiryMonth,
      'card_expiry_year':    expiryYear,
      'card_holder_name': ?holderName,
      'set_as_default':      setAsDefault,
    }));
    if (r is Map<String, dynamic>) {
      final method = SavedPaymentMethod.fromJson(r);
      _methods = [method, ..._methods];
      if (setAsDefault) _refreshDefaults();
      notifyListeners();
      return method;
    }
    return null;
  }

  // ── Save bank account ──────────────────────────────────────────────────────

  Future<SavedPaymentMethod?> saveBankAccount({
    required String bankName,
    required String accountName,
    required String iban,
    String?  swiftCode,
    String?  accountNumber,
    bool     setAsDefault = false,
  }) async {
    final r = await run(() => _api.post('/api/v1/payment-methods/bank-accounts', body: {
      'bank_name':      bankName,
      'account_name':   accountName,
      'iban':           iban,
      'swift_code':     ?swiftCode,
      'account_number': ?accountNumber,
      'set_as_default': setAsDefault,
    }));
    if (r is Map<String, dynamic>) {
      final method = SavedPaymentMethod.fromJson(r);
      _methods = [method, ..._methods];
      if (setAsDefault) _refreshDefaults();
      notifyListeners();
      return method;
    }
    return null;
  }

  // ── Set default ────────────────────────────────────────────────────────────

  Future<void> setDefault(int methodId) async {
    final r = await run(() => _api.get('/api/v1/payment-methods/$methodId/set-default'));
    if (r != null) {
      final updated = SavedPaymentMethod.fromJson(r as Map<String, dynamic>);
      _methods = _methods.map((m) {
        if (m.type != updated.type) return m;
        return m.copyWith(isDefault: m.id == methodId);
      }).toList();
      notifyListeners();
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<bool> delete(int methodId) async {
    final r = await run(() => _api.delete('/api/v1/payment-methods/$methodId'));
    if (r != null || !hasError) {
      _methods.removeWhere((m) => m.id == methodId);
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Fee preview (local calc, instant) ─────────────────────────────────────

  FeeBreakdown previewFees(double coursePrice, CardBrand brand) =>
      FeeBreakdown.calculate(coursePrice: coursePrice, brand: brand);

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _refreshDefaults() {
    // Mirror what backend did — mark newest of each type as default
    bool seenCard = false, seenBank = false;
    _methods = _methods.map((m) {
      if (m.isCard && !seenCard) {
        seenCard = true;
        return m.copyWith(isDefault: true);
      }
      if (m.isBankAccount && !seenBank) {
        seenBank = true;
        return m.copyWith(isDefault: true);
      }
      return m.copyWith(isDefault: false);
    }).toList();
  }
}
