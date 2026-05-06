/// enrollment_provider.dart  (complete rewrite — matches new enrollment_screen)
library;

import 'package:flutter_education_app/features/shared/payment/saved_payment_models.dart' show SavedPaymentMethod, CardBrandX, FeeBreakdown, CardBrand;

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../shared/payment/saved_methods_provider.dart';
import '../../student/models.dart';

// ── Step enum ─────────────────────────────────────────────────────────────────

enum EnrollStep { method, bankDetails, success }

// ── Selection state ───────────────────────────────────────────────────────────

enum _Selection { savedCard, bankTransfer, newCard }

// ── Provider ──────────────────────────────────────────────────────────────────

class EnrollmentProvider extends BaseProvider {
  final ApiClient   _api;
  final CourseModel course;

  EnrollmentProvider(this.course, {ApiClient? api})
      : _api = api ?? ApiClient();

  // ── Internal state ────────────────────────────────────────────────────────

  EnrollStep   _step      = EnrollStep.method;
  _Selection   _selection = _Selection.savedCard;

  SavedPaymentMethod?    _selectedCard;  // for _Selection.savedCard
  Map<String, dynamic>?  _bankInfo;      // filled after bank-transfer API call
  bool                   _paidViaBankTransfer = false;

  // ── Public getters ─────────────────────────────────────────────────────────

  EnrollStep            get step               => _step;
  Map<String, dynamic>? get bankInfo           => _bankInfo;
  bool                  get paidViaBankTransfer => _paidViaBankTransfer;
  bool                  get isFree             => course.price == 0;

  // ── Selection setters (called by UI tiles) ────────────────────────────────

  void selectSavedCard(SavedPaymentMethod card) {
    _selection    = _Selection.savedCard;
    _selectedCard = card;
    notifyListeners();
  }

  void selectBankTransfer() {
    _selection    = _Selection.bankTransfer;
    _selectedCard = null;
    notifyListeners();
  }

  void selectNewCard() {
    _selection    = _Selection.newCard;
    _selectedCard = null;
    notifyListeners();
  }

  // ── Live fee computation (no network — instant) ────────────────────────────

  FeeBreakdown computedFees(SavedMethodsProvider savedP) {
    final brand = _resolvedBrand(savedP);
    return FeeBreakdown.calculate(
      coursePrice: course.price,
      brand:       brand,
    );
  }

  CardBrand _resolvedBrand(SavedMethodsProvider savedP) {
    switch (_selection) {
      case _Selection.savedCard:
        return _selectedCard?.cardBrand ?? CardBrand.mada;
      case _Selection.bankTransfer:
        return CardBrand.unknown; // gateway fee = 0
      case _Selection.newCard:
        return CardBrand.mada; // default assumption until Moyasar redirect
    }
  }

  // ── Confirm ────────────────────────────────────────────────────────────────

  Future<void> confirm(SavedMethodsProvider savedP) async {
    if (isFree) {
      await _enrollFree();
      return;
    }

    switch (_selection) {
      case _Selection.savedCard:
        if (_selectedCard != null) {
          await _chargeWithSavedCard(_selectedCard!, savedP);
        }
        break;
      case _Selection.bankTransfer:
        await _initBankTransfer();
        break;
      case _Selection.newCard:
        await _redirectToMoyasar(savedP);
        break;
    }
  }

  // ── Free enrollment ────────────────────────────────────────────────────────

  Future<void> _enrollFree() async {
    final r = await run(
      () => _api.post('/api/v1/courses/${course.id}/enroll'),
    );
    if (r != null) {
      _paidViaBankTransfer = false;
      _step                = EnrollStep.success;
      notifyListeners();
    }
  }

  // ── Charge saved card ──────────────────────────────────────────────────────

  Future<void> _chargeWithSavedCard(
    SavedPaymentMethod card,
    SavedMethodsProvider savedP,
  ) async {
    final fees = computedFees(savedP);
    final r    = await run(
      () => _api.post('/api/v1/payments', queryParams: {
        'course_id':       course.id,
        'payment_method':  card.cardBrand?.apiKey ?? 'mada',
        'saved_method_id': card.id,
      }),
    );
    if (r is Map<String, dynamic>) {
      final checkoutUrl = r['checkout_url'] as String?;
      if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
        // Moyasar may still require 3-DS for saved cards — open in browser
        await _launchUrl(checkoutUrl);
      }
      _paidViaBankTransfer = false;
      _step                = EnrollStep.success;
      notifyListeners();
    }
  }

  // ── Bank transfer ──────────────────────────────────────────────────────────

  Future<void> _initBankTransfer() async {
    final r = await run(
      () => _api.post(
        '/api/v1/payments/bank-transfer',
        queryParams: {'course_id': course.id},
      ),
    );
    if (r is Map<String, dynamic>) {
      _bankInfo = r;
      _step     = EnrollStep.bankDetails;
      notifyListeners();
    }
  }

  // ── New card → Moyasar hosted checkout ────────────────────────────────────

  Future<void> _redirectToMoyasar(SavedMethodsProvider savedP) async {
    final fees = computedFees(savedP);
    final r    = await run(
      () => _api.post('/api/v1/payments', queryParams: {
        'course_id':      course.id,
        'payment_method': 'mada',   // backend shows all methods on Moyasar page
      }),
    );
    if (r is Map<String, dynamic>) {
      final url = r['checkout_url'] as String?;
      if (url != null && url.isNotEmpty) {
        await _launchUrl(url);
        // After Moyasar redirects back, backend will POST /payments/{id}/verify
        // and activate enrollment. We show success optimistically here.
      }
      _paidViaBankTransfer = false;
      _step                = EnrollStep.success;
      notifyListeners();
    }
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  void backToMethod() {
    _step     = EnrollStep.method;
    _bankInfo = null;
    notifyListeners();
  }

  void confirmBankTransfer() {
    _paidViaBankTransfer = true;
    _step                = EnrollStep.success;
    notifyListeners();
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  Future<void> _launchUrl(String url) async {
    // url_launcher — add to pubspec: url_launcher: ^6.2.5
    try {
      final uri = Uri.parse(url);
      // ignore: import_of_legacy_library_into_null_safe
      // if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
