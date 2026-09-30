/// teacher_transfers_provider.dart — teacher's review queue for
/// bank-transfer / InstaPay proofs.
///
///   GET  /api/v1/payments/transfers/pending
///   POST /api/v1/payments/transfers/{id}/approve
///   POST /api/v1/payments/transfers/{id}/reject
library;

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../student/enrollment/enrollment_models.dart';

class TeacherTransfersProvider extends BaseProvider {
  TeacherTransfersProvider({ApiClient? api}) : api = api ?? ApiClient();
  final ApiClient api;

  List<PendingTransfer> _items = [];
  int _total = 0;
  final Set<int> _processing = {};

  /// True once the first load finished successfully. The screen shows a
  /// loader (or an error + retry) until then, never a false "empty" state.
  bool hasLoaded = false;

  List<PendingTransfer> get items => _items;
  int get total => _total;
  bool isProcessing(int paymentId) => _processing.contains(paymentId);

  Future<void> load() async {
    final json = asJsonMap(await run(() async => api.get('/api/v1/payments/transfers/pending')));
    if (json == null) return;
    _items = [
      for (final raw in (json['items'] as List? ?? const []))
        PendingTransfer.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];
    _total = (json['total'] as num?)?.toInt() ?? _items.length;
    hasLoaded = true;
    notifyListeners();
  }

  Future<bool> approve(int paymentId) async {
    _processing.add(paymentId);
    notifyListeners();
    final ok = await run(() async => api.post('/api/v1/payments/transfers/$paymentId/approve')) != null;
    _processing.remove(paymentId);
    if (ok) _items.removeWhere((t) => t.paymentId == paymentId);
    notifyListeners();
    return ok;
  }

  Future<bool> reject(int paymentId, String reason) async {
    _processing.add(paymentId);
    notifyListeners();
    final ok = await run(() async => api.post(
      '/api/v1/payments/transfers/$paymentId/reject',
      body: {'rejection_reason': reason},
    )) != null;
    _processing.remove(paymentId);
    if (ok) _items.removeWhere((t) => t.paymentId == paymentId);
    notifyListeners();
    return ok;
  }
}