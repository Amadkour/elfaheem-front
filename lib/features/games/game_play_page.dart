// lib/features/games/game_play_page.dart — playing one game (D-1346): loads the game's `config` when the list did
// not carry it, plays one round on its engine (engines/game_engine.dart), then shows the learn kit's result and
// sends the play.
//
//   GamePlayPage  the page: GET /api/v1/games/{id}, a round, then the play through a [GamePlaySubmission] (one
//                 `client_id` per round). With the device's outbox (D-1351) the play is an op: the result shows at
//                 once from the device's grading and the server's answer (points, badges) replaces it when the sync
//                 engine brings it; replaying is allowed meanwhile. Without one (the web, `sync.offline` off) it is
//                 POST /api/v1/games/{id}/plays, kept until the server answers (a retry sends the same id). A guest
//                 plays without saving.
//                 Since Learning Hub v2 (D-1580) the round is played in the GameShell (shell/), the end is the
//                 shell's GameFinishView, and the game's leaderboard (game_leaderboard.dart) sits under it and in the
//                 app bar's sheet; it is loaded only when shown.
//   GamePlayView  the body with plain values (test/ui/games_layout_test.dart)
//   GamesBus      `revision` bumps after a saved play (also one the outbox saved after the page closed), so the tab and
//                 the progress page reload
//
// Games v3 (CONTRACT §2): each round asks for a ranked round (`POST /games/{id}/rounds`) when it starts; any failure,
// no network, a guest or `games.champions` off = the round is played unranked exactly as before. A ranked play
// carries `round_id` + the engine's trace and is posted directly (the outbox keeps it, unranked, only when the
// network lost it); the finish view shows `rank_today` when the server ranked it.
//
// Games v4 (T48, CONTRACT §4, §8): a game whose `engine` is a registered template (templates/register_all.dart) opens
// a level through POST /games/{id}/draw, plays it on a [GameSession] (core/game_session.dart) drawn by the template,
// and posts the play with `draw_id` (+ `round_id`, `trace`). Offline (phones / desktop) a cached pool gives the round
// (`LevelCache.pickRound`) and the play goes to the outbox with `picked`. The result adds coins and unlocked levels
// (learner/result_sheet.dart). The right music starts with the round (none for sacred content). Every other game
// plays exactly as before. Whether a game is v4 is read from the LOADED game: a page opened by URL starts from a stub
// with an empty engine, loads the game, then draws. A challenge draw that fails never falls back to the pool (the
// pool has no challenge seed): it shows the error with Retry.
//
// Offline pools (G3, CONTRACT §4 `pool`, phones / desktop only: `LevelCache.enabled` is `kDownloadsAvailable`): after
// an online draw the level's pool is fetched and stored in the background when it is missing (once per level per
// half hour, never for a guest, a review or a challenge); when it is stored for another reciter,
// `LevelCache.refreshForReciter` re-resolves the stored levels' audio (Wi-Fi only). The app bar's "Download for
// offline" button does the same on demand with its progress, and shows "Saved offline" once the pool is kept.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart';
import 'package:flutter_education_app/core/offline/sync/outbox.dart';
import 'package:flutter_education_app/core/offline/sync/sync_engine.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/content/level_cache.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/duel.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/learner/result_sheet.dart';
import 'package:flutter_education_app/features/games/templates/constellation/constellation.dart';
import 'package:flutter_education_app/features/games/templates/ghost_duel/duel_scene.dart';
import 'package:flutter_education_app/features/games/templates/register_all.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/features/games/engines/game_engine.dart';
import 'package:flutter_education_app/features/games/game_leaderboard.dart';
import 'package:flutter_education_app/features/games/games_api.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/games/shell/game_round.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/games/learner/challenges.dart' show challengeAFriend, gamesChallengesOff;
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// Bumps after a play the server saved.
abstract final class GamesBus {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool _wired = false;

  /// Once: a play the outbox saved bumps [revision], whichever page is open.
  static void wireSync([SyncEngine? engine]) {
    registerGameTemplates();
    if (_wired) return;
    _wired = true;
    (engine ?? SyncEngine.instance).listen(SyncKinds.gamePlay, (r) {
      if (r.accepted) revision.value++;
    });
  }
}

/// A Games v4 play: the v3 fields plus `draw_id`, `picked` (an offline round) and `calm`; the answer also carries the
/// coins and the unlocked levels.
class V4PlaySubmission extends GamePlaySubmission {
  V4PlaySubmission({
    required super.gameId,
    required super.score,
    required super.maxScore,
    super.durationS,
    super.roundId,
    super.trace,
    this.drawId,
    this.picked,
    this.calm,
    this.ghostPlayId,
    this.fromPool = false,
    GamesV4Api? v4,
  }) : _v4 = v4 ?? GamesV4Api();

  /// An offline round (from the cached pool): it waits in the outbox; a live draw is posted straight to the plays
  /// route, which knows `draw_id`.
  final bool fromPool;

  @override
  bool get ranked => !fromPool;

  final String? drawId;
  final List<int>? picked;
  final bool? calm;

  /// Ghost Duel: the ghost play this round raced (null = the training partner). Never a verdict: the server decides.
  final int? ghostPlayId;
  final GamesV4Api _v4;

  /// The coins / unlocked levels of the answer (null until it came).
  V4PlayResult? v4Result;

  @override
  Map<String, dynamic> get payload => {
        ...super.payload,
        'round_id': ?roundId,
        'trace': ?trace,
        'draw_id': ?drawId,
        'picked': ?picked,
        'calm': ?calm,
        'ghost_play_id': ?ghostPlayId,
      };

  @override
  void settle(SyncResult r) {
    super.settle(r);
    if (r.accepted && r.entity != null) v4Result = V4PlayResult.fromJson(r.entity);
  }

  @override
  Future<GamePlayResult?> send(GamesApi api) async {
    if (result != null) return result;
    try {
      final r = await _v4.play(gameId,
          clientId: clientId,
          score: score,
          maxScore: maxScore,
          durationS: durationS ?? 0,
          playedAt: playedAt.toUtc().toIso8601String(),
          roundId: roundId,
          trace: trace,
          drawId: drawId,
          picked: picked,
          calm: calm,
          ghostPlayId: ghostPlayId);
      v4Result = r;
      error = null;
      return result = r.play;
    } catch (e) {
      error = gamesErrorText(e);
      settledWithError = gamesDefiniteAnswer(e) && (e as ApiException).statusCode < 500;
      return null;
    }
  }
}

class GamePlayPage extends StatefulWidget {
  const GamePlayPage({super.key, required this.game, this.api, this.v4, this.cache, this.userId, this.review = false, this.challenge});

  /// Games v4 (T76): a friends challenge's code: the draw takes the challenge's seed (same items, same order).
  final String? challenge;

  /// Games v4 (T72): a spaced-repetition review round (`draw` with `mode: review`).
  final bool review;

  /// The list's row (its `config` may be empty: then the page loads the game).
  final GameSummary game;
  final GamesApi? api;

  /// Tests: the v4 routes, the offline pool cache and the signed-in user.
  final GamesV4Api? v4;
  final LevelCache? cache;
  final int? userId;

  @override
  State<GamePlayPage> createState() => _GamePlayPageState();
}

class _GamePlayPageState extends State<GamePlayPage> {
  late final GamesApi _api = widget.api ?? GamesApi();
  late final GamesV4Api _v4 = widget.v4 ?? GamesV4Api();
  late final LevelCache _cache = widget.cache ?? LevelCache.instance;

  /// A Games v4 level: its engine is a registered template. Its round comes from a draw, never from `config`. Read
  /// from the loaded game, never frozen from the stub a URL opens with (engine '').
  bool get _isV4 => _registered(_game.engine);
  GameSession? _session;
  int? _ghostPlayId;
  List<int>? _picked, _itemIds;
  bool _fromPool = false;
  bool _unreadable = false;
  late GameSummary _game = widget.game;
  bool _loading = false;
  String? _error;

  int _round = 0;
  final Stopwatch _clock = Stopwatch();
  GamePlaySubmission? _sub;
  bool _saving = false;

  /// Bumps when a play is saved, so the leaderboard loads again.
  int _saved = 0;

  /// The ranked round of the round being played (null = unranked) and the trace the engine reported.
  String? _roundId;
  List<Map<String, Object>>? _trace;

  /// The learner's games profile, for a template that draws from it (Constellation's "my sky"); null = not loaded.
  V4Profile? _profile;

  /// The level's pool is kept on this device; a pool download's progress (done, total files), null = none running.
  bool _savedOffline = false;
  (int, int)? _dl;

  /// One pool download per user and level at a time, and a quiet one at most once per [_poolGap] (no retry storm).
  static final Map<String, Future<void>> _poolJobs = {};
  static final Map<String, DateTime> _poolTried = {};
  static const Duration _poolGap = Duration(minutes: 30);
  static bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    GamesBus.wireSync();
    SyncEngine.instance.listen(SyncKinds.gamePlay, _onSync);
    if (_isV4) {
      _startV4();
    } else if (_game.config.isEmpty) {
      _load();
    } else {
      _clock.start();
      _startRound();
    }
  }

  /// Asks for a ranked round for the round that starts now; it never blocks play.
  Future<void> _startRound() async {
    _roundId = null;
    _trace = null;
    if (GuestState.active || gamesChampionsOff() || gameEngine(_game.engine) == null) return;
    final round = _round;
    try {
      final r = await _api.startRound(_game.id);
      // a late answer for a round already replayed or finished is dropped
      if (mounted && round == _round && _sub == null) _roundId = r.roundId;
    } catch (_) {}
  }

  int? _uid() {
    if (widget.userId != null) return widget.userId;
    try {
      return context.read<MyAuthProvider>().currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Opens a level: a draw online; when the network is gone, a round from the cached pool.
  Future<void> _startV4() async {
    _session?.dispose();
    _session = null;
    _picked = _itemIds = null;
    _ghostPlayId = null;
    _fromPool = false;
    _unreadable = false;
    setState(() {
      _loading = true;
      _error = null;
    });
    // asked alongside the draw, only for a template that uses it; a failure or a slow answer is simply 0
    final profile = (!GuestState.active && kProfileTemplates.contains(_game.engine))
        ? _v4.profile().timeout(const Duration(seconds: 4)).then<V4Profile?>((p) => p).catchError((Object _) => null)
        : null;
    Map<String, dynamic>? draw;
    try {
      draw = (await _v4.draw(_game.id, mode: widget.review ? 'review' : null, challenge: widget.challenge)).raw;
    } catch (e) {
      // a challenge draw never falls back to the pool: the pool has no challenge seed (Retry draws again)
      if (gamesDefiniteAnswer(e) || widget.challenge != null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = gamesErrorText(e);
        });
        return;
      }
      final uid = _uid();
      final r = uid == null ? null : await _cache.pickRound(uid, _game.id);
      if (r != null) {
        draw = r.draw;
        _picked = r.picked;
        _itemIds = r.itemIds;
        _fromPool = true;
      }
    }
    if (!mounted) return;
    if (_fromPool) _savedOffline = true;
    if (draw == null) {
      setState(() {
        _loading = false;
        _error = t('تحتاج هذه اللعبة إلى اتصال بالإنترنت.', 'This game needs an internet connection.');
      });
      return;
    }
    final session = GameSession.fromDraw(draw, onFinished: _v4Finished);
    if (session == null) {
      // an empty or unreadable draw: a newer server than this app
      setState(() {
        _loading = false;
        _unreadable = true;
      });
      return;
    }
    if (session.templateKey == 'ghost_duel' && !_fromPool) {
      // Ghost Duel: a recorded opponent of this level, or the training partner when there is none / the call fails
      try {
        final g = await _v4.ghost(_game.id);
        session.ghost = g?.toDuel();
        _ghostPlayId = g?.id;
      } catch (_) {}
      if (!mounted) return;
    }
    if (profile != null) {
      final p = await profile;
      if (!mounted) return;
      if (p != null) _profile = p;
    }
    _roundId = session.roundId;
    _session = session;
    setState(() => _loading = false);
    _clock
      ..reset()
      ..start();
    session.start();
    _playMusic(session);
    if (!_fromPool) _keepPoolFresh(session.reciter?['key'] as String?);
  }

  /// Offline pools are kept only on phones / desktop, for a signed-in learner's normal draws.
  bool get _offlineOk => _cache.enabled && _isV4 && !GuestState.active && !widget.review && widget.challenge == null;

  /// After an online draw: fetch the level's pool when the device has none (quiet), or bring the stored pools to the
  /// learner's reciter when it changed (`staleFor` / `refreshForReciter`, Wi-Fi only).
  Future<void> _keepPoolFresh(String? reciter) async {
    final uid = _uid();
    if (!_offlineOk || uid == null) return;
    try {
      final has = await _cache.hasPool(uid, _game.id);
      if (mounted && has != _savedOffline) setState(() => _savedOffline = has);
      if (!has) {
        await _fetchPool(uid);
      } else if (reciter != null && !_refreshing && (await _cache.staleFor(uid, reciter)).isNotEmpty) {
        _refreshing = true;
        try {
          await _cache.refreshForReciter(uid, reciter);
        } finally {
          _refreshing = false;
        }
      }
    } catch (e) {
      debugPrint('games: offline pool of ${_game.id}: $e');
    }
  }

  /// GET /pool and keep it with its audio. A quiet call ([manual] false) is skipped when one ran in the last
  /// [_poolGap]; a running download is joined, never started twice.
  Future<void> _fetchPool(int uid, {bool manual = false}) {
    final gameId = _game.id;
    final key = '$uid:$gameId';
    final running = _poolJobs[key];
    if (running != null) return running;
    final last = _poolTried[key];
    if (!manual && last != null && DateTime.now().difference(last) < _poolGap) return Future.value();
    _poolTried[key] = DateTime.now();
    Future<void> job() async {
      final pool = await _v4.pool(gameId);
      await _cache.storePool(uid, gameId, pool, onProgress: (done, total) {
        if (mounted && _dl != null && _game.id == gameId) setState(() => _dl = (done, total));
      });
      final has = await _cache.hasPool(uid, gameId);
      if (mounted && _game.id == gameId) setState(() => _savedOffline = has);
    }

    return _poolJobs[key] = job().whenComplete(() => _poolJobs.remove(key));
  }

  /// The app bar's "Download for offline".
  Future<void> _downloadOffline() async {
    final uid = _uid();
    if (uid == null || _dl != null) return;
    setState(() => _dl = (0, 0));
    try {
      await _fetchPool(uid, manual: true);
      if (!mounted) return;
      setState(() => _dl = null);
      showAppNotice(
          _savedOffline
              ? t('حُفظ المستوى، يمكنك لعبه دون اتصال', 'Saved: you can play this level offline')
              : t('تعذّر حفظ المستوى', 'Could not save this level'),
          error: !_savedOffline);
    } catch (e) {
      if (!mounted) return;
      setState(() => _dl = null);
      showAppNotice(gamesErrorText(e), error: true);
    }
  }

  Widget _offlineButton() {
    final dl = _dl;
    final String label = dl != null
        ? t('جارٍ الحفظ للعب دون اتصال', 'Saving for offline play')
        : _savedOffline
            ? t('محفوظ للعب دون اتصال', 'Saved offline')
            : t('تنزيل للعب دون اتصال', 'Download for offline');
    return IconButton(
      key: const ValueKey('games.v4.offline'),
      tooltip: label,
      onPressed: dl != null
          ? null
          : _savedOffline
              ? () => showAppNotice(
                  t('هذا المستوى محفوظ على جهازك ويُلعب دون اتصال', 'This level is saved on your device and plays offline'))
              : _downloadOffline,
      icon: dl != null
          ? SizedBox.square(
              dimension: AppIconSize.md,
              child: CircularProgressIndicator(strokeWidth: 2.2, value: dl.$2 == 0 ? null : dl.$1 / dl.$2),
            )
          : Icon(_savedOffline ? Icons.offline_pin_rounded : Icons.download_for_offline_outlined, semanticLabel: label),
    );
  }

  /// Kids or calm music; none for sacred content or when the level turns it off.
  void _playMusic(GameSession s) {
    final a = GameAudio.instance;
    if (s.sacred || !s.settings.music) {
      a.stopMusic();
      return;
    }
    a.playMusic(s.calm || s.settings.theme == 'adult' ? GameMusic.calm : GameMusic.kids);
  }

  void _v4Finished(GameSession s) {
    _clock.stop();
    GameAudio.instance.stopMusic();
    final sub = V4PlaySubmission(
      gameId: _game.id,
      score: s.score,
      maxScore: s.maxScore,
      durationS: _clock.elapsed.inSeconds,
      roundId: _fromPool ? null : s.roundId,
      trace: [for (final e in s.trace) Map<String, Object>.from(e)],
      drawId: s.drawId,
      picked: _picked,
      calm: s.calm ? true : null,
      ghostPlayId: s.templateKey == 'ghost_duel' ? _ghostPlayId : null,
      fromPool: _fromPool,
      v4: _v4,
    );
    if (mounted) setState(() => _sub = sub);
    GameFeedback.instance.play(GameSound.finish);
    if (_fromPool) {
      final uid = _uid(), ids = _itemIds;
      if (uid != null && ids != null) _cache.markPlayed(uid, _game.id, ids);
    }
    if (!GuestState.active) _send();
  }

  @override
  void dispose() {
    if (_isV4) {
      _session?.dispose();
      GameAudio.instance.stopMusic();
    }
    SyncEngine.instance.unlisten(SyncKinds.gamePlay, _onSync);
    super.dispose();
  }

  /// The outbox brought the server's answer for this page's play.
  void _onSync(SyncResult r) {
    final sub = _sub;
    if (sub == null || r.id != sub.clientId || !mounted) return;
    setState(() {
      sub.settle(r);
      final res = sub.result;
      if (res != null) {
        _game = _game.withProgress(res.progress ?? _game.progress);
        _saved++;
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final g = await _api.game(_game.id);
      if (!mounted) return;
      setState(() {
        _game = g.withProgress(g.progress ?? _game.progress);
        _loading = false;
      });
      // opened by URL: the stub had no engine; a v4 level draws now
      if (_isV4) {
        _startV4();
        return;
      }
      _clock
        ..reset()
        ..start();
      _startRound();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = gamesErrorText(e);
      });
    }
  }

  /// Retry after a failed load or draw: a v4 level draws again; anything else loads the game again.
  void _retryLoad() => _isV4 ? _startV4() : _load();

  void _finished(int score, int max) {
    _clock.stop();
    final trace = _trace;
    final sub = GamePlaySubmission(
        gameId: _game.id,
        score: score,
        maxScore: max,
        durationS: _clock.elapsed.inSeconds,
        roundId: trace == null ? null : _roundId,
        trace: trace);
    setState(() => _sub = sub);
    GameFeedback.instance.play(GameSound.finish);
    if (!GuestState.active) _send();
  }

  Future<void> _send() async {
    final sub = _sub;
    if (sub == null || sub.done || sub.queued) return;
    if (sub.ranked && !_saving) {
      // a ranked play goes straight to the plays route; only a lost answer falls back to the outbox (unranked)
      setState(() => _saving = true);
      final r = await sub.send(_api);
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (r != null) {
          _game = _game.withProgress(r.progress ?? _game.progress);
          _saved++;
        }
      });
      if (r != null) {
        GamesBus.revision.value++;
        return;
      }
      if (sub.done) return;
    }
    if (await sub.enqueue()) {
      if (mounted) setState(() {}); // shown from the device's grading; the engine sends it
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final r = await sub.send(_api);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (r != null) {
        _game = _game.withProgress(r.progress ?? _game.progress);
        _saved++;
      }
    });
    if (r != null) GamesBus.revision.value++;
  }

  void _replay() {
    // an unsaved round keeps its id while it waits: replaying is allowed only once the server has answered (or for a
    // guest, who saves nothing)
    setState(() {
      _sub = null;
      _round++;
    });
    if (_isV4) {
      _startV4();
      return;
    }
    _clock
      ..reset()
      ..start();
    _startRound();
  }

  /// Ghost Duel's end moment: the SERVER's verdict when it answered; for a play that has not reached the server, the
  /// app's own result by the same rule, marked as not confirmed (no coins are promised either way).
  Widget? _duelCard(V4PlaySubmission sub, V4Duel? server) {
    final s = _session;
    if (s == null || s.templateKey != 'ghost_duel') return null;
    final ghost = s.ghost ??
        botDuelGhost(items: s.items.length, parMs: s.items.fold<int>(0, (a, b) => a + b.parSeconds) * 1000);
    final settled = sub.v4Result != null;
    if (settled && server == null) return null;
    final won = server?.won ??
        duelWins(
            myScore: sub.score,
            myMax: sub.maxScore,
            myMs: (sub.durationS ?? 0) * 1000,
            theirScore: ghost.score,
            theirMax: ghost.maxScore,
            theirMs: ghost.durationMs);
    final forced = GameAge.values.where((a) => a.name == s.settings.theme).firstOrNull;
    return DuelResultCard(
      theme: AgeTheme.of(context, age: forced ?? AgeThemeScope.of(context).age),
      won: won,
      opponentName: ghost.name,
      myShare: sub.maxScore == 0 ? 0 : sub.score / sub.maxScore,
      theirShare: ghost.maxScore == 0 ? 0 : ghost.score / ghost.maxScore,
      confirmed: settled,
      bot: (server?.opponent ?? (ghost.bot ? 'bot' : 'ghost')) == 'bot',
    );
  }

  void _openBoard() => showAppSheet<void>(
        context,
        (ctx) => AppSheetContent(
          title: t('لوحة المتصدرين', 'Leaderboard'),
          children: [GameLeaderboardSection(gameId: _game.id, api: _api, refresh: _saved)],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final sub = _sub;
    final waiting = sub != null && !GuestState.active && !sub.done && !sub.queued;
    final kept = sub != null && sub.queued && !sub.done;
    final board = !GuestState.active && !gamesLeaderboardOff();
    return SdArea(area: AppArea.games, child: BasePage(
      appBar: ScreenAppBar(
        title: _game.title,
        compact: true,
        helpPageId: 'games.play',
        actions: [
          if (board)
            IconButton(
              key: const ValueKey('games.board.open'),
              tooltip: t('لوحة المتصدرين', 'Leaderboard'),
              icon: const Icon(Icons.leaderboard_rounded),
              onPressed: _openBoard,
            ),
          // Games v4 T76: challenge a friend on this level (one seed for everyone); not on a challenge or review play
          if (_isV4 && !GuestState.active && !widget.review && widget.challenge == null && !gamesChallengesOff())
            IconButton(
              key: const ValueKey('games.challenge.create'),
              tooltip: t('تحدَّ صديقاً', 'Challenge a friend'),
              icon: const Icon(Icons.emoji_events_rounded),
              onPressed: () => challengeAFriend(context, _game.id, api: _v4),
            ),
          if (_offlineOk) _offlineButton(),
        ],
      ),
      child: SafeArea(
        child: GamePlayView(
          game: _game,
          round: _round,
          loading: _loading,
          error: _error,
          onRetryLoad: _retryLoad,
          onFinished: _finished,
          onTrace: (t) => _trace = t,
          v4Session: _isV4 ? _session : null,
          profile: _profile,
          unreadable: _unreadable,
          extras: switch (sub) {
            V4PlaySubmission(v4Result: final r?) => GameResultExtras(
                coinsAwarded: r.coinsAwarded, coins: r.coins, unlocked: r.unlocked.length, duel: _duelCard(sub, r.duel)),
            V4PlaySubmission() when _duelCard(sub, null) != null => GameResultExtras(coinsAwarded: 0, duel: _duelCard(sub, null)),
            _ => null,
          },
          rankToday: sub?.result?.ranked == true ? sub?.result?.rankToday : null,
          finished: sub == null
              ? null
              : (
                  score: sub.result?.score ?? sub.score,
                  max: sub.result?.maxScore ?? sub.maxScore,
                  stars: sub.result?.stars,
                  badges: sub.result?.newBadges ?? const [],
                  points: sub.result?.pointsAwarded ?? 0,
                ),
          saving: _saving,
          saveError: sub?.error,
          onRetrySave: waiting && !_saving ? _send : null,
          guest: GuestState.active,
          kept: kept,
          onReplay: waiting ? null : _replay,
          onDone: () => Navigator.of(context).maybePop(),
          leaderboard: board && sub != null ? GameLeaderboardSection(gameId: _game.id, api: _api, refresh: _saved) : null,
        ),
      ),
    ));
  }
}

/// A finished round as the result shows it.
typedef GameRoundResult = ({int score, int max, int? stars, List<GameBadge> badges, int points});

/// The play page's body with plain values: loading / error, the engine for [round], or the result.
class GamePlayView extends StatelessWidget {
  const GamePlayView({
    super.key,
    required this.game,
    this.round = 0,
    this.loading = false,
    this.error,
    this.onRetryLoad,
    this.onFinished,
    this.finished,
    this.saving = false,
    this.saveError,
    this.onRetrySave,
    this.guest = false,
    this.kept = false,
    this.onReplay,
    this.onDone,
    this.random,
    this.leaderboard,
    this.onTrace,
    this.rankToday,
    this.v4Session,
    this.profile,
    this.unreadable = false,
    this.extras,
  });

  /// Games v4: the round in progress, drawn by the game's template (instead of the v1-v3 engine).
  final GameSession? v4Session;

  /// The learner's games profile when the page loaded it (see [templateWithProfile]).
  final V4Profile? profile;

  /// The draw was empty or unreadable: "needs a newer version".
  final bool unreadable;

  /// Drawn under the finish view (coins, unlocked levels).
  final Widget? extras;

  final GameSummary game;
  final int round;
  final bool loading;
  final String? error;
  final VoidCallback? onRetryLoad;
  final GameFinished? onFinished;
  final GameRoundResult? finished;
  final bool saving;
  final String? saveError;
  final VoidCallback? onRetrySave, onReplay, onDone;
  final bool guest;

  /// The play waits in the device's outbox: the result is the device's own until the server answers.
  final bool kept;

  /// The engines' shuffle (tests pass a seeded one).
  final Random? random;

  /// Drawn under the result (the game's leaderboard).
  final Widget? leaderboard;

  /// The round's trace, just before [onFinished] (a ranked round sends it).
  final ValueChanged<List<Map<String, Object>>>? onTrace;

  /// A ranked play's place today (the finish view's "Rank 4 today").
  final int? rankToday;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    final spec = gameEngine(game.engine);
    if (loading) {
      body = const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    } else if (error != null) {
      body = AppErrorState(message: error, onRetry: onRetryLoad);
    } else if (spec == null || unreadable) {
      body = AppEmpty(
        icon: Icons.system_update_rounded,
        title: t('هذه اللعبة تحتاج إصداراً أحدث من التطبيق', 'This game needs a newer version of the app'),
        message: t('حدّث التطبيق ثم افتحها من جديد.', 'Update the app, then open it again.'),
      );
    } else if (finished != null) {
      final f = finished!;
      body = Column(key: const ValueKey('games.result'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GameFinishView(
          score: f.score,
          max: f.max,
          stars: f.stars,
          theme: game.theme,
          badges: [for (final b in f.badges) (icon: b.iconData, label: b.name)],
          points: f.points,
          saving: saving,
          saveError: saveError,
          onRetrySave: onRetrySave,
          note: guest
              ? t('سجّل الدخول لتحفظ نجومك وشاراتك.', 'Sign in to keep your stars and badges.')
              : kept
                  ? keptOnDeviceText()
                  : null,
          onReplay: onReplay,
          onDone: onDone,
          rankToday: rankToday,
        ),
        ?extras,
        if (leaderboard != null) ...[const SizedBox(height: AppSpace.lg), leaderboard!],
      ]);
    } else if (v4Session != null && kGameTemplates[game.engine] != null) {
      // a template fills the space it is given (a Flame stage, a board): bounded height, never inside a ListView
      return AppWidthBox(
        width: AppWidth.content,
        child: KeyedSubtree(key: ValueKey('games.v4.$round'), child: templateWithProfile(kGameTemplates[game.engine]!, profile).play(v4Session!)),
      );
    } else if (v4Session == null && kGameTemplates.containsKey(game.engine)) {
      // a v4 level with no round, not loading and no error: never an endless skeleton, offer to start again
      body = AppErrorState(message: t('تعذّر بدء اللعبة.', 'The game could not start.'), onRetry: onRetryLoad);
    } else {
      body = GameRound(
        key: ValueKey('games.round.$round'),
        spec: spec,
        config: game.config,
        theme: game.theme,
        onFinished: onFinished ?? (_, _) {},
        onTrace: onTrace,
        category: game.category,
        random: random,
      );
    }
    return AppWidthBox(
      width: AppWidth.reading,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        children: [body, const SizedBox(height: AppSpace.lg)],
      ),
    );
  }
}

bool _registered(String engine) {
  registerGameTemplates();
  return kGameTemplates.containsKey(engine);
}

/// The templates that draw from the learner's games profile: the page asks for `/me/games/profile` with their draw.
const Set<String> kProfileTemplates = {'constellation'};

/// [template] with what it takes from [profile] (Constellation: the drawings already in the learner's sky).
GameTemplate templateWithProfile(GameTemplate template, V4Profile? profile) => switch (template) {
      ConstellationTemplate() when profile != null => template.withSky(profile.sky.length),
      _ => template,
    };
