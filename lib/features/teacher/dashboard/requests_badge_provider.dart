/// features/teacher/dashboard/requests_badge_provider.dart
/// Pending-request counts (payment transfers + device switches) for the
/// teacher dashboard badge.
library;

import 'package:flutter/foundation.dart';
import '../../../core/api_client.dart';

class RequestsBadgeProvider extends ChangeNotifier {
  RequestsBadgeProvider({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  int transfers = 0;
  int devices = 0;
  int get total => transfers + devices;

  bool _disposed = false;

  Future<void> refresh() async {
    final results = await Future.wait([
      _count('/api/v1/payments/transfers/pending', useTotal: true),
      _count('/api/v1/devices/teacher/switch-requests', auth: true),
    ]);
    if (_disposed) return;
    final changed = transfers != results[0] || devices != results[1];
    transfers = results[0];
    devices = results[1];
    if (changed) notifyListeners();
  }

  Future<int> _count(String path,
      {bool useTotal = false, bool auth = false}) async {
    try {
      final json =
          auth ? await _api.get(path, auth: true) : await _api.get(path);
      if (json is! Map) return 0;
      final items = json['items'] as List? ?? const [];
      if (useTotal) return (json['total'] as num?)?.toInt() ?? items.length;
      return items.length;
    } catch (_) {
      return 0; // the badge must never break the dashboard
    }
  }

  void clear() {
    transfers = 0;
    devices = 0;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
