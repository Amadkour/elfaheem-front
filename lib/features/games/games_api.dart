// lib/features/games/games_api.dart — the educational games' calls (Learning Hub Phase 6, D-1346; server D-1342).
// Every path is a literal `/api/v1/…` (test/contract/ checks each against the server's routes).
//
//   GET  /api/v1/games                          the list (optional auth): country · stage_id · grade_id · subject_id
//   GET  /api/v1/games/{id}                     one game with its `config`
//   POST /api/v1/games/{id}/plays               {client_id, score, max_score, duration_s, played_at} → the play,
//                                               progress, new badges, points (same client_id = the first answer)
//   GET  /api/v1/me/games/progress              my games, every badge, totals
//   GET  /api/v1/parent/children/{id}/games     the same for a linked child (404 LINK_NOT_FOUND otherwise)
//
// Kill switches: `student_tab_games` (the tab and every games route), `games.rewards` (points for a play: the server
// decides, the app only shows what it paid).
library;

import 'dart:async';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:uuid/uuid.dart';

/// The games tab's kill switch (the server answers 403 `feature_disabled` too).
const String kGamesTabKey = 'student_tab_games';

bool gamesOff() => AppConfig.disableList.contains(kGamesTabKey);

/// A games code's bilingual text (null = not a games code).
String? gamesCodeText(String? code) => switch (code) {
      'game_not_found' => t('هذه اللعبة غير متاحة', 'This game is not available'),
      'game_bad_client_id' || 'game_bad_score' =>
        t('تعذّر حفظ هذه النتيجة. العب الجولة من جديد.', 'This result could not be saved. Play the round again.'),
      'LINK_NOT_FOUND' => t('هذا الطالب غير مرتبط بحسابك', 'This student is not linked to your account'),
      _ => null,
    };

/// What to show for a failed games call: the games' own text, else the app's (feature_disabled, network …).
String gamesErrorText(Object e) {
  if (e is TimeoutException) return ApiMessages.timeout;
  final x = ApiException.from(e);
  return gamesCodeText(x.code) ?? apiErrorText(x);
}

/// The server answered (a status), so the play is settled one way or the other: only then is its `client_id`
/// dropped. A timeout or a lost connection keeps it, so the retry is the SAME play and never counts twice.
bool gamesDefiniteAnswer(Object e) => e is ApiException && e.statusCode > 0;

class GamesApi {
  GamesApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<GameList> games({String? country, int? stageId, int? gradeId, int? subjectId}) async =>
      GameList.fromJson(await _api.get('/api/v1/games', queryParams: {
        if (country != null && country.isNotEmpty) 'country': country,
        'stage_id': ?stageId,
        'grade_id': ?gradeId,
        'subject_id': ?subjectId,
      }));

  Future<GameSummary> game(int id) async {
    final r = await _api.get('/api/v1/games/$id');
    return GameSummary.fromJson(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  Future<GamePlayResult> play(int gameId,
          {required String clientId, required int score, required int maxScore, int? durationS, DateTime? playedAt}) async =>
      GamePlayResult.fromJson(await _api.post('/api/v1/games/$gameId/plays', body: {
        'client_id': clientId,
        'score': score,
        'max_score': maxScore,
        'duration_s': ?durationS,
        'played_at': (playedAt ?? DateTime.now()).toUtc().toIso8601String(),
      }));

  Future<GamesReport> myProgress() async => GamesReport.fromJson(await _api.get('/api/v1/me/games/progress'));

  Future<GamesReport> childProgress(int studentId) async =>
      GamesReport.fromJson(await _api.get('/api/v1/parent/children/$studentId/games'));
}

/// One finished round waiting for the server. Its `client_id` (a UUID v4) is made once, when the round ends, and
/// kept until the server answers: a retry after a timeout sends the same id, so the server returns the first answer
/// (`duplicate: true`) instead of counting the play twice.
class GamePlaySubmission {
  GamePlaySubmission({
    required this.gameId,
    required this.score,
    required this.maxScore,
    this.durationS,
    DateTime? playedAt,
    String? clientId,
  })  : playedAt = playedAt ?? DateTime.now(),
        clientId = clientId ?? const Uuid().v4();

  final int gameId, score, maxScore;
  final int? durationS;
  final DateTime playedAt;
  final String clientId;

  GamePlayResult? result;

  /// The last failure's text (null = none).
  String? error;

  /// The server answered with an error (a status): retrying cannot help, the round must be played again.
  bool settledWithError = false;

  bool get done => result != null || settledWithError;

  /// Sends the play (again). Returns the answer, or null on a failure ([error] says why).
  Future<GamePlayResult?> send(GamesApi api) async {
    if (result != null) return result;
    try {
      result = await api.play(gameId,
          clientId: clientId, score: score, maxScore: maxScore, durationS: durationS, playedAt: playedAt);
      error = null;
      return result;
    } catch (e) {
      error = gamesErrorText(e);
      // a 4xx is final (a bad score, the game gone); a 5xx or a lost answer may be retried with the same id
      settledWithError = gamesDefiniteAnswer(e) && (e as ApiException).statusCode < 500;
      return null;
    }
  }
}

/// The games' name in the app's language (the parent's button).
String gamesLabel() => t('الألعاب', 'Games');
