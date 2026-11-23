// lib/features/games/games_api.dart — the educational games' calls (Learning Hub Phase 6, D-1346; server D-1342).
// Every path is a literal `/api/v1/…` (test/contract/ checks each against the server's routes).
//
//   GET  /api/v1/games                          the list (optional auth): country · stage_id · grade_id · subject_id ·
//                                               category · difficulty (Learning Hub v2 §3)
//   GET  /api/v1/games/{id}                     one game with its `config`
//   POST /api/v1/games/{id}/rounds              Games v3: a ranked round → {round_id|null, issued_at, ranked_left}
//                                               (online only; any failure = the round is played unranked)
//   POST /api/v1/games/{id}/plays               {client_id, score, max_score, duration_s, played_at, round_id?,
//                                               trace?} → the play, progress, new badges, points (same client_id =
//                                               the first answer); Games v3: ranked, rank_points, rank_today
//   GET  /api/v1/games/{id}/leaderboard         ?period=week|all&page → {items: [{rank, first_name (+ last initial),
//                                               best_score, stars, duration_s}], me, visible} (CONTRACT C9: no avatar)
//   PUT  /api/v1/me/games/leaderboard           {visible} "Show me on leaderboards" (default visible; a hidden
//                                               student still sees their own rank). Kill switch `games.leaderboard`.
//   GET  /api/v1/me/games/progress              my games, every badge, totals
//
// Kill switches: `student_tab_games` (the tab and every games route), `games.rewards` (points for a play: the server
// decides, the app only shows what it paid).
//
// Offline (D-1351): the list and each opened game's `config` are kept in ReadCache and shown while offline; a play is
// an outbox op (`game_play`, its id = the `client_id`), so it is graded and shown on the device at once and the
// server's answer (points, badges, progress) replaces it when it arrives. Without an outbox (the web, `sync.offline`
// off) the play is posted to the route as before. A ranked play (it carries a round) is posted directly first: the
// outbox's sync route does not carry `round_id` / `trace`, so a ranked play the network lost is kept there unranked.
library;

import 'dart:async';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart';
import 'package:flutter_education_app/core/offline/sync/outbox.dart';
import 'package:flutter_education_app/core/offline/sync/sync_engine.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/learn_kit/learn_grading.dart';
import 'package:uuid/uuid.dart';

/// The games tab's kill switch (the server answers 403 `feature_disabled` too).
const String kGamesTabKey = 'student_tab_games';

bool gamesOff() => AppConfig.disableList.contains(kGamesTabKey);

/// The leaderboards' kill switch (CONTRACT C9): hides the section and the app bar's button.
const String kGamesLeaderboardFeatureKey = 'games.leaderboard';

bool gamesLeaderboardOff() => AppConfig.disableList.contains(kGamesLeaderboardFeatureKey);

/// The champions' kill switch (Games v3): off = no ranked rounds (every play is saved unranked).
const String kGamesChampionsFeatureKey = 'games.champions';

bool gamesChampionsOff() => AppConfig.disableList.contains(kGamesChampionsFeatureKey);

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

  Future<GameList> games(
      {String? country, int? stageId, int? gradeId, int? subjectId, String? category, String? difficulty}) async {
    final q = <String, dynamic>{
      if (country != null && country.isNotEmpty) 'country': country,
      'stage_id': ?stageId,
      'grade_id': ?gradeId,
      'subject_id': ?subjectId,
      'category': ?category,
      'difficulty': ?difficulty,
    };
    return GameList.fromJson(
        await readThrough('games.list?${Uri(queryParameters: {for (final e in q.entries) e.key: '${e.value}'}).query}',
            () => _api.get('/api/v1/games', queryParams: q)));
  }

  Future<GameSummary> game(int id) async {
    final r = await readThrough('games.game.$id', () => _api.get('/api/v1/games/$id'));
    return GameSummary.fromJson(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  /// A ranked round (Games v3, CONTRACT §2). Throws on any failure: the caller plays the round unranked.
  Future<GameRoundStart> startRound(int gameId) async =>
      GameRoundStart.fromJson(await _api.post('/api/v1/games/$gameId/rounds'));

  Future<GamePlayResult> play(int gameId,
          {required String clientId,
          required int score,
          required int maxScore,
          int? durationS,
          DateTime? playedAt,
          String? roundId,
          List<Map<String, Object>>? trace}) async =>
      GamePlayResult.fromJson(await _api.post('/api/v1/games/$gameId/plays', body: {
        'client_id': clientId,
        'score': score,
        'max_score': maxScore,
        'duration_s': ?durationS,
        'played_at': (playedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'round_id': ?roundId,
        if (roundId != null && trace != null) 'trace': trace,
      }));

  /// [period] `week` or `all`.
  Future<GameLeaderboard> leaderboard(int gameId, {String period = 'week', int page = 1}) async =>
      GameLeaderboard.fromJson(
          await _api.get('/api/v1/games/$gameId/leaderboard', queryParams: {'period': period, 'page': page}));

  /// "Show me on leaderboards" (CONTRACT C9).
  Future<void> setLeaderboardVisible(bool visible) async =>
      _api.put('/api/v1/me/games/leaderboard', body: {'visible': visible});

  Future<GamesReport> myProgress() async => GamesReport.fromJson(await _api.get('/api/v1/me/games/progress'));
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
    this.roundId,
    this.trace,
  })  : playedAt = playedAt ?? DateTime.now(),
        clientId = clientId ?? const Uuid().v4();

  final int gameId, score, maxScore;
  final int? durationS;
  final DateTime playedAt;
  final String clientId;

  /// A ranked round (Games v3): its id and the engine's trace (CONTRACT §3). Null = an unranked play.
  final String? roundId;
  final List<Map<String, Object>>? trace;

  /// A ranked play goes to the plays route first (the outbox's sync route drops the round).
  bool get ranked => roundId != null;

  GamePlayResult? result;

  /// The last failure's text (null = none).
  String? error;

  /// The server answered with an error (a status): retrying cannot help, the round must be played again.
  bool settledWithError = false;

  bool get done => result != null || settledWithError;

  /// Kept in the device's outbox (D-1351): the sync engine sends it, [settle] takes the answer, no retry here.
  bool queued = false;

  /// The op's payload (CONTRACT §7: `game_play`).
  Map<String, dynamic> get payload => {'game_id': gameId, 'score': score, 'max_score': maxScore, 'duration_s': ?durationS};

  /// Puts the play in the outbox; false = no outbox here (the web, `sync.offline` off): post it with [send].
  Future<bool> enqueue([Outbox? outbox]) async {
    final r = await (outbox ?? Outbox.instance).enqueue(
        id: clientId, kind: SyncKinds.gamePlay, payload: payload, clientTs: playedAt);
    return queued = r != EnqueueResult.postDirectly;
  }

  /// The outbox's answer for this play: the server's result (or the device's own when a duplicate came back without
  /// one), or the refusal.
  void settle(SyncResult r) {
    if (r.id != clientId) return;
    if (r.accepted) {
      result = r.entity != null
          ? GamePlayResult.fromJson(r.entity)
          : GamePlayResult(stars: learnStars(score, maxScore), score: score, maxScore: maxScore);
      error = null;
    } else if (r.rejected) {
      settledWithError = true;
      error = gamesCodeText(r.code) ?? syncRejectedText(r.code);
    }
  }

  /// Sends the play (again). Returns the answer, or null on a failure ([error] says why).
  Future<GamePlayResult?> send(GamesApi api) async {
    if (result != null) return result;
    try {
      result = await api.play(gameId,
          clientId: clientId,
          score: score,
          maxScore: maxScore,
          durationS: durationS,
          playedAt: playedAt,
          roundId: roundId,
          trace: trace);
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
