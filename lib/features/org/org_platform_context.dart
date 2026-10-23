// lib/features/org/org_platform_context.dart
//
// What changes while an organization is OPEN in the app:
//   • its timezone / 12h-24h override       → AppTime.configureOrg(...)   (cleared when it closes)
//   • features its admin switched off         → AppConfig.setOrgDisableList(...) (merged with the platform list;
//                                               super-admin OFF always wins, an org can only hide more)
// Source: GET /api/v1/org/orgs/{id}/context?platform=… (the server computes the effective values, including what
// parent organizations decided).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_time.dart';

String get _platform {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
}

class OrgPlatformContext {
  OrgPlatformContext._();

  static int? _openId;
  static int _seq = 0;

  /// The organization whose settings are applied right now (null = platform defaults).
  static int? get openId => _openId;

  /// Applies [orgId]'s settings. Safe to call repeatedly; a newer call wins over a slower older one.
  static Future<void> open(int? orgId) async {
    if (orgId == null) return close();
    if (!AppConfig.orgsEnabled) return close();
    if (_openId == orgId) return;
    _openId = orgId;
    final seq = ++_seq;
    try {
      final r = await ApiClient().get('/api/v1/org/orgs/$orgId/context', queryParams: {'platform': _platform});
      if (seq != _seq || _openId != orgId || r is! Map) return;
      AppTime.configureOrg(r['timezone'] as String?, r['time_format'] as String?);
      AppConfig.setOrgDisableList([for (final k in (r['org_disabled'] as List? ?? const [])) '$k']);
    } catch (e) {
      // older server / no access: keep the platform defaults — never block opening the organization
      debugPrint('[OrgPlatformContext] $orgId: $e');
      if (seq == _seq) _openId = null;
    }
  }

  /// Back to the platform defaults (leaving the organization, logging out, organizations switched off).
  static void close() {
    _seq++;
    if (_openId == null && AppConfig.orgDisableList.isEmpty) return;
    _openId = null;
    AppTime.configureOrg(null, null);
    AppConfig.setOrgDisableList(null);
  }

  /// Re-reads the open organization (after its admin changed region or features).
  static Future<void> refresh() async {
    final id = _openId;
    _openId = null;
    await open(id);
  }
}
