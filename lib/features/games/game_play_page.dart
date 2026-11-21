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
//   GamePlayView  the body with plain values (test/ui/games_layout_test.dart)
//   GamesBus      `revision` bumps after a saved play (also one the outbox saved after the page closed), so the tab and
//                 the progress page reload
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart';
import 'package:flutter_education_app/core/offline/sync/outbox.dart';
import 'package:flutter_education_app/core/offline/sync/sync_engine.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/engines/game_engine.dart';
import 'package:flutter_education_app/features/games/games_api.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// Bumps after a play the server saved.
abstract final class GamesBus {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool _wired = false;

  /// Once: a play the outbox saved bumps [revision], whichever page is open.
  static void wireSync([SyncEngine? engine]) {
    if (_wired) return;
    _wired = true;
    (engine ?? SyncEngine.instance).listen(SyncKinds.gamePlay, (r) {
      if (r.accepted) revision.value++;
    });
  }
}

class GamePlayPage extends StatefulWidget {
  const GamePlayPage({super.key, required this.game, this.api});

  /// The list's row (its `config` may be empty: then the page loads the game).
  final GameSummary game;
  final GamesApi? api;

  @override
  State<GamePlayPage> createState() => _GamePlayPageState();
}

class _GamePlayPageState extends State<GamePlayPage> {
  late final GamesApi _api = widget.api ?? GamesApi();
  late GameSummary _game = widget.game;
  bool _loading = false;
  String? _error;

  int _round = 0;
  final Stopwatch _clock = Stopwatch();
  GamePlaySubmission? _sub;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    GamesBus.wireSync();
    SyncEngine.instance.listen(SyncKinds.gamePlay, _onSync);
    if (_game.config.isEmpty) {
      _load();
    } else {
      _clock.start();
    }
  }

  @override
  void dispose() {
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
      if (res != null) _game = _game.withProgress(res.progress ?? _game.progress);
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
      _clock
        ..reset()
        ..start();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = gamesErrorText(e);
      });
    }
  }

  void _finished(int score, int max) {
    _clock.stop();
    final sub = GamePlaySubmission(gameId: _game.id, score: score, maxScore: max, durationS: _clock.elapsed.inSeconds);
    setState(() => _sub = sub);
    if (!GuestState.active) _send();
  }

  Future<void> _send() async {
    final sub = _sub;
    if (sub == null || sub.done || sub.queued) return;
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
      if (r != null) _game = _game.withProgress(r.progress ?? _game.progress);
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
    _clock
      ..reset()
      ..start();
  }

  @override
  Widget build(BuildContext context) {
    final sub = _sub;
    final waiting = sub != null && !GuestState.active && !sub.done && !sub.queued;
    final kept = sub != null && sub.queued && !sub.done;
    return BasePage(
      appBar: ScreenAppBar(title: _game.title),
      child: SafeArea(
        child: GamePlayView(
          game: _game,
          round: _round,
          loading: _loading,
          error: _error,
          onRetryLoad: _load,
          onFinished: _finished,
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
        ),
      ),
    );
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
  });

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

  @override
  Widget build(BuildContext context) {
    final Widget body;
    final spec = gameEngine(game.engine);
    if (loading) {
      body = const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    } else if (error != null) {
      body = AppErrorState(message: error, onRetry: onRetryLoad);
    } else if (spec == null) {
      body = AppEmpty(
        icon: Icons.system_update_rounded,
        title: t('هذه اللعبة تحتاج إصداراً أحدث من التطبيق', 'This game needs a newer version of the app'),
        message: t('حدّث التطبيق ثم افتحها من جديد.', 'Update the app, then open it again.'),
      );
    } else if (finished != null) {
      final f = finished!;
      body = LearnResultView(
        key: const ValueKey('games.result'),
        score: f.score,
        max: f.max,
        stars: f.stars,
        badges: [for (final b in f.badges) LearnEarned(icon: b.iconData, label: b.name)],
        pointsAwarded: f.points,
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
      );
    } else {
      body = KeyedSubtree(
        key: ValueKey('games.round.$round'),
        child: spec.build(game.config, onFinished ?? (_, _) {}, random),
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
