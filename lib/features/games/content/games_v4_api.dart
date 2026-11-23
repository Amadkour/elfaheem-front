// lib/features/games/content/games_v4_api.dart — every learner route of Games v4 (CONTRACT §4, §8, §9), typed.
// Every path is a literal `/api/v1/…` (test/contract/ checks each against the server's routes). The models here are
// thin: a draw / pool keeps its raw map so `GameSession.fromDraw` (core/game_session.dart) and the level cache store
// it as the server sent it; items, settings, audio entries and reciters reuse core/game_items.dart and game_audio.dart.
//
// Errors are ApiException (`code`: `level_locked`, `template_off`, `no_items`, `reciter_unknown`, `age_fixed`, …).
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/games/core/duel.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/games_models.dart';

Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(Object? v) => [for (final e in (v is List ? v : const [])) if (e is Map) Map<String, dynamic>.from(e)];
int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
String? _s(Object? v) => v is String ? v : null;

/// The reciter a draw / pool answers with (null when the draw has no Quran audio).
class DrawReciter {
  const DrawReciter({required this.key, required this.nameAr, required this.nameEn});
  final String key, nameAr, nameEn;

  static DrawReciter? from(Object? j) {
    if (j is! Map) return null;
    return DrawReciter(key: '${j['key']}', nameAr: '${j['name_ar'] ?? ''}', nameEn: '${j['name_en'] ?? ''}');
  }
}

/// `POST /games/{id}/draw` (kind `round`) and one `GET /games/{id}/pool` (kind `pool`): the snapshot.
class V4Draw {
  const V4Draw(this.raw);

  /// The answer as sent: hand it to `GameSession.fromDraw`.
  final Map<String, dynamic> raw;

  String get drawId => '${raw['draw_id']}';
  String get kind => _s(raw['kind']) ?? 'round';
  bool get isPool => kind == 'pool';
  bool get sacred => raw['sacred'] == true;
  String get template => _s(raw['template']) ?? '';
  int get seed => _i(raw['seed']);
  int get maxScore => _i(raw['max_score']);
  int get count => _i(raw['count']);

  /// Null = the round is played unranked.
  String? get roundId => _s(raw['round_id']);
  int get rankedLeft => _i(raw['ranked_left']);
  DrawReciter? get reciter => DrawReciter.from(raw['reciter']);
  DateTime? get issuedAt => DateTime.tryParse('${raw['issued_at'] ?? ''}');

  /// A pool's end (30 days); null on a round.
  DateTime? get expiresAt => DateTime.tryParse('${raw['expires_at'] ?? ''}');
  List<Map<String, dynamic>> get items => _l(raw['items']);
}

/// A level of `GET /games?v=4` (the v3 game object plus the v4 fields) — only the v4 fields are typed here.
class V4Level {
  const V4Level(this.raw);
  final Map<String, dynamic> raw;

  int get id => _i(raw['id']);
  String? get template => _s(raw['template']);
  int? get subjectId => raw['game_subject_id'] is num ? _i(raw['game_subject_id']) : null;
  String? get topic => _s(raw['topic']);
  int get levelNo => _i(raw['level_no']);
  int get ageMin => _i(raw['age_min'], 6);
  int get ageMax => _i(raw['age_max'], 99);
  bool get locked => raw['locked'] == true;
  bool get sacred => raw['sacred'] == true;
  int get coinsReward => _i(raw['coins_reward']);
  int get itemsCount => _i(raw['items_count']);
  Map<String, dynamic> get unlock => _m(raw['unlock']);
}

class V4Profile {
  const V4Profile(this.raw);
  final Map<String, dynamic> raw;

  String? get ageBand => _s(raw['age_band']);
  String? get ageSource => _s(raw['age_source']);
  bool get needsAge => raw['needs_age'] == true;
  int get coins => _i(raw['coins']);
  Map<String, String?> get equipped => {for (final e in _m(raw['equipped']).entries) e.key: _s(e.value)};
  List<Map<String, dynamic>> get sky => _l(raw['sky']);

  /// The learner's own choice (null = the platform default).
  String? get reciterKey => _s(raw['reciter_key']);
  String? get reciterEffective => _s(raw['reciter_effective']);
  bool get canReview => raw['can_review'] == true;
}

class V4Subject {
  const V4Subject(this.raw);
  final Map<String, dynamic> raw;

  int get id => _i(raw['id']);
  String get key => '${raw['key']}';
  String get nameAr => '${raw['name_ar'] ?? ''}';
  String get nameEn => '${raw['name_en'] ?? ''}';
  String? get icon => _s(raw['icon']);
  String? get color => _s(raw['color']);
  bool get sacred => raw['sacred'] == true;
  int get levels => _i(raw['levels']);
  int get done => _i(raw['done']);
  int get stars => _i(raw['stars']);
}

/// `GET /games/v4/home`.
class V4Home {
  const V4Home(this.raw);
  final Map<String, dynamic> raw;

  V4Profile get profile => V4Profile(_m(raw['profile']));
  List<V4Subject> get subjects => [for (final s in _l(raw['subjects'])) V4Subject(s)];
  Map<String, int> get templates => {for (final t in _l(raw['templates'])) '${t['key']}': _i(t['levels'])};
  V4Level? get continueLevel => raw['continue'] is Map ? V4Level(_m(raw['continue'])) : null;
  int get reviewDue => _i(raw['review_due']);
  Map<int, int> get reviewLevels => {for (final r in _l(raw['review_levels'])) _i(r['game_id']): _i(r['due'])};
  Map<String, bool> get flags => {for (final e in _m(raw['flags']).entries) e.key: e.value == true};
  bool flag(String k) => flags[k] == true;
}

/// `POST /games/{id}/plays` with the v4 fields.
class V4PlayResult {
  const V4PlayResult({required this.play, this.coinsAwarded = 0, this.coins, this.unlocked = const [], this.srsDue = 0, this.rankedLeft, this.duel});
  final GamePlayResult play;
  final int coinsAwarded;

  /// The learner's coins after the play (null when the server did not say).
  final int? coins;

  /// The ids of the levels this play unlocked.
  final List<int> unlocked;
  final int srsDue;
  final int? rankedLeft;

  /// Ghost Duel: the SERVER's verdict (`{won, opponent: ghost|bot}`); null when the play has no duel result.
  final V4Duel? duel;

  factory V4PlayResult.fromJson(Object? r) {
    final m = _m(r);
    return V4PlayResult(
      play: GamePlayResult.fromJson(m),
      coinsAwarded: _i(m['coins_awarded']),
      coins: m['coins'] is num ? _i(m['coins']) : null,
      unlocked: [for (final e in (m['unlocked'] as List? ?? const [])) if (e is num) e.toInt()],
      srsDue: _i(m['srs_due']),
      rankedLeft: m['ranked_left'] is num ? _i(m['ranked_left']) : null,
      duel: m['duel'] is Map ? V4Duel(won: _m(m['duel'])['won'] == true, opponent: '${_m(m['duel'])['opponent'] ?? 'bot'}') : null,
    );
  }
}

/// The server's Ghost Duel verdict of a play.
class V4Duel {
  const V4Duel({required this.won, required this.opponent});
  final bool won;

  /// `ghost` or `bot`.
  final String opponent;
}

/// `GET /games/{id}/ghost`: another learner's finished round (events: `[ms, right]`).
class V4Ghost {
  const V4Ghost({this.id, required this.name, required this.score, required this.maxScore, required this.durationMs, required this.events});
  final int? id;
  final String name;
  final int score, maxScore, durationMs;
  final List<(int, int)> events;

  /// The plain values the Ghost Duel template draws.
  DuelGhost toDuel() => DuelGhost(id: id, name: name, score: score, maxScore: maxScore, durationMs: durationMs, events: events);

  static V4Ghost? from(Object? j) {
    if (j is! Map) return null;
    return V4Ghost(
      id: j['id'] is num ? (j['id'] as num).toInt() : null,
      name: '${j['name'] ?? ''}',
      score: _i(j['score']),
      maxScore: _i(j['max_score']),
      durationMs: _i(j['duration_ms']),
      events: [
        for (final e in (j['events'] as List? ?? const []))
          if (e is List && e.length >= 2 && e[0] is num && e[1] is num) ((e[0] as num).toInt(), (e[1] as num).toInt()),
      ],
    );
  }
}

class V4CosmeticItem {
  const V4CosmeticItem(this.raw);
  final Map<String, dynamic> raw;

  String get key => '${raw['key']}';
  String get slot => '${raw['slot']}';
  String get nameAr => '${raw['name_ar'] ?? ''}';
  String get nameEn => '${raw['name_en'] ?? ''}';
  int get priceCoins => _i(raw['price_coins']);
  bool get owned => raw['owned'] == true;
  bool get equipped => raw['equipped'] == true;

  /// `{type: stars|levels|champion, count, have}` or null when nothing blocks it.
  Map<String, dynamic>? get locked => raw['locked'] is Map ? _m(raw['locked']) : null;
}

class V4Cosmetics {
  const V4Cosmetics({required this.coins, required this.items});
  final int coins;
  final List<V4CosmeticItem> items;
}

class V4Challenge {
  const V4Challenge(this.raw);
  final Map<String, dynamic> raw;

  int get id => _i(raw['id']);
  String get code => '${raw['code']}';
  bool get open => raw['status'] == 'open';
  String? get link => _s(raw['link']);
  String get owner => '${raw['owner'] ?? ''}';
  bool get joined => raw['joined'] == true;
  V4Level? get game => raw['game'] is Map ? V4Level(_m(raw['game'])) : null;
  List<Map<String, dynamic>> get board => _l(raw['board']);
}

class V4ClassBoard {
  const V4ClassBoard({required this.weekStart, this.mine, required this.items});
  final String? weekStart;
  final Map<String, dynamic>? mine;
  final List<Map<String, dynamic>> items;
}

class V4BreaksConfig {
  const V4BreaksConfig({this.playNow = false, this.breakReminders = false, this.studyMinutes = 0, this.breakMaxMinutes = 0});
  final bool playNow, breakReminders;
  final int studyMinutes, breakMaxMinutes;
}

/// `GET /parent/children/{id}/games` (the v4 summary shape).
class V4ParentGames {
  const V4ParentGames({required this.minutes7d, required this.finished7d, required this.minutes30d, required this.finished30d, required this.totals});
  final int minutes7d, finished7d, minutes30d, finished30d;
  final Map<String, int> totals;
}

class GamesV4Api {
  GamesV4Api({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  static const _g = '/api/v1/games';

  // ---- levels, home, profile ----

  /// `GET /games?v=4` — the levels (optionally of one subject / template).
  Future<List<V4Level>> levels({int? subjectId, String? template}) async {
    final r = await _api.get(_g, queryParams: {'v': 4, 'game_subject_id': ?subjectId, 'template': ?template});
    return [for (final g in _l(r is Map ? r['items'] : r)) V4Level(g)];
  }

  Future<V4Home> home() async => V4Home(_m(await _api.get('$_g/v4/home')));

  Future<V4Profile> profile() async => V4Profile(_m(await _api.get('/api/v1/me/games/profile')));

  /// `PUT /me/games/profile`: only the fields given are sent. [clearReciter] sends `reciter_key: null`.
  Future<V4Profile> saveProfile({String? ageBand, String? reciterKey, bool clearReciter = false, Map<String, String?>? equipped}) async {
    final body = <String, dynamic>{
      'age_band': ?ageBand,
      if (reciterKey != null || clearReciter) 'reciter_key': reciterKey,
      'equipped': ?equipped,
    };
    return V4Profile(_m(await _api.put('/api/v1/me/games/profile', body: body)));
  }

  // ---- draw, pool, play, ghost ----

  /// `POST /games/{id}/draw`. [mode]: play / review / preview (admins).
  Future<V4Draw> draw(int gameId, {String? mode, String? reciter, String? challenge}) async {
    final body = <String, dynamic>{'mode': ?mode, 'reciter': ?reciter, 'challenge': ?challenge};
    return V4Draw(_m(await _api.post('$_g/$gameId/draw', body: body)));
  }

  /// `GET /games/{id}/pool` — phones and desktop only (the web never calls it).
  Future<V4Draw> pool(int gameId) async => V4Draw(_m(await _api.get('$_g/$gameId/pool')));

  /// `POST /games/{id}/plays` (a v3 body plus `draw_id`, `picked`, `calm`).
  Future<V4PlayResult> play(
    int gameId, {
    required String clientId,
    required int score,
    required int maxScore,
    required int durationS,
    required String playedAt,
    String? roundId,
    List<Map<String, dynamic>>? trace,
    String? drawId,
    List<int>? picked,
    bool? calm,
    int? ghostPlayId,
  }) async {
    final body = <String, dynamic>{
      'client_id': clientId,
      'score': score,
      'max_score': maxScore,
      'duration_s': durationS,
      'played_at': playedAt,
      'round_id': ?roundId,
      'trace': ?trace,
      'draw_id': ?drawId,
      'picked': ?picked,
      'calm': ?calm,
      'ghost_play_id': ?ghostPlayId,
    };
    return V4PlayResult.fromJson(await _api.post('$_g/$gameId/plays', body: body));
  }

  /// Null = no ghost: the app plays its built-in training partner.
  Future<V4Ghost?> ghost(int gameId) async => V4Ghost.from(_m(await _api.get('$_g/$gameId/ghost'))['ghost']);

  // ---- reciters ----

  Future<GameReciterList> reciters() async {
    final m = _m(await _api.get('$_g/reciters'));
    return GameReciterList(
      items: [for (final r in _l(m['items'])) GameReciter.fromJson(r)],
      defaultKey: _s(m['default_key']),
      kidsKey: _s(m['kids_key']),
      mine: _s(m['mine']),
      effective: _s(m['effective']),
    );
  }

  /// `GET /games/quran/audio` — at most 60 refs per call (longer lists are sent in chunks).
  Future<Map<String, RecitationSegment>> quranAudio(List<String> refs, String reciter) async {
    final out = <String, RecitationSegment>{};
    for (var i = 0; i < refs.length; i += 60) {
      final chunk = refs.sublist(i, i + 60 > refs.length ? refs.length : i + 60);
      final m = _m(await _api.get('$_g/quran/audio', queryParams: {'refs': chunk.join(','), 'reciter': reciter}));
      for (final e in _m(m['items']).entries) {
        if (e.value is Map) out[e.key] = RecitationSegment.fromJson(_m(e.value), ref: e.key);
      }
    }
    return out;
  }

  // ---- cosmetics ----

  Future<V4Cosmetics> cosmetics() async {
    final m = _m(await _api.get('$_g/cosmetics'));
    return V4Cosmetics(coins: _i(m['coins']), items: [for (final i in _l(m['items'])) V4CosmeticItem(i)]);
  }

  /// `POST /games/cosmetics/{key}/buy` → the new coins and the item.
  Future<({int coins, V4CosmeticItem? item})> buy(String key) async {
    final m = _m(await _api.post('$_g/cosmetics/$key/buy'));
    return (coins: _i(m['coins']), item: m['item'] is Map ? V4CosmeticItem(_m(m['item'])) : null);
  }

  // ---- challenges and the class board ----

  Future<V4Challenge> createChallenge(int gameId) async => V4Challenge(_m(await _api.post('$_g/challenges', body: {'game_id': gameId})));
  Future<V4Challenge> challenge(String code) async => V4Challenge(_m(await _api.get('$_g/challenges/$code')));
  Future<V4Challenge> joinChallenge(String code) async => V4Challenge(_m(await _api.post('$_g/challenges/$code/join')));

  Future<List<V4Challenge>> myChallenges() async =>
      [for (final c in _l(_m(await _api.get('/api/v1/me/games/challenges'))['items'])) V4Challenge(c)];

  Future<V4ClassBoard> classBoard(int courseId) async {
    final m = _m(await _api.get('$_g/class-board', queryParams: {'course_id': courseId}));
    return V4ClassBoard(weekStart: _s(m['week_start']), mine: m['mine'] is Map ? _m(m['mine']) : null, items: _l(m['items']));
  }

  // ---- smart breaks ----

  Future<V4BreaksConfig> breaksConfig() async {
    final m = _m(await _api.get('$_g/breaks/config'));
    return V4BreaksConfig(
      playNow: m['play_now'] == true,
      breakReminders: m['break_reminders'] == true,
      studyMinutes: _i(m['study_minutes']),
      breakMaxMinutes: _i(m['break_max_minutes']),
    );
  }

  /// A level to suggest for a course (null = none).
  Future<V4Level?> suggest({int? courseId, int? subjectId, String? topic}) async {
    final m = _m(await _api.get('$_g/suggest', queryParams: {'course_id': ?courseId, 'subject_id': ?subjectId, 'topic': ?topic}));
    return m['game'] is Map ? V4Level(_m(m['game'])) : null;
  }

  // ---- parent ----

  Future<V4ParentGames> parentGames(int studentId) async {
    final m = _m(await _api.get('/api/v1/parent/children/$studentId/games'));
    final s = _m(m['summary']);
    return V4ParentGames(
      minutes7d: _i(s['minutes_7d']),
      finished7d: _i(s['finished_7d']),
      minutes30d: _i(s['minutes_30d']),
      finished30d: _i(s['finished_30d']),
      totals: {for (final e in _m(m['totals']).entries) e.key: _i(e.value)},
    );
  }
}
