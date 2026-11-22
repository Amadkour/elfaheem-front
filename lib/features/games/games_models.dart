// lib/features/games/games_models.dart — the educational games' payloads (D-1346, server CONTRACT §6, D-1342):
// the list, one game with its `config`, a play's answer, the progress report (student and parent), and since
// Learning Hub v2 (CONTRACT §3, D-1586) a game's category / difficulty / level / cover / theme and its leaderboard.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/learn_kit/learn_grading.dart';

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
int? _io(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String _s(Object? v) => v == null ? '' : '$v';
DateTime? _d(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v.endsWith('Z') || v.contains('+') ? v : '${v}Z') : null;
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e),
    ];

/// One person's standing in one game.
class GameProgress {
  const GameProgress({required this.gameId, this.bestScore = 0, this.stars = 0, this.plays = 0, this.lastPlayedAt});

  final int gameId, bestScore, stars, plays;
  final DateTime? lastPlayedAt;

  static GameProgress? maybe(Object? j) {
    if (j is! Map) return null;
    final m = Map<String, dynamic>.from(j);
    return GameProgress(
      gameId: _i(m['game_id']),
      bestScore: _i(m['best_score']),
      stars: _i(m['stars']),
      plays: _i(m['plays']),
      lastPlayedAt: _d(m['last_played_at']),
    );
  }
}

/// A game in the list (`GET /games`), or with its [config] (`GET /games/{id}`).
class GameSummary {
  const GameSummary({
    required this.id,
    required this.key,
    required this.engine,
    required this.titleAr,
    required this.titleEn,
    this.pointsReward = 0,
    this.stageId,
    this.gradeId,
    this.subjectId,
    this.progress,
    this.config = const {},
    this.category = '',
    this.difficulty = '',
    this.level,
    this.coverUrl,
    this.theme = 'sand',
    this.status = 'published',
    this.sort = 0,
  });

  final int id;
  final String key, engine, titleAr, titleEn;
  final int pointsReward;
  final int? stageId, gradeId, subjectId;
  final GameProgress? progress;

  /// The engine's content (empty in the list).
  final Map<String, dynamic> config;

  /// `quran | tajweed | fiqh | nahw | general` and `easy | medium | hard` ('' from an older server).
  final String category, difficulty;
  final String? level, coverUrl;

  /// `sand | sea | night | garden`.
  final String theme;

  /// `draft | published | hidden` (the admin list; the student list holds published games only). The editor's
  /// on / off is published ↔ hidden (CONTRACT C10: there is no `enabled` field).
  final String status;
  final int sort;

  bool get published => status == 'published';

  String get title => learnText(titleAr, titleEn);

  factory GameSummary.fromJson(Map<String, dynamic> j) => GameSummary(
        id: _i(j['id']),
        key: _s(j['key']),
        engine: _s(j['engine']),
        titleAr: _s(j['title_ar']),
        titleEn: _s(j['title_en']),
        pointsReward: _i(j['points_reward']),
        stageId: _io(j['stage_id']),
        gradeId: _io(j['grade_id']),
        subjectId: _io(j['subject_id']),
        progress: GameProgress.maybe(j['progress']),
        config: _m(j['config']),
        category: _s(j['category']),
        difficulty: _s(j['difficulty']),
        level: _s(j['level']).isEmpty ? null : _s(j['level']),
        coverUrl: _s(j['cover_url']).isEmpty ? null : _s(j['cover_url']),
        theme: _s(j['theme']).isEmpty ? 'sand' : _s(j['theme']),
        status: _s(j['status']).isEmpty ? 'published' : _s(j['status']),
        sort: _i(j['sort']),
      );

  GameSummary withProgress(GameProgress? p) => GameSummary(
        id: id,
        key: key,
        engine: engine,
        titleAr: titleAr,
        titleEn: titleEn,
        pointsReward: pointsReward,
        stageId: stageId,
        gradeId: gradeId,
        subjectId: subjectId,
        progress: p,
        config: config,
        category: category,
        difficulty: difficulty,
        level: level,
        coverUrl: coverUrl,
        theme: theme,
        status: status,
        sort: sort,
      );
}

/// The game categories (server enum).
const List<String> kGameCategories = ['quran', 'tajweed', 'fiqh', 'nahw', 'general'];

/// The difficulties (server enum).
const List<String> kGameDifficulties = ['easy', 'medium', 'hard'];

String gameCategoryName(String key) => switch (key) {
      'quran' => learnText('القرآن', 'Quran'),
      'tajweed' => learnText('التجويد', 'Tajweed'),
      'fiqh' => learnText('الفقه', 'Fiqh'),
      'nahw' => learnText('النحو', 'Grammar'),
      'general' => learnText('عام', 'General'),
      _ => key,
    };

String gameDifficultyName(String key) => switch (key) {
      'easy' => learnText('سهل', 'Easy'),
      'medium' => learnText('متوسط', 'Medium'),
      'hard' => learnText('صعب', 'Hard'),
      _ => key,
    };

/// One row of a game's leaderboard: the first name with the last initial, as the server sends it, and no avatar
/// (CONTRACT C9).
class GameLeaderRow {
  const GameLeaderRow({required this.rank, required this.name, this.bestScore = 0, this.stars = 0, this.durationS});

  final int rank, bestScore, stars;
  final String name;
  final int? durationS;

  static GameLeaderRow? maybe(Object? j) {
    if (j is! Map) return null;
    final m = Map<String, dynamic>.from(j);
    return GameLeaderRow(
      rank: _i(m['rank']),
      name: _s(m['name'] ?? m['first_name']),
      bestScore: _i(m['best_score']),
      stars: _i(m['stars']),
      durationS: _io(m['duration_s']),
    );
  }
}

/// `GET /games/{id}/leaderboard?period=week|all&page` → `{items, me, visible}` (me = null when the caller has not
/// played; visible = the caller's "Show me on leaderboards", true when the server does not say).
class GameLeaderboard {
  const GameLeaderboard({this.items = const [], this.me, this.visible = true});

  final List<GameLeaderRow> items;
  final GameLeaderRow? me;
  final bool visible;

  /// Whether [me] is already one of [items] (then it is marked there, not pinned again).
  bool get meListed => me != null && items.any((r) => r.rank == me!.rank && r.name == me!.name);

  factory GameLeaderboard.fromJson(Object? r) {
    final m = _m(r);
    return GameLeaderboard(
      items: [for (final e in _l(m['items'])) GameLeaderRow.maybe(e)!],
      me: GameLeaderRow.maybe(m['me']),
      visible: m['visible'] != false,
    );
  }
}

class GameList {
  const GameList({required this.items, this.total = 0, this.champions});

  final List<GameSummary> items;
  final int total;

  /// Games v3 (CONTRACT §6): the `champions` block for the strip, raw (ChampionsStripData.maybe); null = none.
  final Map<String, dynamic>? champions;

  factory GameList.fromJson(Object? r) {
    final m = _m(r);
    final items = [for (final e in _l(m['items'])) GameSummary.fromJson(e)];
    return GameList(
        items: items,
        total: m['total'] is num ? _i(m['total']) : items.length,
        champions: m['champions'] is Map ? _m(m['champions']) : null);
  }
}

/// A badge (`badges` row), earned or not.
class GameBadge {
  const GameBadge({required this.key, required this.nameAr, required this.nameEn, this.icon = '', this.rule = const {}, this.earnedAt});

  final String key, nameAr, nameEn, icon;
  final Map<String, dynamic> rule;
  final DateTime? earnedAt;

  bool get earned => earnedAt != null;
  String get name => learnText(nameAr, nameEn);
  IconData get iconData => gameBadgeIcon(icon);

  factory GameBadge.fromJson(Map<String, dynamic> j) => GameBadge(
        key: _s(j['key']),
        nameAr: _s(j['name_ar']),
        nameEn: _s(j['name_en']),
        icon: _s(j['icon']),
        rule: _m(j['rule']),
        earnedAt: _d(j['earned_at']),
      );
}

/// The badge's server icon name (`play`, `repeat`, `trophy`, `compass`, `star` …) as a glyph.
IconData gameBadgeIcon(String name) => switch (name) {
      'play' => Icons.play_arrow_rounded,
      'repeat' => Icons.repeat_rounded,
      'trophy' => Icons.emoji_events_rounded,
      'compass' => Icons.explore_rounded,
      'star' => Icons.star_rounded,
      'bolt' => Icons.bolt_rounded,
      'medal' => Icons.military_tech_rounded,
      _ => Icons.workspace_premium_rounded,
    };

/// The answer of `POST /games/{id}/plays`.
class GamePlayResult {
  const GamePlayResult({
    required this.stars,
    required this.score,
    required this.maxScore,
    this.progress,
    this.newBadges = const [],
    this.pointsAwarded = 0,
    this.duplicate = false,
    this.ranked = false,
    this.rankPoints = 0,
    this.rankToday,
    this.unrankedReason,
  });

  final int stars, score, maxScore, pointsAwarded;
  final GameProgress? progress;
  final List<GameBadge> newBadges;
  final bool duplicate;

  /// Games v3 (CONTRACT §2): the play counted for the champions; its points there; my place today (null = not
  /// ranked); why it did not count (`no_round`, `too_fast`, …).
  final bool ranked;
  final int rankPoints;
  final int? rankToday;
  final String? unrankedReason;

  factory GamePlayResult.fromJson(Object? r) {
    final m = _m(r);
    final play = _m(m['play']);
    return GamePlayResult(
      stars: _i(play['stars']),
      score: _i(play['score']),
      maxScore: _i(play['max_score']),
      progress: GameProgress.maybe(m['progress']),
      newBadges: [for (final b in _l(m['new_badges'])) GameBadge.fromJson(b)],
      pointsAwarded: _i(m['points_awarded']),
      duplicate: m['duplicate'] == true,
      ranked: m['ranked'] == true,
      rankPoints: _i(m['rank_points']),
      rankToday: m['rank_today'] is num ? (m['rank_today'] as num).toInt() : null,
      unrankedReason: m['unranked_reason'] is String ? m['unranked_reason'] as String : null,
    );
  }
}

/// One game's row in the progress report.
class GameProgressRow {
  const GameProgressRow({required this.progress, required this.key, required this.engine, required this.titleAr, required this.titleEn});

  final GameProgress progress;
  final String key, engine, titleAr, titleEn;

  String get title => learnText(titleAr, titleEn);
}

/// `GET /me/games/progress` and `GET /parent/children/{id}/games`.
class GamesReport {
  const GamesReport({this.games = const [], this.badges = const [], this.plays = 0, this.stars = 0, this.gamesPlayed = 0, this.perfect = 0});

  final List<GameProgressRow> games;
  final List<GameBadge> badges;
  final int plays, stars, gamesPlayed, perfect;

  bool get empty => plays == 0 && games.isEmpty;

  factory GamesReport.fromJson(Object? r) {
    final m = _m(r);
    final t = _m(m['totals']);
    return GamesReport(
      games: [
        for (final g in _l(m['games']))
          GameProgressRow(
            progress: GameProgress.maybe(g)!,
            key: _s(g['key']),
            engine: _s(g['engine']),
            titleAr: _s(g['title_ar']),
            titleEn: _s(g['title_en']),
          ),
      ],
      badges: [for (final b in _l(m['badges'])) GameBadge.fromJson(b)],
      plays: _i(t['plays']),
      stars: _i(t['stars']),
      gamesPlayed: _i(t['games']),
      perfect: _i(t['perfect']),
    );
  }
}

/// `POST /games/{id}/rounds` (Games v3, CONTRACT §2): a ranked round's id (null = no ranked attempt left today; the
/// round is played unranked) and the ranked attempts left for this game today, this one included.
class GameRoundStart {
  const GameRoundStart({this.roundId, this.rankedLeft = 0});

  final String? roundId;
  final int rankedLeft;

  factory GameRoundStart.fromJson(Object? r) {
    final m = _m(r);
    final id = m['round_id'];
    return GameRoundStart(roundId: id is String && id.isNotEmpty ? id : null, rankedLeft: _i(m['ranked_left']));
  }
}
