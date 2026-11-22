// lib/features/org/workspace/ws_store.dart
//
// The teacher workspace's calls (docs/teacher-org/PLAN.md "API contract") and its per user + organization
// preferences on this device (D-1157: `org_ws.<user>.<org>` in SharedPreferences, one JSON value).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../org_providers.dart' show orgBase;
import '../org_v3.dart' show OrgCall, orgCall;
import 'ws_models.dart';

/// The workspace routes of one organization. Every method returns [OrgCall] (never throws); `quiet` loads leave
/// the error to the screen's own state.
class WsApi {
  WsApi(this.orgId);
  final int orgId;

  ApiClient get _api => ApiClient();
  String get base => '$orgBase/orgs/$orgId';
  String unitBase(int unitId) => '$base/my-workspace/units/$unitId';

  String _q(Map<String, String> q) => q.isEmpty ? '' : '?${Uri(queryParameters: q).query}';

  Future<(WsHome?, OrgCall)> home() async {
    final r = await orgCall(() => _api.get('$base/my-workspace'), quiet: true);
    return (r.ok ? WsHome.fromJson(r.map) : null, r);
  }

  Future<(WsPeoplePage?, OrgCall)> people(int unitId, WsPeopleFilter f, {int page = 1, int size = 30}) async {
    final r = await orgCall(() => _api.get('${unitBase(unitId)}/people${_q(f.query(page: page, size: size))}'), quiet: true);
    return (r.ok ? WsPeoplePage.fromJson(r.map) : null, r);
  }

  Future<(WsPersonDetail?, OrgCall)> person(int unitId, int userId, {String? cursor}) async {
    final q = cursor == null ? '' : _q({'cursor': cursor});
    final r = await orgCall(() => _api.get('${unitBase(unitId)}/people/$userId$q'), quiet: true);
    return (r.ok ? WsPersonDetail.fromJson(r.map) : null, r);
  }

  /// Removes [userIds] from the unit. The result's `removed` rows are what [restore] sends back (Undo).
  Future<OrgCall> remove(int unitId, List<int> userIds) =>
      orgCall(() => _api.post('${unitBase(unitId)}/people/bulk', body: {'op': 'remove', 'user_ids': userIds}));

  Future<OrgCall> restore(int unitId, List<Map<String, dynamic>> removed) =>
      orgCall(() => _api.post('${unitBase(unitId)}/people/bulk', body: {'op': 'restore', 'items': removed}));

  Future<(List<WsAlert>, WsAlertCounts, OrgCall)> alerts({String view = 'active'}) async {
    final r = await orgCall(() => _api.get('$base/my-alerts${_q({'view': view})}'), quiet: true);
    final m = r.map;
    final items = [for (final a in (m['items'] is List ? m['items'] as List : const [])) if (a is Map) WsAlert.fromJson(a.cast<String, dynamic>())];
    return (items, WsAlertCounts.fromJson(m['counts'] is Map ? (m['counts'] as Map).cast<String, dynamic>() : const {}), r);
  }

  /// [state]: read · unread · snooze (with [until]) · archive · restore.
  Future<OrgCall> setAlertState(List<String> keys, String state, {DateTime? until}) => orgCall(
        () => _api.post('$base/my-alerts/state', body: {
          'keys': keys,
          'state': state,
          if (until != null) 'until': until.toUtc().toIso8601String(),
        }),
        quiet: true,
      );
}

/// The workspace preferences of one user in one organization (D-1157). Writes are immediate and survive restarts.
class WsPrefsStore extends ChangeNotifier {
  WsPrefsStore(this.userId, this.orgId);

  final int? userId;
  final int orgId;

  static String keyFor(int? userId, int orgId) => 'org_ws.${userId ?? 0}.$orgId';

  WsPrefs _prefs = const WsPrefs();
  bool _loaded = false;

  WsPrefs get prefs => _prefs;
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(keyFor(userId, orgId));
      if (s != null && s.isNotEmpty) {
        final j = jsonDecode(s);
        if (j is Map) _prefs = WsPrefs.fromJson(j.cast<String, dynamic>());
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> update(WsPrefs Function(WsPrefs) change) async {
    final next = change(_prefs);
    _prefs = next;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(keyFor(userId, orgId), jsonEncode(next.toJson()));
    } catch (_) {}
  }
}
