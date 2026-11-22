// lib/features/games/champions/champions_models.dart — the daily / weekly champions' payloads (Games v3,
// CONTRACT §6). Tolerant parsers: a missing field is a default, never a crash.
//
//   ChampionRow        `{rank, name: "First L.", points, games, is_me}` (no user id, no avatar)
//   ChampionStandings  GET /games/champions/standings: the running period, the top 20, my row, the minimums
//   ChampionPeriod     one past period of GET /games/champions (`computed` with winners, or `empty`)
//   ChampionHistory    that page + the scope chips this user may open
//   ChampionsStripData the `champions` block of GET /games (the strip on the Games tab)
//   HomeChampion       the `champion` block of GET /me/home (my newest win, the home line and the winner sheet)
library;

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/games_models.dart' show gameCategoryName;

Map<String, dynamic> _m(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : const <String, dynamic>{};

List<Map<String, dynamic>> _l(Object? v) => v is List ? [for (final x in v) if (x is Map) _m(x)] : const [];

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;

int? _iOrNull(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String? _s(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

/// A naive-UTC server instant (no offset = UTC), or null.
DateTime? championsUtc(Object? v) {
  final s = _s(v);
  if (s == null) return null;
  final zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

/// The champions' kill switch (CONTRACT §1): the Hall, the strip, the home line and the winner sheet.
const String kGamesChampionsKey = 'games.champions';

bool championsOff() => AppConfig.disableList.contains(kGamesChampionsKey);

const List<String> kChampionPeriods = ['daily', 'weekly'];

/// One scope chip: `platform` (key null), a category, or an organization.
class ChampionScope {
  const ChampionScope({required this.scope, this.key, this.nameAr = '', this.nameEn = ''});

  final String scope;
  final String? key;
  final String nameAr, nameEn;

  static const platform = ChampionScope(scope: 'platform', nameAr: 'الجميع', nameEn: 'Everyone');

  String get id => key == null ? scope : '$scope:$key';

  /// The chip's label: the server's name, else a known one.
  String get name {
    final own = AppConfig.lang == 'ar' ? nameAr : nameEn;
    if (own.trim().isNotEmpty) return own;
    return switch (scope) {
      'platform' => t('الجميع', 'Everyone'),
      'category' => gameCategoryName(key ?? ''),
      'org' => t('مؤسستي', 'My organization'),
      _ => scope,
    };
  }

  factory ChampionScope.fromJson(Map<String, dynamic> j) => ChampionScope(
        scope: _s(j['scope']) ?? 'platform',
        key: _s(j['key']),
        nameAr: _s(j['name_ar']) ?? '',
        nameEn: _s(j['name_en']) ?? '',
      );

  @override
  bool operator ==(Object other) => other is ChampionScope && other.scope == scope && other.key == key;

  @override
  int get hashCode => Object.hash(scope, key);
}

class ChampionRow {
  const ChampionRow({this.rank, this.name = '', this.points = 0, this.games = 0, this.isMe = false});

  /// Null for my own row while I am below the minimum activity.
  final int? rank;
  final String name;
  final int points, games;
  final bool isMe;

  /// The first letter of the name, for the podium's tinted circle (no avatar).
  String get initial {
    final n = name.trim();
    return n.isEmpty ? '؟' : n.characters.first.toUpperCase();
  }

  static ChampionRow? maybe(Object? v) {
    if (v is! Map) return null;
    final j = _m(v);
    return ChampionRow(
      rank: _iOrNull(j['rank']),
      name: _s(j['name']) ?? '',
      points: _i(j['points']),
      games: _i(j['games']),
      isMe: j['is_me'] == true,
    );
  }
}

/// GET /games/champions/standings.
class ChampionStandings {
  const ChampionStandings({
    this.scope = ChampionScope.platform,
    this.period = 'daily',
    this.periodStart,
    this.periodEnd,
    this.items = const [],
    this.me,
    this.total = 0,
    this.eligible = false,
    this.needGames = 0,
    this.needDays = 0,
    this.minGames = 3,
    this.minDays = 1,
    this.minPlayers = 5,
    this.visible = true,
  });

  final ChampionScope scope;
  final String period;
  final DateTime? periodStart, periodEnd;
  final List<ChampionRow> items;
  final ChampionRow? me;
  final int total;
  final bool eligible;
  final int needGames, needDays;
  final int minGames, minDays, minPlayers;
  final bool visible;

  /// The top 3 for the podium.
  List<ChampionRow> get podium => items.take(3).toList();

  /// My row is already in [items] (then it is marked there, not pinned again).
  bool get meListed => me != null && items.any((r) => r.isMe);

  factory ChampionStandings.fromJson(Object? r) {
    final j = _m(r);
    final needs = _m(j['needs']);
    return ChampionStandings(
      scope: ChampionScope(scope: _s(j['scope']) ?? 'platform', key: _s(j['key'])),
      period: _s(j['period']) ?? 'daily',
      periodStart: championsUtc(j['period_start']),
      periodEnd: championsUtc(j['period_end']),
      items: [for (final e in _l(j['items'])) ChampionRow.maybe(e)!],
      me: ChampionRow.maybe(j['me']),
      total: _i(j['total']),
      eligible: j['eligible'] == true,
      needGames: _i(needs['games']),
      needDays: _i(needs['days']),
      minGames: _i(j['min_games'], 3),
      minDays: _i(j['min_days'], 1),
      minPlayers: _i(j['min_players'], 5),
      visible: j['visible'] != false,
    );
  }
}

class ChampionPeriod {
  const ChampionPeriod({required this.id, this.kind = 'daily', this.start, this.end, this.status = 'computed', this.winners = const []});

  final int id;
  final String kind, status;
  final DateTime? start, end;
  final List<ChampionRow> winners;

  bool get empty => status == 'empty' || winners.isEmpty;

  factory ChampionPeriod.fromJson(Map<String, dynamic> j) => ChampionPeriod(
        id: _i(j['id']),
        kind: _s(j['period_kind']) ?? 'daily',
        start: championsUtc(j['period_start']),
        end: championsUtc(j['period_end']),
        status: _s(j['status']) ?? 'computed',
        winners: [for (final e in _l(j['winners'])) ChampionRow.maybe(e)!],
      );
}

/// GET /games/champions (past winners, newest first, 10 a page).
class ChampionHistory {
  const ChampionHistory({this.items = const [], this.page = 1, this.total = 0, this.hasMore = false, this.scopes = const []});

  final List<ChampionPeriod> items;
  final int page, total;
  final bool hasMore;
  final List<ChampionScope> scopes;

  factory ChampionHistory.fromJson(Object? r) {
    final j = _m(r);
    return ChampionHistory(
      items: [for (final e in _l(j['items'])) ChampionPeriod.fromJson(e)],
      page: _i(j['page'], 1),
      total: _i(j['total']),
      hasMore: j['has_more'] == true,
      scopes: [for (final e in _l(j['scopes'])) ChampionScope.fromJson(e)],
    );
  }
}

/// The `champions` block of GET /games (null = nothing to show).
class ChampionsStripData {
  const ChampionsStripData({this.scope = ChampionScope.platform, this.period = 'daily', this.periodEnd, this.top = const [], this.me});

  final ChampionScope scope;
  final String period;
  final DateTime? periodEnd;
  final List<ChampionRow> top;
  final ChampionRow? me;

  static ChampionsStripData? maybe(Object? v) {
    if (v is! Map) return null;
    final j = _m(v);
    return ChampionsStripData(
      scope: ChampionScope(scope: _s(j['scope']) ?? 'platform', key: _s(j['key'])),
      period: _s(j['period']) ?? 'daily',
      periodEnd: championsUtc(j['period_end']),
      top: [for (final e in _l(j['top'])) ChampionRow.maybe(e)!],
      me: ChampionRow.maybe(j['me']),
    );
  }
}

/// The `champion` block of GET /me/home (my newest win), also a row of `wins` in GET /me/rewards.
class HomeChampion {
  const HomeChampion({
    required this.championId,
    this.periodKind = 'daily',
    this.scope = ChampionScope.platform,
    this.rank = 1,
    this.periodStart,
    this.periodEnd,
    this.rewardStatus = 'none',
    this.couponId,
  });

  final int championId;
  final String periodKind;
  final ChampionScope scope;
  final int rank;
  final DateTime? periodStart, periodEnd;

  /// `none` / `pending` / `issued` / `revoked`.
  final String rewardStatus;
  final int? couponId;

  bool get weekly => periodKind == 'weekly';

  static HomeChampion? maybe(Object? v) {
    if (v is! Map) return null;
    final j = _m(v);
    final id = _iOrNull(j['champion_id']);
    if (id == null) return null;
    return HomeChampion(
      championId: id,
      periodKind: _s(j['period_kind']) ?? 'daily',
      scope: ChampionScope(scope: _s(j['scope_kind']) ?? 'platform', key: _s(j['scope_key'])),
      rank: _i(j['rank'], 1),
      periodStart: championsUtc(j['period_start']),
      periodEnd: championsUtc(j['period_end']),
      rewardStatus: _s(j['reward_status']) ?? 'none',
      couponId: _iOrNull(j['coupon_id']),
    );
  }
}

/// "Champion of the day" / "2nd this week" … in the app's language.
String championTitle(HomeChampion w) {
  if (w.rank == 1) return w.weekly ? t('بطل الأسبوع', 'Champion of the week') : t('بطل اليوم', 'Champion of the day');
  return w.weekly
      ? t('المركز ${w.rank} هذا الأسبوع', 'Number ${w.rank} this week')
      : t('المركز ${w.rank} اليوم', 'Number ${w.rank} today');
}
