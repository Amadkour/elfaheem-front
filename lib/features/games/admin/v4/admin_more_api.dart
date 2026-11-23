// lib/features/games/admin/v4/admin_more_api.dart — the Games v4 admin calls of analytics, the seed console, cosmetics
// and the breaks settings (T70 / T71, CONTRACT §10). Plain maps in and out: the server validates. Paths are literal for
// test/contract/.
//
//   GET  /api/v1/admin/games/v4/analytics/overview?from&to          {plays, players, completion_pct, avg_score_pct, avg_ms, by_day, by_template}
//   GET  /api/v1/admin/games/v4/analytics/levels?from&to&sort       {items: [{game_id, title_ar, title_en, template, starts, finishes, completion_pct, avg_score_pct, avg_ms}]}
//   GET  /api/v1/admin/games/v4/analytics/items/hardest?limit       {items: [{id, type, prompt, subject, topic, shown, correct, correct_pct, avg_ms}]}
//   GET  /api/v1/admin/games/v4/seed · POST …/seed/run {subjects?, more?, levels?}
//   GET | POST /api/v1/admin/games/v4/cosmetics · PUT …/cosmetics/{key}
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart' show Json;

List<Json> _list(Object? r) => r is Map && r['items'] is List
    ? [for (final x in r['items'] as List) if (x is Map) Map<String, dynamic>.from(x)]
    : <Json>[];

Json _map(Object? r) => r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String adminMoreErrorText(Object e) {
  final x = ApiException.from(e);
  switch (x.code) {
    case 'cosmetic_key_taken':
      return t('هذا المفتاح مستخدم لعنصر آخر', 'Another item already uses this key');
    case 'bad_cosmetic':
      return t('بيانات العنصر غير صالحة، راجع الاسم والسعر', 'The item is not valid, check its name and price');
    case 'feature_disabled':
      return t('هذه الصفحة متوقفة حالياً', 'This page is switched off right now');
    case 'admin_required':
      return t('هذه الصفحة لمدير المنصة فقط', 'Only a platform admin can use this page');
  }
  return x.message.isNotEmpty ? x.message : t('تعذر الاتصال بالخادم', 'Could not reach the server');
}

class GamesAdminMoreApi {
  GamesAdminMoreApi({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  Map<String, dynamic> _range(int days) {
    final now = DateTime.now();
    return {'from': _day(now.subtract(Duration(days: days - 1))), 'to': _day(now)};
  }

  Future<Json> overview(int days) async => _map(await _api.get('/api/v1/admin/games/v4/analytics/overview', queryParams: _range(days)));

  Future<List<Json>> levels(int days, String sort) async =>
      _list(await _api.get('/api/v1/admin/games/v4/analytics/levels', queryParams: {..._range(days), 'sort': sort, 'limit': 50}));

  Future<List<Json>> hardest() async =>
      _list(await _api.get('/api/v1/admin/games/v4/analytics/items/hardest', queryParams: {'limit': 20}));

  Future<Json> seedStatus() async => _map(await _api.get('/api/v1/admin/games/v4/seed'));

  Future<Json> seedRun({List<String>? subjects, bool more = false}) async =>
      _map(await _api.post('/api/v1/admin/games/v4/seed/run', body: {'subjects': ?subjects, 'more': more, 'levels': true}));

  Future<List<Json>> cosmetics() async => _list(await _api.get('/api/v1/admin/games/v4/cosmetics'));

  Future<Json> createCosmetic(Json body) async => _map(await _api.post('/api/v1/admin/games/v4/cosmetics', body: body));

  Future<Json> updateCosmetic(String key, Json body) async => _map(await _api.put('/api/v1/admin/games/v4/cosmetics/$key', body: body));
}
