// lib/features/games/champions/champions_api.dart — the Hall of Champions' calls (Games v3, CONTRACT §6). Every path
// is a literal `/api/v1/…` (test/contract/ checks each against the server's routes).
//
//   GET /api/v1/games/champions/standings ?scope&key&period   the running period: top 20, my row, the minimums
//   GET /api/v1/games/champions           ?scope&key&period&page   past winners, newest first, + the scope chips
//
// The strip on the Games tab reads the `champions` block of GET /api/v1/games, and the home line the `champion`
// block of GET /api/v1/me/home: neither makes a request of its own.
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/champions/champions_models.dart';
import 'package:flutter_education_app/features/games/games_api.dart' show gamesErrorText;

/// A champions code's bilingual text (null = not one of them).
String? championsCodeText(String? code) => switch (code) {
      'champions_bad_scope' || 'champions_bad_period' =>
        t('تعذّر فتح هذه اللوحة. اختر نطاقاً آخر.', 'This board could not be opened. Pick another scope.'),
      'not_a_member' => t('هذه اللوحة لأعضاء مؤسسة أخرى', 'This board belongs to another organization'),
      _ => null,
    };

String championsErrorText(Object e) => championsCodeText(ApiException.from(e).code) ?? gamesErrorText(e);

class ChampionsApi {
  ChampionsApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Map<String, dynamic> _q(ChampionScope s, String period) => {
        'scope': s.scope,
        'key': ?s.key,
        'period': period,
      };

  Future<ChampionStandings> standings(ChampionScope scope, {String period = 'daily'}) async =>
      ChampionStandings.fromJson(await _api.get('/api/v1/games/champions/standings', queryParams: _q(scope, period)));

  Future<ChampionHistory> history(ChampionScope scope, {String period = 'daily', int page = 1}) async =>
      ChampionHistory.fromJson(
          await _api.get('/api/v1/games/champions', queryParams: {..._q(scope, period), 'page': page}));
}
