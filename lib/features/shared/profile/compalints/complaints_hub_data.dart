// lib/features/shared/profile/compalints/complaints_hub_data.dart
//
// Loads and changes what the profile's Complaints page (D-086) shows. Two sources per list, fetched together; one
// that fails never empties the other (the page shows a banner for the part it could not read):
//
//   My complaints   GET /api/v1/complaints?scope=mine&per_page=100            platform complaints I filed
//                   GET /api/v1/org/public/me/complaints?size=50              complaints I filed in my organizations
//   To resolve      GET /api/v1/complaints?scope=to_resolve&per_page=100      platform complaints I handle
//                   GET /api/v1/org/public/me/complaints/to-resolve?status=all  organization complaints I handle
//
// An older server ignores `scope` (the rows are split by owner here as well) and answers the cross-organization
// route with FastAPI's bare 404 (that part is then simply empty). Quick status changes are optimistic and rolled
// back when the server refuses them.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import '../../../org/org_v3.dart' show orgEndpointMissing;
import 'complaint_model.dart';
import 'complaints_hub_model.dart';

class ComplaintsHubController extends ChangeNotifier {
  ComplaintsHubController({required this.myId, ApiClient? api, Map<int, HubName> orgNames = const {}, bool listen = true})
      : _api = api ?? ApiClient(),
        _orgNames = orgNames {
    if (listen) _sub = LiveEvents.instance.listen({LiveEvents.complaints}, (_) => refresh(quiet: true));
  }

  final int myId;
  final ApiClient _api;
  final Map<int, HubName> _orgNames;
  StreamSubscription<LiveEvent>? _sub;
  bool _disposed = false;

  List<HubRow> mine = const [];
  List<HubRow> toResolve = const [];
  bool loadingMine = true, loadingToResolve = true;

  /// A source could not be read (the other one may still have rows).
  bool mineFailed = false, toResolveFailed = false;

  static const _platform = '/api/v1/complaints';
  static const _orgMine = '/api/v1/org/public/me/complaints';
  static const _orgToResolve = '/api/v1/org/public/me/complaints/to-resolve';

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }

  Future<void> refresh({bool quiet = false, bool toResolveToo = true}) async {
    if (!quiet) {
      loadingMine = mine.isEmpty;
      loadingToResolve = toResolveToo && toResolve.isEmpty;
      notifyListeners();
    }
    await Future.wait([_loadMine(), if (toResolveToo) _loadToResolve()]);
  }

  Future<List<HubRow>?> _platformRows(String scope, {required bool mine}) async {
    try {
      final r = await _api.get(_platform, queryParams: {'scope': scope, 'per_page': 100});
      final items = r is Map ? (r['items'] as List? ?? const []) : const [];
      final models = [for (final j in items.whereType<Map>()) ComplaintModel.fromJson(Map<String, dynamic>.from(j))];
      return [
        for (final m in models)
          if ((m.userId == myId) == mine) HubRow.fromPlatform(m, mine: mine),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<List<HubRow>?> _orgRows(String path, Map<String, dynamic> query, {required bool mine}) async {
    if (!AppConfig.orgsEnabled) return const [];
    try {
      final r = await _api.get(path, queryParams: query);
      final items = r is Map ? (r['items'] as List? ?? const []) : const [];
      return [
        for (final j in items.whereType<Map>()) HubRow.fromOrg(Map<String, dynamic>.from(j), mine: mine, orgNames: _orgNames),
      ];
    } catch (e) {
      final ex = ApiException.from(e);
      // older server (no cross-organization route) · organizations switched off → nothing there, not an error
      final detail = ApiException.asMap(ex.body)?['detail'];
      final code = ex.code ?? (detail is Map ? '${detail['code']}' : null);
      return orgEndpointMissing(ex) || code == 'orgs_disabled' ? const [] : null;
    }
  }

  Future<void> _loadMine() async {
    final res = await Future.wait([
      _platformRows('mine', mine: true),
      _orgRows(_orgMine, {'size': 50}, mine: true),
    ]);
    mineFailed = res.any((r) => r == null);
    if (!(res[0] == null && res[1] == null && mine.isNotEmpty)) {
      mine = mergeRows(res[0] ?? const [], res[1] ?? const []);
    }
    loadingMine = false;
    notifyListeners();
  }

  Future<void> _loadToResolve() async {
    final res = await Future.wait([
      _platformRows('to_resolve', mine: false),
      _orgRows(_orgToResolve, {'status': 'all'}, mine: false),
    ]);
    toResolveFailed = res.any((r) => r == null);
    if (!(res[0] == null && res[1] == null && toResolve.isNotEmpty)) {
      toResolve = mergeRows(res[0] ?? const [], res[1] ?? const []);
    }
    loadingToResolve = false;
    notifyListeners();
  }

  /// Quick action (to resolve): move the complaint to [to]. Optimistic; false (and rolled back) when refused.
  Future<bool> setStatus(HubRow row, HubStatus to) async {
    final before = toResolve;
    toResolve = [for (final r in toResolve) r.key == row.key ? r.copyWith(status: to, unread: false, updatedAt: DateTime.now().toUtc()) : r];
    notifyListeners();
    try {
      if (row.source == HubSource.platform) {
        await _api.put('$_platform/${row.id}', body: {'status': to.wire});
      } else {
        await _api.put('/api/v1/org/orgs/${row.orgId}/complaints/${row.id}', body: {'status': to.wire});
      }
      return true;
    } catch (_) {
      toResolve = before;
      notifyListeners();
      return false;
    }
  }

  /// Opening a row marks it read on the server; show it read at once.
  void markRead(HubRow row) {
    List<HubRow> clear(List<HubRow> l) => [for (final r in l) r.key == row.key ? r.copyWith(unread: false) : r];
    mine = clear(mine);
    toResolve = clear(toResolve);
    notifyListeners();
  }
}
