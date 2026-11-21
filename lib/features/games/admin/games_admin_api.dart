// lib/features/games/admin/games_admin_api.dart — the super admin's game calls (Learning Hub v2 §3, D-1589). Every
// path is a literal `/api/v1/…` (test/contract/ checks each against the server's routes). Kill switch `admin.games`.
//
//   GET    /api/v1/admin/games?status&skip&limit      {items: [game + config, status, sort …], total, has_more}
//   POST   /api/v1/admin/games                        {key, engine, title_ar, title_en, config, category, difficulty,
//                                                     level, theme, points_reward, cover_url, status} → the game
//   GET | PATCH | DELETE /api/v1/admin/games/{id}    (DELETE of a played game hides it: {deleted, hidden})
//   POST   /api/v1/admin/games/reorder               {ids: [int]}
//   GET    /api/v1/admin/games/engines               [{key, name_ar, name_en, schema}]
//   POST   /api/v1/admin/games/{id}/cover            multipart `file` → {cover_url} (not in the contract yet: see
//                                                     test/contract knownMissing and the contract's Requests)
//
// The on / off of a game is its status, published ↔ hidden (CONTRACT C10). Server codes: 400 bad_game_config
// {field} · 422 game_bad_key | game_bad_engine | game_bad_status | game_bad_config | game_bad_title · 409
// game_key_taken · 404 game_not_found · 403 admin_required | feature_disabled.
library;

import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/games_api.dart' show gamesErrorText;
import 'package:flutter_education_app/features/games/games_models.dart';

const String kGamesAdminFeatureKey = 'admin.games';

bool gamesAdminOff() => AppConfig.disableList.contains(kGamesAdminFeatureKey);

/// One engine the server knows (`/admin/games/engines`).
typedef GameAdminEngine = ({String key, String nameAr, String nameEn});

/// A failed admin call's text: the config check names its field.
String gamesAdminErrorText(Object e) {
  final x = ApiException.from(e);
  switch (x.code) {
    case 'bad_game_config':
    case 'game_bad_config':
      final raw = x.body;
      final detail = raw is Map ? (raw['detail'] is Map ? raw['detail'] : raw) : null;
      final field = detail is Map ? '${detail['field'] ?? ''}' : '';
      return field.isEmpty
          ? t('محتوى اللعبة غير صالح', 'The game\'s content is not valid')
          : t('محتوى اللعبة غير صالح ($field)', 'The game\'s content is not valid ($field)');
    case 'game_key_taken':
      return t('هذا المعرّف مستخدم للعبة أخرى', 'Another game already uses this key');
    case 'game_bad_key':
      return t('المعرّف حروف إنجليزية صغيرة وأرقام وشرطات', 'The key is lower-case letters, digits and dashes');
    case 'game_bad_title':
      return t('اكتب عنوان اللعبة', 'Write the game\'s title');
  }
  return gamesErrorText(e);
}

class GamesAdminApi {
  GamesAdminApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<List<GameSummary>> games() async {
    final r = await _api.get('/api/v1/admin/games', queryParams: {'limit': 200});
    final list = GameList.fromJson(r).items;
    return [...list]..sort((a, b) => a.sort.compareTo(b.sort));
  }

  Future<GameSummary> game(int id) async {
    final r = await _api.get('/api/v1/admin/games/$id');
    return GameSummary.fromJson(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  Future<GameSummary> create(Map<String, dynamic> body) async {
    final r = await _api.post('/api/v1/admin/games', body: body);
    return GameSummary.fromJson(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  Future<GameSummary> update(int id, Map<String, dynamic> body) async {
    final r = await _api.patch('/api/v1/admin/games/$id', body: body);
    return GameSummary.fromJson(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  /// True = deleted; false = it had plays, so the server hid it.
  Future<bool> delete(int id) async {
    final r = await _api.delete('/api/v1/admin/games/$id');
    return !(r is Map && r['hidden'] == true);
  }

  Future<void> reorder(List<int> ids) => _api.post('/api/v1/admin/games/reorder', body: {'ids': ids});

  /// The server's engines; null when the route is not there yet (an older server): the editor uses its own list.
  Future<List<GameAdminEngine>?> engines() async {
    try {
      final r = await _api.get('/api/v1/admin/games/engines');
      final raw = r is Map ? r['items'] : r;
      if (raw is! List) return null;
      return [
        for (final e in raw)
          if (e is Map && '${e['key'] ?? ''}'.isNotEmpty)
            (key: '${e['key']}', nameAr: '${e['name_ar'] ?? ''}', nameEn: '${e['name_en'] ?? ''}'),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<String?> uploadCover(int id, Uint8List bytes, String fileName) async {
    final r = await _api.postMultipart('/api/v1/admin/games/$id/cover',
        fields: const {}, fileField: 'file', fileName: fileName, fileBytes: bytes);
    final url = r is Map ? '${r['cover_url'] ?? ''}' : '';
    return url.isEmpty ? null : url;
  }
}
